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
        eq(Card(S, "squat").title:GetText(), "Squat break: 8-10 squats")
        eq(Card(S, "squat").reason:GetText(), "40 min of play since your last squat break.")
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
        eq(S.ns.db.stats.today.reps, 13, "the bottom of the 13-15 range")
        eq(S.ns.db.stats.total.reps, 13)
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
        ok(not T.Shown(S, "eye"), "not right after the fight")
        contains(S.ns.StatusLines(), "waiting for a calm moment")
        S.Advance(12)
        ok(T.Shown(S, "eye"), "shown once things are calm")
    end)

    test("an open card steps aside when a fight starts and returns after", function()
        local S = T.Login()
        S.Advance(20 * MIN + 2)
        ok(T.Shown(S, "eye"))
        S.SetCombat(true)
        ok(not T.Shown(S, "eye"), "hidden in combat")
        S.Advance(MIN)
        S.SetCombat(false)
        S.Advance(16)
        ok(T.Shown(S, "eye"), "back after combat")
    end)

    -----------------------------------------------------------------------
    -- Dungeons and raids
    -----------------------------------------------------------------------
    local function Buttons(card)
        local out = {}
        for _, b in ipairs(card.buttons) do out[#out + 1] = b:GetText() end
        return table.concat(out, ", ")
    end

    test("reminders are held inside a dungeon and summed up after leaving", function()
        local S = T.Login()
        S.SetInstance("party", "The Deadmines")
        S.Advance(50 * MIN)
        ok(not T.Shown(S, "eye") and not T.Shown(S, "squat"), "nothing pops up inside")
        contains(S.ns.StatusLines(), "held in The Deadmines, 2 missed so far")
        S.SetInstance(nil)
        S.Advance(2)
        ok(T.Shown(S, "summary"), "summary after leaving")
        ok(not T.Shown(S, "eye") and not T.Shown(S, "squat"), "one summary, not a pile of cards")
        local c = Card(S, "summary")
        eq(c.title:GetText(), "Back from The Deadmines")
        eq(c.action:GetText(), "You were inside for 50 min and missed 2 eye breaks and 1 squat break.")
        eq(Buttons(c), "Eye break now, Squat break now, Dismiss")
        eq(S.ns.db.stats.today.missed, 3, "missed breaks in the stats")
        Click(c.eyeButton)
        ok(T.Shown(S, "eye"), "eye card opened")
        ok(T.Shown(S, "summary"), "summary stays for the squat break")
        Click(c.squatButton)
        ok(T.Shown(S, "squat"), "squat card opened")
        ok(not T.Shown(S, "summary"), "summary closes once every break is opened")
    end)

    test("leaving restarts the missed reminders' clocks", function()
        local S = T.Login()
        S.SetInstance("raid", "Molten Core")
        S.Advance(25 * MIN)
        S.SetInstance(nil)
        S.Advance(2)
        local c = Card(S, "summary")
        eq(c.action:GetText(), "You were inside for 25 min and missed 1 eye break.")
        eq(Buttons(c), "Eye break now, Dismiss")
        Click(c.dismiss)
        ok(not T.Shown(S, "summary"), "dismissed")
        S.Advance(20 * MIN - 5)
        ok(not T.Shown(S, "eye"), "a full 20 minutes after leaving")
        S.Advance(6)
        ok(T.Shown(S, "eye"), "then the eye reminder")
    end)

    test("a short run with nothing missed shows no summary", function()
        local S = T.Login()
        S.SetInstance("party")
        S.Advance(10 * MIN)
        S.SetInstance(nil)
        S.Advance(5)
        ok(not T.Shown(S, "summary"), "no summary")
        S.Advance(10 * MIN)
        ok(T.Shown(S, "eye"), "eye clock kept running inside: due 20 minutes after login")
    end)

    test("leaving in combat holds the summary until the fight ends", function()
        local S = T.Login()
        S.SetInstance("party")
        S.Advance(21 * MIN)
        S.SetCombat(true)
        S.SetInstance(nil)
        S.Advance(MIN)
        ok(not T.Shown(S, "summary"), "not in combat")
        S.SetCombat(false)
        S.Advance(4)
        ok(T.Shown(S, "summary"), "after combat")
    end)

    test("a /reload inside the dungeon keeps the run", function()
        local S = T.Login()
        S.SetInstance("party", "Wailing Caverns")
        S.Advance(30 * MIN)
        local saved = T.Logout(S)
        local S2 = T.Login({ epoch = S.epoch + S.now + 20 }, saved)
        S2.SetInstance("party", "Wailing Caverns")
        S2.Advance(15 * MIN)
        S2.SetInstance(nil)
        S2.Advance(2)
        local c = Card(S2, "summary")
        ok(T.Shown(S2, "summary"), "summary after the reload")
        eq(c.action:GetText(), "You were inside for 45 min and missed 2 eye breaks and 1 squat break.")
    end)

    test("a turned-off reminder gets no button", function()
        local S = T.Login()
        S.SetInstance("party")
        S.Advance(45 * MIN)
        S.ns.SetEnabled("squat", false)
        S.SetInstance(nil)
        S.Advance(2)
        local c = Card(S, "summary")
        eq(c.action:GetText(), "You were inside for 45 min and missed 2 eye breaks.")
        eq(Buttons(c), "Eye break now, Dismiss")
    end)

    test("with the option off reminders show inside and there is no summary", function()
        local S = T.Login()
        S.ns.db.quietInstances = false
        S.SetInstance("party")
        S.Advance(20 * MIN + 2)
        ok(T.Shown(S, "eye"), "shown in the dungeon")
        Click(Card(S, "eye").skip)
        S.SetInstance(nil)
        S.Advance(5)
        ok(not T.Shown(S, "summary"), "no summary")
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
        eq(Card(S, "squat").title:GetText(), "Squat break: 3-5 chair stands")
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

    -----------------------------------------------------------------------
    -- Smart timing: natural pauses, calm moments, weekly progression
    -----------------------------------------------------------------------
    test("a flight brings a squat break forward after 30 of its 40 minutes", function()
        local S = T.Login({}, { RonisHealthDB = { eye = { enabled = false } } })
        S.Advance(20 * MIN)
        S.TakeFlight("Stormwind", "Sentinel Hill")
        S.Advance(2)
        ok(not T.Shown(S, "squat"), "too early at 20 min")
        S.Land()
        S.Advance(11 * MIN)
        S.TakeFlight("Sentinel Hill", "Lakeshire")
        S.Advance(2)
        ok(T.Shown(S, "squat"), "offered on a flight at 31 min")
        local c = Card(S, "squat")
        contains({ c.reason:GetText() }, "You took a flight")
        contains({ c.reason:GetText() }, "31 min since your last squat break")
        eq(c.snooze:GetText(), "Not now", "an early card can be turned down")
        ok(not c.skip:IsShown(), "no skip on an early card")
        Click(c.snooze)
        ok(not T.Shown(S, "squat"), "closed")
        eq(S.ns.db.stats.today.skipped or 0, 0, "Not now is not a skip")
        S.Land()
        S.Advance(9 * MIN + 5)
        ok(T.Shown(S, "squat"), "regular reminder still comes at 40 min")
    end)

    test("flight times are learned and set the reps: longer flight, more squats", function()
        local S = T.Login({}, { RonisHealthDB = { eye = { enabled = false } } })
        S.TakeFlight("Stormwind", "Lakeshire")
        S.Advance(3 * MIN)
        S.Land()
        S.Advance(2)
        eq(S.ns.db.flights["Lakeshire - Stormwind"], 180, "3 min route learned")
        S.TakeFlight("Goldshire", "Stormwind")
        S.Advance(60)
        S.Land()
        S.Advance(31 * MIN)
        -- same route both ways: back from Lakeshire takes about 3 min
        S.TakeFlight("Lakeshire", "Stormwind")
        S.Advance(2)
        local c = Card(S, "squat")
        eq(c.title:GetText(), "Squat break: 2 x 10 squats", "two rounds on a 3 min flight")
        contains({ c.reason:GetText() }, "about 3:00 last time")
        Click(c.primary)
        eq(S.ns.db.stats.today.reps, 20)
        S.Land()
        S.Advance(31 * MIN)
        S.TakeFlight("Stormwind", "Goldshire")
        S.Advance(2)
        eq(Card(S, "squat").title:GetText(), "Squat break: 10 squats", "one round on a 1 min flight")
    end)

    test("very short known flights do not pop up a card", function()
        local S = T.Login({}, { RonisHealthDB = { eye = { enabled = false }, flights = { ["A - B"] = 25 } } })
        S.Advance(35 * MIN)
        S.TakeFlight("A", "B")
        S.Advance(2)
        ok(not T.Shown(S, "squat"), "25 s flight skipped")
    end)

    test("campfire, sleeping bag and food say why the break came", function()
        local cases = {
            { "Cozy Fire", "You sat down at the campfire" },
            { "Well-Rested", "You lay down on your sleeping bag" },
            { "Food", "You sat down to eat or drink" },
        }
        for _, case in ipairs(cases) do
            local S = T.Login()
            S.Advance(16 * MIN)
            S.SetAuras({ "Power Word: Fortitude", case[1] })
            S.Advance(2)
            ok(T.Shown(S, "eye"), case[1] .. ": eye break at 16 of 20 min")
            ok(not T.Shown(S, "squat"), case[1] .. ": squat not near due")
            contains({ Card(S, "eye").reason:GetText() }, case[2])
        end
    end)

    test("an aura that stays on does not keep popping cards", function()
        local S = T.Login()
        S.Advance(16 * MIN)
        S.SetAuras({ "Cozy Fire" })
        S.Advance(2)
        Click(Card(S, "eye").snooze) -- Not now
        S.Advance(MIN)
        ok(not T.Shown(S, "eye"), "not offered again while still at the fire")
        eq(S.ns.AuraMoment("Fire Shield"), nil, "other fire buffs do not count")
    end)

    test("busy questing: a due break waits for a calm moment, at most 5 minutes", function()
        local S = T.Login()
        S.Advance(19 * MIN + 50)
        -- fight after fight with quests in between
        local shownAt
        for i = 1, 14 do
            S.SetCombat(true); S.Advance(15); S.SetCombat(false)
            S.TurnInQuest()
            S.Advance(10)
            if T.Shown(S, "eye") then shownAt = i break end
        end
        ok(shownAt and shownAt >= 11, "held for about 5 minutes of fighting, shown at round " .. tostring(shownAt))
        contains({ Card(S, "eye").reason:GetText() }, "You have been busy")
    end)

    test("a quiet stretch after a fight shows the waiting break with its reason", function()
        local S = T.Login()
        S.Advance(19 * MIN + 55)
        S.SetCombat(true); S.Advance(30); S.SetCombat(false)
        S.Advance(5)
        ok(not T.Shown(S, "eye"), "waits after the fight")
        S.Advance(15)
        ok(T.Shown(S, "eye"), "shown when calm")
        eq(Card(S, "eye").reason:GetText(), "You were busy when this came due, so it waited for a calm moment.")
    end)

    test("calm waiting can be turned off", function()
        local S = T.Login({}, { RonisHealthDB = { smart = { calm = false } } })
        S.Advance(19 * MIN + 55)
        S.SetCombat(true); S.Advance(10); S.SetCombat(false)
        S.Advance(4)
        ok(T.Shown(S, "eye"), "right after combat like before")
    end)

    test("squat range grows week by week when you keep up, and drops when you skip", function()
        local DAY = 24 * 3600
        local S = T.Login()
        local lo, hi = S.ns.RepRange()
        eq(lo .. "-" .. hi, "8-10", "week 1")
        for _ = 1, 5 do S.ns.Done("squat", 8) end
        local saved = T.Logout(S)
        S = T.Login({ epoch = 1800000000 + 7 * DAY + 60 }, saved)
        lo, hi = S.ns.RepRange()
        eq(lo .. "-" .. hi, "9-12", "week 2 after keeping up")
        contains(S.printLog, "now 9%-12 squats")
        for _ = 1, 5 do S.ns.Done("squat", 9) end
        saved = T.Logout(S)
        S = T.Login({ epoch = 1800000000 + 14 * DAY + 120 }, saved)
        lo, hi = S.ns.RepRange()
        eq(lo .. "-" .. hi, "10-13", "week 3")
        S.ns.Done("squat", 10)
        S.ns.Skip("squat"); S.ns.Skip("squat")
        saved = T.Logout(S)
        S = T.Login({ epoch = 1800000000 + 21 * DAY + 180 }, saved)
        lo, hi = S.ns.RepRange()
        eq(lo .. "-" .. hi, "9-12", "back down after a week of skipping")
        S.ns.SetLevel("standard")
        lo, hi = S.ns.RepRange()
        eq(lo .. "-" .. hi, "8-10", "picking a level starts over")
    end)

    test("a quiet week keeps the range; progression off shows a single number", function()
        local DAY = 24 * 3600
        local S = T.Login()
        S.ns.Done("squat", 8)
        local saved = T.Logout(S)
        S = T.Login({ epoch = 1800000000 + 8 * DAY }, saved)
        local lo, hi = S.ns.RepRange()
        eq(lo .. "-" .. hi, "8-10", "one break is not enough to go up")
        S.ns.db.smart.progress = false
        S.Slash("/health", "squat")
        eq(Card(S, "squat").title:GetText(), "Squat break: 10 squats")
    end)

    test("options window has the smart timing switches and the weekly line", function()
        local S = T.Login()
        S.Slash("/health", "")
        local texts = {}
        for _, f in ipairs(S.frames) do
            if f._type == "CheckButton" and f.Text then texts[#texts + 1] = f.Text:GetText() end
        end
        contains(texts, "natural pauses")
        contains(texts, "calm moment")
        contains(texts, "each week")
        local found
        for _, f in ipairs(S.env.RonisHealthOptions._children) do
            if f._type == "FontString" and tostring(f._text):find("This week: 8%-10 squats") then found = true end
        end
        ok(found, "weekly progress line")
    end)

    test("new texts stay plain ASCII", function()
        local S = T.Login()
        local all = { S.ns.TEXT.timing, S.ns.TEXT.squat.More(S.ns.db) }
        for _, m in ipairs({ "flight", "campfire", "bedroll", "food" }) do
            all[#all + 1] = S.ns.WhyNow("squat", { moment = m, window = 100, early = true, elapsed = 1900 })
        end
        for _, t in ipairs(all) do ok(not t:find("[\128-\255]"), "ASCII: " .. t:sub(1, 40)) end
    end)
end
