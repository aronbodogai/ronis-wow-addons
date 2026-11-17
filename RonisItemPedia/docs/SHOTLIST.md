# Project page: setup and GIF shot list

## Project pages (one time, in the web UI)

Each addon has its own project.

- **Roni's ItemPedia**: CurseForge project 1804431, Wago bGoYgo60. Name
  **Roni's ItemPedia**. Summary: *Alt-click any item for its recipes, drops,
  vendors and quests, with map pins. Made for WoW: Forever.* Paste
  `RonisItemPedia/docs/DESCRIPTION.md` into the description editor.
- **Roni's MailMats**: create a new project on CurseForge and on Wago. Name
  **Roni's MailMats**. Summary: *Open a mailbox and send each alt the
  reagents it can use in one click. Made for WoW: Forever.* Paste
  `RonisMailMats/docs/DESCRIPTION.md` into the description editor, then add
  the new IDs to `RonisMailMats/RonisMailMats.toc` as
  `## X-Curse-Project-ID: <id>` and `## X-Wago-ID: <id>`.
- Upload each GIF in the editor and swap it in for the `GIF-...` placeholder
  with the same number (1 to 4 on ItemPedia, 5 on MailMats).
- Delete the stray alpha file `RonisOneForAll-v0.4.0-2-gf20b7a7-forever.zip`
  from the ItemPedia project's Files tab on both sites (a test build that
  uploaded by mistake).

## Recording

ScreenToGif or ShareX (free). Capture only the addon window, not the full
screen: about 800 px wide, 15 fps, 3 to 6 seconds per clip. UI scale normal,
nameplates and chat spam hidden. Keep each GIF under about 5 MB.

## The five clips

1. **ITEMPEDIA-OPEN** (hero, top of the page): bags open, Alt + Left-Click
   Linen Cloth, the window opens. Scroll slowly through Used in and Dropped by.
2. **RECIPES**: open Crocolisk Steak. Hold on Created by so the skill numbers
   and the Learn from line are readable, then click the recipe item icon to
   jump to its page.
3. **MAP**: on any item's Sold by or Dropped by, click the map button; the
   world map opens with the pin.
4. **QUESTS**: an item with several quests (Linen Cloth, Wool Cloth or a
   common quest mat). Show Required for quests, click a quest's map button.
5. **MAILMATS**: open a mailbox with mats in your bags. Hover a Send button
   (tooltip lists the items), click it, the Send Mail tab fills in.

## Guides site

The same GIFs go in `site/media/` with these names: itempedia-open.gif (1),
itempedia-recipes.gif (2), itempedia-map.gif (3), itempedia-quests.gif (4),
mailmats.gif (5). Commit and push; the site redeploys by itself. Until a file
exists its spot on the page stays hidden.

## Logo

Square 400x400 PNG. Simplest fitting option: the book icon the addons use
(INV_Misc_Book_09) on a dark background with "Roni's" in the orange title
color (#FF8C1A).
