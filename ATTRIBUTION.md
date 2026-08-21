# Attribution

## Original content

All content in Waddle Wars is original work created for this project:

- **Code**: all GDScript, Python tooling, and configuration — original.
- **3D runtime art**: current models are procedural (Godot primitive meshes +
  SurfaceTool geometry composed in code). Authored glTF pipeline exists, but no
  third-party models are bundled.
- **2D art**: `assets/icons/icon.svg` (logo/icon) is an original SVG drawn for
  this project. The Antarctic expedition title backgrounds and loading penguin
  under `assets/art/ui/` were generated for this project from original prompts
  using OpenAI's built-in ImageGen tool, then reviewed and prepared for runtime
  use. Exact prompts, dimensions, hashes, and tool disclosure live in
  `art_src/ui/title/title_expedition_v1.prompt.md`.
- **Audio**: every sound effect and music track is synthesized by
  `tools/generate_audio.py` (original DSP code, original melodies). No samples,
  no recordings, no third-party audio.
- **Art-direction concept**: `art_src/runner/style/concepts/runner_day_keyart_v1.png`
  was generated for this project from an original prompt using OpenAI's built-in
  ImageGen tool. It is source-only (`art_src/.gdignore`) and not exported with
  the game. Prompt/provenance lives beside the image.

The game does not copy any existing franchise's characters, names, logos,
locations, UI, or melodies.

## Font

**Atkinson Hyperlegible Next 2.001** by the Atkinson Hyperlegible Next Project
Authors (Copyright 2020–2024) is bundled at
`assets/fonts/AtkinsonHyperlegibleNext-wght.ttf` under the SIL Open Font
License 1.1. Upstream revision:
`7925f50f649b3813257faf2f4c0b381011f434f1` from
https://github.com/googlefonts/atkinson-hyperlegible-next.

Full license: `assets/fonts/AtkinsonHyperlegibleNext-OFL.txt`.

## Engine

Built with **Godot Engine 4.7.1** — free and open source software released
under the MIT license. Engine license text: https://godotengine.org/license/
Godot Engine's third-party notices apply to distributed binaries; when shipping
builds, include Godot's license notices as described at the link above (the
editor's Export dialog embeds them automatically).

## Authoring tools

Blender 5.2.0 LTS and Git LFS are workstation dependencies only. The official
Khronos glTF-Validator 2.0.0-dev.3.10 is pinned under `tools/art/package.json`
for export QA and is Apache-2.0 licensed. These tools and `node_modules` are not
part of game runtime exports.

## License obligations summary

- Godot Engine (MIT): include copyright + license notice in distributed builds.
- Atkinson Hyperlegible Next (SIL OFL 1.1): retain copyright and OFL text when
  redistributing the font; do not sell the font by itself.
