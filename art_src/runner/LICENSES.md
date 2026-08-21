# Authored art provenance ledger

No authored Blender model is registered yet. Three project-original frontend
raster textures are registered with generated-source records; this file also
remains the policy ledger for future authored 3D work and does not claim
existing procedural gameplay art was authored in Blender.

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

## Registered authored sources

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
