# Android emulator purchase QA — 2026-10-11

## Build identity

- iOS TestFlight is build 44. Google Play production is build 40; its latest internal test build is 41.
- Tested Android `versionCode=41`, `versionName=1.0.0` on a fresh Pixel 9 Pro API 35 Play Store emulator. Installed APKs were generated from the retained build 41 AAB and debug-signed for emulator use. This is not a Play-installed, Play-signed binary.
- The AAB has the Google Play Billing permission and pinned billing provider. Its release receipt records `native_accounts_enabled=false`, `device_tested=false`, `billing_purchases_verified=false`, and `store_ready=false`.

## Observed on emulator

- Game launched and reached title, Base Camp, and Account pages. Account showed Guest Explorer and local progress; no account connection was available. Base Camp omitted Shop.
- Started Waddle Run, paused and resumed, lost three lives, saw the post-hit whiteout, and reached Run Complete at 438 m, 1,536 points, and 44 fish. Returned to title; fish showed 44.
- Force-stopped and relaunched the app. Fish still showed 44. Game process remained alive through the run and results screen. No app fatal exception appeared in the sampled logcat.
- The fresh emulator has no signed-in Google Account. Play license-test purchases require a licensed Google Account on the test device.
- Production `https://waddlewars.io/api/commerce/catalogue` returned HTTP 404. Isolated commerce staging returned HTTP 401 without credentials, as expected. Neither response proves an authenticated catalogue or transaction.

## Result

Android **purchase end-to-end: blocked, not passed**. The current build cannot reach sign-in, shop, product query, Play payment sheet, server grant, restore, or refund. A licensed tester account alone cannot fix the app and backend gates.

## Required before rerun

1. Complete the normal Android sign-in return flow without a connection-code step. Enable native accounts and commerce in an Android test candidate; verify the signed-in account binds to purchase requests.
2. Deploy a commerce-capable test backend with provider verification and notifications configured. Keep live sales off until sandbox acceptance passes.
3. Sign a Play license tester into the emulator or a dedicated Android test device; install a test candidate eligible for Play Billing.
4. Test product prices, all three non-consumables, cancellation, pending payment, one-time grant, acknowledgment, restore after reinstall, account isolation, and refund reversal against the backend ledger.
5. Run a smaller independent StoreKit sandbox smoke on iOS. Google Play Billing and StoreKit use different native bridges and store verification paths; Android success cannot establish iOS transaction correctness.

Official test guidance: [Google Play Billing testing](https://developer.android.com/google/play/billing/test), [Apple StoreKit sandbox testing](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox).
