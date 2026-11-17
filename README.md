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
- **Random messages:** every draft gets one of 100 messages in the mail
  body, in 20 tones (pirate, grumpy dwarf, secret agent, cozy grandma,
  corporate memo...), with the recipient's first name and what is sent
  filled in. **New message** on the panel rolls another one. Text you typed
  yourself is never replaced. `/mailmats message off` stops it. The
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

Break reminders while you play. Timers count play time only: they stop
while you are flagged AFK (option) or paused, and an open reminder stops
its own clock until you answer it.

- **Eye breaks (20-20-20)**, every 20 minutes (10–60): look at something
  at least 6 m (20 ft) away for 20 seconds, then a few slow, full blinks.
  **Start 20 s** counts the break down on the card and counts it as done.
  Coming back from 5+ minutes AFK restarts the eye timer.
- **Squat breaks**, every 40 minutes (20–90): a level sets the move and reps
  (Gentle: 5 chair stands; Standard: 10 squats; Strong: 15 squats; Athletic:
  20 slow squats); the move (calf raises, supported mini-squats, chair
  stands, squats, slow squats) and reps (5–20) can then be changed.
- Each card: title, what to do, a one-line reason, **More** for the longer
  explanation (`Data/Texts.lua`), and Start/Done, Snooze, Skip. Cards stack
  at the top of the screen; drag one to move them, **Reset position** in
  the options puts them back.
- Due in combat: waits until combat ends (+3 s). A card open when a fight
  starts hides and returns afterwards. **No reminders in dungeons and
  raids** (off by default) holds them until you leave.
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
