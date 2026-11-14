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
    win.title:SetText(("%s |cff999999(%d items, %s)|r"):format(selected, #ids, kind))
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
    win:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    win:SetBackdropColor(0, 0, 0, 0.95)
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
-- Minimap button (drag it around the minimap; /mailmats minimap hides it)
---------------------------------------------------------------------------
local mini

local function PlaceMini()
    local angle = math.rad(ns.db.minimapAngle or 200)
    local r = 80
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function DragMini(self)
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    ns.db.minimapAngle = math.deg((math.atan2 or math.atan)(cy / scale - my, cx / scale - mx))
    PlaceMini()
end

function ns.InitMinimap()
    if mini or not Minimap then return end
    mini = CreateFrame("Button", "RonisMailMatsMinimapButton", Minimap)
    mini:SetSize(31, 31)
    mini:SetFrameStrata("MEDIUM")
    mini:SetFrameLevel(8)
    mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mini:RegisterForDrag("LeftButton")
    local icon = mini:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(ns.UPGRADE_ICON or "Interface\\Icons\\INV_Letter_15")
    local border = mini:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    mini:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            SlashCmdList.RONISMAILMATS("")
        else
            ns.ToggleGroups()
        end
    end)
    mini:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", DragMini) end)
    mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mini:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(ns.TAG)
        GameTooltip:AddLine("Left-click: view and edit item groups", 1, 1, 1)
        GameTooltip:AddLine("Right-click: list your characters", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
    PlaceMini()
    mini:SetShown(not ns.db.hideMinimap)
end

function ns.SetMinimapShown(show)
    ns.db.hideMinimap = not show
    if mini then mini:SetShown(show) end
end
