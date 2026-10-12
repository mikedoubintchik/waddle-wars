# Authored art provenance ledger

This policy began with three frontend raster textures. The current source tree
also contains authored Blender exports registered in the art fragments; consult
those records for exact models, hashes and generation history. Registration is
not a substitute for a final content-rights review.

Every source/export entry must record:

| Field | Requirement |
|---|---|
| Asset/export ID | Stable `lower_snake_case` ID |
| Creator | Human or studio responsible for final authored asset |
| Creation date | ISO `YYYY-MM-DD` |
| License ID | `project_original` unless separately reviewed |
| Source files | Exact repository-relative paths |
| External inputs | URL, author, license, and modification notes |
| AI assistance | Tool/model and which stages used, if any |
| Reviewer | Person who verified provenance and originality |

`project_original` means created specifically for Waddle Wars and cleared for
use in project. Third-party marketplace, stock, or extracted game assets are
forbidden unless license and redistribution rights are documented before
source enters repository.

Reference images may guide abstract craft qualities—silhouette clarity,
rhythm, color hierarchy, animation principles. They may not be traced or used
as texture/model source.

## Open provenance review

### `imagegen_runner_painted_v1`

- Creator: Waddle Wars project, generated through Codex built-in ImageGen.
- Date: 2026-10-07.
- License ID: `project_original` (subject to final originality review).
- Material source IDs: `imagegen_runner_painted_ice_v1` and
  `imagegen_runner_painted_snow_v1`.
- Material sources: `art_src/runner/painted/runner_painted_ice_v1.png` and
  `art_src/runner/painted/runner_painted_snow_v1.png`; actual dimensions
  1254×1254 each, despite 1024×1024 requested in the original prompts.
- Art direction source: `art_src/runner/painted/runner_course_reference_v1.png`
  (1672×941), ID `imagegen_runner_course_reference_v1`. This image is a
  source-only composition/material reference, not runtime gameplay art.
- Exact briefs: `art_src/runner/painted/runner_painted_v1.prompt.md`.
- Runtime exports: `assets/art/runner/textures/runner_painted_ice_v1.webp`
  (318,810 bytes) and `runner_painted_snow_v1.webp` (200,608 bytes) in the
  same directory. Source pixels were not repainted; format conversion only,
  retaining original dimensions.
- Input roles: approved project menu art supplied painted snowy material/style
  direction; current project gameplay supplied the course camera and geometry
  reference. No new third-party image was introduced. Existing project
  provenance reviews remain applicable to content visible in these references.
- AI assistance: built-in ImageGen created the textures and course reference;
  exact model/build identifier was not exposed.
- Registration and immutable hashes:
  `data/art/fragments/runner_painted_v1.json`.
- Reviewer: Codex verified file hashes, source paths and actual dimensions;
  final human originality, visual tiling and gameplay review pending.
- Status: local painted course candidate. Both runtime texture registrations
  remain `production_ready: false`. Shader code is authored separately and
  is not part of this generated texture provenance record.

### `imagegen_runner_painted_water_v1`

- Creator: Waddle Wars project, generated through Codex built-in ImageGen.
- Date: 2026-10-07.
- License ID: `project_original` (subject to final originality review).
- Source: `art_src/runner/painted/runner_painted_water_v1.png` (1254×1254).
  The prompt requested 1024 square; actual generated dimensions are retained.
- Exact brief: `art_src/runner/painted/runner_water_v1.prompt.md`.
- Runtime export: `assets/art/runner/textures/runner_painted_water_v1.webp`
  (1254×1254, 198,630 bytes); WebP quality 94 format conversion only, without
  source pixel edits or resizing.
- Input role: registered project `runner_course_reference_v1.png` supplied
  the painted Arctic water style. No new external reference was introduced.
- AI assistance: built-in ImageGen generated the source texture; exact
  model/build identifier was not exposed.
- Registration and immutable source/runtime hashes:
  `data/art/fragments/runner_painted_v1.json`.
- Reviewer: Codex verified paths, hashes and dimensions; final human
  originality, visual tiling and gameplay review pending.
- Status: local water material candidate; `production_ready: false`.

### `runner_painted_material_programs_20261007`

- Creator: Waddle Wars project, authored with Codex coding assistance.
- Date: 2026-10-07.
- License ID: `project_original`.
- Source/runtime code: `assets/art/runner/materials/runner_painted_surface_v1.gdshader`
  and `runner_painted_sea_v1.gdshader` in the same directory, plus
  `assets/art/runner/day/materials/runner_day_palette_v2.gdshaderinc`.
  These are editable project-authored shader sources, not ImageGen output.
- Sea shader revision: material/reference normalization now shares the
  renderer's color space, preserving painted water detail in Compatibility;
  distant color follows the existing sky ground gradient. No generated
  texture pixels changed. Registered SHA-256:
  `f9394ce1e58f6f125d3724cf75a4aaf61816d2fbf92a69c84b758787e591cf17`.
- Related revisions: `runner_day_surface_v1.gdshader`,
  `runner_day_shell_v1.gdshader`, `runner_day_surface_v1.tres`, and
  `runner_day_shell_v1.tres` under `assets/art/runner/day/materials/`.
- Inputs: the registered painted ice/snow/water textures and approved project course
  reference; existing DAY geometry/semantic atlas. No new external code or
  third-party material was introduced.
- Source ownership: the painted ice generated source is the canonical input
  anchor for the shared painted surface program; the water generated source
  anchors the sea shader, consumed by `scripts/runner/runner_painted_sea.gd`.
  The DAY deck export retains
  ownership of shared DAY palette/material resources. These links identify
  packed input ownership, not shader generation by ImageGen.
- Immutable code/material hashes:
  `data/art/fragments/runner_painted_v1.json` and
  `data/art/fragments/runner_day_kit_v1.json`.
- Reviewer: Codex checked file hashes and source links; final rendered and
  performance review pending. All affected entries remain
  `production_ready: false`.

### `imagegen_runner_hud_v1`

- Creator: Waddle Wars project, generated through Codex built-in ImageGen.
- Date: 2026-10-07.
- License ID: `project_original` (subject to final originality review).
- Source IDs: `imagegen_runner_hud_icons_v1`,
  `imagegen_runner_hud_landscape_v1`, `imagegen_runner_hud_portrait_v1`.
- Sources: `art_src/ui/runner/runner_hud_icons_v1.png` (1536×1024),
  `art_src/ui/runner/runner_hud_landscape_v1.png` (1672×941), and
  `art_src/ui/runner/runner_hud_portrait_v1.png` (941×1672).
- Exact briefs: `art_src/ui/runner/runner_hud_v1.prompt.md`.
- Runtime export: `assets/art/ui/runner/runner_hud_icons_v1.webp` (278,196 bytes).
  Only this icon atlas is consumed, through `scripts/ui/runner_hud_art.gd`.
  Full-screen landscape/portrait art remains design reference; changing HUD
  values, labels and progress are native live controls.
- Input roles: approved project Base Camp v2 art supplied material/style
  direction; current project gameplay supplied layout/world reference. No new
  third-party image was introduced. Existing project provenance reviews remain
  applicable to content visible within those references.
- AI assistance: built-in ImageGen generated the references and icon atlas;
  exact model/build identifier was not exposed. PNG-to-WebP conversion only;
  runtime alpha matches source byte-for-byte, with no pixel repaint or mask.
- Registration and immutable file hashes:
  `data/art/fragments/runner_hud_v1.json`. All three PNGs use the schema's
  `generated_assets` UI-source inventory; that bucket does not make the two
  full-screen design references runtime assets.
- Reviewer: automated source/hash/dimension/alpha checks completed by Codex;
  final human originality and rendered gameplay review pending.
- Status: local runner HUD candidate; runtime fragment retains
  `production_ready: false` until applicable review gates pass.

### `imagegen_desktop_menu_refresh_v2`

- Creator: Waddle Wars project, generated through built-in ImageGen.
- Date: 2026-10-07.
- License ID: `project_original`.
- Sources and briefs: `art_src/ui/menu/desktop_refresh_v2.prompt.md`.
- Runtime exports: four corresponding desktop backgrounds/wordmark in
  `assets/art/ui/menu/`, documented in `assets/art/LICENSES.md`.
- Inputs: existing project-owned menu concept images; no external characters.
- Source PNGs and checksums backed up in Google Drive's Waddle Wars /
  Final Imagegen Assets archive (`ASSET_INDEX-20261007.csv`).
- Status: local menu candidate; rendered review recorded separately from
  launch and browser-performance acceptance.

### `imagegen_runner_avalanche_front_v1`

- Creator: Waddle Wars project, generated through Codex built-in ImageGen.
- Date: 2026-10-05.
- License ID: `project_original` (subject to final originality review).
- Source/provenance: `art_src/runner/avalanche_front_v1.prompt.md`.
- Runtime export: `assets/art/runner/avalanche_front_v1.png`.
- External inputs: none.
- Reviewer: pending final art review.
- Status: local animated opening-avalanche candidate; mobile/web quality gate pending.

`art_src/characters/hero_penguin_user_reference_2026-08-18.png` was supplied
by the user as an art-direction reference. Its original creator, generator and
license are unknown. It is source-only and must not be shipped as runtime art.
The dark and cream feather swatches were generated from prompts that cite this
image for surface fidelity only, then processed into the hero material maps by
`tools/art/derive_hero_penguin_material_v11.py`. Their prompt records expressly
forbid character/pose copying, but that fact alone does not clear the source
image's provenance or the final derived maps. Review originality and rights,
or replace these maps with independently authored material, before a store
content-rights declaration. The source fragment tags this reference
`reference_unverified`. This is a source-only classification, not a
distribution license.

## Registered authored sources

### `imagegen_waddle_wars_app_icon_v2` and `imagegen_waddle_wars_wordmark_v2`

- Creator: Waddle Wars project, generated through Codex built-in ImageGen.
- Date: 2026-10-04.
- License ID: `project_original` (subject to final originality review).
- Sources: `art_src/ui/icon/waddle_wars_app_icon_v2_source.png` and
  `art_src/ui/title/waddle_wars_wordmark_v2_source.png`.
- Prompts, input role, dimensions and hashes: sibling `.prompt.md` files.
- Use: premium app/store/PWA icon; title/loading wordmark. Icon uses only the
  already project-owned loader penguin as character reference.
- Status: local source and target-size rendering checked; no store upload or
  candidate-matched mobile package acceptance yet.

### `imagegen_waddle_wars_app_icon_v3` and `imagegen_waddle_wars_wordmark_v3`

- Creator: Waddle Wars project, generated through Codex built-in ImageGen.
- Date: 2026-10-04.
- License ID: `project_original` (subject to final originality review).
- Sources: `art_src/ui/icon/waddle_wars_app_icon_v3_source.png` and
  `art_src/ui/title/waddle_wars_wordmark_v3_source.png`.
- Prompt, input roles, dimensions and hashes: sibling `.prompt.md` files.
- Use: tighter, simpler app icon and icy title/loading wordmark. Icon references
  only the project-owned loader penguin. The existing v2 sources remain for rollback.
- Status: local candidate; final phone/store QA and candidate-matched build pending.

### `imagegen_waddle_wars_wordmark_v4`

- Creator: Waddle Wars project, generated through Codex built-in ImageGen.
- Date: 2026-10-04.
- License ID: `project_original` (subject to final originality review).
- Source: `art_src/ui/title/waddle_wars_wordmark_v4_source.png`.
- Input: project-owned v3 runtime wordmark as edit target; no outside art.
- Prompt, dimensions and hashes: sibling `.prompt.md` file.
- Use: smoother, more readable title/menu/loading wordmark. v3 stays for rollback.
- Status: local candidate; final phone/native QA pending.

### `imagegen_loader_penguin_v1`

- Creator: Waddle Wars project, generated through Codex built-in ImageGen.
- Date: 2026-08-18.
- License ID: `project_original`.
- Source: `art_src/ui/title/loader_penguin_expedition_v1.png`.
- Prompt/provenance: `art_src/ui/title/title_expedition_v1.prompt.md`.
- Generator model/build ID: not exposed by tool.
- Use: production loading-screen mascot texture.

### `imagegen_title_expedition_landscape_v1` and `imagegen_title_expedition_portrait_v1`

- Creator: Waddle Wars project, generated through Codex built-in ImageGen.
- Date: 2026-08-18.
- License ID: `project_original`.
- Sources: `art_src/ui/title/title_expedition_landscape_v1.png` and
  `art_src/ui/title/title_expedition_portrait_v1.png`.
- Prompt/provenance: `art_src/ui/title/title_expedition_v1.prompt.md`.
- Generator model/build ID: not exposed by tool.
- Use: production title, loading, and menu backdrop textures.
- Review: original Antarctic expedition-port environment; generated
  signature-like corner mark removed before production registration.

### `runner_day_keyart_v1`

- Creator: Waddle Wars project, generated through built-in
  `image_gen.imagegen` under human art direction.
- Date: 2026-08-18.
- License ID: `project_original`.
- Source: `style/concepts/runner_day_keyart_v1.png`.
- Prompt: `style/concepts/runner_day_keyart_v1.prompt.md`.
- Generator model/build ID: not exposed by tool.
- Use: art-direction concept only; not runtime poster, model, texture, or UI.
- Review: accepted for world layering, Antarctic research-port vocabulary,
  color hierarchy, and gameplay cue callouts. Character clothing/proportions
  and individual concept props require fresh production design, not tracing.


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

- Additional `runner_pause_background_v2`: built-in ImageGen edit of approved pause reference into UI-free scene plate; source941×1672RGB, runtime941×1672RGB. Source/prompt preserved, same-size WebP conversion; source/runtime hashes in `runner_menu_reference_v3.json`. Project-original, human review pending, production_ready false; import compress0+mipmaps true.

- Additional `runner_pause_landscape_background_v2`: built-in ImageGen landscape recomposition of the approved pause scene, preserving the complete scarf penguin at left with a quiet course at right. Source1672×941RGB, runtime1672×941RGB; same-size WebP quality92 conversion. Source/prompt preserved under `art_src/ui/menu/`; hashes in `runner_menu_reference_v3.json`. Project-original, human originality review pending, `production_ready: false`; import compress0+mipmaps true.

## Race mode reference regions — 2026-10-07

Project-original existing ImageGen reference `art_src/ui/menu/race_mode_select_v1.png` copied losslessly to `assets/art/ui/menu/race_mode_reference_v1.png`; runtime AtlasTexture regions isolate illustrated card scenes and static wood plaque. See `art_src/ui/menu/race_reference_regions_v1.prompt.md` and fragment `race_reference_regions_v1.json` for provenance and source hash. No new image generation or third-party art.

Race flag penguin: project-original reference-derived ImageGen `art_src/ui/menu/race_flag_penguin_v1.png`; transparent source preserved, runtime compression-only WebP. Exact prompt/retry outcome/visual review in `art_src/ui/menu/race_flag_penguin_v1.prompt.md`.

Utility landscape backgrounds v3: project-original ImageGen edits of approved Controls, Credits, race setup references; sources and exact briefs retained in `art_src/ui/menu/*_background_landscape_v3.png` / `.prompt.md`, runtime WebP compression-only, fragment `race_reference_regions_v1.json`.

Missions landscape plate v3: project-original built-in ImageGen edit of approved desktop reference; raw source/exact prompt retained in art_src/ui/menu/missions_background_landscape_v3.*; unchanged-composition runtime WebP; race_reference_regions_v1 fragment.

Loader portrait background v3: project-original built-in ImageGen edit of approved portrait reference, source/exactprompt under art_src/ui/menu/loader_background_portrait_v3.*; runtime WebP conversion only; race_reference_regions_v1 fragment.

## Runner in-run artwork v4 — 2026-10-07

Project-original artwork generated with Codex built-in ImageGen. Raw PNGs, exact prompts, input references and generation output paths: `art_src/ui/runner/inrun_v4/`. Five runtime WebP conversions preserve the generated images and alpha; four HUD/catch reference PNGs remain review references. Full SHA-256 provenance: `data/art/fragments/runner_inrun_v4.json`. Runtime approval pending rendered integration/performance checks; no third-party stock material.

## Runner HUD reference fidelity v5 — 2026-10-07

`hud_reference_surfaces_v1` and `hud_reference_icons_v1`: original OpenAI built-in ImageGen assets, `project_original`. Reference: unchanged approved `art_src/ui/runner/inrun_v4/runner_hud_portrait_v5.png`. Raw PNGs/prompts/job provenance: `art_src/ui/runner/inrun_v5/`. Runtime WebPs: `assets/art/ui/runner/inrun_v5/`. Exact hashes/source IDs: `data/art/fragments/runner_hud_fidelity_v5.json`. Lossy WebP q94, alpha q100, atomic publication; no alpha or pixel recoloring. Production review flag remains false pending visual/performance acceptance.

`hud_heart_spent_v1`: original built-in ImageGen derivative of the v5 HUD heart; same provenance directory/fragment and project_original license. Approved gray outline + ivory interior; transparent PNG preserved and atomically encoded WebP.

## Settings Controls header — 2026-10-08

Project-original built-in ImageGen cutout, visually reviewed navy/coral gamepad and snowy mountain base from the project Controls desktop reference. Source: `art_src/ui/menu/reference_iteration_v6/settings_controls_header_v6.png`; exact prompt sibling `.prompt.txt`; runtime unchanged lossless format conversion: `assets/art/ui/menu/settings_controls_header_v6.webp`. Provenance/hashes: `data/art/fragments/settings_tabs_v6.json`. Reference-only Sound/Graphics outputs listed in `sound_graphics_manifest.json`. No third-party source added.


## Wardrobe category icons v3 — 2026-10-08

Project-original Codex built-in ImageGen reconstruction of five category icons from unchanged approved `art_src/ui/menu/penguins_v1.png`. Original transparent PNG and exact prompt retained under `art_src/ui/menu/wardrobe_category_icons_v3.*`; runtime PNG is byte-identical. Full hashes/source relationship: `data/art/fragments/wardrobe_category_icons_v3.json`. Runtime import compress0, mipmaps true. Root visually accepted generated source art; only this asset readiness promoted. Rendered Chrome integration review pending.

## Retained menu inventory metadata — 2026-10-08

`data/art/fragments/legacy_menu_inventory_v11.json` indexes pre-existing project-original runtime art and retained source/reference images. Exact bytes, hashes, dimensions and available original prompt links are preserved; two original PNGs have byte-identical source-tree copies. This is inventory recovery, not new generation or production approval. All 74 recovered runtime entries remain `production_ready: false`; 55 direction references remain source-only. Four historical reference invocations were not retained: the explicit limitation is recorded in `art_src/ui/menu/legacy_inventory_recovery_20261008.md`. Seventy-three flat UI textures retain their existing no-mipmap imports through the explicit `screen_space_no_mipmaps` sampling policy; no runtime image or import settings changed.
