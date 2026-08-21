# Runtime authored art

Godot-importable outputs only. Editable sources live under `art_src/` and are
excluded from Godot scans.

Current state: art foundation plus three production frontend textures (two
orientation-specific expedition backgrounds and one transparent loading
mascot). Authored 3D models are not registered yet; gameplay geometry remains
procedural while that rollout continues.

## Contract

- `art_manifest.json` is runtime catalog authority.
- Asset IDs are stable `lower_snake_case` API keys, not display labels.
- Runtime paths stay below `res://assets/art/`.
- Entries are sorted by ID; groups are sorted and unique.
- Hash is lowercase SHA-256 of committed runtime file.
- Every entry names a validated Blender export job or generated-source record,
  plus its approved license.
- Production scenes reference external Godot materials.
- Runtime code requests catalog IDs. It never loads `art_src` paths.

Validate after every asset change:

```bash
python3 tools/art/validate_art.py
godot --headless --path . res://tests/art_foundation_test.tscn
```

Use `python3 tools/art/validate_art.py --format` only to canonicalize manifests;
it does not generate or invent asset records.
