```markdown
# AGENTS.md — Creature Comforts

## Summary
Creature Comforts (`creature_comforts`) is a GDScript mod for **Batomon Showdown** that observes shop/battle state and provides contextual gameplay advice. It logs readable state changes, emits distinct trainer-specific notices, and displays on-screen reminders for critical trainer events without automating gameplay. Reusable rules support shop targets, day reminders, and compound team conditions. Development prioritizes verified game data, maintainability, quiet logging, and incremental runtime validation.

## Current goals
- ✅ Complete the shared shop-snapshot refactor while preserving working behavior.
- ✅ Maintain Scavenger target notices and Black Belt Beetbud/Beetdown checks.
- ✅ Add the Mad Scientist Day 6 transformation reminder with on-screen display.
- ✅ Retire the exploratory owned-trinket reflection probe from deep-inspection logging; trinket-aware advice would require re-verified game data first.
- ✅ Battle entry logs trinket state only (`trinket_ids` + `_active_passives` attribution), and shop visits report `--- TRINKETS GAINED ---` as a shop-to-shop inventory diff.
- ✅ Add a trinket-gain panel that appears right-center on shop return, auto-hides after 10 seconds, using the NP_QoL drawing patterns.
- ✅ Refactored trinket-gain panel to be battle-scoped: keeps a rolling pre-battle inventory snapshot (needed because the autobattler simulates the fight before the 500ms poll sees the battle state), diffs it against the last in-battle snapshot, filters out Junk trinkets, and shows a collapsible panel on the battle results screen (above the achievement toast) only when non-junk trinkets were earned. Uses the collapsible-panel pattern from examples/MyBattleStats/disabled_collapsible_panel.gd (header drag, -/+ toggle, height animation).
- ✅ Add the post-battle achievement panel (Phase 1): battle-completion detection, placeholder achievement evaluation, and a bottom-right panel driven by a clearly marked temporary demo trigger, gated by the opt-in Achievement Notifications setting.
- ✅ Port NP_QoL's battle player HUD (HP / Wins / Day) into the mod, restyled to the shared dark-navy/gold panel look and text-only (no heart/badge/sun icons).

## Files
| File | Responsibility |
|---|---|
| `mod.json` | Mod identity, version, descriptions, and settings declarations. |
| `mod_main.gd` | Loader lifecycle, initialization, polling, phase transitions, catalog-driven rule registration, reminder label/highlight/trinket-panel/player-HUD/achievement management, per-poll achievement detection + persistence, battle-scoped trinket gain capture (rolling pre-battle baseline → in-battle diff), Junk filtering, and console/file output coordination. |
| `core/shop_snapshot.gd` | Shared capture of run, shop, team, and bench values, including identity, species, levels, types, prices, and slots. |
| `core/shop_changes.gd` | Structured snapshot comparison for detecting shop state changes. |
| `core/log_formatter.gd` | Readable names, summaries, detailed inspection, and change output. |
| `advice/advice_context.gd` | Supplies the rule-facing context from snapshot data. |
| `advice/trainer_advisor.gd` | Evaluates registered rules, tracks active advice, and suppresses unchanged notices by rule ID. |
| `advice/trainer_rules.gd` | Reusable rule classes (`ShopTargetsRule`, `DayReminderRule`, `TeamCompositionRule`) emitting a shared advice contract (rule_id, trainer_id, severity, message, display mode, reminder text, chime flag); returns structured advice without output side effects. |
| `advice/trainer_catalog.gd` | Declarative trainer definitions (id, display name, rule data) consumed by the rule factory. |
| `advice/rule_factory.gd` | Builds rule instances from `trainer_catalog.gd`; supports per-trainer custom scripts via a `script` key. |
| `hud/reminder_label.gd` | Compact top-bar label showing label-mode reminders for the current trainer. |
| `hud/player_hud.gd` | Battle-only single-line HUD showing HP / Wins / Day, ported from NP_QoL and restyled to the shared dark-navy/gold panel look (text-only, no icons). Centered near the top of the battle screen; visibility driven by mod_main. |
| `hud/shop_highlight.gd` | Click-through overlay that outlines shop cards for highlight-mode advice (slot + offer instance id, resolved against live cards each frame). |
| `hud/trinket_panel.gd` | Collapsible panel showing non-junk trinkets earned during a battle; appears on the battle results screen (above the achievement toast), auto-hides after 8 seconds. Uses the collapsible-panel pattern (header drag, -/+ toggle, height animation) adapted from examples/MyBattleStats/disabled_collapsible_panel.gd. |
| `achievements/battle_completion_detector.gd` | Reports each battle's completion exactly once via `simulation.data.battle_over` (wins, losses, and draws); resets when leaving the battle phase. |
| `achievements/achievement_evaluator.gd` | Poll-based achievement detection. Keeps a rolling team+bench species/level baseline and awards "Oh Yeah!" when the Twins trainer evolves a level-2 Beetbud into two level-3 Beetdowns (Beetdown count rises by ≥2). Returns structured achievements without persistence or UI side effects. |
| `achievements/achievement_store.gd` | Simple JSON persistence for achievement completion at the mod root (`achievements.json`). Tracks completed/not-completed per achievement id with a completion timestamp; tolerates missing or corrupt files. |
| `achievements/achievement_panel.gd` | Bottom-right achievement toast; auto-hides after ~4 seconds. Uses the NP_QoL / Trinket Panel drawing pattern. Displays only when the Achievement Notifications setting is enabled. |
| `gd_checks.ps1` | Runs Godot checks across mod scripts; excludes example directories. |
| `examples/` | Sample/test material, separate from production script checks. |

## Working conventions
- **Versioning:** on every edit, bump the version by `0.0001` in BOTH places: `mod.json` (`version`) and `mod_main.gd` (`const VERSION`).
- Verify game identifiers/properties from source or runtime evidence; never invent APIs.
- Keep rules independent of live game objects, file writing, and UI drawing.
- Rules declare a display mode; label reminders, shop highlights, and the trinket-gain panel are always on (no setting gate), the achievement toast is gated by the Achievement Notifications setting, and the Pika chime plays only for chime-flagged day reminders.
- Preserve snapshot schemas consistently across producers and consumers.
- Retain the 500 ms polling interval unless measurements justify changing it.
- Suppress unchanged notices; reset on new shop visits and actual trainer/run changes.
- Keep crash tracing temporary and disabled during normal use.
- Run GDScript checks on every changed helper as well as the main script. Parse success does not establish runtime correctness.
- The user performs gameplay tests; report actual checks separately from pending runtime validation.
- Make one focused change at a time and keep related explanations together.
```