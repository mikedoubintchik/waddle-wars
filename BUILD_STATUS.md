# Waddle Wars — Build Status

Last updated: 2026-08-05 (prod-readiness round).
This file records verified reality with evidence, not intentions.

## Overall status: SHIPPING — playable and deployed, with a short known-issues list

The game is feature-complete against GAME_SPEC and deployed as a web build at
https://mikedoubintchik.github.io/waddle-wars/ (gl_compatibility, no-threads
WASM, GitHub Pages) plus desktop exports. "COMPLETE" was previously overstated:
QA_FINDINGS.md items were open. As of the 2026-08-05 prod round, 14 of those
are FIXED/PARTIAL with evidence (see QA_FINDINGS.md); still OPEN: #5 silent
glacier fallback, #8 endless/tutorial finish-flow mismatch, #13 get_setting
defaults alloc, #17 GP mutation inside results UI, and the non-racer half
of #11 (course_base/path_guide per-frame dicts). Known limitations: no
localization keys (English-only), no confirmation dialogs except GP-abandon
(two-press confirm in pause menu).

Full automated suite: **ALL PASSED** (`./run_tests.sh`, exit 0, 2026-07-21 03:01):
unit_tests (49/49), menu_load_test, race_sim glacier/aurora/iceberg,
time_trial ghost, endless_sim, tutorial_sim, grand_prix_sim.
Difficulty coverage: chill + emperor race sims PASS.
Desktop exports built and boot-tested. Screenshot review at 4 resolutions.

## Acceptance criteria (GAME_SPEC §23)

- [x] Opens in Godot 4.7.1 without missing-resource errors — headless import + boot clean.
- [x] Title screen polished + animated — live 3D diorama (penguins, snow, camera sway, rocking logo); screenshot reviewed.
- [x] Every main-menu button works — Play/Waddle School/Customize/Achievements/Settings/Credits/Quit all route (menu-load unit tests + code paths).
- [x] First-time player can complete Waddle School — tutorial_sim PASS end-to-end incl. achievement grant; prompts show live keybinds.
- [x] Quick Race fully playable — race sims all courses; countdown/HUD/results screenshots.
- [x] Grand Prix fully playable — gp_sim: 3 rounds, 117 pts distributed, sorted standings, podium ceremony, records saved.
- [x] Endless Expedition fully playable — endless_sim PASS; storm chase, score, high-score save.
- [x] Time Trial + local ghost — record on first run, replay on second (both PASS); per-course best times saved.
- [x] Three complete visually distinct courses — bright Glacier Gauntlet / twilight Aurora Ascent / sunset Iceberg Bay (screenshots).
- [x] 1 player + 7 AI complete every course — 8/8 finish, 0 DNF on all three (multiple sims).
- [x] Jumping, sliding, swimming, shoving, items, pickups, hazards, checkpoints, recovery — exercised in sims; unit tests for powerups/racer.
- [x] ≥5 power-ups — snowball, shield, fish frenzy, magnet, blizzard (all activate; unit-tested).
- [x] ≥7 hazard types — rolling snowballs, falling icicles, cracking ice, wind zones, geysers, sliding seals, moving/tilting platforms, low ice tunnels (8).
- [x] Keyboard controls — full input map + remapping.
- [x] Gamepad controls + menu focus — bindings incl. sticks/triggers, focus chains + visible focus styles (no hardware present for live test; code + focus screenshots).
- [x] Touch controls exist and usable — steer zone + 5 buttons, scale/opacity settings, auto/on/off; instantiation unit-tested.
- [x] Race HUD complete — position, count, progress, item, fish, speed, time, checkpoints, endless score/storm.
- [x] Pause and resume — screenshot; also auto-pause on focus loss + controller disconnect.
- [x] Results and rewards screens — standings, fish/XP rewards, GP standings + cup podium.
- [x] Progression persists — save round-trip + corruption-recovery unit tests.
- [x] Cosmetics unlock/equip/preview/save — customize screen with rotating 3D preview; unit-tested unlock/equip; trails render in-race.
- [x] ≥12 cosmetics — 16 (4 bodies, 4 hats, 3 neckwear, 2 eyewear, 3 trails).
- [x] ≥12 achievements — 14, with toast notifications.
- [x] Audio settings work — volumes/mute/mute-unfocused applied immediately + persisted.
- [x] Display + gameplay settings work — window mode, resolution, vsync, quality/shadows/particles, MSAA, FPS cap, sensitivity, vibration, slide mode, touch options.
- [x] Accessibility options work — camera shake tiers, high-contrast pickups, reduced flashing, colorblind-safe redundant cues, HUD/UI scale, disconnect pause, audio-event captions.
- [x] Interface scales desktop + wide mobile — screenshots at 1920×1080, 1280×720, 2560×1440, 2400×1080.
- [x] Original music and SFX — 28 synthesized WAVs (3 seamless music loops + 25 SFX), generator in tools/.
- [x] Original logo and icon — assets/icons/icon.svg + wordmark title.
- [x] No required features as TODOs/stubs — grep clean.
- [x] Automated tests pass — 9/9 suite groups.
- [x] Runtime logs free of repeated errors — windowed run audit clean.
- [x] README explains run/test/export — yes, incl. per-platform steps.
- [x] BUILD_STATUS reflects the completed project — this file.

## Export status

- Web (primary): `build/web/` deployed to GitHub Pages via orphan gh-pages
  branch — iOS audio unlock, Clerk sign-in (optional), OG/twitter share meta,
  share.png card, IndexedDB saves. Online leaderboard: Cloudflare Worker + D1
  (leaderboard/, deployed at waddle-wars-leaderboard.ninjaconsultingllc.workers.dev).
- Windows Desktop: `build/waddle-wars-windows.exe` (115MB, embedded PCK) — built.
- macOS: `build/waddle-wars-macos.zip` (65MB) — built; exported app boot-tested (exit 0). Unsigned (no Developer ID on machine).
- Linux: `build/waddle-wars-linux.x86_64` (79MB) — built.
- Android: preset configured; requires local SDK + keystore (documented in README).
- iOS: requires Xcode + certificates (documented in README).

## Known non-critical limitations

- Trail cosmetics don't show in the customize preview panel (render in-race).
- Music stored as OGG, written directly by tools/generate_audio.py (~1.9MB for
  five tracks). The generator used to leave a WAV beside each OGG, which was a
  real hazard: AudioManager keys its library on basename, so whichever file the
  directory listed first won and a regenerate could silently swap the game onto
  a 4MB WAV. Fixed -- the intermediate WAV is deleted after encoding.
- Race pace: autopilot finishes ~1.7–3.4 min depending on course/difficulty; human first-timers land in the 2–4 min spec window via hazards/recoveries.

## Supervisor final validation (post-cutoff, 2026-07-24)

Independent supervisor session. Reset deadline (2026-07-21T06:59:53-04:00) has
passed; builder session ended at its provider token limit after commit 649711c.
Final state validated on the working tree:

- `godot --headless --import .` → clean, zero parse/script errors.
- `godot --headless tests/race_sim.tscn` → PASS course=glacier; earlier runs
  PASS on aurora + iceberg; 8/8 racers finish.
- Power-ups proven live: instrumented sim showed 10 activations
  (snowball/shield/magnet/blizzard) — earlier they were dead code.
- QA_FINDINGS.md: 4 FIXED with evidence (powerup consumer, item-box spawns,
  touch-controls null wire-up, AI branch-hint space), **14 OPEN** remaining
  (rubberband granularity, focus-loss pause soft-lock, silent course fallback,
  uphill slide floor, save-merge typing, per-frame allocs, misc low). The
  "full acceptance checklist verified complete" claim above is optimistic:
  treat QA_FINDINGS.md OPEN items as the real remaining work.
- This checkpoint also lands an uncommitted trail-preview addition to the
  customize screen (resolves the prior "trails not in customize preview" note).

## Development history

See git log — checkpoint commits from skeleton → core slice → hazards →
courses → modes → UI/audio integration → test suite → polish → exports →
supervisor QA + fixes.

## Prod-readiness round (2026-08-05)

Scope: animated boost-pad arrows; 9-agent production audit (67 raw findings,
synthesized+verified) followed by a 6-agent fix round; optional online
leaderboard (Clerk + Cloudflare Worker + D1); per-course music variants.

Fixed this round (see QA_FINDINGS.md for per-item evidence): web Quit freeze
(blocker), pause/focus soft-lock during scene fades, Endless touch dead-wire
regression, Time Trial item boxes (now suppressed), mobile-web quality profile
(.web overrides + first-run medium defaults), OG/twitter share meta + share
image, keyboard onboarding strip during countdown, touch pause/item-slot
overlap, README front door rewrite, GP tiebreak, save-merge typing,
rubberband continuous metres, uphill slide floor, racer ray-query caching,
pickup Area3D static colliders, swim stroke sfx, wind/snowball hazard audio,
squash single-decay, countdown final-beep pitch, joypad button names, WAV
loop_end format-aware, tests/* excluded from exports, endless storm hint,
iceberg platform-crossing resonance (pad 70m upstream + randomized respawn
stumble).

Validation evidence (2026-08-05): headless import 0 script errors; units
50/50 (incl. new leaderboard menu-load); race sims PASS glacier/aurora;
endless_sim, gp_sim, tutorial_sim PASS; iceberg pre-fix flake measured 3/6
TIMEOUT at baseline b0a5c19 (autopilot resonance, pre-existing); post-fix:
7/8 after pad-move + respawn stumble, then 10/10 PASS after adding the AI
progress watchdog (respawn when <6m course progress in 12s); boost-arrow direction verified via tests/pad_shot.tscn
top-down captures; leaderboard Worker endpoints smoke-tested (health,
empty board, 401 on missing/garbage token).

## Fidelity + playtest-fix round (2026-08-06)

Scope: 7-agent "100x realism" fidelity pass (seals rebuilt as realistic
lathe-body animals with wet-skin shader + whiskers; penguin feather/
iridescence/bill/eye detail; snow/ice/boost/water/aurora shader upgrades;
all hazards; pickups incl. 3-ball snowball stacks + item-box glints; course
dressing: glacier boulders/cave glints, aurora starfield/crystals, iceberg
floes/hero bergs). Plus playtest fixes: two-press fish-purchase confirm;
instant boost on pad entry; causeway tilt intensified (9→13°, 15° reverted
after Marina DNF); accessibility pass (high_contrast_pickups now covers
pads/platforms/hazards/item boxes, shape+brightness cues); vanity domain
waddlewars.ninjaconsulting.ai (DNS CNAME + Pages custom domain + HTTPS +
301 from github.io); race-pause Mute All toggle; touch shove/steer hint
strip during countdown; gamer-name entry in leaderboard (POST /api/profile,
sanitized 2-20 chars); main-menu sign-in chip + cloud save sync (pristine
local adopts cloud, else local pushes; debounced 8s); web leaderboard
transport replaced with __ww_api page-fetch bridge (Godot web HTTPRequest
unreliable on phone); Clerk lazy-load + dpr cap 2 (phone perf); global +
per-course exposure/warmth grade (overexposure fix); iceberg violet blob
artifact fixed via _flat_lit_snow() per-course material (snow normal-map
self-shadowing under -13° sun).

Validation evidence (2026-08-06): headless import 0 script errors; units
50/50; race sims PASS glacier/aurora/iceberg×2 (13° tilt battery also 3/3);
endless_sim, gp_sim, tutorial_sim PASS. Visual QA via qa_shots/fidelity/
series (v8-glacier, v10-iceberg clean of blob artifacts, aurora/seal/penguin
close-ups). Known-open: leaderboard/sign-in bridge rewrite not yet
re-verified on user's phone; Clerk keys are TEST instance (swap before
serious traffic); LICENSE choice pending user.

## Mega round 2 (2026-08-06, second session)

Bug fixes (verified in Chrome on the live site): menu pixelation root-caused
to SubViewport logical-res rendering — UITheme.crisp_subviewport() now
supersamples title/customize/results by the real canvas scale; SceneRouter
"Loading…" overlay held until 3 frames post-draw (was: seconds of raw sky
during WebGL shader compile after the studio splash); race-HUD control strip
holds 8s after GO (was 2s — players missed it); leaderboard + sign-in
confirmed WORKING live (stale 10-min GitHub Pages cache explains the phone
failure; no service worker). tools/deploy_web.sh added (later deleted — see
"Hosting moved off GitHub Pages" below).

Feature passes (8 parallel agents across two workflow runs, disjoint file
ownership): (1) PHYSICS — apex-hang/fast-fall jump arc, surface-scaled slide
grip, low-speed steering assist, wall glancing instead of sticking,
mass-weighted racer bumps, velocity-based shove knock (no teleport), moving-
platform carry (player-only, see below), ease-out boost decay, speed-reactive
trails. (2) PERF — ~45-60 unique materials per course build collapsed to ~12
cached instances (WebGL first-sight compile hitches were the browser
freezes), shared meshes, quality-tier dressing culling + shadow scaling,
web-only FPS governor (avg <22 over 8s → one-tier step-down, never
persisted). (3) SHARING — ShareManager (navigator.share + clipboard
fallback), Share on results, Challenge Friends on leaderboard. (4) BEAUTY —
title diorama ambient life (diver penguin, whale spout, shooting stars, water
glints, floe bob), hover glow/header rules/refined backdrop across all menus.
(5) MINIMAP — course-ribbon card with live dots, wired into race HUD.
(6) ITEMS — snowball fuzz/trail/impact splat, pickup wobble/flecks, fish fin
flutter + droplet burst, item-box prize glow. (7) WADDLE SCHOOL — lesson
cards with live keycap hints, per-station chime + sparkle, gold graduation
confetti, dressed course. (8) OFF-COURSE — glacier icefall + bird flocks,
aurora starfield/spires/fifth veil, iceberg breaching whale + drifting pack
ice, endless per-biome horizon bands, water sparkle pinpoints.

Physics regression handled: iceberg sim flaked 1/9 (triple AI DNF at the
platform crossing) after the physics pass; fixed by making platform carry
player-only and halving AI-vs-AI bump impulses (AI target selection doesn't
model inherited drift). Post-fix battery results in TESTING.md.

## Round 3 (2026-08-06, playtest batch 3)

Shipped (commit 0026ca2): AI difficulty buff (competitive/emperor) plus
pace-projected finish times replacing mass DNF — a janky low-FPS browser run
can no longer wipe the field; new frozen `tutorial_demo` AI profile for the
Waddle School autopilot; control strip holds 30s and the full control
reference now also appears in the pause menu; Course/Boost progress-bar
labels; "Finish Race" button once the player is done while AI still race;
menu touch-scaling system so phone menus fill the screen; Settings redesigned
into sections with visible values and per-section reset; Ninja Consulting
credit link; water shader realism (multi-octave normals, fresnel sky
reflection, crest foam).

Deploy note: gh-pages was recreated as a single orphan commit — repeated
"Page build failed" errors were tied to the accumulated branch history.

Held back (see wip/README.md + wip/round3-heldback.patch): ultra-physics
contact pass, compound hazard motion, dressing grounding, Chrome shader
warm-up. Each regressed the sim suite; rework individually with its own
battery.

Root causes found this round (both pre-existing in the part-2 build, which
never reached players because its Pages deploy failed): (1) the physics
contact pass made racers grind along low hurdle bars instead of hopping —
jump hints stop being returned once progress passes them, so a stalled racer
never re-triggers a jump; (2) the buffed competitive profile, reused by the
tutorial autopilot, overshot the lesson obstacles.

Validation (2026-08-06): units 50/50; race sims PASS on all nine
course x difficulty combinations; endless, GP, tutorial (3/3) PASS.

## Round 4 (2026-08-06, rework of the held-back work)

All four held-back items reworked and landed after isolating what actually
broke the sim suite. Bisect method: parallel git worktrees, one subsystem
disabled per worktree, tutorial_sim + race_sim run side by side.

- **Physics** (commit 9937e1c) — the culprit was the low-speed steering
  assist (1.45x yaw response below base speed), which over-steered
  guide-following racers into a wall-hugging oscillation and deadlocked the
  tutorial autopilot. It was NOT the contact system, the first suspect.
  Removed the assist; landed the rest: apex-hang + fast-fall jump arc,
  impact-scaled landing squash, surface-scaled slide grip, wall glancing
  gated to contacts above jump-clearing height (low hurdles must be hopped,
  not ground along), mass-weighted racer bumps at half impulse between AI,
  damped AI platform carry, ease-out boost decay, speed-reactive trails.
- **Hazard motion** (commit 9937e1c) — the upgraded platform code passes
  with the original values; the aggressive lurch/yaw config was what AI
  could not cross. Ships gentle heave + slow yaw + seeded per-platform
  variance plus telegraph edge strips that flash before a reversal.
- **Dressing grounding** and **Chrome shader warm-up** (commit 93a749f) —
  both passed in isolation and together, landed unchanged.

Also this round: dancing-penguin loading indicators everywhere (in-game
scene transitions, leaderboard fetch, and a matching CSS splash on the web
boot screen before WASM starts), and one-finger slide steering on touch — a
finger holding a belly slide now also steers, where gesture classification
used to hand steering to a second finger.

Validation (2026-08-06): units 50/50; tutorial_sim 3/3 PASS; race_sim PASS
on all nine course x difficulty combinations; endless_sim and gp_sim PASS.

## Deploy incident (2026-08-06, GitHub-side)

Live publishing broke mid-session and is NOT a code problem. Symptoms, in
order: the legacy Pages branch builder returned "Page build failed" with no
detail on every push once the payload carried the ~40MB WASM blob;
`workflow_dispatch` returned HTTP 500 twice; and the Actions publish path
failed with `Invalid actions OIDC token due to No keys from key endpoint
match the id token` — GitHub's own OIDC key endpoint rejecting a token it had
just issued.

Result: https://waddlewars.ninjaconsulting.ai/ is serving the 14:48 UTC build
(round 3). Everything after that — physics rework, hazard motion, dressing
grounding, Chrome shader warm-up, dancing-penguin loaders, touch slide
steering, M-mute, drawn item icons, minimap rivals — is committed on main and
staged on the gh-pages branch, waiting only on a successful publish.

### Correction (2026-08-06, later): the push failures were ours

The Pages *build* failures above were real and GitHub-side. The `git push`
rejections were not. Every push was refused for its own reason:

    remote: error: File leaderboard/node_modules/@cloudflare/workerd-darwin-arm64/bin/workerd
    is 109.26 MB; this exceeds GitHub's file size limit of 100.00 MB
    remote: error: GH001: Large files detected.

The Cloudflare deploy path commit carried 1558 node_modules files with it,
including that binary. "pre-receive hook declined" during an active outage
read as more of the same outage; it was not, and it would have kept failing
after the outage cleared. Fixed by untracking node_modules (reproducible with
npm install, now in .gitignore) and running `git filter-repo --invert-paths
--path leaderboard/node_modules` over the ten unpushed commits. The remote was
still at a1a5014, so no published history was rewritten.

`.github/workflows/deploy-pages.yml` (dispatch-triggered, fired by
tools/deploy_web.sh) publishes the gh-pages contents through the Pages
artifact API. Switch `build_type` between "workflow" and "legacy" with
`gh api -X PUT repos/mikedoubintchik/waddle-wars/pages` depending on which
path is healthy; re-run the deploy once GitHub recovers and verify with the
index.pck md5 comparison in tools/deploy_web.sh.


## Boot cost: measured, and a correction to the Chrome diagnosis (2026-08-06)

Added `scripts/utilities/boot_profiler.gd` (enable with `?profile=1` on web or
`-- profile` on desktop) to separate CPU scene construction from GPU first-draw
cost. Numbers from the title screen, `--rendering-driver opengl3`:

| Condition                          | BUILD (cpu) | FIRST DRAWS (3 frames) |
|------------------------------------|-------------|------------------------|
| Cold GPU pipeline cache            | 49.8 ms     | 3566.7 ms              |
| Same diorama rebuilt in-process    | 3.7 ms      | 197.3 ms               |

So construction was never the problem: it is first-sight shader program
linking, and re-linking is what costs. This also corrects the earlier reading
of "the splash hangs": nothing hangs. `change_scene_to_file()` is synchronous,
so the splash is simply the last frame presented before the title's first draw
blocks the main thread — which is why no loading overlay could ever show
through it.

`scripts/utilities/boot_warmup.gd` spends the splash's otherwise idle hold
linking those programs two per frame into a small offscreen viewport that
mirrors the title's feature set (sky, fog, glow, ACES, shadowed sun, matching
MSAA — sample count is part of the pipeline key). It covers every VisualLibrary
factory, every track surface, ShaderWarmup's synthetic feature probes and one
live PenguinVisual: 28 programs. The splash now holds until the pass drains
(min 2.4 s, cap 9 s) instead of a fixed 2.4 s; a tap still skips.

### Chrome measurements in this session are INVALID

Every in-browser observation taken here — including the earlier A/B that
concluded "the old build hangs identically, so the hang is pre-existing" — was
made through a Chrome tab reporting `document.visibilityState === "hidden"`.
Chrome stops driving `requestAnimationFrame` in hidden tabs and Godot's main
loop rides on rAF, so the engine was barely stepping. Proof: a script asking
for 3 seconds of rAF frames never completed inside a 45 s CDP timeout, and the
splash tween advanced roughly one second per twenty seconds of wall clock.

The MCP browser tooling could not produce a foreground tab (creating and
navigating a tab still left it hidden, and the Chrome grant is read-only), so
**the user-reported "unplayable in Chrome" issue is neither reproduced nor
disproved here.** Chrome is confirmed hardware-accelerated on this machine
(`ANGLE (Apple, ANGLE Metal Renderer: Apple M2)`), so a SwiftShader fallback is
ruled out. The warm-up above is justified on its own measured evidence; whether
it resolves the Chrome report needs a human with a focused Chrome window.

Ruled out while investigating: `UITheme.crisp_subviewport()` does not
double-count device pixel ratio (it targets `win.size / logical`, clamped 1..2,
which lands on the real backbuffer — 2940x1984 at dpr 2 on this display).

## Hosting moved off GitHub Pages to a Cloudflare Worker (2026-08-06)

`waddlewars.ninjaconsulting.ai` is now served by the `waddle-wars-web` Worker
out of R2, not GitHub Pages. Everything above about Pages build failures,
`build_type` switching and `tools/deploy_web.sh` is history — that script and
`web/CNAME` are deleted, and the only deploy path is:

    tools/deploy_cloudflare.sh

Why the move: Pages was in a multi-hour major outage (incident opened
2026-08-06T15:22Z, still investigating at 20:40Z) and a queued build sat in
`building` indefinitely, so there was no way to publish. The Worker was already
serving the current build, and it is the better host regardless — GitHub Pages
cannot send `Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy` at
all, and Cloudflare Pages rejects the ~38 MB WASM against its 25 MB per-file
ceiling.

What changed, in order:
1. Backed up and deleted the zone's `CNAME waddlewars -> mikedoubintchik.github.io`
   (backup JSON kept in the session scratchpad).
2. Bound the hostname to the Worker via the Workers Custom Domains API, which
   creates its own proxied record and certificate.
3. Verified the domain serves the current build: `index.pck` md5 matches the
   local export, `cross-origin-opener-policy: same-origin`,
   `cross-origin-embedder-policy: require-corp`, `.wasm` as `application/wasm`.
4. Cleared the Pages custom domain (`cname: null`) and deleted the `gh-pages`
   branch. The Pages *site* could not be deleted — the API returns 422
   "Deactivating GitHub pages for this repository is not allowed" — but with no
   custom domain and no source branch it has nothing to serve.

The canonical URL did not change, so `ShareManager.SHARE_URL`, the OG/Twitter
meta in `export_presets.cfg` and every shared link still resolve correctly.

## 2026-08-07 — Reactive defect round, then a graphics/physics pass

### Root causes found (each explained several reported symptoms)

**Every SFX broken; endless whooshing.** `racer.gd` set `loop_mode =
LOOP_FORWARD` on the *shared* `sfx_slide` resource so the belly scrape could
loop. `AudioManager.get_stream()` returns one shared resource per key, so every
one-shot use of that sound — the wind zone fired one every 2.6 s — looped
forever, and a looping stream in a one-shot pool player never frees it. Within
a minute the pool was a chorus of stuck loops. Fixed at both ends: the racer
duplicates before looping, and the one-shot pools now take guaranteed
non-looping copies (`AudioManager._one_shot_stream`), so no future caller can
reintroduce it.

**"Buttons are cut off."** `UITheme.apply_ui_scale` multiplied each screen
root's *transform* by the accessibility `ui_scale`, on top of
`SettingsManager._apply_ui_scale` already implementing it correctly by
shrinking `content_scale_size`. The design-size route reflows; a Control
transform cannot, it only magnifies about the pivot. At `ui_scale` 1.5 the
layout was fitted to a 1280x720 canvas and then blown up 1.4x, pushing ~40% of
every screen off the display — worse the more the player needed it. Reproduced
at 1064x676 (`qa_shots/ui/customize_scale.png`), fixed, re-verified on
customize/settings/results/main menu.

**Arrows, stars and emoji rendered as hex boxes.** `ThemeDB.fallback_font`
carries none of U+2190..2194, U+25B2/BC/C4/BA, U+2605 or any emoji, and a web
export has no OS font fallback. Added `UITheme.arrow_texture/arrow_icon` and
removed every typed symbol from in-engine strings. `share_manager` keeps its
emoji — that text is rendered by the destination platform, not by Godot.

**"Partially rendered acceleration pads."** Regression from the corner banking
added the previous round: the ribbon banks, `guide.transform_at()` does not,
and pads mounted on the unbanked frame sat crooked in the deck. Added
`TrackBuilder.deck_transform_at()`.

**Loading freeze.** Measured rather than guessed: course construction is
30-65 ms headless across all five courses. The cost is GL program linking,
which ANGLE charges in milliseconds. `ShaderWarmup` already spread that per
frame but the overlay lifted after a fixed 3 frames, dumping the stall into the
first seconds of play. The overlay now waits for the warmup (capped at 180
frames).

### Content and quality
- Two new courses: **Cinder Coast** (`cinder`) and **Sapphire Hollow**
  (`hollow`), with their own poster art and sky gradients. Roster is 5.
- Leaderboard tabs now derive from `CoursesDB.ORDER` — the hand-written list
  had left both new courses with no board.
- Procedural **polar bears** on glacier. Placement is *searched*, not authored:
  candidate sites must have ground under all four paws and a clear sightline
  from the racing line. All five hand-picked sites failed both tests.
- **Racer reads as a bird at distance**: mantle break baked into vertex colour,
  dual-polarity edge (ink line for bright courses, emissive rim for dark),
  per-racer identity tint. New `assets/shaders/penguin.gdshader`.
- **Racer conforms to the surface** and shifts weight under acceleration; it
  had been staying level on banked corners.
- Shield power-up rebuilt as a fresnel shell — it had been an unshaded 30%
  alpha sphere that erased the character wearing it.
- Snow drifts have collision and plough (`SnowDriftField`); wind zones rebuilt
  as gated course furniture; icicle mesh and shader rebuilt.

### Known open
- Loader still cannot animate through a genuinely blocking frame; the fix
  removes the stall from gameplay, it does not make the block interruptible.
- Glacier compresses the racer's mantle break more than aurora does; past ~20 m
  identity is carried by hats rather than plumage.
- `RESET_AT.txt` reads 2026-07-21, long elapsed. Deadline behaviour is not
  being enforced.
