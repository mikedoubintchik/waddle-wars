# Art manifest fragments

Parallel art streams write reviewable fragments here. Each JSON file has
exactly these arrays:

```json
{
  "runtime_assets": [],
  "source_exports": [],
  "generated_assets": [],
  "concepts": []
}
```

Rules:

- Use stable, globally unique IDs and one runtime entry per shipped file.
- Runtime paths stay below `res://assets/art/` and must include the exact
  SHA-256, source export ID, license, groups, kind, and
  `production_ready: true`.
- Blender exports record their canonical `.blend` source, exact source hash,
  collection, output, class, geometry limits, transforms, sockets, and clips.
- Generated images record the exact source image, prompt record, generator
  disclosure, date, dimensions, hash, and license.
- Shared texture/material files point to the source export that canonically
  owns their packed inputs. The runner DAY kit uses
  `runner_day_deck_kerb_v1` as that atlas anchor.
- Never set `production_ready` before rendered visual review, import checks,
  gameplay integration, and applicable performance gates pass.

Check all fragments without changing central manifests:

```bash
python3 tools/art/merge_art_fragments.py
```

After every stream is frozen and reviewed, merge atomically:

```bash
python3 tools/art/merge_art_fragments.py --apply
```

The apply command validates both merged manifests and restores their previous
contents on any failure. Keep fragments after merge as provenance records.
