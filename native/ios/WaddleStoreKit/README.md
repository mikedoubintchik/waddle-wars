# WaddleStoreKit

Original StoreKit 2 bridge for Godot 4.7.1. Device-side verified purchases replay through `Transaction.unfinished`/`Transaction.updates`. The server must verify account token, bundle/product, type/environment, refund state, and durable idempotent fulfillment before calling `finish_transaction`. No purchase handler finishes automatically. Transaction IDs travel as strings to avoid JSON numeric precision loss. JWS and app-account token are provided for server verification, never logged.

`WaddleStoreKit` singleton exposes:

- `request_products(PackedStringArray)` → `products_received(Array)` with store-localized prices.
- `purchase(product_id, app_account_token)` → `purchase_received(Dictionary)` or `purchase_failed(String)`.
- `restore_purchases()` → account authentication/entitlement events and `restore_finished`; call only from an explicit Restore button.
- `finish_transaction(transaction_id)` → finish after verified durable server fulfillment.
- `begin_auth_session(authorize_url, request_id)` → `auth_session_started(request_id)` only after the secure in-app session starts.
- `end_auth_session(request_id)` → dismiss a matching modal without emitting a new cancellation outcome.
- `auth_session_finished(request_id, outcome)` → `cancelled`, `unavailable`, `invalid_request`, or `invalid_callback`; never credentials or ownership.
- `auth_session_authorized(request_id, callback_code)` → internal delivery to `NativeAuthClient` only. The short-lived, single-use code must never be logged, saved, displayed, or forwarded into account/status/UI events. It grants nothing without the initiating app's private PKCE verifier.

`purchase_received` states are `purchased`, `refunded`, `pending`, `cancelled`. Verified transactions contain `product_id`, string `transaction_id`, string `original_transaction_id`, `signed_transaction` JWS, and `app_account_token` when present. Pending/cancelled events have no verified transaction and grant nothing. Only one-time non-consumables are supported.

Version 1.2.0 adds callback-bound iOS authentication v2. Rebuild both native libraries and regenerate source-bound receipts before preparing a candidate; earlier 1.1.1 binaries do not expose the required callback event and the new client rejects them. Previous compilation/packaging evidence does not certify this changed source. Earlier billing-only 1.0.0 binaries/receipt remain preserved under QA output. Older community StoreKit2 v0.2 binaries are not reused: no exact Godot 4.7.1 release binary is published, and its API does not expose the required account-bound finish flow.

`WWAuthenticationBridge` uses `ASWebAuthenticationSession`, anchored to Godot's actual visible window on the main actor. The sole authorization URL is pinned to `https://waddlewars.io` plus `/api/commerce/native-auth/authorize-ios-v2?request_id=<canonical UUID>`. The sole callback is `com.blubberandbyte.waddlewars.auth://native-auth/return?request_id=<same UUID>&code=<43 base64url characters>` in that exact order. Access tokens, verifier, user identity, caller-selected redirects, extra/duplicate parameters, encoded aliases, and fragments are rejected. A private session, strong presentation provider, generation guard, and matching request ID prevent stale completion. iOS 17.4+ uses the modern callback API; iOS 15–17.3 uses the compatible older initializer. No external-browser fallback exists.

The iOS client starts with `presentation: "ios", flow_version: 2` and rejects missing or older protocol versions. It never polls for a token while the sheet is open. Only the validated native callback permits one `/token` request containing both the private verifier and `callback_code`. A shared authorization URL alone therefore cannot let its initiator obtain a signed-in user's token. The code expires after at most 120 seconds and the overall request after 300 seconds. A lost/failed exchange response requires fresh sign-in; the client never replays the one-use code or falls back to verifier-only exchange. The server remains the authority for provider-session validation, account ownership and refresh. Desktop's existing explicit device-linking flow is separate and unchanged.

A caller-initiated end, expiration, logout, or shutdown invalidates the generation before canceling; late system callbacks are ignored. Code and verifier remain in memory only, with the callback code cleared immediately after dispatch and on every teardown. The plugin manifest links `AuthenticationServices`/`UIKit` and registers the fixed callback scheme. App Store authentication, privacy, signup/deletion, and third-party-login eligibility still need review.

Build using generated headers from exact Godot source commit `a13da4feb8d8aefc283c3763d33a2f170a18d541`:

```sh
python3 tools/release/prepare_godot_headers.py /absolute/godot-4.7.1-source \
  --python /absolute/isolated-scons-venv/bin/python

python3 tools/release/build_ios_billing.py --godot-source /absolute/godot-4.7.1-source \
  /absolute/new/WaddleStoreKit

python3 tools/release/install_ios_billing.py /absolute/new/WaddleStoreKit
```

### Simulator-only QA libraries

Device is the builder's default. For owner-selected iOS simulator QA, compile
separately with the existing exact generated headers:

```sh
python3 tools/release/build_ios_billing.py --godot-source /absolute/godot-4.7.1-source \
  --variant simulator /absolute/new/WaddleStoreKit-simulator
```

ARM64 is the default. Inspect the actual engine archive with `xcrun lipo -info`
before choosing the simulator architecture; XCFramework directory names and
plist declarations alone are not proof. The installed Godot4.7.1 release
simulator library actually contains **x86_64 only**. Its matching QA bridge is:

```sh
python3 tools/release/build_ios_billing.py --godot-source /absolute/godot-4.7.1-source \
  --variant simulator --architecture x86_64 /absolute/new/WaddleStoreKit-simulator-x86_64
```

Both architectures use `iphonesimulator`, an iOS15 simulator target and Godot's
`IOS_SIMULATOR` define. Device builds remain ARM64-only. Compiler side outputs
stay inside the fresh
per-mode folders. The receipt explicitly records `ios_simulator`, variant,
SDK and target, with `store_ready: false`; all source/commit/entrypoint checks
remain. Select the same architecture in the separate Xcode QA build and use an
installed compatible runtime; iOS18.5 supports x86_64, iOS26.5 does not. This
older-runtime/translated QA path is not a phone-performance measurement.
**Do not install these into the production plugin directory.** The
unchanged production verifier/installer rejects simulator receipts. Use them
only in a separately recorded simulator QA derivative; preserve accepted device
archives and source bindings. Compilation alone proves neither app linkage/run
nor StoreKit, phone, store or performance acceptance. Native purchase entry points remain disabled in the free MVP. Optional iOS accounts require the explicit production `native_accounts` release capability and its separate acceptance gate; Android remains offline.

Copy only `WaddleStoreKit.gdip`, `WaddleStoreKit.debug.a`, `WaddleStoreKit.release.a`, and `waddle_build_receipt.json` into `ios/plugins/WaddleStoreKit/` before preparing a candidate. Both binary variants are required for Godot to recognize this multi-target plugin. Godot 4.7.1's exported Xcode template already contains a Swift source and Swift library settings; older plugin examples' `use_swift_runtime` field is no longer read by the current plugin parser. `native_release.py` enables the iOS plugin in its isolated preset and sets iOS 15 minimum. This source package is not proof of a working native purchase; retain the launch gate until device and server tests pass.

Primary APIs: [Apple Product purchase](https://developer.apple.com/documentation/storekit/product/purchase(options:)), [appAccountToken](https://developer.apple.com/documentation/storekit/product/purchaseoption/appaccounttoken(_:)), [Godot native iOS plugin format](https://docs.godotengine.org/en/4.7/tutorials/platform/ios/ios_plugin.html).

Authentication primary APIs: [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession), [callback matching](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback), [presentation anchor](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationpresentationcontextproviding/presentationanchor(for:)). `tests/auth_policy_test.swift` exercises the Foundation-only exact-URL policy; compilation and execution belong in the coordinated native build window.
