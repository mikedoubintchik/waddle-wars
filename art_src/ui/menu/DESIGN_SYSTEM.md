# Waddle Wars expedition UI — implementation contract

Source of truth: approved ImageGen home and submenu concepts in this folder.
The current painted backdrops alone are not the design system. All foreground
controls must share the same sculpted-material language before a page counts as
visually migrated.

## Layers

1. **World plate:** full-bleed illustrated Antarctic location, no embedded UI.
2. **Character art:** expressive, high-fidelity penguin portraits for static
   identity and species selection. Do not substitute loader art or an unrelated
   procedural icon. The 3D gameplay rig is outside this menu pass. Keep the
   existing live outfit preview available and label it honestly; a still
   portrait cannot show equipped items.
3. **Material kit:** snow-lipped ivory shelves/cards, coral-orange departure
   actions, frosted translucent detail panes, dark blue title ink. Reuse actual
   image assets with nine-slice margins, not flat color approximations.
4. **Live content:** localized labels, save state, prices, missions, records,
   settings, sign-in, and button hit areas remain native Godot controls.

## Geometry and hierarchy

- Portrait starts with art/character, then one dominant CTA, then compact
  destinations. Never place long text over a face.
- Safe-area aware; controls at least 48 logical pixels high, including cards.
- A screen has one dominant action. Secondary navigation appears on a shared
  ivory shelf or as quiet, consistent controls.
- Typography: accessible Atkinson for body/data; heavy navy display treatment
  for short headings; sufficient contrast on all painted regions.
- Buttons, cards, and tabs use stable centers so nine-slice scaling does not
  stretch snow, bevels, or shadows. Focus and disabled states remain visible.

## Asset and performance rules

- Prompt/source images and prompt metadata live here; compressed runtime art
  lives in `assets/art/ui/menu`.
- Each reusable UI material is textless and iconless, with transparent edges.
- Icon crops from approved concepts retain exact illustrated artwork and are
  not substitutes for live labels, scores, achievement state, or prices.
- No per-button texture creation or shader compilation during gameplay.
- Keep functional text live. Exception: the approved English home `WADDLE RUN`
  hero-action artwork is used exactly as supplied, with a native Button and
  accessible name underneath. Localized builds need their own hero-action art.
- Check 540×960 and 960×540 captures before applying a kit to every page.
- Approved headings are transparent cutouts from the corresponding full
  concepts, not generic text over the painted backdrop. Source and runtime
  filenames are recorded in `approved_title_cutouts_v1.prompt.md`.
- Where no dedicated landscape concept exists, crop the matching submenu
  environment and compose content in a right-side stack; never fall back to
  the unrelated home-run illustration.

## Quality gate

Compare captures side by side with `waddle_wars_menu_rethink_portrait_v1.png`
and corresponding submenu concept. Pass only if backgrounds, character art,
buttons, shelves, type hierarchy, and icon treatment read as one family. A
painted background under generic flat controls is a failure.
