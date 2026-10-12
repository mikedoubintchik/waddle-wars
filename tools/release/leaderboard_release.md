# Scoped web leaderboard deployment

The development Worker contains unreleased commerce and account-lifecycle
features. Do not deploy `leaderboard/wrangler.toml` as a leaderboard hotfix.
Authenticated requests in that Worker require additional database tables even
when sales/account-deletion flags are disabled.

## October 9, 2026 release profile

`prepare_leaderboard_release.py` builds a self-contained Worker from the exact
previous production version and current leaderboard functions. It preserves
the production Clerk issuer, D1 binding, JWT verifier and cloud-save handlers.
It enables Waddle Run and all five race courses, fixes public names and tied
ranks, adds profile GET, and makes best-score writes atomic. No migration is
required by this scoped artifact.

The helper accepts the previously downloaded deployed Worker, the corresponding
Cloudflare version metadata, and a fresh output directory. Both the source hash
and version/binding contract are checked. A different production baseline needs
an explicit release-profile update after reviewing its source and bindings.

```sh
python3 tools/release/prepare_leaderboard_release.py \
  DEPLOYED_WORKER.js VERSION_METADATA.json OUTPUT_DIRECTORY
```

Test the exact candidate against the original three-table schema, independently
of the development Worker's expanded schema:

```sh
WADDLE_LEADERBOARD_WORKER=/absolute/OUTPUT_DIRECTORY/worker.mjs \
WADDLE_LEADERBOARD_SCHEMA=/absolute/legacy-schema.sql \
node --test tests/leaderboard_privacy.test.mjs tests/clerk_issuer_cache.test.mjs

node tools/release/verify_leaderboard_runtime.mjs \
  OUTPUT_DIRECTORY/worker.mjs legacy-schema.sql runtime-receipt.json

leaderboard/node_modules/.bin/wrangler deploy --dry-run \
  --config OUTPUT_DIRECTORY/wrangler.toml
```

The runtime verifier uses workerd, a new local D1 database, synthetic signed
identities, and a local JWKS fixture. External requests are rejected. It checks
every board, submissions, ownership, concurrent best scores, name changes,
browser preflight, and unchanged legacy-save behavior. It never posts test
scores or saves to production.

Before publishing, inspect fresh deployment metadata and verify the active
version still equals `release-receipt.json`'s `baseline_version`. Verify artifact
hashes and all local validation receipts. Then deploy only the generated config:

```sh
leaderboard/node_modules/.bin/wrangler deploy \
  --config OUTPUT_DIRECTORY/wrangler.toml --keep-vars
```

Read public health and every leaderboard afterward, then verify the game uses
the live API in Chrome. A successful deployment command alone is insufficient.
Preserve the previous version as the rollback target:

```sh
leaderboard/node_modules/.bin/wrangler rollback \
  e4e238cf-81ed-46aa-b0d9-549a980c6763 \
  --config OUTPUT_DIRECTORY/wrangler.toml \
  --message 'Restore previous leaderboard after failed verification' --yes
```

This release keeps the deployed legacy cloud-save protocol. The newer save
protocol, commerce, native authentication and account deletion require a
separate reviewed release and its migration/feature gates.
