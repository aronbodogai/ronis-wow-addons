-- Roni's Health - the reminder window: a small card at the top of the screen
-- with what to do, one line on why, and "More" for the longer explanation.
local ADDON, ns = ...

local WIDTH, PAD, ICON = 400, 12, 36
local TEXT_W = WIDTH - PAD * 3 - ICON
local EYE_SECONDS = 20

local cards = {}

local function Sound(name, fallback)
    if not ns.db.sound or not PlaySound then return end
    local id = (SOUNDKIT and SOUNDKIT[name]) or fallback
    pcall(PlaySound, id, "Master")
end

---------------------------------------------------------------------------
-- Stack: cards hang below a movable anchor, in the order they appeared
---------------------------------------------------------------------------
local anchor = CreateFrame("Frame", "RonisHealthAnchor", UIParent)
anchor:SetSize(WIDTH, 1)
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)

local function PlaceAnchor()
    anchor:ClearAllPoints()
    local p = ns.db.pos
    if p then
        anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
    else
        anchor:SetPoint("TOP", UIParent, "TOP", 0, -110)
    end
end

local order = {}

local function Restack()
    local y = 0
    for _, kind in ipairs(order) do
        local c = cards[kind]
        c:ClearAllPoints()
        c:SetPoint("TOP", anchor, "TOP", 0, -y)
        y = y + c:GetHeight() + 6
    end
end

local function StartDrag(card)
    anchor:StartMoving()
    card.dragging = true
end

local function StopDrag(card)
    if not card.dragging then return end
    card.dragging = nil
    anchor:StopMovingOrSizing()
    local left, top = anchor:GetLeft(), anchor:GetTop()
    if left and top then ns.db.pos = { x = left, y = top } end
    PlaceAnchor()
    Restack()
end

---------------------------------------------------------------------------
-- Card
---------------------------------------------------------------------------
local function Text(card, font)
    local fs = card:CreateFontString(nil, "OVERLAY", font)
    fs:SetWidth(TEXT_W)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    return fs
end

local function Button(card, label, width, onClick)
    local b = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

-- Lay the texts out top to bottom and size the card to fit.
local function Layout(card)
    local x = PAD * 2 + ICON
    local y = PAD
    local function Put(fs, gap)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
        y = y + fs:GetStringHeight() + (gap or 4)
    end
    if card.reason:GetText() and card.reason:GetText() ~= "" then
        card.reason:Show()
        Put(card.reason, 4)
    else
        card.reason:Hide()
    end
    Put(card.title, 6)
    Put(card.action, 6)
    Put(card.why, 8)
    if card.expanded then
        card.more:Show()
        Put(card.more, 8)
    else
        card.more:Hide()
    end
    y = math.max(y, PAD + ICON + 8)
    local bx = PAD
    for _, b in ipairs(card.buttons) do
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", card, "TOPLEFT", bx, -y)
        bx = bx + b:GetWidth() + 6
    end
    card:SetHeight(y + 22 + PAD)
    Restack()
end

local function Close(card)
    card.countdown = nil
    card:Hide()
    for i, k in ipairs(order) do
        if k == card.kind then table.remove(order, i) break end
    end
    Restack()
end

local function FinishEye(card)
    Sound("READY_CHECK", 8960)
    ns.Done("eye")
    Close(card)
end

-- The eye card counts its 20 seconds down on the main button.
local function CountDown(card, token)
    if card.countdown ~= token or not card:IsShown() then return end
    card.remaining = card.remaining - 1
    if card.remaining <= 0 then
        card.countdown = nil
        FinishEye(card)
        return
    end
    card.primary:SetText(("Look away... %d"):format(card.remaining))
    C_Timer.After(1, function() CountDown(card, token) end)
end

local function Primary(card)
    if card.kind == "eye" then
        if card.countdown then return end
        card.countdown = {}
        card.remaining = EYE_SECONDS
        card.primary:SetText(("Look away... %d"):format(card.remaining))
        card.primary:Disable()
        local token = card.countdown
        C_Timer.After(1, function() CountDown(card, token) end)
    else
        local lo, hi, rounds = ns.RepsFor(card.ctx and card.ctx.window)
        ns.Done("squat", rounds > 1 and hi * rounds or lo)
        Close(card)
    end
end

-- The frame, look, icon and texts every card shares.
local function Shell(kind)
    local card = CreateFrame("Frame", "RonisHealthCard_" .. kind, UIParent, "BackdropTemplate")
    card.kind = kind
    card:SetWidth(WIDTH)
    card:SetFrameStrata("DIALOG")
    card:SetClampedToScreen(true)
    card:EnableMouse(true)
    card:RegisterForDrag("LeftButton")
    card:SetScript("OnDragStart", StartDrag)
    card:SetScript("OnDragStop", StopDrag)
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    card:SetBackdropColor(0.05, 0.07, 0.06, 0.95)
    card:SetBackdropBorderColor(0.31, 0.82, 0.55, 1)

    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON, ICON)
    icon:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -PAD)
    icon:SetTexture(ns.TEXT[kind].icon)
    card.icon = icon

    card.reason = Text(card, "GameFontHighlightSmall")
    card.reason:SetTextColor(0.31, 0.82, 0.55)
    card.reason:SetText("")
    card.title = Text(card, "GameFontNormalLarge")
    card.action = Text(card, "GameFontHighlight")
    card.why = Text(card, "GameFontDisableSmall")
    card.more = Text(card, "GameFontHighlightSmall")
    return card
end

local function Build(kind)
    local card = Shell(kind)
    card.primary = Button(card, "", 132, function() Primary(card) end)
    card.snooze = Button(card, "Snooze", 70, function()
        if card.ctx and card.ctx.early then ns.NotNow(kind) else ns.Snooze(kind) end
        Close(card)
    end)
    card.skip = Button(card, "Skip", 56, function()
        ns.Skip(kind)
        Close(card)
    end)
    card.moreButton = Button(card, "More", 64, function()
        card.expanded = not card.expanded
        card.moreButton:SetText(card.expanded and "Less" or "More")
        Layout(card)
    end)
    card.buttons = { card.primary, card.snooze, card.skip, card.moreButton }

    card:Hide()
    cards[kind] = card
    return card
end

-- Fill a card with the current settings' texts.
local function Fill(card)
    local T = ns.TEXT[card.kind]
    local ctx = card.ctx
    card.reason:SetText(ns.WhyNow(card.kind, ctx) or "")
    card.title:SetText(T.Title(ns.db, ctx))
    card.action:SetText(T.Action(ns.db, ctx))
    card.why:SetText(T.why)
    card.more:SetText(T.More(ns.db) .. "\n\n" .. ns.TEXT.timing)
    card.icon:SetTexture(T.icon)
    card.primary:Enable()
    card.primary:SetText(card.kind == "eye" and "Start 20 s" or "Done")
    -- an early card (natural pause) can be turned down without touching the clock
    if ctx and ctx.early then
        card.snooze:SetText("Not now")
        card.skip:Hide()
        card.buttons = { card.primary, card.snooze, card.moreButton }
    else
        card.snooze:SetText(("Snooze %d min"):format(ns.db.snooze))
        card.skip:Show()
        card.buttons = { card.primary, card.snooze, card.skip, card.moreButton }
    end
    card.snooze:SetWidth(card.snooze:GetText():len() * 6 + 20)
end

---------------------------------------------------------------------------
-- API used by the core
---------------------------------------------------------------------------
function ns.Showing(kind)
    local c = cards[kind]
    return c and c:IsShown() or false
end

-- ctx (optional): why the card shows now, see ns.WhyNow in Data/Texts.lua
function ns.ShowReminder(kind, ctx)
    if not anchor.placed then
        PlaceAnchor()
        anchor.placed = true
    end
    local card = cards[kind] or Build(kind)
    if card:IsShown() then return end
    card.expanded = false
    card.countdown = nil
    card.moreButton:SetText("More")
    card.ctx = ctx
    Fill(card)
    card:Show()
    order[#order + 1] = kind
    Layout(card)
    Sound("TELL_MESSAGE", 3081)
    if FlashClientIcon then FlashClientIcon() end
end

---------------------------------------------------------------------------
-- After a dungeon or raid: one card with what was missed inside
---------------------------------------------------------------------------
local function BuildSummary()
    local card = Shell("summary")
    card.eyeButton = Button(card, "Eye break now", 116, function(self)
        self:Disable()
        ns.ShowReminder("eye")
        card.CheckDone()
    end)
    card.squatButton = Button(card, "Squat break now", 128, function(self)
        self:Disable()
        ns.ShowReminder("squat")
        card.CheckDone()
    end)
    card.dismiss = Button(card, "Dismiss", 76, function() Close(card) end)
    -- close once every offered break has been opened
    function card.CheckDone()
        for _, b in ipairs(card.buttons) do
            if b ~= card.dismiss and b:IsEnabled() then return end
        end
        Close(card)
    end
    card:Hide()
    cards.summary = card
    return card
end

function ns.ShowSummary(trip)
    if not anchor.placed then
        PlaceAnchor()
        anchor.placed = true
    end
    local card = cards.summary or BuildSummary()
    local T = ns.TEXT.summary
    card.title:SetText(T.Title(trip))
    card.action:SetText(T.Action(trip))
    card.why:SetText(T.why)
    card.more:SetText("")
    card.expanded = false
    card.icon:SetTexture(T.icon)
    -- one button per reminder that was missed (and is still turned on)
    card.buttons = {}
    for _, kind in ipairs(ns.KINDS) do
        local b = card[kind .. "Button"]
        if (trip.missed[kind] or 0) > 0 and ns.Enabled(kind) then
            b:Enable()
            b:Show()
            card.buttons[#card.buttons + 1] = b
        else
            b:Hide()
        end
    end
    card.buttons[#card.buttons + 1] = card.dismiss
    if not card:IsShown() then
        card:Show()
        table.insert(order, 1, "summary")
    end
    Layout(card)
    Sound("TELL_MESSAGE", 3081)
    if FlashClientIcon then FlashClientIcon() end
end

function ns.HideReminder(kind)
    local c = cards[kind]
    if c and c:IsShown() then Close(c) end
end

function ns.Card(kind) return cards[kind] end

function ns.ResetPosition()
    ns.db.pos = nil
    PlaceAnchor()
    Restack()
end
