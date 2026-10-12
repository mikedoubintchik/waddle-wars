# Account footer removal — built-in ImageGen

Use case: precise-object-edit. Edit target: the attached existing Waddle Wars ACCOUNT screen reference. Make exactly one local edit: remove the bottom footer phrase "Play without an account" and its two short horizontal divider lines. Inpaint that small footer area using the surrounding snow/background so the footer is completely absent. Preserve every other pixel-level design decision as closely as possible: exact framing and orientation, penguin characters and poses, ACCOUNT heading, Back button, guest card with avatar and all its existing words, coral sign-in button and icon, journal/stat panel including any existing numbers, Privacy & Data heading, privacy and delete rows, all borders/shadows/colors/type sizes/spacing. Do not enlarge, move, redesign or remove any card or character. Do not add text or controls. Keep original canvas proportions and fully opaque background. This is a revised reference illustration, not a game screenshot.

Two independent built-in `image_gen` edit calls, transparent_background=false:

- Desktop input: `art_src/ui/menu/reference_iteration_v3/account_desktop_v2.png`
- Portrait input: `art_src/ui/menu/account_v1.png`

Reviewed output: footer text and rules removed; surrounding snow restored. Main illustration, labels, card layout and orientation retained visually. Generated reference revisions; no screenshot pixels edited.
