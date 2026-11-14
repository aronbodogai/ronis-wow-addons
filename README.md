# Roni's AddOns

Personal World of Warcraft (WoW Forever client, Interface 16001) addons.
Only folders starting with `Ronis` are tracked; every other addon in this
directory is third-party and ignored by `.gitignore`.

## RonisItemPedia — "Roni's ItemPedia"

A Factoriopedia-style item window.

- **Alt + Left-Click** an item anywhere (bags, bank, character sheet, loot,
  vendors, chat links, quest rewards, auction rows, Bagnon...) to inspect it.
  Action bar buttons are skipped because Alt-click there is self-cast.
- Left: search box plus **Bags / Recent** item grids.
- Right: header, then sections:
  - **Created by**: every recipe that makes the item (reagents -> product)
  - **Teaches**: for patterns/plans/formulas, the recipe they teach
  - **Used in**: every recipe that uses the item, grouped by profession
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

## RonisMailMats — "Roni's MailMats"

Mails reagents to the alt who can use them.

- On login every character records its professions (and ranks).
- Opening a mailbox docks a panel to the right of the mail window listing
  your other characters on the same realm and faction, with a
  **Send <profession> mats (N)** button per crafting profession.
- Clicking a button switches to the Send Mail tab, fills in the recipient
  and subject and attaches up to 12 matching stacks from your bags. Nothing
  is sent: review the draft and press Send yourself. If more stacks remain,
  press the button again after sending.
- Hover a button to see which items and how many would be attached.
- **Keep mats for my own professions** (on by default) never drafts items
  the current character can use for its own professions.

"Mats" for a profession are all items used as a reagent by any of its
recipes (`Data/Reagents.lua`, generated from RonisItemPedia's recipe database
by `tools/gen_reagents.js`). Soulbound and locked stacks are skipped.

Commands: `/mailmats` lists known characters, `/mailmats forget <name>`,
`/mailmats ignore <item>` / `unignore <item>` / `ignored` to keep specific
items out of drafts.

Regenerating after the recipe database changes:

    node RonisMailMats/tools/gen_reagents.js > RonisMailMats/Data/Reagents.lua

## Releasing

Releases are built by `.github/workflows/release-itempedia.yml` with the
BigWigsMods packager (config: `RonisItemPedia/.pkgmeta`).

1. Add a `## vX.Y.Z` section to `RonisItemPedia/CHANGELOG.md`.
2. `git tag vX.Y.Z && git push origin vX.Y.Z`

The zip always goes to GitHub Releases. CurseForge and Wago uploads need the
`CF_API_KEY` / `WAGO_API_TOKEN` repository secrets and the
`X-Curse-Project-ID` / `X-Wago-ID` lines in `RonisItemPedia.toc`.
