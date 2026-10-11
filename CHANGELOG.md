# ForeverCompanion

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
