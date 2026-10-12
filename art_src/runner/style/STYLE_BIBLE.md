# Waddle Wars authored art bible

Version 1.0 — runner-first production target

## North star

Premium stylized Antarctic action: readable at phone size, rich in motion,
specific enough to feel authored, efficient enough for Godot Compatibility on
the web. Quality comes from silhouette, proportion, bevels, controlled value,
animation, staging, and contact feedback—not photoreal shader complexity.

Subway Surfers City supplies only a quality bar: clean forms, layered worlds,
strong pose language, anticipation, overshoot, and dense polish. Waddle Wars
must remain visually and legally distinct.

## Original world

Runner crosses a polar research-and-logistics causeway. Human-built forms feel
field-repaired and weather-tested: modular gantries, snow fencing, instrument
masts, rope rails, cargo sleds, beacon cages, fuel-safe research equipment,
ice-cut tunnels, and expedition markers. Nature remains dominant: pressure
ridges, blue ice, wind-carved snow, ice shelves, berg silhouettes, seals, and
aurora.

Avoid urban rail vocabulary, subway cars, spray-paint graffiti, copied street
furniture, or another runner's landmarks. Humor comes from penguin-scale use
of Antarctic hardware.

## Shape language

- Player: round core, tapered limbs, clear head/body pinch, strong rear-view
  white flank break. Never a featureless dark egg.
- Safe route: broad horizontal planes and continuous edges.
- Dodge hazard: compact, top-heavy, blunt, orange structural cue.
- Duck hazard: spanning arch, open negative space, cyan cue.
- Ramp/reward: rising wedge, forward diagonal, green cue.
- Environment: chunky bevels and 3–5 intentional planes per major mass.
- Human hardware: rectangular modular frame plus one rounded safety detail.
- Natural ice: asymmetric wedges, pressure folds, fractured but readable.

Silhouette carries gameplay meaning before texture or color. Any obstacle that
fails in flat black fails review.

## Value hierarchy

Each frame uses three main value bands:

1. Dark silhouettes: player dorsal, deep kerb, far structure.
2. Mid-value route and environment body.
3. Bright snow edges, path seams, pickups, and action accents.

Keep horizon distinct from ground. Reserve near-white for navigation/contact
highlights. Detail never erases player or obstacle outline.

## Semantic color

Meaning remains fixed across every biome:

- Gold: collect.
- Violet: power-up.
- Orange-red: dodge/harm.
- Cyan: duck/near miss.
- Green: ramp/go/launch.
- White-blue: kicked snow/contact.

Biome accent is decorative only. Never reuse semantic hues to mean unrelated
decoration near gameplay lane.

## Biome scripts

### Day glacier

Cobalt sky, pale blue horizon, warm cream sun, saturated blue structural mid
tones. Crisp visibility. Research-port silhouettes and wind make world active.

### Dusk shelf

Violet upper sky, coral horizon, long warm shadows, gold seam light. Maintain
cool player rim so penguin remains separate from warm route.

### Blue-ice cave

Deep navy void, turquoise transmitted ice, cyan seam light, small warm safety
hardware accents. Opaque faceted ice; no large alpha-blended shells.

### Aurora night

Near-black blue ground, indigo horizon, restrained green/violet sky motion.
Route values remain explicit; aurora never competes with obstacle verbs.

## Materials and texture

- One opaque atlas material per repeated prop or obstacle.
- Maximum two opaque surfaces on player; three on hero landmark.
- Use authored albedo, OpenGL tangent normal, and ORM map.
- Broad painted variation survives ETC2. Avoid fine grain and subtle smooth
  gradients that collapse under web compression/render scaling.
- Bake macro AO/cavity; use geometry bevels where silhouette catches light.
- Opaque RGB by default. Alpha scissor only for flags, feathers, or cut cards.
- Avoid alpha blending, refractive ice, screen decals, SSS, and DOF.
- Atlas islands need 12–16 px gutters at 2048 with mipmaps.
- Regular texture maximum 2048 square. 4096 requires measured exception.

## Character

One canonical skeleton/rest pose drives all eight penguin species. Species use
shared topology where possible, swappable bill/crest parts, material parameters,
and limited shape keys. Cosmetics attach to named head, face, neck, and trail
sockets.

Runner motion set:

- `countdown_idle`, `fidget`
- `run` (speed-scaled), `lean_left`, `lean_right`
- `jump_takeoff`, `jump_air`, `jump_land`
- `slide_enter`, `slide_loop`, `slide_exit`
- `ramp_launch`, `ramp_flip`, `ramp_land`
- `swim`, `shove`
- `hit_left`, `hit_right`, `stumble`, `recover`
- `wipeout`, `defeat`, `celebration`

Physics owns translation. Animation contains no root-motion authority. Every
action needs anticipation, readable key pose, fast action, overshoot, settle,
and restrained secondary wing/scarf motion.

## Environment composition

- Near: route edges, obstacles, contact snow; strongest contrast.
- Mid: modular hardware, ice walls, flags, moving wildlife; rhythm and scale.
- Far: large simple landmarks and dark horizon silhouettes; destination.
- One landmark beat every 3–5 chunks. Do not uniformly sprinkle props.
- Empty breathing chunks are deliberate. Density without hierarchy looks cheap.

Current runner chunk is 36 m. Author and batch to this boundary. Repeated art
uses one MultiMesh per chunk, mesh, and material so culling/LOD remain local.

## Lighting and VFX

Compatibility renderer is shipping truth. Use one directional key, non-shadow
fill, baked surface response, and controlled emission. Local shadow lights are
rare. Emission must read with glow disabled.

Contact feedback hierarchy:

- collect: compact gold burst
- power-up: larger violet ring/core
- jump land: low lateral snow fan plus contact ring
- slide: continuous low spray
- hit: orange impact plus camera impulse
- near miss: cyan snap
- ramp: green launch accent plus authored flip

No particle trail or decal dependency. Use mesh/MultiMesh equivalents.

## Budgets

Manifest is machine-readable authority. Review targets:

| Asset | LOD0 triangles | Surfaces |
|---|---:|---:|
| Player plus cosmetics | 18,000–25,000 | ≤2 |
| Gameplay obstacle | 1,500–5,000 | 1 |
| Repeated dressing | 300–1,500 | 1 |
| Hero landmark | 10,000–30,000 | ≤3 |

Character: ≤36 deform bones, ≤4 skin influences per vertex. Scene: ≤16 shader
signatures. Measured draw-call gates are high 250 average/300 peak, medium 205
average/250 peak, low 190 average/225 peak. Visible primitive caps are 100k,
75k, and 50k respectively. Full runner authored textures: ≤64 MiB VRAM.
Vertical slice: ≤15 MiB compressed; full runner authored increment: ≤40 MiB;
all authored art across game: ≤120 MiB compressed.

Triangle minima are visual-complexity review floors for production-ready LOD0
assets, not encouragement to add invisible geometry. Deliberately simpler assets
need a measured, documented budget revision instead of padding topology.

## Quality tiers

Gameplay silhouettes and animation never downgrade.

| Tier | Dressing | LOD threshold | Shadow distance | VFX | Far art |
|---|---:|---:|---:|---:|---:|
| High | 100% | 1.0 | 90 m | 100% | 7 chunks |
| Medium | 65% | 2.0 | 55 m | 60% | 5 chunks |
| Low | 35% | 4.0 | critical only | 35% | 4 chunks |

## Acceptance

- Obstacle verb identifiable at 50–60 m in color and silhouette-only review.
- Player/species recognizable at chase-camera size.
- No visible atlas bleed, broken normal, transparent sort error, or gradient
  banding in Compatibility captures.
- Planted foot drift ≤2 cm; action contact within one 60 Hz frame.
- Zero shader/material first appearance after opening six seconds.
- Zero frame over 100 ms after countdown.
- Desktop web high and representative midrange phone medium target at least
  57 fps average with p95 at most 20 ms. Low-tier fallback targets at least
  29 fps average with p95 at most 36 ms.
- Review deterministic rear, side, slow-motion, phone, and Compatibility
  captures. Attractive editor viewport alone is not acceptance.

## First authored milestone

360 m / ten DAY chunks: hero penguin, full runner motion set, five obstacle
verbs, seal, fish, power-up crate, modular causeway, 12–18 dressing props, and
three landmark beats. Procedural fallback remains until complete slice passes
readability, performance, and provenance gates.
