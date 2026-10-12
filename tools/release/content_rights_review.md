# Content-rights checkpoint — 2026-10-04

This is a source audit, **not** a store declaration or legal clearance.

**Owner attestation, 2026-10-05:** The owner confirmed they own or have
permission to use the penguin reference image documented in
`art_src/characters/hero_penguin_user_reference_2026-08-18.prompt.md`.
Its original generator remains unknown; the file stays source-only and the
`reference_unverified` guard remains until the final runtime material and
package review. The attestation resolves the missing owner-permission fact.

**Apple portal draft, 2026-10-05:** Saved “Yes, this app has the necessary
rights to its third-party content.” A fresh reload read back the same answer.
The bundled font's OFL notice and owner-confirmed reference support this
draft. Recheck final runtime package and licenses before review submission.

| Input | Current evidence | Status |
| --- | --- | --- |
| UI font | `assets/fonts/AtkinsonHyperlegibleNext-wght.ttf`; bundled `AtkinsonHyperlegibleNext-OFL.txt` and `README.md` record upstream/version/hash | Notice bundled; verify inclusion in final packages. |
| Title/loader art | Project ImageGen source records, prompts and hashes in `art_src/ui/title/`; runtime entries in `assets/art/art_manifest.json` | Provenance recorded; final visual/originality review pending. |
| Generated audio | `tools/generate_audio.py` creates current music/effects procedurally; no external sample source identified in this audit | Recheck final runtime package. |
| Hero material | `tools/art/derive_hero_penguin_material_v11.py` processes two generated feather swatches. Their prompts use a user-provided image only as surface-fidelity reference; owner confirms permission to use it. The source image keeps `reference_unverified` ID; validator rejects that ID on runtime assets/exports. | Confirm final material maps do not sample reference pixels; preserve source-only guard. |
| 3D exports | `data/art/fragments/*.json` and Blender sources record source/export IDs; runtime has 43 `.glb` files under `assets/art/` at this checkpoint | Manifest validation and human originality review still required for final package. |

Do not treat the saved Apple answer as final-package clearance. Final package
may differ from the current dirty source tree.

Focused check: `python3 -m unittest
tests.test_art_tools.ArtToolTests.test_unverified_reference_is_source_only`
passes 1/1. `python3 tools/art/validate_art.py --review-fragments` passes
review integrity (112 assets, 43 exports, 7 concepts); it explicitly reports
103 unresolved review-only assets and **release_ready=false**.
