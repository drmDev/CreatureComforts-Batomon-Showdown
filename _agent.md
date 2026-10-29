```markdown
# AGENTS.md — Creature Comforts

## Summary
Creature Comforts (`creature_comforts`) is a GDScript mod for **Batomon Showdown** that observes shop/battle state and provides contextual gameplay advice. It logs readable state changes, emits distinct trainer-specific notices, and displays on-screen reminders for critical trainer events without automating gameplay. Reusable rules support shop targets, day reminders, and compound team conditions. Development prioritizes verified game data, maintainability, quiet logging, and incremental runtime validation.

## Preserve Existing Functionality

- Prefer surgical changes over large refactors.
- Do not modify unrelated systems unless necessary.
- Preserve existing UI behavior, layout, and visual styling.
- Avoid introducing new abstractions for one-off functionality.
- Never remove existing functionality without explicitly asking.
- If a requested change risks breaking another feature,
  explain the tradeoff before implementing it.

  ## Investigation

- Before modifying code, inspect the relevant existing implementation.
- Reuse existing hooks, signals, and utilities when possible.
- Do not invent game APIs, node paths, or signal names.
- If uncertain about a game's internal behavior, inspect the source.
- Avoid reading entire large files when targeted searches suffice.
- Do not modify the game's original files.

## Communication Style

- Be concise and direct.
- Avoid lengthy explanations of straightforward changes.
- Do not repeat the entire task back to me.
- Do not explain basic programming concepts unless asked.
- Assume I am an experienced software developer.
- When changes are complete, summarize:
  - What changed.
  - What should be tested.
  - Any remaining concerns.
- Do not add unnecessary praise or filler.

## Scope Discipline

Implement only what was requested.

Do not add speculative features, extra configuration,
new dependencies, or unrelated refactors.

If you identify a worthwhile improvement outside the
requested scope, mention it briefly instead of implementing it.

## Current goals
- ✅ Complete the shared shop-snapshot refactor while preserving working behavior.
- ✅ Maintain Scavenger target notices and Black Belt Beetbud/Beetdown checks.
- ✅ Add the Mad Scientist Day 6 transformation reminder with on-screen display.
- ✅ Retire the exploratory owned-trinket reflection probe from deep-inspection logging; trinket-aware advice would require re-verified game data first.
- ✅ Battle entry logs trinket state only (`trinket_ids` + `_active_passives` attribution); gains are logged as a battle-scoped diff (`--- BATTLE TRINKET GAINS ---`), not a shop-to-shop diff.
- ✅ Add a trinket-gain panel that appears right-center on shop return, auto-hides after 10 seconds, using the NP_QoL drawing patterns.
- ✅ Refactored trinket-gain panel to be battle-scoped: keeps a rolling pre-battle inventory snapshot (needed because the autobattler simulates the fight before the 500ms poll sees the battle state), diffs it against the snapshot frozen at `battle_over`, filters out Junk trinkets, and shows a collapsible panel only when non-junk trinkets were earned. The panel appears when the battle state ends and only for VICTORIES. Locked Box and Mysterious Chest apply their gift to `trinket_ids` during the battle simulation, so on a defeat those gifts are already in the `battle_over` snapshot and cannot be separated from real gains by timing; showing them would reveal the gift before the game does. Defeat gains are still logged. Uses the collapsible-panel pattern from examples/MyBattleStats/disabled_collapsible_panel.gd (header drag, -/+ toggle, height animation).
- ✅ Add the post-battle achievement panel (Phase 1): battle-completion detection, placeholder achievement evaluation, and a bottom-right panel driven by a clearly marked temporary demo trigger, gated by the opt-in Achievement Notifications setting.
- ✅ Add the "Big Dog, Best Dog" battle achievement: awards when a Cinnabark unit generates more than 1,000,000 shield in a single battle, read from `simulation.data.battle_units` (`team_id == 0`, `slot_index`, `shield_granted`) with species resolved through the player run's team slot.
- ✅ Add "Herd U Liek Mudkipz" using the same Twins double-evolution rule as "Oh Yeah!", for Frillet (level 2) evolving into two level-3 Dewlotls.
- ✅ Add "So I started blasting": Gentleman trainer owns a level-2 Rhizuka on Day 5 or earlier (`run.current_round`), checked from team + bench state.
- ✅ Port NP_QoL's battle player HUD (HP / Wins / Day) into the mod, restyled to the shared dark-navy/gold panel look and text-only (no heart/badge/sun icons).
- ✅ Add the shop income panel: a tiny bottom-center square showing the day's income (base schedule + `gold_gain` trinket/passive bonuses).

## Files
| File | Responsibility |
|---|---|
| `mod.json` | Mod identity, version, descriptions, and settings declarations. |
| `mod_main.gd` | Loader lifecycle, initialization, polling, phase transitions, catalog-driven rule registration, reminder label/highlight/trinket-panel/player-HUD/shop-income/achievement management, per-poll and per-battle achievement detection + shared award persistence, battle-scoped trinket gain capture (rolling pre-battle baseline → in-battle diff), Junk filtering, and console/file output coordination. |
| `core/shop_snapshot.gd` | Shared capture of run, shop, team, and bench values, including identity, species, levels, types, and slots. |
| `core/shop_changes.gd` | Structured snapshot comparison for detecting shop state changes. |
| `core/log_formatter.gd` | Readable names, summaries, detailed inspection, and change output. |
| `advice/advice_context.gd` | Supplies the rule-facing context from snapshot data. |
| `advice/trainer_advisor.gd` | Evaluates registered rules, tracks active advice, and suppresses unchanged notices by rule ID. |
| `advice/trainer_rules.gd` | Reusable rule classes (`ShopTargetsRule`, `DayReminderRule`, `TeamCompositionRule`) emitting a shared advice contract (rule_id, trainer_id, severity, message, display mode, reminder text, chime flag); returns structured advice without output side effects. |
| `advice/trainer_catalog.gd` | Declarative trainer definitions (id, display name, rule data) consumed by the rule factory. |
| `advice/rule_factory.gd` | Builds rule instances from `trainer_catalog.gd`; supports per-trainer custom scripts via a `script` key. |
| `hud/reminder_label.gd` | Compact top-bar label showing label-mode reminders for the current trainer. |
| `hud/player_hud.gd` | Battle-only single-line HUD showing HP / Wins / Day, ported from NP_QoL and restyled to the shared dark-navy/gold panel look (text-only, no icons). Panel width is fitted to the measured text (no fixed/trailing space) and re-centered when stats change. Centered near the top of the battle screen; visibility driven by mod_main. |
| `hud/shop_income_panel.gd` | Tiny square shop-only panel near bottom-center showing the current daily income (base 35 on Day 1, +5 per day, plus `gold_gain` passive bonuses such as Gold Nugget). Styled like the other panels; visibility follows the reminder layer's shop gate. |
| `hud/shop_highlight.gd` | Click-through overlay that outlines shop cards for highlight-mode advice (slot + offer instance id, resolved against live cards each frame). |
| `hud/trinket_panel.gd` | Collapsible panel showing non-junk trinkets earned in a battle; appears when the battle state ends after a VICTORY (defeat-triggered gifts like Locked Box / Mysterious Chest are pre-applied at combat start and would otherwise be spoiled) and auto-hides after 8 seconds. Uses the collapsible-panel pattern (header drag, -/+ toggle, height animation) adapted from examples/MyBattleStats/disabled_collapsible_panel.gd. |
| `achievements/battle_completion_detector.gd` | Reports each battle's completion exactly once via `simulation.data.battle_over` (wins, losses, and draws); resets when leaving the battle phase. |
| `achievements/achievement_evaluator.gd` | Poll-based achievement detection. Run-scoped `poll(run)`: state-checks "So I started blasting" (Gentleman trainer + a level-2 Rhizuka on team/bench while `run.current_round` ≤ 5), collects team+bench species/levels in one pass, and awards the Twins double-evolution achievements — "Oh Yeah!" (Beetbud → Beetdown) and "Herd U Liek Mudkipz" (Frillet → Dewlotl). The evolved-count baseline arms when a level-2 pre-evolution is seen and stays armed for 2 s because the game can apply the Twins double across separate 500 ms polls; the award fires when the evolved count rises by ≥2 from that baseline. Battle-scoped `poll_battle(state, run)`: awards "Big Dog, Best Dog" when a Cinnabark slot's summed `shield_granted` in the player's `battle_units` exceeds 1,000,000 (once per battle state); `reset_battle()` clears battle tracking. Returns structured achievements without persistence or UI side effects. |
| `achievements/achievement_store.gd` | Simple JSON persistence for achievement completion at the mod root (`achievements.json`). Tracks completed/not-completed per achievement id with a completion timestamp; tolerates missing or corrupt files. |
| `achievements/achievement_panel.gd` | Bottom-right achievement toast; auto-hides after ~4 seconds. Uses the NP_QoL / Trinket Panel drawing pattern. Displays only when the Achievement Notifications setting is enabled. |
| `gd_checks.ps1` | Runs Godot checks across mod scripts; excludes example directories. |
| `run_tests.ps1` | Runs the headless unit-test suite (`tests/run_tests.gd`) with the same Godot binary as `gd_checks.ps1`; propagates the exit code. |
| `tests/` | Zero-dependency unit tests for pure logic (`achievement_evaluator.gd`, `trainer_rules.gd`): `test_runner.gd` (assertions + `test_*` discovery), `test_helpers.gd` (Object fakes/builders), `run_tests.gd` (SceneTree entry point), and per-target test suites. |
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
- Run `run_tests.ps1` after changing the achievement evaluator or trainer rules; it runs headless and exits non-zero on failure.
- The user performs gameplay tests; report actual checks separately from pending runtime validation.
- Make one focused change at a time and keep related explanations together.
```