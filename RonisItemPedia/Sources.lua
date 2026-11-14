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

local function ZoneName(zoneID)
    if type(zoneID) ~= "number" or zoneID <= 0 then return nil end
    if C_Map and C_Map.GetAreaInfo then
        local ok, name = pcall(C_Map.GetAreaInfo, zoneID)
        if ok and name and name ~= "" then return name end
    end
end

-- Drop chance in percent. Questie only ships rates for quest-related items.
local questieDB
local function DropChance(itemID, npcID)
    if questieDB == nil then
        questieDB = false
        if QuestieLoader and QuestieLoader.ImportModule then
            local ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
            if ok and type(mod) == "table" then questieDB = mod end
        end
    end
    if not (questieDB and questieDB.GetItemDroprate) then return nil end
    local ok, rate = pcall(questieDB.GetItemDroprate, itemID, npcID)
    if ok and type(rate) == "table" and type(rate[1]) == "number" and rate[1] > 0 then
        return rate[1]
    end
end

local function NpcRow(npcID, itemID)
    local name = Get("NpcDB", npcID, "name")
    if not name then return nil end
    local lo, hi = Get("NpcDB", npcID, "minLevel"), Get("NpcDB", npcID, "maxLevel")
    local lvl
    if type(lo) == "number" and lo > 0 then
        lvl = (type(hi) == "number" and hi > lo) and (lo .. "-" .. hi) or tostring(lo)
    end
    local rank = Get("NpcDB", npcID, "rank")
    return {
        id = npcID,
        name = name,
        sub = Get("NpcDB", npcID, "subName"),
        level = lvl,
        rank = RANK[rank],
        zone = ZoneName(Get("NpcDB", npcID, "zoneID")),
        chance = itemID and DropChance(itemID, npcID),
    }
end

local function SortRows(rows)
    table.sort(rows, function(a, b)
        if (a.chance or -1) ~= (b.chance or -1) then return (a.chance or -1) > (b.chance or -1) end
        return a.name < b.name
    end)
end

-- Returns { drops = {rows}, dropsTotal, objects = {rows}, objectsTotal,
--           containers = {itemIDs}, vendors = {rows}, vendorsTotal, quests = {rows},
--           teaches = spellID }
function ns.GetSources(itemID)
    local out = { drops = {}, objects = {}, containers = {}, vendors = {}, quests = {} }
    if not ns.HasQuestieDB() then return out end

    local npcs = List(Get("ItemDB", itemID, "npcDrops"))
    for _, npc in ipairs(npcs) do
        local row = NpcRow(npc, itemID)
        if row then out.drops[#out.drops + 1] = row end
    end
    SortRows(out.drops)
    out.dropsTotal = #out.drops
    for i = #out.drops, MAX_ROWS + 1, -1 do out.drops[i] = nil end

    for _, obj in ipairs(List(Get("ItemDB", itemID, "objectDrops"))) do
        local name = Get("ObjectDB", obj, "name")
        if name then
            out.objects[#out.objects + 1] = { id = obj, name = name, zone = ZoneName(Get("ObjectDB", obj, "zoneID")) }
        end
    end
    -- the same herb/ore node exists as many object IDs; merge them by name
    local seen, merged = {}, {}
    for _, o in ipairs(out.objects) do
        local key = o.name .. "|" .. (o.zone or "")
        if not seen[key] then seen[key] = true; merged[#merged + 1] = o end
    end
    SortRows(merged)
    out.objectsTotal = #merged
    for i = #merged, MAX_ROWS + 1, -1 do merged[i] = nil end
    out.objects = merged

    for _, id in ipairs(List(Get("ItemDB", itemID, "itemDrops"))) do
        out.containers[#out.containers + 1] = id
    end

    for _, npc in ipairs(List(Get("ItemDB", itemID, "vendors"))) do
        local row = NpcRow(npc)
        if row then out.vendors[#out.vendors + 1] = row end
    end
    SortRows(out.vendors)
    out.vendorsTotal = #out.vendors
    for i = #out.vendors, MAX_ROWS + 1, -1 do out.vendors[i] = nil end

    for _, q in ipairs(List(Get("ItemDB", itemID, "questRewards"))) do
        local name = Get("QuestDB", q, "name")
        if name then
            out.quests[#out.quests + 1] = { id = q, name = name, level = Get("QuestDB", q, "questLevel") }
        end
    end

    local teaches = Get("ItemDB", itemID, "teachesSpell")
    if type(teaches) == "number" and teaches > 0 then out.teaches = teaches end
    return out
end
