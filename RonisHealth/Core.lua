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
    smart = {
        moments = true,  -- flights, crafting, sitting, sleeping bags, eating: a nearly due break comes early
        calm = true,     -- a break due while you are busy waits for a calm moment (up to 5 min)
        progress = true, -- the squat range grows a little each week you keep up
    },
    -- bedtime: wind-down card (no new dungeon), then bedtime every 10 min
    bedtime = { enabled = false, windDown = 22 * 60 + 30, bed = 23 * 60 },
    -- weekly squat progression: step 0 = the reps you picked
    prog = { step = 0, done = 0, skipped = 0 },
}
ns.DEFAULTS = DEFAULTS

-- Limits for the options window and slash commands.
ns.LIMITS = {
    eyeInterval = { 10, 60, 5 },   -- min, max, step (minutes)
    squatInterval = { 20, 90, 5 },
    reps = { 5, 20, 1 },
    snooze = { 1, 15, 1 },
    -- bedtime times in minutes since noon: 19:00 to 02:00, 15 min steps
    bedTime = { 7 * 60, 14 * 60, 15 },
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
-- ns.waited[kind] seconds a due reminder has waited so far
-- ns.snoozed[kind] true when the running countdown is a snooze
ns.left, ns.due, ns.waited, ns.snoozed = {}, {}, {}, {}
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
    ns.due[kind], ns.waited[kind], ns.snoozed[kind] = nil, nil, nil
end

---------------------------------------------------------------------------
-- Squat reps: a range that grows week by week, scaled to the time you have
---------------------------------------------------------------------------
ns.WEEK = 7 * 24 * 3600
ns.REPS_CAP = 25

-- The current range: lo-hi reps ("8-10"). Step 0 is the picked reps R as
-- (R-2)-R; each step adds 1 to the bottom and about 1.5 to the top.
function ns.RepRange()
    local r = ns.db.squat.reps
    if not ns.db.smart.progress then return r, r end
    local step = ns.db.prog.step or 0
    local hi = math.min(ns.REPS_CAP, r + math.ceil(step * 1.5))
    local lo = math.min(hi, math.max(1, r - 2 + step))
    return lo, hi
end

-- Reps for a pause of `window` seconds (a flight), or the range when the
-- length is unknown. Returns lo, hi, rounds. About 15 s go on standing up;
-- room for two full sets plus 30 s rest gives two rounds (3-minute bouts
-- are what the studies used).
function ns.RepsFor(window)
    local lo, hi = ns.RepRange()
    if not window then return lo, hi, 1 end
    local pace = ns.MOVES[ns.db.squat.move].pace or 3
    local avail = window - 15
    if avail >= 2 * hi * pace + 30 then return hi, hi, 2 end
    if avail >= hi * pace then return hi, hi, 1 end
    local n = math.max(lo, math.floor(avail / pace))
    return n, n, 1
end

local function StartWeek()
    local p = ns.db.prog
    p.since, p.done, p.skipped = time(), 0, 0
end

-- Once a week: kept up (5+ squat breaks, at most one skip per two done)
-- means one step up; skipping more than doing means one step down.
function ns.CheckProgress()
    local p = ns.db.prog
    if not p.since then StartWeek() return end
    if time() - p.since < ns.WEEK then return end
    local oldLo, oldHi = ns.RepRange()
    if ns.db.smart.progress then
        if p.done >= 5 and p.skipped * 2 <= p.done then
            if oldHi < ns.REPS_CAP then p.step = (p.step or 0) + 1 end
        elseif p.skipped > p.done and (p.step or 0) > 0 then
            p.step = p.step - 1
        end
    end
    StartWeek()
    local lo, hi = ns.RepRange()
    if lo ~= oldLo or hi ~= oldHi then
        ns.Print(("New week: squat breaks are now %d-%d %s (were %d-%d)."):format(
            lo, hi, ns.MOVES[ns.db.squat.move].unit, oldLo, oldHi))
    end
end

-- Picking a level or rep count starts the progression over.
function ns.ResetProgress()
    ns.db.prog.step = 0
    StartWeek()
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

-- A reminder ran out: show it, or let it wait for combat to end or (when
-- you are busy questing) for a calm moment, at most ns.CALM_GRACE.
local function TryShow(kind, dt)
    if ns.due[kind] then ns.waited[kind] = (ns.waited[kind] or 0) + dt end
    local waited = ns.waited[kind] or 0
    if ns.Blocker() then
        ns.due[kind] = true
        return
    end
    local busy = ns.db.smart.calm and ns.Busy()
    if busy and waited < ns.CALM_GRACE then
        ns.due[kind] = true
        ns.waited[kind] = waited
        return
    end
    local ctx = { elapsed = ns.Elapsed(kind), snoozed = ns.snoozed[kind] }
    if busy then
        ctx.forced = waited
    elseif waited >= 15 then
        ctx.calm = waited
    end
    ns.due[kind], ns.waited[kind] = nil, nil
    ns.ShowReminder(kind, ctx)
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

    ns.WatchBedtime()

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
                TryShow(kind, dt)
            else
                ns.left[kind] = (ns.left[kind] or ns.Interval(kind)) - dt
                if ns.left[kind] <= 0 then
                    ns.left[kind] = 0
                    TryShow(kind, 0)
                end
            end
        end
    end

    -- flights, crafting, sitting, sleeping bags, food: a nearly due break comes early
    if not ns.trip then ns.WatchMoments() end
end

local function Loop()
    ns.Tick()
    C_Timer.After(1, Loop)
end

---------------------------------------------------------------------------
-- Reminder outcomes (called by the reminder window)
---------------------------------------------------------------------------
-- reps: what the card asked for (squats)
function ns.Done(kind, reps)
    if kind == "squat" then
        ns.Record("squat", reps or ns.db.squat.reps)
        ns.CheckProgress()
        ns.db.prog.done = (ns.db.prog.done or 0) + 1
    else
        ns.Record("eye")
    end
    ns.Reset(kind)
end

function ns.Snooze(kind)
    ns.Reset(kind, ns.db.snooze * 60)
    ns.snoozed[kind] = true
end

function ns.Skip(kind)
    ns.RecordSkip()
    if kind == "squat" then
        ns.CheckProgress()
        ns.db.prog.skipped = (ns.db.prog.skipped or 0) + 1
    end
    ns.Reset(kind)
end

-- An early break offered at a natural pause was turned down: nothing is
-- counted and its regular clock keeps running.
-- For a few minutes after that, sitting down again does not offer it again.
function ns.NotNow(kind)
    ns.notNowUntil[kind] = GetTime() + ns.NOT_NOW_QUIET
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
    db.flights, db.taxiSpeed = nil, nil -- flight times come from OneForAll now
    for _, k in ipairs({ "windDown", "bed" }) do
        local v = tonumber(db.bedtime[k]) or DEFAULTS.bedtime[k]
        db.bedtime[k] = (Clamp(ns.SinceNoon(v), ns.LIMITS.bedTime) + 720) % 1440
    end
    if ns.SinceNoon(db.bedtime.bed) <= ns.SinceNoon(db.bedtime.windDown) then
        db.bedtime.bed = (db.bedtime.windDown + 15) % 1440
    end
    db.prog.step = math.max(0, math.floor(tonumber(db.prog.step) or 0))
    Stats()
    ns.CheckProgress()
    RestoreClock()
    -- a tab in the shared Roni's addons window and its minimap button
    RonisHub:Register("health", { db = db, build = ns.BuildOptions })
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
    ns.ResetProgress()
end

function ns.SetReps(n)
    ns.db.squat.reps = Clamp(n, ns.LIMITS.reps)
    ns.ResetProgress()
end

function ns.SetMove(key)
    if ns.MOVES[key] then ns.db.squat.move = key end
end

-- Bedtime times, as minutes of the day. Bedtime stays after wind-down.
function ns.SetBedTime(key, minuteOfDay)
    local b = ns.db.bedtime
    b[key] = (Clamp(ns.SinceNoon(minuteOfDay), ns.LIMITS.bedTime) + 720) % 1440
    local wind, bed = ns.SinceNoon(b.windDown), ns.SinceNoon(b.bed)
    if bed <= wind then
        if key == "windDown" then b.bed = (b.windDown + 15) % 1440 else b.windDown = (b.bed - 15) % 1440 end
    end
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
    "/health test - wind the clocks to 3/4 to try natural pauses",
    "/health bed on | off - bedtime reminders (/health bed shows one)",
}

function ns.StatusLines()
    local out = {}
    if ns.Paused() then
        out[#out + 1] = "Paused for " .. ns.Clock(ns.pausedUntil - GetTime()) .. " more."
    end
    local b = ns.db.bedtime
    if b.enabled then
        out[#out + 1] = ("Bedtime: wind down at %s, bed at %s%s"):format(ns.TimeText(b.windDown),
            ns.TimeText(b.bed), b.dismissed == ns.NightID() and " (off for tonight)" or "")
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
        elseif ns.due[kind] and ns.InCombat() then
            out[#out + 1] = name .. ": due, waiting until combat ends"
        elseif ns.due[kind] then
            out[#out + 1] = ("%s: due, waiting for a calm moment (at most %s more)"):format(
                name, ns.Clock(ns.CALM_GRACE - (ns.waited[kind] or 0)))
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

-- "This week: 8-10 squats, 3 done, 1 skipped. Next step at 5 done."
function ns.ProgressLine()
    if not ns.db.smart.progress then return "Weekly progression is off." end
    local p = ns.db.prog
    local lo, hi = ns.RepRange()
    local line = ("This week: %d-%d %s, %d done, %d skipped."):format(
        lo, hi, ns.MOVES[ns.db.squat.move].unit, p.done or 0, p.skipped or 0)
    if hi >= ns.REPS_CAP then return line .. " Top of the range: try a harder move." end
    return line .. " 5 done (and few skips) moves it up next week."
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
    elseif cmd == "bed" or cmd == "bedtime" then
        local b = ns.db.bedtime
        if arg == "on" or arg == "off" then
            b.enabled = arg == "on"
            ns.Print("Bedtime reminders " .. (b.enabled and "on." or "off."))
        else
            ns.ShowBedtime("wind", b.windDown)
        end
    elseif cmd == "test" then
        -- for trying smart timing: wind both clocks to 3/4 so the next
        -- flight, campfire, sleeping bag or meal brings the breaks up
        for _, kind in ipairs(ns.KINDS) do
            if ns.Enabled(kind) and not ns.Showing(kind) then
                ns.Reset(kind, math.floor(ns.Interval(kind) * (1 - ns.EARLY_SHARE)))
            end
        end
        ns.Print("Both breaks are now 3/4 of the way through. Take a flight, sit at a campfire, "
            .. "lie on your sleeping bag or eat to see them come early. /health status shows the clocks.")
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
