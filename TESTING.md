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
  remap screen. (Trail cosmetics now also render in the customize preview panel
  as of the 2026-07-24 checkpoint.)

## Supervisor final validation — 2026-07-24 (post-cutoff)

Reset deadline 2026-07-21T06:59:53-04:00 has passed. Fastest meaningful
validation run on the working tree at final checkpoint:

| Check | Command | Result |
|-------|---------|--------|
| Parse/import | `godot --headless --import .` | clean, 0 errors |
| Race sim (glacier) | `godot --headless tests/race_sim.tscn` | PASS, 8/8 finish |
| Race sim (aurora) | `... -- course=aurora` | PASS (earlier run) |
| Race sim (iceberg) | `... -- course=iceberg` | PASS (earlier run) |
| Power-up activation | instrumented sim | 10 activations, was 0 |

Outstanding defects tracked in QA_FINDINGS.md: 4 FIXED, 14 OPEN. `run_tests.sh`
full suite exceeded 10 min wall-clock in the supervisor environment — recommend
a fast-subset flag before relying on it in CI.

## Prod-readiness round — 2026-08-05

Full audit (9 agents, 67 raw findings → verified list) + fix round (6 agents)
+ optional online leaderboard (Clerk + Cloudflare Worker + D1). Validation on
the working tree:

| Check | Command | Result |
|-------|---------|--------|
| Parse/import | `godot --headless --import .` | 0 script errors |
| Unit suite | `godot --headless tests/unit_tests.tscn` | 50/50 (adds leaderboard menu-load) |
| Race sim glacier | `... -- course=glacier` | PASS |
| Race sim aurora | `... -- course=aurora` | PASS |
| Race sim iceberg | see flake note below | PASS (battery) |
| Endless sim | `tests/endless_sim.tscn` | PASS |
| GP sim | `tests/gp_sim.tscn` | PASS (3 rounds, tiebreak-sorted standings) |
| Tutorial sim | `tests/tutorial_sim.tscn` | PASS |
| Boost arrows | `tests/pad_shot.tscn` top-down captures | direction + scroll verified |
| Leaderboard API | curl health/board/401 checks | all correct |
| Visual QA | screenshot_tour: menu, leaderboard, countdown | reviewed; control-strip contrast fixed |

2026-08-06 fidelity-round rerun: import 0 errors; units 50/50; sims PASS
glacier/aurora/iceberg×2/endless/gp/tutorial (SUITE-DONE, exit 0). Iceberg
causeway tilt at 13° also passed a separate 3/3 battery (15° caused one
Marina DNF and was reverted).

2026-08-06 mega round 2: part-1 (sharing/minimap/UI) battery — units 50/50,
glacier/aurora/iceberg/tutorial PASS. Post-physics-pass battery — import 0
errors, units 50/50, all sims PASS except iceberg 2/3 (one triple-AI-DNF
run; 8/9 including follow-up reps). After making platform carry player-only
and halving AI-vs-AI bump impulses: iceberg 8/8 PASS + glacier PASS.
Physics jump-arc parity checked by the agent analytically (airtime 0.83s vs
0.73s, height 2.10m vs 2.02m — gaps only get more forgiving).

Iceberg flake investigation: baseline b0a5c19 timed out 3/6 sim runs — a
pre-existing autopilot resonance (boost pad 16m before the moving-platform
crossing + fixed respawn cadence re-hitting the same platform phase), NOT a
regression from this round (verified by stash-and-rerun bisect). Fixes: pad
moved 70m upstream, randomized 0.2–1.4s post-respawn stumble, and an AI
progress watchdog (respawn if <6m course progress in 12s — catches full-speed
circling the position-delta check misses). Post-fix battery results recorded
in BUILD_STATUS.md.

2026-08-06 round 3: units 50/50; race_sim PASS for glacier/aurora/iceberg x
chill/competitive/emperor (9/9); endless_sim, gp_sim PASS; tutorial_sim 3/3
PASS. Bisect method that found the regressions: parallel git worktrees at the
suspect commit, each with one subsystem disabled, running tutorial_sim and
race_sim side by side. tutorial_sim's TIMEOUT diagnostic (player progress /
position / state) is what localised the hurdle stall — keep it.

2026-08-06 round 4: units 50/50; tutorial_sim 3/3; race_sim 9/9 across
glacier/aurora/iceberg x chill/competitive/emperor; endless_sim, gp_sim PASS
— with physics, hazard motion, grounding and Chrome warm-up all integrated.
Each was validated alone in its own worktree before combining, which is what
separated the real causes (low-speed steer assist; aggressive platform lurch
config) from the subsystems blamed first.


2026-08-07: units 63/63; menu_load 0 failures; race_sim PASS on all five
courses (glacier, aurora, iceberg, cinder, hollow); tutorial_sim PASS;
endless_sim PASS. Racer shader additionally verified under
`--rendering-method gl_compatibility`, which is the actual web path.

New QA harnesses this round:
- `tests/prop_shot.tscn` — stands one hazard or prop in a neutral set with a
  fixed camera (`prop=wind|icicle|bear`). Racing past an obstacle on autopilot
  gives it to you for a third of a second at whatever angle the course happens
  to offer; this is how the icicle's intersecting-plate collar and the wind
  zone's missing structure were actually seen.
- `screenshot_tour` gained `uiscale=` (layout bugs that only appear for players
  who raise the accessibility scale are invisible at the default),
  `shot=customize_buy` (opens the purchase confirmation) and
  `shot=course_select` (advances to the course picker so poster art can be
  checked rather than assumed).

Lesson worth keeping: three separate visual defects this round were found ONLY
by reading captured frames back — the icicle collar, the penguin's tail wedge
rendering as a mouth, and the polar bears standing behind a translucent wall.
None of them failed a test.

2026-08-07 (later): units 71/71 (adds 8 tilt-axis checks); menu_load 0
failures; race_sim PASS on all five courses with 8/8 finishers and no DNFs;
tutorial_sim PASS.

New harness capability: `GameConfig.force_touch` plus `touch=1` on
screenshot_tour renders the PHONE layout on a desktop box. Every touch-only
layout rule is gated on real hardware, so before this the phone layouts were
literally unrenderable here — which is how the results screen shipped running
off both edges despite being captured several times.

Two lessons from this round, both about verifying the wrong thing:
- `uiscale=` persists to settings.json, so a value left by an earlier capture
  silently changes every later one. A mobile fix got tuned against a canvas no
  phone has. The harness now pins ui_scale on every capture.
- Forcing `UITheme.is_touch()` alone was not enough: the canvas shrink lives in
  SettingsManager behind `GameConfig.has_touchscreen()`. Half-forcing the phone
  path produced a canvas that exists nowhere.

2026-08-08: units 91/91 (adds 12 ice-shield lifetime/i-frame checks and 5 shove
animation-envelope checks); menu_load 0 failures; race_sim PASS on all five
courses; time_trial ghost, endless_sim, tutorial_sim, grand_prix_sim PASS.
`./run_tests.sh` RESULT: ALL PASSED.

New QA harness this round:
- `tests/overlap_probe.tscn` — measures scenery that intrudes into the racing
  corridor, instead of hoping someone notices it while driving past.

  ```sh
  godot --path . res://tests/overlap_probe.tscn -- course=aurora
  ```

  Walks every guide (main and branches), builds the corridor from the deck
  half-width and a deck-1m..deck+6m headroom band, and triangle-tests every
  mesh against it. Reports each offender with its node path, world AABB,
  nearest arc offset, how far inboard of the deck edge it reaches and over how
  many samples — and prints the exclusions it applied (track ribbon, Area3D
  triggers, hazard classes, named furniture) so false negatives are auditable
  rather than silent. Flat decals and translucent VFX are listed separately
  from solid intrusions, because a reflection quad on the deck is not a defect
  and a mountain through it is.

  Run it on glacier as a control before trusting a threshold: glacier's
  offenders are almost all snowbanks and sastrugi sitting at or below deck
  level, so a run that flags them the same way it flags a mountain is
  mis-tuned.

  Baselines after this round's fixes: aurora 9 (was 17), glacier 21 (was 32),
  cinder 6. Aurora's nine are the six cavern arches and a lamp arm at 5.8-5.9 m
  overhead, plus the two ridge berms, which are the intentional wind channel.

- `screenshot_tour` gained `shot=race_shove`, and `pose_check` gained
  `impulse=lunge|tumble` and `view=behind`. Both save a *strip* of frames
  across the impulse rather than one still: a shove is a 0.4-1.0 s one-shot,
  and a single screenshot that misses the peak looks identical to the effect
  not existing. `view=behind` puts the camera where ChaseCamera actually sits,
  which is the only angle a player judges their own animation from.

Lesson worth keeping, again: the shove impact ring passed every test and read
as a white croquet hoop planted in the snow the first time it was captured.
Tests prove an effect fires; only a frame shows what it looks like.

2026-08-08 (later): units 107/107 (adds 12 pause/settings round-trip checks and
5 setup-entry-step checks); `./run_tests.sh` RESULT: ALL PASSED.

`screenshot_tour` gained `pause=settings`, which opens the pause menu and then
the settings overlay, so the in-race settings screen can be inspected.

Worth keeping: the pause/settings work is a case where a screenshot proves the
wrong half. A capture shows that settings RENDERS over the paused race; it
cannot show that Back hands the race back rather than unloading it, that the
tree is still paused underneath, or that Escape does not close settings and
unpause in one press. Those are the three ways this feature can be broken, and
all three are unit-tested.

The phone course-list overflow was diagnosed by measuring, not by looking. Two
guesses from the screenshot alone (the title Label's minimum width, then the
column width) were both wrong; printing `get_combined_minimum_size()` down the
tree found it immediately — card 647, inner content 720. When a layout overflows
and the cause is not obvious, walk the tree and print the minimums.
