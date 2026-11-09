Creature Comforts v3.319 - Quality of Life Mod for Batomon Showdown
=================================================================
Creature Comforts adds helpful reminders, shop planning tools, and quality-of-life improvements to Batomon Showdown.

FEATURES
--------

WATCHLIST & SHOP HIGHLIGHTING
Track Batomon and items you want to find in the shop. Matching shop entries are automatically highlighted.
The Watchlist and Shop Highlights setting shows the Watchlist button and enables these highlights; turning it off hides both.

- Browse and select Batomon and items.
- Filter Batomon by rarity, type, and region. A specific region shows the Batomon in that region's dex; use All for special circumstances.
- Sort the list by name (alphabetical) or by rarity (lowest to highest).
- Snapshot your active team into the Watchlist.
- Use Tracked Only to quickly review and adjust selections.
- Clear every tracked entry at once with the clear button.
- Save, load, and delete builds to reuse your favorite setups.
- Watchlist selections persist between sessions.

TRINKET REMINDERS
Get reminders for timing-sensitive trinkets such as Duplicators, Treasure Map, Upgrade Disc, and Greedy Gloves. Each row shows the trinket's icon and stack count; expand the reminder panel to view their effects.

POSITIONAL TRINKET SUMMARY
A movable, collapsible panel in the shop summarizes the bonuses from your positional trinkets
(left column, top middle, right column). Passive effects and permanent battle-start effects are
listed separately, and duplicate copies are added together. The panel starts collapsed and can be
dragged anywhere on screen.

BATTLE TRINKET REWARDS
See which trinkets you gained during battle in a collapsible panel, with each trinket's icon and
stack count, sorted by quantity (highest first). The panel waits for you to be back in the shop,
so event or gift screens cannot hide it. It stays until you collapse it or start the next battle.

BATTLE STATUS DISPLAY
View your current day, remaining lives, and wins during combat. Once the Second
Chance has been used, the heart icon is shown upside down to mark your last life.

BATTLE ELAPSED TIME
After a battle finishes, a small panel shows the simulation's total elapsed time.
This is the battle simulation clock, so fast-forwarding and replaying steps make
it different from real time. It is shown with the battle status HUD and is hidden
when Battle Status Panel is turned off. The panel appears when a battle or replay
finishes, hides while a replay is running, and hides when you leave the battle.
While it is visible, the lives/wins/day HUD is hidden so the two never overlap.

OPPONENT INFO
During battle, a small bottom-right panel shows the opponent's name and MMR
(ranked, casual, or Bot). It shares the Battle Status Panel toggle and hides
together with the lives/wins/day HUD.

COMBAT STATS
After a battle finishes, a collapsible panel compares your team's combat
statistics with the opponent's. Each side opens with its trainer's portrait and
a centered heading: "Your Team" and "Opponent Team". It shows team
totals for damage, status damage, healing, shield, and casts with a comparison
operator (>, <, or =) between the two sides, then a compact one-row-per-unit
table for each team. Each unit row
shows the monster's icon beside its name, the top value for each metric is
highlighted in green, and zero or missing values are muted. The panel can be
collapsed and dragged, and it remembers where you put it. It is hidden while a
replay runs and when you leave the battle.

The Combat Stats Panel setting shows or hides the whole panel, including the
team headings and the summed comparison at the top. This panel was merged from
the BatoStats++ mod, so BatoStats++ is no longer needed alongside Creature
Comforts.

SHOP INCOME
Displays your current income directly in the shop.

DAY REMINDERS
Receive reminders for important trainer-specific events and global events on Days 3, 6, and 9.

NOTIFICATION SOUNDS & VOLUME
Reminder chimes and UI clicks can be muted with Notification Sounds. The
Mod Volume slider (0-100, default 100) directly under it sets how loud they
are, and plays a click at the new level when you let go. Both are at the
bottom of Settings > Mods > Creature Comforts.

SHOP RANK ODDS
View shop rarity probabilities for ranks 1 through 14+ using the chart icon near the shop rank display.

BASE HP BY DAY
View a day-by-day base HP table for days 1 through 17 using the heart chart icon in the shop HUD.
The current day is highlighted, and the Total column adds the HP bonus from your current trinkets and trainer.


SETTINGS
--------
Features can be enabled or disabled individually under:

Settings > Mods > Creature Comforts

Mod Volume is a single slider (mouse drag, or focus it and use left/right) at
the bottom of the list, under Notification Sounds. Scroll down to reach it.
It is saved by the mod itself in user://creature_comforts/settings.cfg.

Settings are saved automatically and persist between sessions.


AUTO-UPDATE
-----------
Creature Comforts keeps itself current. On game start it checks for a newer version. 
When a new version is out, Auto-update (Settings > Mods > Creature Comforts,
on by default) downloads it and checks it before anything is replaced: the
download must match the release's checksum, contain only Creature Comforts
files, and every script must load on your game build. If a check fails or the
download fails, nothing on disk changes.

After a successful update a small notice says to restart. The new version takes
effect the next time Batomon Showdown starts.

Turn Auto-update off to get a notice only and install new versions yourself
(e.g. from Nexus Mods or GitHub) by replacing the Mods\CreatureComforts folder.

REQUIREMENTS
------------
- Batomon Showdown (Steam, PC)
- Community Batomon Showdown Mod Loader

IMPORTANT: The community Mod Loader is REQUIRED and must be installed before Creature Comforts.

Mod Loader by EmoUsedHM01 and madibye (separate download).


INSTALLATION
------------
1. Install the community Batomon Showdown Mod Loader first.
   Follow the installation instructions on its Nexus Mods page.

2. Close Batomon Showdown.

3. Locate your game installation folder:
   Steam > Right-click Batomon Showdown > Manage > Browse local files

4. Extract the Creature Comforts ZIP into the game folder, preserving the folder structure.

   The resulting structure should look like:

   Batomon Showdown\Mods\CreatureComforts\
      mod_main.gd
      mod.json
      ...additional mod files and assets...

   IMPORTANT:
   - Do not create an extra nested CreatureComforts folder.
   - mod_main.gd and mod.json must be directly inside Mods\CreatureComforts\.

5. Launch Batomon Showdown.

The Mod Loader should automatically detect Creature Comforts.


UNINSTALLATION
--------------
1. Close Batomon Showdown.
2. Delete the folder:

   Batomon Showdown\Mods\CreatureComforts

3. Launch the game normally.

Creature Comforts does not modify game saves or permanent gameplay data. Uninstalling does not require starting a new run.


COMPATIBILITY & TROUBLESHOOTING
-------------------------------
Creature Comforts is designed to work alongside other mods using the community Mod Loader, but compatibility with every mod is not guaranteed.

If the mod does not appear:
- Confirm the Mod Loader is installed and working.
- Verify the folder structure shown above.
- Restart the game.

If you encounter a bug, please include a description, reproduction steps, and screenshots if possible.


FEEDBACK
--------
Suggestions, bug reports, and feature requests are welcome!

Leave feedback on Nexus Mods or submit an issue on GitHub.


CREDITS
-------
Creature Comforts is an unofficial fan-made mod.

The combat statistics panel was merged from BatoStats++, also by NescapePlan.

Not affiliated with or endorsed by the developers of Batomon Showdown.

Community Mod Loader by EmoUsedHM01 and madibye.

Batomon Showdown and its assets belong to their respective owners.