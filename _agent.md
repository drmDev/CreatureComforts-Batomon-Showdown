```markdown
# AGENTS.md — Brainrot Edition

## Summary
Brainrot Edition (`np_brainrot`) is a GDScript mod for **Batomon Showdown** that observes shop/battle state and provides contextual gameplay advice. It logs readable state changes, emits distinct trainer-specific notices, and displays on-screen reminders for critical trainer events without automating gameplay. Reusable rules support shop targets, day reminders, and compound team conditions. Development prioritizes verified game data, maintainability, quiet logging, and incremental runtime validation.

## Current goals
- ✅ Complete the shared shop-snapshot refactor while preserving working behavior.
- ✅ Maintain Scavenger target notices and Black Belt Beetbud/Beetdown checks.
- ✅ Add the Mad Scientist Day 6 transformation reminder with on-screen display.
- Discover owned-trinket data and eventually display an organized list.
- Add a compact shop advice panel using the working NP_QoL drawing patterns.

## Files
| File | Responsibility |
|---|---|
| `mod.json` | Mod identity, version, descriptions, and settings declarations. Includes `enable_trainer_reminders` setting. |
| `mod_main.gd` | Loader lifecycle, initialization, polling, phase transitions, rule registration, reminder panel management, and console/file output coordination. |
| `shop_snapshot.gd` | Shared capture of run, shop, team, and bench values, including identity, species, levels, types, prices, and slots. |
| `advice_context.gd` | Supplies the rule-facing context from snapshot data. |
| `trainer_advisor.gd` | Evaluates registered rules, tracks active advice, and suppresses unchanged notices by rule ID. |
| `trainer_rules.gd` | `ShopTargetsRule`, `DayReminderRule`, and compound `BeetdownCompanyRule`; returns structured advice without output side effects. |
| `reminder_panel.gd` | Reusable UI panel for displaying trainer reminders on-screen during shop phase. Supports multiple simultaneous reminders. |
| `log_formatter.gd` | Readable names, summaries, detailed inspection, and change output. |
| `shop_changes.gd` | Structured snapshot comparison for detecting shop state changes. |
| `gd_checks.ps1` | Runs Godot checks across mod scripts; excludes example directories. |
| `examples/` | Sample/test material, separate from production script checks. |

The trinket list and expanded advice panel are future features, not yet implemented.

## Working conventions
- Verify game identifiers/properties from source or runtime evidence; never invent APIs.
- Keep rules independent of live game objects, file writing, and UI drawing.
- Preserve snapshot schemas consistently across producers and consumers.
- Retain the 500 ms polling interval unless measurements justify changing it.
- Suppress unchanged notices; reset on new shop visits and actual trainer/run changes.
- Keep crash tracing temporary and disabled during normal use.
- Run GDScript checks on every changed helper as well as the main script. Parse success does not establish runtime correctness.
- The user performs gameplay tests; report actual checks separately from pending runtime validation.
- Make one focused change at a time and keep related explanations together.
```