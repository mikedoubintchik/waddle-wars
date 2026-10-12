# Store listing checkpoint — 2026-10-05 EDT

## Current portal state — October 8

- Apple version 1.0 has five screenshots each in the iPhone Dynamic Island medium slot (1206×2622) and 13-inch iPad slot (2048×2732). App Store Connect showed **5 of 10** in both slots after a fresh reload. Order: Waddle Run gameplay, Menu, Penguins customization, Results, Achievements. These are current desktop Godot gameplay and UI captures, with hashes in `store_assets/desktop-phone-current-20261008/apple-prepared-receipt.json`; they still need comparison with the signed native candidate.
- Apple reviewer notes were cleaned of internal draft language and saved. App Privacy has four configured data types: Email Address, Customer Support, Coarse Location, and Product Interaction. Each is for App Functionality, linked to identity, and not used for tracking. App Store Connect now shows the privacy label **published by Mike Doubintchik** on October 8.
- **Add for Review** was attempted before that privacy publication. Apple then returned two blockers: choose a build and publish App Privacy. The privacy blocker is resolved; no version was added for review because a build is still required. Google Play likewise cannot send changes for review until a production release is created. Native builds remain outside this listing task.
- Earlier dated sections below record the state at each checkpoint. Their pending items may have been resolved by this current portal state.

## October 8 screenshot refresh

- Screenshot follow-up: Play now has **6 of 8** phone screenshots in order: avalanche chase, Menu, Missions, Penguins, Results, Achievements. The final two 1080×1920 images were captured from the current Godot Results and Achievements screens. Draft saved; reload confirmed count and order. Both new shots were marked as created or edited with AI in Play's asset declaration; Review changes saved. `store_assets/desktop-phone-current-20261008/receipt.json` records hashes and limitations.
- Apple added Results and Achievements for both iPhone and iPad. Fresh reload confirmed five images per slot and correct order. Portal proof: `apple-iphone-portal-verified-5-20261008.png`, `apple-ipad-portal-verified-5-20261008.png`; Play proof: `play-phone-portal-verified-6-20261008.png` in the same asset folder.
- Screenshot strategy: show distinct actual game moments, lead with chase, and avoid repeating similar frames to fill the limit. Apple permits up to 10 and Google Play permits up to 8 phone screenshots; neither limit is a target. The current images contain legible in-game headings. Optional one-line benefit overlay on the lead screenshot could be tested later, but it should not obscure gameplay or replace representative UI. Results fixture values are illustrative but coherent; final signed iOS/Android builds remain unverified.

- Google Play en-US default listing now has four phone screenshots saved as a draft and verified after reload: an unretouched October 8 Chrome game avalanche frame (941×1672), plus current Godot phone-layout Menu, Missions, and Penguins captures (each 1080×1920). The older two 540×960 Android b29 screenshots were removed from the listing. The icon, feature graphic, and Waddle Run copy stayed saved. The portal still says **Ready to send for review / Draft changes**; no review submission or public release occurred.
- Play's AI asset declaration now labels the app icon, feature graphic, and all four phone screenshots as created or edited with AI. Saved on the listing Review step; reopening the declaration confirmed all six selections persisted.
- Google Play production availability now targets the United States; portal readback showed **Targeted**. The production track remains inactive. Publishing overview has **Send app for review** disabled and says to complete dashboard steps; release creation is still required.
- Google Play Games on PC was opted out in Advanced settings because this launch has no PC package. Readback showed the prior Opt-out control replaced by Remove and its Opt-in task locked. Android XR still displays Active; no XR release was created.
- Play Data Safety now declares optional collection of Feedback's reply email and message (Email address and Other user-generated content, app functionality, retained beyond ephemeral processing). Source `scripts/network/feedback_client.gd` sends both through the public feedback endpoint. The saved review preview, then a fresh reload, confirmed both categories alongside existing approximate location and app interactions. The change is pending review with the rest of the draft.
- Exact uploaded file hashes, dimensions, order, and source limitations are in `store_assets/desktop-phone-current-20261008/receipt.json`. The three Godot captures are real UI scenes rendered from the current local checkout with touch layout, and the Chrome frame is real running gameplay. They are not accepted signed Android or iOS candidate evidence. A fresh `runner_store` attempt produced only 0 m frames, so those were excluded. The exact Apple 1206×2622 capture attempt was capped by the desktop window at 1206×2082 and was not uploaded.
- At this checkpoint Apple still had zero screenshots. The later portal state above supersedes this. See <https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/>.
- Six Apple slot-size screenshots were prepared locally: live gameplay, Menu, and Penguins at 1206×2622 iPhone and 2048×2732 iPad sizes. See `store_assets/desktop-phone-current-20261008/apple-prepared-receipt.json` for exact paths and hashes. They are desktop Godot captures, not signed iOS evidence. Missions captures were excluded after a missing art resource error. They were uploaded later, as recorded above.
- Apple Feedback audit found the native form asks for an optional email and free-text message and sends both off device. Apple's optional-disclosure exception requires, among other things, that the user's name or account name appear prominently alongside submitted data; this form has no such field. The later portal edit added Email Address and Customer Support for app functionality. Source: <https://developer.apple.com/app-store/app-privacy-details/>.

This records draft state only. No build was uploaded, no review was requested,
and neither store listing is public.

## Google Play

- Existing Waddle Wars app `4974838896609027403`, en-US default listing:
  **Ready to send for review**, with draft changes.
- Portal readback on October 5: title, 71-character short description,
  729-character full description, one `icon-512-v4.png`, one
  `feature-graphic-1024x500-v2.png`, and two 540×960 Android b29 emulator
  screenshots (`menu.png`, `repeat-live-at-12s.png`) are saved. Both screenshots
  predate the final release candidate; they cannot certify its appearance.
- Published privacy, support, and deletion-request URLs on `waddlewars.io`
  each returned HTTP 200 with `text/html; charset=utf-8` through a public DNS
  resolver. Their new URLs were saved in the Play drafts. The support website
  and Data safety deletion URL persisted on readback; the privacy URL showed
  “Change saved. Send for review in Publishing overview.”
- Play setup reached 11/11 in the October 4 portal readback. Target audience,
  IARC content rating, and Data safety have saved draft answers. Final Data
  safety still requires the accepted native package and network/SDK audit.
- Google's current asset guidance says screenshots must demonstrate actual
  in-app or in-game experience. The portal requires 2–8 phone screenshots;
  its promotion guidance requests at least four, with at least three at
  1080 pixels or above. Current uploads satisfy the listing minimum, not that
  promotion target. Source: <https://support.google.com/googleplay/android-developer/answer/9866151>.
- A five-image 1080×1920 desktop Godot phone-size **draft** now exists in
  `tools/release/store_assets/play-phone-draft-20261005/`: race, avalanche,
  fish run, customization, title. First three show gameplay. These are JPEGs
  with no alpha; they have not been uploaded to Play or matched to an accepted
  native build.

## App Store Connect

- Existing Waddle Wars app `6818416048`: prior portal readback saved free
  U.S.-only pricing, manual release, support/privacy URLs, and age rating.
- Signed-in portal readback on October 5 confirms saved app name, subtitle,
  promotional text, description, keywords, support URL, copyright, and
  source-derived review notes. App Information shows Games / Racing / Action.
  The version remains **Prepare for Submission** with manual release selected.
  Marketing URL is blank and optional.
- App Privacy shows the published policy URL but no data-collection answers;
  `Get Started` remains available. Apple's opening questionnaire defines collection
  as off-device transmission accessible beyond real-time request servicing; the
  final provider/runtime evidence is insufficient to answer it yet. The version's iPhone Dynamic Island medium
  display screenshot slot shows **0 of 10**. Its listed screenshot sizes are
  1179×2556 and 1206×2622, including landscape rotations. Current 540×960
  Android captures are not suitable Apple screenshot uploads.
- The iOS export targets `UIDeviceFamily` 1 and 2, so accepted-build screenshots
  are needed for iPhone and iPad. The App Review contact has no saved name,
  phone, or email. The account profile shows Mike Doubintchik and the owner
  confirmed `ninjaconsultingllc@gmail.com`, but App Store Connect discarded a
  partial contact save with the phone blank. A current private phone number is
  still needed to complete this form; none was found in release records.
- Content Rights is saved as “Yes, this app has the necessary rights to its
  third-party content”; fresh reload confirmed persistence. The saved portal
  view is `tools/release/store_assets/apple-content-rights-saved-20261005.png`.
  Bundled font has
  an OFL license; owner confirmed permission for the source-only penguin
  reference. Recheck final package before review submission.
- Still needed: final-candidate iPhone and iPad screenshots,
  private App Review contact and App Privacy answers based on the accepted build.
  Apple allows 1–10 screenshots per supported device size. Source:
  <https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/>.

## Release boundary

The October 4 b31 Android debug build still failed native stall acceptance.
The Waddle Wars Release chat is diagnosing that loader; source is not frozen.
Use the phone-size desktop drafts for listing layout review; replace them with
accepted-candidate native captures before submission.
Do not submit either listing, upload a build, or claim store readiness from
these drafts.

## New MVP copy revision — October 5 late evening EDT

The current local MVP hides Waddle Race (`GameConfig.RACE_VISIBLE_IN_MVP=false`).
The Apple description, subtitle/category, review notes, and some draft
screenshots still advertise Race. Revised Waddle Run copy, reviewer notes, and
suggested Games/Action/Casual classification are staged in
`tools/release/store_listing.en-US.json`. The new 67-character short and
565-character full descriptions were saved as a **Google Play draft**; Play
confirmed “Your changes have been saved.” The existing two Play screenshots
still predate the current MVP. Apple copy remains unchanged. Recheck against
the accepted build before final submission. Portal proof:
`tools/release/store_assets/play-waddle-run-copy-saved-full-20261005.png`.
Additional proof: `tools/release/store_assets/play-waddlewars-io-privacy-saved-20261005.png`
and `tools/release/store_assets/play-waddlewars-io-deletion-saved-20261005.png`.

## Domain and live page follow-up, October 6 UTC

The purchased `waddlewars.io` domain is live with DNSSEC. The apex home and
mobile support pages were updated to describe Waddle Run without advertising
the hidden Race mode; readback over normal local HTTPS confirmed the new copy.
The `play.waddlewars.io` Godot game rendered its title screen in the in-app
browser. Google sign-in displays “continue to Waddle Wars” and uses the new
Clerk callback. Google OAuth's legacy callback was removed after the new flow
returned to the apex. These changes do not close the accepted native build,
final screenshot, Apple session/contact, or privacy audit gates above.

## Homepage and privacy follow-up, October 5 EDT

- Rebuilt `waddlewars.io` homepage around existing game artwork, Waddle Run,
  browser play, and mobile store badges. Both unpublished store URLs return
  HTTP 404, so badges say **Coming soon** and cannot open broken listings.
  Removed publisher email from homepage; it remains on required privacy and
  support pages. Added canonical/social metadata and checked desktop plus
  390×844 phone layout. Live R2 readback and browser rendering passed.
- Updated mobile privacy text for current Android share-sheet/clipboard
  fallback, and changed privacy/support links to the new game subdomain.
  Updated the browser privacy page's home link. All pages were published to
  the existing R2 bucket. Native in-app privacy/support constants now point
  to `waddlewars.io`; share links and web preview tags point to `play.waddlewars.io`.
  Those source changes require the next accepted build before they appear in
  native apps or the live web game.
- Google Play Data safety draft readback: optional **Approximate location**
  and **App interactions**, collected for app functionality and security,
  not marked shared with third parties or ephemeral; HTTPS encryption and
  deletion-request URL saved. Preview lists these exact types and the new
  privacy/deletion URLs. This is a saved draft, not a submitted declaration.
- Apple privacy questionnaire still needs a signed-in App Store Connect
  session. The required label must reflect the final native candidate and
  provider retention, following Apple's off-device collection definition.
  `https://waddlewars.io/native/delete-data.html` is staged locally as the
  optional Privacy Choices URL. Private App Review phone remains missing.
- Live policy-page bytes for privacy, support, and deletion matched local
  sources over HTTPS on October 6 UTC. Current hashes and URLs are recorded
  in `native_privacy_inventory.json` under `public_pages_followup_20261005`;
  the October 3 publication checkpoint remains unchanged. The two focused
  publication/policy checks pass. The full release Python suite currently has
  one unrelated stale feature-graphic source hash: `scripts/ui/main_menu.gd`
  changed during active Release work. The Godot native-offline fixture passed
  its privacy/link assertions but has two unrelated menu-rank presentation
  failures from the same evolving menu. Reconcile after menu work freezes.
- Google Search Console already had the `waddlewars.io` domain property under
  `mike.doubintchik@gmail.com`. Its home URL was unknown to Google; a live
  test passed and Search Console confirmed **Indexing requested**, placing
  `https://waddlewars.io/` in a priority crawl queue. This is a crawl request,
  not proof of indexing. Proof: `store_assets/search-console-indexing-requested-20261005.jpg`.

## Branding, search, and Apple follow-up, October 6 UTC

- Published favicon PNGs at 16, 32, and 48 pixels, a 180-pixel Apple touch icon,
  a 512-pixel PWA maskable icon, and a 1200×630 social card derived from the
  v4 penguin icon and current hero artwork. Replaced the homepage's placeholder
  W with the penguin icon. All live asset bytes matched local sources over HTTPS.
- Updated homepage title/description, canonical/social metadata, and
  `VideoGame` + `WebApplication` structured data to describe the visible free
  browser runner. Added canonical and favicon links to browser/privacy/support
  pages. Published `sitemap.xml` with five canonical URLs and verified XML
  MIME type. Google Search Console accepted it and reported **Success / 5
  discovered pages**. Discovery does not establish indexing or AI answer
  inclusion. Proof: `store_assets/search-console-sitemap-success-20261005.jpg`.
- Desktop and 390×844 Chrome visual checks passed. Captures:
  `store_assets/waddlewars-home-brand-desktop-20261005.png` and
  `store_assets/waddlewars-home-brand-mobile-20261005.png`.
- Apple App Information subtitle changed to **Avalanche chase & penguin runs**;
  Games subcategories changed to **Action / Casual**. Saved and reload-verified.
  Proof: `store_assets/apple-subtitle-category-saved-20261005.jpg`.
- Apple privacy and Privacy Choices URLs now point to the live mobile policy and
  deletion-request page. Saved and reload-verified. Apple questionnaire has an
  unpublished draft declaring Coarse Location and Product Interaction, linked
  to identity, for app functionality, with no tracking. Reconcile this with
  the accepted native candidate before publishing the label; current checkout
  contains account/commerce work beyond the frozen free-offline MVP.
- Updated version description, keywords, promotional text, Support URL,
  Marketing URL, and reviewer notes are entered in App Store Connect but remain
  **unsaved** because Apple requires a private App Review phone number. Mike
  Doubintchik and the confirmed support email are entered; the phone is still
  missing. The Apple version tab is preserved for completion when provided.
- Updated publication hashes for the three live native information pages under
  `public_pages_followup_20261006`; the prior publication receipt remains as
  historical evidence. Focused publication and host-policy checks passed.

## Apple version form completion, October 5 EDT

- Found Mike Doubintchik’s mobile number on his Contacts card, alongside his
  matching Gmail identity. Used it only for Apple’s private App Review contact.
  Apple accepted the full form. Reload confirmed the Waddle Run promotional
  text, description, keywords, Support URL, Marketing URL, reviewer notes,
  and contact all persisted. The earlier required-field errors disappeared;
  **Add for Review** is enabled. Proof:
  `store_assets/apple-waddle-run-version-saved-20261005.jpg`.
- This saves the draft version metadata. It does not submit for review or make
  a listing public. Final screenshots, accepted native build, and privacy-label
  reconciliation remain before submission.
