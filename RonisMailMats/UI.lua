-- Roni's MailMats - side panel docked to the right of the mailbox.
local ADDON, ns = ...

local WIDTH = 230
local PAD = 10
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemIcon = GetItemIcon or (C_Item and C_Item.GetItemIconByID)

local panel, title, keepBox, emptyText
local headers, buttons = {}, {}

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return "ffffffff" end
    if c.colorStr then return c.colorStr end
    return ("ff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
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
    h:Show()
    return h
end

local function ButtonTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(("%s mats for %s"):format(self.prof, self.alt))
    local stacks, totals, ids = ns.StacksFor(self.prof)
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
            GameTooltip:AddDoubleLine(label, "x" .. totals[id], r, g, b, 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("%d stack(s); one mail holds %d."):format(#stacks, ATTACHMENTS_MAX_SEND or 12), 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Click to draft the mail. Nothing is sent until you press Send.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function GetButton(i)
    local b = buttons[i]
    if not b then
        b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(WIDTH - 2 * PAD - 8, 22)
        b:SetScript("OnClick", function(self) ns.Draft(self.alt, self.prof) end)
        b:SetScript("OnEnter", ButtonTooltip)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        buttons[i] = b
    end
    b:Show()
    return b
end

function ns.Refresh()
    if not (panel and panel:IsShown()) then return end
    for _, h in ipairs(headers) do h:Hide() end
    for _, b in ipairs(buttons) do b:Hide() end

    local y = -34
    local nh, nb = 0, 0

    for _, alt in ipairs(ns.Alts()) do
        local c = ns.db.chars[ns.realm][alt]
        local crafts = {}
        for _, p in ipairs(ns.CRAFT_ORDER) do
            if c.profs and c.profs[p] then crafts[#crafts + 1] = p end
        end
        if #crafts > 0 then
            nh = nh + 1
            local h = GetHeader(nh)
            h:SetPoint("TOPLEFT", PAD, y)
            h:SetText(("|c%s%s|r |cff999999%s|r"):format(ClassColor(c.class), alt, ns.ProfString(c)))
            y = y - h:GetStringHeight() - 4
            for _, p in ipairs(crafts) do
                nb = nb + 1
                local b = GetButton(nb)
                b.alt, b.prof = alt, p
                local stacks = ns.StacksFor(p)
                b:SetText(("Send %s mats (%d)"):format(p, #stacks))
                b:SetEnabled(#stacks > 0)
                b:SetPoint("TOPLEFT", PAD + 8, y)
                y = y - 24
            end
            y = y - 6
        end
    end

    if nh == 0 then
        emptyText:Show()
        emptyText:SetPoint("TOPLEFT", PAD, y)
        y = y - emptyText:GetStringHeight() - 8
    else
        emptyText:Hide()
    end

    keepBox:SetPoint("TOPLEFT", PAD - 4, y)
    keepBox:SetChecked(ns.db.keepOwn)
    keepBox.label:SetText("Keep mats for my own professions")
    y = y - 28

    panel:SetHeight(-y + PAD)
end

function ns.InitUI()
    if panel or not MailFrame then return end
    panel = CreateFrame("Frame", "RonisMailMatsPanel", MailFrame, "BackdropTemplate")
    panel:SetWidth(WIDTH)
    panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 2, 0)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(0, 0, 0, 0.9)
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
