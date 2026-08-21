# Glacier Gauntlet authored art

Project-original Blender 5.2 LTS source and deterministic export pipeline for
the first authored race-course milestone.

- Art-direction reference: `art_src/ui/course_posters/glacier_gauntlet_wave1.png`
- Generator: `generate_glacier_kit.py`
- Build: `python3 tools/art/build_glacier_gauntlet_kit.py --all`
- Source: `glacier_gauntlet_kit_v1.blend` (`.gdignore`, Git LFS)
- Runtime: `assets/art/courses/glacier/`
- Fragment: `data/art/fragments/glacier_gauntlet_v1.json`

All runtime meshes are visual-only. Existing guides, ribbons, colliders, AI
hints, respawns, hazard timing and race rules remain authoritative. Assets use
one atlas material, COLOR_0 baked value response, generated mesh LODs and
Compatibility-safe features. Fragment stays `production_ready=false` until
portrait/landscape capture, performance and stability gates pass.

Runtime staging uses a separate fixed `art_rng`: local track chunks and cream
groomed snow in the near field, two-sided cyan expedition bivouacs and
clustered ice forms in the middle field, then three destination landmarks
against smooth authored `glacier_layered_ridge_v1` silhouettes. Legacy
procedural triangle mountains are suppressed. Ridge layers use a rough,
low-contrast atlas response for atmospheric recession. Sparse stories use
local MultiMesh centroids so distance culling cannot hide an entire camp from
an otherwise nearby camera.
Natural ice uses one restrained rim/clearcoat family; canvas and hardware keep
the matte atlas response.

Authored cave uses mirrored mineral `glacier_cave_buttress_v1` shoulders;
repeated procedural hoops are removed and one continuous wind-carved arch with
a seated frost mantle and cyan inner rim owns gateway.
Kerbs retain at least 2.8 m high-tier gaps instead of merging into navy verge.
Pooled contact patches ground expedition props and natural forms.

Semantic cues stay fixed: gold route/collect, violet power-up, orange hazard,
cyan duck and green launch. Every hazard also carries a distinct shape/pattern.

Focused verification:

```sh
godot --headless --rendering-method gl_compatibility \
  res://tests/glacier_gauntlet_art_test.tscn
godot --rendering-method gl_compatibility \
  res://tests/glacier_gauntlet_art_shot.tscn -- \
  zone=opening out=qa_shots/courses/glacier/opening_1920x1080.png \
  w=1920 h=1080
```

The capture harness waits through countdown before saving. Performance harness
remains gated on visual approval; a fast image of rejected art is not approval.
