# Desktop refresh / loading and results — 2026-10-07

Generated with built-in ImageGen; model/build/seed not exposed. All input images
are project-owned menu art, used as style references or exact extraction targets.
Raw PNGs preserved alongside compressed runtime WebP siblings. Not whole-bitmap
menus: runtime text, prices, scores, state and progress remain real controls.

## Reference briefs

- `base_camp_desktop_v2.png`: shippable 16:9 desktop BASE CAMP. Match
  `base_camp_v1.png` material style, penguin identity, palette and typography.
  Wide warm timber cabin, Antarctic window and scarf penguin left. Snow-capped
  hanging BASE CAMP sign top; ivory blue-arrow Back left, fish 492 right.
  Right 48%: Guest Explorer/sign-in strip plus five evenly spaced tall ivory
  sculpted-icon pill rows: LEADERBOARD, ACHIEVEMENTS, SHOP, SETTINGS, CREDITS.
  Readable navy display text, comfortable margins, no clipped controls, extra
  entries, browser chrome or watermark.
- `leaderboard_desktop_v2.png`: 16:9 desktop layout matching
  `leaderboard_v1.png`. Full-width consistent top header; left 42% three cheerful
  penguins on ice podium in Antarctic plaza. No baked names on podium. Right
  broad ivory score sheet, five spacious sample score rows with avatars, names
  and stars; coral own-score row; large CHALLENGE FRIENDS pill. No stretched
  portrait, browser chrome, clipping or watermark. Sample users are reference
  only, never injected into the live board.
- `runner_results_desktop_v2.png`: match `runner_results_v1.png`. 16:9 sunset
  Antarctic scene; RUN COMPLETE icy/gold title and cheerful scarf penguin in
  powder left. Right ivory journal with dominant SCORE 1,038; equal BEST 6,692,
  DISTANCE 363 m, FISH 27 tiles; two completed mission chips. Large coral RUN
  AGAIN and ivory BASE CAMP pills. No yellow focus rectangle, plain Run Over,
  dense uppercase paragraphs, clipping or browser chrome.
- `loader_theme_v2.png`: 16:9 loading reference matching `base_camp_v1.png`.
  Defocused expedition basecamp, compact ivory snow-edged card, running scarf
  penguin, carved WADDLE WARS sign, one continuous coral progress bar at 65% in
  sculpted pale-blue track, message “Packing extra fish…”. No black card,
  percentage, technical labels, duplicate bar, marquee, menus or watermark.

## Runtime background extraction prompt (each desktop reference independently)

Use case: precise-object-edit. Edit supplied desktop Waddle Wars reference into
its RUNTIME BACKGROUND, 16:9. Preserve exact environment, camera, colors, light,
high-fidelity penguin character(s), and left-side art positions. Remove every UI
element: all headings/wordmarks, Back button, fish balance, profile strip, menu
cards, score/list sheets, stats, mission chips, action buttons, usernames and
labels. Replace removed areas with natural continuation of the same scene.
RIGHT half deliberately quiet and unobstructed for live runtime UI. Preserve
decorative ice podium numbers on leaderboard only, but no players' names. No
added text, menus or watermark; no new composition or different penguin.

## RUN COMPLETE extraction prompt

Use case: background-extraction. Extract ONLY the top RUN COMPLETE wordmark from
`runner_results_v1.png` as a high-resolution game UI asset on a genuinely
transparent background. Preserve exact rounded chunky ice-blue RUN lettering,
golden orange COMPLETE lettering, dark blue rocky extrusion, scattered little
ice crystals and white snow edge. Two lines. No penguin, scenery, panels, buttons
or extra words. Tight clean transparent padding around entire sign; no opaque
rectangle, no new design.
