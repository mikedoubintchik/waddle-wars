# Missing menu concepts — ImageGen pass, 2026-10-06

These are art-direction references, not flattened runtime UI. All controls,
prices, standings, account states, bindings, and actions remain live Godot nodes.
Each generated concept follows the approved `DESIGN_SYSTEM.md` ice/ivory/coral
materials and original penguin identity.

| Concept | Source | Intended screen |
| --- | --- | --- |
| `controls_v1.png` | Settings art direction and live binding semantics | Controls / remapping |
| `runner_pause_v1.png` | Waddle Run hero, avalanche chase | Runner pause |
| `runner_results_v1.png` | Waddle Run finish/retry state | Runner results |
| `race_mode_select_v1.png` | Four existing race modes; no invented mode | Race setup |
| `race_pause_v1.png` | Existing resume/restart/settings/course/base actions | Race pause |
| `race_results_v1.png` | Existing standings columns and race actions | Race results |
| `mode_select_v1.png` | Early Waddle Run mode exploration | Archive only; not a runtime target |
| `settings_category_icons_v1.png` | Five illustrated settings category icons | Runtime icon atlas |
| `race_setup_background_v1.png` | UI-free edit of race setup concept | Runtime race setup backdrop |
| `race_results_background_v1.png` | UI-free edit of race results concept | Runtime race finish backdrop |
| `waddle_race_wordmark_v1.png` | Standalone icy/gold wordmark | Runtime race mode header |
| `race_complete_wordmark_v1.png` | Standalone icy/gold finish heading | Runtime ordinary race result |
| `controls_title_v1.png` | Standalone snow-capped CONTROLS lettering | Runtime key-bindings header |

Generation instructions: portrait 9:16 animated-film Antarctic expedition game
UI; large approachable penguins; hand-painted glacier/base camp environments;
carved ice display lettering; snowy ivory rounded controls; navy readable text;
coral primary action; no copied franchise design; real phone-safe composition.
Screen-specific labels and actions above were supplied verbatim. The settings
icon generation was a transparent five-icon atlas; runtime asset is
`assets/art/ui/menu/settings_category_icons_v1.webp`.
The race backdrop edits specifically removed concept-only buttons, text and
characters; scene composition and finish-line landmarks were retained. The
wordmarks were separate transparent output assets, never clickable bitmaps.

Rejected wardrobe exploration: a proposed transparent eight-species full-body
atlas returned only seven species and an opaque gradient. It is *not* in the
runtime or this source set. Existing eight differentiated species portraits
remain in use until a complete, approved full-body set is authored.
