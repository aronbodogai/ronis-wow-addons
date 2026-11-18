# Roni's AddOns

Personal World of Warcraft (WoW Forever client, Interface 16001) addons.
Only folders starting with `Ronis` are tracked; every other addon in this
directory is third-party and ignored by `.gitignore`.

## RonisItemPedia — "Roni's ItemPedia"

A Factoriopedia-style item window.

- **Alt + Left-Click** an item anywhere (bags, bank, character sheet, loot,
  vendors, chat links, quest rewards, auction rows, Bagnon...) to inspect it.
  Action bar buttons are skipped because Alt-click there is self-cast.
- Left: search box (finds any item by name or ID) plus **Bags / Quests / Recent** item grids.
- Right: header, then sections:
  - **Created by**: every recipe that makes the item (reagents -> product), with
    skill levels and where to learn it (recipe item and its vendor, or the nearest trainers)
  - **Teaches**: for patterns/plans/formulas, the recipe they teach
  - **Used in**: every recipe that uses the item, grouped by profession
  - **Required for quests**: quests needing the item, with level, zone, giver and map button
  - **Dropped by**: NPCs with rank, level, zone, distance and drop chance (when known)
  - **Contained in**, **Gathered from**, **Sold by** (nearest first), **Quest reward**
  - Map button on NPC/object rows: Questie pins every spawn and the world
    map opens on the nearest one
  - **Properties** (quality, type, ilvl, stack size, vendor price, Auctionator
    price, how many you own) and the full tooltip **Description**
- Every icon is clickable; back/forward buttons (or mouse buttons 4/5) walk
  your browsing history. Shift-click an icon to link it in chat.

Data sources:
- Recipes: `Data/Recipes.lua`, generated from the WoW Forever client's own
  DB2 tables by `tools/gen_recipes.js` (see the header of that file).
  Season of Discovery leftovers in the client data are listed in
  `tools/sod_leftovers.txt` and skipped.
- Drops, vendors, containers, gathering nodes and quest rewards are read live
  from QuestieDB (installed with Questie) when it is loaded. Questie only ships
  drop chances for quest-related items, so most drops show no percentage.

Commands: `/pedia` toggles, `/pedia <item link | id | name>` opens an item,
`/pedia reset` recenters the window.

Regenerating recipes after a game patch:

    # download CSVs for SkillLineAbility, SkillLine, SpellReagents, SpellEffect from
    # https://wago.tools/db2/<Table>/csv?build=<build> into a folder, then:
    node RonisItemPedia/tools/gen_recipes.js <csv-folder> <build> > RonisItemPedia/Data/Recipes.lua
    node RonisMailMats/tools/gen_reagents.js > RonisMailMats/Data/Reagents.lua

## RonisMailMats — "Roni's MailMats"

Mails reagents to the alt who can use them.

- On login every character records its professions (and ranks) under its
  full name: Forever characters have a first name and a surname, and mail
  needs both. Alts saved by a version before 0.6 are marked "surname
  unknown" until they log in once.
- Opening a mailbox docks a panel to the right of the mail window listing
  your other characters on the same realm and faction, with a
  **Send <profession> mats (N)** button per crafting profession.
- Clicking a button switches to the Send Mail tab, fills in the recipient
  and subject and attaches up to 12 matching stacks from your bags. Nothing
  is sent: review the draft and press Send yourself. If more stacks remain,
  press the button again after sending.
- Hover a button to see which items and how many would be attached.
- **Keep mats for my own professions** (on by default) never drafts items
  the current character uses for its own professions. **Choose** picks
  which professions count: by default the main crafting professions,
  Lockpicking and Comprehension do; Cooking, First Aid and Poisons do not
  (otherwise Linen Cloth for bandages would never reach your tailor). Hover
  a Send button to see what is held back and why.
- Rogue alts with **Lockpicking** get a **Send lockboxes** button (lockboxes,
  junkboxes, locked chests), mage alts with **Comprehension** a **Send
  scrolls** button (the Forever mage scrolls). The tooltip marks items above
  the alt's current skill with "(needs N)"; they are still sent.
- **Gear upgrades:** every character also records the item level it wears
  in each slot. Gear in your bags that an alt can wear now (level, its
  class's best armor type, a weapon type the class can learn, no off-hand
  while it wields a two-hander) and that has a higher item level than what
  the alt wears there:
  - gets a mail icon on its bag slot (Bagnon and the default bags),
  - shows "Upgrade for <alt> (+N item level)" in its tooltip,
  - is drafted by the alt's **Send upgrades (N)** button, which only appears
    when there is something to send.
  Bind-on-pickup and soulbound items are never counted. Item level is the
  only measure; stats are not compared.
  - Gear the alt can wear within a few levels counts too (default 3): its
    tooltip says "Upgrade for <alt> at level N", and the Send upgrades
    tooltip marks it "(level N)". `/mailmats ahead <levels>` changes how
    far ahead to look; `/mailmats ahead 0` only counts gear wearable now.
- **Other recipients** (friends, guildies, anyone): **Add a recipient...**
  on the panel opens an editor with a name and a checkbox per category
  (every profession's mats, lockboxes, scrolls). Each recipient gets one
  **Send all to <name> (N)** button that drafts everything they want in one
  mail. Right-click the button to change it; the **X** next to the name
  removes the recipient.
  - The editor suggests people when adding a new recipient: friends (online
    first), Battle.net friends playing on this realm and faction, people you
    mailed (the last 15 sends are remembered), senders in your open inbox,
    and guild members. Your own characters and existing recipients are left
    out. Clicking a suggestion fills in the name; a mage also gets scrolls
    ticked and a rogue lockboxes.

- **Groups window** (minimap button, or `/mailmats groups [group]`): every
  group (each profession's mats, lockboxes, scrolls, your own groups) with
  its items, a page at a time. Remove an item with its **X**; add one by
  dropping it on the window or typing its id, link or name. Edited built-in
  groups show in gold and have **Reset to default**. **New group** makes a
  group of your own (blue), which you can give to recipients like any
  other; **Delete group** removes it and takes it off every recipient.
  Drag the minimap button to move it; `/mailmats minimap` hides or shows it.
- **Waylaid Supplies and Waylaid Crates** go to the profession that fills
  them: the crafter of what they ask for (Journeyman Fabrics: Tailoring and
  Leatherworking; Apprentice Parts: Engineering), or for raw materials the
  profession of their type (cloth Tailoring, leather Leatherworking, ore and
  bars Mining, herbs Alchemy, dust and shards Enchanting). The list
  (`Data/Crates.lua`, 134 crates) is generated from the client's own data by
  `tools/gen_crates.js` (needs Item, ItemSparse, ItemXItemEffect,
  ItemEffect, SpellReagents and Spell CSVs from wago.tools).
- **BoE green weapons and armor** go to Enchanting, to be disenchanted,
  unless one is an upgrade for one of your alts (then it goes to that alt).
  Bind-on-pickup and soulbound items never count. `/mailmats greens off`
  stops it.
  - Greens mailed to another player (a recipient, not one of your own
    characters) ask cash on delivery: by default 100% of their vendor
    price. The **Greens COD** button on the panel cycles off / 25% / 50% /
    75% / 100% / 150% / 200% (left-click up, right-click down), or use
    `/mailmats cod <percent>` / `/mailmats cod off`. Other items in the
    same mail are not charged.
- **Mail history:** every item you send, or take from the mailbox, is
  logged (who, what, how many, when). `/mailmats history` or **Mail
  history** on the MailMats tab opens a dashboard of what went to (or came
  from) other players: per item and per person, for the last day, 7 days,
  30 days, 6 months, year and all time. Your own characters are left out
  unless you tick **Include my alts**.
- **Random subjects:** every draft gets a random subject for what it
  holds (12 per profession, skill, upgrades, class reagents and mixed
  mails), from `Data/Subjects.lua`.
- **Random messages (off by default):** `/mailmats message on` or the
  checkbox on the MailMats tab adds one of 100 messages to the mail
  body, in 20 tones (pirate, grumpy dwarf, secret agent, cozy grandma,
  corporate memo...), with the recipient's first name and what is sent
  filled in. **New message** on the panel rolls another one. Text you typed
  yourself is never replaced. A mail with a message is not deleted when
  you take its attachments, so it stays in the inbox until you delete it,
  and a full inbox queues new mail. The
  messages were written by four Claude models (Haiku, Sonnet, Opus, Fable),
  25 each, and live in `tools/messages/*.json`; regenerate with
  `node RonisMailMats/tools/gen_messages.js > RonisMailMats/Data/Messages.lua`,
  which also checks length, characters and placeholders.
- Windows have a solid background. Like the world map, the mailbox panel
  and the Groups window fade while you move (unless the mouse is over
  them) and turn solid again when you stop.

"Mats" for a profession are all items used as a reagent by any of its
recipes (`Data/Reagents.lua`, generated from RonisItemPedia's recipe database
by `tools/gen_reagents.js`). Soulbound and locked stacks are skipped.

Commands: `/mailmats` lists known characters, `/mailmats forget <name>`,
`/mailmats ignore <item>` / `unignore <item>` / `ignored` to keep specific
items out of drafts. `/mailmats target <first last>: tailoring, scrolls` adds or changes a recipient,
`/mailmats untarget <first last>` removes one, `/mailmats targets` lists them.
`/mailmats scan` re-reads this character's
professions; `/mailmats selftest` checks the client API the addon needs and
shows what it reads.

Professions are read with `GetProfessions` / `GetProfessionInfo` (the
Forever client has no Classic `GetSkillLineInfo`), keyed by skill line ID so
the client language does not matter. Lockpicking (633) and Comprehension
(3012) are not professions; they are read with
`C_SkillInfo.GetSkillLineInfoByID`. `/mailmats selftest` prints that call's
raw fields for both.

Tests: `cd RonisMailMats/tests && npm install && npm test`. The addon runs
in a Lua VM (fengari) against a mocked client (`wowmock.lua`); the mock may
only define functions that exist on the Forever client, checked against
Ketho/BlizzardInterfaceResources (branch `forever`, cached in
`tests/.cache`, `REFRESH_API=1` to re-download). The same suite runs in
GitHub Actions (`.github/workflows/test-mailmats.yml`).

Regenerating after the recipe database changes:

    node RonisMailMats/tools/gen_reagents.js > RonisMailMats/Data/Reagents.lua

Lockboxes and scrolls (`Data/SkillItems.lua`) come from the client's
ItemSparse and Lock tables:

    # download ItemSparse and Lock CSVs from https://wago.tools/db2/<Table>/csv?build=<build>, then:
    node RonisMailMats/tools/gen_skill_items.js <csv-folder> <build> > RonisMailMats/Data/SkillItems.lua

## RonisHealth — "Roni's Health"

Optional dependency: **OneForAll** (`## OptionalDeps: OneForAll`), for
flight times. Without it flights are estimated from their length.

Break reminders while you play. Timers count play time only: they stop
while you are flagged AFK (option) or paused, and an open reminder stops
its own clock until you answer it.

- **Eye breaks (20-20-20)**, every 20 minutes (10–60): look at something
  at least 6 m (20 ft) away for 20 seconds, then a few slow, full blinks.
  **Start 20 s** counts the break down on the card and counts it as done.
  Going AFK (the game's flag, after 5 minutes without input) restarts the
  eye timer and closes an open eye card; squat timers only pause.
- **Squat breaks**, every 40 minutes (20–90): a level sets the move and reps
  (Gentle: 5 chair stands; Standard: 10 squats; Strong: 15 squats; Athletic:
  20 slow squats); the move (calf raises, supported mini-squats, chair
  stands, squats, slow squats) and reps (5–20) can then be changed.
- Each card: title, what to do, a one-line reason, **More** for the longer
  explanation (`Data/Texts.lua`), and Start/Done, Snooze, Skip. Cards stack
  at the top of the screen; drag one to move them, **Reset position** in
  the options puts them back.
- Due in combat: waits until combat ends (+3 s). A card open when a fight
  starts hides and returns afterwards.
- **Dungeons and raids** (on by default, option "Hold reminders in dungeons
  and raids, sum up after"): no cards pop up inside. The clocks keep
  running and every interval that runs out counts as missed. On leaving,
  one **Back from <instance>** card says how long you were in and what you
  missed ("missed 2 eye breaks and 1 squat break"), with an **Eye break
  now** / **Squat break now** button per missed reminder and **Dismiss**.
  Missed reminders' clocks restart on leaving; a /reload inside keeps the
  run. Missed breaks count in the stats.
- **Smart timing** (`Moments.lua`, each part can be switched off under
  Smart timing in the options):
  - *Natural pauses*: boarding a flight (`UnitOnTaxi`); sitting down, caught
    when it happens (no stand-state API exists, so: hooks on
    `C_ChatInfo.PerformEmote` SIT/KNEEL/SLEEP and `SitStandOrDescendStart`,
    not while mounted/flying/swimming; moving, STAND or combat clears it);
    `IsResting()` switching on while standing still (the sleeping bag's
    rested spot; ignored 15 s after a loading screen); and buffs: campfire
    (Cozy Fire / Campfire / Camp Chair), Well-Rested, Food/Drink. This brings a break forward once 3/4 of its
    interval has passed. Early cards have **Not now** (clock untouched,
    not a skip, no early offer of it for 5 min). Flights under 40 s are ignored.
  - *Calm moments*: a break due right after a fight or quest turn-in waits
    until you have been calm for 10 s + 5 s per fight/turn-in in the last
    5 minutes (max 45 s), but never more than 5 minutes past due.
  - *Why now*: a green first line on each card ("You took a flight (about
    3:00 last time)...", "You were busy when this came due...").
  - *Weekly progression*: squats show a range, (R-2)-R at first (8-10 at
    Standard). A week with 5+ squat breaks and at most one skip per two
    done steps it up (+1 bottom, +1.5 top: 9-12, 10-13, top capped at 25);
    a week with more skips than breaks steps it down. Choosing a level or
    reps starts over.
  - *Reps fit the pause*: the flight time comes from OneForAll when it is
    installed (`OneForAll.FlightTimeTo(slot)`, which uses the client's
    flight path data and the flights you take); otherwise straight-line hop
    yards (`C_TaxiMap.GetAllTaxiNodes` positions via
    `C_Map.GetWorldPosFromMapPos`) / 22 yd/s + 5 s per hop. A flight also
    ends on PLAYER_CONTROL_GAINED or when you slow below 20 yd/s after flying
    fast, because `UnitOnTaxi` can stay true after landing. A crafting queue
    (`C_TradeSkillUI.CraftRecipe` with a count of 2+) lasts count x cast
    time (`UnitCastingInfo` at the first cast) + 0.5 s per gap; 40 s or
    more counts as a natural pause. With ~15 s to
    stand up and the move's pace (2-5 s/rep), a flight with room for two
    full sets and 30 s rest gets 2 x top; otherwise one set.
- **Bedtime** (`Bedtime.lua`, on by default; `/health bed on|off`):
  at the wind-down time (22:30) one card: no new dungeon, queue crafting,
  brush teeth / shower. In a dungeon or raid it waits until you leave, and
  coming out of another one before bedtime shows it again. From bedtime
  (23:00) a card that returns 10 minutes after each **OK**; **Not tonight**
  stores the night (`RonisHealthDB.bedtime.dismissed`). Local computer
  time; a night runs noon to 06:00 so after-midnight times still count.
  Waits for combat to end. Times 19:00-02:00 in 15-minute steps, 12/24 h
  per `timeMgrUseMilitaryTime`.
- A /reload or relog within 5 minutes keeps the countdowns; a longer
  break starts them fresh. Stats per day and all time (`/health stats`).

Commands: `/health` options, `/health eye|squat` show now, `/health pause
<minutes>`, `/health resume`, `/health status`, `/health stats`.

Texts follow the research behind the addon and avoid claims stronger than
it supports: the 20-20-20 rule is recommended by the AOA and AAO but its
evidence is modest (Talens-Estarelles et al. 2023, Contact Lens & Anterior
Eye, doi:10.1016/j.clae.2022.101744; Johnson & Rosenfield 2023, Optom Vis
Sci 100(1):52); "blink 20 times" has no source, so the card asks for a few
complete blinks. Squat breaks are based on small one-day lab trials of
3-minute bouts every 20–45 minutes (Dempsey et al. 2016, Diabetes Care,
doi:10.2337/dc15-2336; Dunstan et al. 2012; Thosar et al. 2015) and the
WHO 2020 guidance to replace sitting with activity of any intensity; the
levels are chosen by effort, not age or weight (NHS strength exercises,
ACSM/AHA). Tests: `cd RonisHealth/tests && npm install && npm test`
(same harness as MailMats, `.github/workflows/test-health.yml`).

## Shared minimap button and options window (`RonisHub.lua`)

Every addon ships an identical `RonisHub.lua` (the Health tests fail if the
copies differ; the Health workflow runs when any copy changes). It is a
small versioned library on the global `RonisHub`: the newest copy loaded
replaces the functions, and the window and button are built at login.

- One minimap button (`RonisHubMinimapButton`): click toggles the window,
  drag moves it. Position and "hidden" are written to `db.hub` of every
  registered addon, so they survive uninstalling any one of them.
- The window (`RonisHubFrame`) has a tab per known addon (`Hub.KNOWN`):
  Health, ItemPedia, MailMats. An addon joins with
  `RonisHub:Register(key, { db = savedVars, build = function(page) ... return height end })`;
  `build` runs on first view. Unregistered tabs are disabled; hovering says
  "Not installed" or, when `C_AddOns.DoesAddOnExist` finds the folder,
  "turned off in the AddOns list". Long pages scroll with the mouse wheel.
- Helpers for pages: `RonisHub:Label`, `:Button`, `:Check`, `:Stepper`
  (checks and steppers re-read their value whenever the page is shown).
- To change it: edit `RonisHealth/RonisHub.lua`, raise `VERSION`, copy it
  to the other addon folders.
- `.github/scripts/check-hub.sh` (the Lint workflow, every push and pull
  request) fails when a copy differs, a .toc does not load it, or it
  changed without a higher `VERSION`. Locally:
  `bash .github/scripts/check-hub.sh origin/main`.

## Guides site

`site/` is a plain HTML site (no build step) published to
https://aronbodogai.github.io/ronis-wow-addons/ by `.github/workflows/pages.yml`
on every push to main that touches it. GIFs go in `site/media/`.

## Releasing

Each addon is its own download with its own CurseForge and Wago project,
built by `.github/workflows/release.yml` with the BigWigsMods packager
(config: `<Addon>/.pkgmeta`). The tag prefix picks the addon:

1. Add a `## vX.Y.Z` section to the addon's `CHANGELOG.md`.
2. `git tag itempedia-vX.Y.Z && git push origin itempedia-vX.Y.Z`
   (or `mailmats-vX.Y.Z`, `health-vX.Y.Z`)

The version in game and on the project pages is the part after the prefix.
Uploads need the `CF_API_KEY` / `WAGO_API_TOKEN` repository secrets and the
`X-Curse-Project-ID` / `X-Wago-ID` lines in the addon's toc. Running the
workflow by hand only builds the zip and attaches it to the run.

Project page text: `<Addon>/docs/DESCRIPTION.md`. Setup steps and the GIF
shot list: `RonisItemPedia/docs/SHOTLIST.md`.

Until v0.5.0 both addons shipped together as "Roni's One For All" (with a
small `RonisOneForAll` hub addon for `/roni`); that bundle is retired.
