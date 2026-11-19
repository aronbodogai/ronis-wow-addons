-- Roni's MailMats - the Groups window (minimap button or /mailmats groups).
--
-- Left: every group (the professions, lockboxes, scrolls and your own
-- groups). Right: the items in the selected group, a page at a time, each
-- with a remove button. Add an item by dropping it on the window or typing
-- its id, link or name. Built-in groups can be reset to the data files;
-- your own groups can be deleted.
local ADDON, ns = ...

local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemIcon = GetItemIcon or (C_Item and C_Item.GetItemIconByID)

local W, H = 460, 420
local LEFT_W = 150
local PAD = 12
local ROWS = 12
local ROW_H = 22

local win, selected, page = nil, nil, 1
local catButtons, rows = {}, {}

local function Cursor()
    if GetCursorInfo then
        local kind, id = GetCursorInfo()
        if kind == "item" then return id end
    end
end

-- Item id from user input: an id, an item link, or the name of a cached item.
local function ParseItem(text)
    text = strtrim(text or "")
    if text == "" then return nil end
    local id = ns.ItemID(text)
    if id then return id end
    local _, link = GetItemInfo(text)
    return ns.ItemID(link)
end

local function ItemName(id)
    local name, _, quality = GetItemInfo(id)
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        return "item " .. id, nil
    end
    return name, quality
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
function ns.RefreshGroups()
    if not (win and win:IsShown()) then return end
    local cats = ns.Categories()
    if not selected or not ns.IS_REAGENT[selected] then selected = cats[1] end

    -- left: group list
    for _, b in ipairs(catButtons) do b:Hide() end
    for i, cat in ipairs(cats) do
        local b = catButtons[i]
        if not b then
            b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
            b:SetSize(LEFT_W - 8, 20)
            b:SetScript("OnClick", function(self)
                selected, page = self.cat, 1
                ns.RefreshGroups()
            end)
            catButtons[i] = b
        end
        b.cat = cat
        local mark = (ns.IsCustomGroup(cat) and "|cff80c0ff" or (ns.GroupEdited(cat) and "|cffffd100" or "|cffffffff"))
        b:SetText(mark .. cat .. "|r" .. (cat == selected and " <" or ""))
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", PAD, -34 - (i - 1) * 21)
        b:Show()
    end

    win:SetHeight(math.max(H, 34 + #cats * 21 + 64)) -- room for every group on the left

    -- right: items of the selected group
    local ids = ns.GroupItems(selected)
    local pages = math.max(1, math.ceil(#ids / ROWS))
    if page > pages then page = pages end
    local kind = ns.IsCustomGroup(selected) and "your group" or (ns.GroupEdited(selected) and "edited" or "built-in")
    local extra = (selected == "Enchanting" and not ns.db.noGreens) and "\n|cff1eff00+ every BoE green weapon and armor piece|r" or ""
    if ns.HAS_RECIPES[selected] then extra = extra .. "\n|cff1eff00+ every " .. selected .. " recipe|r" end
    win.title:SetText(("%s |cff999999(%d items, %s)|r%s"):format(selected, #ids, kind, extra))
    for i = 1, ROWS do
        local r = rows[i]
        local id = ids[(page - 1) * ROWS + i]
        if id then
            local name, quality = ItemName(id)
            local color = (quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex) or "|cffffffff"
            r.id = id
            r.icon:SetTexture(GetItemIcon(id) or 134400)
            r.text:SetText(color .. name .. "|r")
            r:Show()
        else
            r.id = nil
            r:Hide()
        end
    end
    win.pageText:SetText(("Page %d / %d"):format(page, pages))
    win.prev:SetEnabled(page > 1)
    win.next:SetEnabled(page < pages)
    win.empty:SetShown(#ids == 0)
    if ns.IsCustomGroup(selected) then
        win.reset:SetText("Delete group")
        win.reset:SetEnabled(true)
    else
        win.reset:SetText("Reset to default")
        win.reset:SetEnabled(ns.GroupEdited(selected))
    end
end

local function AddToSelected(id)
    if not id then
        ns.Print("Unknown item. Use an item id or link, or drop the item on the window.")
        return
    end
    ns.GroupAdd(selected, id)
    local name = ItemName(id)
    ns.Print(("Added %s to %s."):format(name, selected))
    ns.RefreshGroups()
end

local function OnDrop()
    local id = Cursor()
    if id then
        ClearCursor()
        AddToSelected(id)
    end
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Build()
    win = CreateFrame("Frame", "RonisMailMatsGroups", UIParent, "BackdropTemplate")
    win:SetSize(W, H)
    win:SetPoint("CENTER")
    ns.StyleWindow(win, true)
    win:SetFrameStrata("DIALOG")
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    win:SetScript("OnReceiveDrag", OnDrop)
    win:SetScript("OnMouseUp", function() if Cursor() then OnDrop() end end)
    win:SetScript("OnShow", ns.RefreshGroups)
    if UISpecialFrames then table.insert(UISpecialFrames, "RonisMailMatsGroups") end -- Escape closes it

    local head = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    head:SetPoint("TOPLEFT", PAD, -PAD)
    head:SetText(ns.TAG .. " groups")

    local close = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    close:SetSize(22, 20)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetText("X")
    close:SetScript("OnClick", function() win:Hide() end)

    local x = PAD + LEFT_W
    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.title:SetPoint("TOPLEFT", x, -34)
    win.title:SetWidth(W - x - PAD)
    win.title:SetJustifyH("LEFT")

    win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.empty:SetPoint("TOPLEFT", x, -56)
    win.empty:SetWidth(W - x - PAD)
    win.empty:SetJustifyH("LEFT")
    win.empty:SetText("No items yet. Drop an item here, or type its id or link below.")

    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, win)
        r:SetSize(W - x - PAD, ROW_H - 2)
        r:SetPoint("TOPLEFT", x, -52 - (i - 1) * ROW_H)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18)
        r.icon:SetPoint("LEFT", 0, 0)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 22, 0)
        r.text:SetWidth(W - x - PAD - 50)
        r.text:SetJustifyH("LEFT")
        r.remove = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.remove:SetSize(20, 18)
        r.remove:SetPoint("RIGHT", 0, 0)
        r.remove:SetText("X")
        r.remove:SetScript("OnClick", function()
            local name = ItemName(r.id)
            ns.GroupRemove(selected, r.id)
            ns.Print(("Removed %s from %s."):format(name, selected))
            ns.RefreshGroups()
        end)
        r:SetScript("OnEnter", function(self)
            if not self.id then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.id) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnReceiveDrag", OnDrop)
        rows[i] = r
    end

    local by = -52 - ROWS * ROW_H - 4
    win.prev = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.prev:SetSize(60, 20)
    win.prev:SetPoint("TOPLEFT", x, by)
    win.prev:SetText("< Prev")
    win.prev:SetScript("OnClick", function() page = page - 1; ns.RefreshGroups() end)
    win.next = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.next:SetSize(60, 20)
    win.next:SetPoint("TOPLEFT", x + 64, by)
    win.next:SetText("Next >")
    win.next:SetScript("OnClick", function() page = page + 1; ns.RefreshGroups() end)
    win.pageText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.pageText:SetPoint("TOPLEFT", x + 132, by - 4)

    -- add an item
    by = by - 28
    win.addBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    win.addBox:SetSize(W - x - PAD - 70, 20)
    win.addBox:SetPoint("TOPLEFT", x + 6, by)
    win.addBox:SetAutoFocus(false)
    win.addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    win.addBox:SetScript("OnEnterPressed", function(self)
        AddToSelected(ParseItem(self:GetText()))
        self:SetText("")
    end)
    win.add = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.add:SetSize(60, 20)
    win.add:SetPoint("TOPLEFT", W - PAD - 60, by)
    win.add:SetText("Add")
    win.add:SetScript("OnClick", function()
        AddToSelected(ParseItem(win.addBox:GetText()))
        win.addBox:SetText("")
    end)
    local addHint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    addHint:SetPoint("TOPLEFT", x, by - 22)
    addHint:SetText("Item id, link or name - or drop an item on the window")

    win.reset = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.reset:SetSize(130, 20)
    win.reset:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    win.reset:SetScript("OnClick", function()
        if ns.IsCustomGroup(selected) then
            ns.DeleteGroup(selected)
            ns.Print("Deleted group " .. selected .. ".")
            selected = nil
        else
            ns.GroupReset(selected)
            ns.Print(selected .. " is back to its default items.")
        end
        ns.RefreshGroups()
    end)

    -- new custom group
    win.newBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    win.newBox:SetSize(LEFT_W - 60, 20)
    win.newBox:SetPoint("BOTTOMLEFT", PAD + 6, PAD)
    win.newBox:SetAutoFocus(false)
    win.newBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local function Create()
        local name, err = ns.NewGroup(win.newBox:GetText())
        if not name then return ns.Print(err) end
        win.newBox:SetText("")
        selected, page = name, 1
        ns.Print("Created group " .. name .. ". Add items, then give it to a recipient.")
        ns.RefreshGroups()
    end
    win.newBox:SetScript("OnEnterPressed", Create)
    win.new = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.new:SetSize(50, 20)
    win.new:SetPoint("BOTTOMLEFT", PAD + LEFT_W - 50, PAD)
    win.new:SetText("New")
    win.new:SetScript("OnClick", Create)
    local newHint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    newHint:SetPoint("BOTTOMLEFT", PAD, PAD + 24)
    newHint:SetText("New group:")

    win:Hide()
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    ev:SetScript("OnEvent", function()
        if win:IsShown() and not ev.pending then
            ev.pending = true
            C_Timer.After(0.2, function() ev.pending = false; ns.RefreshGroups() end)
        end
    end)
end

-- Opens the window, on `cat` if given.
function ns.ToggleGroups(cat)
    if not win then Build() end
    if cat then
        selected, page = cat, 1
        win:Show()
        ns.RefreshGroups()
    elseif win:IsShown() then
        win:Hide()
    else
        win:Show()
    end
end

---------------------------------------------------------------------------
-- Minimap button: the shared Roni's addons button (RonisHub.lua) now; its
-- MailMats tab opens the groups window. The old button's place and
-- hidden state carry over.
---------------------------------------------------------------------------
function ns.InitMinimap()
    local db = ns.db
    db.hub = db.hub or {}
    if db.minimapAngle and db.hub.angle == nil then db.hub.angle = db.minimapAngle end
    if db.hideMinimap and db.hub.hideButton == nil then db.hub.hideButton = true end
    db.minimapAngle, db.hideMinimap = nil, nil
    RonisHub:Register("mailmats", { db = db, build = ns.BuildHubPage })
end

function ns.SetMinimapShown(show)
    RonisHub:SetButtonShown(show)
end

-- The MailMats tab in the Roni's addons window.
function ns.BuildHubPage(page)
    local H = RonisHub
    local w = page:GetWidth()
    local function Changed() if ns.Refresh then ns.Refresh() end end
    local y = 4
    local function Row(widget, x, h)
        widget:SetPoint("TOPLEFT", page, "TOPLEFT", x or 4, -y)
        y = y + (h or 22) + 6
    end

    Row(H:Label(page, "Open a mailbox: each alt gets a button that drafts a mail with the mats it can use. "
        .. "Nothing is sent until you press Send.", "GameFontHighlight", w), nil, 30)
    local groups = H:Button(page, "Item groups", 110, function() ns.ToggleGroups() end)
    groups:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -y)
    local chars = H:Button(page, "List my characters", 140, function() SlashCmdList.RONISMAILMATS("") end)
    chars:SetPoint("LEFT", groups, "RIGHT", 6, 0)
    local history = H:Button(page, "Mail history", 110, function() ns.ToggleHistory() end)
    history:SetPoint("LEFT", chars, "RIGHT", 6, 0)
    y = y + 34

    Row(H:Check(page, page, "Send BoE green gear to enchanters", function() return not ns.db.noGreens end,
        function(v) ns.db.noGreens = (not v) or nil; Changed() end), nil, 22)
    Row(H:Check(page, page, "Add a random message to drafts", function() return ns.db.withMessage end,
        function(v) ns.db.withMessage = v or nil end), nil, 22)
    local warn = H:Label(page, "|cffffd100Note:|r " .. ns.MESSAGE_WARNING, "GameFontDisableSmall", w - 24)
    Row(warn, 24, warn:GetStringHeight())

    local cod = H:Label(page, "Cash on delivery for greens to other players:")
    cod:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -y - 4)
    y = y + 22
    Row(H:Stepper(page, page, 0, 200, 10, function() return ns.CODPercent() end,
        function(v) ns.db.greenCOD = v > 0 and v or false; Changed() end,
        function(v) return v == 0 and "off" or (v .. "% of vendor price") end), 24, 22)

    local ahead = H:Label(page, "Upgrades for alts who can wear them within:")
    ahead:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -y - 4)
    y = y + 22
    Row(H:Stepper(page, page, 0, 20, 1, function() return ns.UpgradeAhead() end,
        function(v) ns.db.upgradeAhead = v; Changed() end,
        function(v) return v == 0 and "now only" or (v .. " level" .. (v == 1 and "" or "s")) end), 24, 22)

    Row(H:Label(page, "Recipients and more: /mailmats", "GameFontDisableSmall", w), nil, 14)
    return y
end
