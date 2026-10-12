# Native release preparation

For the current two-store launch sequence, use [LAUNCH_RUNBOOK.md](LAUNCH_RUNBOOK.md). The dated checkpoints below are historical evidence and do not authorize uploading an older candidate.

## Launch MVP — authoritative scope, October 2

Owner narrowed launch to **a free, offline-first game on both iOS and Android**.
This governs the immediate launch milestone; premium graphics and commerce
remain deferred, not achieved. Historical purchase gates below apply before
enabling those later features. Do not resume those workstreams during MVP preparation.

- Include runner's avalanche chase, existing races/tutorial/endless, existing
  local progression and earned cosmetics, current shipped art, readable controls
  and functional loading/retry. Preserve bundle identity and existing saves.
- Defer premium penguin/environment/frontend rebuilds, new gamification,
  accounts/cloud, Stripe and in-app purchases. Native entry points for deferred
  account/purchase flows must be hidden/disabled; earned customization remains.
  Do not enable sales or alter existing web services to satisfy native launch.
- Only fix crashes, freezes, data loss, unreachable controls, loading failures
  or other demonstrated submission/device blockers. No speculative cleanup,
  art experiments, new QA frameworks or open-ended profiling/soak loops.
- Browser freeze is provisionally resolved by owner play. If browser access
  returns, allow at most the already-agreed two-minute cumulative active check
  with three retries; a clean result closes the investigation. No long soak.

Owner's later test-cadence instruction: **defer regression suites until the final
candidate**. Essential import/parser checks may run during implementation.
Do not treat interrupted/partial suites as passes. This does not waive the
applicable final local validation gate before any remote CI/upload.

**Latest signing checkpoint, October 4:** Current-source iOS build 16 (runtime
`d849cd516cfcd232d6d8ea4f27f9ff97a2300da8c257cf2f6ddb973d411af972`)
exports, archives and produces a locally verified signed IPA with the existing
Ninja Consulting Apple Distribution identity and exact Waddle App Store profile.
IPA SHA-256 `885781615e810ec1c5ceaf7a79f9176b8674b84e51145740113c8043b8cdf70a`;
archive and IPA receipts are in
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-signing-current-20261003.TcthdW/archive.esFtCK`.
The previous `errSecInternalComponent` does not reproduce. Its former cause is
unproven. After normal Apple sign-in, an isolated development-signed iOS-on-Mac
run reaches title/menu, runner, lane input, avalanche result and instant retry.
This is not iPhone/simulator or race acceptance. Android16 from the same runtime
is now upload-signed with the existing app-specific key and passes offline AAB
verification (SHA-256
`5bb25f4612783f9a93cfcd59331fc2c7efbfaa05762bc1be49276cb33924786b`).
Android15 remains installed in owned emulator and renders title, but active
gameplay is unverified after Computer Use input failed. Both platforms' targeted
virtual-device gameplay, final suite, Play identity and store gates remain.
**MVP ~80% / full ~35%** is a coarse estimate.

Free-MVP preparation now omits deferred native billing/auth SDKs and verifies
their absence. Both Android production export paths skip billing-only build
inputs without weakening signing or runtime gates. Optional custom iOS template
ZIPs require an exact SHA-256 and are copied outside the game payload into frozen
candidate inputs. These release-tool changes have only parser verification; new
fixture assertions await the final gate. Earlier iOS12 exported/linked the finished
device-only Release template and passes unsigned static review; its actual PCK
and privacy match the export, with deferred SDK linkage/capacity imports absent.
Only the reviewed template SHA selects the empty disk-reason mask. One manual
archive attempt failed at CodeSign (`errSecInternalComponent`); its cause and
exact lock state at signing are unproven. One fresh retry after visible unlock
failed with the same error, terminal1. Both attempts are preserved; later
current-source signing succeeds as recorded above. Gameplay and privacy/store
acceptance remain open. `BUILD_STATUS.md` records exact immutable evidence.

Earlier Android14 exports the same free-MVP runtime without the deferred SDK chain
or billing-only build prerequisites. Bundletool and 16-KB structural checks pass.
One existing-helper signing dispatch fails at app-specific Keychain password
access before signing; the unchanged unsigned AAB and failed-attempt receipt are
preserved. No unchanged retry or permission/key change follows. That Android14
bundle remains unsigned and unaccepted; current iOS16 signing and Android15
title evidence are recorded above. Exact Android14 paths/hashes are in `BUILD_STATUS.md`.
Privacy draft fixtures now match bounded provider wording; only AST parsing is
complete, not their final regression or policy publication.

Critical path, in order:

1. Fix demonstrated native cold-loading failure and establish rendered iOS play.
   Recovery containment is implemented and parser verified, but is not a
   cold-start fix or native acceptance. A native Compatibility-only covered-sky
   warmup patch now has a clean final-source editor import and independent
   source review. Its one changed-build iOS QA pass renders title/menu but
   reaches runner loading recovery; the fix was not accepted there. Current
   iOS-on-Mac QA does reach moving runner/retry with the same payload, but does
   not establish simulator, portrait-phone, sustained-performance or race
   acceptance. Preserve the existing art/gameplay and shader workload.
2. Freeze the final runtime and run complete required local regression gates,
   then refresh affected native candidates. Current iOS16 archive/IPA and
   Android16 AAB signing pass; these are offline artifact gates only. Earlier signed
   Android11/iOS9 packages do not contain the recovery-containment change.
3. Owner-selected **simulator/emulator-only smoke**: current-source iOS simulator
   app and Android emulator APK; cold load, runner actions/retries, one race/
   tutorial, orientation/safe areas, pause/resume and local save persistence.
   Use separately labeled QA derivatives; preserve signed release packages.
   Fix only observed blockers, then rerun affected checks.
4. Complete truthful store listings/privacy/support and store
   identity prerequisites; prepare TestFlight and Play internal submissions.
   Store approval/public release and legal declarations are not inferred from a
   build, emulator, structural verifier or automated receipt.

Remaining MVP work also includes final privacy/SDK required-reason reconciliation,
rendered in-app policy access, accurate age/audience and store declarations,
both platforms' screenshots and listing fields, and authorized
internal uploads/review/release. Support/privacy pages are published. Both app records now
exist; Play creation follows explicit action-time policy/export confirmation.
Physical tests are waived, not passed. Purchases and accounts are not MVP work.

Owner's October 3 web-deployment request is completed independently of mobile
submission: `https://waddlewars.ninjaconsulting.ai/` now serves
**`web-20261003-d5766c0a42a3`**. Versioned payloads were staged/verified before
switching only the root entry; previous production files remain available for
rollback. Twelve raw HTTP artifacts pass; the single HTML host-beacon insertion
is precisely accounted for. Remote root storage and public Chrome build/title
are verified. No backend/payment/store settings changed, and no live rollback,
active-gameplay performance or native acceptance is inferred. Final local suite
history is 104 PASS / 9 SKIP / 1 FAIL; sole test-only parse failure is corrected
and its affected rerun passes 95 assertions. Three NumPy groups separately pass
10 tests; six window-only groups remain unrun. Exact evidence:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/web-release-20261003.He1W9j/deployment-result.json`.
Earlier containment-source Android QA build12 passes export and actual AAB
static gates, but has no APKS/install/runtime pass. Interactive native smoke,
cold loading, refreshed production signatures, privacy/support and store gates
remain critical path. **Mobile MVP ~75% / full goal ~35%** remains unchanged.

The full plan adds the authored shared penguin rig/species/cosmetics and polished
waddle/action motion; runner golden slice, four distinct biomes, avalanche and
contact VFX; all five courses, tutorial and endless visual rebuilds; portrait and
landscape frontend/loading/HUD/results redesign; full accessibility, asset,
motion and performance acceptance; additional retention/progression; and verified
StoreKit/Play Billing/Stripe commerce, restore/refund/revocation and account/cloud
isolation before sales. It remains deferred, not achieved by launching the MVP.

Latest implementation evidence:
`../../qa_shots/native/recovery-containment-20261003-Nd6A0j/source-verified-receipt.json`.
Runtime SHA-256 `bc05858a927ec9da0ea1c56a0c73931269fae687f6827f6a5f3f3f866ac17cd2`;
isolated parser/import passes; subsequent final web-candidate headless checks
execute as recorded above. Native verification
and gameplay cold-start acceptance open. New verified iOS launch milestone moves
coarse estimates to **MVP ~75% / full ~35%**.

Latest reported-fix native packages are **iOS simulator11 / unsigned Android13**,
both frozen from runtime `cc89e3d732a9f8ccdf49df130975abec84c57438414dd373c5a2fff640593606`.
iOS imports/exports and links the reused ARM64 simulator engine with signing
disabled; Android imports/exports and passes bundletool plus 16-KB structural
checks. iOS11 renders title/menu but remains at runner warmup; Android13 is
installed without a launch. They include read-only native privacy/help
information, not an effective policy; its extended fixture remains unrun.
Receipts and exact paths are in `../../BUILD_STATUS.md#refreshed-native-test-packages`.
Android13 also has a verified development-signed APKS derivative from the same
unchanged AAB. All five APK signatures and 16-KB alignment checks pass. Use its
retained API35/ARM64 spec and exact owned isolated emulator data. Installation
through `bundletool install-apks` completes0; actual version13 and all five
installed package hashes match, including the game asset pack. Old private
splitcompat-cache cleanup is refused because the app is non-debuggable; no
permission workaround or uninstall follows. Emulator is shut down without
launching the app. This is not production signing, verified runtime resource
resolution, cold-loading or gameplay acceptance.
Historical signed packages and deployed web remain unchanged. Current native
smoke/cold-loading, final regressions/signing, privacy/store gates remain open;
**MVP ~75% / full ~35%**. Do not repeat exports without a changed source or failed
package gate; use these current QA packages for the next applicable check.

Earlier containment-source ARM64 iOS QA evidence:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-arm64-20261003-b10.d3FU9J/title-smoke-receipt.json`,
SHA-256 `69c61a8035acd4655b02d9da820caeb0f16d321a8c967311bd0b3b26cf88a353`.
One actual ARM64 simulator engine build and one separate build10 app link finish0.
Current PCK/privacy match the export; historical signed packages are unchanged.
Reused owned iOS18.4 boots as ARM64, installs and launches once through public
virtual-device controls while the Mac is locked. Actual captures show title/loading
at observed process age8s and settled Begin Expedition title at38s. This establishes
current-source iOS launch/rendered title, not continuous startup latency, pristine
cold-device, gameplay or performance acceptance. Owned device is Shutdown, app
PID absent. Interactive smoke after unlock and Android changed-build cold loading
remain; regression suites stay deferred.

Earlier x86 iOS frontend evidence:
`../../qa_shots/native/ios-frontend-launch-20261003/final-receipt.json`.
A fresh owned iOS18.4 device reaches readiness, installs build9 and starts the
app process through one supported icon click. The observed frame stays black;
the one-second stack sample shows software GL canvas rendering under Rosetta.
The owned device is Shutdown, app process absent, and packages/source unchanged.
No title/gameplay acceptance in that earlier pass. Do not repeat x86 launches.
Actual ARM64 engine acquisition above removes translation, not necessarily
software rendering. The pinned simulator target disables Metal
and Vulkan. This historical build excludes recovery containment.

### Signed candidates before recovery containment

Frozen runtime **524 files** / SHA-256
`dc50ecd61b568091d3f5effedbc0d2ee545447d657ce96d191b0ed65c9faa569`.
Existing full suite: **105 PASS / 9 SKIP / 0 FAIL**, terminal0; NumPy classes
separately **10 / 0 / 0** on the same snapshot; release tools **522 / 0 / 0**
after draft screenshot preparation.
Known shutdown warnings, six real-window groups and one internal geometry skip
remain. Source/test evidence:
`qa_shots/native/locked-mvp-smoke-20261002/REVIEW.md` and
`qa_shots/tests/waddle-wars-tests-19908-19383/`.

**Android11 is now upload-signed and verified offline**. Canonical candidate:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-release-parity-qa-20261002-b11`.
AAB `project/build/waddle-wars.aab` SHA-256:
`1241dc2aed31c99875edd6104727dc7cc16ada5ae079c7d5761cbb95ce3efa7e`.
Its `receipt.json` binds the exact source, upload signature/pin, unchanged game
payload, bundletool and 16-KB structural gates.
**iOS9 signed archive and IPA pass strict offline verification**. Evidence root:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-mvp-archive-20261002-b9.1qNmjo`.
IPA `ipa-export/waddlewars.ipa` SHA-256:
`35bc5de48e0bebe40bd4a05a2dfe502dfc618bd85f447ea287273942ec211273`.
`handoff-receipt.json` and archive/IPA verifier receipts bind signature/profile/
title/ARM64/native linkage, frozen PCK and resource equivalence; both Xcode steps
exit0. These supersede the initial unsigned Android11/iOS9 and older signed
Android8/iOS6 checkpoints. Preserve historical failures and receipts.

Separate Android release QA audit matches **641 normalized game/ARM64 payloads**;
transformed Android packaging entries are classified, not claimed byte-identical:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-release-smoke-20261002.VufZ19/audit.d1xkr5/audit.json`.
Fresh offline zero-fish menu is observed. Cold runner route at **21:46:13 UTC**
reaches 30-second Recovery, observed **21:46:48**. Public Retry at **21:46:59**
reaches gameplay, observed **21:47:25**; jump, left lane, Pause, landscape and
Resume are captured. Slide was injected but not visually confirmed. Settled
portrait menu at **21:50:15** is nonoverlapping; rotation during entrance is not
timing-proven. Owned emulator shutdown finishes terminal0. Cold loading and
full native acceptance remain open. Current-source **x86_64 iOS simulator
build9 links**, zero errors/one duplicate `-lc++` warning. Single bounded iOS18.5
boot fails readiness after **150.683 seconds**: `Status=3`, `isTerminal=YES`,
`Data Migration Failed`. Monitor exit0 is not a pass; readiness wrapper correctly
exits3. No app installation, launch or title capture. Exact-owned simulator
shutdown finishes terminal0 with `Shutdown` confirmed. Link receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-x86_64-20261002-b9.IqelQw/receipt.json`.
Failure receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-x86_64-20261002-b9.IqelQw/headless-title-smoke-20261002/receipt.json`;
SHA-256 `28daeda98d77df6976eb974a615e93007bd5db1ba1e45e97898074cc8de4b82c`.
Historically, Data volume had only **3.7 GiB available / 100% rounded capacity** at 21:54 UTC,
versus approximately 11 GiB before QA. Scoped owned logs contain no explicit
`ENOSPC`; migration cause is unproven. This is a pre-app environment failure,
not game acceptance.
Full current evidence:
[current signing and QA review](../../qa_shots/native/unlocked-mvp-signing-20261002/REVIEW.md).

Owner-requested cleanup removes **14.7 GiB allocated regenerable caches**;
free space reaches **21.88 GiB** at its checkpoint. Source, keys, saves, signed
packages, frozen projects, QA evidence and pinned Maven artifacts are preserved.
Runtime and Android11/iOS9 hashes still match. Receipt:
[disk cleanup](../../qa_shots/native/disk-cleanup-20261002/receipt.json).
The goal is active after resume, not currently paused or complete.
One iOS18.5 retry still fails readiness (**56.257 seconds**). Fresh owned
iOS18.4 readiness passes (`Finished`, **128.597 seconds**), but the single
build9 installation request times out (**30.021 seconds**) with outcome
unconfirmed. No launch/title capture. Both owned devices are confirmed
`Shutdown`; public post-shutdown lookup cannot resolve installation
(`SimError405`). All owned heavy handles are terminal. Immutable receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-x86_64-20261002-b9.IqelQw/headless-title-ios184-20261003.DyMiI3/receipt.json`;
SHA-256 `7e3dc238ee843879fb27d66a5e987c485a107e6daa298c22fc7bb400c92b1645`.
Earlier evidence is unchanged; no rebuild, signing retry or fresh suite run.
Next native work is installation/title confirmation and precise diagnosis of
the demonstrated Android cold-loading blocker, not another unchanged run.

Later iOS18.4 public bundle metadata confirms installation without reinstall.
One normal launch request times out (**30.011 seconds**); outcome remains unknown.
The one supported screenshot shows SpringBoard, not the game. Both owned devices
are confirmed `Shutdown`; title/game acceptance remains open. Latest receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-x86_64-20261002-b9.IqelQw/headless-install-resolution-20261003.dsKjSS/receipt.json`;
SHA-256 `9a1b4f8d710b477e68fe5920406f3f158f14e1c454fef37d59a3c7cbf804fe70`.
The owner-requested interruption of suite session96138 ends130; retained logs
and receipt are at `qa_shots/tests/waddle-wars-tests-46760-10662/`, not a full pass.

One iOS18.4 console-attached diagnostic passes readiness and installation lookup
but produces no app output/PID during a bounded 75-second capture. Its one actual
PNG shows SpringBoard; launch server outcome is unknown, not a proved game crash.
Client -15/wrapper0 is not app PASS. Exact owned shutdown succeeds and both devices
are confirmed Shutdown; original app/preparation/receipt pins remain unchanged.
No more headless launch retries. Immutable receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-simulator-qa-x86_64-20261002-b9.IqelQw/headless-console-diagnostic-20261003.lo7eSm/receipt.json`,
SHA-256 `6fc4225a1bf505b464b62ff49d446647c5546e08fcc1ed04283faf203287c404`.
Title/gameplay/native/performance/store acceptance remains open.

The opt-in native runner capture diagnostic must be packaged under distinct
`com.blubberandbyte.waddlewars.runnerdiag`, with fresh QA app data, release engine,
`waddle_native_trace_qa` feature and baked `native_trace=1`. Custom user-dir names
are intent markers, not Android OS sandbox isolation. Keep shipping packages,
runtime and saves untouched. Real route/warmup logging still bypasses boot/menu;
it diagnoses the observed blocker but cannot establish launch acceptance.
The fresh unsigned derivative passes import/export and offline artifact gates;
it has not yet run. Receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-runnerdiag-20261002.E9U8YP/candidate/receipt.json`,
SHA-256 `4df6a9b1c7a5ed159fc17c7d61b564f34fbe6c2e02eadb7b02916cec065b0955`.
Actual nondebug release manifests, baked QA feature/main scene/user argument,
ZIP/CRC and two baseline-equal ARM64 engine libraries are verified. The 42
generated title XML files and one theme are classified against pinned exporter
source; all other sealed inputs match. Keep the initial verification hold and
before/after hashes. This is not a runtime fix or shipping acceptance.

The single subsequent Android diagnostic misses its 120-second emulator boot
cap before app installation (59 offline probes, one absent). No game timing;
owned shutdown/process cleanup is confirmed, original userdata preserved. New
and previous encryption-key paths differ, but cause is not established; no key
content inspection or blind retry. Immutable receipt:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-runnerdiag-runtime-20261002.dmYbG8/native-diagnostic-final.receipt.json`,
SHA-256 `bae09a628007e1509223868115a8ee3a80b9a56ed01c6c772152b02d8f9d7d50`.

Owner specifically requests Play creation in parallel. The existing Chrome form
is readable and already has the approved title/package (available), English US,
Game and Free selected. It awaits action-time confirmation for mandatory policy
compliance and US export/encryption certification; no declaration/Create action,
upload or publication. Evidence:
`../../qa_shots/native/play-create-20261003.Xfn75H/receipt.json`.

Three unchanged Android11 release captures are prepared as local draft listing
screenshots in `store_assets/android-build11-draft/`. The receipt binds original
image hashes and source/AAB/APKS/audit provenance, and retains the cold runner
failure and subsequent Retry context. The full release-tool suite passes
**522 tests / 0 skips / 0 failures**, terminal0, including the new PNG/provenance
regression. These are not uploaded, approved or substitutes for iOS screenshots.
Runtime and signed packages are unchanged; **MVP ~70% / full goal ~35%** remains.

Native acceptance is **not passed**. Signed release receipts remain
**`store_ready: false`**; no upload, TestFlight/Play acceptance or public release.
Prior extension interruption is historical: current Play form access succeeds,
but no controlled game-performance pass or security change is implied.
Audience, public policy URLs/disclosures, SDK/required-reason reconciliation and
store setup remain open. Coarse estimates: **MVP ~70% / full goal ~35%**.
Earlier chronology below records dated checkpoints, not current unsigned status.

Physical-device testing is waived for this MVP, not passed; stop device polling.
Simulator results do not establish phone/store-installed performance, physical
touch or 16-KB runtime compatibility. Original full-plan evidence gaps remain.
Stop at missing simulator UI/account/signing access; report the exact prerequisite.
Headless virtual-device development controls may perform lock-independent QA;
they do not bypass the Mac lock and must never operate physical devices here.
The latest corrected Android10 headless pass captures native Help, runner
actions/Pause/Resume, landscape, Home/resume and saved results after restart.
Cold loading fails and rotation during entrance overlaps mode cards; native
acceptance remains open. Debug-only DAY assets are not release-art parity.
The UI race is repaired (**90/3 RED → 93/0 GREEN**) and full repaired-source gates
pass **105/9/0**, NumPy separately10/0/0. Initial canonical unsigned Android11/iOS9
exports shared `dc50ecd6…`; signing and QA derivative/linkage are superseded by
the current checkpoint above. Native runtime acceptance remains pending.
Do not strip graphics or promote draft assets. Evidence:
`qa_shots/native/locked-mvp-smoke-20261002/REVIEW.md`.
Do not repeatedly poll unchanged state or start deferred work while waiting.
Prepared/exported/offline-signed receipts remain `store_ready: false` until the
applicable current QA and store gates actually pass. Real purchases are **not** an
MVP acceptance gate because purchases are disabled.

The iOS native bridge builder supports explicit `--variant simulator`, with
ARM64 by default and `--architecture x86_64` for the actual installed Godot4.7.1
release simulator archive. Actual `lipo` inspection finds that archive contains
x86_64 only, despite its XCFramework metadata advertising ARM64 too; the first
ARM64 QA app link failed at `_main`. Keep that failed result, not a signing retry.
Both simulator targets use exact generated Godot headers and separate receipts.
Default device build/production installation gates
are unchanged; they reject simulator receipts. Keep QA libraries and app
derivatives outside the installed device-plugin directory and accepted signed
packages. See `native/ios/WaddleStoreKit/README.md#simulator-only-qa-libraries`.
Eighteen mocked builder regressions and the consolidated **521-test** release-tool
suite pass without skips/failures. Earlier isolated ARM64 bridge compilation
passes, with all four objects reporting IOSSIMULATOR / iOS15 / SDK26.5, and actual
production installation rejects its receipt. That alone did not prove matching
engine linkage. Installed iOS18.5 supports x86_64 and host translation is usable.
One matching x86_64 bridge compilation and a fresh, separately copied simulator
app link now succeed, actual Xcode terminal 0; result bundle has zero errors and
one duplicate `-lc++` warning. Neither app is installed/run yet; foreground smoke
awaited manual unlock at that checkpoint. Android QA build9 and canonical iOS export7 shared
`1951ebde…`, whose full existing suite passes 105/9/0 (three NumPy groups separately
10/0/0). No accepted signed package was replaced. Current evidence:
`qa_shots/native/simulator-packages-20261002-2040Z/REVIEW.md`.
The later provider-request draft case accounts for test521; its focused page
suite passes24/24. Actual service-specific limits, SDK/audience choices and public
policy/store approval remain open; see `privacy_review.md`. No new runtime export.
Earlier bridge-only evidence:
`qa_shots/native/simulator-bridge-20261002-2020Z/REVIEW.md`.

The historical Android8/iOS6 signed baseline is 524 files / `2d3518aa…`, including the runner touch-Pause fix.
Fresh-cache focused runner-platform checks pass **264 assertions / 0 failures**,
including viewport GUI-dispatched Resume and repeated touch pause/resume.
One consolidated existing-suite run exits 0 with **105 PASS / 9 SKIP / 0 FAIL**.
Three NumPy-dependent skipped groups then pass their exact existing classes
using bundled Python (**10 assertions / 0 failures**, no full-suite rerun).
Three renderer-window follow-ups now pass: orientation, **72 menu layouts + 24
inset/rotation cases**, and **390 race HUD/touch-rectangle checks**. Live portrait
runner loading/Pause/GUI Resume/forced death/GUI Retry passes **46 / 0** with 15
actual captures. The synthetic warmup gate timed out; landscape lost focus at
2.682 seconds and stopped drawing. Neither is accepted. Its next diagnostic
fixture revision is unrun. Stop rendered retries until foreground availability
changes. Atlas/dusk renderer skips remain deferred, not passed. Known shutdown
diagnostics remain explicit; no phone/browser/performance acceptance. Evidence:
`qa_shots/native/mvp-critical-path-20261002/REVIEW.md`.

Runner now has an active-play touch Pause button inside safe areas, with existing
Resume/Main Menu behavior. Pause-owned touches cannot also jump/change lanes,
and any prior gameplay gesture is canceled before pausing. Loading/countdown,
results and routing-busy calls reject the touch entry point. Portrait/landscape,
HUD scale, raw fingers 0/1 and emulated-mouse isolation pass locally. Resume's
existing GUI input path is covered; physical touch/device evidence is absent and
testing is waived in the current owner-selected MVP scope.

Android **build 7** exported the previous `b316cd77…` MVP runtime, before the
runner touch-Pause fix, but signing failed at
`reading_app_specific_keychain_password`. Unsigned AAB and failed launch receipt
are preserved outside the checkout at
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-mvp-release-20261002-b7`.
No prompt, key replacement, password disclosure or automatic retry occurred.
The intended signed AAB was not produced or release-verified. Do not install or
upload this incomplete candidate as a signed release. Resume only after normal
Mac/Keychain access changes; preserve this attempt and use the canonical fresh
candidate workflow, not a credential workaround.

Build 6's failed attempt is also preserved. Build 7 followed an observed access
change (screen-lock marker cleared; default Keychain status 7), not a blind retry.
That metadata does not prove access to the app-specific password item.

iOS **build 5** exports that same previous `b316cd77…` runtime, before the
runner touch-Pause fix, but the single manual archive
fails at app CodeSign with `errSecInternalComponent`. Existing profile/helper/
certificate pins were verified; no automatic provisioning, new keys/profiles or
upload. Candidate and failed archive are retained at
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-mvp-export-20261002-b5`
and sibling `ios-mvp-archive-20261002-b5`. No signed archive/IPA is accepted.

Android build 5 was the last signed artifact at that historical failure checkpoint
and is stale. The restart checkpoint below now supersedes the signing-access
failure. Device and Play/store gates remain open; no store acceptance has passed.
Do not fill prerequisite waits with deferred art, commerce, extra exports or
profiling work.

The subsequent owner-authorized native Keychain request also failed before any
confirmed approval: GUI-context unlock reports `errSecAuthFailed` (-25293), and
the exact Apple identity signing probe exits 1. No authentication task remains
live. Keychain Access was opened; the owner reports an earlier Deny/rejected
password, with no verified recovery yet. Do not reset/delete the keychain,
change access policy or replace signing keys. That signing checkpoint was
blocked pending normal credential access and connected physical devices;
status-only prompt/device evidence is recorded in the MVP review above.
Subsequent independent MVP preparation does not clear the signing/device gate.

Owner subsequently paused **all Keychain/signing work until a computer restart**,
then explicitly confirmed that restart. One actual Android key-use probe and one
exact-identity iOS signing/strict-verification probe now pass, with the existing
public certificate pin. No Keychain policy changed. **At that checkpoint Android 8 AAB and
iOS 6 archive/IPA now pass canonical offline verification** from `2d3518aa…`,
including touch Pause, not a promotion of stale builds 7/5. Three actual verifier
issues received narrow source-bound localization, concrete pinned-tool and
identical-profile mode-tightening fixes; all **499 release-tool host tests pass**
with zero skips/failures. Failed attempts remain unchanged. `store_ready: false`;
no upload/deployment, new key/profile or device/store acceptance. Evidence:
`qa_shots/native/mvp-signing-restart-20261002/REVIEW.md`.
Device check still finds no online Android and the paired iPhone unavailable.
Public submission or legal declarations are not authorized by preparation.

#### Subsequent native presentation guard — source changed, packages unchanged

A bounded content review found public player-chosen leaderboard handles reach
native labels, without identified report/block/profanity moderation in those
paths. Apple/Google UGC rules require relevant safeguards; treating this as a
submission risk is an inference from the source and rules, not an actual store
rejection. See the source/rating notes in `privacy_review.md`.

`LeaderboardClient.fetch_board` now projects successful **native-only** replies
to numeric ranks/scores and game-authored `Penguin #<rank>` aliases. Unknown
text/metadata are discarded; source dictionaries, non-native successful replies,
failures, GET routes/body, once-delivery and account-generation protections stay
unchanged. The original caller's freed-node callback guard is retained too.
This preserves read-only boards, not a new moderation/account service or a claim
that no data is collected. Gameplay/scoring/save mechanics are untouched.

Source at that presentation-guard checkpoint: **524 files** / SHA-256
`1951ebdecfdea4aa8618a8f26d98c28f666020e7c10905d67424355ce7d98c45`.
Fresh isolated Godot 4.7.1 import and policy fixture pass **44 / 0**, terminal 0;
baseline shutdown diagnostics remain explicit. Evidence:
`qa_shots/tests/waddle-wars-tests-50538-28305/`.
Accepted Android 8/iOS 6 packages at that checkpoint bind **`2d3518aa…`**, not that
source. No fresh export/signature/upload followed at that initial guard
checkpoint. The later current-source full suite and QA exports are recorded
at the top; Android11/iOS9 now bind `dc50ecd6…`. Do not
relabel historical full-suite/package receipts as this revision.

### Prepared store materials — not submitted

#### Current portal checkpoint — October 2, 18:48 UTC

The existing Apple app is **6818416048 / Waddle Wars: Penguin Panic**, under
**Ninja Consulting, LLC**. Saved English-US version-1.0 fields: description,
`avalanche,racing,runner,Antarctica,arcade,offline` keywords, source-derived
reviewer notes, and **Sign-in required: off**. A reload preserves all four.
The copy avoids an unmeasured instant-retry claim. Save is disabled after reload;
status remains **Prepare for Submission**. No build, screenshot, review or
release was submitted. Support URL and review contact remain blank. The October 3
follow-up saves **Outrun avalanches, race icy courses, and earn penguin cosmetics
offline.** as promotional text and **2026 Ninja Consulting LLC** as copyright;
both persist after reload. Evidence:
`qa_shots/native/ios-store-draft-20261003.ttUVf9/receipt.json`. This changes draft
metadata only, not native acceptance or release readiness.
App Information subsequently confirms **Saved** for subtitle
**Avalanche chase & icy races** and **Games / Racing / Action**, matching the
local draft. Bundle ID is the existing `com.blubberandbyte.waddlewars`; SKU is
`waddle-wars`. Content rights and age ratings still display setup controls.
App Privacy, age/audience and pricing completion remain unestablished. Existing
Digital Services Act text says this developer identified itself as a non-trader
for this app; this declaration was not changed or independently approved here.
Resolve operator/territory facts before any submission. The pre-existing release default is
**Automatically release this version**; it was not changed. Before any review
submission, explicitly resolve the release policy; do not infer that a draft's
enabled Add for Review button grants permission to submit.

The Google Play app is created in **Ninja Consulting**
(`ninjaconsultingllc@gmail.com`, developer **9132521315692749104**): exact title,
existing package `com.blubberandbyte.waddlewars`, English-US, Game, Free;
app ID **4974838896609027403**. The owner explicitly confirms **Developer Program
Policies** and **US export laws** at action time. Creation reaches its dashboard;
this is not proof of worldwide display-name uniqueness or store acceptance.
Arcade category and `ninjaconsultingllc@gmail.com` contact then show saved
confirmations. Screenshots: `qa_shots/native/play-created-20261003-dashboard.png`
and `qa_shots/native/play-created-20261003-category-contact.png`. Default automatic
installer protection remains on; no security-setting change occurred. No build
upload, review or public release is submitted. Remaining privacy/audience/listing
tasks are uncompleted.

These are portal-draft facts, not store acceptance or new authorization. Reuse
the staged tabs; no account, signing or device polling loop is needed.
Local snapshot bound at that portal checkpoint:
`store_listing.en-US.json` SHA-256
`2a093a5354ffad36ea64d337e494695015c6d19eabbb3f3aa19bd1d9c5057787`.
The subsequent owner-authorized local contact update is not a portal update.
Subsequent local contact choices are recorded below; they do not change the
previous portal snapshot's binding.

Current final-package static privacy review closes iOS manifest placement and
refreshes Android manifest/dependency facts without executing either game.
See `privacy_review.md#superseding-signed-candidate-checkpoint--october-2`;
runtime data/required-reason use/host/support practices remain unverified.

Subsequent pinned-engine review explicitly sets future iOS file/timer privacy
reason masks to `C617.1`/`35F9.1`; focused preparation/listing tests pass **21/21**.
Disk-space defaults remain unapproved pending actual-purpose reconciliation.
This does not modify accepted iOS6 packages or establish final privacy acceptance.
See `privacy_review.md#subsequent-preset-correction--filetimer-reasons-only` and
`qa_shots/native/privacy-preset-20261002-1939Z/REVIEW.md`. No new export or upload.

`store_listing.en-US.json` now leads with the avalanche chase in both store
summaries and retains earned cosmetics, local offline progress and no-IAP copy.
Source-derived reviewer routes are drafted, pending current simulator/emulator smoke.
Owner authorized reuse of Chancey's publisher/contact. Current local drafts use
**Ninja Consulting LLC**, verified in Chancey's public Play listing/copyright
sources. Owner then explicitly selected **ninjaconsultingllc@gmail.com** for
Waddle's public support/privacy contact, superseding Chancey's email. Provenance
is in `privacy_review.md`.
Privacy/support URLs are published and saved in Apple/Play drafts. Apple age
rating is saved; Play rating, audience and both stores' final privacy/data
declarations remain open. Do not copy Chancey's rating/data practices or submit
"no data collected" from static guards alone.

The original SVG mark was rasterized directly at required store sizes. Those
baseline files and immutable receipt remain for rollback:

- `store_assets/icon-1024.png`: iOS RGB8, 1024×1024, no alpha; 72,175 bytes.
- `store_assets/icon-512.png`: Play RGBA8, 512×512, all alpha 255; 37,082 bytes.
- `store_assets/generation_receipt.json`: exact source/generator/output hashes,
  `generated_unsubmitted`, `store_ready: false`.

Premium v2 icon now uses the project-owned loading penguin, with full generated
source and prompt under `art_src/ui/icon/`. Current local listing references
`icon-1024-v2.png` and `icon-512-v2.png`; deterministic export and hashes are
in `store_assets/export_premium_icon.gd` and `icon_v2_receipt.json`. They are
saved in Waddle Wars' **Play draft listing**; this does not publish the app or
prove they are embedded in a final signed build. Default
`tools/make_pwa_icons.gd` now derives PWA PNGs from
that premium source; its historical `--store-icons` mode still preserves the
old vector delivery. Prior 20/20 result describes the historical checkpoint,
not the current full launch candidate.

The current Play draft feature graphic is
`store_assets/feature-graphic-1024x500-v2.png`, 1024×500, generated from
project-owned penguin, city, and wordmark sources. Exact prompt/provenance
is `art_src/ui/feature/waddle_wars_feature_v2.prompt.md`. The older flat
graphic remains at `store_assets/feature-graphic-1024x500.png`: 1024×500
RGB8, no alpha, 80,995 bytes.
It reuses the shipped penguin mark, avalanche glyph and OFL font, with the exact
title and "OUTRUN THE AVALANCHE" lettering. Editable composition/helpers and
`feature_graphic_receipt.json` retain exact source/output hashes. Isolated render,
finite repeat/source-binding checks and visual inspection passed; this is
existing-art store composition, not new premium penguin art or a game screenshot.
Receipt remains `generated_unsubmitted` / `store_ready: false`.

Mobile-specific drafts now live in `web/native/privacy.html`,
`web/native/support.html` and `web/native/policy.css`. They distinguish local
mobile saves and public leaderboard reads from separate browser accounts/payments,
use no scripts or remote embedded assets, and visibly retain unpublished notices.
Contact/operator, host/support retention, actual SDK and age/audience practices
remain unverified; no public URLs or legal answers were filled from inference.
See `privacy_review.md` for exact publication blockers, intended R2 keys, and
final in-app-access requirements. The full-game deploy script does not upload
these nested pages; do not run it to publish unfinished drafts.
The local Worker now maps CSS to `text/css; charset=utf-8`; a controlled RED
host case previously returned `application/octet-stream`. Ten local mocked
routing/content-type/cache/conditional/missing-object cases pass after the fix.
This hosting change is not deployed and must accompany approved page publication.
Read-only deployment metadata was available through existing Wrangler, but actual
logging/retention remains unverified; see the review worksheet. No alternate
credentials, new login, log capture or live setting changes were attempted.

Local Chrome captured readable top-of-page phone privacy and desktop support
previews, but its isolated startup unexpectedly reported a Keychain authentication
error and display-link warnings. Both exact-owned preview processes were stopped
and are terminal; no auth dialog, signing retry or follow-up browser attempt ran.
This is limited visual inspection, not complete page/device acceptance. Preview
files are retained at `/var/tmp/waddle-mobile-policy-preview.wXkaBj/`.

Current-build mobile screenshots are still missing. One bounded device check
again found zero online Android devices and the paired iPhone unavailable; no
build, install, re-sign or emulator launch was attempted during the signing pause.
Historical build-5 emulator captures are not current MVP store assets.
Use actual final-build captures; don't relabel them. [Play asset requirements](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en),
[Apple version metadata](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/).
Store materials live outside the runtime inventory. The subsequent runner
touch-Pause fix changes game source to 524 files / `2d3518aa…`; neither retained
Android 7 nor iOS 5 contains it. Fresh Android 8 and iOS 6 now include it and pass
offline signing/package verification; old receipts were not mutated. No new
build, account change, publication or privacy declaration ran during the pause.

Previous completed snapshot (October 2): Android **1.0.0/build 5** is upload-signed
and passes actual offline verification; iOS **1.0.0/build 4** passes export/frozen
candidate verification, not signing. Both use the same tested 524-file
`f3695235…` recovery runtime (historical, before the current shared UI fixes).
Existing Android key was reused without prompting;
iOS signing was not retried while the Mac remains locked. No connected Android
device; physical iPhone is offline. Receipt:
`qa_shots/native/mobile-recovery-refresh-20261002/receipt.json`.
Older candidate descriptions below are historical milestones, not latest builds.

## Reproducible candidate

The bundle ID remains `com.blubberandbyte.waddlewars`. Android emits an ARM64 Gradle AAB with API 36 target and API 24 minimum. iOS emits an ARM64 Xcode project for iPhone/iPad with iOS 15 minimum. Native accounts and purchases are disabled for the MVP. Deferred purchase architecture uses Play Billing/StoreKit; existing web commerce uses Stripe and is unchanged. Region-specific alternative billing has not been enabled.

The selected public store and installed display title is **Waddle Wars: Penguin
Panic**. Public `native_release.json` separates `app_name` from the original
`project_name: "Waddle Wars"`; `project.godot` and the bundle ID stay unchanged so
the rename does not alter application/save identity. Android release and debug
presets set `package/name` to the new title; debug verification also checks the
actual APK's default launcher label. The pinned [Godot Apple exporter](https://github.com/godotengine/godot/blob/a13da4feb/editor/export/editor_export_platform_apple_embedded.cpp)
derives its default plist title from the project name rather than an
`application/name` option. Therefore the canonical iOS build stamps only
`CFBundleDisplayName` in the exported, unsigned app plist before final artifact
hashes, recording its separate before/after policy receipt. Existing retained
candidates are not rewritten. Fresh exports, their final installed labels, and
any future localized `InfoPlist.strings` title overrides still need platform
acceptance; host fixtures are not a device or store-name-availability pass.

`native_release.json` now selects `launch_edition: "free_offline_mvp"`. New
snapshots omit `addons/GodotGooglePlayBilling/` and `ios/plugins/WaddleStoreKit/`,
remove only the billing editor plugin from the enabled list, and disable the iOS
bridge export option. Source SDKs remain intact for the deferred commerce edition;
receipts retain original hashes and exact omitted paths. Game scripts, earned
cosmetics and save identity remain intact. Neither existing native package has
been rebuilt with this policy.

Final verification requires the free edition's SDK absence, not purchase
acceptance. Android checks actual manifests and reviewed provider/SDK DEX
markers; iOS checks the frozen preset plus actual framework/bridge linkage.
Receipts without an edition retain the historical commerce contract. The normal
`build_native.py` MVP path does not require native billing artifacts. Older
integration/debug helpers remain billing-specific; external Android signing
still has an unnecessary pinned-billing input preflight, although its free
snapshot omits those SDKs. New fixture tests are unrun until the final candidate.

For deferred commerce, official Android addon3.3.0 stays pinned in
`billing_plugins.lock.json` with its MIT license and original AARs. The original
iOS bridge/build instructions remain under `native/ios/WaddleStoreKit/`.
Installation or compilation never proves purchases work.

`ios/plugins/WaddleStoreKit/` now contains version 1.1.0 compiled ARM64 debug/release libraries and a hash receipt from exact Godot 4.7.1 headers, Xcode 26.6, and iOS SDK 26.5. Its separate secure `ASWebAuthenticationSession` helper presents in-app iOS account sign-in, with credential-free exact callback matching and server PKCE verification remaining authoritative. `install_ios_billing.py` verifies artifact hashes and all current Swift/Objective-C++/manifest sources before installing into a new directory. Native export verifies the compilation receipt again. Header-only preparation uses four explicit generated-header targets, not a full engine build; use an isolated Python venv containing pinned SCons 4.11.1. App linkage, signed archives, real device authentication, and device purchases remain separate launch gates.

Read-only inventory:

```sh
python3 tools/release/native_release.py inspect
```

Prepare outside the checkout, using an unused store build number. Never substitute an invented Team ID. This copies only runtime folders and keeps `.envrc`, authoring sources, test saves, signing files, and QA output out of the candidate. Existing destinations are refused. Runtime snapshots and exact Android source-template hashes go in `receipt.json`.

```sh
python3 tools/release/native_release.py prepare android /absolute/new/android-candidate \
  --version 1.0.0 --build-number 1

python3 tools/release/native_release.py prepare ios /absolute/new/ios-candidate \
  --version 1.0.0 --build-number 1 --team-id REALTEAMID
```

Run locally without concurrent heavy builds or browser acceptance timing. Godot 4.7.1 templates and Editor Settings must already point to the correct Android SDK and JDK. The script validates immutable snapshot hashes, imports with an isolated temporary user directory, restores production save identity, rejects parse/import errors even when Godot exits zero, and stores sanitized logs plus artifact hashes. No game entry point runs during import/export.

### Preferred macOS Android upload-signing path

`android_upload_signing.py` exports the game **unsigned**, then uses the fixed
Swift helper to sign through JDK `jarsigner`. The password stays in the exact
Waddle Wars macOS Keychain item and a signing-child-only environment. It is never
returned to Python, passed to Godot/Gradle, printed or persisted in build logs.
Locked/protected Keychain access fails without opening a prompt. Signing children
are bounded to 180 seconds. This avoids the pinned [Godot Android exporter's](https://github.com/godotengine/godot/blob/4.7.1-stable/platform/android/export/export_plugin.cpp)
release-password Gradle command arguments; log redaction alone cannot hide argv.

The first-key setup already completed on this Mac. Do **not** rerun bootstrap,
replace the key or delete its failed/completed state to bypass a refusal. The
exact app-owned signing folder is outside the checkout:
`~/Library/Application Support/WaddleWarsSigning/com.blubberandbyte.waddlewars/android-upload-v1/`.
It contains two matching encrypted PKCS12 copies (0600), a public DER certificate,
a pinned compiled helper and a public receipt under private 0700 directories.
The password is a nonsynchronizing, device-only Keychain item. These two local
copies are **not independent off-device recovery** and the certificate is
**intended, not registered with Play**. Independent recovery/custody and Play
upload/app-signing identity must be established before release.

For a fresh candidate, provide explicit existing, nonsymlink tool paths and an
unused build number. Candidate parent must already exist. Failed candidates,
unsigned bundles, signing receipts and logs are preserved, never overwritten.

```sh
python3 tools/release/android_upload_signing.py build /absolute/new/android-candidate \
  --jdk /absolute/jdk --bundletool /absolute/tools/bundletool.jar \
  --godot /absolute/Godot --android-sdk /absolute/Android/sdk \
  --python /absolute/python --version 1.0.0 --build-number UNUSED_BUILD_NUMBER
```

For a Keychain-independent Android build, first perform the one-time migration
from the **existing** upload password while its Keychain item is accessible:

```sh
python3 tools/release/android_password_vault.py migrate \
  --jdk "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
```

The owner chooses a new 16+ character vault passphrase at local hidden prompts.
Migration checks the same PKCS12 and public certificate, writes only an
scrypt/AES-GCM encrypted 0600 vault file outside the checkout, and refuses to
overwrite it. Add `--direct-p12-vault` to the `android_upload_signing.py build`
command above; it prompts for that passphrase and signs with the same upload key
through `jarsigner`, then runs the same offline release verifier. The original
Keychain signing path remains the default until a live vault-backed candidate
passes. Back up the encrypted `.p12` and vault independently of this Mac, and
retain the passphrase separately. Neither the raw upload password nor the vault
passphrase belongs in shell arguments, the repository, or chat.

`build_android_upload.py` performs only credential-free export/verification; it
does not generate keys or sign. Signing retains the original unsigned AAB as
`project/build/waddle-wars-unsigned.aab`. Acceptance requires identical game
payload before/after signing, prepared runtime and pinned input/tool rechecks,
the exact public upload-certificate pin and the mandatory release verifier.
No app code or player save runs during export.

Both release paths disable only the pinned main manifest's `profileable`
shell/enabled attributes in their fresh snapshots, recording before/after hashes.
The [official 4.7.1 template](https://github.com/godotengine/godot/blob/4.7.1-stable/platform/android/java/app/src/main/AndroidManifest.xml)
enables profiling by default. Debug preparation stays unchanged; actual release
manifest verification remains authoritative. Unknown template nodes fail rather
than silently changing unrelated permissions, activities or application identity.

The older `build_native.py` Android compatibility path still accepts externally
configured `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`,
`GODOT_ANDROID_KEYSTORE_RELEASE_USER` and
`GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`. Do not use that route with the new
Waddle Wars Keychain password: it would reach Godot/Gradle argv. The safe launcher
above is the chosen workflow on this Mac. iOS continues using the canonical
candidate build and existing authorized Apple signing configuration.

Android additionally requires the independently obtained **public upload-certificate
SHA-256**, existing bundletool JAR and explicit JDK. Set `WW_UPLOAD_CERT_SHA256`
to that public fingerprint, not a password or private key. Missing prerequisites
fail before export. Existing-key continuity and the intended Play account must be
established before supplying the pin; a matching invented/test certificate is not
proof of Play registration.

```sh
python3 tools/release/build_native.py /absolute/android-candidate \
  --upload-certificate-sha256 "$WW_UPLOAD_CERT_SHA256" \
  --bundletool /absolute/tools/bundletool.jar --jdk /absolute/jdk
python3 tools/release/build_native.py /absolute/ios-candidate

python3 tools/release/check_android_artifact.py /absolute/android-candidate/project/build/waddle-wars.aab \
  --bundletool /absolute/tools/bundletool.jar
```

The Android structural checker verifies every ARM64 ELF LOAD/RELRO segment and requires bundletool's `PAGE_ALIGNMENT_16K` packaging evidence. For a Play-generated APK, also run the checker with `--zipalign /absolute/SDK/build-tools/36.1.0/zipalign`. A structural pass does not replace a real 16-KB device test. Open the exported iOS project in Xcode only after acquiring the correct team/signing configuration, archive for a generic iOS device, validate the archive, then use TestFlight. Do not weaken signing, replace certificates, or automatically enable provisioning to work around a blocker.

### Android release signature gate

Every Android release export now calls `verify_android_release.py` before recording
success. It inspects the actual AAB ZIP, verified JAR signature and every payload's
manifest coverage, exact embedded public certificate pin, actual package/version/
build/SDK/release flags, billing metadata, Godot resource presence, install-time
asset packs, and the existing 16-KB structural gate. Unknown tool formats and
artifact/tool changes fail closed. It uses an isolated, credential-free child
environment and never signs, generates keys, downloads tools or uploads.

An existing release AAB can be checked separately. Set `WW_AAB_SHA256` to its
independently recorded SHA-256; values below are required public inputs:

```sh
python3 tools/release/verify_android_release.py /absolute/waddle-wars.aab \
  --artifact-sha256 "$WW_AAB_SHA256" \
  --upload-certificate-sha256 "$WW_UPLOAD_CERT_SHA256" \
  --package com.blubberandbyte.waddlewars --version 1.0.0 --build-number 3 \
  --bundletool /absolute/tools/bundletool.jar --jdk /absolute/jdk
```

Fastlane's default `android build` uses only the fresh safe upload-signing
launcher above, with explicit `candidate`, `python`, `godot`, `android_sdk`,
`bundletool`, `jdk`, `version` and `build_number` options. It refuses the old
certificate/signing options and never bootstraps a key or retries a failed
candidate. `android verify_release` separately requires the public
`upload_certificate_sha256`, `artifact`, `artifact_sha256`, `version` and
`build_number` pins.
`android verify_artifact` remains **structural-only**, not signing acceptance.
Verified exports retain `android_upload_artifact_verified_offline` and
`store_ready:false`. Neither the public pin nor conventional debug-subject
rejection establishes Play registration, distribution app-signing identity,
complete resource equivalence, real 16-KB runtime, device gameplay or purchases.
An arbitrarily renamed test certificate cannot be inferred from its subject.

The initial gate was covered by synthetic fixtures only. The October 2 real
upload-signed candidate exposed the asset pack's official `assets.pb` table and
Godot's default shell-profiling node; it was rejected and retained unchanged.
The verifier accepts only the exact, bounded asset table in an asset-only module
and additionally requires full bundletool validation. Arbitrary protobuf files,
code/native/resource content in asset modules and shell-profileable releases
remain rejected. See `qa_shots/native/android-upload-release-20261002/receipt.json`
for actual artifact results and the preserved first rejection; host tests alone
never establish real artifact acceptance. The corrected current full-game
**1.0.0/build 4** now passes this actual offline gate and retains
`android_upload_artifact_verified_offline`, still `store_ready:false`. Play
registration, independent signing recovery, real devices/purchases and store
acceptance remain open. Its source hash matches the earlier full-game suite;
the new title is verified in bundled resources, not on an installed device.

Tool regressions (no engine, signing or devices):

```sh
python3 -m unittest discover -s tools/release -p 'test_*.py'
```

### iOS profile metadata is not signing approval

The Apple portal now has Waddle Wars' explicit App ID under the verified Ninja
Consulting, LLC team `V8MBW2V2C2`. After the owner's action-time approval on
October 1, the **Waddle Wars App Store** profile was generated and downloaded
from Apple (portal ID `DBYJX2DCPC`, expiry April 29, 2027). It uses the existing
distribution certificate; no certificate or private key was created or revoked.
Download alone is not signature, archive, or store acceptance. Verify the
profile's trust, exact metadata and existing identity match before installation
and manual signing.

`verify_ios_profile.py --decoded-plist` performs metadata-only checks and exits
**2** even on a match: CMS trust remains `UNVERIFIED`. Signed mode instead takes
`--mobileprovision`, an explicitly compiled `--cms-helper`, and its exact
`--cms-helper-sha256`. The narrow `verify_ios_profile_cms.c` helper uses Apple's
public CMS decoder and provisioning-policy factory (OID
`1.2.840.113635.100.1.56`), rejects unsigned/encrypted/nested inputs, verifies one
signer plus the Apple profile-signing chain, and disables network fetching.
Neither tool imports certificates, changes trust anchors, or uses private keys.
Only verified content enters the exact app/team/name, App Store flags, date and
public certificate fingerprint checks. Signed mode exits **0** on this profile
gate, **1** on rejection; it still reports `signing_authorized: false` and
`store_ready: false`. Revocation freshness is **NOT CHECKED OFFLINE**. Private-key
availability and signed archive acceptance are separate mandatory gates.

After the approved official profile download and trust validation, use explicit
manual signing on the generated Xcode project: `CODE_SIGN_STYLE=Manual`,
`DEVELOPMENT_TEAM=V8MBW2V2C2`, `CODE_SIGN_IDENTITY=Apple Distribution`, and the
verified `PROVISIONING_PROFILE_SPECIFIER`. Do not enable automatic provisioning
to bypass a mismatch. The exact Godot release-profile environment lookup has a
debug-variable bug, so prefer these explicit Xcode settings. Embedded-profile,
signature, entitlement and real archive validation remain mandatory.

Twenty synthetic profile tests pass; the complete release-tool suite now passes
86 tests with no skips. Actual profile signature/metadata verification and four
native rejection checks also pass, with offline-revocation limits. These are not
signed-archive acceptance. Receipt: `qa_shots/native/ios-profile-verified-20261001/receipt.json`.

The subsequent local manual Release archive succeeds after installing the
official missing Xcode platform support. Its standalone strict signature,
existing signer fingerprint, embedded profile and exact app/team entitlements
verify; debugging is disabled. StoreKit/auth framework linkage and binary
presence also verify. This archive is tied to source snapshot
`0ce96eea798d213140a23eadf9b8d60461e98c909c7c56f40da65379249818f7`.
Receipt: `qa_shots/native/ios-signing-20261001/receipt.json`. Canonical export now
removes only three unused blank permission-purpose strings before hashing;
nonblank declarations reject pending policy review. Fourteen focused host tests
pass, but fresh export/archive must verify warnings disappear. Existing archive
is unchanged. Complete local release-helper suite also passes 93 tests, zero
skips. IPA export, real device behavior,
TestFlight and store acceptance remain open. The canonical build helper still
exports the project only; it does not silently perform archive or upload steps.

Pinned local Fastlane entry points wrap these same guarded helpers. See
[FASTLANE.md](FASTLANE.md) for prepare/build/verification lanes and their limits.
No upload, automatic provisioning, key generation or promotion lane is enabled.

### Retained iOS candidate — October 2

The historical build 1 archive above was temporary and is now absent. Fresh
1.0.0/build 2 is retained under `~/Library/Application Support/WaddleWarsLaunchCandidates/`;
manual archive and strict signature/profile/entitlement verification pass using
the existing approved identity. The three unused permission declarations and
their warnings are absent. Subsequent local-only App Store distribution IPA
export also passes; all eleven runtime-resource hashes match the archive.
Receipts: `qa_shots/native/ios-signing-recovery-20261002/receipt.json` and
`qa_shots/native/ios-ipa-local-20261002/receipt.json`. Xcode's expired account-session
warning did not prevent export; browser App Store Connect login still works.
No upload or new key/profile occurred. Distribution IPA is not a development
sideload, real-device, TestFlight or store-acceptance pass. Those gates remain open.

### Receipt-bound local iOS archive and IPA

`build_ios_distribution.py` explicitly separates local archive and local IPA
export from the canonical unsigned Xcode-project export. Both operations require
fresh private outside-checkout outputs, exact existing public signer/profile
pins, unchanged export/runtime inventories and the pinned offline CMS helper.
No upload, automatic provisioning, account login, new key/profile or private-key
export is implemented. The archive uses manual signing with the exact public
certificate SHA1, profile UUID and team. Existing signing identity discovery is
metadata-only; normal Xcode code signing uses the authorized existing identity.

```sh
python3 tools/release/build_ios_distribution.py archive /absolute/ios-candidate /absolute/private-run \
  --receipt-sha256 EXACT_EXPORT_RECEIPT_SHA256 --source-sha256 EXACT_SOURCE_SHA256 \
  --team-id REALTEAMID --certificate-sha1 EXACT_PUBLIC_CERTIFICATE_SHA1 \
  --certificate-sha256 EXACT_PUBLIC_CERTIFICATE_SHA256 \
  --installed-profile /absolute/existing.mobileprovision --profile-sha256 EXACT_PROFILE_SHA256 \
  --cms-helper /absolute/existing/verify_ios_profile_cms --cms-helper-sha256 EXACT_HELPER_SHA256 \
  --xcodebuild /absolute/installed/xcodebuild

python3 tools/release/build_ios_distribution.py ipa /absolute/private-run \
  --archive-receipt-sha256 EXACT_VERIFIED_ARCHIVE_RECEIPT_SHA256 \
  --cms-helper /absolute/existing/verify_ios_profile_cms --cms-helper-sha256 EXACT_HELPER_SHA256 \
  --xcodebuild /absolute/installed/xcodebuild
```

`verify_ios_artifact.py` is the separate read-only gate. It verifies strict
signature, exact public certificate/profile/team/entitlements, ARM64 architecture,
edition-specific native SDK absence or commerce linkage, current launcher title
and the sole frozen export PCK.
IPA validation requires safe bounded ZIP paths and the same resource inventory,
plist semantics and executable bytes as the verified archive. Modes must match
except the identical, independently pinned regular `embedded.mobileprovision`
may tighten from 0644 to 0600; widening and other file-mode differences fail.
Only the
trailing code-signature payload and its size word may differ. Tool, source,
profile and artifact hashes are rechecked before acceptance. Xcode's canonical
compiled-empty localization is accepted only at its frozen neutral export path;
unknown/nonempty/alternate encodings are rejected. Inspection uses concrete
single-link binaries in the reviewed Xcode toolchain instead of multiply linked
OS dispatchers, with containment and binary hash rechecks. Verification does
not itself prove an Xcode invocation succeeded; orchestration requires exit zero
and the exact terminal success line independently. Failed outputs/logs remain.

Godot import-generated `.gd.uid` sidecars are recorded separately in
`import_metadata`, never folded into original source/prepared hashes. Only new
bounded `uid://` ASCII files adjacent to frozen prepared `.gd` scripts qualify.
For the already exported build 3, an explicit `import-metadata.json` supplement
binds the unchanged original receipt/source and those sidecars; it cannot coexist
with canonical metadata. Any extra, changed or missing runtime/export file fails.

Local archive/IPA receipts retain `store_ready:false`: they are not device,
TestFlight, App Store, purchase/restore/refund or privacy acceptance. Store
upload and public release remain separate actions.

### Full-game Android development candidate

`build_android_debug.py` is separate from the canonical release-signing path.
It requires the already-configured existing Godot debug keystore before any
engine import, pins the exact official engine, uses new retained snapshots and
isolated bounded Gradle caches, and exports an ARM64 APK with full game resources
and pinned billing integration. No key generation, device installation, SDK/JDK
download, license acceptance or upload occurs. Development receipts always remain
`development_only:true`, `store_ready:false`; debug signing is not release-key
continuity or Play purchase acceptance. A late structural failure preserves
earlier actual artifact/signature/resource evidence rather than claiming nothing
was exported. Verification-only retries recheck the same immutable APK without
another engine build. Default invocation plans only; choose a new destination.

The October 2 retained DEBUG APK passes signature/resources/dependencies and
16-KB ELF/zipalignment after a verifier-only correction. The old blanket RELRO
end rule was a false positive: whole-LOAD RELRO may end off a page boundary if
rounded protection touches no still-mutable or executable bytes. The checker
validates containment, segment sizes/overflow and both protection boundaries,
including adjacent LOADs. See [Bionic's whole-LOAD exception](https://android.googlesource.com/platform/bionic/+/android16-qpr2-release/linker/linker_phdr_16kib_compat.cpp#427)
and [page-rounded protection](https://android.googlesource.com/platform/bionic/+/android16-qpr2-release/linker/linker_phdr.cpp#1391).
Receipt: `qa_shots/native/android-relro-correction-20261002/receipt.json`.
No rebuild occurred; actual 16-KB runtime and release-signing gates remain open.

```sh
python3 tools/release/build_android_debug.py /absolute/new/android-debug-candidate
python3 tools/release/build_android_debug.py /absolute/new/android-debug-candidate --compile
python3 -m unittest discover -s tools/release -p 'test_android_debug.py'
```

For isolated web-commerce configuration prerequisites and their fail-closed
public-copy guard, see [sandbox preparation](../commerce/README.md). Production
commerce remains disabled; actual provider/device purchase/restore/refund proof
is still required.

### Unsigned Android integration QA

`build_android_integration_qa.py` provides a separate native-template packaging check while browser/device testing is unavailable. It never runs Godot or the game, exports game resources, accesses release keys, generates signing keys, installs to a device, accepts SDK licenses, or uploads anything. The canonical release helper's signing gate remains unchanged. The resulting unsigned AAB is **not a runnable Waddle Wars build** and must never be submitted.

The helper requires the exact installed Godot 4.7.1 Android source-template hash, pinned billing 3.3.0 release AAR/export-plugin hashes, SDK 36/build tools 36.1.0/NDK 29, and the configured JBR. It uses a fresh outside-checkout directory, isolated Gradle/Android user caches, a credential-free environment, two workers and a 2-GiB JVM heap. Compilation downloads Gradle 8.11.1 and official Maven dependencies into that isolated cache; SDK/JDK auto-download and signing are disabled. Missing prerequisites fail without installation or license acceptance.

Inspect the exact command without writes, then run only in a root-coordinated build window using a new destination:

```sh
python3 tools/release/build_android_integration_qa.py /tmp/NEW-waddle-android-integration-qa
python3 tools/release/build_android_integration_qa.py /tmp/NEW-waddle-android-integration-qa --compile
```

The preserved receipt verifies the **resolved**, not merely requested, Billing/Billing-KTX 9.1.0 artifacts, hashes their compiled dependencies, checks the merged singleton/permission/SDK manifest and provider DEX class, and inventories ARM64 ELF alignment findings. It remains `native_integration_only: true`, `game_resources_exported: false`, and `store_ready: false`. AAB 16-KB packaging, actual full-game export/linkage, signing continuity, real device lifecycle and real purchases remain separate mandatory gates. Existing QA directories are refused; preserve failures rather than overwriting them.

October 1 local evidence: the first attempt exposed the template ZIP's missing
empty install-time asset directory. The helper now creates that empty directory
without exporting game resources; eight host regressions pass. The fresh `r2`
attempt compiled successfully in 78.68 seconds with resolved Billing and
Billing-KTX 9.1.0, provider DEX, merged manifest and ARM64 libraries verified.
Preserved initial failure, successful receipt/log and unsigned AAB:
`qa_shots/native/android-integration-20261001/`. The AAB SHA-256 is
`1d3bb7540870fa7bee8eebe5c70ef5e9b0b20243fc2fadaa1070197ee52d82d2`.
This is native integration evidence only, not a playable game or store build.
The original compilation receipt records packaging as unchecked; a subsequent
read-only bundletool dump confirms `PAGE_ALIGNMENT_16K`. The historical checker
flagged RELRO end alignment in both libraries. This warning was not proof of a
runtime crash: rounded protection and subsequent writable segment placement
must be considered. No physical/emulated 16-KB-page runtime gate has passed.

## Historical full-scope launch evidence

The October 2 MVP scope at the top supersedes this original full-overhaul list.
Native accounts and purchases are disabled/deferred, so their sign-in, purchase
and deletion acceptance gates below are **not current MVP dependencies**. Web
behavior is unchanged. Device, listing/privacy, signing and store gates remain;
browser investigation remains bounded by the owner-approved stop gate, not the
historical soak mandate. `native_release.json` retains broader evidence gaps;
it does not override the current scope. Tie each applicable receipt to the
exact immutable build.

- Foreground Chrome/Safari performance, all biomes/courses, loading, death/retry, 15-minute soak, no visible freezes.
- Physical iPhone, iPad, and Android performance/lifecycle; safe areas and independent portrait/landscape layouts; pause/background/resume, audio interruptions, airplane mode, installation and save-preserving upgrades.
- StoreKit and Play Billing integrations, signed server verification, pending/cancel/error handling, restored ownership, refund/revocation reconciliation, and idempotent grants. No paid gameplay advantages. Native purchase UI remains unavailable until this passes.
- Real HTTPS privacy/support URLs, in-app privacy access, accurate App Privacy and Data Safety disclosures covering every SDK/backend, updated age-rating answers, and an owner-approved target audience remain MVP prerequisites. Account deletion is a prerequisite for any later account-enabled native release, not a requirement to implement disabled MVP accounts. Existing hosted web sign-in/deletion policy remains separate. Sign-out is not account deletion.
- iOS sign-in now requires the compiled `ASWebAuthenticationSession` helper, with no default-browser fallback. Its fixed credential-free return callback does not authenticate the player; server PKCE/session verification remains authoritative. Actual app linkage, configured Clerk/CSP/OAuth flow, cancellation, expiry and account switching still require device acceptance. Passing source/contract tests does not establish compliant iOS UX. [Apple authentication session documentation](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession), [account-deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/).
- Original 1024-pixel opaque iOS icon, Play icon/feature graphic, actual device screenshots; store listing claims reviewed against the shipped build. `store_listing.en-US.json` is an unsubmitted draft, not a ready listing.
- Correct App Store Connect/Play applications, real developer memberships, agreements, tax/bank setup, app signing continuity, internal Play test and TestFlight receipts. New personal Play accounts may have additional closed-testing requirements; inspect the actual account.

## Privacy inventory to verify against the final build

Local saves contain progression, cosmetics, settings, and time-trial ghosts.
Local files alone are not evidence of server data collection. Current native
MVP guards prevent sign-in, shop refresh, purchase and restore dispatch; no
account or payment collection should be asserted from the mere presence of
deferred source. However, native public leaderboard reads remain reachable:
`leaderboard_menu.gd` calls `LeaderboardClient.fetch_board()`, whose non-web
transport uses HTTPRequest. These requests may produce hosting/IP logs even
without an account. Review the actual hosting policy and native SDK startup
before choosing App Privacy or Data Safety answers. Do not claim "no data
collected" from the offline-core/no-IAP scope alone.

The bounded native startup source audit found no reachable automatic account/
payment dispatch: autoload startup is local, Android billing connection requires
explicit adapter startup, and iOS registration installs handlers without starting
the provider. A later pinned-AAR bytecode inspection confirms the plugin constructor
initializes local fields, with no plugin-owned automatic startup dispatch;
inherited engine behavior, SDK internals and actual traffic remain unverified.
See `native_privacy_inventory.json` and `privacy_review.md` for actual candidate
permissions, dependency metadata and iOS privacy-manifest evidence. This is not
a final-binary network/privacy certification or an approved Data Safety answer.

Optional **web** Clerk sign-in transmits account identifiers, profile/display
name, leaderboard results and cloud saves to Clerk/Cloudflare. The deferred
native PKCE flow uses an iOS authentication session or Android browser, with
session tokens in memory; production configuration/device acceptance remains
unverified and is not an MVP dependency. Deferred purchases would add store/
Stripe transaction identifiers and entitlement records. Review collection and
retention before enabling those features. No advertising SDK is currently part
of this source inventory; this is not a completed final-binary privacy audit.

Account deletion needs coordinated Clerk identity, D1 score/profile/save, native-session and linked local-cache cleanup, plus durable retries and suppression of stale-token/cloud-upload writes. These are ordinary implementation requirements, not unresolved product choices. Owner/legal input is needed only for lawful retention categories, purposes and durations for financial/fraud records, logs and backups; applicable fulfillment deadlines; and the documented post-deletion purchase-restoration policy. Do not assign arbitrary retention periods or silently destroy purchase proof required for legitimate refunds/restoration.

Backend retirement and status-recovery foundations exist in
`leaderboard/src/account_lifecycle.mjs` and migrations
`0006_account_retirement.sql` / `0007_deletion_receipts.sql`, but client/server
features remain **disabled and undeployed**. Apply the base schema and all
migrations, including `0007_deletion_receipts.sql`, before any enabled Worker
deployment: normal authentication requires the retirement table. No existing live
database was modified. A durable subject marker and 16 atomic SQL mutation guards
prevent old JWTs, delayed profile/save/score writes, anonymous PKCE approval, and payment
refund reversals from resurrecting a retired subject. Personal game rows and
native-session/request rows are erased in one transaction. Existing financial
proof and store mappings remain quarantined pending the retention decisions above;
verified refund/dispute updates may still update same-subject non-grant evidence.
Retirement is not a provider-refund tombstone and cannot be undone by a reversal.

Prepared API: fresh authenticated `POST /api/account/delete` accepts exactly two
fields: `confirm` set to `DELETE_ACCOUNT`, and `recovery_receipt` containing a
32-byte CSPRNG receipt encoded as 64 lowercase hexadecimal characters. The client
durably persists the receipt and pending marker together before dispatch; a
failed persistence step sends no request. The server stores only its bound
SHA-256 digest, transactionally with retirement and personal-data erasure.
Authenticated `GET /api/account/deletion` remains available. Required feature flag,
configured Clerk issuer/secret, explicit origin policy and deletion rate limiter
fail closed. Fresh JWT issuance is required, but **does not prove password/MFA
re-entry**. The deletion route intentionally uses raw verified auth for idempotent
retry after retirement; all ordinary game/commerce routes reject retired subjects.
Responses are no-store and do not disclose credentials or raw provider errors.

Signed-out or expired-auth recovery uses status-only
`GET /api/account/deletion/receipt`, with the capability only in the
`X-Waddle-Deletion-Receipt` header: no JWT, cookies, query token, redirect or
provider call. Unknown receipts return `404 status_unavailable` and cannot
unpause an ambiguous pending request. Only positive retirement confirmation
repairs the receipt owner's local purchase cache; earned offline progress and
other accounts remain intact. Legacy requests without a persisted receipt cannot
retroactively recover an already deleted identity. See the
[canonical account-deletion contract](../commerce/README.md) for transport,
durability and recovery limits.

Identity erasure first confirms the exact Clerk user with the configured backend
credential. A first provider 404 is not treated as proof of erasure: it could be a
wrong-instance credential. Subsequent DELETE 404 is idempotent only after verified
identity observation with the same issuer/key binding. Binding digest stays
internal, never logged or returned. Credential rotation requires fresh observation.
Provider failure keeps retirement intact and identity pending. A bounded durable
retry helper does not depend on a device token, but **no scheduler/cadence is
configured**. Every response explicitly keeps `deletion_complete:false` while
retention/full lifecycle acceptance is unfinished. D1 documents transactional
batch rollback; provider user lookup/deletion uses Clerk's Backend API.
[D1 batch transactions](https://developers.cloudflare.com/d1/worker-api/d1-database/#batch),
[Clerk Backend API](https://clerk.com/docs/reference/backend-api).

Shared in-app destructive confirmation, account-isolated local purchase-cache
cleanup (main save, backup and owned staging files), and the standalone public
`/account/delete` request page are implemented locally, not launch acceptance.
The public page remains undeployed; client/server deletion switches remain off.
Still required: public-page deployment and real SDK/provider acceptance,
disclosed retention/restoration policy, provider-bound retry scheduler, real
identity-deletion tests, and stale-session/device acceptance. A provider
acknowledgment already in flight cannot be made atomic with D1 retirement; no new
server grant or checkout URL may be delivered afterward. Local synthetic tests
are not a completed store-policy
certification. Do not enable `ACCOUNT_DELETION_ENABLED` yet.

Cloud sync now excludes local per-account `commerce` caches in the client and
backend, plus the reserved top-level `account_deletion`,
`account_deletion_receipt`, `account_deletion_receipts` and
`account_deletion_recovery_owner` fields. Adopting old cloud progress cannot
introduce cached purchase grants or deletion capabilities.
Current device caches remain available offline, and earned progress keeps its
existing save format. Legacy server responses are filtered, not purged from D1.
Local retired-owner purchase-cache repair does not prove erasure of provider,
financial/log/backup records or complete the remaining retention workflow.
No production data was altered by the local implementation/tests.

## Current primary requirements

Verified 2026-10-01. Recheck before submission; these are current floors, not permanent policy assumptions.

- New Play apps/updates target API 36 after August 31, 2026. [Google Play target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en).
- Native libraries need 16-KB ELF and packaging compatibility, plus runtime testing. [Android 16-KB guidance](https://developer.android.com/guide/practices/page-sizes).
- App Store uploads require Xcode 26/iOS 26 SDK or later, and current iOS deployment floor is 13. Host inspection found Xcode 26.6/iOS SDK 26.5. [Apple submission requirements](https://developer.apple.com/news/upcoming-requirements/).
- Godot requires Gradle for AAB and genuine signing configuration; installed 4.7.1 `config.gradle` pins AGP 8.6.1, compile/target SDK 36, build tools 36.1.0, NDK 29.0.14206865 and Java 17 source/bytecode compatibility. Its `validateJavaVersion` checks Java 17 as a minimum, not an exact runtime pin; the wrapper uses Gradle 8.11.1. Current Godot editor points to Android Studio's JBR 21. NDK 29.0.14206865 was installed and its compiler verified locally on October 1; full export compatibility still needs an actual build. This installed template is authoritative for the candidate; the generic setup page lists older SDK versions. [Godot Android export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html), [Android export options](https://docs.godotengine.org/en/4.7/classes/class_editorexportplatformandroid.html).
- iOS export requires macOS/Xcode, real Team ID and bundle ID; project-only export separates Godot export from Xcode archive/signing. [Godot iOS export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html), [iOS export options](https://docs.godotengine.org/en/4.7/classes/class_editorexportplatformios.html).
- Digital goods, privacy links, privacy disclosures, age/content ratings and account deletion must match the final feature set. [Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/), [Google user data policy](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en), [Google account deletion](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en).

## Browser worker experiment (QA only)

`web_worker_template.lock.json` pins official Godot 4.7.1 source and Emsdk 4.0.11, matching the exact engine's own web-build workflow. The isolated SDK installation lives under a QA scratch directory and writes its `.emscripten` there; do not add it to shell startup files or change production presets. A source-build window must be coordinated with foreground browser timing tests.

`build_web_worker.py` validates pinned Git commits, exact Emscripten/SCons versions, and local SDK configuration before running a fixed four-job build. Default `--qa-variant official` requires clean tracked Godot source. The sole reviewed alternative, `--qa-variant eval_main_thread`, requires exactly one changed file and pinned upstream, patched, and patch-file hashes; unrelated source or mode changes are refused. It runs the eval contract checks before compiling and rechecks source identity afterward. Explicit `--compile` and a new QA output directory are required. Exact command/time/status/log and source hashes go in the receipt; the resulting ZIP is copied aside before another build can overwrite the engine source's generic output filename. A `compiled_qa_unverified` receipt never implies browser acceptance or production readiness.

Stock worker QA exposed `ReferenceError: window is not defined` in `JavaScriptBridge.eval`. The one-line patch adds Emscripten's `godot_js_eval__proxy: 'sync'`, matching the already-proxied object/interface calls and byte-buffer transfer protocol. This preserves the browser global context without a fake `window=self` shim. Node VM checks reproduce the original failure and preserve scalar/string/NIL/error/local-eval and shared-byte-buffer contracts, but do not prove native thread safety. A real browser preflight must exercise DOM, scalar/string, and `PackedByteArray` results before gameplay timing. No OffscreenCanvas change is included; GL operations can still execute on the browser UI thread.

```sh
node tools/release/test_web_eval_proxy.mjs /absolute/exact/godot/platform/web/js/libs/library_godot_javascript_singleton.js
```

The engine build needs `platform=web target=template_release threads=yes proxy_to_pthread=yes dlink_enabled=no`. `threads=no` or GDExtension dynamic linking silently disables the worker option, so neither is a valid A/B. Keep 3D, OpenGL3, GDScript, font shaping, physics, and resource loaders enabled; lowering art or disabling game systems would confound the test. Explicit `arch=wasm32` supports a browser-compatibility candidate; `arch=wasm64` matches the current upstream threaded build. Pick and record one architecture for both the regular-threaded control and worker candidate.

The custom ZIP must be selected only in a copied QA export preset (`custom_template/release`, `variant/thread_support=true`, `variant/extensions_support=false`). Serve it with genuine COOP/COEP isolation and verify `crossOriginIsolated`, SharedArrayBuffer, audio, browser-JS auth/purchases, input, quit and context loss. Enabling the editor's thread toggle alone does not compile `PROXY_TO_PTHREAD` into an installed template. Moving Godot's main loop to a worker can isolate UI blocking, but DOM/JavaScript/WebGL operations still proxy to the browser main thread: this is a testable hypothesis, not a performance guarantee or shipping change.

Primary references: exact source `platform/web/detect.py`, `platform/web/web_main.cpp`, `.github/workflows/web_builds.yml`; [official Emsdk installation](https://emscripten.org/docs/getting_started/downloads.html), [Emscripten pthreads](https://emscripten.org/docs/porting/pthreads.html).
