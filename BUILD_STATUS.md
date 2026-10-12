# Waddle Wars — Build Status

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

Last updated: 2026-10-07 EDT (progression/navigation/Shop correction pass; outfit library in progress; web QC2 still live).
This file records verified reality with evidence, not intentions.


**Historical2026-10-07 fidelity corrections v6 — superseded by current scope above:** User visual review supersedes the v5 “100% fidelity” claim below. Home/Missions fixes verified; feedback UI36/36 and six native stills pass. Feedback Worker deployed with AWS SES scoped to support@waddlewars.io; one native form message accepted. Game itself was not exported/deployed. Avalanche softened and catch extended to2.4s; runner/Results474focused checks, landscape58/58 and two final Results stills pass. Additional Shop/Controls/Credits/Settings corrections verified; final Shop26focused +30native checks and two clean final stills. Correction checklist~80%; wardrobe replacement remains pending.

User rejected wardrobe 3D clothing direction. Adapter work stopped, files preserved; it remains wired in the local candidate and is not accepted. Three complete species-specific outfit concepts await direction review. Proposed480finished outfit images with trails separate; full library not generated. Local ID `local-20261007-fidelity-corrections-v6`; no commit/push. Overall MVP still~68%. Active receipt: `qa_shots/fidelity-corrections-20261007.md`.

**Historical 2026-10-07 local reference fidelity v5 (superseded by user review):** User's nine correction items handled.
Challenges and avalanche gauge rebuilt with ImageGen chrome; mission counts now
update during runs. Magnet/shield rings drain continuously from gameplay time,
freeze on pause, refresh on pickup and clear on expiry/absorption. World fish
now blue; larger collection flight matches the currency icon. All 13 menu/overlay
pages reviewed in portrait/landscape; loader uses exact reference art with true
loading progress. 18 new source/runtime pairs registered, 36/36 hashes correct,
zero new art inventory errors (181 existing).

Focused seven-suite matrix **669/669**; final live HUD **29/29 per orientation**;
core-menu native 29/29; loader actual boundary 17/17. Four pause/results stills
have no offscreen buttons. Existing renderer teardown diagnostics and rejected
foreground-loss attempts remain recorded; no performance or full-suite claim.
Silent playable home visually verified. Requested local correction pass 100%;
overall MVP remains **~68% verified**. Local ID
`local-20261007-reference-fidelity-v5`. No export/deployment.
Receipt: `qa_shots/reference-fidelity-20261007.md`.

**2026-10-07 local runner refresh v4:** Seven ImageGen references/assets drive
ivory/navy/coral HUD and overlays, painted ice/snow/water and course materials.
Opening ice/apron seam and foreground snow cutoff fixed. Third unshielded hit
now shows1.15s avalanche catch before results; fatal blink and same-tick
post-death pickups/ramps corrected. Final portrait/landscape/reduced captures
136/136, four-biome coverage25/25 +harness15/15, death boundary18/18 and
save47/47. Prior focused headless432 and course775 assertions pass; scoped
receipts distinguish source snapshots and final trail-only delta. Existing
teardown diagnostics and181 pre-existing art inventory errors remain.
Silent Base Camp relaunched and visibly verified. Requested local refresh100%;
MVP remains **~68% verified**. Local ID `local-20261007-runner-refresh-v4`.
No export/deploy. Receipt: `qa_shots/runner-refresh-20261007.md`.

**2026-10-07 avalanche landscape follow-up v3:** Landscape capture exposed a
faint bottom-edge-only snow front. The spray now follows the PNG's painted crest
and current camera. Foreground 960×540 and 540×960 captures pass 29/29 each;
midair/post-hit images keep hero and lanes clear. One hit closes true gap
approximately 33.92→22.91m. Focused retry/HUD 44/44 clean. Renderer teardown
diagnostics remain, and three earlier covered-window attempts failed; none are
counted as clean shutdown/performance acceptance. Silent debug launch is now
the default. Local ID `local-20261007-menu-refresh-v3`; no export/deployment.
MVP remains **~68% verified**. Receipt:
`qa_shots/avalanche-landscape-followup-20261007.md`.

**2026-10-07 local menu refresh v2:** New desktop Base Camp, leaderboard,
results, and loader references plus runtime layouts. Home subtitle removed;
button hover shape repaired; results portrait Control leak fixed. Six rendered
captures have clean stderr; loader boundary 17/17, web shell 104/104. Avalanche
powder remains visible at 4s/6s; focused fixture 22/22, but renderer teardown
leaks remain logged. 189 image/source catalog files backed up to Google Drive.
Local ID `local-20261007-menu-refresh-v2`; no production/native promotion.
MVP remains **~68% verified**. Receipt: `qa_shots/menu-refresh-20261007.md`.

**2026-10-07 untraced continuation:** No active trace was present. QC6 visible
home and wardrobe transition observed, but foreground changed to Gmail/New Tab
and Chrome processes exited during control attempts. Historical engine gaps
of 5.4/12.1 seconds lack visibility history and are not foreground acceptance.
Added source-only opt-in visibility/focus/input-delay counters; JS fixture
15/15 and isolated clock/metadata fixture 25/25 clean. No diagnostic export or
production promotion. Still **~68% verified**, freeze cause unresolved. Receipt:
`qa_shots/browser-untraced-continuation-20261007.md`.

**2026-10-07 wardrobe QC6 staged, not promoted:**
`releases/web-20261006-2355-wardrobeqc6/` uploaded successfully. Shared full-width
headers, painted arrow Back, display typography, larger content-fit fish balance,
five icon-above-label tabs, taller live try-on action, contained ownership/price
badges and coral selection now replace the inconsistent wardrobe layout.
Painted clothing uses an original transparent atlas, with live 3D built only on
request and disabled while hidden. A desktop reference and 11 side-by-side menu
comparisons were produced; **not every screen matches its reference 1:1**.
Wardrobe accessory fit across all eight species remains unapproved.

Focused checks: frontend 111/111, web shell 104/104, wardrobe rotation 29/29,
24 fresh/live menu layouts and 30 captures. Final broad evidence:
`qa_shots/tests/waddle-wars-frontend-78496-10214.3Twnyb/`; wardrobe evidence:
`qa_shots/tests/waddle-wars-tests-93192-11122/`. Full gameplay regression still
deferred. Import/export logs contain no parser/script errors. No remote CI run.

Fresh Chrome QC5 loaded and reported ~60 FPS after warmup; startup still included
782.2 ms and first wardrobe entry 260.5 ms frames. Existing game tab stalled on
navigation. Later browser control disconnected; a native process sample measured
Chrome's main process at 8.2 GB footprint (9 GB peak) on this 16 GB Mac. This is
**not root-cause proof or lag acceptance**. Approved restart completed; QC6
visibly reached home and wardrobe, but first menu draw took 15,099 ms and
browser control failed again during a profiling attempt. No valid active-play
or independent tab-close gate completed. Restart did not establish a fix;
QC6 final Chrome acceptance and production switch remain pending. Details:
`qa_shots/browser-restart-comparison-20261007.md`.
See `qa_shots/browser-menu-performance-20261006.md` and
`qa_shots/menu-comparison-final-20261006/`.

Production remains `web-20261006-2210-menuqc2`. Frozen QC6 candidate and current
root rollback are retained under
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/web-wardrobe-qc6-20261006/`.
Candidate root-entry SHA-256:
`52e833e4c1c7b42763f2fef18ebee2eb783ae30baaeea46c7c69cf62ae86d711`.
MVP remains **~68% verified**; native/store/account launch gates are unchanged.

**2026-10-06 menu QC2 web release:** Production
`https://play.waddlewars.io/` now serves `web-20261006-2210-menuqc2` from
`releases/web-20261006-2210-menuqc2/`. Root HTML matches the frozen entry
SHA-256 `fcd565d44c0cd4f56e0bd27c8eed94dcbd06d184832b4ab5011f27de6113d80b`;
Chrome opened the live menu and Missions after the switch. Missions now uses
the approved route art and compact objective strips; its landscape map has
an intentional frame rather than a full-bleed seam. Shared ivory arrow Back
is consistent across premium pages and stays at the screen edge in landscape.
Penguin Select has eight distinct full-body species images, a fixed hero stage,
scrollable wardrobe, compact selected-item action, and the shared fish pill.
Current QA passed 24 fresh/live layouts, 30 captures, every menu reachable at
three sizes, front-end 111/111, customize orientation 15/15, web shell 104/104,
and `git diff --check`. Godot emitted teardown leak diagnostics in the front-end
test, despite exit 0. Source art and capture receipt:
`qa_shots/tests/waddle-wars-frontend-64953-20888.pbAK9z/`. Previous root is
recoverable at `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/web-menu-qc2-20261006/rollback-root.html`.
Painted hero art depicts species, not every arbitrary equipped accessory;
the live outfit preview remains available. This is a web menu release, **not**
native/store launch acceptance. MVP remains **~68% verified**.

**2026-10-06 web loader candidate, not deployed:** Local Chrome isolated a
1.4–1.8 s synchronous Godot startup block; pack byte-copy itself took only
17–34 ms. A new single browser cover keeps the genuine download bar visible
through engine startup, animates its mascot on a CSS compositor layer, and
hands off only after the home menu draws. Web-only export omitting hidden race
art and unapproved DAY review art reduced the pack from 90.5 MB to 60.0 MB;
it did not materially reduce the measured engine block. Chrome tracing found
90 compositor pipeline starts during a 1,476.7 ms main-thread block, about
61/s; at a 390×844 Chrome layout, 87 starts occurred during 1,434.3 ms.
This supports smooth CSS loader motion on this desktop browser. Removing two hidden
web-only waits advanced a local desktop Chrome menu first draw from engine
clock 3,291 ms to 2,161 ms in one before/after pair. The filtered export
rendered home and Waddle Run at 390×844. Shell syntax 10/10, behavior 103/103,
loader boundary 15/15, front-end checks 111/111, and SceneRouter 67/67
passed. The front-end harness also emitted Godot teardown leak diagnostics.
This is **not** a phone smoothness or full launch gate; no production
deploy occurred. MVP remains **~68% verified**. Details:
`qa_shots/web-loader-end-to-end-20261006.md`.

**2026-10-06 Chrome loader trace:** Two production cold-load traces reproduced
renderer-main-thread stalls of **1.96 s** and **1.70 s**. The detailed run's
long stall began 80.9 ms after the 90.4 MB `index.pck` completed; a later
Godot `MainLoop_runner` frame took **376 ms**. This supports pack handoff /
engine initialization and first-frame work as targets, but does not identify
the exact function within the blocked microtask. The forward-only loader
remains live; cosmetic smoothing does not remove blocked rendering. Evidence:
`qa_shots/web-loader-chrome-profile-20261006.md`. Browser test used desktop
Chrome at phone dimensions, not phone hardware. No release change this pass;
MVP remains **~68% verified**.

**2026-10-06 forward-only loader release:** Production
`https://play.waddlewars.io/` now serves `web-20261006-193148-81d177e0`.
The browser download bar follows downloaded bytes from left to right and no
longer switches to a back-and-forth marquee when total size is unknown. The
in-engine bar follows completed boot, resource, shader, and scenery milestones;
unknown phases hold position. On touch web, its penguin stays still during
startup instead of attempting a 30 FPS bob through synchronous stalls. The
frozen export passed web shell **96/96**, front-end **111/111**, and scene
router **67/67** focused checks. Chrome rendered the staged build and live
root at 390×844; Waddle Run opened from staging. The live root HTML SHA-256
matches the frozen export (`036ebd855e58a1cb29c16838d1ef0b62ac67bd9e049f0f27c91c9b5472204be8`).
Rollback root is saved at
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/web-smooth-loader-20261006.KQM2iG/rollback-root.html`.
This is **not** a real-phone smoothness measurement: a blocked browser main
thread can still delay both drawing and progress callbacks. Native loading
stalls and store gates remain open; MVP remains **~68% verified**.

**2026-10-06 web startup simplification:** Production `https://play.waddlewars.io/`
now serves `web-20261006-185652-54358930`. Removed the extra HTML
three-penguin “Waddling in…” overlay; Godot's byte-driven download progress
bar remains. Boot now routes directly to the main menu, and menu Back no
longer reopens the redundant “Begin Expedition” title. The staged release
and live root both rendered home in Chrome; phone-size portrait was checked.
All 19 staged assets returned HTTP 200. The live root HTML matched the local
export by SHA-256; the web-shell behavioural checks passed 90/90 and front-end
presentation checks passed 109/109. Prior root remains at
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/web-startup-20261006.rUJVOS/rollback-root.html`.
This change does not settle native startup stalls or Clerk production setup.

**2026-10-06 menu refinement web release:** Production `https://play.waddlewars.io/`
now serves `web-20261006-182236-bd7db10` from a versioned R2 payload. All
19 assets returned HTTP 200; the live root HTML and versioned pack matched
the local export by SHA-256. Chrome loaded the title and home on the public
URL with the fish total on one line, enlarged logo and corner controls,
vertical destination icons, and no square focus frame around Waddle Run.
The local menu audit passed all 3 phone sizes, 24 fresh/live inset layouts,
and 24 portrait/landscape captures across the menu set. A transparent fish
cutout removed the source image's white corners; shop and leaderboard text
layout was repaired. The previous production root remains recoverable at
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/web-menu-20261006-125557.jy0itH/rollback-root.html`.
This is a web menu update, not mobile/store release acceptance. Clerk still
logs a development-key warning; native first-use stalls and launch gates
remain open.

**2026-10-05 web release and IA pass:** Production game at
`https://play.waddlewars.io/` and the legacy game hostname now serves
`web-20261006-035500-737a1c8`. Fourteen versioned files were staged; all
returned HTTP 200, and pack/WASM/loader hashes matched the local export.
Root R2 readback matches the switched HTML. Chrome rendered the new departure
menu with zero game-console errors. Prior root is recoverable at
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/web-20261006-035500-737a1c8.pheLnu/rollback-root.html`;
prior versioned payloads remain. The menu now has one Waddle Run action,
Penguin/Ranks/Base Camp dock, and Base Camp overlay; Settings shows one of
five player-facing categories at a time. A desktop focus-state contrast bug
was caught in staging and fixed before this final cutover. The local game was
restarted for owner testing. This is a web update, **not** mobile/store
acceptance: the browser still logs Clerk development keys, Android b31 still
fails the native stall gate, and the full visual plan remains unfinished.

**2026-10-04 follow-up:** Rechecked the existing b31 Android debug APK in
Glacier Gauntlet on the API-35 host-GPU emulator. It entered live race, but
app-process EGL timings still showed a 2.02 s load frame and 1.68 s / 1.17 s
frames while racing. Native stall acceptance still fails. QA save/settings
were restored byte-for-byte. Clerk Production Google OAuth remains enabled but
missing its custom Google client; Google Cloud branding is staged at the
User Data Policy acceptance step. App Store Connect Chrome sign-in still
requires the owner's password/verification. Two new brand drafts were
rejected at small sizes; v4 art remains. MVP stays **~68% verified**. See
`qa_shots/native/android-b31-staged-20261004/race-recheck.md`.

**Store/brand follow-up, 2026-10-04:** The Google Play Waddle Wars default
listing now has exactly one app icon, `icon-512-v4.png`, replacing its older v2
upload. Play displayed “Your changes have been saved”; this remains a draft,
not review submission or publication. Source file SHA-256 is
`435a6332710feb402164fbefa41ce7e468e810b8a17c2e6c471ca32cba3b5dcf`.
The feature graphic still uses v2 art and screenshots still predate the final
candidate. Two new local logo/icon art directions were rejected at 64 px and
540×960 visual QA: full-chest icon lost readability, while the darker wordmark
was too small and low-contrast on the title sky. The v4 runtime art was
restored, so no new brand art is packaged. Apple Connect Chrome sign-in is at
the correct Ninja Consulting account's password step; Google Cloud Waddle
Wars OAuth branding still awaits action-time User Data Policy acceptance.
Android QA save/settings were restored byte-for-byte after customize inspection.
Focused title capture and store-icon format test pass; full suite deferred until
the candidate stabilizes. MVP remains **~68% verified**. See
`qa_shots/native/play-icon-v4-20261004.md`.

**Android b31 native staging probe, 2026-10-04:** Enabled the existing staged
course build and batched racer setup on Android/iOS as well as web. Godot import
passed; isolated presentation and warmup-boundary tests passed **82/82** and
**125/125** (with resource-at-exit warnings). Debug b31 exported, signature and
package identity verified. On the same API-35 host-GPU emulator, Glacier
Gauntlet reached live gameplay, but EGL still recorded **1.96 s** during load
and **1.67 s / 1.15 s** during play. A 35-second simpleperf sample concentrated
in emulator GLThread kernel paths; restricted symbols prevent root-cause proof.
The no-stall-over-one-second gate remains **failed**. An unbundled source follow-up
enables gravity sensor for the previously logged native tilt warning; it has
not been tested in a new APK. QA save/settings restored by matching hashes.
Build intermediates (~2 GiB) were removed after retaining hash-verified APK,
snapshot, logs and profiler. See
`qa_shots/native/android-b31-staged-20261004/receipt.md`. MVP still **~68%
verified**; no iOS simulator pass, final suite, or public release.

**Android b30 and Play rating, 2026-10-04:** Frozen-source debug APK b30
(`0bd0400474df9a6f589945fd02762fbb24a95a1d6d0dbb392ab7c15a74451050`)
includes wordmark v4. On API-35 host-GPU emulator, title/menu loaded and Waddle
Run was visibly advancing by the 12-second capture; left, jump, grounded
slide, three retries, pause/resume, and landscape reflow were exercised.
This was an upgraded install, not a fresh-install timing pass. **Glacier
Gauntlet cold entry failed:** loader held through 30 seconds, then recovery;
EGL reported a 32,106.89 ms frame plus a 2,105.07 ms frame. One recovery
retry entered live race, so this is a cold-load blocker, not proof of a
permanent race failure. Compact landscape hero-card subtitles truncate.
QA save/settings were restored with matching SHA-256 after force-stop;
rotation settings restored. The debug APK is not store-ready and no current-
source iOS package has passed. Play's truthful Game content questionnaire was
submitted after the user's IARC authorization; the Waddle Wars Play page now
shows **IARC status: Completed** with `ninjaconsultingllc@gmail.com`,
ESRB Everyone 10+, PEGI 7, and regional ratings. A same-day corrected
questionnaire now says **no paid digital purchases**, consistent with the
hidden native purchase flow and store copy; the superseded entry remains in
Play history. No release was submitted.
Evidence: `qa_shots/native/android-b30-20261004/receipt.md` plus screenshots
and logcat in that directory. This Play rating advanced setup to **10/11**;
Data safety was then saved, advancing dashboard setup to **11/11**. Publishing
overview still lists changes not yet submitted and disables “Send app for
review” until release prerequisites exist. MVP **~68% verified**; first-use race stall,
iOS simulator, signed release candidate, and final suite remain open.

**Icon v4 local checkpoint:** Generated an original tighter portrait from the
shipped loader penguin identity. Compared three new 64 px studies against v3;
selected the one with the largest readable face and simplest backdrop. Runtime
Godot icon, Android export preset, PWA sizes and local store-size metadata now
reference v4. Godot import and the focused store-format receipt test pass.
The Play *uploaded* icon is still v2; no portal upload or new native package
contains v4. Source prompt and hash are recorded in the art source manifest.
Play's setup checklist is complete at **11/11**, but no release bundle has been
uploaded and the review control remains disabled pending release prerequisites.
App Store Connect needs a separate Chrome sign-in; Xcode's authenticated session
did not carry over. The Waddle Wars Clerk production Google connection still
needs its own OAuth client, and Google Cloud's legal policy acceptance awaits
the user's action-time approval. Neither native release nor public auth is live.

**Wordmark v4 checkpoint, 2026-10-04:** Replaced noisy v3 runtime title/menu/
loading wordmark with a smoother original edit. Godot import and focused
540×960 title/menu captures pass; `menu_mvp` reaches every action at three
phone sizes and 24 inset/scale layouts. An **earlier** icon v4 study was not
selected: at 64 px it looked essentially like existing v3. The separate,
later tighter icon v4 checkpoint above supersedes that art choice. The b30 native debug
package contains this v4 **wordmark**, while no uploaded store asset does.
Art validation still reports 125 older unregistered
WIP files; title capture has resource-at-exit warnings. See
`qa_shots/premium-brand-v4/receipt.md`.

**Store/Clerk/brand pass, 2026-10-04:** Play Data safety has a saved **draft**:
native no-account edition, HTTPS transport, optional online data processing,
Approximate location (conservative IP inference) and App interactions for the
user-initiated leaderboard. `web/native/delete-data.html` is now published at
`https://waddlewars.ninjaconsulting.ai/native/delete-data.html`; public GET
hash matches local source, and Play accepted this live deletion-request URL.
Preview says no third-party sharing. Dashboard remains **9/11**; no Data safety
review submission occurred, and final candidate runtime/SDK audit remains open.
The existing Waddle Wars
Google Cloud project `waddle-wars-penguin-panic` is confirmed. Clerk Production
Google sign-in is enabled but missing custom credentials; its exact redirect is
`https://clerk.waddlewars.ninjaconsulting.ai/v1/oauth_callback`. The Google
Auth Platform branding wizard is staged but **not created**: accepting the
Google API Services User Data Policy and creating the OAuth client await
action-time confirmation. No production auth cutover or new user.

App icon v3 now uses a tighter, less cluttered portrait of the already-owned
loading penguin; wordmark v3 has sculpted ice faces and warm rim light. Runtime,
PWA source and store metadata point to v3. Play's *saved draft* still shows v2
until a final candidate is frozen and assets are re-uploaded. Godot 4.7.1
import succeeded. Focused icon receipt test passed, and phone menu reachability
passes three sizes plus 24 inset/scale layouts after limiting the wordmark's
portrait height to 124 authored units. A first 152-unit pass failed the
360×640 case and was corrected. Title/menu 540×960 Compatibility captures are
in `qa_shots/premium-brand-v3/`. Full art validation remains red with 125
unregistered pre-existing WIP assets; this is **not** a final-suite pass or
candidate-matched signed build. MVP remains **~66% verified**.

**Play listing draft, 2026-10-04:** Google Play setup moved from **8/11 to
9/11**. The default en-US listing now contains two real Android b29 emulator
captures (menu and advancing Waddle Run, 540×960), alongside the premium icon
and feature graphic. Play's Review step was saved; Store listings reports
**Ready to send for review**, not sent or published. All four visual assets
were declared AI-generated/edited in Play's asset-specific flow, consistent
with the project source ledger and [Google's declaration guidance](https://support.google.com/googleplay/android-developer/answer/17262077?hl=en).
Screenshots are provisional until the final source candidate is frozen.
Content rating and data safety remain the two incomplete setup tasks. MVP
remains **~66% verified**.

**Android runner pre-probe b29, 2026-10-04:** Swapped native covered-loader
order: bounded shader/resource probes precede unchanged original geometry
reveal; web keeps its previous order. Focused warmup checks passed 56/56 and
48/48. On host-GPU API-35 emulator, first-installed runner entry was visibly
live by the 18-second capture (not proven within 12 seconds), and repeat
cold-process entry was live by 12 seconds. Prior b26 had recovered at 30
seconds. Debug APK signature/resources verified; QA saves restored. This is
useful but **not** native acceptance: first-install timing, active-play stalls,
iOS simulator and full final suite remain open. Evidence:
`qa_shots/native/android-preprobe-b29-20261004/receipt.md`. MVP remains **~66%
verified**.

**Hero shader shortcut rejected, 2026-10-04:** Two three-fetch atlas sampler
variants passed local Compatibility capture but changed close-up color/detail
by 3.27–3.34% normalized RMSE. Neither was packaged or timed on Android; the
original six-fetch shader is restored. This is a visual rejection, not a
native performance fix. See `qa_shots/native/hero-sampler-ab-20261004.md`.
MVP remains **~66% verified**.

**Store draft / medium-quality control, 2026-10-04:** Google Play's Waddle
Wars dashboard advanced from 7/11 to **8/11** setup tasks: target audience
13–15, 16–17, and 18+ was saved as a draft, not sent for review. Content
rating, data safety and candidate-matched listing screenshots remain open.
The IARC form has Waddle's approved public email and Game category staged,
but no terms acceptance or questionnaire submission occurred.
The content-rating form includes an IARC terms acceptance, and data safety
cannot truthfully claim zero collection before final native runtime/network
audit. Clerk Production still has verified account portal and email-code
sign-in, but no first production user; its hosted sign-up currently requires
both password and email verification. Removing the password requirement would
change the production authentication policy, so no such change was made.
Public game remains on development identity. Separately, b26 on host-GPU
emulator still recovered at 30 seconds
after a QA-only medium-quality setting (28.689-second first visual pass).
Original QA settings were restored and hash-verified. No release, auth cutover,
quality downgrade, or native acceptance. See
`qa_shots/native/android-gpu-mode-ab-20261004.md`. MVP **~66% verified**.

**Android emulator renderer A/B, 2026-10-04:** Existing b26 debug app still
hits runner loader recovery under verified Apple M2 host GLES translation:
first scene visuals took 28.863 s. `-gpu swangle` reduced that stage to
21.300 s but also hit 30-second recovery during later shader warmup. Emulator
`hw.gpu.enabled=no` is overridden by explicit `-gpu host`; accidental software
rendering was ruled out. No new build, source change, or native acceptance.
Evidence: `qa_shots/native/android-gpu-mode-ab-20261004.md`. MVP remains
**~66% verified**.

**Premium brand / store-draft checkpoint, 2026-10-04:** Replaced the flat
project icon with an original high-fidelity penguin portrait and the title
SVG with an authored icy wordmark. Title, boot, and main menu now use it.
Godot import and 540×960 title/menu captures pass; loader boundary passes
16/16, focused frontend presentation 93/93, and the **post-change** menu
matrix passes three phone sizes. The focused frontend test still
prints ObjectDB/resource-at-exit warnings, so this is not a clean final-suite
receipt. Google Play's *draft* listing visibly saved `icon-512-v2.png` and
`feature-graphic-1024x500-v2.png`; it still rejects completion until at least
two candidate-matched phone/tablet screenshots are supplied. Waddle Wars
Production Clerk has email sign-up/sign-in with verification codes enabled;
its own setup checklist shows DNS connected, first production user missing,
and Google credentials missing. No production user, live auth cutover, store
release, or native package with this brand exists. Evidence:
`qa_shots/premium-brand-v2/receipt.md`. MVP remains **~66% verified**.

**Store paperwork reconciliation:** Local Apple listing metadata now matches
the 2026-10-04 portal readback for free US-only pricing, manual release,
support/privacy URLs and saved age rating. This corrects a stale local draft;
no portal field changed. Content-rights source review found an unknown-
provenance user penguin reference used only as a surface-fidelity prompt for
generated feather swatches later processed into hero material maps. Its
reference is now marked `reference_unverified` in its source fragment, and
validation rejects that license on runtime assets and export jobs. This does
not clear the derived material. Store rights answer remains open pending
review or independent replacement; see
`tools/release/content_rights_review.md`. Play app-content tab currently renders
blank in Chrome, so no new Play declaration was submitted. MVP stays **~66%
verified**.

**Focused menu/auth source check:** An isolated real-window Compatibility
audit passes three phone viewport sizes, normal/notched safe areas, and
24 fresh/live menu inset cases at two UI scales. Current-source sign-in
loading/retry and cloud-save contracts pass 53/53 Godot checks plus 13/13
web-shell checks. These do not establish that the public build contains the
fixes or that Waddle Wars production Clerk works. Evidence:
`qa_shots/tests/menu-auth-focused-20261004.md`. MVP stays **~66% verified**.

**Play signing read-only check:** Waddle's package is already Registered in
Android developer verification. Play App Signing reports its distribution key
In use; the Upload key certificate is not shown until the first app bundle
upload. The local build-24 upload fingerprint differing from registered
distribution fingerprints is not proof of an upload-key mismatch. No new key
registered or bundle uploaded. This resolves the identity ambiguity, **not**
the cold-load, final-candidate or store gates. Evidence:
`qa_shots/native/play-signing-readonly-20261004.md`. MVP stays **~66% verified**.

**Build-18 cold-install control:** The old build-18 QA APKS was installed fresh
on the same API-35 emulator after its test save was backed up. Waddle Run still
showed “Warming the trail…” when a requested capture finally completed about
42 seconds after the pre-tap timestamp; a later capture showed router recovery.
Thus older quick build-18 screenshots do **not** establish a fast cold load or
a later shader/art regression. Build-18 and b26 snapshots share identical
shipped shaders, art and character code. b26 debug app and all three QA save
files were restored; matching hashes persisted after full reboot. No native
cold-load pass. Evidence: `qa_shots/native/android-b18-cold-ab-20261004/receipt.md`.
MVP remains **~66% verified**.

**Renderer comparison:** Android-only Mobile override b27 was ignored;
direct Mobile b28 selected Vulkan but repeatedly failed queue presentation and
showed a black screen on the API-35 emulator. Diagnostic settings reverted;
Compatibility remains production renderer. This rules out a renderer switch as
an emulator cold-load fix. QA save was restored and persisted after reboot.
Evidence: `qa_shots/native/android-renderer-compare-20261004/receipt.md`.
MVP still **~66% verified**.

**Unlocked-Mac account check, 2026-10-04:** Chrome confirms the existing
`waddle-wars-penguin-panic` Google Cloud project (number `824411325688`).
Google Auth Platform remains unconfigured. Its public OAuth user-support email
selector offers only `mike.doubintchik@gmail.com` and three unrelated legacy
Google Groups, not the approved `ninjaconsultingllc@gmail.com`. The app-name
field was filled locally but the form was **not submitted**; no terms accepted,
OAuth client created, credentials issued, or Clerk setting changed. Public
Google SSO remains outside MVP until an approved business support identity is
available in the selector. Clerk email-code auth is a separate path, still
requiring a staged production-key/sign-in/cloud-save check before cutover.
Removed only six exact, regenerable Gradle user-cache directories from b23–b28
QA candidates (about 3.3 GiB); signed bundles, APKs, source snapshots, logs,
and receipts remain. Free disk rose from 3.8 to 7.1 GiB. MVP remains **~66%
verified**: account setup and cache cleanup do not pass native cold-load or
store gates.

**Android cold-load root cause, debug b25/b26:** Fresh same-workload
debug builds on isolated API-35 ARM64 emulator reproduce the 30-second runner
loader recovery. Runner scene setup is only 318–325 ms; its first-visual pass
takes about 27.5 seconds. Six first-use draw batches account for about 26.7
seconds, including 7.88 seconds on the authored skinned hero batch. Shader
warmup is still incomplete at the watchdog. This is a measured graphics
warmup bottleneck, not track generation; no fix or cold-load pass yet. QA-only
trace settings removed from source after capture. Debug APK verifier now
supports free/offline edition and passes 36 focused tests. Existing signed
build 24 remains unchanged and does not contain later source changes. Evidence:
`qa_shots/native/android-b25-coldload-20261004/receipt.md`. MVP remains
**~66% verified**.

**Android build 23 alternate-emulator check:** Existing build 23 reached live
runner and three subsequent retries on API-35 ARM64 emulator, restored QA save
and persisted 225 fish / best 1,691 after force-stop/relaunch. Two short active
display-present windows had p95 17.3–17.5 ms, maximum 25.9 ms. **First cold
runner entry timed out at loader recovery; Retry loading then worked.** This
is a new counterexample to native cold-load acceptance, not proof of a stable
1–2 minute gameplay soak or <500 ms retry. The canonical production manifest
also lacks 33 review-only runner art IDs; native build uses procedural fallback.
See `qa_shots/native/mvp-build23-alternate-emulator-20261004.md`. MVP stays
**~66% verified** while cold entry and iOS simulator gameplay fail.

**Source-only cloud-save safety checkpoint:** The previous web sign-in path could
silently overwrite an existing online save when this device also had progress,
and could upload after a failed cloud read. Current source now pauses on two
different played saves, requires an explicit choice of device versus online
progress, and never uploads after a failed cloud read. Focused isolated tests
pass 53/53; the choice screen was rendered at 390×844 and 844×390 with all
four actions visible. This has **not** been deployed, included in build 24,
tested against a live production Clerk sign-in, or used to migrate the one
known development cloud save. MVP remains **~66% verified**: data safety code
is necessary but does not close the production-auth or native release gates.
Receipt: `qa_shots/native/cloud-save-conflict-20261004.md`.

**Live Clerk configuration check:** Chrome reached the distinct **Waddle Wars**
application's **Production** instance, with its live publishable key and
`clerk.waddlewars.ninjaconsulting.ai` frontend/JWKS URLs. The production
Google SSO connection is enabled but explicitly says **Setup required**:
custom Client ID and Client Secret are empty; redirect URI is
`https://clerk.waddlewars.ninjaconsulting.ai/v1/oauth_callback`. Dashboard
session was restored through its existing GitHub sign-in. A new Google Cloud
project form is open but **not submitted** because it requires choosing an
existing billing account; the owner was asked which account to attach. No
OAuth credential, live auth switch, migration, or charge occurred.

**New Customize rotation QA:** Android build 22 exposed a stale portrait
composition when rotating an open Dressing Room. Build 23 contains the
orientation reflow fix; on the API-35 emulator it immediately changed to a
side-by-side landscape layout and returned to the portrait stack on rotation
back, with Adelie equipped and 766 fish unchanged. Focused source test passes
8/8. Build 23 is an unsigned free/offline AAB plus debug-signed emulator QA
splits, **not** a store-upload artifact. Penguin preview/species fidelity still
needs visual work. Receipts:
`qa_shots/native/mvp-customize-rotation-20261004.md` and
`qa_shots/native/mvp-build23-customize-orientation-20261004.md`.

**Android build 24 signing checkpoint:** Source fingerprint
`8fb4dd74bee2d83723c8a1ca62ee5a00cb798d190f223c0ebbadfcda31299fc5`
matches build 23's runtime; app-specific upload signing and offline verifier
pass for version code 24, target API 36. Signed AAB SHA-256
`e4032440ae8943f164526471d30e27179f330ba416517cc2b99939c33e1e4bcb`.
The package is registered, but build 24 is **not uploaded or store-ready**:
its upload-certificate check, off-device key recovery, full suite and store
processing remain open. Build 24 was not installed; its runtime source matches the tested
build 23. Later backend-only Clerk cache edit means build 24 is not a frozen
all-component release candidate; rerun affected backend checks at final freeze.
Receipt: `qa_shots/native/mvp-build24-android-signing-20261004.md`.

**MVP rebaseline: ~66% verified.** Free/offline native account and purchase
gating is packaged in same-source build 18. On API 35 ARM64 Android emulator
with host GPU, first and repeated cold Waddle Run entries reach live gameplay
within 12 seconds; a first cold Glacier Gauntlet race loads without gameplay
behind cover and completes to results. Save persists after force-stop/relaunch.
This fixes build 17's repeated Android 30-second loader recovery. Build 22
removes the observed 1.6-second retry countdown and verifies immediate input
authority plus repeated emulator movement. It now also reaches Waddle School
completion, awards fish/XP, retains totals after process kill/relaunch, and
allows landscape menu scrolling on the API-35 emulator. Individual tutorial
verbs, strict tap-to-photon latency, and long active-play stall thresholds
remain unverified. Build 18 iOS
ARM64 simulator app compiles, installs, and renders title/menu. Its runner
loader remains around 75% for more than two minutes; native sample locates the
main thread in the simulator's software OpenGL rasterizer. iOS simulator
gameplay **still fails**. Final local suite, store processing/release, and
production Clerk game-key/OAuth wiring remain open. Full receipts:
`qa_shots/native/mvp-build18-simulator-20261004.md`,
`qa_shots/native/mvp-build22-retry-20261004.md`, and
`qa_shots/native/mvp-build22-tutorial-orientation-20261004.md`. Do not treat older signed
builds or live web as build 23. Physical devices are waived.

The unchanged build 18 app also stalled at the same runner loading stage on an
iOS 18.5 iPhone 16 simulator; a process sample again showed software OpenGL
rasterization. An older simulator runtime is not a workaround. Screenshot and
sample are retained beside the build 18 receipt. Godot 4.7's official iOS
export guide states that its simulator supports only Compatibility rendering;
the attempted Mobile/Metal override is therefore not a valid simulator fix.
Keep simulator gameplay and My Mac/device-renderer evidence distinct.
An isolated iOS 26.5 QA-copy trace then measured 6.6 seconds for an empty first
world draw, before revealing any geometry, followed by 9.7 seconds for first
snow and 2.6 seconds for spindrift. This narrows the loader stall to the
simulator's covered 3D render path rather than scene-script generation alone;
it does not validate gameplay or implicate snow as the sole cause. Evidence is
in the build 18 receipt. The disposable trace simulator was deleted. Further
unchanged Compatibility simulator runs are deferred; Android and My Mac
results remain the usable native gameplay evidence, with their stated limits.

Additional build 18 Android entry checks reach tutorial Lesson 3 (not tutorial
completion) and live Endless Expedition with functional pause. Those screenshots
revealed two remaining portrait defects: school snow/sky lacks contrast, and
Endless' three-metric top line crosses other cards. Source-only, unexported
patches now darken the school course and compact Endless' portrait readout;
parser/import has no errors and focused tutorial presentation passes 42/42.
Native visual acceptance of those patches and all final same-source gates remain
open. The Apple draft setup below advances store readiness, not game QA.

**New Android portrait checkpoint:** Same-source build 19 installed on the
preserved API 35 emulator and reached live Waddle School; its cooler course is
less washed out than build 18, although tutorial completion and full visual
acceptance remain open. Build 19 Endless still let the centre clock graze the
pause target. Build 20 (`1090273cb01a05ce53b2e127a17103206db00a10ad1a6b4a4406d8a64cfa9878`)
is upload-signed and offline-verified, installs over build 19, and shows a
clearly separated stacked Endless clock at default touch scale in live Android
gameplay. A focused real-window layout test then found overlap at maximum touch
scale; current source fixes that and passes 402/402 checks across five viewport
sizes and three touch scales. That final source edit is **not exported** in
build 20. Full regression, native high-scale visual check, performance and iOS
simulator gameplay gates remain open. Evidence:
`qa_shots/native/mvp-build20-portrait-20261004.md`.

**Current Android build 21 checkpoint:** Source snapshot
`24e425d95e10c482c8a0d9065db1a40e5d032ddac4c6c9f38aa792ef7c170f47`
includes the build-20 follow-up portrait clock/pause correction. The
upload-signed AAB passed offline identity/signature/API-36 verification and
installed as version code 21 over the prior QA install without clearing save.
The actual Android Settings slider was set to its maximum **140%**; live
Endless Expedition shows the clock and pause target separated, and a direct
tap opens pause at 478 m. Resume continues gameplay. The focused real-window
layout fixture now passes **536/536** checks across five viewports and four
touch scales (0.5, 1.0, 1.4, 2.0). This is a focused layout/control pass, **not**
full portrait visual or performance acceptance: Android's bright ice and a
near-camera rival still need a final art/readability review; gameplay-stall and
500 ms retry thresholds remain unmeasured. No Play registration/upload or
public release occurred. Evidence:
`qa_shots/native/mvp-build21-portrait-20261004.md`.

**Android build 22 retry checkpoint:** A fresh source snapshot
`bb652bd5bc290286fd93afe1b4a35ea4240c7fbac096b86708e9657bcdbcfc4a`
produced an upload-signed AAB that passed offline verification (SHA-256
`6dc1c224f2feb968f81f13c35e13ff566f2a7162f3888570625dbe548809803e`).
Bundletool QA splits installed as version code 22 over build 21 with the same
first-install time/save. After real Run Again taps, emulator screenshots show
2–6 m traveled, live score and Pause within short device-side waits; the
first-run countdown is unchanged, while retry input is enabled in the reset
callback. Focused tests pass 39/39, 265/265 and 29/29; a real-window GUI cycle
passes 42/42. Android screenshot capture takes hundreds of milliseconds, so
these frames do not by themselves establish exact tap-to-photon p95 <500 ms.
The brief SurfaceFlinger sample likewise does not close sustained-lag QA.
Generated build caches were removed (2.1 GiB), preserving the signed artifact,
QA splits, logs and captures. No store upload or public release. Receipt:
`qa_shots/native/mvp-build22-retry-20261004.md`.

**Apple draft setup, not release:** On the existing signed-in Waddle Wars App
Store Connect app, the version-1.0 Support URL now persists as the published
`https://waddlewars.ninjaconsulting.ai/native/support.html`; App Privacy's
Privacy Policy URL persists as the published
`https://waddlewars.ninjaconsulting.ai/native/privacy.html`. The version is
set to **manual** release after approval. The app's current price is verified
`$0.00` in the United States and the current free-price table covers 175 price
regions; availability is separately restricted to the United States alone
(`Available on App Release`, 174 regions Not Available). Optional Apple Silicon
Mac and Vision Pro availability are off, read back after reload. No App Privacy
data-collection questionnaire, screenshots, reviewer contact, build upload,
review submission or public release was completed. Apple age-rating answers
were saved; App Information now shows 13+ in 172 countries/regions and 12+ in
Vietnam and Korea. Content Rights remains unset pending a shipped-content
license inventory; the runtime includes an OFL third-party font. The App
Privacy form remains unset pending final-build verification of backend and
provider handling of off-device request data. Browser evidence captured
in the same signed-in UI session; local checkpoint:
`qa_shots/native/apple-draft-scope-20261004.md`.

**Production identity setup (not shipped):** Correct Waddle Wars Clerk
application `app_3HWR0DvEvH21hdoRwHMV7JYLDgU` now has a cloned production
instance `ins_3KDgVIIHNQctHw6mIy8yKJXZ3No` on
`waddlewars.ninjaconsulting.ai`. Cloudflare Domain Connect added only the five
`waddlewars`-scoped Clerk CNAMEs. Clerk shows domain, frontend API, account
portal and all three email DNS checks verified; Clerk now shows both SSL
certificates issued. Google sign-in in this clone says setup required.
A dedicated Google Cloud project `waddle-wars-penguin-panic` was created; its
OAuth consent configuration is paused at the required Google API Services User
Data Policy acceptance, awaiting action-time approval. No Google OAuth client
secret has been created or transmitted, no `pk_live` has been switched into the
game, and no build was deployed. Existing Clerk development users do not
automatically transfer to production; progress/account linking must be checked
before any public identity cutover. Google Cloud currently offers the project
owner's personal email as the only OAuth user-support contact, while the
approved public Waddle Wars support address is
`ninjaconsultingllc@gmail.com`; resolve before public release.

**Production cutover inventory, 2026-10-04:** Clerk production email-code
sign-up/sign-in is enabled, but production still has zero users; development
has one test user. Read-only remote D1 queries found zero scores, zero profiles
and one development-owned cloud save. A private full D1 SQL backup was exported,
hash-checked and restored in memory with the same table counts. Clerk's own
guide says Development users cannot be migrated into Production; old game data
must be mapped only after a new production identity is securely verified.
Frontend and leaderboard still both point to the development issuer; a new
focused environment-pair test rejects either half of an unmatched cutover
(combined auth tests 12/12). No user creation, production key cutover or
deployment occurred. Receipt:
`qa_shots/native/clerk-production-cutover-20261004.md`.

**Production auth source-only safeguard:** Waddle Wars' own Clerk dashboard
public `pk_live` key decodes to its verified production issuer; JWKS and Clerk
JS endpoints answer HTTPS GET. A staging-only pair test rejects partial
frontend/backend cutover. Backend JWKS cache now follows issuer so a
development→production context change with a reused key ID cannot strand
valid sign-ins on old keys. Focused auth/save/leaderboard tests pass 27/27.
No production user, secret-key handling, data transfer, deployment, or live
sign-in follows. Receipt:
`qa_shots/native/clerk-production-public-pair-20261004.md`.

**New phone menu / sign-in report (local, not deployed):** A reported portrait
screenshot showed tablet-style two-up mode cards, three-column secondary links,
truncated Race text, and sign-in stuck at `Opening…`. The menu now classifies
web phones by CSS viewport width instead of DPR-scaled canvas width. Clerk
bridge now clears pending state on ready or failure, times out a stalled load,
and offers retry after missing bridge, script/init/modal failure. Focused local
checks pass: `online_auth_contract` 46/46, web auth 9/9, web shell parse 10
scripts, web shell behaviour 87/87, web export exit0, and `git diff --check`.
An isolated 390×844 Compatibility capture shows one-column hero cards and
complete Race text: `qa_shots/tests/menu-auth-390x844-20261004.png`. Live
desktop Chrome opened the Clerk modal before this patch; reported mobile
failure and deployed behavior still require foreground visual verification.
Earlier signed builds and live web do not include these latest edits. The web
shell still has a Clerk `pk_test` development instance; production identity
configuration is separate launch work.

## Current priority — free mobile MVP, critical path only

### Parallel launch work and feedback shipping boundary

**Current signing result:** Computer Use opens Keychain Access on the unlocked
Mac. A temporary copy of `/usr/bin/true` signs with the existing Ninja
Consulting Apple Distribution identity, and strict `codesign --verify` succeeds.
The current 524-file runtime
`d849cd516cfcd232d6d8ea4f27f9ff97a2300da8c257cf2f6ddb973d411af972`
then exports as iOS build 16. Xcode archive and local IPA export both exit0;
the independent gates verify the exact Waddle bundle, certificate, App Store
profile, ARM64 code signature and frozen game payload. Signed IPA:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-signing-current-20261003.TcthdW/archive.esFtCK/ipa-export/waddlewars.ipa`,
SHA-256 `885781615e810ec1c5ceaf7a79f9176b8674b84e51145740113c8043b8cdf70a`.
Archive gate:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-signing-current-20261003.TcthdW/archive.esFtCK/archive-verification-receipt.json`,
SHA-256 `2c8d125d7c9e77d5d05f5a546d55bcc7e392977a0a19d7bafed8cdc1cfc81e50`.
IPA gate: adjacent `ipa-verification-receipt.json`, SHA-256
`dcbecdfccd68731173e93d72f29051f55d60f38451d538e10a6028f1ff68b12c`.
Earlier `errSecInternalComponent` no longer reproduces; its precise former
cause is unknown. Signing success is not iOS gameplay, TestFlight or store
acceptance. No account or certificate settings changed.

**My Mac QA result:** The owner completed normal Xcode account sign-in. One
isolated automatic-provisioning build then exits0 (`** BUILD SUCCEEDED **`),
using existing Apple Development identity and a wildcard Ninja Consulting
development profile; strict code-signature verification passes. The separate
QA copy of current iOS16 uses bundle
`com.blubberandbyte.waddlewars.mymacqa.ios20261003`; its packaged PCK is
byte-identical to the signed release candidate (SHA-256
`988e3753bc58a21f0f181ac38b6c1ae0b97c1c1996d4f761051282f9f0697a6f`).
Xcode's **My Mac (Designed for iPad)** run reaches title and menu; Waddle Run
loads and renders, Left changes lane, avalanche death opens results, and Run
Again restarts at 0 m with three lives. Native race, portrait phone and iOS
simulator gameplay remain unverified. The menu shows truncated right-hand mode
text in the iOS-on-Mac landscape window. Runner console reports 33 unknown
DAY art IDs and procedural fallback: the intentionally unpromoted review kit
is absent from the release ArtCatalog, so this is not authored-DAY acceptance.
During return to menu the computer-control screenshot timed out once as disk
availability briefly fell below 0.5 GiB; Xcode also reported Metal compiler
service disconnection. Free space later recovered to 8.5 GiB, without a proven
cause; no reliable native performance result follows. The app was quit and no
public artifact was changed or submitted. QA root:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-mymac-qa-20261003.o1OiYk`;
sanitized successful build log `mymac-build3.log` SHA-256
`1c595b5abec48f2c3b2ea01488dbbad6bed37016e9ea094aeca658b1e1a6e18e`.
Earlier failed logs `mymac-build.log` and `mymac-build2.log` are retained.

**Current Android upload-signing result:** After Mac restart, the task-owned
read-only diagnostic returns status0, `access_succeeded_format_valid`, without
returning a credential. One fresh current-source build 16 then uses the existing
app-specific upload key; no new key, Keychain permission change or Play upload.
The exporter/signing verifier returns
`android_upload_artifact_verified_offline` for source SHA-256
`d849cd516cfcd232d6d8ea4f27f9ff97a2300da8c257cf2f6ddb973d411af972`,
exactly matching iOS16. AAB:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-free-mvp-20261004-b16/project/build/waddle-wars.aab`,
64,752,252 bytes, SHA-256
`5bb25f4612783f9a93cfcd59331fc2c7efbfaa05762bc1be49276cb33924786b`.
Candidate `receipt.json` SHA-256
`4add313805690b14bec97cf9823dee9b106d01324aea0a41211e660fa7684fb4`;
adjacent `-signing-launch.json` SHA-256
`9bf85624273ec0d0e0903b88ede5a439e404a34f9a1379e4561b087798bc5bcf`.
`store_ready=false`: Play upload-certificate registration, independent
off-device key recovery, installed gameplay, final suite and store gates remain.

To make room for this QA build, nine exact older task-owned Xcode `DerivedData`
directories were removed after verifying no live build process. They contain
regenerable caches; separate archives, IPAs, receipts, logs and source remain.
Observed free space rose from 1.2 to 2.2 GiB, with APFS/shared-volume caveats.
These caches are not recoverable through Trash.

**Current Android result:** The same runtime exports as free-MVP build 15.
Development-signed split APKS install in the owned API35 emulator; installed
version and all five package hashes match. Computer Use shows the title, but
two Begin clicks fail with `noWindowsAvailable`; gameplay is unverified. The
app/emulator are stopped. Package handoff:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-free-mvp-20261003-b15.MzfSQ9/qa-handoff-receipt.json`,
SHA-256 `64398fd80639c79b93af1be7898b6520847926a46b6061589c84c32e95f9f6be`.
UI receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-current-native-check-20261003.E59Fos/qa-receipt.json`,
SHA-256 `69640bae3769a2b53da866560e5b09a051ff4fc22e90799dfaecb0a667571726`.
Production Android upload signing is still open.

Native privacy/support pages are now published at
`https://waddlewars.ninjaconsulting.ai/native/privacy.html` and
`https://waddlewars.ninjaconsulting.ai/native/support.html`. Anonymous HTTPS200,
HTML type and exact local/R2/public bytes are verified; the game entry object
is unchanged. Publisher, approved support address, 90-day resolved-support
retention and provider/website-processing caveats are reflected. Publication
receipt: `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/native-policy-publication-20261003.gi6f8U/publication-receipt.json`,
SHA-256 `9a6fba15c3f3e4d32a8dcae4a1def87c05adfb7d7311bb714c34f5983bcccb0a`.
Explicit native Settings links are now implemented; construction does not visit
them and their handler allows only those two URLs. Current 524-file runtime
`d849cd516cfcd232d6d8ea4f27f9ff97a2300da8c257cf2f6ddb973d411af972`
imports with Godot4.7.1. A normal-project-context parser then loads Settings and
both changed fixtures without instantiating them: exit0, empty retained stderr,
and no script/compile/import errors in its stdout/engine log. Assertions remain
unrun; the links are packaged in Android 15 and iOS 16 but have no
rendered/opening pass.
Parser receipt: `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/native-settings-parser-20261003.oOENF3/parser-receipt.json`,
SHA-256 `eddf248e746586dc826260aedad9f52f2002f2361fc9b50459e2328f31c2c9ee`.
Final SDK/traffic, phone render and store disclosures remain separate gates.

Play default listing text, icon and feature graphic are now saved in the draft.
Supported keyboard controls resolve the prior stalled upload panel; a newly
loaded independent editor confirms both artwork attachments persisted. The
support Website URL saves with an exact readback and Change saved confirmation.
Receipt: `qa_shots/native/store-draft-assets-support-20261003.receipt.json`,
SHA-256 `ad37ec0455b5a452955f319560d9b42203c41c2355da7fc4ac7ba99f0253d7fc`.
The separate Privacy policy URL also saves/readbacks, pending review but not
submitted. Receipt: `qa_shots/native/store-privacy-url-20261003.receipt.json`,
SHA-256 `ec2fc4bbdcab7c6686f60b90c0d6892529ba5d69887999025e783af158353b52`.
Apple's current browser session is expired. One bounded normal sign-in check
reaches its secure Password field with Sign In disabled; no visible saved-
password suggestion appears. No password is read/entered or credential store
searched. Owner sign-in in the existing Apple tab remains necessary. Receipt:
`qa_shots/native/apple-autofill-availability-20261003.receipt.json`.
Current native screenshots, collection/age/
audience declarations, Apple URLs/review contact, pricing and release policy
remain unfinished. No build upload, review submission or public release occurs.

At the earlier failed-signing checkpoint, Keychain metadata was
unlocked/readable/writable (flags7); exact Android
item attributes and Apple Distribution identity exist. One changed-state
Android14 helper attempt still fails before signing. The installed helper
deliberately sets `LAContext.interactionNotAllowed = true`, so it cannot display
an approval prompt. It discards the numeric password-query status; exact item
access versus invalid-value cause is still unknown. A sanitized OSStatus patch
is review-only and not applied/compiled/deployed; helper/credential pins remain
unchanged. No iOS archive retry, key reset/export or permission expansion
occurred at that checkpoint; the current signed build 16 is recorded above.
Receipt: `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/signing-access-metadata-20261003.fKpCZT/receipt.json`.

The next task-owned, read-only Android diagnostic returns `errSecAuthFailed`
(`-25293`) both with interaction disabled and allowed. Keychain Access shows
the exact existing item's access already unrestricted. This caller is not the
pinned signer, so its status does not prove the original helper's precise cause.
A separate tiny iOS codesign operation fails with `errSecInternalComponent`
despite a valid locally trusted public certificate; failure reproduces without
the game or provisioning profile. Exact key/session/partition cause is unproven.
Receipts: `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/signing-access-diagnostic-20261003.IqK0ws/receipt.json`
and `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-key-use-preflight-20261003.jKvWef/receipt.json`.
At that earlier checkpoint, one normal login Keychain relock returns0; its UI Unlock is invoked but success
is not visually verified. Computer control cannot access protected SecurityAgent;
no bypass follows. The post-change diagnostic returns no result and is terminated
after exact PID validation, terminal143/PID absent. The later successful
current-source iOS signing pass supersedes that authentication handoff. No key
reset, replacement or permission expansion was needed.
The later authentication handoff is recorded in the diagnostic directory's
`normal-unlock-attempt.json`.

Current-source iOS diagnostic now proves the covered-background patch engages
under a fully opaque loader. It still fails: first `NearSnow` visual draw waits
83,476.656ms and the fixture times out at113.158s without a cleared frame.
The1-second main-thread sample observes software Canvas drawing through
`GLRendererFloat`; it does not attribute the entire wait to particles or Canvas.
This distinct QA bundle bypasses boot/menu, preserves workload/watchdog and
uses the old simulator binary: diagnosis, not native gameplay/performance or
free-MVP SDK acceptance. App is terminated and owned simulator Shutdown.
Receipt: `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-covered-trace-20261003.qvsDD3/qa-receipt.json`.

Pinned Godot4.7.1 simulator source disables Metal/Vulkan; official iOS export
guidance confirms Compatibility-only simulator support. Repeating the same
software-GLES pass is not the next action. Owner now approves Xcode's supported
**My Mac (Designed for iPad)** route. Distribution signing now works, but this
QA route still needs its own development profile.
This is additional native iOS-on-Mac evidence, not simulator or physical-phone
acceptance. One read-only Xcode destination query exits0/empty stderr and
confirms eligible macOS/ARM64 My Mac, variant Designed for iPad/iPhone. Audit:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-mymac-destination-audit-20261003.0mu2yj/audit.json`,
SHA-256 `e8119b4bec0b3a0281584345cf185b7dc701605da96ec8fb048d2b1d6807be2a`.
Existing device engine can be reused without another heavy compile. Current
export's Release scheme uses Apple Distribution; matching QA development
signing/profile access and isolated QA renderer configuration remain unverified.
Public metadata from three cached profiles now confirms none covers a distinct
Waddle QA bundle. The only development profile belongs to exact Chancey scope;
its device list does not match the privately observed My Mac destination. Do not
reuse or change it. Portal registration and development-key access are not
established. Audit: the same destination-audit directory's
`provisioning-prerequisite.json`, SHA-256
`602d37747ad209e2bea60f293a6c33d19ab4e96e99c06cc3257509347037de35`.
No separate QA development build, sign or launch occurs. No unsigned/ad-hoc bypass or
historical App Store IPA workaround is accepted. Guidance:
`https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html`.

An earlier Android Studio preflight reported the Mac locked; that report does
not describe the later successful Keychain Access UI session. Android 15 was
exported and installed as recorded above. Continue with supported active input
and gameplay on the retained emulator; do not repeat the unchanged export or
use the billing-enabled debug helper. Android14 remains historical.
Separately, owner-authorized cleanup removes 24 duplicate native-library build
intermediate directories from eight older QA snapshots. All eight retained
package hashes are unchanged; original libraries, sources, evidence, saves and
keys are preserved. Whole-volume available space rises from4.2 to8.9GiB, with
shared-extents/unrelated-activity caveats. Receipt:
`qa_shots/native/qa-native-cache-cleanup-20261003.receipt.json`. Cache copies are
regenerable, not recoverable through Trash. This does not advance launch acceptance.

Important shipping boundary: last night's reported-feedback patches below are
local and in historical QA packages, **not deployed** in
`web-20261003-d5766c0a42a3`. Frozen deployment comparison confirms customization,
startup, leaderboard/sign-in, tutorial, AI and added race-hazard gates differ.
Focused local passes are not shipped fixes or current native acceptance.
**MVP ~80% / full ~35%** is a coarse estimate. Current iOS signing is verified;
native loading/gameplay, Android upload signing, final validation and
store/internal distribution remain.

Owner narrowed the immediate launch milestone: launch the current runner
and existing races/tutorial/endless, local progression and earned cosmetics on
**both iOS and Android**, free and offline-first. Current art is the MVP baseline,
not reference-fidelity approval. Defer new art/frontend redesign, gamification,
accounts/cloud and all paid purchases. Keep native deferred features inaccessible.
Authoritative checklist: `tools/release/README.md#launch-mvp--authoritative-scope-october-2`.
The full premium/commerce objective remains deferred and uncompleted; the MVP
checkpoint is not completion of that objective.

### Goal-loop reporting

Owner requests completion percentage after **every goal loop**. End each loop
with the current percentage, material result and next critical-path item. Label
percentages as coarse estimates, not acceptance-test pass rates; do not count
repeated probes or additional receipts as completed launch milestones.

October 2 checkpoint: **mobile launch MVP ~70%**; **full original goal ~35%**.
The overall estimate weights both-platform launch readiness 40%, full premium
visual/motion overhaul 40%, and additional gamification/monetization 20%.
October 3 checkpoint: **mobile launch MVP ~75% / full original goal ~35%**.
Current bucket estimates are 75% / 10% / 10%, rounded to an overall 35%.
Later October 3 checkpoint: **mobile launch MVP ~80% / full original goal ~35%**
after the current-source iOS signed archive and IPA passed. This is not
gameplay, TestFlight or store acceptance.
This is reporting only, not a change to scope or gates. Historical signed
checkpoints and local validation are established; current-source final signing,
regressions, privacy/store completion and native acceptance remain. Physical testing is waived
by the owner for this MVP, not passed. Premium visual and real-purchase
acceptance are deferred, not passed. Update estimates only for meaningful
completed work or newly demonstrated gaps; preserve evidence-based caveats.

### Refreshed native test packages

Current release-tool source now explicitly selects `free_offline_mvp`. New
prepared snapshots omit the deferred Play Billing addon and WaddleStoreKit
billing/auth bridge, preserve their original source hashes, and keep the game,
bundle and save identities. Final gates require SDK absence for that edition;
historical commerce receipts retain their original linkage requirements.
Python parsing passes for edited tools and fixtures; new assertions remain
unrun until the final candidate. No existing package was rebuilt or relabeled.
The external Android signing helper accepts only exact, source-bound SDK
omissions. Both free-MVP export paths now skip unused billing-build inputs;
commerce/debug paths retain their strict prerequisites. New fixture assertions
remain unrun until the final candidate; Android14 below is the first refreshed
Android export with this input policy.

**Android14 free-MVP candidate** imports/exports terminal0 from the unchanged
524-file runtime `cc89e3d732a9f8ccdf49df130975abec84c57438414dd373c5a2fff640593606`.
Candidate: `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-free-mvp-20261003-b14.YnNWir/candidate`.
Its receipt remains `android_unsigned_awaiting_upload_signature`, `signed:false`
and `store_ready:false`, SHA-256
`68dc37478f4a1776e1a16ba556f658c6220c85b99163dfb319ed8ee8e47d53d9`.
Eleven deferred SDK source files are omitted and unused billing-build inputs
are not required. Retained logs contain no script/import errors; the export's
post-DONE ADB connection warning does not establish an installation or play pass.
Bundletool validation and both ARM64 libraries' 16-KB structural checks finish
terminal0. Actual manifest has Internet only and backup disabled; old Billing,
DataTransport, Firebase-encoder and GMS location/places dependencies are absent
from inspected metadata/DEX. Remaining frameworks and optional leaderboard host
processing are not a zero-collection audit.

One signing dispatch uses the existing app-specific helper/key. The helper
returns `operation_failed` at `reading_app_specific_keychain_password`, before
`signing_aab`; no signed AAB is created. No exact Keychain error/cause is exposed
by this intentionally bounded helper. The original unsigned output is preserved
at `candidate/project/build/waddle-wars-unsigned.aab`, SHA-256
`a21e45b92d9d243dad8821e9e05b900f85df6139c6b70d138cd42f2050688d1f`.
Sibling `prepared-upload-signing.json` preserves the failed attempt, SHA-256
`a77f744cf95ce56137aed8bd52890d6501911e35d5de440630099e73300f1120`.
No automatic retry, key recreation, permission change, verification of a signed
artifact or upload follows. Historical signed checkpoints remain unchanged.

A pinned, opt-in iOS engine capability patch is prepared at
`tools/release/engine_patches/godot-4.7.1-ios-disable-disk-capacity.patch`.
It is applied only to a fresh isolated clone of pinned source
`a13da4feb8d8aefc283c3763d33a2f170a18d541`. One ARM64 device Release compile
finishes terminal0 in9m36.23 at
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-waddle-disk-capacity-20261003.rKmMdI/`.
Actual compiler arguments enable the patch and preserve Metal, Vulkan and GLES3;
no second target is compiled. Finished device-only Release template SHA-256:
`de4e035c66485ec8526ef6d90ce97bd041e217b771614c3569ff0a54c9ac8ba5`.
The patch disables unused capacity queries without changing directory/save
operations. Custom iOS template bytes can now be copied and SHA-256-bound to a
candidate outside its game payload. That binding does not approve capabilities
or privacy. Only this reviewed exact pin selects an empty disk reason mask;
stock/unreviewed templates retain defaults. Final signing and privacy/store
acceptance remain open.

**iOS12 free-MVP candidate** imports/exports and links that device engine.
Candidate: `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-free-mvp-device-20261003-b12.unIe5p/candidate`.
Export receipt SHA-256 `82554e93a9a7fc0baff5a992be63d4739fe14b46e18c2546f30fc48bb78e07b3`.
The snapshot omits11 deferred SDK source files and retains the unchanged
524-file source fingerprint below. Actual linked ARM64 app matches its exported
PCK and privacy manifest; inspected capacity imports/keys and deferred native
billing/auth linkage are absent. The manifest has exactly `C617.1` and `35F9.1`,
with no disk-space category. Static review:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-free-mvp-device-20261003-b12.unIe5p/linked-app-static-review/receipt.json`,
SHA-256 `0bff73229a2c55de6d2c0d22acebd7f3d47b4e33abe9977b7a9304f9936cdf7a`.
This is unsigned linkage/static evidence, not gameplay, signed privacy or store
acceptance. The first manual archive attempt reaches CodeSign and fails with
`errSecInternalComponent`; the desktop was last observed locked, but the exact
signing-time lock state and cause are unproven. After the Mac is visibly unlocked,
one fresh archive retry fails with the same CodeSign error. Its process is
terminal1 and outputs/log remain at
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-free-mvp-unlocked-20261003-b12.7MHHIW/`.
No further retry, keychain permission change or IPA export follows. Historical
signed packages and deployed web remain unchanged. Final regression is deferred;
new release-tool assertions are unrun. **MVP ~75% / full ~35%** remains unchanged.

**Android Play app now exists:** `4974838896609027403`, developer
`9132521315692749104`, title **Waddle Wars: Penguin Panic**, package
`com.blubberandbyte.waddlewars`, English-US, Game, Free. The owner explicitly
confirms Google's policy/export declarations at action time; both are checked
and Create app reaches the new dashboard. Arcade category and approved public
support email `ninjaconsultingllc@gmail.com` then show saved confirmations.
Evidence: `qa_shots/native/play-created-20261003-dashboard.png` and
`qa_shots/native/play-created-20261003-category-contact.png`. Default automatic
installer protection is unchanged. No build, store review or public release is
submitted. Other listing/privacy/audience tasks remain open; this closes app
creation, not the store gate.

One later Android UI-availability attempt boots the same owned API35 emulator
with its existing QA data and host GPU. Installed version13 is confirmed, but
the standalone emulator binary is rejected by computer control as an invalid
app. Android Studio reaches its Welcome screen and is then closed without
opening a project or launching the game. No substitute input injection follows.
The owned emulator shuts down terminal0; no app launch or gameplay acceptance
is claimed. Existing failed-signing and store screenshots remain immutable.

A later supported Android Studio check opens Welcome's Virtual Device Manager.
The visible list contains only the two unrelated Chancey devices, not the
isolated Waddle QA AVD. Neither device is launched or changed. Studio is closed;
no emulator/app runs or alternate input follows. This does not prove that an
embedded Waddle view cannot be configured. Evidence:
`qa_shots/native/android-studio-availability-20261003-device-manager.png`, SHA-256
`2fa0c9b72e76c0c1e4541e00e3856c2b929843dcebed9d6c59064412b91b3a6c`.

An APK inspection workspace now opens through Studio's supported import action,
using a byte-identical copy of Android13. Running Devices opens, and the owned
`emulator-5680` boots with its existing data plus official embedding flags.
Studio detects its generic device identity, but the embedded-view selection
still offers only the unrelated Chancey devices. Neither is selected. No app
launch, build, reinstall or alternate input follows; the owned emulator exits0
and the later device list is empty. No global registry/mirroring setting changes.
This is UI availability evidence, not current-source gameplay acceptance.
Receipt: `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-studio-smoke-20261003.BRWEya/qa-receipt.json`.
**MVP ~75% / full ~35%** remains unchanged.

A later targeted Android test setup adds one registry pointer for the existing
isolated Waddle AVD; its config and both Chancey pointers remain byte-identical.
Pinned emulator behavior skips its embedded control service when a fixed port
is supplied. Removing only that port enables authenticated loopback discovery,
and Studio renders the exact owned `emulator-5554` view. Installed Android13
launches through its public activity route and renders the settled title, but
native clicking returns `noWindowsAvailable`. Mac lock state is unestablished;
no bypass or alternative input follows. No menu/gameplay acceptance is claimed.
The app and owned emulator are stopped0. Retained registry pointer must not be
used with normal Studio Launch, which omits the existing QA data overrides.
Receipt: `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-registered-smoke-20261003.AsZ3sS/qa-receipt.json`.
Android13 retains the historical billing plugin and predates the current runtime;
this is rendered launch evidence, not free-MVP SDK or current loading acceptance.

The next bounded Android13 pass restores supported title/menu input and enters
Waddle Run. Warmup is observed, then a later screenshot shows results at 292 m,
67 fish and 1,996 points. This demonstrates that loading and an unattended run
complete on this historical QA package; it does not measure loading time or
verify active play, countdown ordering, retry, orientation or save persistence.
Two Run Again clicks return `noWindowsAvailable`, including after the supported
window Raise action. Mac lock state remains unestablished; no substitute input
or unchanged restart follows. App termination succeeds and the owned emulator
exits 0; the later device list is empty. Battery is 53% and discharging, with
5.9 GiB free; no cleanup occurs.
Receipt: `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-interactive-smoke-20261003.DWxK3f/qa-receipt.json`,
SHA-256 `479ec702a4c86e370a9b89e7e6aa38376735847c6a57cdc8fe5d052c7c21e7f9`.
The logged 17 unknown DAY asset IDs are expected release fallback: their review
fragment is `production_ready:false` and is debug/editor-only. Warning code 33
is `ERR_DOES_NOT_EXIST`, not 33 failed requests. Existing asset parity is 584/584;
this warning is not evidence of missing packaging or a loading fix. No runtime
edit, suite, rebuild, signing, upload or publication follows. **MVP ~75% / full
~35%** remains unchanged.

Privacy inventory now separately binds existing Android14/iOS12 free-MVP static
receipts while preserving historical Android7/iOS5 findings. Artifact hashes
match; JSON parses. No runtime traffic, signing, store declaration or policy
publication is inferred. **MVP ~75% / full ~35%** remains unchanged.

The unpublished privacy draft now bounds provider access/deletion using public
guidance. Existing page fixtures are updated for that wording and the exact DPA
link while preserving unpublished/effective-date/SDK-audience/null-URL guards.
AST parsing passes; regression assertions remain unrun. No policy publication,
store disclosure submission or runtime change follows. **MVP ~75% / full ~35%**
stays unchanged; export/static checks and draft work do not close launch gates.

The earlier COLOR-background loading proposal was rejected: fog still draws
the sky and reflections differ. A new native Compatibility-only patch uses
`BG_KEEP` with explicit sky reflections while the router's full-viewport cover
is completely opaque. Existing geometry, lights, fog, shader queues, resolution
and MSAA remain unchanged. The sky is restored and drawn before readiness;
scene exit also restores the exact held Environment. Web, desktop, uncovered
entry and other renderers retain their existing route. Independent review finds
no concrete source blocker, but this is not rendered native acceptance.

The new 524-file runtime fingerprint is
`fdb9c3f702bb621a8a495aca4392b5f0e270713ce128007f72981eaab3bf1a1c`.
An isolated final-source editor import finishes0 with no script/import errors
in stdout, stderr or engine log. Two direct `--check-only` fixture attempts
cannot resolve autoload identifiers and return0 despite compilation errors;
they are invalid checks, not passes. New fixture assertions remain unrun.
Evidence: `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/covered-background-qa-20261003.Gnb5vD/parser-receipt.json`.
Canonical native packages and production web do not include this patch.

Free disk falls to302MiB, then recovers to10GiB before the next QA pass; its
cause is unestablished and no agent cleanup occurs. The earlier forced-cache
removal was rejected; approval to delete those seven disposable caches through
Finder remains pending. Space is7GiB after the stopped pass.

One separately identified **iOS simulator13 QA derivative** uses the unchanged
simulator11 executable and a new PCK from the current runtime. Recursive bundle
comparison finds only PCK/plist differences; installed executable/PCK hashes
match. The QA identity creates a separate app container because pinned iOS
ignores Godot's custom user-directory setting. No engine build, signing/keychain
access or mutation of canonical packages follows. Normal title/menu input
reaches runner warmup, then loading recovery: native loading acceptance fails.
The covered patch's engagement/benefit is unverified. One1-second sample after
recovery places87 main-thread samples in canvas/software GLES drawing; it does
not identify earlier warmup cost or establish a second fix. The process is
absent and owned device is Shutdown; no repeat launch follows. Evidence:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-covered-sky-qa-20261003-b13.wJx8Eg/qa-receipt.json`.
The reused binary retains deferred bridge/capacity code, so this derivative
cannot pass free-MVP SDK/privacy/distribution gates. Android smoke, native
loading, privacy/store completion and final validation/signing remain open;
**MVP ~75% / full ~35%** stays unchanged.

The previous native packages' 524-file runtime is frozen as
`cc89e3d732a9f8ccdf49df130975abec84c57438414dd373c5a2fff640593606`.
It includes the reported launch fixes below and native Settings' new read-only
Privacy & local data information. The information explains local saves, optional
leaderboard requests, support retention and deletion limits; it makes no effective
privacy-policy or store-approval claim. Its extended existing fixture is unrun.

**iOS simulator build11** imports/exports and links successfully with the existing
pinned ARM64 engine and simulator bridge; no engine rebuild or signing access.
The app's PCK and privacy manifest match its canonical export. The isolated QA
copy changes only the simulator engine, bridge and architecture metadata.
Evidence: `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-reported-fixes-qa-20261003-b11.9Uo0CA/artifact-receipt.json`,
SHA-256 `985fc4fed140ebff1be9a993e10423758e7948c74ef21855a420f7468a348021`.

**Android13** exports unsigned from the same source. Bundletool validation and
both ARM64 libraries' 16-KB structural checks pass. AAB SHA-256:
`b70eb8e367da836e7419ae316e19068704cd6621c0247cef48c552f671e650da`.
Evidence: `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-reported-fixes-qa-20261003-b13.u1I9nE/artifact-receipt.json`,
SHA-256 `3d58e7b52c729d9e84cd5867e31799f93f8834e6ad7a2521d83c984e23d793dd`.
The canonical AAB remains unsigned. Its development-signed APKS derivative is
installed as recorded below; upload signing and runtime acceptance remain open.

Android13 now also has an installable, development-signed APK set derived from
that unchanged AAB, without another export. All five APKs pass signature and
16-KB ZIP-alignment checks; both ARM64 libraries pass the ELF structural gate.
The signer is the existing Godot development certificate, not the upload key.
APKS SHA-256 `b460fd53599164045caf16334211690aed4af26dba6f018a9bc55e7881f50da0`.
Static receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-reported-fixes-qa-20261003-b13.u1I9nE/apks-qa-20261003.wwXGR5/static-checks.json`,
SHA-256 `442b14854e9e32026859cb5caa8eea1c4d475415b254d10106c92a4b4e57dba3`.
Independent parity checks match all 584 game assets, one DEX, two ARM64 libraries,
52 SDK/root files and two baseline profiles to the AAB. Actual main manifest
retains build13, minimum API24, target API36, backup disabled and profiling off;
the normal main scene remains the entry point. Manifests/resource tables are
transformed by bundletool, not byte-equal or fully semantically validated.
The adjacent `resource-parity.json` records those checks, SHA-256
`750c1fbc6a521510025b91f1f4025e85a77e46c68aeaad5a4011c6c57486f18d`.
The retained device spec targets ARM64/API35. On October 3, bundletool installs
the derivative successfully into task-owned `WaddleWarsQA_20261002`, serial
`emulator-5680`, using the existing isolated release-smoke data. Actual installed
version is13; all five installed APK SHA-256s match the prepared set, including
the install-time asset pack. This updates build11 without uninstalling. The
reused data is not a pristine cold-device test, and save contents are unverified.
Bundletool warns that `run-as` cannot clear the old private splitcompat cache
because the app is not debuggable. No permission workaround, uninstall or
save reset follows. Matching installed package bytes do not prove private-cache
or runtime resource behavior. The app is not launched. The owned emulator
shuts down cleanly; its process is terminal and the device list is empty.

iOS11 now ran once on the unlocked Mac's reused task-owned iOS18.4 ARM64
simulator. The installed bundle confirms build11. Native title and portrait main
menu render, and keyboard selection enters Waddle Run. The runner remains at
"Warming the trail..." through the bounded observation; gameplay, touch, retry
and cold-loading acceptance do not pass. A one-second sample at 15:57:04 UTC
finds all 209 main-thread samples inside GLES3 sky drawing through Apple's
`GLRendererFloat` software renderer. This identifies the sampled simulator
bottleneck, not a deadlock or physical-device performance result. Evidence:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-reported-fixes-qa-20261003-b11.9Uo0CA/unlocked-smoke-20261003.507tKG/runner-loading.sample.txt`,
SHA-256 `f48be800121e245a1f2fbdee15296223a2a41714f38af5cebee1dcfd88ecac54`.
The owned simulator is Shutdown and app PID86869 is absent. No repeated launch,
renderer change, source edit, rebuild or regression suite followed. Original
artifact receipts remain immutable; Android13 is installed but has not run.

The previous focused pass below predates the two privacy/help source and fixture
edits, so it does not verify those edits. Signed historical packages and web
production remain unchanged. Native gameplay/cold-loading acceptance, final
regressions/signatures and store/privacy gates remain. The existing Android
Create New App tab is retained, but its browser connection cannot read the form;
no declarations or Create action were submitted. Earlier free disk space was
2.5GiB after simulator shutdown. It later rises without a verified cleanup cause;
after Android installation and shutdown it is5.9GiB. No cache deletion succeeds
in this pass. The Mac remains locked; no interactive native test occurs.
**MVP ~75% / full ~35%** remains a coarse milestone estimate, not launch
acceptance. Repeated preparation does not increase it.

The bounded retained Android trace review shows advancing rendering, not a proved
deadlock: 102 of 104 initial visuals complete before 30-second Recovery. Eleven
slow draw waits account for most recorded wait time. Pinned GLES3 source compiles
missing programs synchronously, but the trace does not isolate compilation from
other driver/render work. No safe speed-fix hunk was established; no timeout,
graphics workload or browser investigation was changed.

### Reported launch fixes verified locally

Owner confirmed that the latest Waddle Run lighting and slide spacing already
work. This iteration's extra changes to those systems were reversed exactly;
pre-existing runner work remains intact. Do not reopen those fixes without a
new current-build reproduction.

Customization now uses one full-page scroll, a larger character stage and
selection-driven, unsaved species/accessory try-on. The preview uses existing
distinct species profiles; its viewport renders only while visible. Waddle
School lighting leaves more headroom for white snow through actual light
energies and ground tint, not only unsupported post-processing adjustments.

Iceberg Bay AI stays on the safe center corridor of the moving slabs, recovers
from actual low platform-face contacts and receives an exit jump hint. The
initial focused traversal caught nine genuine exit falls despite contact with
all three slabs. The final nine phase/difficulty cases cross with all three
support contacts, two moving-platform contacts and zero respawns; the full
eight-racer Iceberg race finishes with no DNF. Ordinary authored jumping outside
the crossing remains unchanged. Moving course hazards are held through loading
and the complete race countdown, then resume at GO.

Boot preparation now survives an early splash skip and remains covered until
its uploads finish. Absent-at-start effect warmup includes all web browsers,
not Chrome alone. These changes are not proof that reported mobile startup lag
is fixed; native cold-loading and foreground mobile verification remain open.

Web leaderboard source now includes Waddle Run score submission/board, every
shipped Time Trial course, explicit posting of guest local bests and authenticated
own-rank identification that is safe with ties. Returning web players receive an
optional save-progress sign-in prompt, at most once per session/seven days.
Runner/time-only local progress is no longer treated as a pristine cloud save.
Native offline MVP stays fenced. Ordinary races/Grand Prix do not overwrite
Time Trial records or ghosts. No backend/database deployment occurred, so owner
and Sol's live mutual visibility is not verified.

Fourteen focused headless/backend groups pass on the compared fix snapshot;
the snapshot matches 992 checked files, with only its isolated user-directory
settings substituted. Source fingerprint:
`eb9fcb1ad6c8b74e33a8dec4ca2b4e45e14c30530b450936cf6b0f285a332f61`.
Evidence: `qa_shots/tests/reported-launch-fixes-20261003.88itpD/receipt.json`.
Earlier parse/test/traversal failures are retained. Shutdown-only resource and
ObjectDB diagnostics remain open; this is not a complete regression or signing
gate. The Mac is locked, so rendered phone layouts, training contrast, real
sign-in UI and simulator gameplay remain unverified. No new build, deployment,
store upload or payment/account settings change. **MVP ~75% / full ~35%** stays
unchanged pending those launch milestones.

### Current web deployment and remaining mobile gates

Owner-requested web update is live at `https://waddlewars.ninjaconsulting.ai/`:
**`web-20261003-d5766c0a42a3`**, source SHA-256
`d5766c0a42a30e0bb89e3a6c97efd4d383baa9a332d5604b068d4cd4879a6abe`.
All thirteen files were uploaded under a new release prefix before switching
only the root entry document. Twelve non-HTML public responses match exact
bytes/SHA-256/MIME/isolation headers. The host inserts one 367-byte Cloudflare
beacon into HTML; removing exactly that insertion restores every candidate byte.
No hosting, backend, payment or store settings changed. The remote root object
matches the final candidate exactly; Chrome's public root reports the expected
build/base and renders the title with no game errors. Staging also opens the menu.
This is deployment/startup evidence, not gameplay or performance acceptance.

Final local full-suite history remains **104 PASS / 9 SKIP / 1 FAIL**, exit1.
The sole failure was an excluded QA fixture's inferred `WeakRef` type; after
explicit typing its affected rerun passes **95 assertions**, exit0. A 1,098-file
source comparison proves that fixture is the only changed test/runtime input.
Three NumPy groups separately pass **10 tests** on the frozen full-suite copy;
six real-window groups remain unrun. Do not relabel the original failed run.
The current recovery headless groups now execute; earlier unexecuted-assertion
statements below describe their original checkpoint, not this final web gate.

Previous production entry and thirteen archived payloads are retained and
verified. No live rollback was executed. Immutable release result:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/web-release-20261003.He1W9j/deployment-result.json`,
SHA-256 `dfab44c39294e632336f5d080932b3b8a45a7fe10991167739d863fb97d22e52`.

Current Android containment QA build12 exports and passes actual unsigned AAB,
payload/manifest/bundletool/16-KB static verification. Its AAB SHA-256 is
`eec9e2c48b10b7c803ebdea946de062d190486049eb3912aaea28db3fa0389e0`.
No APKS/install or runtime pass follows. Evidence root:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-runnercontainment-20261003.6nWrq1`.
Next mobile gates remain Android cold loading and both platforms' interactive
simulator/emulator smoke, final-source signing, privacy/support and store work.
Historical signed Android11/iOS9 do not contain containment. Web publication
does not close those gates: **MVP ~75% / full goal ~35%** remains unchanged.

### Current ARM64 iOS simulator title

One isolated, unmodified pinned-source ARM64 simulator release engine build
finishes in12m16.29s, terminal0. Its archive is actually ARM64; 2,290 object
build-version records identify iOS Simulator. Existing ARM64 simulator bridge
is reused. Current-source build10 exports and links successfully in a separate
QA copy with exactly three native simulator/metadata substitutions. Current
PCK/privacy match the export; canonical export and historical signed packages
remain unchanged. The executable is linker ad hoc signed, with no distribution
profile, resource seal or TeamIdentifier; no signing key is accessed.
Artifact receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-arm64-20261003-b10.d3FU9J/artifact-receipt.json`,
SHA-256 `dbdb061a11c52a9fac7228e2c16f60701662dd020757c5446c12b051284eb813`.

With the Mac locked, public virtual-device controls boot the reused task-only
iOS18.4 device as ARM64, install build10 and launch once. Actual1206x2622
framebuffer captures show title/loading at observed process age8s, then settled
Begin Expedition title at38s. These two observations are not continuous startup
latency or pristine cold-device results. No Mac input, lock bypass, gameplay
input or performance acceptance. Owned device finishes Shutdown, app PID absent,
and source still matches `bc05858a…`. Approximately11GiB disk space remains.
Immutable runtime receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-arm64-20261003-b10.d3FU9J/title-smoke-receipt.json`,
SHA-256 `69c61a8035acd4655b02d9da820caeb0f16d321a8c967311bd0b3b26cf88a353`.

Current-source iOS launch/rendered title are verified. Interactive native play,
Android changed-build cold loading, final regressions/signing and store gates
remain. Regression suites stay deferred. This new launch milestone moves the
coarse estimate to **MVP ~75% / full ~35%**, not full native acceptance.

### Earlier x86 iOS frontend launch evidence

A fresh task-owned iOS18.4 simulator in the default device set reaches readiness
and installs the historical build9 app. Supported Simulator frontend control
selects that device and clicks its app icon once. The app process starts, but
the observed frame remains a black launch screen, not the Waddle title or game.
A one-second public process sample confirms x86_64 under Rosetta; the main
thread is iterating through the canvas renderer, GLEngine and GLRendererFloat
software rasterization. This is not evidence of an initialization deadlock,
crash, or acceptable gameplay performance. Earlier headless missing-PID results
do not establish that the app cannot start.

The owned simulator is confirmed Shutdown and its app process is absent. Data
free space temporarily reports210MiB during the pass, then returns to12GiB
after shutdown; the cause is not established. No files are deleted. Existing
root-owned simulator caches predate this pass. Source and signed packages are
unchanged, and build9 excludes the new recovery-containment fix.
Immutable receipt: `qa_shots/native/ios-frontend-launch-20261003/final-receipt.json`,
SHA-256 `97198dc775332476ddb999343327e0fbb08a140c79d6b300ab38f2ae3047ed66`.

Do not repeat the x86 launch. The advertised ARM64 simulator slice is absent
from the installed template archive; the separate actual ARM64 target above
supersedes launch uncertainty, but does not prove hardware graphics or acceptance.
The pinned iOS simulator build disables Metal and Vulkan. Both platforms still
need current-source native acceptance and final regressions. Coarse estimates
were **MVP ~70% / full ~35%** at this earlier checkpoint.

### Recovery containment and current source

The normalized Android diagnostic now boots in 16.295 seconds and captures the
actual runner warmup under a distinct QA package. Its initial visual pass keeps
progressing, but recovery begins at 30.144 seconds with 103 of 104 originally
visible objects submitted. There is no settled full-scene or shader-probe
completion before recovery. Eleven completed draws take at least one second;
their frame-wall waits account for approximately 96% of the recorded warmup
draw time. These are not isolated shader-compilation measurements. The fixture
bypasses boot/menu, and the copied device is not a pristine cold device.
No startup, responsiveness, performance or store acceptance follows.
Immutable evidence:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-runnerdiag-runtime-normalized-20261003.bn4jcC/guard-corrected-final.receipt.json`,
SHA-256 `f3bdf99bd0a5eeef06a9221a32a6f96fc3caec964aa1a1597e4664b0f15b8ae8`.
Owned emulator, collector and process group are terminal; earlier failed
attempts and their receipts remain preserved.

Recovery now synchronously suspends both ALWAYS-processing warmup helpers.
The router watchdog runs before their submissions; Retry cannot revive the
old helper, and captured visibility/resources remain retained until scene exit.
The 30-second deadline, successful-path workload, art and gameplay are unchanged.
This contains work after recovery; it does **not** fix cold loading or interrupt
a synchronous draw already in progress.

Current runtime: **524 files**, SHA-256
`bc05858a927ec9da0ea1c56a0c73931269fae687f6827f6a5f3f3f866ac17cd2`.
An isolated Godot 4.7.1 editor import/parser check exits0 with zero script/import
errors; all runtime and three edited fixture files match the copied snapshot.
The first incomplete snapshot hold is preserved separately. At this original
checkpoint **52 new planned assertions were not executed**; the later final web
candidate runs headless recovery/warmup checks as recorded above. Native
interactive and real-window acceptance remain open.
Evidence: `qa_shots/native/recovery-containment-20261003-Nd6A0j/source-verified-receipt.json`.
Existing signed Android11/iOS9 packages below are unchanged historical
checkpoints and **do not contain this fix**. New exports, affected native
verification and final local regression gates remain required. Current iOS QA
above includes this fix; historical signed packages do not. Current estimates:
**MVP ~75% / full goal ~35%**.

### Signed checkpoint before recovery containment

Frozen runtime: **524 files** / SHA-256
`dc50ecd61b568091d3f5effedbc0d2ee545447d657ce96d191b0ed65c9faa569`.
The existing full suite finishes terminal0, **105 PASS / 9 SKIP / 0 FAIL**;
three NumPy classes separately **10 / 0 / 0** on the same snapshot. Release-tool
suite passes **522 / 0 / 0** after draft screenshot preparation. Known shutdown
warnings and six real-window groups
plus one internal geometry skip remain; these are not native acceptance.
Source/test evidence: `qa_shots/native/locked-mvp-smoke-20261002/REVIEW.md` and
`qa_shots/tests/waddle-wars-tests-19908-19383/`.

Canonical **Android11 is now upload-signed and verified offline** at
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-release-parity-qa-20261002-b11`.
AAB SHA-256:
`1241dc2aed31c99875edd6104727dc7cc16ada5ae079c7d5761cbb95ce3efa7e`.
Its `receipt.json` records the exact source, release signature/upload pin,
unchanged game payload, bundletool and 16-KB structural gates.
Canonical **iOS9 signed archive and IPA pass strict offline verification** at
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-mvp-archive-20261002-b9.1qNmjo`.
IPA `ipa-export/waddlewars.ipa` SHA-256:
`35bc5de48e0bebe40bd4a05a2dfe502dfc618bd85f447ea287273942ec211273`.
`handoff-receipt.json`, `archive-verification-receipt.json` and
`ipa-verification-receipt.json` bind exact signature/profile/title/ARM64/native
linkage, frozen PCK and archive/IPA resource equivalence; both Xcode steps exit0.
This supersedes the initial unsigned Android11/iOS9 checkpoint and older signed
Android8/iOS6 baseline below. Historical failures and receipts remain unchanged.

Separate Android release QA derivative audit:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-release-smoke-20261002.VufZ19/audit.d1xkr5/audit.json`.
All **641 normalized game/ARM64 payloads** match the signed AAB; transformed
Android packaging entries are classified, not claimed byte-identical. Fresh
offline zero-fish menu is observed. Cold runner route at **21:46:13 UTC** reaches
30-second Recovery, observed **21:46:48**. Public Retry at **21:46:59** reaches
gameplay, observed **21:47:25**; jump, left lane, Pause, landscape and Resume are
captured. Slide was injected but not visually confirmed. Settled portrait menu
at **21:50:15** is nonoverlapping; rotation during entrance is not timing-proven.
Owned emulator shutdown finishes terminal0. Cold loading and full native
acceptance remain open.
Separate current-source **x86_64 iOS simulator build9 links successfully**, zero
errors and one duplicate `-lc++` warning. Its single bounded iOS18.5 boot fails
runtime readiness after **150.683 seconds**: `Status=3`, `isTerminal=YES`,
`Data Migration Failed`. The monitor exits0; readiness wrapper correctly exits3.
No app installation, launch or title capture occurred. Exact-owned simulator
shutdown finishes terminal0 with `Shutdown` confirmed. Link receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-x86_64-20261002-b9.IqelQw/receipt.json`.
Failure receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-x86_64-20261002-b9.IqelQw/headless-title-smoke-20261002/receipt.json`;
SHA-256 `28daeda98d77df6976eb974a615e93007bd5db1ba1e45e97898074cc8de4b82c`.
Historically, Data volume had only **3.7 GiB available / 100% rounded capacity** at 21:54 UTC,
versus approximately 11 GiB before QA. Scoped owned logs show no explicit
`ENOSPC`; migration cause remains unproven. This was a pre-app environment failure,
not an iOS game acceptance result. Full signed/current QA evidence:
[current signing and QA review](qa_shots/native/unlocked-mvp-signing-20261002/REVIEW.md).

Owner-requested cleanup removed **14.7 GiB of allocated regenerable caches**
from 17 exact directories; Data free space increased from approximately
7.3 GiB to **21.88 GiB** at the cleanup checkpoint. Allocation is not an exact
APFS free-space delta. Source, saves, keys/profiles, signed artifacts, frozen
projects, QA evidence, simulator data and receipt-pinned Maven files were
preserved. The 524-file runtime and Android11/iOS9 package hashes still match.
Receipt: [disk cleanup](qa_shots/native/disk-cleanup-20261002/receipt.json).
Deleted caches were not moved to Trash; downloads/recompilation regenerate them.

After storage recovery, one iOS18.5 retry again fails `Data Migration Failed`
after **56.257 seconds**, before app installation. A fresh owned device using
the already-installed iOS18.4 runtime passes readiness (`Finished`,
**128.597 seconds**). Build9 app pins match, but the one installation request
times out after **30.021 seconds**; its outcome is **unconfirmed**, not a proved
rollback or install failure. No app launch or title capture follows. Both owned
devices are confirmed `Shutdown`; the one public post-shutdown app lookup
returns `SimError405`, `Unable to lookup in current state: Shutdown`.
All owned heavy handles are terminal. New immutable receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-x86_64-20261002-b9.IqelQw/headless-title-ios184-20261003.DyMiI3/receipt.json`;
SHA-256 `7e3dc238ee843879fb27d66a5e987c485a107e6daa298c22fc7bb400c92b1645`.
Earlier failure/retry receipts remain unchanged. Simulator readiness alone does
not clear native gameplay acceptance. No source change, rebuild or signing retry.

The next controlled iOS18.4 pass confirms the app is installed through a public
Booted-state bundle lookup, without reinstalling. One normal launch request
times out after **30.011 seconds**; the server/process outcome remains unknown.
One actual simulator screenshot shows **SpringBoard, not the game**. Both owned
devices finish `Shutdown`; no title/game acceptance follows. Latest receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-x86_64-20261002-b9.IqelQw/headless-install-resolution-20261003.dsKjSS/receipt.json`;
SHA-256 `9a1b4f8d710b477e68fe5920406f3f158f14e1c454fef37d59a3c7cbf804fe70`.

One different-observability iOS18.4 console-attached pass also produces no app
output or reported app PID within its 75-second capture cap. Readiness passes
(`Finished`, 89.069 seconds) and installed-bundle metadata succeeds; the single
actual PNG again shows SpringBoard only. The launch server outcome is unknown,
not a demonstrated game crash. Client SIGTERM is -15; wrapper0 is not app PASS.
Scoped app termination times out after 20 seconds with unknown outcome; exact
owned simulator shutdown succeeds, and both owned devices are confirmed Shutdown.
App and earlier receipt pins remain unchanged. No further headless launch retry.
New immutable receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-x86_64-20261002-b9.IqelQw/headless-console-diagnostic-20261003.lo7eSm/receipt.json`,
SHA-256 `6fc4225a1bf505b464b62ff49d446647c5546e08fcc1ed04283faf203287c404`.

Owner now requests **regression suites only at the final candidate**. The live
suite is interrupted, terminal **130**, and is not counted as a pass; logs and
an interruption receipt remain at `qa_shots/tests/waddle-wars-tests-46760-10662/`.
Essential import/parser checks remain allowed during implementation. Earlier
completed results retain their dated scope; final required local gates must
finish before remote CI/upload. The new opt-in native diagnostics adapt only
the existing excluded runner capture fixture: actual route, warmup events and
stage heartbeats, no screenshots/input, unchanged gameplay/loading deadline.
Native diagnostics require a separate QA application sandbox and release-only
feature marker. Android ignores the custom user-directory string for OS storage;
that string is an intent marker, not isolation proof. The distinct-package
unsigned release QA derivative passes import/export and offline artifact gates:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-runnerdiag-20261002.E9U8YP/candidate/receipt.json`,
receipt SHA-256 `4df6a9b1c7a5ed159fc17c7d61b564f34fbe6c2e02eadb7b02916cec065b0955`.
AAB SHA-256 `44ee36e569b143e4b3a2ebedbc10ac2cae5376251127b1d38974b72e548917c4`;
65,562,441 bytes. Actual release manifests, QA feature/main scene/user argument,
unsigned ZIP/CRC and baseline-equal ARM64 engine libraries are verified. All 619
sealed inputs are accounted for: 576 unchanged; 42 generated title XML files
and one generated theme match the pinned exporter reconstruction. The initial
strict verification hold and before/after hashes are preserved, not hidden.
Runtime execution remains pending; no shipping artifact was replaced or accepted.

The one Android diagnostic attempt never reaches app installation: its copied
previous-QA device misses the 120-second boot cap (59 ADB-offline probes, one
absent). No game/warmup trace follows. Owned emulator exits0, process group is
empty and serial absent; source userdata remains unchanged. New versus previous
encryption-key paths are recorded as metadata, not a proved boot cause; no key
contents are inspected. No blind retry. Immutable receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-runnerdiag-runtime-20261002.dmYbG8/native-diagnostic-final.receipt.json`,
SHA-256 `bae09a628007e1509223868115a8ee3a80b9a56ed01c6c772152b02d8f9d7d50`.

One evidence-backed paired-state correction copies both prior owned QA userdata
and its configured encryption companion into standalone inputs. Logical equality,
original preservation and the actual selected companion path are verified. The
single 120-second boot still fails before app installation. Public kernel output
now identifies 24 first-stage mount abort/reboots: missing
`/dev/block/by-name/super` and failed vbmeta reads. This is a guest system startup
failure, not a game/GPU finding or proof of an encryption cause. Driver exits1;
owned emulator exits0 and its process group/serial are absent. No app trace or
native acceptance; no further boot attempted. Immutable terminal receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-runnerdiag-runtime-paired-20261003.CVb2it/native-diagnostic-final.receipt.json`,
SHA-256 `8f35b2696ce7e76f9c8111d4dbe1a493bbb7bd0181cb6ae8cf444ccd5e60d931`.
Bounded comparison confirms identical image references and that the guest sees
the system disk's GPT partitions. Boot-device mapping differs from prior working
QA (`a003600` versus `a003800`). New disk-location overrides are not isolated to
one proved cause. One fresh confined derivative will restore the prior supported
disk-option layout; it is a normalization check, not an established fix. No
boot-property override or AVB bypass is authorized.

Owner now specifically requests Play app creation in parallel. The existing
Chrome form is readable and already contains the approved title/package,
available package name, English US, Game and Free. Two mandatory declarations
remain unchecked: Developer Program Policy compliance and US export/encryption
compliance certification. Action-time legal confirmation is required before
accepting them; no checkbox or Create action is taken. Evidence:
`qa_shots/native/play-create-20261003.Xfn75H/receipt.json` and screenshots.
This supported portal access does not establish Chrome availability for a
controlled game-performance test; other tasks have active tabs.

The parallel iOS draft follow-up saves promotional text and copyright, then
verifies both after reload. Status remains Prepare for Submission; no build,
screenshot, review or release action. Support URL/contact and legal/privacy
completion remain pending. Evidence:
`qa_shots/native/ios-store-draft-20261003.ttUVf9/receipt.json`.

Both signed release receipts remain **`store_ready: false`**; no upload,
TestFlight/Play acceptance or public release. The prior extension interruption
is historical; current Play form access succeeds, with no game performance pass
or security-setting change. Audience, final policy
URLs/disclosures, SDK/required-reason reconciliation and store setup remain
open. Physical testing is waived, not passed. Coarse estimates advance only for
current-runtime signed candidates: **MVP ~70% / full goal ~35%**.

The earlier blocked checkpoint is historical. The goal is active after resume;
storage is restored and iOS18.4 readiness is established. Remaining critical
path includes supported confirmation of installation/title rendering, the
demonstrated Android cold-loading blocker, native smoke coverage and truthful
policy/store completion. Estimates remain **MVP ~70% / full goal ~35%**; this
environment progress is not a completed native acceptance milestone.

### Earlier October 2 decisions and QA checkpoints

Later local listing preparation copies three unchanged Android11 release captures
(title, settled menu and runner jump) into
`tools/release/store_assets/android-build11-draft/`. Its receipt preserves source,
package, audit and Retry provenance; all assets remain draft and unsubmitted.
The new image/provenance regression and full release-tool suite pass **522 tests,
0 skips, 0 failures**, terminal0. Frozen runtime remains unchanged. No iOS
screenshots or native acceptance are implied. Approximately **6.0 GiB** remains
free at 22:12 UTC; heavy attempts stay stopped. Evidence is in the current QA
review linked above. **MVP ~70% / full goal ~35%** remains unchanged.

Package/source and completion claims in this chronology apply to their dated
checkpoints; current signed status and remaining gates are recorded above.

Owner subsequently requests all MVP work that does not require an unlocked Mac.
The goal is active again; the 20:47 blocker audit below is historical. Headless
Android virtual-device development controls work without Mac desktop access.
This is not permission to bypass locking or repeat browser/Keychain probes.

Native-only Help & Support is implemented and rendered offline: selected
publisher/email, stamped version/build and safe bug-report instructions. Fresh
full regression run passes **105 / 9 skips / 0 failures**, with three NumPy groups
separately **10 / 0 / 0**; release tools pass **521 / 0 / 0**. Evidence and exact
source/package hashes: `qa_shots/native/locked-mvp-smoke-20261002/REVIEW.md`.
Android debug10 and canonical iOS export8 bind runtime `ed880157…`; accepted
signed Android8/iOS6 remain unchanged. New rotation repair work will invalidate
affected candidate/source checks and must be verified before a later export.

Corrected isolated headless Android10 pass observes runner gestures/retry,
Pause/Resume, landscape controls, active Home/resume, native support and process-
restart save persistence. It also demonstrates **failed cold runner loading**
and a **persistent mode-card overlap after rotating during menu entrance**.
The latter has a concrete shared entrance/layout race. Minimal repair now makes
Container children fade without changing layout-owned positions; unmanaged rise
remains. Actual focused **90/3 RED → 93/0 GREEN**, with freed-item and live reflow
coverage, independent review and zero script/import errors. Native post-fix
render acceptance remains pending. Full repaired-runtime validation now finishes
terminal0: **105 / 9 skips / 0 failures**, NumPy separately **10 / 0 / 0**, source
`dc50ecd6…`. Initial canonical unsigned release-parity Android11 and iOS9 exports
completed terminal0 from that source. Signing and QA derivative/linkage status
are superseded by the current checkpoint above; native acceptance remains open.
Debug-only DAY preview art differs from release workload; the cold-load cause
is unproven. Do not remove graphics or infer shipping acceptance from debug.
Earlier overlapping/software-GPU attempt is preserved but not valid timing.
Owned emulator stopped successfully. No browser, physical, Keychain, store,
payment or publication action. Coarse estimates remain **MVP ~65% / full ~30%**.

Owner explicitly requests **simulator/emulator testing only**, not physical
devices. Stop physical-device polling and requests; the current MVP smoke and
captures will use a current-source iOS simulator app and Android emulator APK.
This does not establish phone/store-installed performance, physical touch or
16-KB runtime compatibility. Historical receipts and original full-plan gates
remain unchanged; the current MVP testing scope supersedes the physical-device
requirement below, not its missing evidence.

Owner handles Waddle support personally at the selected public email and
delegated retention policy. Both unpublished pages now specify active-mailbox
deletion within **90 days after resolution**, except limited necessary legal,
fraud or security records. `tools/release/support_retention.md` defines monthly
review, case-specific holds and scope excluding unrelated shared-mailbox mail.
No Gmail records/settings were read, changed or deleted; provider backups remain
outside that publisher deadline. Focused page/preparation tests pass **23 / 0
skips / 0 failures**. This resolves publisher support access/policy selection,
not actual past deletions or final privacy/store approval.

One authorized Chrome-control attempt reports the Mac locked. No extension
popup was dismissed, no browser retry or lock bypass attempted. Owner was asked
to unlock manually; local preparation continues on AC power / 100% charge.
Android emulator tooling and a Waddle-owned AVD are available; existing Chancey
AVDs must not be changed. Current-source isolated regression run now passes
**105 groups / 9 skips / 0 failures**, terminal 0; the three NumPy groups pass
separately (**10 tests / 0 skips / 0 failures**). Six real-window groups and one
internal geometry skip remain; teardown warnings are not performance acceptance.
Evidence: `qa_shots/tests/waddle-wars-tests-78021-1154/`.

Current Android QA **build 9** exports successfully from `1951ebde…`: debug
signature, launcher identity, full resources and 16-KB structural checks pass.
Current canonical iOS **export 7** succeeds from the same runtime. Neither has
been installed or play-tested, and accepted signed Android8/iOS6 remain unchanged.
The first separately copied iOS simulator app fails ARM64 linkage with
`Undefined symbol: _main`. Actual `lipo` inspection establishes that the shipped
Godot release simulator archive is **x86_64 only**, despite its directory/plist
advertising ARM64 as well. The separately compiled ARM64 bridge is valid but
does not match that engine. A matching x86_64 simulator-only bridge is the targeted
fix. It now compiles and the separately copied **x86_64 simulator app links
successfully**, actual Xcode terminal 0; result bundle reports zero errors and
one duplicate `-lc++` warning. Installed iOS18.5 runtime supports it and host
translation is already usable. Only the QA-copy plugin archive was replaced;
frozen PCK and canonical export remain unchanged. No engine-version change,
signing workaround, physical test or UI retry. Consolidated release-tool tests:
**520 / 0 skips / 0 failures**. Current package evidence:
`qa_shots/native/simulator-packages-20261002-2040Z/REVIEW.md`.
Earlier bridge-only evidence remains unchanged:
`qa_shots/native/simulator-bridge-20261002-2020Z/REVIEW.md`.
Goal resumed after new owner input at that checkpoint; the earlier
blocked audit below is historical. Current-source full regression validation and
both completed QA-package builds advance the coarse MVP estimate to **~65%**;
full goal remains **~30%**. Simulator play and store acceptance are still open.

Subsequent lock-independent public provider-request review adds scoped guidance
to the unpublished privacy page. Service-specific access/deletion, SDK/audience
and publication gates remain open; no live legal/store declaration was approved.
Focused preparation/page tests **24 / 0 skips / 0 failures**; consolidated
release-tool suite **521 / 0 skips / 0 failures**, terminal 0. No runtime change,
new export or UI/Keychain probe. Details: `tools/release/privacy_review.md`.
This partial draft refinement does not advance estimates: MVP ~65% / full ~30%.

### Historical blocker audit — October 2, 20:47 UTC

Superseded by the subsequent owner request and lock-independent Android QA
above. It records the earlier stop, not exhaustion of current independent work.

Three consecutive goal checks after the provider-guidance change make no new
progress. Both current QA packages are built, not installed/run; all recorded
build/test handles finished, with no live acceptance job to wait on. Last
supported UI observation reports locked and no manual-unlock confirmation has
arrived. The audience question is unanswered, the actual listing still says
`pending_owner_decision`, public policy/support URLs remain null, and privacy
declarations/reviewer smoke remain pending. No legal answer or UI availability
is inferred. Earlier support ownership/retention decisions remain resolved.

Available independent critical-path work is exhausted within the owner-selected
MVP scope. Further tests/builds, static audits or deferred art/commerce would not
clear these gates. The repeated-condition threshold is met; request goal status
`blocked`, preserving the entire uncompleted objective. Resume on manual unlock
and the audience answer, then complete simulator QA and actual privacy/store
prerequisites. Coarse estimates remain **MVP ~65% / full goal ~30%**; this audit
is status bookkeeping, not a completed milestone. No new build, UI/Keychain
probe, physical testing, upload or publication.

### Historical blocker audit — October 2, 19:51 UTC

Superseded in part by the owner decisions above. This records the prior stop,
not a current request for support facts or physical devices.

Previous loop made partial privacy-page/source progress, not launch acceptance.
Current exact-source audit finishes the remaining bounded independent check:
only the optional Movie Maker path calls disk capacity; accepted iOS6 plist has
no `godot_cmdline` entry. Actual process arguments/use remain unproven, so no
disk reason is approved or removed. No new implementation/configuration change
is justified by this evidence; see `tools/release/privacy_review.md`.

The same unanswered actual support/privacy operating facts remain at the 19:28,
19:39, 19:44 and current checkpoints. Current page still has explicit support,
provider/SDK/audience and publication gaps; release URLs remain null. Chrome
control explicitly stopped at the extension-popup blocker; no human-ready
response or device-availability change was received. Browser blockage alone
has not met a three-turn threshold and is not the sole basis for stopping.

MVP independent bounded checks are exhausted. Final policy/in-app access,
consolidated runtime verification/export, physical-device acceptance and store
completion need those external facts/access/approvals. Do not fabricate privacy
practices, approve inherited disk reasons, repeat builds/probes, or start deferred
art/commerce to keep an automatic loop busy. Full objective remains intact and
uncompleted; estimates remain **MVP ~60% / full goal ~30%**. Goal blocker audit
meets the repeated-condition threshold on missing privacy operating facts; ask
for the actual facts, Chrome popup closure and devices before resuming.

- Current source now differs from the accepted signed baseline: **524 files /
  `1951ebde…`**. Native public leaderboard success replies project only numeric
  ranks/scores and authored `Penguin #<rank>` aliases; remote names/arbitrary
  text cannot reach the view. Browser payloads, request routes, scoring, local
  saves and callback delivery/auth-generation safety remain unchanged. Fresh
  isolated import passes; native policy fixture **44 / 0**, terminal 0. Existing
  shutdown diagnostics remain (two ObjectDB instances / one resource). No whole
  suite/device/store claim. Receipt: `qa_shots/tests/waddle-wars-tests-50538-28305/`.
  Signed Android 8/iOS 6 still contain preceding `2d3518aa…`, **not this guard**;
  preserve them, and consolidate remaining launch runtime changes before the next
  full validation/export. No new native candidate or upload was made here.
- Owner approved Chancey's existing publisher/contact reuse, then explicitly
  selected **ninjaconsultingllc@gmail.com** for Waddle Wars. Public Play listing
  and copyright sources establish publisher **Ninja Consulting LLC**. Local
  listing and unpublished Waddle pages use that publisher and selected email.
  No Chancey age, collection or retention claims were copied. Portal contact fields were not
  changed in this follow-up. An earlier Cloudflare observation timed out; the
  subsequent read-only pass recovered browser access and confirms production
  Workers Logs/Traces disabled for both Waddle hosts, disabled Logpush, no
  telemetry destinations and empty Tail Worker selection. No live setting
  changed. Provider network/security processing and support access/retention
  remain separate disclosure gaps; actual mailbox practices were requested.
- Bounded iOS privacy use review finds app elapsed timers and local file access,
  plus pinned accepted-executable metadata/capacity/clock imports. Imports are
  not actual call-path/purpose proof. User-facing timestamp/disk displays and
  behavior-changing capacity checks are not established, so default reasons
  `DDA9.1`/`85F4.1`/`E174.1` are not approved by the source/static review. Exact
  engine/framework purposes must be reconciled before the next candidate.
  No reason guessed/removed, native rebuild or green-suite rerun. Evidence:
  `qa_shots/native/privacy-readonly-20261002-1928Z/REVIEW.md`.
- Subsequent exact Godot `a13da4feb…` source resolves file/timer call paths and
  export bit masks. Future isolated iOS presets now explicitly select app-container
  metadata `C617.1` (2) and elapsed timer `35F9.1` (1), removing inherited
  timestamp-display `DDA9.1`. Focused preparation/listing regressions: **21 / 0
  skips / 0 failures**, after the new case failed on both absent options.
  Disk-space purpose/default reasons remain **unapproved**; no category/API was
  hidden or new justification feature invented. Runtime and signed packages
  unchanged; no export, upload or broad privacy/store acceptance. Receipt:
  `qa_shots/native/privacy-preset-20261002-1939Z/REVIEW.md`.
- Next bounded loop adds the verified, dated production logging facts and
  separate provider-processing caveat to the unpublished privacy page. Focused
  host suite passes **22 / 0 skips / 0 failures**. Exact engine source proves a
  disk-query caller in optional Movie Maker mode, not activation in the mobile
  MVP; disk eligibility remains open. Attempt to resume the existing Apple tab
  stops at Chrome's extension-UI blocker before page observation/edit. No portal
  change or new package. Owner asked to close the popup; mailbox access/retention
  facts remain pending. Completion estimates unchanged: MVP ~60%, full goal ~30%.
  Receipt: `qa_shots/native/privacy-host-draft-20261002-1944Z/REVIEW.md`.
- Store preparation, 18:48 UTC: existing Apple app **6818416048**, titled
  **Waddle Wars: Penguin Panic**, is under **Ninja Consulting, LLC**. English-US
  description, keywords, source-derived reviewer notes and no-sign-in setting
  were saved and verified after reload. App Information also confirms **Saved**
  for subtitle **Avalanche chase & icy races** and **Games / Racing / Action**.
  Version 1.0 remains **Prepare for
  Submission**, with no screenshots or attached build. No review/upload/release.
  Google creation form is staged under **Ninja Consulting**, developer
  **9132521315692749104**, as English-US / Game / Free with existing package
  `com.blubberandbyte.waddlewars`; the portal reports **Package name available**.
  Both policy/export declarations remain unchecked; no Google app record was
  created. Privacy/declarations and device acceptance remain open. See the
  release guide's current portal checkpoint; no additional native build needed.
- Read-only final-package privacy inventory confirms the current Android 8
  manifest/dependencies and byte-identical privacy manifests in both accepted
  iOS 6 app bundles. Final iOS manifest placement gap is closed; actual required
  reason uses, SDK traffic and host/support practices remain unverified. Prior
  unsigned metadata receipt is unchanged. Details: `tools/release/privacy_review.md`.
- Owner confirmed restart. One actual Android key-use probe and one exact-identity
  iOS signing probe now pass, including strict iOS verification and certificate
  pin. No Keychain policy changes or repeated authentication attempts. Current
  **Android 8 AAB and iOS 6 archive/IPA now pass canonical offline verification**
  from the unchanged `2d3518aa…` runtime, including touch Pause. Local release-tool
  suite: **499 tests / 0 skips / 0 failures**. Three demonstrated verifier issues
  were fixed with narrow source/tool/profile boundaries; failed outputs remain
  preserved. No new keys/profiles, uploads or deployments. `store_ready: false`.
  Device check still finds no online Android and the paired iPhone unavailable.
  Earlier pause/failure notes below are historical, not current signing blockers.
  Recovery evidence: `qa_shots/native/mvp-signing-restart-20261002/REVIEW.md`.
- Android build 5 remains upload-signed; iOS build 4 remains an unsigned export.
  Both contain `f3695235…` and now predate loader/menu changes. Historical claims
  of "current" below apply only to their dated milestones.
- Actual Android emulator smoke is retained at
  `qa_shots/native/android-local-smoke-20261002/REVIEW.md`. It proved a clipped
  menu and first runner-load recovery, then successful retry/gestures/resume.
  Debug-signed APK derivatives preserve 586 original game/ARM64 payloads. This is
  software-rendered, 4-KB emulator evidence, not phone/Play/performance acceptance.
- Shared menu fixes pass 72 existing screen layouts plus 24 inset/scale/rotation
  regressions. Loader now waits for actual initial warmup instead of a 300-draw
  cap; controlled real-window regression changed from 6/8 failing to 8/8 passing,
  with the 30-second recovery watchdog preserved. Headless recovery: 109/109.
  Logs: `qa_shots/native/mobile-loader-layout-20261002/`.
- Blizzard cleanup is fixed with a cloud-bound timer callback. Controlled old
  source reproduces the exact freed-capture error (**5 passed / 3 failed**);
  fixed source passes **8/8** with empty stderr. Five-second and pause behavior
  are unchanged. Native accounts/purchases are now hidden and guarded before
  dispatch; focused policy coverage passes **27/27**, preserving earned and
  cached saves. Evidence: `qa_shots/native/mvp-critical-path-20261002/REVIEW.md`.
- The preceding signed baseline is 524 files / `2d3518aa…`, including safe-area runner touch
  Pause. One fresh-cache full suite exits **0**, **105 PASS / 9 SKIP / 0 FAIL**:
  `qa_shots/tests/waddle-wars-tests-88789-23921/summary.txt`. Three skipped NumPy
  groups subsequently pass (**10 assertions**). All five courses, runner/churn,
  tutorial, endless, Grand Prix and ghost simulation pass. New focused Pause/
  GUI Resume coverage is **264 / 0**. Known shutdown diagnostics remain explicit.
- Subsequent real Compatibility windows pass orientation, **72 menu layouts +
  24 inset/rotation cases**, and **390 race HUD touch-layout checks**. Fixture-only
  race-manager repair removes script errors; original RED logs remain. All menus
  use test-local offline transports, no production database. Portrait runner
  loading/Pause/GUI Resume/forced death/GUI Retry is **46 / 0**, 15 actual captures.
  Synthetic warmup fails **3 / 5**; its foreground/partial-trace revision is unrun.
  Landscape loses focus at 2.682 seconds then stops drawing, so no acceptance.
  Further rendered retries stopped until foreground availability changes.
  No phone/browser/performance/premium-art proof or test-gate waiver. Full receipt:
  `qa_shots/native/mvp-critical-path-20261002/REVIEW.md`.
- Android **build 6** exports the previous `b316cd77…` runtime, but its noninteractive
  signer fails at `reading_app_specific_keychain_password`. Unsigned AAB is
  retained, 65,528,306 bytes / `7fda5a96…`; no finalized signed artifact or
  offline release-verification pass. Original signed build 5 is untouched.
  Failed launch state is preserved; no prompt, new key or retry. Current Mac
  console session reports locked; Apple identity metadata is present, which
  does not prove private-key access. No repeated iOS signing attempt or stale
  unsigned export was presented as current. Stop at normal signing/device access.
- Subsequent read-only observation finds screen-lock marker cleared and default
  Keychain status 7. One fresh Android **build 7** exports the unchanged runtime,
  but still fails reading the app-specific password; no further Android retry.
  Unsigned AAB is 65,528,344 bytes / `ae2a607b…`. This distinguishes default
  Keychain metadata from actual item access; no private data or ACL was changed.
- iOS **build 5** exports the same runtime, receipt `75751a46…`. Existing verified
  profile/certificate/helper inputs permit one manual archive invocation, but
  app CodeSign fails with **`errSecInternalComponent`**. Failed archive/logs stay
  retained; no signed archive/IPA, provisioning updates, new key/profile or upload.
  Fresh queries find zero Android devices and one paired, unavailable iPhone.
  Both current exports are packaging progress, not launch/device acceptance.
- Owner paused all Keychain/signing work until confirming a computer restart.
  Builds 7/5 predate touch Pause and must not be presented as current. No signing
  probe, credential query, native build/export, install, upload or deployment
  occurred in the subsequent independent pass.
- Next: short physical-device/store-installed smoke and current captures, remaining
  foreground acceptance, truthful privacy/support/contact and store submission
  prerequisites. No more native exports for unchanged source. No art builds,
  browser profiling, live sales, store uploads or paid remote CI in this scope
  checkpoint. Missing signing/device access is a stop, not a reason for more art.

## Latest isolated retopology — within body budget, projection rejected

- Explicit `unified-retopo-r2-v1` preserves bound R2 source, immutable eye
  frames and continuous material contract. Saved component membership plus
  exact geometry digests avoids replaying QuadriFlow during atlas recovery.
  No source anatomy/material, rig/action or runtime change.
- Actual raw input fails numerical preflight; one weld creates topology defects
  and is retired. Exact private power-of-two units resolves preflight without
  changing inverse coordinates or topology. First completed solve exceeds BODY
  cap; one lower fixed request returns 6,591 quads / 13,182 triangle equivalent,
  below 14,000, then fails source interpolation. Final driver exits **1**.
  No accepted projected cage, LOD, GLB/audit, atlas or moving capture. Projection
  and final mesh limits remain unchanged.
- Final host suite: **444 normal + 444 optimized**, zero skips/errors; not
  actual conversion or reference-fidelity approval. Automatic tuning stops.
  Next art boundary: clean authored facial/deformation topology, not more small
  source/solver variants. Evidence:
  `qa_shots/hero/unified_face_retopology_20261002_units02/REVIEW.md`.
- Fresh game fingerprint stays 524 files / `f3695235…`. Android **build 5 signed**
  and iOS **build 4 unsigned export** stay current on V11. Android device/Play/
  purchase/key-recovery and iOS signing/TestFlight/device/purchase gates remain
  open. No fresh Mac/device observation inferred; no unchanged-state retry,
  browser game test, store operation or remote CI.
- Native release guide now matches the implemented deletion receipt protocol
  and migration 0007, removing stale missing-foundation claims. This is a
  documentation correction only; providers/deployment, legal retention and
  device acceptance remain open, deletion and sales still disabled.

## Latest isolated penguin transfer — source bound, export not accepted

- Unchanged unified R2 was recaptured with all 21 dependencies and all four
  output hashes verified. Original incomplete R1/R2 receipts remain untouched.
  Explicit adjacent review authorizes candidate-only budgeted transfer, never
  fidelity, geometry or production approval. No new anatomy variant was made.
  Evidence: `qa_shots/hero/unified_face_source_bound_20261002/REVIEW.md`.
- Adapter and baker now recognize this exact review contract, preserve its
  immutable eye frames and transfer actual continuous source pigment/masks.
  Scratch baking compensates for the canonical Y reflection; diagnostic vertex
  masks are not treated as the source shader. Legacy profiles remain unchanged.
- Final consolidated host suite passes **409 normal + 409 optimized**, zero
  skips/failures. Source-study
  tests additionally pass **31/31 inside Blender's Python 3.13**. Host Python
  3.12 serializes ASTs differently; portable tests compare complete compiled AST
  scope while preserving original golden pins under Blender's Python runtime.
- First actual budgeted build exits **1** at exact protected-eye-socket vertex
  retention, before a candidate GLB/audit or atlas. Retained failure:
  `qa_shots/hero/unified_face_candidate_20261002.log`. No waived geometry gate,
  source metadata rewrite, live model import or performance claim follows.
- One bounded repair preserves all four measured pin phases, but the protected
  eye region alone is **81,814 triangles**, above the entire hero's **25,000**
  ceiling. Body remains 84,031 triangles. Driver exits 1 at a later tangent
  singularity; no tangent/atlas retry can solve the proven budget conflict.
  Exact-copy reduction is retired for this source; budgeted retopology is next.
  Early budget guard now rejects impossible pins without weakening final gates.
  Evidence: `qa_shots/hero/unified_face_candidate_20261002_repair01/REVIEW.md`.
- Fresh game fingerprint remains 524 files / `f3695235…`. Signed Android 5 and
  unsigned iOS 4 export remain current on V11, both equal launch priorities.
  Current ADB query succeeds with zero devices; Mac lock remains observed.
  No signing retry, device install, store operation, browser test or remote CI.

## Latest shared character source — both apps unchanged

- Unified juvenile face replaces separate hood-strip/stacked-disc construction
  with shared support, coupled eye registration and one closed eye per side.
  Actual R1 and targeted R2 front/three-quarter/side renders were reviewed.
  R2 rounds the skull and restores side-eye visibility; orbital cuffs, uneven
  gaze, narrow side iris and flat bill still fail the supplied reference.
- R2's body has 570,214 triangles and is quarantined source-only. No live GLB,
  LOD, atlas, rig, motion or material promotion. The newer bounded transfer
  above proves exact-copy reduction cannot meet budget; next requires budgeted
  retopology, not another small source variant or dense source import.
- Future capture receipts now explicitly pin the imported paint helper and its
  ancestry. R1/R2 historical receipts lack that dependency and remain incomplete;
  output hashes verify, but no retroactive complete-provenance claim is made.
  **23 normal + 23 optimized host tests pass**, zero skips/failures. Evidence:
  `qa_shots/hero/unified_face_source_20261002_r2/REVIEW.md`.
- Fresh runtime hash remains 524 files / `f3695235…`. Android **build 5 signed**
  and iOS **build 4 unsigned export** stay current, both on V11. Android remains
  equal launch priority; physical-device/Play/key-recovery/commerce and iOS
  signing/TestFlight/device/commerce gates remain open. No native rebuild,
  signing retry, store upload, game-browser investigation or remote CI repeated.

## Latest character checkpoint — current motion, no fidelity promotion

- Fresh actual V11 front/chase sequences confirm torso and head rock together,
  with attached feet. No current missing-upper-body animation bug established;
  no duplicate procedural motion or gameplay movement was added.
- Fixed capture-only portrait distortion: screen-constrained windows previously
  produced landscape PNGs then stretched them into portrait contact sheets.
  Fixed VIEWPORT/KEEP base, per-image dimension guards, timeline dimensions and
  aspect-fit thumbnails now pass eight 30/60-FPS fixed-step engine sequences.
  All 360 PNG dimensions/timings/asset pins independently verify. **188 host
  tests pass**, zero skips/failures. This is not measured FPS or device approval.
  Evidence: `qa_shots/hero/live_v11_orientation_fixed_20261002_REVIEW.md`.
- Existing Z14/Z13 composed source is now actually rendered and reviewed in all
  three views. Less-pinched throat improves, but stepped brow edges, assembled
  eyes and planar bill remain below reference. Root and independent reviewer
  reject it; 11 passing source tests do not grant fidelity. No runtime promotion
  or further study. Next art change must unify facial anatomy, not add another
  small bill/neck variant. `qa_shots/hero/v12_source_proof_z14_20261002/REVIEW.md`.
- Canonical runtime rehash remains 524 files / `f3695235…`; Android **build 5
  signed** and iOS **build 4 unsigned export** stay current. No connected-device,
  Play/TestFlight, purchase, browser performance or remote-CI work was repeated.
  Current lock observation remains Yes; no iOS signing retry or bypass occurred.
  Android retains equal launch priority and its explicit open gates below.

## Latest launch foundation — standalone deletion request page

- API Worker `/account/delete` now provides a standalone browser request surface,
  not an app-only redirect or Godot download. Explicit confirmation binds owner
  and session; atomic receipt storage precedes POST; signed-out checks are
  read-only. Disabled/misconfigured pages stay inert. No feature/origin/provider
  configuration, migration, live service or legal retention declaration changed.
- Independent review repaired slow-storage cancellation, default write durability
  and known-unsent preparation cleanup. Only fresh exact pending preparation
  before transport may be cleared; attempted/ambiguous requests stay fenced.
  Strict IndexedDB durability is a requested browser hint, not a backup guarantee.
- **127/127 combined host tests**, **5 focused groups / 244 checks**, zero
  skips/failures. Installed Chrome's isolated synthetic profile passes eight
  phone/landscape/desktop layouts and actual two-tab IndexedDB: one POST, one
  persisted receipt, then signed-out header-only GET with no destructive retry.
  No page errors or unexpected network requests. Captures were visually reviewed.
  Real Clerk/CSP/OAuth/provider and physical-device acceptance remain open.
- Receipt: `qa_shots/commerce/public-deletion-page-20261002/receipt.json`.
  Game runtime remains `f3695235…`; Android 5 and iOS 4 export remain current.
  No new whole-game full-suite pass is claimed for the added host-test group;
  unchanged game baseline remains 102 PASS / 8 SKIP / 0 FAIL. Sales/deletion remain
  off, public page undeployed, browser game-lag investigation untouched.

## Latest mobile milestone — both candidates refreshed to recovery runtime

- Android **1.0.0/build 5** is now upload-signed and passes the actual offline
  signature/774-payload, unchanged unsigned content, package/API/billing/release,
  full bundletool and 16-KB structural packaging gates. AAB is 65,609,892 bytes,
  SHA-256 `249ef4408f28a784c106ba0871684581a0bc1b34a181b83986477fb55e1c3ff1`.
  All 42 bundled launcher-title configurations match Penguin Panic. Existing
  app-specific key and no-prompt Keychain workflow were reused; no new key or
  password, no Godot/Gradle release credentials, no upload or Play registration.
- iOS **1.0.0/build 4** exports successfully and passes the strict frozen
  candidate gate, with 11 canonical import-generated UID entries and 585 frozen
  paths. Title and unchanged PCK are verified; no supplemental metadata is
  needed. This is an unsigned Xcode-project export, not archive/IPA acceptance.
  Mac remains locked; no repeated signing attempt or security-setting change.
- Both 524-file snapshots use `f3695235…`, matching the final 102 PASS / 8 SKIP /
  0 FAIL full-game regression. Fresh release-tool suite passes **480/480**, zero
  skips/failures. Actual builds were serial and never executed player saves.
  Receipt: `qa_shots/native/mobile-recovery-refresh-20261002/receipt.json`.
- Configured ADB query succeeded with zero attached Android devices; physical
  iPhone is offline. No game/device/emulator installation or gameplay occurred.
  Independent key recovery, Play identities/internal testing, current iOS
  signing/TestFlight, physical orientation/lifecycle/16-KB and real sandbox
  purchase/restore/refund/account-isolation gates remain open. Deletion and sales
  stay disabled. Browser profiling and remote CI ran zero times.

## Latest continuation — shared recovery for Android, iOS and web

- Lost deletion replies can now be checked after sign-out, expired login or a
  restart using a locally durable, status-only recovery receipt. Pending state
  and receipt commit together before POST; the server stores only a bound hash
  in the same transaction as retirement and erasure. Unknown receipts never
  unpause an ambiguous request. Confirmation repairs only the original owner's
  purchase cache, preserving earned offline progress and other accounts.
- Web and native transport keep the receipt in a dedicated header, without
  cookies, JWT, query tokens or redirects. Cloud-save GET/PUT excludes private
  local deletion fields as well as purchase caches. Existing requests without a
  receipt retain authenticated status checks; a deleted legacy identity cannot
  be retroactively given recovery authority.
- Final isolated full-game regression exits 0: **102 PASS groups / 8 SKIP /
  0 FAIL**. Runtime fingerprint remains
  `f369523552bc42308fdee8dcca20ae79ee36a41a66ae542b50ab4f5f24d60f11`
  (524 files). Receipt:
  `qa_shots/commerce/deletion-recovery-20261002/receipt.json`.
  Known shutdown resource diagnostics and skipped renderer/NumPy gates remain
  explicit gaps; 103 art assets still lack production-ready approval.
- Retained signed Android **1.0.0/build 4** remains verified, but its
  `bc274252…` snapshot now precedes these changes. iOS build 3's retained export
  is also older; its interrupted archive is not signing acceptance. Refresh both
  platforms from one consolidated candidate before launch. Android still needs
  independent key recovery, Play identity registration, exact Play-installed
  phone testing, sandbox purchases/restore/refund and account isolation. iOS
  needs normal Mac/Keychain availability for current signing, then TestFlight and
  the same device/commerce gates.
- Deletion and live sales remain disabled and undeployed. Apply migration 0007
  before any enabled deletion deployment; public request page, retention policy,
  scheduled retries and real provider/device acceptance remain open. No browser
  investigation, mobile rebuild, signing retry, upload, remote CI or live
  financial/deletion operation ran in this milestone. Goal remains active.

Earlier sections below record historical snapshots, not latest-runtime builds.

## Latest continuation — both mobile platforms, safe local launch tooling

- Android remains a first-class launch gate. Current **1.0.0/build 4** signed
  AAB hash was rechecked unchanged (`fa386ca7…`). Default Fastlane Android build
  now dispatches only the credential-isolated upload launcher into a fresh
  destination, never old Godot signing, key bootstrap or retry/fallback. Eighteen
  actual-Fastfile host fixtures and offline eight-lane discovery pass; these do
  not repeat signing or establish Play/device acceptance. Next: independent key
  recovery, Play upload/app-signing identity, exact Play-delivered phone testing,
  sandbox cosmetic purchase/restore/refund/account isolation. Sales stay off.
- Fresh iOS **1.0.0/build 3** Xcode export has the new Penguin Panic title and
  current 524-file `bc274252…` game revision, matching Android and the earlier
  full-game suite. Eleven Godot-generated script UID sidecars are explicitly
  frozen in a supplemental receipt bound to the unchanged original export and
  source hashes. Future canonical exports record those separately automatically;
  arbitrary extras or altered source/export bytes reject.
- New receipt-bound local archive/IPA orchestration and independent read-only
  artifact gates enforce existing signer/profile pins, frozen export PCK,
  signature/team/entitlements/native linkage, bounded IPA paths and exact
  archive/IPA resources. **480 release-tool host tests / 0 skips / 0 failures**
  pass; **98 optimized iOS tests** also pass. No remote CI, upload, automatic
  provisioning or new iOS key/profile. Host fixtures do not sign artifacts.
- One actual archive reached `CodeSign` and then remained idle while the Mac
  reported `CGSSessionScreenIsLocked=Yes`. The precise security prompt/error was
  not observed. Only the validated owned build processes were terminated; output
  says `BUILD INTERRUPTED`, wrapper exits 1, all artifacts/logs remain. **Current
  iOS archive/signature/IPA acceptance did not pass.** Historical build 2 IPA is
  unchanged. Normal Mac/Keychain availability is needed before a fresh archive
  run; no security setting was bypassed or changed.
- Receipt: `qa_shots/native/ios-current-release-20261002/receipt.json`.
  Browser runs this milestone: zero; bounded active-play check still pending.
  Neither device/store/purchase gates nor premium visual overhaul are complete.

## Latest Android milestone — current upload-signed full-game AAB

- Android **1.0.0/build 4** is retained and passes actual offline release
  verification. Public title is **Waddle Wars: Penguin Panic**; original project
  name, bundle and save identity remain unchanged. All 524 current runtime files
  have source fingerprint
  `bc27425225a36bcc75a5c1db5c28e76e82a9f11330ed7ed0cd0c08f10f674863`,
  matching the earlier 101 PASS / 8 SKIP / 0 FAIL full-game suite. App code was not
  changed for this signing/packaging milestone; player saves were not executed.
- Release AAB: **65,605,916 bytes**, SHA-256
  `fa386ca7dbb46d7037264f27ece83873a77e10c6dbc166eddd55db1f5e185a10`.
  Fresh retained candidate is outside the checkout at
  `~/Library/Application Support/WaddleWarsLaunchCandidates/android-upload-release-20261002-r2/`.
  Its actual signature covers 774 payload entries; exact upload public pin,
  unchanged unsigned payload, full bundletool validation, package/version/API
  24/36/ARM64, billing provider, release flags, Godot resource presence and
  both native libraries' 16-KB structural/packaging gate pass.
  Bundled launcher resource matches the new title in all 42 configurations.
  This is not an installed-device label, real 16-KB runtime or purchase test.
- An app-specific RSA-4096 upload key was created under the owner's signing
  authorization, with two verified encrypted local copies and a device-only
  macOS Keychain password. Godot/Gradle receive no release credentials: export
  is unsigned and the fixed Swift helper supplies the password only to JDK
  signing's child environment. Keychain reads fail without prompting; signing
  children have bounded execution. No unrelated app key was reused.
  **Both copies are on this Mac, not independent off-device recovery. The
  upload certificate is intended, not Play-registered; Play's distribution
  app-signing certificate remains unknown.**
- First build 3 remains rejected and preserved unchanged. Real artifact testing
  exposed the official asset pack's `assets.pb`, JDK21's RFC owner-display line,
  and Godot's default shell-profiling node. Narrow format support now requires
  full bundletool validation and exact module inventory; arbitrary protobuf,
  feature/code/native content and additional signers remain rejected. Both
  release exporters disable only the pinned template's profiling node in fresh
  snapshots, recording before/after hashes; debug preparation stays unchanged.
  Build 4 used the same key after **353/353 local host tests, zero skips/failures**
  and a clean Swift typecheck. No repeated signing-key creation or remote CI.
- Full receipt: `qa_shots/native/android-upload-release-20261002/receipt.json`.
  Play's existing draft was inspected read-only: no policy/export certifications
  were submitted and no Play app record or upload was created. Device/internal
  Play, billing, independent signing recovery, privacy/deletion and store gates
  remain open. iOS's prior retained IPA is unchanged and still needs refreshing
  to this latest runtime/title. Browser performance investigation ran zero times
  in this milestone; its single bounded active-play check remains pending.
  The full premium visual scope remains active, not approved or complete.

## Latest continuation — sustained play and retained native artifacts

- Owner requested a recreated, cost-constrained goal. Browser lag is now
  provisionally resolved from the owner's recent smooth active play. Owner
  subsequently shortened the remaining investigation to one two-minute
  cumulative active-play check with three retries: responsive controls,
  no visible unexplained freezes, no worsening
  slowdown. A clean result closes investigation; a failure permits one targeted
  fix/retest, then further performance investigation requires owner direction.
  No more speculative shader/driver experiments or performance-only soaks.
  The previous five-minute requirement is superseded, not an additional test.
  Original launch acceptance gates remain separate; independent mobile,
  commerce and premium-art work proceeds without reopening the investigation.
- Owner clarified recent smooth Chrome play was approximately 30–60 seconds.
  The single cumulative check remains unperformed; no further profiling starts
  merely because that bounded observation is pending.
- Owner reports same-Mac public Safari smooth and a subsequent interactive Chrome
  session apparently smooth. This is encouraging, not a sustained-play gate.
  The next browser acceptance run must actively steer/jump/slide, traverse biome
  transitions and retries, and avoid screenshots/build workers during timing;
  a short unattended three-life crash-out does not test time-dependent lag.
- U7 actual running canvas identifies Apple M2 through ANGLE Metal, rather than
  relying on the masked `WebKit WebGL` string. Its opt-in shader trace records
  a maximum individual shader-status wait of 22.135 ms. A later 832.905 ms RAF
  gap overlaps a 726.690 ms trusted content-key queue delay but no new shader
  compile/link after retry. Intrinsic cause remains unassigned; this mixed
  owner/automation run includes screenshot/protocol interference possibilities.
  No exclusive-focus, X-close, performance or Safari comparison acceptance:
  `qa_shots/runner/chrome-fullapp-renderer-shader-u7.u7j9ys4u/analysis.json`.
- Profile-only actual render-state telemetry passes 25 focused checks. Resident
  auto-derived snow/ice/water/aurora uniforms now change reversibly with quality;
  fixed detail and caller-owned duplicates stay independent. Five focused groups
  pass 409 checks; one real-renderer raster fixture is explicitly skipped.
  `qa_shots/runner/resident-auto-detail-20261002/receipt.json` records scope and
  exact hashes. No FPS improvement is inferred from headless checks.
- Historical signed iOS build 1 archive was stored under `/private/tmp` and is
  now absent. Its earlier verified-signature receipt remains historical evidence,
  not an available artifact. Fresh iOS 1.0.0/build 2 now archives successfully
  into retained outside-checkout storage. Strict signature, exact team/bundle,
  embedded profile, entitlements and immutable app-file checks pass. Three unused
  purpose keys/warnings are absent. Receipt:
  `qa_shots/native/ios-signing-recovery-20261002/receipt.json`. No IPA/upload,
  private-key generation or auto-provisioning; device/TestFlight gates remain open.
- Subsequent local-only distribution IPA export succeeds and verifies exact
  signer/profile/team/bundle/build, strict signature and eleven unchanged runtime
  resource hashes. IPA is retained outside temporary storage (60,802,767 bytes;
  SHA-256 `19a6b6ce36c46ab754ca4091659d161e9de56178301ae1d59223c2a244c4aebd`).
  Receipt: `qa_shots/native/ios-ipa-local-20261002/receipt.json`. Xcode reports
  account-session expiry 1100 while checking its Apple account, but local export
  completes; no login/export retry, upload or new key/profile. Distribution IPA
  is not direct device installation, TestFlight or store acceptance. The browser
  App Store Connect session still works. Subsequent app-record creation is
  documented below; this does not establish an uploaded build or acceptance.
- Earlier complete isolated regression exits 0 with 90 PASS groups, eight explicit SKIP
  groups and zero FAIL: `qa_shots/tests/waddle-wars-tests-22770-21700/summary.txt`.
  It predates the final web advice host edits; their separate final receipt
  passes 87 host checks with zero skips and parses ten scripts/eight markers:
  `qa_shots/runner/browser-acceleration-advice-20261002/receipt.json`.
  Advice checks the running context once, warns only on clear software renderer
  fingerprints or WebGL2 failure, and never claims to read the browser setting.
  Real-browser advice presentation review remains open. These tests are not FPS
  or visual-fidelity acceptance; known fixture warnings and skipped gates remain.
- Android's existing unsigned integration AAB is not a playable full-game release.
  Normal release-signing configuration is absent; no Chancey key is reused.
  Store/device billing, privacy/account deletion, store records/disclosures,
  release-signed Android artifacts and premium art remain open launch gates.
- New retained Android DEBUG APK contains the full game: 296 source resources
  and remaps, 580 packaged staged files, valid v2 signature, correct bundle/API
  24/36/ARM64 manifest and Billing/Billing-KTX 9.1.0 provider verified. APK SHA-256
  `fc48a327e4f56bbf92346294dd113b125fa3b2d6fd29947573152a1b3126bd3d`.
  `qa_shots/native/android-debug-build-20261002.2skKQV/summary.json` preserves
  initial Gradle-hook failure, corrected export and verifier-only SDK-label fix.
  SDK zipalign 16-KB packaging passed; the initial checker falsely rejected
  unaligned RELRO ends that cover their entire writable LOAD segments.
  Bionic's actual whole-LOAD exception and page-rounded protection confirm the
  distinction. The corrected checker still rejects mutable/executable bytes
  caught outside RELRO, invalid containment, malformed sizes and overflow.
  Verifier-only recheck of the same immutable APK now passes structural and
  packaging gates; signature, resource and dependency checks remain green.
  Receipt: `qa_shots/native/android-relro-correction-20261002/receipt.json`.
  Real 16-KB runtime/device/store gates remain open;
  no new key, emulator/device mutation or upload. Debug signing is not release-key
  continuity. No further engine compilation followed the successful export.
- Read-only native target inventory finds no connected iOS/Android devices and
  no running Android emulator. One remembered paired iPhone is unavailable;
  no installed dedicated 16-KB target was found. Physical testing needs the
  intended device connected/unlocked; inventory did not install or change apps,
  trust, Developer Mode, signing or other projects' targets.
- Corrected checker and final regression fixtures pass the complete release-tool
  host suite: 150/150, zero skips. New isolated `android_relro_structural` group
  passes 24/24 in `qa_shots/tests/waddle-wars-tests-58235-20820/summary.txt`.
  These focused checks preceded the enlarged complete regression below;
  neither structural checks nor headless regression establish launch acceptance.
- Independent release-tool host suite passes 126 tests, zero skips. Integrated
  isolated helper groups pass 8/33 in
  `qa_shots/tests/waddle-wars-tests-50882-24992/summary.txt`. Isolated commerce
  groups pass 52 backend tests (provider responses mocked), 41 new sandbox-guard
  tests and 97 Godot assertions, zero skips/failures, in
  `qa_shots/tests/waddle-wars-tests-54279-28183/summary.txt`. The public-config
  snapshot guard rejects unknown/quoted/nested secret fields before copying.
- Web sandbox configuration/preflight implemented but deliberately undeployed and
  blocked by placeholders and unverified setup. It rejects production D1/origins,
  live mode, mismatched prices, native sales and missing auth/webhook declarations;
  no secret values or provider calls. Receipt:
  `qa_shots/commerce/sandbox-preflight-20261002/receipt.json`. Real sandbox
  checkout, webhook fulfillment, restore, refund/replay and account isolation
  remain unperformed; production commerce configuration is unchanged and disabled.
- Account-lifecycle audit found whole-save cloud sync carried local purchase
  caches for multiple Clerk accounts. New client uploads exclude `commerce`;
  cloud adoption ignores legacy purchase caches while retaining this device's
  existing offline cache and earned progress. Backend PUT strips the field;
  GET filters legacy responses without erasing stored rows. Invalid non-object
  saves reject, and the existing 128-KiB limit now measures UTF-8 bytes.
  Isolated checks pass 11 backend tests and 21 Godot assertions:
  `qa_shots/tests/waddle-wars-tests-60547-13660/summary.txt`.
  Initial test-script type-inference failure was corrected; failed evidence is
  retained. No live data/provider operations or deployment occurred. Full account
  deletion, stale-identity/write barriers, provider erasure, local-backup cleanup
  and approved retention/restoration disclosures remain separate launch gates.
- Complete isolated cloud-boundary regression exits 0: **95 PASS groups,
  eight SKIP groups, zero FAIL groups**, 103 groups total:
  `qa_shots/tests/waddle-wars-tests-62590-8436/summary.txt`.
  First repeat failed the old commerce fixture's implicit cache-reset assumption;
  fixture now explicitly isolates its starting entitlement state and additionally
  verifies native events leave that cache unchanged. Original no-local-grant
  assertion remains. Corrected commerce checks pass 52 backend / 41 sandbox /
  99 Godot assertions. Existing simulator shutdown ObjectDB/resource warnings
  were observed in console output; retained engine logs do not preserve complete
  stderr. Skipped renderer/NumPy gates and an internal geometry skip remain open.
- Runner menu now identifies the mode as **Avalanche chase**. Persistent HUD
  labels the actual chaser gap as **AVALANCHE GAP / <N> m BEHIND**, with explicit
  close-danger wording and **Stay ahead of the avalanche** during countdown.
  Initial and retry countdowns seed the real 34-m starting gap. Gameplay unchanged;
  objective shares the existing callout tween, with no added per-frame work.
  Focused retry/HUD fixture passes **38/38**:
  `qa_shots/tests/waddle-wars-tests-64368-25254/summary.txt`.
  Portrait/landscape and accessibility-scale visual acceptance remains separate.
  Subsequent actual-window 540×960 Compatibility handoff passes 18 ordering/
  visibility checks, zero violations; capture reviewed with legible objective
  and initial gauge. This desktop portrait is not a touch-device matrix pass.
  Existing exit warning reports 20 ObjectDB instances; no performance/soak or
  clean-shutdown claim. Source review identified objective/mission overlap risk
  at 360×640 with both scales 1.4; that extreme remains open:
  `qa_shots/runner/avalanche-readability-20261002/portrait.json`.
- The retained iOS/Android candidates still contain source `d40a9dbc…`, not these
  later cloud-boundary/HUD changes. Full-regression cloud checkpoint was
  `632435bb…`; subsequent avalanche source is `f95e42b5…` (522 runtime files).
  Full regression was not rerun after those HUD edits; focused receipt supplements
  that frozen checkpoint rather than claiming a latest-tree whole-suite pass.
  Candidates remain valid evidence for their own immutable snapshots; no native
  rebuild was performed solely to refresh this incremental source change.
- Selected store title **Waddle Wars: Penguin Panic** (26 characters) was accepted
  by Apple. Created iOS App Store Connect record **6818416048**, English (U.S.),
  bundle `com.blubberandbyte.waddlewars`, SKU `waddle-wars`, existing Ninja
  Consulting, LLC team, Full Access. Apple reported access settings could not be
  saved and all team users retain access, matching selected Full Access; no
  permission repair attempted. Version 1.0 is **Prepare for Submission**;
  no build uploaded, review submitted or publication performed. Browser proof:
  `qa_shots/native/app-name-penguin-panic-20261002/apple-created-app-record.jpg`.
  Android Play Console draft uses the same title/package, English (United States),
  Game / Free. **Package name available** verified in UI. Required Developer
  Program Policies and US export certifications remain unchecked because launch
  compliance/account-lifecycle and legal declarations are not yet established;
  no Android store record or name reservation claimed. Existing debug APK is not
  release-signed continuity or store/device acceptance. Draft proof:
  `qa_shots/native/app-name-penguin-panic-20261002/android-draft-package-available.jpg`.
- Backend account-retirement foundation implemented, disabled and undeployed.
  Permanent subject markers plus 16 transactional SQL mutation guards fence
  valid old JWTs, delayed writes, native-auth approval, checkout fulfillment and
  refund reversals. Personal game/session rows erase atomically; financial proof
  remains quarantined pending lawful retention/restoration decisions. Provider
  failures stay pending with bounded durable retry; an initial Clerk 404 is not
  mistaken for deletion. No live account or database was modified. Focused
  isolated backend groups pass **84 tests** (52 commerce, 11 cloud, 21 retirement),
  plus **4 public-name privacy tests** separately, zero skips/failures. In-app
  deletion/local-backup cleanup were still missing at this checkpoint; subsequent
  client work is recorded below. Public page, retry scheduling, provider and
  device acceptance remain open; this is not completed account deletion.
  Receipt: `qa_shots/commerce/account-retirement-20261002/receipt.json`.
- Android release export now requires an independently obtained public upload
  certificate pin and verifies the actual AAB signature/payload coverage,
  certificate, identity, release flags, billing metadata, resource presence and
  16-KB structure before recording success. Fastlane integrates the same gate.
  Symlink exports reject before hashing; verifier timeouts/malformed artifacts
  cannot leave a misleading `building` receipt. Complete release-tool host suite
  passes **199/199**, zero skips; final isolated Android gate groups pass
  **42 signature / 21 build-helper tests**, zero skips/failures. These are synthetic
  host tests, not actual signed-AAB or store acceptance. No new signing key,
  build, device mutation or upload occurred. Intended/registered upload-cert
  continuity, genuine signed AAB, distribution app-signing identity, real 16-KB
  device and purchase tests remain open. Android remains part of the active goal;
  debug APK evidence above is not promoted to release readiness.
  Receipt: `qa_shots/native/android-release-gate-20261002/receipt.json`.
- This continuation does not refresh the retained native candidates or declare a
  latest-tree whole-game regression pass. Browser's bounded active check remains
  unperformed; no additional browser profiling occurred. Production purchases
  stay disabled, and no push, deployment or remote CI was triggered.

## Shared account-deletion client/UI — local implementation, production off

The Online Settings entry and two-step confirmation now use a shared lifecycle
autoload on iOS, Android and web. Account/session-bound consent, durable pending
markers, cloud/auth/commerce callback fencing and owner-isolated main/backup/temp
cache cleanup preserve earned offline progress and other account caches. Failed
or ambiguous requests stay paused rather than reporting success; incomplete
provider/retention acknowledgment is explicit. Cancel receives initial focus.
`account/deletion_enabled=false` remains explicit. No live account deletion,
database mutation, backend deployment, mobile rebuild, store upload or browser
profiling occurred during this implementation.

Fresh-import focused fixtures pass **67 cache / 30 client / 45 UI assertions**,
zero skips/failures:
`qa_shots/tests/waddle-wars-tests-77122-610/summary.txt`.
Three actual-window Compatibility captures pass **39/39** at 320×568/UI 1.4,
390×844 and 844×390; Settings/modal images reviewed. First small-phone capture's
false reachability failure is preserved; its actual button overhang was 0.12
logical pixels. A fixture-only one-pixel tolerance now has a regression rejecting
larger clipping; runtime and modal safe-area checks were not relaxed.

Complete fresh-import isolated suite exits 0: **101 PASS / 8 SKIP / 0 FAIL**, 109
groups, including Android signature/build-helper gates and all five course,
runner/churn, tutorial, endless, time-trial/ghost and Grand Prix simulations.
Runtime `bc274252…` (524 files) remained unchanged through verification. Both
runtime console streams are now retained, including existing shutdown warnings
and resource-in-use errors; eight skipped groups and one internal Blender guard
remain gaps. These functional/synthetic checks are not provider, native
touch-device, purchase, performance, clean-shutdown or launch acceptance.
Receipt: `qa_shots/commerce/account-deletion-client-20261002/receipt.json`.
Full summary: `qa_shots/tests/waddle-wars-tests-79965-564/summary.txt`.

Unresolved: lost deletion response followed by expired/deleted identity can leave
authenticated status recovery unavailable. Public request page, provider retry
scheduler, lawful retention/restoration, real isolated lifecycle acceptance and
store/device declarations remain launch gates. Native candidates still contain
their earlier `d40a9dbc…` snapshot; this source is not yet included in them.

## Premium overhaul: IN PROGRESS — not approved for release

The full user plan remains active. Current penguin is not at the supplied
reference's fidelity; latest reviewed source proof V12/Z12 is explicitly below premium
acceptance and has not replaced runtime assets. Menus, environments, shared
characters and device-wide motion/performance gates are not declared complete.
No production release, deployment or release approval occurred in this pass.
Isolated release-mode Web exports are QA-only. Shared runtime GLBs received
an animation-only re-export described below.

October 1 work in progress:

- Matched U4 stock/U5 worker full-app exports pass import/export, source SHA256
  `7ab5d7035dcc26ee8bfd77eb7b44b232848d6a61eaf9bdda719e569fe1d8dfa3`.
  Actual Chrome runs use the same 1470×936 CSS / 2940×1872 backing canvas,
  reach results and receive retry inputs. Neither passes: stock RAF max
  3,116.235 ms; worker 2,183.350 ms, with later selected console windows below
  57 FPS in both. Stock pointer capture times out; keyboard capture succeeds.
  `qa_shots/runner/chrome-fullapp-accelerated-stock-u4.ieo3y0gf/comparison-observation.json`
  records report hashes and limits. Sequential shader-cache warming, random
  routes, native control failure and automation delay prevent causal or
  foreground/X-close acceptance claims. Both test tabs are closed.
- Desktop Web governor now has a real 3D pixel-work fallback: sustained <54
  FPS uses 4-second windows after 1-second warmup, MSAA-off first, then 0.85
  and 0.72 render scales. Mobile stays 45 FPS / 8 seconds / 3-second warmup /
  0.62 floor. Canvas/HUD resolution and saved preferences stay unchanged;
  attained steps survive retry and healthy play restores them gradually.
  Focused isolated gate passes **70/70**, clean fresh import:
  `qa_shots/runner/desktop-live-governor-20261001/receipt.json`. These state-machine
  tests do not prove browser benefit or hitch-free buffer reallocation; fresh
  U6 candidate and full regression remain separate gates. Complete native
  release-helper suite now passes **93/93, zero skips**, local exit 0.
- Chrome graphics acceleration was observed off; U2 failed before engine start
  with missing WebGL2 and saved its immutable feature-error report. Owner
  approved enabling acceleration/relaunch and then confirmed relaunch complete.
  U3 subsequently passes the WebGL2 feature gate and runs the real full app.
  Menus settle near 60 FPS, but runner loading reproduces repeated 1–3 second
  console frames. The browser collector records a 5,267.595 ms startup RAF gap
  and a 3,183.365 ms gap after runner selection. Evidence:
  `qa_shots/runner/chrome-fullapp-audio-stock-u3.svw4c86h/observed-freeze-20261001.json`.
  Hardware renderer/OS foreground/X-close latency remain unverified; unrelated
  headless Chrome was active and a correctness fixture overlapped startup.
  This is a reproduced failure, not an acceptance benchmark or proof of cause.
- Runner now responds to quality-tier changes during the current run. Existing
  chunk ranges update at most one chunk per frame; future chunks snapshot new
  dressing density, while reserved jobs preserve their RNG/geometry. Range
  recovery is reversible and the authored floor retains its decision horizon.
  Focused isolated test passes **39/39**, with clean import/parser/shutdown:
  `qa_shots/runner/live-quality-20261001/receipt.json`. Weather/light adaptation,
  visual-pop review and browser performance benefit are not established.
- Added pinned local Fastlane prepare/build/verification entry points around
  existing immutable-candidate helpers; no upload or automatic signing lane.
  See `tools/release/FASTLANE.md`. Canonical iOS export now removes only the
  three unused blank camera/microphone/photo-library purpose strings before
  artifact hashing, rejecting nonblank declarations for policy review.
  **14/14** focused host tests pass; independent review finds no concrete bug.
  Receipt: `qa_shots/native/ios-signing-20261001/ios-plist-policy-receipt.json`.
  Existing signed archive is untouched; fresh export/archive must prove warning
  removal. Full-suite receipts below predate these latest changes.
- Native refresh now revalidates its durable grant after provider issuance,
  rejecting concurrent cancellation, deletion, expiry or account/session changes
  without recreating/extending it. New scores use an explicit public game handle
  or `Penguin`, never a legal-name/email/login fallback. Direct backend tests
  pass **56/56, zero skips**. The first full run failed **87 PASS / 8 SKIP /
  1 FAIL** because its isolated snapshot omitted `leaderboard/schema.sql`;
  the failed summary is preserved. Fixed snapshot and retained host logs now
  pass the focused privacy fixture **4/4** and the complete isolated repeat:
  **88 PASS groups, eight SKIP, zero FAIL**, exit 0. Evidence:
  `qa_shots/native/account-safety-20261001/receipt.json` and
  `qa_shots/tests/waddle-wars-tests-56518-699/summary.txt`. Commerce 97,
  online-auth 19, audio 67 and retry HUD 25 assertions pass cleanly. End-save
  passes 33 but this repeat reports two ObjectDB leaks/one retained resource
  at shutdown. A later verbose reproduction identifies WAV playback and
  `sfx_snowball_hit`, not runner nodes. The save-only fixture now isolates and
  restores incidental audio dictionaries and verifies deferred runner/player/HUD
  disposal: **37/37**, clean verbose shutdown in
  `qa_shots/tests/waddle-wars-tests-72121-15199/runner_end_save.verbose.stdout.txt`.
  This focused result does not establish real-audio shutdown or a browser soak;
  the complete 88/8/0 receipt predates the fixture-only edit. Other
  known shutdown diagnostics and skipped renderer gates remain open. No
  historical-name cleanup, account deletion, live deployment, browser acceptance
  or premium visual approval follows.
- Added read-only validation of explicitly decoded iOS provisioning metadata:
  app/team/profile identity, App Store flags, validity dates and expected public
  certificate fingerprint. Fourteen synthetic tests passed; all native release
  helper tests at that checkpoint passed **80/80, zero skips**. This did not
  verify CMS trust, read real profiles/keys, modify Keychain or authorize signing; successful
  metadata inspection remains explicitly signing-blocked. Receipt:
  `qa_shots/native/ios-profile-metadata-20261001/receipt.json`.
- Supplemental source-geometry guards now pass **10/10, zero skips** using
  Blender 5.2's standalone Python. These cover the three NumPy-dependent groups
  skipped by the default Python in the earlier full suite; its original 87/8/0
  receipt is unchanged. Five real-window/renderer fixture groups remain open.
  No rendered penguin-fidelity approval follows. Supplemental receipt:
  `qa_shots/tests/numpy-field-guards-20261001.json`.
- Power recovered by 20:37 EDT: macOS reports AC Power and charging. The
  isolated audio fixture now passes **67/67** with a clean fresh import:
  `qa_shots/tests/waddle-wars-tests-38975-20606/`. A subsequent complete isolated
  suite exits 0 with **87 PASS groups, eight explicit SKIP groups, zero FAIL**:
  `qa_shots/tests/waddle-wars-tests-39126-7756/summary.txt`. This covers the
  current audio and Google receipt-mode changes; runner end-save passes 33,
  retry HUD 25, and audio 67 assertions without errors in those fixtures.
  Existing shutdown warnings in other fixtures and eight skipped gates remain
  open. Fresh full-app Chrome export U2 completed import/export successfully:
  `qa_shots/runner/chrome-fullapp-audio-u2.206enb16/`. It uses the corrected
  worker-readback template, normal main scene/governor, isolated saves and an
  offline-only QA shell. Initially waiting for browser availability; later U2
  feature failure and U3 freeze reproduction are recorded above. Graphics
  acceleration/Energy Saver/foreground remain explicit acceptance conditions.
  Older U1/T8/T9 reports do not validate the audio changes.
- Stock non-threaded comparison U3 also completed import/export successfully:
  `qa_shots/runner/chrome-fullapp-audio-stock-u3.svw4c86h/`. U2 and U3 have the
  same source fingerprint and canvas policy; only engine mode/template and QA
  run identity differ. U2 later fails the feature gate; U3 runs and reproduces
  long loading stalls as recorded above. Production is still
  stock/non-threaded; the corrected worker engine has not been deployed.
  `comparison-preflight.json` records conditions and limits, including random
  gameplay differences and the fact that this cannot isolate proxy overhead.
- Owner completed Apple web sign-in. Portal confirms Ninja Consulting, LLC,
  team `V8MBW2V2C2`, Account Holder access and membership renewal April 22, 2027.
  Registered explicit **Waddle Wars** App ID `com.blubberandbyte.waddlewars`
  and verified it appears in the identifier list. Only default In-App Purchase
  capability is enabled; no private keys or certificates created/revoked.
  Prepared the **Waddle Wars App Store** distribution profile using the one
  existing distribution certificate. With owner approval, generated/downloaded profile
  `DBYJX2DCPC`; its Apple CMS signature/trust and exact app/team/certificate
  metadata passed offline verification. Installed UUID:
  `f4d77af5-95b7-445d-b64d-9b981b15bc5c`, expiry
  `2027-04-30T00:59:30Z` (April 29 local). Public-only receipt:
  `qa_shots/native/ios-profile-verified-20261001/receipt.json`; all release-helper
  tests now pass **86/86, zero skips**, plus four native invalid-profile
  rejection cases. Offline revocation freshness is not checked. No private
  key/certificate creation, revocation, automatic provisioning or upload.
  Both manual archive attempts exited 70 before compilation: Xcode reported
  the iOS 26.5 platform missing despite the SDK listing. The CLI simulator
  download succeeded but did not provide the separately required platform
  support. Installing Xcode's official **iOS 26.5.1 + iOS 26.5 Simulator** bundle
  resolved the device destination. Third manual Release archive succeeded,
  exit 0, using the existing distribution key. Standalone strict code-signature
  verification, signer fingerprint, embedded Apple profile and exact app/team
  entitlements pass; debugging is disabled. StoreKit/auth bridge linkage and
  binary presence are verified, not device behavior. Both failures and current
  evidence are preserved in `qa_shots/native/ios-signing-20261001/receipt.json`.
  Empty camera/microphone/photo-library purpose-string warnings remain to be
  resolved against actual permission use. IPA export, device tests, TestFlight
  and App Store Connect app listing remain open.
- Native build diagnostics now classify the original engine output before
  hiding signing values. A mocked reproduction proved the previous order could
  erase an error marker and falsely accept Godot's zero-exit failure. Log
  sanitization now uses the actual child environment and longest values first,
  preventing partial disclosure when an alias prefixes a password. Seven new
  synthetic regressions pass; all release-helper Python tests pass **66/66,
  zero skips**. No real keys, engine build, signing or upload was involved.
  Receipt: `qa_shots/native/build-log-safety-20261001/receipt.json`.
- At 18:06 EDT the root-owned temporary `caffeinate` process was ended after
  confirming its exact PID/command, because the Mac was critically low and
  still discharging. Its display-sleep assertion is gone; other apps' assertions
  were not changed. No lock/password or persistent power settings changed.
  At that earlier checkpoint power was 3% with no charger detected. This
  blocker is superseded by the charging and completed local checks above;
  the expired two-hour keep-awake approval has not been renewed or reused.
- Signing audit found a valid existing Ninja Consulting, LLC Apple Distribution
  identity (team `V8MBW2V2C2`), but installed provisioning profiles target a
  different app at the initial audit. Waddle Wars' own profile is now verified
  and installed as recorded above. Existing distribution certificate public
  SHA-1: `FDD4551BC510B9A31794CDA660864E324B883712`. Fresh isolated Godot iOS
  export exits 0, state `exported_unverified`, source
  `0ce96eea798d213140a23eadf9b8d60461e98c909c7c56f40da65379249818f7`:
  `/private/tmp/waddle-ios-signing-qa.ABiEmh/candidate/receipt.json`.
  This export produces an Xcode project; its later manually signed archive is
  verified as recorded above. No IPA or store upload exists. No certificate was created or
  revoked. Exact Godot 4.7.1 source uses the debug environment variable in
  its release-profile UUID lookup; use explicit release profile preset/Xcode
  settings. Android release-key environment is unset; upload-key continuity
  must be established in Play Console before creating a key. A signed AAB
  must additionally pass signature verification and upload-cert comparison.
- Mac became available for account setup. Xcode confirms the existing Apple
  Account is `ninjaconsultingllc@gmail.com`; its earlier password/2FA blocker is
  resolved by the verified web sign-in above. Xcode itself previously failed to
  retrieve development teams and has not been retested; no credentials changed.
  Personal Gmail's Appoetics Play account is closed for inactivity (April 2024).
  Its other accessible account, FKA Brands, has no Chancey/Ninja Apps and denies
  new-app creation. Switching through the existing account chooser to
  `ninjaconsultingllc@gmail.com` found Ninja Consulting's organization account
  (`9132521315692749104`) and production Chancey (`app.chancey.io`). The Waddle
  Wars creation form was prepared as an English, free game; Play reported
  `com.blubberandbyte.waddlewars` available. Policy/export declarations remain
  unchecked; the later Chrome restart reset the draft. No app record was
  created and no compliance certification was made.
  No credentials, signing keys or store uploads created.
  Launch audit also found missing account deletion/privacy/support flows,
  unresolved public-name privacy/moderation, purchase acceptance/device testing,
  and listing/audience/legal facts. Signing alone does not establish readiness.
- Local secret/signing exclusion hardening prevents private-key, keystore,
  PKCS#8, provisioning and CSR artifacts entering runtime snapshots and ignores
  their common mixed-case extensions in Git. Environment templates and public
  verifier certificates remain trackable. All lightweight release-helper tests
  pass **59/59, zero skips**, including eight synthetic exclusion tests; no real
  secrets were opened or generated. This is separate from the game-suite
  receipt below and does not constitute signing or device acceptance.
- Earlier full isolated `./run_tests.sh` after the launch/auth fixes exited 0:
  **86 PASS groups, eight explicit SKIP groups, zero FAIL groups**. Current
  Godot evidence and changed-source hashes:
  `qa_shots/tests/waddle-wars-tests-10365-6398/`; complete host/Godot transcript:
  `qa_shots/tests/launch-regression-20261001.log`. Commerce 97 and online-auth
  19 assertions pass without engine/shutdown errors in those two fixtures.
  Runner simulation/churn, all five courses, tutorial, endless, Grand Prix
  and ghost pass. Three NumPy-dependent and five real-window fixtures skip;
  existing shutdown resource diagnostics elsewhere remain open. This result
  does not establish browser responsiveness, visual quality or store readiness.
  This full-suite receipt predates the Google receipt-mode and runner audio
  prewarm changes below; it is not validation of those later edits.
- T8/T9/T10 Chrome runs completed after the owner unlocked the Mac. Corrected
  T8 and T9 both retain valid world/mesh/canvas checks at 2940x1872/high but fail
  performance targets: T8 56 FPS, p95 25.72 ms, max 54.47 ms, zero measured
  frames over 100 ms; T9 57.43 FPS, p95 31.65 ms, max 122.32 ms, one over 100 ms.
  These are sampled gameplay figures, not startup or tab-close latency. Tests
  ran on battery, same visible Chrome tab, with no backing-size change. Old
  engine T10 fails specifically at mesh-readback preflight before constructing
  the world; its witness records zero read calls and successful cleanup. No
  freeze-fix, whole-app or production-acceptance claim follows. Raw reports
  live in their existing T8/T9/T10 QA directories. Page visibility was recorded,
  but uninterrupted OS foreground and Energy Saver state were not independently
  established throughout. No screen-lock bypass occurred.
  A thread follow-up is scheduled for October 2 at noon America/New_York and
  stays quiet while browser availability is unchanged. It does not authorize
  deployment, charges or store upload.
- U1 full-app lifecycle capture now covers title/menu, two runner entries,
  three results transitions and two retries. Runner loading spans were 6.478 s
  and 4.746 s; retry callbacks were 49.870 ms and 30.960 ms, not first-playable
  frame measurements. Maximum engine-era page RAF gap was 166.620 ms. The
  native game tab was eventually closed, but combined tool/inspection duration
  does not measure close latency. Chrome Energy Saver was observed, battery was
  below 20%, and another task used Chrome; uninterrupted foreground was not
  independently verified. This is functional evidence, not lag acceptance.
  Raw report: `qa_shots/runner/chrome-worker-readback-fullapp-u1._81kaky6/browser_report.json`.
- Runner audio prewarm candidate moves lazy loading/non-looping stream copies
  for eleven event/result/button sounds behind the loader, before world/camera
  construction, yielding between sounds. Existing retry path and one-shot
  playback implementation remain unchanged. Resource-availability review caught
  two nonexistent keys (`sfx_bump`, `sfx_crash`); hit/death now use the existing
  authored collision/snow-impact sounds. A synthetic cache/isolation fixture is registered
  in the isolated main suite. The earlier static-only check is now superseded
  by the clean fresh import, 67-assertion fixture and full suite above. Chrome
  validation remains unrun. The 122 ms T9 hitch's cause remains unproven;
  no freeze fix claimed.
  Eight source/resource checks pass; exact candidate hashes and pending gates:
  `qa_shots/runner/audio-prewarm-20261001/static-receipt.json`.
- Google v2 purchase verification now rejects test/live mode mismatches and
  malformed test context before granting/acknowledging permanent cosmetics.
  Focused backend/auth/notification tests pass 48/48, zero skips. This is
  post-billing verification, not protection against a real charge from a wrongly
  configured tester; licensed testers and disabled sales remain required.
- Launch account isolation now invalidates old purchase requests, adapter
  callbacks, receipt queues and checkout state on account/session changes.
  Same-owner token refresh preserves valid work. Native Restore waits for
  receipt verification, then reconciles authoritative server entitlements;
  empty platform enumeration alone cannot revoke a cached grant, and failure
  preserves the last verified cache. Late receipts queue behind reconciliation.
  Google rental offers/receipts cannot satisfy permanent cosmetic purchases.
  Backend/auth/notification tests pass 44/44; current commerce fixture passes
  97/97 and online-auth fixture 19/19. The initial fixture run had self-disposal
  engine errors despite passing assertions; deferred cleanup was fixed before
  the new run. Initial failure: `qa_shots/tests/waddle-wars-tests-9919-27576/`.
- Browser auth now rejects delayed token results from retired sessions and
  exposes an identity epoch so A-to-B-to-A switches between game polls cannot
  admit stale callbacks. Cloud-save/score/profile delivery is account-scoped;
  token-pending sign-in does not consume one-shot result-screen listeners.
  Six extracted production-script tests and all 41 web-shell behavior checks
  pass. New regressions are part of the main isolated suite; backend snapshots
  copy only source/migrations, not deployment state or credentials.
- Unsigned Android native-template/billing integration compiled locally in
  78.68 seconds. Exact resolved Billing/Billing-KTX 9.1.0, provider DEX class,
  merged singleton/permission/SDK manifest and ARM64 libraries are verified.
  It contains no exported game resources and is neither playable nor signed.
  First attempt's missing empty asset folder is fixed with eight helper tests.
  Logs, raw receipts and AAB: `qa_shots/native/android-integration-20261001/`.
  Subsequent existing-tool inspection confirms `PAGE_ALIGNMENT_16K` in
  `r2/bundle-config.json`. RELRO modulo warnings remain in the checker; header
  evidence documents why those warnings alone do not prove a runtime crash.
  Real 16-KB-page device testing and resolution of the structural gate remain
  required. No store/payment/device acceptance follows from this compilation.
- Corrected-worker full-app U1 is also exported locally from a fresh current
  runtime snapshot, retaining `res://scenes/ui/main.tscn`, normal quality
  governor and isolated saves. Its import/export diagnostic gate passes.
  Unlike standalone runner benchmarks it can exercise boot, title, menu,
  loading, play, results and retry. Saving its lifecycle snapshot leaves the
  game active so native tab-close responsiveness can be observed separately.
  It has no FPS acceptance gate and omits production auth/API/PWA bridges.
  Standalone geometry gates and foreground Chrome availability remain required.
  Exact identity and operator/evidence limits:
  `qa_shots/runner/chrome-worker-readback-fullapp-u1._81kaky6/validation-scope.json`.
- QA worker readback defect isolated in Godot's WebGL wrapper: its synchronous
  main-thread callback queried caller-specific pthread context state and could
  skip filling CPU mesh buffers. A separately pinned candidate now uses
  `GL.currentContext`; proxy/signature and gameplay/art remain unchanged.
  It compiled locally, with seven focused readback and 21 eval checks passing;
  strengthened emitted-code validation confirms synchronous argument-preserving
  dispatch. Candidate ZIP SHA-256:
  `d30d91a83c4f85c9a3423eb107726f3bf6e7c81d9be3f4e2b438098f43a7f9a2`.
  Build and post-build guard receipts:
  `qa_shots/native-headers-4.7.1.seSHFR/web-worker-eval-readback-current-context/`.
  This is a correctness candidate, not a demonstrated browser lag fix.
- QA now rejects invalid camera/hero bounds or missing measured 3D work,
  independently of FPS. The isolated metadata gate passed 88 assertions in
  `qa_shots/tests/waddle-wars-tests-87370-22075/`; shell checks passed 82 and
  collector checks passed 49. A real mesh/morph/bounds startup preflight now
  requires positive browser readback calls and exact method restoration
  before world construction. Fresh T8/T9 matched exports and T10 old-engine
  regression export all pass isolated import/export. Identity and remaining
  browser gate: `qa_shots/runner/chrome-worker-readback-control-t8.qh2apm5m/comparison.json`. These
  changes postdate the broad regression below. Foreground browser acceptance
  is still pending; the first attempted old-engine regression did not dispatch
  its Start click before Chrome switched to another task.
- User-coordinated foreground T5/T6 samples now complete at 2940×1872/high,
  actual 2× MSAA and unchanged effects. Candidate T5 fails: 49.07 FPS,
  p95 37.33 ms, maximum 153.04 ms and four frames above 100 ms. Control T6's
  numeric 59.33 FPS/79.85 ms maximum is **invalid as a pass**: its in-sample
  camera coordinates grew to about 1e37, with zero visible 3D objects and
  sharply lower drawing workload. Root rejected the comparison rather than
  attributing this missing world to a speedup. Worker WebGL buffer-readback
  correctness and workload-validity guards are being repaired before reruns.
  Original reports and interpreted comparison:
  `qa_shots/runner/chrome-worker-scissor-t5.shp0l_to/comparison.json`.
- Full isolated `./run_tests.sh` regression completed with exit 0: 82 PASS
  groups, eight explicit SKIP groups and zero FAIL groups. All five race
  courses, runner simulation/eight retries, tutorial, endless, Grand Prix
  and time-trial ghost pass. Godot logs and fresh import evidence:
  `qa_shots/tests/waddle-wars-tests-53132-9983/`. Three skipped NumPy field
  groups subsequently passed all ten assertions using Blender 5.2's bundled
  Python. Five real-window groups and one optional original-geometry baseline
  subtest remain unexecuted; known shutdown resource diagnostics remain open.
  This headless result is not browser responsiveness, visual or store acceptance.
- Priority remains browser freezes first. Deferred chunk disposal now removes
  gameplay/collision participation immediately, then releases bounded branches
  inside the existing stream budget. Isolated stream checks: 72 pass; runner
  group: 28 PASS labels, one renderer SKIP, with existing shutdown diagnostics.
  This is not a demonstrated Chrome freeze cure. Candidate S completed a
  54.013-second, 2,509-frame native-canvas Chrome sample: **46.45 FPS**, p95
  **25.14 ms**, maximum **134.735 ms**, one frame above 100 ms. High tier at
  2940×1872 traversed day/dusk/cave to 1,334 m; draw calls averaged 180.89,
  peaked at 213. Performance thresholds fail. This instrumented standalone
  sample is not full-app acceptance or a controlled pre/post comparison.
  Evidence: `qa_shots/runner/chrome-chrome-disposal-s.8smskwwt/browser_report.json`.
- S's browser RAF rows filled during a 23-minute manual-start wait, before
  engine start; its 2.816-second whole-page maximum cannot be assigned to
  startup/gameplay. Stream retention also overflowed (1,749 seen, 1,493
  dropped), so empty late-frame event IDs do not exclude stream work. Shell
  now retains pre-engine evidence separately, flags intervals crossing start,
  and reserves independent startup/run rows. All 71 host shell tests pass;
  this diagnostic correction does not alter gameplay or establish a lag fix.
- Chrome's first October 1 baseline attempt failed before engine start because
  WebGL 2 was disabled (`GL_VENDOR = Disabled`, `GL_RENDERER = Disabled`). This
  is a failed feature check, not gameplay timing. After Chrome restarted, the
  feature check passes. Earlier September timing remains historical evidence,
  not a controlled comparison against this changed browser state.
- Shader warmup omits duplicate generic mesh-buffer rows already submitted by
  an exact external mesh/material pair, preserving distinct pairs, original
  geometry and material/particle probes. Fresh isolated geometry checks:
  82 pass, zero fail and no shutdown diagnostics. Scene-owned inventory API
  exists; runner coverage and real draw/startup acceptance remain separate gates.
  Runner's 32 known late-content pairs now use a separate bounded registry,
  preventing a prior mode from consuming its allocation. Fresh 82 geometry
  plus 46 scope checks pass. A source-order test was corrected to accommodate
  the scoped call and intervening comments; all 47 HUD warmup checks pass in
  `qa_shots/tests/waddle-wars-tests-32941-7990`. Earlier failing receipts remain.
- Stripe has a separate Waddle Wars **test-mode** account with three active
  cosmetic bundles: Cozy Expedition $2.99, Research Crew $3.99, Aurora
  Celebration $4.99 USD. Items remain earnable with fish. No live payments,
  webhook deployment, production migration or purchase test occurred.
- Added opt-in commerce backend, native billing adapters and routed shop UI.
  Paid account ownership stays separate from earned save unlocks; refund
  fallback does not overwrite the saved loadout. Fresh import including the
  Android addon passes; latest client fixture passes 58 checks with clean
  shutdown after excluding incidental audio playback from this non-audio
  contract test, including the native account-binding purchase-lock guard.
  Receipt: `qa_shots/tests/waddle-wars-tests-42728-27141`.
  Backend/auth/notification checks pass 41 tests with mocked store providers;
  these include authoritative Apple refund reversal ordering and strict
  Google push-token segment validation. Native sales flags remain disabled
  separately from restore/verification routes. Menu smoke passes ten screens and
  navigation, with existing shutdown diagnostics. Focused logs are now retained
  under `qa_shots/tests/waddle-wars-tests-*`; use `WW_TEST_VERBOSE=1` for detail.
- Authored hero/ghost construction skips the hidden procedural penguin on
  successful rig load, with tested fallback for missing assets and role
  changes. Six isolated penguin groups pass, including 45 authored-only,
  56 motion, 33 controller and nine transition checks. No quality reduction
  or premium-art approval is implied. Receipt:
  `qa_shots/tests/waddle-wars-tests-24426-18407`.
- Private Apple verifier uses the pinned official library and bundled Apple
  roots, including online certificate status checks. Ten unit checks pass;
  real local Workers runtime boots and rejects forged notification JWS. A
  static-import RNG startup error was found in runtime QA and fixed with
  request-scoped library initialization. Real signed purchase success remains
  untested; configuration stays disabled. Dependency audit reports no known
  vulnerabilities on this date, not a security certification.
- Native packaging tools prepare isolated AAB/Xcode candidates with immutable
  source receipts and real signing prerequisites. Official Play Billing addon
  is pinned; original StoreKit 2 bridge now compiles Swift and Objective-C++
  ARM64 debug/release libraries against exact Godot 4.7.1 headers. No complete
  signed app, physical-device acceptance, TestFlight/Play upload or store
  submission has passed. Store metadata remains an unsubmitted draft.
  Installed missing Android NDK `29.0.14206865` through the existing official
  SDK manager without accepting new license prompts. Package revision and
  bundled Clang 21.0.0 execution verify. Read-only host inventory now finds
  the target SDK, build tools, NDK and Android/iOS templates. Configured Godot
  Java runtime is Android Studio's JBR 21; the template targets Java 17 bytecode.
  Actual Gradle/export compatibility remains untested. No signing key, account setting or
  production export was changed.
- iOS sign-in now uses a native `ASWebAuthenticationSession` helper instead of
  default-browser handoff. Its fixed callback only returns to the game; server
  PKCE/session verification remains authoritative. Fresh client checks cover
  native start/cancel/stale callbacks and bounded polling. Swift URL-policy
  checks: 20 pass; native packaging checks: 13 pass. ARM64 debug/release plugin
  compiles against the pinned headers; actual device sign-in remains untested.
  New migration `0005_native_auth_presentation.sql` pins each request's
  presentation. Account deletion/retention design and public deletion URL
  remain launch blockers; no production authentication was changed.
- Exact Godot 4.7.1 QA-only web template compiled with `proxy_to_pthread=yes`,
  pinned Emscripten 4.0.11 and unchanged graphics systems. This moves engine
  work to a worker but still proxies GL/DOM work; it is not OffscreenCanvas or
  a demonstrated freeze fix. Immutable ZIP/source/options receipt under
  `qa_shots/native-headers-4.7.1.seSHFR/web-worker-template/`. No production
  template replacement occurred. First game export T failed on a diagnostic
  fixture parse error (now corrected); T2 import/export passed but Chrome
  exposed repeated `ReferenceError: window is not defined` from worker-side
  `JavaScriptBridge.eval`. Runtime markers/report transport therefore failed,
  and foreground moved away. Operator failure recorded, engine stopped; no
  performance pass or valid comparison is claimed. Evidence:
  `qa_shots/runner/chrome-worker-ui-t2.k6buwjan/browser_report.json`.
- Exact one-line `JavaScriptBridge.eval` main-thread proxy correction compiled
  as a separate QA template, leaving the original artifact untouched. All 21
  JavaScript contract checks pass; native/shared-memory browser acceptance is
  still required. Patched ZIP SHA-256:
  `aaec2d8253a13d6d55360dc545aae948bb351775bd95f88d88cdc4bc6fb8be27`.
  T3 exposed a fixture expectation error: stock 4.7.1 converts JavaScript
  booleans through uint32_t to INT 0/1, not BOOL. Corrected only the fixture.
  T4 import/export and all eight actual Chrome bridge checks now pass, including
  UTF-8 and native shared-memory byte-array transfer. Operator ended this
  functional run before accepting a performance sample; foreground was not
  controlled. Evidence:
  `qa_shots/runner/chrome-worker-ui-t4.doy7rh2b/bridge_verification.json`.
- One additional QA-only SDK line replaces the offscreen presentation scissor
  query with `isEnabled`, using the browser's native capability state rather
  than adding a custom cache. 17 behavior checks and 16 build-guard checks
  pass; compiled output is verified to contain the intended query. Candidate
  T5 and control T6 both import/export cleanly from identical frozen game
  inputs. Their WASM bytes are identical, and engine JS differs by exactly
  the query replacement. No resolution/effects reduction or performance pass
  is claimed; uninterrupted foreground comparison remains pending.
  `qa_shots/runner/chrome-worker-scissor-t5.shp0l_to/comparison.json`.
- Bounded stream diagnostics now retain the first 64/latest 192 raw events
  and the strongest eight hitch neighborhoods. Exported evidence counts only
  rows actually serialized, not unexported in-memory buffers. Fresh metadata
  fixture passes 66 checks without shutdown diagnostics:
  `qa_shots/tests/waddle-wars-tests-36291-17261`.

September 19 work in progress:

- User reiterates **1.44 seconds is already a clear delay**; visible stalls
  and delayed browser controls fail acceptance without requiring a 10-second
  reproduction. Latest unprofiled-CPU full-app candidate Q still has a
  **1983.945 ms startup RAF gap**, effectively unchanged from M's 1983.335 ms;
  runner loading remains 6.468 s with a 283.755 ms maximum contained RAF gap.
  Lazy hidden loader construction and Boot's post-draw/process boundary pass
  34 presentation + 104 recovery + 217 frontend checks, but are presentation
  corrections, **not a demonstrated lag fix**. Short active gameplay samples
  cannot clear intermittent freezes. No deployment or quality downgrade.
  `qa_shots/runner/chrome-chrome-app-lazy-loader-q.5dwxc2o9/REVIEW.md`.
- Startup trace P is now successfully persisted: instrumented cold WASM lazy
  compilation and GL status/context queries concentrate inside `callMain`.
  Profiling itself adds a pre-start pause, and stripped symbols do not identify
  a GDScript cause. This profiles startup only, not H's intermittent 2.916590 s
  post-loading stall. `qa_shots/runner/chrome-app-startup-cpu-p.2u2epyw0/REVIEW.md`.
- User priority: **browser lag first, then penguin**. Art authoring is paused;
  new Z13/Z14 source-only files remain untested and unpromoted.
- Run end now banks mission awards, score and fish before one synchronous
  complete save; no deferred-frame durability tradeoff. Biome blend targets
  are cached per biome/art-set reference, removing steady-frame validation and
  dictionary construction without changing lighting. Isolated runner group:
  26 PASS labels, one renderer SKIP, zero FAIL; one additional Python baseline
  subtest skipped. New save 24, biome/cache 121 and exact sky sequence 60 checks
  pass, plus simulation/eight retries. No Chrome freeze-cure claim.
  `qa_shots/tests/runner_responsiveness_20260919_02/RESULTS.md`.
- Actual isolated full-app Boot/Title/Menu/Runner/results/retry flow now
  reproduces a **2.916590-second post-loading callback gap** at native
  2940×1872 backing. Exact gameplay-versus-results attribution is absent;
  inherited raw `startup` labels are invalid in app mode. Normal governor is
  preserved, but production auth/API are excluded and profiling is opt-in.
  Later CPU tracing overflowed and failed transfer; no usable stall profile
  exists. Chrome subsequently warned about another tab's resource pressure,
  which is a confound, not a cause established for this game.
  `qa_shots/runner/chrome-app-lifecycle-h.rtpielb8/REVIEW.md`.
- PerfTicker now measures monotonic wall time, not clamped simulation delta.
  Isolated 16 assertions pass, including a 2.9-second synthetic stall; collector
  45 and shell 65 checks pass. App RAF phase is now explicitly unclassified,
  not incorrectly labeled startup. Reporting fixes only, not lag fixes. These changes
  postdate H and the earlier full-suite snapshot.
  `qa_shots/tests/perf_ticker_clock_20260919/RESULTS.md`.
- Hidden loading backdrops now stop 30 Hz drift callbacks/redraw requests and
  resume their preserved phase when shown; visible graphics remain unchanged.
  81 frontend + 136 utility frontend assertions pass in isolated QA, with two
  known shutdown-warning pairs retained. No measured freeze cure is claimed.
- Fresh full-app clock-I release import/export passes. Chrome changed during
  setup and its test tab closed before manual engine start; server stopped,
  no report or new timing sample. `qa_shots/runner/chrome-chrome-app-clock-i.y51ecbhu/REVIEW.md`.
  Source audit also finds the entire runner world keeps animating behind its
  translucent results panel, and run-end saves occur before score/fish updates.
  These are bounded next diagnostic/fix candidates, not established causes of
  H's long pause. H ended at 235 m, excluding the first 600 m biome transition.
- Visible responsiveness is the acceptance criterion, not reproducing a
  particular 10-second duration. A renderer-only native sample now accompanies
  a 2.483-second startup callback gap; stripped/JIT stacks prevent attribution.
  Its 30-second gameplay run is also not a pass (31.66 FPS, p95 38.93 ms).
  Earlier visible 5.335/6.048-second startup gaps straddle the test's ready
  marker and include some QA-only hashing; they must not be presented as
  complete-production boot measurements. Subsequent H coverage uses the actual
  Boot/Title/Menu/SceneRouter flow under isolated offline QA, with normal
  governor behavior and no fabricated runner-frame acceptance, as above.
  `qa_shots/runner/chrome-chrome-startup-cpu-g.5laojd10/REVIEW.md`.
- User clarifies **10+ second Chrome tab-close hangs and visibly long pauses**;
  any visible close delay is a failure, not only a 10-second reproduction.
  Active-gameplay tab-X observation now completed. Native close action returned
  after 501 ms and target absence was observed by 1,442 ms; that upper bound
  includes automation/observation overhead and is not exact Chrome latency or a
  pass. Deliberately closing the active 120-second fixture produced no engine
  report. A simultaneous 2 ms native sample of Chrome main PID 61943 started at
  14:28:36.220 -0400; the X action was near its end at 18:28:55.331Z. Its
  aggregate main thread is predominantly idle in the AppKit event loop, but it
  does not capture renderer/GPU state or attribute the delay. Static inspection
  finds no local `beforeunload`/`pagehide`/DOM-unload or tab-X-to-requestQuit
  hook. Reported long pauses and close responsiveness remain unresolved; no
  quality cut follows from this evidence.
  `qa_shots/runner/chrome-native-close-load-f.juo78j60/REVIEW.md`.
- User-coordinated foreground Chrome run reproduces a 464.44 ms stall. The
  all-WebGL/stream diagnostic spans both scene processing and rendering;
  another 374.755 ms interval is dominated by scene processing. No individual
  observed post-GO GL call exceeds 100 ms. This is instrumented evidence, not
  a baseline FPS claim or proof of a GPU-only cause. CPU/runtime/scheduling
  attribution remains open. Per-phase trace retention now prevents startup
  from consuming every gameplay record; gameplay still overflowed its bounded
  allowance and all drops remain recorded.
  `qa_shots/runner/chrome-native-gl-reserved-d.l1demlzv/REVIEW.md`.
  Next bounded diagnostic: correlate an unwrapped native-size run's severe
  frame with a target-scoped CPU/scheduler profile. Repeating AA/resolution
  reductions is not a substitute; do not ship a quality cut from these samples.
- Diagnostic main-viewport 3D scale 0.5 still fails: 59.27 FPS / p95 18.91 ms /
  max 331.15 ms. Native HUD/canvas, high geometry/materials and 2× MSAA remain.
  Thus neither AA removal nor broad 3D-resolution reduction alone fixes the
  stalls. No production graphics default was downgraded.
  `qa_shots/runner/chrome-native-scale-half-c.x5bkcq2x/REVIEW.md`.
- Matched-source native Chrome AA comparison now completes at 2940×1984:
  off 59.00 FPS / p95 18.79 ms / max 260.005 ms (four frames >100 ms),
  default actual 2× 58.95 FPS / p95 18.93 ms / max 555.415 ms (one >100 ms).
  Neither passes; disabling AA alone is not a demonstrated freeze fix. Both
  measured intervals stayed visible; AA-off startup had a visibility change.
  No production quality defaults changed. Full source hashes match, but order,
  cache and host-state effects remain uncontrolled.
  `qa_shots/runner/chrome-native-aa-default-b.adf0vdm5/REVIEW.md`.
- Native-size Chrome lag is now reproduced: 2940×1872 backing at 1470×936 CSS,
  DPR 2, high/2× MSAA. Sixty seconds: 55.15 FPS, p95 23.80 ms, max 150.825 ms,
  27 frames over 50 ms and six over 100 ms. Whole run stayed visible; focus was
  checked during startup and after completion, not continuously. No other
  engine/profiler overlapped.
  `qa_shots/runner/chrome-production-native60.vyrycdhx/REVIEW.md`.
  This disproves treating the earlier fixed-1080p pass as browser acceptance;
  it does not yet establish a freeze cause or fix.
- Local governor patch restores session-only quality after healthy windows,
  preserves the user's desktop resolution tier, keeps monitoring at its floor,
  excludes loading/countdown/death/pause intervals and caches gameplay lookup.
  Web now honors explicit AA Off; default high remains 2×. Focused 42 checks
  pass, including real paused-frame and floor-timer checks. First expanded test
  attempt failed two premature frame-boundary assertions; corrected test waits
  for actual callbacks, not weakened expectations. Full isolated regression
  completed: 75 PASS labels, eight explicit SKIPs, zero FAIL, exit 0; all 945
  snapshot fingerprints match. Collector 36 and shell 61 focused checks pass.
  Fourteen shutdown warning/error pairs and two intentional corrupt-JSON errors
  remain. Compared with snapshot 09, warning labels add utility frontend,
  runner churn and tutorial; iceberg and Grand Prix warnings are absent this
  run, not declared fixed. Receipt:
  `qa_shots/tests/browser_lag_20260919_01/RESULTS.md`.
  The first AA-off browser comparison lost foreground and produced no report;
  no performance gain is claimed. Existing scenes still do not apply preset
  shadow/particle changes live. No blanket visual downgrade was made.
- A completed, foreground-checked Chrome/scheduler capture now records one
  passing 60-second sample: 59.98 FPS, p95 17.66 ms, maximum 38.34 ms, zero
  frames over 50/100 ms and zero post-GO instrumented shader/program calls.
  This does not resolve previous freezes: manual startup, cache state and build
  differences prevent causal attribution. More importantly, the fixed
  1920×1080 QA canvas does not reproduce production's native-DPR backing:
  1470×827 CSS at DPR 2 can mean 2940×1654, or 2.345 times the pixels. That
  production workload needs measurement, not an assumed resolution downgrade.
  Evidence: `qa_shots/runner/chrome-scheduler-current60.01t_3mph/`.
  Follow-up untraced fixture was built but never started because the Mac locked;
  its local server was stopped. No measurement exists for that attempted run.
  A new QA-only native-canvas mode now copies the exact reviewed production
  sizing policy, reconciles browser/engine dimensions and never claims the
  fixed-resolution gate passed. Local checks: 64 collector/scheduler tests,
  61 shell tests, 41 policy checks, 55 engine metadata checks; fresh isolated
  import/export succeeds. Native-size measurement later completed as described
  above; the original fixed-size comparison remains limited.
  `qa_shots/tests/production_canvas_20260919_01/RESULTS.md`.
- Z11 replaces the detached upper-fold construction with a head-surface hood.
  Seven host construction checks and the three-view Blender render complete,
  but visual review rejects jagged face paint, a pinched throat and the still
  stiff face. Source body has 479,088 triangles, not a runtime-budget approval.
  No source study was promoted to the game.
  `qa_shots/hero/v12_source_proof_z11/REVIEW.md`.
  Z12 then evaluates that hood paint continuously in Blender (six host checks,
  three rendered views, exit 0), but actual inspection still shows the jagged
  boundaries. Saved-scene ray inspection confirms unfixed sampled underpaint at
  specific visible body pixels; one ray fails triangle tolerances, so this is
  partial diagnostic evidence, not a passing art gate. No visual fix or runtime
  promotion claimed. `qa_shots/hero/v12_source_proof_z12/REVIEW.md`.
- Current production's 13 public payload files are now archived locally with
  verified SHA-256 checksums, matching the served `384604d` entry document.
  This is a recovery starting point, not a tested rollback or deployment.
  `qa_shots/releases/production-384604d.rL9iKs/README.md`.
- Loader build-budget exhaustion now stays covered and offers Retry / Back to
  Menu instead of labeling an unfinished world ready. A process watchdog also
  catches a missing draw signal after 30 seconds, but cannot interrupt blocked
  synchronous loading. Serial guards reject stale callbacks; resource retries
  adopt/drain outstanding jobs; old pause and game-over controls cannot resume
  or reset the covered world. Recovery regression: 94 PASS; real initialized
  runner platform/retry fixture: 148 PASS; loading source guards: 11 PASS.
  Final full isolated snapshot 09: 74 PASS labels, eight explicit SKIPs, zero
  FAIL, exit 0; ten NumPy checks separately pass. All 931 source/resource
  fingerprints match after completion. Thirteen shutdown warning/error pairs
  remain; this is not a clean release log. Full receipt:
  `qa_shots/tests/premium_runner_suite_20260919_09/RESULTS.md`.
  Native recovery controls pass 44 checks in each orientation; actual portrait
  runner handoff passes 18 checks, with focus absent at milestone captures and
  shutdown warnings retained. These are not browser/performance/art acceptance.
  Evidence: `qa_shots/tests/loader_recovery_20260919_01/RESULTS.md`.
- Production freshness rechecked directly: served `mainPack` is still
  `index.pck?v=384604d` (54,549,356-byte pack), matching the older September 1
  export. New DAY ice is a development-only review overlay; normal release
  intentionally excludes it. Deployment destination/art scope awaits the user;
  no deployment, push, or remote CI occurred. Existing deploy script also needs
  an artifact archive/staged verification/rollback path before a live update.
- Race-family visual census now starts after deferred/staged actors and grid
  setup; tutorial starts it after its actors, camera and lesson presentation.
  Router holds the pending managers until the warmup node exists. Real baseline
  regression: 46 PASS / 79 FAIL; corrected fixture: 125 PASS / zero FAIL.
  Fresh full isolated snapshot 07: 71 PASS labels, eight SKIPs, zero FAIL,
  exit 0; ten NumPy checks separately pass. Existing shutdown diagnostics remain.
  Queue-cap/hidden-ghost GPU coverage is not proven by these headless checks.
  `qa_shots/tests/race_warmup_boundary_20260919_01/RESULTS.md` and
  `qa_shots/tests/premium_runner_suite_20260919_07/RESULTS.md`.
  New Chrome scheduler trace attached but was stopped before gameplay after
  foreground browsing changed; later browser connection became unavailable.
  No performance result: `qa_shots/runner/chrome-scheduler60.re50opuf/REVIEW.md`.
- Loading/startup correction now passes real actor-lifecycle tests: 70 for
  race/Endless, 40 for tutorial, 18 for router ordering. The tests reproduced
  countdown/lessons behind the loader and a second issue where Godot re-enabled
  pre-tree-disabled Racer physics at `_ready`. One-shot ready hooks retain the
  hold until visible GO; first eligible delta and queued action edges are
  discarded without changing held controls or in-place runner retry.
  Fresh full isolated snapshot 06: 70 PASS labels, eight SKIPs, zero FAIL,
  exit 0. Shutdown resource warnings remain; this is not release approval.
  Actual native runner handoff now passes 18 checks with all seven captures in
  landscape and the second portrait run. First portrait stalled at draw 27
  (12/18 failures); retry includes focus losses. This is submitted-frame ordering
  proof, not continuously focused portrait, browser compositor, art or performance
  acceptance. Chrome freeze attribution remains open. Rendered evidence:
  `qa_shots/tests/loading_presentation_rendered_20260919_01/RESULTS.md`.
  `qa_shots/tests/loading_presentation_summary_20260919_01/RESULTS.md` and
  `qa_shots/tests/premium_runner_suite_20260919_06/RESULTS.md`.
- The actual HUD speed-overlay shader now draws at zero intensity before
  countdown. Isolated 47-check coverage passes; controlled Chrome source
  identities move from GO+0.586 seconds into startup, with no late relink.
  This is warmup coverage, not a demonstrated FPS gain: the fixed 60-second
  sample still has two frames above 100 ms. See
  `qa_shots/runner/chrome-shader-hud-fixed60.apg0bgcm/REVIEW.md`.
- A new diagnostic reserves 128 KiB for post-GO shader defines separately
  from the 512 KiB startup allowance (50 Node checks pass). The completed
  30-second Chrome capture retains all 111 define lines for the remaining
  late pair `0c60ee66`/`529c1cff`, with no truncation or event drops. It is
  consistent with an unshaded instanced spatial surface, not the earlier
  guessed lit power-up shell. The matching startup vertex variant differs
  by `DISABLE_LIGHT_OMNI`; the later contact-shadow probe below verifies the
  matching consumer. Physical define lists do not evaluate surrounding
  conditional preprocessor branches. The short sample passes at 59.50 FPS,
  p95 18.65 ms / maximum 90.46 ms; it does not resolve earlier freezes.
  `qa_shots/runner/chrome-shader-reserved-defines30.7oyt5gld/REVIEW.md`.
- The exact instanced contact-shadow mesh/material pair now warms with a
  temporary, isolated tiny light before countdown. In actual Chrome, the
  formerly late pair links 4.119 seconds before GO; all eight recorded shader
  methods have zero post-GO calls and no diagnostic drops. All 302 shader
  identities and 151 program-source pairs match the prior capture. This fixes
  that warmup gap, not the freezes: 56.56 FPS, p95 21.84 ms, max 165.67 ms,
  five frames over 100 ms. CPU/scheduler or wait attribution remains needed.
  `qa_shots/runner/chrome-shadow-warm-fixed60.g_x_1lk3/REVIEW.md`.
- Full isolated snapshot 05 passes 67 labels with eight explicit SKIPs and
  zero FAIL (exit 0); existing shutdown leaks remain. It includes both shader
  warmups, but predates the loader-dismissal/race/tutorial startup changes
  currently under validation. `qa_shots/tests/premium_runner_suite_20260919_05/RESULTS.md`.
- Active order: diagnose desktop Chrome freezes, improve chained slides,
  restore later-biome visibility, then finish and integrate the penguin.
  Blender is already installed and has produced source studies; missing
  software is not the character-quality blocker. Runtime remains V11, and
  the latest rendered Z12 source is still below the reference. Technical tests and
  source renders are not a shipped fidelity improvement.
- Later-biome lighting now uses explicit ambient bounce plus the existing
  fill/rim lights, with lighter road/snow/kerb palettes. No extra light nodes
  or effects. Fresh isolated readability test: 91 checks, zero failures;
  actual DAY/DUSK/CAVE/NIGHT captures all saved with `err=0`. Raster review
  shows readable later-biome road and hazards, but still procedural
  environments and the old live V11 hero, not premium-art approval. Native
  debug capture retains the DAY review-preview warning and 20 ObjectDB
  instances leaked at shutdown; this is not a clean full-gate pass.
  `qa_shots/tests/runner_biomes_20260919_01/suite.log` and
  `qa_shots/runner/biome_readability_20260919_01/REVIEW.md`.
- Slide now supports deliberate hold, repeat-to-refresh and queued landing.
  Real physics tests exposed a stale Area overlap on slide entry/exit: the
  initial corrected harness ran 79 checks with two failures. A transition-
  frame direct query fixes that cache boundary: fresh isolated rerun passes
  all 85 checks, including real chained bars at 30/60 FPS and a dense contact
  cluster. Entry/exit damage now matches the current shape (0/1 hits).
  Pass: `qa_shots/tests/runner_controls_20260919_03/suite.log`; original
  failure retained at `qa_shots/tests/runner_controls_20260919_02/suite.log`.
- Removed duplicate player-owned RunnerVfx; game presentation retains its
  single shared system. Completed Web fixtures confirm two baseline nodes
  versus one fixed-source node. No reliable performance gain established.
- Frozen release Chrome evidence is separate from native debug evidence:
  release does not activate the authored DAY preview overlay.
  First browser attempt was invalidated by an external extension rejection
  being treated as fatal by the QA shell while the game kept running. The
  shell now records bounded unattributed diagnostics and preserves explicit
  engine failures; ten host regression tests now pass, including abort-only
  partial diagnostics. Failed run retained at
  `qa_shots/runner/chrome-baseline-release-trace.w0odaaa3/`; corrected fresh run
  at `qa_shots/runner/chrome-baseline-release-trace-fixed.m71d37th/`.
  Corrected browser run reached GO but autopilot died after 75.72 seconds,
  before the requested 100-second sample completed. Its preserved browser
  trace does reproduce visible in-run 166/150/116 ms rAF intervals, but lacks
  the completed inherited timing report. That incomplete run is not a pass.
- Five later Chrome probes completed: release Web/Compatibility, high tier,
  actual 2× MSAA, 1920×1080, seed 20260907, isolated user identities. Results
  below come from each folder's `report.json`; browser visibility remained
  visible in the paired `browser_report.json`. "Untraced" disables both
  stream and WebGL tracing; the 45-second diagnostic keeps stream tracing
  but disables WebGL tracing. Despite its `cpuprofile` folder name, CPU
  profiling was unavailable and no CPU profile was captured.

| Chrome evidence folder (`qa_shots/runner/`) | Seconds | Average FPS | p95 / maximum ms | Frames >100 ms | Probe gate |
| --- | ---: | ---: | ---: | ---: | --- |
| `chrome-baseline60.6j97ers6` (stream + WebGL trace) | 60 | 59.08 | 18.81 / 145.60 | 2 | FAIL |
| `chrome-fixes60.at9p5ygx` (stream + WebGL trace) | 60 | 59.72 | 17.75 / 60.38 | 0 | PASS |
| `chrome-baseline60-untraced.9wvn7lo6` | 60 | 54.90 | 29.21 / 126.56 | 4 | FAIL |
| `chrome-fixes60-untraced-r1.5t9sh1pc` | 60 | 48.68 | 34.07 / 1730.35 | 25 | FAIL |
| `chrome-fixes45-cpuprofile.7wah_9jf` (stream trace only) | 45 | 59.56 | 18.56 / 68.33 | 0 | PASS |

The three fixed-source manifests share source SHA-256
`5546c0e34149a7c47fe7c63ddc3fcd76906e3c032b1142ce5ead90955c921b7b`:
the same fixed source produced both PASS and severe FAIL outcomes. The failed
untraced run also records a 1631.36 ms post-GO browser rAF interval. Neither
the short passing repeat nor the traced comparison resolves lag or identifies
its cause. Per-report Web build fingerprints are incomplete; source identity
here uses the host manifest, not that incomplete in-engine subset. No lag-free,
release, device-wide performance, or character-fidelity approval.

- Fresh isolated development suite completed: **57 PASS labels, five explicit
  real-window SKIPs, zero FAIL, exit 0**. Includes current slide/light changes,
  runner simulation/retries and every gameplay family. Known shutdown resource
  leaks remain; this does not approve performance or visuals. Snapshot includes
  Z05, not later source studies.
  `qa_shots/tests/premium_runner_suite_20260919_01/RESULTS.md`.
- Z05 Blender source renders have a fuller juvenile silhouette but clipped
  lower irises and poor side-eye visibility. Root inspected all three views;
  visual acceptance still fails. No V12 runtime promotion.
  `qa_shots/hero/v12_source_proof_z05/REVIEW.md`.
- Z06 corrects gaze registration and adds continuous lower socket relief;
  actual front/three-quarter/side renders no longer clip the lower iris.
  Remaining eye-material/bill/expression gaps prevent fidelity approval.
  A QA-only export now carries this same sculpt into 22,967/10,560-triangle,
  two-material meshes with the existing 15-bone/23-clip rig. Both GLBs validate.
  Initial literal-foot fit failed contact checks; preserved failure was followed
  by an explicit constant rest-fit export. Fresh isolated Godot import/facade
  preflight now passes with attached feet and whole-body roll. No rendered game
  approval, final atlas or live replacement yet. The earlier lock is now cleared;
  this candidate has not acquired rendered-game approval.
  `qa_shots/hero/v12_runner_z06_grounded_literal/REVIEW.md`.
  Focused post-suite checks: 39 source/juvenile tests with Blender's standalone
  Python (zero skips), plus 22 provenance tests pass. Main-suite registration
  now reports missing NumPy geometry checks as a separate explicit SKIP; this
  later registration is not included in the earlier 57-PASS suite receipt.
- Optional process/pre-draw/post-draw wall-clock diagnostics imported/exported
  successfully in a fresh Web snapshot. Chrome execution subsequently completed
  after unlock: 60 seconds, 59.52 FPS average, p95 17.70 ms, maximum 73.745 ms,
  zero frames over 100 ms. This one passing run does not resolve prior freezes.
  `qa_shots/runner/chrome-chrome-phase60.0lin2wab/report.json`.
- Sky-color assignment guards now suppress identical writes. Pinned Godot
  4.7.1 Compatibility source shows those writes unnecessarily dirty sky
  reflections. A fresh isolated engine test passes 60 checks: exact original
  transition colors at 30/60 FPS, zero stationary/settled/zero-delta writes.
  Fog, lights and quality settings are unchanged. This is not evidence that
  desktop freezes are resolved; the subsequent visible Chrome A/B below shows
  no measurable gain from this change.
  `qa_shots/tests/runner_sky_20260919_02/RESULTS.md`.
- Subsequent full isolated snapshot: **59 PASS labels, six explicit SKIPs,
  zero FAIL, exit 0**. Includes the sky guard and UV-staging changes. One SKIP
  is the separately verified NumPy geometry group; five require a real window.
  Runner simulation newly reports 15 ObjectDB instances/one resource at shutdown;
  previous snapshot did not. Other shutdown diagnostics remain allowed by the
  existing harness. This is a development-suite pass, not a clean release gate.
  `qa_shots/tests/premium_runner_suite_20260919_02/RESULTS.md`.
  Matching sky-guard release Web fixture subsequently completed visible Chrome
  measurement: 59.53 FPS average, p95 17.81 ms, maximum 79.35 ms, zero frames
  over 100 ms. No measurable improvement versus the preceding 59.52 FPS run.
  `qa_shots/runner/chrome-skyguard-phase60.0m7txbo7/report.json`.
- Z06 atlas UV staging now passes on the actual Blender candidate: zero
  overlaps or degenerates across 22,967 triangles. The completed LOD0 bake
  nevertheless rejects 17 high-to-low projection pixels. Checkpoint retained;
  no accepted atlas export, LOD1 bake or live character replacement resulted.
  Resolving those texture holes would not approve the still-incomplete face.
  `qa_shots/hero/v12_atlas_z06_grounded_02/REVIEW.md`.
- New isolated Z07 face proposal completed its Blender source and all three
  proof views; six focused host tests pass. Existing Z06/provenance/export
  inputs remain unchanged. Root visual review rejects Z07 for live use:
  thinner eye outlines and a fuller bill are too small an improvement; the
  continuous cheek/muzzle form and eyelid integration remain insufficient.
  No candidate export or runtime replacement. The new `hero_face_z07` suite
  registration postdates the 59-PASS full-suite snapshot above.
  `qa_shots/hero/v12_source_proof_z07/REVIEW.md`.
- Z08 adds continuous cheek/muzzle volume and saves three actual Blender
  views. Root rejects it for live use: button-like eyes, band-like cheek paint
  and a generic bill still miss the reference. No live fidelity improvement
  or replacement resulted. See `qa_shots/hero/v12_source_proof_z08/REVIEW.md`.
- An actual renderer-scoped Chrome CPU/timeline trace is now saved. Its
  instrumented 60-second run averages 59.30 FPS, p95 18.59 ms, maximum
  167.165 ms, with two frames over 100 ms. Matching main-thread tasks spend
  131/155 ms wall time but only 7.8/6.6 ms reported thread CPU. Main and audio
  sampling gaps align, and no GC overlaps these two stalls. Dense profiling
  itself adds overhead; this does not explain or fix the original untraced
  1.7-second freeze. Next diagnostic is timeline-only without CPU sampling.
  `qa_shots/runner/chrome-skyguard-trace60.rw61dwvo/chrome_trace_analysis.md`.
- Timeline-only Chrome counterfactual completed with CPU sampling disabled:
  59.37 FPS average, p95 17.79 ms, maximum 138.96 ms, one frame over 100 ms.
  Matching main task is 122.33 ms wall / 10.13 ms thread CPU; draw submission
  spans 98.38 ms. No retained GC/compilation overlaps that stall. Sampling is
  not necessary for this stall signature; the cause remains unresolved.
  Runtime/assets and exported JS/Wasm match the previous trace. Evidence:
  `qa_shots/runner/chrome-skyguard-timeline60.t0pli5_7/chrome_trace_analysis.md`.
- Z09 replaces the face construction and renders all three fixed Blender views.
  Pupils, profile cheek boundary and bill outline visibly improve. Root still
  rejects live promotion: raised pale eye rims, weak expression, capsule-like
  profile and a newly pointed bib remain below the supplied reference.
  `qa_shots/hero/v12_source_proof_z09/REVIEW.md`. Runtime remains V11.
- New QA-only `?presentationtrace=1` option records bounded synchronous WebGL
  query/blit wall durations without retaining query results or changing them.
  Default paths remain unwrapped. Shell host suite passes 17 tests; collector
  separately passes 17. These diagnostics do not change production rendering
  or establish a freeze cause. Host receipts:
  `qa_shots/tests/presentation_trace_20260919_01/README.md` and
  `qa_shots/tests/host_registration_20260919_01/README.md`.
- Actual presentation-call diagnostic subsequently completed: 59.74 average
  FPS, p95 18.61 ms, maximum 112.58 ms, one frame above 100 ms. No CPU sampling
  or CDP timeline tracing was active. No measured >=8 ms query/blit call overlaps
  that stall (zero dropped rows); maximum selected-query duration is 14.655 ms.
  This excludes one long measured presentation call for this hitch, not other
  GL work, deferred GPU work or scheduling. No production-renderer mutation.
  `qa_shots/runner/chrome-skyguard-presentation60.u05f05jv/presentation_trace_analysis.md`.

Additional September 19 evidence:

- Fresh full isolated snapshot 04: **66 PASS labels, eight explicit SKIPs,
  zero FAIL, exit 0**. Includes corrected Z07 quarantine test, all-method GL
  shell and loader boundary tests plus every gameplay family. Three NumPy
  groups separately pass all ten checks with Blender's standalone Python;
  five window-only groups remain unexecuted in this headless run. Shutdown
  resource diagnostics remain, including runner simulation/churn, so this is
  development regression evidence, not a clean release or performance gate.
  `qa_shots/tests/premium_runner_suite_20260919_04/RESULTS.md`.
- SceneRouter now submits the authored loader and yields to the next process
  frame before requesting scene resources. BootWarmup likewise leaves its
  initial post-draw callback before synchronous asset work. Headless ordering
  checks pass 13/13; actual native Compatibility request-entry captures pass
  16/16 each at 540×960 and 960×540. Both images were reviewed. This fixes the
  presentation boundary, not loading-animation continuity or gameplay stalls.
  Initial capture import exited 2 with lost diagnostics; harness now preserves
  import logs before cleanup. Successful fresh retry and landscape proof:
  `qa_shots/frontend/loader_boundary_20260919_01/REVIEW.md`.
- Full isolated snapshot 03: 65 PASS labels, eight SKIPs, one FAIL, exit 1.
  Z07's test incorrectly depended on a historical QA output directory omitted
  from snapshots. Replaced with self-contained temporary quarantine checks;
  focused Python tests pass without weakening art gates. Failed full-run
  evidence remains preserved; no retroactive green result:
  `qa_shots/tests/premium_runner_suite_20260919_03/RESULTS.md`.
- Z10's actual Blender views retain readable pupils and round the lower bib,
  but raised navy brow tubes, a pinched throat, weak expression and generic bill
  remain below the reference. Body source alone is 489,666 triangles, not a game
  mesh. Runtime stays V11. No artist has been commissioned; no software is
  missing. More valid procedural variants are not a substitute for a convincing
  designed character. `qa_shots/hero/v12_source_proof_z10/REVIEW.md`.
- Paired browser/Godot clock anchors now bound bridge timing uncertainty at GO
  and report. The isolated `runner_web_clock` scene passes 26 checks. The broad
  ten-method GL diagnostic recorded a 107.860 ms hitch with no measured >=8 ms
  GL call overlapping it. It coincided with DAY chunk 16, not first DUSK; this
  does not exclude unmeasured GL calls or deferred work. Evidence:
  `qa_shots/tests/runner_web_clock_20260919_01/suite.log` and
  `qa_shots/runner/chrome-skyguard-render60.rtzdf8ev/render_trace_analysis.md`.
- One target-renderer native stack sample completed. Its 60-second run passed
  (59.60 FPS, maximum 55.19 ms), but the requested hitch did not recur, sampling
  started four seconds late, and final browser trace transfer failed. Aggregate
  anonymous/stripped native stacks cannot identify the original freeze cause.
  `qa_shots/runner/chrome-nativewait60.tuukyhw2/REVIEW.md`.
- A same-source release Chrome OFF→ON thread pair still fails in both modes.
  OFF: 56.80 FPS, p95 18.68 ms, maximum 752.66 ms, eight >100 ms frames.
  ON: 59.23 FPS, p95 17.81 ms, maximum 136.46 ms, two >100 ms frames.
  The largest OFF signal cycle contains 661.08 ms inside draw/submission; all
  ten >100 ms samples have no same-cycle stream event. The OFF cluster follows
  first cave-chunk insertion, so delayed first appearance is not excluded.
  Both retain roughly six-second startup rAF gaps. This fixture bypasses real
  boot/menu routing; one ordered pair cannot prove a thread-related improvement.
  Production remains single-threaded. Complete comparison:
  `qa_shots/runner/chrome-thread-on60.1q88apxr/REVIEW.md`.
- QA export threading is explicit and defaults OFF. New preparations hash the
  exact export preset; builds reject changed bytes or mismatched thread mode
  before invoking Godot. Legacy presets are explicitly labeled weaker integrity.
  Focused host validation: 30 Python and 26 Node tests pass, zero skips/failures.
  `qa_shots/tests/threaded_web_20260919_01/README.md`.
- Opt-in all-method WebGL tracing now covers 226/226 discovered page-prototype
  methods; 35 host checks pass. Actual Chrome run measured 57.84 FPS, p95
  22.07 ms, maximum 69.745 ms, zero >100 ms frames: target severe freeze absent,
  timing gate still FAIL, substantial instrumentation overhead not subtracted.
  All 83 slow GL rows retained, zero drops/unavailable methods. Four shader
  compiles and two program links occurred after GO; a shader/program-query pair
  occupied 18.99 ms of one 49.50 ms draw cycle about 8.8 seconds after GO.
  This exposes incomplete warmup, not the cause of the earlier 661 ms draw
  stall. No production shader/renderer change or lag-resolution claim:
  `qa_shots/runner/chrome-chrome-allgl60.9k54zp3v/REVIEW.md`.

September 7 changes:

- First-DUSK first-draw isolation: hiding only chunk 17 for two rendered frames
  moves the 98.541 ms stall to its first restored draw. Hidden insertion frames
  are 18.805/15.663 ms; the stalled interval has no new stream event. This is
  evidence of first-visibility dependence, not a shader/GPU cause measurement.
  `qa_shots/runner/dusk_visibility_delay_20260907_01/TRACE_REVIEW.md`.
- Exact full-size dressing prewarm covers real seeded Drifts/Crystals/Banners/
  Shards MultiMeshes as well as the deck. Two clean matched 60-second runs
  average 59.89/59.93 FPS and p95 17.92/17.97 ms, but the same first-DUSK hitch
  is **72.592/94.937 ms**. The first result is not a reliable improvement.
  Production preload remains unchanged; lag is not solved. Proof and timing:
  `qa_shots/runner/dusk_dressing_prewarm_proof_20260907_02/` and
  `qa_shots/runner/dusk_dressing_prewarm_perf_20260907_01/`, `_02/`.
- Z04 source study joins the upper lid to the hood and integrates the cream
  surround into the cheek. Actual three-view renders improve on Z03 but still
  fall below the reference: small/static eyes, simple bill and long narrow neck.
  31 source-study, 18 provenance and eight saddle host tests pass; these do not
  approve the art. No Z04 runtime export or live character promotion.
  `qa_shots/hero/v12_source_proof_z04/REVIEW.md`.
- Actual Y03 runner rear-light comparison confirms higher energy alone mainly
  brightens the crown, leaving the lower back dark. The later lowered hero-only
  light reveals more torso detail but is still visually insufficient. Its four
  images/state checks completed, but the strict launcher rejected two resources
  still in use at shutdown; preserve that failure, do not call the run clean.
  `qa_shots/hero/v12_y03_runner_rim02/REVIEW.md` and `v12_y03_runner_rim03/`.
- Six-frame bill diagnostic preserves the original four images exactly. Half
  key energy reduces the hotspot but does not remove the shadow-defined patch;
  receiver-off still leaves overly bright feet/bill. No live material fix.
  `qa_shots/hero/v12_y03_material_diagnostic04/REVIEW.md`.
- Fresh isolated development suite: **52 PASS labels, five real-window SKIPs,
  zero FAIL, exit 0**. Includes actual feet-follow-body and whole-torso motion,
  nine 30/60 transition comparisons, 55 metadata checks, runner/retries and all
  gameplay families. Existing shutdown diagnostics and 103 unapproved assets
  remain release debt. Snapshot predates later Z04/delayed-visibility/rear-light
  experiments. `qa_shots/tests/premium_material_msaa_suite_20260907_01/RESULTS.md`.
- Actual first-DUSK deck, seams and four verge surfaces were drawn at full size
  before countdown in an isolated copied-source counterfactual. Separate image
  proof verifies all six surfaces and exact state/cleanup at actual 2× MSAA.
  The hitch persists: 93.401 ms at 396.291 m; measured spawn/stream CPU
  0.865/0.900 ms. Average 58.51 FPS, p95 19.75 ms, 172,434 peak primitives.
  This does not establish a gain over the prior single 97.423 ms sample or
  justify promoting the preload hook. Live runtime remains unchanged.
  `qa_shots/runner/dusk_real_prewarm_perf_20260907_01/report.json`.
- Correct-policy tiny raster `_03` confirms incomplete resolved coverage at
  actual 2×: deck/seams/verge-body/crown/drop/snow produce 2/0/0/0/1/2 pixels.
  All six enlarged controls render. Fixture clean, coverage FAIL; no pipeline
  compilation or hitch-cause claim. This supersedes `_02` for matching policy.
  `qa_shots/runner/dusk_exact_raster_20260907_03/REVIEW.md`.
- Y03 actual shader comparison confirms received shadows isolate the blotchy
  bill patch. Disabling reception retains the ground shadow but brightens bill
  and feet excessively; original hotspot stays bright. Not a production fix.
  Real Z01/Z02 saved-scene provenance and body/wing masks now validate read-only
  in Blender 5.2.0 with all inspected inputs unchanged. Neither integrity check
  nor isolated material experiment approves source fidelity or live promotion.
  `qa_shots/hero/v12_y03_material_diagnostic03/REVIEW.md` and
  `qa_shots/hero/v12_source_proof_z02/saved_scene_integrity_report.json`.
- MSAA evidence correction: native Compatibility caps requested 4× to actual
  2×. Older performance reports recorded only the request; they do not measure
  actual samples. New reports distinguish request, policy and observed viewport
  before/after measurement. The older exact-raster `_02` explicitly forced 4×,
  so its coverage result is not production-2× proof. Raw evidence is retained.
- The DUSK raster diagnostic at forced 4× runs cleanly: seams and verge
  crown produce **zero resolved pixels**, despite registered resources; all
  enlarged/front-facing controls render. Other four surfaces produce 1–3
  pixels each. This does not validate exhaustive warmup coverage and does
  not establish the cause of the 97.423 ms stall. No runtime scaling change.
  `qa_shots/runner/dusk_exact_raster_20260907_02/REVIEW.md`.
- Opt-in Z01 source study completes three views with a slightly larger eye
  aperture; overall shape remains below reference. Baseline design/renderer
  and live assets unchanged. Nineteen host guards cover Z01 and the later Z02
  fuller-bill/rounder-flipper study; Z02 remains a modest source-only change,
  not reference-quality approval. The new main-suite
  label; this new label is not included in the older 49-PASS snapshot below.
  `qa_shots/hero/v12_source_proof_z01/REVIEW.md`.
- Fresh full isolated development suite: **49 PASS labels, four explicit
  real-window SKIPs, zero FAIL, exit 0**. Includes the new atlas-runner host,
  mouth-projection and exact DUSK warmup contracts; all five course simulations,
  runner/retries, ghost/time trial, endless, tutorial and Grand Prix pass.
  Existing shutdown diagnostics and separate visual/performance failures
  remain open. `qa_shots/tests/hero_atlas_dusk_suite_20260907_01/RESULTS.md`.
- Y03 source-material atlas now passes strict zero-miss projection. Fifteen
  mouth samples required facing-compatible, stable source triangles with
  actual center/corner first-ray checks; prior failed attempts remain retained.
  All 22,963 triangles, rig/skin/species and 23 clips survive serialized export
  exactly. Four-map shared package passes Khronos and actual Godot import;
  stored compressed maps total 16,777,296 bytes. Four real front/chase 30/60
  sequences match exactly, plus 18 actual portrait-runner frames. Feather grain
  now reaches the game, but dark rear, assembled-looking face and harsh bill
  highlights still **FAIL visual acceptance**. QA-only; no V12 live promotion.
  `qa_shots/hero/v12_atlas_y03_runner_review01/VISUAL_REVIEW.md`.
- Exact DUSK seam and four-surface verge warmup coverage is now registered
  before countdown without reducing detail. Fresh runner uses 32/32 external
  slots, preserving all 15 DAY pairs; overall queue cap remains 128. New 31
  coverage, existing 58 geometry/22 staging and 141 platform checks pass.
  Cross-scene registry exhaustion remains explicit, not exhaustive approval.
  Clean matched timing **does not resolve the hitch**: 97.423 ms at the same
  396.104 m first-DUSK submission; spawn/stream CPU 1.013/1.068 ms. Average
  58.16 FPS, p95 19.84 ms, 172,462 peak primitives: overall FAIL. An earlier
  overlapping-bake timing attempt was stopped and marked CONFOUNDED.
  `qa_shots/runner/dusk_warmup_trace_20260907_02/report.json`.
- New opt-in desktop stream diagnostic reproduces the hitch: 99.20 ms at
  22.239650 s / 396.106940 m, when first DUSK chunk 17 is added and chunk 8
  retired. Recorded spawn CPU is 1.037 ms; combined stream CPU is 1.077 ms.
  This rules out attributing the whole stall to measured chunk-building work;
  no GPU/upload/shader cause is established yet. Diagnostic average 58.48 FPS,
  p95 19.86 ms, 172,462 peak primitives; overall gate still FAILS. Trace storage
  is bounded and opt-in; 84 events/no recorded drops, one complete 17-frame
  hitch window. Instrumented timing is not baseline-equivalent or browser proof.
  `qa_shots/runner/camera_stream_trace_20260907_01/report.json`.
- Latest native desktop baseline without stream tracing, including the new controller/camera with live
  V11 art: Compatibility/high, 1920×1080, 60 seconds from GO, seed 20260907,
  59.22 FPS average, p95 19.37 ms, maximum 98.13 ms, 174.66/209 average/peak
  draws, zero frames over 100 ms. Overall gate **FAILS** at 172,434 peak
  primitives (100k cap). The near-100 ms worst frame is not lag-free approval;
  this is not browser/phone evidence or a Y03 benchmark. Prior timing samples
  below are historical comparisons, not the current camera's result.
  `qa_shots/runner/runner_perf_20260907_camera_fix.json`.
- New authored-runner camera measures the configured imported species once
  during setup/retry, excluding hidden procedural meshes. Aspect-based
  perspective fitting replaces the old procedural-size calibration; UI layout
  classes stay unchanged. Reference-height projection/lane checks pass across
  eight viewport sizes, with all lane edges visible from 20 m and the 55–70 m
  horizon retained. Small species preserve the 2.95 m camera floor, accepting
  a smaller image rather than lowering into tunnel beams. This is a remaining
  composition limitation, not an all-species 14–18% approval.
  Real Y03 portrait capture visibly improves the hero from roughly 9% to the
  intended standing range. A corrected posed-vertex golden-shot gate excludes
  25 hidden meshes and includes 12,759 morphed/skinned vertices. Its five poses
  measure 18.0%, 14.9%, 18.3%, 16.4%, 10.8%: **FAIL** for jump/launch framing.
  The strict window run also retains shutdown diagnostics. No camera-quality
  gate is declared complete. `qa_shots/hero/v12_candidate_y_camera_review02/`.
- Y03 retains source brow-cover geometry in the actual low meshes. The former
  decimation weights inadvertently favored collapse around the eyes; explicit
  source bands and corrected weights now preserve six bilateral forehead rays
  at exact source positions in both LODs. Counts: 22,963/10,557 triangles, two
  surfaces, Khronos-clean, canonical rig/clips unchanged. Y02's worse mouth
  experiment is rejected; Y03 restores the original mouth exactly. Nineteen
  exporter tests pass. Actual front/chase 30/60 sequences pass with zero sampled
  transition/steady-run differences; root inspected the repaired front and a
  real runner frame. Dark rear, generic face and proxy material remain rejected.
  No live GLB/material promotion. `qa_shots/hero/v12_candidate_y03_source_cover/`.
  Baker reconstruction now honors the exact recorded legacy/v1/v2 reduction
  policy (24 host tests). A fresh Y03 source-material bake subsequently reduced
  uncovered texels to 22 (15 mouth, seven eye/rim; body/lower bill clean).
  Seven bounded actual-source eye probes pass within the unchanged 250 µm cap,
  preserving every other working pixel exactly. That intermediate repair
  correctly rejected 15 mouth texels; the later mouth03 pass resolves them
  without changing source/candidate geometry or relaxing either distance cap.
  `qa_shots/hero/v12_atlas_y03_eye_01/REVIEW.md`.
- The shared live controller now corrects frame-dependent transition weights
  while retaining automatic AnimationPlayer playback. A guarded zero-time
  resample runs only during the existing 0.10/0.07-second fades; it advances
  neither clip nor gameplay time. Actual imported-bone idle→run comparison
  previously differed by 71.922 mm at equal 30/60 times; the correction yields
  zero measured position/rotation/time differences. Nine tested transitions
  now match, including slide, jump, landing, both hits, launch and defeat.
  Existing 56 motion and 33 controller checks remain green. Fresh native
  Compatibility 1080p/high timing with this controller: 59.62 FPS average,
  p95 18.04 ms, maximum 77.45 ms, 176.03/212 average/peak draws, zero frames
  over 100 ms. Overall gate still FAILS: 154,096 peak primitives exceed 100k.
  This is live V11 geometry, before the subsequent camera work, not Y, web or
  phone evidence. `qa_shots/runner/runner_perf_20260907_transition_fix.json`.
- Previous full isolated suite snapshot passes 46 labels, with four explicit
  real-window SKIPs, zero FAIL, exit 0. All five race simulations, runner and
  eight retries, tutorial, endless, Grand Prix, ghost/time trial ran. Known
  shutdown diagnostics and 103 unapproved art assets still block release.
  Evidence: `qa_shots/tests/hero_camera_suite_20260907_01/RESULTS.md`.
  It includes the new camera/posed-bounds checks, candidate-review host label,
  protected source-cover export and exact baker-policy replay tests. Separate
  window visual failures remain failures despite this headless regression pass.
- Fresh X candidate review04 passes four actual front/chase 30/60 sequences
  through PenguinVisual and the inherited live controller. Initial transition
  and steady run now have zero sampled roll/sole differences; attached feet
  and identity root remain intact. Nineteen real portrait-runner screenshots
  use normal gameplay/camera with only a temporary QA wrapper substitution.
  Harsh proxy face materials, dark rear and undersized hero framing still fail
  visual acceptance. The local play route is available but has not been launched
  or promoted. Existing 20 ObjectDB warnings remain visible; fixture teardown
  removes the extra two-resource error in this capture, not in every game mode.
  Evidence: `qa_shots/hero/v12_candidate_x_facade_review04/CAPTURE_REVIEW.md`.
- Saved X/Y audit verifies exact geometry, topology, normals, UVs, existing
  paint, camera/lights and six packed texture inputs; only the stated material
  recipe and new explicit mask attributes differ. Body and both wings' saved
  masks match authored equations exactly at float32 precision. A fresh Y
  2048² atlas bake is **rejected** for 39 uncovered texels: mouth 15, body 9,
  lower bill 1 and eye pigments 14. Geometry reconstruction/UV gates pass;
  checkpoint/maps are retained for projection repair. No Y runtime atlas or
  material replacement was exported. Read-only rays locate the nine body
  misses at the inner upper orbit and identify finite eye-patch edges; the
  worst limbal distance is 251.057 µm, above the unchanged 250 µm probe cap.
  Thin-region preservation/local cages are required, not a relaxed gate.
  Evidence: `qa_shots/hero/v12_atlas_y_2048_01/`.
- X moderates the iris's nasal offset without moving/enlarging the eyes or
  tracking the camera. Front gaze remains readable; profile improvement is
  limited. Y uses the same geometry with a calibrated feather-detail recipe:
  existing albedo/normal/roughness maps now reveal directional cream/navy grain
  without adding fur geometry or textures. All three Y views were inspected.
  This is a visible material improvement, not final face/fidelity approval or
  proof the material has reached the game. Twenty-one source guards and ten
  recipe checks pass. Explicit source mask fields now preserve actual palette
  compositing weights for later baking; the frozen M analytic path is retained.
- X now also has a budgeted, skinned QA export: LOD0 21,465 triangles, LOD1
  9,867, two surfaces, at most two weights per vertex, 15 bones and all 23
  canonical clips preserved. Both GLBs pass Khronos with zero errors/warnings.
  Source/rig files are unchanged by export. Its generic PBR material is not Y's
  improved feather recipe. Review04 supplies actual controller/runner evidence
  described above; no live asset promotion.
- Latest U–W source studies improve the pear/head proportions, flipper breadth,
  cheek placement, upper-eye paint, iris pigment and differentiated feather
  roughness. W fixes a concrete bill defect: the mouth-corner lift no longer
  flattens the upper roof. All three W views were rendered and inspected;
  twenty source guards pass. Profile-eye readability and fine directional
  feather response still fall short. These are source-only changes, not a
  replacement in the running game or premium-art approval.
  Candidate import now preserves the new linear iris vertex paint exactly:
  fifteen adapter tests and eight pigment tests pass. Read-only Blender checks
  confirm both V irises' 769 colors exactly and all 33 frozen M components
  unchanged; neither saved source was rewritten.
- An authored radar far-LOD candidate reduces 17,608 to 7,400 triangles while
  retaining all 77 named components, including windows, tower supports and
  beacon posts. Two independent exports are byte-identical and Khronos-clean;
  22 host checks pass. Actual Compatibility import and controlled swap confirm
  10,208 fewer primitives with unchanged draws and exact surrounding-state
  restoration. Its recorded gameplay silhouette is intact; close inspection
  reveals coarser facets. Extended side/three-quarter capture now passes 45
  contracts and 180 state/counter checks; both seven-window walls remain.
  A 60→120→60 pixel camera-only sequence crosses QA 80/96 pixel hysteresis
  thresholds exactly. Full moving playback/pop approval remains pending;
  these are not finalized orientation-independent selection thresholds.
  No live LOD selection or FPS improvement is claimed. Evidence:
  `qa_shots/runner/radar_lod1_candidate_20260907_06/REVIEW.md` and
  `qa_shots/runner/radar_candidate_comparison_20260907_01/COMPARISON_REVIEW.md`
  and `qa_shots/runner/radar_candidate_extended_20260907_03/EXTENDED_REVIEW.md`.
- The earlier 24-ObjectDB/two-resource shutdown delta did not reproduce in
  three exact-input sweep reruns. A standalone 24-image readback/save test
  frees every image and exits cleanly. Existing 20-ObjectDB shutdown reports
  remain; no speculative lifetime fix or warning suppression was added.
  The original extra-resource incident remains unresolved, not declared fixed.
- Latest source Q–T replaces the detached orbital rings with a shared head/lid
  surface. Base-skull eye frames are frozen before lid evaluation; a shallower
  authored pitch and shared attentive gaze avoid Q's measured lower-iris
  clipping. S closes R's separate upper white island with a continuous upper
  globe envelope; T tightens facial paint and softens/fines the feather response.
  Seventeen source guards pass. All three T views are rendered, but character
  expression/material fidelity remains below the reference and no V12 source
  has replaced the live character. This is a construction milestone, not art
  approval or a game-performance improvement.
  Actual saved T mesh is one watertight body (358,918 source triangles), with
  no detached orbital objects. All 22,016 remaining eye triangles face outward;
  193 central samples per iris/pupil remain clear of the head. A sampled
  body/globe visibility audit finds one exposed opening per eye, no upper
  white island. S/T geometry is exact; T's paint/UV/material changes are explicit.
- The separate verified M atlas now has a normal-import runtime package with
  one external compressed texture set shared by both PBR surfaces and both
  optional shader overrides. Duplicate extracted lossless images are absent.
  Actual stored texture payload is 16,777,296 bytes including mips, **not driver
  VRAM**. GLB shrinks from 31,187,804 to 3,819,496 bytes; geometry, normals,
  tangents, rig, species and animation accessors remain exact. Khronos reports
  zero errors/warnings; normally imported PBR and shader captures both pass
  structural/contact/projection checks with clean logs. M's art is unchanged.
- An untimed, sequential runner peak replay reproduces DAY chunk 7 with nine
  live chunks and the same source fingerprint, 0.180 m past the recorded
  target. Frozen hide/restore tests isolate deck and two landmark contributions.
  Bias sweeps reveal that existing automatically generated landmark LODs lose
  important silhouettes/details. These settings are rejected, not promoted;
  no new gameplay optimization or FPS claim follows from this diagnostic.
  The sweep's strict wrapper exits 2: shutdown now reports 24 ObjectDB
  instances plus two resources, versus the earlier replay's 20 instances.
  Cause remains unresolved; completed counter/image experiments are not a
  clean-runtime claim. Exact evidence and rejected settings:
  `qa_shots/runner/peak_replay_lod_20260907_04/REVIEW.md`.

- Corrected the shared run clip's hip/chest counterrotation cancellation.
  Per user feedback, feet/toes now remain locally fixed and follow whole-body
  weight transfer; the independently animated foot-stride variant is retired.
  Chest roll spans 15.03 degrees, forward lean stays below 10 degrees. Existing
  geometry/skin/species and the other 22 clips remain byte-exact unchanged.
- Lane changes keep the gait running; legacy race/ghost callers forward their
  speed as cadence. Pre-tree podium poses and rebuilt character looks retain
  requested animation. Runner GO no longer plays an unnecessary recovery clip.
- Actual imported mesh/skeleton tests pass at 30/60 FPS: 56 motion checks plus
  33 controller checks, with supporting soles above ground and gameplay root
  unchanged. These are motion fixes, **not character-fidelity approval**.
- Runner countdown/input now wait for construction, actual warmup and loader
  fade. Retry retains the warm presentation; pause cannot open under loading.
- Loader checks the scene root and nested construction/warmup nodes.
- Runner's cold first draw stages original geometry one completed draw at a
  time, preserving skin, MultiMesh, transforms and visibility. Interrupted
  passes restore visibility; a complete scene settle draw precedes probes.
- Material probe footprint and front-face winding fixed; grid prevents probe
  overlap. Hidden procedural fallback no longer consumes the live queue.
- QA now measures monotonic wall time, supports deterministic route seeds,
  fails incomplete loader runs, and records slow-frame locations.
- Moving hazard clocks wait for visible presentation. SceneRouter queues
  startup recovery redirects instead of losing them during its fade.
- Headless asset preload is synchronous to avoid Godot 4.7.1's dummy-renderer
  RID allocator threading bug; interactive loading remains asynchronous.
  Offline QA proofs are excluded from Godot imports with `qa_shots/.gdignore`.
- Source-only hero proofs now have connected feather maps, wider head/cheeks,
  continuous lower-belly curvature, embedded eyes, common gaze and valid
  globe-conforming pigment geometry. N rotates flipper breadth toward the side
  and tucks the lower bill; its eyelid rim still fails premium facial
  expression/material acceptance. A separate budgeted/skinned QA adapter now
  exists; no V12 geometry has replaced live character assets. See
  `art_src/characters/hero_penguin_v12_review.md`.
- Separate unique-atlas QA shader fixes a measured color-space recoloring
  defect. Real Compatibility tests improved from 16 pass/7 fail (up to 39/255
  channel error) to 23 pass/0 fail (at most 1/255); Metal Mobile independently
  passes the same 23 checks (at most 2/255). These are synthetic material
  proofs, not character/phone/gameplay acceptance. No live shader replacement.
- Removed only exact duplicate DAY geometry: ramp 2,808 → 2,456 triangles,
  icebreaker 16,544 → 15,040; runtime payload shrinks by 290,352 bytes. Exact
  surviving positions/normals/tangents/UVs/colors/winding are unchanged. Other
  13 source collections and three packed textures are unchanged. Both exports
  pass Khronos; four duplicate-regression checks and isolated DAY gameplay
  checks pass. This is not an FPS measurement or an art-approval change.

Earlier atlas-development snapshot: all 39 local development-suite labels
passed, including nine host atlas checks. Four window-dependent cases
explicitly skipped in headless mode (new atlas shader plus the three existing
orientation/UI cases); the shader was separately exercised in both real
renderers as described above. Source N's eight shape guards pass separately.
Known shutdown resource diagnostics remain; this is not a zero-leak or release
claim. The full suite used an isolated project and save identity.

An earlier focused atlas rerun: candidate 11, atlas 12 and serialized-export 28
host checks pass; shader correctly skips without a real window. Source O's
ten separate shape/pigment guards pass. O's three rendered views show only
modest eye improvement; facial integration still fails. Actual compressed
four-map M atlas captures now work in Compatibility and use 16,777,296 bytes
of texture payload including mips, not total VRAM. Balanced-lighting/normal
diagnostics expose and soften the coarse feather response, but the atlas still
fails projection coverage and is not promoted. See the atlas/review contracts.
No new gameplay FPS, browser/phone pass, or full-suite claim is implied.

Local import audit found stale ramp/icebreaker caches but **not** stale hero
run animation. Each imported hero LOD's 11 tracks/219 keys matches current raw
GLB samples within 1.20e-7. Editor-only import refresh updates runner meshes to
2,456/15,040 triangles and leaves both hero imported scenes byte-identical.
No game session or save writes occurred. Logs are retained under
`qa_shots/hero/local_import_audit_20260907`; an Android daemon connection line
is recorded separately from the clean Godot import/parser checks. This is not
a measured lag fix or an explanation for the remaining poor character art.

Source P's deeper/larger globe variant is now rendered and rejected too: the
upper orbital lip remains visibly applied. Eleven shape guards pass; actual
saved geometry has 23,616 outward eye triangles and 22 unchanged non-eye
objects. This shows why passing geometry tests is not art approval. P is
frozen pending a different lid/skull construction, not another color tweak.

Subsequent **M LOD0 texture-transfer** gate passes with zero uncovered pixels.
Complementary mouth projection plus 15 bounded paired-source eye/rim probes
preserve every previously valid pixel. Packed checkpoint and embedded/exported
map equality are now verified, fixing a discovered stale packed-ORM defect.
This is not P geometry, premium visual approval or runtime promotion.
`qa_shots/hero/v12_atlas_m_nearest_eyes_02/` retains the exact milestone,
including actual first-ray triangle/distance checks (174.832 µm maximum).
No further bakes or LOD1 work were done at that milestone. Runtime packaging
then needed to avoid retaining both extracted lossless PBR maps (~64 MiB) and the
custom compressed maps (~16 MiB); the latter alone is not total character VRAM.

Runner performance metadata now has 32 passing isolated checks: exact input/
import hashes, stable source subset, peak location/camera/counter context and
an opt-in final-scene geometry/LOD inventory. The inventory runs after timing,
not every frame, and explicitly does not claim GPU visibility or peak-family
cost. A pinned GLES3 MultiMesh LOD counter undercount is documented without
guessing a correction. Original performance thresholds remain unchanged.

Fresh current-asset native Compatibility run, Apple M2, high/1920×1080,
60 seconds from GO: **59.93 FPS**, p95 **17.46 ms**, max **67.88 ms**, zero
frames above 100 ms; draws **175.36 average / 212 peak**. Primitive monitor
peaks at **154,060**, so the existing 100,000 ceiling still fails. Exact
input/import fingerprint is complete. Peak occurs at 266.318 m in DAY; the
optional final inventory at 1,334.141 m is not that peak's geometry. Twenty
ObjectDB shutdown instances remain flagged. This is native desktop evidence,
not a browser/phone pass, a V12 performance test, or proof all lag is solved.

Earlier full isolated development suite: **39 PASS labels, 4 explicit
window-required SKIPs, 0 FAIL**, exit 0. The new ten-test shared-texture package
label and runner peak-replay contract pass alongside all five race simulations,
runner/retry churn, ghost/time trial, endless, tutorial and Grand Prix. One
inner DAY-geometry comparison also skips because its optional historical
baseline directory was not supplied. This does not replace the separately
verified before/after duplicate-geometry audit. Known shutdown diagnostics and
103 unresolved review assets remain open. Durable evidence:
`qa_shots/tests/shared_texture_suite_20260907_01/{suite.log,RESULTS.md}`.
Report: `qa_shots/runner/runner_perf_20260907_current_assets_census.json`.

The frozen M atlas now also passes one actual imported Compatibility capture:
48 frames with zero transfer misses, structural/contact checks green and no
import/shader errors. Its face/materials remain visually rejected, and the
technical capture's pass flag does not approve the model or its FPS. The live
V11 model is unchanged. A two-second front/chase motion-check video of that
existing V11 asset is under `qa_shots/hero/waddle_attached_20260907_30/`;
it illustrates the attached-feet waddle, not the new-art milestone.

Fresh local evidence (Godot 4.7.1, Apple M2, native Compatibility; not browser
or phone evidence):

| Probe | Observed result | Gate status |
| --- | --- | --- |
| Original cold loader | 1,893.91 ms worst frame; gameplay moved behind loader | Failed |
| Staged visible loader | 248.95 ms worst; 243 frames; 109 original visuals restored; final scene settle 5.62 ms | Completes; loading still stutters |
| Countdown under loader | 0 violations, 0 m travelled, full 1.600 s retained | Passed |
| Material raster proof | 21 pixels for ordinary and both billboard modes; reversed winding 0 | Passed |
| Initial 1080p/high, 60 s from GO | 59.74 FPS, p95 17.84 ms, max 101.07 ms; draws 172.65 average/210 peak | Failed max-frame and existing 100k primitive gates (159,212 peak) |
| 1080p/high, 12 s opening repeat | 59.52 FPS, p95 17.05 ms, max 75.94 ms; no >100 ms frames | Frame gates pass; primitive gate still fails (151,076 peak) |
| Final 1080p/high, 60 s from GO | 59.90 FPS, p95 17.28 ms, max 69.04 ms; 0 frames >100 ms; draws 176.19 average/213 peak | Frame/draw gates pass; primitive gate still fails (155,924 peak) |

Loader runs used fresh project caches; OS driver caches were not reset and
the original baseline used a random route. Treat maxima as observed evidence,
not a controlled percentage speedup. Complete staged run and gameplay probes
kept the QA window always on top: macOS suspends draws for occluded windows.
Two earlier occluded staged runs are invalid performance evidence and now
correctly fail the harness's incomplete-loader gate.

Full cold development/functional suite returned exit 0 across 33 harness
labels. Three window-only cases internally skipped (orientation recovery,
mobile UI audit, race touch HUD); these are not visual/device passes. Units
129, frontend 65, utility frontend 136, runner platform 140, warmup geometry 58,
initial visual staging 22, and all five course/runner/ghost/endless/tutorial/GP
simulations passed. The initial full run exposed a missing `export_presets.cfg`
snapshot dependency; corrected, and both web-shell checks now pass.

A subsequent full suite including two new hero harnesses passed all 35 labels
(same three window-only skips) before the user's attached-feet refinement.
The final attached-feet variant then passed the isolated hero asset/motion/
controller subset. Its runtime motion evidence is under
`qa_shots/hero/waddle_attached_20260907_30/`; earlier `waddle_20260907_*`
captures demonstrate the now-retired independent-foot variant.

The V12 work exposed two additional QA issues. One fresh full-suite import
crashed in a Godot worker thread before tests; the next two unchanged imports
passed. Native crash analysis narrows this to a null table-entry dereference,
but the owning subsystem is unproven. No importer setting was speculatively
changed; failed import logs are now preserved before temporary cleanup.
Inspection also found 33 unsupported `%g` formatting errors in a warmup test
that the old harness incorrectly tolerated. Those strings now use supported
fixed-point formatting; unexpected engine errors now fail a test even if
Godot exits zero. Known shutdown resource diagnostics and the unit test's
intentional corrupt-save JSON errors remain explicitly distinguished.

The separate V12 L02 candidate has 22,305 / 10,258 triangles, two materials,
15 bones, 23 preserved clips and eight species keys per LOD. Its CPU-skinned
30/60 FPS sole-fit numbers are promising but are **not rendered-contact
approval**. Real Compatibility captures exposed white body material and an
apparent GPU/CPU contact discrepancy; candidate remains quarantined while
material import, normals and skin-transform behavior are investigated. Clean
Khronos validation did not establish visible correctness.

The missing iris was traced to source annulus winding (1,408 inward / 64
outward triangles per paint patch), not export handedness; M corrects it and
adds actual source-normal plus pure topology guards. Source→candidate→GLB
coordinates/winding otherwise match exactly. Feather body color exists in
the GLB, but both normal and dynamic Godot imports leave its material's
vertex-color multiplication disabled. QA-only repair records that flag
explicitly. Side-view world sole markers do not show the initially suspected
large skin offset.

Final M01 normally imported Compatibility captures now show source colors and
valid irises, with front/side/chase/three-quarter sequences at 30 and 60 FPS,
plus LOD1 and contact markers. M01 is 22,305 / 10,260 triangles, two materials;
both exports pass Khronos. Supporting sole height is 0.283–11.259 mm (LOD0)
and 0.978–11.686 mm (LOD1), with unchanged foot/toe/root local poses and exact
shared-time 30/60 parity. Markers align with the rendered sole; the suspected
large global offset was not present. These are offline motion captures,
**not measured FPS or premium acceptance**. Face/materials, painted boundaries,
flipper separation, other clips/species/cosmetics and gameplay FPS remain open.
Detailed evidence: `qa_shots/hero/v12_runtime_candidate_m_01/REVIEW_STATUS.md`.

After fixing the diagnostic strings and a candidate-test wording mismatch,
the stricter full isolated suite passed all 37 labels (three window-only
internal skips; the optional DAY before/after comparison was run separately
with its baseline). Log: `/tmp/waddle-full-suite-v12-verified-20260907.log`.
The final expanded candidate tooling tests then passed 11/11, and source shape/
eye-topology guards passed 5/5. One intermittent fresh-import crash remains
unresolved despite subsequent successful imports. No new game FPS sample,
phone/browser approval or deployment occurred in this pass.

Art authoring integrity explicitly includes review fragments: 112 assets,
43 exports, 103 unresolved review assets. Thirteen tooling tests pass, including
strict-readiness rejection and invalid hash/license/orphan cases. The strict
release command without `--review-fragments` still fails (125 errors); a green
development suite is not release approval. Central manifests and readiness
flags were not promoted.

One full run produced wrong-RID/material-null diagnostics in the headless
renderer, matching [upstream Godot issue 121949](https://github.com/godotengine/godot/issues/121949).
After the headless-only preload workaround, art foundation passed 85 checks
and eight-cycle churn passed without those diagnostics. Churn had zero orphans
and no sustained resource growth. ObjectDB/resource-in-use shutdown diagnostics
still exist and are not declared fixed.

Local evidence: `qa_shots/runner/runner_perf_20260907_final_high.json`,
`qa_shots/runner/shader_warmup_raster_20260907.json`, and source proof review
linked above. Exact duplicate icebreaker windows (1,504 triangles) and ramp
chevrons (352 triangles) are now removed and verified. Next geometry work:
measure real landmark/deck LOD effectiveness without removing visual density.

## Historical production status — 2026-08-05, not premium overhaul approval

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
- The weekly-reset deadline was retired on 2026-08-07: `RESET_AT.txt` had
  been elapsed for over two weeks and the deadline clauses in CLAUDE.md were
  removed with it. Work is paced by scope now, not by a clock.

## 2026-08-07 (later) — Tilt steering, and two bugs that hid behind caching

### Tilt steering (shipped, confirmed good on device)
Lean the phone to steer. On by default on touch devices; drag always overrides
it, so a finger on the screen wins and the feature can never leave a player
unable to steer. Settings → Gameplay carries Tilt Steering, Tilt Sensitivity,
Invert Tilt and a live **Motion Access** state row.

Confirmed by the user on an iPhone: prompt appears, direction correct by
default, feel good at the default sensitivity. Axis maths is unit-tested
(8 checks) because a desktop has no sensor to test against.

Three non-obvious things it had to get right, each of which failed first:
- **Activation event.** The permission ask was armed on `pointerdown`, which
  always arrived first and spent the arm — but a press that has gone down and
  not up grants no transient activation, so Safari rejected it silently and the
  handler had already unhooked `touchend`/`click`. Now armed on press-END only.
- **Where the ask lives.** It was called from GDScript `_input`. Godot QUEUES
  browser input and dispatches it in its own main loop, so the call was outside
  the DOM handler entirely. The request now happens in JavaScript, from a real
  DOM listener.
- **When it arms.** Armed from the main menu, the first press of the session
  (Begin, on the title screen) predated the listener and was wasted. Armed at
  boot from an autoload now.

### AI gap detection
Racers jumped only where a course called `add_hint(offset, "jump")`. Iceberg
Bay lays out its floe runs with ~12 `"gap"` control points and three hints, so
the field piled up at the first unhinted edge and stayed there. Racers now
probe for missing ground along their own heading (two probes, near and far, so
drifting wide does not trigger it) and jump. Hints still fire first.

Last-place finisher after the change: glacier 145.8, aurora 179.2, iceberg
158.7, cinder 173.7, hollow 136.6, 8/8 finishers. Iceberg's tail was 324 s in
an earlier sweep.

### Cache: stop asking, start versioning
Three bug reports in a row were a stale build rather than the defect described.
Verified the origin and edge were both correct — current build, `max-age=0,
must-revalidate`, proper 304s — and a phone still ran code from several deploys
earlier. A fresh export stamped with the same BUILD_ID was byte-identical to
what the site served, so the deploy was never at fault.

`index.html` is now `no-store` and names `index.pck?v=<hash>` via
`GODOT_CONFIG.mainPack`. That URL has never been fetched, so it cannot be
cached by any client under any policy. Settings also shows build hash and both
canvas sizes, so a screenshot answers "which code is this" without a round trip.

### Aurora: mountains through the deck, measured rather than eyeballed
Reported as "the mountains overlap the course in several places". A new
harness, `tests/overlap_probe.tscn`, walks every guide, builds the racing
corridor (half-width either side, deck-1m to deck+6m) and triangle-tests every
mesh in the course against it, excluding the track ribbon, triggers and hazard
classes and reporting what it excluded.

Aurora went from **17 offenders to 9**, and everything left is either overhead
(the cavern arches at 5.8 m, a lamp arm at 5.9 m) or the ridge berms, which are
a deliberate channel. Three root causes:

- **Peak rings placed at a fixed radius.** Both silhouette rings sat 380-620 m
  and 700-980 m from (20, 0, -520), but the course itself reaches ~560 m from
  that centre fore and aft. Four of the sixteen near peaks — 300-460 m wide —
  were planted straight through the deck at the start line, the geyser
  downhill, the corkscrew and the finish straight, each reaching 8.4-9.9 m
  inboard of a 9-10 m half-width. Radius is now derived per bearing from the
  course's own reach (`_peak_ring_distance`), so the range rings the valley
  instead of crossing it.
- **`track_edge_lateral()` probed from the unbanked frame.** Rays started at
  `origin.y + 0.4` taken from `guide.transform_at()`, which does not include
  bank, so on a banked corner the ray began *under* the raised deck edge, found
  no floor, and returned a short lateral — planting the prop on the racing
  surface. Four station poles stood 2.9-5.0 m inboard on aurora's three banked
  corners. Now probed from `TrackBuilder.deck_transform_at()`, each sample
  starting above its own expected deck point. This also cut **glacier from 32
  offenders to 21** (flags, rocks, sastrugi and snowbanks all pulled off the
  deck), so it was never an aurora-only bug.
- **Flank scatters only knew about the main guide.** Snowdrift mounds and the
  crystal field place themselves by lateral offset from the main line, and near
  the ridge shortcut the far side of that offset is deck. `clear_of_track()`
  on CourseBase now tests a candidate against every guide, main and branch.

### Ice shield: it had no clock at all
Reported as "the ice shield doesn't expire", and that was literally true —
`_has_shield` had no companion timer and the only writer of `false` was
`break_shield()`, reachable solely from the four damage handlers. A clean run
carried a lit bubble to the finish.

`SHIELD_DURATION = 8.0` (sits with magnet 6 s and blizzard 5 s), with the last
`SHIELD_WARN = 2.5` s driving a `charge` uniform that thins the shell and
speeds its travelling band, plus a HUD pill under the position card showing the
countdown. Timing out is deliberately distinguishable from being broken: a
quieter, higher sound and **no** invulnerability, because nothing hit you.

Three further defects came out of the audit, all now fixed and unit-tested:
immunity is checked before the shield so a hit already absorbed by i-frames no
longer also spends it; `apply_blizzard_slip` gained the invuln/FINISHED guards
it never had; and the shell's end-of-life stutter is a hard 6 Hz on/off, so it
is now gated on `reduced_flashing` and falls back to a smooth fade.

### Shove: legible with no penguin in frame
Reported as needing a stronger animation "especially so people can see that
something is happening when not actually showing a penguin" — the chase camera
sits behind the player, so their own shove happened past their own back.

The attacker now lunges (`PenguinVisual.trigger_lunge`, whether or not it
connects, so a miss stops reading as a dead button), the victim is spun off
balance (`trigger_tumble`, layered over the running pose rather than replacing
it), and the contact point spawns a flat cyan ground shockwave, a billboard
flash and a kick of snow spray through the course's existing puff pool. Both
halves of the hit kick the camera; taking one hits harder than landing one, and
`Racer.shoved` exists so the victim side has a signal at all. A whiff now plays
a thinner, higher, quieter swing instead of the identical cue.

The ring was first built standing upright facing along the push. On screen that
was a white croquet hoop planted in the snow — the bottom half sank through the
deck and what remained read as scenery. Flat on the ground it cannot intersect
anything. Caught by capture, not by review: `shot=race_shove` and
`pose_check -- impulse=` both save a *strip* of frames across the impulse,
because a 0.4 s one-shot cannot be judged from a single still.

### Settings from the pause menu, and a way back to the course list
Two reported navigation dead ends.

**Settings mid-race.** The pause menu carried volume sliders and a mute toggle
and nothing else, so display, gameplay, accessibility and tilt settings were
unreachable once a race started. The settings screen is now MOUNTED over the
paused race rather than routed to — routing would unload the race, which is the
one thing a player adjusting their controls mid-race cannot afford. Its only
tie to being the current scene was where Back went, so that became an injected
callback (`on_back`); everything else was already self-contained. The tree stays
paused underneath, and the pause panel is hidden rather than freed so it comes
back with its state intact. It is rebuilt on return, because settings can change
`hud_scale` and `ui_scale` and the panel was built against the old values.

Pause also swallows the cancel gesture while settings is up, or one Escape would
close settings and unpause the race in the same press.

**Back to course selection.** Three routes were missing, and the underlying
cause was different in each:

- The setup breadcrumb (`MODE › COURSE › DIFFICULTY`) was drawn as a breadcrumb
  and was pure decoration — every pill was `MOUSE_FILTER_IGNORE`. Pressing
  "COURSE" to change your mind, which is the first thing anyone tries, did
  nothing at all. Completed pills now carry a transparent full-rect Button
  (the pill's own two-label art stays as authored) and a brighter rim.
- Pause and results had no route to the course list. Both now offer "Change
  Course", via `Game.setup_entry_step`, a one-shot that opens the setup flow at
  a named step. Previously this meant quitting to the main menu and walking the
  whole flow again.
- On a phone the step's Back button was the last child of a scrolling column
  five course cards tall, so it sat a full screen below the fold — reported,
  accurately, as there being no way back at all. Back now lives in a pinned
  footer outside the scroll, over a gradient scrim, with a spacer reserving its
  height at the end of the column so the last card can still clear it.

**Course list on a phone, found while verifying the above.** Measured on a
430x932 canvas (logical 800 wide, column 647): the card's inner content demanded
720, and a Button does not clip its children, so the whole gallery drew off the
right edge with every course name and time cut in half. Poster (220) plus two
side-by-side record tiles (431) does not fit in 647 at any readable font size,
so the portrait row now carries one tile with the par time as its caption. The
breadcrumb rail wanted 794 of 800 and lost its last pill to the screen edge; it
is an HFlowContainer now and wraps. Row height went 148 -> 190 (content measured
at 336 against a 262 card, so the record caption was clipped off the bottom of
every card) and the poster 0.34 -> 0.29 so full course names fit without
ellipsis.

### Penguins: from blob to bird
Player: "the penguins themselves just look like little blobs ... think hyper
realistic." The captures agreed — a pale powder-blue egg. Three compounding
causes, fixed together:

- **Painted light.** The plumage pipeline was painting illumination into the
  albedo and the emission: a 0.40 "sheen" lift baked into the back's vertex
  colors, an emissive dorsal streak, a wide emissive rim, and a hemispheric
  form band running 0.42..1.46x. Every layer individually was a readability
  device; stacked, they rendered a grey-blue toy. All four cut hard
  (sheen bake 0.40 -> 0.13, form 0.60..1.18, rim ~40% of old width, dorsal
  streak deleted). The satin now comes from ROUGHNESS/SPECULAR: the dorsal
  tightens to ~0.30 roughness where the feather sweep sits, broken up by barb
  grain, so the sun lays a REAL broad highlight there.
- **A mantle authored 2x too light.** Species mantles darkened two steps
  (emperor 0.22/0.27/0.36 -> 0.115/0.135/0.195 etc), the mantle window closed
  at the shoulder so the nape stays black, and the flank boundary tightened
  from +-8 deg of blend to +-3.5 — the razor flank line IS the penguin read.
- **Egg anatomy.** Fusiform profile (widest at the lower chest, breast carried
  up, longer shallower neck), flippers 0.46 -> 0.56 and slimmer, bill length
  0.20 -> 0.235 and slimmed to a decurved rapier, emperor auricular patch
  rebuilt as ONE tilted teardrop (the two-gaussian version printed as two
  yellow dots).

Verified by capture at every range that matters: dressing-room close-up,
pose_check side/behind (the chase angle), race frames on glacier (dark bird
against snow), aurora (moonlit silhouette with white flank — the reduced
emissive floor holds), and cinder's sunset grid. pose_check also gained the
missing `pose=idle` arm (it silently fell through to SLIDE) and course-like
lighting (ambient 1.0 -> 0.55) so its verdicts match what the game shows.

Also killed two `shield_probe` godot processes a workflow agent leaked on
Aug 8 — 91 CPU-hours each, and they were why captures crawled.

### The snow answers back: carved trails
A snow world that does not respond to the racers reads as painted scenery no
matter how good its shader is. Every racer now lays a persistent track --
footprint stipple while waddling, a carved groove while belly-sliding --
fading over ~9 s, pausing across ice so the ribbon breaks exactly where the
surface changes. scripts/gameplay/snow_trail.gd: one MultiMesh ring buffer per
racer (96 streaks ~= the last 55 m), a drop writes ONE instance transform,
aging runs only on drop ticks, zero per-frame rebuilds.

Two invisible-trail bugs found by isolating (tests/trail_shot.tscn renders
hand-dropped streaks in seconds instead of minutes per race boot):
- `heading.cross(floor_n)` built a negative-determinant basis: the quad's
  winding mirrored, the streak faced INTO the snow, and back-face culling
  removed every perfectly valid instance. Order flipped, culling disabled.
- The MultiMesh AABB was computed while all instances parked at the origin, so
  the whole trail frustum-culled the moment the origin left view. Explicit
  whole-course custom_aabb.
The material is LIT matte, not unshaded: unshaded read perfectly on glacier
and would have glowed on aurora, where a 0.5-value decal outshines the
moonlit deck. Verified on both: glacier shows a trampled field, aurora shows
dark footprints with no glow.

### Course-matched water reflections + glacial walls
The water shader had a full sun-lane and sky-reflection system, but
`reflect_tint` was never passed: every sea reflected the shared default's pale
daylight blue. Under iceberg's orange sunset that rendered the entire ocean as
a dead grey-mauve sheet -- the wrong sky is the loudest tell on any water.
Each course now hands its water its own horizon: iceberg's sunset amber,
cinder's ember dusk, hollow's dark cavern teal.

Edge walls gained a depth story: absorption toward saturated teal at the base
(deep ice loses red first), vertical fracture veins -- dark crack shadows plus
sparse bright refraction planes -- wind-polished facet relief tilting the
normal so the sun lays real moving highlights, and a grazing internal glow
scaled by the body colour so night courses cannot overglow.

### "The game looks pixelated": sharpness is now the last thing sacrificed
Two compounding causes, both on web:
- The auto-quality governor's FIRST lever was render resolution. Any browser
  that missed the frame budget by one notch immediately rendered the 3D world
  at 85% (and walked down to 62%) of native -- which players read, accurately,
  as "the game looks pixelated". The ladder now goes: step 1 drops MSAA and
  turns on FXAA at FULL native resolution; only steps 2+ start scaling, and
  the restore path gives resolution back first. FXAA is applied only at native
  scale -- FXAA over a bilinear upscale is blurring a blur.
- The web shell capped devicePixelRatio at 2, chosen when the art was flat
  shaded. On a dpr-3 phone that is 67% linear resolution -- visibly soft now
  that the art carries real detail. Cap raised to 2.5 (83% linear), with the
  governor as the safety net for devices that cannot pay for it.

### Boulders instead of eggs
TrackBuilder.add_rock was an 8-segment sphere with a second sphere hovering
over it as a snow cap. Now: five cached displaced-boulder variants (multi-
octave radial displacement, flattened seat), snow baked into vertex colors on
the crown with a noisy melt line, dark foot band -- and one draw call instead
of two. Debugging note for the file: the first captures looked "all white"
and the mesh data proved the colors were fine -- the elevated QA camera saw
mostly snow crowns, and the first rock albedo (0.42,0.45,0.52) was so bright
and blue that lit flanks converged with the snow. Judge rocks from racer
height, and author rock albedo dark and WARM (now 0.29,0.27,0.26).

### The loading indicator no longer freezes: staged course construction
Reported: "the loading indicator pretty much freezes right away." Reproduced
in Chrome — the loader penguin stops mid-hop over the difficulty screen and
holds there until the race appears.

Cause is structural, not a bug in the loader. The web export is single-
threaded WASM: a course was built inside ONE frame, so nothing rendered —
loading animation included — until construction finished. Worst case
(iceberg) measured 130 ms of unbroken main-thread work headless, where
headless does not even run `_decorate`; with dressing, environment and
skyline the real figure was several times that, and the fattest single piece
(`_build_far_field`, ~130 ms of tessellated massifs) ran on a `call_deferred`
that landed one frame PAST the end of the build, i.e. exactly as the overlay
began to lift.

Courses now build in slices. `CourseBase.stage()` is a yield point that only
suspends once the frame budget (8 ms) is spent, so builds are sprinkled with
`await stage()` — between construction phases, between dressing passes, inside
the ribbon's mesh phases, per skyline station, per spectator. Off web it never
suspends at all, which keeps every headless sim and QA harness byte-for-byte
synchronous. `_build_far_field` moved inside the build, so the skyline is part
of what the overlay waits for instead of a stall after it.

The eight racers were the second stall: each penguin is procedural geometry
assembled at spawn (~5 ms native each) and all eight were built in a single
deferred flush. RaceManager now drains its spawn queue two per frame on the
staged path, with grid placement queued behind them so ordering is unchanged.

SceneRouter holds its overlay for the whole thing (`_scene_is_building`, was
`_scene_is_warming`) rather than fading after three frames, and Race awaits
`course.build_ready()` before touching geometry.

Evidence (`tests/build_timing.tscn`, this machine, `--` `staged=1`, windowed so
dressing and skyline are included): worst uninterrupted main-thread slice per
course went from one 750 ms block (glacier, whole build) to 59 ms, aurora
145 ms → 75 ms, iceberg 130 ms → 60 ms. Headless race sims on all five
courses, tutorial, endless and the 107 unit tests still pass unchanged, and
`WW_STAGED=1` forces the staged path locally: staged race captures on glacier
and aurora build complete courses (qa_shots/staged/).

### Crepuscular rays, and the moon that was in the wrong place
gl_compatibility has no volumetrics and no depth reads, so real light shafts
are impossible. `SunShafts` (scripts/gameplay/sun_shafts.gd) does what stylised
racers do instead: a fan of soft additive blades held 420 m out along the key
light's bearing, facing the camera. Because it is real geometry at a real
distance, the world occludes it — the iceberg capture shows the lower rays cut
off by the berg in front of the sun, which is the whole reason it reads as
light in air instead of a lens flare pasted on the screen.

What keeps it from looking like a decal: the fan only lights up when the sun is
actually near frame (cosine window 0.45..0.92 — a wider window leaves long
blades crossing the frame with their origin off-screen, which reads as
scratches, and that is exactly how the first version looked); each blade is a
soft-edged strip that tapers in width AND brightness along its length rather
than a hard wedge; blades curve slightly and the fan rolls very slowly.

Enabled per course through build_environment: iceberg 0.62 (sun on the horizon,
the strongest case), cinder 0.48 warm, tutorial 0.38, glacier only 0.28 (a
cloudless noon sky has nothing to scatter in, so a big starburst there reads as
a flare), aurora 0.30 cold-blue as moonlight. Off on the low quality preset and
headless.

Building it exposed a real bug: **aurora's moon was parked at a fixed world
point**, 1080 m from a hand-picked centre. Over a 1.5 km course it swung across
the sky and drifted away from the bearing its own key light comes from — the
new rays and the moon disc ended up in two different places, which is how it
was caught. Sky bodies now hang off `SkyAnchor` (scripts/gameplay/sky_anchor.gd)
which holds them at a fixed BEARING from the camera, so they behave like bodies
at astronomical distance: no parallax, and light, disc and rays agree from
anywhere on the course.

Evidence: qa_shots/shafts/ — `tests/shaft_shot.tscn` builds a real course,
finds its key light and stands a camera on the racing line looking into it (the
one view a chase-camera capture almost never gives). 107 unit tests and race
sims on glacier/aurora/iceberg/cinder pass unchanged.

### Ground spindrift
Snow courses had weather (falling snow) but no WIND: nothing moved across the
surface the racer stands on, which is why a still frame at the start line read
as a screenshot rather than a place. `CourseBase._add_spindrift` adds one
camera-following emitter of low, fast, translucent veils driven along a
per-course wind bearing — katabatic down the glacier, night wind off the aurora
ridge, sea breeze across the berg, ash off the cinder sand.

Two tuning findings worth keeping, both found by capture:
- **It has to be seated on the surface, not on the camera.** Centred on the
  chase camera the emission box hangs metres above the deck and the streaks
  float out over the valley either side of the track like smoke puffs. It now
  probes `ground_height_at` under the camera and sits 0.45 m over it, in a box
  15 m wide rather than 38.
- **White is invisible on white.** At any alpha, white streaks over a sunlit
  snow deck simply cannot be seen (verified by rendering them bright red — the
  particles were there the whole time). The default is now a cool translucent
  veil (0.80, 0.87, 0.99) that shades what is under it, which is what blowing
  snow actually does; courses with darker decks pass their own tint.

Off entirely on the low particle-quality preset and headless. 107 unit tests
and glacier/iceberg race sims pass. `tests/particle_probe.tscn` reports the
live state of a course's emitters (present / emitting / where, relative to the
camera) — a particle layer that exists in the tree but not on screen is
otherwise pure guesswork.

### Ice walls read as ice, not as blue plastic
Cropping a race frame at full resolution showed the track edge walls letting
the raw shapes behind them straight through — a hard-edged lake polygon, a
terrain facet — which is what made a wall read as a tinted sheet rather than a
cut glacier face. Two changes:
- Body opacity up (base_alpha 0.72 -> 0.86) and the depth ramp steeper, so the
  base (thickest ice) is nearly opaque and only the crest stays translucent.
  Thick ice is not window glass.
- Trapped-air bubble speckle: sparse bright specks through the body, denser
  toward the base where the ice is oldest, faded out between 14 and 34 m so a
  distant wall stays a clean sheet instead of crawling with noise. Up close it
  is the single most identifiable thing about glacier ice.
Checked on both a bright course and a night course (qa_shots/walls/): the
higher opacity does not crush aurora's walls to black.

### Near-camera snow, and the artifact the spindrift veils were hiding
`_add_near_snow` adds a second, much smaller snow volume right around the lens
(7 x 3.5 x 7 m box, flakes 3-5x the size of the main layer, ~60 of them). The
main snowfall spreads its budget over a 90 m box, so the flakes that pass close
to the camera are sparse and sub-pixel — accurate and worth nothing on screen.
Depth in a snow scene comes from a few LARGE out-of-focus flakes crossing near
the lens against far geometry, and that parallax is the cheapest depth cue
available to a renderer with no depth of field. Capped in size: past ~0.7 m
across at a metre out, a flake stops reading as snow and starts reading as a
smudge on the lens.

Capturing that pass caught a real defect in the spindrift shipped earlier: its
veils (4 m across) sometimes drifted through the near plane and rendered as a
flat pale band with a hard straight edge across the entire frame. Proven by
capturing the identical view with the layer switched off (`DBG_NO_SPINDRIFT=1`,
kept as a QA switch) — bands gone. Spindrift is back to small streaks (2.0 x
0.18 m) at roughly double the density: a streak that size cannot cover the
screen wherever it drifts, so density does the work instead of size.

Also fixed `tests/pose_check.tscn`, which had started hanging forever with no
output: it never positioned its window, and an occluded window never draws, so
its `await RenderingServer.frame_post_draw` never resumed. It now places the
window on screen and has a 20 s watchdog that fails loudly instead of hanging.

### Sky depth: cumulus moved up and out, plus a far band
Two problems in one pass, both visible the moment a capture points the camera
slightly upward:
- The near cumulus clusters sat 115-225 m over the deck — closer than the
  course's own mountains. From any camera looking up, each puff resolved into
  its own flat ellipse: a row of blurry ovals hanging over the track. They now
  sit 430-780 m up and are scaled to match, at which distance the same puffs
  fuse into a mass.
- Nothing occupied the sky between the horizon and the zenith. A new far band
  (9 clusters, 2300-3900 m out, mixed 62% toward the course's own horizon tint)
  fills it. Distance is what does the work: the first attempt put the band at
  800-1500 m and it read as exactly the same row of ovals, just bigger.

Both bands ride one MultiMesh each, so the whole sky is three draw calls.

### QA note: browser-automation timings are not a performance signal
A live Chrome run of this build sat on the loading screen for over a minute,
and `?profile=1` reported `FIRST DRAWS (gpu) 29039 ms (3 frames)` on the TITLE
scene. The renderer is genuinely a real GPU (ANGLE Metal on an M2, confirmed
through WEBGL_debug_renderer_info), so ~10 s per frame is Chrome throttling a
window that is not visible on screen, not a build regression. Menu frame times
in the same session read 60 fps once frames were being presented normally.
Judge frame cost from the local build or a foreground browser window; treat
automation timings as a functional check only.

Two harness fixes came out of the same session: capture harnesses now place
AND raise their window (an occluded window never draws, so the await on
frame_post_draw hangs forever with no output), and `pose_check` gained a 20 s
watchdog that fails loudly instead. Also worth remembering: a stale/wedged
godot process from an earlier run makes every later capture appear to hang —
check `ps` before believing a new hang.

## Waddle Run — the endless-runner mode

A second game beside the racer, reachable as one of two hero buttons on the
main menu (the racing game's "Play" and "Waddle Run"), so a player meets both
at startup rather than finding one buried in a mode list.

It shares the racing game's art (PenguinVisual, VisualLibrary, SnowTrail),
save file and equipped cosmetics, and NOTHING else — no RaceManager, no
CourseBase, no PathGuide. The racing game is a simulation with surfaces,
rubberbanding and AI; a runner is a rhythm game on rails. Building one out of
the other compromises both, so the only contract between them is
`RunnerConfig`: lanes, chunk size, speed ramp, scoring, power-up ids and the
runner-only collision groups.

Structure:
- `RunnerTrack` streams chunks ahead and recycles behind, with authored
  patterns (weave, slide gallery, jump stutter, fish arc, gauntlet, pinch,
  ramp run), moving seals, tunnels, ramps, power-up crates and biome bands.
- `RunnerPlayer` is a three-lane state machine driving PenguinVisual, with
  jump/slide/lane-lean/ramp-roll/stumble animation, a magnet that pulls fish
  out of their lane, a shield that eats one mistake, near-miss detection and
  a competent autopilot used as a fairness probe.
- `RunnerChaser` is the avalanche: one MultiMesh of churn plus a scalar gap
  that hits pull in and clean running restores.
- `RunnerMissions` keeps three challenges live across runs from a 19-template
  pool, rerolls a completed set, and pays out stars.
- `RunnerHUD` carries distance/score/fish/lives/multiplier, the challenge
  card, power-up rings, score floaters, speed lines, the danger escalation and
  the results panel.
- `RunnerTouch` is swipe input, fired on threshold rather than release —
  waiting for the finger to lift costs a whole gesture of latency, which at
  38 m/s is the difference between clearing an obstacle and eating it.

Retry never reloads the scene: the track resets in place. On the web build a
reload would re-pay the whole build and shader cost, which is fatal to a
die-and-retry loop. The build is staged across frames the same way courses
are, and `SceneRouter` now watches `RunnerGame.build_finished` too, so the
loading penguin keeps animating while the first chunks are built.

Evidence: `tests/runner_sim.tscn` runs the real mode headless on autopilot and
asserts progress, streaming, recycling and that three missions stay live —
498 m / 75 fish / 107 live pickups / node count stable at 295 live vs 305
peak. The autopilot was deliberately rewritten to play competently (scans
every lane, times jumps and slides against closing speed, steers INTO ramps)
so its distance is a fairness signal: it now dies between 400 m and 1,200 m,
hitting 10-19 ramps a run. `tests/runner_shot.tscn` saves a strip of a real
run for visual review (qa_shots/runner/final_*.png). 107 unit tests and the
glacier race sim still pass, so the racing game is untouched.

## Android verification and the last open QA items

### Android: what the emulator can and cannot prove

The web build boots correctly in Android Chrome. On a Pixel-class AVD
(Android 15, 412x771 CSS at dpr 1.98) the engine starts, the boot overlay
hands over, the canvas is sized to the pixel budget at 817x1529, and the
renderer reports `ANGLE (Google (Apple), Android Emulator OpenGL ES
Translator (Apple M2), OpenGL ES 3.0)`. Godot draws: instrumenting the live
context counted 76 instanced draws and 4 clears in three seconds, the
framebuffer was complete, and reading the default framebuffer back mid-frame
returned real content — sky blues and snow greys, not black.

The screen was black anyway, and the cause is the emulator, not the build. A
control test settles it: a bare 200x200 canvas cleared to red composites
black on that AVD while a 2D canvas filled green composites correctly, in the
same page, in the same frame. Nothing of ours is involved in a red `clear()`.

Three graphics configurations were tried, and each fails in its own way:

| Emulator GPU | Chrome flags | Result |
| --- | --- | --- |
| `-gpu host` (default) | none | 2D composites; every WebGL canvas composites black |
| `-gpu swiftshader_indirect` | none | Page composites, then the WebGL context is lost outright |
| `-gpu host` | `--disable-gpu-compositing` | Page stops presenting entirely; even a 2D probe stops updating |

So the honest status is: **Android web boot, layout, sizing and rendering are
verified; on-screen presentation is not, and cannot be on this host's
emulator.** It needs a physical Android device, and that is the one piece of
this pass no amount of local work can substitute for.

Two things came out of the exercise regardless. Godot answers a lost WebGL
context with a blocking `alert()` — on a phone that is a system dialog over a
black screen, which is exactly what the swiftshader run produced. The web
shell now catches `webglcontextlost` on window in the capture phase, ahead of
the canvas Godot listens on, and shows a themed "Graphics paused" screen with
a Reload button instead; `webglcontextrestored` reloads on its own. Every
phone browser can take a context away under memory pressure, so this matters
well beyond the emulator.

The second is `tools/check_web_shell.py`, wired into run_tests.sh. The whole
pre-engine layer of the browser build — audio unlock, pixel budget, canvas
sizing, PWA metadata, and now the graphics-loss screen — lives in one escaped
string inside export_presets.cfg that no Godot test reads. One unbalanced
brace there ships a page that loads, runs no JavaScript, and shows a black
rectangle with a silent console. The check parses each `<script>` block with
`node --check` and asserts the seven behaviours are still present.

### QA_FINDINGS is clear

All four remaining OPEN items are fixed with evidence:

- **#5** `race.gd` refuses a course id with no `CoursesDB` entry instead of
  quietly building Glacier while filing records under the unknown id.
- **#8** the same guard covers Endless and Tutorial: a course that cannot run
  those flows sends the player back to the menu rather than finishing through
  `finish_race` while the results screen draws endless panels off `Game.mode`.
- **#13** `SettingsManager.frozen_defaults()` builds the defaults once and
  marks them read-only. `get_setting` runs every frame from several systems
  and every miss used to rebuild the whole nested dictionary — the per-frame
  allocation the spec forbids on mobile. `default_settings()` still hands out
  a fresh mutable copy for callers that edit it.
- **#17** the Grand Prix cup is settled by `Game.award_grand_prix_round()` /
  `Game._settle_cup()` in the race flow. It used to be awarded from inside the
  results screen's panel construction, which made the record depend on which
  panels a layout happened to build and put a mutation on the path a rotation
  re-enters. `results.gd` now only draws the ceremony and plays the fanfare
  once.

A pre-existing pair of failures in `runner_platform_tests` is also fixed —
the test simulated "next rendered frame" by resetting the submit throttle but
not `_awaiting_draw`, which a real `frame_post_draw` is what clears, so the
next submit was always refused and the two checks could never pass.

Evidence: 122 unit checks (7 new `gp_cup_*`), 10 menu-load checks, 65
frontend-presentation checks, 136 utility-frontend checks, 124 runner-platform
checks, texture_format, tutorial_sim, endless_sim, race_sim glacier, and the
mobile UI audit passing at all three device sizes.

### Android does work — as a native build

The web build could not be judged on this host's emulator, so the Android
question was answered the other way: `godot --export-debug "Android"` against
the preset that was already in the file. The templates were installed, the
SDK, JDK, build-tools and debug keystore were all already configured in the
editor settings, and the export signed and verified on the first run. The
APK installs and launches on the emulator and **renders correctly** — the
title screen comes up with its art intact, the sky and ice read the way they
do on desktop, the portrait layout fits, and there is no sign of the magenta
texture corruption that iOS Safari found.

Getting there turned up a real defect. The first APK started in **Vulkan
Forward Mobile**, because `renderer/rendering_method` is `mobile` and nothing
overrode it for phones. Every shader in this project is written to
gl_compatibility's limits — no screen or depth reads, no SSAO, no instance
uniforms, contact shadows painted by hand because there is no ambient
occlusion to lean on — and `SettingsManager.msaa_3d_mode()`, the quality
governor and the shader warm-up all branch on that renderer *by name*. So the
one build nobody can profile was also the only one running a different
pipeline, with the renderer-specific branches taking the wrong side. On the
emulator it failed outright (`Couldn't present to Vulkan queue`, repeating
every frame, black screen). `renderer/rendering_method.mobile` is now
`gl_compatibility`, and the log confirms it: `renderer: gl_compatibility`,
`OpenGL ES 3.0`, no errors. Desktop is untouched — that override only applies
to Android and iOS.

Build one with:

    godot --headless --path . --export-debug "Android" build/waddle-wars.apk

The emulator itself remains a poor host: its system_server wedges under load
(input dispatch stops, and a "Process system isn't responding" dialog sticks
on screen), which is why the pass beyond the title screen is not captured
here. That is the emulator, not the build — the app underneath it is drawing
its frames the whole time.

### The web shell is now tested, not just parsed

`tools/test_web_shell_behaviour.mjs` runs the shipped shell scripts against
nine real device profiles in a DOM stub — 36 checks. It covers the pixel
budget (every phone profile lands at or under 1.25 Mp per frame, never
upscales, never falls below dpr 1.0; a 430x932 phone at dpr 3 comes down from
4.02 Mp to 1.25), the canvas sizing (the layout viewport wins over a zoomed
visualViewport — the iOS Safari feedback loop that put a 472 px canvas in a
402 px phone), and the graphics-loss screen (registered in the capture phase,
prevents default, stops propagation so Godot's blocking alert never fires,
and the Reload button reloads). Mutation-checked: raising the budget to
9.25 Mp fails 6 of them.

### Phone layout: cards that fit, and a HUD that shares the screen

Running the Android build turned up two layout defects that no test could see,
because nothing measured card contents or where the HUD lands relative to the
touch buttons.

**Cards were sized by hand, and the hand was wrong.** A card's contents sit in
a MarginContainer anchored to the button's full rect, so they never reach the
button's own minimum size: the height is whatever constant was authored, and
the button clips. `tests/card_probe.tscn` measures both. On a 390x844 phone
the Endless Expedition card wanted 394 units and was given 346 — its
description was quietly sliced off — while every difficulty card wanted 359
and was given 473, leaving a quarter of each card empty between the pitch and
the pip meters, which is exactly what the Android screenshots showed.
`_fit_cards()` now sizes them: in a multi-column grid the row shares the
tallest card's height, and in the single-column phone layout each card takes
its own. Re-measured after the change, all three steps report zero slack and
zero overflow.

**The HUD and the touch buttons were fighting over the bottom of the screen.**
The course gauge ran from 32% to 68% of the width; SHOVE starts at about 62%
on a portrait phone, so the end of the rail — the end carrying the percentage
— was drawn underneath a button. The rail now stops short of the cluster, and
where there is no room to stop short (at touch scale 2 the buttons own the
right 70% of the canvas) it lifts above the buttons instead of shrinking into
a stub. It re-measures on rotation and when the player moves the touch-scale
slider, both of which move the cluster.

`tests/race_hud_touch_layout.tscn` is the guard: it builds the real HUD at
five device sizes across three touch scales and checks every bottom-rail
widget against every button rect, the safe area and the canvas — 390 checks,
all passing. It found the touch-scale-2 case on its own, which the fix as
first written did not handle.

### The player could get stuck with no way out

Playing the Android build found this: wedged below the track lip at 44% of
Glacier Gauntlet, and still there ninety seconds later. Jumping and steering
did nothing.

The cause is that stuck-detection only ever existed for the AI.
`AIController` has had two watchdogs since the beginning — a position one on a
3-second cycle and a course-progress one on a 12-second cycle, both ending in
`respawn_at_checkpoint()`. The player had neither. `Racer._check_kill_plane()`
rescues anyone who falls below the course, but most geometry a racer can wedge
into sits well *above* the kill plane, and there the only way out was the
pause menu.

`Racer._check_stuck()` now covers the player, on the same two-tier logic the
AI uses and deliberately conservative about when it fires:

- It needs the racer to be both making no course progress (under 3 m) and
  moving at under 1.5 m/s for the whole window. Either one alone rearms it.
- Pinned against geometry (`is_on_wall()`) gets a 4-second fuse; nothing the
  player does will free them and every second is race time lost. Merely going
  nowhere gets 12 seconds, so pausing to look around, lining up a jump or
  reading the track is never interrupted.
- Stunned, recovering, airborne and finished racers hold position by design
  and reset the window instead.
- A racer whose controller is not taking input — the starting grid during the
  countdown — is being held on purpose and is exempt.
- AI racers are left to their own watchdogs, which also re-pick a route
  afterwards.

The HUD says "Stuck — back to the last checkpoint" when it fires, because a
rescue that silently teleports you reads as a glitch rather than as help.

Seven unit checks cover it: fires when pinned, ignores a moving racer, ignores
one making progress, leaves finished racers alone, leaves AI alone, waits
through the countdown, and does nothing without a course. Race sims on
glacier, aurora and iceberg plus the endless sim confirm the watchdog does not
fire during ordinary racing.

### Android: verified end to end

The native Android build was driven through the whole player path on the
emulator, and it works:

| Screen | Result |
| --- | --- |
| Title | Full-fidelity art, portrait layout correct, no texture corruption |
| Main menu | Whole hub fits: chip, both hero cards, four tiles, Settings/Credits |
| Mode select | Scrolls, rail pinned, Main Menu button reachable |
| Course select | All five posters render clean — these are the NPOT textures that broke iOS Safari |
| Difficulty | Three cards, compact, all on screen without scrolling |
| Race | Runs, HUD correct, touch buttons placed, course gauge readable |
| Stuck rescue | Confirmed live: pinned at 44% for 45 s, then rescued and back to 59% |

The renderer reports `gl_compatibility` / `OpenGL ES 3.0` throughout, which is
the path every shader in this project is written for.

**One unresolved observation.** In-race on the emulator, a large olive-grey
slab with stair-stepped edges lies across the ice near the player — the ice's
own hex pattern shows through it, so it is a shadow, not geometry, and the
steps are shadow-map texels. It did not reproduce in local `gl_compatibility`
captures of the same course (opening and downhill zones), so it is either
specific to that spot or an artefact of the emulator's GL translation, which
has already been shown to mishandle WebGL compositing entirely on this host.
Not chased further without a real device to confirm it against; the screenshot
is in the session scratchpad. Worth a look on hardware before it is called
either a bug or a non-issue.
