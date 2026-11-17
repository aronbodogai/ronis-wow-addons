-- Roni's Health - every text the reminders show.
--
-- Written from the research notes behind this addon (see README "Sources").
-- Rules for editing: no claim stronger than the studies, no "prevents",
-- "cures" or "proven". Plain ASCII only (the game fonts lack some symbols).
local ADDON, ns = ...

local GREY, GOLD, R = "|cff9d9d9d", "|cffffd100", "|r"

local function H(s) return GOLD .. s .. R end

---------------------------------------------------------------------------
-- Squat moves, easiest first
---------------------------------------------------------------------------
ns.MOVE_ORDER = { "calf", "mini", "chair", "squat", "slow" }
ns.MOVES = {
    calf = {
        name = "Calf raises",
        pace = 2, -- seconds per rep, to fit reps into a flight
        unit = "calf raises",
        short = "No squat: stand holding your desk, rise onto your toes, lower slowly. For sore knees or a tight space.",
        how = "Stand holding your desk or a chair back. Rise slowly onto your toes, then lower your heels back down.",
    },
    mini = {
        name = "Supported mini-squats",
        pace = 3, -- seconds per rep, to fit reps into a flight
        unit = "supported mini-squats",
        short = "Hands on a chair back or desk, bend your knees only as far as is comfortable.",
        how = "Rest your hands on a chair back or your desk. Bend your knees as far as is comfortable, keeping them in line with your toes, then come up squeezing your buttocks.",
    },
    chair = {
        name = "Chair stands",
        pace = 3, -- seconds per rep, to fit reps into a flight
        unit = "chair stands",
        short = "Sit-to-stand from a sturdy chair without wheels. Stand up using your legs, then sit down slowly.",
        how = "Sit on the edge of a sturdy chair without wheels, feet hip-width apart. Lean slightly forward and stand up using your legs, then sit back down slowly.",
    },
    squat = {
        name = "Bodyweight squats",
        pace = 3, -- seconds per rep, to fit reps into a flight
        unit = "squats",
        short = "Sit back and down as if onto a chair, go as low as is comfortable, push up through your whole foot.",
        how = "Feet hip- to shoulder-width apart. Sit back and down as if onto a chair, chest up, knees following your toes. Go as low as is comfortable and push up through your whole foot.",
    },
    slow = {
        name = "Slow squats",
        pace = 5, -- seconds per rep, to fit reps into a flight
        unit = "slow squats (3 s down)",
        short = "Bodyweight squats taking about 3 seconds on the way down. For people who exercise regularly.",
        how = "A bodyweight squat, but take about 3 seconds on the way down and come up under control. Go only as deep as you can keep good form.",
    },
}

---------------------------------------------------------------------------
-- Fitness levels: a starting move and rep count. Pick by how it feels,
-- not by age or weight; you can change the move and reps afterwards.
---------------------------------------------------------------------------
ns.LEVEL_ORDER = { "gentle", "standard", "strong", "athletic" }
ns.LEVELS = {
    gentle = {
        name = "Gentle", move = "chair", reps = 5,
        desc = "5 chair stands. For limited mobility, joint pain, balance worries or if 5 stands without your arms is hard.",
    },
    standard = {
        name = "Standard", move = "squat", reps = 10,
        desc = "10 bodyweight squats. A good start for most adults. Should feel easy to moderate: you can still talk.",
    },
    strong = {
        name = "Strong", move = "squat", reps = 15,
        desc = "15 bodyweight squats. If 10 feels very easy. Still a break, not a workout: you can talk but not sing.",
    },
    athletic = {
        name = "Athletic", move = "slow", reps = 20,
        desc = "20 slow squats. For people who train regularly. Drop back if it feels hard, hurts or makes you dizzy.",
    },
}

---------------------------------------------------------------------------
-- Reminder texts
---------------------------------------------------------------------------
ns.TEXT = {}

ns.TEXT.eye = {
    name = "Eye breaks (20-20-20)",
    icon = "Interface\\Icons\\Spell_Holy_MindVision",
    Title = function() return "Eye break: 20-20-20" end,
    Action = function()
        return "Look at something at least 6 m (20 ft) away for 20 seconds. Then blink slowly and fully a few times."
    end,
    why = "Looking far away lets the muscles that focus your eyes up close relax, and screens make you blink less.",
    More = function()
        return table.concat({
            H("What it does"),
            "Up close, small muscles inside and around your eyes work to focus and turn them inward. "
                .. "At about 6 m (20 ft) the eye is focused near its resting point, so they can relax. "
                .. "The rule is a simple way to remember regular short breaks; the numbers are a rule of thumb, not exact science.",
            "",
            H("How good is the evidence?"),
            "Eye-care bodies (American Optometric Association, American Academy of Ophthalmology) recommend it. "
                .. "In a 2023 study, two weeks of reminder software reduced eye strain and dry-eye symptoms, "
                .. "but the benefit was gone a week after the reminders stopped. Another lab study found no "
                .. "difference between break schedules. So: it helps comfort for some people, it does not prevent eye disease.",
            "",
            H("Why blink?"),
            "People blink much less while looking at a screen (one study: about 18 times a minute down to 4), and many "
                .. "blinks are only half-closed, so the eye surface dries. A few slow, complete blinks with a gentle squeeze "
                .. "spread the tear film again. The popular \"blink 20 times\" has no study behind the number; a few full blinks will do.",
            "",
            H("Other things that help"),
            "Screen about an arm's length away (50-70 cm), its centre a little below eye level, no glare from windows "
                .. "or lamps. Lubricating eye drops can ease dryness. If your eyes still bother you, see an optometrist: "
                .. "you may need glasses for screen distance.",
        }, "\n")
    end,
}

ns.TEXT.squat = {
    name = "Squat breaks",
    icon = "Interface\\Icons\\Spell_Nature_Strength",
    Title = function(db, ctx)
        local lo, hi, rounds = ns.RepsFor(ctx and ctx.window)
        local unit = ns.MOVES[db.squat.move].unit
        if rounds > 1 then return ("Squat break: %d x %d %s"):format(rounds, hi, unit) end
        if lo == hi then return ("Squat break: %d %s"):format(hi, unit) end
        return ("Squat break: %d-%d %s"):format(lo, hi, unit)
    end,
    Action = function(db, ctx)
        local _, _, rounds = ns.RepsFor(ctx and ctx.window)
        local s = ns.MOVES[db.squat.move].how .. " Stand up slowly first."
        if rounds > 1 then s = s .. " Rest about 30 seconds between the rounds." end
        return s
    end,
    why = "Using your leg muscles between long stretches of sitting lowers blood sugar after meals and keeps blood flowing in your legs.",
    More = function()
        return table.concat({
            H("What it does"),
            "Your thigh and buttock muscles are the biggest in your body. Working them pulls sugar out of the blood. "
                .. "In a study of adults with type 2 diabetes, 3 minutes of half-squats and calf raises every 30 minutes "
                .. "lowered the rise in blood sugar after meals by about 40% compared with sitting straight through. "
                .. "Sitting for an hour also reduced how well the main leg artery widens; short movement breaks prevented that.",
            "",
            H("How good is the evidence?"),
            "These are small, one-day lab studies, mostly in people who were overweight or had diabetes; one trial in lean "
                .. "young adults found no blood sugar benefit. Your break is "
                .. "shorter than the 3-minute bouts studied, so think of it as a regular nudge, not a treatment. The WHO "
                .. "says replacing sitting with activity of any intensity, even light, benefits health. Studies used breaks "
                .. "every 20 to 45 minutes; 40 sits in that range, and shorter is fine too.",
            "",
            H("Why the number grows"),
            "With weekly progression on, the range goes up a little each week you keep up "
                .. "(5 or more breaks, few skips): 8-10, then 9-12, then 10-13. Muscles adapt to a load "
                .. "they are used to, so exercise guidelines raise it gradually (the ACSM's progression "
                .. "principle). Skipping more than you do brings it back down; picking a level or rep count "
                .. "starts over. On a flight the reps fit the flight: a long one gets two rounds.",
            "",
            H("Good form"),
            "Knees follow your toes (passing your toes is fine). Back straight, chest up. Go only as low as is "
                .. "comfortable. Breathe out on the way up; do not hold your breath. It should feel easy to moderate: you can still talk.",
            "",
            H("Stay safe"),
            "After a long session, pump your calves a few times and stand up slowly; sit back down if you feel light-headed. "
                .. "Achy knees or knee arthritis: exercise is a recommended treatment, so use a chair or desk for support "
                .. "and keep it pain-free; sharp pain means stop. Stop if you feel chest pain, unusual breathlessness, "
                .. "palpitations or faintness.",
        }, "\n")
    end,
}

---------------------------------------------------------------------------
-- "Why now": one line on top of a card saying what brought it up.
-- ctx = { moment, window, estimated, early, elapsed, calm, forced, snoozed }
---------------------------------------------------------------------------
local MOMENT = {
    flight = "You took a flight",
    campfire = "You sat down at the campfire",
    bedroll = "You lay down on your sleeping bag",
    food = "You sat down to eat or drink",
    sit = "You sat down",
    lie = "You lay down",
}

local BREAK_NAME = { eye = "eye break", squat = "squat break" }

function ns.WhyNow(kind, ctx)
    if not ctx then return nil end
    local since = ctx.elapsed and ns.Duration(ctx.elapsed)
    if ctx.moment then
        local s = MOMENT[ctx.moment] or "You are taking a pause"
        if ctx.moment == "flight" and ctx.window then
            s = s .. (ctx.estimated and " (about %s by its length)" or " (about %s last time)"):format(ns.Clock(ctx.window))
        end
        s = s .. ": the game does not need you for a bit."
        if ctx.early and since then
            s = s .. (" %s since your last %s, so it comes a little early."):format(since, BREAK_NAME[kind])
        end
        return s
    end
    if ctx.forced then
        return ("Due %s ago. You have been busy, so it waited as long as it could; a minute now still counts.")
            :format(ns.Duration(ctx.forced))
    end
    if ctx.calm then
        return "You were busy when this came due, so it waited for a calm moment."
    end
    if ctx.snoozed then return "You snoozed this one; time is up." end
    if since then return ("%s of play since your last %s."):format(since, BREAK_NAME[kind]) end
    return nil
end

ns.TEXT.timing = H("Why now?") .. "\n" .. "Cards come at natural pauses (flights, campfires, sleeping bags, eating) and wait "
    .. "for a calm moment when you are busy, up to 5 minutes. Interruptions at a break point in a task are "
    .. "less disruptive than in the middle of one (Adamczyk and Bailey, 2004), and linking a habit to a moment "
    .. "that happens anyway helps it become automatic (Gardner, Lally and Wardle, 2012)."

-- Shown after leaving a dungeon or raid with "quiet in instances" on.
local function Plural(n, one) return ("%d %s%s"):format(n, one, n == 1 and "" or "s") end

ns.TEXT.summary = {
    icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    Title = function(trip) return "Back from " .. trip.name end,
    Action = function(trip)
        local parts = {}
        if (trip.missed.eye or 0) > 0 then parts[#parts + 1] = Plural(trip.missed.eye, "eye break") end
        if (trip.missed.squat or 0) > 0 then parts[#parts + 1] = Plural(trip.missed.squat, "squat break") end
        return ("You were inside for %s and missed %s."):format(
            ns.Duration((trip.stop or time()) - trip.start), table.concat(parts, " and "))
    end,
    why = "No need to make them all up: one break now, after a long stretch of sitting and focusing, is what helps.",
}

ns.TEXT.disclaimer = GREY .. "General wellbeing suggestions, not medical advice. Pregnant, recovering from surgery or injury, "
    .. "or told to limit exercise? Ask your doctor or physio first, and pick Gentle or turn squats off." .. R
