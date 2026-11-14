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
