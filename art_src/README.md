# Waddle Wars art sources

This tree contains editable art-production sources. Godot ignores the entire
tree through `.gdignore`; shipped resources live under `res://assets/art/`.

## Toolchain contract

- Blender: **5.2.0 LTS**, exact version recorded in `runner/BLENDER_VERSION`.
- Godot: **4.7.1** exactly for production import verification.
- Runtime interchange: core glTF 2.0 binary (`.glb`).
- Layered texture source: Krita (`.kra`) or Blender source data.
- Bake intermediates: lossless `.exr` or `.png`; never shipped directly.
- Runtime textures: power-of-two `.png`, imported by Godot.

Blender is an art-export prerequisite, not a game build prerequisite. Normal
Godot tests and exports consume committed runtime assets. Never put `.blend`
files under `assets/`, and never rely on Godot's direct Blender importer.

## Layout

```text
runner/
  BLENDER_VERSION       exact exporter version
  source_manifest.json  deterministic export jobs
  blender/              runner-specific canonical .blend files
  textures/             layered and baked texture sources
  style/                 visual rules and review targets
  LICENSES.md            provenance ledger
characters/
  blender/              shared character rig/model sources
  textures/             layered and baked character sources
ui/
  title/                 generated production textures + exact prompt record
  course_posters/        generated course plates + exact prompt records
```

The central source manifest may reference `.blend` files anywhere below
`art_src/`; every source remains covered by `.gdignore` and Git LFS.

Source binaries should use Git LFS. Runtime `.glb` and `.png` files stay in
ordinary Git unless repository policy changes, so web build automation does
not silently omit LFS objects.

## Export

```bash
git lfs install --local
npm ci --prefix tools/art
python3 tools/art/export_art.py --dry-run
python3 tools/art/export_art.py --check-blender
python3 tools/art/export_art.py --check-validator
python3 tools/art/export_art.py --all
python3 tools/art/validate_art.py
```

`--all` processes export jobs sorted by ID. Empty manifest is valid and exits
without requiring Blender. Once jobs exist, missing/wrong Blender fails with
an actionable message. Exported files are not considered registered until
`assets/art/art_manifest.json` contains matching hashes and passes validation.
One canonical `.blend` may back multiple collection-specific jobs; each job
records the same current source hash and its own unique runtime output.
Each Blender source job records its `.blend` SHA-256, approved license, asset class,
`-Z` runtime-forward contract, pivot policy, X/Y/Z bounds, triangle range,
surface/rig/texture limits, required sockets, and required clips. Export writes
a candidate GLB, requires zero errors and warnings from pinned official Khronos
glTF-Validator 2.0.0-dev.3.10, then atomically promotes it.

Production-generated 2D sources use `generated_assets` records instead. Each
records exact prompt path, source image hash/dimensions, generation date,
generator disclosure, and license; runtime copies retain independent hashes in
the art catalog.

## DCC rules

- Metric scale: 1 Blender meter = 1 Godot meter.
- Exported root transform: identity; validate forward as Godot `-Z`.
- Apply non-armature modifiers. Export triangles, custom normals, tangents,
  UVs, vertex colors, and deform bones only.
- Export keeps Blender `export_apply=false` so shape keys survive; validation
  rejects unapplied render modifiers other than the exported armature.
- Maximum four skin influences per vertex.
- Bake constraints, Geometry Nodes, procedural materials, and NLA output.
- Remove scratch armature actions before export. Blender `ACTIONS` mode emits
  every bone action in the file; character jobs permit only their manifest clips.
- No cameras, lights, gameplay collision, or Blender-only shader nodes.
- Use stable `lower_snake_case` collection, object, material, bone, and action
  names. Renaming a bone is a breaking asset change.
- Character sockets are named Empty objects parented directly to exported
  bones; a same-named bone alone does not satisfy the runtime socket contract.
- Each skinned mesh is parented to the same armature targeted by its Armature
  modifier. Character armatures have exactly one root bone; exporter removes
  Blender's armature wrapper so skinned meshes remain standards-clean GLB roots.
- Runtime materials are external Godot `.tres` resources. GLB material slots
  are stable placeholders, not final look development.
- Pack every regular image used by export materials into the canonical `.blend`
  before hashing. This makes `source_sha256` cover baked texture inputs; layered
  `.kra`/`.exr` files remain provenance sources, not live export dependencies.
- Core glTF 2.0 only. No Draco, meshopt, KTX, or vendor extension without a
  verified Godot 4.7.1 Mobile + Compatibility test.

## Originality

Subway Surfers City is a polish benchmark only. No model, texture, character
proportion, animation timing, prop, logo, graffiti, layout, or UI may be
copied or traced. Waddle Wars uses an original Antarctic expedition/research
port visual language defined in `runner/style/STYLE_BIBLE.md`.
