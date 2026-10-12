# Reviewed runner promotion

The October 12, 2026 integration activates the reviewed penguin and DAY water in normal gameplay. No candidate flags or sibling QA replacement model are required. Runtime activation does not imply completion of the deferred front/podium design, other species, or physical-device performance review.

## Penguin identity and import

- Runtime model: `assets/art/characters/runner_penguin_v1.glb`.
- Exact source: `art_src/characters/penguin_motion_v1/candidate.glb`.
- Both GLBs have SHA-256 `206632fc655b49dc590caa621b01f2ce83ccd3108ff4a4c82787e0e8a016eef2`.
- Import binding: `assets/art/characters/runner_penguin_v1.json`; settings: adjacent `.glb.import`.
- Post-import scripts: `scripts/characters/runner_penguin_post_import.gd` and `runner_surface_post_import.gd`.

The runtime copy retains the fresh 15-bone skeleton, one 14,720-triangle surface, and three embedded 1024px maps. The importer preserves unoptimized animation keys, declared loops, and lossless mip chains with normal-aware normal-map generation. Standard PBR remains authoritative: imported albedo/normal/metallic-roughness maps, normal scale 0.65, and source-authored specular 0.15. `HeroPenguinRig` and its separate legacy material/clip contract remain unchanged.

## Selection and ownership

`RunnerPlayer.setup()` calls `PenguinVisual.setup_runner_look()`. The classic emperor with no hat, scarf, or goggles selects `ReviewedRunnerPenguin`; cosmetic trails remain supported. The same `PenguinVisual` owns visibility for both the reviewed model and its hidden procedural fallback, so normal player visibility updates cannot reveal a second penguin.

The adapter plays the imported `waddle`, `jump`, and `slide` clips. The neutral jump endpoint supplies idle rest. Gameplay owns forward travel, lane changes, collision, vertical motion, and ramp rotation. The adapter samples jump articulation from actual vertical velocity and launch speed, including fast-fall; it never adds a second ballistic height. Repeated slides retain their animation phase. Ordinary hits add a brief presentation response while retaining the reviewed mesh and material.

Gameplay scale is `0.6201416744371788`, giving the reviewed 1.05m rest height. Rest soles seat against the actual visible `GlacialIceSkin` or `Deck`; floor changes update the local offset without changing the player, collider, camera, or animated limb geometry.

Other species, equipped head/neck/face geometry, racing, menus, and podium views retain the established renderer. Rear death/catch presentation uses the reviewed slide. The explicit desktop face-first `present_catch_face()` call switches to the existing finished-face renderer for the remainder of that run. The candidate has no approved front design; this fallback remains intentional until that gate is completed.

`PenguinVisual.reviewed_runner_snapshot()` reports the actual visible renderer, clip/time, transform, imported material identity, map dimensions, and visible procedural mesh count. Declared source identity is separate from the observed raw GLB hash: exported PCKs may retain only the imported scene, so an absent observed raw hash is not evidence of changed source bytes.

## DAY water and scene color

[`runner_day_water_v6.json`](runner_day_water_v6.json) records the historical recipe hash, five promoted runtime files, and their before/after hashes. Normal runtime now includes the DAY lighting, ice, sky, and water changes. The water uses the existing painted texture and filtering, calibrated blue facets, sparse highlights, angular lateral mapping for the runner camera, and a slower DAY haze transition. Other biomes retain the existing interpolated behavior. This camera-specific mapping is not a general-purpose ocean material.

`tools/qa/runner_color_candidate.py` remains a historical replay against its exact pre-promotion source fixture. Do not run its `--runner-color-review` path against current promoted sources; ordinary exports already contain the change.

## Local verification and final gallery

From the repository root, use the existing isolated suite runner. It copies resources into a temporary project identity, rebuilds imports, and uses separate save data:

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot ./run_tests.sh reviewed_runner_penguin
```

The focused scene checks actual runtime asset/import identity, live-player visibility, physics/articulation ownership, jump lean, slide continuity and limb motion, ramp timing, and fallback behavior. It does not establish artistic approval, browser rendering fidelity, or the complete pre-push gate. Run the full applicable suite separately before remote work; retain actual logs and pass/fail/skip counts.

Follow [`tools/qa/gallery_iteration.md`](../../qa/gallery_iteration.md) for the final gallery: one immutable turn-start snapshot, finish edits and local checks, freeze sources, then run `plan`. Use its full desktop/mobile matrix; add affected routes explicitly when import settings change. Capture the ordinary game export through the coordinated silent Chrome workflow. The `runner_character_waddle`, `runner_character_jump`, and `runner_character_slide` routes exercise ordinary character actions without installing a candidate replacement or synthetic power-ups.

Run `review`, inspect original full-scene frames against references, and record explicit acceptance only for inspected valid frames. Then run `build` and `delivery-delta`. Preserve the full catalogue, historical dates, and pending views; keep private raw receipts outside the public gallery and update any current pointer last. These are required commands and evidence rules, not a claim that a particular revision has passed them.
