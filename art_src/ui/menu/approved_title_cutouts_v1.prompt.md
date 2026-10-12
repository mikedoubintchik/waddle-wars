# Approved menu title cutouts v1

Source: original Waddle Wars ImageGen concepts in this directory. These are
original project artwork; no third-party image license. Each transparent PNG
was extracted with built-in ImageGen background-extraction mode, then converted
to quality-88 WebP for runtime. Keep the PNG as the editable source and the
WebP under `assets/art/ui/menu/` as the shipped asset.

| Output stem | Edit target | Invariant |
|---|---|---|
| `base_camp_sign_v1` | `base_camp_v1.png` | Only hanging snow/wood BASE CAMP sign and ropes; exact blue/orange lettering; transparent elsewhere. |
| `settings_title_v1` | `settings_v1.png` | Only icy SETTINGS lettering and snow; transparent elsewhere. |
| `leaderboard_title_v1` | `leaderboard_v1.png` | Only icy LEADERBOARD lettering and WADDLE RUN ribbon; transparent elsewhere. |
| `achievements_title_v1` | `achievements_v1.png` | Only hanging ACHIEVEMENTS sign and ropes; transparent elsewhere. |
| `shop_title_v1` | `shop_v1.png` | Only hanging SHOP sign and ropes; transparent elsewhere. |
| `missions_title_v1` | `missions_v1.png` | Only snowy ivory MISSIONS capsule; transparent elsewhere. |
| `account_title_v1` | `account_v1.png` | Only snow-topped navy ACCOUNT lettering; transparent elsewhere. |
| `penguins_title_v1` | `penguins_v1.png` | Only snowy PENGUINS capsule and avatar; transparent elsewhere. |

Generation prompt pattern: “Use case: background-extraction. Extract ONLY the
specified title from the approved imagegen mockup. Preserve exact lettering,
materials, snow, shadows, and colors. Remove all other objects and background
to genuine transparent alpha. Tight framing. No new elements.” The text names
above were required verbatim for each asset. Recheck transparency and spelling
before any replacement.
