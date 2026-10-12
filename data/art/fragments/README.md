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
  an explicit boolean `production_ready`. Unapproved review fragments keep
  `false`; only approved central catalog entries may use `true`.
- Blender exports record their canonical `.blend` source, exact source hash,
  collection, output, class, geometry limits, transforms, sockets, and clips.
- Generated images record the exact source image, prompt record, generator
  disclosure, date, dimensions, hash, and license.
- Shared texture/material files point to the source export that canonically
  owns their packed inputs. The runner DAY kit uses
  `runner_day_deck_kerb_v1` as that atlas anchor.
- Never set `production_ready` before rendered visual review, import checks,
  gameplay integration, and applicable performance gates pass.

Validate the complete authoring inventory without changing central manifests:

```bash
python3 tools/art/validate_art.py --review-fragments
```

This mode checks every registered file, hash, license, source link, declared budget,
and orphan, while permitting `production_ready: false` only for additional
review-fragment entries. It reports the unresolved review count and explicitly
does not establish release readiness. A false entry in the central catalog is
still an error.

The strict release gate remains:

```bash
python3 tools/art/validate_art.py
```

It rejects unregistered review files and any central entry that is not
production ready. Keep that gate open until the art itself has passed review;
never copy review fragments into production merely to make this command pass.

Check merge conflicts and inventory counts without changing central manifests:

```bash
python3 tools/art/merge_art_fragments.py
```

After every stream is frozen and reviewed, merge atomically:

```bash
python3 tools/art/merge_art_fragments.py --apply
```

The apply command validates both merged manifests and restores their previous
contents on any failure. Keep fragments after merge as provenance records.

The rear runner penguin uses a prepared `authored_packages` source entry with
the separate `runner_character` contract: at most 15,000 triangles, one surface,
15 bones, four skin influences, and `jump`, `slide`, `waddle` clips. Its custom
builder writes the GLB directly; it is not a generic named-collection export.
The package binds the Blender source, custom builder, runtime GLB and JSON
binding by hash. The JSON binding is registered with the `metadata` runtime
kind. Front/podium art remains incomplete (`front_ready: false`), and fragment
entries remain `production_ready: false` pending applicable release gates.
The existing shared-character geometry, 23-clip and accessory-socket contract
is unchanged.

Historical Blender iterations are recorded separately in `study_sources`.
These entries verify path, hash and license while remaining source-only. They
do not create runtime exports or grant approval to rejected/archived studies.
