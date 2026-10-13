# ForeverCompanion

## v2.7.0

- New Professions tab in the leveling guide (/fc lvl prof, or Professions in the minimap menu):
  - The best profession pairs for your class (Skinning + Leatherworking, Mining + Blacksmithing or Engineering, Herbalism + Alchemy, Tailoring + Enchanting...) and why they go together.
  - Leveling plan from 1 to 300 for Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring, Cooking and First Aid: the cheapest recipe for each skill range, how many to craft, the materials and an estimated cost. Your current step is highlighted and the materials still needed from your skill are added up.
  - Recipes come from the trainers; when a vendor recipe is cheaper, the vendor and its place are shown for your faction. Recipes with a cooldown or a reputation requirement are left out.
  - Mining, Herbalism and Skinning: what to gather at each skill level and the zones to do it.
  - Trainer ranks (Journeyman, Expert, Artisan) with the level they need.

## v2.6.0

- Levels 1 to about 22: the leveling routes now follow the RestedXP Forever guides step by step, in their order, with quests grouped the way they do (accept everything around, do the objectives together, hand everything in at once). Credit: RXPGuides by RestedXP (https://github.com/RestedXP/RXPGuides), CC BY-NC-SA 4.0; that part of the routes keeps this licence.
- Every race and class has its own version of these guides (Orcs and Trolls through Tirisfal Glades and Silverpine Forest like RestedXP, Hunters with their own start, Night Elves to Darkshore...). About 95 % of the RestedXP quests are kept; the others are missing from the Forever quest database or placed on the wrong continent in it.
- From about level 22 to 60 the route is still computed by the simulator, starting from where the RestedXP part ends.

## v2.5.3

- Routes checked against tested leveling guides, quest by quest, for levels 1 to 22, and corrected:
  - Orcs, Trolls and Tauren no longer take the boat to Tirisfal Glades at level 3-4: they level in Durotar or Mulgore up to 12, like every guide. No route crosses the sea before level 10.
  - Every route now does its starting zone fully (all its quests) before moving on: Durotar, Mulgore, Tirisfal Glades up to 12, Elwynn Forest, Dun Morogh, Teldrassil up to 11, Zephras Isle up to 12.
  - 20 quests the database refused to some races although they get them in game are now offered (Elwynn Forest chain from Rascally Rodents for Humans, Skyborne class quests...).
  - A route chapter that ends with dungeons now shows the right levels.

## v2.5.2

- /fc lvl > Leveling route: right-click a zone to see every step of it (quest, level, quest ID, NPC to talk to and place), to check a route before playing it. Click the first line to go back.

## v2.5.1

- Quest requirements checked: a quest that needs a previous quest (all of a list, or one of several) is no longer shown to accept until that quest is turned in. When the route reaches a quest whose previous quest was passed, it passes it too and says in the chat which quest was missing (example: Aggressive Encroachment needs Aetheen of the Gales).
- The "quests around you" list uses the same requirements.

## v2.5.0

- First time a leveling route is picked for a character, a window asks: follow it, choose another start in /fc lvl, or no thanks (the step window then shows the quests around you; /fc lvl to follow a route again).
- Zephras Isle can now be left at any time by the airship of Valanaar (Dalaran for the Alliance, near Thunder Bluff for the Horde): the route says when to take it and points to the dock.
- Routes computed again for every race and class: the simulator now also tries leaving the starting area earlier (levels 6 to 12) and keeps it when the route gets faster. 26 routes are faster, 1 to 60 now in 101.6 to 109.6 hours.

## v2.4.3

- Arrow: smaller, and it no longer disappears when you get close to the quest giver. It stays on them until the quest is accepted or turned in, and its title shows the NPC's name.
- Route window: the name of the NPC to talk to is shown under the current step (and in the tooltip of the others). Long quest names no longer run into the distance.
- Quests done another way are passed: a quest whose follow-up quest is already taken or done, and a breadcrumb quest whose destination quest is already taken or done (the giver no longer offers it).
- Talking to a quest giver also passes the coming steps of that NPC whose quest they do not offer you.

## v2.4.2

- Route window made small and discreet: 250 pixels wide, thin coloured marks for each step, 3 steps by default with details only on the current one, and a single line for the best-in-slot item to pick up.
- The window fades when the mouse is elsewhere (opacity set in /fc > Leveling) and comes back on mouse-over. Click its title to fold it down to one line.

## v2.4.1

- Leveling routes: the route list of /fc lvl only shows the routes of your class (a druid could pick the warrior route and get warrior quests). A route of another class picked before is replaced by yours on its own, and the chat says which route is followed.
- A quest the giver does not offer you (another class or race, or not available yet) is passed instead of blocking the route.
- Zephras Isle and the other new zones: the arrow, the map pin and the place under each step use the zone map (no more "?").
- Dungeon quests rebuilt from the WoW Forever database (693 quests): Skyborne now see the quests of every dungeon (Ragefire Chasm: 6 quests), with the Forever givers, turn-ins and rewards. A quest done inside a dungeon now points to the dungeon entrance.
- Quests whose objectives are inside a dungeon are only done with that dungeon in the routes, and quests that need a raid or battleground quest first are left out.
- Routes computed again for every race and class (102 to 110 hours from 1 to 60) and checked one by one: right class, race and faction, quest chains in order, accept before turn-in, every step placed.
- Best gear: stats of about 1 100 more items read from the WoW Forever database (Forever changed many Classic items). Items Wowhead has no Forever data for keep their Classic stats.

## v2.4.0

- Leveling routes rebuilt on the WoW Forever quest database (4 455 quests, the new Forever quests and zones included, Skyborne too): one route for every race and class, 72 in all. Each route is simulated from 1 to 60 (walking and riding time, flight paths, boats, kill time, quest and kill experience, quest chains) and its settings are tried again and again to keep the fastest one.
- Dungeons are now steps of the routes, at the right level, with the dungeon quests to pick up before going in. A dungeon is in the route when it levels at least 75 % as fast as questing at that point (its loot makes up for the rest). Solo? Untick "Include the dungeons in the route" and they are skipped.
- Best-in-slot reminder: when an item of the best gear list for your level can be picked up (quest reward, dungeon boss, vendor, rare), the route window shows it under the steps and the chat tells you once. Click it to point the arrow there.
- Best gear lists recomputed with the WoW Forever item stats (856 items read from Wowhead's WoW Forever database), the Forever quest rewards, the new dungeon loot, the new rares and vendors.
- Dungeon guide: missing bosses added (Ragefire Chasm now has its 4 bosses: Oggleflint, Taragaman the Hungerer, Jergosh the Invoker and Bazzalan; The Stockade, Blackfathom Deeps and Razorfen Kraul completed too), the Forever loot of each boss and of the trash, dungeon quests fixed, and the Scarlet Monastery, Dire Maul and Blackrock Spire wings named.
- Themes: 8 colour themes, softer by default (Forever, Arcane, Horde, Alliance, Emerald, Classic, Midnight, your class colour), plus window size and opacity, in /fc > Appearance.

## v2.3.1

- Fixed a Lua error on the world map (Map.lua:24) that repeated while the map was open: the player coordinates were read wrong.

## v2.3.0

- Best gear: the 5 best items for each slot instead of one, best first, every 5 levels for your class and faction, each with how to get it (quest with its giver, dungeon boss, vendor or crafting). Rings and trinkets: wear the first two.
- The new WoW Forever dungeons are now in the gear lists and in the dungeon guide: Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands, City of Dalaran and The Drowned City, with their bosses, loot (stats from Wowhead's WoW Forever database) and dungeon quests with their rewards and givers. Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold and Shaper's Terrace are listed with their levels and zone; their loot is not published yet. Items without published stats are ranked from their item level and type, and marked as such.
- The entrance of the new dungeons can be shown with the arrow. A new dungeon gets its instance ID the first time you go in, so the drop collector measures its drop rates.

## v2.2.0

New leveling guide in the spirit of RestedXP (`/fc lvl`, or the minimap menu).

- Built-in leveling route from 1 to 60 for every starting area (Human, Dwarf and Gnome, Night Elf, Orc and Troll, Tauren, Undead), picked automatically from your race. About 600 quests each, in order: accept, do, turn in, travel to the next zone. The step window shows the next steps, moves on by itself when you accept, finish or turn in a quest, and the arrow points to each step. Right-click a step to skip it. The routes are computed from the quest database (levels, quest chains, distances, quest and kill experience), not written by hand: please report odd steps.
- Best gear every 5 levels (10 to 60) for your class and faction, slot by slot, with where to get each item: quest (click to point the arrow at the quest giver), dungeon boss and drop rate, vendor or crafted.
- Leveling talents: one point per level from 10 to 60 for the classic leveling build of your class (Arms, Retribution, Beast Mastery, Combat, Shadow, Enhancement, Frost, Affliction, Feral).
- Spells learned while leveling, level by level, with their cost, what you already know and what to learn now.
- Rotation for your class and level, with the next one when a key spell arrives, and tips.
- When you level up, the chat lists your new spells and the talent to take.

## v2.1.0

- Dungeon & raid guide: new Quests page for every dungeon and raid (547 quests). For each quest: who gives it and where (zone and coordinates), where to turn it in, the quest it requires, what to kill or bring, the group size, the reward choices with icons, the other rewards and the money. Buttons point the arrow at the quest giver or the turn-in. Quests already done are checked, quests in your log are marked. Shows the quests of your faction, race and class by default; one click shows them all.

## v2.0.0

The final version: economy, PvP, hardcore and five new languages.

- Economy: auction house prices from a full scan (`/fc eco scan`) and from every search you make, 14-day average, crafting cost and profit in item tooltips, vendor prices, a gold ledger by source (loot, quests, vendor, auction house, mail, repairs...), your recipes with their cost, a shopping list and a 30-day gold chart.
- PvP: battleground results, honor and honorable kills per session and per battleground, win rate, a session panel (`/fc pvp`).
- Hardcore: warnings for zones and targets too dangerous for your level and for enemy territory, a danger badge on the target, a survival panel (deaths, healing potions, bandages, food, drinks, hearthstone, durability), a pre-pull checklist and your death history (`/fc hc`).
- New menu on the minimap button: guide, next quests, economy, PvP, hardcore, characters, options (`/fc menu`).
- Now in German, Spanish, Portuguese, Italian and Russian, in addition to English and French.

## v1.2.0

New look for the whole addon: bigger text, dark panels with a cyan accent, gold titles.

- Dungeon & raid guide redesigned: sidebar with search (dungeons, bosses, items), level ranges colored for your level, boss cards with their best items, a 3D model of each boss (drag to turn it), large loot rows with icons, item type and a drop-rate bar. Home page with the dungeons for your level.
- New navigation arrow: larger, with a ring, colors from green (straight ahead) to red (behind), a glow when you are right on target and the time to arrival.
- Quest window redesigned: colored tags (pick up, do, turn in), click a quest to point the arrow at it, right-click to skip it, objectives of the current quest.
- XP window redesigned: big XP bar with rested XP, XP per hour, time to level, quests to turn in.
- Info bar with icons, characters window with cards, camp buffs panel, new addon logo.

## v1.1.0

The guide, the arrow, the quests and the map now work without any data collected first.

- Dungeon & raid guide rebuilt on a built-in database: 33 dungeons, raid wings and world bosses, every boss with level, health and loot with drop rates, and every trash monster with level, health and loot with drop rates. Rates measured in game are shown next to them.
- Quest assistant: with no written route, the XP window lists the next quests to pick up, do and turn in for your race, class, faction and level (3,000 quests), nearest first, and the arrow points to the best one.
- The arrow now works from one zone to another (world coordinates) and turns with your character.
- "Dungeon" button in the XP window and "Show the way to the entrance" in the guide point the arrow to the dungeon.
- World map icons: dungeon and raid entrances, quests to pick up (!), quests to turn in (?), objective areas, notes and camps. Click an icon to point the arrow there.
- Bags: item level, on-use/on-equip and junk markers now work with every bag window.
- Item tooltips show where an item drops and its rate.
- License changed to GPL v3 (database credits: AtlasLootClassic, CMaNGOS).

## v1.0.0

First version for the WoW Forever launch.

- XP tracker: XP/hour, time to level, rested XP, XP of quests ready to turn in.
- Optional quest automation (accept, turn in, best reward), Shift to skip.
- XP route engine by race, faction and class, with route recorder, export and import.
- Navigation arrow and `/fc way`.
- Map coordinates (world map and minimap) and personal map notes.
- Camps: camp buff timers and remembered camps.
- Alts: every character with gold, professions, lockouts, items; `/fc find`; 1-60 journeys count.
- Bags: sell junk, auto-repair, item level and on-use/on-equip markers.
- Drop collector: boss and trash drop rates measured in game, export and import.
- Dungeon & raid guide: every instance, bosses, loot, trash loot, drop rates, wishlist with alert.
- Interface: info bar, tooltips (item level, owners, drop sources), clickable web links in chat.
- Safety: death log, durability and bag warnings, rare and dangerous elite alerts.
- English and French.
