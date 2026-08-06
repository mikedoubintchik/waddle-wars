# QA Findings — independent review (supervisor session)

Source: 29-agent adversarially-verified review of commit c44f7c6, re-checked against fb761ac.
Every finding below was confirmed by reading the code; fix and mark FIXED with evidence, or rebut with evidence.

## CRITICAL

1. **[FIXED @1636b1e — supervisor-verified: instrumented sim shows 10 activations (snowball/shield/magnet/blizzard), PASS] Power-ups can never be activated — `item_pressed` has no consumer.**
   `scripts/characters/racer.gd` (~line 170 / 547-563). PlayerController and AIController set
   `controller.item_pressed`, but nothing reads it before `consume_edges()` wipes it each tick.
   `use_held_item()` (racer.gd:563) has ZERO callers → `item_used` never fires →
   `RaceManager._on_item_used` → `PowerupSystem.activate` unreachable. `held_item` never clears,
   so after one pickup, item boxes refuse all further pickups. Entire powerup system dead for all
   8 racers; AI `_should_use_item` is dead code. Verified still true at fb761ac.
   Fix: in `_physics_process` read the edge, e.g. `if controller.item_pressed and state != State.FINISHED: use_held_item()` before `consume_edges()`.
   **Supervisor-verified patch (ran race_sim on a patched clone — PASS, no crash):** insert before `move_and_slide()` in `_physics_process`:
   ```gdscript
   if controller.item_pressed and state != State.FINISHED and held_item != "":
       use_held_item()
   ```

1b. **[FIXED @1636b1e — add_item_row now called in glacier/aurora/iceberg/endless; verified by activation sim] No item boxes spawn on any course — `add_item_row()` has zero callers.**
   `scripts/courses/course_base.gd:434` defines `add_item_row`, but no course script calls it
   (verified by grep across scripts/courses at c8898b1). Even with finding #1 fixed, instrumented
   race_sim shows **0 powerup activations** because no racer can ever hold an item. Both #1 and #1b
   must be fixed for spec §5 "at least five polished power-ups" to be satisfiable.
   Fix: call `add_item_row(...)` at sensible offsets in glacier/aurora/iceberg course builds
   (and Endless segments), then re-run sim and confirm activations > 0.

## HIGH

2. **[FIXED @1636b1e — race.gd:88 defers wire-up via _setup_touch_deferred; sim PASS] TouchControls wired to null controller.** `scripts/gameplay/race.gd:80`.
   `player.setup` is `call_deferred` (race_manager.gd), but `touch.setup(manager.player.controller)`
   runs synchronously in `_ready` while `controller` is still null. TouchControls stores null forever;
   every JUMP/SLIDE/SHOVE/ITEM tap → "Attempt to call function ... in base 'Nil'"; steer drag is a
   silent no-op (null guard). All touch input dead on mobile/touch configs.
   Fix: defer `touch.setup`, or assign `player.controller` synchronously before deferring `add_child`.

3. **[FIXED @prod-round — race_manager.gd:_update_rubberband now uses continuous racer.progress metres; sims 3-course PASS] Rubberband gap uses checkpoint-quantized progress, not meters.**
   `scripts/gameplay/race_manager.gd:189`. Catch-up assistance computed from `total_progress`
   (checkpoint-index granularity) so gap jumps in large steps; boost flips on/off wrongly mid-segment.
   Fix: compute gap from continuous course-distance meters.

4. **[FIXED @prod-round — SceneRouter._change_now forces paused=false (+deferred re-assert); PauseMenu._open refuses while SceneRouter.is_busy(); _exit_tree unpause safety] Auto-pause on focus loss during race→results transition soft-locks.**
   `scripts/ui/pause_menu.gd:121`. Focus-loss pause during the finish/results handoff pauses a tree
   that results flow never unpauses. Fix: gate auto-pause on race state RACING only.

5. **[OPEN] Silent glacier fallback for missing course scripts.**
   `scripts/gameplay/race.gd:74`. Unknown course id falls back to Glacier silently → wrong records
   written under wrong course key; misroutes Endless/Tutorial. Fix: push_error + abort to menu instead.

## MEDIUM

6. **[FIXED @cefbf0d — builder converted hint space; commit message confirms] AI branch hints in wrong coordinate space.** `scripts/ai/ai_controller.gd:138` +
   `scripts/courses/course_glacier.gd:87`. On-branch `racer.progress` is main-line-mapped (~700-930)
   but hints registered branch-local (10-120); `hints_in_range` can never match; `_slide_zone_until`
   same bug. Shortcut slide hint provably unreachable (only opportunistic ICE_SMOOTH slide saves it).
   Fix: store hints in mapped space or convert query to branch-local.

7. **[FIXED @prod-round — floor now gated on downhill_dot >= -0.02 (racer.gd:344), same gate as the ramp; uphill slides bleed to the <5.0 stand-up] Slide min-speed floor defeats uphill stall stand-up.** `scripts/characters/racer.gd:272`.
   Slide branch pushes speed toward ~6.9 m/s while stall check triggers only < 5.0 → racer slides
   uphill indefinitely at half waddle speed; AI opportunistic ice-slide can lock into slow crawl.
   Fix: disable the floor when slope is uphill, or raise stall threshold above floor on uphill.

8. **[OPEN] Endless/Tutorial fallback races finish through `finish_race` while results renders by
   Game.mode.** `scripts/gameplay/race_manager.gd:248`. Mode/flow mismatch on fallback path.

9. **[FIXED @prod-round — main_menu Quit calls SaveManager.save_now() before quit(); Quit also hidden on web where quit() freezes the canvas] Quit button bypasses SaveManager flush.** `scripts/ui/main_menu.gd:42`. Dirty save data
   silently lost on desktop quit. Fix: flush save before `get_tree().quit()` (and on NOTIFICATION_WM_CLOSE_REQUEST).

10. **[FIXED @prod-round — typeof mismatch keeps default (int/float coerced for JSON), version stamped only at top level in load_save; units 50/50] `_merge_defaults` has no type validation, stamps version without migration.**
    `scripts/save/save_manager.gd:134`. Corrupt-typed fields survive merge then crash consumers;
    version bump without migration path violates spec save requirements.

11. **[PARTIAL @prod-round — racer.gd ray queries + exclude arrays now cached per racer; CourseBase.get_guide/PathGuide.nearest dict allocs and get_setting defaults remain] Per-frame heap allocations in core race loop.** `scripts/characters/racer.gd:200`
    (and neighbors). Spec explicitly forbids per-frame allocation in race loops (mobile GC spikes).

## LOW

12. **[FIXED @prod-round — gp_times accumulated per racer; standings sort points desc -> total time asc -> name] GP standings sort has no tiebreaker** — cup winner nondeterministic on point ties.
    `scripts/gameplay/game.gd:88`. Add total-time (or best-finish) tiebreak.
13. **[OPEN] `get_setting` allocates full defaults dict per missing-key call, hit per frame.**
    `scripts/save/settings_manager.gd:66`. Cache defaults.
14. **[FIXED @prod-round — loop_end computed from wav.format + wav.stereo] WAV `loop_end` formula assumes 16-bit stereo.** `scripts/utilities/audio_manager.gd:90`.
    Breaks looping for mono/ADPCM streams.
15. **[FIXED @prod-round — redundant early decay deleted; single 6/s decay remains, root.scale still chases _squash] Squash-and-stretch decays via two competing lerps per frame** — jump/land squash nearly
    invisible. `scripts/characters/penguin_visual.gd:294`.
16. **[FIXED @prod-round — final beep pitch 1.25] Countdown pitch ternary dead code (both branches 1.0).** `scripts/gameplay/race_manager.gd:128`.
17. **[OPEN] GP round mutation + record submission runs inside results UI construction.**
    `scripts/ui/results.gd:124`. Move to game-flow layer (spec: no gameplay logic in UI scripts).

## Environment notes (supervisor-verified)

- Godot 4.7.1.stable at /opt/homebrew/bin/godot — matches spec.
- Export templates for 4.7.1 NOT installed → test exports impossible locally; validate presets +
  document per spec §20.
- Headless race_sim at e190abb exited with `21 ObjectDB instances leaked` + `6 resources still in
  use` — likely hazard framework not freeing nodes/refs. Investigate before mobile pass.
- run_tests.sh at f65cc46 exceeded 10 min wall-clock in supervisor run — keep full suite under
  ~5 min or provide a fast subset flag so validation stays practical.

## Added during prod-readiness round (2026-08-05)

18. **[FIXED — pad moved 70m upstream (course_iceberg.gd) + randomized post-respawn stumble
    (racer.gd:respawn_at_checkpoint)] Iceberg autopilot resonance stuck-loop at the moving-platform
    crossing.** Boost pad 16m before the crossing launched full-speed racers onto a bad platform
    phase; a fixed respawn->arrival period re-met the same phase every retry. Baseline (b0a5c19)
    timed out 3/6 sims; see BUILD_STATUS for post-fix evidence.
