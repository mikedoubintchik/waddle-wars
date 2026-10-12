# Monetization direction — October 11, 2026

## Launch offer

Lead with one **$1.99 USD, permanent penguin pack**. It needs a visibly distinct
penguin, matching equipment, and an animated trail that read clearly during a
run and in the wardrobe preview. Keep normal equipment earnable with fish.
Do not position the existing $2.99–$4.99 bundles of fish-earnable equipment as
the launch offer. They are useful draft/test products, not approved sales.

The product page should show the complete look on the penguin, a short in-run
preview of the trail, exact included items, permanent ownership, and Restore
Purchases. Purchasing must not change score, speed, lives, or leaderboard rank.
The storefront must display the platform-reported localized price, not a hard-
coded USD value.

## Later offers

- Keep fish earnable through play. Defer fish packs and paid revives until the
  economy, refund handling, and competitive integrity have been measured.
- Defer a seasonal pass until recurring quests and new rewards ship reliably.
  Do not start an auto-renewing subscription for a game without that cadence.
- Use repeat runs, missions, achievements, and new content to support retention;
  purchases are optional additions to the core loop.

## Validation before sales

Instrument store views, product views, purchase starts, cancellations,
verified grants, restores, and refunds, without logging payment credentials.
Review early retention and completion data alongside the purchase funnel.
Sandbox-test purchase, cancel, pending, restore, reinstall, account switch,
and refund on both native platforms before enabling sales. The first Apple IAP
of a given type must accompany a new app version; current iOS 1.0 build 44 is
waiting for review and explicitly describes a free app without IAP.

## Store setup already performed

- App Store Connect draft `cozy_expedition` / `6821736128`: non-consumable,
  USD $2.99 base price, all-region availability, English (U.S.) localization.
- App Store Connect draft `research_crew` / `6821736775`: non-consumable,
  unpriced, no availability/localization. `aurora_celebration` was not created.
- App Store Connect draft `founder_penguin` / `6821740411`: non-consumable,
  USD $1.99 base price with Apple's regional equivalents. English (U.S.)
  localization is saved: “Founder Penguin Pack” / “Founder Penguin, matching
  gear, and a golden ice trail.” Availability, review artwork, and in-game
  entitlement remain pending. This draft has not been submitted for review.
- Google Play draft `com.blubberandbyte.waddlewars.founder_penguin`:
  `standard` Buy option, USD $1.99 base pricing across 174 configured regions,
  status Draft. It is not activated. Product icon and runtime entitlement are
  pending. The description names planned assets and must be checked against the
  final game build before activation.
- Founder portrait and trail concepts are saved under `art_src/commerce/`.
  They are not runtime assets yet. In-run fidelity and ownership handling must
  pass QA before this product is placed in the client/server catalog.
- None submitted for review or enabled for sale. Paid Apps Agreement, bank
  account, and U.S. W-9 display Active; two sandbox testers already exist.

Source context: [Apple's freemium games guidance](https://developer.apple.com/app-store/freemium-games/)
stresses ongoing content and optional IAP; [Apple's IAP types](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-types)
distinguish permanent non-consumables from depleted consumables; [Apple's
review instructions](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)
require each type's first IAP to ship with a new app version.
