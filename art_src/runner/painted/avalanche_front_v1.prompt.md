# Opening avalanche VFX source

Generated with Codex built-in image generation on 2026-10-05 as original Waddle Wars game art. Runtime cutout: `assets/art/runner/avalanche_front_v1.png` (SHA-256 `b4e7f671433510a29c990f5958ebbb0a280450acf1a9242b61ce927d20c07265`). Transparent PNG, 2172×724. No external image reference or third-party asset used.

Built-in ImageGen prompt (verbatim):

> Use case: stylized-concept
> Asset type: production game VFX sprite sheet element for Waddle Run
> Primary request: one continuous rolling avalanche front made of wind-blown Antarctic powder snow, to appear along the lower edge of a portrait 3D runner camera. It should read as a dangerous moving snow mass, not cute clouds or separated balls.
> Subject: layered uneven snow crest with dense blue-gray body below, luminous white frothy lip, turbulent powder wisps and small snow flecks lifting above the crest.
> Style/medium: polished stylized 3D game render with hand-painted material response and soft baked shading, matching an expedition-adventure ice environment. Natural irregular silhouette and believable depth.
> Composition/framing: very wide horizontal strip, entire wave visible edge-to-edge, viewed slightly from above and front. Mass fills bottom half of canvas; soft spray rises into transparent upper half. Tile-friendly edges. No ground plane, no horizon.
> Lighting/mood: cool Antarctic daylight; readable blue shadow under white foam.
> Constraints: genuinely transparent background with clean alpha and feathered powder edges. No characters, words, logos, UI, geometric polygons, round snowballs, separate floating clouds, watermark.

Runtime use: two offset `Sprite3D` layers in `RunnerChaser` during countdown and opening seconds. This is presentation only; collision and pressure remain code-owned. Preview under Mobile and Compatibility before release. Resize to power-of-two atlas before final art-budget gate.
