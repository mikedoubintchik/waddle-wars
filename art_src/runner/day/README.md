# Runner DAY authored kit

Project-original polar research-port kit for runner DAY chunks, reviewed first
through the internal golden slice. Runtime entries remain review-only until
moving-footage and performance gates pass. Blender 5.2.0 source is generated
deterministically from `generate_day_kit.py`; committed
`runner_day_kit_v1.blend` remains canonical editable source and is exported to
core glTF 2.0 by `tools/art/build_runner_day_kit.py`.

Design rules:

- one metre in Blender equals one metre in Godot;
- Blender `-Y` is runtime forward (`-Z` after glTF Y-up conversion);
- every collection has one joined mesh, one placeholder surface, identity root;
- baked face response and semantic paint are stored in `COLOR_0`; macro wear,
  edge AO, roughness, and normal response live in shared atlas maps;
- orange means hazard, cyan means duck, green means launch;
- all gameplay shells preserve existing collider silhouettes;
- sources contain no cameras, lights, collision, or runtime scripts.

Deck uses three dimension-identical topology variants:
`runner_day_deck_kerb_v1`, `runner_day_deck_kerb_b_v1`, and
`runner_day_deck_kerb_c_v1`. Modeled beveled cassettes, snow-bank caps, broad
irregular ice repairs, nonuniform panel runs, and distinct service access
layouts preserve macro detail after mipmapping without changing lane
silhouettes. Runtime groups each variant into its own MultiMesh; gameplay floor
and collision remain unchanged.

V8 review direction treats this as an occupied Antarctic logistics port, not a
white display plinth. Deck paint is warm gray/cyan with two broad service-wear
tracks, irregular frost deposits, orange cliff-route trim, and restrained white
only on snow banks. Research windows and work lamps use a separate warm amber
surface that is less saturated than semantic hazard orange. Existing joined
prop families now carry large route panels, service cable reels, labels, doors,
and rounded portal joints; these details share the same atlas and shader pair.
Seeded staging uses clustered pylons/labs/cargo, one authored iceberg beat every
three chunks, and one distinct destination landmark every four chunks. Empty
shelf between clusters preserves the 55–70 m lane decision horizon.

`runner_day_iceberg_cluster_v1` is an authored skyline dressing family, not a
hero landmark. Five overlapping faceted masses provide fractured, rounded,
multi-plane silhouettes while retaining one surface/one MultiMesh draw. DAY
uses this mesh in the existing seeded iceberg placement seam; other biomes keep
their existing procedural families and no gameplay RNG is consumed.

`runner_day_deck_kerb_v1` is kit provenance anchor. Canonical `.blend` packs
shared 1024² painted albedo, OpenGL normal, and packed ORM inputs. Runtime PNG
and material-family derivatives reference that anchor because its source SHA
covers entire kit file and all three packed images. GLBs keep placeholder
material slots; Godot wrapper consumers apply external `runner_day_surface_v1`
or double-sided `runner_day_shell_v1` material.

Runtime texture imports use VRAM compression (`compress/mode=2`) and mipmaps.
The normal atlas is explicitly tagged as a normal map; the packed ORM atlas
uses optimized channel packing. Two shared Compatibility-safe shader variants
cover back-face and double-sided culling. Both sample the same atlas once per
channel and add at most 0.065 hue-preserving emission—enough to hold paint in
shadow without flattening normal response. No screen/depth textures,
derivatives, per-asset variants, or parallax are used. Wrapper scenes own
stable catalog/import paths; `RunnerTrack` applies the external material family
to extracted meshes so each per-chunk MultiMesh remains one surface and one
draw.

Rebuild:

```bash
python3 tools/art/build_runner_day_kit.py --all
```

This rebuilds source, validates budgets during each Blender export, runs pinned
Khronos glTF Validator, and refreshes proposal fragment hashes. Normal game
builds consume committed GLBs and wrapper scenes; Blender is not required.
