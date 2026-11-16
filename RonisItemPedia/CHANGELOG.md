# Roni's ItemPedia

Released as part of Roni's One For All since v0.5.0 (see
`RonisOneForAll/CHANGELOG.md`).

## v0.4.0

- New **Required for quests** section: every quest that asks for the item,
  with quest level, required level, zone and quest giver. Quests your
  faction cannot take are hidden, ones you already finished are greyed out
  and listed last.
- Map button on each quest: pins the quest giver and opens the world map.
- Recipes show their skill levels (learn, yellow, green, grey) and whether
  you already know them.
- **Learn from** under each recipe in Created by: the recipe item with its
  nearest vendor (or how it drops), or the nearest trainers of your faction
  for trainer recipes, each with a map button.
- **Quest reward** rows now show level, required level, zone and quest
  giver, with a map button to the giver. Other-faction quests are hidden.

## v0.3.0

First public release.

- **Alt + Left-Click** any item (bags, bank, character sheet, loot, vendors,
  chat links, quest rewards, Bagnon...) to open a Factoriopedia-style item window.
- **Created by** and **Used in**: every WoW Forever profession recipe (2212),
  taken from the game client's own data. Patterns, plans and formulas show
  the recipe they **Teach**.
- **Dropped by**, **Contained in**, **Gathered from**, **Sold by** and
  **Quest reward** from Questie's database (Questie recommended), sorted
  nearest first with distance, drop chance when Questie knows it, and a
  map button that pins every spawn and opens the world map.
- Properties (vendor price, Auctionator price, how many you own...) and the
  full item tooltip.
- Clickable icons everywhere, back/forward history (mouse buttons 4/5),
  search, Bags and Recent lists. `/pedia` toggles the window.
