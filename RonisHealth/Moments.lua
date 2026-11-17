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
-- Flights: how long a route took last time (both directions are shared)
---------------------------------------------------------------------------
local pendingRoute   -- { key, at } from the flight master, until takeoff
local flight         -- { key, start } while on a flight path

local function RouteKey(a, b)
    if not a or not b then return nil end
    if a > b then a, b = b, a end
    return a .. " - " .. b
end

local function CurrentNode()
    if not NumTaxiNodes then return nil end
    for i = 1, NumTaxiNodes() do
        if TaxiNodeGetType(i) == "CURRENT" then return TaxiNodeName(i) end
    end
end

if hooksecurefunc and TakeTaxiNode then
    hooksecurefunc("TakeTaxiNode", function(slot)
        local key = RouteKey(CurrentNode(), TaxiNodeName and TaxiNodeName(slot))
        pendingRoute = key and { key = key, at = GetTime() } or nil
    end)
end

-- Seconds a route took last time, or nil when it is new.
function ns.FlightTime(key)
    local t = key and ns.db.flights[key]
    return tonumber(t)
end

local function OnTaxi()
    return UnitOnTaxi and UnitOnTaxi("player") and true or false
end

---------------------------------------------------------------------------
-- Auras that mean you sat or lay down
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

local auraState = {} -- moment -> true while one of its auras is on you

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
-- Played seconds since the last break of this kind.
function ns.Elapsed(kind)
    local iv = ns.Interval(kind)
    return iv - (ns.left[kind] or iv)
end

-- A natural pause started: show each break that is due or nearly due.
-- info = { moment = "flight"|"campfire"|"bedroll"|"food", window = seconds or nil }
function ns.Moment(info)
    if not ns.db or not ns.db.smart.moments then return end
    if ns.Paused() or ns.trip or ns.Blocker() then return end
    if info.window and info.window < ns.MIN_FLIGHT then return end
    -- squats first: they gain the most from a long pause
    for _, kind in ipairs({ "squat", "eye" }) do
        if ns.Enabled(kind) and not ns.Showing(kind) then
            local due = ns.due[kind] or (ns.left[kind] or 1) <= 0
            local elapsed = ns.Elapsed(kind)
            if due or elapsed >= ns.Interval(kind) * ns.EARLY_SHARE then
                ns.due[kind], ns.waited[kind] = nil, nil
                ns.ShowReminder(kind, {
                    moment = info.moment, window = info.window, early = not due,
                    elapsed = elapsed, flightKnown = info.flightKnown,
                })
            end
        end
    end
end

-- Called every second by the core's clock.
function ns.WatchMoments()
    local onTaxi = OnTaxi()
    if onTaxi and not flight then
        local key = pendingRoute and GetTime() - pendingRoute.at < 30 and pendingRoute.key or nil
        pendingRoute = nil
        flight = { key = key, start = GetTime() }
        local t = ns.FlightTime(key)
        ns.Moment({ moment = "flight", window = t, flightKnown = t ~= nil })
    elseif not onTaxi and flight then
        local took = GetTime() - flight.start
        if flight.key and took >= 10 then
            local old = ns.FlightTime(flight.key)
            ns.db.flights[flight.key] = math.floor((old and (old + took) / 2 or took) + 0.5)
        end
        flight = nil
    end
    for _, m in ipairs(ScanAuras()) do ns.Moment({ moment = m }) end
end

function ns.OnFlight() return flight ~= nil end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" or event == "QUEST_TURNED_IN" then
        ns.NoteActivity()
    end
    if event == "PLAYER_REGEN_ENABLED" or event == "QUEST_TURNED_IN" then
        lastBusy = GetTime()
    end
end)
