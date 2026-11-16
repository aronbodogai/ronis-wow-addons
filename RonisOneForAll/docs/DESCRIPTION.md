![Roni's ItemPedia: Alt-click an item, see everything about it](GIF-1-ITEMPEDIA-OPEN)

Roni's One For All
==================

Small, focused addons for WoW: Forever that answer the questions you keep
alt-tabbing for. Where does this drop? What do I craft with it? Which alt
needs these mats? One download, every addon in its own folder, so you can
turn off any of them in the AddOns list.

**Made for WoW: Forever.** Type `/roni` in game to see what is installed.

**Full guides:** [aronbodogai.github.io/ronis-wow-addons](https://aronbodogai.github.io/ronis-wow-addons/)

Roni's ItemPedia
----------------

Alt + Left-Click any item and a window opens with everything about it. It
works on your bags, bank, character sheet, loot, vendors, chat links, quest
rewards, auction rows and bag addons like Bagnon. Every icon in the window is
clickable, so you can follow a material from the mob that drops it to the
thing you craft with it, and go back and forward with your mouse's side
buttons.

**Recipes.** Created by and Used in list every profession recipe in the game,
read from the game client's own data, not from what you happened to open.
Each recipe shows its skill levels in the profession window's colors, whether
you already know it, and where you learn it: the recipe item and its nearest
vendor, or the nearest trainers of your faction.

![Created by with skill levels and Learn from](GIF-2-RECIPES)

**Where it comes from.** Dropped by, Gathered from, Sold by and Quest reward,
nearest first, with the distance from where you stand and the drop chance when
it is known. Every row has a map button that pins the spot and opens your
world map there.

![Map button pins the nearest vendor](GIF-3-MAP)

**Quests.** Required for quests lists every quest that asks for the item,
with its level, zone and quest giver. Quests your faction cannot take are
hidden, and the ones you already finished are greyed out.

![Required for quests](GIF-4-QUESTS)

Roni's MailMats
---------------

Open a mailbox and a panel docks next to it with your alts. Each alt gets a
**Send Tailoring mats** (or Alchemy, Mining, ...) button that fills in the
name and attaches the reagents that alt can use. Nothing is sent until you
press Send yourself, so you always see the draft first.

Mats your current character needs for its own professions stay in your bags.
Lockboxes go to your rogue, scrolls to your mage, and gear in your bags that
is an upgrade for an alt gets a little mail icon on its bag slot. Friends and
guildies can be recipients too, and so can groups of them.

![MailMats panel drafting a mail](GIF-5-MAILMATS)

Commands
--------

| Command | What it does |
|---|---|
| `/roni` | List the installed Roni's addons and how to use them |
| `/pedia` | Open or close the ItemPedia window |
| `/pedia <item link or ID>` | Look up an item |
| `/pedia reset` | Put the ItemPedia window back in the middle of the screen |
| `/mailmats` | List your characters and their professions |
| `/mailmats groups` | Open the recipient groups window |

Good to know
------------

Mob drops, vendors, spawn locations and quests come from **Questie**. With
Questie installed you get the full ItemPedia; without it you still get every
recipe, the item's properties and its tooltip. Auctionator prices show up when
Auctionator is installed.

The map button cannot open the world map during combat, because the game
does not allow it.

Source code and issues:
[github.com/aronbodogai/ronis-wow-addons](https://github.com/aronbodogai/ronis-wow-addons)
