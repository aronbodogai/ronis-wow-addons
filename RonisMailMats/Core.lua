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

-- Order professions are shown in.
ns.CRAFT_ORDER = {
    "Tailoring", "Leatherworking", "Blacksmithing", "Engineering", "Alchemy",
    "Enchanting", "Mining", "Cooking", "First Aid", "Poisons",
}

-- Skill names we remember (crafting ones get buttons, gathering ones are
-- only shown next to the character's name).
local KNOWN_SKILLS = {}
for _, p in ipairs(ns.CRAFT_ORDER) do KNOWN_SKILLS[p] = true end
for _, p in ipairs({ "Herbalism", "Skinning", "Fishing" }) do KNOWN_SKILLS[p] = true end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
local function InitDB()
    RonisMailMatsDB = RonisMailMatsDB or {}
    local db = RonisMailMatsDB
    db.chars = db.chars or {}    -- [realm][name] = { class, faction, level, profs = {[name]=rank} }
    db.ignore = db.ignore or {}  -- [itemID] = true: never put in a draft
    if db.keepOwn == nil then db.keepOwn = true end
    ns.db = db
    ns.realm = GetRealmName()
    ns.me = UnitName("player")
    ns.faction = UnitFactionGroup("player")
    db.chars[ns.realm] = db.chars[ns.realm] or {}
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
-- Profession scan (Classic skill lines)
---------------------------------------------------------------------------
local function ScanSkills()
    if not GetNumSkillLines then return end
    -- expand collapsed headers so every skill line is listed
    for i = GetNumSkillLines(), 1, -1 do
        local _, isHeader, isExpanded = GetSkillLineInfo(i)
        if isHeader and not isExpanded and ExpandSkillHeader then ExpandSkillHeader(i) end
    end
    local n = GetNumSkillLines()
    if n == 0 then return end -- not loaded yet; keep what we had

    local profs = {}
    for i = 1, n do
        local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        if not isHeader and name and KNOWN_SKILLS[name] then
            profs[name] = { rank = rank, max = maxRank }
        end
    end

    local _, class = UnitClass("player")
    ns.db.chars[ns.realm][ns.me] = {
        class = class,
        faction = ns.faction,
        level = UnitLevel("player"),
        profs = profs,
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
function ns.StacksFor(prof)
    local set = ns.IS_REAGENT[prof]
    local stacks, totals, ids = {}, {}, {}
    if not set then return stacks, totals, ids end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id = GetContainerItemID(bag, slot)
            if id and set[id] and not ns.HoldReason(id) then
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
    local stacks = ns.StacksFor(prof)
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
    SendMailNameEditBox:SetText(name)
    SendMailSubjectEditBox:SetText(prof .. " mats")
    local left = #stacks - attached - skipped
    if left > 0 then
        ns.Print(("Drafted %d stacks of %s mats for %s. %d more stack(s) left - press the button again after sending.")
            :format(attached, prof, name, left))
    else
        ns.Print(("Drafted %d stack(s) of %s mats for %s. Review and press Send."):format(attached, prof, name))
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
        C_Timer.After(2, ScanSkills) -- skill lines can be empty right at login
        if ns.InitUI then ns.InitUI() end
    elseif ns.db then
        ScanSkills()
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
        ns.Print("/mailmats forget <name> | ignore <item> | unignore <item> | ignored")
    end
end
