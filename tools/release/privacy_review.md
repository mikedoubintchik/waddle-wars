# Mobile MVP privacy and support review

State: **mobile privacy/support pages published; store declarations not submitted**.
Scope: free iOS/Android MVP only. Final signed-package/runtime collection and
store audience/privacy answers remain separate unresolved gates. Historical
checkpoints below retain their original state; this current publication section
supersedes their draft-page and null-URL statements only.

## Published mobile policy and support pages October 3

The owner authorized parallel completion/publication of MVP privacy and support.
Only the two new `native/privacy.html` and `native/support.html` R2 keys were
created using the existing task hosting configuration. The game entry, Worker,
leaderboard, account settings and payments are unchanged. R2 readback of the
game entry before/after remains SHA-256
`be80b15e3e428e1312dffedd3a351ef9d3b50d7f4a4f81feea821109c2bbf95c`.

- [Mobile privacy policy](https://waddlewars.ninjaconsulting.ai/native/privacy.html),
  effective October 3, 2026, SHA-256
  `1183d297b36a3cc708e890614b14c3a49dd3c87a706977f0b4c43b4e583f07c6`.
- [Mobile support](https://waddlewars.ninjaconsulting.ai/native/support.html),
  SHA-256 `7f2717899dd75e7555eeb14f371aa0ced65401ada49eee066b6a79c9c9d88032`.

Both anonymous public HTTPS responses return 200 and `text/html; charset=utf-8`;
public bodies and stored R2 objects match local source bytes exactly. Neither
capture contains a Set-Cookie header or an injected beacon. Sources have no
scripts, forms, remote images or fonts, and their anchors/cross-links resolve.
Self-contained inline styling avoids the old deployed Worker's CSS MIME gap;
no Worker deployment or stylesheet upload was required. Phone rendering still
needs a supported browser preview; source/HTTP verification is not visual QA.

The earlier deployed game-root receipt proves a Cloudflare beacon insertion.
The policy therefore explains conditional website-beacon processing, separate
from native game play, rather than falsely claiming every information-page view
ran analytics or that live hosting never adds scripts. Current primary provider
sources were reviewed: [Cloudflare privacy](https://www.cloudflare.com/privacypolicy/),
[published DPA](https://www.cloudflare.com/cloudflare-customer-dpa/),
[beacon collection](https://developers.cloudflare.com/web-analytics/data-metrics/data-origin-and-collection/)
and [report dimensions](https://developers.cloudflare.com/web-analytics/data-metrics/dimensions/).
Provider retention/record access remain bounded by purpose, law and available
records; the publisher's 90-day support deadline is not extended to providers.

Current source review accounts for local saves/settings/ghosts, explicitly chosen
leaderboard GETs, user-selected clipboard sharing, external links and support
email. Native sign-in/cloud/score submission/purchase guards remain disabled;
the prior free Android14/iOS12 static inventories are preserved below. Publishing
the policy does not establish final SDK behavior, a runtime traffic capture,
accepted store labels, age/audience classification or signed current binaries.
The policy makes no child-directed or zero-collection declaration. Parents have
a support contact for information a child sends, without inventing an audience.

Immutable publication evidence:
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/native-policy-publication-20261003.gi6f8U/publication-receipt.json`.
The initial policy capture is retained separately; its final wording was corrected
to make beacon execution conditional before the final readback. Existing page
fixtures now bind published state, exact source pins, HTTP/readback and provider
limits; only AST parsing has run. Regression assertions remain deferred to the
final gate. Native in-app links and their affected runtime validation remain open.

## Current Android build 14 free MVP review

October 3 static inspection covers the free-MVP candidate at
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-free-mvp-20261003-b14.YnNWir/candidate`,
version 1.0.0 (14), source SHA-256
`cc89e3d732a9f8ccdf49df130975abec84c57438414dd373c5a2fff640593606`.
The retained `project/build/waddle-wars-unsigned.aab` matches SHA-256
`a21e45b92d9d243dad8821e9e05b900f85df6139c6b70d138cd42f2050688d1f`.
Its frozen `candidate/receipt.json` matches SHA-256
`68dc37478f4a1776e1a16ba556f658c6220c85b99163dfb319ed8ee8e47d53d9`,
remains `android_unsigned_awaiting_upload_signature`, and
records the pre-signing filename `waddle-wars.aab`; the retained file was renamed,
not rebuilt. `prepared-upload-signing.json` records
`launch_failed_preserved_no_automatic_retry`: the helper failed at
`reading_app_specific_keychain_password`, with `store_ready=false` and
`uploaded=false`. No signed-package or store acceptance follows.

- The actual AAB base manifest declares **Internet only** and
  `allowBackup=false`. Billing, network-state, location and advertising-ID
  permissions are absent. ProfileInstaller startup and the nonexported
  FileProvider remain; the ProfileInstaller receiver requires `DUMP`.
- Dependency metadata strings and DEX markers no longer identify Billing,
  DataTransport, Firebase encoders, or GMS location/places. Remaining inspected
  libraries are Godot, AndroidX UI/lifecycle/storage/startup/ProfileInstaller,
  Kotlin/coroutines, Guava `ListenableFuture`, and annotations. This is static
  inspection, not a decoded dependency graph or runtime traffic measurement.
- The actual asset-pack manifest declares **install-time** delivery. No Play
  Asset Delivery runtime Library/API was identified in the dependency records,
  Godot runtime JAR or DEX markers; exact Godot source reads assets through
  Android `AssetManager`. Google's [integration guidance](https://developer.android.com/guide/playcore/asset-delivery/integrate-java)
  distinguishes this access from the optional runtime Library for fast-follow
  and on-demand packs. Do not infer that Library's documented device-metadata
  collection merely from install-time packaging. Its separate
  [data-handling table](https://developer.android.com/guide/playcore/asset-delivery)
  applies when the Library is used, not as proof of Waddle runtime behavior.
- [ProfileInstaller](https://developer.android.com/reference/androidx/profileinstaller/ProfileInstaller)
  installs bundled profiles into local ART profile storage; its presence alone
  does not establish diagnostics uploads. Native accounts/commerce remain off,
  but optional leaderboard HTTPS reads and host/provider processing remain.

The Android 7/8 findings below are historical and do not describe this free
candidate. **No data collected** remains unresolved: final disclosures must
reflect actual off-device app/provider processing, not SDK names or permission
absence. [Google's Data safety definitions](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en)
distinguish local processing, off-device collection and service-provider sharing.
This review does not approve account-specific practices, policy publication,
audience declarations or store answers.

## Current iOS build 12 free MVP static review

The existing free-MVP export and unsigned linked app use the same
`cc89e3d732a9f8ccdf49df130975abec84c57438414dd373c5a2fff640593606`
source as Android14 above. The candidate is at
`/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-free-mvp-device-20261003-b12.unIe5p/candidate`.
Its frozen `receipt.json` remains `exported_unverified`, with SHA-256
`82554e93a9a7fc0baff5a992be63d4739fe14b46e18c2546f30fc48bb78e07b3`.
The separate `linked-app-static-review/receipt.json` records
`linked_unsigned_app_static_review_passed`, SHA-256
`0bff73229a2c55de6d2c0d22acebd7f3d47b4e33abe9977b7a9304f9936cdf7a`.
That receipt explicitly records signing and gameplay as not passed and
`store_ready=false`.

The retained linked ARM64 executable, PCK and `PrivacyInfo.xcprivacy` hashes
were rechecked against those receipts, without executing or modifying the app:

- Executable: `69a76a599e4b70a8a3d060cc4fe44826d62aef8d360c866e2c087593100f3824`.
- PCK: `6235c28b69c9c72500c2a335752ad16a7052ef07516f6854104ac0190513a2ee`.
- Privacy manifest: `7b856fa8cdbb2d03e861eac7e1ca7531559651ee092b736e49e360345fc08e7f`.

The linked-app static receipt finds exactly FileTimestamp `C617.1` and
SystemBootTime `35F9.1`, tracking declared false, and no disk-space category.
Its inspected capacity imports/keys and deferred billing/auth bridge tokens and
frameworks are absent; the linked PCK and manifest match the export. These are
bounded static findings for the prepared free edition, not proof of no
off-device processing, SDK runtime behavior, signed final-bundle acceptance or
approved App Privacy answers. Historical iOS5/6/9 manifest findings below remain
unchanged and do not describe this unsigned linked app.

`native_privacy_inventory.json` now retains its original top-level Android7/iOS5
observations and separately records this Android14/iOS12 static checkpoint.
Both free candidates predate the covered-background runtime
`fdb9c3f702bb621a8a495aca4392b5f0e270713ce128007f72981eaab3bf1a1c`;
neither receipt establishes acceptance of that newer code. Runtime traffic,
host/provider handling, final disclosures and age/audience review remain open.
No new build, test, signing attempt, policy publication or store submission is
part of this reconciliation.

## Historical signed iOS 9 manifest reconciliation

October 3 current-artifact reconciliation: signed iOS9 archive manifest contains
FileTimestamp `C617.1` and SystemBootTime `35F9.1`, matching the retained IPA
verification and the independently inspected unpacked IPA. Manifest SHA-256 is
`dd84f00c6606da86523cb14fa9f66b3b37abc1dfb9ed7f9ba005d3d99316e256`.
Both actual build9 Info.plists omit `godot_cmdline`. The file/timer correction is
therefore included, not merely a future preset. DiskSpace still declares
`E174.1` and `85F4.1`; eligible shipped use remains unestablished. This narrow
artifact fact does not approve those reasons, SDK traffic, privacy/store answers
or native acceptance. No package rebuilt or changed.
Do not copy the separate browser-account or deferred-purchase policy into mobile
disclosures. Do not interpret this worksheet as legal approval or binary acceptance.

## Published page locations

- `web/native/privacy.html` → published
  `https://waddlewars.ninjaconsulting.ai/native/privacy.html`
- `web/native/support.html` → published
  `https://waddlewars.ninjaconsulting.ai/native/support.html`
- Inline styles in each published page; `web/native/policy.css` remains a local
  historical stylesheet and is not a live dependency.

No scripts, forms, remote fonts, tracking pixels, or embedded services are part
of these page sources. Effective-date content replaces draft notices and review
placeholders. Public HTTPS/readback passes above allow the store worker to fill
the actual URLs; doing so does not approve collection/audience declarations.

### Confirmed publisher and public contact — October 2

The owner authorized reuse of Chancey's publisher, then explicitly selected
**ninjaconsultingllc@gmail.com** for Waddle Wars. Current local listing and both
unpublished pages use **Ninja Consulting LLC** and that public support/privacy
email. This is explicit contact authorization, not an inference from a login.
Chancey's `chancey-app/fastlane/metadata/copyright.txt` records the publisher;
its [public Play listing](https://play.google.com/store/apps/details?id=app.chancey.io&hl=en_US)
also identifies Ninja Consulting LLC. Chancey's original support email is not
the selected Waddle contact. No Chancey age, collection or retention claims were
copied. Portal fields and public pages were not updated by this local change.

The final contact-draft regression passes **20 tests / 0 skips / 0 failures**,
terminal 0, using `test_native_release.py`. The local listing SHA-256 is
`5ca6d2d1bedac959ae7545e958da47bd2a28b542c51826b26f6fe9f7492730c4`.
That earlier contact-only checkpoint did not establish support practices.
The subsequent owner explicitly confirms personally handling support and
delegates selection of a regular retention policy. Draft pages now specify
deleting publisher active-mailbox correspondence within **90 days of resolution**,
with limited necessary legal/fraud/security records and documented holds.
`support_retention.md` defines monthly deadline review and excludes unrelated
shared-mailbox mail. Google provider processing/backups are separate; no backup
deletion deadline is promised. Focused host regressions pass **23/23**, zero
skips/failures. No Gmail change, automation, publication or final policy approval.

## Source-backed data inventory

| Flow | Current evidence | Disclosure status |
| --- | --- | --- |
| Local progress, cosmetics, results, runner missions, settings, ghosts | `scripts/save/save_manager.gd`, `scripts/save/settings_manager.gd`; mobile cloud/auth entry points disabled; actual Android14 AAB manifest `allowBackup=false` | On-device storage; Android automatic app-data backup disabled. iOS/device backups are separate. No game-cloud upload claim. |
| Public leaderboard reads | `leaderboard_menu.gd` opens/selects a board; `leaderboard_client.gd:fetch_board` sends mode/course/limit, empty body and empty native token | Online requests occur when opening/using Leaderboard, including retries/tab changes/layout rebuilds. Not app-launch polling. |
| Public leaderboard backend | `leaderboard/src/worker.js` GET reads scores from D1 and returns entries; signed-out `me:null` | No IP database-write path found in this handler. This does **not** establish Cloudflare logging practices. |
| Host/request logs | Live production dashboards show Workers Logs/Traces disabled for both Waddle hosts; scoped observability views show no destination and Logpush disabled | Named per-service settings established October 2. Public provider access/deletion limits are bounded in the October 3 clarification below; account-specific record availability, runtime practices and final store answers remain **unverified**. |
| Support email | Owner selected `ninjaconsultingllc@gmail.com`, personally handles support and delegated retention policy; draft pages and `support_retention.md` agree | Publisher handling and 90-days-after-resolution active-mailbox policy resolved; legal/fraud/security holds limited. Actual past deletion and Google processing/backups are not verified or promised. |
| Native billing/auth startup | Current free snapshots omit deferred billing/auth SDK sources; native accounts, shop, purchase and restore entry points remain off. Android14 static package findings supersede the historical billing-constructor review. | No native account/commerce collection established for this edition. Remaining inherited engine/framework behavior and optional leaderboard host/provider processing are not proven zero; actual traffic and final disclosures remain **unverified**. |
| Browser accounts/cloud/purchases | Separate web/deferred source exists | Not enabled native MVP features. Do not claim browser-account deletion by deleting mobile storage. |

## Historical Android 7 and iOS 5 candidate metadata

`native_privacy_inventory.json` records hashes and exact findings for the retained
`b316cd77…` candidates, before the subsequent runner touch-Pause fix. Original
candidates were not altered or executed. This is submission preparation, not
signing, phone acceptance, a traffic capture or a completed collection audit.

- Android7 unsigned AAB hash still matches its frozen export. Actual merged
  permissions are Internet, network state, Play billing and the app's signature-only
  receiver permission. No camera, microphone, location, contacts, storage or
  advertising-ID permission found. Backup and shell profiling are disabled.
- Billing9.1.0, DataTransport, Firebase **encoders**, Play Services location19.0.0
  and places-placereport17.0.0 remain packaged. No Ads/Firebase Analytics/
  Crashlytics dependency identified in the decoded dependency list. Those
  observations neither prove collection nor prove zero collection; an SDK package
  name is not a runtime data-flow measurement.
- Android startup includes ProfileInstaller; billing/GMS activities, FileProvider
  and DataTransport components are non-exported. The ProfileInstaller receiver is
  exported but protected by the platform `DUMP` permission. No permission or SDK
  was stripped to obtain a clean-looking inventory.
- iOS5 export includes `PrivacyInfo.xcprivacy`, referenced in the app's Resources
  phase, with tracking false and file-timestamp, system-boot-time and disk-space
  reason declarations. The stamped Info.plist has no camera/microphone/photo/
  location/tracking usage-purpose declarations; entitlements are empty. Existing
  Godot/MoltenVK and StoreKit/auth-helper linkage remains in the unsigned project.
  An absent collected-data key or a tracking-false declaration is not evidence
  that hosting/support/SDKs collect nothing.
- Confirm declared required-reason uses and manifest placement in the accepted
  signed app/archive after restart; an exported resource-phase reference alone
  does not prove the final bundle. [Apple required-reason API guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api),
  [third-party SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/).

### Historical signed Android 8 and iOS 6 checkpoint

Signing access recovered after the owner-confirmed restart. Current accepted
packages use the preceding accepted 524-file runtime
`2d3518aada39b7ef949578a3c7d0873d7e5cf1bda60c324405fc895f0ea67d52`.
The historical top-level entries in `native_privacy_inventory.json` remain
unchanged; they describe builds 7/5, not the packages below. This new inspection is read-only static
metadata, with no app execution, credentials, traffic, build or deployment.

- **Android 8** signed AAB:
  `android-mvp-release-20261002-b8/project/build/waddle-wars.aab` under
  `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/`.
  Actual SHA-256 matches
  `57d09a087d17d6b5188ff30547a30519c5350549f64764eb71f02d3e97386598`.
  Pinned bundletool's stdout-only manifest/dependency dump exits 0. The actual
  permissions remain Internet, network state, Play billing and the app's
  signature-only receiver permission; no camera, microphone, location, contacts,
  storage or advertising-ID permission was found. Backup and shell profiling
  remain disabled. Manifest protobuf SHA-256:
  `5a86ac5dda52b9c1655a637aeedf61efd1b167656987f8003050d33a84e2134b`;
  dependency protobuf SHA-256:
  `a1028d6f44dce0015e3745352fff1af01a33dbf1fa157bdd1a36db12c03d0af7`.
  Actual Billing 9.1.0, DataTransport, Firebase encoders and GMS location/places
  dependencies remain packaged; no named Ads/Analytics/Crashlytics dependency
  was identified. Startup metadata names ProfileInstallerInitializer; prior
  nonexported/DUMP-protected component findings remain. The final release AAR
  matches the previously reviewed `b667b4ae…` plugin bytes. This establishes
  neither zero collection nor runtime SDK behavior.
- **iOS 6** accepted archive and IPA:
  `ios-mvp-archive-20261002-b6-final/WaddleWars-build6.xcarchive` and sibling
  `ipa-export/waddlewars.ipa` under the same candidate root. Actual IPA SHA-256
  matches
  `4508c700c68ddc44b19963cbd2bc6cd6fc9272a112c8e25e68663f84838f6dc1`.
  Both final app bundles contain exactly one byte-identical 990-byte
  `PrivacyInfo.xcprivacy`, SHA-256
  `4b61978794a0d6042d6fb5751bf9474cded649ab89956a1304667a1f0260ab2e`.
  Final-bundle manifest placement is now established. Tracking is declared false;
  timestamp/boot/disk reason values match the historical inventory above.
  Collected-data and tracking-domain keys are absent; that is not a no-collection
  audit. Actual plists have no usage-purpose, ATS, Bonjour, background-mode or
  application-query-scheme keys; the existing auth callback URL scheme remains
  packaged although native auth entry points are disabled. Both identify 1.0.0
  (6), iOS 15 minimum. Archive Info.plist SHA-256:
  `070b0548d6dd26d2ca73f442280a4c3d7785d01222a73e30893459c553692a29`;
  IPA Info.plist SHA-256:
  `2528d1ba164b5141d47ed823c012e74bd910e1f9feddda3ecbe3b5fd24506333`.
  These match the accepted receipts and are semantically equal, not
  byte-identical. Existing offline verification binds StoreKit,
  AuthenticationServices and native bridge linkage; no verifier rerun was needed.

Required-reason **actual use**, SDK/runtime traffic, host/support logging and
retention, age/audience and truthful store disclosures remain
open. Offline signature/static inspection is not signed-device or store
acceptance. See `qa_shots/native/mvp-signing-restart-20261002/REVIEW.md` for
accepted package provenance; do not rebuild unchanged packages for this review.

### Subsequent bounded required-reason use review

App timers use `Time.get_ticks_msec/usec()` for swipe intervals, power-ups,
loading watchdogs, construction budgets and animation. Local FileAccess/
DirAccess use covers `user://` saves/settings/ghosts and bundled `res://` assets;
no direct timestamp/capacity query or display was established in inspected
app/native bridge source. The pinned accepted executable imports `stat`/`fstat`/
`lstat`, `statvfs` and monotonic clocks, narrowing the engine-review gap without
proving actual calls or eligible purposes.

Apple's current [reason definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)
make the distinction material: elapsed timers and app-container metadata have
relevant reasons, but `DDA9.1`/`85F4.1` require timestamp/disk displays and
`E174.1` requires a capacity check affecting user-visible behavior. Those
display/check purposes were not established. Do not promote stock exporter
defaults or imported symbols to reason-use approval. Reconcile exact engine/
framework call paths and reason masks before the next iOS candidate, without
inventing a feature or stripping an API solely to hide the issue. No manifest
or preset changed in this review. Details and exact executable/tool provenance:
`qa_shots/native/privacy-readonly-20261002-1928Z/REVIEW.md`.

### Subsequent preset correction — file/timer reasons only

Exact pinned engine source is now available. Apple's elapsed clock implementation
subtracts process start from `mach_absolute_time`; app-local file existence and
metadata queries use `stat`. Future presets explicitly select `C617.1` and
`35F9.1`, not a timestamp-display reason. Sources:
[Godot elapsed clock](https://raw.githubusercontent.com/godotengine/godot/a13da4feb8d8aefc283c3763d33a2f170a18d541/drivers/unix/os_unix.cpp),
[local file access](https://raw.githubusercontent.com/godotengine/godot/a13da4feb8d8aefc283c3763d33a2f170a18d541/drivers/unix/file_access_unix.cpp).

[Pinned exporter](https://raw.githubusercontent.com/godotengine/godot/a13da4feb8d8aefc283c3763d33a2f170a18d541/editor/export/editor_export_platform_apple_embedded.cpp)
defines ordered reason arrays and emits entries selected by `1 << k`:
file mask 2 is `C617.1`; boot mask 1 is `35F9.1`. Disk defaults remain inherited
and **unapproved**, not silently removed. The inspected
[capacity implementation](https://raw.githubusercontent.com/godotengine/godot/a13da4feb8d8aefc283c3763d33a2f170a18d541/drivers/unix/dir_access_unix.cpp)
uses `statvfs`, but an eligible MVP call/purpose remains unestablished. Resolve
that gate before final candidate preparation; do not invent behavior to justify it.

Focused host regressions pass **21/21**, zero skips, after the new mask case
reproduced both omissions. This is partial configuration correction, not complete
data-use, signed-manifest, device or store approval. Accepted iOS6 packages and
their default manifest remain unchanged. No rebuild/upload occurred. Receipt:
`qa_shots/native/privacy-preset-20261002-1939Z/REVIEW.md`.

Bounded follow-up finds a real capacity-query caller in
[MovieWriter::begin](https://github.com/godotengine/godot/blob/a13da4feb8d8aefc283c3763d33a2f170a18d541/servers/movie_writer/movie_writer.cpp#L95).
It compares free space to 10 GiB and formats a low-space warning; recording
proceeds. [Startup](https://github.com/godotengine/godot/blob/a13da4feb8d8aefc283c3763d33a2f170a18d541/main/main.cpp#L1841)
requires a nonempty movie-output path and matching writer. No such activation
was established for native Waddle; bounded project/script/tool search finds no
`write-movie`, `movie_writer` or `set_movie_path` setting/call. This is a located
engine purpose, not an eligible shipped-use conclusion. No API/reason removed.

The unpublished privacy page now includes the dated per-service logging facts,
distinguishes Cloudflare provider processing, and links its
[policy](https://www.cloudflare.com/privacypolicy/). It does not promise zero
provider processing or a fixed deletion deadline. Provider access/deletion
limits and actual support-mailbox practices remain open. Focused page/preparation
regressions pass **22/22**, zero skips. No website/portal publish or native export;
Chrome store editing stopped at an extension-popup blocker. Receipt:
`qa_shots/native/privacy-host-draft-20261002-1944Z/REVIEW.md`.

### Final bounded exact-source audit — October 2, 19:51 UTC

One official exact-commit source archive was downloaded/read, never executed or
built. Scratch retained at `/private/var/tmp/waddle-godot-disk-audit.Hm9Jr7`;
archive SHA-256 `98c5c1c101d15d43de5e3dca81cfb57ef3698495d67eeaf5e34db739b751bbb9`.
Sole root is `godot-a13da4feb8d8aefc283c3763d33a2f170a18d541`; 15,209 entries,
no unexpected root/traversal names. Complete hidden/no-ignore source search
finds one nonbinding capacity caller: MovieWriter queries at actual source lines
115/117; Unix implementation uses `statvfs` at 518. Other matches are bindings,
declarations, platform implementations and packed-resource zero-return. Located
`statfs` uses identify filesystem type on Linux/macOS; no `fstatfs`, `fstatvfs`,
`getattrlist` or `fgetattrlist` match found in this archive. No wider SDK/runtime
traffic or Apple submission acceptance follows.

Actual source line numbers supersede earlier web-rendered indices:
[movie capacity check](https://github.com/godotengine/godot/blob/a13da4feb8d8aefc283c3763d33a2f170a18d541/servers/movie_writer/movie_writer.cpp#L115),
[argument parse](https://github.com/godotengine/godot/blob/a13da4feb8d8aefc283c3763d33a2f170a18d541/main/main.cpp#L1956),
[writer guard](https://github.com/godotengine/godot/blob/a13da4feb8d8aefc283c3763d33a2f170a18d541/main/main.cpp#L4836).
Apple startup combines process arguments with plist `godot_cmdline`, then passes
them to Main::setup. Accepted iOS6 Info.plist passes `plutil -lint`, identifies
`com.blubberandbyte.waddlewars`, and has no `godot_cmdline` value. Bounded Waddle
project/script/native source search also finds no `set_write_movie_path`,
`write_movie`, capacity-query or direct covered capacity API call. Actual device
arguments/invocation remain unproven; no disk reason or omission is approved.

Apple's [required-reason guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api.md)
was read through its advertised public Markdown form after web extraction
reported unsupported content type. Reasons must match actual user-presented
functionality, not merely imported symbols. No manifest/API was stripped, new
feature invented, or fresh package built to evade this unresolved gate.

This exhausts the bounded independent source check; it does not finalize policy.
Actual mailbox/provider/SDK/audience facts, browser access and real devices remain
necessary. No tests rerun for this read-only audit/documentation checkpoint.
Completion estimates remain MVP ~60% / original goal ~30%, not accepted gates.

## Native content/rating preparation — source review, not rating selection

Inspected gameplay includes cartoon shoves/knockback/stun, snowball impacts,
comedic seal bumps, runner hits and avalanche defeat, and endless-storm
elimination. Source references: `scripts/characters/racer.gd`,
`scripts/gameplay/snowball.gd`, `scripts/gameplay/hazard_seal.gd`,
`scripts/runner/runner_game.gd`, `scripts/runner/runner_chaser.gd` and
`scripts/gameplay/endless_manager.gd`. No blood/gore implementation was found
in the inspected combat/effect paths; this is not an exhaustive visual/audio
certification. Earned cosmetics remain fixed fish-cost purchases through play;
native paid shop/account/purchase entry points stay disabled. Random race
power-up boxes are gameplay pickups, not paid random rewards in this MVP.
No age rating, target audience or Kids/Families declaration was selected from
these source observations. Final visuals/audio and questionnaire definitions
still require review.

Public leaderboard replies previously exposed player-chosen handles. The
backend's bounded ASCII/length sanitization is not identified report/block or
content moderation. Treating that exposure as a submission risk is an inference
from the source and [Apple UGC guidelines](https://developer.apple.com/app-store/review/guidelines/#user-generated-content)
and [Google Play UGC policy](https://support.google.com/googleplay/android-developer/answer/9876937?hl=en),
not evidence of an actual rejection or a final legal classification.

Current `LeaderboardClient.fetch_board` projects successful native-MVP replies
to numeric ranks/scores and authored `Penguin #<rank>` aliases, discarding
remote free text and unknown metadata. Requests, server data, failed responses,
browser presentation, scores and saves remain unchanged. Existing once-delivery,
auth-generation and original freed-caller callback protections are preserved.
This removes free-text display, not all network traffic or collection; it is
not a new moderation system or complete store-compliance claim.

Fresh isolated import and focused policy fixture pass **44 / 0**, terminal 0,
at `qa_shots/tests/waddle-wars-tests-50538-28305/`. Known shutdown diagnostics
remain: two ObjectDB instances and one resource, matching the earlier fixture;
do not interpret this as clean stderr or memory acceptance. Current source is
**524 files** / SHA-256
`1951ebdecfdea4aa8618a8f26d98c28f666020e7c10905d67424355ce7d98c45`.
Accepted Android 8/iOS 6 packages and their static privacy inspection above
still bind `2d3518aa…`, **not this later guard**. No full-suite rerun, fresh
native package, device run or upload followed. Consolidate remaining runtime
changes before one full validation/export pass; preserve baseline receipts.

## Publication and submission blockers

### Public provider request guidance reviewed October 2

[Cloudflare policy section 8](https://www.cloudflare.com/privacypolicy/) directs
requests from users of customer applications to the customer and describes
identity checks and safeguards for other people's data. The unpublished mobile
page now explains customer-first contact and avoids promising universal provider
record access/deletion. This adds a request route, not account-specific service
capabilities or store/legal approval. The service-specific provider placeholder,
SDK/audience gaps, draft notices and null release URLs remain.

New scoped regression first fails on five missing wording checks (one test,
terminal 1); the complete preparation/page suite then passes **24 tests / 0 skips
/ 0 failures**, terminal 0, 0.303 seconds. Independent read-only review found no
actionable issue. Page-writing workflow retained the established repository
destination and separated verified public guidance from unresolved practice.
No preview, publication, runtime edit, export or UI/Keychain retry.
Consolidated release-tool suite subsequently passes **521 tests / 0 skips / 0
failures**, terminal 0, 9.758 seconds; no game-suite/export rerun for these
excluded page/fixture changes. Coarse MVP ~65% / full goal ~30% stays unchanged.

- Privacy page SHA-256: `4fa012eca948a3f5bc51bb22b7e79ba0ecdb82b58b047bd94dedc05ae1d9f2b8`.
- Fixture SHA-256: `8cfe6dfa6ae3dbe0ccc20582352b6cd9261eb8c46e1e4ea3527425a9898166ad`.

### Provider access/deletion limits — October 3 draft clarification

The provider placeholder is superseded by bounded wording, not a new account
setting or deletion test. The October 2 observation remains dated: both named
Workers had Logs/Traces disabled, Logpush disabled, no destinations and no Tail
Worker connection. Local `web-host/wrangler.toml` and `leaderboard/wrangler.toml`
identify those R2/D1-backed services; they do not prove all provider processing
or current dashboard settings. The retained observation is
`qa_shots/native/privacy-readonly-20261002-1928Z/REVIEW.md`.

Primary sources reviewed October 3:

- [Cloudflare privacy policy](https://www.cloudflare.com/privacypolicy/), effective
  November 4, 2025, sections 2/6/8/11: customer logs differ from provider network
  data; end-user rights requests go through the customer; identity and other
  people's rights matter; retention depends on purpose and legal need. No
  universal record-access or fixed deletion deadline follows.
- [Published customer DPA](https://www.cloudflare.com/cloudflare-customer-dpa/),
  section 3.1(g–i): request handling depends on association/identity verification;
  assistance is limited by ability and applicable law. Service-completion
  return/deletion is not an on-demand promise for every provider-held record.
  This review does not establish the account's accepted contract or a successful
  record-specific request.
- [Workers Logs documentation](https://developers.cloudflare.com/workers/observability/logs/workers-logs/)
  describes customer-configurable logging. Its log retention limits are not a
  retention guarantee for all Cloudflare network/security processing.

The unpublished page now explains these limits without the provider placeholder.
Effective date, final SDK/audience review and store answers remain open; no
zero-collection claim, refreshed live configuration, publication or account
change follows. No builds or tests ran. Existing page fixtures requiring the old
placeholder/review wording must be updated before the final local gate.

### Remaining publication and submission gates

1. Publisher/public contact and publisher support handling/retention are resolved
   above. Production logging facts are dated and scoped; broader provider
   processing/deletion limits remain separate. Replace remaining bracketed
   review fields with accurate practices; do not extend the selected support
   deadline to provider backups, security logs or deferred purchase records.
2. Review final native SDK/binary practices, OS permission usage, and age/audience
   declarations. Do not select Kids/Families categories or “no data collected”
   from cartoon art, offline core, or absent native accounts alone.
3. Replace draft notices with effective policy/support content and a real
   publication date. Recheck pages and all links, with no unresolved placeholders.
4. Publish **only** approved static keys using the existing host's normal
   configured credentials; preserve/restore previous objects if any. Do not run
   `tools/deploy_cloudflare.sh` merely to publish these pages: it exports/uploads
   the game, does not include these files, and strips directory names.
5. Verify exact public bodies, status, HTML/CSS content types, access without
   authentication, both cross-links, and phone layout. Retain immutable hashes
   and publication evidence before filling store URLs.
6. Add in-app privacy/support access only to finalized reachable pages (or an
   approved bundled policy), then revalidate affected runtime gates and refresh
   native candidates. No in-app link was added in this draft-only pass.
7. Complete accurate App Privacy/Data Safety disclosures for the accepted build;
   do not submit or set launch evidence from this worksheet.

The R2-backed Worker resolves explicit `/native/privacy.html` and
`/native/support.html` paths. Exact intended R2 keys are `native/privacy.html`,
`native/support.html`, and `native/policy.css`; basename-only uploads would break
the links. Local host regression exposed a missing CSS MIME mapping: the old
Worker returned `application/octet-stream` for the stylesheet. The scoped
`text/css; charset=utf-8` fix now passes ten mocked local routing/MIME/cache/
conditional/missing-object cases. The hosting fix must be published with approved
static pages; no full-game export is needed, but the Worker is not yet updated
live. No publication ran here.

A read-only check through the existing configured Wrangler CLI confirms web-host
deployment `2a6da881-235f-4fb5-89de-640c5fe8e576` uses version
`f3ba1c9d-9829-4a03-908b-04049c3a9533` at 100%; leaderboard deployment
`d77b9d03-b30a-421b-865d-c3bde2d54e6e` uses version
`e4e238cf-81ed-46aa-b0d9-549a980c6763` at 100%. These IDs identify Worker code,
not current game/R2 content or privacy collection. The filtered version metadata
did not establish observability settings. A separate read-only settings request
stopped before network because its normally configured API-token environment was
unavailable; no alternate OAuth credential lookup, new token, login, log capture
or setting change was attempted. Actual host logging/retention remains unverified.
[Cloudflare Workers Logs](https://developers.cloudflare.com/workers/observability/logs/workers-logs/).

An earlier supported Chrome inventory confirms a Cloudflare dashboard tab was
created, but its observation timed out and Chrome then became unavailable.
No dashboard setting was observed or changed. This does not establish lock
state, logging configuration or retention; no unsupported control or alternate
credential path was used.

That availability gap changed in the subsequent 19:28 UTC read-only pass.
Both production service overviews now establish **Workers Logs Disabled** and
**Workers Traces Disabled**. Scoped Settings/Observability views show disabled
Logpush, no telemetry destinations, and empty Tail Worker selection. No live
setting was changed. These per-service settings do not establish absence of
Cloudflare network/security processing, historical data or other retention.
The provider's [privacy policy](https://www.cloudflare.com/privacypolicy/)
describes end-user traffic processing and purpose/legal-need-based retention;
do not translate it into a fixed Waddle retention deadline. Remaining support
access/retention facts were requested from the owner. Exact scoped evidence:
`qa_shots/native/privacy-readonly-20261002-1928Z/REVIEW.md`.

## Store screenshots — historical availability checkpoint

One bounded availability check found zero online Android devices and one paired,
unavailable iPhone. Existing Android build-5 emulator images use the older
`f3695235…` runtime; they are not relabeled as current MVP store captures.
Retained Android build 7 and iOS build 5 use `b316cd77…`, predate the runner
touch-Pause fix, and are unsigned/failed signing candidates. Keychain/signing
work is explicitly paused until owner
confirms restart. No build, install, debug re-sign, emulator launch, or capture
was attempted to bypass that pause.

Remaining prerequisite: recover normal signing access after restart, make an
accepted current candidate available on a device, then capture real game
screens and record exact build/source/device provenance. Store screenshots and
device acceptance remain pending, not satisfied by the feature graphic.

The signing portion above is superseded by the current Android 8/iOS 6 signed
checkpoint. No current physical-device capture or accepted store delivery has
occurred; previous emulator images remain historical. Owner subsequently
selects simulator/emulator-only QA for this MVP. Current prerequisite: build
separate current-source iOS simulator/Android emulator candidates, perform the
short MVP smoke and capture genuine app screens with exact source/build/runtime
provenance. Physical testing is waived, not passed; do not relabel simulator
captures as phone/store-installed or runtime-performance evidence.

## Requirements references

Apple requires accurate app/third-party privacy answers and a public policy link;
on-device-only data and request-only processing differ from retained collection.
[Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/).

Google requires an accessible privacy policy in the listing and app, developer/
contact information, and accurate data-handling and retention/deletion details,
including applicable third-party practices.
[Google Play User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en).

Prepared graphic/icon files do not replace genuine, representative app screenshots.
[Google Play preview assets](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en).
