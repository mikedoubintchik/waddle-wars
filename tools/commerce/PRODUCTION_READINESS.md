# Purchase launch status — October 11, 2026

**Sales remain disabled.** The native release policy is `free_offline_mvp`;
the deployed leaderboard Worker is a scoped release without commerce tables.
The development Worker must not replace it as a shortcut. Native purchase UI
requires both `native_accounts` and `native_commerce` export features. Android
does not yet have an accepted account flow, so its commerce UI remains closed.
Android build 41 emulator findings and the blocked purchase matrix are recorded
in [Android emulator purchase QA](../../docs/android-commerce-emulator-qa-2026-10-11.md).

## Verified locally this turn

- Backend purchase/auth/notification/privacy tests: 77 passed, zero failures.
  These use real SQLite migrations and cryptographic checks, but mocked store
  responses.
- Apple verifier tests: 10 passed, zero failures.
- Native release suite: 616 passed, zero failures.
- Full game test runner: all executed checks passed; real-window rendering and
  physical-device checks were skipped by that runner.
- Installed iOS StoreKit bridge matches its pinned source and artifact hashes,
  but its receipt still says `compiled_unverified`, with device billing and auth
  acceptance false. Android Billing 3.3.0 addon matches the pinned release hash.

None of these checks proves a real purchase, refund, restore, or grant.

## External launch gates

1. **Store products.** Play internal build 41 was signed, verified, and published
   only to internal testers. Its manifest includes `com.android.vending.BILLING`;
   production remains build 40. Play now has all three catalog product IDs with
   active backward-compatible `standard` Buy options, accurate 512 px icons,
   and USD base prices $2.99/$3.99/$4.99. Register matching non-consumables in
   App Store Connect. RevenueCat's Google service account validates, Google
   developer notifications are connected, and all three Play products were
   imported as non-consumables and attached to their matching entitlements.
   App Store Connect now has Cozy Expedition (`6821736128`) as a draft
   non-consumable at USD $2.99 with English (U.S.) text and all-region
   availability. Research Crew (`6821736775`) is an unpriced draft. No Apple
   product was submitted for review. Founder Penguin Pack (`6821740411`) is a
   separate draft non-consumable at a USD $1.99 base price. Its English (U.S.)
   name and description are saved. Availability and review art are pending.
   Google Play has a matching Founder draft with a `standard` Buy option and
   USD $1.99 base pricing in 174 configured regions; it is not activated.
   Outfit-only bundles at $2.99 or more are
   not the intended lead offer. The working direction is a $1.99 permanent
   penguin pack with a distinct character, matching gear, and visible animated
   trail; see [monetization direction](MONETIZATION_DIRECTION.md). Create and
   validate its assets and product identifiers before configuring a live store
   price. Existing drafts remain for testing. App Store Connect shows the Paid Apps
   Agreement, bank account, and U.S. W-9 as Active on October 11, 2026.
   Two sandbox Apple test accounts already exist in App Store Connect; neither
   has completed a Waddle Wars purchase acceptance run.
   This dashboard setup does not prove transaction fulfillment. Confirm
   disclosures before a public release. The Waddle Wars Stripe account
   is test-only; its live business account has not been activated.
2. **Account and provider setup.** Confirm production Clerk sign-in on both
   devices. Android needs a normal in-app return flow before commerce can open.
   Configure the private Apple verifier, App Store Server Notifications V2,
   Google Android Publisher access and RTDN, and Stripe live API/webhook in
   appropriately scoped production services. Never put credentials in tracked
   files, command arguments, or evidence logs.
3. **Backend migration and isolation.** A new remote staging D1,
   `waddle-wars-commerce-staging` (`434033da-2364-4e38-9afa-888b6bdf7e0b`),
   has the base schema and migrations 0001–0008 applied; readback found 12
   tables, 21 indexes, and 18 triggers. The isolated Worker version
   `ec4e2cd2-8e4e-4564-8c41-2f08d158cb6d` is deployed at
   `https://waddle-wars-commerce-staging.ninjaconsultingllc.workers.dev`.
   Live checks returned health 200 and unauthorized catalogue/purchase 401;
   authenticated catalogue, ledger writes and provider callbacks remain untested.
   Plan production migration from the deployed three-table schema. Preserve existing leaderboard
   and cloud saves. Keep `COMMERCE_ENABLED` and each provider sales flag false
   until its own acceptance is complete. Do not deploy
   `leaderboard/wrangler.toml` directly over the scoped production Worker.
4. **Real sandbox acceptance.** With two distinct test accounts, buy each bundle
   on StoreKit sandbox, Play license testing, and Stripe test Checkout. Verify
   cancelled and pending payments grant nothing; paid notifications grant once;
   duplicated and out-of-order events do not grant twice; fresh sign-in and
   reinstall restore the correct account only; full refunds and Google voided
   purchases revoke only paid entitlements; fish-earned items remain. Confirm
   receipt acknowledgment/transaction finishing and account deletion behavior.
5. **Customer disclosures and release.** Update the native privacy policy, Apple
   App Privacy, Play Data Safety, support/refund guidance, and store metadata for
   payments before enabling sales. Build signed candidates from frozen sources,
   run the complete local release gate, test on actual devices, then submit to
   internal/TestFlight tracks. Turn on provider sales independently only after
   store approval and live webhook/notification readback.

The current production mobile policy explicitly says the editions have no
in-app purchases. This must remain true until the corresponding store build and
policy are published together.
