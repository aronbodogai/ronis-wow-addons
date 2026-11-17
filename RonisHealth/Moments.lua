-- Roni's Health - good and bad moments for a break.
--
-- Natural pauses: when you take a flight, sit at a campfire, lie on a
-- sleeping bag or sit down to eat or drink, a break that is at least 3/4 of
-- the way through its interval comes early. The game does not need you for
-- a while, and tying a habit to a moment that happens anyway helps it stick.
--
-- Busy moments: when a break comes due while you are fighting and questing,
-- it waits for a calm moment (some seconds out of combat; the busier you
-- have been, the longer) but never longer than ns.CALM_GRACE.
local ADDON, ns = ...

ns.EARLY_SHARE = 0.75     -- a natural pause brings a break forward from 3/4 of its interval
ns.CALM_GRACE = 5 * 60    -- a due break waits at most this long for a calm moment
ns.ACTIVITY_WINDOW = 5 * 60
ns.MIN_FLIGHT = 40        -- known flights shorter than this are not worth a card

---------------------------------------------------------------------------
-- How busy you are: fights started and quests handed in lately
---------------------------------------------------------------------------
local activity = {}       -- GetTime() of each fight start / quest turn-in
local lastBusy            -- GetTime() of the last fight end or quest turn-in

function ns.NoteActivity()
    local now = GetTime()
    activity[#activity + 1] = now
    while activity[1] and now - activity[1] > ns.ACTIVITY_WINDOW do table.remove(activity, 1) end
end

function ns.Activity()
    local now, n = GetTime(), 0
    for _, t in ipairs(activity) do
        if now - t <= ns.ACTIVITY_WINDOW then n = n + 1 end
    end
    return n
end

-- Seconds out of combat that count as calm: 10, plus 5 per recent fight or
-- quest, at most 45.
function ns.CalmNeeded()
    return math.min(45, 10 + 5 * ns.Activity())
end

-- True while you are in the thick of it (a break should wait if it can).
function ns.Busy()
    if not lastBusy then return false end
    return GetTime() - lastBusy < ns.CalmNeeded()
end

---------------------------------------------------------------------------
-- Flights
--
-- Times are learned per route and direction (keyed by taxi node IDs, like
-- the InFlight addon does). A route never flown before is estimated from
-- the straight-line length of its hops: seconds = yards / speed + 5 per hop.
-- The speed starts at 22 yd/s (taxis fly about 30 yd/s, but the path curves
-- and takeoff and landing take time) and calibrates itself after each flight.
---------------------------------------------------------------------------
ns.TAXI_SPEED = 22
ns.HOP_SECONDS = 5

local pendingRoute   -- set when a route is picked at the flight master
local flight         -- { key, start, dist, hops, noRecord } while flying

local function OnTaxi()
    return UnitOnTaxi and UnitOnTaxi("player") and true or false
end

-- slot -> node info ({ nodeID, name, position, slotIndex }) on the open taxi map
local function TaxiNodes()
    local out = {}
    local mapID = GetTaxiMapID and GetTaxiMapID()
    if not mapID or not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return out end
    local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
    if ok and type(nodes) == "table" then
        for _, n in ipairs(nodes) do
            if n.slotIndex then out[n.slotIndex] = n end
        end
    end
    return out, mapID
end

local function WorldXY(mapID, pos)
    if not (mapID and pos and C_Map and C_Map.GetWorldPosFromMapPos) then return nil end
    local ok, _, wp = pcall(C_Map.GetWorldPosFromMapPos, mapID, pos)
    if not ok or type(wp) ~= "table" then return nil end
    local x, y = wp.x, wp.y
    if not x and wp.GetXY then x, y = wp:GetXY() end
    return x, y
end

-- Straight-line yards along the hops to `slot`, and the number of hops.
local function RouteDistance(slot, nodes, mapID)
    local hops = GetNumRoutes and GetNumRoutes(slot) or 0
    if not hops or hops < 1 or not TaxiGetNodeSlot then return nil, nil end
    local total = 0
    for hop = 1, hops do
        local a, b = TaxiGetNodeSlot(slot, hop, true), TaxiGetNodeSlot(slot, hop, false)
        local x1, y1 = WorldXY(mapID, nodes[a] and nodes[a].position)
        local x2, y2 = WorldXY(mapID, nodes[b] and nodes[b].position)
        if not (x1 and x2) then return nil, hops end
        total = total + math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
    end
    return total, hops
end

local function NodeKey(node, slot)
    if node and node.nodeID then return "#" .. node.nodeID end
    return TaxiNodeName and TaxiNodeName(slot) or nil
end

if hooksecurefunc and TakeTaxiNode then
    hooksecurefunc("TakeTaxiNode", function(slot)
        local nodes, mapID = TaxiNodes()
        local from
        for i = 1, (NumTaxiNodes and NumTaxiNodes() or 0) do
            if TaxiNodeGetType(i) == "CURRENT" then from = i break end
        end
        local a, b = from and NodeKey(nodes[from], from), NodeKey(nodes[slot], slot)
        local dist, hops = RouteDistance(slot, nodes, mapID)
        pendingRoute = {
            key = a and b and (a .. ">" .. b) or nil,
            dist = dist, hops = hops or 1, at = GetTime(),
        }
    end)
end
if hooksecurefunc and TaxiRequestEarlyLanding then
    hooksecurefunc("TaxiRequestEarlyLanding", function()
        if flight then flight.noRecord = true end
    end)
end

-- Seconds a route took last time, or nil when it is new.
function ns.FlightTime(key)
    local t = key and ns.db.flights[key]
    return tonumber(t)
end

function ns.TaxiSpeed()
    return tonumber(ns.db.taxiSpeed) or ns.TAXI_SPEED
end

-- Estimated seconds for a new route from its length, or nil.
function ns.EstimateFlight(dist, hops)
    if not dist or dist <= 0 then return nil end
    local t = dist / ns.TaxiSpeed() + ns.HOP_SECONDS * (hops or 1)
    if t < 15 or t > 900 then return nil end
    return math.floor(t + 0.5)
end

local function TakeOff()
    local r = pendingRoute and GetTime() - pendingRoute.at < 30 and pendingRoute or {}
    pendingRoute = nil
    flight = { key = r.key, start = GetTime(), dist = r.dist, hops = r.hops }
    local window = ns.FlightTime(r.key)
    local estimated = false
    if not window then
        window = ns.EstimateFlight(r.dist, r.hops)
        estimated = window ~= nil
    end
    ns.Moment({ moment = "flight", window = window, estimated = estimated })
end

local function Landed()
    local f = flight
    flight = nil
    local took = GetTime() - f.start
    if f.noRecord or took < 10 then return end
    if f.key then
        local old = ns.FlightTime(f.key)
        if not old or math.abs(old - took) > 2 then ns.db.flights[f.key] = math.floor(took + 0.5) end
    end
    -- calibrate the speed used for new routes
    if f.dist and f.dist > 0 then
        local v = f.dist / math.max(1, took - ns.HOP_SECONDS * (f.hops or 1))
        if v > 8 and v < 60 then
            ns.db.taxiSpeed = math.floor((0.8 * ns.TaxiSpeed() + 0.2 * v) * 10 + 0.5) / 10
        end
    end
end

function ns.OnFlight() return flight ~= nil end

---------------------------------------------------------------------------
-- Sitting and lying down
--
-- The game has no "is sitting" query, so this follows what sits you down:
-- /sit, /kneel, /sleep (C_ChatInfo.PerformEmote), the sit key
-- (SitStandOrDescendStart, a toggle) and, for the sleeping bag, resting
-- switching on while you stand still (the bag makes a rested spot). Moving,
-- /stand or a fight stands you up. Sitting at a camp or with food is told
-- apart by your buffs.
---------------------------------------------------------------------------
local sitting
local ignoreRestUntil = 0
local auraState = {} -- moment -> true while one of its auras is on you

local function StandUp() sitting = nil end

local function SatDown(how) -- "sit", "lie" or "rest"
    if sitting then return end
    sitting = how
    local moment = (how == "rest" and "bedroll") or how
    if auraState.food then
        moment = "food"
    elseif auraState.campfire then
        moment = "campfire"
    end
    ns.Moment({ moment = moment })
end
function ns.Sitting() return sitting end

if hooksecurefunc and C_ChatInfo and C_ChatInfo.PerformEmote then
    hooksecurefunc(C_ChatInfo, "PerformEmote", function(token)
        token = type(token) == "string" and token:upper() or ""
        if token == "SIT" or token == "KNEEL" then
            SatDown("sit")
        elseif token == "SLEEP" then
            SatDown("lie")
        elseif token == "STAND" then
            StandUp()
        end
    end)
end

if hooksecurefunc and SitStandOrDescendStart then
    hooksecurefunc("SitStandOrDescendStart", function()
        -- the same key descends while swimming or flying
        if (IsMounted and IsMounted()) or (IsFlying and IsFlying()) or (IsSwimming and IsSwimming())
            or (IsFalling and IsFalling()) or OnTaxi() then
            return
        end
        if sitting then StandUp() else SatDown("sit") end
    end)
end

local function Still()
    return not (GetUnitSpeed and GetUnitSpeed("player") > 0)
end

local function RestingChanged()
    if not (IsResting and IsResting()) or GetTime() < ignoreRestUntil or OnTaxi() then return end
    -- walking into an inn or a city also starts resting: only count it
    -- when you are standing still on the spot a second later
    C_Timer.After(1, function()
        if IsResting() and Still() and not OnTaxi() then SatDown("rest") end
    end)
end

---------------------------------------------------------------------------
-- Buffs that mean you sat or lay down
---------------------------------------------------------------------------
local FOOD = { ["Food"] = true, ["Drink"] = true, ["Food & Drink"] = true, ["Refreshment"] = true }

local function AuraMoment(name)
    if not name then return nil end
    if FOOD[name] then return "food" end
    local low = name:lower()
    if low:find("well%-rested") or low:find("well rested") or low:find("sleeping bag") then return "bedroll" end
    if low:find("cozy fire") or low:find("campfire") or low:find("camp chair") then return "campfire" end
    return nil
end
ns.AuraMoment = AuraMoment

local function ScanAuras()
    local now = {}
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 80 do
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not a then break end
            local m = AuraMoment(a.name)
            if m then now[m] = true end
        end
    end
    local gained = {}
    for m in pairs(now) do
        if not auraState[m] then gained[#gained + 1] = m end
    end
    auraState = now
    table.sort(gained)
    return gained
end

---------------------------------------------------------------------------
-- Offering breaks at a natural pause
---------------------------------------------------------------------------
ns.NOT_NOW_QUIET = 5 * 60 -- after "Not now", no early offer of that break for this long
ns.notNowUntil = {}

-- Played seconds since the last break of this kind.
function ns.Elapsed(kind)
    local iv = ns.Interval(kind)
    return iv - (ns.left[kind] or iv)
end

-- A natural pause started: show each break that is due or nearly due.
-- info = { moment, window = seconds or nil, estimated = window is a guess }
function ns.Moment(info)
    if not ns.db or not ns.db.smart.moments then return end
    if ns.Paused() or ns.trip or ns.Blocker() then return end
    if info.window and info.window < ns.MIN_FLIGHT then return end
    -- squats first: they gain the most from a long pause
    for _, kind in ipairs({ "squat", "eye" }) do
        if ns.Enabled(kind) and not ns.Showing(kind) then
            local due = ns.due[kind] or (ns.left[kind] or 1) <= 0
            local elapsed = ns.Elapsed(kind)
            local early = not due and elapsed >= ns.Interval(kind) * ns.EARLY_SHARE
                and GetTime() >= (ns.notNowUntil[kind] or 0)
            if due or early then
                ns.due[kind], ns.waited[kind] = nil, nil
                ns.ShowReminder(kind, {
                    moment = info.moment, window = info.window, estimated = info.estimated,
                    early = not due, elapsed = elapsed,
                })
            end
        end
    end
end

-- Called every second by the core's clock.
function ns.WatchMoments()
    local onTaxi = OnTaxi()
    if onTaxi and not flight then
        StandUp()
        TakeOff()
    elseif not onTaxi and flight then
        Landed()
    end
    for _, m in ipairs(ScanAuras()) do ns.Moment({ moment = m }) end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:RegisterEvent("PLAYER_STARTED_MOVING")
ev:RegisterEvent("PLAYER_UPDATE_RESTING")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" or event == "QUEST_TURNED_IN" then
        ns.NoteActivity()
    end
    if event == "PLAYER_REGEN_ENABLED" or event == "QUEST_TURNED_IN" then
        lastBusy = GetTime()
    end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_STARTED_MOVING" then
        StandUp()
    elseif event == "PLAYER_UPDATE_RESTING" then
        RestingChanged()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- logging in or hearthing into an inn is not lying down, and a
        -- loading screen in the middle of a flight spoils its time
        ignoreRestUntil = GetTime() + 15
        StandUp()
        if flight then flight.noRecord = true end
    end
end)
