-- Specs for Roni's Health. Each login is a fresh mocked client session;
-- saved variables are carried between sessions like the real client does.
return function(T)
    local test, eq, ok, contains = T.test, T.eq, T.ok, T.contains
    local MIN = 60

    local function Click(btn) btn:Click() end
    local function Card(S, kind) return T.Card(S, kind) end

    -----------------------------------------------------------------------
    -- Timing
    -----------------------------------------------------------------------
    test("eye reminder shows after 20 minutes of play, not before", function()
        local S = T.Login()
        S.Advance(20 * MIN - 3)
        ok(not T.Shown(S, "eye"), "eye card hidden at 19:57")
        S.Advance(4)
        ok(T.Shown(S, "eye"), "eye card shown at 20:01")
        ok(not T.Shown(S, "squat"), "squat card not yet")
        eq(#S.sounds, 1, "one sound")
        eq(S.flashes, 1, "taskbar flash")
    end)

    test("squat reminder shows after 40 minutes and stacks under the eye card", function()
        local S = T.Login()
        S.Advance(40 * MIN + 2)
        ok(T.Shown(S, "eye"), "eye card still waiting")
        ok(T.Shown(S, "squat"), "squat card shown")
        local p = Card(S, "squat")._points[1]
        ok(p[5] < 0, "squat card placed below the eye card")
        eq(Card(S, "squat").title:GetText(), "Squat break: 10 squats")
    end)

    test("an open reminder stops its own clock until answered", function()
        local S = T.Login()
        S.Advance(20 * MIN + 2)
        S.Advance(30 * MIN) -- left on screen for half an hour
        ok(T.Shown(S, "eye"), "still showing")
        Click(Card(S, "eye").skip)
        ok(not T.Shown(S, "eye"), "skipped")
        S.Advance(20 * MIN - 5)
        ok(not T.Shown(S, "eye"), "full interval after skipping")
        S.Advance(6)
        ok(T.Shown(S, "eye"), "back after 20 more minutes")
    end)

    -----------------------------------------------------------------------
    -- Card buttons
    -----------------------------------------------------------------------
    test("eye Start counts 20 seconds down, then counts the break", function()
        local S = T.Login()
        S.Advance(20 * MIN + 2)
        local c = Card(S, "eye")
        eq(c.primary:GetText(), "Start 20 s")
        Click(c.primary)
        ok(not c.primary:IsEnabled(), "button locked while counting")
        S.Advance(5)
        eq(c.primary:GetText(), "Look away... 15")
        ok(T.Shown(S, "eye"), "still showing during countdown")
        S.Advance(16)
        ok(not T.Shown(S, "eye"), "closed after 20 s")
        eq(S.ns.db.stats.today.eye, 1, "eye break counted")
        eq(S.sounds[#S.sounds], 8960, "finish sound")
    end)

    test("squat Done records the reps", function()
        local S = T.Login()
        S.ns.SetLevel("strong")
        S.Advance(40 * MIN + 2)
        Click(Card(S, "squat").primary)
        ok(not T.Shown(S, "squat"), "closed")
        eq(S.ns.db.stats.today.squat, 1)
        eq(S.ns.db.stats.today.reps, 15)
        eq(S.ns.db.stats.total.reps, 15)
    end)

    test("snooze brings the reminder back after the snooze time", function()
        local S = T.Login()
        S.Advance(20 * MIN + 2)
        eq(Card(S, "eye").snooze:GetText(), "Snooze 5 min")
        Click(Card(S, "eye").snooze)
        S.Advance(5 * MIN - 3)
        ok(not T.Shown(S, "eye"), "quiet during snooze")
        S.Advance(4)
        ok(T.Shown(S, "eye"), "back after 5 minutes")
    end)

    test("More shows the longer explanation and grows the card", function()
        local S = T.Login()
        S.Slash("/health", "eye")
        local c = Card(S, "eye")
        ok(not c.more:IsShown(), "explanation hidden at first")
        local h = c:GetHeight()
        Click(c.moreButton)
        ok(c.more:IsShown(), "explanation shown")
        ok(c:GetHeight() > h + 100, "card grew")
        eq(c.moreButton:GetText(), "Less")
        Click(c.moreButton)
        ok(not c.more:IsShown(), "hidden again")
        eq(c:GetHeight(), h, "back to its size")
    end)

    -----------------------------------------------------------------------
    -- When not to interrupt
    -----------------------------------------------------------------------
    test("a reminder due in combat waits until combat ends", function()
        local S = T.Login()
        S.Advance(19 * MIN)
        S.SetCombat(true)
        S.Advance(5 * MIN)
        ok(not T.Shown(S, "eye"), "no card in combat")
        contains(S.ns.StatusLines(), "waiting until combat ends")
        S.SetCombat(false)
        S.Advance(4)
        ok(T.Shown(S, "eye"), "shown a few seconds after combat")
    end)

    test("an open card steps aside when a fight starts and returns after", function()
        local S = T.Login()
        S.Advance(20 * MIN + 2)
        ok(T.Shown(S, "eye"))
        S.SetCombat(true)
        ok(not T.Shown(S, "eye"), "hidden in combat")
        S.Advance(MIN)
        S.SetCombat(false)
        S.Advance(4)
        ok(T.Shown(S, "eye"), "back after combat")
    end)

    test("quiet in dungeons and raids only when that option is on", function()
        local S = T.Login()
        S.SetInstance("party")
        S.Advance(20 * MIN + 2)
        ok(T.Shown(S, "eye"), "default: reminders in dungeons too")
        Click(Card(S, "eye").skip)
        S.ns.db.quietInstances = true
        S.Advance(20 * MIN + 2)
        ok(not T.Shown(S, "eye"), "quiet in the dungeon")
        S.SetInstance(nil)
        S.Advance(2)
        ok(T.Shown(S, "eye"), "shown after leaving")
    end)

    test("the clock stops while AFK and a long AFK counts as an eye break", function()
        local S = T.Login()
        S.Advance(15 * MIN)
        S.SetAFK(true)
        S.Advance(60 * MIN)
        ok(not T.Shown(S, "eye") and not T.Shown(S, "squat"), "nothing while AFK")
        S.SetAFK(false)
        S.Advance(2)
        -- eye was reset by the time away; squat kept its 25 minutes
        S.Advance(20 * MIN - 10)
        ok(not T.Shown(S, "eye"), "eye restarted from 20 minutes")
        S.Advance(25 * MIN - 20 * MIN + 12)
        ok(T.Shown(S, "squat"), "squat after 40 minutes of play")
    end)

    test("/health pause and resume", function()
        local S = T.Login()
        S.Slash("/health", "pause 30")
        S.Advance(25 * MIN)
        ok(not T.Shown(S, "eye"), "paused")
        contains(S.ns.StatusLines(), "^Paused for")
        S.Slash("/health", "resume")
        S.Advance(20 * MIN + 2)
        ok(T.Shown(S, "eye"), "running again")
    end)

    -----------------------------------------------------------------------
    -- Saved data
    -----------------------------------------------------------------------
    test("a quick /reload keeps the countdown", function()
        local S = T.Login()
        S.Advance(12 * MIN)
        local saved = T.Logout(S)
        local S2 = T.Login({ epoch = S.epoch + S.now + 30 }, saved)
        S2.Advance(8 * MIN - 5)
        ok(not T.Shown(S2, "eye"), "not early")
        S2.Advance(8)
        ok(T.Shown(S2, "eye"), "due 8 minutes after the reload")
    end)

    test("coming back after a long break starts fresh", function()
        local S = T.Login()
        S.Advance(18 * MIN)
        local saved = T.Logout(S)
        local S2 = T.Login({ epoch = S.epoch + S.now + 3600 }, saved)
        S2.Advance(10 * MIN)
        ok(not T.Shown(S2, "eye"), "full 20 minutes again")
    end)

    test("settings and stats survive relogging and stay inside the limits", function()
        local S = T.Login()
        S.ns.SetLevel("gentle")
        S.ns.SetInterval("squat", 30)
        S.ns.Record("eye")
        local saved = T.Logout(S)
        saved.RonisHealthDB.squat.reps = 99
        saved.RonisHealthDB.eye.interval = 1
        local S2 = T.Login({ epoch = S.epoch + 7200 }, saved)
        local db = S2.ns.db
        eq(db.squat.level, "gentle")
        eq(db.squat.move, "chair")
        eq(db.squat.reps, 20, "reps clamped")
        eq(db.eye.interval, 10, "interval clamped")
        eq(db.squat.interval, 30)
        eq(db.stats.total.eye, 1, "all-time stats kept")
    end)

    test("a new day starts today's stats over", function()
        local S = T.Login()
        S.ns.Record("squat", 10)
        local saved = T.Logout(S)
        local S2 = T.Login({ epoch = S.epoch + 2 * 86400 }, saved)
        eq(S2.ns.db.stats.today.squat, 0)
        eq(S2.ns.db.stats.total.squat, 1)
    end)

    -----------------------------------------------------------------------
    -- Settings
    -----------------------------------------------------------------------
    test("changing the interval keeps the time already played", function()
        local S = T.Login()
        S.Advance(15 * MIN)
        S.ns.SetInterval("eye", 30)
        S.Advance(15 * MIN - 5)
        ok(not T.Shown(S, "eye"), "not before 30 minutes in total")
        S.Advance(8)
        ok(T.Shown(S, "eye"), "due at 30 minutes")
    end)

    test("turning a reminder off hides it and stops it", function()
        local S = T.Login()
        S.Advance(20 * MIN + 2)
        S.ns.SetEnabled("eye", false)
        ok(not T.Shown(S, "eye"))
        S.Advance(60 * MIN)
        ok(not T.Shown(S, "eye"), "stays off")
        contains(S.ns.StatusLines(), "Eye breaks %(20%-20%-20%): off")
    end)

    test("options window: levels set move and reps, steppers obey limits", function()
        local S = T.Login()
        S.Slash("/health", "")
        local win = S.env.RonisHealthOptions
        ok(win:IsShown(), "window open")
        local gentle
        for _, f in ipairs(S.frames) do
            if f._type == "Button" and f._parent == win and f:GetText() == "Gentle" then gentle = f end
        end
        ok(gentle, "Gentle button")
        Click(gentle)
        eq(S.ns.db.squat.reps, 5)
        eq(S.ns.db.squat.move, "chair")
        ok(not gentle:IsEnabled(), "chosen level is greyed out")
        S.Slash("/health", "squat")
        eq(Card(S, "squat").title:GetText(), "Squat break: 5 chair stands")
        S.Slash("/health", "")
        ok(not win:IsShown(), "toggled closed")
    end)

    test("every level and move has its texts", function()
        local S = T.Login()
        for _, key in ipairs(S.ns.LEVEL_ORDER) do
            local l = S.ns.LEVELS[key]
            ok(l and l.name and l.desc and S.ns.MOVES[l.move], "level " .. key)
            ok(l.reps >= 5 and l.reps <= 20, "level reps in 5-20: " .. key)
        end
        for _, key in ipairs(S.ns.MOVE_ORDER) do
            local m = S.ns.MOVES[key]
            ok(m and m.name and m.unit and m.short and m.how, "move " .. key)
        end
    end)

    test("texts are plain ASCII and avoid overclaiming", function()
        local S = T.Login()
        local all = {}
        local function Add(s) all[#all + 1] = s end
        for _, kind in ipairs({ "eye", "squat" }) do
            local t = S.ns.TEXT[kind]
            Add(t.name); Add(t.why)
            for _, key in ipairs(S.ns.LEVEL_ORDER) do
                S.ns.SetLevel(key)
                Add(t.Title(S.ns.db)); Add(t.Action(S.ns.db)); Add(t.More(S.ns.db))
            end
        end
        Add(S.ns.TEXT.disclaimer)
        for _, l in pairs(S.ns.LEVELS) do Add(l.desc) end
        for _, m in pairs(S.ns.MOVES) do Add(m.short); Add(m.how) end
        for _, s in ipairs(all) do
            ok(not s:find("[\128-\255]"), "non-ASCII character in: " .. s)
            local low = s:lower():gsub("not prevent", "")
            for _, bad in ipairs({ "prevents? eye", "cures?", "proven", "undoes", "blue light damage" }) do
                ok(not low:find(bad), ("overclaim %q in: %s"):format(bad, s))
            end
        end
        -- the eye card asks for a few full blinks, not a count of 20
        ok(not S.ns.TEXT.eye.Action(S.ns.db):find("20 times"), "no blink count")
    end)
end
