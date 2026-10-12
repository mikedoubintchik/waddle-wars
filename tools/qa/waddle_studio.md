# Waddle Wars Studio

Keep one full-game comparison site with the complete 67-page catalogue and a **Character studies → Penguin model & motion** collection. Do not replace the full catalogue with a separate penguin-only landing page.

The original site-only package used the preserved October 9 iteration-14 gallery in the primary workspace:

`/Users/ninja/Fun/waddle-wars/qa_shots/menu-reference-review-20261009-iteration14/gallery`

Its 134 desktop/phone captures retain their original dates, references, hashes and review limits. They are historical evidence, not a fresh acceptance of the current game. A newly captured gallery must instead be supplied with `--preserve-gallery-iteration`, as described below. The Penguin collection contains separately dated study work; human review remains pending. Packaging either collection does not approve art, promote the candidate into production, refresh game captures, or imply physical-device testing.

## Rebuild the local site

From `/Users/ninja/.codex/worktrees/penguin-visual-strategy/waddle-wars`, use an empty output directory. The packager refuses destructive overwrite; choose a fresh destination when preserving an existing build.

```sh
python3 tools/qa/build_waddle_studio.py \
  --base-gallery /Users/ninja/Fun/waddle-wars/qa_shots/menu-reference-review-20261009-iteration14/gallery \
  --penguin-task /Users/ninja/.codex/worktrees/penguin-visual-strategy/waddle-wars/qa_shots/penguin-motion-corrections-20261012 \
  --output /Users/ninja/.codex/worktrees/penguin-visual-strategy/waddle-wars/qa_shots/waddle-wars-studio-20261012/site
python3 tools/qa/build_waddle_studio.py --validate-only \
  --output /Users/ninja/.codex/worktrees/penguin-visual-strategy/waddle-wars/qa_shots/waddle-wars-studio-20261012/site
```

These paths are also the CLI defaults. The packaged `provenance` directory contains `build-receipt.json`, `package-inventory.json`, and the unchanged `base-gallery-manifest.json`. Preserve these receipts with the output. Validation must pass before browser handoff.

## Preserve a freshly reviewed game gallery

First complete the source-freeze, capture, review, explicit acceptance, `build`, and `delivery-delta` steps in [incremental gallery QA](gallery_iteration.md). Then package that iteration's `gallery` directory with `--preserve-gallery-iteration`:

```sh
python3 tools/qa/build_waddle_studio.py \
  --base-gallery qa_shots/combined-feature-20261012/gallery-iteration/gallery \
  --preserve-gallery-iteration \
  --penguin-task qa_shots/penguin-motion-corrections-20261012 \
  --output qa_shots/combined-feature-20261012/studio/site
python3 tools/qa/build_waddle_studio.py --validate-only \
  --output qa_shots/combined-feature-20261012/studio/site
```

This mode preserves all 67 routes and 134 desktop/phone entries when supplied by that gallery, including its **This turn** filter, `affected_routes`, `fresh_views`, pending counts, per-view change flags, acceptance/status, iteration, plan, source fingerprint, and original media/provenance. Partial iterations remain partial; pending views do not become accepted. Dates in the Studio note come from the actual capture provenance, so a fresh gallery is not labeled October 9 evidence.

The receipt distinguishes `preserved_gallery_fresh_views` (captures already made for the supplied iteration) from `new_game_page_captures: 0` (the packager generates no captures). `this_turn_routes` matches the supplied iteration. `human_approval: false` means packaging grants no new approval; existing per-view evidence is retained unchanged. The separate Penguin study collection is not relabeled as production evidence by this flag.

Use the flag only when preserving the supplied gallery's iteration as the current review. Omit it for a site-only update built from an older gallery: that default still clears This turn activity and marks the game evidence as historical. Do not infer freshness from an output directory's name or the current date.

## Collection integration

The packaged root keeps the original game rows and supplies these presentation fields:

```json
{
  "studio_note": "Game pages preserve their recorded capture dates and review status. Penguin studies remain separately dated evidence.",
  "studio_collections": [{
    "id": "penguin",
    "title": "Penguin model & motion",
    "path": "penguin/studio/index.html",
    "note": "Candidate · review pending"
  }],
  "affected_routes": []
}
```

In the default site-only mode, `affected_routes` is empty; it must not inherit an old gallery's capture activity as work from this turn. With `--preserve-gallery-iteration`, the source gallery's exact route list and per-frame activity remain available in **This turn**. Both modes leave the source manifest unchanged and keep Character studies available.

`#collection=penguin` opens the local study inside the root gallery. Selecting a game page unloads the study and restores the two-image comparison with the same orientation and filter. Collection paths must be relative local HTML paths; external URLs, traversal and query destinations are rejected. Empty or absent `studio_note` stays hidden.

## Verify and review

Run these checks from the worktree:

```sh
node tools/qa/gallery_assets/gallery.test.mjs
/Users/ninja/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tools/qa/test_gallery_iteration.py -q
/Users/ninja/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tools/qa/test_build_waddle_studio.py -q
```

The local Studio address is `http://127.0.0.1:60253/`. Serve the packaged `site` directory, not either source workspace. Browser review must confirm all 67 page links, both capture orientations, actual capture dates/status, Penguin navigation, and return-to-page cleanup. Check the populated **This turn** routes/counts for a fresh preserved iteration, or the unchanged-captures empty state for a historical site-only update.

```sh
python3 -m http.server 60253 --bind 127.0.0.1 \
  --directory /Users/ninja/.codex/worktrees/penguin-visual-strategy/waddle-wars/qa_shots/waddle-wars-studio-20261012/site
```

Reuse an existing coordinated server on this port rather than starting a duplicate.

Future updates continue through the full catalogue plus Penguin collection. Preserve prior proof directories and source manifests; build a fresh destination and verify its receipt before changing any current pointer. Actual game changes still follow [incremental gallery QA](gallery_iteration.md); packaging is not a substitute for its capture and acceptance gates.

## Add a full-scene water comparison

The reusable October 12 water packager and capture validator now live in
`tools/qa/build_water_review.py` and `tools/qa/validate_water_capture.py`.
The copies under dated `qa_shots` directories and their receipts remain historical
evidence. Existing Studio outputs and original captures are local review inputs;
they are not recreated by a source checkout or silently treated as current proof.

The water packager requires an already validated Studio, an empty output path,
and a JSON review config. All input paths may be absolute or relative to the
config file, so no particular checkout location is required:

```sh
python3 tools/qa/build_water_review.py \
  --base-site qa_shots/previous-studio/site \
  --output qa_shots/current-studio/site \
  --config qa_shots/current-water/review-config.json
python3 tools/qa/build_waddle_studio.py --validate-only \
  --output qa_shots/current-studio/site
```

The config requires `review_date`, `title`, `summary`, `verdict`,
`comparison_limits`, `visual_status` (`ready_for_review` or `residual_gap`),
`human_approval: false`, and `frames`. Each frame has a unique `id`, `label`,
`device` (`desktop` or `mobile`), `action`, `phase`, and paths named `current`,
`sidecar`, `previous`, and `reference`. Both device views are required. The
`current` hash must match the paused capture sidecar. Supply an explicit date
for a new review; do not edit an archived config to imply newer evidence.

The `#collection=water` view defaults to uncropped reference and current frames.
An optional previous-version column preserves the prior evidence. The packager
keeps the inherited game catalogue, dates, pending views and original media bytes.
Public sidecars are sanitized; receipts bind their raw and sanitized hashes.
Human approval and production promotion remain false. This presentation step
does not validate runtime integration or approve the unfinished front/podium art.

For a **new isolated water-only candidate**, first take the gallery turn-start
snapshot, complete edits, and freeze the exact QA source before export/capture:

```sh
python3 tools/qa/validate_water_capture.py freeze \
  --task qa_shots/current-water
# Prepare the isolated export and capture final desktop/phone originals.
python3 tools/qa/validate_water_capture.py validate \
  --task qa_shots/current-water \
  --export qa_shots/tests/current-water-export \
  --previous-task qa_shots/previous-color-review
```

Use `--root /path/to/checkout` before `freeze` or `validate` when running from
another checkout. The validator requires Pillow and the original gallery
`source-start.json`. It binds the frozen model, current water recipe, prepared
files, PCK, and six full-scene captures: waddle at 0, jump at 0.5, slide at 0.25
on desktop (1920×1200) and phone (430×932; logical 800×1733). Previous environment
sidecars must be in `candidate-originals/<device>/rear/<action>/frame-NNN.json`
with indices 000, 002 and 001 respectively. It verifies unchanged production
runtime and unchanged nonwater environment; therefore it is deliberately not
the validator for a promoted runtime integration. That integration needs fresh
gallery verification and runtime tests. It also rejects old freezes after
source or validator changes; preserve archived receipts instead of relabeling them.

```sh
python3 tools/qa/test_build_water_review.py -q
python3 tools/qa/test_validate_water_capture.py -q
python3 tests/test_penguin_build_inputs.py -q
```
