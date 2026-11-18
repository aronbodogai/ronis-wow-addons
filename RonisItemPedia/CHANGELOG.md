# Roni's ItemPedia

## Unreleased

- **One minimap button for all Roni's addons.** Click it for a window with a
  tab per addon. Tabs of Roni's addons you don't have are greyed out;
  hovering one says whether it is not installed or turned off.
  The ItemPedia tab opens the item window and resets its position.

## v0.6.0

Roni's MailMats is its own download again. Since v0.5.0 this project shipped
the "Roni's One For All" bundle (ItemPedia, MailMats and the `/roni`
helper); from now on it contains only Roni's ItemPedia. If you use MailMats,
install it from its own project page.

- The search box finds any item in the game, not only the ones in your bags
  or Recent list. Matches from the open tab come first.
- New **Quests** tab: the tradable items the quests in your quest log ask
  for, so you can check whether you can buy them. Hover one to see which
  quest needs it.
- New **Reagent for spells** section: class spells that use the item, such as
  Water Walking (Fish Oil) or the warlock spells that use a Soul Shard.
- Items the game has not sent details for yet show their name and every
  section right away instead of "Retrieving item info...". Items that are
  not in the WoW: Forever data at all say so.
- If one section fails to draw, the others still show and the error is
  printed in chat.

## v0.5.0

Released as part of Roni's One For All.

- Fixed: the v0.4.0 download also contained the MailMats folder inside the
  ItemPedia folder. It was never loaded; it is now its own proper folder.

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
