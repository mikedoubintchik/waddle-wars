#!/usr/bin/env python3
"""Prepare optional native accounts atop the exact deployed leaderboard repair.

Never deploys, migrates, reads credentials, or changes existing web identity.
The four-table additive schema is specific to native auth/account retirement;
unreleased purchase, billing and notification handlers are excluded.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
from prepare_leaderboard_release import function, replace_once

ROOT = Path(__file__).resolve().parents[2]
BASELINE_SHA256 = 'aa6a378cb7483673eeb93884ef0e898a9e21b716fed20f8d01771cb2627894e2'
BASELINE_VERSION = '1ea99c29-fc08-4ccf-a170-a250372bbb74'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def prepare(baseline: Path, output: Path):
    raw = baseline.read_bytes()
    if digest(raw) != BASELINE_SHA256:
        raise ValueError('Expected exact currently deployed leaderboard source')
    if output.exists():
        raise ValueError('Preserve existing candidate; select fresh output')
    original = raw.decode()
    candidate = original
    current = (ROOT / 'leaderboard/src/worker.js').read_text()
    match = function(candidate, 'verifyClerkJwt')
    candidate = candidate[:match.start()] + function(current, 'verifyClerkJwt').group() + candidate[match.end():]
    candidate = '''import { handleNativeAuth } from './modules/commerce_native_auth.mjs';
import { handleAccountLifecycle, requireActiveSubject, retryPendingIdentityDeletions } from './modules/account_lifecycle.mjs';
import { acceptedClerkIssuer, nativeAccountEnvironment, nativeStorageSubject } from './modules/native_accounts_policy.mjs';
''' + candidate
    candidate = replace_once(candidate, '  return verifyClerkJwt(env, auth.slice(7));', '''  const claims = await verifyClerkJwt(env, auth.slice(7));
  if (claims && ((env.NATIVE_ACCOUNTS_ENABLED === 'true' && claims.iss === env.NATIVE_CLERK_ISSUER) || env.ACCOUNT_SUBJECT_PREFIX === 'clerk_live:')) {
    const scoped = { ...claims, sub: nativeStorageSubject(claims.sub) };
    // Lifecycle status/deletion must still authenticate retired sessions.
    if (!new URL(request.url).pathname.startsWith('/api/account/')) {
      try { await requireActiveSubject(env, scoped.sub); } catch { return null; }
    }
    return scoped;
  }
  return claims;''')
    anchor = '      if (url.pathname === "/api/health") return json({ ok: true });'
    candidate = replace_once(candidate, anchor, anchor + '''
      if (url.pathname.startsWith('/api/commerce/native-auth/') || url.pathname.startsWith('/api/account/')) {
        const nativeEnv = nativeAccountEnvironment(env);
        if (!nativeEnv) return json({ error: 'native_auth_unavailable' }, 503);
        // Session approval/deletion only accepts production tokens, never the
        // development web credential accepted by the existing game endpoints.
        if (url.pathname.startsWith('/api/commerce/native-auth/'))
          return await handleNativeAuth(request, nativeEnv, async (_env, req) => {
            const bearer = req.headers.get('Authorization') || '';
            return bearer.startsWith('Bearer ') ? verifyClerkJwt(nativeEnv, bearer.slice(7)) : null;
          });
        return await handleAccountLifecycle(request, nativeEnv, authFromRequest);
      }''')
    # New iOS client requires revisioned sync. Keep existing development/web
    # save functions byte-for-byte, routing only verified native subjects to CAS.
    native_save = "\n".join(function(current, name).group() for name in
        ['cloudProgressJSON', 'saveRevision', 'changedRows', 'handleSaveGet', 'handleSavePut'])
    native_save = native_save.replace('handleSaveGet(', 'handleNativeSaveGet(').replace('handleSavePut(', 'handleNativeSavePut(')
    candidate = native_save + '\n' + candidate
    for method in ['Get', 'Put']:
        original_dispatch = f'        return await handleSave{method}(env, request);'
        candidate = replace_once(candidate, original_dispatch,
            "        const identity = await authFromRequest(env, request);\n"
            "        if (identity?.sub?.startsWith('clerk_live:'))\n"
            f"          return await handleNativeSave{method}(env, request);\n" + original_dispatch)
    candidate = replace_once(candidate, 'var worker_default = {', 'var worker_default = {\n  async scheduled(_event, env, ctx) {\n    const nativeEnv = nativeAccountEnvironment(env);\n    if (nativeEnv) await retryPendingIdentityDeletions(nativeEnv, { limit: 5 });\n  },')
    preserved = {}
    for name in ['getJwk', 'displayName', 'handleLeaderboard', 'handleSubmit', 'handleProfile',
                 'handleProfileGet', 'handleSaveGet', 'handleSavePut']:
        text = function(original, name).group()
        if function(candidate, name).group() != text:
            raise ValueError('Unrelated deployed function changed: ' + name)
        preserved[name] = digest(text.encode())
    modules = ['commerce_native_auth.mjs', 'account_lifecycle.mjs', 'commerce_providers.mjs', 'native_accounts_policy.mjs']
    output.mkdir(parents=True)
    (output / 'modules').mkdir()
    for name in modules:
        shutil.copy2(ROOT / 'leaderboard/src' / name, output / 'modules' / name)
    (output / 'worker.mjs').write_text(candidate)
    # Fresh schema also works on current production base. Existing installations
    # with partial historical auth migrations must be inspected before applying.
    sql = (ROOT / 'leaderboard/migrations/0002_native_auth.sql').read_text()
    sql = sql.replace('  created_at INTEGER NOT NULL\n', "  created_at INTEGER NOT NULL,\n  presentation TEXT NOT NULL DEFAULT 'browser' CHECK (presentation IN ('browser', 'ios'))\n")
    # Fresh scoped schema includes v2 columns; existing production receives
    # the explicit one-time upgrade file, never a re-created table.
    sql = sql.replace("  presentation TEXT NOT NULL DEFAULT 'browser' CHECK (presentation IN ('browser', 'ios'))\n",
        "  presentation TEXT NOT NULL DEFAULT 'browser' CHECK (presentation IN ('browser', 'ios')),\n"
        "  flow_version INTEGER NOT NULL DEFAULT 1 CHECK (flow_version IN (1, 2)),\n"
        "  callback_code_hash TEXT,\n  callback_code_expires_at INTEGER,\n  callback_code_consumed_at INTEGER\n")
    shutil.copy2(ROOT / 'leaderboard/migrations/0008_native_auth_callback_code.sql', output / 'native-auth-v2-upgrade.sql')
    retirement = (ROOT / 'leaderboard/migrations/0006_account_retirement.sql').read_text()
    retirement = re.sub(r'CREATE TRIGGER IF NOT EXISTS retired_(?:store_accounts|checkouts|purchases)_(?:insert|update)\n.*?END;\n', '', retirement, flags=re.S)
    retirement = retirement.replace('  clerk_deleted_at TEXT\n', '  clerk_deleted_at TEXT,\n  last_identity_attempt_at TEXT\n')
    sql += '\n' + retirement + '\n' + (ROOT / 'leaderboard/migrations/0007_deletion_receipts.sql').read_text()
    (output / 'native-accounts-schema.sql').write_text(sql)
    # Confirmed production console on Oct9: only scores/profiles/saves. This
    # fixture excludes unreleased development schema additions.
    base_schema = (ROOT / 'leaderboard/schema.sql').read_text()
    base_schema = re.sub(r'CREATE TABLE IF NOT EXISTS account_retirements \(.*?\);', '', base_schema, flags=re.S)
    (output / 'production-base-schema.sql').write_text(base_schema)

    config = '''name = "waddle-wars-leaderboard"
main = "worker.mjs"
compatibility_date = "2026-08-01"
account_id = "592217b354c4f0813d17c0818429ef93"
workers_dev = true
keep_vars = true

[[routes]]
pattern = "waddlewars.io/api/commerce/native-auth/*"
zone_name = "waddlewars.io"

[[d1_databases]]
binding = "DB"
database_name = "waddle-wars"
database_id = "2be032bd-7d5b-4958-a310-7f48607fa2d7"

[triggers]
crons = ["17 * * * *"]

[vars]
CLERK_ISSUER = "https://stunning-hen-13.clerk.accounts.dev"
NATIVE_ACCOUNTS_ENABLED = "true"
NATIVE_CLERK_ISSUER = "https://clerk.waddlewars.io"

[[ratelimits]]
name = "COMMERCE_AUTH_LIMITER"
namespace_id = "2041"
simple = { limit = 120, period = 60 }

[[ratelimits]]
name = "ACCOUNT_DELETION_LIMITER"
namespace_id = "2042"
simple = { limit = 10, period = 60 }
'''
    (output / 'wrangler.toml').write_text(config)
    receipt = {'state': 'prepared_not_deployed', 'baseline_sha256': BASELINE_SHA256,
               'baseline_version': BASELINE_VERSION, 'preserved_functions': preserved,
               'candidate_sha256': digest(candidate.encode()), 'schema_sha256': digest(sql.encode()),
               'module_hashes': {name: digest((output / 'modules' / name).read_bytes()) for name in modules},
               'required_secret_binding': 'NATIVE_CLERK_SECRET_KEY',
               'required_native_origin': 'https://waddlewars.io',
               'production_schema_changed': False, 'deployed': False}
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.baseline, args.output), indent=2))
