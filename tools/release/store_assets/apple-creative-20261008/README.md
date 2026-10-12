# Apple header and search creative — 2026-10-08

Final files:

- `header-3840x1646.png` — App Store product page header, 21:9.
- `search-1920x1280.png` — App Store search result image, 3:2.

Both are opaque RGB PNGs and were uploaded to [App Store Connect version 1.0](https://appstoreconnect.apple.com/apps/6818416048/distribution/ios/version/inflight) under **Header and Search Results**. Each slot showed `1 of 1` after upload and again after a page reload. `header-portal-preview.png` and `search-portal-preview.png` capture Apple's iPhone previews; the corrected header keeps the full wordmark in frame.

Built-in ImageGen supplied reframed scenic backgrounds using `art_src/ui/menu/home_background_landscape_v1.png` as edit target, preserving the scarfed penguin and avalanche. Header prompt requested a 21:9 Antarctic coastal scene with the penguin left and clear sky on the right; search prompt requested the same subject in 3:2 with clear right-side logo space. Both prompts prohibited text, logos, UI, extra characters, and watermarks. Exact `art_src/ui/title/waddle_wars_wordmark_v4_source.png` was composited on top of each output, then rasterized to Apple's required dimensions. No AI-rendered lettering was used.

Source outputs are in `$CODEX_HOME/generated_images/01a10e8d-4326-7813-a0f4-67cc5f75cc79/` as `exec-e1d4c03f-3006-4e35-a9ab-4e676627f0f8.png` (header scene) and `exec-abf1cdb8-26f9-4eeb-8f61-b2f53923d3e5.png` (search scene).
