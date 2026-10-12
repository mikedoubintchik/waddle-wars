# V12 unique-atlas review contract

Status: QA-only. No live character, wrapper, catalog, save, or gameplay change.
Passing these checks does not approve the model, animation, art payload, or FPS.

## Inputs and binding

`tools/art/bake_hero_penguin_v12_atlas.py` consumes a saved source sculpt and its
matching audited skinned candidate, both read-only. Each LOD has a unique UV
atlas and four `hero_penguin_v12_atlas_<kind>.png` maps. Normal builds require
only runtime files, not Blender. The authoring version remains Blender 5.2.0.

Exact reconstruction reads the candidate audit's `geometry_policy`: absent
means `legacy`, while `source-cover-v1` (rejected Y02 mouth experiment) and
`source-cover-v2` (Y03, original mouth restored) replay distinctly. Unknown or
malformed policy values fail. The audit hash and selected policy are retained
in bake evidence; source membership/count gates are unchanged. Twenty-four
host tests pass. Fresh Y03 LOD0 baking now verifies that reconstruction and UV
gate; initial 22 uncovered texels become 15 mouth-only misses after seven
actual-source eye probes. The 250 µm eye cap and untouched-pixel hashes pass.
Subsequent mouth03 repairs the 15 remaining misses with actual same-mouth,
outward-compatible stable source triangles; maximum actual center/corner
distance 1.229 mm is below the separate unchanged 1.25 mm mouth cap. All 60
center/corner first rays and real material bakes pass. Float64 signed-area
barycentrics avoid cancellation on thin source triangles. Eight working maps'
unselected pixels and original mesh/skin/morph data remain exact before final
packing. Strict full-atlas coverage is now zero-miss; 13 mouth host tests pass.
See `qa_shots/hero/v12_atlas_y03_mouth_03/REVIEW.md`. This does not approve art.

Y03's exported and shared-external packages are Khronos-clean. Serialized
geometry/rig/clip parity is exact (UV/normals intentionally outside that parity
test's scope). Real Godot imported four-map residency is 16,777,296 stored bytes,
not driver VRAM. Actual facade front/chase 30/60 and normal runner captures
pass integration but fail visual fidelity: dark rear, generic facial shapes,
harsh highlights. `qa_shots/hero/v12_atlas_y03_runner_review01/VISUAL_REVIEW.md`.

`atlas_binding.json` version 1 binds the exact exported GLB and all four PNG
SHA-256 hashes to `unique-nonoverlapping-v1`. The capture harness rejects stale
or mismatched bindings. Repeating-UV M01 cannot silently use this new material.
The bake must preserve positions, topology, skin weights, species keys, rest
rig and clips; triangle/tangent/UV and Khronos checks remain separate gates.

| Map | Encoding | Meaning |
| --- | --- | --- |
| albedo | sRGB | Source pigment and feather detail, no stage lighting |
| normal | Linear data | High-to-low tangent-space normal, +Y green |
| orm | Linear data | R occlusion, G roughness, B metallic |
| masks | Linear data | R ivory, G gold, B identity cyan, A feather membership |

Mask RGB weights are exclusive. Hard parts and eyes have A=0. Body, waterline
and wing masks derive from explicit source construction, checked against saved
paint; RGB color guesses are not authoritative masks. Gutters and mipmaps must
survive real compressed imports. Separate LOD atlases currently increase
memory: raw RGBA8 totals are not a compressed-memory acceptance claim.

New source studies can store `SourceSemanticMasks` as linear FLOAT_COLOR/POINT
with object contract `feather-palette-weights-v1`. These are original
compositing weights, saved before variable ivory/throat pigments are mixed.
Every vertex must be covered; finite exclusive RGB weights and feather A=1
are required. Incomplete contracts fail rather than falling back to guesses.
The baker copies them exactly into its bake field. Frozen M has neither field
nor tag and retains its original analytic paint-verification path. This new
input path does not rebake or alter the verified M package.

## Renderer contract and measured regression

`tests/shaders/hero_v12_atlas_review.gdshader` reconstructs source and desired
pigments from masks, then applies their ratio to baked albedo in linear space.
Identical palettes preserve the bake; hard parts ignore recoloring. The material
uses no vertex color, generated feather geometry, noise, fake rim, or alpha
transparency. Four texture samplers; four instance palette parameters.

Godot Compatibility decodes custom-fragment ALBEDO before lighting, whereas
Mobile/Forward+ expose linear source-color samples. The shader converts only
at that boundary, selected by `OUTPUT_IS_SRGB`. See the [pinned engine
implementation](https://github.com/godotengine/godot/blob/4.7.1-stable/drivers/gles3/shaders/scene.glsl#L2203)
and [spatial shader contract](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html#global-built-ins).

September 7, Apple M2, Godot 4.7.1 real framebuffer tests:

- Before boundary correction: 16 pass/7 fail; recolor errors reached 39/255 per channel.
- Corrected Compatibility: 23 pass/0 fail; changed-color maximum 1/255.
- Corrected Metal Mobile: 23 pass/0 fail; changed-color maximum 2/255.
- Original colors, hard-region protection and raw data channels matched exactly
  in both renderers. Original lit flat-normal control differed by at most 1/255.

The test copies the actual shader and changes only render mode for quantitative
albedo cases. Its final normal case uses the original lit shader. CPU expected
colors and tolerance are identical across renderers. It does not substitute
for a real lit character capture, browser/device run, or frame-time benchmark.
Headless execution explicitly skips this visual gate.

Evidence: `/tmp/waddle-hero-atlas-shader.EraUgB/` contains isolated project,
before/after logs and Mobile log. Shader code SHA-256:
`31e7fb7359bc17fe590b41692ecd3dd386c712fb8fd2addf9cd3a785e76f654a`.

## Actual imported M atlas: diagnostic, still rejected

`qa_shots/hero/v12_atlas_m_rejected_review_01/` retains the first four-map
unique-atlas export and its exact binding. Its projection gate fails with 41
genuine uncovered texels (26 mouth, 15 eye/rim). Diagnostic export/capture
intentionally returns a nonzero result after saving useful evidence; it does
not bypass or pass this gate. The original input is M/M01, not newer N/O.

Independent serialized-GLB parity establishes 22,305 identical oriented
triangles with unchanged positions, skin weights and eight species deltas.
Fifteen joints, rest/bind transforms, four sockets, 23 clips, 1,035 channels
and 4,358 animation samples are unchanged. UV seam splitting increases
vertices from 12,519 to 14,135. This audit does **not** prove normals, UV quality,
appearance, or performance. See `lod0/export_parity_audit.json`.

Normal Godot `PackedScene` imports on Apple M2 Compatibility produced both
standard PBR and explicit QA-shader sequences: 48 frames each, no import,
parser or shader errors, structural/contact checks passed, overall projection
gate correctly failed. **Later byte/pixel auditing found stale embedded ORM
in this old GLB**: its red/green channels are constant 255/204, whereas the
external bake varies. Blender had retained earlier packed image bytes after
saving changed pixels. The old PBR capture therefore does not prove correct
AO/roughness transfer or equivalence with the custom shader. The custom
shader loads the independently hashed external PNGs; its material evidence
remains valid. Corrected packing/export requires a separate fresh artifact.
Neither material appears final quality. Legacy stage
lighting blows out cream/orange; a softer stage still leaves overbright cream
and embossed-looking feather normals.

The subsequent `balanced-review` stage (linear tonemap, ambient 0.35,
key 0.28, fill 0.12) restores visible ivory/orange detail. Two matching
48-frame sequences compare normal strength 1.0 and 0.35, with unchanged
GLB/shader/map hashes. The weaker normal visibly reduces coarse feather
ridges. This is a **diagnosis**, not final tuning: it also reduces baked
high-to-low geometry correction. A final bake must weaken only the source
feather field while preserving shape normals. Both captures correctly retain
the failed 41-pixel projection gate. Evidence paths end in
`v12_atlas_m_rejected_shader_3q60_balanced_normal1_01` and
`v12_atlas_m_rejected_shader_3q60_balanced_normal035_01` under `qa_shots/hero`.
No lighting/material change was applied to the live game.

Actual compressed texture data, each 2048² with 11 mip levels:

| Map | Stored bytes including mips |
| --- | ---: |
| albedo | 2,796,216 |
| normal | 5,592,432 |
| ORM | 2,796,216 |
| RGBA masks | 5,592,432 |
| Total | 16,777,296 |

This is Godot texture payload, **not driver VRAM, frame time, or the full runner
budget**. The comparison harness also retains original imported PBR resources.
Working PNG masters are currently 16-bit; eventual runtime quantization and
LOD1 remain separate, unfinished steps. No live GLB/material was promoted.

## Subsequent zero-miss transfer milestone

`qa_shots/hero/v12_atlas_m_nearest_eyes_02/lod0/` now passes the LOD0
projection gate: zero missing pixels across 1,838,604 covered texels. This
supersedes the earlier rejected transfer variants, **not their visual verdict**.
The input is still M/M01; it is not a baked P or a live model replacement.

The 26 mouth holes use actual complementary same-component face-cage hits;
all other pixels are preserved. The final 15 eye/rim texels sample only their
paired high-source triangle through Blender's material evaluator. The first
variant proved coverage but left physical sampling distance provisional.
Variant 02 now audits exact float32 first-ray intersections: all 15 hit the
intended triangle strictly inside (minimum barycentric weight 0.0098897).
Maximum actual source distance is 174.832 µm against the 250 µm limit; ray
length is at most 20.054 µm. Every probe records source triangle/barycentrics
and actual hit coverage; no hole mask was
silently dilated or accepted. Original target tangent frames are retained,
including mirrored-UV handedness. All previously valid pixels stay unchanged.

Checkpoint reload now verifies packed PNG bytes and decoded pixels. Export
also verifies decoded embedded albedo/normal/ORM against external maps; all
differences are zero, and Khronos reports no errors/warnings. The exported
GLB SHA-256 is
`7aab5fc7605ff4e75adda92990c1a7703388a22672d33d29dfaf678415dbae8c`.
Production readiness remains false. Final face/material tuning, LOD1, species,
cosmetics, motion matrix and in-game/browser/device performance are still open.

Final normally imported Compatibility capture also passes its technical gate:
48/48 frames, zero projection misses, exact source binding, structural/contact
checks true, clean import/shader logs, engine/wrapper exit 0. Evidence:
`qa_shots/hero/v12_atlas_m_nearest_eyes02_shader_3q60_balanced_01/`.
Main-agent review still rejects the M face/rim/coarse-surface appearance.
`overall_gate_pass=true` in this harness means only its explicit technical
checks—not premium fidelity, production readiness or measured gameplay FPS.

### Historical duplicate-texture packaging blocker

Review04's actual normally imported PBR materials used three extracted,
lossless RGBA8 maps: 67,108,860 bytes including mips. The custom shader's four
separately compressed maps add 16,777,296 bytes. This harness retains both
resource sets; **16 MiB is not the character's total memory cost**. Their
filtering/compression and deliberate specular differences also prevent a
pixel-equivalence claim, despite identical decoded source images and normal
strength 1.0. Before live integration, use shared external texture imports or
a geometry-only GLB/material wrapper so unused extracted PBR maps cannot
remain resident. That duplicate-import issue is resolved by the subsequent
package below; the older capture's memory statement is not retroactively fixed.

### Shared compressed external-image package — verified

`qa_shots/hero/v12_shared_texture_package_02/lod0/` retains the exact verified
M atlas geometry/material/animation data while replacing embedded images with
same-directory glTF image URIs. Embedded image bufferViews and unused bytes
are removed. GLB size falls from 31,187,804 to 3,819,496 bytes; SHA-256 is
`5325452db55e24fff7c355c6d60b45b7bb26ea9467b55676a1f4897c39930956`.
All four source maps remain byte-identical. No Blender is needed for packaging
or normal Godot builds.

Exact raw/accessor parity now includes normals and tangents as well as the
previous geometry/skin/species/clip contract. Khronos resolves all local PNGs
and reports zero errors/warnings. Fresh normal Godot import proves both PBR
surfaces, normal/AO/roughness/metallic bindings and optional atlas overrides
share the same external Texture2D instances. Four compressed images total,
16,777,296 stored bytes including 11 mip levels; no extracted PBR copies.
This is resource identity and payload accounting, **not driver VRAM or FPS**.

Normally imported PBR and atlas-shader captures of the byte-identical package
both exit zero, with 48 frames, zero projection misses and clean engine logs.
The two paths now show broadly matching feather relief, but no pixel-equivalence
claim is made. These remain the rejected M face/materials, not T source art.
Evidence: `qa_shots/hero/v12_shared_package01_{imported,shader}_3q60_balanced_01/`.
Ten package host tests and a separate hash-bound engine fixture pass. LOD1,
species/cosmetics, final look and full-app/device/release acceptance stay open.
