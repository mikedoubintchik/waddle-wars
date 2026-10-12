# Menu visual audit — 2026-10-06

Reference images live in this directory. Fresh rendered Godot captures:
`qa_shots/tests/waddle-wars-frontend-49097-3125.kNijOE/` (360×640,
390×844, 844×390). This is a screen-by-screen comparison, not a claim that
every screen is pixel-identical. The refs contain illustrative placeholder
content; runtime state and purchase/account truth take precedence.

| Screen | Reference | Current result | Remaining visual gap |
| --- | --- | --- | --- |
| Home | `waddle_wars_menu_rethink_portrait_v1.png` | Hero, wordmark, coral Run, three illustrated nav buttons | Some portrait button proportions still differ |
| Base Camp | `base_camp_v1.png` | Cabin, carved hanging sign, tall ivory rows, illustrated icons, account strip | Some row spacing/material differs |
| Missions | `missions_v1.png` | Route chart, three live mission strips, Run Now visible | Mission iconography and map labels differ with live missions |
| Account | `account_v1.png` | Live guest/cloud status, metrics, privacy and deletion actions | Lower sheet/material detail differs |
| Penguins | `penguins_v1.png` | Distinct eight species and live wardrobe/equip actions | Hero art remains a bust, not full-body; category/gallery begins low |
| Leaderboard | `leaderboard_v1.png` | Finish podium, runner-only board, honest unavailable/guest state | No fabricated podium usernames/standings while offline |
| Achievements | `achievements_v1.png` | Illustrated case, live 2-column badge gallery | Gallery cards simpler than reference |
| Shop | `shop_v1.png` | Three illustrated bundle selectors with selected detail, live product/price state | More disclosure below fold than reference; no invented price |
| Settings | `settings_v1.png` | Five illustrated ivory/coral categories and live section sheet | Generated concept's control rows are more sculpted |
| Controls | `controls_v1.png` | Carved icy title, compact live binding rows and remapping sheet | Lacks concept's illustrated action pictograms |
| Credits | `credits_v1.png` | Landscape artwork, ivory journal, functional links | Typography is smaller than reference |
| Waddle Run pause | `runner_pause_v1.png` | Native ivory/coral pause actions; resume/retry kept | Paused game world substitutes for concept's authored avalanche scene |
| Waddle Run results | `runner_results_v1.png` | Live results/retry on ivory/coral material | Header composition and reward illustration still differ |
| Waddle Race setup | `race_mode_select_v1.png` | New finish-arch backdrop, icy/gold wordmark, four ivory/coral mode cards; course/difficulty remain live | Course/difficulty art not migrated; hidden from MVP home |
| Waddle Race pause | `race_pause_v1.png` | Ivory/coral control card, existing live actions and quick audio | No full-screen authored penguin illustration; hidden from MVP home |
| Waddle Race results | `race_results_v1.png` | New finish backdrop, wordmark, ivory standings, full-width coral retry and exits on phones, live rows | Dynamic podium art and rank plinth still differ; hidden from MVP home |

No generated concept bitmap is used as a whole UI. Runtime backgrounds, title
art and icons are separate from native buttons/labels/scrolling and live data.
The requested full-body species atlas was not accepted: generation produced
only seven characters and an opaque background; keep the proven differentiated
portraits until a complete sheet can be authored and reviewed.
One individual full-body variant was also rejected because its claimed
transparent output retained a dark studio background and did not preserve the
established Emperor design closely enough. No rejected image enters runtime.
