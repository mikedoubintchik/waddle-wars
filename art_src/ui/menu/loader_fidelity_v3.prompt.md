# Loader fidelity — 2026-10-07

Built-in ImageGen, with `loader_theme_v2.png` as project-owned edit reference.
Model, build and seed not exposed. Raw transparent PNGs preserved; runtime
WebP siblings encoded with cwebp quality 92, alpha quality 100. No invented
progress, percentages or loading milestones baked into images.

## loader_courier_v3.png

Use case: background-extraction. Production game UI transparent character
cutout. Extract only the exact small running scarf penguin from the center of
the reference. Preserve cheerful baby penguin identity, black fluffy fur,
creamy belly, blue eyes, open smiling yellow beak, orange feet, rightward
side-running pose with extended front foot, red knitted scarf streaming left,
and tiny kick of snow under rear foot. No vest, bag, hat or other clothing.
Match premium sculpted storybook finish, warm ivory highlights and cool snow
reflections. Entire scarf and feet visible; centered with transparent padding.
Remove card, bar, logo, words and scenery; genuine transparent alpha.

Generated source: `exec-95dd4afe-c387-40fc-863d-c6cbcc27fd55.png`.

## loader_track_v3.png

Use case: precise-object-edit. Production loading progress empty track sprite.
Extract only the reference horizontal pale-blue icy progress track, removing
all coral fill. Preserve long capsule silhouette, thick sculpted pale-blue
beveled ice rim, frosty cracks, white snow on upper edge/corners, dimensional
blue inner shadow, front orthographic view. Uniform empty powder-blue recess.
Outside genuine transparent alpha. No penguin, card, background, text, logo,
numbers or progress fill. Wide composition with full track inside frame.

Generated source: `exec-553c9b55-24e1-49f8-a3bc-8e88f6f0e52d.png`.

Runtime uses an AtlasTexture region `(32,142,2014,420)` to remove transparent
padding without repainting the artwork. Coral remains the existing authored
`coral_shelf_blank_v1.webp`, controlled by real loading progress.

## Exact-reference follow-up extracts

- `loader_card_v3.png`: Extract only blank ivory card; preserve rounded
  parchment face, fine warm paper texture, thick irregular fluffy snow on all
  outer edges/corners, blue dimensional shadow. Remove mascot, bar, logo,
  scenery and every word; reconstruct uninterrupted ivory. Genuine alpha.
  Source `exec-5938dd79-84e8-4419-a78e-9f6a69249430.png`.
- `loader_logo_v3.png`: Extract exact WADDLE WARS sign: ice-blue WADDLE,
  gold/orange WARS, rustic brown wooden planks, two bolts, snow cap and lower
  snow edge. Full sign, genuine alpha; no card, mascot, bar or scenery.
  Source `exec-7d879c88-6dd9-49f6-9aa5-f61bc3b05ea4.png`.
- `loader_background_v3.png`: Remove entire central card, mascot, progress,
  loading copy and WADDLE WARS sign. Preserve defocused outdoor BASE CAMP
  cabin, lantern, snowy red mug/barrels, map, pennant, Antarctic vista and
  ADVENTURE AHEAD sign. Reconstruct quiet natural central scene; opaque16:9.
  Source `exec-487dece5-80c8-4132-ac3f-a7a366ea98dc.png`.

Card runtime compressed at768×512 and cropped by AtlasTexture
`(16,28,746,442)`; logo quality91; background quality90. Web startup copies
use768×512 courier and1007×210 track cropped from the same source region.
Browser assets are versioned `web/loader-*-v3.webp`; shipping script includes
them and correct WebP content type. No export or deployment was performed.
