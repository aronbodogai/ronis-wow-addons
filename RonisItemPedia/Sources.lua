-- Roni's ItemPedia - where an item comes from, read live from QuestieDB
-- (the database addon Questie uses, which has WoW Forever data). Optional:
-- without QuestieDB loaded these lookups simply return nothing.
local ADDON, ns = ...

local RANK = { [1] = "Elite", [2] = "Rare Elite", [3] = "Boss", [4] = "Rare" }
local MAX_ROWS = 12

local function DB(name)
    local db = _G[name]
    if type(db) == "table" and type(db.Get) == "function" then return db end
end

function ns.HasQuestieDB()
    return DB("ItemDB") ~= nil
end

local function Get(dbName, id, key)
    local db = DB(dbName)
    if not db then return nil end
    local ok, v = pcall(db.Get, id, key)
    if ok then return v end
end

local function List(v)
    return type(v) == "table" and v or {}
end

-- Questie modules (only present when Questie itself is loaded)
local modules = {}
local function Module(name)
    if modules[name] == nil then
        modules[name] = false
        if QuestieLoader and QuestieLoader.ImportModule then
            local ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
            if ok and type(mod) == "table" then modules[name] = mod end
        end
    end
    return modules[name] or nil
end

local function ZoneName(zoneID)
    if type(zoneID) ~= "number" or zoneID <= 0 then return nil end
    if C_Map and C_Map.GetAreaInfo then
        local ok, name = pcall(C_Map.GetAreaInfo, zoneID)
        if ok and name and name ~= "" then return name end
    end
end

-- Drop chance in percent. Questie only ships rates for quest-related items.
local function DropChance(itemID, npcID)
    local qdb = Module("QuestieDB")
    if not (qdb and qdb.GetItemDroprate) then return nil end
    local ok, rate = pcall(qdb.GetItemDroprate, itemID, npcID)
    if ok and type(rate) == "table" and type(rate[1]) == "number" and rate[1] > 0 then
        return rate[1]
    end
end

---------------------------------------------------------------------------
-- Locations and distance
-- Questie stores spawns as { [areaID] = { {x, y}, ... } } with 0-100 coords.
---------------------------------------------------------------------------
local function UiMapID(areaID)
    local zdb = Module("ZoneDB")
    if not (zdb and zdb.GetUiMapIdByAreaId) then return nil end
    local ok, id = pcall(zdb.GetUiMapIdByAreaId, zdb, areaID)
    if ok and type(id) == "number" then return id end
end

local HBD = LibStub and LibStub("HereBeDragons-2.0", true)

-- World position (x, y, instance) of a map coordinate, or nil.
local function WorldPos(uiMapID, x, y)
    if HBD then
        local ok, wx, wy, inst = pcall(HBD.GetWorldCoordinatesFromZone, HBD, x / 100, y / 100, uiMapID)
        if ok and wx then return wx, wy, inst end
    end
    if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local ok, inst, pos = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, CreateVector2D(x / 100, y / 100))
        if ok and inst and pos then
            local wx, wy = pos:GetXY()
            return wx, wy, inst
        end
    end
end

local function PlayerWorldPos()
    if HBD and HBD.GetPlayerWorldPosition then
        local ok, x, y, inst = pcall(HBD.GetPlayerWorldPosition, HBD)
        if ok and x then return x, y, inst end
    end
    if C_Map and C_Map.GetBestMapForUnit then
        local map = C_Map.GetBestMapForUnit("player")
        local pos = map and C_Map.GetPlayerMapPosition(map, "player")
        if pos then
            local px, py = pos:GetXY()
            return WorldPos(map, px * 100, py * 100)
        end
    end
end

-- Fills row.dist (yards, nil when on another continent), row.mapID, row.x,
-- row.y and row.spawnZone from the spawn nearest to the player.
local function Locate(row, spawns, player)
    local best
    for areaID, list in pairs(List(spawns)) do
        local mapID = UiMapID(areaID)
        for _, c in ipairs(List(list)) do
            local x, y = c[1], c[2]
            if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
                local dist
                if mapID and player then
                    local wx, wy, inst = WorldPos(mapID, x, y)
                    if wx and inst == player[3] then
                        dist = math.sqrt((wx - player[1]) ^ 2 + (wy - player[2]) ^ 2)
                    end
                end
                if not best or (dist and (not best.dist or dist < best.dist)) then
                    best = { dist = dist, mapID = mapID, x = x, y = y, zone = areaID }
                end
            end
        end
    end
    if best then
        row.dist, row.mapID, row.x, row.y, row.spawnZone = best.dist, best.mapID, best.x, best.y, best.zone
        row.zone = ZoneName(best.zone) or row.zone -- show the zone of the spawn we point at
    end
end

local function NpcRow(npcID, itemID, player)
    local name = Get("NpcDB", npcID, "name")
    if not name then return nil end
    local lo, hi = Get("NpcDB", npcID, "minLevel"), Get("NpcDB", npcID, "maxLevel")
    local lvl
    if type(lo) == "number" and lo > 0 then
        lvl = (type(hi) == "number" and hi > lo) and (lo .. "-" .. hi) or tostring(lo)
    end
    local row = {
        kind = "npc",
        id = npcID,
        name = name,
        level = lvl,
        rank = RANK[Get("NpcDB", npcID, "rank")],
        zone = ZoneName(Get("NpcDB", npcID, "zoneID")),
        chance = itemID and DropChance(itemID, npcID),
    }
    Locate(row, Get("NpcDB", npcID, "spawns"), player)
    return row
end

-- Drop chance first (when known), then nearest, then name.
local function SortRows(rows)
    table.sort(rows, function(a, b)
        if (a.chance or -1) ~= (b.chance or -1) then return (a.chance or -1) > (b.chance or -1) end
        local da, db = a.dist or math.huge, b.dist or math.huge
        if da ~= db then return da < db end
        return a.name < b.name
    end)
end

local function Trim(rows)
    local total = #rows
    for i = total, MAX_ROWS + 1, -1 do rows[i] = nil end
    return total
end

---------------------------------------------------------------------------
-- Quests that need an item (item objectives + required source items).
-- QuestieDB has no item -> quest link for this, so every quest is scanned once,
-- spread over frames after login to avoid a hitch.
---------------------------------------------------------------------------
local questsByItem       -- [itemID] = { questID, ... } once ready
local QUESTS_PER_FRAME = 250

function ns.QuestIndexReady()
    return questsByItem ~= nil
end

function ns.StartQuestScan()
    local qdb = DB("QuestDB")
    if questsByItem or ns.questScanning or not qdb or type(qdb.GetAllIds) ~= "function" then return end
    local ok, ids = pcall(qdb.GetAllIds)
    if not ok or type(ids) ~= "table" then return end
    ns.questScanning = true
    local index, i = {}, 1
    local function add(item, q)
        if type(item) ~= "number" then return end
        local t = index[item]
        if not t then t = {}; index[item] = t end
        if t[#t] ~= q then t[#t + 1] = q end
    end
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local stop = math.min(i + QUESTS_PER_FRAME - 1, #ids)
        for k = i, stop do
            local q = ids[k]
            local obj = Get("QuestDB", q, "objectives")
            for _, o in ipairs(List(obj and obj[3])) do
                if type(o) == "table" then add(o[1], q) end
            end
            for _, item in ipairs(List(Get("QuestDB", q, "requiredSourceItems"))) do add(item, q) end
        end
        i = stop + 1
        if i > #ids then
            ticker:Cancel()
            questsByItem, ns.questScanning = index, false
            if ns.UI and ns.UI.OnDataChanged then ns.UI:OnDataChanged(true) end
        end
    end)
end

local band = bit and bit.band
local playerRaceBit
local function AvailableToPlayer(q)
    local mask = Get("QuestDB", q, "requiredRaces")
    if type(mask) ~= "number" or mask == 0 or not band then return true end
    if not playerRaceBit then
        local _, _, raceID = UnitRace("player")
        playerRaceBit = raceID and 2 ^ (raceID - 1) or 0
    end
    return playerRaceBit == 0 or band(mask, playerRaceBit) ~= 0
end

local IsQuestDone = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted

local function QuestRow(q, player)
    local name = Get("QuestDB", q, "name")
    if not name then return nil end
    local row = {
        quest = q,
        name = name,
        level = Get("QuestDB", q, "questLevel"),
        reqLevel = Get("QuestDB", q, "requiredLevel"),
    }
    local zoneOrSort = Get("QuestDB", q, "zoneOrSort")
    if type(zoneOrSort) == "number" and zoneOrSort > 0 then row.questZone = ZoneName(zoneOrSort) end
    if IsQuestDone then
        local ok, done = pcall(IsQuestDone, q)
        row.done = ok and done or nil
    end
    -- quest giver: first NPC, else first object (item-started quests have no map spot)
    local starters = List(Get("QuestDB", q, "startedBy"))
    local npc, obj = List(starters[1])[1], List(starters[2])[1]
    if npc and Get("NpcDB", npc, "name") then
        row.kind, row.id, row.pinName = "npc", npc, Get("NpcDB", npc, "name")
        Locate(row, Get("NpcDB", npc, "spawns"), player)
    elseif obj and Get("ObjectDB", obj, "name") then
        row.kind, row.id, row.pinName = "object", obj, Get("ObjectDB", obj, "name")
        Locate(row, Get("ObjectDB", obj, "spawns"), player)
    end
    row.zone = row.questZone or row.zone
    return row
end

local function SortQuests(rows)
    table.sort(rows, function(a, b)
        if (a.done and 1 or 0) ~= (b.done and 1 or 0) then return not a.done end
        local la, lb = tonumber(a.level) or 0, tonumber(b.level) or 0
        if la ~= lb then return la < lb end
        return a.name < b.name
    end)
end

-- Returns { drops = {rows}, dropsTotal, objects = {rows}, objectsTotal,
--           containers = {itemIDs}, vendors = {rows}, vendorsTotal, quests = {rows},
--           teaches = spellID }
-- Rows: { kind, id, name, level, rank, zone, chance, dist, mapID, x, y }
function ns.GetSources(itemID)
    local out = { drops = {}, objects = {}, containers = {}, vendors = {}, quests = {} }
    if not ns.HasQuestieDB() then return out end

    local px, py, pinst = PlayerWorldPos()
    local player = px and { px, py, pinst } or nil
    out.hasPlayerPos = player ~= nil

    for _, npc in ipairs(List(Get("ItemDB", itemID, "npcDrops"))) do
        local row = NpcRow(npc, itemID, player)
        if row then out.drops[#out.drops + 1] = row end
    end
    SortRows(out.drops)
    out.dropsTotal = Trim(out.drops)

    -- the same herb/ore node exists as many object IDs; keep the nearest per name+zone
    local byKey, objects = {}, {}
    for _, obj in ipairs(List(Get("ItemDB", itemID, "objectDrops"))) do
        local name = Get("ObjectDB", obj, "name")
        if name then
            local row = { kind = "object", id = obj, name = name, zone = ZoneName(Get("ObjectDB", obj, "zoneID")) }
            Locate(row, Get("ObjectDB", obj, "spawns"), player)
            local key = name .. "|" .. (row.zone or "")
            local prev = byKey[key]
            if not prev then
                byKey[key] = row
                objects[#objects + 1] = row
            elseif (row.dist or math.huge) < (prev.dist or math.huge) then
                for k, v in pairs(row) do prev[k] = v end
            end
        end
    end
    SortRows(objects)
    out.objects = objects
    out.objectsTotal = Trim(objects)

    for _, id in ipairs(List(Get("ItemDB", itemID, "itemDrops"))) do
        out.containers[#out.containers + 1] = id
    end

    for _, npc in ipairs(List(Get("ItemDB", itemID, "vendors"))) do
        local row = NpcRow(npc, nil, player)
        if row then out.vendors[#out.vendors + 1] = row end
    end
    SortRows(out.vendors)
    out.vendorsTotal = Trim(out.vendors)

    for _, q in ipairs(List(Get("ItemDB", itemID, "questRewards"))) do
        local name = Get("QuestDB", q, "name")
        if name then
            out.quests[#out.quests + 1] = { id = q, name = name, level = Get("QuestDB", q, "questLevel") }
        end
    end

    out.requiredFor = {}
    if questsByItem then
        for _, q in ipairs(questsByItem[itemID] or {}) do
            if AvailableToPlayer(q) then
                local row = QuestRow(q, player)
                if row then out.requiredFor[#out.requiredFor + 1] = row end
            end
        end
        SortQuests(out.requiredFor)
        out.requiredForTotal = Trim(out.requiredFor)
    else
        out.questsScanning = ns.questScanning
    end

    local teaches = Get("ItemDB", itemID, "teachesSpell")
    if type(teaches) == "number" and teaches > 0 then out.teaches = teaches end
    return out
end

---------------------------------------------------------------------------
-- Show on map: Questie pins every spawn, the world map opens on the nearest.
---------------------------------------------------------------------------
local shown -- { id, kind } of the last NPC/object we pinned

function ns.ShowOnMap(row)
    local qmap = Module("QuestieMap")
    if qmap then
        if shown and qmap.UnloadManualFrames then
            pcall(qmap.UnloadManualFrames, qmap, shown.kind == "object" and -shown.id or shown.id)
        end
        local fn = row.kind == "object" and qmap.ShowObject or qmap.ShowNPC
        if fn and pcall(fn, qmap, row.id) then shown = { id = row.id, kind = row.kind } end
    end

    if row.mapID then
        if C_Map and C_Map.OpenWorldMap then
            -- Blizzard's own path; avoids tainting the world map
            if InCombatLockdown() then
                ns.Print("can't open the map in combat.")
            else
                C_Map.OpenWorldMap(row.mapID)
            end
        elseif WorldMapFrame then
            if not WorldMapFrame:IsShown() then ToggleWorldMap() end
            WorldMapFrame:SetMapID(row.mapID)
        end
    end

    if row.x then
        local label = row.pinName or row.name
        if row.quest then label = row.name .. ": " .. label end
        ns.Print(string.format("%s - %s (%.1f, %.1f)", label, row.zone or "?", row.x, row.y))
    end
end

function ns.CanShowOnMap(row)
    return row.kind ~= nil and (row.mapID ~= nil or Module("QuestieMap") ~= nil)
end
