# RevenueCat preparation — 2026-10-08

Project: [Waddle Wars](https://app.revenuecat.com/projects/e65dcdbe/overview) in Ninja Consulting RevenueCat account. Category: Games. Intended platforms: native Apple and native Android. This is preparation for a later paid cosmetics release; native 1.0 remains free with purchases disabled.

## Verified dashboard state

- Test Store: `appbc64c09518` (created automatically with project).
- Google Play app record: [Waddle Wars (Play Store)](https://app.revenuecat.com/projects/e65dcdbe/apps/app5c963ece69), package `com.blubberandbyte.waddlewars`. Service account JSON saved. RevenueCat can read both Play product catalogs, but purchase validation reports `No application was found for the given package name`; retry after the first signed Android bundle is uploaded and Google has registered the package.
- Apple app record: [Waddle Wars (App Store)](https://app.revenuecat.com/projects/e65dcdbe/apps/appba38e7d51c), bundle `com.blubberandbyte.waddlewars`. Existing IAP key `QWCZK8T43M` and App Store Connect API key `4PNUZWB4J7` both show **Valid credentials**. RevenueCat successfully applied Apple server notifications in App Store Connect.
- Google Cloud service account `revenuecat-waddlewars@waddle-wars-penguin-panic.iam.gserviceaccount.com` exists in Mike's dedicated `waddle-wars-penguin-panic` project. Android Publisher, Play Developer Reporting, and Pub/Sub APIs enabled. Project roles: Pub/Sub Editor and Monitoring Viewer. Play Console user is **Active** with access only to Waddle Wars: app information and quality read access, financial data, and order/subscription management. No access to Chancey, production release, or store presence.
- One user-managed Google service account key remains (`be771b6bdd993e53019f57ac0f945f1b828a07bf`), saved in RevenueCat. Two unused keys from browser downloads were revoked; local temporary JSON was removed. No private key is in this repository.
- Google real-time developer notifications are connected: topic `projects/waddle-wars-penguin-panic/topics/Play-Store-Notifications`. Play Console has notifications enabled for subscriptions, voided purchases, and all one-time products. The Google Play notifications service account has Pub/Sub Publisher on this topic only. Google test notification was received by RevenueCat on 2026-10-08 at 11:12 p.m. UTC.
- [Test offering `test_cosmetics`](https://app.revenuecat.com/projects/e65dcdbe/product-catalog/offerings/ofrngdc105789e9) has three custom packages. Because this is the first offering, RevenueCat made it default. It contains Test Store products only. No production app SDK uses this project yet.

| Bundle | Entitlement | Test Store product | USD test price | Future Apple and Google product ID |
| --- | --- | --- | ---: | --- |
| Cozy Expedition | `cozy_expedition` | [`test.cozy_expedition`](https://app.revenuecat.com/projects/e65dcdbe/product-catalog/products/prod53ebb36903) | 2.99 | `com.blubberandbyte.waddlewars.cozy_expedition` |
| Research Crew | `research_crew` | [`test.research_crew`](https://app.revenuecat.com/projects/e65dcdbe/product-catalog/products/prod4f0760abf3) | 3.99 | `com.blubberandbyte.waddlewars.research_crew` |
| Aurora Celebration | `aurora_celebration` | [`test.aurora_celebration`](https://app.revenuecat.com/projects/e65dcdbe/product-catalog/products/prod54edbcc1df) | 4.99 | `com.blubberandbyte.waddlewars.aurora_celebration` |

All three Test Store products are **non-consumable** and each is attached to its matching entitlement. Offering package identifiers match entitlement identifiers. Source of intended real products and pricing: `data/commerce/catalog.json`.

## Remaining before paid launch

1. Upload the first signed Android App Bundle to Google Play. Retry RevenueCat's credential validation after Google registers `com.blubberandbyte.waddlewars`; Google credentials may also take up to 36 hours to activate.
2. Create the three real non-consumable products in App Store Connect and Google Play Console with IDs above, then attach them to the matching RevenueCat entitlements and packages. Test Store products remain separate.
3. Design and implement Godot integration. RevenueCat lists native Apple and Android SDKs but no official Godot SDK, so a native bridge or another documented supported path is needed. Keep secret REST API keys server-side; only platform public SDK keys belong in clients.
4. Validate sandbox purchase, restoration, refund/revocation, cross-device entitlement refresh, offline behavior, and disclosures before changing the free-launch listing or enabling paid sales.

Evidence: `store_assets/apple-creative-20261008/revenuecat-apple-connected-proof.png`, `store_assets/apple-creative-20261008/revenuecat-google-validation-proof.png`, `store_assets/apple-creative-20261008/revenuecat-google-notification-proof.png`, `store_assets/apple-creative-20261008/play-service-account-proof.png`, and `store_assets/apple-creative-20261008/play-rtdn-setup-proof.png`.

Do not ship the Test Store public API key in production. The `test_cosmetics` offering is a dashboard sandbox fixture, not a live purchase configuration.
