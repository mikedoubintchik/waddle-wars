# Waddle Wars menu rethink — ImageGen concept v1

Generated with the built-in ImageGen tool. These are visual targets, not runtime UI. Rebuild text, buttons, focus states, safe-area behavior, and accessibility in Godot; do not use the mockup as a single tappable bitmap.

## Portrait prompt

```text
Use case: ui-mockup
Asset type: premium mobile game main-menu design concept, portrait 9:16 phone screen
Primary request: Completely redesign the Waddle Wars main menu for a polished penguin adventure game. This must look like a believable shippable game interface, not loose concept art. The only primary mode at launch is the endless avalanche-chase runner.
Scene/backdrop: a richly art-directed Antarctic expedition route at sunrise. A playful, expressive, high-quality 3D animated-film penguin in an orange scarf runs toward the viewer on a sculpted blue-ice trail; a huge rolling avalanche is clearly visible in the distance behind the penguin. Expedition outpost and mountains are small atmospheric landmarks, not the main focus. Dynamic snow spray and warm low sun add depth. Show enough ice path to explain the gameplay, but let the hero dominate.
Style/medium: premium original stylized 3D game render with polished, tactile UI composited over it. Rounded handcrafted silhouettes, subtle painted texture, cinematic lighting, carefully controlled contrast; sophisticated and joyful, never generic clip art.
Composition/framing: full-bleed vertical screen. Top 20% contains a prominent custom illustrated title mark, WADDLE WARS, with clean safe-area margins. Middle 50% gives the penguin and avalanche room to breathe. Bottom 30% contains a single very large, unmistakable coral-red pill-shaped primary action labeled 'WADDLE RUN' with a small running-penguin icon and a right arrow. Below that, a slim ivory navigation shelf with three generously spaced illustrated icons and labels: 'PENGUINS', 'MISSIONS', 'MORE'. Small but legible fish balance and profile control at top corners. All controls appear physically tappable, with consistent spacing and no squashed rows. The game art stays visible behind the UI.
Color palette: glacial blue and snowy ivory, warm sunrise peach, tiny coral-red accent for primary action, deep ink navy for readable type. Distinct from a dark navy glass dashboard.
Text (verbatim): 'WADDLE WARS', 'WADDLE RUN', 'PENGUINS', 'MISSIONS', 'MORE'. No other words or numbers.
Constraints: original characters and original interface; true functional-looking game menu; clear visual hierarchy; large legible type; credible touch targets and safe areas; no multi-column card grid; no translucent black panels; no tiny gray copy; no rectangular outline around primary button; no race button; no copied franchise design; no watermark; no device frame.
```

## Landscape prompt

Reference: portrait concept above, used as a visual style and character reference, not an edit target.

```text
Use case: ui-mockup
Asset type: landscape 16:9 adaptation of the same premium Waddle Wars game main-menu concept in Image 1. Image 1 is a visual style and character reference, not an edit target. Create a NEW wide composition rather than stretching or cropping the portrait menu.
Primary request: preserve the original high-quality penguin design, fluffy snow avalanche, glacial-blue ice, warm sunrise, tactile off-white navigation, and coral primary action from Image 1. Make a believable shippable landscape game interface.
Composition/framing: full-bleed 16:9 screen. The penguin running toward camera, snow spray, trail and looming avalanche dominate the left two-thirds; penguin stays fully visible and avalanche remains legible. On the right third, a very clear large 'WADDLE WARS' title near upper right, a large coral 'WADDLE RUN' action beneath it, and a low-profile ivory three-item navigation row near bottom right. Small fish and profile controls at top corners within safe margins. Airy, balanced, physically tappable layout; never a vertical stretch of the portrait art. Expedition outpost and mountain silhouettes far behind. No menu items overlap penguin's face or action.
Style/medium: original premium 3D animated-film game art, handcrafted rounded shapes, painted texture, controlled cinematic lighting, substantial environmental depth; polished game UI, not loose concept art.
Text (verbatim): 'WADDLE WARS', 'WADDLE RUN', 'PENGUINS', 'MISSIONS', 'MORE'. No other text or numbers.
Constraints: original IP, strong contrast and legibility, functional-looking controls, no multi-column cards, no dark glass dashboard, no tiny gray copy, no race button, no copied franchise design, no watermark, no device frame.
```

## Implementation direction

- Full-bleed artwork, original rounded penguin, avalanche visible immediately.
- One bright coral Run action. No secondary game-mode tile on MVP home.
- Three destinations: Penguins, Missions, More. More opens utility screens; not a second grid on the home screen.
- Art is atmosphere, not the hit target. Implement every control with native Godot nodes and accessible names, focus/hover/pressed states, safe-area constraints, and responsive portrait/landscape compositions.
- Export a separate clean background and UI art elements before integration. Do not ship the full mockup bitmap as the interface or introduce a large texture upload during gameplay.
