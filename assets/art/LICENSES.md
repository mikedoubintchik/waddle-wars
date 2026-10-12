# Runtime art licenses

Approved license IDs:

## `project_original`

Created specifically for Waddle Wars and cleared for project distribution.
Source provenance must exist in `art_src/runner/LICENSES.md` before runtime
manifest registration.

This base manifest lists the expedition title backgrounds, loading penguin,
and premium title/loading wordmark.
Additional runtime exports are registered by `data/art/fragments/*.json`; their
source and hashes must be reviewed with this ledger. The user-supplied penguin
reference is source-only and has unknown provenance; see the open review in
`art_src/runner/LICENSES.md`. Do not infer final rights clearance merely from
a `project_original` tag in a fragment.

## Desktop menu refresh — 2026-10-07

Project-original ImageGen artwork: `assets/art/ui/menu/` desktop background
files `base_camp_desktop_background_v2.webp`,
`leaderboard_desktop_background_v2.webp`,
`runner_results_desktop_background_v2.webp`, and
`runner_complete_wordmark_v2.webp`. Editable source PNGs and exact briefs are
retained in `art_src/ui/menu/desktop_refresh_v2.prompt.md` and its sibling
files. Inputs were existing project-owned menu references. Runtime controls
render all changing text and values; sample scores in concept art are not
runtime data. These four runtime files total approximately 1.6 MiB.

## Runner HUD refresh — 2026-10-07

Project-original built-in ImageGen artwork:
`assets/art/ui/runner/runner_hud_icons_v1.webp`. The 1536×1024 transparent
atlas contains heart, magnet, shield, x2, pause and avalanche icons; runtime
controls select atlas regions and render changing labels and values. Source
PNG and exact prompts are retained in `art_src/ui/runner/`; registration and
SHA-256 hashes are in `data/art/fragments/runner_hud_v1.json`.

Runtime WebP is a format conversion of the generated PNG with identical alpha;
no background removal or painted-pixel edits were applied. Landscape and
portrait PNGs are design references only and are not runtime screen images.
Inputs were approved project menu art and current project gameplay. Provenance
details are in `art_src/runner/LICENSES.md`. This local candidate remains
`production_ready: false` pending final rendered and performance review.

## Painted runner course — 2026-10-07

Project-original built-in ImageGen materials:
`assets/art/runner/textures/runner_painted_ice_v1.webp` and
`assets/art/runner/textures/runner_painted_snow_v1.webp`. Both runtime textures
retain the 1254×1254 generated source dimensions; WebP conversion only.
Source PNGs and exact prompts remain in `art_src/runner/painted/`.
`data/art/fragments/runner_painted_v1.json` records immutable source/runtime
hashes and registers both textures as local review candidates with
`production_ready: false`. The course reference PNG remains art direction
only. Inputs were approved project menu art and current project gameplay;
see `art_src/runner/LICENSES.md` for roles and review status.

The same source/runtime ledger also registers
`assets/art/runner/textures/runner_painted_water_v1.webp` (1254×1254,
198,630 bytes). Its untouched generated source and exact brief are
`art_src/runner/painted/runner_painted_water_v1.png` and
`runner_water_v1.prompt.md`. The project course reference supplied style
direction; runtime conversion used WebP quality 94 with no resizing.

Project-authored material programs apply those textures and the same painted
palette: `assets/art/runner/materials/runner_painted_surface_v1.gdshader`,
`assets/art/runner/materials/runner_painted_sea_v1.gdshader`, and
`assets/art/runner/day/materials/runner_day_palette_v2.gdshaderinc`. The DAY
surface/shell shader and material revisions retain their original source
ownership; updated hashes are recorded in `runner_day_kit_v1.json`. These code
resources are original project work, not ImageGen output, and remain review
candidates under `project_original`.

## `reference_unverified` (source-only)

Source-only art-direction input. Ownership and redistribution rights are not
established. No runtime asset or export may use this ID. It does not clear
derived work; inspect the open hero-material review before store attestation.


## Settings / Account reference reconstruction v2 (2026-10-07)

- `settings_account_reference_atlas_v2`: built-in ImageGen transparent cutouts based on approved `art_src/ui/menu/settings_v1.png` and `account_v1.png`. Actual1254×1254 RGBA. Comfort penguin, explorer portrait, blank leather journal and six page pictograms; no baked labels/state.
- `settings_cabin_blank_v2`: built-in ImageGen edit of approved settings cabin; removed only the embedded penguin so hero can follow live panel layout. Actual941×1672RGB.
- Source PNGs/prompts: `art_src/ui/menu/`; runtime siblings: `assets/art/ui/menu/`. WebP quality94 conversion only, no resizing; atlas alpha preserved. Hashes and ownership: `data/art/fragments/settings_account_reference_v2.json`.
- Generator model/build identifier not exposed. Project-original AI-generated assets; human originality review remains pending. `production_ready: false` retained. Consumed by page-local `SettingsAccountArt`, `settings_premium.gd` and account-only main-menu composition. No auth/save data baked into artwork.

- Additional `account_background_landscape_v2`: built-in ImageGen landscape adaptation of approved Account portrait,1672×941, two unchanged explorer identities left, calm snow courtyard right. Source/prompt and same-size WebP quality94 runtime recorded in `settings_account_reference_v2.json`; project_original, human review pending, production_ready false.


## Runner HUD / results and menu reference assets (2026-10-07)

Built-in ImageGen under project art direction; model/build identifier not exposed. Exact prompts and approved input references live beside source PNGs. Project-original AI-generated artwork; human originality review pending. Registration remains `production_ready: false`.

| Asset | Preserved source | Runtime |
| --- | --- | --- |
| `runner_hud_chrome_v2` | 1536×1024 RGBA | 1536×1024 RGBA |
| `runner_end_icons_v3` | 1536×1024 RGBA | 1536×1024 RGBA |
| `runner_results_portrait_background_v3` | 941×1672 RGB | 941×1672 RGB |
| `mission_wood_plaque_v2` | 2172×724 RGBA | 1024×342 RGBA |
| `penguins_background_landscape_v2` | 1671×941 RGB | 1671×941 RGB |

HUD chrome: blank illustrated challenge panel, gap meter backing, powerup tile and ice fill; approved HUD references. Run-end icons: six transparent cutouts based on approved runner pause/results screens. Results portrait: approved exact scene with UI/text removed, original seated scarf-penguin preserved. Mission plaque: new blank snowy wood/parchment material. Wardrobe landscape: approved desktop scene with UI and hero removed for live controls and selected species.

Source PNGs preserved intact. HUD/end/icons/results runtime images use same-size format conversion; mission plaque resized2172→1024px wide at WebP quality90 with alpha retained; wardrobe original1671×941 converted WebP quality90. Full hashes, source ownership and dimensions: `data/art/fragments/runner_menu_reference_v3.json`. Runtime import contract: compress/mode0 and mipmaps=true, including non-power-of-two images. No gameplay values, actual account information, or interactive state baked into these assets.

## Loader, controls and credits reference assets (2026-10-07)

Built-in ImageGen under project art direction, model/build identifier not exposed. Project-original AI-generated artwork; human originality review pending, `production_ready: false`. Five loader cutouts/plate (`loader_courier_v3`, `loader_track_v3`, `loader_card_v3`, `loader_logo_v3`, `loader_background_v3`) derive from approved `loader_theme_v2.png`. Controls cabin and nine-icon atlas derive from `controls_v1.png`; blank credits journal derives from `credits_v1.png`. Sources preserved intact; exact generation provenance and runtime transforms in `art_src/ui/menu/loader_fidelity_v3.prompt.md` and `controls_credits_fidelity_v2.prompt.md`. Runtime/source SHA256 and source dimensions recorded in `data/art/fragments/menu_loader_controls_v3.json`. Native imports use compress/mode0 and mipmaps=true. Live progress, remappable bindings, license text and all actions remain real controls.

- Additional `runner_pause_background_v2`: built-in ImageGen edit of approved pause reference into UI-free scene plate; source941×1672RGB, runtime941×1672RGB. Source/prompt preserved, same-size WebP conversion; source/runtime hashes in `runner_menu_reference_v3.json`. Project-original, human review pending, production_ready false; import compress0+mipmaps true.

- Additional `runner_pause_landscape_background_v2`: built-in ImageGen landscape recomposition of the approved pause scene, preserving the complete scarf penguin at left with a quiet course at right. Source1672×941RGB, runtime1672×941RGB; same-size WebP quality92 conversion. Source/prompt preserved under `art_src/ui/menu/`; hashes in `runner_menu_reference_v3.json`. Project-original, human originality review pending, `production_ready: false`; import compress0+mipmaps true.


## Feedback and wardrobe navigation (2026-10-07)

Built-in ImageGen under project art direction; model/build identifier not exposed. Feedback penguin source and runtime remain identical 1536×1024 RGBA PNGs. Wardrobe navigation atlas retains its 1254×1254 RGBA source; runtime conversion is lossless WebP with real alpha. Original prompts and images remain under `art_src/ui/menu/`; exact hashes and local review status are recorded in `feedback_reference_v1.json` and `wardrobe_category_icons_v2.json` under `data/art/fragments/`. Project-original AI-generated assets; human originality review pending, `production_ready: false`. Three complete outfit samples under `art_src/ui/wardrobe_concepts/` are direction concepts only and are not runtime assets or approved catalog entries.

## Race mode reference regions — 2026-10-07

Project-original existing ImageGen reference `art_src/ui/menu/race_mode_select_v1.png` copied losslessly to `assets/art/ui/menu/race_mode_reference_v1.png`; runtime AtlasTexture regions isolate illustrated card scenes and static wood plaque. See `art_src/ui/menu/race_reference_regions_v1.prompt.md` and fragment `race_reference_regions_v1.json` for provenance and source hash. No new image generation or third-party art.

Race flag penguin: project-original reference-derived ImageGen `art_src/ui/menu/race_flag_penguin_v1.png`; transparent source preserved, runtime compression-only WebP. Exact prompt/retry outcome/visual review in `art_src/ui/menu/race_flag_penguin_v1.prompt.md`.

Utility landscape backgrounds v3: project-original ImageGen edits of approved Controls, Credits, race setup references; sources and exact briefs retained in `art_src/ui/menu/*_background_landscape_v3.png` / `.prompt.md`, runtime WebP compression-only, fragment `race_reference_regions_v1.json`.

Missions landscape plate v3: project-original built-in ImageGen edit of approved desktop reference; raw source/exact prompt retained in art_src/ui/menu/missions_background_landscape_v3.*; unchanged-composition runtime WebP; race_reference_regions_v1 fragment.

Loader portrait background v3: project-original built-in ImageGen edit of approved portrait reference, source/exactprompt under art_src/ui/menu/loader_background_portrait_v3.*; runtime WebP conversion only; race_reference_regions_v1 fragment.


## Complete wardrobe outfit library v1 — 2026-10-07

Project-original built-in ImageGen artwork under project art direction; model/build identifier not exposed. The catalog contains 480 complete-character images: eight approved penguin identities × five headwear states × three eyewear states × four neckwear states. 469 approved variants were newly generated for this library; 11 approved existing ImageGen images were reused unchanged as source artwork (eight bare species and three existing complete outfits). Each job records the exact reference, original output path, prompt or reuse specification, visual review note, and SHA256.

Untouched RGBA PNG sources and prompt records: `art_src/ui/wardrobe_outfits_v1/`. Runtime WebP images: `assets/art/ui/wardrobe_outfits_v1/`; encoding quality88, method6, resized proportionally to512px wide with alpha retained. No accessory compositing, recoloring, or other image edits were used for outfit generation. Four rejected pilot concepts remain preserved under `rejected/` and excluded from the runtime catalog. One transient tool failure and successful identical-prompt retry are retained in `qa_shots/tests/wardrobe-library-v1/rockhopper-earwarmers-tool-failure.json`.

Source/runtime provenance: `data/art/fragments/wardrobe_outfits_v1.json`. Reviewed outfit matrix: `data/wardrobe/outfits_v1.json`. Registration initially remains `production_ready: false`; runtime readiness is handled by the final complete-library texture-load gate. Human originality review remains separate from visual and technical acceptance.


## Menu reference iteration v3 — 2026-10-07

Project-original built-in ImageGen artwork under the supplied Waddle Wars direction. Generator model/build identifier not exposed. Exact generation briefs, approved reference paths and original PNG outputs preserved in `art_src/ui/menu/reference_iteration_v3/`. Current references are design concepts; their example values do not override live game state. Nine runtime assets (ivory/coral capsules, ivory card, mission plaque, feedback wordmark/mailbox/backgrounds, running-penguin action icon) use same-resolution WebP conversion at quality94 with transparency preserved. Runtime source regions are selected with native Godot materials/AtlasTexture, not edited screenshots. Full source/runtime hashes, dimensions and ownership recorded in `data/art/fragments/menu_reference_iteration_v3.json`. Rejected runner-icon v3/v4 drafts remain archived and unused; v5 is integrated.

## Menu alignment v4 (2026-10-07)

Race and Credits title sprites, plus the wide Settings cabin plate, are project-original artwork generated with Codex built-in ImageGen from approved project references. Original PNGs and exact prompts are retained in `art_src/ui/menu/alignment_v4/`; runtime WebPs preserve dimensions and transparency. Provenance and review readiness: `data/art/fragments/menu_alignment_v4.json`.

## Runner in-run artwork v4 — 2026-10-07

Project-original artwork generated with Codex built-in ImageGen. Raw PNGs, exact prompts, input references and generation output paths: `art_src/ui/runner/inrun_v4/`. Five runtime WebP conversions preserve the generated images and alpha; four HUD/catch reference PNGs remain review references. Full SHA-256 provenance: `data/art/fragments/runner_inrun_v4.json`. Runtime approval pending rendered integration/performance checks; no third-party stock material.

## Runner course fidelity v5 — 2026-10-07

Project-original built-in ImageGen crystal ice and transparent cloud bank. Untouched source PNGs and exact prompts retained in `art_src/runner/painted/v5/`; runtime WebP conversions preserve dimensions and alpha, quality94. Provenance: `data/art/fragments/runner_course_v5.json`. Two persistent cloud cards share one texture and material; no per-chunk texture allocations.

## Runner HUD reference fidelity v5 — 2026-10-07

`hud_reference_surfaces_v1` and `hud_reference_icons_v1`: original OpenAI built-in ImageGen assets, `project_original`. Reference: unchanged approved `art_src/ui/runner/inrun_v4/runner_hud_portrait_v5.png`. Raw PNGs/prompts/job provenance: `art_src/ui/runner/inrun_v5/`. Runtime WebPs: `assets/art/ui/runner/inrun_v5/`. Exact hashes/source IDs: `data/art/fragments/runner_hud_fidelity_v5.json`. Lossy WebP q94, alpha q100, atomic publication; no alpha or pixel recoloring. Production review flag remains false pending visual/performance acceptance.

## Runner terminal-state fidelity v5 — 2026-10-07

Project-original Codex built-in ImageGen extractions of unchanged approved catch/results and pause references. Two clean snow-buried hero backgrounds, two orientation-specific avalanche headlines and one blank snow-framed pause card. Original RGBA PNGs and exact prompts retained under `art_src/ui/runner/inrun_v5/`; proportional runtime WebP conversions at quality94. Native captions, live counters, missions and actions remain interactive. Provenance: `data/art/fragments/runner_end_fidelity_v5.json`. Visual/runtime acceptance pending final capture.

`hud_heart_spent_v1`: original built-in ImageGen derivative of the v5 HUD heart; same provenance directory/fragment and project_original license. Approved gray outline + ivory interior; transparent PNG preserved and atomically encoded WebP.

## Settings Controls header — 2026-10-08

Project-original built-in ImageGen cutout, visually reviewed navy/coral gamepad and snowy mountain base from the project Controls desktop reference. Source: `art_src/ui/menu/reference_iteration_v6/settings_controls_header_v6.png`; exact prompt sibling `.prompt.txt`; runtime unchanged lossless format conversion: `assets/art/ui/menu/settings_controls_header_v6.webp`. Provenance/hashes: `data/art/fragments/settings_tabs_v6.json`. Reference-only Sound/Graphics outputs listed in `sound_graphics_manifest.json`. No third-party source added.

## Functional Missions map v7 — 2026-10-08

Project-original built-in ImageGen edits/extractions from approved Missions references. Two clean map plates preserve region geography; separate transparent red-scarf penguin and three-state route-marker atlas permit real saved progression. Raw PNGs and exact prompts: `art_src/ui/menu/mission_map_v7/`. Runtime WebPs preserve dimensions and transparency via lossless format conversion. Hashes and source relationships: `data/art/fragments/mission_map_v7.json`. References unchanged; all four generated assets visually accepted by root. Only their asset readiness promoted; runtime integration acceptance pending actual Chrome review.


## Wardrobe category icons v3 — 2026-10-08

Project-original Codex built-in ImageGen reconstruction of five category icons from unchanged approved `art_src/ui/menu/penguins_v1.png`. Original transparent PNG and exact prompt retained under `art_src/ui/menu/wardrobe_category_icons_v3.*`; runtime PNG is byte-identical. Full hashes/source relationship: `data/art/fragments/wardrobe_category_icons_v3.json`. Runtime import compress0, mipmaps true. Root visually accepted generated source art; only this asset readiness promoted. Rendered Chrome integration review pending.

## Avalanche curling snow v10 — 2026-10-08

Project-original Codex built-in ImageGen transparent desktop and portrait snow surrounds, derived from unchanged approved avalanche catch references. Untouched PNGs and exact prompts: `art_src/ui/runner/inrun_v10/`. Runtime WebPs preserve dimensions and alpha through lossless format conversion and atomic publication. Source/runtime hashes: `data/art/fragments/runner_catch_surround_v10.json`. Generated sources visually reviewed; runtime readiness remains pending actual Chrome integration review.

## Equipment trail illustrations — iteration 10 (2026-10-08)

Four original trail particle designs generated with Codex built-in ImageGen from the approved wardrobe atlas / Aurora Trail style references. Exact prompts and untouched 1254×1254 transparent PNG originals: `art_src/ui/equipment_v10/trail_{snowflake,fish,aurora,rainbow}_particle_v1.*`. Runtime: `assets/art/characters/trails/trail_{snowflake,fish,aurora,rainbow}_particle_v1.webp`. Full-canvas contain resize to 256×256, lossless WebP conversion; source alpha preserved, no cropping or retouch. License: `project_original`. Exact hashes and generator provenance: `data/art/fragments/equipment_trails_v10.json`. Art reviewed for isolated subject, palette and transparency; runtime/Chrome checks are recorded separately. Existing outfit source illustrations are reused unchanged.

## Retained menu inventory metadata — 2026-10-08

`data/art/fragments/legacy_menu_inventory_v11.json` indexes pre-existing project-original runtime art and retained source/reference images. Exact bytes, hashes, dimensions and available original prompt links are preserved; two original PNGs have byte-identical source-tree copies. This is inventory recovery, not new generation or production approval. All 74 recovered runtime entries remain `production_ready: false`; 55 direction references remain source-only. Four historical reference invocations were not retained: the explicit limitation is recorded in `art_src/ui/menu/legacy_inventory_recovery_20261008.md`. Seventy-three flat UI textures retain their existing no-mipmap imports through the explicit `screen_space_no_mipmaps` sampling policy; no runtime image or import settings changed.
