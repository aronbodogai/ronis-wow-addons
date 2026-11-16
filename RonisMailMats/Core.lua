-- Roni's MailMats - core: saved data, profession scan, bag scan, mail drafting.
local ADDON, ns = ...

ns.TAG = "|cffff8c1aRoni's MailMats|r"

function ns.Print(...)
    print(ns.TAG .. ":", ...)
end

---------------------------------------------------------------------------
-- API shims (Classic-based client; prefer globals, fall back to C_ APIs)
---------------------------------------------------------------------------
local CC = C_Container
local GetContainerNumSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
local GetContainerItemID   = (CC and CC.GetContainerItemID) or GetContainerItemID
local PickupContainerItem  = (CC and CC.PickupContainerItem) or PickupContainerItem
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)

-- Returns count, locked, bound for a bag slot.
local function SlotInfo(bag, slot)
    if CC and CC.GetContainerItemInfo then
        local info = CC.GetContainerItemInfo(bag, slot)
        if not info then return end
        local bound = info.isBound
        if bound == nil and C_Item and C_Item.IsBound and ItemLocation then
            bound = C_Item.IsBound(ItemLocation:CreateFromBagAndSlot(bag, slot))
        end
        return info.stackCount, info.isLocked, bound
    end
    local _, count, locked = GetContainerItemInfo(bag, slot)
    local bound
    if C_Item and C_Item.IsBound and ItemLocation then
        bound = C_Item.IsBound(ItemLocation:CreateFromBagAndSlot(bag, slot))
    end
    return count, locked, bound
end

---------------------------------------------------------------------------
-- Window look: a solid background, and (for the top-level windows) the
-- world map's behaviour: while you move and the mouse is not over the
-- window it fades so you can see past it; standing still or hovering it, it
-- is solid again.
---------------------------------------------------------------------------
local FADED, FADE_SPEED = 0.35, 4 -- alpha while moving; alpha change per second

local function PlayerMoving()
    if IsPlayerMoving then return IsPlayerMoving() and true or false end
    return (GetUnitSpeed and (GetUnitSpeed("player") or 0) > 0) or false
end
ns.PlayerMoving = PlayerMoving

function ns.StyleWindow(frame, fade)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.06, 0.06, 0.07, 1)
    frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    if not fade then return end
    frame.RonisMailMatsAlpha = 1
    frame:HookScript("OnUpdate", function(self, elapsed)
        local target = (PlayerMoving() and not self:IsMouseOver()) and FADED or 1
        local a = self.RonisMailMatsAlpha
        if a == target then return end
        local step = (elapsed or 0) * FADE_SPEED
        if a < target then a = math.min(target, a + step) else a = math.max(target, a - step) end
        self.RonisMailMatsAlpha = a
        self:SetAlpha(a)
    end)
end

function ns.ItemID(ref)
    if type(ref) == "number" then return ref end
    if type(ref) ~= "string" then return nil end
    return tonumber(ref:match("item:(%d+)")) or tonumber(ref)
end

---------------------------------------------------------------------------
-- Reagent lookup: REAGENTS[prof] = {id,...}  ->  IS_REAGENT[prof][id] = true
---------------------------------------------------------------------------
-- BASE_GROUP[cat] is what the data files say; IS_REAGENT[cat] is that plus
-- your own edits (db.groups, see "Groups" below), and your custom groups.
ns.BASE_GROUP = {}
for prof, ids in pairs(ns.REAGENTS) do
    local set = {}
    for _, id in ipairs(ids) do set[id] = true end
    ns.BASE_GROUP[prof] = set
end

-- Items that need a non-crafting skill (Data/SkillItems.lua): a rogue's
-- lockboxes, a mage's Comprehension scrolls. They go through the same
-- lookup as reagents; SKILL_RANK[id] is the skill rank the item asks for.
ns.SKILL_RANK = {}
for skill, list in pairs(ns.SKILL_ITEMS or {}) do
    local set = ns.BASE_GROUP[skill] or {}
    for _, e in ipairs(list) do
        set[e[1]] = true
        ns.SKILL_RANK[e[1]] = e[2]
    end
    ns.BASE_GROUP[skill] = set
end

-- Waylaid Supplies and Waylaid Crates (Data/Crates.lua) go to the
-- profession that makes, or mostly uses, what they ask for.
for id, profs in pairs(ns.CRATES or {}) do
    for _, p in ipairs(profs) do
        ns.BASE_GROUP[p] = ns.BASE_GROUP[p] or {}
        ns.BASE_GROUP[p][id] = true
    end
end

-- Bind-on-equip green weapons and armor belong to Enchanting (to be
-- disenchanted). Decided from the item's own data, so it is not a list.
function ns.IsDisenchantable(id)
    if ns.db and ns.db.noGreens then return false end
    local name, _, quality, _, _, _, _, _, equipLoc, _, _, classID, _, bindType = GetItemInfo(id)
    return name ~= nil and quality == 2 and bindType == 2 and (classID == 2 or classID == 4)
        and equipLoc ~= nil and equipLoc ~= ""
end

-- Whether an item belongs to a group (a name, or a list of names).
function ns.InGroup(cat, id)
    if type(cat) == "table" then
        for _, c in ipairs(cat) do
            if ns.InGroup(c, id) then return true end
        end
        return false
    end
    local set = ns.IS_REAGENT[cat]
    if set and set[id] then return true end
    return cat == "Enchanting" and ns.IsDisenchantable(id)
end
ns.IS_REAGENT = {}
for cat, set in pairs(ns.BASE_GROUP) do
    local copy = {}
    for id in pairs(set) do copy[id] = true end
    ns.IS_REAGENT[cat] = copy
end

-- Order professions are shown in.
ns.CRAFT_ORDER = {
    "Tailoring", "Leatherworking", "Blacksmithing", "Engineering", "Alchemy",
    "Enchanting", "Mining", "Cooking", "First Aid", "Poisons",
    "Lockpicking", "Comprehension",
}

-- What a button sends ("Send <what> (N)"); professions default to "<prof> mats".
local WHAT = { Lockpicking = "lockboxes", Comprehension = "scrolls", Upgrades = "upgrades" }
local function WhatOne(p)
    if WHAT[p] then return WHAT[p] end
    if ns.IsCustomGroup and ns.IsCustomGroup(p) then return p end
    return p .. " mats"
end
function ns.What(prof)
    if type(prof) == "table" then -- a recipient's categories
        local parts = {}
        for _, p in ipairs(prof) do parts[#parts + 1] = WhatOne(p) end
        return #parts > 0 and table.concat(parts, ", ") or "nothing"
    end
    return WhatOne(prof)
end

-- Skills that GetProfessions does not list, read by skill line ID instead.
ns.EXTRA_SKILLS = { [633] = "Lockpicking", [3012] = "Comprehension" }

-- Profession skill line IDs -> the English names used as keys everywhere
-- (GetProfessionInfo's name follows the client language; the ID does not).
ns.SKILL_LINES = {
    [171] = "Alchemy", [164] = "Blacksmithing", [185] = "Cooking", [333] = "Enchanting",
    [202] = "Engineering", [129] = "First Aid", [165] = "Leatherworking", [186] = "Mining",
    [197] = "Tailoring", [40] = "Poisons",
    [182] = "Herbalism", [393] = "Skinning", [356] = "Fishing",
}
for id, name in pairs(ns.EXTRA_SKILLS) do ns.SKILL_LINES[id] = name end

-- Skill names we remember (crafting ones get buttons, gathering ones are
-- only shown next to the character's name).
local KNOWN_SKILLS = {}
for _, p in pairs(ns.SKILL_LINES) do KNOWN_SKILLS[p] = true end

-- Lockpicking and Comprehension are plain skill lines, not professions:
-- C_SkillInfo.GetSkillLineInfoByID(id) -> { name, rank, maxRank?, skillID,
-- isHeader, modifier } (field names as Questie and GatherLite use them on
-- this client). Unknown skills come back nil or at rank 0.
local function SkillMax(info)
    return info.maxRank or info.skillMaxRank or info.max or info.rank
end

function ns.ReadExtraSkills(profs)
    local SI = C_SkillInfo
    if not SI then return false end
    local any = false
    local found = {}
    if SI.GetSkillLineInfoByID then
        for id, key in pairs(ns.EXTRA_SKILLS) do
            local info = SI.GetSkillLineInfoByID(id)
            if info and (info.rank or 0) > 0 then
                profs[key] = { rank = info.rank, max = SkillMax(info) }
                found[key], any = true, true
            end
        end
    end
    -- fallback: walk the skill list for anything the by-ID lookup missed
    if SI.GetNumSkillLines and SI.GetSkillLineInfo then
        for i = 1, SI.GetNumSkillLines() or 0 do
            local info = SI.GetSkillLineInfo(i)
            local key = info and not info.isHeader and info.skillID and ns.EXTRA_SKILLS[info.skillID]
            if key and not found[key] and (info.rank or 0) > 0 then
                profs[key] = { rank = info.rank, max = SkillMax(info) }
                any = true
            end
        end
    end
    return any
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
local function InitDB()
    RonisMailMatsDB = RonisMailMatsDB or {}
    local db = RonisMailMatsDB
    db.chars = db.chars or {}    -- [realm][name] = { class, faction, level, profs = {[name]=rank} }
    db.ignore = db.ignore or {}  -- [itemID] = true: never put in a draft
    if db.keepOwn == nil then db.keepOwn = true end
    db.targets = db.targets or {} -- [realm][name] = { cats = { "Tailoring", ... } }: friends, guildies, anyone
    -- your changes to the item groups: edits[cat] = { add = {[id]=true}, remove = {[id]=true} },
    -- custom[name] = {[id]=true}
    db.groups = db.groups or {}
    db.groups.edits = db.groups.edits or {}
    db.groups.custom = db.groups.custom or {}
    ns.db = db
    ns.realm = GetRealmName()
    -- WoW Forever characters have a first name and a surname; UnitName gives
    -- them as two values ("Silva", "Moonbrook") and mail needs both, joined
    -- with a space. Other clients give no second value for the player.
    local first, surname = UnitName("player")
    ns.me = (surname and surname ~= "") and (first .. " " .. surname) or first
    ns.surnames = ns.me ~= first
    ns.RebuildGroups()
    ns.faction = UnitFactionGroup("player")
    db.chars[ns.realm] = db.chars[ns.realm] or {}
    db.targets[ns.realm] = db.targets[ns.realm] or {}
    -- versions before 0.6 filed this character under its first name only
    local chars = db.chars[ns.realm]
    if ns.surnames and chars[first] and not chars[ns.me] then
        local _, class = UnitClass("player")
        if chars[first].class == class then chars[ns.me], chars[first] = chars[first], nil end
    end
end

-- On a client with surnames, an alt saved by an older version under its
-- first name only cannot be mailed until it logs in once.
function ns.NeedsFullName(name)
    return ns.surnames and not name:find(" ")
end

---------------------------------------------------------------------------
-- Other recipients: anyone (friend, guildie, an alt on another account) with
-- the categories they want. One button sends all of them in one mail.
---------------------------------------------------------------------------
-- Categories a recipient can want: every profession and skill, in panel order.
-- Built-in groups in panel order, then your custom groups by name.
function ns.Categories()
    local list = {}
    for _, p in ipairs(ns.CRAFT_ORDER) do list[#list + 1] = p end
    local custom = {}
    for name in pairs(ns.db and ns.db.groups.custom or {}) do custom[#custom + 1] = name end
    table.sort(custom)
    for _, name in ipairs(custom) do list[#list + 1] = name end
    return list
end

---------------------------------------------------------------------------
-- Groups: the item lists behind every button, editable
---------------------------------------------------------------------------
function ns.IsCustomGroup(name)
    return ns.db ~= nil and ns.db.groups.custom[name] ~= nil
end

function ns.RebuildGroups()
    local g = ns.db.groups
    ns.IS_REAGENT = {}
    for cat, base in pairs(ns.BASE_GROUP) do
        local e = g.edits[cat] or {}
        local set = {}
        for id in pairs(base) do
            if not (e.remove and e.remove[id]) then set[id] = true end
        end
        for id in pairs(e.add or {}) do set[id] = true end
        ns.IS_REAGENT[cat] = set
    end
    for name, items in pairs(g.custom) do
        local set = {}
        for id in pairs(items) do set[id] = true end
        ns.IS_REAGENT[name] = set
    end
    if ns.Refresh then ns.Refresh() end
end

-- Item ids in a group, sorted by name (uncached items last, by id).
function ns.GroupItems(cat)
    local ids = {}
    for id in pairs(ns.IS_REAGENT[cat] or {}) do ids[#ids + 1] = id end
    local names = {}
    for _, id in ipairs(ids) do names[id] = GetItemInfo(id) end
    table.sort(ids, function(a, b)
        local na, nb = names[a], names[b]
        if na and nb and na ~= nb then return na < nb end
        if (na ~= nil) ~= (nb ~= nil) then return na ~= nil end
        return a < b
    end)
    return ids
end

-- Whether a built-in group differs from the data files.
function ns.GroupEdited(cat)
    local e = ns.db.groups.edits[cat]
    return e ~= nil and (next(e.add or {}) ~= nil or next(e.remove or {}) ~= nil)
end

function ns.GroupAdd(cat, id)
    if not (cat and id) then return false end
    local g = ns.db.groups
    if g.custom[cat] then
        g.custom[cat][id] = true
    elseif ns.BASE_GROUP[cat] then
        local e = g.edits[cat] or { add = {}, remove = {} }
        g.edits[cat] = e
        e.remove[id] = nil
        if not ns.BASE_GROUP[cat][id] then e.add[id] = true end
    else
        return false
    end
    ns.RebuildGroups()
    return true
end

function ns.GroupRemove(cat, id)
    local g = ns.db.groups
    if g.custom[cat] then
        g.custom[cat][id] = nil
    elseif ns.BASE_GROUP[cat] then
        local e = g.edits[cat] or { add = {}, remove = {} }
        g.edits[cat] = e
        e.add[id] = nil
        if ns.BASE_GROUP[cat][id] then e.remove[id] = true end
    else
        return false
    end
    ns.RebuildGroups()
    return true
end

-- Undo every edit to a built-in group.
function ns.GroupReset(cat)
    ns.db.groups.edits[cat] = nil
    ns.RebuildGroups()
end

-- Creates an empty custom group; returns its name, or nil and why not.
function ns.NewGroup(name)
    name = strtrim(name or "")
    if name == "" then return nil, "Enter a name for the group." end
    for _, p in ipairs(ns.Categories()) do
        if p:lower() == name:lower() then return nil, "There is already a group called " .. p .. "." end
    end
    ns.db.groups.custom[name] = {}
    ns.RebuildGroups()
    return name
end

-- Deletes a custom group and takes it off every recipient.
function ns.DeleteGroup(name)
    if not ns.IsCustomGroup(name) then return false end
    ns.db.groups.custom[name] = nil
    for _, t in pairs(ns.db.targets[ns.realm] or {}) do
        for i = #t.cats, 1, -1 do
            if t.cats[i] == name then table.remove(t.cats, i) end
        end
    end
    for rname, t in pairs(ns.db.targets[ns.realm] or {}) do
        if #t.cats == 0 then ns.db.targets[ns.realm][rname] = nil end
    end
    ns.RebuildGroups()
    return true
end

-- Category from user input: "tailoring", "Tailoring mats", "scrolls", ...
function ns.FindCategory(text)
    text = strtrim(text or ""):lower()
    if text == "" then return nil end
    for _, p in ipairs(ns.Categories()) do
        if p:lower() == text or ns.What(p):lower() == text then return p end
    end
    for _, p in ipairs(ns.Categories()) do -- unique prefix: "tail", "lock"
        if p:lower():sub(1, #text) == text then return p end
    end
end

local function NormalName(name)
    name = strtrim(name or "")
    if name == "" then return nil end
    return name:sub(1, 1):upper() .. name:sub(2)
end

-- Sets (or with no categories, removes) a recipient. Returns the stored name.
function ns.SetTarget(name, cats)
    name = NormalName(name)
    if not name then return nil end
    local want, list = {}, {}
    for _, p in ipairs(cats or {}) do want[p] = true end
    for _, p in ipairs(ns.Categories()) do -- keep panel order
        if want[p] then list[#list + 1] = p end
    end
    local targets = ns.db.targets[ns.realm]
    for k in pairs(targets) do -- same name, other case
        if k:lower() == name:lower() then targets[k] = nil end
    end
    targets[name] = #list > 0 and { cats = list } or nil
    if ns.Refresh then ns.Refresh() end
    return name
end

function ns.Targets()
    local list = {}
    for name in pairs(ns.db.targets[ns.realm] or {}) do list[#list + 1] = name end
    table.sort(list)
    return list
end

function ns.TargetCats(name)
    local t = ns.db.targets[ns.realm][name]
    return t and t.cats or {}
end

function ns.MyChar()
    return ns.db.chars[ns.realm][ns.me]
end

-- Alts on this realm and faction (mail can reach them), sorted by name.
function ns.Alts()
    local list = {}
    for name, c in pairs(ns.db.chars[ns.realm] or {}) do
        if name ~= ns.me and c.faction == ns.faction then
            list[#list + 1] = name
        end
    end
    table.sort(list)
    return list
end

---------------------------------------------------------------------------
-- Profession scan
---------------------------------------------------------------------------
-- Returns { [name] = { rank, max } } and the API used, or nil when the client
-- has no profession API or it has not loaded yet.
--
-- The Forever client runs the modern engine: it has GetProfessions /
-- GetProfessionInfo and NOT the Classic GetNumSkillLines / GetSkillLineInfo
-- (Ketho/BlizzardInterfaceResources, forever branch). The skill line list
-- is only a fallback for real Classic clients.
function ns.ReadProfessions()
    if GetProfessions and GetProfessionInfo then
        local idx = { GetProfessions() } -- prof1, prof2, archaeology, fishing, cooking, first aid (nil holes)
        local profs, any = {}, false
        for k = 1, 6 do
            if idx[k] then
                local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(idx[k])
                local key = (skillLine and ns.SKILL_LINES[skillLine]) or (KNOWN_SKILLS[name] and name)
                if key then
                    profs[key] = { rank = rank, max = maxRank }
                    any = true
                end
            end
        end
        if ns.ReadExtraSkills(profs) then any = true end
        return profs, "GetProfessions", any
    end
    if GetNumSkillLines and GetSkillLineInfo then
        -- expand collapsed headers so every skill line is listed
        for i = GetNumSkillLines(), 1, -1 do
            local _, isHeader, isExpanded = GetSkillLineInfo(i)
            if isHeader and not isExpanded and ExpandSkillHeader then ExpandSkillHeader(i) end
        end
        local n = GetNumSkillLines() or 0
        if n == 0 then return nil, "GetSkillLineInfo" end -- not loaded yet
        local profs, any = {}, false
        for i = 1, n do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if not isHeader and name and KNOWN_SKILLS[name] then
                profs[name] = { rank = rank, max = maxRank }
                any = true
            end
        end
        return profs, "GetSkillLineInfo", any
    end
    return nil, "none"
end

-- Records this character. Always stores the character (so it shows up as an
-- alt even without professions); professions are only replaced by a
-- non-empty read, or an empty one after login has settled (`final`), so an
-- API that is not ready yet never wipes what we knew.
function ns.ScanSkills(final)
    local profs, _, any = ns.ReadProfessions()
    local chars = ns.db.chars[ns.realm]
    local old = chars[ns.me]
    if not any and not final and old and old.profs then
        profs = old.profs
    end
    local _, class = UnitClass("player")
    chars[ns.me] = {
        class = class,
        faction = ns.faction,
        level = UnitLevel("player"),
        profs = profs or (old and old.profs) or {},
        gear = old and old.gear, -- Gear.lua
        seen = time(),
    }
    if ns.Refresh then ns.Refresh() end
end

---------------------------------------------------------------------------
-- Bag scan: which stacks in my bags would go to <prof>
---------------------------------------------------------------------------
-- Why an item is held back (nil = mailable): on the ignore list, or (with
-- "keep my own mats" on) a reagent for one of this character's professions.
--
-- Which of my professions keep their mats is chosen per profession
-- (db.keepFor[prof]); by default the main crafting professions do and the
-- secondary professions (Cooking, First Aid, Poisons) do not, so Linen Cloth for one bandage recipe does not
-- stop it from going to your tailor.
local KEEP_DEFAULT = {
    Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true,
    Leatherworking = true, Tailoring = true, Mining = true,
    Cooking = false, ["First Aid"] = false, Poisons = false,
    Lockpicking = true, Comprehension = true, -- you open and read these yourself
}
function ns.KeepsFor(prof)
    local v = ns.db.keepFor and ns.db.keepFor[prof]
    if v == nil then return KEEP_DEFAULT[prof] or false end
    return v
end
function ns.SetKeepFor(prof, on)
    ns.db.keepFor = ns.db.keepFor or {}
    ns.db.keepFor[prof] = on and true or false
    if ns.Refresh then ns.Refresh() end
end

-- This character's professions that have mats, in panel order.
function ns.MyCraftProfs()
    local me = ns.MyChar()
    local list = {}
    for _, p in ipairs(ns.CRAFT_ORDER) do
        if me and me.profs and me.profs[p] then list[#list + 1] = p end
    end
    return list
end

function ns.HoldReason(id)
    if ns.db.ignore[id] then return "ignored" end
    if ns.db.keepOwn then
        for _, p in ipairs(ns.MyCraftProfs()) do
            if ns.KeepsFor(p) and ns.InGroup(p, id) then
                return "kept for your " .. p
            end
        end
    end
end

-- Items of a group that are in the bags but held back: { {id, count, reason} }.
function ns.HeldFor(prof)
    local out, index = {}, {}
    if type(prof) ~= "table" and not ns.IS_REAGENT[prof] then return out end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id = GetContainerItemID(bag, slot)
            local why = id and ns.InGroup(prof, id) and ns.HoldReason(id)
            if why then
                local count = SlotInfo(bag, slot) or 1
                if index[id] then
                    index[id][2] = index[id][2] + count
                else
                    index[id] = { id, count, why }
                    out[#out + 1] = index[id]
                end
            end
        end
    end
    return out
end

-- Returns { {bag, slot, id, count}, ... } of mailable stacks for prof,
-- plus a total-by-item table { [id] = count } in first-seen order (ids list).
-- prof "Upgrades" means gear that is an upgrade for `alt` (Gear.lua).
function ns.StacksFor(prof, alt)
    local upgrades = prof == "Upgrades"
    local stacks, totals, ids = {}, {}, {}
    if not upgrades and type(prof) ~= "table" and not ns.IS_REAGENT[prof] then return stacks, totals, ids end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id = GetContainerItemID(bag, slot)
            local wanted
            if upgrades then
                wanted = id and not ns.db.ignore[id] and ns.IsUpgradeIn(bag, slot, alt)
            else
                wanted = id and ns.InGroup(prof, id) and not ns.HoldReason(id)
                -- a green that upgrades one of your alts is not disenchant fodder
                if wanted and ns.IsDisenchantable(id) and not (ns.IS_REAGENT.Enchanting or {})[id]
                    and ns.IsUpgradeIn and ns.IsUpgradeIn(bag, slot) then
                    wanted = false
                end
            end
            if wanted then
                local count, _, bound = SlotInfo(bag, slot)
                if not bound then
                    stacks[#stacks + 1] = { bag = bag, slot = slot, id = id, count = count or 1 }
                    if not totals[id] then ids[#ids + 1] = id end
                    totals[id] = (totals[id] or 0) + (count or 1)
                end
            end
        end
    end
    return stacks, totals, ids
end

---------------------------------------------------------------------------
-- Drafting: open the Send Mail tab with recipient, subject and attachments.
-- Nothing is sent; the player reviews and presses Send.
---------------------------------------------------------------------------
local MAX_ATTACH = ATTACHMENTS_MAX_SEND or 12

---------------------------------------------------------------------------
-- Mail body: a random message (Data/Messages.lua) with {name} and {what}
-- filled in. Never replaces text you typed yourself.
---------------------------------------------------------------------------
-- The body box: SendMailBodyEditBox on Classic-style mail frames, the
-- scrolling MailEditBox on modern ones.
local function BodyBox()
    if SendMailBodyEditBox then return SendMailBodyEditBox end
    if MailEditBox then return (MailEditBox.GetEditBox and MailEditBox:GetEditBox()) or MailEditBox end
end
ns.BodyBox = BodyBox

local lastIndex

-- A random message, never the one shown last. Returns the text and its index.
function ns.RandomMessage(name, what)
    local list = ns.MESSAGES or {}
    if #list == 0 then return nil end
    local i = math.random(#list)
    if #list > 1 and i == lastIndex then i = (i % #list) + 1 end
    lastIndex = i
    local first = (name or ""):match("^(%S+)") or name or "friend"
    local text = list[i]:gsub("{name}", first):gsub("{what}", what or "mats")
    return text, i
end

-- Puts a random message in the body. `force` (the New message button) also
-- replaces our own earlier message; text you typed is always left alone.
function ns.FillMessage(force)
    if ns.db and ns.db.noMessage and not force then return end
    local box = BodyBox()
    if not box then return end
    local current = box:GetText() or ""
    if current ~= "" and current ~= ns.lastBody then return false end
    local d = ns.lastDraft or {}
    local name = d.name or (SendMailNameEditBox and SendMailNameEditBox:GetText()) or ""
    local text = ns.RandomMessage(name, d.what)
    if not text then return false end
    box:SetText(text)
    ns.lastBody = text
    return true
end

-- Next empty attachment slot. `used` tracks slots filled this pass, since
-- HasSendMailItem may lag behind until the attachment is confirmed.
local function FreeSlot(used)
    for i = 1, MAX_ATTACH do
        if not used[i] and not HasSendMailItem(i) then return i end
    end
end

---------------------------------------------------------------------------
-- Cash on delivery for BoE greens sent to someone else for disenchanting:
-- a share of their vendor price (db.greenCOD: percent, default 100; false
-- = never). Never asked of your own characters - that would pay yourself.
---------------------------------------------------------------------------
ns.COD_STEPS = { false, 25, 50, 75, 100, 150, 200 }

function ns.CODPercent()
    local v = ns.db.greenCOD
    if v == nil then return 100 end
    return v or 0
end

-- A green that would go to an enchanter only because it is a BoE green.
function ns.IsGreenForCOD(id)
    return ns.IsDisenchantable(id) and not ((ns.IS_REAGENT.Enchanting or {})[id])
end

function ns.MoneyText(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

local codSet = false -- whether the money field holds a COD we put there

-- Sets (or clears) the draft's cash on delivery. Returns the amount set.
function ns.SetDraftCOD(name, greenValue)
    local mine = ns.db.chars[ns.realm][name] ~= nil
    local pct = ns.CODPercent()
    local copper = 0
    if not mine and pct > 0 and greenValue > 0 then
        copper = math.max(1, math.floor(greenValue * pct / 100))
    end
    if copper == 0 and not codSet then return 0 end -- leave the player's own money settings alone
    if SendMailMoney and MoneyInputFrame_SetCopper then MoneyInputFrame_SetCopper(SendMailMoney, copper) end
    if SendMailRadioButton_OnClick then SendMailRadioButton_OnClick(copper > 0 and 2 or 1) end
    if SetSendMailCOD then SetSendMailCOD(copper) end
    codSet = copper > 0
    return copper
end

local function Attach(name, prof)
    local stacks = ns.StacksFor(prof, name)
    local attached, skipped = 0, 0
    local greenValue = 0 -- vendor value of the BoE greens attached
    local used = {}
    ClearCursor()
    for _, s in ipairs(stacks) do
        local _, locked = SlotInfo(s.bag, s.slot)
        if locked then
            skipped = skipped + 1
        else
            local i = FreeSlot(used)
            if not i then break end
            PickupContainerItem(s.bag, s.slot)
            if CursorHasItem() then
                ClickSendMailItemButton(i)
                used[i] = true
                if CursorHasItem() then -- refused (soulbound, quest item...)
                    ClearCursor()
                    skipped = skipped + 1
                else
                    attached = attached + 1
                    if ns.IsGreenForCOD(s.id) then
                        local sell = select(11, GetItemInfo(s.id)) or 0
                        greenValue = greenValue + sell * (s.count or 1)
                    end
                end
            end
        end
    end
    if SendMailNameEditBox then SendMailNameEditBox:SetText(name) end
    local what = ns.What(prof)
    if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText((what:gsub("^%l", string.upper))) end
    ns.lastDraft = { name = name, what = what }
    ns.FillMessage(false)
    local cod = ns.SetDraftCOD(name, greenValue)
    local left = #stacks - attached - skipped
    if left > 0 then
        ns.Print(("Drafted %d stacks of %s for %s. %d more stack(s) left - press the button again after sending.")
            :format(attached, what, name, left))
    else
        ns.Print(("Drafted %d stack(s) of %s for %s. Review and press Send."):format(attached, what, name))
    end
    if cod and cod > 0 then
        ns.Print(("Cash on delivery: %s (%d%% of the greens' vendor price)."):format(ns.MoneyText(cod), ns.CODPercent()))
    end
    if ns.Refresh then ns.Refresh() end
end

function ns.Draft(name, prof)
    if InCombatLockdown and InCombatLockdown() then return end
    if not (MailFrame and MailFrame:IsShown()) then return end
    if not (SendMailFrame and SendMailFrame:IsShown()) and MailFrameTab2 then
        MailFrameTab2:Click()
    end
    -- start a fresh draft: return anything already attached to the bags
    ClearCursor()
    local cleared = false
    for i = 1, MAX_ATTACH do
        if HasSendMailItem(i) then
            ClickSendMailItemButton(i, true)
            cleared = true
        end
    end
    if cleared then
        C_Timer.After(0.3, function() Attach(name, prof) end)
    else
        Attach(name, prof)
    end
end

---------------------------------------------------------------------------
-- Events and slash commands
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("SKILL_LINES_CHANGED")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        InitDB()
        ns.ScanSkills(false)
        -- profession data can arrive a little after login: look again, and
        -- trust an empty answer only once things have settled
        C_Timer.After(3, function() ns.ScanSkills(false) end)
        C_Timer.After(15, function() ns.ScanSkills(true) end)
        if ns.InitGear then ns.InitGear() end
        if ns.InitSocial then ns.InitSocial() end
        if ns.InitMinimap then ns.InitMinimap() end
        if ns.InitUI then ns.InitUI() end
    elseif ns.db then
        ns.ScanSkills(false)
    end
end)

local function ProfString(c)
    local parts = {}
    for p, info in pairs(c.profs or {}) do
        parts[#parts + 1] = ("%s %d"):format(p, info.rank or 0)
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ", ") or "no professions"
end
ns.ProfString = ProfString

SLASH_RONISMAILMATS1 = "/mailmats"
SlashCmdList.RONISMAILMATS = function(msg)
    msg = strtrim(msg or "")
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "forget" and arg ~= "" then
        local key
        for name in pairs(ns.db.chars[ns.realm]) do
            if name:lower() == arg:lower() then key = name end
        end
        if key then
            ns.db.chars[ns.realm][key] = nil
            ns.Print("Forgot " .. key .. ".")
            if ns.Refresh then ns.Refresh() end
        else
            ns.Print("No character named " .. arg .. " on " .. ns.realm .. ".")
        end
    elseif cmd == "ignore" or cmd == "unignore" then
        local id = ns.ItemID(arg)
        if not id then
            local _, link = GetItemInfo(arg)
            id = ns.ItemID(link)
        end
        if not id then return ns.Print("Usage: /mailmats " .. cmd .. " <item link or id>") end
        ns.db.ignore[id] = (cmd == "ignore") or nil
        local _, link = GetItemInfo(id)
        ns.Print((link or ("item " .. id)) .. (cmd == "ignore" and " will never be drafted." or " can be drafted again."))
        if ns.Refresh then ns.Refresh() end
    elseif cmd == "target" or cmd == "untarget" then
        -- "Name Surname: tailoring, scrolls", or "Name tailoring, scrolls"
        local name, rest = arg:match("^([^:]+):%s*(.-)$")
        if name then name = strtrim(name) else name, rest = arg:match("^(%S+)%s*(.-)$") end
        if cmd == "untarget" and arg ~= "" then name, rest = strtrim(arg), "" end
        if not name then
            return ns.Print("Usage: /mailmats target <first last>: <category>, <category>... | /mailmats untarget <first last>")
        end
        local cats = {}
        if cmd == "target" then
            for part in rest:gmatch("[^,]+") do
                local p = ns.FindCategory(part)
                if not p then return ns.Print("Unknown category '" .. strtrim(part) .. "'.") end
                cats[#cats + 1] = p
            end
            if #cats == 0 then return ns.Print("Name at least one category, e.g. /mailmats target " .. name .. " tailoring, scrolls") end
        end
        local stored = ns.SetTarget(name, cats)
        if #cats > 0 then
            ns.Print(("%s will get %s."):format(stored, ns.What(ns.TargetCats(stored))))
        else
            ns.Print(stored .. " removed.")
        end
    elseif cmd == "targets" then
        local list = ns.Targets()
        if #list == 0 then ns.Print("No other recipients. Add one: /mailmats target <name> tailoring, scrolls") end
        for _, name in ipairs(list) do ns.Print(("  %s: %s"):format(name, ns.What(ns.TargetCats(name)))) end
    elseif cmd == "groups" or cmd == "group" then
        local cat = arg ~= "" and ns.FindCategory(arg) or nil
        if arg ~= "" and not cat then return ns.Print("No group called '" .. arg .. "'.") end
        ns.ToggleGroups(cat)
    elseif cmd == "cod" then
        local v = arg:lower():gsub("%%", "")
        if v == "off" or v == "0" then
            ns.db.greenCOD = false
        elseif tonumber(v) then
            ns.db.greenCOD = math.max(1, math.min(1000, math.floor(tonumber(v))))
        elseif v ~= "" then
            return ns.Print("Usage: /mailmats cod <percent of vendor price> | off")
        end
        local pct = ns.CODPercent()
        ns.Print(pct == 0 and "Greens are sent without cash on delivery."
            or ("Greens sent to other players ask %d%% of their vendor price as cash on delivery."):format(pct))
        if ns.Refresh then ns.Refresh() end
    elseif cmd == "ahead" then
        local n = tonumber(arg)
        if n then
            ns.db.upgradeAhead = math.max(0, math.min(20, math.floor(n)))
        elseif arg ~= "" then
            return ns.Print("Usage: /mailmats ahead <levels> (0 = only gear an alt can wear now)")
        end
        local v = ns.UpgradeAhead()
        ns.Print(v == 0 and "Upgrades: only gear your alts can wear now."
            or ("Upgrades: also gear your alts can wear within %d level(s)."):format(v))
        if ns.Refresh then ns.Refresh() end
    elseif cmd == "greens" then
        if arg == "off" then ns.db.noGreens = true elseif arg == "on" then ns.db.noGreens = nil end
        ns.Print(ns.db.noGreens and "BoE green gear is no longer sent to enchanters. /mailmats greens on turns it back on."
            or "BoE green weapons and armor go to Enchanting (except upgrades for your alts). /mailmats greens off stops it.")
        if ns.Refresh then ns.Refresh() end
    elseif cmd == "message" or cmd == "messages" then
        if arg == "off" then
            ns.db.noMessage = true
        elseif arg == "on" then
            ns.db.noMessage = nil
        end
        ns.Print(ns.db.noMessage and "Drafts get no message. /mailmats message on turns it back on."
            or ("Drafts get a random message (%d to pick from). /mailmats message off turns it off."):format(#(ns.MESSAGES or {})))
    elseif cmd == "minimap" then
        ns.SetMinimapShown(ns.db.hideMinimap and true or false)
        ns.Print(ns.db.hideMinimap and "Minimap button hidden. /mailmats minimap shows it again." or "Minimap button shown.")
    elseif cmd == "scan" then
        ns.ScanSkills(true)
        ns.Print(ns.me .. ": " .. ProfString(ns.MyChar()))
    elseif cmd == "selftest" then
        ns.SelfTest()
    elseif cmd == "ignored" then
        local any = false
        for id in pairs(ns.db.ignore) do
            local _, link = GetItemInfo(id)
            ns.Print("  " .. (link or id))
            any = true
        end
        if not any then ns.Print("No ignored items.") end
    else
        ns.Print("Known characters on " .. ns.realm .. ":")
        local names = {}
        for name in pairs(ns.db.chars[ns.realm]) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local c = ns.db.chars[ns.realm][name]
            ns.Print(("  %s (%s, %s): %s"):format(name, c.faction or "?", c.level or "?", ProfString(c)))
        end
        ns.Print("/mailmats scan | selftest | forget <name> | ignore <item> | unignore <item> | ignored")
        ns.Print("/mailmats target <first last>: <category>, ... | untarget <first last> | targets")
        ns.Print("/mailmats groups [group] | minimap | ahead <levels> | cod <percent>|off | greens on|off | message on|off")
    end
end

---------------------------------------------------------------------------
-- In-game self test: /mailmats selftest
-- Checks the client API this addon relies on and shows what it reads.
---------------------------------------------------------------------------
local REQUIRED = {
    "GetRealmName", "UnitName", "UnitClass", "UnitFactionGroup", "UnitLevel",
    "C_Container.GetContainerNumSlots", "C_Container.GetContainerItemID",
    "C_Container.GetContainerItemInfo", "C_Container.PickupContainerItem",
    "HasSendMailItem", "ClickSendMailItemButton", "CursorHasItem", "ClearCursor",
    "C_Timer.After", "MailFrame", "MailFrameTab2", "SendMailFrame",
    "SendMailNameEditBox", "SendMailSubjectEditBox",
}

local function Lookup(path)
    local v = _G
    for part in path:gmatch("[^.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
    end
    return v
end

function ns.SelfTest()
    local bad = 0
    for _, name in ipairs(REQUIRED) do
        if Lookup(name) == nil then
            bad = bad + 1
            ns.Print("|cffff4040missing|r " .. name)
        end
    end
    local profs, api = ns.ReadProfessions()
    if api == "none" then
        bad = bad + 1
        ns.Print("|cffff4040missing|r profession API (GetProfessions or GetSkillLineInfo)")
    end
    local parts = {}
    for p, info in pairs(profs or {}) do parts[#parts + 1] = p .. " " .. tostring(info.rank) end
    table.sort(parts)
    ns.Print(("Profession API: %s -> %s"):format(api, #parts > 0 and table.concat(parts, ", ") or "nothing"))
    ns.Print("Mail body box: " .. ((SendMailBodyEditBox and "SendMailBodyEditBox") or (MailEditBox and "MailEditBox")
        or "|cffff4040not found|r (random messages are off)"))
    -- raw skill line data for Lockpicking / Comprehension, to check field names
    local SI = C_SkillInfo
    for id, key in pairs(ns.EXTRA_SKILLS) do
        local info = SI and SI.GetSkillLineInfoByID and SI.GetSkillLineInfoByID(id)
        local fields = {}
        if type(info) == "table" then
            for k, v in pairs(info) do fields[#fields + 1] = k .. "=" .. tostring(v) end
            table.sort(fields)
        end
        ns.Print(("  %s (%d): %s"):format(key, id,
            #fields > 0 and table.concat(fields, " ") or (SI and SI.GetSkillLineInfoByID and "not known" or "no C_SkillInfo")))
    end
    local n = 0
    for _ in pairs(ns.db.chars[ns.realm] or {}) do n = n + 1 end
    ns.Print(("Realm '%s', %s, %d character(s) saved, %d alt(s) mailable."):format(
        tostring(ns.realm), tostring(ns.faction), n, #ns.Alts()))
    ns.Print(bad == 0 and "|cff40ff40Self test passed.|r" or ("|cffff4040%d problem(s).|r"):format(bad))
    return bad
end
