-- Roni's ItemPedia - the window. Layout follows Factoriopedia: a browse list on
-- the left, the inspected item on the right split into sections, clickable
-- icons everywhere and back/forward history. Skinned with WoW fonts/borders.
local ADDON, ns = ...

local WHITE    = "Interface\\Buttons\\WHITE8X8"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local FW, FH   = 780, 520
local PAD      = 10
local LW       = 252                 -- left panel width
local RW       = FW - LW - PAD * 2 - 8  -- right panel width
local CW       = RW - 32             -- detail content width
local SEARCH_LIMIT = 100               -- most search results shown from all items
local COLS     = 5                   -- left grid columns
local CELL     = 42                  -- left grid cell (slot 38 + gap)
local TABS     = { "Bags", "Quests", "Recent" }

local UI = { stack = {}, pos = 0, sections = {}, nsec = 0, listSlots = {} }
ns.UI = UI

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Flat(f, bg, edge)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    f:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
end

local function QualityColor(q)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

---------------------------------------------------------------------------
-- Item slot (the square icon button used everywhere)
---------------------------------------------------------------------------
local function Slot_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.link or self.tipLink then
        GameTooltip:SetHyperlink(self.link or self.tipLink)
    elseif self.label then
        GameTooltip:SetText(self.label, 1, 1, 1)
    end
    if self.extra then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(self.extra, 1, 0.82, 0, true)
    end
    GameTooltip:Show()
end

local function Slot_OnClick(self, button)
    if not self.link then return end
    if IsModifiedClick("CHATLINK") then
        local _, full = ns.GetItemInfo(self.link)
        if full then ChatEdit_InsertLink(full) end
    elseif button == "LeftButton" and self.navigable then
        ns.Open(self.link)
    end
end

function ns.CreateSlot(parent, size)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(size, size)
    Flat(b, { 0.05, 0.05, 0.05 }, { 0.3, 0.3, 0.3 })
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 2, -2)
    hl:SetPoint("BOTTOMRIGHT", -2, 2)
    hl:SetColorTexture(1, 1, 1, 0.18)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", Slot_OnEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnClick", Slot_OnClick)
    b.navigable = true
    return b
end

local function SetBorder(b, q, selected)
    if selected then
        b:SetBackdropBorderColor(1, 0.82, 0, 1)
    elseif q and q >= 2 then
        local r, g, bl = QualityColor(q)
        b:SetBackdropBorderColor(r, g, bl, 0.9)
    else
        b:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end
end

function ns.SetSlot(b, link, count, extra, selected)
    b.link, b.tipLink, b.label, b.extra = link, nil, nil, extra
    b.icon:SetTexture(ns.GetItemIcon(ns.ItemID(link)) or QUESTION)
    local q = select(3, ns.GetItemInfo(link))
    if q == nil and ns.ItemMeta then q = select(2, ns.ItemMeta(ns.ItemID(link))) end
    SetBorder(b, q, selected)
    b.count:SetText((count and count ~= 1) and count or "")
    b:Show()
end

-- For spells that create no item (enchants): spell tooltip, not navigable
function ns.SetSlotSpell(b, spellID, extra)
    local name, icon = ns.SpellInfo(spellID)
    b.link, b.tipLink, b.label, b.extra = nil, "spell:" .. spellID, name, extra
    b.icon:SetTexture(icon or QUESTION)
    SetBorder(b, nil)
    b.count:SetText("")
    b:Show()
end

---------------------------------------------------------------------------
-- Detail sections (pooled panels with their own pooled children)
---------------------------------------------------------------------------
local Section = {}

function Section:Reset()
    for _, t in ipairs(self.texts) do t:Hide() end
    for _, s in ipairs(self.slots) do s:Hide() end
    for _, x in ipairs(self.texs) do x:Hide() end
    for _, b in ipairs(self.btns) do b:Hide() end
    self.nt, self.ns, self.nx, self.nb = 0, 0, 0, 0
end

local function MapButton_OnEnter(self)
    local row = self.row
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Show on map", 1, 1, 1)
    if row.x then
        GameTooltip:AddLine(string.format("Nearest: %s (%.1f, %.1f)", row.zone or "?", row.x, row.y), 0.8, 0.8, 0.8)
    end
    if row.quest then
        GameTooltip:AddLine("Quest giver: " .. (row.pinName or "?"), 1, 0.82, 0)
    end
    GameTooltip:AddLine("Questie pins every spawn of " .. (row.pinName or row.name) .. ".", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

-- Small map-icon button used on NPC/object rows
function Section:MapButton(row)
    self.nb = self.nb + 1
    local b = self.btns[self.nb]
    if not b then
        b = CreateFrame("Button", nil, self)
        b:SetSize(18, 18)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.25)
        b:SetScript("OnEnter", MapButton_OnEnter)
        b:SetScript("OnLeave", GameTooltip_Hide)
        b:SetScript("OnClick", function(btn) ns.ShowOnMap(btn.row) end)
        self.btns[self.nb] = b
    end
    b.row = row
    b:ClearAllPoints()
    b:Show()
    return b
end

function Section:Text(font, r, g, b)
    self.nt = self.nt + 1
    local fs = self.texts[self.nt]
    if not fs then
        fs = self:CreateFontString(nil, "OVERLAY")
        self.texts[self.nt] = fs
    end
    fs:SetFontObject(font or "GameFontHighlightSmall")
    fs:SetTextColor(r or 1, g or 1, b or 1)
    fs:ClearAllPoints()
    fs:SetWidth(0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:Show()
    return fs
end

function Section:Slot(size)
    self.ns = self.ns + 1
    local s = self.slots[self.ns]
    if not s then
        s = ns.CreateSlot(self, size)
        self.slots[self.ns] = s
    end
    s:SetSize(size, size)
    s:ClearAllPoints()
    s.navigable = true
    return s
end

function Section:Tex()
    self.nx = self.nx + 1
    local t = self.texs[self.nx]
    if not t then
        t = self:CreateTexture(nil, "ARTWORK")
        self.texs[self.nx] = t
    end
    t:ClearAllPoints()
    t:Show()
    return t
end

local function NewSection(parent)
    local s = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Flat(s, { 0.13, 0.13, 0.13 }, { 0, 0, 0 })
    s.title = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    s.title:SetPoint("TOPLEFT", 8, -7)
    s.rule = s:CreateTexture(nil, "ARTWORK")
    s.rule:SetColorTexture(1, 0.82, 0, 0.25)
    s.rule:SetHeight(1)
    s.rule:SetPoint("TOPLEFT", 6, -24)
    s.rule:SetPoint("TOPRIGHT", -6, -24)
    s.texts, s.slots, s.texs, s.btns = {}, {}, {}, {}
    for k, v in pairs(Section) do s[k] = v end
    return s
end

function UI:AcquireSection(title, y)
    self.nsec = self.nsec + 1
    local s = self.sections[self.nsec]
    if not s then
        s = NewSection(self.content)
        self.sections[self.nsec] = s
    end
    s:Reset()
    s.title:SetText(title)
    s:ClearAllPoints()
    s:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
    s:SetWidth(CW)
    s:Show()
    return s
end

function UI:ReleaseSections()
    for _, s in ipairs(self.sections) do s:Hide() end
    self.nsec = 0
end

local SECTION_TOP = 32
local SECTION_GAP = 8

local function Finish(s, cy, y)
    s:SetHeight(cy + 6)
    return y + cy + 6 + SECTION_GAP
end

---------------------------------------------------------------------------
-- Section builders
---------------------------------------------------------------------------
local ARROW = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"

local function MadeText(r)
    if r.max > r.min then return r.min .. "-" .. r.max end
    return r.min
end

local function DistanceText(yards)
    if yards < 1000 then return string.format("%d yd", yards) end
    return string.format("%.1fk yd", yards / 1000)
end

local function ChanceText(c)
    if c >= 10 then return string.format("%.0f%%", c) end
    if c >= 1 then return string.format("%.1f%%", c) end
    return string.format("%.2f%%", c)
end

-- Skill colours like the profession window: orange (learn), yellow, green, grey.
local function SkillText(r)
    local parts = {}
    if r.learn then parts[#parts + 1] = "|cffff8040" .. r.learn .. "|r" end
    if r.yellow then parts[#parts + 1] = "|cffffff00" .. r.yellow .. "|r" end
    if r.yellow and r.grey then parts[#parts + 1] = "|cff40c040" .. math.floor((r.yellow + r.grey) / 2) .. "|r" end
    if r.grey then parts[#parts + 1] = "|cff808080" .. r.grey .. "|r" end
    if #parts == 0 then return nil end
    return "Skill  " .. table.concat(parts, "  ")
end

local KnowsSpell = IsPlayerSpell or IsSpellKnown

-- Draws "Profession - Recipe" and "reagents -> product" at cy; returns new cy.
local function DrawRecipe(s, r, cy, currentID)
    local lbl = s:Text("GameFontHighlightSmall", 0.75, 0.75, 0.75)
    lbl:SetPoint("TOPLEFT", 10, -cy)
    local title = "|cffffd100" .. r.prof .. "|r  -  " .. (ns.SpellInfo(r.spell) or ("Spell " .. r.spell))
    if KnowsSpell then
        local ok, known = pcall(KnowsSpell, r.spell)
        if ok and known then title = title .. "  |cff40ff40(known)|r" end
    end
    lbl:SetText(title)
    local skill = SkillText(r)
    if skill then
        local st = s:Text("GameFontHighlightSmall", 0.6, 0.6, 0.6)
        st:SetPoint("TOPRIGHT", -10, -cy)
        st:SetJustifyH("RIGHT")
        st:SetText(skill)
    end
    cy = cy + 16
    local x = 10
    for _, rg in ipairs(r.reagents) do
        if x > CW - 90 then x = 10; cy = cy + 40 end
        local b = s:Slot(36)
        b:SetPoint("TOPLEFT", x, -cy)
        ns.SetSlot(b, "item:" .. rg[1], rg[2], nil, rg[1] == currentID)
        x = x + 40
    end
    local arrow = s:Tex()
    arrow:SetTexture(ARROW)
    arrow:SetSize(28, 28)
    arrow:SetPoint("TOPLEFT", x, -cy - 4)
    x = x + 32
    local p = s:Slot(36)
    p:SetPoint("TOPLEFT", x, -cy)
    if r.product then
        ns.SetSlot(p, "item:" .. r.product, MadeText(r), nil, r.product == currentID)
    else
        ns.SetSlotSpell(p, r.spell, r.prof)
    end
    return cy + 44
end

function UI:SectionCreatedBy(id, y)
    local list = ns.madeBy[id]
    if not list then return y end
    local s = self:AcquireSection("Created by (" .. #list .. ")", y)
    local cy = SECTION_TOP
    for _, idx in ipairs(list) do
        local r = ns.Recipe(idx)
        cy = DrawRecipe(s, r, cy, id)
        cy = self:DrawLearn(s, r, cy - 4) + 4
    end
    return Finish(s, cy - 4, y)
end

-- Recipe items (patterns, plans, formulas...) show the recipe they teach.
function UI:SectionTeaches(src, id, y)
    local idx = src.teaches and ns.bySpell[src.teaches]
    if not idx then return y end
    local s = self:AcquireSection("Teaches", y)
    return Finish(s, DrawRecipe(s, ns.Recipe(idx), SECTION_TOP, id) - 4, y)
end

function UI:SectionUsedIn(id, y)
    local list = ns.usedIn[id]
    if not list then return y end
    local s = self:AcquireSection("Used in (" .. #list .. ")", y)
    local groups, order = {}, {}
    for _, idx in ipairs(list) do
        local r = ns.Recipe(idx)
        if not groups[r.prof] then
            groups[r.prof] = {}
            order[#order + 1] = r.prof
        end
        table.insert(groups[r.prof], r)
    end
    table.sort(order)
    local itemName = ns.GetItemInfo(id) or "this item"
    local cy = SECTION_TOP
    for _, prof in ipairs(order) do
        local lbl = s:Text("GameFontNormalSmall", 1, 0.82, 0)
        lbl:SetPoint("TOPLEFT", 10, -cy)
        lbl:SetText(prof .. " (" .. #groups[prof] .. ")")
        cy = cy + 16
        local x = 10
        for _, r in ipairs(groups[prof]) do
            if x > CW - 46 then x = 10; cy = cy + 40 end
            local need = 1
            for _, rg in ipairs(r.reagents) do
                if rg[1] == id then need = rg[2] end
            end
            local extra = r.prof .. " - needs " .. need .. "x " .. itemName
            local b = s:Slot(36)
            b:SetPoint("TOPLEFT", x, -cy)
            if r.product then
                ns.SetSlot(b, "item:" .. r.product, MadeText(r), extra)
            else
                ns.SetSlotSpell(b, r.spell, extra)
            end
            x = x + 40
        end
        cy = cy + 44
    end
    return Finish(s, cy - 4, y)
end

-- Class spells that use the item as a reagent, one row per spell name
-- (ranks of the same spell are merged).
local function ClassText(classes)
    local out = {}
    for cls in classes:gmatch("[^,]+") do
        local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls])
            or (cls:sub(1, 1) .. cls:sub(2):lower())
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
        out[#out + 1] = c and string.format("|cff%02x%02x%02x%s|r", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5), name) or name
    end
    return table.concat(out, ", ")
end

function UI:SectionReagentFor(id, y)
    local list = ns.reagentFor and ns.reagentFor[id]
    if not list then return y end
    local rows, byName = {}, {}
    for _, e in ipairs(list) do
        local name = ns.SpellInfo(e.spell) or ("Spell " .. e.spell)
        local row = byName[name]
        if not row then
            row = { name = name, spell = e.spell, classes = e.classes, min = e.count, max = e.count, ranks = 0 }
            byName[name] = row
            rows[#rows + 1] = row
        end
        row.ranks = row.ranks + 1
        row.min, row.max = math.min(row.min, e.count), math.max(row.max, e.count)
    end
    table.sort(rows, function(a, b)
        if a.classes ~= b.classes then return a.classes < b.classes end
        return a.name < b.name
    end)
    local s = self:AcquireSection("Reagent for spells (" .. #rows .. ")", y)
    local cy = SECTION_TOP
    for _, r in ipairs(rows) do
        local need = r.min == r.max and r.min or (r.min .. "-" .. r.max)
        local b = s:Slot(22)
        b:SetPoint("TOPLEFT", 10, -cy)
        ns.SetSlotSpell(b, r.spell, "needs " .. need)
        local t = s:Text("GameFontHighlight")
        t:SetPoint("LEFT", b, "RIGHT", 8, 0)
        t:SetText("|cffffd100" .. r.name .. "|r  |cff8c8c8c" .. need .. "x  -|r  " .. ClassText(r.classes)
            .. (r.ranks > 1 and ("  |cff8c8c8call " .. r.ranks .. " ranks|r") or ""))
        cy = cy + 26
    end
    return Finish(s, cy, y)
end

local RANK_COLOR = { Boss = "|cffff6040", Elite = "|cffffd100", ["Rare Elite"] = "|cffc0c0ff", Rare = "|cffc0c0ff" }

local function NpcText(row)
    local t = (RANK_COLOR[row.rank] or "|cffffffff") .. row.name .. "|r"
    local meta = {}
    if row.rank then meta[#meta + 1] = row.rank end
    if row.level then meta[#meta + 1] = "Lv " .. row.level end
    if row.zone then meta[#meta + 1] = row.zone end
    if #meta > 0 then t = t .. "  |cff8c8c8c" .. table.concat(meta, "  -  ") .. "|r" end
    return t
end

local function ObjectText(row)
    return row.name .. (row.zone and ("  |cff8c8c8c" .. row.zone .. "|r") or "")
end

-- "[24] Quest name  req 20 - Zone - Giver", greyed out when already done
local function QuestReqText(row)
    local lvl = (type(row.level) == "number" and row.level > 0) and ("[" .. row.level .. "] ") or ""
    local meta = {}
    if type(row.reqLevel) == "number" and row.reqLevel > 0 then meta[#meta + 1] = "req " .. row.reqLevel end
    if row.zone then meta[#meta + 1] = row.zone end
    if row.pinName then meta[#meta + 1] = row.pinName end
    local tail = #meta > 0 and ("  |cff8c8c8c" .. table.concat(meta, "  -  ") .. "|r") or ""
    if row.done then
        return "|cff7f7f7f" .. lvl .. row.name .. " (done)|r" .. tail
    end
    return "|cff8c8c8c" .. lvl .. "|r|cffffd100" .. row.name .. "|r" .. tail
end

function UI:SectionQuestsScanning(src, y)
    if not src.questsScanning then return y end
    local s = self:AcquireSection("Required for quests", y)
    local t = s:Text("GameFontDisableSmall")
    t:SetPoint("TOPLEFT", 10, -SECTION_TOP)
    t:SetText("Scanning the quest database...")
    return Finish(s, SECTION_TOP + 16, y)
end

-- One text row with optional chance/distance and a map button on the right.
local function DrawRow(s, text, row, cy, left)
    left = left or 10
    local l = s:Text("GameFontHighlightSmall")
    l:SetPoint("TOPLEFT", left, -cy - 2)
    l:SetWidth(CW - 140 - left)
    l:SetWordWrap(false)
    l:SetText(text)

    local right = 10
    if row and row.kind and ns.CanShowOnMap(row) then
        local b = s:MapButton(row)
        b:SetPoint("TOPRIGHT", -8, -cy)
        right = 32
    end
    local parts = {}
    if row and row.chance then parts[#parts + 1] = "|cffffd100" .. ChanceText(row.chance) .. "|r" end
    if row and row.dist then parts[#parts + 1] = "|cff8c8c8c" .. DistanceText(row.dist) .. "|r" end
    if #parts > 0 then
        local r = s:Text("GameFontHighlightSmall")
        r:SetPoint("TOPRIGHT", -right, -cy - 2)
        r:SetJustifyH("RIGHT")
        r:SetText(table.concat(parts, "   "))
    end
end

function UI:SectionRows(title, rows, total, fmt, y)
    if #rows == 0 then return y end
    total = total or #rows
    local s = self:AcquireSection(title .. " (" .. total .. ")", y)
    local cy = SECTION_TOP
    local anyChance = false
    for _, row in ipairs(rows) do
        if row.chance then anyChance = true end
        DrawRow(s, fmt(row), row, cy)
        cy = cy + 20
    end
    if total > #rows then
        local more = s:Text("GameFontDisableSmall")
        more:SetPoint("TOPLEFT", 10, -cy)
        more:SetText("...and " .. (total - #rows) .. " more")
        cy = cy + 16
    end
    if anyChance then
        local note = s:Text("GameFontDisableSmall")
        note:SetPoint("TOPRIGHT", -10, -cy - 2)
        note:SetText("drop chance from Questie (Wowhead data)")
        cy = cy + 16
    end
    return Finish(s, cy, y)
end

-- "Learn from" lines under a recipe: recipe items (with their nearest vendor),
-- or the nearest profession trainers.
function UI:DrawLearn(s, r, cy)
    local ok, src = pcall(ns.LearnSources, r)
    if not ok or type(src) ~= "table" then return cy end
    local head = s:Text("GameFontDisableSmall")
    head:SetPoint("TOPLEFT", 10, -cy)
    if src.auto then
        head:SetText("Learned automatically with " .. r.prof .. ".")
        return cy + 18
    end
    head:SetText("Learn from")
    cy = cy + 14
    for _, e in ipairs(src.items) do
        local b = s:Slot(22)
        b:SetPoint("TOPLEFT", 10, -cy)
        ns.SetSlot(b, "item:" .. e.id)
        local name, _, q = ns.GetItemInfo(e.id)
        if not name then self.waitNames[e.id] = true end
        local hex = GetItemQualityColor and select(4, GetItemQualityColor(q or 1)) or "ffffffff"
        local text = "|c" .. hex .. (name or ("Item " .. e.id)) .. "|r"
        local row
        if e.vendor then
            row = e.vendor
            text = text .. "  |cff8c8c8c-|r  Sold by " .. NpcText(row)
            if e.vendorsTotal > 1 then text = text .. "  |cff8c8c8c(+" .. (e.vendorsTotal - 1) .. " more)|r" end
        elseif e.dropsTotal > 0 then
            text = text .. "  |cff8c8c8c-  drops from " .. e.dropsTotal .. (e.dropsTotal == 1 and " source" or " sources") .. "|r"
        elseif e.quest then
            row = e.quest
            text = text .. "  |cff8c8c8c-|r  Quest reward: " .. QuestReqText(row)
            if e.questsTotal > 1 then text = text .. "  |cff8c8c8c(+" .. (e.questsTotal - 1) .. " more)|r" end
        end
        DrawRow(s, text, row, cy + 2, 38)
        cy = cy + 26
    end
    if src.trainer then
        if #src.trainers == 0 then
            local t = s:Text("GameFontHighlightSmall", 0.75, 0.75, 0.75)
            t:SetPoint("TOPLEFT", 10, -cy - 2)
            t:SetText(r.prof .. " trainer" .. (src.trainersScanning and "  |cff8c8c8c(finding trainers...)|r" or ""))
            cy = cy + 20
        end
        for _, row in ipairs(src.trainers) do
            local text = "|cffffffff" .. row.name .. "|r"
            if row.title then text = text .. "  |cffffd100<" .. row.title .. ">|r" end
            if row.zone then text = text .. "  |cff8c8c8c" .. row.zone .. "|r" end
            DrawRow(s, text, row, cy)
            cy = cy + 20
        end
        if (src.trainersTotal or 0) > #src.trainers then
            local more = s:Text("GameFontDisableSmall")
            more:SetPoint("TOPLEFT", 10, -cy)
            more:SetText("...and " .. (src.trainersTotal - #src.trainers) .. " more trainers")
            cy = cy + 16
        end
    end
    return cy + 4
end

function UI:SectionContainers(src, y)
    if #src.containers == 0 then return y end
    local s = self:AcquireSection("Contained in (" .. #src.containers .. ")", y)
    local cy, x = SECTION_TOP, 10
    for _, cid in ipairs(src.containers) do
        if x > CW - 46 then x = 10; cy = cy + 40 end
        local b = s:Slot(36)
        b:SetPoint("TOPLEFT", x, -cy)
        ns.SetSlot(b, "item:" .. cid)
        x = x + 40
    end
    return Finish(s, cy + 40, y)
end

local BIND = {
    [1] = ITEM_BIND_ON_PICKUP or "Binds when picked up",
    [2] = ITEM_BIND_ON_EQUIP or "Binds when equipped",
    [3] = ITEM_BIND_ON_USE or "Binds when used",
    [4] = ITEM_BIND_QUEST or "Quest Item",
}

local function AuctionPrice(link)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemLink) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemLink, ADDON, link)
    if ok and type(price) == "number" and price > 0 then return price end
end

function UI:SectionProperties(link, id, info, y)
    local _, _, q, ilvl, req, itype, isub, stack, equip, _, sell, _, _, bind = unpack(info)
    local rows = {}
    local function row(k, v, r, g, b)
        if v ~= nil and v ~= "" then rows[#rows + 1] = { k, tostring(v), r, g, b } end
    end

    if q then
        local r, g, b = QualityColor(q)
        row("Quality", _G["ITEM_QUALITY" .. q .. "_DESC"] or q, r, g, b)
    end
    if itype then row("Type", (isub and isub ~= itype) and (itype .. " / " .. isub) or itype) end
    if equip and equip ~= "" then row("Slot", _G[equip] or equip) end
    if ilvl and ilvl > 0 then row("Item level", ilvl) end
    if req and req > 0 then row("Requires level", req) end
    if stack then row("Stack size", stack) end
    if bind and BIND[bind] then row("Binding", BIND[bind]) end
    row("Vendor price", (sell and sell > 0) and GetCoinTextureString(sell) or "Cannot be sold to vendors")
    local ah = AuctionPrice(link)
    if ah then row("Auction (Auctionator)", GetCoinTextureString(ah)) end
    local bags, total = ns.GetItemCount(id) or 0, ns.GetItemCount(id, true) or 0
    row("You own", total > bags and (bags .. " in bags, " .. total .. " incl. bank") or bags)
    row("Item ID", id, 0.6, 0.6, 0.6)

    local s = self:AcquireSection("Properties", y)
    local cy = SECTION_TOP
    for _, rw in ipairs(rows) do
        local k = s:Text("GameFontHighlightSmall", 0.6, 0.6, 0.6)
        k:SetPoint("TOPLEFT", 10, -cy)
        k:SetText(rw[1])
        local v = s:Text("GameFontHighlightSmall", rw[3] or 1, rw[4] or 1, rw[5] or 1)
        v:SetPoint("TOPLEFT", 150, -cy)
        v:SetWidth(CW - 160)
        v:SetText(rw[2])
        cy = cy + math.max(16, v:GetStringHeight() + 4)
    end
    if not ns.HasQuestieDB() then
        local hint = s:Text("GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", 10, -cy - 4)
        hint:SetWidth(CW - 20)
        hint:SetJustifyH("LEFT")
        hint:SetText("Enable QuestieDB (installed with Questie) to see drops, vendors and quests.")
        cy = cy + 20
    end
    return Finish(s, cy, y)
end

local scanTip = CreateFrame("GameTooltip", "RonisItemPediaScanTip", UIParent, "GameTooltipTemplate")

local function ScanTooltip(link)
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetHyperlink(link)
    local out = {}
    for i = 2, scanTip:NumLines() do
        local L = _G["RonisItemPediaScanTipTextLeft" .. i]
        local R = _G["RonisItemPediaScanTipTextRight" .. i]
        local lt = L and L:GetText()
        local rt = R and R:IsShown() and R:GetText()
        if rt == "" then rt = nil end
        if (lt and lt ~= "") or rt then
            out[#out + 1] = {
                text = lt or "", r = { L:GetTextColor() },
                right = rt, rr = rt and { R:GetTextColor() },
            }
        end
    end
    scanTip:Hide()
    return out
end

function UI:SectionTooltip(link, y)
    local lines = ScanTooltip(link)
    if #lines == 0 then return y end
    local s = self:AcquireSection("Description", y)
    local cy = SECTION_TOP
    for _, ln in ipairs(lines) do
        local l = s:Text("GameFontHighlightSmall", ln.r[1], ln.r[2], ln.r[3])
        l:SetPoint("TOPLEFT", 10, -cy)
        l:SetWidth(ln.right and (CW - 130) or (CW - 20))
        l:SetText(ln.text)
        if ln.right then
            local r = s:Text("GameFontHighlightSmall", ln.rr[1], ln.rr[2], ln.rr[3])
            r:SetPoint("TOPRIGHT", -10, -cy)
            r:SetJustifyH("RIGHT")
            r:SetText(ln.right)
        end
        cy = cy + math.max(14, l:GetStringHeight() + 3)
    end
    return Finish(s, cy, y)
end

---------------------------------------------------------------------------
-- Window construction
---------------------------------------------------------------------------
local function NavButton(parent, kind)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(26, 26)
    local base = "Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-"
    b:SetNormalTexture(base .. "Up")
    b:SetPushedTexture(base .. "Down")
    b:SetDisabledTexture(base .. "Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    return b
end

local function MakeTab(parent, name, i)
    local w = (LW - 16 - 8) / #TABS
    local t = CreateFrame("Button", nil, parent, "BackdropTemplate")
    t:SetSize(w, 20)
    t:SetPoint("TOPLEFT", 8 + (i - 1) * (w + 4), -36)
    Flat(t, { 0.1, 0.1, 0.1 }, { 0, 0, 0 })
    t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.text:SetPoint("CENTER")
    t.text:SetText(name)
    t.tabName = name
    t:SetScript("OnClick", function()
        ns.db.tab = name
        UI:RefreshList()
    end)
    return t
end

function UI:Create()
    if self.frame then return end

    local f = CreateFrame("Frame", "RonisItemPediaFrame", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(FW, FH)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetBackdrop({
        bgFile = WHITE,
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    local pos = ns.db.pos
    if pos then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("CENTER") end
    f:Hide()
    tinsert(UISpecialFrames, "RonisItemPediaFrame") -- Escape closes it
    f:SetScript("OnMouseUp", function(_, button)
        if button == "Button4" then UI:Back() elseif button == "Button5" then UI:Forward() end
    end)
    f:SetScript("OnHide", function() GameTooltip:Hide() end)

    -- Title bar (drag handle) -------------------------------------------------
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 6, -6)
    bar:SetPoint("TOPRIGHT", -6, -6)
    bar:SetHeight(24)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local p, _, _, x, y = f:GetPoint()
        ns.db.pos = { p, x, y }
    end)

    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 6, 0)
    title:SetText(ns.TITLE)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -1, -1)

    self.fwd = NavButton(f, "Next")
    self.fwd:SetPoint("RIGHT", close, "LEFT", -2, 0)
    self.fwd:SetScript("OnClick", function() UI:Forward() end)
    self.back = NavButton(f, "Prev")
    self.back:SetPoint("RIGHT", self.fwd, "LEFT", 0, 0)
    self.back:SetScript("OnClick", function() UI:Back() end)

    -- Factorio-style grooved drag filler between the title and the buttons
    for i, off in ipairs({ -3, 3 }) do
        local g = bar:CreateTexture(nil, "ARTWORK")
        g:SetColorTexture(i == 1 and 0.28 or 0.02, i == 1 and 0.28 or 0.02, i == 1 and 0.28 or 0.02, 1)
        g:SetHeight(2)
        g:SetPoint("LEFT", title, "RIGHT", 12, off)
        g:SetPoint("RIGHT", self.back, "LEFT", -8, off)
        local g2 = bar:CreateTexture(nil, "ARTWORK")
        g2:SetColorTexture(0.02, 0.02, 0.02, 1)
        g2:SetHeight(1)
        g2:SetPoint("TOPLEFT", g, "BOTTOMLEFT")
        g2:SetPoint("TOPRIGHT", g, "BOTTOMRIGHT")
    end

    -- Left panel: search, tabs, item grid ----------------------------------
    local left = CreateFrame("Frame", nil, f, "BackdropTemplate")
    left:SetPoint("TOPLEFT", PAD, -34)
    left:SetPoint("BOTTOMLEFT", PAD, PAD)
    left:SetWidth(LW)
    Flat(left, { 0.03, 0.03, 0.03, 0.9 }, { 0, 0, 0 })

    local search = CreateFrame("EditBox", "RonisItemPediaSearch", left, "InputBoxTemplate")
    search:SetPoint("TOPLEFT", 14, -8)
    search:SetSize(LW - 24, 20)
    search:SetAutoFocus(false)
    search.hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    search.hint:SetPoint("LEFT", 2, 0)
    search.hint:SetText("Search any item: name or ID...")
    search:SetScript("OnTextChanged", function(eb)
        eb.hint:SetShown(eb:GetText() == "" and not eb:HasFocus())
        UI:RefreshList()
    end)
    search:SetScript("OnEditFocusGained", function(eb) eb.hint:Hide() end)
    search:SetScript("OnEditFocusLost", function(eb) eb.hint:SetShown(eb:GetText() == "") end)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    search:SetScript("OnEnterPressed", function(eb)
        local txt = strtrim(eb:GetText())
        eb:ClearFocus()
        if tonumber(txt) then
            ns.Open("item:" .. tonumber(txt))
        elseif UI.firstResult then
            ns.Open(UI.firstResult)
        elseif txt ~= "" then
            local link = ns.Normalize(txt)
            if link then ns.Open(link) end
        end
    end)
    self.search = search

    self.tabs = {}
    local validTab = false
    for i, name in ipairs(TABS) do
        self.tabs[i] = MakeTab(left, name, i)
        if name == ns.db.tab then validTab = true end
    end
    if not validTab then ns.db.tab = TABS[1] end

    local ls = CreateFrame("ScrollFrame", "RonisItemPediaListScroll", left, "UIPanelScrollFrameTemplate")
    ls:SetPoint("TOPLEFT", 6, -62)
    ls:SetPoint("BOTTOMRIGHT", -26, 6)
    local lc = CreateFrame("Frame", nil, ls)
    lc:SetSize(LW - 32, 1)
    ls:SetScrollChild(lc)
    self.listChild = lc
    self.listEmpty = lc:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.listEmpty:SetPoint("TOP", 0, -20)
    self.listEmpty:SetWidth(LW - 50)
    self.listMore = lc:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.listMore:SetWidth(LW - 50)

    -- Right panel: header + scrolling sections -------------------------------
    local right = CreateFrame("Frame", nil, f, "BackdropTemplate")
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    Flat(right, { 0.03, 0.03, 0.03, 0.9 }, { 0, 0, 0 })

    local hdr = ns.CreateSlot(right, 48)
    hdr:SetPoint("TOPLEFT", 8, -8)
    hdr.navigable = false
    self.hdrSlot = hdr
    self.hdrName = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.hdrName:SetPoint("TOPLEFT", hdr, "TOPRIGHT", 10, -4)
    self.hdrName:SetPoint("RIGHT", right, "RIGHT", -10, 0)
    self.hdrName:SetJustifyH("LEFT")
    self.hdrName:SetWordWrap(false)
    self.hdrSub = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.hdrSub:SetPoint("TOPLEFT", self.hdrName, "BOTTOMLEFT", 0, -6)
    self.hdrSub:SetTextColor(0.7, 0.7, 0.7)
    local rule = right:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 0.82, 0, 0.3)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 6, -64)
    rule:SetPoint("TOPRIGHT", -6, -64)

    self.empty = right:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.empty:SetPoint("CENTER", 0, 20)
    self.empty:SetText("Alt + Left-Click any item\nto inspect it here.")

    local sf = CreateFrame("ScrollFrame", "RonisItemPediaDetailScroll", right, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -70)
    sf:SetPoint("BOTTOMRIGHT", -26, 6)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(CW, 1)
    sf:SetScrollChild(content)
    self.scroll, self.content = sf, content
end

---------------------------------------------------------------------------
-- Left list
---------------------------------------------------------------------------
local function SortByQualityName(list)
    local meta = {}
    for _, l in ipairs(list) do
        local n, _, q = ns.GetItemInfo(l)
        meta[l] = { q or -1, n or "~" }
    end
    table.sort(list, function(a, b)
        local A, B = meta[a], meta[b]
        if A[1] ~= B[1] then return A[1] > B[1] end
        return A[2] < B[2]
    end)
end

function UI:GatherList()
    local tab, list, seen = ns.db.tab, {}, {}
    self.listExtra = {}
    local function add(link, extra)
        local id = ns.ItemID(link)
        if id and not seen[id] then
            seen[id] = true
            list[#list + 1] = link
            self.listExtra[link] = extra
        end
    end
    if tab == "Bags" then
        for bag = 0, NUM_BAG_SLOTS or 4 do
            for slot = 1, ns.GetContainerNumSlots(bag) or 0 do
                add(ns.GetContainerItemLink(bag, slot))
            end
        end
        SortByQualityName(list)
    elseif tab == "Quests" then
        -- items your current quests ask for that you could buy or be sent
        for _, e in ipairs(ns.QuestLogItems and ns.QuestLogItems() or {}) do
            if ns.IsTradable(e.id) then
                add("item:" .. e.id, "Needed for: " .. table.concat(e.quests, ", "))
            end
        end
    elseif tab == "Recent" then
        for _, l in ipairs(ns.db.history) do add(l) end
    end

    -- Search: matches in this tab first, then every other item in the game.
    self.searchMore = nil
    local query = strtrim(self.search:GetText() or ""):lower()
    if query ~= "" then
        local filtered = {}
        local num = tonumber(query)
        for _, l in ipairs(list) do
            local id = ns.ItemID(l)
            local n = ns.GetItemInfo(l) or (ns.ItemMeta and ns.ItemMeta(id))
            if (num and id == num) or (not num and n and n:lower():find(query, 1, true)) then
                filtered[#filtered + 1] = l
            end
        end
        list, seen = {}, {}
        for _, l in ipairs(filtered) do add(l, self.listExtra[l]) end
        if num then
            if ns.ItemMeta(num) or ns.GetItemInfo(num) then add("item:" .. num) end
        elseif ns.SearchItems then
            local ids, total = ns.SearchItems(query, SEARCH_LIMIT)
            for _, id in ipairs(ids) do add("item:" .. id) end
            if total and total > #ids then self.searchMore = total - #ids end
        end
    end
    return list
end

local EMPTY_TEXT = {
    Bags = "Your bags are empty.",
    Quests = "No tradable items needed by the quests in your quest log.",
    Recent = "Items you inspect show up here.",
}

function UI:RefreshList()
    if not (self.frame and self.frame:IsShown()) then return end
    for _, t in ipairs(self.tabs) do
        local on = t.tabName == ns.db.tab
        t:SetBackdropColor(on and 0.22 or 0.1, on and 0.22 or 0.1, on and 0.22 or 0.1, 1)
        t.text:SetTextColor(on and 1 or 0.6, on and 0.82 or 0.6, on and 0 or 0.6)
    end

    local list = self:GatherList()
    self.firstResult = list[1]
    local curID = ns.ItemID(self.stack[self.pos])
    local x0 = (LW - 32 - COLS * CELL) / 2 + 2
    for i, link in ipairs(list) do
        local b = self.listSlots[i]
        if not b then
            b = ns.CreateSlot(self.listChild, 38)
            self.listSlots[i] = b
        end
        local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x0 + col * CELL, -row * CELL)
        local id = ns.ItemID(link)
        local count = ns.db.tab == "Bags" and ns.GetItemCount(id) or nil
        ns.SetSlot(b, link, count, self.listExtra and self.listExtra[link], id == curID)
    end
    for i = #list + 1, #self.listSlots do self.listSlots[i]:Hide() end
    local rows = math.ceil(#list / COLS)
    self.listMore:ClearAllPoints()
    self.listMore:SetPoint("TOP", 0, -rows * CELL - 4)
    self.listMore:SetText(self.searchMore and ("...and " .. self.searchMore .. " more, type more letters") or "")
    self.listMore:SetShown(self.searchMore ~= nil)
    self.listChild:SetHeight(math.max(1, rows * CELL + (self.searchMore and 24 or 0)))

    local query = self.search:GetText() or ""
    self.listEmpty:SetText(query ~= "" and "No matches." or EMPTY_TEXT[ns.db.tab])
    self.listEmpty:SetShown(#list == 0)
end

---------------------------------------------------------------------------
-- Detail rendering & navigation
---------------------------------------------------------------------------
function UI:Render()
    if not self.frame then return end
    local link = self.stack[self.pos]
    self.back:SetEnabled(self.pos > 1)
    self.fwd:SetEnabled(self.pos < #self.stack)
    self:ReleaseSections()
    if link ~= self.renderedLink then
        self.scroll:SetVerticalScroll(0) -- keep scroll position on in-place refreshes
        self.renderedLink = link
    end
    self.pending = nil
    self.waitNames = {}

    if not link then
        self.hdrSlot:Hide()
        self.hdrName:SetText("")
        self.hdrSub:SetText("")
        self.empty:Show()
        self:RefreshList()
        return
    end
    self.empty:Hide()

    local id = ns.ItemID(link)
    local info = { ns.GetItemInfo(link) }
    local name, full, q = info[1], info[2], info[3]
    ns.SetSlot(self.hdrSlot, full or link)

    if not name then
        self.pending = id
        self.hdrName:SetText("Retrieving item info...")
        self.hdrName:SetTextColor(0.6, 0.6, 0.6)
        self.hdrSub:SetText("Item " .. id)
        self.content:SetHeight(1)
        self:RefreshList()
        return
    end

    self.hdrName:SetText(name)
    self.hdrName:SetTextColor(QualityColor(q))
    local sub = info[7] and info[7] ~= "" and info[7] or (info[6] or "")
    if info[9] and info[9] ~= "" and _G[info[9]] then sub = sub .. "  -  " .. _G[info[9]] end
    if info[4] and info[4] > 0 then sub = sub .. "  -  Item Level " .. info[4] end
    self.hdrSub:SetText(sub)

    local y = 0
    local ok, src = pcall(ns.GetSources, id)
    if not ok or type(src) ~= "table" then
        src = { drops = {}, objects = {}, containers = {}, vendors = {}, quests = {} }
    end
    -- One broken section must not hide the ones after it: run each in pcall
    -- and report the error once per item in chat.
    local reported = false
    local function Draw(fn, ...)
        local n = select("#", ...)
        local args = { ... }
        args[n + 1] = y
        local ok, res = pcall(fn, self, unpack(args, 1, n + 1))
        if ok and type(res) == "number" then
            y = res
        elseif not ok and not reported then
            reported = true
            print("|cffff8c1aRoni's ItemPedia|r: could not draw part of item " .. tostring(id) .. ": " .. tostring(res))
        end
    end
    Draw(self.SectionCreatedBy, id)
    Draw(self.SectionTeaches, src, id)
    Draw(self.SectionUsedIn, id)
    Draw(self.SectionReagentFor, id)
    Draw(self.SectionRows, "Required for quests", src.requiredFor or {}, src.requiredForTotal, QuestReqText)
    Draw(self.SectionQuestsScanning, src)
    Draw(self.SectionRows, "Dropped by", src.drops or {}, src.dropsTotal, NpcText)
    Draw(self.SectionContainers, src)
    Draw(self.SectionRows, "Gathered from", src.objects or {}, src.objectsTotal, ObjectText)
    Draw(self.SectionRows, "Sold by", src.vendors or {}, src.vendorsTotal, NpcText)
    Draw(self.SectionRows, "Quest reward", src.quests or {}, src.questsTotal, QuestReqText)
    Draw(self.SectionProperties, link, id, info)
    Draw(self.SectionTooltip, full or link)
    self.content:SetHeight(math.max(1, y))
    self:RefreshList()
end

function ns.Open(ref)
    local link = ns.Normalize(ref)
    if not link then return end
    UI:Create()
    local cur = UI.stack[UI.pos]
    if not (cur and ns.ItemID(cur) == ns.ItemID(link)) then
        for i = #UI.stack, UI.pos + 1, -1 do UI.stack[i] = nil end
        UI.stack[#UI.stack + 1] = link
        if #UI.stack > 100 then table.remove(UI.stack, 1) end
        UI.pos = #UI.stack
    end
    ns.AddHistory(link)
    UI.frame:Show()
    UI:Render()
end

function UI:Back()
    if self.pos > 1 then
        self.pos = self.pos - 1
        self:Render()
    end
end

function UI:Forward()
    if self.pos < #self.stack then
        self.pos = self.pos + 1
        self:Render()
    end
end

function ns.Toggle()
    UI:Create()
    if UI.frame:IsShown() then
        UI.frame:Hide()
    else
        UI.frame:Show()
        UI:Render()
    end
end

---------------------------------------------------------------------------
-- Data callbacks from Core
---------------------------------------------------------------------------
-- full = true re-renders the detail view too (recipes changed); otherwise only
-- the left list refreshes (bag changes, icons/names arriving from the server).
local queued, queuedFull = false, false
function UI:OnDataChanged(full)
    if not (self.frame and self.frame:IsShown()) then return end
    queuedFull = queuedFull or full
    if queued then return end
    queued = true
    C_Timer.After(0.2, function()
        queued = false
        local doFull = queuedFull
        queuedFull = false
        if not UI.frame:IsShown() then return end
        if doFull then UI:Render() else UI:RefreshList() end
    end)
end

function UI:OnItemInfo(itemID)
    if not (self.frame and self.frame:IsShown()) then return end
    if self.pending and self.pending == itemID then
        self:Render()
    elseif self.waitNames and self.waitNames[itemID] then
        self:OnDataChanged(true)
    else
        self:OnDataChanged(false)
    end
end

function UI:OnQuestLog()
    if ns.db and ns.db.tab == "Quests" then self:OnDataChanged(false) end
end
