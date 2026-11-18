-- Roni's Health - options window (/health).
local ADDON, ns = ...

local W, PAD = 432, 4
local win
local refreshers = {} -- functions that re-read the settings into the widgets

local function Refresh()
    for _, fn in ipairs(refreshers) do fn() end
end
ns.RefreshOptions = Refresh

local function Label(parent, font, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    if text then fs:SetText(text) end
    return fs
end

local function Btn(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Check(parent, text, get, set)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    local label = c.Text or c.text
    if label then label:SetText(text) end
    c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); Refresh() end)
    refreshers[#refreshers + 1] = function() c:SetChecked(get()) end
    return c
end

-- [-] value [+] stepper; get() returns the number, set(n) stores it.
-- fmt: a format string, or a function(value) returning the text.
local function Stepper(parent, lim, get, set, fmt)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(150, 22)
    local minus = Btn(f, "-", 24, function() set(get() - lim[3]); Refresh() end)
    minus:SetPoint("LEFT", f, "LEFT", 0, 0)
    local val = Label(f, "GameFontHighlight")
    val:SetWidth(90)
    val:SetJustifyH("CENTER")
    val:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    local plus = Btn(f, "+", 24, function() set(get() + lim[3]); Refresh() end)
    plus:SetPoint("LEFT", val, "RIGHT", 4, 0)
    refreshers[#refreshers + 1] = function()
        local v = get()
        val:SetText(type(fmt) == "function" and fmt(v) or fmt:format(v))
        minus:SetEnabled(v > lim[1])
        plus:SetEnabled(v < lim[2])
    end
    f.minus, f.plus, f.value = minus, plus, val
    return f
end

-- Fills Health's tab in the Roni's addons window (RonisHub.lua) and
-- returns the height used.
local function Build(page)
    W = page:GetWidth()
    win = CreateFrame("Frame", "RonisHealthOptions", page)
    win:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    win:SetWidth(W)

    local y = PAD
    local function Row(widget, x, h, gap)
        widget:SetPoint("TOPLEFT", win, "TOPLEFT", x or PAD, -y)
        y = y + (h or 22) + (gap or 6)
    end

    -- Eye breaks -----------------------------------------------------------
    Row(Label(win, "GameFontNormal", ns.TEXT.eye.name), nil, 14, 4)
    local eyeOn = Check(win, "Remind me", function() return ns.db.eye.enabled end,
        function(v) ns.SetEnabled("eye", v) end)
    eyeOn:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
    local eyeEvery = Stepper(win, ns.LIMITS.eyeInterval, function() return ns.db.eye.interval end,
        function(v) ns.SetInterval("eye", v) end, "every %d min")
    Row(eyeEvery, 200, 22, 10)

    -- Squat breaks ---------------------------------------------------------
    Row(Label(win, "GameFontNormal", ns.TEXT.squat.name), nil, 14, 4)
    local sqOn = Check(win, "Remind me", function() return ns.db.squat.enabled end,
        function(v) ns.SetEnabled("squat", v) end)
    sqOn:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
    local sqEvery = Stepper(win, ns.LIMITS.squatInterval, function() return ns.db.squat.interval end,
        function(v) ns.SetInterval("squat", v) end, "every %d min")
    Row(sqEvery, 200, 22, 8)

    -- fitness levels: one button each, the chosen one is disabled
    local lvlLabel = Label(win, "GameFontHighlightSmall", "Pick what fits you today:")
    Row(lvlLabel, nil, 12, 4)
    local bw = math.floor((W - PAD * 2 - 6 * (#ns.LEVEL_ORDER - 1)) / #ns.LEVEL_ORDER)
    local lvlButtons = {}
    for i, key in ipairs(ns.LEVEL_ORDER) do
        local b = Btn(win, ns.LEVELS[key].name, bw, function() ns.SetLevel(key); Refresh() end)
        b:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + (i - 1) * (bw + 6), -y)
        lvlButtons[key] = b
    end
    y = y + 28
    local lvlDesc = Label(win, "GameFontDisableSmall")
    lvlDesc:SetWidth(W - PAD * 2)
    lvlDesc:SetWordWrap(true)
    lvlDesc:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
    y = y + 28

    local moveLabel = Label(win, "GameFontHighlight", "Move:")
    moveLabel:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y - 4)
    local moveBtn = Btn(win, "", 200, function()
        local cur = ns.db.squat.move
        for i, key in ipairs(ns.MOVE_ORDER) do
            if key == cur then
                ns.SetMove(ns.MOVE_ORDER[i % #ns.MOVE_ORDER + 1])
                break
            end
        end
        Refresh()
    end)
    moveBtn:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 48, -y)
    y = y + 28
    local repsLabel = Label(win, "GameFontHighlight", "Reps:")
    repsLabel:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y - 4)
    local reps = Stepper(win, ns.LIMITS.reps, function() return ns.db.squat.reps end,
        function(v) ns.SetReps(v) end, "%d")
    Row(reps, PAD + 48, 22, 4)
    local moveDesc = Label(win, "GameFontDisableSmall")
    moveDesc:SetWidth(W - PAD * 2)
    moveDesc:SetWordWrap(true)
    moveDesc:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
    y = y + 40

    refreshers[#refreshers + 1] = function()
        local sq = ns.db.squat
        for key, b in pairs(lvlButtons) do b:SetEnabled(key ~= sq.level) end
        lvlDesc:SetText(ns.LEVELS[sq.level].desc)
        local mv = ns.MOVES[sq.move]
        moveBtn:SetText(mv.name .. "  >")
        moveDesc:SetText(mv.short)
    end

    -- General --------------------------------------------------------------
    Row(Label(win, "GameFontNormal", "General"), nil, 14, 4)
    Row(Check(win, "Play a sound", function() return ns.db.sound end,
        function(v) ns.db.sound = v end), nil, 22, 2)
    Row(Check(win, "Stop the clock while I am AFK", function() return ns.db.pauseAFK end,
        function(v) ns.db.pauseAFK = v end), nil, 22, 2)
    Row(Check(win, "Hold reminders in dungeons and raids, sum up after", function() return ns.db.quietInstances end,
        function(v) ns.db.quietInstances = v end), nil, 22, 4)
    local snoozeLabel = Label(win, "GameFontHighlight", "Snooze:")
    snoozeLabel:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y - 4)
    Row(Stepper(win, ns.LIMITS.snooze, function() return ns.db.snooze end,
        function(v) ns.db.snooze = ns.Clamp(v, ns.LIMITS.snooze) end, "%d min"), PAD + 56, 22, 10)

    -- Smart timing ---------------------------------------------------------
    Row(Label(win, "GameFontNormal", "Smart timing"), nil, 14, 4)
    Row(Check(win, "Use natural pauses: flights, campfires, sleeping bags, eating",
        function() return ns.db.smart.moments end,
        function(v) ns.db.smart.moments = v end), nil, 22, 2)
    Row(Check(win, "When I am busy, wait for a calm moment (up to 5 min)",
        function() return ns.db.smart.calm end,
        function(v) ns.db.smart.calm = v end), nil, 22, 2)
    Row(Check(win, "Add squats a little each week I keep up",
        function() return ns.db.smart.progress end,
        function(v) ns.db.smart.progress = v end), nil, 22, 4)
    local prog = Label(win, "GameFontDisableSmall")
    prog:SetWidth(W - PAD * 2)
    prog:SetWordWrap(true)
    Row(prog, nil, 26, 8)
    refreshers[#refreshers + 1] = function() prog:SetText(ns.ProgressLine()) end

    -- Bedtime --------------------------------------------------------------
    Row(Label(win, "GameFontNormal", "Bedtime"), nil, 14, 4)
    Row(Check(win, "Remind me to wind down and go to bed",
        function() return ns.db.bedtime.enabled end,
        function(v) ns.db.bedtime.enabled = v end), nil, 22, 4)
    -- times step in minutes since noon so 23:45 -> 00:00 just works
    local function TimeStepper(key)
        return Stepper(win, ns.LIMITS.bedTime,
            function() return ns.SinceNoon(ns.db.bedtime[key]) end,
            function(v) ns.SetBedTime(key, (v + 720) % 1440) end,
            function(v) return ns.TimeText((v + 720) % 1440) end)
    end
    local windLabel = Label(win, "GameFontHighlight", "No new dungeons from")
    windLabel:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y - 4)
    Row(TimeStepper("windDown"), PAD + 160, 22, 4)
    local bedLabel = Label(win, "GameFontHighlight", "Bedtime from")
    bedLabel:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y - 4)
    Row(TimeStepper("bed"), PAD + 160, 22, 10)

    -- Status and stats -----------------------------------------------------
    local status = Label(win, "GameFontHighlightSmall")
    status:SetWidth(W - PAD * 2)
    status:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
    y = y + 44
    local stats = Label(win, "GameFontHighlightSmall")
    stats:SetWidth(W - PAD * 2)
    stats:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
    y = y + 32
    refreshers[#refreshers + 1] = function()
        status:SetText(table.concat(ns.StatusLines(), "\n"))
        stats:SetText(table.concat(ns.StatsLines(), "\n"))
    end

    local note = Label(win, "GameFontDisableSmall", ns.TEXT.disclaimer)
    note:SetWidth(W - PAD * 2)
    note:SetWordWrap(true)
    Row(note, nil, 40, 8)

    local tEye = Btn(win, "Try eye break", 110, function() ns.ShowReminder("eye") end)
    tEye:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
    local tSq = Btn(win, "Try squat break", 120, function() ns.ShowReminder("squat") end)
    tSq:SetPoint("LEFT", tEye, "RIGHT", 6, 0)
    local pos = Btn(win, "Reset position", 110, function() ns.ResetPosition() end)
    pos:SetPoint("LEFT", tSq, "RIGHT", 6, 0)
    y = y + 22 + PAD
    win:SetHeight(y)

    -- keep the countdowns ticking while the window is open
    -- (one loop per opening: an old loop stops when its token is replaced)
    local live
    local function Live(token)
        if live ~= token or not win:IsVisible() then return end
        Refresh()
        C_Timer.After(1, function() Live(token) end)
    end
    win:SetScript("OnShow", function()
        Refresh()
        live = {}
        local token = live
        C_Timer.After(1, function() Live(token) end)
    end)
    return y
end
ns.BuildOptions = Build

function ns.ToggleOptions()
    RonisHub:Toggle("health")
end

function ns.OptionsFrame() return win end
