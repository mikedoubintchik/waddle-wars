# Waddle Wars — Architecture

## Guiding decision: code-built scenes

All gameplay and UI construction happens in GDScript `_ready()` code attached to
thin `.tscn` wrappers (root node + script only). This keeps every scene
headless-verifiable, avoids hand-authored scene-file corruption, and makes the
whole game testable from the command line.

## Autoloads (global responsibilities only)

| Autoload | Responsibility |
|---|---|
| `GameConfig` | game name/version, physics layers, groups, platform helpers |
| `SaveManager` | versioned `user://save.json`, atomic writes (tmp+rename), backup fallback, deep default-merge on load |
| `SettingsManager` | `user://settings.json`, immediate apply (display/audio/gameplay/accessibility), InputMap remapping persistence |
| `AudioManager` | bus volumes, music crossfade (2 players), pooled SFX (14 + 10 positional), library scan of `assets/audio/` |
| `Progression` | fish, XP/level, cosmetics unlock/equip, achievements, records (domain layer over SaveManager) |
| `Game` | mode/course/difficulty context, Grand Prix state, race-result handoff, reward calculation |
| `SceneRouter` | fade transitions, `change_scene_to_file`, achievement toasts |

## Separation of concerns

- **Racer physics** (`Racer` : CharacterBody3D): state machine (Waddling, Sliding, Airborne, Swimming, Boosted, Stunned, Recovering, Finished), surface-aware movement, guide-following auto-run. Reads intents from a `RacerController`.
- **Input** (`PlayerController` : RacerController): keyboard/gamepad/touch → intents. Touch UI calls public methods.
- **AI** (`AIController` : RacerController): steering to guide targets, branch decisions, hint-driven jumps/slides, item/shove policy, stuck recovery. Local-multiplayer-ready: adding a second human = another Racer with a PlayerController.
- **Race rules** (`RaceManager`): spawning, countdown, live positions, bounded rubberband, finish resolution/projection, result reporting. `EndlessManager` and `TutorialManager` specialize it.
- **Course data** (`CourseBase` + concrete courses): geometry via `TrackBuilder`, guides via `PathGuide`, checkpoints (progress-based), branches, AI hints, environment.
- **Presentation**: `PenguinVisual` (procedural mesh + code animation), `ChaseCamera`, HUD/menus in `scripts/ui/`.

## Course/guide system

`TrackBuilder.build_ribbon(control_points)` generates floor runs (split per
surface, trimesh collision with `backface_collision`, surface metadata for the
racer's downward raycast), walls, skirts, and optional floorless `gap` spans.
`PathGuide` pre-bakes uniform samples (2m) and answers windowed nearest-point
queries (±90m, with global fallback) so 8 racers track progress cheaply even on
self-overlapping layouts. Branch shortcuts are separate ribbons registered with
entry/exit offsets; `CourseBase.get_guide()` picks the nearest path with
hysteresis and maps branch progress back to main-line progress for ranking.

## Save format

`save.json` v1: fish, xp, unlocked_cosmetics, equipped, achievements, stats,
tutorial_complete, best_times, endless_high_score, gp_records. Loads merge over
defaults recursively — missing/new fields never destroy progress; corrupt JSON
falls back to `save.json.bak`, then defaults. Ghosts are separate
`ghost_<course>.dat` (`store_var` packed arrays).

## Signals over coupling

Racer emits (checkpoint_reached, race_finished, fish_collected, item_used,
shove_landed, respawned, stunned_changed); RaceManager and HUD subscribe.
Progression emits (fish_changed, achievement_unlocked, cosmetics_changed);
UI and SceneRouter toasts subscribe.

## Mobile considerations

Mobile renderer; landscape; canvas_items stretch with expand aspect; touch
controls layer (steer zone + buttons, scale/opacity settings); `user://`
saves; pooled particles/SFX; per-quality particle counts and shadow toggles;
pause on focus loss; no hover-dependent UI; ETC2/ASTC import enabled.

## Determinism & testing

Endless generation seeds `CourseEndless.run_seed`; all course RNG is seeded.
`tests/race_sim.tscn` boots the real game flow headless (autoloads intact) at
time_scale 12 and asserts all 8 racers finish. `tests/unit_tests.tscn` covers
saves, settings, DBs, powerups, guides, and menu-scene loads.
