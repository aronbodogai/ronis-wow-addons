# Roni's Health

## Unreleased

- **One minimap button for all Roni's addons.** Click it for a window with a
  tab per addon. Tabs of Roni's addons you don't have are greyed out;
  hovering one says whether it is not installed or turned off.
  `/health` opens the Health tab.
- **Bedtime** (off by default: options or `/health bed on`). At 22:30 one
  card says not to start a new dungeon and to switch to easy stuff: queue up
  some crafting, brush your teeth or shower while it runs. Inside a dungeon
  or raid it waits until you come out. From 23:00 a bedtime card comes back
  every 10 minutes after you close it; **Not tonight** stops it until the
  next evening. Both times can be changed (19:00 to 02:00) and follow the
  game's 12/24-hour clock setting.

## v0.3.0

- **Natural pauses:** taking a flight, sitting down (/sit, /kneel, /sleep or
  the sit key), lying on a sleeping bag, sitting at a campfire or sitting
  down to eat or drink brings a break forward once 3/4 of its interval has
  passed. Sitting is caught the moment it happens; the sleeping bag by its
  rested spot switching on while you stand still. An early card has **Not now**,
  which leaves the regular clock alone and is not offered again for 5 minutes.
- **Calm moments:** a break that comes due while you are fighting and
  handing in quests waits until you have been out of combat for a bit
  (longer the busier you were), at most 5 minutes.
- **Why now:** every card starts with one line on what brought it up.
- **Weekly progression:** squats show a range (8-10 at Standard). Each week
  with 5+ breaks and few skips adds to it (9-12, 10-13, ...); a week of
  mostly skips steps it back. Picking a level or rep count starts over.
- **Long crafting queues:** queuing 2 or more crafts that will take 40 s or
  more counts as a natural pause too ("You queued up crafting (40 crafts,
  about 2:20)").
- **Reps fit the pause:** a long pause gets two rounds, a short one a single
  set, under 40 s no card. Flight times come from the OneForAll addon when
  it is installed (new optional dependency), otherwise from the route's
  length; crafting time from the queue.
- Flights are noticed reliably even when the game keeps the taxi flag up
  after landing.
- Options: a Smart timing section to switch each of these off.

## v0.2.0

- **Dungeon and raid summary:** reminders are held inside dungeons and
  raids (now on by default). Leaving shows one "Back from <instance>" card
  with how long you were in and which breaks you missed, plus a button to
  take each one now. Missed breaks count in the stats.

## v0.1.0

First release.

- **Eye breaks (20-20-20):** every 20 minutes of play a small card asks you
  to look at something at least 6 m (20 ft) away for 20 seconds and blink
  slowly a few times. **Start 20 s** counts the break down for you.
- **Squat breaks:** every 40 minutes a card asks for a short set of squats.
  Pick a level (Gentle 5 chair stands, Standard 10 squats, Strong 15,
  Athletic 20 slow squats), then change the move and reps to suit you.
- Every card has a one-line reason and a **More** button with the longer
  explanation, what the evidence does and does not show, and safety notes.
- Reminders wait until combat ends, the clock stops while you are AFK, and
  a short /reload keeps the countdown. Snooze, skip, pause, daily stats.
