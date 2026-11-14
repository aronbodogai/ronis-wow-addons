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
local COLS     = 5                   -- left grid columns
local CELL     = 42                  -- left grid cell (slot 38 + gap)
local TABS     = { "Bags", "Recent", "Recipes" }

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
    if self.link then
        GameTooltip:SetHyperlink(self.link)
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
    b.link, b.label, b.extra = link, nil, extra
    b.icon:SetTexture(ns.GetItemIcon(ns.ItemID(link)) or QUESTION)
    local q = select(3, ns.GetItemInfo(link))
    SetBorder(b, q, selected)
    b.count:SetText((count and count ~= 1) and count or "")
    b:Show()
end

-- For things that are not items (e.g. enchants)
function ns.SetSlotPlain(b, texture, label, extra)
    b.link, b.label, b.extra = nil, label, extra
    b.icon:SetTexture(texture or QUESTION)
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
    self.nt, self.ns, self.nx = 0, 0, 0
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
    s.texts, s.slots, s.texs = {}, {}, {}
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
local function MadeText(r)
    local lo, hi = r.made[1] or 1, r.made[2] or 1
    if hi > lo then return lo .. "-" .. hi end
    return lo
end

function UI:SectionRecipe(id, y)
    local keys = ns.madeBy[id]
    if not keys then return y end
    local s = self:AcquireSection(#keys > 1 and ("Recipes (" .. #keys .. ")") or "Recipe", y)
    local cy = SECTION_TOP
    for _, key in ipairs(keys) do
        local r = ns.db.recipes[key]
        local lbl = s:Text("GameFontHighlightSmall", 0.6, 0.6, 0.6)
        lbl:SetPoint("TOPLEFT", 10, -cy)
        lbl:SetText("Made by |cffffd100" .. r.prof .. "|r  -  " .. r.name)
        cy = cy + 16
        local x = 10
        for _, rg in ipairs(r.reagents) do
            if x > CW - 90 then x = 10; cy = cy + 40 end
            local b = s:Slot(36)
            b:SetPoint("TOPLEFT", x, -cy)
            ns.SetSlot(b, "item:" .. rg[1], rg[2])
            x = x + 40
        end
        local arrow = s:Tex()
        arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
        arrow:SetSize(28, 28)
        arrow:SetPoint("TOPLEFT", x, -cy - 4)
        x = x + 32
        local p = s:Slot(36)
        p:SetPoint("TOPLEFT", x, -cy)
        if r.product then
            ns.SetSlot(p, "item:" .. r.product, MadeText(r), nil, r.product == id)
        else
            ns.SetSlotPlain(p, r.icon, r.name, r.prof)
        end
        cy = cy + 44
    end
    return Finish(s, cy, y)
end

function UI:SectionUsedIn(id, y)
    local keys = ns.usedIn[id]
    if not keys then return y end
    local s = self:AcquireSection("Used in (" .. #keys .. ")", y)
    local cy, x = SECTION_TOP, 10
    for _, key in ipairs(keys) do
        local r = ns.db.recipes[key]
        local need = 1
        for _, rg in ipairs(r.reagents) do
            if rg[1] == id then need = rg[2] end
        end
        if x > CW - 46 then x = 10; cy = cy + 40 end
        local b = s:Slot(36)
        b:SetPoint("TOPLEFT", x, -cy)
        local extra = r.prof .. ": " .. r.name .. " needs " .. need
        if r.product then
            ns.SetSlot(b, "item:" .. r.product, nil, extra)
        else
            ns.SetSlotPlain(b, r.icon, r.name, extra)
        end
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
    if not next(ns.db.recipes) then
        local hint = s:Text("GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", 10, -cy - 4)
        hint:SetWidth(CW - 20)
        hint:SetText("Tip: open your profession windows once so recipes show up here.")
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
    search.hint:SetText("Search name or item ID...")
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
    for i, name in ipairs(TABS) do self.tabs[i] = MakeTab(left, name, i) end

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
    local function add(link)
        local id = ns.ItemID(link)
        if id and not seen[id] then
            seen[id] = true
            list[#list + 1] = link
        end
    end
    if tab == "Bags" then
        for bag = 0, NUM_BAG_SLOTS or 4 do
            for slot = 1, ns.GetContainerNumSlots(bag) or 0 do
                add(ns.GetContainerItemLink(bag, slot))
            end
        end
        SortByQualityName(list)
    elseif tab == "Recent" then
        for _, l in ipairs(ns.db.history) do add(l) end
    else
        for id in pairs(ns.known) do add("item:" .. id) end
        SortByQualityName(list)
    end

    local query = strtrim(self.search:GetText() or ""):lower()
    if query ~= "" and not tonumber(query) then
        local filtered = {}
        for _, l in ipairs(list) do
            local n = ns.GetItemInfo(l)
            if n and n:lower():find(query, 1, true) then filtered[#filtered + 1] = l end
        end
        list = filtered
    end
    return list
end

local EMPTY_TEXT = {
    Bags = "Your bags are empty.",
    Recent = "Items you inspect show up here.",
    Recipes = "Open a profession window to teach the pedia its recipes.",
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
        ns.SetSlot(b, link, count, nil, id == curID)
    end
    for i = #list + 1, #self.listSlots do self.listSlots[i]:Hide() end
    self.listChild:SetHeight(math.max(1, math.ceil(#list / COLS) * CELL))

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
    y = self:SectionRecipe(id, y)
    y = self:SectionUsedIn(id, y)
    y = self:SectionProperties(link, id, info, y)
    y = self:SectionTooltip(full or link, y)
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
    else
        self:OnDataChanged(false)
    end
end
