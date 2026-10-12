# Incremental screenshot comparisons

Keep one full catalogue. Refresh only pages affected by source changes. The gallery always keeps its left sidebar and uses exactly two reusable full-image elements. "This turn" filters the text navigation; it does not preload images.

## One capture pass per completed turn

Take one turn-start snapshot before edits. Finish every requested change and local check, then freeze sources and capture at the end of the entire turn. Do not capture each internal sub-iteration or partial fix. Intermediate plans are metadata-only. CLI iteration labels remain durable receipt IDs; they do not imply multiple capture passes per user turn.

Use the bundled Python with Pillow already installed; no package install needed. From the repository root:

```sh
GALLERY_PYTHON=/Users/ninja/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3
```

On another host, set `GALLERY_PYTHON` to a Python3 interpreter that can import Pillow (`PIL`). The system `python3` on this Mac cannot.

```sh
"$GALLERY_PYTHON" tools/qa/gallery_iteration.py start \
  --dir qa_shots/menu-reference-review-NEXT \
  --base qa_shots/menu-reference-review-PREVIOUS/gallery/manifest.json \
  --label NEXT

# Finish all work for this turn, test and freeze production sources. Then:
"$GALLERY_PYTHON" tools/qa/gallery_iteration.py plan --dir qa_shots/menu-reference-review-NEXT
```

`source-start.json` is immutable. `plans/<hash>/source-end.json` and `plan.json` preserve every distinct plan. `capture-request.json` points to the latest plan and contains its complete desktop/mobile matrix. Added, modified and deleted files all count, regardless of Git status. Repeating an unchanged plan keeps its original receipt.

The scope covers `assets`, `data`, `scenes`, `scripts`, `shaders`, `addons`, `native`, `web`, `project.godot` and `export_presets.cfg`. Generated `.godot` caches, `.import` sidecars, Python caches, tests, receipts and source-art archives are excluded. If an import-setting change itself is the visual edit, explicitly add its routes with `plan --routes ROUTE ...`; the normal source inventory does not prove importer settings. Preserve the export/import receipt with the capture evidence.

`gallery_dependencies.json` is explicit and copied into each iteration. All matching rules are combined. Unmapped runtime changes affect **every** route. Changes to shared helpers/configuration are broad by design. Narrow a mapping only after inspecting actual consumers; never remove a route just to lower the capture count.

For the first migration from an older gallery, add `--base-source PATH/manifest.json`, pointing to its verified production-wrapper export manifest. This catches changes made since the last published gallery, in addition to this iteration's edits. Later incremental galleries automatically retain the previous source snapshot and pending status, including edits made between turns.

## Capture and review

Root/coordinator owns browser, export and review. The tools launch no engine, browser, server or uploader. Expected originals:

```text
ITER/originals/desktop/ROUTE.jpg
ITER/originals/desktop/ROUTE.json
ITER/originals/mobile/ROUTE.jpg
ITER/originals/mobile/ROUTE.json
```

JPEGs stay byte-identical. JSON can contain direct scalar state or the older `{ "state": ... }` wrapper. Capture state requires route, ready status, empty error, capture timestamp, canvas backing dimensions, touch points, source URL and build identity. Silent isolated visual QA requires `runtime_audio_driver: Dummy` and `qa_auth_isolation: offline_visual_qa`. A portrait desktop-input capture is explicitly labeled; it is never promoted to physical-phone or touch proof.

Set CDP device metrics and touch emulation **before the Godot engine starts**.
If the page already loaded, reload after applying those overrides and wait for
the QA ready gate. Godot caches touchscreen availability at startup: changing
`navigator.maxTouchPoints` afterward can produce a misleading touch sidecar
while the game still uses desktop scaling and has no touch-scroll helpers.
Verify the logical viewport as well as the CSS/backing dimensions. For the
current 430×932 phone profile, actual touch startup yields 800×1733 logical
pixels; 1080×2340 indicates desktop input scaling. Switch back to desktop by
disabling touch and clearing the simulated phone safe-area query before another
engine reload. Keep an invalid setup's originals as rejected evidence rather
than silently overwriting an accepted set.

```sh
"$GALLERY_PYTHON" tools/qa/gallery_iteration.py review \
  --dir ITER --export qa_shots/tests/FROZEN_EXPORT
```

This emits `review-draft.json` with **accepted=false**, per-frame validation errors and exact hashes. After visual inspection, create a separate `accepted-captures.json`: set top-level `accepted=true`; keep only inspected frames; set each frame's `accepted=true`, `reviewed_by`, `reviewed_at`, and an honest `note`. Do not discard validation errors without fixing their cause. Partial acceptance is allowed for a local preview; publication stays blocked until every affected view is accepted.

```sh
"$GALLERY_PYTHON" tools/qa/gallery_iteration.py build --dir ITER --acceptance ITER/accepted-captures.json
"$GALLERY_PYTHON" tools/qa/gallery_iteration.py delivery-delta --dir ITER
```

Both commands recheck current runtime files against the planned snapshot. The capture export must match that source inventory and actual PCK hash. Each image/sidecar hash, route, error, timestamp, dimensions, browser, input mode and source/build identity is checked again. If final review rejects a frame, keep the turn unfinished, repair the concrete defect, then repeat only required final views after the source is frozen again. Planned intermediate edits never trigger captures. Editing an approval or image after build invalidates delivery.

`gallery/index.html` shows affected older frames with a prominent **PREVIOUS CAPTURE · REFRESH PENDING** label. Unaffected captures preserve exact bytes, dates and builds. New comparisons and six-state overview sheets contain full uncropped source images; only derived comparisons are JPEG encoded. Raw captures and references are never altered. Raw private sidecars remain outside the public gallery; sanitized copies remove QA tokens.

## Previously accepted but unpublished captures

Use an explicit mapping to avoid guessing filenames/states:

```json
{"captures":[{"id":"cosmetic_shop","orientation":"desktop",
  "path":"qa_shots/tests/OLD/chrome/desktop-shop-low-fish.jpg",
  "sidecar":"qa_shots/tests/OLD/chrome/desktop-shop-low-fish.json",
  "source_iteration":"prior shop correction",
  "note":"Actual low-balance state; paid checkout not exercised."}]}
```

```sh
"$GALLERY_PYTHON" tools/qa/gallery_iteration.py review --dir ITER --export OLD_EXPORT \
  --historical-map prior-capture-map.json --output ITER/prior-review-draft.json
```

The draft has `historical=true`; explicit review is still required. Then add `--historical ITER/prior-accepted.json` to `build`. These frames keep their original date/build and do not count as freshly captured this iteration. If their affected source changed again, they remain pending. Route aliases require explicit `state_route` plus exact `state_checks` predicates; another page's screenshot is never silently substituted.

## Limited delivery

`delivery-delta.json` lists content hashes, sizes, `reuse`/`upload`, prior paths and only new comparison/overview/document bytes. It performs no remote writes. The existing bounded Drive uploader can reuse previous verified IDs by exact SHA; upload only jobs marked `upload`, verify returned metadata, regenerate links, and update CURRENT last. Keep sharing and prior collections intact. No full-gallery reupload is required.

## Local checks

```sh
"$GALLERY_PYTHON" tools/qa/test_gallery_iteration.py -v
node tools/qa/gallery_assets/gallery.test.mjs
```

Tests cover untracked additions/deletions, unknown fallback, unchanged byte/date preservation, pending/failed/partial frames, source edits after planning, corrupt captures/sidecars/builds/dimensions/timestamps, duplicate/obsolete approvals, delivery revalidation, and two-image navigation/filtering. No browser or engine required.
