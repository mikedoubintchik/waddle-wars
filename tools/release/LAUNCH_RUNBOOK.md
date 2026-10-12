# Mobile release: repeatable path

Applies to the free, offline-first iOS and Android MVP. Keep accounts and real-money purchases disabled in native packages. `native_release.json` is the platform/version policy. `store_listing.en-US.json` is listing copy, not proof of store approval.

## 1. Freeze and validate source

1. Stop edits in every Waddle Wars task. Check `git status --short` and record the exact dirty-tree source snapshot; Git HEAD alone is insufficient. Do not submit a candidate while another task changes runtime files.
2. Run the full local game gate: `./run_tests.sh` with no filter. Record passes, failures, skips, source identity, and log path. Then run `python3 -m unittest discover -s tools/release -p 'test_*.py' -q` and `python3 tools/release/native_release.py inspect`. Any skipped native/device group remains an open gate, not a pass. Rerun affected checks if source or release tooling changes afterward.
3. Verify public privacy, support, and deletion page bodies against `web/native/*.html` via HTTPS, including content type and visible phone layout. Reconcile Apple App Privacy and Play Data Safety with the actual frozen binary. Compare every uploaded screenshot and store statement with the frozen game; replace stale assets before review.
4. If runtime visuals change, follow `tools/qa/gallery_iteration.md`: one start snapshot before edits, one final capture pass after the source freezes, explicit review and acceptance, then build and delivery delta. Import sidecar canonicalization with unchanged texture settings does not itself establish a visual change.

## 2. Build one immutable version

Choose an unused `1.0.0` build number in **both** stores. Use a fresh outside-checkout directory per attempt. Keep failed receipts/logs; never overwrite or silently retry a failed candidate. Never put passwords or private keys in command arguments, repository files, or logs.

**iOS:** Before the expensive export/archive, run `python3 tools/release/signing_preflight.py --identity-sha1 FDD4551BC510B9A31794CDA660864E324B883712`. It signs and verifies a disposable test executable with the existing distribution key; require `ready_for_codesign: true`. Then run `native_release.py prepare ios` with the exact existing team ID and the reviewed disk-capacity-disabled template ZIP plus SHA-256 from `native_release.json`. Then `build_native.py CANDIDATE`. Its output is an Xcode project, not an IPA. Compile `verify_ios_profile_cms.c` using the pinned local Clang command recorded in `qa_shots/native/ios-profile-verified-20261001/receipt.json`; verify the existing Waddle Wars App Store profile. Use `build_ios_distribution.py archive` and `ipa` with explicit public certificate/profile/helper hashes, fresh private run directory, and `/usr/bin/xcodebuild`. Those helpers perform manual signing and offline archive/IPA verification. `tools/release/README.md` has exact arguments. If CodeSign reports `errSecInternalComponent`, diagnose access to the **existing** private key before a fresh archive run; never create/replace keys or enable automatic provisioning.

**Android:** Until the encrypted vault migration is complete, run `python3 tools/release/android_signing_preflight.py`; require `ready_for_password_read: true`. It queries the existing exact Keychain item without printing the password. Then use `android_upload_signing.py build` or the safe `fastlane android build` lane with fresh candidate, installed Godot/SDK/JDK/bundletool paths, version and build number. The app-specific Keychain helper signs only after an unsigned export and preserves the unsigned AAB. The launcher verifies signature, package/version, release flags, full bundle, and 16-KB structure. It does not create another upload key. If Keychain access fails, preserve the failed launch receipt and unsigned AAB; after unlock, prepare a fresh candidate. `tools/release/FASTLANE.md` has exact arguments. Keep an independent encrypted backup of the upload key before production submission; two copies on this Mac are not independent recovery.

### Signing access recovery without reboot

First check both exact preflights above and `security show-keychain-info "$HOME/Library/Keychains/login.keychain-db"`. On macOS 26.5.2, the current failure pattern is: `show-keychain-info` reports an incorrect passphrase without asking for one, Android's password read returns `errSecAuthFailed` (`-25293`), and Apple CodeSign fails with a valid identity. A report on Apple's developer forum describes the same `show-keychain-info`/`-25293` combination with a visually unlocked Keychain and recovery by locking and unlocking it. This is a matching symptom and a recovery attempt, not a proved root cause for either Waddle Wars item.

From Terminal **in the logged-in desktop session**, run the following commands separately. Enter the login Keychain password only at the second command's local prompt; never use `-p`, shell history, chat, or a repo file for it:

```sh
security lock-keychain "$HOME/Library/Keychains/login.keychain-db"
security unlock-keychain "$HOME/Library/Keychains/login.keychain-db"
```

Then rerun `security show-keychain-info "$HOME/Library/Keychains/login.keychain-db"`, `python3 tools/release/signing_preflight.py --identity-sha1 FDD4551BC510B9A31794CDA660864E324B883712`, and `python3 tools/release/android_signing_preflight.py`. Require **both** preflights to pass. If only one passes, diagnose that credential's storage/access policy separately. Do not reboot, change global Keychain ACLs, reset the Keychain, or rotate either key as a diagnostic shortcut.

### Permanent signing architecture

- **Android:** The encrypted `primary/upload.p12` can be passed directly to `jarsigner`; the missing input is its randomly generated 64-character password, currently held only in the app-specific Keychain item. While access works, run `python3 tools/release/android_password_vault.py migrate --jdk "/Applications/Android Studio.app/Contents/jbr/Contents/Home"` in the owner's Terminal. The owner enters a new vault passphrase twice locally; the bridge moves the existing password through a private pipe into a scrypt/AES-GCM encrypted file, verifies the *same* upload certificate, and never prints the password. Migration refuses to overwrite a vault. After migration, add `--direct-p12-vault` to `android_upload_signing.py build` and enter that passphrase locally. This path uses the existing key and the same offline verifier, without a Keychain read during builds. Its first live signed candidate must pass full offline verification before replacing the established Keychain signer. Keep an independent encrypted copy of the `.p12` **and** vault file and retain the passphrase separately; copies on this Mac alone are not independent recovery.
- **Apple:** `/usr/bin/codesign` consumes an identity from a Keychain, not an encrypted `.p12` path. For repeatable **local manual signing**, export the existing Apple Distribution identity during a working session and import it into a dedicated release Keychain; unlock that Keychain explicitly, scope access to `/usr/bin/codesign`, and verify a disposable CodeSign before each archive. This removes dependence on the login Keychain state but still uses macOS Keychain. To avoid a local distribution private key, investigate Xcode Organizer's cloud-managed distribution signing and validate a complete Godot-generated archive/export before replacing the pinned manual pipeline. Do not claim cloud signing works with the current manual `xcodebuild` commands without that test.

Sources: [Apple code-signing troubleshooting](https://developer.apple.com/forums/topics/code-signing-topic/code-signing-topic-general), [matching macOS forum report](https://developer.apple.com/forums/topics/privacy-and-security/privacy-and-security-general?page=2&sortBy=lastUpdated&sortOrder=DESC), [Apple cloud-managed certificates](https://developer.apple.com/help/account/certificates/cloud-managed-certificates), [Apple signing identity export](https://developer.apple.com/documentation/Xcode/sharing-your-teams-signing-certificates).

Run `python3 tools/release/release_audit.py --ios IOS_CANDIDATE --ios-run IOS_ARCHIVE_RUN --android ANDROID_CANDIDATE`. It must exit 0 with `ready_for_upload_offline: true` and one matching runtime SHA/version/build. This is a continuity gate; separately retain the strict iOS and Android verifier receipts. Run it again immediately before each upload to catch intervening source changes.

## 3. Test, submit, release

1. Perform the owner-selected simulator/emulator smoke from source-equivalent QA derivatives: cold title/load, Waddle Run, swipe/jump/slide, pause/resume/retry, one race/tutorial path, portrait/landscape safe areas, local save after relaunch, Feedback, privacy/support links, and no account/payment entry points. Record virtual device/OS/build and failures. After upload, verify exact build processing in TestFlight and Play internal testing; use a Play-generated package for delivered Android signature and 16-KB runtime evidence. Physical phone testing is waived, not passed.
2. Upload the verified IPA to App Store Connect 1.0 and the verified AAB to Google Play. Select those exact build numbers. Wait for store processing; compare the portal package identity, icon, permissions, and privacy answers to the artifact receipts. No rebuild after acceptance without a new build number and repeated gates.
3. Submit both listings for review. Apple is configured for manual public release; Play production should target the saved U.S. availability with managed publishing on. Submit the Play listing/content changes and the production release together when possible; submitting a later change restarts an in-progress review. Record review submission IDs and portal screenshots. Resolve rejections locally, then repeat the affected gates and upload a new build number.
4. After approval, release both stores, verify public URLs/availability, update `waddlewars.io` store badges, and save final exact build hashes, approval IDs, release timestamps, and rollback links in a dated receipt. Do not mark release complete while a store remains in draft, review, or unavailable.

## 2026-10-08 attempt

- iOS b39 project exported from runtime `dcfb4ef68e264a83c580a3aebd4f612d1edca038eabe839a89d76a91fd6d1f76`; existing App Store profile/CMS validation passed. Archive failed at CodeSign `errSecInternalComponent`; no IPA.
- Android b39 unsigned AAB exported from the same runtime. Upload signer failed while reading the existing app-specific Keychain password; no signed AAB. Unsigned SHA-256 `0331124e3c717f961a22e8a3b801e4ead710f930d8027cbd923284c5a7d49462` retained with receipts/logs. Only regenerable Gradle/cache intermediates were pruned with a receipt.
- Runtime changed after both snapshots (`scripts/utilities/audio_manager.gd`); `release_audit.py` correctly blocks upload. Source must freeze again before a fresh pair of candidates.
- Release-tool suite: 582 tests passed, zero skips on October 9. Live privacy/support/deletion pages match current local bytes. Apple 1.0 still has no build. Play has listing, U.S. availability, and content changes queued; its review button is disabled until release setup is complete. Neither store has a submitted or public mobile release.
- Both b39 candidates became stale after further runtime edits in the concurrently active game task. Do not upload either. Apple CodeSign and the Android app-specific password retrieval failed during b39; Keychain Access now visually shows the login keychain unlocked, so the cause of either failure is unproven. Prepare fresh candidates after source freeze and diagnose any repeat failure without changing signing keys or weakening access controls.
- Disposable iOS signing preflight now fails before an archive: Clang 0, CodeSign 1, verification not attempted (`qa_shots/native/ios-signing-preflight-20261009/receipt.json`). Ad hoc signing of the same test executable succeeds, while both valid Apple identities fail, isolating a current private-key-access problem. Resolve this gate before spending disk/time on another iOS archive.
- Android password preflight also fails early: Keychain returns `errSecAuthFailed` (`-25293`) for the existing exact upload-password item, though the non-secret presence probe finds the item. Its `.p12` primary and backup files exist, but both require that inaccessible password. Do not create a replacement key or upload an unsigned bundle.
- After the owner restarted the Mac on October 9, the **same** Apple Distribution SHA-1 passed disposable CodeSign and verification (`ready_for_codesign: true`); the **same** Android upload-password item returned status `0` (`ready_for_password_read: true`); and `security show-keychain-info` succeeded. No identity, keystore, password, profile, access policy, or build artifact was changed by these preflights. This confirms a session-state problem at that checkpoint, not a permanent fix or a signed current-source release.

Apple's [code-signing troubleshooting guidance](https://developer.apple.com/forums/topics/code-signing-topic/code-signing-topic-general) documents `errSecInternalComponent` when a signing process cannot unlock or use a private key in its execution context. Inspect the existing keychain and process context; this receipt alone does not prove which one failed.

## 2026-10-09 build 40 checkpoint

- Frozen runtime: 1,929 files, SHA-256 `26edd96592557f7d884529ee1e331fe523d3687e301ab2fcab51d75a657997ea`; app `com.blubberandbyte.waddlewars`, version `1.0.0`, build `40` on both platforms. Do not use b39.
- Apple distribution preflight and Android upload-password preflight passed with existing credentials. Signed iOS IPA: `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-archive-20261009-b40/ipa-export/waddlewars.ipa`, SHA-256 `21d166fb738a1aa86d782ef48e29e6336f3146514445f93af5284d99900d5c7f`. Signed Android AAB: `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/android-release-20261009-b40-signed/project/build/waddle-wars.aab`, SHA-256 `daccf2e3fb9929a5cdb7dc34981364ee7a470ce70044d486c731c81e18040f04`. Both pass strict offline verifier; `release_audit.py` reports `ready_for_upload_offline: true`. Rerun that audit immediately before each store upload.
- Full game suite: 132 pass, 9 skip, 0 fail; independent NumPy groups: 10 pass; release-tool suite: 587 pass. Final real-window frontend QA passes all requested groups. Incremental visual gallery iteration 13 accepted 78 new Chrome views, 134/134 accepted overall, zero pending; its delivery delta is ready for selective publication, with no remote gallery write yet.
- Build 40 Android QA derivative installed on existing API 35 ARM64 emulator without clearing saves. Observed cold menu, Waddle Run, Pause/Resume, result, Retry, Base Camp, and persisted fish count after app relaunch. Captures and limits: `qa_shots/native/release-freeze-20261009/b40-android-smoke.md`. Gesture counters did not prove swipe/jump/slide. iOS simulator, one race/tutorial route, privacy/support link taps, and Play-delivered package remain unverified. Physical-device testing remains waived, not passed.
- Play internal testing is **active** for build `40 (1.0.0)` in release `1.0.0 (40) Internal`: [Play Console internal track](https://play.google.com/console/u/2/developers/9132521315692749104/app/4974838896609027403/tracks/4701677298489060686?tab=releases). The existing `Ninja Testers` list (three accounts, including Mike) is selected. Testers can join at [Play internal test](https://play.google.com/apps/internaltest/4701677298489060686). Console states “Available to internal testers”; proof: `qa_shots/native/release-freeze-20261009/play-internal-build40-live.jpg`. The app is not yet reviewed, so testers see temporary package name `com.blubberandbyte.waddlewars (unreviewed)`. Play's uploaded bundle details report API 24+, target SDK 36, ARM64, INTERNET and CHECK_LICENSE permissions, and **Supports 16 KB** memory page size. Play showed optional warnings for missing R8 mapping and native debug symbols; no release error. Play-generated APK installation/signature and 16-KB runtime behavior remain unverified.
- Owner authorized acceptance of the Apple Transporter software license on October 9; agreement accepted. Transporter signed in as `ninjaconsultingllc@gmail.com` under Ninja Consulting, LLC. The offline release audit passed immediately before delivery, with the same IPA SHA-256 `21d166fb738a1aa86d782ef48e29e6336f3146514445f93af5284d99900d5c7f`. Transporter delivered Waddle Wars `1.0.0 (40)` to App Store Connect at 08:19 local; proof: `qa_shots/native/release-freeze-20261009/transporter-build40-delivered.png`. App Store Connect showed upload **Complete** and binary **Validated**, with matching bundle ID, version/build, ARM64, iPhone/iPad, minimum iOS 15.0, and no non-exempt encryption. Build 40 was assigned to new `Waddle Wars Internal` TestFlight group, automatic future-build distribution disabled, with account holder Mike **Invited**. TestFlight Test Information and build-specific What to Test notes were saved; portal proof: `qa_shots/native/release-freeze-20261009/testflight-build40-internal.png`. Actual tester installation remains unverified.
- App Store version 1.0 now selects build 40 and was submitted to App Review at 08:28 local. Submission `37f88032-6ebf-46a0-8909-4428710124a8` shows **Waiting for Review**, one item, with manual public release retained after approval. Proof: `qa_shots/native/release-freeze-20261009/apple-review-waiting-build40.png`. Public approval and release are pending. The encrypted Android password vault migration and independent off-device backup remain open; current build used the existing Keychain-backed signer.
- Play production release `1.0.0 (40) Production` reuses the verified version-40 AAB already in the Play library. U.S. country availability, en-US store listing, content rating, target audience 13+, privacy URL, ads, Data Safety, health apps declaration, and Arcade category were sent for review. Production build 40 was then submitted, which restarted that same-day review; the Publishing overview now shows **Changes in review** with the production rollout and listing/content changes together. Play quick checks were still running (up to 14 minutes) at that observation. **Managed publishing is on**, so approval will not itself make the public production release live. Proof: `qa_shots/native/release-freeze-20261009/play-production-review-submitted.png`. Review approval, public release, and store URL verification remain pending.

## 2026-10-09 launch update: Android 40 and iOS 44

This checkpoint supersedes the build-40 store statuses above. Keep those earlier
records as dated evidence, not current launch state.

- **Google Play:** Android `1.0.0 (40)` is live in production in the United
  States; Publishing overview showed no unpublished changes. The Waddle Wars
  store-listing contact email is published as `support@waddlewars.io` (proof:
  `qa_shots/native/ios-b44-release-20261009/play-support-email-published.png`).
  The organization's public developer address still comes from its linked
  Google Payments profile and is shared with other apps in this developer
  account. The owner asked to leave that address unchanged for now. Do not
  mistake an app-specific support-email edit for a developer-profile change.
- **iOS candidate:** runtime source snapshot SHA-256
  `7e320375fdefeb1cfaf6e52fcb5bc8f7dfa9d2ed41f0209426b8633e8e61bf64`
  (1,947 files); bundle `com.blubberandbyte.waddlewars`, version `1.0.0 (44)`.
  Full local game suite: 137 pass, 9 skip, 0 fail. Separate requested window
  checks: 4 pass, 0 fail. Release-tool unit suite: 616 pass. The remaining
  skipped checks and build-44 TestFlight-installed physical-device observation
  are not passes. A prior build-43 development install had successful Apple
  sign-in on the owner's phone; that observation does not prove a build-44
  TestFlight install.
- **iOS signing:** install the exact renewed distribution profile into Xcode's
  `UserData/Provisioning Profiles` directory before archive, as described in
  `IOS_ACCOUNT_RELEASE.md`. Build 44's fresh signed archive/IPA passed offline
  verification. IPA:
  `/Users/ninja/Library/Application Support/WaddleWarsLaunchCandidates/ios-archive-20261009-b44-r2/ipa-export/waddlewars.ipa`,
  SHA-256 `2fa6da2e724dbd6b63a2ee56f91fa7537a8492a2f09d4854e4ded09cc010d7cd`.
  Transporter delivered it at 15:26 EDT (proof:
  `qa_shots/native/ios-b44-release-20261009/transporter-delivered-b44.png`).
- **TestFlight:** App Store Connect processed and validated build 44. Its
  build-specific What to Test was saved, Test Information feedback email is
  `support@waddlewars.io`, and `Waddle Wars Internal` has build 44 with one
  tester. The build metadata reports no non-exempt encryption. No new
  physical TestFlight install has been recorded.
- **App Store review:** The former build-40 submission
  `37f88032-6ebf-46a0-8909-4428710124a8` was removed. Version 1.0 now
  selects build 44, with optional-account description and updated reviewer
  notes. The Header and Search Results creative each remained 1 of 1. App
  Privacy was published for eight relevant data categories, linked to user,
  App Functionality, no tracking. Build 44 submission
  `64649d84-8de0-468b-ac2f-e67fbef8a0b8` shows **Waiting for Review** at
  15:34 EDT. Automatic release after approval is selected. Proof:
  `qa_shots/native/ios-b44-release-20261009/apple-review-b44-submitted.png`.
  Approval and public App Store availability are pending.

- **Apple expedited review (Oct 9):** The official Apple Developer expedited
  review form was submitted for Waddle Wars: Penguin Panic on iOS. Its result
  stated, “We’ll expedite review for Waddle Wars: Penguin Panic.” This applies
  to the already-submitted build-44 review; it does not mean App Store approval.
- **Age ratings and child audience (Oct 9):** The live U.S. Play listing shows
  ESRB Everyone 10+ / Fantasy Violence. The IARC live notice has global rating
  ID `3ffdc4d2-4e78-8a3a-8d00-3fa63eb367df`. IARC's rating-check page also
  shows PEGI 7 and other region-specific results. An ESRB-only rating check was
  submitted through the notice's official IARC link, accurately disclosing
  throwable snowballs, shoves, brief stuns, avalanche retries, and absence of
  depicted injury, blood, death, and realistic weapons. The page confirmed
  successful submission; ESRB will respond by email. Do not change the Play
  questionnaire to “no violence” while those mechanics remain. Play target
  audience is currently 13+; changing it to include under-13 users needs a
  Google Play Families review of accounts, public leaderboard names, data
  collection, privacy disclosures, and any child-specific controls. Apple's
  saved questionnaire currently produces 13+ in most regions, with frequent
  contests and infrequent cartoon violence declared. Its rating is separate
  from IARC and would need its own accurate reassessment.
- **Google Play screenshot order (Oct 9):** Reordered the existing six phone
  screenshots to put `menu.png` first, followed by the avalanche gameplay
  frame, missions, customization, results, and achievements. The branded menu
  image is an actual in-game page; the current Play feature graphic remains
  unchanged. Play Console confirmed “1 change sent for review.” Quick checks
  and Google review are pending, and managed publishing is on, so approval
  alone may leave the listing update ready to publish. The currently live
  listing can still show the old order until publication.
- **Same-day status check (Oct 9):** App Store Connect still shows build 44
  Waiting for Review; the Apple expedite request has already been accepted.
  Play Publishing overview still shows the screenshot reorder in Changes in
  review, with no approved update ready to publish. IARC sent the ESRB rating
  check receipt; no decision has arrived. Apple's saved age questionnaire was
  inspected without edits: user-generated content Yes, cartoon/fantasy
  violence Infrequent, guns/other weapons Infrequent, contests Frequent. Apple
  describes contests as events involving rankings, rewards, or personal goals;
  the Frequent answer is what raises the current 13+ rating. Future changes
  to this answer need a factual review of the game's score/leaderboard design
  and should be coordinated with a new app version.
- **Oct 10 launch check:** `ninjaconsultingllc@gmail.com` accepted the Play
  Console Terms of Service after owner approval. Publishing overview showed
  the single phone-screenshot change approved and ready to publish. It was
  published; the page then showed “Last published on October 10, 2026” and no
  changes ready to publish. An immediate reload of the public U.S. Play
  listing still showed the avalanche image first, so storefront propagation
  remains unverified. The release mailbox had no newer Apple review or
  ESRB/IARC decision email. The public U.S. App Store page for app ID
  `6818416048` returned “The page you're looking for can't be found.” Apple
  Connect itself required sign-in, so its current private review status was
  not independently rechecked. The daily launch reminder remains active.
- **Oct 11 launch check:** The public U.S. Google Play listing now serves the
  branded menu screenshot first and the avalanche screenshot second. The
  first two public images were matched against the prepared local assets;
  screenshot-order publication is complete. Apple's U.S. public catalog lookup
  for app ID `6818416048` returned no result, and App Store Connect still
  required sign-in. Searches of the Ninja Consulting release mailbox found
  no new Apple review or ESRB/IARC rating decision message since October 9.
  The daily reminder now tracks only Apple availability and the ESRB decision.
- **Oct 12 ESRB/IARC decision:** IARC email for certificate
  `3ffdc4d2-4e78-8a3a-8d00-3fa63eb367df` says ESRB found violence
  over-disclosed. U.S./Canada rating changed to **Everyone / Mild Fantasy
  Violence**. IARC says the updated rating should appear on Google Play
  shortly, and no further action is required for this rating check. The public
  U.S. Play page still served **Everyone 10+ / Fantasy Violence** at the first
  post-decision check, so storefront propagation remains pending. Play target
  audience remains 13+; Apple's independent 13+ age rating remains unchanged.

For the next iOS release: use a new build number and fresh private directories;
freeze and hash runtime source; run the applicable local checks once after the
freeze; run signing preflight; install and hash the pinned distribution profile
in Xcode's profile directory; prepare/export/archive/verify the IPA; deliver
through Transporter; wait for App Store Connect processing; set build-specific
What to Test and internal group; update version build and review notes; submit
the exact processed build; retain the submission ID and screenshot. A new
runtime or release-tool edit invalidates its affected local-check receipt.
