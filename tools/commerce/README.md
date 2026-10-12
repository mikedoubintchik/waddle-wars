# Isolated web-commerce sandbox preflight

`wrangler.staging.toml` is a separate deployed integration Worker bound to the
dedicated `waddle-wars-commerce-staging` D1. Its checkout, native sales, and
native authentication paths have no provider secrets and are disabled. On
October 11, 2026, version `ec4e2cd2-8e4e-4564-8c41-2f08d158cb6d` returned
health 200 and rejected unauthenticated commerce requests with 401. It does not
replace the production leaderboard Worker or constitute purchase acceptance.

The following public sandbox templates and preflight helper remain undeployed
preparation material.

The preflight helper performs no resource creation, deployment, key generation,
provider API calls, payment, refund, or production configuration changes.
Python 3.11+; standard library only.

`wrangler.public.sandbox.toml` deliberately contains invalid Worker/D1/origin
placeholders. `policy.public.sandbox.json` deliberately contains empty allowlists
and false setup assertions. Default preflight must fail. No fictional valid cloud
IDs are supplied. Unit fixtures use explicitly fictional UUIDs/example.invalid
hosts and must never be mistaken for deployable setup.

```sh
python3 -m unittest discover -s tools/commerce -p 'test_*.py' -v
python3 tools/commerce/sandbox_preflight.py
```

Before copying the tracked public production reference into a test snapshot:

```sh
python3 tools/commerce/sandbox_preflight.py \
  --check-production-public-config /absolute/waddle-wars/leaderboard/wrangler.toml
```

This separate copy gate permits only the explicitly reviewed public top-level,
D1 and vars fields. Quoted secret keys, unknown nested tables/bindings, extra vars
and parser failures block with fixed check IDs; no values/input lines are echoed.
Future production config fields require review and an explicit whitelist update.
It validates public schema only, not commerce readiness or deployment.

For a future authorized sandbox, copy both public templates into a dedicated
directory, retaining the `.public.sandbox.toml` / `.public.sandbox.json` suffixes.
Resolve the `main` and `migrations_dir` paths to this checkout's canonical Worker
and commerce migrations. Fill only public configuration from verified dedicated
TEST resources. Do not put secret values, customer IDs or transaction data in
either file. Do not copy production D1 or production game origins. No deploy
command is provided or run by this helper.

Required setup declarations: isolated D1; applied leaderboard schema plus all
commerce migrations; frontend targeting the sandbox API and matching test Clerk
instance; actual JWKS/sign-in checks; two distinct synthetic test accounts; Stripe
test-account credential provenance; registered test webhook endpoint and all five
handled event types. Declarations start false: do not mark them true without
their independent checks. Web-only testing requires Clerk JWT authentication,
not Apple/Google receipt verifiers; all native sales/auth/notification flags must
stay explicitly false.

```sh
python3 tools/commerce/sandbox_preflight.py \
  --config /absolute/sandbox/wrangler.public.sandbox.toml \
  --policy /absolute/sandbox/policy.public.sandbox.json
```

Helper observes presence of `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` in its
normally configured environment **by key name only**. It never reads their values,
loads `.envrc`/`.env`/`.dev.vars`, or prints credentials. An absent key blocks;
presence cannot prove a nonempty/test-mode key or correct account. Credential
provenance and provider registration require independent authorized setup proof.
Worker deployment secrets are not inferred from local environment presence.

Exit `0`: public configuration/declaration prerequisites pass, **not purchase or
launch readiness**. Exit `2`: blocked. Every report explicitly retains
`store_ready=false`, `e2e_verified=false`, `deployment_verified=false`. Reports
contain only fixed check names and generic gaps; parse/argument errors do not
echo input. Unknown bindings/variables/environment overrides are rejected.

Next actual acceptance, only after authorized isolated setup: A buys Cozy using
Stripe test mode; return URL grants nothing; genuine signed webhook grants once;
duplicate unchanged; fresh session restores; B gets nothing; account-switch
in-flight results remain isolated; full sandbox refund revokes paid-only items
while retaining fish-earned items; replay cannot regrant. Preserve a sanitized
receipt tied to exact build/config/provider mode. This helper does not run that
scenario, inspect player saves, or validate native stores.

## Account deletion foundation — disabled, not launch acceptance

`AccountLifecycleClient` and the Online Settings confirmation are shared by iOS,
Android and web. `account/deletion_enabled=false` is explicit in `project.godot`.
Client and server feature switches remain disabled; Worker changes remain
undeployed. Do not enable them merely because local fixtures pass. No live
provider deletion or device acceptance has been performed. The interface requires
an acknowledgment and separate confirmation, binds consent to the current account/session, and defaults focus
to Cancel. It reports pending provider/retention work rather than claiming that
all account data has been deleted.

A 32-byte CSPRNG recovery receipt and local durable pending marker are persisted
before dispatch. The fresh authenticated POST body is exactly
`{"confirm":"DELETE_ACCOUNT","recovery_receipt":"<64 lowercase hex characters>"}`.
The server stores only the receipt's SHA-256 digest, bound to the retired subject,
transactionally with the retirement marker and personal-data erasure. Receipt
ownership cannot be transferred or arbitrarily rotated. Apply migration
`0007_deletion_receipts.sql` before any enabled Worker deployment.

Pending/retired subjects cannot resume cloud uploads or accept cached purchase
grants; stale
callbacks and a subsequent account switch cannot affect another account. A
positive retirement confirmation repairs only the persisted receipt owner's
local purchase cache in the main save, backup and explicitly owned staging files
while preserving earned offline
progress and other account caches. Failed or ambiguous POST responses stay
paused; only a successful authenticated status response showing `requested=false`
may clear an unaccepted request. The client exposes no authentication token to
the confirmation UI.

Signed-out or expired-auth recovery uses the read-only
`GET /api/account/deletion/receipt` with the capability only in the
`X-Waddle-Deletion-Receipt` header: no JWT, query token or provider call. A known
receipt returns minimal retirement status, never the owner, receipt or timestamps;
an unknown receipt returns `404 status_unavailable` and cannot unpause the local
fence. Only positive retirement confirmation repairs the owner's local cache;
receipt reads never authorize clearing an ambiguous pending marker. The legacy
authenticated `GET /api/account/deletion` remains available. Old requests without
a persisted receipt cannot retroactively recover an already deleted identity.
All retirement responses still report `deletion_complete=false` while retention
review remains pending.

Cloud-save GET responses and PUT storage strip `commerce` and the exact reserved
top-level fields `account_deletion`, `account_deletion_receipt`,
`account_deletion_receipts` and `account_deletion_recovery_owner`. Earned nested
progress remains unchanged; GET filtering does not rewrite legacy stored rows.

### Standalone public request surface — implemented, not deployed

The API Worker now serves `/account/delete` independently of Godot and the game's
R2 host. It can sign in, collect explicit account/session-bound confirmation,
submit the existing authenticated request and check a saved receipt while signed
out. This is not an app-only redirect. Production remains disabled and undeployed.

An enabled page requires the existing exact deletion switch, limiter, provider
configuration and `COMMERCE_CLERK_PUBLISHABLE_KEY` matching `CLERK_ISSUER`. Its own
HTTPS origin must already be in `COMMERCE_ALLOWED_ORIGINS`; no origin or feature
is automatically broadened. Missing/mismatched configuration returns an inert
503 page without loading Clerk or dispatching requests. Responses use nonce CSP,
no-store/no-referrer and framing guards. Real SDK/CSP/OAuth acceptance is pending.

Atomic IndexedDB create-if-absent prevents two tabs replacing an owner's receipt
or sending duplicate POSTs. Capability writes request strict durability and await
transaction completion; unsupported/downgraded hints fail closed. This is a
[browser durability hint](https://w3c.github.io/IndexedDB/#transaction-durability),
not protection against storage clearing or hardware failure. Cancellation/account
change may discard only this tab's exact newly created, never-dispatched pending
preparation. Existing, replaced, retired or attempted/ambiguous requests retain
their fence; unknown receipt reads never authorize removal. The page does not
claim to erase native/Godot offline progress or device purchase caches.

Local acceptance: 19 focused page fixtures, 127 combined backend/transport tests,
and eight isolated installed-Chrome layouts with synthetic Clerk/API responses.
Actual Chrome IndexedDB two-tab execution sends one synthetic POST; restart while
signed out sends a receipt-only GET and unknown status does not retry deletion.
This is not real Clerk/D1/provider, physical-device or store acceptance. Receipt:
`qa_shots/commerce/public-deletion-page-20261002/receipt.json`.

Optional macOS capture requires existing installed Chrome/Playwright and an
already existing output parent; the output directory itself must be fresh:

```sh
node tools/commerce/capture_account_deletion_page.mjs \
  /absolute/fresh/output /absolute/installed/playwright
```

Focused isolated fixtures and actual-window synthetic captures:

```sh
./run_tests.sh account_deletion
./run_frontend_qa.sh account_deletion \
  out=/absolute/fresh/deletion.png w=320 h=568 ui_scale=1.4
```

Captures never sign in or contact a provider; their desktop logical geometry is
not an iOS/Android safe-area, touch, purchase or device acceptance result. Full
regression is needed after changes to SaveManager or the authentication clients.

Remaining lifecycle gates: public request-page deployment and real SDK/provider
acceptance; lawful financial/log/backup and
local retirement-marker retention policy; scheduled provider-bound retries;
real isolated Clerk/D1 lifecycle tests; native/web stale-session tests; signed
device acceptance and store privacy declarations. Implemented local receipt
recovery and synthetic fixtures are not live Clerk/D1, provider-deletion, device
or launch acceptance. Local signed-out cache repair is not proof of provider
deletion or completion of the remaining retention workflow.
