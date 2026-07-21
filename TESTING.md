# Waddle Wars — Testing

## Test commands

All commands run from the repository root. The suite is plugin-free: plain
Godot scenes that print `PASS`/`FAIL`/`SKIP` lines and exit `0` on success,
nonzero on failure.

```sh
# Full suite (discovers the Godot binary; override with GODOT=/path/to/godot)
./run_tests.sh

# Individual cases
godot --headless --path . res://tests/unit_tests.tscn
godot --headless --path . res://tests/menu_load_test.tscn
godot --headless --path . res://tests/race_sim.tscn -- course=glacier
godot --headless --path . res://tests/race_sim.tscn -- course=aurora
godot --headless --path . res://tests/race_sim.tscn -- course=iceberg
godot --headless --path . res://tests/race_sim.tscn -- course=glacier difficulty=emperor

# Parser / import / resource validation (no gameplay)
godot --headless --path . --quit-after 2
```

`run_tests.sh` skips the aurora and iceberg race sims automatically while
`scripts/courses/course_aurora.gd` / `course_iceberg.gd` do not exist yet, and
reports them as `SKIP` in its summary.

## Automated test coverage

### `tests/unit_tests.tscn` (`tests/unit_tests.gd`)

| Area | Checks |
| --- | --- |
| Save round trip | Modified `fish`, `achievements`, `best_times` survive `save_now()` + `load_save()`; original save restored afterwards. |
| Save corruption | Garbage written to `user://save.json` and `user://save.json.bak`; `load_save()` recovers merged defaults without crashing; backup file re-validated. |
| Settings defaults | Every key in `SettingsManager.default_settings()` resolves via `get_setting` with a compatible type; music volume in range; touch mode valid. |
| Settings round trip | `set_setting("audio","music_volume",0.33)` persists across a fresh `_load_settings()`; original value restored. |
| CosmeticsDB | ≥ 12 non-body items (or ≥ 16 total); every item has `name`/`category`/`cost`; `items_in_category` covers all items sorted by cost. |
| AchievementsDB | ≥ 12 entries; `ORDER` exactly matches `ITEMS` keys; every entry has `name`/`desc`. |
| PowerupsDB.roll | 200 seeded rolls across positions 1–8 all return catalog ids with ≥ 3 distinct results. |
| Progression | `add_fish`/`spend_fish` arithmetic; unlock rejected when broke and charged correctly when affordable; equip works; equipping a locked item is rejected. Runs against a fresh default save with deep backup/restore. |
| Racer | `Racer.new()` + `setup()` with a `RacerController`, `PenguinVisual`, and null course survives physics ticks in-tree. |
| PathGuide | `TrackBuilder.make_curve` + `PathGuide`: nearest-point distance small for on-curve probes, offsets monotonic along the path, yaw/positions finite and sane. |
| Powerups activate | `PowerupSystem.activate` for every id in `PowerupsDB.ORDER`: snowball node spawns, shield applies, frenzy boosts, magnet registers, blizzard cloud spawns; live effects tick one physics frame without errors. |
| Menu scenes | title, main_menu, mode_select, results (with a pre-filled 8-row `Game.last_race_results`), settings, controls, customize, achievements, credits each instantiate, build > 3 nodes with a live script, and free cleanly. Scenes not yet written by the parallel UI stream are reported as `SKIP`, not failures. |
| Touch controls | `TouchControls.new()` + `setup(PlayerController.new())` builds the steer zone, action buttons, and pause button without a racer or course. |

### `tests/menu_load_test.tscn` (`tests/menu_load_test.gd`)

Focused menu smoke test: instantiates every menu scene listed above (same
skip rule for unwritten scenes), then drives `SceneRouter.go_to` to the main
menu and verifies the headless scene swap actually lands on `MainMenu`.

### `tests/race_sim.tscn` (`tests/race_sim.gd`)

Full-race integration test: boots the real race scene with all eight racers
under AI control (`RaceManager.autopilot_player`) at 12x time scale, requires
every racer to finish with no DNFs, and validates the results handoff to the
results scene. Parameters: `-- course=<id> difficulty=<id>`.

## Manual QA checklist

Player-facing flow (run on every release candidate):

- [ ] Title screen: logo visible, prompt pulses, any input advances to main menu.
- [ ] Main menu: every button navigates; focus visible; Quit hidden on mobile.
- [ ] Quick Race: mode select → course select → difficulty → countdown → race →
      results → rewards → Race Again and Main Menu both work.
- [ ] Grand Prix: all three rounds chain, standings shown between rounds, cup
      ceremony after the final, GP record saved.
- [ ] Time Trial: solo run, best time recorded, record banner on improvement.
- [ ] Endless Expedition: run ends cleanly, score/distance/fish on results,
      high score persists.
- [ ] Waddle School (tutorial): completes, `first_waddle` unlocks, reward paid.
- [ ] Pause during a race: game halts, resume/settings/quit-to-menu all work,
      quitting mid-race does not corrupt the save.
- [ ] Settings: change music/sfx volume, resolution, window mode, steer
      sensitivity — each applies immediately AND survives a full app restart.
- [ ] Controls: rebind a key, verify it works in a race, reset to defaults.
- [ ] Customize: buy an item with fish, equip it, see it on the racer in-game;
      balance and unlock persist after restart.
- [ ] Achievements screen: unlocked entries display correctly; toast appears
      when a new achievement unlocks mid-game.
- [ ] Save integrity: force-quit during a race and mid-menu; relaunch keeps
      fish, unlocks, records.
- [ ] Race readability: positions update promptly, checkpoint recovery returns
      racers to the track, no racer permanently stuck (watch one full AI race).
- [ ] Audio: music crossfades between menu and race; SFX for jump, slide,
      shove, item use, finish; mute and mute-on-unfocus behave.

### Resolutions to test (per GAME_SPEC section 20)

- [ ] 1920×1080 (baseline 16:9)
- [ ] 1280×720 (small window)
- [ ] 2560×1440 (where practical)
- [ ] 2400×1080 (wide mobile landscape)
- [ ] Tablet-like landscape (e.g. 2160×1620 or 1600×1200)

At each: no text overlap or clipping, HUD anchored correctly, menus centered,
touch buttons reachable, no horizontal letterboxing artifacts.

### Input methods to test

- [ ] Keyboard (default bindings and a remapped set)
- [ ] Gamepad (steer axis with deadzone setting, buttons, pause)
- [ ] Touch (steer drag zone, jump/slide/shove/item buttons, pause button,
      touch scale and opacity settings)

## Last validation results

- **Date/time:** 2026-07-21 03:05 (local)
- **Godot:** 4.7.1.stable.official.a13da4feb (`/opt/homebrew/bin/godot`)
- **`run_tests.sh` summary:** ALL PASSED (exit 0) —
  `unit_tests` (49/49 checks), `menu_load_test`, `race_sim glacier`,
  `race_sim aurora`, `race_sim iceberg`, `time_trial ghost`, `endless_sim`
  (deterministic-seed check + storm-end flow), `tutorial_sim`,
  `grand_prix_sim` (3 rounds, 117 points distributed, standings sorted).
- **Difficulty coverage:** `race_sim glacier difficulty=chill` PASS,
  `race_sim aurora difficulty=emperor` PASS (all 8 racers finish at every
  difficulty tested).
- **Headless import/parse:** clean — zero script/parse/import errors.
- **Runtime log audit:** full windowed race run stderr shows no repeated
  errors (only Godot's benign exit-time ObjectDB note from force-quit).
- **Exports:** Windows (`waddle-wars-windows.exe`, 115MB), macOS
  (`waddle-wars-macos.zip`, 65MB), Linux (`waddle-wars-linux.x86_64`, 79MB)
  all export successfully with 4.7.1 templates; exported macOS app
  boot-tested headless (exit 0, no errors). Android preset validated but not
  built (no keystore on this machine); iOS documented in README.
- **Manual/visual checks:** screenshot review of title, main menu,
  mode select, customize, achievements, settings, results, pause overlay,
  countdown, mid-race HUD on all 3 courses + tutorial + endless, at
  1920×1080 / 1280×720 / 2560×1440 / 2400×1080. Fixed during review:
  penguin belly geometry, title logo overlap, washed-out palette, unthemed
  buttons, fish readability, fog density.
- **Known issues:** gamepad binding labels show raw indices ("Pad 0") in the
  remap screen; trail cosmetics render in-race but not in the customize
  preview panel.
