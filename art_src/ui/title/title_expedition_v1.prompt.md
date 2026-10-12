# `title_expedition_v1` provenance

Generated on 2026-08-18 with Codex built-in ImageGen. Model/build identifier
was not exposed by the tool. Both images are original Waddle Wars source art;
runtime copies live under `assets/art/ui/`.

## Landscape

- Source: `title_expedition_landscape_v1.png`
- Size: 1672×941
- SHA-256: `9b7c4ee5341f1f8a25052062aa99e1355009c7f8d63c60803d671178b871b5b3`

Base prompt:

```text
Use case: stylized-concept
Asset type: shippable landscape game title and loading-screen background for Waddle Wars
Primary request: original premium Antarctic expedition-city scene for a polished arcade game, showing a lively ice research port built around a three-lane frozen causeway leading toward a distinctive domed observatory landmark
Scene/backdrop: expansive Antarctic ocean, rounded snow shelves, modular research domes, radar dishes, small crane, flags and warm windows; strong near/mid/far staging; distant tiny penguin expedition silhouettes only
Subject: environment is hero; recognizable destination landmark centered in upper-middle distance; three-lane causeway creates forward energy
Style/medium: extremely high-quality hand-painted stylized 3D game key art, chunky rounded silhouettes, clean readable shapes, baked ambient occlusion and curvature, controlled gradients, premium mobile game finish, original visual identity
Composition/framing: wide landscape composition suitable for 16:9 crop; generous calm negative space across upper center for separate game logo; keep lower center and bottom corners low-detail enough for separate loading/menu UI; preserve useful crop area for portrait center crop
Lighting/mood: crisp polar sunrise, warm coral-gold light against cyan and deep navy ice, optimistic expedition adventure, subtle blowing snow and depth haze
Color palette: deep navy, glacial cyan, snow white, coral-orange warmth, restrained violet accents; no neon overload
Materials/textures: hand-painted snow, frosted painted metal, translucent ice, soft atmospheric clouds; controlled detail, no noisy microtexture
Constraints: no text, no letters, no logos, no watermarks, no UI, no copied franchise characters or locations, no trains, no city streets, no photorealism; original Antarctic world only
Avoid: empty flat corridor, generic stock concept art, clutter behind future UI, excessive bloom, cheap low-poly look, visible modern brand marks
```

Cleanup edit prompt:

```text
Use case: precise-object-edit
Asset type: shippable landscape game title/loading background
Input images: Image 1 is the edit target
Primary request: remove only the small white signature-like/watermark-like mark in the extreme bottom-right corner and reconstruct that tiny area as clean matching blue snow and ice
Constraints: change only that bottom-right mark; preserve exact dimensions, composition, Antarctic research city, causeway, lighting, colors, clouds, buildings, landmark, and every other pixel-level visual feature as closely as possible; no new text, logo, mark, watermark, character, or object
```

## Portrait

- Source: `title_expedition_portrait_v1.png`
- Size: 941×1672
- SHA-256: `45203a0cdfadc249ca292f2a27900e5cc70b092cd8be049fcffdb4a2907b6125`

Prompt, using landscape generation as style/world reference:

```text
Use case: stylized-concept
Asset type: shippable portrait game title and loading-screen companion background for Waddle Wars
Input images: Image 1 is style, world, palette, material, and landmark reference; generate a new portrait composition, do not merely crop
Primary request: recompose the same original Antarctic expedition city and domed observatory into a premium 9:16 portrait scene
Scene/backdrop: same glacial research port, frozen three-lane causeway, modular domes, radar and crane, ocean and ice shelves
Subject: environment remains hero; causeway starts wide at bottom and leads to observatory around upper-middle; tiny distant penguin expedition silhouettes only
Style/medium: exactly match Image 1's high-quality hand-painted stylized 3D game finish, rounded silhouettes, clean readable shapes, baked AO/curvature, controlled gradients
Composition/framing: tall portrait; generous clean sky in top 22% for separate logo; landmark below logo zone; bottom 22% low-detail enough for separate Begin/loading UI; keep causeway and three lanes readable
Lighting/mood: same crisp polar sunrise and optimistic expedition adventure
Color palette/materials: match Image 1
Constraints: no text, no letters, no logos, no watermarks, no UI, no copied characters or locations, no trains, no street city, no photorealism; remove any signature-like or watermark-like mark
Avoid: cramped crop, clutter under future UI, excessive bloom, cheap low-poly look
```

## Loading penguin

- Source: `loader_penguin_expedition_v1.png`
- Size: 1146×1372, RGBA with transparent background
- SHA-256: `c3d78dd0ef1c86bbdeb9b44621a04968fbec0c24c4f72b8ea73ee8f882e80af6`

Prompt:

```text
Use case: stylized-concept
Asset type: premium game loading indicator character cutout with genuine transparent background
Primary request: original Waddle Wars penguin expedition courier, full body, in a lively forward-running pose that reads clearly at 160 pixels tall
Subject: chunky rounded penguin with expressive determined-friendly eyes, compact flippers, orange bill and feet, wearing a deep navy expedition vest, short warm coral-orange scarf, small violet utility pouch; one foot forward, subtle snow kick at feet
Style/medium: extremely polished hand-painted stylized 3D mobile game character render, clean silhouette, soft baked AO and curvature, controlled highlights, appealing original mascot proportions
Composition/framing: centered full body, three-quarter front view, generous transparent padding, no crop, no ground plane except tiny isolated snow kick attached to feet
Lighting/mood: warm key light and cool cyan rim, energetic and optimistic
Color palette: black/charcoal and cream penguin, orange bill/feet, navy clothing, coral scarf, restrained violet accent
Constraints: genuinely transparent background with clean alpha edges; no text, no letters, no logo, no watermark, no frame, no badge, no scenery, no shadow rectangle, no copied franchise character
Avoid: photorealism, cheap low-poly, baby proportions, excessive gear, weapons, gradients filling background
```
