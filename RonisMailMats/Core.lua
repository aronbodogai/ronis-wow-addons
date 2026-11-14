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

function ns.ItemID(ref)
    if type(ref) == "number" then return ref end
    if type(ref) ~= "string" then return nil end
    return tonumber(ref:match("item:(%d+)")) or tonumber(ref)
end

---------------------------------------------------------------------------
-- Reagent lookup: REAGENTS[prof] = {id,...}  ->  IS_REAGENT[prof][id] = true
---------------------------------------------------------------------------
ns.IS_REAGENT = {}
for prof, ids in pairs(ns.REAGENTS) do
    local set = {}
    for _, id in ipairs(ids) do set[id] = true end
    ns.IS_REAGENT[prof] = set
end

-- Items that need a non-crafting skill (Data/SkillItems.lua): a rogue's
-- lockboxes, a mage's Comprehension scrolls. They go through the same
-- lookup as reagents; SKILL_RANK[id] is the skill rank the item asks for.
ns.SKILL_RANK = {}
for skill, list in pairs(ns.SKILL_ITEMS or {}) do
    local set = ns.IS_REAGENT[skill] or {}
    for _, e in ipairs(list) do
        set[e[1]] = true
        ns.SKILL_RANK[e[1]] = e[2]
    end
    ns.IS_REAGENT[skill] = set
end

-- Order professions are shown in.
ns.CRAFT_ORDER = {
    "Tailoring", "Leatherworking", "Blacksmithing", "Engineering", "Alchemy",
    "Enchanting", "Mining", "Cooking", "First Aid", "Poisons",
    "Lockpicking", "Comprehension",
}

-- What a button sends ("Send <what> (N)"); professions default to "<prof> mats".
local WHAT = { Lockpicking = "lockboxes", Comprehension = "scrolls", Upgrades = "upgrades" }
function ns.What(prof)
    if type(prof) == "table" then -- a recipient's categories
        local parts = {}
        for _, p in ipairs(prof) do parts[#parts + 1] = WHAT[p] or (p .. " mats") end
        return #parts > 0 and table.concat(parts, ", ") or "nothing"
    end
    return WHAT[prof] or (prof .. " mats")
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
    ns.db = db
    ns.realm = GetRealmName()
    ns.me = UnitName("player")
    ns.faction = UnitFactionGroup("player")
    db.chars[ns.realm] = db.chars[ns.realm] or {}
    db.targets[ns.realm] = db.targets[ns.realm] or {}
end

---------------------------------------------------------------------------
-- Other recipients: anyone (friend, guildie, an alt on another account) with
-- the categories they want. One button sends all of them in one mail.
---------------------------------------------------------------------------
-- Categories a recipient can want: every profession and skill, in panel order.
function ns.Categories() return ns.CRAFT_ORDER end

-- Category from user input: "tailoring", "Tailoring mats", "scrolls", ...
function ns.FindCategory(text)
    text = strtrim(text or ""):lower()
    if text == "" then return nil end
    for _, p in ipairs(ns.CRAFT_ORDER) do
        if p:lower() == text or ns.What(p):lower() == text then return p end
    end
    for _, p in ipairs(ns.CRAFT_ORDER) do -- unique prefix: "tail", "lock"
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
    for _, p in ipairs(ns.CRAFT_ORDER) do -- keep panel order
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
function ns.HoldReason(id)
    if ns.db.ignore[id] then return "ignored" end
    if ns.db.keepOwn then
        local me = ns.MyChar()
        for p in pairs(me and me.profs or {}) do
            if ns.IS_REAGENT[p] and ns.IS_REAGENT[p][id] then
                return "my " .. p
            end
        end
    end
end

-- Returns { {bag, slot, id, count}, ... } of mailable stacks for prof,
-- plus a total-by-item table { [id] = count } in first-seen order (ids list).
-- prof "Upgrades" means gear that is an upgrade for `alt` (Gear.lua).
function ns.StacksFor(prof, alt)
    local upgrades = prof == "Upgrades"
    local set = ns.IS_REAGENT[prof]
    if type(prof) == "table" then -- several categories at once (a recipient's)
        set = {}
        for _, p in ipairs(prof) do
            for id in pairs(ns.IS_REAGENT[p] or {}) do set[id] = true end
        end
    end
    local stacks, totals, ids = {}, {}, {}
    if not set and not upgrades then return stacks, totals, ids end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id = GetContainerItemID(bag, slot)
            local wanted
            if upgrades then
                wanted = id and not ns.db.ignore[id] and ns.IsUpgradeIn(bag, slot, alt)
            else
                wanted = id and set[id] and not ns.HoldReason(id)
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

-- Next empty attachment slot. `used` tracks slots filled this pass, since
-- HasSendMailItem may lag behind until the attachment is confirmed.
local function FreeSlot(used)
    for i = 1, MAX_ATTACH do
        if not used[i] and not HasSendMailItem(i) then return i end
    end
end

local function Attach(name, prof)
    local stacks = ns.StacksFor(prof, name)
    local attached, skipped = 0, 0
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
                end
            end
        end
    end
    if SendMailNameEditBox then SendMailNameEditBox:SetText(name) end
    local what = ns.What(prof)
    if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText((what:gsub("^%l", string.upper))) end
    local left = #stacks - attached - skipped
    if left > 0 then
        ns.Print(("Drafted %d stacks of %s for %s. %d more stack(s) left - press the button again after sending.")
            :format(attached, what, name, left))
    else
        ns.Print(("Drafted %d stack(s) of %s for %s. Review and press Send."):format(attached, what, name))
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
        local name, rest = arg:match("^(%S+)%s*(.-)$")
        if not name then
            return ns.Print("Usage: /mailmats target <name> <category>, <category>... | /mailmats untarget <name>")
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
        ns.Print("/mailmats target <name> <category>, ... | untarget <name> | targets")
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
