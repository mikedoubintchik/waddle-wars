# Combined integration validation — 2026-10-12

Branch: `codex/main-penguin-integration`. Scope: combined main-workspace and
penguin worktree changes, including the production runner character, camera,
water, menu work, backend changes, and review tooling.

## Local checks

| Check | Verified result |
| --- | --- |
| Complete isolated suite and affected reruns | 171 headless groups passed: 123 Godot and 48 host groups. All six deferred renderer fixtures subsequently executed; see the diagnostic limit below. |
| Final runner subset | 57 groups: 56 effective headless passes and one separately executed renderer diagnostic. Golden framing rerun passed 29/29 after aligning its expectation with the current reference contract. |
| Godot numeric summaries | At least 19,419 passed checks across 103 headless groups; another 20 passing groups provide no complete numeric total. Separate review bridge: 177/177. |
| Python inventory | All 81 modules: 1,428 passed, zero unresolved skips. Includes release helpers, art/provenance, water review (22), and Studio packaging (15). |
| Node and backend | 337 TAP cases; 45 engine-source model checks; 12 local workerd cases; three Worker dry-run bundles. Synthetic SQLite schema and migration checks use fresh local databases. |
| Native authentication | Foundation-only Swift policy: 36/36. |
| Test harness | 16 isolation/watchdog/class-cache guards and 11 diagnostic-filter guards passed. |
| Art integrity | Development review validation passed: 753 assets, 43 exports, 657 generated assets and 113 concepts. |

Counts overlap between the complete suite and independent host runs; they must
not be added together. The optional historical-geometry case was rerun against
the original Git baseline: 4/4, zero skips.

The original complete run exited nonzero. Its four failures were fixed and
superseded by verified reruns: menu composition 227/227, navigation 124/124,
resource lifetime 63/63, and biome readability 121/121. Subsequent production
camera and foot seating checks passed 64/64 and 1,330/1,330. Original failures,
raw logs, rerun hashes, and per-group counts remain in the local receipts.

## Actual renderer checks and remaining limit

Eight native fixtures completed: seven functional passes and one valid DUSK
coverage diagnostic. Compatibility and Mobile atlas checks passed 23/23 each;
HUD layout passed 536/536; initial warmup passed 8/8. Orientation, four shader
raster probes, and the mobile menu audit also passed. The menu audit saved 30
captures and checked 24 fresh/live layouts.

The DUSK diagnostic is **valid and complete, but exhaustive coverage fails**:
`fixture_valid=true`, `complete=true`, `errors=[]`, and
`production_surface_coverage_pass=false`. At the observed 2× MSAA, deck, seams,
verge body, crown, drop and snow produced respectively **2, 1, 1, 0, 0, 2**
resolved pixels. All six enlarged controls rendered. The fixture execution gate
checks validity; it does not establish complete warmup coverage or elimination
of the hitch. This limitation predates this integration; see the DUSK raster
notes in [BUILD_STATUS.md](../../BUILD_STATUS.md).

## Web export and browser review

The final ordinary release export uses the reviewed character and DAY water
without candidate overrides. Fresh import and export passed. The package is
**218,098,028 bytes** against a 220,000,000-byte budget, with 599 verified texture
imports and 1,863 pack entries. Its SHA-256 is
`d3f21adf5702827c44720f81ae731101d451d98ce711db6d103428c72b24f233`.
The build receipt is `qa_shots/tests/combined-feature-20261012-final/build.json`.
Audio used the Dummy driver and authentication used offline visual QA isolation;
this verifies production rendering and wiring, not live authentication or sound.

Chrome boot and review completed on the frozen export: **67 routes × two
viewports = 134 accepted views, zero pending**. Desktop captures use 1920×1200;
phone captures use 430×932 with touch enabled before boot and simulated safe
insets. These are browser simulations, not physical-device results. Six additional
unobscured gameplay captures cover desktop and phone waddle, jump, and slide.
They show one visible reviewed character, actual animation clips, preserved
material maps, and normal gameplay physics. Each was compared with the prior
reviewed preview and original scene reference; no blocking integration regression
was found. Stills do not establish continuous motion quality or pixel matching.

The final Waddle Wars Studio package preserves the complete page list, dated
history, and This turn view. Validation checked **1,914 local links and 1,982
output hashes**, with no missing files or localhost dependencies. Agent visual
acceptance is recorded in `gallery-iteration/accepted-captures.json` beneath
`qa_shots/combined-feature-20261012/`; it is not human art approval. Final review
and comparison receipts are in that directory's `checks/` folder. No remote
publication was performed.

The gallery plan ID is
`0c070956a5eb437ad08b31672eafe6962673f353ae190aa93907e22bfc9bf1a1`;
its frozen runtime fingerprint is
`9b49dc48440803acb239e5de3b255bcceac1df7798897fbbe2cf33309a1ab48d`.
The export preparation fingerprint is
`73d8aca87f9ed8e220680d85de43e472bc0f3bf61d624cdc759fe69410c3d75c`.
These inventories have different scopes and are not Git commit IDs.

## Evidence and release scope

Detailed evidence remains locally under
`qa_shots/combined-feature-20261012/checks/`: `HEADLESS-VALIDATION.json`,
`NATIVE-VALIDATION.json`, `host/FINAL-HOST-VALIDATION.json`, and
`host/final-ci-gate-audit.json`. The DUSK report is
`qa_shots/combined-feature-20261012/native-verified/dusk/report.json`.
Receipts retain exact commands, source inventories, hashes and superseded logs.

The audited repository has no code workflows or path filters, no required
status checks, and no branch rulesets. Remote CI is not required; none was
dispatched for validation. The Git LFS pre-push hook remains enabled.

This is development integration evidence. Art still contains 217 unresolved
review entries; strict production art readiness and human visual approval are
not asserted. The reviewed model is active for the default Emperor rear runner
without equipped head/body accessories. Other species, equipped accessory
geometry, menus, podium/front views, and the explicit front-facing catch retain
the established renderer. Signed store builds, real purchases, and real-device performance
were not exercised by these local checks.
