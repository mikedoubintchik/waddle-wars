# Candidate preview path

Review the character inside the actual runner. Front and side controls move its camera around the same player instance; they do not construct a second character or replace its materials. Chase restores the game camera. Run, jump and slide use the existing staged runner QA routes.

## Current fixture

The available canonical `hero_penguin_v1.glb` proves integration. It uses the unchanged `HeroPenguinRig`, semantic vertex colors, production shader and production albedo/normal/ORM textures. This is not a new sculpt or approval of its appearance. Normal production still uses its existing procedural backend; authored selection is restricted to the isolated review project. No complete V12 candidate package is available in this workspace.

The browser receipt reports the actual loaded scene, imported mesh/skin signatures, active shader source hash, texture paths/dimensions, material parameters and effective palette. Host package hashes bind the original files; they are labeled separately from resources actually imported by the renderer. Switching camera must preserve the active signature. A fallback, changed shader, global override, overlay or extra material pass fails review.

## Browser review

From the worktree root, after source changes and local checks are complete:

```sh
python3 tools/qa/chrome_reference_export.py prepare qa_shots/tests/NEW-preview --hero-candidate-runtime
python3 tools/qa/chrome_reference_export.py build qa_shots/tests/NEW-preview --silent
python3 tools/qa/chrome_reference_export.py serve qa_shots/tests/NEW-preview --port 60254
```

Use the exact localhost URL/token from `server.json`, with `qa_route=runner_hud`. Keep Chrome's QA resource watcher active. Candidate review controls appear only in this export. The build disables external auth/API traffic, uses isolated save data and requests Dummy audio. The manifest explicitly marks it ineligible for the shipping screenshot gallery.

Review both desktop and touch-emulated phone layouts. Set device metrics and touch input before engine startup. A 430 × 932 phone profile with `qa_device=iphone15promax` should report an 800 × 1733 logical viewport. This is browser emulation, not physical-phone evidence. Follow the [one final capture pass](../../tools/qa/gallery_iteration.md) rule. Save original frames with `__wwQA.read()`, `__wwHeroCandidate.read()` and `__wwQABuild` receipts.

## Native candidate preparation

```sh
python3 tools/art/run_hero_v12_runner_review.py prepare \
  --candidate-glb assets/art/characters/hero_penguin_v1.glb \
  --material-mode runtime \
  --output-dir qa_shots/hero/NEW-runtime-proof
```

Preparation imports a fresh isolated project and validates both the facade and actual runner. It selects the authored backend only around player construction and restores the previous flag. Interactive play uses the same validation and cannot bypass it. Capture/play commands retain their existing rendered-evidence gates.

The runtime fixture requires the exact canonical GLB and preserves its importer parameters. The default literal mode still requires two literal `COLOR_0` surfaces. Atlas candidates use `run_hero_v12_atlas_runner_review.py` and its existing verified package contract. These material contracts are intentionally distinct; an arbitrary artist export cannot inherit semantic mask interpretation accidentally.

Prepared projects bind all inputs, including helper scripts, material files, maps and import settings. Any change requires fresh preparation. Headless success proves selection/structure only: the engine uses a neutral headless material and explicitly reports `material_parity_verified=false`. Rendered browser evidence supplies the material check.

## Focused checks

```sh
python3 -m unittest tests.test_hero_v12_runner_review tests.test_hero_v12_atlas_runner_review tests.test_hero_candidate_session tests.test_chrome_reference_export tests.test_hero_candidate_export
```

In a prepared isolated project, also run `tests/hero_candidate_session_test.tscn`, `tests/hero_penguin_controller_test.tscn` and `tests/penguin_authored_only_test.tscn` headlessly with Dummy audio. Preserve engine logs: exit zero alone does not establish success if script/resource errors are present.
