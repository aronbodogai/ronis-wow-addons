-- Roni's Health - core: settings, break timers, slash commands.
--
-- Two reminders run on play time:
--   eye   - the 20-20-20 rule (every N minutes, look ~6 m away for 20 s)
--   squat - stand up and do a short set of squats (every N minutes)
--
-- A timer counts down only while you are logged in, not AFK and not paused.
-- When it runs out in combat the reminder waits until combat ends.
local ADDON, ns = ...

ns.TAG = "|cff4fd18bRoni's Health|r"

function ns.Print(...)
    print(ns.TAG .. ":", ...)
end

ns.KINDS = { "eye", "squat" }

local DEFAULTS = {
    eye = { enabled = true, interval = 20 },
    squat = { enabled = true, interval = 40, level = "standard", reps = 10, move = "squat" },
    snooze = 5,          -- minutes
    sound = true,
    pauseAFK = true,     -- timers stop while you are flagged AFK
    quietInstances = true, -- hold reminders inside dungeons and raids, sum them up after
}
ns.DEFAULTS = DEFAULTS

-- Limits for the options window and slash commands.
ns.LIMITS = {
    eyeInterval = { 10, 60, 5 },   -- min, max, step (minutes)
    squatInterval = { 20, 90, 5 },
    reps = { 5, 20, 1 },
    snooze = { 1, 15, 1 },
}

-- Coming back after this long (offline or AFK) counts as a break.
ns.AWAY_RESET = 5 * 60

local function Fill(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            Fill(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function Clamp(v, lim)
    v = math.floor(tonumber(v) or lim[1])
    if v < lim[1] then return lim[1] end
    if v > lim[2] then return lim[2] end
    return v
end
ns.Clamp = Clamp

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
-- ns.left[kind]  seconds of play time until the reminder is due
-- ns.due[kind]   true while the reminder is due but waiting (combat, instance)
-- ns.pausedUntil GetTime() value until which everything is paused (0 = not)
ns.left, ns.due = {}, {}
ns.pausedUntil = 0
local afkSince -- GetTime() when the AFK flag went up

function ns.Interval(kind)
    return ns.db[kind].interval * 60
end

function ns.Enabled(kind)
    return ns.db[kind].enabled
end

-- Restart a reminder's countdown (after it was done, skipped or turned on).
function ns.Reset(kind, seconds)
    ns.left[kind] = seconds or ns.Interval(kind)
    ns.due[kind] = nil
end

local function Today()
    return date("%Y-%m-%d")
end

-- Stats: { day = "YYYY-MM-DD", today = { eye, squat, reps }, total = { ... } }
local function Stats()
    local s = ns.db.stats
    if s.day ~= Today() then
        s.day = Today()
        s.today = { eye = 0, squat = 0, reps = 0, skipped = 0 }
    end
    return s
end
ns.Stats = Stats

function ns.Record(kind, reps)
    local s = Stats()
    for _, t in ipairs({ s.today, s.total }) do
        t[kind] = (t[kind] or 0) + 1
        if reps then t.reps = (t.reps or 0) + reps end
    end
end

function ns.RecordMissed(n)
    local s = Stats()
    s.today.missed = (s.today.missed or 0) + n
    s.total.missed = (s.total.missed or 0) + n
end

function ns.RecordSkip()
    local s = Stats()
    s.today.skipped = (s.today.skipped or 0) + 1
    s.total.skipped = (s.total.skipped or 0) + 1
end

---------------------------------------------------------------------------
-- When a reminder may show
---------------------------------------------------------------------------
function ns.InCombat()
    if InCombatLockdown and InCombatLockdown() then return true end
    return UnitAffectingCombat and UnitAffectingCombat("player") and true or false
end

function ns.InQuietInstance()
    if not ns.db.quietInstances or not IsInInstance then return false end
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid") or false
end

-- Why a due reminder has to wait, or nil when it can show now.
function ns.Blocker()
    if ns.InCombat() then return "combat" end
    if ns.InQuietInstance() then return "instance" end
    return nil
end

---------------------------------------------------------------------------
-- Dungeon and raid runs: with "quiet in instances" on, reminders do not pop
-- up inside. Their clocks keep running and each time one runs out it counts
-- as missed; leaving shows one summary card instead of a pile of reminders.
-- ns.trip = { name, start (time()), missed = { eye = n, squat = n } },
-- kept in the saved variables so a /reload inside does not lose it.
---------------------------------------------------------------------------
local function InstanceName()
    if GetInstanceInfo then
        local name = GetInstanceInfo()
        if name and name ~= "" then return name end
    end
    return "the dungeon"
end

local function StartTrip()
    ns.trip = { name = InstanceName(), start = time(), missed = { eye = 0, squat = 0 } }
    ns.db.trip = ns.trip
end

local function EndTrip()
    local trip = ns.trip
    ns.trip, ns.db.trip = nil, nil
    local any = false
    for _, kind in ipairs(ns.KINDS) do
        local n = trip.missed[kind] or 0
        if n > 0 then
            any = true
            ns.RecordMissed(n)
            -- the summary offers this break now, so its clock starts over
            ns.Reset(kind)
        end
    end
    if any then
        trip.stop = time()
        ns.pendingSummary = trip
    end
end

-- How many breaks a trip has missed so far.
function ns.TripMissed(trip)
    local n = 0
    for _, kind in ipairs(ns.KINDS) do n = n + (trip.missed[kind] or 0) end
    return n
end

local function IsAFK()
    return UnitIsAFK and UnitIsAFK("player") and true or false
end

---------------------------------------------------------------------------
-- The clock: one tick per second while logged in
---------------------------------------------------------------------------
local lastTick

function ns.Paused()
    return ns.pausedUntil > GetTime()
end

local function TryShow(kind)
    if ns.Blocker() then
        ns.due[kind] = true
        return
    end
    ns.due[kind] = nil
    ns.ShowReminder(kind)
end

function ns.Tick()
    local now = GetTime()
    local dt = lastTick and math.max(0, now - lastTick) or 0
    lastTick = now

    -- entering or leaving a dungeon/raid (with quiet instances on)
    local quiet = ns.InQuietInstance()
    if quiet and not ns.trip then
        StartTrip()
    elseif not quiet and ns.trip then
        EndTrip()
    end

    -- AFK: stop the clocks; coming back after a while counts as an eye break
    if ns.db.pauseAFK then
        if IsAFK() then
            afkSince = afkSince or now
            return
        elseif afkSince then
            local away = now - afkSince
            afkSince = nil
            if away >= ns.AWAY_RESET and not ns.Showing("eye") then ns.Reset("eye") end
        end
    end
    if ns.Paused() then return end

    if ns.pendingSummary and not ns.Blocker() then
        local trip = ns.pendingSummary
        ns.pendingSummary = nil
        ns.ShowSummary(trip)
    end

    for _, kind in ipairs(ns.KINDS) do
        if ns.Enabled(kind) and not ns.Showing(kind) then
            if ns.trip then
                -- inside: count each interval that runs out as a missed break
                ns.due[kind] = nil
                ns.left[kind] = (ns.left[kind] or ns.Interval(kind)) - dt
                if ns.left[kind] <= 0 then
                    ns.trip.missed[kind] = (ns.trip.missed[kind] or 0) + 1
                    ns.left[kind] = ns.Interval(kind)
                end
            elseif ns.due[kind] then
                TryShow(kind)
            else
                ns.left[kind] = (ns.left[kind] or ns.Interval(kind)) - dt
                if ns.left[kind] <= 0 then TryShow(kind) end
            end
        end
    end
end

local function Loop()
    ns.Tick()
    C_Timer.After(1, Loop)
end

---------------------------------------------------------------------------
-- Reminder outcomes (called by the reminder window)
---------------------------------------------------------------------------
function ns.Done(kind)
    if kind == "squat" then
        ns.Record("squat", ns.db.squat.reps)
    else
        ns.Record("eye")
    end
    ns.Reset(kind)
end

function ns.Snooze(kind)
    ns.Reset(kind, ns.db.snooze * 60)
end

function ns.Skip(kind)
    ns.RecordSkip()
    ns.Reset(kind)
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
local function SaveClock()
    local db = ns.db
    db.clock = { at = time(), eye = ns.left.eye, squat = ns.left.squat }
end

local function RestoreClock()
    local c = ns.db.clock
    local away = c and c.at and (time() - c.at) or math.huge
    for _, kind in ipairs(ns.KINDS) do
        -- a short /reload or relog keeps the countdown; a longer break resets it
        local left = c and tonumber(c[kind])
        if away < ns.AWAY_RESET and left then
            ns.Reset(kind, math.max(1, math.min(left, ns.Interval(kind))))
        else
            ns.Reset(kind)
        end
    end
end

local function Init()
    RonisHealthDB = RonisHealthDB or {}
    local db = RonisHealthDB
    Fill(db, DEFAULTS)
    db.stats = db.stats or {}
    db.stats.total = db.stats.total or {}
    db.stats.today = db.stats.today or {}
    ns.db = db
    -- keep stored values inside the current limits
    db.eye.interval = Clamp(db.eye.interval, ns.LIMITS.eyeInterval)
    db.squat.interval = Clamp(db.squat.interval, ns.LIMITS.squatInterval)
    db.squat.reps = Clamp(db.squat.reps, ns.LIMITS.reps)
    db.snooze = Clamp(db.snooze, ns.LIMITS.snooze)
    if not ns.LEVELS[db.squat.level] then db.squat.level = DEFAULTS.squat.level end
    if not ns.MOVES[db.squat.move] then db.squat.move = DEFAULTS.squat.move end
    Stats()
    RestoreClock()
    -- a run in progress survives a /reload; an old one is forgotten
    local c = db.clock
    if db.trip and c and c.at and time() - c.at < ns.AWAY_RESET and type(db.trip.missed) == "table" then
        ns.trip = db.trip
    else
        db.trip = nil
    end
end

---------------------------------------------------------------------------
-- Settings helpers (used by the options window and slash commands)
---------------------------------------------------------------------------
function ns.SetInterval(kind, minutes)
    local lim = kind == "eye" and ns.LIMITS.eyeInterval or ns.LIMITS.squatInterval
    local old = ns.Interval(kind)
    ns.db[kind].interval = Clamp(minutes, lim)
    -- keep the time already played: shorten or lengthen what is left
    local played = old - (ns.left[kind] or old)
    ns.left[kind] = math.max(1, ns.Interval(kind) - played)
end

function ns.SetEnabled(kind, on)
    ns.db[kind].enabled = on and true or false
    if on then ns.Reset(kind) else
        ns.due[kind] = nil
        if ns.trip then ns.trip.missed[kind] = 0 end -- turned off: not missed
        ns.HideReminder(kind)
    end
end

-- Pick a fitness level: sets its move and reps.
function ns.SetLevel(key)
    local lvl = ns.LEVELS[key]
    if not lvl then return end
    local sq = ns.db.squat
    sq.level, sq.move, sq.reps = key, lvl.move, lvl.reps
end

function ns.SetReps(n)
    ns.db.squat.reps = Clamp(n, ns.LIMITS.reps)
end

function ns.SetMove(key)
    if ns.MOVES[key] then ns.db.squat.move = key end
end

function ns.Pause(minutes)
    ns.pausedUntil = GetTime() + minutes * 60
    for _, kind in ipairs(ns.KINDS) do ns.HideReminder(kind) end
end

function ns.Resume()
    ns.pausedUntil = 0
end

-- "25 min" / "1 h 12 min"
function ns.Duration(sec)
    local m = math.floor(math.max(0, sec or 0) / 60 + 0.5)
    if m < 60 then return ("%d min"):format(m) end
    return ("%d h %d min"):format(math.floor(m / 60), m % 60)
end

-- "12:05" style countdown
function ns.Clock(sec)
    sec = math.max(0, math.floor(sec or 0))
    return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
    "/health - open the options window",
    "/health eye | squat - show that reminder now",
    "/health pause <minutes> - no reminders for a while (default 60)",
    "/health resume - end a pause",
    "/health status - time until each reminder",
    "/health stats - breaks taken today and in total",
}

function ns.StatusLines()
    local out = {}
    if ns.Paused() then
        out[#out + 1] = "Paused for " .. ns.Clock(ns.pausedUntil - GetTime()) .. " more."
    end
    for _, kind in ipairs(ns.KINDS) do
        local name = ns.TEXT[kind].name
        if not ns.Enabled(kind) then
            out[#out + 1] = name .. ": off"
        elseif ns.Showing(kind) then
            out[#out + 1] = name .. ": showing now"
        elseif ns.trip then
            out[#out + 1] = ("%s: held in %s, %d missed so far"):format(
                name, ns.trip.name, ns.trip.missed[kind] or 0)
        elseif ns.due[kind] then
            out[#out + 1] = name .. ": due, waiting until combat ends"
        else
            out[#out + 1] = name .. ": in " .. ns.Clock(ns.left[kind])
        end
    end
    return out
end

function ns.StatsLines()
    local s = Stats()
    local t, a = s.today, s.total
    return {
        ("Today: %d eye breaks, %d squat breaks (%d reps), %d skipped, %d missed in dungeons."):format(
            t.eye or 0, t.squat or 0, t.reps or 0, t.skipped or 0, t.missed or 0),
        ("All time: %d eye breaks, %d squat breaks (%d reps)."):format(a.eye or 0, a.squat or 0, a.reps or 0),
    }
end

local function Slash(msg)
    local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "options" or cmd == "config" then
        ns.ToggleOptions()
    elseif cmd == "eye" or cmd == "squat" then
        ns.ShowReminder(cmd)
    elseif cmd == "pause" then
        local m = tonumber(arg) or 60
        ns.Pause(m)
        ns.Print(("Paused for %d minutes. /health resume ends it."):format(m))
    elseif cmd == "resume" then
        ns.Resume()
        ns.Print("Reminders are back on.")
    elseif cmd == "status" then
        for _, l in ipairs(ns.StatusLines()) do ns.Print(l) end
    elseif cmd == "stats" then
        for _, l in ipairs(ns.StatsLines()) do ns.Print(l) end
    else
        for _, l in ipairs(HELP) do ns.Print(l) end
    end
end

SLASH_RONISHEALTH1 = "/health"
SLASH_RONISHEALTH2 = "/ronishealth"
SlashCmdList.RONISHEALTH = Slash

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        Init()
        C_Timer.After(1, Loop)
    elseif event == "PLAYER_LOGOUT" then
        if ns.db then SaveClock() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- a reminder on screen when a fight starts steps aside until it ends
        for _, kind in ipairs(ns.KINDS) do
            if ns.Showing(kind) then
                ns.HideReminder(kind)
                ns.due[kind] = true
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- give looting a moment before popping up
        C_Timer.After(3, ns.Tick)
    end
end)
