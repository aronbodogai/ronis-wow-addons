-- Roni's Health - bedtime.
--
-- At the wind-down time (22:30 by default) one card says not to start a new
-- dungeon. Inside a dungeon or raid it waits until you come out. From
-- bedtime (23:00) a card asks you to log off, and comes back every 10
-- minutes after you close it. "Not tonight" stops all of it until tomorrow.
--
-- Times are your computer's clock. A night runs from noon to 06:00, so
-- times after midnight belong to the evening before.
local ADDON, ns = ...

ns.BED_REPEAT = 10 * 60 -- seconds between bedtime cards after you close one
ns.MORNING = 6 * 60     -- reminders stop at 06:00

local wasInside       -- were in a dungeon or raid during wind-down
local nextBed = 0     -- GetTime() when the next bedtime card may show

-- Minutes since noon (22:30 = 630), so a night does not wrap at midnight.
local function SinceNoon(minuteOfDay) return (minuteOfDay - 720) % 1440 end
ns.SinceNoon = SinceNoon

local function Now()
    local t = date("*t")
    return t.hour * 60 + t.min
end

-- The evening's date: 01:00 on the 18th still belongs to the night of the 17th.
function ns.NightID()
    return date("%Y-%m-%d", time() - 12 * 3600)
end

-- "22:30" or "10:30 PM", following the game's clock setting.
function ns.TimeText(minuteOfDay)
    local h, m = math.floor(minuteOfDay / 60) % 24, minuteOfDay % 60
    local h24 = true
    if C_CVar and C_CVar.GetCVarBool then
        local ok, v = pcall(C_CVar.GetCVarBool, "timeMgrUseMilitaryTime")
        if ok and v == false then h24 = false end
    end
    if h24 then return ("%d:%02d"):format(h, m) end
    local h12 = h % 12
    if h12 == 0 then h12 = 12 end
    return ("%d:%02d %s"):format(h12, m, h < 12 and "AM" or "PM")
end

local function InDungeon()
    if not IsInInstance then return false end
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid") or false
end

-- "Not tonight"
function ns.DismissBedtime()
    ns.db.bedtime.dismissed = ns.NightID()
    ns.HideReminder("bed")
end

-- "OK" on a bedtime card: back in 10 minutes
function ns.BedtimeOK(variant)
    if variant == "bed" or variant == "late" then nextBed = GetTime() + ns.BED_REPEAT end
end

-- Called every second by the core's clock.
function ns.WatchBedtime()
    local b = ns.db.bedtime
    if not b.enabled then return end
    local night = ns.NightID()
    if b.dismissed == night then return end
    local now = Now()
    local nm = SinceNoon(now)
    local wind, bed = SinceNoon(b.windDown), SinceNoon(b.bed)
    if nm < wind or nm >= SinceNoon(ns.MORNING) then
        wasInside = nil
        return
    end

    if nm < bed then
        -- wind-down: say it once, and again when you come out of a dungeon
        if InDungeon() then
            wasInside = true
            return
        end
        if ns.InCombat() then return end
        if b.windShown ~= night then
            b.windShown = night
            ns.ShowBedtime(wasInside and "back" or "wind", now)
        elseif wasInside then
            ns.ShowBedtime("back", now)
        end
        wasInside = nil
        return
    end

    -- bedtime: a card, and again every 10 minutes after you close it
    wasInside = nil
    if ns.InCombat() or ns.Showing("bed") and ns.BedVariant() ~= "wind" and ns.BedVariant() ~= "back" then return end
    if GetTime() < nextBed then return end
    ns.ShowBedtime(nm - bed < 5 and "bed" or "late", now)
    nextBed = math.huge -- until the card is closed
end
