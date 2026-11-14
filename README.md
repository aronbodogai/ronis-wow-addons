# Roni's AddOns

Personal World of Warcraft (WoW Forever client, Interface 16001) addons.
Only folders starting with `Ronis` are tracked; every other addon in this
directory is third-party and ignored by `.gitignore`.

## RonisItemPedia — "Roni's ItemPedia"

A Factoriopedia-style item window.

- **Alt + Left-Click** an item anywhere (bags, bank, character sheet, loot,
  vendors, chat links, quest rewards, auction rows, Bagnon...) to inspect it.
  Action bar buttons are skipped because Alt-click there is self-cast.
- Left: search box plus **Bags / Recent / Recipes** item grids.
- Right: header, **Recipe** (reagents -> product), **Used in**, **Properties**
  (quality, type, ilvl, stack size, vendor price, Auctionator price, how many
  you own) and the full tooltip **Description**.
- Every icon is clickable; back/forward buttons (or mouse buttons 4/5) walk
  your browsing history. Shift-click an icon to link it in chat.
- Recipes are learned by opening profession windows (saved account-wide).

Commands: `/pedia` toggles, `/pedia <item link | id | name>` opens an item,
`/pedia reset` recenters the window, `/pedia forget` clears learned recipes.
