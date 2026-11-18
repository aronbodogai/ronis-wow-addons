-- Roni's MailMats - side panel docked to the right of the mailbox.
local ADDON, ns = ...

local WIDTH = 230
local PAD = 10
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemIcon = GetItemIcon or (C_Item and C_Item.GetItemIconByID)

local panel, title, keepBox, emptyText, addButton, msgButton, editor, keepText, keepChoose, keepFrame, codButton
local headers, buttons, removers = {}, {}, {}

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return "ffffffff" end
    if c.colorStr then return c.colorStr end
    return ("ff%02x%02x%02x"):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
end

local function GetHeader(i)
    local h = headers[i]
    if not h then
        h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetJustifyH("LEFT")
        h:SetWidth(WIDTH - 2 * PAD)
        h:SetWordWrap(true)
        headers[i] = h
    end
    h:SetWidth(WIDTH - 2 * PAD)
    h:Show()
    return h
end

local function ButtonTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local what = ns.What(self.prof)
    GameTooltip:AddLine(("%s for %s"):format(what:gsub("^%l", string.upper), self.alt))
    local stacks, totals, ids = ns.StacksFor(self.prof, self.alt)
    local alt = ns.db.chars[ns.realm][self.alt]
    local skill = alt and alt.profs and type(self.prof) == "string" and alt.profs[self.prof]
    if #ids == 0 then
        GameTooltip:AddLine("Nothing in your bags.", 0.6, 0.6, 0.6)
    else
        for _, id in ipairs(ids) do
            local name, _, quality = GetItemInfo(id)
            local r, g, b = 1, 1, 1
            if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
                local q = ITEM_QUALITY_COLORS[quality]
                r, g, b = q.r, q.g, q.b
            end
            local icon = GetItemIcon(id)
            local label = (icon and ("|T" .. icon .. ":14|t ") or "") .. (name or ("item " .. id))
            if self.prof == ns.UPGRADES then
                local _, link = GetItemInfo(id)
                for _, up in ipairs(link and ns.UpgradesFor(link) or {}) do
                    if up.alt == self.alt and up.at then
                        label = label .. (" |cffa0d070(level %d)|r"):format(up.at)
                    end
                end
            end
            local need = ns.SKILL_RANK[id]
            if need and skill and need > (skill.rank or 0) then
                -- a lockbox or scroll the alt cannot open yet
                label = label .. (" |cffff6060(needs %d)|r"):format(need)
            end
            GameTooltip:AddDoubleLine(label, "x" .. totals[id], r, g, b, 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("%d stack(s); one mail holds %d."):format(#stacks, ATTACHMENTS_MAX_SEND or 12), 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Click to draft the mail. Nothing is sent until you press Send.", 0.6, 0.6, 0.6)
    end
    if self.prof ~= ns.UPGRADES then
        local held = ns.HeldFor(self.prof)
        if #held > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Not sent:", 1, 0.5, 0.25)
            for _, h in ipairs(held) do
                local name = GetItemInfo(h[1]) or ("item " .. h[1])
                GameTooltip:AddDoubleLine(("%s x%d"):format(name, h[2]), h[3], 0.8, 0.8, 0.8, 1, 0.5, 0.25)
            end
            GameTooltip:AddLine("Change this with \"Keep mats for\" on the panel.", 0.6, 0.6, 0.6)
        end
    end
    if self.target then
        GameTooltip:AddLine("Right-click to change what " .. self.alt .. " gets.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function GetButton(i)
    local b = buttons[i]
    if not b then
        b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(WIDTH - 2 * PAD - 8, 22)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                if self.target then ns.OpenEditor(self.alt) end
                return
            end
            ns.Draft(self.alt, self.prof)
        end)
        b:SetScript("OnEnter", ButtonTooltip)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        buttons[i] = b
    end
    b:Show()
    return b
end

-- Small "X" next to a recipient's name: removes the recipient.
local function GetRemover(i)
    local b = removers[i]
    if not b then
        b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(20, 18)
        b:SetText("X")
        b:SetScript("OnClick", function(self)
            local name = self.target
            ns.SetTarget(name, nil)
            ns.Print(("Removed %s. Add them again with \"Add a recipient...\"."):format(name))
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Remove " .. self.target)
            GameTooltip:AddLine("Right-click the Send button to edit instead.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        removers[i] = b
    end
    b:Show()
    return b
end

function ns.Refresh()
    if not (panel and panel:IsShown()) then return end
    for _, h in ipairs(headers) do h:Hide() end
    for _, b in ipairs(buttons) do b:Hide() end
    for _, b in ipairs(removers) do b:Hide() end

    local y = -34
    local nh, nb = 0, 0

    for _, alt in ipairs(ns.Alts()) do
        local c = ns.db.chars[ns.realm][alt]
        local crafts = {}
        for _, p in ipairs(ns.CRAFT_ORDER) do
            if c.profs and c.profs[p] then crafts[#crafts + 1] = p end
        end
        -- gear upgrades: only when there are some, so the panel stays short
        if #ns.StacksFor(ns.UPGRADES, alt) > 0 then crafts[#crafts + 1] = ns.UPGRADES end
        local spells = ns.CLASS_GROUP[c.class or ""]
        if spells and #ns.StacksFor(spells, alt) > 0 then crafts[#crafts + 1] = spells end
        if #crafts > 0 then
            nh = nh + 1
            local h = GetHeader(nh)
            h:SetPoint("TOPLEFT", PAD, y)
            local note = ns.NeedsFullName(alt) and " |cffff6060(log in once on this alt: surname unknown)|r" or ""
            h:SetText(("|c%s%s|r |cff999999%s|r%s"):format(ClassColor(c.class), alt, ns.ProfString(c), note))
            y = y - h:GetStringHeight() - 4
            for _, p in ipairs(crafts) do
                nb = nb + 1
                local b = GetButton(nb)
                b.alt, b.prof, b.target = alt, p, false
                local stacks = ns.StacksFor(p, alt)
                b:SetText(("Send %s (%d)"):format(ns.What(p), #stacks))
                b:SetEnabled(#stacks > 0)
                b:SetPoint("TOPLEFT", PAD + 8, y)
                y = y - 24
            end
            y = y - 6
        end
    end

    -- other recipients: one button for everything they want
    for i, name in ipairs(ns.Targets()) do
        local cats = ns.TargetCats(name)
        nh = nh + 1
        local h = GetHeader(nh)
        h:SetPoint("TOPLEFT", PAD, y)
        h:SetWidth(WIDTH - 2 * PAD - 24) -- room for the remove button
        local rm = GetRemover(i)
        rm.target = name
        rm:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD + 2, y + 3)
        local names = {}
        for _, p in ipairs(cats) do names[#names + 1] = p end
        h:SetText(("|cffffd100%s|r |cff999999%s|r"):format(name, table.concat(names, ", ")))
        y = y - h:GetStringHeight() - 4
        nb = nb + 1
        local b = GetButton(nb)
        b.alt, b.prof, b.target = name, cats, true
        local stacks = ns.StacksFor(cats)
        b:SetText(("Send all to %s (%d)"):format(name, #stacks))
        b:SetEnabled(#stacks > 0)
        b:SetPoint("TOPLEFT", PAD + 8, y)
        y = y - 30
    end

    if nh == 0 then
        emptyText:Show()
        emptyText:SetPoint("TOPLEFT", PAD, y)
        y = y - emptyText:GetStringHeight() - 8
    else
        emptyText:Hide()
    end

    addButton:SetPoint("TOPLEFT", PAD, y)
    y = y - 26
    msgButton:SetPoint("TOPLEFT", PAD, y)
    msgButton:SetEnabled(ns.BodyBox() ~= nil and #(ns.MESSAGES or {}) > 0)
    y = y - 26

    keepBox:SetPoint("TOPLEFT", PAD - 4, y)
    keepBox:SetChecked(ns.db.keepOwn)
    keepBox.label:SetText("Keep mats for my own professions")
    y = y - 24
    -- which of my professions keep their mats
    local mine, kept = ns.MyCraftProfs(), {}
    for _, p in ipairs(mine) do if ns.KeepsFor(p) then kept[#kept + 1] = p end end
    keepText:SetPoint("TOPLEFT", PAD + 4, y)
    keepText:SetText(#mine == 0 and "|cff999999(this character has no professions with mats)|r"
        or ("|cff999999Keeping for:|r " .. (#kept > 0 and table.concat(kept, ", ") or "nothing")))
    keepText:SetShown(ns.db.keepOwn)
    keepChoose:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, y + 4)
    keepChoose:SetShown(ns.db.keepOwn and #mine > 0)
    if ns.db.keepOwn then y = y - math.max(20, keepText:GetStringHeight() + 6) end
    if keepFrame and keepFrame:IsShown() then ns.RefreshKeepFrame() end

    -- cash on delivery for greens sent to other players
    local pct = ns.CODPercent()
    codButton:SetPoint("TOPLEFT", PAD, y)
    codButton:SetText(pct == 0 and "Greens: no COD" or ("Greens COD: %d%% of vendor"):format(pct))
    y = y - 26

    panel:SetHeight(-y + PAD)
end

function ns.InitUI()
    if panel or not MailFrame then return end
    panel = CreateFrame("Frame", "RonisMailMatsPanel", MailFrame, "BackdropTemplate")
    panel:SetWidth(WIDTH)
    panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 2, 0)
    ns.StyleWindow(panel, true)
    panel:EnableMouse(true)

    title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PAD, -PAD)
    title:SetText(ns.TAG)

    emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetJustifyH("LEFT")
    emptyText:SetWidth(WIDTH - 2 * PAD)
    emptyText:SetText("No alts with crafting professions known yet. Log in once on each alt so I can learn their professions.")

    keepBox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    keepBox:SetSize(24, 24)
    keepBox.label = keepBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    keepBox.label:SetPoint("LEFT", keepBox, "RIGHT", 2, 0)
    keepBox:SetScript("OnClick", function(self)
        ns.db.keepOwn = self:GetChecked() and true or false
        ns.Refresh()
    end)
    keepBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Keep my own mats")
        GameTooltip:AddLine("Never draft items this character can use for its own professions.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    keepBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

    keepText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    keepText:SetWidth(WIDTH - 2 * PAD - 70)
    keepText:SetJustifyH("LEFT")
    keepText:SetWordWrap(true)
    keepChoose = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    keepChoose:SetSize(64, 20)
    keepChoose:SetText("Choose")
    keepChoose:SetScript("OnClick", function() ns.ToggleKeepFrame() end)

    -- left-click: next COD step, right-click: previous
    codButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    codButton:SetSize(WIDTH - 2 * PAD, 22)
    codButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    codButton:SetScript("OnClick", function(_, button)
        local steps, cur = ns.COD_STEPS, ns.CODPercent()
        local at = 1
        for i, v in ipairs(steps) do if (v or 0) == cur then at = i end end
        at = at + (button == "RightButton" and -1 or 1)
        if at > #steps then at = 1 elseif at < 1 then at = #steps end
        ns.db.greenCOD = steps[at]
        ns.Refresh()
    end)
    codButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Cash on delivery for greens")
        GameTooltip:AddLine("BoE green weapons and armor mailed to another player for disenchanting ask this share of their vendor price as cash on delivery. Never for your own characters.", 1, 1, 1, true)
        GameTooltip:AddLine("Left-click: more. Right-click: less. Also /mailmats cod <percent> | off", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    codButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    addButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addButton:SetSize(WIDTH - 2 * PAD, 22)
    addButton:SetText("Add a recipient...")
    addButton:SetScript("OnClick", function() ns.OpenEditor(nil) end)

    -- another random message in the mail body
    msgButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    msgButton:SetSize(WIDTH - 2 * PAD, 22)
    msgButton:SetText("New message")
    msgButton:SetScript("OnClick", function()
        if not (SendMailFrame and SendMailFrame:IsShown()) and MailFrameTab2 then MailFrameTab2:Click() end
        if ns.FillMessage(true) == false then
            ns.Print("The mail body has your own text; clear it first to get a random message.")
        end
    end)
    msgButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("New message")
        GameTooltip:AddLine(("Puts another of %d random messages in the mail body. Text you typed yourself is never replaced.")
            :format(#(ns.MESSAGES or {})), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    msgButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    panel:SetScript("OnShow", ns.Refresh)

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("MAIL_SHOW")
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    ev:RegisterEvent("MAIL_SEND_SUCCESS")
    ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    local pending = false
    ev:SetScript("OnEvent", function()
        -- coalesce bursts of bag/item events into one refresh
        if pending then return end
        pending = true
        C_Timer.After(0.1, function()
            pending = false
            ns.Refresh()
        end)
    end)
end

---------------------------------------------------------------------------
-- Recipient editor: a name and the categories they get
---------------------------------------------------------------------------
local EDIT_W = 200

local function BuildEditor()
    editor = CreateFrame("Frame", "RonisMailMatsEditor", panel, "BackdropTemplate")
    editor:SetWidth(EDIT_W)
    editor:SetPoint("TOPLEFT", panel, "TOPRIGHT", 2, 0)
    ns.StyleWindow(editor)
    editor:EnableMouse(true)

    local t = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", PAD, -PAD)
    t:SetText("Recipient")

    local nameBox = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    nameBox:SetSize(EDIT_W - 2 * PAD - 6, 20)
    nameBox:SetPoint("TOPLEFT", PAD + 6, -30)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(48)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editor.nameBox = nameBox

    local hint = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PAD, -56)
    hint:SetText("Sends one mail with all of:")

    -- one checkbox per group; made and placed by Relayout (custom groups come and go)
    editor.boxes, editor.boxByCat = {}, {}
    local y = -72

    local function Btn(text, x, fn)
        local b = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
        b:SetSize((EDIT_W - 2 * PAD - 8) / 3, 22)
        b:SetPoint("TOPLEFT", x, y)
        b:SetText(text)
        b:SetScript("OnClick", fn)
        return b
    end
    local w = (EDIT_W - 2 * PAD - 8) / 3
    editor.save = Btn("Save", PAD, function()
        local cats = {}
        for _, cb in ipairs(editor.boxes) do
            if cb:GetChecked() then cats[#cats + 1] = cb.cat end
        end
        local name = strtrim(nameBox:GetText() or "")
        if name == "" or #cats == 0 then
            ns.Print("Enter a name and tick at least one category.")
            return
        end
        if editor.editing and editor.editing:lower() ~= name:lower() then ns.SetTarget(editor.editing, nil) end
        ns.SetTarget(name, cats)
        editor:Hide()
    end)
    editor.delete = Btn("Delete", PAD + w + 4, function()
        if editor.editing then ns.SetTarget(editor.editing, nil) end
        editor:Hide()
    end)
    editor.cancel = Btn("Cancel", PAD + 2 * (w + 4), function() editor:Hide() end)
    y = y - 30

    -- suggestions (new recipients only): friends, guild, mail partners
    editor.sugTitle = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editor.sugTitle:SetPoint("TOPLEFT", PAD, y)
    editor.sugTitle:SetText("Suggestions")
    editor.sugEmpty = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    editor.sugEmpty:SetPoint("TOPLEFT", PAD, y - 18)
    editor.sugEmpty:SetWidth(EDIT_W - 2 * PAD)
    editor.sugEmpty:SetJustifyH("LEFT")
    editor.sugEmpty:SetText("Nobody to suggest: no friends, guild members or mail partners who are not already here.")
    editor.sugButtons = {}
end

-- Places a checkbox for every current group, then the buttons and the
-- suggestions title below them.
local function Relayout()
    local y = -72
    for _, cb in pairs(editor.boxByCat) do cb:Hide() end
    editor.boxes = {}
    for _, p in ipairs(ns.Categories()) do
        local cb = editor.boxByCat[p]
        if not cb then
            cb = CreateFrame("CheckButton", nil, editor, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            cb.label:SetText(p .. (p == "Lockpicking" and " (lockboxes)" or p == "Comprehension" and " (scrolls)"
                or (ns.IsCustomGroup(p) and " (your group)" or "")))
            cb.cat = p
            editor.boxByCat[p] = cb
        end
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", PAD - 4, y)
        cb:Show()
        editor.boxes[#editor.boxes + 1] = cb
        y = y - 20
    end
    y = y - 6
    local w = (EDIT_W - 2 * PAD - 8) / 3
    for i, b in ipairs({ editor.save, editor.delete, editor.cancel }) do
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", PAD + (i - 1) * (w + 4), y)
    end
    y = y - 30
    editor.sugTitle:ClearAllPoints()
    editor.sugTitle:SetPoint("TOPLEFT", PAD, y)
    editor.sugEmpty:ClearAllPoints()
    editor.sugEmpty:SetPoint("TOPLEFT", PAD, y - 18)
    editor.baseY = y
    editor.baseH = -y + PAD
end

local function Suggest(self)
    editor.nameBox:SetText(self.name)
    local hint = {}
    for _, p in ipairs(self.cats) do hint[p] = true end
    for _, cb in ipairs(editor.boxes) do
        if hint[cb.cat] then cb:SetChecked(true) end
    end
end

local function ShowSuggestions(show)
    for _, b in ipairs(editor.sugButtons) do b:Hide() end
    editor.sugTitle:SetShown(show)
    editor.sugEmpty:Hide()
    if not show then
        editor:SetHeight(editor.baseH)
        return
    end
    local list = ns.Suggestions(8)
    local y = editor.baseY - 18
    for i, s in ipairs(list) do
        local b = editor.sugButtons[i]
        if not b then
            b = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
            b:SetSize(EDIT_W - 2 * PAD, 20)
            b:SetScript("OnClick", Suggest)
            editor.sugButtons[i] = b
        end
        b.name, b.cats = s.name, s.cats
        b:SetText(("%s |cff999999(%s)|r"):format(s.name, s.why))
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", PAD, y)
        b:Show()
        y = y - 22
    end
    if #list == 0 then
        editor.sugEmpty:Show()
        y = y - editor.sugEmpty:GetStringHeight() - 4
    end
    editor:SetHeight(-y + PAD)
end

-- Opens the editor for a recipient, or empty for a new one.
function ns.OpenEditor(name)
    if not panel then return end
    if not editor then BuildEditor() end
    editor.editing = name or false
    Relayout()
    editor.nameBox:SetText(name or "")
    local want = {}
    for _, p in ipairs(name and ns.TargetCats(name) or {}) do want[p] = true end
    for _, cb in ipairs(editor.boxes) do cb:SetChecked(want[cb.cat] or false) end
    editor.delete:SetEnabled(name ~= nil)
    ShowSuggestions(name == nil)
    editor:Show()
end

---------------------------------------------------------------------------
-- "Keep mats for" chooser: one checkbox per profession of this character
---------------------------------------------------------------------------
local keepBoxes = {}

function ns.RefreshKeepFrame()
    for _, cb in ipairs(keepBoxes) do cb:Hide() end
    local y = -30
    for i, p in ipairs(ns.MyCraftProfs()) do
        local cb = keepBoxes[i]
        if not cb then
            cb = CreateFrame("CheckButton", nil, keepFrame, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            cb:SetScript("OnClick", function(self) ns.SetKeepFor(self.prof, self:GetChecked()) end)
            keepBoxes[i] = cb
        end
        cb.prof = p
        cb.label:SetText(p)
        cb:SetChecked(ns.KeepsFor(p))
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", PAD - 4, y)
        cb:Show()
        y = y - 20
    end
    keepFrame:SetHeight(-y + PAD)
end

function ns.ToggleKeepFrame()
    if not keepFrame then
        keepFrame = CreateFrame("Frame", "RonisMailMatsKeep", panel, "BackdropTemplate")
        keepFrame:SetWidth(170)
        keepFrame:SetPoint("BOTTOMLEFT", panel, "BOTTOMRIGHT", 2, 0)
        ns.StyleWindow(keepFrame)
        keepFrame:EnableMouse(true)
        local t = keepFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOPLEFT", PAD, -PAD)
        t:SetText("Keep mats for")
        keepFrame:Hide()
    end
    if keepFrame:IsShown() then
        keepFrame:Hide()
    else
        keepFrame:Show()
        ns.RefreshKeepFrame()
    end
end
