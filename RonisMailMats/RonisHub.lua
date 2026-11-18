-- Roni's addons hub: one minimap button and one options window with a tab
-- per Roni's addon. Tabs of addons that are not installed (or not loaded)
-- are greyed out.
--
-- Every Roni's addon ships an identical copy of this file. The newest
-- version loaded wins: it replaces the functions on the shared RonisHub
-- table, and the window and button are only built at login, after every
-- copy has loaded. Keep the copies identical (the Health tests check it)
-- and raise VERSION when changing it.
--
-- An addon joins with
--   RonisHub:Register("health", { db = savedTable, build = function(page) ... return height end })
-- build fills `page` (a frame as wide as RonisHub.PAGE_W) on first view and
-- returns the height it used. db gets a `hub` subtable for the minimap
-- button's position; it is written to every registered addon's saved
-- variables, so the button keeps its place whichever addons stay installed.
local VERSION = 1

local Hub = rawget(_G, "RonisHub")
if Hub and (Hub.version or 0) >= VERSION then return end
Hub = Hub or { addons = {} }
_G.RonisHub = Hub
Hub.version = VERSION

-- Every Roni's addon, in tab order.
Hub.KNOWN = {
    { key = "health", folder = "RonisHealth", name = "Health", icon = "Interface\\Icons\\Spell_Holy_MindVision" },
    { key = "itempedia", folder = "RonisItemPedia", name = "ItemPedia", icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { key = "mailmats", folder = "RonisMailMats", name = "MailMats", icon = "Interface\\Icons\\INV_Letter_15" },
}
Hub.TITLE = "|cffff8c1aRoni's|r addons"
Hub.W, Hub.H, Hub.PAD = 480, 560, 14
Hub.PAGE_W = Hub.W - Hub.PAD * 2 - 20

function Hub:Register(key, spec)
    self.addons[key] = spec
    spec.db.hub = spec.db.hub or {}
    if self.window then self:RefreshTabs() end
    -- an addon that sets up at login itself comes after the hub's login
    if self.loggedIn then self:BuildButton() end
end

function Hub:Known(key)
    for _, a in ipairs(self.KNOWN) do
        if a.key == key then return a end
    end
end

---------------------------------------------------------------------------
-- Settings shared by all addons (stored in each registered addon's db.hub)
---------------------------------------------------------------------------
function Hub:Get(field)
    for _, a in ipairs(self.KNOWN) do
        local spec = self.addons[a.key]
        if spec and spec.db.hub[field] ~= nil then return spec.db.hub[field] end
    end
end

function Hub:Set(field, value)
    for _, spec in pairs(self.addons) do spec.db.hub[field] = value end
end

-- Why a tab is greyed out.
function Hub:Missing(a)
    local exists = C_AddOns and C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist(a.folder)
    if exists then
        return "Installed, but turned off in the AddOns list."
    end
    return "Not installed. Get Roni's " .. a.name .. " on CurseForge or Wago."
end

---------------------------------------------------------------------------
-- Widgets for the pages. Checks and steppers re-read their value each time
-- the page is shown (page.refreshers).
---------------------------------------------------------------------------
local function Btn(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end
Hub.Button = function(_, parent, text, w, onClick) return Btn(parent, text, w, onClick) end

function Hub:Label(parent, text, font, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    if width then
        fs:SetWidth(width)
        fs:SetWordWrap(true)
    end
    fs:SetText(text or "")
    return fs
end

local function Refresher(page, fn)
    local list = rawget(page, "refreshers") or {}
    page.refreshers = list
    list[#list + 1] = fn
end

function Hub:RefreshPage(page)
    for _, fn in ipairs(rawget(page, "refreshers") or {}) do fn() end
end

function Hub:Check(page, parent, text, get, set)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    local label = c.Text or c.text
    if label then label:SetText(text) end
    c:SetScript("OnClick", function(b) set(b:GetChecked() and true or false); Hub:RefreshPage(page) end)
    Refresher(page, function() c:SetChecked(get() and true or false) end)
    return c
end

-- [-] value [+]; fmt(value) gives the text
function Hub:Stepper(page, parent, min, max, step, get, set, fmt)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(150, 22)
    local minus = Btn(f, "-", 24, function() set(math.max(min, get() - step)); Hub:RefreshPage(page) end)
    minus:SetPoint("LEFT", f, "LEFT", 0, 0)
    local val = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    val:SetWidth(90)
    val:SetJustifyH("CENTER")
    val:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    local plus = Btn(f, "+", 24, function() set(math.min(max, get() + step)); Hub:RefreshPage(page) end)
    plus:SetPoint("LEFT", val, "RIGHT", 4, 0)
    Refresher(page, function()
        local v = get()
        val:SetText(fmt(v))
        minus:SetEnabled(v > min)
        plus:SetEnabled(v < max)
    end)
    f.minus, f.plus, f.value = minus, plus, val
    return f
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

function Hub:Build()
    local win = CreateFrame("Frame", "RonisHubFrame", UIParent, "BackdropTemplate")
    self.window = win
    win:SetSize(self.W, self.H)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    win:SetBackdropColor(0.06, 0.06, 0.07, 1)
    win:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    tinsert(UISpecialFrames, "RonisHubFrame") -- Escape closes it

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", win, "TOPLEFT", self.PAD, -self.PAD)
    title:SetText(self.TITLE)
    local close = Btn(win, "Close", 60, function() win:Hide() end)
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -self.PAD, -self.PAD + 4)

    -- one tab button per known addon
    self.tabs = {}
    local tw = math.floor((self.W - self.PAD * 2 - 6 * (#self.KNOWN - 1)) / #self.KNOWN)
    for i, a in ipairs(self.KNOWN) do
        local tab = Btn(win, a.name, tw, function() Hub:Select(a.key) end)
        tab:SetPoint("TOPLEFT", win, "TOPLEFT", self.PAD + (i - 1) * (tw + 6), -self.PAD - 26)
        tab:SetMotionScriptsWhileDisabled(true)
        tab:SetScript("OnEnter", function(b)
            if Hub.addons[a.key] then return end
            GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
            GameTooltip:AddLine("Roni's " .. a.name)
            GameTooltip:AddLine(Hub:Missing(a), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.tabs[a.key] = tab
    end

    -- the selected addon's page, scrolled with the mouse wheel when long
    local top = self.PAD + 26 + 22 + 10
    local scroll = CreateFrame("ScrollFrame", nil, win)
    scroll:SetPoint("TOPLEFT", win, "TOPLEFT", self.PAD, -top)
    scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -self.PAD, self.PAD + 28)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(s, delta)
        local max = math.max(0, (Hub.pageHeight or 0) - (Hub.H - top - Hub.PAD - 28))
        s:SetVerticalScroll(math.max(0, math.min(max, s:GetVerticalScroll() - delta * 40)))
    end)
    self.scroll = scroll
    self.pages = {}

    -- shared: the minimap button
    local foot = {}
    local mini = self:Check(foot, win, "Minimap button", function() return Hub:ButtonShown() end,
        function(v) Hub:SetButtonShown(v) end)
    mini:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", self.PAD - 4, self.PAD - 4)
    win:SetScript("OnShow", function() Hub:RefreshPage(foot) end)
    win:Hide()
    self:RefreshTabs()
end

function Hub:RefreshTabs()
    for _, a in ipairs(self.KNOWN) do
        local tab = self.tabs[a.key]
        tab:SetEnabled(self.addons[a.key] ~= nil and a.key ~= self.selected)
    end
end

function Hub:Select(key)
    local spec = self.addons[key]
    if not spec then return end
    if not self.window then self:Build() end
    for k, page in pairs(self.pages) do page:SetShown(k == key) end
    local page = self.pages[key]
    if not page then
        page = CreateFrame("Frame", nil, self.scroll)
        page:SetWidth(self.PAGE_W)
        page.height = spec.build(page) or 400
        page:SetHeight(page.height)
        self.pages[key] = page
    end
    page:Show()
    self:RefreshPage(page)
    self.scroll:SetScrollChild(page)
    self.scroll:SetVerticalScroll(0)
    self.pageHeight = page.height
    self.selected = key
    self:Set("tab", key)
    self:RefreshTabs()
end

-- Open the window (on `key`'s tab if given), or close it.
function Hub:Toggle(key)
    if not self.window then self:Build() end
    if self.window:IsShown() and (not key or key == self.selected) then
        self.window:Hide()
        return
    end
    key = key or self.selected or self:Get("tab")
    if not self.addons[key or ""] then
        for _, a in ipairs(self.KNOWN) do
            if self.addons[a.key] then key = a.key break end
        end
    end
    self:Select(key)
    self.window:Show()
end

---------------------------------------------------------------------------
-- Minimap button: click opens the window, drag moves it around the map
---------------------------------------------------------------------------
function Hub:PlaceButton()
    local angle = math.rad(self:Get("angle") or 210)
    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end

function Hub:SetButtonShown(show)
    self:Set("hideButton", not show or nil)
    if self.button then self.button:SetShown(show) end
end

function Hub:ButtonShown() return not self:Get("hideButton") end

function Hub:BuildButton()
    if self.button or not Minimap then return end
    local b = CreateFrame("Button", "RonisHubMinimapButton", Minimap)
    self.button = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    -- the icon of the first installed addon
    for _, a in ipairs(self.KNOWN) do
        if self.addons[a.key] then icon:SetTexture(a.icon) break end
    end
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetScript("OnClick", function() Hub:Toggle() end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            Hub:Set("angle", math.deg((math.atan2 or math.atan)(cy / scale - my, cx / scale - mx)))
            Hub:PlaceButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(Hub.TITLE)
        GameTooltip:AddLine("Click: options", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self:PlaceButton()
    b:SetShown(self:ButtonShown())
end

---------------------------------------------------------------------------
-- Login: build the button once every addon has loaded and registered
---------------------------------------------------------------------------
function Hub:OnEvent(event)
    if event == "PLAYER_LOGIN" then
        self.loggedIn = true
        if next(self.addons) then self:BuildButton() end
    end
end

if not Hub.events then
    Hub.events = CreateFrame("Frame")
    Hub.events:RegisterEvent("PLAYER_LOGIN")
    -- through the table, so the newest copy's OnEvent runs
    Hub.events:SetScript("OnEvent", function(_, event) RonisHub:OnEvent(event) end)
end
