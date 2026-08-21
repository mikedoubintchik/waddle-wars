# Runner DAY V9 — Expedition Port Structure Pass

V8 proves asset loading, budgets, deterministic staging, semantic colours, and
both camera compositions. V9 must change scene authorship, not exposure.

## 360 m destination sequence

1. **Operations apron, 0–108 m** — staggered lab/service-bay cluster on one
   side, tracked snowcat maintenance on the other, one broad cream/cyan pipe
   rack. Open centre preserves three-lane verbs and 70 m horizon.
2. **Cargo transfer, 108–216 m** — offset container stacks, crane boom,
   suspended cable bundle, route boards, repair tent, and one chunky gantry.
   Ship grows from skyline landmark into destination silhouette.
3. **Science approach, 216–360 m** — radar compound, antenna forest, elevated
   enclosed walkway, warm window rhythm, then research-hub arrival gate.

Each beat gets one dominant silhouette, one secondary cluster, and negative
space. No prop family may repeat at equal spacing for three consecutive chunks.

## New authored modules

- Three portal families sharing one atlas/material: rounded service arch,
  offset pipe rack, enclosed observation bridge. Use at authored beats only;
  never stamp one portal every chunk.
- Five 36 m deck modules: operations panels, drainage channels, frosted tyre
  lanes, bolted repair plates, cargo apron. Model bevels, expansion joints,
  inset hatches, snow-bank lips, and shallow ice patches. Gameplay surface and
  collision remain unchanged below visual shell.
- Service-bay cluster: curved lab end caps, doors, window recesses, external
  conduit, bollards, cable reel, tool lockers, lamp arm.
- Cargo-transfer cluster: rounded containers, snow-loaded corners, crane base,
  boom, hook silhouette, tied cable bundle, route signage.
- Science cluster: radar pedestal, antenna dishes, enclosed walkway, mast
  braces, warm window strips, destination identifier.
- Snowcat hero prop: modeled continuous tracks, articulated bogies, cabin
  frame, inset glazing, work lamps, hazard-orange body panels, snow buildup.

## Value and material construction

- Warm-gray/cyan deck is mid-light base. Cream structural faces catch light.
- Navy appears only in recessed joints, glazing, vents, track cavities, and
  underside gaps—never as continuous rail or portal band.
- Orange marks route/hazard hardware only. Warm amber marks occupied windows.
- Atlas carries broad painted panel breakup, 0.5–2 m frost/wear shapes, edge
  chipping, grease around mechanisms, and directional tyre abrasion. Details
  must remain visible at 100–300 px object size in Compatibility captures.
- Keep current two shared DAY shader variants; no screen/depth sampling,
  parallax, derivatives, or per-asset material duplication.

## Staging and performance limits

- Preserve gameplay RNG/colliders; all choices use seeded `art_rng`.
- Maintain unobstructed lane silhouettes and 55–70 m decision horizon.
- Maximum one hero cluster plus one secondary cluster per chunk.
- Reuse MultiMesh for cable reels, bollards, route signs, lamps, and small
  containers. Target runner average <=250 / peak <=300 draws on High.
- Keep runner shader census <=16 and external warmup probes <=32.
- Keep repeated props <=1,500 triangles where practical; interactive visual
  shells 1,500–5,000; landmarks 10,000–30,000; one material surface each.

## Review gate

Capture portrait 540x960 and compact 960x540 at 2/74/146/218/280 m plus close
service-bay, snowcat, portal, and deck crops. Reject if modules still read as
primitive cuboids, deck repeats as uniform tiles, occupancy cues vanish at
chase distance, or any portal/cluster masks future lane verbs.
