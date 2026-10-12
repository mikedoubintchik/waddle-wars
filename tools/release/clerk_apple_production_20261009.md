# Clerk Production Apple sign-in receipt — October 9, 2026

## Configured and verified

- Apple Developer team: Ninja Consulting, LLC, `V8MBW2V2C2`.
- App ID `com.blubberandbyte.waddlewars`: Sign in with Apple enabled as the primary App ID. This changes future provisioning; regenerate the provisioning profile before the next signed iOS export.
- Services ID `com.blubberandbyte.waddlewars.signin`: Sign in with Apple enabled, linked to the Waddle Wars App ID, with domain `clerk.waddlewars.io` and return URL `https://clerk.waddlewars.io/v1/oauth_callback`.
- Dedicated Sign in with Apple key `HJZSP22KZQ`, named `Waddle Wars Clerk Sign In`, scoped to that primary App ID. Its one-time `.p8` download is stored outside the repository at `~/Library/Application Support/WaddleWarsSecrets/apple/AuthKey_HJZSP22KZQ.p8` with owner-only permissions. Never commit or copy its contents into release receipts.
- Apple private email relay source `bounces+116079009@clkmail.waddlewars.io` registered. Apple showed SPF status for the source; DNS also returned an SPF record for `clkmail.waddlewars.io`.
- Clerk Production Waddle Wars instance `ins_3KDgVIIHNQctHw6mIy8yKJXZ3No`: Apple OAuth credentials saved, provider enabled, and “Enable for sign-up and sign-in” enabled. Reload readback confirmed provider, Services ID, Key ID and sign-in switch.
- Public `https://accounts.waddlewars.io/sign-in` displays Apple and Google. Clicking Apple reached `appleid.apple.com/auth/authorize` with the Waddle Wars Services ID, Clerk callback, `name email` scope, and Apple’s “sign in to Waddle Wars” heading.
- Completed Apple authorization in the in-app browser returned to the Waddle Wars site. The same browser session then opened `https://accounts.waddlewars.io/user`, showing a signed-in profile and Apple under Connected accounts alongside the existing Google connection. This verifies the production Clerk Apple web login and account link.

## Remaining acceptance

- Verify the account-enabled iOS binary on a physical iPhone after build/export and TestFlight upload. Hosted Account Portal redirect alone does not prove native game sign-in.
- Regenerate iOS provisioning after the App ID capability change, then use the signed-build release gate in `IOS_ACCOUNT_RELEASE.md`.

Evidence: `qa_shots/native/apple-signin-20261009/apple-relay-registered.png`, `clerk-apple-enabled.png`, `apple-button-live.png`, and `apple-account-connected.png`.
