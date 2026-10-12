# Private Apple purchase verifier

Uses Apple's pinned official App Store Server Library to fetch transactions from
the App Store Server API and verify Apple's JWS certificate chain, signature,
app identity, environment, and online revocation status. Commerce separately
checks the product, quantity, non-consumable type, and app account token before
granting ownership. Client redirects never grant purchases.

The Worker has no public URL or route. Its only caller is the commerce Worker's
`APPLE_RECEIPT_VERIFIER` service binding. The config starts disabled. Configure
`COMMERCE_MODE` (`test` or `live`), `APPLE_KEY_ID`, `APPLE_ISSUER_ID`, the numeric
production `APPLE_APP_ID`, and secret `APPLE_PRIVATE_KEY` through deployment
configuration; never put a private key in game files or source control. Enable
only after real sandbox purchase, restore, pending, revocation and retry tests.

Local checks:

```sh
npm ci --ignore-scripts
npm test
../leaderboard/node_modules/.bin/wrangler deploy --dry-run --outdir /absolute/temporary/output
```

The official library must initialize inside a request: its cryptographic RNG
initialization is forbidden at Worker module scope. A dry-run bundle alone does
not catch this. On 2026-10-01 the real local Workers runtime successfully booted,
returned `503 verifier_unavailable` with the default disabled configuration, and
returned `400 unverified_transaction` for a forged notification using explicitly
dummy test configuration. No real Apple credential or remote purchase was used.
Repeat this runtime check when changing the library or compatibility settings.

No live deployment, Apple credentials or valid store transaction have been
configured yet. Unit checks include actual rejection of a forged JWS using the
bundled Apple roots; mocked successful responses do not prove StoreKit's full
purchase flow. Native notification reconciliation remains part of the shared
commerce launch gate.

Sources: [Apple's library](https://github.com/apple/app-store-server-library-node),
[Apple PKI](https://www.apple.com/certificateauthority/),
[Cloudflare Node crypto](https://developers.cloudflare.com/workers/runtime-apis/nodejs/crypto/).
