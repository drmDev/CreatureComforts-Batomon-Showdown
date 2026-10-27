```markdown
# AGENTS.md — Brainrot Edition

## Summary
Brainrot Edition (`np_brainrot`) is a GDScript mod for **Batomon Showdown** that observes shop/battle state and provides contextual gameplay advice. It logs readable state changes, emits distinct trainer-specific notices, and displays on-screen reminders for critical trainer events without automating gameplay. Reusable rules support shop targets, day reminders, and compound team conditions. Development prioritizes verified game data, maintainability, quiet logging, and incremental runtime validation.

## Current goals
- ✅ Complete the shared shop-snapshot refactor while preserving working behavior.
- ✅ Maintain Scavenger target notices and Black Belt Beetbud/Beetdown checks.
- ✅ Add the Mad Scientist Day 6 transformation reminder with on-screen display.
- ✅ Retire the exploratory owned-trinket reflection probe from deep-inspection logging; trinket-aware advice would require re-verified game data first.
- ✅ Battle entry logs trinket state only (`trinket_ids` + `_active_passives` attribution), and shop visits report `--- TRINKETS GAINED ---` as a shop-to-shop inventory diff.
- ✅ Add a trinket-gain panel that appears right-center on shop return, auto-hides after 10 seconds, using the NP_QoL drawing patterns.

## Files
| File | Responsibility |
|---|---|
| `mod.json` | Mod identity, version, descriptions, and settings declarations. |
| `mod_main.gd` | Loader lifecycle, initialization, polling, phase transitions, catalog-driven rule registration, reminder label/highlight/trinket-panel management, and console/file output coordination. |
| `shop_snapshot.gd` | Shared capture of run, shop, team, and bench values, including identity, species, levels, types, prices, and slots. |
| `advice_context.gd` | Supplies the rule-facing context from snapshot data. |
| `trainer_advisor.gd` | Evaluates registered rules, tracks active advice, and suppresses unchanged notices by rule ID. |
| `trainer_rules.gd` | Reusable rule classes (`ShopTargetsRule`, `DayReminderRule`, `TeamCompositionRule`) emitting a shared advice contract (rule_id, trainer_id, severity, message, display mode, reminder text, chime flag); returns structured advice without output side effects. |
| `trainer_catalog.gd` | Declarative trainer definitions (id, display name, rule data) consumed by the rule factory. |
| `rule_factory.gd` | Builds rule instances from `trainer_catalog.gd`; supports per-trainer custom scripts via a `script` key. |
| `reminder_label.gd` | Compact top-bar label showing label-mode reminders for the current trainer. |
| `shop_highlight.gd` | Click-through overlay that outlines shop cards for highlight-mode advice (slot + offer instance id, resolved against live cards each frame). |
| `trinket_panel.gd` | Right-center panel showing trinkets gained since the last shop visit; auto-hides after 10 seconds. Uses the NP_QoL drawing pattern. |
| `log_formatter.gd` | Readable names, summaries, detailed inspection, and change output. |
| `shop_changes.gd` | Structured snapshot comparison for detecting shop state changes. |
| `gd_checks.ps1` | Runs Godot checks across mod scripts; excludes example directories. |
| `examples/` | Sample/test material, separate from production script checks. |

## Working conventions
- Verify game identifiers/properties from source or runtime evidence; never invent APIs.
- Keep rules independent of live game objects, file writing, and UI drawing.
- Rules declare a display mode; label reminders, shop highlights, and the trinket-gain panel are always on (no setting gate), and the Pika chime plays only for chime-flagged day reminders.
- Preserve snapshot schemas consistently across producers and consumers.
- Retain the 500 ms polling interval unless measurements justify changing it.
- Suppress unchanged notices; reset on new shop visits and actual trainer/run changes.
- Keep crash tracing temporary and disabled during normal use.
- Run GDScript checks on every changed helper as well as the main script. Parse success does not establish runtime correctness.
- The user performs gameplay tests; report actual checks separately from pending runtime validation.
- Make one focused change at a time and keep related explanations together.
```