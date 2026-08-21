# Art pipeline tools

## Validate

```bash
python3 tools/art/validate_art.py
python3 tools/art/validate_art.py --format
```

Validator uses Python standard library only. It checks canonical JSON, schema
versions, pinned budgets/toolchain, safe paths, hashes, generated-source and
Blender-export catalog cross-references, concept provenance, orphan art files,
`.gdignore`, and Git LFS rules.

Registered frontend textures additionally require committed Godot import
settings with VRAM compression and mipmap generation; a raw lossless PNG import
fails validation before release.

## Merge parallel asset streams

Each independently reviewed art stream writes one canonical JSON fragment under
`data/art/fragments/` with exactly four arrays: `runtime_assets`,
`source_exports`, `generated_assets`, and `concepts`.

```bash
python3 tools/art/merge_art_fragments.py
python3 tools/art/merge_art_fragments.py --apply
```

Default mode is read-only. `--apply` merges by stable ID, accepts identical
entries idempotently, rejects ID/path conflicts, writes both central manifests
atomically, runs the complete validator, and restores both originals on any
failure. Fragments remain as review/audit records after merge.

## Export

```bash
python3 tools/art/export_art.py --dry-run
python3 tools/art/export_art.py --check-blender
python3 tools/art/export_art.py --check-validator
python3 tools/art/export_art.py --self-test-blender
python3 tools/art/export_art.py --all
python3 tools/art/export_art.py --id character_penguin
```

Bare invocation performs manifest preflight only and never exports. Use
`--all` or one or more `--id` flags for the explicit destructive boundary.

Resolution order: `--blender`, `BLENDER_BIN`, PATH, standard macOS/Homebrew
locations. Exact Blender 5.2.0 required. Empty export manifest succeeds without
Blender because game builds consume committed GLBs.

Exporter validates registered source hashes/licenses, root identity transforms,
`-Z` forward metadata, pivots, bounds, triangle ranges, material surfaces,
power-of-two textures, deform bones, skin influences, named sockets, and clip
coverage before export. It exports selected collection only, with core GLB
settings and required placeholder materials. Exact Blender capability drift
fails the self-test instead of silently falling back.

Install the pinned authoring-only official Khronos validator once with
`npm ci --prefix tools/art`. Every registered export is written to a candidate,
required to produce zero Khronos errors and warnings, then atomically promoted.
Normal Godot builds neither invoke nor ship Node or this dependency.

Export never marks work production-ready and never edits runtime manifest.
Artist/reviewer must inspect output, add explicit runtime record/hash/license,
then rerun validator.
