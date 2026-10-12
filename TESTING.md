# Waddle Wars — Testing

## Runner action sounds and browser focus mute — 2026-10-08 EDT

Runner jump/slide now use the existing distinct hop/snow-scrape sounds, once per
accepted state entry, prewarmed with the runner and routed through Effects.
Browser blur/visibility now feeds AudioManager directly; Master mute combines
explicit mute, zero volume and the unfocused preference, preserving all saved
sound levels when focus returns. The accepted iOS keepalive fix is unchanged.

Focused checks: browser focus7, keepalive14, real action/bus rules26,
runner audio warmup71, existing shell104 = **222 passed**; eleven inline scripts
parse. Final stderr empty. Runtime checks were silent Dummy audio with isolated
saves; initial stale-class-cache attempt is retained as failed. Actual Chrome
integration/audible playback remains a separate coordinated gate.

Commands: `./run_tests.sh audio_focus`, `./run_tests.sh runner_audio_warmup`,
`node --test tests/web_audio_keepalive.test.mjs`,
`node tools/test_web_shell_behaviour.mjs`, `python3 tools/check_web_shell.py`.
Receipt and browser steps: `qa_shots/tests/audio-focus-runner-20261008/README.md`.

## Chrome zero-frame audio loop correction — 2026-10-07 EDT

The production iOS audio workaround accidentally ran on desktop and looped a
44-byte WAV containing zero audio frames. A minimal real-Chrome control on the
same muted origin, without Godot or DevTools, produced **3,328,601 media events
in 30 seconds**. Replacing only the source with valid one-second silence produced
**300 events**. Browser/renderer CPU was **116.15%/142.73%** during the zero-frame
trial and **2.59%/3.56%** during the valid control; removing the source stopped the
storm. This establishes an event/CPU defect, not a complete explanation or fix
for the separately observed multi-GiB browser-main footprint.

The corrected `export_presets.cfg` helper gates iOS/iPadOS before installing any
listeners, waits for a trusted event, uses valid one-second PCM silence, rejects
empty/nonfinite decoded duration, and releases playback on hide/pagehide.
Desktop and Android create no helper audio. Failed starts have a three-event
limit and no automatic retry. Game volume preferences remain unchanged.

Focused regression commands:

```sh
node --test tests/web_audio_keepalive.test.mjs
node tools/test_web_shell_behaviour.mjs
python3 tools/check_web_shell.py
```

Result: **14/14** helper tests, **104/104** existing shell behavior checks; all
**10** inline scripts parse and **8** required behaviors remain present. The
helper test is registered as `./run_tests.sh web_audio_keepalive`. These synthetic
platform/media tests do not establish actual iOS silent-switch behavior; that
requires an iPhone/iPad check including background/foreground return. Full-game
Chrome exposure and RAM verification is tracked separately; no deployment or
whole-regression acceptance follows from these checks.

Evidence: `qa_shots/tests/web-shell-lifetime-audit-20261007/AUDIO-AUDIT.md`,
`audio-helper-fixed-hashes.json` in that directory, and
`qa_shots/tests/web-memory-20261007-v6/audio-control-analysis.md`.

## Current correction pass — functional candidate verified; outfit library in progress

Missions, achievement pacing, previous-page Back navigation, Shop and the complete-image wardrobe are implemented and locally verified. Debug runs use Dummy audio. No commit, push, remote CI or game deployment occurred. The previously deployed feedback Worker/SES integration remains unchanged.

Verified scopes:
- Progression: 510/510 checks. 32 runner trophies in four tiers; the full set requires at least 10 active gameplay hours. Actual mission assignment/retry feeds and durable rewards verified. Calibration and official SYBO sources: `docs/qa/runner-progression-calibration-20261007.md`.
- Navigation: original 620/620 affected checks; final current-source traversal 123/123, empty stderr. Back restores previous scene, internal page and Settings state. Credits/Achievements footer now says BACK.
- Shop: 147 focused, 99 commerce, 26 portrait checks; final 155 native checks/four stills. Actual-root confirmation/Cancel preserved the player's balance; no real purchase was performed. `qa_shots/tests/shop-functionality-20261007-v4/receipt.json`.
- Wardrobe: complete illustrations replace layered clothing. Multi-slot try-on, explicit Buy/Equip, visible failed-purchase feedback and a four-texture cache. Original flow 120/120 and native 212/212 across 24 frames. Final root polish: 43/43 orientation checks and 128/128 native flow/capture checks, two reviewed stills. Cropped atlas regions restore icon size; labels fit the shelf; standard portrait includes the full gallery and page dots.
- Menu smoke: updated stale 3D assumptions; 120 wardrobe checks, all 10 menu scenes and one actual router transition pass with zero skips. Final menu fidelity: 140/140. Fresh actual-root import and silent desktop startup/preview passed. Detailed current evidence: `qa_shots/tests/correction-final-20261007/RECEIPT.md`.

Full 480-outfit library remains required and incomplete. Only visually reviewed entries enter `data/wardrobe/outfits_v1.json`; use `art_src/ui/wardrobe_outfits_v1/jobs.json` for current counts. Art ownership: ice_seam owns Adelie/Emperor/Rockhopper; avalanche_catch owns Chinstrap/King/Little Blue; desktop_visual_review owns Gentoo/Macaroni. All original generated PNGs/prompts and rejected attempts are retained. Trails remain separate. Strict 480-entry provenance/runtime-load verification must pass before declaring the library complete. Missing combinations deliberately show unavailable and cannot be bought/equipped through that preview. Menu stills do not change the animated in-run avatar.

Current correction estimate: approximately 80%; functional and layout scopes verified, full outfit generation/review and its final integration gate remain. Earlier progress/completion claims below are historical. Current source identity is recorded in the final receipt rather than inferred from the older local build label.

## Historical fidelity corrections v6 — 2026-10-07 (superseded by current scope above)

Home/Missions128/128 focused +144/144 native, eight final visual frames. Feedback36/36 clean focused checks, six final native form/retry/success frames with0errors. Worker9/9 local tests and production bundle pass; deployed Worker accepted one actual native form test via SES. No game export or remote CI.

Runner/Results474focused checks, landscape58/58 and two final Results stills pass with source-specific limits. Page corrections122focused +104menus +38Settings/Account pass; final Info delta26focused +30native with two final Shop stills. Twelve earlier page frames retain current Controls/Credits/Settings/wide-Shop evidence; earlier portrait Shop defects are superseded. Three wardrobe outfit concepts await user direction; 3D preview direction rejected, no wardrobe fidelity acceptance. Art review inventory remains181prior gaps, zero new errors; all three samples registered as source-only concepts. Two focused art tests pass. Detailed source scopes and failures: `qa_shots/fidelity-corrections-20261007.md`.

## Historical menu/runner reference fidelity — 2026-10-07 (superseded by user review)

Seven focused fixtures: countdown 18, platform 281, retry/live mission feed 49,
Settings/Account 38, frontend 111, router 68, remaining menus 104 = **669 passed**.
Final native HUD 29/29 in portrait and landscape, live 36/700 and 11/12 counts,
three 7s powerups. Core menus 29/29 and loader boundary 17/17; four final
pause/results stills fit both orientations. All requested menu pages independently
reviewed. Root importer 0, no parser/script errors; nonfatal Android daemon discovery
message retained. Art 36/36 hashes, zero new errors against 181 baseline.

Capture losses of foreground, earlier layout defects and an invalid loader 0%
expectation remain recorded as failed/superseded attempts. Existing native
renderer teardown warnings remain; no browser/device performance or full-regression
claim. Silent playable home visibly verified, no export/deploy.
Full receipt: `qa_shots/reference-fidelity-20261007.md`.

## Runner HUD/course/catch refresh — 2026-10-07

Final actual-window Compatibility captures: landscape45/45, portrait45/45,
reduced46/46; independently reviewed. Four-biome committed deck coverage25/25
and harness15/15, all four road images reviewed. Final death boundary18/18;
end/save47/47, clean stderr. Pre-player-fix headless432/432 and course775/775
focused assertions retained with exact scopes; final trail-only delta separately
tested and fingerprinted. Art hashes18/18; no new inventory errors (181 existing).
Fresh root import clean; silent playable Base Camp visibly verified.

V1 failed banner timing, v2 invalid empty-course biome captures, and v3 fixture
startup race/mission/hero visual bugs are preserved and superseded, not counted
as final acceptance. Existing renderer shutdown diagnostics remain. No FPS,
natural-input/collision, full-regression or export/deployment claim. Full receipt:
`qa_shots/runner-refresh-20261007.md`.

## Avalanche landscape/action follow-up — 2026-10-07

V3 anchors visible painted snow rather than transparent image bounds, after
camera placement. Foreground landscape 960×540 and portrait 540×960 each pass
29/29 with zero invariant violations. Reviewed baseline, jump and post-hit
frames keep powder visible and hero/lanes clear. Synthetic direct jump/hit
calls are recorded explicitly; not physical-input or natural-collision proof.
Focused isolated retry/HUD 44/44 clean. Existing renderer/ObjectDB/resource
teardown diagnostics remain. Three covered-window capture failures retained;
owner-assisted visible capture succeeded. No performance/full-regression pass.
Receipt: `qa_shots/avalanche-landscape-followup-20261007.md`.

## Menu/results/loading refresh — 2026-10-07

Six Compatibility captures inspected against new desktop references; all exits
0 and stderr empty. Loader boundary 17/17; web shell behavior 104/104. Source
fix removes a portrait results orphan Control. Final portrait recapture shows
score heading clear of the hero. Avalanche real 4s/6s captures: 22/22 fixture
checks, visible powder below clear hero/lanes, but teardown ObjectDB/resource/RID
leaks remain recorded. No browser-performance or full-regression acceptance.
Receipt and Drive archive: `qa_shots/menu-refresh-20261007.md`.

## Untraced foreground continuation — 2026-10-07

Tracing probe explicitly reported no trace running. Existing QC6 logs contained
5.4/12.1-second gaps without visibility history; changing foreground and later
Chrome process exit invalidate a controlled game-only comparison. No active-play
or independent close gate completed. Source-only context diagnostic: JS 15/15,
isolated Godot clock/metadata 25/25 clean at
`qa_shots/tests/waddle-wars-tests-5503-22743/`. Full regression deferred.
Receipt: `qa_shots/browser-untraced-continuation-20261007.md`.

## Wardrobe/menu QC and Chrome continuation — 2026-10-07 EDT

QC6 is staged, not production-promoted. Focused frontend 111/111 and web shell
104/104 clean; wardrobe rotation/lazy preview/painted clothing/card containment
29/29 clean. Menu audit: 24 layouts, three sizes, 30 captures. Side-by-side review
of 11 pages saved in `qa_shots/menu-comparison-final-20261006/`; it establishes
remaining mismatches, not 1:1 visual acceptance. Knit/crown placement was
window-captured; the subsequent final knit-height adjustment and QC6 Chrome
review are pending visual acceptance.

Fresh QC5 Chrome tab rendered menus, changed categories, showed clothing before
purchase, and canceled purchase without spending fish. Warm engine windows
reported ~60 FPS; 8-second visible RAF sample had 481 callbacks, p95 17.66 ms,
max 17.665 ms, zero >100 ms. Startup/first wardrobe entry still included
782.2/260.5 ms frames. Old-tab navigation stalled; browser diagnostics then
disconnected. Native Chrome sample: 8.2 GB process footprint, 9 GB peak. This
does not establish cause, click latency, phone performance or solved freezing.
Preserved evidence: `qa_shots/browser-menu-performance-20261006.md`,
`qa_shots/chrome-main-process-20261007.sample.txt`. No settings/extensions changed.

Approved Chrome restart completed; QC6 reached visible home and wardrobe.
First menu draw logged 15,099 ms. Browser controls disconnected again during
attempted tracing; active-play/retry and independent close timing remain
unverified. Tracing's contribution is unknown; inspect collector state before
any further trace. See `qa_shots/browser-restart-comparison-20261007.md`.
Production root unchanged; final browser check requires restored Chrome control.
Full regression/native/store launch gates not claimed by this focused pass.

## Web release and menu IA — 2026-10-05 EDT

`web-20261006-035500-737a1c8` is live at `https://play.waddlewars.io/`.
Fresh isolated import/export had no parser/import errors. Runner focused suite
passed all executed groups after restoring fog across covered warmup, meeting
low-light road contrast gates, and updating camera checks for the deliberate
procedural MVP character backend; window-only dusk raster remained skipped.
Frontend structural/category checks passed 125/125; the main-menu inset matrix
passed 24 fresh/rotation layouts; full menu audit reported every screen
reachable at three sizes. Windowed 540×960 and 960×540 captures, 360×640 and
844×390 audit captures, Base Camp, Settings, and desktop keyboard-focus capture
were reviewed. Staged 14/14 HTTP artifacts returned 200; pack/WASM/loader
SHA-256 matched export. Chrome staged and public roots rendered the corrected
menu, with the expected build ID and zero game-console errors. R2 production
root readback matches the candidate. Earlier versioned payloads and root
rollback file are retained at
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/web-20261006-035500-737a1c8.pheLnu/`.
Full suite, mobile performance acceptance, Clerk production-key cutover and
store submissions remain open; this receipt claims none of them.

## Current gate — 2026-10-04

Play Waddle Wars listing draft now shows one `icon-512-v4.png` (old v2 removed)
and “Your changes have been saved.” This does not submit or publish the listing.
The image source hash matches local store asset. Two new visual studies were
rejected after 64 px and 540×960 review; runtime remains v4. Focused Godot
title capture reports `err=0`, and the store-icon PNG/receipt test passes 1/1.
The full regression suite remains deferred per user instruction. Android
customize QA's three save/settings files were restored to pretest hashes. See
`qa_shots/native/play-icon-v4-20261004.md`.

Android b31 tested existing staged course/racer creation on native. Isolated
`race_presentation_gate` passed 82/82 and `race_warmup_boundary` 125/125;
Godot import and debug APK identity/signature checks passed. Same host-GPU
emulator entered live Glacier Gauntlet, but app-process EGL recorded 1,960.79 ms
while loading and 1,666.77/1,150.08 ms during play. `simpleperf` captured
635 samples with zero loss and points to emulator GLThread/kernel work, not a
proven engine root cause. Native performance gate still **fails**. b31 source
SHA-256 `f9a89f3ad291be6aae5e0396c211f6d17e391dec6a1ed0fab5625d033bbff62a`;
see `qa_shots/native/android-b31-staged-20261004/receipt.md`. A subsequent
unbundled `project.godot` gravity-sensor setting fixes a logged tilt warning
in source only; no current native candidate or store build contains it.

Android b30 from source SHA-256 `0bd0400474df9a6f589945fd02762fbb24a95a1d6d0dbb392ab7c15a74451050`
is debug-signed only. API-35 host-GPU emulator: upgraded-install runner live
by 12-second capture, left/jump/grounded slide, three retries, pause held
distance, and landscape menu reflow observed. First Glacier Gauntlet entry
stayed under loader and recovered; logcat records a 32,106.89 ms graphics
frame. One retry then reached live race. No fresh-install, full active-play
soak, tutorial/endless, or current-source iOS acceptance. QA save/settings
restored byte-for-byte and rotation restored. Play IARC content rating now
shows Completed. A corrected questionnaire removes
the earlier in-game-purchases descriptor for this no-paid-IAP MVP; Play's
current rating page shows ESRB Everyone 10+ and PEGI 7. Data Safety preview
was rechecked against b30 package (only INTERNET permission, Godot native
library) and optional leaderboard code, then saved. Dashboard setup is now
11/11, but Publishing overview says changes not submitted and disables review
send until release prerequisites. Not published. See
`qa_shots/native/android-b30-20261004/receipt.md`.

Icon v4 local source/import generated from the loading-penguin identity. 64 px
thumbnail review selected the tightest of three studies; Godot import and
focused native store-icon format/receipt test pass 1/1. Runtime, export preset,
PWA outputs and local store-size outputs use v4. b30 and Play's listing upload
predate the icon change; debug b31 contains v4, but a final signed candidate
and matching store upload remain needed.

Wordmark v4 local checkpoint: Godot import passes; Compatibility title/menu
540×960 captures reviewed; `menu_mvp` passes three phone sizes and 24 live
inset/scale layouts. Art validator remains red on 125 older WIP files, with
no v4-specific failure; title shot printed resource-at-exit warnings. An
earlier icon v4 study was rejected; the separate later selected icon v4 is
described above. b31 includes the wordmark and icon v4 but no store upload does. See
`qa_shots/premium-brand-v4/receipt.md`.

Mobile deletion-request page now returns HTTP 200 at
`https://waddlewars.ninjaconsulting.ai/native/delete-data.html`, and its public
GET SHA-256 matches `web/native/delete-data.html`:
`973405cb64f0c6b0de12f5c5e0717d91f814f3a09105a71b6a7cfb203aa6c035`.
Play accepted URL and saved Data safety as a draft. Preview lists optional
Approximate location and App interactions, no third-party sharing, and HTTPS
transport; dashboard still 9/11. No review submission or final native
runtime/SDK audit. See `qa_shots/native/play-data-safety-deletion-20261004.md`.

Play default listing saved with b29 menu/gameplay screenshots and per-asset AI
labels; dashboard confirms 9/11 setup tasks. It is ready to send for review,
not submitted or public. Replace/reverify screenshots against final candidate.

Android pre-probe b29 replaces b26 as the newest native cold-load evidence:
live runner by first-installed 18-second capture and repeat cold-process
12-second capture, with no recovery observed. This is not a first-install
12-second or active-play acceptance. Details at the b29 checkpoint below.

Hero shader sampler experiment: both temporary three-fetch variants passed
six local pose captures but differed from baseline by 3.27–3.34% normalized
neutral close-up RMSE. Original source restored; no Android package or
performance claim. See `qa_shots/native/hero-sampler-ab-20261004.md`.

Play Waddle Wars draft now shows 8/11 setup tasks complete after saving
13+ target-audience ranges. This remains a draft, not review or publication.
Content rating, data safety and listing screenshots are open. Clerk Production
account portal/email-code configuration is present, but hosted sign-up requires
a password plus verification code and no production sign-in has been tested.
The b26 host-GPU medium-quality QA control still took
28.689 s for first visuals and recovered at 30 s; original settings were
restored with matching SHA-256. No quality-default change.

Existing Android b26 emulator A/B: explicit host GPU confirmed at runtime,
yet first visual pass took 28.863 s and hit recovery. ANGLE/SwiftShader took
21.300 s and also hit recovery. `-gpu swiftshader` aliases `swangle` here;
no third workload run. Debug build is stale, not a current-source candidate.
No cold-entry pass. See `qa_shots/native/android-gpu-mode-ab-20261004.md`.

Brand candidate: new icon and wordmark imported locally; title, boot, and
main menu use the wordmark. `loader_boundary` passes 16/16;
`frontend_presentation` passes 93/93 but reports six ObjectDB instances and
three resources still in use at exit. Post-change `menu_mvp` passes three
phone sizes and 24 inset/resize cases. Focused title/menu captures and 64 px
icon review pass. Play draft saved the new icon and feature graphic, while
candidate-matched screenshots, production Clerk login,
signed packages, and final full suite remain open. See
`qa_shots/premium-brand-v2/receipt.md`.

Content-rights data correction: user-supplied penguin reference now carries
`reference_unverified` rather than `project_original`; authored-art validator
rejects that ID on runtime assets/exports. Focused test passes 1/1; review
manifest validates but reports 103 unresolved review-only assets and
`release_ready=false`. Derived hero material and final store rights answer
remain open. See `tools/release/content_rights_review.md`.

Focused source-only menu/auth pass: `./run_frontend_qa.sh menu_mvp` passes
three real-window phone sizes, safe-area passes and 24 fresh/live menu inset
cases; 6 captures retained. `./run_tests.sh online_auth_contract` passes
53/53, and the two targeted web auth tests pass 13/13. This is not deployed
or a production Clerk sign-in pass. See
`qa_shots/tests/menu-auth-focused-20261004.md`.

Play Console read-only: developer verification already registers Waddle's
package; Play App Signing distribution key is in use. Upload certificate
fingerprint is unavailable before first bundle upload, so local build-24's
different upload fingerprint cannot yet be treated as a Play signing failure.
No bundle uploaded or release submitted. See
`qa_shots/native/play-signing-readonly-20261004.md`.

Cold-install control: old Android build 18 also fails first Waddle Run entry
on the same emulator, ending at loader recovery; its prior quick screenshots
were not cold-load acceptance. Frozen build-18/b26 shader, art and character
trees are identical. b26 QA app and three saved files were restored with hash
persistence checked after full reboot. See
`qa_shots/native/android-b18-cold-ab-20261004/receipt.md`. No fix yet.

Android b27 Mobile feature override did not activate; b28 direct Mobile
rendered black with repeated Vulkan present errors. No renderer-based cold-load
pass. QA renderer settings reverted, isolated save restored with persistence
verified after reboot. See
`qa_shots/native/android-renderer-compare-20261004/receipt.md`.

Android b25/b26 fresh debug installs reproduce the cold runner timeout. Native
stage and per-draw trace shows 318–325 ms setup, then ~27.5 seconds of first-use
visual submission; six batches contribute ~26.7 seconds, including 7.88
seconds on the skinned hero/VFX batch. Shader warmup has not completed when
SceneRouter recovers at 30 seconds. No graphics fix or acceptance pass yet.
Debug edition verifier passes 36/36 focused tests; b26 APK is verified but
development-only, not store-ready. See
`qa_shots/native/android-b25-coldload-20261004/receipt.md`.

Alternate API-35 ARM64 emulator accepted existing build 23 after preserving
and restoring its test-only save across a signature-mismatch reinstall. Three
Run Again actions reached live gameplay, and fish/high score survived app
force-stop/relaunch. Two short active display-present samples were smooth,
but **first cold runner load hit recovery after 30 seconds**. That fails the
native cold-load gate; short frame samples and a 565 ms tap-to-screenshot do
not establish full no-stall or strict retry latency acceptance. Evidence:
`qa_shots/native/mvp-build23-alternate-emulator-20261004.md`.

Cloud-save conflict guard is source-only. `./run_tests.sh online_auth_contract`
passes 53/53 in an isolated `user://`; phone portrait and compact landscape
render captures show all four explicit choices. Failed GET/PUT and account
switch behavior are covered. This does not prove a live Clerk flow or remote
save migration and is absent from Android build 24. Evidence:
`qa_shots/native/cloud-save-conflict-20261004.md`.

Clerk dashboard read-only check confirms Waddle Wars Production, not Legacy
Legal. Its Google OAuth provider is enabled but reports `Setup required` with
empty custom credentials; this prevents claiming production Google sign-in.
No production auth or backend acceptance test has run. The dedicated
`waddle-wars-penguin-panic` project exists under the personal Google account,
but its OAuth support-email picker offers only that personal address and
unrelated groups. The approved business Google account is already signed in
as another Chrome account; its own Google Cloud first-use Terms of Service
screen has not been accepted. No OAuth consent form was submitted, no client
credential was made, and Clerk still reports `Setup required`. This is an
account/consent prerequisite, not a native or public-auth pass.

Build-22 Android Dressing Room portrait page scroll and species selection are
observed. Its live portrait-to-landscape rotation exposed a stale stacked
layout. Build 23 fixes this in the installed native app: portrait → landscape
side-by-side → portrait, with equipped Adelie and 766 fish retained. Focused
`customize_orientation_reflow_test` passes 8/8. Build-23 QA splits are
debug-signed; the AAB is unsigned and not store-ready. Visual fidelity remains
open. Evidence: `qa_shots/native/mvp-customize-rotation-20261004.md` and
`qa_shots/native/mvp-build23-customize-orientation-20261004.md`.

Android build 24 is locally upload-signed and offline-verified from the exact
build-23 runtime source fingerprint. Its signed AAB is not installed or
Play-registered; build 23's native Customize QA is the applicable gameplay
evidence. Backend Clerk cache changed afterward, so this is not a frozen
all-component candidate. See `qa_shots/native/mvp-build24-android-signing-20261004.md`.

Verified MVP estimate is ~66%, superseding historical estimates below. Android
build 22 preserves the build-21 app data, reaches live runner, and removes the
1.6-second retry countdown. The retry callback enables input synchronously;
focused runner checks pass 39/39, 265/265, 29/29, and a real-window GUI cycle
passes 42/42. Repeated Android retry screenshots show movement, but screenshot
overhead prevents a precise <500 ms tap-to-photon claim. Build 22 also reaches
native Waddle School completion, persists its fish/level rewards across a
force-stop/relaunch, and exposes all menu controls by scrolling in landscape.
The eight individual lesson verbs were not all captured. Receipts:
`qa_shots/native/mvp-build22-retry-20261004.md`,
`qa_shots/native/mvp-build22-tutorial-orientation-20261004.md`, and prior
build-18/21 native receipts. Build 21 also verifies Endless pause at maximum
touch size; build 18 verifies first Glacier race/results. iOS simulator
title/menu render, but runner remains stalled at loader 75% in software OpenGL.
Long active-play stall QA, full portrait visual acceptance, the final full
regression suite, same-source iOS gameplay and store processing remain open.
The final suite stays deferred until a stable candidate as requested. Waddle
Wars Clerk production DNS/SSL is verified, but Google OAuth, production keys,
development-user progress handling, and live sign-in remain open. No public
deploy, TestFlight, or Play submission has followed. Physical devices are
waived, not passed.

Production Clerk public-key/issuer staging and issuer-scoped JWKS cache are
source-only, not deployed. Four focused Node files pass 27/27 with no skips;
they do not replace a production-user sign-in or save migration. Evidence:
`qa_shots/native/clerk-production-public-pair-20261004.md`.

## October 2 MVP scope and current launch checks

October 3 current-source signing checkpoint: iOS build 16 exports from the
same 524-file runtime `d849cd516cfcd232d6d8ea4f27f9ff97a2300da8c257cf2f6ddb973d411af972`
as Android build 15. Computer Use opens Keychain Access. The existing Apple
Distribution key signs a temporary executable; strict `codesign --verify`
exits0. Waddle's Xcode archive and local IPA export both exit0. Independent
offline gates verify the Waddle bundle, App Store profile, certificate, ARM64
signature and game payload. IPA SHA-256:
`885781615e810ec1c5ceaf7a79f9176b8674b84e51145740113c8043b8cdf70a`.
Archive and IPA gates:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-signing-current-20261003.TcthdW/archive.esFtCK/archive-verification-receipt.json`
and adjacent `ipa-verification-receipt.json`. Earlier
`errSecInternalComponent` no longer reproduces; its original cause is unknown.
Active gameplay, TestFlight and store acceptance remain open.

Current Android15 free-MVP unsigned AAB and development-signed APKS pass static
gates. Bundletool installs all five splits in the owned API35 emulator; version
and installed hashes match. Computer Use shows the title, but two Begin clicks
fail with `noWindowsAvailable`, leaving gameplay, retry and native loading
unverified. App/emulator were stopped. Receipts and hashes are at the top of
`BUILD_STATUS.md`. Android production upload signing remains open. A later Mac
session successfully opened Keychain Access, so the earlier locked-Mac
preflight is historical. **MVP ~80% / full ~35%** remains an estimate.

Latest parallel checkpoint: native privacy/support static pages pass anonymous
HTTPS200/type/byte readback; Play listing text saves/readback. This is not native
SDK/traffic/store-declaration acceptance. Native Settings URL buttons are now
packaged in Android15 and iOS16; current runtime imports0 and normal-project-context loading
parses Settings, native offline fixture and runner presentation fixture. Those
resources are never instantiated; fixture assertions do not execute. Retained
parser stderr is empty and stdout/engine logs contain no script/import/compile
errors. Runtime `d849cd516cfcd232d6d8ea4f27f9ff97a2300da8c257cf2f6ddb973d411af972`
and changed source hashes are bound in
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/native-settings-parser-20261003.oOENF3/parser-receipt.json`.
This is essential parsing only, not regressions, rendered links, link opening,
native loading/gameplay or store acceptance. Separate current package/signature
results are recorded above.

Play icon/feature graphic now persist in an independently loaded draft editor;
approved support Website and Privacy policy URL save with exact readback. The
privacy edit is pending review, not submitted. Store receipts:
`qa_shots/native/store-draft-assets-support-20261003.receipt.json` and
`qa_shots/native/store-privacy-url-20261003.receipt.json`.
No old gameplay captures are uploaded as current. Native screenshots, privacy/
age/audience disclosures and store submission remain open. Apple browser session
has expired. One bounded normal sign-in check reaches the secure password step
without a visible saved-password suggestion; no credential is read/entered or
searched. Owner sign-in remains required. Receipt:
`qa_shots/native/apple-autofill-availability-20261003.receipt.json`.

Latest iOS loading diagnostic uses distinct QA bundle
`com.blubberandbyte.waddlewars.runnerdiag.ios20261003qvsdd3`, base runtimefdb9c3f7,
old simulator executable and real `Game.start_runner`/SceneRouter. Import/export0
with no script/import errors; actual trace proves opaque cover and deferred
background engage. First `NearSnow` draw waits83,476.656ms; fixture timeout113.158s,
20draws, no cleared frame and no native gameplay pass. A1-second sample observes
software GLES Canvas work, not isolated particle/shader timing. Simulator log
wall dates differ from host sample dates; use engine ticks for durations.
App termination/owned-device Shutdown0 verified. No engine rebuild, timeout,
quality reduction, signing, upload or suite. Immutable evidence:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-covered-trace-20261003.qvsDD3/qa-receipt.json`.

Godot4.7.1's supported iOS simulator route is Compatibility-only; current native
software-GLES evidence does not justify another unchanged simulator experiment.
Owner approves additional **My Mac (Designed for iPad)** QA. Distribution
signing now works, but this route still needs a separate development profile.
It cannot be relabeled as simulator/phone performance or
shipping Compatibility acceptance. One read-only Xcode query confirms an
eligible macOS/ARM64 My Mac destination, terminal0/empty stderr. Private audit:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-mymac-destination-audit-20261003.0mu2yj/audit.json`.
Existing Metal-capable device engine is available; matching development
key/profile access, current isolated QA package and labeled QA renderer selection
remain unverified. No new engine/wrapper build, sign, launch or ad-hoc key bypass.
Public metadata audit of three cached profiles finds no matching isolated Waddle
QA development profile; the only development profile is exact Chancey scope and
must remain untouched. Its device-list comparison does not prove portal state or
key access. Evidence: the destination-audit directory's
`provisioning-prerequisite.json`. At an earlier supported Android Studio
preflight the Mac was locked; no emulator boot or input workaround occurred
then. Current Android15 was later exported, installed and title-tested as
recorded above. The billing-enabled debug helper was not used. Supported
interactive gameplay still remains necessary.

Owner-authorized disk cleanup removes only 24 old merged/stripped/JNI-library
intermediate directories. All eight canonical package hashes match before/after;
current snapshots, original libraries, source, logs, receipts, keys and saves
remain. Available-space observation rises4.2→8.9GiB, not a gameplay or signing
pass. Exact scope/recovery caveats:
`qa_shots/native/qa-native-cache-cleanup-20261003.receipt.json`.

Last night's focused feedback-fix passes bind local source/QA packages, not the
deployed web buildweb-20261003-d5766c0a42a3. Live phone layouts, mutual leaderboard
visibility, startup lag and current native gameplay remain unverified.

Free, offline-first iOS **and** Android MVP is the current scope; see
`tools/release/README.md#launch-mvp--authoritative-scope-october-2`.
Premium art, new gamification, accounts/cloud and real-purchase acceptance are
deferred, not implicitly passed. Native purchase/account flows must be disabled.
No further art-tool experiments or open-ended browser profiling are authorized
by this launch checklist. Existing local regressions are not weakened.

**Owner test cadence:** defer regression suites until the final candidate.
During implementation, run only essential parser/import checks. The interrupted
suite at `qa_shots/tests/waddle-wars-tests-46760-10662/` ends **130**, without a
summary/pass claim. Its capture fixture was edited after snapshot copying;
the retained parser pass is not proof for the final fixture. Final local gates
remain mandatory before remote CI/upload; prior completed counts below are
historical evidence, not a replacement for affected final validation.

**Native covered-background patch:** final-source editor import finishes0,
with no script/import errors in stdout, stderr or engine log. The 524-file
runtime is `fdb9c3f702bb621a8a495aca4392b5f0e270713ce128007f72981eaab3bf1a1c`.
New runner/router fixtures have independent source review, not executed
assertions. Their standalone `--check-only` attempts fail compilation because
autoload identifiers are unavailable; exit0 is not a pass. Final fixture checks
must use their normal project/test context. Exact logs/source binding:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/covered-background-qa-20261003.Gnb5vD/parser-receipt.json`.
That parser checkpoint establishes no native loading/gameplay acceptance,
export, signature, deployment or upload. Disk later recovers from302MiB to10GiB
without agent deletion, enabling one changed-build simulator pass below.
Canonical packages/receipts remain unchanged.

**Changed-build iOS simulator13 loading pass:** current PCK exports0 with no
script/import errors. A copied simulator11 app has a unique QA bundle identity,
version13 and matching installed PCK/executable hashes; other bundle files stay
byte-identical except plist. Separate identity isolates iOS saves: the native
engine ignores the custom user-directory option used for desktop import QA.
Normal title and main menu render, then Waddle Run shows warmup and reaches
loading recovery. This fails native loading acceptance; covered-patch engagement
and benefit remain unverified. The1-second post-recovery sample has87 main-thread
samples in software canvas drawing, not evidence of earlier warmup cost.
No unchanged launch, engine rebuild, renderer experiment, signing or regression
suite follows. PID46239 is absent, owned device Shutdown, disk7GiB. The old binary
retains deferred bridge/capacity code, so this is not free-MVP SDK/privacy or
distribution acceptance. Receipt/screenshots/log:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-covered-sky-qa-20261003-b13.wJx8Eg/qa-receipt.json`.

Release-tool source now distinguishes free-MVP SDK absence from historical
commerce linkage. New native snapshots omit deferred billing/auth SDKs; Android
manifest/DEX checks and iOS linkage checks reject their reintroduction. Existing
fixtures cover preparation, iOS verification, Android verification, external
signing, custom-template binding and free Android input preflight; their new
assertions remain unrun. Python parsing is not a regression pass.
iOS12 is the first export/linked app with this package policy. Its one patched
ARM64 device Release engine compile finishes0 in9m36.23, preserving all three
device renderers. Device-only template metadata and actual linked app bytes pass
static review: no inspected capacity APIs/keys, no deferred native SDK linkage,
exact file/timer reasons without a disk category, and PCK/privacy equal to export.
The first archive attempt fails at CodeSign with `errSecInternalComponent`;
its signing-time lock state and cause are unproven. One fresh retry after visible
unlock fails with the same error, terminal1. Failed artifacts/log are preserved;
no additional retry, keychain change or IPA follows. This does not pass signed privacy, gameplay or store
acceptance. Exact receipts are recorded in `BUILD_STATUS.md`. No loading fix is
claimed; final regressions remain deferred and new fixture assertions unrun.

**Android14 free-MVP export** now includes the billing-input omission policy.
Import/export exit0 and retained logs have no script/import errors. Bundletool
validation and both ARM64 libraries' 16-KB structural checks pass, terminal0;
actual manifest/metadata/DEX review confirms the omitted SDK chain is absent.
The one subsequent signing helper dispatch fails at
`reading_app_specific_keychain_password`, before signing. The unsigned bundle
is retained under `project/build/waddle-wars-unsigned.aab`; failed-attempt and
export receipts remain unchanged. No signed verifier, installation, gameplay,
store upload or regression suite follows. Exact paths/hashes are in
`BUILD_STATUS.md`. SDK absence and structural passes are not runtime/privacy
acceptance.

Current unpublished provider wording and its existing page fixtures are
reconciled; AST parsing passes. Fixture assertions remain unrun until the final
gate. Draft dates, final SDK/audience review and null live policy URLs remain
guarded. No published policy or collection declaration is inferred.

Google Play draft `4974838896609027403` is created after the owner's action-time
policy/export confirmation. The dashboard and saved Arcade/contact confirmations
are observed and captured. This is portal setup only, not a native test, store
review, build upload or public release. Other store declarations remain pending.
One Android UI-availability attempt confirms installed build13 on the same owned
API35 emulator but does not launch the game: standalone computer control rejects
the unbundled emulator binary. Android Studio only reaches Welcome before being
closed. Emulator shutdown is terminal0. Reused QA data, UI availability and
installation are not cold-start/gameplay acceptance; no alternative input is
injected and no regression suite runs.

A subsequent supported Studio check reaches Welcome's Virtual Device Manager,
whose visible list contains only unrelated Chancey devices. No device is started
or altered; Studio closes and no emulator/app process remains. The isolated
Waddle UI path is still unestablished, not disproven. Screenshot evidence is
recorded in `BUILD_STATUS.md`; this is availability evidence only.

A supported APK import subsequently opens a local inspection workspace and its
Running Devices panel. The isolated owned emulator boots with official embedding
flags, but the panel's device menu still lists only unrelated Chancey AVDs.
No game is launched or accepted, no Run/Debug/Profile/reinstall/build occurs,
and no global registry/mirroring setting changes. The emulator is stopped0;
its process and later device list are absent. This uses historical Android13,
not the current covered-background patch. Exact receipt/log binding is in
`BUILD_STATUS.md`; final native acceptance and regressions remain open.

The next Android availability check registers only the existing Waddle pointer
and removes the fixed port that suppresses authenticated embedded discovery in
the pinned emulator. Studio renders owned `emulator-5554`; Android13 starts
through its public activity and reaches a settled title. Native input fails with
`noWindowsAvailable`, so menu/gameplay/retry/orientation/save acceptance remain
open. No substitute input is injected; app/emulator are stopped0. Config and
Chancey registry pointers are unchanged. The retained Waddle pointer is not
permission to use normal Studio Launch without the established data overrides.
Receipt: `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-registered-smoke-20261003.AsZ3sS/qa-receipt.json`.
The Android13 historical billing plugin initializes; this is not an SDK-absence
test for Android14 or a current-runtime test. No suite/signing/rebuild follows.

**Android13 bounded interactive pass:** supported Begin Expedition and Waddle
Run clicks work. Warmup is observed; the next settled observation shows results
at 292 m, 67 fish and 1,996 points. An unattended run therefore completes, but visual
loading latency, countdown ordering and active controls are not measured.
Both retry clicks fail with `noWindowsAvailable`, including after supported
window activation. No alternate input, reinstall, unchanged restart or suite
follows. App termination succeeds, emulator exits 0 and the device list is empty.
Exact receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-interactive-smoke-20261003.DWxK3f/qa-receipt.json`.
This package remains older `cc89e3d7` with billing retained, not final `fdb9c3f7`
or free-MVP acceptance. Its 17 unknown DAY IDs are intentional release fallback
from the unapproved debug/editor-only fragment; 33 is an error enum, not a failure
count. Existing 584/584 asset parity does not establish current runtime loading,
responsive gameplay, retry, orientation, persistence or performance. **MVP ~75%
/ full ~35%** remains unchanged.

**October 3 refreshed native QA packages:** iOS simulator11 and unsigned Android13
share the current 524-file runtime
`cc89e3d732a9f8ccdf49df130975abec84c57438414dd373c5a2fff640593606`.
Both imports/exports pass with no script/import error. iOS links ARM64 Release
with distribution signing disabled; Xcode records zero errors and one duplicate
`-lc++` warning. Actual app PCK/privacy match the export. Android passes bundletool
validation and both libraries' 16-KB structural gates; its canonical AAB remains
unsigned, with no runtime acceptance. A separate Android13 APKS derivative has five
development-signed APKs with verified signatures/16-KB alignment; its canonical
AAB remains unsigned and unchanged. This is preparation for an isolated ARM64
emulator, not upload-signature or native acceptance. Receipts:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-reported-fixes-qa-20261003-b11.9Uo0CA/artifact-receipt.json`
and `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-reported-fixes-qa-20261003-b13.u1I9nE/artifact-receipt.json`.
Its adjacent APKS QA receipts separately verify 584 game assets, DEX and both
engine libraries against the AAB. Transformed Android resources are not claimed
byte-equal or fully semantically verified. Bundletool subsequently installs the
derivative into the exact owned ARM64/API35 emulator with terminal0; actual
version13 and all five installed APK hashes match, including the asset pack.
The existing isolated device data is reused, not pristine. Bundletool cannot
clear the old private splitcompat cache through `run-as` on this non-debuggable
app; no permission workaround or uninstall follows. Installation passes, but
cache/resource behavior, rendered gameplay and cold-loading remain unverified.
The app is not launched and the owned emulator is shut down. Exact derivative
paths and hashes are in `BUILD_STATUS.md`; original static receipts are unchanged.
iOS11 ran once through its normal entry point on the unlocked Mac's reused
task-owned ARM64 iOS18.4 simulator. Installed build identity is confirmed. Native
title and portrait main menu render; keyboard input selects Waddle Run. The
runner remains at "Warming the trail..." during the bounded pass, so gameplay,
touch, retry and cold-loading acceptance remain open. One 1-second process sample
at 15:57:04 UTC places all 209 main-thread samples in GLES3 sky drawing through
Apple's `GLRendererFloat` software renderer; this is not a deadlock or a physical
device result. The sample path/hash are recorded in `BUILD_STATUS.md`. Simulator
is Shutdown and app PID86869 is absent. No repeat launch or renderer experiment.
Android13 is installed but has not run.

The native Settings privacy/help addition and extended existing fixture were
made after the focused pass below; that fixture remains unrun and affected final
checks must be repeated. No regression suite, keychain access, physical device,
deployment or store upload occurred. The later isolated engine compile is now
terminal; prior native QA handles are also terminal. Interactive
native/cold-loading, privacy/store and final signing gates remain open;
**MVP ~75% / full ~35%** is a coarse estimate, not launch acceptance.

**October 3 reported launch fixes:** owner confirms current runner lighting and
slide spacing are already good; no additional changes to those systems remain.
Focused evidence lives at
`qa_shots/tests/reported-launch-fixes-20261003.88itpD/receipt.json`.
Fourteen selected groups pass: menu/customization, online auth/score/prompt
contracts, native offline fences, runner end-save, router presentation/recovery,
race/tutorial start gates, race warmup boundary, shader inventory/geometry,
nine real Iceberg platform crossings, full Iceberg race and backend privacy/auth.
Source fingerprint `eb9fcb1ad6c8b74e33a8dec4ca2b4e45e14c30530b450936cf6b0f285a332f61`
binds 992 compared files; only QA user-directory settings differ. Backend28/28,
online auth42/42, native offline103/103, race start82/82; all nine traversal cases
have zero respawns and all eight full-race results have no DNF. Earlier failures
are preserved, not relabeled. Known shutdown-only leaks remain open.

This focused pass does not replace final regressions, phone visual QA, mobile
startup/performance verification or signed native acceptance. The Mac is locked;
interactive simulator/layout checks remain pending. Leaderboard backend/game
updates are local only, and live owner/Sol visibility is not established.
Deployed web and all native packages remain unchanged. **MVP ~75% / full ~35%**.

**October 3 previously deployed web candidate:** full suite at
`qa_shots/tests/waddle-wars-tests-82774-1607/` records **104 PASS / 9 SKIP / 1 FAIL**,
exit1. Sole failure: excluded shader-warmup geometry fixture inferred `WeakRef`
types, treated as parse errors. Explicit typing fixes it; isolated affected rerun
at `qa_shots/tests/waddle-wars-tests-85201-4412/` passes **95 assertions**, exit0.
The 1,098-file comparison in the release's `full-suite-source-binding.json`
shows only that fixture changed; all runtime and export inputs remain bound.
Three previously skipped NumPy groups separately pass **10 tests** on the frozen
full-suite source. Six window-only groups remain unrun: hero atlas shader,
initial scene-router draw, dusk raster, orientation recovery, mobile UI and race
HUD/touch layout. Original failed/skipped history is preserved, not overwritten.

Web **`web-20261003-d5766c0a42a3`** is deployed. Twelve non-HTML staged HTTP
objects match exact bytes/digests/types/isolation headers. HTML has one precisely
accounted-for host beacon insertion; removing it restores the exported bytes.
After the atomic root switch, remote root storage equals the candidate; Chrome
shows the canonical URL's new build/base and rendered title without game errors.
Staged title/menu are observed. No active gameplay/performance acceptance,
native/store acceptance or executed live rollback is claimed. Evidence:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/web-release-20261003.He1W9j/deployment-result.json`.

Current recovery-containment source is **524 files** / SHA-256
`bc05858a927ec9da0ea1c56a0c73931269fae687f6827f6a5f3f3f866ac17cd2`.
Isolated Godot 4.7.1 editor import/parser exits0 with zero script/import errors;
the copied runtime and three edited fixtures match source. At that earlier
checkpoint no game entry point or regression suite ran, and **52 new planned
assertions were unexecuted**. Final web-candidate headless recovery/warmup groups
now execute as recorded above; native effects and real-window gates remain open.
Receipt: `qa_shots/native/recovery-containment-20261003-Nd6A0j/source-verified-receipt.json`.
Earlier signed Android11/iOS9 packages do not include this source change.
Final local gates and refreshed native candidates remain required.

The actual normalized Android trace ends in `router_recovery`, not acceptance:
initial visual submission continues until the 30-second deadline; no settled
full-scene or shader-probe completion follows. The diagnostic bypasses boot/menu
and uses a copied QA device, not a pristine cold device. Recorded long draw
intervals are frame-wall waits, not isolated compile times. Recovery containment
stops subsequent helper work without changing art, gameplay or the deadline;
its native effect and cold-start speed remain unverified.
Immutable receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-runnerdiag-runtime-normalized-20261003.bn4jcC/guard-corrected-final.receipt.json`,
SHA-256 `f3bdf99bd0a5eeef06a9221a32a6f96fc3caec964aa1a1597e4664b0f15b8ae8`.

Earlier containment-source iOS simulator **build10 is actual ARM64** and includes recovery
containment. One supported pinned-source simulator engine target and one
separate Release app link finish0; current export PCK/privacy and canonical
inventory match. No distribution signing/keychain access. Public virtual-device
controls run once on reused task-only iOS18.4 while the Mac remains locked.
Actual1206x2622 captures show title/loading at observed process age8s, then settled
Begin Expedition title at38s. These are two observations, not continuous startup
latency or pristine cold-device evidence. No gameplay/performance acceptance.
Owned device is Shutdown, app process absent; source remains `bc05858a…`.
Regression suites stay deferred. Immutable receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-arm64-20261003-b10.d3FU9J/title-smoke-receipt.json`,
SHA-256 `69c61a8035acd4655b02d9da820caeb0f16d321a8c967311bd0b3b26cf88a353`.
Verified current iOS launch milestone: **MVP ~75% / full ~35%**. Full native
smoke, Android changed-build cold loading, final signing/tests/store gates remain.

Earlier iOS frontend evidence uses a fresh owned default-set iOS18.4 simulator
and historical build9. Readiness and installation succeed; one supported app
icon click starts the actual app process. The observed frame is a black launch
screen, not the Waddle title/game. A one-second process sample shows the canvas
renderer running through GLEngine/GLRendererFloat software rasterization under
Rosetta. It does not establish a deadlock, crash, or gameplay performance.
The owned simulator finishes Shutdown and the app process is absent. No source,
signed package, physical-device or regression work occurs in this pass.
Receipt: `qa_shots/native/ios-frontend-launch-20261003/final-receipt.json`,
SHA-256 `97198dc775332476ddb999343327e0fbb08a140c79d6b300ab38f2ae3047ed66`.
No repeated x86 launch. Actual ARM64 simulator engine acquisition is completed
above, without a claim of hardware graphics. Full native acceptance remains open.

Earlier signed checkpoint runtime: **524 files** / SHA-256
`dc50ecd61b568091d3f5effedbc0d2ee545447d657ce96d191b0ed65c9faa569`.
Full existing suite finishes terminal0, **105 PASS / 9 SKIP / 0 FAIL**, retained
at `qa_shots/tests/waddle-wars-tests-19908-19383/`; three NumPy classes separately
**10 / 0 / 0** on the same snapshot. Release tools **522 / 0 / 0** after draft
screenshot preparation. Known shutdown
warnings, six real-window groups and one internal geometry skip remain.
These counts are local validation, not native gameplay/performance acceptance.

Current canonical **Android11 AAB is upload-signed and verified offline**:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-release-parity-qa-20261002-b11/receipt.json`.
AAB SHA-256:
`1241dc2aed31c99875edd6104727dc7cc16ada5ae079c7d5761cbb95ce3efa7e`.
Signature/upload pin, payload equivalence, bundletool and 16-KB structural gates
pass. Current **iOS9 signed archive/IPA pass strict offline gates**, both Xcode
steps terminal0. Evidence root:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-mvp-archive-20261002-b9.1qNmjo`.
Its `handoff-receipt.json` and archive/IPA verifier receipts bind the same source,
signature/profile/title/ARM64/native linkage, frozen PCK and resource equivalence.
IPA `ipa-export/waddlewars.ipa` SHA-256:
`35bc5de48e0bebe40bd4a05a2dfe502dfc618bd85f447ea287273942ec211273`.
Both remain **`store_ready: false`**, without upload/store acceptance. This
supersedes earlier unsigned Android11/iOS9 and older Android8/iOS6 package status.
Earlier failure evidence below remains unchanged.

Separate current Android release QA audit matches **641 normalized game/ARM64
payloads**; transformed packaging entries are classified, not byte-equivalence
claims. Receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-release-smoke-20261002.VufZ19/audit.d1xkr5/audit.json`.
Fresh offline zero-fish menu is observed. Cold runner route at **21:46:13 UTC**
reaches 30-second Recovery, observed **21:46:48**. Public Retry at **21:46:59**
reaches gameplay, observed **21:47:25**; jump, left lane, Pause, landscape and
Resume are captured. Slide was injected but not visually confirmed. Settled
portrait menu at **21:50:15** is nonoverlapping; rotation during entrance is not
timing-proven. Owned emulator shutdown finishes terminal0. Cold loading and
full native acceptance remain open.
Current-source x86_64 iOS simulator **build9 links**, zero errors/one duplicate
`-lc++` warning. Single bounded iOS18.5 boot fails runtime readiness after
**150.683 seconds**: `Status=3`, `isTerminal=YES`, `Data Migration Failed`.
Monitor exit0 is not a pass; readiness wrapper correctly exits3. No app
installation, launch or title screenshot. Exact-owned shutdown finishes
terminal0 with `Shutdown` confirmed. Separate link receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-x86_64-20261002-b9.IqelQw/receipt.json`.
Failure receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-x86_64-20261002-b9.IqelQw/headless-title-smoke-20261002/receipt.json`;
SHA-256 `28daeda98d77df6976eb974a615e93007bd5db1ba1e45e97898074cc8de4b82c`.
Historically, at 21:54 UTC, Data volume had only **3.7 GiB available / 100% rounded capacity**,
versus approximately 11 GiB before QA. Scoped owned logs contain no explicit
`ENOSPC`; migration cause is unproven. This is pre-app environment evidence,
not game acceptance.
Full current evidence:
[current signing and QA review](qa_shots/native/unlocked-mvp-signing-20261002/REVIEW.md).

Requested cache cleanup removes **14.7 GiB allocated**, with **21.88 GiB free**
at its checkpoint. Runtime and signed Android11/iOS9 pins remain unchanged;
no test/build/signing pass is inferred. Receipt:
`qa_shots/native/disk-cleanup-20261002/receipt.json`.
After cleanup, one iOS18.5 retry again fails readiness after **56.257 seconds**.
Fresh owned iOS18.4 readiness passes (`Finished`, **128.597 seconds**), with
build9 app pins matching. Its single install request times out after
**30.021 seconds**; installation remains unconfirmed. No launch/title capture.
Both owned devices finish `Shutdown`; a public lookup then returns
`SimError405`, `Unable to lookup in current state: Shutdown`, so it cannot
resolve installation. No additional boot/install retry. Immutable receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-x86_64-20261002-b9.IqelQw/headless-title-ios184-20261003.DyMiI3/receipt.json`;
SHA-256 `7e3dc238ee843879fb27d66a5e987c485a107e6daa298c22fc7bb400c92b1645`.
Old failure/retry receipts are unchanged. All owned heavy handles are terminal.
Existing suite counts above remain their dated results; no fresh suite run.

Subsequent iOS18.4 public Booted-state metadata confirms the existing app is
installed; no reinstall. One normal launch request times out (**30.011 seconds**)
with server/process outcome unknown. The one supported screenshot succeeds but
shows **SpringBoard only**, not Waddle Wars. Both owned devices finish `Shutdown`.
No title/game/performance acceptance. Latest immutable receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-x86_64-20261002-b9.IqelQw/headless-install-resolution-20261003.dsKjSS/receipt.json`;
SHA-256 `9a1b4f8d710b477e68fe5920406f3f158f14e1c454fef37d59a3c7cbf804fe70`.

One iOS18.4 console-attached diagnostic changes observability, not the app:
readiness passes in 89.069 seconds, installed-bundle metadata succeeds, but one
75-second console capture has zero stdout/stderr and no reported app PID. One
actual PNG shows SpringBoard only. Server outcome remains unknown; client -15
and wrapper0 are not an app pass or proved crash. Scoped app termination also
times out (20 seconds); exact owned shutdown succeeds, both owned devices are
Shutdown, and all app/previous receipt pins still match. No further headless
launch retry. New immutable receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-x86_64-20261002-b9.IqelQw/headless-console-diagnostic-20261003.lo7eSm/receipt.json`,
SHA-256 `6fc4225a1bf505b464b62ff49d446647c5546e08fcc1ed04283faf203287c404`.
No title/gameplay/performance/store acceptance follows.

Native runner diagnostics now use an opt-in branch in the existing excluded
`tests/runner_presentation_capture.gd`, retaining `Game.start_runner()` and
SceneRouter's real deadline. They log existing per-item warmup events and stage
snapshots without PNG readbacks/input. They bypass boot/menu and are expressly
not acceptance evidence. Release mode, a QA feature marker, fresh report and
distinct verified QA package/sandbox are required. Android's custom user-dir
name alone does not isolate OS app storage. The distinct-package unsigned QA
import/export and actual artifact checks pass; no regression suite was run.
Receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-runnerdiag-20261002.E9U8YP/candidate/receipt.json`,
SHA-256 `4df6a9b1c7a5ed159fc17c7d61b564f34fbe6c2e02eadb7b02916cec065b0955`.
The actual nondebug release manifest, feature/main scene/user argument, ZIP/CRC
and two baseline-equal ARM64 engine libraries are verified. Of 619 sealed inputs,
576 remain unchanged; 42 generated title XML files and one generated theme are
individually accounted for against the pinned exporter. The initial verification
hold remains immutable. Runtime execution is pending; no shipping acceptance.

The sole Android diagnostic then stops before app installation at its 120-second
emulator boot cap: 59 offline probes, one absent. No game trace or cold-loading
diagnosis. Owned emulator exits0, process group/serial are absent and original
userdata is unchanged. New/previous encryption-key paths differ; cause remains
unestablished, with no key-content inspection or retry. Immutable receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-runnerdiag-runtime-20261002.dmYbG8/native-diagnostic-final.receipt.json`,
SHA-256 `bae09a628007e1509223868115a8ee3a80b9a56ed01c6c772152b02d8f9d7d50`.

The one paired-state correction then verifies copied userdata plus its configured
encryption companion, but again reaches the 120-second boot cap before app
installation. Public kernel evidence establishes a guest first-stage mount
reboot loop (missing `super` device and failed vbmeta reads), not a game or GPU
failure. All originals/sealed inputs remain unchanged; owned emulator/process
group/serial finish absent. No runtime trace, regression suite or acceptance.
Immutable terminal receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-runnerdiag-runtime-paired-20261003.CVb2it/native-diagnostic-final.receipt.json`,
SHA-256 `8f35b2696ce7e76f9c8111d4dbe1a493bbb7bd0181cb6ae8cf444ccd5e60d931`.
Read-only comparison confirms the system disk and GPT partitions exist; the
boot-device mapping differs from prior working QA (`a003600` versus `a003800`).
One confined derivative restoring the prior supported disk-option layout is
pending. This is not a causal fix or acceptance; no unmodified retry,
boot-property override or AVB bypass.

Current Play form access succeeds under the owner's new creation request; the
historical extension interruption is not a current blanket access claim. No
controlled Chrome game pass or security change. Existing populated form awaits
action-time policy/export legal confirmation; no app creation/upload/publication.
Evidence: `qa_shots/native/play-create-20261003.Xfn75H/receipt.json`.
Audience, policy/SDK/required-reason and store gates remain open. Physical tests
are waived, not passed. Coarse progress: **MVP ~70% / full goal ~35%**.

Draft Android11 screenshot assets now include three unchanged 540x960 release
captures: title, settled menu and runner jump. Listing and receipt remain draft,
unsubmitted and not store-ready. The runner frame follows Recovery Retry and
does not clear cold loading. The new test checks original SHA-256 values, source
and package provenance, confined paths, PNG dimensions and every chunk CRC.
`python3.12 -m unittest discover -s tools/release -p 'test_*.py'` finishes
terminal0: **522 tests in 8.610 seconds, 0 skips, 0 failures**. Runtime still
matches all 524 frozen files; no new engine run, export or native acceptance.
Receipt: `tools/release/store_assets/android-build11-draft/receipt.json`.

Earlier October 2 checkpoints below retain their original runtime/results;
current package/test status is recorded above.

Earlier lock-independent follow-up: native Help & Support fixture **103 / 0**,
fresh full suite **105 PASS / 9 SKIP / 0 FAIL**, NumPy classes separately
**10 / 0 / 0**, release tools **521 / 0 / 0**. Full evidence:
`qa_shots/tests/waddle-wars-tests-11228-10362/`. Runtime `ed880157…`, Android QA10,
canonical iOS export8; known shutdown warnings and real-window skips remain.
This supersedes the preceding `1951ebde…` package-source checkpoint below.

Headless Android corrected pass uses fresh explicit QA userdata, host GPU,
airplane mode/no default network and no competing heavy build. Actual runner
jump/slide/retry, Pause/Resume, landscape, active Home/resume, native support and
process-restart save persistence are observed. **Cold runner load times out**;
**rotation during entrance persistently overlaps menu mode cards**. Debug DAY
preview assets differ from release art; neither timeout cause nor shipping
acceptance is established at that checkpoint. The subsequent UI repair passes
the fixture below; current native release-parity acceptance remains open.
First reused-Waddle-QA-data/software-GPU/overlapping attempt is timing-invalid,
not a fresh-save pass. Owned emulator finished terminal0. No Mac desktop/lock,
browser, Keychain, physical device, upload or live settings were used. Receipt:
`qa_shots/native/locked-mvp-smoke-20261002/REVIEW.md`.

Menu entrance repair: actual **90 passed / 3 failed RED → 93/0 GREEN** in the
existing frontend fixture, covering live 2→1-column reflow, unmanaged rise/fade
and lifetime guards. Repaired runtime is 524 files / `dc50ecd6…`. Fresh full suite
then finishes terminal0, **105 PASS / 9 SKIP / 0 FAIL**, evidence
`qa_shots/tests/waddle-wars-tests-19908-19383/`; three NumPy classes separately
**10 / 0 / 0** on the same snapshot. No script/import or freed-capture errors;
known shutdown warnings, six real-window groups and one internal geometry skip
remain. Native post-fix rendering/release-parity smoke are still open.

Earlier fresh-cache full local suite: exit **0**, **105 PASS / 9 SKIP / 0 FAIL**,
retained at `qa_shots/tests/waddle-wars-tests-78021-1154/summary.txt`.
This run binds the earlier 524-file runtime, including the native leaderboard
guard. Source hash:
`1951ebdecfdea4aa8618a8f26d98c28f666020e7c10905d67424355ce7d98c45`.
All five courses, runner/churn, tutorial, endless, Grand Prix and time-trial
ghost simulations pass. Three NumPy skipped groups subsequently pass their exact
existing classes (**10 tests / 0 skips / 0 failures**, 1.864 seconds); preserve
the original summary. Six real-window groups remain unrun, and the passing host
runner-day geometry group contains one additional internal skip. Known headless
ObjectDB/resource teardown warnings remain, not clean stderr or memory acceptance.
Focused runner platform passes **264 / 0**, including GUI Resume and repeat touch
cycles; native offline policy passes **44 / 0**, runner slide **85 / 0**.

Bounded actual Compatibility follow-ups pass orientation, **72 menu layouts + 24
inset/rotation cases**, and **390 race HUD/touch rectangle checks**. The old HUD
fixture emitted nil-manager script errors despite green assertions; a test-only
inert real roster/course repair passes without those errors. Live portrait runner
loading/Pause/GUI Resume/forced death/GUI Retry passes **46 / 0**, 15 actual PNGs.
Synthetic warmup fails **3 / 5**; diagnostic foreground/partial-trace revision is
not yet engine-run. Landscape loses focus at **2.682 seconds**, then no more
draws while process frames continue; loader/recovery never reaches play. Neither
gate is accepted, and further rendered runs stop pending foreground availability.
Atlas/dusk window skips stay deferred. No full-suite rerun for excluded test/
harness-only changes; no deadline, workload, assertion or error gate weakened.
Known shutdown warnings are not memory/performance proof. Current receipts:
`qa_shots/native/mvp-critical-path-20261002/REVIEW.md`.

Earlier suite's freed-capture error is repaired, not whitelisted: actual cloud
teardown reproduces it (**5 passed / 3 failed**) before the target-bound callback;
fixed lifetime test is **8/8** with empty stderr, including pause semantics.
Native account/purchase policy fixture passes **27/27** with no simulated
auth/HTTP/billing dispatch and unchanged earned/cached saves. It retains known
headless shutdown warnings, not clean stderr. Review/logs:
`qa_shots/native/mvp-critical-path-20261002/REVIEW.md`.

Shared UI focused gates: **109/109** headless loader recovery; actual-draw warmup
regression **6/8 RED → 8/8 GREEN** with original wall-clock watchdog intact;
**72 existing layouts + 24** inset/scale/rotation regressions pass with zero
script/import errors. Logs:
`qa_shots/native/mobile-loader-layout-20261002/`.
Android emulator smoke uses old build 5, not these fixes; receipt and exclusions:
`qa_shots/native/android-local-smoke-20261002/receipt.json`.

Owner subsequently narrowed MVP QA to **simulators/emulators only**. After
local code gates, test current-source Android emulator APK and iOS simulator app:
cold start, core runner actions/retry, race/tutorial, orientation/safe areas,
suspend/resume and local save persistence. Preserve signed release packages;
device IPA/AAB files are not directly simulator-installable. Capture exact
source/build/runtime provenance, and label QA derivatives explicitly.
Physical-device testing is waived for this MVP, not passed. No claim of actual
phone/store-installed performance, physical touch or 16-KB runtime acceptance
follows. Stop physical-device polling; preserve earlier observations below.

Android 7 unsigned export and iOS 5 unsigned export contain the previous
`b316cd77…` runtime, before touch Pause. Android signing fails at the app-specific Keychain
password read even after default-Keychain metadata reports unlocked; iOS's one
manual archive fails at CodeSign with `errSecInternalComponent`. All failed
attempts remain preserved. No signature/IPA, device, Play/TestFlight or store
acceptance follows from successful export. Exact hashes and failure evidence:
`qa_shots/native/mvp-critical-path-20261002/REVIEW.md`.
The owner subsequently confirmed restart. One actual app-specific Android
key-use probe and one exact-identity iOS signing/strict-verification probe pass.
They establish signing access, not current artifact/device/store acceptance.
At the signing-restart checkpoint, Android **8** AAB and iOS **6** archive/IPA pass canonical offline
verification from that frozen source; old failed candidates remain unchanged.
Android signature/payload/upload-pin/bundletool/16-KB structural checks pass.
iOS strict signature/profile/title/ARM64/native linkage/frozen PCK and IPA
resource equivalence pass, with actual Xcode terminal success in both steps.
Three real verifier mismatches have bounded RED/GREEN regressions: Xcode's
compiled-empty localization, OS hard-linked tool dispatchers, and identical
embedded-profile permissions tightening from 0644 to 0600. No generic title,
link, permission, signature or resource waiver. Entire release-tool host suite:
**499 tests / 0 skips / 0 failures**, terminal 0. Game runtime remains unchanged;
no full game-suite rerun or device/store/performance claim. No Keychain policy
change, key/profile replacement, upload or deployment. `store_ready: false`.
Evidence: `qa_shots/native/mvp-signing-restart-20261002/REVIEW.md`.

Listing-only follow-up: native preparation/listing/icon/policy-host tests pass
**20 / 0 skips / 0 failures**, terminal 0. Apple factual draft fields persist
after Save and reload; Google reports package availability in an unsubmitted
creation form, with both legal declarations unchecked. Neither portal check is
upload, store approval, physical-device smoke or performance acceptance. That
portal/listing checkpoint did not change runtime or repeat a native export.

Subsequent source change: native successful leaderboard replies now expose only
numeric ranks/scores and authored aliases, not remote free text/metadata. Browser
and failure payloads, request routes, score/save mechanics and callback lifetime/
auth-generation protections are covered by the expanded policy fixture. Fresh
isolated Godot **4.7.1** import passes with zero script/import errors;
`native_offline_mvp` passes **44 / 0**, terminal 0. Immutable evidence:
`qa_shots/tests/waddle-wars-tests-50538-28305/`.
Known shutdown diagnostics remain (two ObjectDB instances / one resource), as in
the earlier 27-check fixture; not clean stderr or memory acceptance. Runtime at
that guard checkpoint: **524 files** /
`1951ebdecfdea4aa8618a8f26d98c28f666020e7c10905d67424355ce7d98c45`.
Client SHA-256:
`7edde3a0e04ad5ab8a5af7bdcff4aa629dbfda998208cc6ca35d8139d01385b2`;
fixture SHA-256:
`b64bf0328304c60dec446b1aa632fc2b5b4ead736fbb4d6f62942b97d6db7700`.
Import log SHA-256:
`000e1810e0124dc171825f74887ec3b8639b0a64acbef8fd7b51db8e04907cd7`;
fixture log SHA-256:
`54197e8f269f234913d4c05dc6da6489ed8f56f73b26bbb7f2a9d473df53d032`.
The earlier full suite and accepted signed Android 8/iOS 6 packages bind the
preceding `2d3518aa…` baseline, not this source revision. The later current-source
full suite is recorded at the top. Android QA build 9 and iOS export 7 at that checkpoint
are separate candidates, not replacements for those signed release packages;
simulator execution and store/performance acceptance remain open.

Owner explicitly chose public contact **ninjaconsultingllc@gmail.com**, with
Chancey's publisher **Ninja Consulting LLC**. Final local contact/listing/draft
page checks pass **20 / 0 skips / 0 failures**, terminal 0:
`python3.12 -m unittest discover -s tools/release -p test_native_release.py -v`.
Listing SHA-256:
`5ca6d2d1bedac959ae7545e958da47bd2a28b542c51826b26f6fe9f7492730c4`.
Privacy/support URLs remain null and pages unpublished. No portal update or
public publication follows from this local check. Detailed provenance and open
disclosure gates: `tools/release/privacy_review.md`.

Read-only privacy follow-up now establishes per-service production Workers
Logs/Traces disabled on both hosts. It also binds accepted iOS6 executable
imports to the recorded artifact pin; imported metadata/capacity/clocks do not
prove eligible purpose or actual runtime use. No timestamp/disk-display or
capacity-sensitive behavior was established in inspected app source. Reason
eligibility, SDK behavior, host/provider/support retention and device/store
acceptance remain open. No native rebuild, whole-suite rerun, API removal or
live logging-setting mutation. Evidence:
`qa_shots/native/privacy-readonly-20261002-1928Z/REVIEW.md`.

Pinned engine-source follow-up changes only the native preset generator and its
existing host regression suite. A new file/timer mask case first fails on both
missing options (one test / two failing subtests, exit 1); after explicit
`C617.1`/`35F9.1` masks, the full `test_native_release.py` suite passes **21 / 0
skips / 0 failures**, exit 0. No engine export, signing, device execution or
full release-suite rerun. Disk-space reason eligibility remains open; current
iOS6 manifest still has preceding defaults. Outcome and exact source hashes:
`qa_shots/native/privacy-preset-20261002-1939Z/REVIEW.md`.

Privacy-page follow-up retains noindex/unpublished notices and null release
URLs. The new dated-host-facts/provider-caveat case first fails on the old draft;
updated page plus exact provider-link allowlist passes **22 / 0 skips / 0
failures**, exit 0. Browser store edit is blocked before observation by an open
extension UI, so no save/publication claim. Engine Movie Maker call-path review
does not establish shipped-mode activation or disk-reason eligibility. Runtime,
native packages and their preceding acceptance receipts are unchanged. Receipt:
`qa_shots/native/privacy-host-draft-20261002-1944Z/REVIEW.md`.

Subsequent owner instructions resolve support responsibility and authorize a
regular retention policy. Both unpublished pages and the operating procedure
now state publisher active-mailbox deletion within 90 days of resolution, with
limited documented legal/fraud/security exceptions and no provider-backup
deadline. Focused `test_native_release.py` suite passes **23 / 0 skips / 0
failures**. No Gmail changes or publication. Chrome-popup dismissal is now
authorized, but the first native-control attempt reports the Mac locked; no
UI action occurred. Simulator UI QA waits for manual unlock while the explicit
iOS simulator bridge build path is prepared locally. No physical testing planned.

Subsequent bounded simulator builder gate completes: **13 mocked tests / 0
skips / 0 failures**, then consolidated release-tool suite **515 / 0 skips /
0 failures**, terminal 0 (10.138 seconds). Exact pinned Git checkout is clean;
header-only SCons plan generates four headers, not an engine. One actual
`--variant simulator` build produces separate debug/release libraries, terminal
0. All four object build-version records identify IOSSIMULATOR / iOS15 / SDK26.5.
Actual production installer rejects this receipt with expected terminal 1 and
leaves its new destination absent. Installed device libraries/signatures remain
unchanged. No iOS app link/run or Android simulator play is established here.
Receipt: `qa_shots/native/simulator-bridge-20261002-2020Z/REVIEW.md`.

Current-source packaging follow-up: Android QA build9 exports its debug-signed
APK successfully from `1951ebde…`; actual signature, launcher manifest/title,
full packaged resources and 16-KB structural checks pass. iOS canonical export7
succeeds from the same source. A separate ARM64 simulator derivative fails
with `_main`; actual shipped Godot release simulator archive is x86_64 only,
despite its XCFramework metadata. That failed result bundle is retained.

Matching x86_64 simulator-only builder support passes **18 mocked tests**, then
the consolidated release-tool suite passes **520 tests / 0 skips / 0 failures**,
terminal 0, 11.617 seconds. One actual matching bridge compilation and one fresh
separate simulator Xcode app build both finish terminal 0. Xcode result bundle:
zero errors, one duplicate `-lc++` warning. Frozen PCK is unchanged; production
plugin/installer and accepted signed Android8/iOS6 packages remain unchanged.
Neither QA app has been installed/run. Foreground simulator play/captures await
manual unlock; there are no physical, phone-performance, store or purchase
acceptance claims. Evidence and exact pins:
`qa_shots/native/simulator-packages-20261002-2040Z/REVIEW.md`.

Unpublished provider-request guidance follow-up: new case first fails on five
missing wording checks, then full preparation/page suite passes **24/24** and
consolidated release-tool suite passes **521 tests / 0 skips / 0 failures**,
terminal 0, 9.758 seconds. Actual service-specific provider/SDK/audience gaps,
draft notices and null public URLs stay intact. No runtime changes, game-suite
rerun, new package, preview or publication. See `tools/release/privacy_review.md`.

## October 2 bounded R2 retopology — rejected, no runtime change

Final `test_hero*.py` suite passes **444 normal + 444 optimized**, zero skips/
errors. Logs: `qa_shots/hero/unified_face_retopology_all_host_20261002.log` and
`qa_shots/hero/unified_face_retopology_all_host_optimized_20261002.log`.
Added gates cover stored-edge preflight, exact reversible solver units, fixed
approximate sizing, source/shape contracts and saved component/geometry recovery.
Host fixtures are not actual Blender, fidelity, motion or FPS acceptance.

Actual drivers all exit 1: raw preflight cancellation, rejected private weld,
over-budget first unit-conditioned solve, then one fixed-size correction. Last
solve returns 6,591 quads / 13,182 triangle equivalent below BODY cap 14,000, but
interpolation rejects `nearest projection does not lie on its source triangle`.
No completed projected cage, shape/contact audit, LOD1, rigged GLB, candidate
audit, atlas or capture. Unit conditioning itself passes exact coordinate/
topology checks; that does not approve the cage. No limit waiver, retry loop,
new anatomy variant or runtime promotion. Automatic tuning stops here.
Evidence: `qa_shots/hero/unified_face_retopology_20261002_units02/REVIEW.md`.

Fresh runtime stays 524 files / `f3695235…`; Android 5 signed and iOS 4 unsigned
export remain current. No browser investigation, device play, store operation,
native rebuild/signing retry, game-suite rerun or remote CI. Next art boundary
needs clean authored topology and facial correction, not automatic tuning.

## October 2 bound R2 transfer — exact pins fixed, budget infeasible

Fresh unchanged R2 source capture exits 0 and binds 21 dependencies, three
inspected PNGs and the saved blend. Adjacent candidate-only review remains
unapproved for geometry/fidelity/production. Earlier incomplete capture receipts
are not rewritten. Source, sidecars, review and image digests are validated
before source-study transfer, without executing mutable construction helpers.

Final consolidated `test_hero*.py` host suite passes **409/409**, zero skips/failures:
`qa_shots/hero/unified_face_all_host_tests_final_20261002.log`. Blender Python 3.13
passes **31/31** source-study tests:
`qa_shots/hero/unified_face_source_study_blender_python_tests_20261002.log`.
Identical source bytes produce different AST serialization in host Python 3.12
and Blender Python 3.13. Tests compare complete AST transformations on both,
retaining the original frozen AST digest assertions on Blender's runtime.
Optimized host run additionally passes **409/409**, zero skips/failures:
`qa_shots/hero/unified_face_all_host_tests_final_optimized_20261002.log`.

Actual `unified-face-r2-v1` candidate build exits 1 with
`reduction moved or removed hard-pinned source cover vertices`; no completed
GLB/audit, source atlas or moving capture is accepted. Failure is retained at
`qa_shots/hero/unified_face_candidate_20261002.log`. Passing host fixtures do
not prove Blender reduction, fidelity or rendered/browser/mobile performance.

One bounded pin-aware cleanup repair preserves exact vertices/triangles in four
actual phases: 41,820 protected vertices / 81,814 protected triangles, zero
missing. Body after reduction is 84,031 triangles against target 14,000. Protected
triangles alone exceed the whole-hero 25,000 ceiling; no accepted budgeted asset
can result from this exact-copy policy. Driver later exits 1 at unresolved tangent
charts. No tangent retry or atlas bake follows; no geometry requirement is waived.
Final helper rejects this impossible necessary condition before reduction; its
host tests are not a claim of another completed Blender run. Review and next gate:
`qa_shots/hero/unified_face_candidate_20261002_repair01/REVIEW.md`.

Runtime remains 524 files / `f3695235…`; signed Android 5 and unsigned iOS 4
export remain current. No game regression rerun, native rebuild, signing retry,
store upload, device play, game-browser performance investigation or remote CI.

## October 2 unified-face source construction — no runtime promotion

Blender 5.2.0 LTS completes R1 and one targeted R2 run with two CPU threads,
48 samples, retained stage and original six feather maps. Both driver exits
are 0; all six actual views were inspected, and all eight saved image/source
output hashes independently verify. R2's side eye and skull improve; orbital
cuffs/gaze, side iris and bill still fail the reference. No export or fidelity
approval follows from these offline images or source tests.

After repairing the launcher's missing imported paint-helper input binding,
bundled Python passes **23 normal / 23 optimized**, zero skips/failures: 12
unified construction/dependency guards plus 11 Z13/Z14 legacy guards. Historical
R1/R2 receipts omit that helper and explicitly remain incomplete; the fix is
for future captures, not a retroactive frozen-input approval. Evidence/logs:
`qa_shots/hero/unified_face_source_20261002_r2/REVIEW.md`,
`qa_shots/hero/unified_face_source_20261002_host_tests.log` and
`qa_shots/hero/unified_face_source_20261002_host_tests_optimized.log`.

Fresh canonical runtime rehash is unchanged: 524 files / `f3695235…`.
Android 5 signed and iOS 4 unsigned export still contain V11. No native rebuild,
full-game rerun, device/Play/TestFlight/purchase acceptance, browser game-lag
test or remote CI was performed for excluded source-tool/test/doc changes.

## October 2 penguin capture correction and bounded art review

Capture-only orientation fix passes eight actual Compatibility sequences:
front/chase × portrait/landscape × fixed-step 30/60 FPS, one second each.
Independent verification checks all 360 PNG headers, recorded dimensions,
sample times and unchanged live GLB pin. Pixel sizes are exactly 720×1280 and
1280×720. Contact sheets preserve aspect; whole torso/head visibly rocks.
This does not measure rendering FPS or approve all contacts/transitions,
in-game composition or physical Android/iOS performance.

Bundled Python `test_hero_v12*.py` exits 0: **188 pass / 0 skip / 0 fail**,
including three added source guards. Separate Z13/Z14 tests pass **11/11**;
system Python's earlier missing-NumPy invocation did not pass. Blender 5.2.0
source Z14 completes three actual views, but visual review rejects remaining
face defects. No new live art or animation change. Evidence:
`qa_shots/hero/live_v11_orientation_fixed_20261002_REVIEW.md` and
`qa_shots/hero/v12_source_proof_z14_20261002/REVIEW.md`.

Canonical runtime rehash remains 524 files / `f3695235…`; current Android 5
signed AAB and iOS 4 unsigned export are unchanged. Expanded full-game suite
was not rerun for excluded QA/doc changes. No browser investigation, mobile
install/store upload/purchase or signing retry was performed.

## October 2 standalone public request page

Combined Node backend/page/transport/privacy regression exits 0: **127 passed /
0 skipped / 0 failed**. Page's 19 focused fixtures execute the exact embedded
script. Isolated `./run_tests.sh account_deletion` exits 0 with **5 PASS groups /
244 checks / 0 SKIP / 0 FAIL** (5 web transport, 19 public page, 130 durable cache,
44 client, 46 UI). Summary:
`qa_shots/tests/waddle-wars-tests-14128-14715/summary.txt`.

Installed Chrome 154.0.8037.98 uses a fresh synthetic profile, routed fake Clerk
and API responses, never the owner's browser session. Eight enabled/disabled
layouts pass horizontal containment and 48-pixel button bounds at 320×568,
390×844, 844×390 and 1280×800. Three representative captures visually inspected.
Actual IndexedDB two-tab race yields one synthetic POST and one persisted owner
receipt; reopening signed out uses receipt-only GET, and unknown status sends no
new POST. Strict durability hint is supported, not proof against storage loss.
Zero page errors/unexpected network requests. R1 failed before browser startup
because the output parent was absent; retained diagnostics precede successful R2.

Independent source review repaired cancellation during storage commit, strict
write durability and exact known-unsent cleanup. Existing/retired/replaced and
attempted/ambiguous requests remain fenced. No new provider/config/migration,
runtime, signing, game/performance test, device install, live operation or deploy.
Receipt: `qa_shots/commerce/public-deletion-page-20261002/receipt.json`.
Real Clerk/CSP/OAuth and provider/browser/device lifecycle are still unaccepted;
disabled pre-release page is not a public compliant deletion service.

Game source remains `f3695235…`, matching retained Android 5/iOS 4 export and prior
102 PASS / 8 SKIP full-game snapshot. Added host group is registered; entire
expanded harness was not rerun, only its affected focus and backend consumers.

## October 2 current mobile refresh — Android 5, iOS 4

New **480/480 release-tool tests**, zero skips/failures, pass before sequential
actual builds. Android build 5 exits 0 and passes mandatory offline signature,
774-payload coverage, exact existing public upload pin, unsigned-to-signed game
payload equivalence, complete bundletool validation, actual package/API/billing/
release flags, Godot resources and 16-KB structural packaging. All 42 launcher
resource configurations match **Waddle Wars: Penguin Panic**; installed-device
label and real 16-KB runtime remain untested.

iOS build 4 export exits 0; strict pinned-receipt/source candidate gate passes
585 frozen paths and 11 canonical UID sidecars. Exported launcher title and PCK
hash verify. No archive/signing retry occurred with the Mac still locked, and no
new signing key/profile or security change occurred. Current archive/IPA remains
unaccepted. Both candidates use the unchanged 524-file `f3695235…` snapshot tested
below; no gameplay regression rerun is inferred from packaging checks.

Configured ADB query starts the ordinary daemon and returns zero attached
devices; Xcode lists the physical iPhone offline. No simulator/emulator, device
install, active gameplay, purchase/provider operation, store upload or remote CI.
Receipt: `qa_shots/native/mobile-recovery-refresh-20261002/receipt.json`.
Android AAB SHA-256:
`249ef4408f28a784c106ba0871684581a0bc1b34a181b83986477fb55e1c3ff1`.
Device/Play/TestFlight/purchase/retention/rendered/performance/art gates stay open.

## October 2 receipt recovery — final frozen regression

Final isolated `./run_tests.sh` exits 0: **102 PASS groups / 8 SKIP / 0 FAIL**,
110 groups total. Exact unchanged runtime fingerprint (524 files):
`f369523552bc42308fdee8dcca20ae79ee36a41a66ae542b50ab4f5f24d60f11`.
Summary: `qa_shots/tests/waddle-wars-tests-5147-23885/summary.txt`.
Receipt: `qa_shots/commerce/deletion-recovery-20261002/receipt.json`.

Recovery-specific tests pass **220 Godot assertions** (130 durable cache,
44 client, 46 confirmation/UI), **32 real-SQLite backend tests**, **15 cloud-save
privacy tests** and **5 actual web-bridge transport fixtures**. They cover atomic
pre-POST persistence, lost reply/restart/expired-auth recovery, immutable receipt
ownership and transaction rollback, header-only no-redirect transport, unknown
status retaining the fence, owner-switch isolation, legacy authenticated negative
status, signed-out cache repair and exclusion from cloud/local progress copies.
These are local synthetic provider/transport tests, not live Clerk/D1 or devices.

Initial focused cache run failed 14 assertions; JSON integer/float normalization
in exact authorized journal readback was repaired without weakening rollback
protection. Failure remains at `qa_shots/tests/waddle-wars-tests-99972-4510/`;
corrective 130-assertion run at `qa_shots/tests/waddle-wars-tests-703-29914/`.
An earlier full pass is retained at `qa_shots/tests/waddle-wars-tests-1055-11063/`;
the final pass above includes all subsequent client and cloud-privacy changes.

Three NumPy geometry groups and five real-window/renderer groups are skipped;
`runner_day_geometry` also reports one internal dependency skip. Fifteen executed
groups retain known ObjectDB/resource-in-use shutdown diagnostics in raw stdout.
Import/parser gate and unexpected-error checks pass; this is not a zero-warning
shutdown or rendered/device acceptance claim. Art integrity reports **103
production_ready=false assets** and does not approve visual fidelity.

Deletion and live sales remain disabled; no deploy, provider request, purchase,
browser test, signing/build retry or remote CI ran. Retained Android build 4 and
iOS build 3 export are older `bc274252…` snapshots and require coordinated refresh
before device/store acceptance. Historical sections below retain their original
snapshot results, not latest-source build claims.

## October 2 current iOS export, safe Android lane and local archive gates

Complete release-tool suite now passes **480 / 0 skips / 0 failures / 0 errors**;
Python-optimized iOS artifact/orchestration suite passes **98 / 0 skips / 0
failures**. Python syntax and tracked diff whitespace checks pass. Synthetic
fixtures perform no signing, Keychain, Xcode, network or device operations.
Failed intermediate fixture runs remain alongside the final logs; every
reproducible issue was repaired before the final full pass.

Current iOS 1.0.0/build 3 export exits 0 and passes strict frozen candidate checks:
524 runtime files, source `bc274252…`, exact Penguin Panic title, unchanged pack,
and 11 separately bound import-generated `.gd.uid` files. Export receipt stays
unchanged; a supplemental import-metadata receipt records those sidecars. New
canonical exports record them directly without changing source provenance.
Exact existing public signing identity metadata and trusted profile pins pass
preflight. One actual archive reaches `CodeSign` but remains idle while Mac is
locked; processes are stopped and all outputs/logs preserved. Terminal reports
`BUILD INTERRUPTED`, wrapper exits 1. No successful current archive/signature or
IPA export is claimed. No new iOS key/profile or lock/Keychain setting change.

Android 1.0.0/build 4 AAB hash was rechecked unchanged; no repeat build/signing.
Its default Fastlane lane now invokes only the isolated fresh upload-signing
workflow, with 18 mock-Fastfile tests and actual offline eight-lane discovery.
Play registration, independent key recovery, device/16-KB runtime and real
purchase/restore/refund/account-isolation gates remain open. Both platforms use
the earlier unchanged full-game test snapshot (101 PASS / 8 SKIP / 0 FAIL); known
skips and shutdown warnings remain. No browser test or remote CI ran.

Receipt and retained logs: `qa_shots/native/ios-current-release-20261002/receipt.json`.

## October 2 actual upload-signed Android candidate

Current full-game Android **1.0.0/build 4** passes mandatory offline release
verification: actual JAR signature/774 signed payloads, exact public DER pin,
unchanged unsigned game payload, full bundletool validation and module inventory,
API24/36/ARM64/billing/release flags, game resources and 16-KB structural packaging.
Bundled launcher title matches **Waddle Wars: Penguin Panic** in all 42 resource
configurations. No parser/import/export error markers occur in either retained
engine log. Signing password never reaches Godot/Gradle or logs.

Final `python3 -m unittest discover -s tools/release -p 'test_*.py'` passes
**353 tests / 0 skips / 0 failures**; final Swift typecheck exits 0 with zero
diagnostics. Coverage includes locked-Keychain/path/source guards, mocked first
key/signing boundaries, immutable unsigned-to-signed payload, real template
profiling-policy fixtures, actual JDK report structure and narrow asset metadata
support plus full bundle validation. Host fixtures themselves never access keys
or build/sign real artifacts; the subsequent two actual exports are recorded
separately. First rejected build 3 and all diagnostic attempts are preserved;
one concrete corrected build 4 used the same upload key.

Receipt: `qa_shots/native/android-upload-release-20261002/receipt.json`.
AAB SHA-256: `fa386ca7dbb46d7037264f27ece83873a77e10c6dbc166eddd55db1f5e185a10`.
Its unchanged 524-file source snapshot matches the full isolated suite below
(`bc274252…`, 101 PASS / 8 SKIP / 0 FAIL); no game rerun was needed for tool-only
edits. Known skipped/rendered/device/shutdown gaps remain explicit. Android is
now refreshed to that source; iOS's prior retained candidate is not refreshed.

No Play app creation/certification/upload, real Android installation/gameplay,
16-KB runtime, billing purchase/restore/refund or off-device key recovery passed.
No browser performance run or paid remote CI was performed. Offline artifact
acceptance is a launch milestone, not store/device/fidelity acceptance.

## October 2 shared account-deletion client and confirmation

Fresh isolated `./run_tests.sh account_deletion` passes **3 groups / 142 assertions /
0 skips / 0 failures**: 67 cache, 30 lifecycle-client and 45 confirmation/UI.
Evidence: `qa_shots/tests/waddle-wars-tests-77122-610/summary.txt`.
Coverage includes durable pre-dispatch fencing, corrupt/unwritable journal and
backup recovery, ambiguous replies, owner/session changes, delayed auth/cloud
callbacks, preserving other accounts and earned progress, and safe-area/resize
confirmation behavior. The initial UI geometry failure is retained under
`qa_shots/tests/waddle-wars-tests-73738-14102/`; container settling was repaired
before the final focused pass.

Three actual-window Compatibility captures pass **39/39 checks**, zero failures:
320×568 at UI scale 1.4, 390×844, and 844×390. Settings and modal PNGs were visually
reviewed. Evidence: `qa_shots/commerce/account-deletion-client-20261002/` with
`small-phone-r2`, `phone-portrait`, and `phone-landscape` JSON/PNG/log files.
The original `small-phone` capture remains as failed evidence: 0.12 logical-pixel
scroll-edge rounding exceeded a strict containment comparison. The fixture now
allows at most one logical pixel and independently rejects larger clipping;
modal safe-area checks are unchanged. Actual/logical sizes are recorded separately:
320×568 / 572×1016, 390×844 / 800×1731, 844×390 / 1729×800. These desktop windows use
synthetic disabled services and forced insets, not real iOS/Android touch/device
or signed-in provider acceptance. No auth, billing or deletion was dispatched.

`account/deletion_enabled=false` remains explicit. Lost replies followed by an
expired/deleted provider identity still need a reliable status-recovery path;
public request page, retry scheduling, lawful retention and real lifecycle/store
acceptance remain open. Neither native candidate was refreshed. The full-suite
harness now retains each Godot runtime's stdout **and stderr**, preserving engine
exit status and rejecting unexpected errors from either stream. Known shutdown
resource diagnostics remain explicit release gaps, not hidden clean-log claims.

Complete latest-source isolated `./run_tests.sh` exits 0 with **101 PASS groups /
8 SKIP / 0 FAIL**, 109 groups total. Frozen runtime SHA-256:
`bc27425225a36bcc75a5c1db5c28e76e82a9f11330ed7ed0cd0c08f10f674863`
(524 files), unchanged after completion. Summary:
`qa_shots/tests/waddle-wars-tests-79965-564/summary.txt`.
All five course simulations, runner simulation/churn, tutorial, endless,
time-trial/ghost and Grand Prix pass. Android signature/build-helper fixtures
pass 42/21 host tests, not a real release-signed AAB. Complete console retained:
`qa_shots/commerce/account-deletion-client-20261002/full-regression.stdout.txt`.
Eight NumPy/window-dependent groups are skipped; the geometry host group also
skips one Blender-only guard. Existing ObjectDB/resource-in-use diagnostics appear
in 13 groups. Expected corrupt-save/negative-fixture, review-preview and texture
inspection warnings remain. No unexpected script/resource or engine error was
accepted by the harness, but this is not clean-shutdown or launch acceptance.
Exact source/test/evidence hashes, diagnostic list and remaining gates:
`qa_shots/commerce/account-deletion-client-20261002/receipt.json`.

## October 2 account-retirement and Android release gates

Isolated `./run_tests.sh backend` exits 0 with **3 PASS groups / 0 SKIP / 0 FAIL**:
52 commerce, 11 cloud-save privacy and 21 account-retirement tests (84 total),
clean isolated import. Evidence:
`qa_shots/tests/waddle-wars-tests-69519-20204/summary.txt` and sibling host logs.
Four final public-name privacy tests also pass separately with both streams
retained. Retirement fixtures use transactional SQLite, synthetic provider
responses and in-memory signed test JWTs; no live credentials/accounts/data.
They cover atomic erasure/rollback, 16 write fences, stale JWT denial, delayed
fulfillment/refund reversal/native-auth races, exact destructive confirmation,
provider-failure queues and wrong-instance/rotated-key 404 handling. Production
deletion remains disabled/undeployed, financial proof retained, full lifecycle
acceptance incomplete. Receipt:
`qa_shots/commerce/account-retirement-20261002/receipt.json`.

Final complete release-tool host suite passes **199 tests / 0 skips / 0 failures**.
Final isolated `android_release` groups pass **42 signature / 21 build-helper
tests**, with clean fresh import. Synthetic cases exercise AAB inventory,
signature coverage, public pin, manifests, 16-KB gate linkage, source/tool mutation,
pre-export prerequisites, symlink rejection and verifier failure normalization.
No genuine AAB was signed/verified, JDK or bundletool executed, key generated,
device tested or store upload performed by these fixtures. Ruby/Bash/Node syntax
and tracked diff whitespace checks pass; actual Fastlane execution remains open.
Receipt: `qa_shots/native/android-release-gate-20261002/receipt.json`.
These focused host results supplement the frozen broad regression below; they
do not establish latest-tree whole-game, browser, mobile performance, privacy,
purchase or launch acceptance. Retained native candidates were not rebuilt.

## October 2 focused checks and browser scope

`perf_ticker_clock` passes 25 checks, clean fresh import and runtime diagnostics.
`visual_library_live_detail`, `settings_governor_state`, `runner_live_quality`,
`runner_stream_staging` and `runner_dusk_warmup` pass 195/70/39/72/33 checks
respectively (409 total). One associated raster fixture explicitly skips under
headless; runner live-quality emits only its known unapproved DAY preview warning.
Receipt: `qa_shots/runner/resident-auto-detail-20261002/receipt.json`.

U7 browser trace confirms an Apple M2 ANGLE Metal context. It is diagnosis-only:
its retained timing/input gap cannot distinguish game CPU/GC, governor buffer
reallocation or automation screenshot interference. It does not prove sustained
performance or Chrome close-button latency. Require an interactive no-build,
no-screenshot timing window with biome transitions and retries, not an unattended
short crash-out. Owner's apparently smooth play is observational evidence, not
the full launch soak. Owner's cost-constrained goal caps remaining browser
investigation at one two-minute cumulative active-play check with three retries,
followed by at most one targeted fix/retest if needed. A clean run ends investigation;
further performance investigation after a failed retest requires owner direction.
Original launch acceptance gates remain separate, not an unlimited profiling loop.
Owner shortened this from five minutes because the former slowdown was normally
obvious within one to two minutes. The old five-minute check is superseded.

Cloud-save account/cache boundary passes **11 backend tests / 21 Godot assertions**
in an isolated project/user directory, zero skips/failing groups:
`qa_shots/tests/waddle-wars-tests-60547-13660/summary.txt`.
Tests cover actual upload/adoption paths, preserving offline local caches and
earned progress, rejecting imported purchase grants, authenticated cross-user
isolation, UTF-8 limits and filtering legacy responses without DB purge.
The initial new fixture failed type inference; corrected and retested, with
failed evidence retained at `qa_shots/tests/waddle-wars-tests-60315-12170/`.
No production/provider calls occurred. This is not account-deletion completion,
real entitlement verification, native-build refresh or purchase acceptance.

Latest complete isolated cloud-boundary regression exits 0 with **95 PASS groups,
eight SKIP groups, zero FAIL groups**, 103 groups total:
`qa_shots/tests/waddle-wars-tests-62590-8436/summary.txt`.
This froze runtime `632435bb…`, before subsequent avalanche HUD/menu changes.
Those changes pass focused `runner_retry_hud` **38/38**, zero skipped/failing
groups, clean isolated import:
`qa_shots/tests/waddle-wars-tests-64368-25254/summary.txt`.
Later runtime `f95e42b5…` is not claimed to have a complete latest-tree suite pass.
Actual-window Compatibility handoff at 540×960 subsequently passes **18/18**
ordering/visibility checks, zero violations; reviewed countdown objective and
initial gap capture under `qa_shots/runner/avalanche-readability-20261002/`.
Existing terminal shutdown warning reports 20 ObjectDB instances. This is not
touch-device, extreme-scale, landscape, performance or clean-shutdown acceptance.
Source review identifies objective/mission overlap risk at 360×640 and both scales
1.4; visual verification/fix remains open rather than claiming the matrix complete.
Eight skipped groups require NumPy or a real renderer/window; geometry also has
an internal Blender guard skip. Existing ObjectDB/resource shutdown warnings in
simulation console output remain; retained engine logs do not capture complete
stderr. Do not call full logs, device performance or launch memory acceptance clean.

The first enlarged repeat failed **94 PASS / 8 SKIP / 1 FAIL** at
`qa_shots/tests/waddle-wars-tests-60743-24831/summary.txt`. Its commerce fixture
implicitly expected cloud adoption to erase a legitimate cached entitlement.
Fixture now explicitly isolates baseline and checks native events preserve cache;
original no-local-grant assertion stays. Corrected focused commerce passes
**52 backend / 41 sandbox / 99 Godot** checks, no skips/failures:
`qa_shots/tests/waddle-wars-tests-62389-20223/summary.txt`.

Earlier complete isolated regression exits 0 with **90 PASS groups, eight SKIP
groups, zero FAIL groups**:
`qa_shots/tests/waddle-wars-tests-22770-21700/summary.txt`. No script parse or
ObjectDB/resource-leak diagnostic appears in retained logs. Expected corrupt-save
JSON diagnostics, negative-fixture warnings, unapproved DAY preview warnings and
texture-inspection export warnings remain; do not label every log error-free.
This run predates the final web advice host edits. Their final separate host
receipt passes **87/87, zero skips**, with ten scripts/eight required markers:
`qa_shots/runner/browser-acceleration-advice-20261002/receipt.json`.
Real-browser advice presentation QA is not performed; no performance claim follows.

Retained iOS 1.0.0/build 2 archive and exact signature/profile/entitlement/app-file
verification both exit 0. Three unused camera/photo/microphone purpose declarations
and their warnings are absent. Receipt:
`qa_shots/native/ios-signing-recovery-20261002/receipt.json`. StoreKit/auth linkage
is present, not device behavior. IPA, device, TestFlight, store and billing gates
remain open; no upload or new key occurred.

Subsequent retained local-only IPA export and public-artifact verifier exit 0:
`qa_shots/native/ios-ipa-local-20261002/receipt.json`. Strict signature, exact
profile/entitlements/identity and eleven resource hashes match the archive.
Xcode reserialized Info.plist without changing its complete values; unsigned
Mach-O bytes match except explicitly excluded code-signature payload/size.
Failed initial raw-plist comparison remains preserved. Apple account-session
expiry warning does not prevent local export; no login or export retry occurred.
Distribution IPA does not establish direct sideload, device, TestFlight or store
acceptance. Owner's smooth 30–60 second browser play leaves the single cumulative
two-minute stop check open without authorizing more profiling.

Android full-game DEBUG export produced a retained signed APK. Actual package/API
24/36/ARM64/billing manifest, native provider DEX/singleton, resolved Billing and
Billing-KTX 9.1.0, 296 source resources/remaps and 580 packaged files verify.
Standalone SDK zipalign 16-KB check exits 0; the initial ELF checker flagged
two RELRO ends. Historical receipt:
`qa_shots/native/android-debug-build-20261002.2skKQV/summary.json`. First Gradle
task-order failure and later verifier-only SDK-label correction are preserved;
no recompilation after the successful export. Device/16-KB runtime, release-key
continuity, store and actual purchase behavior remain unproven.

Verifier-only recheck now passes ELF/16-KB packaging for the **same APK**, with
no rebuild. The corrected RELRO rule checks containing writable LOADs and the
entire page-rounded protection envelope; it permits a whole-LOAD unaligned end
only when no mutable or executable bytes are caught outside RELRO. This matches
Bionic's explicit whole-LOAD exception, rather than deleting the RELRO gate.
Old failures/logs remain preserved. Receipt:
`qa_shots/native/android-relro-correction-20261002/receipt.json`.
Structural success is not a 16-KB device run, purchase test or store acceptance.
Read-only inventory finds no currently connected native test devices, no running
Android emulator and no installed dedicated 16-KB target.
Final corrected release-tool suite passes **150/150, zero skips**. New integrated
isolated `android_relro_structural` group passes **24/24**, clean import and
zero failing/skipped groups:
`qa_shots/tests/waddle-wars-tests-58235-20820/summary.txt`.
This focused receipt preceded the enlarged complete regression recorded above.

After final SDK-label correction, complete native release-tool host suite passes
**126/126, zero skips**. Newly integrated isolated helper groups pass **8/33**:
`qa_shots/tests/waddle-wars-tests-50882-24992/summary.txt`. Newly integrated
isolated commerce groups pass **52 backend tests, 41 sandbox-preflight tests,
97 Godot checks**, zero failures/skips:
`qa_shots/tests/waddle-wars-tests-54279-28183/summary.txt`. No engine/error/leak
diagnostic appears in these focused logs. Backend provider responses remain mocked;
SQLite's experimental-feature notice is not provider acceptance. The public-copy
guard rejects unknown and quoted/nested secret fields; undeployed sandbox template
intentionally fails preflight. No secret values, provider calls or deployment.
These focused receipts preserve their original snapshots; the subsequent enlarged
95/8/0 regression above includes these host groups, without implying provider E2E.

Store-record browser evidence: Apple accepted **Waddle Wars: Penguin Panic**,
created iOS record `6818416048` in **Prepare for Submission**, with no build upload
or review/publication. Apple access-saving warning left all existing team users
with access, matching selected Full Access. Android draft has matching title,
package `com.blubberandbyte.waddlewars`, Game / Free, and UI-confirmed available
package. Policy/export certifications remain unchecked; no Play record created.
Screenshots retained under `qa_shots/native/app-name-penguin-panic-20261002/`.

## Previous broad regression — 2026-10-01

Latest complete `./run_tests.sh`, after native refresh cancellation/public-name
safety and the isolated snapshot fix, exits 0 with **88 PASS groups, eight
SKIP groups, zero FAIL groups**. Evidence:
`qa_shots/tests/waddle-wars-tests-56518-699/summary.txt` and sibling host/Godot
logs. Commerce 97, online auth 19, audio 67 and retry HUD 25 assertions pass
without errors in those fixtures. End-save passes 33 assertions, but this
repeat's terminal output reports two ObjectDB leaks and one resource still in
use at shutdown; its retained Godot log omits those final stderr lines. Do not
label this full suite or the end-save teardown error-free. Existing shutdown
diagnostics elsewhere and eight skipped groups remain release gaps.

Later focused verbose end-save reproduction identifies the retained objects as
WAV playback and `sfx_snowball_hit`, not runner nodes. The save-only fixture now
isolates/restores incidental audio state and verifies runner/player/HUD disposal
after the required deferred-free frame: **37/37**, with no shutdown warnings in
`qa_shots/tests/waddle-wars-tests-72121-15199/runner_end_save.verbose.stdout.txt`.
Runtime audio/save behavior is unchanged. This does not verify real-audio
shutdown or soak; the complete suite above predates this fixture-only edit.

The first full run with the privacy fixture failed: **87 PASS / 8 SKIP / 1 FAIL**,
exit 1, `leaderboard_name_privacy`. Preserve
`qa_shots/tests/waddle-wars-tests-49157-4866/summary.txt`. Reproduction showed
all four privacy tests failing `ENOENT` because the snapshot lacked
`leaderboard/schema.sql`; no assertions were weakened. The harness now copies
that allowlisted schema and retains host stdout/stderr with failure-preserving
`pipefail`. A synthetic exit-7 case proved logging cannot turn failure into PASS.
Focused isolated privacy rerun passes **4/4**:
`qa_shots/tests/waddle-wars-tests-56132-27585/`. Direct combined backend tests
pass **56/56, zero skips**; the full isolated repeat also passes its 52 commerce
and four privacy host cases. Receipt, exact hashes and preserved failed TAP:
`qa_shots/native/account-safety-20261001/receipt.json`. Real provider responses
are mocked; no live sign-in/purchase/refund, deployment or account deletion was
performed. Already-issued JWT revocation and historical public names remain
separate work. Actual player saves were not used.

Earlier complete `./run_tests.sh`, after the runner audio and Google receipt-mode
changes, exits 0 with **87 PASS groups, eight SKIP groups, zero FAIL groups**.
Evidence: `qa_shots/tests/waddle-wars-tests-39126-7756/summary.txt` and sibling
fixture/import logs. New audio fixture passes 67 assertions; runner end-save
passes 33 and retry HUD 25, with no errors in those three fixtures. Its earlier
focused fresh-import/audio run also passed all 67 assertions in
`qa_shots/tests/waddle-wars-tests-38975-20606/`. Native release-helper tests are a
separate 80/80 host-only pass after 14 new profile-metadata regressions; neither suite establishes Chrome performance,
physical-device readiness or signed-store acceptance. Known shutdown warnings
and the eight skipped gates below remain open.

Earlier release-tool receipt:
`qa_shots/native/ios-profile-metadata-20261001/receipt.json`. Tests use synthetic
decoded plists only; no real certificate/profile, signing, SDK, device or CMS
trust gate was exercised.

Current public-only profile receipt:
`qa_shots/native/ios-profile-verified-20261001/receipt.json`. The downloaded
Waddle Wars profile now passes offline Apple CMS signature/trust policy and
exact app/team/certificate metadata checks; four invalid native-profile cases
are rejected. Full release-helper tests pass **86/86, zero skips**. The verified
profile is installed, but offline revocation freshness is not checked. The first
two manual archives exited 70 before compile because Xcode lacked iOS platform
support. Installing the official **iOS 26.5.1 + iOS 26.5 Simulator** bundle
resolved the destination; the third manual Release archive succeeds, exit 0.
Standalone strict signature verification, existing signer fingerprint, embedded
profile and app/team entitlements pass; `get-task-allow=false`. The compiled
StoreKit/auth bridge is linked and present. Evidence and prior failures:
`qa_shots/native/ios-signing-20261001/receipt.json`. Empty camera, microphone and
photo-library purpose-string warnings remain open. IPA export, physical-device
authentication/purchases, TestFlight and store acceptance remain pending. No
upload or new signing identity was created.

Supplemental rerun now covers the three NumPy-dependent groups from that exact
suite: **10 tests pass, zero skips/failures**, in 2.151 s using Blender 5.2's
standalone Python (not the Blender renderer). Receipt:
`qa_shots/tests/numpy-field-guards-20261001.json`. The original suite's 87/8/0
summary remains unchanged; five real-window/renderer groups still need execution.
These source shape checks do not establish visual fidelity.

Previous `./run_tests.sh` completed with exit 0 after account/restore hardening:
**86 PASS groups, eight SKIP groups, zero FAIL groups**. Fresh isolated import,
Godot logs and changed-source hashes are retained in
`qa_shots/tests/waddle-wars-tests-10365-6398/`. Full host/Godot output is retained
in `qa_shots/tests/launch-regression-20261001.log`. Actual player saves were not used.
Runner simulation/eight retries, all five race courses, tutorial, endless,
Grand Prix and time-trial ghost pass. Commerce passes 97 assertions and online
auth passes 19, with no engine/shutdown diagnostics in those two fixtures.
New host groups cover six web identity races, 44 backend/auth/notification cases
and eight Android integration helper cases. All 41 existing web-shell behavior
checks also pass. An earlier commerce fixture self-disposal error failed the
gate despite passing assertions; its log remains in
`qa_shots/tests/waddle-wars-tests-9919-27576/`. Deferred fixture cleanup fixed it.

Earlier broad evidence remains in `qa_shots/tests/waddle-wars-tests-53132-9983/`
(82 PASS/eight SKIP). Its three NumPy-dependent skips were separately executed
with Blender 5.2's bundled Python: all ten assertions passed. The latest full
run still reports those three as skips; the fresh supplemental rerun above
provides current separate coverage without rewriting that original result.
Five whole-fixture skips still require a real
window/renderer: hero atlas shader, dusk warmup raster, orientation recovery,
mobile UI and race HUD touch layout. The day geometry group also skips its
optional original-geometry baseline comparison when no baseline is supplied.
Known ObjectDB/resource shutdown diagnostics elsewhere remain unresolved.
No browser, visual, physical-device or launch acceptance follows from this run.

The previous 86-group receipt predates audio/Google mode changes; the earlier
87-group receipt covers those, but predates the latest account-safety/harness
changes. The 88-group repeat above covers the current source. Google v2 receipt
mode isolation also passed all 48 focused backend/auth/notification tests with
zero skips. Runner audio prewarm's
synthetic cache/isolation fixture is in the main suite
(`./run_tests.sh runner_audio_warmup`). Browser comparison remains open;
the headless fixture does not prove audio hitch causality or playback latency.

## Locked-Mac native preparation — 2026-10-01

Unsigned Android template/billing integration compiled using exact Godot 4.7.1
sources and resolved Google Billing/Billing-KTX 9.1.0. Provider DEX, merged
manifest and ARM64 library inventory were inspected. This contains no game
resource export, no signing and no device/purchase test. Preserve the first
missing-empty-asset-directory failure and the successful corrected attempt:
`qa_shots/native/android-integration-20261001/`.

The raw `r2/receipt.json` predates the separate read-only packaging inspection.
`r2/bundle-config.json` and its invocation prove `PAGE_ALIGNMENT_16K`; the raw
receipt was not rewritten to hide that sequence. `r2/elf-program-headers.txt`
records the RELRO modulo warnings and rounded-page/writable-segment layout.
Those warnings alone do not establish a runtime crash. Structural resolution,
real 16-KB-page execution and complete signed game builds remain release gates.
No browser measurements or native launch claims follow from compilation.

## Current browser evidence — 2026-10-01

Later matched U4/U5 full-app Chrome runs share source SHA256
`7ab5d7035dcc26ee8bfd77eb7b44b232848d6a61eaf9bdda719e569fe1d8dfa3`
and actual 1470×936 CSS / 2940×1872 backing canvas. Both reach results and
receive retry input. Neither passes: stock RAF max 3,116.235 ms; worker
2,183.350 ms, with selected later console windows below 57 FPS. Stock pointer
capture times out; keyboard capture later saves the report. See
`qa_shots/runner/chrome-fullapp-accelerated-stock-u4.ieo3y0gf/comparison-observation.json`
for immutable report hashes and explicit caveats. Runs share shader caches,
routes are random, native foreground/X-close remains unverified, and tool
round-trip delays are not native-close measurements. No engine cause or final
performance acceptance is inferred.

Desktop resolution-governor repair passes **70/70** isolated state checks,
clean fresh import: `qa_shots/runner/desktop-live-governor-20261001/receipt.json`.
Sustained 48 FPS feeds reach MSAA-off at sample 5, 0.85 at 9, 0.72 at 13;
mobile behavior, saved settings, native UI resolution, retry persistence,
readiness exclusions and recovery remain covered. U4/U5 snapshots predate this
repair. Browser transitions/performance and the full suite are still pending.
The complete local native release-helper suite separately passes **93/93**,
zero skips, in 3.738 seconds; this is not native device acceptance.

Fresh full-app U2 audio candidate completed import/export with no detected
engine errors. Build/source hashes: `qa_shots/runner/chrome-fullapp-audio-u2.206enb16/`.
Run ID: `runner-web-cd4cb27ea5ee4efd93619d67d7cdbfb2`. It preserves the normal
main scene and quality governor, uses the corrected worker-readback template,
and excludes production auth/API/PWA integration. U2 later saves a feature-error
report before engine start: Chrome acceleration is off and WebGL2 unavailable.
Owner approves enabling acceleration/relaunch, then confirms relaunch complete.
After relaunch U3 passes the WebGL2 feature gate. Hardware renderer, Energy Saver
and OS foreground still require acceptance verification. Battery is charging on AC.

Stock non-threaded U3 has also passed fresh import/export:
`qa_shots/runner/chrome-fullapp-audio-stock-u3.svw4c86h/`. Its source fingerprint
matches U2 exactly (`ce618e24ebe808c8c33721ea523f35fa83eb2d0a5cae0ede79b96583fa7b792a`),
as does its canvas policy. U3 now reproduces long loading stalls: browser RAF
max 5,267.595 ms during startup and 3,183.365 ms after runner selection;
console logs repeated 1–3 second runner-labelled frames while screenshots show
the loader. Report SHA256 `118115513e311460ab8d92ca9a0db79d5d40e73400ef1483ed162e31f1881b9a`.
See U3's `observed-freeze-20261001.json` for timestamps and limitations.
Unrelated headless Chrome is active; native foreground/X-close observation is
unavailable and a correctness test overlaps startup. This is failure reproduction,
not a passed performance gate or engine-causality result. Separate run IDs
isolate saves; gameplay/mission randomness is not fixed. Existing conditions
are in U3's `comparison-preflight.json`. No new engine instrumentation added.

Focused live-quality adaptation test passes **39/39**, parser/import clean and
no teardown leaks: `qa_shots/runner/live-quality-20261001/receipt.json`.
It verifies same-run signal handling, bounded chunk updates, future density,
unchanged collision/RNG/save behavior and reversible ranges. Browser benefit,
visual transitions and the complete suite remain separate gates.

Post-comparison correctness work: a pinned QA worker template fixes the
main-thread WebGL readback context selection, without changing visuals or
gameplay. The compiled ZIP and post-link dispatch receipt are under
`qa_shots/native-headers-4.7.1.seSHFR/web-worker-eval-readback-current-context/`.
T8/T9 Chrome runs verify the corrected readback/world path, while T10's
unfixed engine fails specifically at mesh-readback preflight before world
construction. Neither corrected run passes performance targets. Do not treat
compilation, the seven modeled readback checks, or the 30 source/emitted-template
guard tests as performance proof. Workload validity and initial real-mesh preflight
passed 88 isolated metadata assertions (`waddle-wars-tests-87370-22075`),
82 shell tests and 49 collector tests after witness hardening. Fresh matched
T8/T9 and old-engine regression T10 import/export gates pass. Chrome
reports at matching 2940x1872/high on battery: T8 average 56 FPS, p95 25.72 ms,
max 54.47 ms, zero sampled frames above 100 ms; T9 average 57.43 FPS, p95
31.65 ms, max 122.32 ms, one above 100 ms. Both keep valid world and stable
canvas, but fail thresholds. These sampled gameplay metrics do not cover
startup or tab-close delays. Recorded page visibility does not independently
establish uninterrupted OS foreground or Energy Saver state. Full-app/device
acceptance remains pending.
Full identity/limits receipt and sibling raw report directories:
`qa_shots/runner/chrome-worker-readback-control-t8.qh2apm5m/comparison.json`.

Full-app U1 capture is now saved in
`qa_shots/runner/chrome-worker-readback-fullapp-u1._81kaky6/browser_report.json`.
It covers title/menu, two runner entries, three results transitions and two
retries. Loading spans: 6.478 s and 4.746 s; retry callbacks: 49.870 ms and
30.960 ms. These are state-edge spans, not first-present/first-playable latency.
Maximum engine-era page RAF gap: 166.620 ms. Trusted input dispatch delay peaked
at 2.700 ms; handler-to-next-RAF peaked at 30.780 ms, not proof of visible response.
No page errors; 26 lifecycle events with no dropped events. There is no engine
FPS/p95 gate in this report. Chrome Energy Saver was observed and battery was
below 20%; another task used Chrome, so uninterrupted foreground is unverified.
The exact game tab was closed, but combined click/accessibility time includes
inspection overhead and active gameplay at closing was unverified. No native
tab-close acceptance. Repeat charged, controlled foreground and Energy Saver off
before making a responsiveness claim; preserve this diagnostic as-is.

User-coordinated foreground T5/T6 pair completed with matching 2940×1872/high,
actual 2× MSAA and scale1. T5: 49.07 FPS, p95 37.33 ms, maximum 153.04 ms,
four frames above100 ms. T6: numeric 59.33 FPS, p95 19.38 ms, maximum79.85 ms,
but **not accepted**: camera at the primitive-peak snapshot had coordinates
about1e37, zero visible 3D objects/primitives and sharply reduced draw work.
The original numeric eligibility gate did not check world integrity. No
performance benefit can be inferred from this invalid comparison. Both reports
remain unchanged, including the false-positive numeric result; interpretation
and foreground evidence are recorded in
`qa_shots/runner/chrome-worker-scissor-t5.shp0l_to/comparison.json`.
Both also logged an audio teardown exception after their reports. Original
release-only art policy deliberately used procedural DAY fallback in both;
no unapproved asset was silently promoted. Correctness repairs and fresh
comparisons are required before full-app/device acceptance.

Browser lag is unresolved. Candidate S completed 54.013 seconds at native
2940×1872/high: 46.45 FPS, p95 25.14 ms, maximum 134.735 ms, one frame above
100 ms. Draw calls average 180.89/peak 213; day/dusk/cave traversed to 1,334 m.
No CPU or GL wrappers, but stream/phase diagnostics were enabled. It is a
controlled standalone workload, not full-app acceptance. Source/build/report:
`qa_shots/runner/chrome-chrome-disposal-s.8smskwwt/`.

S's RAF log was exhausted during its 23-minute manual-start wait. Its
whole-page 2.816-second gap must not be labeled game startup or gameplay.
Its stream log also dropped 1,493 of 1,749 events; missing late-frame IDs are
not evidence of no stream work. New shell schema 2 keeps pre-engine evidence
separate, retains full start-crossing intervals with explicit flags, and
reserves 64 slow rows each for runner startup and run. Full-app rows remain
unclassified. The 71 shell and 48 collector host checks pass.

An optional custom QA release engine can be tested without replacing the
installed engine or production export settings:

```sh
python3 tools/qa/runner_web_perf.py prepare worker-candidate \
  --threads --template-release /absolute/path/to/template.zip \
  --canvas-policy production --tier high --warmup 6 --seconds 54
```

The tool copies the ZIP into the isolated run, records its hash/size in the
manifest and build receipt, embeds its hash in browser metadata, and rejects
changed artifacts before engine execution. The original template's source,
compiler and options require their separate build receipt; a custom ZIP alone
does not prove worker mode or performance. Build and browser acceptance are
still required. No quality setting or deployment is changed by preparation.

## Historical premium evidence — 2026-09-19

Latest focused runner snapshot: 26 PASS labels, one renderer SKIP, zero FAIL,
exit 0, plus one internal Python baseline-comparison skip. Run-end transaction
24, biome/cache 121, exact sky sequence 60 and slide 85 checks pass; simulation
and eight retries also pass. Fresh isolated import/saves. No browser performance
claim; subsequent chunk staging is outside this snapshot.
`qa_shots/tests/runner_responsiveness_20260919_02/RESULTS.md`.

Latest full-app lifecycle capture H **fails responsiveness**: a 2.916590-second
RAF gap after loading, with precise gameplay/results attribution unknown.
Original Boot/Title/Menu/Runner/results/retry flow and governor, native
2940×1872 backing, isolated saves, no production auth/API. No FPS acceptance
gate is fabricated for this mode. Later profiling did not capture/attribute
that stall. See `qa_shots/runner/chrome-app-lifecycle-h.rtpielb8/REVIEW.md`.

PerfTicker's opt-in console timing now uses monotonic time so clamped engine
delta cannot hide severe pauses. Fresh isolated import plus 16 clock checks,
45 collector checks and 65 shell checks pass; zero skips in these focused
cases. This is a measurement correction, not a browser-performance fix or an
exact-current full-suite pass.
`qa_shots/tests/perf_ticker_clock_20260919/RESULTS.md`.

Hidden-backdrop processing regression: 81 frontend + 136 utility frontend
assertions pass, two PASS labels, no skips/fails, isolated import/exit 0.
Both labels still emit known ObjectDB/resource shutdown warnings. This proves
hidden callbacks stop and visible drift resumes, not a browser freeze cure.

User-coordinated foreground Chrome diagnostic still reproduces severe stalls:
464.44 ms maximum, eight frames over 100 ms. All-WebGL wrappers and stream
instrumentation add overhead, so its 50.23 FPS is not an uninstrumented baseline.
Captured phases include both scene-processing and render-submission stalls;
no individual observed post-GO GL call exceeds 100 ms. CPU/runtime/scheduler
cause remains unresolved. Bounded trace retention drops are recorded, not
silently treated as complete coverage.
`qa_shots/runner/chrome-native-gl-reserved-d.l1demlzv/REVIEW.md`.

A diagnostic 0.5 main-viewport 3D scale also fails (max 331.15 ms), with native
HUD/canvas and unchanged high-tier geometry/materials/2× MSAA. No production
quality change was made. The later QA-only scale/retention extensions pass 39
collector and 61 shell tests plus fresh isolated import/export, but postdate
the full 75-label snapshot below. No exact-current full-suite claim is made.
`qa_shots/runner/chrome-native-scale-half-c.x5bkcq2x/REVIEW.md`.

Latest matched-source Chrome native-size AA pair **fails both variants**:
2940×1984 backing, high tier, off 59.00 FPS / p95 18.79 ms / max 260.005 ms,
default actual 2× 58.95 FPS / p95 18.93 ms / max 555.415 ms. Four and one
frames respectively exceed 100 ms. Measured intervals stayed visible; AA-off
startup visibility changed. No AA speedup or freeze fix established.
`qa_shots/runner/chrome-native-aa-default-b.adf0vdm5/REVIEW.md`.

Earlier Chrome native-size diagnostic **fails**: 2940×1872 backing, high tier,
2× MSAA, 55.15 FPS / p95 23.80 ms / max 150.825 ms over 60 seconds, with six
frames over 100 ms. The canvas reconciled at GO/report and stayed visible.
`qa_shots/runner/chrome-production-native60.vyrycdhx/REVIEW.md`.
Governor is disabled in this controlled workload; it is not the complete app.
An AA-off comparison was interrupted after focus moved to another tab; no
result exists and no speedup is claimed. Browser lag remains the first priority.

Earlier Chrome diagnostic: one passing 60-second run at fixed 1920×1080,
59.98 FPS / p95 17.66 ms / max 38.34 ms, zero frames above 50/100 ms. All eight
instrumented shader/program methods remain silent after GO. Native scheduler
capture completed and the 69 MiB thread-state export parses to 254,311 target
intervals; its bounded parser now permits 128 MiB and 500,000 target intervals
(29 host checks pass). State intervals are elapsed scheduling states, not CPU
samples. Evidence: `qa_shots/runner/chrome-scheduler-current60.01t_3mph/`.

This is **not a freeze fix or production-performance pass**. The previous
failure below remains valid; startup timing, cache and source changed. Also,
the diagnostic fixes backing resolution and disables the quality governor.
Production's canvas script can use 2940×1654 at the same 1470×827 CSS/DPR 2
geometry, versus the probe's 1920×1080 (2.345× the pixels). Actual production
workload was unmeasured in that comparison. The subsequent untraced fixture
was not started after the Mac locked; its server was stopped with no report.

Optional QA-only production-canvas measurement preserves the current
`export_presets.cfg` viewport, page-canvas sizing and DPR policy while keeping
the requested fixed tier and disabling the adaptive governor:

```sh
python3 tools/qa/runner_web_perf.py prepare production-canvas \
  --canvas-policy production --tier high --seconds 60
```

Preparation extracts only three reviewed sizing/DPR IIFEs, records source and
fragment hashes, and fails closed if their source changes; it never copies the
production auth/API bridge. Width/height remain probe-reference metadata, not a
forced production backing size. A result is native-size-workload eligible only
when positive browser and engine dimensions agree and backing size matches at
first-running and report (endpoint checks, not continuous monitoring). This mode always reports the fixed-resolution
gate as not applicable and `complete_production=false`; it is a controlled
requested-tier diagnostic, not production acceptance. Fixed 1920×1080 remains
the default mode.

Focused validation: 64 collector/scheduler tests, 61 shell tests, 41 production
policy checks and 55 engine metadata checks pass; fresh isolated import/export
succeeds. Earlier two harness failures and corrections are retained. Browser
execution had not occurred at that receipt's date; the later native-size result
is recorded above. See
`qa_shots/tests/production_canvas_20260919_01/RESULTS.md`.

HUD speed and instanced contact-shadow variants now draw before build completion.
Isolated coverage passes 47 HUD checks and 73 warmup geometry/ownership checks.
Actual Chrome source identities move into startup: the contact pair formerly
linked near GO+8.8 s, now GO−4.119 s. All eight instrumented shader methods record
zero post-GO calls, with no event drops. **Freezes remain unresolved:** that
60-second capture reports 56.56 FPS, p95 21.84 ms, max 165.67 ms and five frames
over 100 ms. No causal FPS benefit is established. See
`qa_shots/runner/chrome-shadow-warm-fixed60.g_x_1lk3/REVIEW.md`.

Latest full isolated snapshot: **75 PASS labels, eight explicit SKIPs, zero FAIL,
exit 0**. Five SKIPs need a real window; three need NumPy. No separate execution
of those skipped checks is claimed for this snapshot. Fourteen ObjectDB shutdown
warnings and fourteen retained-resource error lines remain, plus two intentional
corrupt-JSON recovery errors; this is not a clean release error log. All 945
snapshot fingerprints match after completion. Governor 42, collector 36 and
shell 61 focused checks pass. See
`qa_shots/tests/browser_lag_20260919_01/RESULTS.md`.
Compared with snapshot 09's thirteen shutdown pairs, warning labels add
`utility_frontend_test`, `runner_churn` and `tutorial_sim`; `race_sim iceberg`
and `grand_prix_sim` warnings are absent this run, not declared fixed. Source
fingerprints do not imply test coverage for paused, unpromoted Z13/Z14 art tools.
This snapshot includes both shader warmups and the loader-dismissal/race/tutorial
lifecycle changes, timeout recovery and pause/game-over callback ownership
(94 recovery / 148 runner platform / 11 host source checks), plus the late-spawn
census correction (125 checks). That
fixture proves timing/readiness, not full queue membership or GPU compilation;
the 128-entry cap and hidden ghost coverage remain unverified in real races.
Reproduction: `qa_shots/tests/race_warmup_boundary_20260919_01/RESULTS.md`.
The real-tree startup checks pass 70 race/Endless assertions
and 40 tutorial assertions; the new real-window runner capture only receives a
parser/autoload check headlessly. Separate native-window runs now pass all 18
handoff assertions and save all seven captures in landscape and portrait retry.
The first portrait attempt remains FAIL (12/18 failed, draw stall at 27); retry
records focus losses. These are submitted-frame ordering checks, not continuously
focused portrait, browser compositor, performance or art approval. Rendered
results: `qa_shots/tests/loading_presentation_rendered_20260919_01/RESULTS.md`.
Earlier reproduction history and limits:
`qa_shots/tests/loading_presentation_summary_20260919_01/RESULTS.md`.

Snapshot 03 genuinely failed: Z07's art test depended on a historical QA
directory absent from isolated copies. Self-contained temporary quarantine
checks fix that test without weakening art validation. Original failure remains
at `qa_shots/tests/premium_runner_suite_20260919_03/RESULTS.md`.

Loader boundary: `./run_tests.sh scene_router_presentation` checks ordering and
cancellation and dismissal (18 checks). `python3 -m unittest tests.test_loader_presentation_boundary`
checks eleven source/fixture invariants. Neither establishes browser presentation.
Actual-window request-entry proof uses isolated `user://`:

```sh
GODOT=/opt/homebrew/bin/godot ./run_frontend_qa.sh loader_boundary out=/absolute/fresh/portrait.png w=540 h=960
GODOT=/opt/homebrew/bin/godot ./run_frontend_qa.sh loader_boundary out=/absolute/fresh/landscape.png w=960 h=540
```

Run serially, with fresh output paths. PNG/JSON are captured at backend request
entry after a real authored-loader draw and subsequent process frame. This
cannot prove uninterrupted animation during synchronous loading.

Real Runner handoff fixture (requires an unlocked display, not a performance
benchmark) is invoked with `./run_frontend_qa.sh runner_handoff` and the same
fresh `out=`, `w=` and `h=` arguments. It must observe the real scene swap,
loader-cleared draw, full visible countdown and subsequent movement. Merely
passing a synthetic flag/countdown test does not establish that handoff.

Loading recovery: `./run_tests.sh scene_router_recovery` includes 94 deterministic
state/ordering checks plus a parse-only invocation of its capture fixture.
It covers exhausted draw budget, no-draw process deadline, stale callbacks,
outstanding/failed resource jobs, redirects, context preservation and pause
ownership. The initialized runner platform fixture adds blocked-retry state
preservation and normal idle retry (148 total checks). Original failures and
corrected runs: `qa_shots/tests/loader_recovery_20260919_01/RESULTS.md`.

```sh
GODOT=/opt/homebrew/bin/godot ./run_frontend_qa.sh loader_recovery out=/absolute/fresh/recovery-portrait.png w=540 h=960
GODOT=/opt/homebrew/bin/godot ./run_frontend_qa.sh loader_recovery out=/absolute/fresh/recovery-landscape.png w=960 h=540
```

These serial native-window runs pass 44 assertions each: opaque cover, actual
post-draw recovery controls, safe-area fit, paused-tree processing, client-pixel
touch sizes and keyboard focus. They inject the watchdog clock around its real
armed deadline; they do not wait thirty wall seconds or navigate through a real
failed asset load. A process watchdog cannot interrupt blocked main-thread work
or recover a renderer that no longer draws. Browser compositor and phone touch
acceptance remain separate gates.

QA-only `?glalltrace=1` measures effective page-realm WebGL2 methods, excluding
worker/extension-object methods. Default OFF, incompatible with the three older
GL trace flags. It adds per-call overhead; never use as an uninstrumented
performance baseline. Host coverage: 35 Node checks pass.

Exact sky assignment/color-parity gate: `./run_tests.sh runner_sky_uniform`.
The real production blend is instrumented in a test-only scene: 60 checks,
zero failures, exact original transitions at 30/60 FPS and zero redundant
stationary writes. Visible Chrome A/B subsequently completed after unlock:
59.52 versus 59.53 average FPS, no frames over 100 ms in either 60-second run.
No measurable benefit established. Later same-runtime diagnostics still hitch:
CPU-sampled maximum 167.165 ms; timeline-only (sampling off) maximum 138.96 ms.
Both fail the >100 ms gate. See the trace receipts linked from BUILD_STATUS.md.

Z06 source has a grounded budgeted rig candidate, but its new atlas remains
rejected for 17 projection pixels. UV staging itself now validates cleanly.
Reference fidelity and live character replacement remain unapproved. Current
status/evidence links are maintained in `BUILD_STATUS.md`.

Earlier host checks, not included in the historical 59-PASS snapshot:

- Collector contract: 17 tests pass. Presentation-call QA shell: 17 tests pass.
  New opt-in `?presentationtrace=1` measures only getParameter enums 3089/36006
  and blitFramebuffer wall time, with bounded slow rows. It retains no query
  results and does not change renderer behavior. Disabled mode leaves methods
  unwrapped. Native GPU time and cause attribution are not implied.
- Z08: three scope checks pass with ordinary Python; three field checks pass
  separately with Blender's standalone Python. Missing NumPy is an explicit
  suite SKIP. Z09: six scope plus four field checks pass with standalone Python.
  New registrations likewise separate the NumPy-only group from scope checks.
- Actual Z09 Blender source/front/three-quarter/side renders complete, but root
  visual review still rejects live promotion. Numerical art checks are not
  visual-quality acceptance. Runtime character remains V11.

Focused receipts: `qa_shots/tests/host_registration_20260919_01/README.md`,
`qa_shots/tests/presentation_trace_20260919_01/README.md`, and
`qa_shots/hero/v12_source_proof_z09/HOST_TEST_RECEIPT.md`.

## Historical premium evidence — 2026-09-07

Newer focused evidence (not included in the full-suite snapshot below):

- First-DUSK hidden insertion is normal (18.805/15.663 ms); first restored draw
  stalls 98.541 ms without a new stream event. First-visibility dependence is
  established for this sample, not a shader/upload cause.
  `qa_shots/runner/dusk_visibility_delay_20260907_01/TRACE_REVIEW.md`.
- Full-size real dressing prewarm passes ten surface/family coverage checks,
  original-state restoration, exact art RNG/inventory and zero residual nodes.
  Repeated 60-second traces still hitch 72.592/94.937 ms at first DUSK;
  averages 59.89/59.93 FPS, p95 17.92/17.97 ms. No reliable lag fix or live hook.
  `qa_shots/runner/dusk_dressing_prewarm_perf_20260907_01/`, `_02/`.
- Z04 actual source renders improve facial continuity, not reference fidelity.
  Focused host tests: 31 source-study +18 provenance +8 saddle PASS. No actual
  Z04 runtime reduction/export or new source-cover approval.
- Y03 rim03 four-frame state checks pass but strict engine gate rejects two
  resources retained at shutdown. Images remain diagnostic evidence, not a
  clean run. Lower hero-only light helps slightly; visual acceptance still fails.
- Material diagnostic04 has six actual frames with complete state restoration;
  original four hashes match diagnostic03. Half key/receiver-off is a useful
  control, not production material policy or a performance measurement.

Latest complete isolated development snapshot:52 PASS labels,5 explicit window
SKIPs,0FAIL,exit0. Includes34 material-diagnostic host tests,25 source-study
guards through Z03,16 provenance and55 performance metadata checks; all gameplay
families pass. Existing shutdown diagnostics/103 unapproved assets remain.
Later Z04/delayed-visibility/rear-light studies are outside this snapshot.
`qa_shots/tests/premium_material_msaa_suite_20260907_01/RESULTS.md`.

Full-size first-DUSK prewarm counterfactual: actual-material proof covers all six
deck/verge surfaces, exact state restored and zero helper nodes left. Subsequent
ordinary 60-second probe still records 93.401 ms at396.291 m, spawn/stream CPU
0.865/0.900 ms, average58.51 FPS,p9519.75 ms,peak172,434 primitives. Copied-source
QA only. This does not prove an improvement or justify a runtime hook.
`qa_shots/runner/dusk_real_prewarm_perf_20260907_01/report.json`.

Fresh actual-2× tiny raster `_03`: clean fixture, coverage FAIL. Original deck,
seams, verge body/crown/drop/snow resolve2/0/0/0/1/2pixels; enlarged controls all
render. No GPU compilation/cause attribution. `_03` matches production resolver,
unlike the earlier forced-4× fixture below.
`qa_shots/runner/dusk_exact_raster_20260907_03/REVIEW.md`.

Y03 four-frame material diagnostic `_03` passes exact state/shader/restoration.
Receiver-off removes isolated bill-patch contour by brightening the surrounding
bill; hotspot itself stays bright. Feet also overbright, ground shadow retained.
No material policy promotion. Actual saved Z01/Z02 scene/mask validation passes
read-only Blender5.2.0; all inspected inputs unchanged, art approval remains false.
`qa_shots/hero/v12_y03_material_diagnostic03/REVIEW.md` and
`qa_shots/hero/v12_source_proof_z02/saved_scene_integrity_report.json`.

MSAA evidence correction: native Compatibility resolves requested 4× to 2×.
Old performance reports captured only the requested setting. New metadata
records requested, policy-resolved and actual viewport modes before and after
the measurement, not continuous GPU samples. Raster `_02` forced 4× and is
therefore not exact production-2× coverage evidence. Raw artifacts unchanged.

The forced-4× DUSK raster run is clean/complete but **coverage FAILS**: seams and
verge crown produce zero resolved pixels at actual warmup placement; all six
enlarged controls render. Registration alone was insufficient. ID colors prove
resolved geometry coverage, not GPU sample counts or pipeline compilation.
No FPS claim or live probe-scaling change follows this diagnostic.
`qa_shots/runner/dusk_exact_raster_20260907_02/REVIEW.md`.

Z01 source eye-aperture and Z02 fuller-bill/rounder-flipper studies complete
three views each, with 19 host guards covering the two opt-in profiles.
The new `hero_source_study` suite label is not part of the prior suite below.
Z01 changes only burial depth; Z02 also changes stated bill, orbit-paint and
flipper-width literals. Baseline files/live assets unchanged.
Visual improvement is modest and overall fidelity remains unapproved.
`qa_shots/hero/v12_source_proof_z01/REVIEW.md`.

Latest full isolated development suite:49 PASS labels,4 explicit window SKIPs,
0FAIL,exit0. Includes three new atlas-runner/mouth/DUSK labels and all gameplay
families. Existing shutdown diagnostics and separate visual/performance FAILs
remain release debt. Exact evidence:
`qa_shots/tests/hero_atlas_dusk_suite_20260907_01/RESULTS.md`.

Latest Y03 **source-atlas** integration: strict zero missing pixels, Khronos
clean and exact serialized geometry/rig/clip parity. Actual front/chase 30/60
sequences match including startup, plus 18 normal portrait-runner frames.
Exactly four shared compressed maps, 16,777,296 stored bytes. Root inspected
front/chase/runner: feather grain present, but dark rear, generic face, harsh
bill highlights and blue tail still fail fidelity. No live promotion or Y03
FPS measurement. `qa_shots/hero/v12_atlas_y03_runner_review01/VISUAL_REVIEW.md`.

New DUSK preload coverage uses the exact seam buffer and one four-surface verge
instance. No detail/collision/RNG change; fresh external registry32/32, full
queue cap128 unchanged. New31 coverage +existing58 geometry/22 staging/141
platform checks pass. Cross-scene preoccupied-registry truncation is explicit.
Clean matched 60-second trace after this fix still hitches97.423 ms at396.104 m;
average58.16 FPS,p9519.84 ms,primitive peak172,462,overallFAIL. Source subset
differs only in runner_track/shader_warmup from its paired pre-fix diagnostic.
Coverage is improved; lag is **not solved**. Evidence:
`qa_shots/runner/dusk_warmup_trace_20260907_02/`. The earlier01 attempt is
CONFOUNDED by overlapping Blender work and was stopped/excluded.

Latest native desktop baseline without stream tracing, with the current controller/camera and live V11
geometry: Compatibility/high, 1920×1080, 60 seconds from GO, seed 20260907.
59.22 FPS average, p95 19.37 ms, maximum 98.13 ms, draws 174.66 average/209
peak, zero frames over 100 ms. Overall **FAIL**: 172,434 peak primitives exceed
the 100k cap. Timing is close to the stall ceiling, not lag-free approval.
No browser/phone result or Y03 FPS claim. Evidence:
`qa_shots/runner/runner_perf_20260907_camera_fix.json` and matching CSV/log.

New opt-in `stream_trace=true` diagnostic reproduces a 99.20 ms hitch at
22.239650 s / 396.106940 m, paired with first DUSK chunk 17 and retirement of
chunk 8. Actual recorded spawn/stream CPU is only 1.037/1.077 ms; the remaining
interval is not assigned to GPU, uploads or shader compilation. Instrumented
average 58.48 FPS, p95 19.86 ms, primitive peak 172,462: overall gate FAIL.
One other >30 ms frame is 47.533 ms without a same-collection stream event.
84 events/no recorded drops and one complete 17-frame hitch window retained:
`qa_shots/runner/camera_stream_trace_20260907_01/`. This is diagnostic timing,
not baseline-equivalent and not an improvement claim.

Authored camera checks now use the configured imported height (one loading-time
species morph snapshot), not hidden procedural bounds. Eight-size projection
checks retain lane edges from 20 m and the 55–70 m horizon; smaller species
retain the 2.95 m clearance floor with a documented size concession. Shared UI
classification is unchanged. Twenty new posed-bounds checks cover effective
visibility, morph order and skin binding; the golden capture now measures posed
visible vertices instead of rest AABBs. This is not a raster/occlusion mask.

Actual Y03 front/chase 30/60 capture passes, including zero initial-blend and
steady-run differences, plus 18 real portrait-runner frames. Brow islands are
visibly repaired, but the proxy material remains rejected. Five golden poses
measure 18.0/14.9/18.3/16.4/10.8% and **fail** strict jump/launch framing. Logs
also preserve 24 ObjectDB/two-resource shutdown diagnostics in this separate
golden run. Evidence: `qa_shots/hero/v12_candidate_y_camera_review02/`.

Y03 geometry preserves six exact source-cover ray intersections in both LODs,
with 22,963/10,557 triangles and two surfaces. Mouth equals original Y01 exactly;
Y02's experimental mouth was rejected. Nineteen exporter and 24 baker tests pass;
the baker now explicitly replays each audited reduction policy. Fresh Y03 LOD0
bake passes reconstruction/UV checks but initially misses 22 actual texels.
Seven same-source eye repairs pass with every other working pixel unchanged;
that intermediate checkpoint retains15mouth misses. Mouth03 subsequently
resolves all15 using outward-compatible stable source faces, actual material
bakes and60center/corner first-ray checks. Caps unchanged; all unselected
working pixels and original geometry/skin/morph data exact. Thirteen mouth
host guards pass. QA atlas GLB now exists; no live material promotion.
Evidence: `qa_shots/hero/v12_atlas_y03_mouth_03/REVIEW.md`.

New shared-atlas runner QA route preserves the real controller/facade/camera
and blocks rejected/ambiguous projection bindings before project creation.
Fourteen host tests pass; main suite now includes its host label. Frozen M
normal-import preflights pass in shader and imported-PBR modes, sharing exactly
four compressed mipmapped maps (16,777,296 stored bytes; not driver VRAM).
Those M preflights contain no rendered Y pixels. The later actual Y captures
above now validate this path but still do not approve source fidelity. Usage:
`qa_shots/hero/v12_atlas_runner_m_preflight02/ATLAS_RUNNER_ROUTE.md`.

New shared-controller transition gate covers nine equal-time 30/60 transitions
through actual imported bones. Original idle→run differed by 71.922 mm; guarded
zero-time weight resampling yields zero measured bone-position, quaternion-
component and clip-time errors. Automatic playback is retained. The existing
56 motion and 33 controller checks pass after this change. The fresh timing
sample below includes this controller, but predates subsequent camera work.

The correction addresses the pinned engine's incoming/outgoing weight update
order, not clip speed: [AnimationPlayer blend evaluation](https://github.com/godotengine/godot/blob/4.7.1-stable/scene/animation/animation_player.cpp#L247)
and [end-of-mix notification](https://github.com/godotengine/godot/blob/4.7.1-stable/scene/animation/animation_mixer.cpp#L937).
The zero-time evaluation is recursion-guarded and limited to active transitions.

Actual X review04 uses the same controller through PenguinVisual: front/chase
48/96-frame sequences and 19 real portrait-runner screenshots pass contact,
root, attached-feet, material-binding and unchanged transition parity gates.
Logs retain the established 20 ObjectDB warnings. Proxy materials/framing
remain visually unapproved; source Y's feather recipe is not in this candidate.
See `qa_shots/hero/v12_candidate_x_facade_review04/CAPTURE_REVIEW.md`.

Older performance tables below describe earlier art and timing methods, not
current premium acceptance. Earlier controller-only native 1080p/high 60-second
sample from GO: 59.62 FPS, p95 18.04 ms, max 77.45 ms, 176.03/212 draw calls,
zero frames over 100 ms, 154,096 peak primitives. Frame/draw gates pass; overall
gate **fails** the existing primitive cap.
Local report: `qa_shots/runner/runner_perf_20260907_transition_fix.json`.
This is the live V11 character, not the QA-only V12 source or atlas package.

An untimed sequential replay reproduces the recorded DAY peak context at
266.498 m (0.180 m overshoot), with the same comparable source fingerprint.
`qa_shots/runner/peak_replay_20260907_03/report.json` records frozen per-family
hide/restore counters. It is not an exact replay of the historical rendered
frame or a GPU-time/FPS attribution. A subsequent per-instance LOD-bias sweep
and 24 captures are under `peak_replay_lod_20260907_04`: some existing automatic
LODs remove major landmark features, so those bias settings are not approved.
Its strict wrapper exits 2 on shutdown diagnostics (24 ObjectDB instances and
two resources still held, versus 20 instances in the prior replay). This new
diagnostic-lifetime difference is unresolved; `REVIEW.md` preserves full scope
and counter/visual evidence. It is not a clean performance/release run.

Subsequent shutdown investigation: three exact-input reruns return the earlier
20-ObjectDB baseline without the two-resource delta; a standalone 24-image
readback/save probe exits cleanly and frees every image. The original delta
is unreproduced, not fixed. Evidence:
`qa_shots/runner/peak_replay_lod_shutdown_before_03/SHUTDOWN_AUDIT.md`.

Authored radar far-LOD candidate: 22 host tests, two byte-identical exports and
Khronos zero errors/warnings. Actual Compatibility comparison retains the
recorded 119-MultiMesh state, swaps only the radar, and restores exactly;
35 replay contracts pass. Candidate has 7,400 triangles versus 17,608, one
surface and no auto-LODs. Both recorded/inspection views measure a 10,208
primitive reduction with unchanged draws. Far silhouette survives; close
faceting remains. A subsequent side/three-quarter and 90-frame camera-motion
capture passes 45 contracts and 180 exact state/counter checks; two seven-window
walls survive. Both normal/quarter-speed encoded clips are available, but full
moving playback/pop approval and final LOD-selection policy remain pending.
See `qa_shots/runner/radar_candidate_extended_20260907_03/EXTENDED_REVIEW.md`.
Strict capture still
exits 2 for the existing DAY warning and 20-ObjectDB shutdown report. No live
policy, clean-runtime or FPS claim. Comparison artifacts:
`qa_shots/runner/radar_candidate_comparison_20260907_01/`.

Frame gates now use monotonic wall-clock intervals, not Godot's potentially
smoothed/capped simulation delta. `warmup=0` includes all frames after GO.
`seed` makes route comparisons repeatable; ordinary gameplay stays random.
For native desktop QA, `keep_visible=true` keeps the temporary window above
other apps; macOS can otherwise suspend rendering while process ticks continue.

```sh
./run_runner_perf.sh tier=high w=1920 h=1080 warmup=0 seconds=60 seed=20260907 keep_visible=true enforce=true
./run_tests.sh runner
```

The runner suite includes actual countdown/loader/retry checks, initial visual
staging visibility/identity/cancellation checks, and warmup footprint/winding
checks. `tests/shader_warmup_raster_test.tscn` additionally requires a rendering
window: it verifies visible pixels through the production material spawn path
with ordinary back-face culling and a reversed-winding negative control.
Material census signatures are resource approximations, not GPU program IDs.
Incomplete loader runs fail even when no gameplay occurred under the overlay.
Development asset checks use `validate_art.py --review-fragments`; the strict
release command is `python3 tools/art/validate_art.py` without that option and
currently fails. Review integrity never implies `production_ready=true`.

Godot 4.7.1's headless dummy renderer is not safe for parallel mesh/material
allocation ([upstream issue](https://github.com/godotengine/godot/issues/121949)).
ArtCatalog therefore loads synchronously headless, retaining asynchronous
loading in desktop/web play. This avoids the observed wrong-RID startup
diagnostics; existing shutdown ObjectDB/resource warnings remain separate.

## Test commands

Shared penguin motion now has imported-bone and skinned-vertex regression
coverage. Feet/toes are intentionally locally fixed during RUN and inherit the
body's rocking weight transfer. This is separate from visual-fidelity approval:
runtime geometry still falls short of the user reference.

```sh
./run_tests.sh hero_penguin
./run_tests.sh hero_penguin_transition
./run_hero_capture.sh motion=run fps=30 seconds=2 always_on_top=true output=/absolute/fresh/hero-30
./run_hero_capture.sh motion=run fps=60 seconds=2 always_on_top=true output=/absolute/fresh/hero-60
```

Motion mode defaults to front/side/rear chase and beauty/silhouette. Restrict
with `views=front,chase renders=beauty orientations=landscape`. Each sequence
contains exact fixed-step frames, contact sheet and a timeline with the GLB
hash. Captures are not FPS benchmarks: deliberate offline stepping and image
readback have no relationship to live frame time. Existing still-matrix mode
is unchanged when `motion` is omitted.

Latest attached-feet evidence: `qa_shots/hero/run_waddle_attached_feet/` and
`qa_shots/hero/waddle_attached_20260907_30/`. Older `waddle_20260907_30/60`
captures use the superseded independent-foot clip, not the final user-directed
motion. Material diagnostics: `art_src/characters/hero_penguin_material_audit_20260907.md`.

V12 replacement tests are separate from the live V11 model:

```sh
python3 tests/test_hero_v12_candidate.py
python3 tests/test_hero_v12_shared_texture_package.py
python3 tests/test_hero_v12_atlas_runner_review.py
python3 tests/test_hero_v12_mouth_projection.py
python3 tests/test_hero_penguin_eye_pigment.py
python3 tests/test_hero_penguin_v12_feather_detail_recipe.py
python3 tests/test_runner_radar_lod1_candidate.py
python3 tests/test_runner_day_duplicate_geometry.py
# Requires NumPy; Blender's bundled Python is a suitable authoring runtime.
python3 tests/test_hero_penguin_v12_design.py
```

The normal suite includes candidate-adapter safety/math checks and DAY duplicate
geometry/hash guards. `--baseline-dir /path/to/saved/baseline` on the duplicate
test additionally proves exact unique vertex-attribute/winding preservation.
Source shape guards do not establish visual quality. Candidate exports are
restricted to fresh QA-only directories and remain unapproved.

V12/X–Y has 21 source guards, including immutable base-skull eye frames, real
whole-perimeter eye/head brackets, continuous upper occlusion without a white
island, clear central pupil/iris samples and upper-only mirrored lid pigment.
Additional guards preserve the authored pear/flipper proportions and keep the
upper bill domed while raising the mouth corners. All three source renders
remain below reference fidelity. Do not confuse this
source model with the separate M atlas packaging fixture.

The candidate adapter has 15 passing host checks, including exact preservation
of the new linear IrisPigment field; the pigment helper has eight. Actual
read-only Blender verification preserves both V irises' 769 colors and all
33 frozen M source components without rewriting either saved file:
`qa_shots/hero/v12_source_proof_v/source_color_adapter_audit.json`.
These focused reruns do not supersede the full-suite snapshot below.

Y's material recipe has ten host checks. Its three source renders show stronger
directional grain with unchanged texture count; actual source/geometry binding
and material transfer remain separate gates. Twenty atlas host checks include
new explicit mask-field validation and preserve legacy M's analytic path.
X's two QA GLBs pass Khronos (21,465/9,867 triangles, two surfaces, maximum two
weights, 15 bones, 23 preserved clips); the reduced export is not a claim of
approved deformation, Y material transfer or gameplay performance.

Saved X/Y audit confirms unchanged geometry/paint/UVs/cameras and six packed
maps; explicit source-mask values match authored equations exactly. Fresh Y
2048² LOD0 bake passes reconstruction/UV checks but fails projection coverage:
39 genuine uncovered texels. It exports no runtime atlas GLB. Retained inputs,
working maps and checkpoint: `qa_shots/hero/v12_atlas_y_2048_01/`.

The M shared-texture package is verified under
`qa_shots/hero/v12_shared_texture_package_02/`: exact accessor and raw-data
parity, Khronos zero errors/warnings, and normally imported resource identity
proving one compressed four-image set (16,777,296 stored bytes including mips,
not driver VRAM). See `VERIFIED_PACKAGE_STATUS.md` there for commands and
hash-bound Godot evidence. No runtime Blender dependency or live promotion.

Latest full isolated snapshot (`qa_shots/tests/hero_camera_suite_20260907_01/`):
46 PASS labels, four explicit real-window SKIPs, zero FAIL, exit 0. Window-only
shader/orientation/UI evidence is not supplied by that run. The optional inner
historical-baseline comparison in DAY geometry also skipped; its live-source
guards ran. All five race simulations, runner/retry churn, ghost/time trial,
endless, tutorial and Grand Prix executed. Known shutdown resource diagnostics
and 103 unresolved art-review assets remain separate release failures. This
snapshot includes camera/posed-bounds, candidate-review and exact source-cover
policy tests. It does not turn the separate jump/launch golden-window framing
failures into passes.

Failed fresh imports now preserve `import.log`, stdout and stderr under
`qa_shots/tests/<isolated-run-id>` before the temporary project is removed.
This retains crash evidence without retaining or modifying the player's saves.
The runner also rejects unexpected engine `ERROR:` lines even when Godot exits
zero. Only known shutdown resource diagnostics and the unit test's exact
intentional corrupt-save JSON diagnostics are excepted; neither exception is
a release-readiness pass. The warmup geometry test's unsupported `%g` strings
were replaced after this stricter audit exposed them.

All commands run from the repository root. The suite is plugin-free: plain
Godot scenes that print `PASS`/`FAIL`/`SKIP` lines and exit `0` on success,
nonzero on failure.

```sh
# Full suite. It snapshots the project under a unique custom user://, cold
# imports it, resets that isolated save before each case, then removes it.
./run_tests.sh

# Filter labels without bypassing save isolation
./run_tests.sh runner
./run_tests.sh art
./run_tests.sh glacier

# Parser / import / resource validation (no gameplay)
godot --headless --import --path .
```

Avoid direct unit/simulation commands against the normal project identity:
several tests deliberately exercise saves, settings, missions, corruption
recovery, and retry. Use the isolated harness or a temporary custom user path.

## Automated test coverage

### `tests/unit_tests.tscn` (`tests/unit_tests.gd`)

| Area | Checks |
| --- | --- |
| Save round trip | Modified `fish`, `achievements`, `best_times` survive `save_now()` + `load_save()`; original save restored afterwards. |
| Save corruption | Garbage written to `user://save.json` and `user://save.json.bak`; `load_save()` recovers merged defaults without crashing; backup file re-validated. |
| Settings defaults | Every key in `SettingsManager.default_settings()` resolves via `get_setting` with a compatible type; music volume in range; touch mode valid. |
| Settings round trip | `set_setting("audio","music_volume",0.33)` persists across a fresh `_load_settings()`; original value restored. |
| CosmeticsDB | ≥ 12 non-body items (or ≥ 16 total); every item has `name`/`category`/`cost`; `items_in_category` covers all items sorted by cost. |
| AchievementsDB | ≥ 12 entries; `ORDER` exactly matches `ITEMS` keys; every entry has `name`/`desc`. |
| PowerupsDB.roll | 200 seeded rolls across positions 1–8 all return catalog ids with ≥ 3 distinct results. |
| Progression | `add_fish`/`spend_fish` arithmetic; unlock rejected when broke and charged correctly when affordable; equip works; equipping a locked item is rejected. Runs against a fresh default save with deep backup/restore. |
| Racer | `Racer.new()` + `setup()` with a `RacerController`, `PenguinVisual`, and null course survives physics ticks in-tree. |
| PathGuide | `TrackBuilder.make_curve` + `PathGuide`: nearest-point distance small for on-curve probes, offsets monotonic along the path, yaw/positions finite and sane. |
| TrackBuildResult | Guide identity, surface runs, paired edge samples, and unchanged legacy visual/collision root layout. |
| UI font | Bundled OFL font loads from a cold import, carries Latin glyphs, and all menu roots receive the runtime theme. |
| Powerups activate | `PowerupSystem.activate` for every id in `PowerupsDB.ORDER`: snowball node spawns, shield applies, frenzy boosts, magnet registers, blizzard cloud spawns; live effects tick one physics frame without errors. |
| Menu scenes | title, main_menu, mode_select, results (with a pre-filled 8-row `Game.last_race_results`), settings, controls, customize, achievements, credits each instantiate, build > 3 nodes with a live script, and free cleanly. Scenes not yet written by the parallel UI stream are reported as `SKIP`, not failures. |
| Touch controls | `TouchControls.new()` + `setup(PlayerController.new())` builds the steer zone, action buttons, and pause button without a racer or course. |

### Runner and art foundation

- `tests/runner_platform_tests.tscn`: four portrait/landscape layout classes,
  asymmetric safe areas, touch controls at 0.5/1/2 scale, camera-shake
  full/reduced/off, reduced flashing, runner quality-governor registration,
  and Compatibility AA policy.
- `tests/runner_golden_slice.tscn`: deterministic 360 m DAY slice, every runner
  verb/obstacle/power-up, art-RNG isolation, typed presentation contexts,
  layout refresh, and instant retry contract.
- `tests/runner_golden_shot.tscn`: five deterministic moving-render review
  positions spanning that slice. Run only through `run_runner_capture.sh`; its
  cold snapshot and custom `user://` protect live saves. Defaults are 1600×900;
  pass `w=540 h=960` for portrait review. It emulates touch metrics by default;
  pass `touch=0` for a desktop-window comparison.
- `tests/runner_sim.tscn` / `runner_churn.tscn`: 60-second gameplay soak plus
  repeated retry/resource-growth checks.
- `tests/art_foundation_test.tscn`, `tools/art/validate_art.py`, and
  `tests/test_art_tools.py`: catalog/resource contracts, pinned budgets and
  toolchain, source/runtime manifests, provenance, hashes, schemas, and
  actionable authoring failure modes.
- `tests/runner_perf_probe.tscn`: windowed tier/resolution probe with JSON+CSV
  frame, draw, primitive, memory, and acceptance-gate output. It is report-only
  unless `enforce=true` is passed. Run through `run_runner_perf.sh`; the wrapper
  cold-imports a temporary project identity so benchmarking cannot touch the
  player's save/settings. `tier=` fixes preset, shadows, particles, and MSAA as
  one profile; reports record actual and requested window size and refuse an
  enforced pass when the platform clamps either resolution or tier. A stopped
  runner or incomplete sample exits with a timeout instead of hanging.
  Reports now retain exact source/import hashes and a comparable source subset
  (excluding isolated project identity/cache bytes). Peak-counter location,
  biome and camera context are recorded; `census=true` adds a final-scene-only
  geometry/LOD inventory after timing ends. It is not peak-frame GPU attribution.
  `stream_trace=true` additionally arms the existing chunk CPU trace and keeps
  bounded event IDs, >30 ms rows and eight-before/eight-after >50 ms windows.
  Monotonic interval/source/observation frame tags distinguish producer time
  from later collection. No timed-loop images, geometry walks or file hashing.
  Trace overhead and truncation are explicit; no GPU attribution is inferred.
  `runner_perf_metadata` exercises 51 report/scope checks without a window.

### V12 candidate atlas (not a live character replacement)

- Host math/safety: `python3 tests/test_hero_v12_atlas.py`. Covers explicit
  semantic weights, authoritative wing paint, UV overlap and face density.
- Actual shader: `tests/hero_v12_atlas_shader_test.tscn`, in an isolated
  no-autoload project. Headless skips. Compatibility and Metal Mobile each
  passed 23 quantitative framebuffer checks on Apple M2; this is not phone
  performance evidence. See `art_src/characters/hero_penguin_atlas_contract.md`.
- Normal imported character capture, after a baked LOD has its binding file:

  ```sh
  ./run_hero_atlas_capture.sh qa_shots/hero/BAKED_CANDIDATE/lod0 FRESH_LABEL view=threequarter fps=60 renderer=gl_compatibility mode=atlas
  ```

  Use `mode=imported` for original GLB PBR comparison; `renderer=mobile` for
  the independent Mobile path. `lighting=legacy|soft-review|balanced-review`
  pins separately audited QA lighting (default legacy). In atlas mode only,
  `normal-strength=0|0.35|1` isolates the complete baked normal's influence;
  weakening it also weakens geometry correction and is not final tuning.
  Rejected bindings still save diagnostic frames and return a failing result.
  Outputs, logs and isolated project location are
  retained. Exact GLB/PNG hashes, UV binding, compressed mipmapped maps,
  material mode, frame completeness and actual imported contact are checked.
  Recorded texture bytes exclude driver overhead and inactive comparison
  resources; fixed-timeline captures are not FPS benchmarks. Never promote a
  candidate solely because the tooling or import checks pass.

### Front-end presentation

- `tests/frontend_presentation_test.tscn`: 65 contract checks covering the
  Canvas-only boot, title, shared backdrop, and loading indicator; authored
  texture bounds; portrait/landscape crop selection; reduced motion; semantic
  title CTA; and public loader progress API.
- `tests/frontend_shot.tscn`: isolated title, menu, boot, loader, and router
  captures through `run_frontend_qa.sh shot`. Use `touch=1` for phone layout.
- `tests/frontend_perf_probe.tscn`: cold first-present, boot-route hitch, title
  frame pacing, and draw-call gates through `run_frontend_qa.sh perf`.

### `tests/menu_load_test.tscn` (`tests/menu_load_test.gd`)

Focused menu smoke test: instantiates every menu scene listed above (same
skip rule for unwritten scenes), then drives `SceneRouter.go_to` to the main
menu and verifies the headless scene swap actually lands on `MainMenu`.

### `tests/race_sim.tscn` (`tests/race_sim.gd`)

Full-race integration test: boots the real race scene with all eight racers
under AI control (`RaceManager.autopilot_player`) at 12x time scale, requires
every racer to finish with no DNFs, and validates the results handoff to the
results scene. Parameters: `-- course=<id> difficulty=<id>`.

## Manual QA checklist

Player-facing flow (run on every release candidate):

- [ ] Title screen: logo visible, prompt pulses, any input advances to main menu.
- [ ] Main menu: every button navigates; focus visible; Quit hidden on mobile.
- [ ] Quick Race: mode select → course select → difficulty → countdown → race →
      results → rewards → Race Again and Main Menu both work.
- [ ] Grand Prix: all three rounds chain, standings shown between rounds, cup
      ceremony after the final, GP record saved.
- [ ] Time Trial: solo run, best time recorded, record banner on improvement.
- [ ] Endless Expedition: run ends cleanly, score/distance/fish on results,
      high score persists.
- [ ] Waddle School (tutorial): completes, `first_waddle` unlocks, reward paid.
- [ ] Pause during a race: game halts, resume/settings/quit-to-menu all work,
      quitting mid-race does not corrupt the save.
- [ ] Settings: change music/sfx volume, resolution, window mode, steer
      sensitivity — each applies immediately AND survives a full app restart.
- [ ] Controls: rebind a key, verify it works in a race, reset to defaults.
- [ ] Customize: buy an item with fish, equip it, see it on the racer in-game;
      balance and unlock persist after restart.
- [ ] Achievements screen: unlocked entries display correctly; toast appears
      when a new achievement unlocks mid-game.
- [ ] Save integrity: force-quit during a race and mid-menu; relaunch keeps
      fish, unlocks, records.
- [ ] Race readability: positions update promptly, checkpoint recovery returns
      racers to the track, no racer permanently stuck (watch one full AI race).
- [ ] Audio: music crossfades between menu and race; SFX for jump, slide,
      shove, item use, finish; mute and mute-on-unfocus behave.

### Resolutions to test (per GAME_SPEC section 20)

- [ ] 540×960 and 1080×1920 (portrait phones)
- [ ] Tall notched portrait phone safe area
- [ ] Portrait tablet (e.g. 1600×2560)
- [ ] 1920×1080 (baseline 16:9)
- [ ] 1280×720 (small window)
- [ ] 2560×1440 (where practical)
- [ ] 2400×1080 (wide mobile landscape)
- [ ] Landscape tablet (e.g. 1600×1200)

At each: no text overlap or clipping, HUD anchored correctly, menus centered,
touch buttons reachable, no horizontal letterboxing artifacts.

### Input methods to test

- [ ] Keyboard (default bindings and a remapped set)
- [ ] Gamepad (steer axis with deadzone setting, buttons, pause)
- [ ] Touch (steer drag zone, jump/slide/shove/item buttons, pause button,
      touch scale and opacity settings)

## Premium overhaul validation — 2026-08-18

- **Godot:** 4.7.1.stable.official.a13da4feb.
- **Full isolated suite:** 20/20 cases PASS. Includes 115/115 units, menu
  routing, 65/65 front-end presentation checks, 54/54 art-foundation checks,
  PenguinVisual facade, 96/96 runner platform checks, 25/25 golden-slice
  checks, 60-second runner simulation, eight-retry churn, all five race-course
  simulations, time-trial ghost, Endless, tutorial, and three-round Grand Prix.
- **Art authoring:** manifest validator PASS (`assets=3 exports=0 generated=3
  concepts=1`); Python tooling 5/5 PASS.
- **Cold Compatibility front end, 1920x1080:** two enforced runs PASS. First
  present 62.17/61.24 ms; worst boot frame 22.36/18.70 ms; steady title 60 FPS,
  p95/max 16.67 ms, 19 draw calls. No BPTC fallback warnings.
- **Runner, 1920x1080 after warmup:** Compatibility High 59.82 FPS, p95
  16.67 ms, max 84.76 ms, 241/268 average/peak draws; Compatibility Medium
  59.81 FPS, p95 16.67 ms, max 59.82 ms, 198/227 draws; Mobile High 59.98 FPS,
  p95 16.67 ms, max 18.06 ms, 189/224 draws. Every enforced run had zero
  frames above 100 ms.
- **Resource stability:** runner soak grew 0 resources over measured 30 s;
  retry churn reported zero orphans and no sustained resource growth.
- **Visual QA:** title, boot, route loader, and main menu reviewed at portrait
  phone and 1920x1080 landscape. Phone main-menu physical targets: hero cards
  104-107 px, secondary rows 59 px, utility floor 45.8 px.

## Last validation results

- **Date/time:** 2026-07-21 03:05 (local)
- **Godot:** 4.7.1.stable.official.a13da4feb (`/opt/homebrew/bin/godot`)
- **`run_tests.sh` summary:** ALL PASSED (exit 0) —
  `unit_tests` (49/49 checks), `menu_load_test`, `race_sim glacier`,
  `race_sim aurora`, `race_sim iceberg`, `time_trial ghost`, `endless_sim`
  (deterministic-seed check + storm-end flow), `tutorial_sim`,
  `grand_prix_sim` (3 rounds, 117 points distributed, standings sorted).
- **Difficulty coverage:** `race_sim glacier difficulty=chill` PASS,
  `race_sim aurora difficulty=emperor` PASS (all 8 racers finish at every
  difficulty tested).
- **Headless import/parse:** clean — zero script/parse/import errors.
- **Runtime log audit:** full windowed race run stderr shows no repeated
  errors (only Godot's benign exit-time ObjectDB note from force-quit).
- **Exports:** Windows (`waddle-wars-windows.exe`, 115MB), macOS
  (`waddle-wars-macos.zip`, 65MB), Linux (`waddle-wars-linux.x86_64`, 79MB)
  all export successfully with 4.7.1 templates; exported macOS app
  boot-tested headless (exit 0, no errors). Android preset validated but not
  built (no keystore on this machine); iOS documented in README.
- **Manual/visual checks:** screenshot review of title, main menu,
  mode select, customize, achievements, settings, results, pause overlay,
  countdown, mid-race HUD on all 3 courses + tutorial + endless, at
  1920×1080 / 1280×720 / 2560×1440 / 2400×1080. Fixed during review:
  penguin belly geometry, title logo overlap, washed-out palette, unthemed
  buttons, fish readability, fog density.
- **Known issues:** gamepad binding labels show raw indices ("Pad 0") in the
  remap screen. (Trail cosmetics now also render in the customize preview panel
  as of the 2026-07-24 checkpoint.)

## Supervisor final validation — 2026-07-24 (post-cutoff)

Reset deadline 2026-07-21T06:59:53-04:00 has passed. Fastest meaningful
validation run on the working tree at final checkpoint:

| Check | Command | Result |
|-------|---------|--------|
| Parse/import | `godot --headless --import .` | clean, 0 errors |
| Race sim (glacier) | `godot --headless tests/race_sim.tscn` | PASS, 8/8 finish |
| Race sim (aurora) | `... -- course=aurora` | PASS (earlier run) |
| Race sim (iceberg) | `... -- course=iceberg` | PASS (earlier run) |
| Power-up activation | instrumented sim | 10 activations, was 0 |

Outstanding defects tracked in QA_FINDINGS.md: 4 FIXED, 14 OPEN. `run_tests.sh`
full suite exceeded 10 min wall-clock in the supervisor environment — recommend
a fast-subset flag before relying on it in CI.

## Prod-readiness round — 2026-08-05

Full audit (9 agents, 67 raw findings → verified list) + fix round (6 agents)
+ optional online leaderboard (Clerk + Cloudflare Worker + D1). Validation on
the working tree:

| Check | Command | Result |
|-------|---------|--------|
| Parse/import | `godot --headless --import .` | 0 script errors |
| Unit suite | `godot --headless tests/unit_tests.tscn` | 50/50 (adds leaderboard menu-load) |
| Race sim glacier | `... -- course=glacier` | PASS |
| Race sim aurora | `... -- course=aurora` | PASS |
| Race sim iceberg | see flake note below | PASS (battery) |
| Endless sim | `tests/endless_sim.tscn` | PASS |
| GP sim | `tests/gp_sim.tscn` | PASS (3 rounds, tiebreak-sorted standings) |
| Tutorial sim | `tests/tutorial_sim.tscn` | PASS |
| Boost arrows | `tests/pad_shot.tscn` top-down captures | direction + scroll verified |
| Leaderboard API | curl health/board/401 checks | all correct |
| Visual QA | screenshot_tour: menu, leaderboard, countdown | reviewed; control-strip contrast fixed |

2026-08-06 fidelity-round rerun: import 0 errors; units 50/50; sims PASS
glacier/aurora/iceberg×2/endless/gp/tutorial (SUITE-DONE, exit 0). Iceberg
causeway tilt at 13° also passed a separate 3/3 battery (15° caused one
Marina DNF and was reverted).

2026-08-06 mega round 2: part-1 (sharing/minimap/UI) battery — units 50/50,
glacier/aurora/iceberg/tutorial PASS. Post-physics-pass battery — import 0
errors, units 50/50, all sims PASS except iceberg 2/3 (one triple-AI-DNF
run; 8/9 including follow-up reps). After making platform carry player-only
and halving AI-vs-AI bump impulses: iceberg 8/8 PASS + glacier PASS.
Physics jump-arc parity checked by the agent analytically (airtime 0.83s vs
0.73s, height 2.10m vs 2.02m — gaps only get more forgiving).

Iceberg flake investigation: baseline b0a5c19 timed out 3/6 sim runs — a
pre-existing autopilot resonance (boost pad 16m before the moving-platform
crossing + fixed respawn cadence re-hitting the same platform phase), NOT a
regression from this round (verified by stash-and-rerun bisect). Fixes: pad
moved 70m upstream, randomized 0.2–1.4s post-respawn stumble, and an AI
progress watchdog (respawn if <6m course progress in 12s — catches full-speed
circling the position-delta check misses). Post-fix battery results recorded
in BUILD_STATUS.md.

2026-08-06 round 3: units 50/50; race_sim PASS for glacier/aurora/iceberg x
chill/competitive/emperor (9/9); endless_sim, gp_sim PASS; tutorial_sim 3/3
PASS. Bisect method that found the regressions: parallel git worktrees at the
suspect commit, each with one subsystem disabled, running tutorial_sim and
race_sim side by side. tutorial_sim's TIMEOUT diagnostic (player progress /
position / state) is what localised the hurdle stall — keep it.

2026-08-06 round 4: units 50/50; tutorial_sim 3/3; race_sim 9/9 across
glacier/aurora/iceberg x chill/competitive/emperor; endless_sim, gp_sim PASS
— with physics, hazard motion, grounding and Chrome warm-up all integrated.
Each was validated alone in its own worktree before combining, which is what
separated the real causes (low-speed steer assist; aggressive platform lurch
config) from the subsystems blamed first.


2026-08-07: units 63/63; menu_load 0 failures; race_sim PASS on all five
courses (glacier, aurora, iceberg, cinder, hollow); tutorial_sim PASS;
endless_sim PASS. Racer shader additionally verified under
`--rendering-method gl_compatibility`, which is the actual web path.

New QA harnesses this round:
- `tests/prop_shot.tscn` — stands one hazard or prop in a neutral set with a
  fixed camera (`prop=wind|icicle|bear`). Racing past an obstacle on autopilot
  gives it to you for a third of a second at whatever angle the course happens
  to offer; this is how the icicle's intersecting-plate collar and the wind
  zone's missing structure were actually seen.
- `screenshot_tour` gained `uiscale=` (layout bugs that only appear for players
  who raise the accessibility scale are invisible at the default),
  `shot=customize_buy` (opens the purchase confirmation) and
  `shot=course_select` (advances to the course picker so poster art can be
  checked rather than assumed).

Lesson worth keeping: three separate visual defects this round were found ONLY
by reading captured frames back — the icicle collar, the penguin's tail wedge
rendering as a mouth, and the polar bears standing behind a translucent wall.
None of them failed a test.

2026-08-07 (later): units 71/71 (adds 8 tilt-axis checks); menu_load 0
failures; race_sim PASS on all five courses with 8/8 finishers and no DNFs;
tutorial_sim PASS.

New harness capability: `GameConfig.force_touch` plus `touch=1` on
screenshot_tour renders the PHONE layout on a desktop box. Every touch-only
layout rule is gated on real hardware, so before this the phone layouts were
literally unrenderable here — which is how the results screen shipped running
off both edges despite being captured several times.

Two lessons from this round, both about verifying the wrong thing:
- `uiscale=` persists to settings.json, so a value left by an earlier capture
  silently changes every later one. A mobile fix got tuned against a canvas no
  phone has. The harness now pins ui_scale on every capture.
- Forcing `UITheme.is_touch()` alone was not enough: the canvas shrink lives in
  SettingsManager behind `GameConfig.has_touchscreen()`. Half-forcing the phone
  path produced a canvas that exists nowhere.

2026-08-08: units 91/91 (adds 12 ice-shield lifetime/i-frame checks and 5 shove
animation-envelope checks); menu_load 0 failures; race_sim PASS on all five
courses; time_trial ghost, endless_sim, tutorial_sim, grand_prix_sim PASS.
`./run_tests.sh` RESULT: ALL PASSED.

New QA harness this round:
- `tests/overlap_probe.tscn` — measures scenery that intrudes into the racing
  corridor, instead of hoping someone notices it while driving past.

  ```sh
  godot --path . res://tests/overlap_probe.tscn -- course=aurora
  ```

  Walks every guide (main and branches), builds the corridor from the deck
  half-width and a deck-1m..deck+6m headroom band, and triangle-tests every
  mesh against it. Reports each offender with its node path, world AABB,
  nearest arc offset, how far inboard of the deck edge it reaches and over how
  many samples — and prints the exclusions it applied (track ribbon, Area3D
  triggers, hazard classes, named furniture) so false negatives are auditable
  rather than silent. Flat decals and translucent VFX are listed separately
  from solid intrusions, because a reflection quad on the deck is not a defect
  and a mountain through it is.

  Run it on glacier as a control before trusting a threshold: glacier's
  offenders are almost all snowbanks and sastrugi sitting at or below deck
  level, so a run that flags them the same way it flags a mountain is
  mis-tuned.

  Baselines after this round's fixes: aurora 9 (was 17), glacier 21 (was 32),
  cinder 6. Aurora's nine are the six cavern arches and a lamp arm at 5.8-5.9 m
  overhead, plus the two ridge berms, which are the intentional wind channel.

- `screenshot_tour` gained `shot=race_shove`, and `pose_check` gained
  `impulse=lunge|tumble` and `view=behind`. Both save a *strip* of frames
  across the impulse rather than one still: a shove is a 0.4-1.0 s one-shot,
  and a single screenshot that misses the peak looks identical to the effect
  not existing. `view=behind` puts the camera where ChaseCamera actually sits,
  which is the only angle a player judges their own animation from.

Lesson worth keeping, again: the shove impact ring passed every test and read
as a white croquet hoop planted in the snow the first time it was captured.
Tests prove an effect fires; only a frame shows what it looks like.

2026-08-08 (later): units 107/107 (adds 12 pause/settings round-trip checks and
5 setup-entry-step checks); `./run_tests.sh` RESULT: ALL PASSED.

`screenshot_tour` gained `pause=settings`, which opens the pause menu and then
the settings overlay, so the in-race settings screen can be inspected.

Worth keeping: the pause/settings work is a case where a screenshot proves the
wrong half. A capture shows that settings RENDERS over the paused race; it
cannot show that Back hands the race back rather than unloading it, that the
tree is still paused underneath, or that Escape does not close settings and
unpause in one press. Those are the three ways this feature can be broken, and
all three are unit-tested.

The phone course-list overflow was diagnosed by measuring, not by looking. Two
guesses from the screenshot alone (the title Label's minimum width, then the
column width) were both wrong; printing `get_combined_minimum_size()` down the
tree found it immediately — card 647, inner content 720. When a layout overflows
and the cause is not obvious, walk the tree and print the minimums.

## Premium visual foundation and runner golden slice — 2026-08-18

All final probes used cold source snapshots with unique project identities and
isolated `user://` directories. The player's live save, settings and ghost
hashes were unchanged by this validation run.

| Check | Command | Result |
|-------|---------|--------|
| Cold import + full regression | `./run_tests.sh` | PASS, 19/19 cases |
| Units | isolated suite case | 115/115 |
| Art foundation | isolated suite case | 53/53; validator + Python 5/5 |
| Runner platform/layout/accessibility | isolated suite case | 88/88 |
| Runner golden contract | isolated suite case | 25/25 |
| Runner simulation | `runner_sim -- seconds=60` | PASS; 1,221 m, +1 resource/30 s, -0.1 MiB static |
| Runner retry churn | `runner_churn -- runs=8` | PASS; 0 orphans, +0 resources/cycle, +0.00 MiB/cycle |
| Five race courses | isolated suite cases | PASS: glacier, aurora, iceberg, cinder, hollow |
| Other modes | isolated suite cases | PASS: time-trial ghost, endless, tutorial, Grand Prix |
| Runner Compatibility performance | `./run_runner_perf.sh tier=high w=1920 h=1080 seconds=30 enforce=true` | PASS: 70.28 FPS avg, 19.2 ms p95, 80.65 ms max, 230/251 draws, 47,262 primitives |
| Touch portrait framing | `./run_runner_capture.sh w=540 h=960 ...` | PASS: 15.0–17.5% hero height |
| Touch compact-landscape framing | `./run_runner_capture.sh ...` | PASS: 15.7–17.4% hero height |

`run_runner_capture.sh` now treats the 14–18% framing contract as a hard
failure. `run_runner_perf.sh` verifies requested/effective resolution and tier,
writes JSON + CSV, enforces a wall-clock timeout, and works under macOS Bash 3.

Godot still reports pre-existing ObjectDB/resource-in-use diagnostics when some
full scenes exit. Runtime runner churn shows zero orphans and no sustained
resource growth, but the shutdown diagnostics are not represented as fixed.
The runtime art manifest now registers the three production frontend textures
(orientation-specific expedition backgrounds and loading mascot) with exact
generated-source provenance. Authored character, obstacle, and course GLBs are
still outstanding; this remains a runner/frontend milestone, not the completed
full-app asset overhaul.
# Android b29 runner pre-probe checkpoint, 2026-10-04

Native covered runner loading now probes shader/resource signatures before
revealing unchanged real geometry. Focused warmup checks passed 56/56 and
48/48. Host-GPU Android emulator: first-installed runner visibly live in an
18-second capture; repeat cold-process entry visibly live in a 12-second
capture. No loader recovery captured. These brackets do not prove first
install <12 seconds or stable active play; iOS simulator and final suite remain
open. See `qa_shots/native/android-preprobe-b29-20261004/receipt.md`.
# Focused store/brand check — 2026-10-04

- Waddle Wars Play Data safety basic answers saved as incomplete draft only;
  deletion URL and final network data types not submitted.
- Clerk Production Google OAuth redirect read back. Google branding wizard
  staged, not created; legal-policy acceptance and credential creation pending
  explicit action-time confirmation.
- App icon v3 at 64/512 pixels and wordmark v3 visually inspected. Godot import
  passes. Native store icon format/hash unit test passes 1/1.
- `./run_frontend_qa.sh menu_mvp`: final run passes 24 fresh/live inset/scale
  cases and all menu content reachable at three phone sizes. Earlier 152-unit
  wordmark height failed 360×640; final 124-unit setting passes.
- Full `tools/art/validate_art.py` is not green: 125 unregistered WIP art files.
  Full regression suite deferred until candidate freeze per owner direction.
- No native signed build, public store submission, live web-auth cutover or
  deletion-page publication in this pass.
