#!/usr/bin/env python3
"""Build the schema-neutral leaderboard hotfix from the verified live baseline.

This does not deploy or migrate anything. It preserves the deployed cloud-save
handlers and authentication bindings; unreleased commerce/account lifecycle
features in the development Worker are intentionally not part of this release.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BASELINE_SHA256 = "ca194e211cf11c6bc74b94e9eab9a1c4a0ec4980ede9423bafa03c3c352629d4"
BASELINE_VERSION = "e4e238cf-81ed-46aa-b0d9-549a980c6763"
ISSUER = "https://stunning-hen-13.clerk.accounts.dev"
ACCOUNT = "592217b354c4f0813d17c0818429ef93"
DATABASE = "2be032bd-7d5b-4958-a310-7f48607fa2d7"
TRANSFER = ["getJwk", "displayName", "handleLeaderboard", "handleSubmit", "handleProfile"]


def digest(value):
    return hashlib.sha256(value).hexdigest()


def function(source, name):
    matches = list(re.finditer(r"^(?:async )?function " + re.escape(name) + r"\([^\n]*\).*?^}",
                               source, re.M | re.S))
    if len(matches) != 1:
        raise ValueError(f"expected exactly one top-level {name} function")
    return matches[0]


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError(f"baseline contract changed: {old[:80]}")
    return source.replace(old, new, 1)


def prepare(baseline, version_file, output):
    original = baseline.read_bytes()
    if digest(original) != BASELINE_SHA256:
        raise ValueError("deployed baseline hash mismatch; inspect the new deployment first")
    version = json.loads(version_file.read_text())
    if version["id"] != BASELINE_VERSION:
        raise ValueError("unexpected live version")
    bindings = {binding["name"]: binding for binding in version["resources"]["bindings"]}
    if bindings["CLERK_ISSUER"].get("text") != ISSUER or bindings["DB"].get("database_id") != DATABASE:
        raise ValueError("live issuer/database mismatch; never silently reconfigure authentication")
    if set(bindings) != {"CLERK_ISSUER", "CLERK_SECRET_KEY", "DB"}:
        raise ValueError("live bindings changed; inspect before preparing another release")
    if output.exists():
        raise ValueError("output already exists")
    current_path = ROOT / "leaderboard/src/worker.js"
    current_bytes = current_path.read_bytes()
    current = current_bytes.decode()
    candidate = original.decode()
    start = candidate.index("var MODES =")
    end = candidate.index("var CORS =")
    constants = current[current.index("const RACE_COURSES ="):current.index("const CORS =")]
    candidate = candidate[:start] + constants + candidate[end:]
    candidate = replace_once(candidate, "var jwksCache = { keys: null, fetchedAt: 0 };",
                             "var jwksCache = { issuer: null, keys: null, fetchedAt: 0 };")
    transferred = {}
    for name in TRANSFER:
        new = function(current, name).group()
        old = function(candidate, name)
        candidate = candidate[:old.start()] + new + candidate[old.end():]
        transferred[name] = digest(new.encode())
    obsolete = function(candidate, "clerkName")
    candidate = candidate[:obsolete.start()] + candidate[obsolete.end():]
    candidate = replace_once(candidate, '__name(clerkName, "clerkName");\n', "")
    profile_get = function(current, "handleProfileGet").group()
    candidate = candidate.replace("var MAX_SAVE_BYTES =", profile_get + "\nvar MAX_SAVE_BYTES =", 1)
    old_route = '      if (url.pathname === "/api/profile" && request.method === "POST") {'
    candidate = replace_once(candidate, old_route,
        '      if (url.pathname === "/api/profile" && request.method === "GET") {\n'
        '        return await handleProfileGet(env, request);\n      }\n' + old_route)
    candidate = replace_once(candidate, 'return json({ error: "internal", detail: String(e) }, 500);',
                             'return json({ error: "internal" }, 500);')
    candidate = candidate.replace("//# sourceMappingURL=worker.js.map\n", "")
    unchanged = {}
    for name in ["verifyClerkJwt", "authFromRequest", "handleSaveGet", "handleSavePut"]:
        old = function(original.decode(), name).group()
        if function(candidate, name).group() != old:
            raise ValueError(f"unrelated deployed behavior changed: {name}")
        unchanged[name] = digest(old.encode())
    for forbidden in ["account_retirements", "handleCommerce", "handleAccountLifecycle", "commerce_"]:
        if forbidden in candidate:
            raise ValueError(f"unreleased feature leaked into scoped candidate: {forbidden}")
    output.mkdir(parents=True)
    (output / "worker.mjs").write_text(candidate)
    config = f'''name = "waddle-wars-leaderboard"
main = "worker.mjs"
compatibility_date = "2026-08-01"
account_id = "{ACCOUNT}"
workers_dev = true
keep_vars = true

[vars]
CLERK_ISSUER = "{ISSUER}"

[[d1_databases]]
binding = "DB"
database_name = "waddle-wars"
database_id = "{DATABASE}"
'''
    (output / "wrangler.toml").write_text(config)
    subprocess.run(["node", "--check", str(output / "worker.mjs")], check=True)
    receipt = {"baseline_version": BASELINE_VERSION, "baseline_sha256": BASELINE_SHA256,
        "source_sha256": digest(current_bytes), "helper_sha256": digest(Path(__file__).read_bytes()),
        "candidate_sha256": digest(candidate.encode()), "config_sha256": digest(config.encode()),
        "transferred_functions": transferred, "preserved_deployed_functions": unchanged,
        "requires_schema_migration": False, "commerce_enabled": False,
        "account_deletion_enabled": False, "issuer": ISSUER, "database_id": DATABASE,
        "live_schema_inspection": "separate read-only receipt; no production test writes"}
    (output / "release-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("version", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.baseline, args.version, args.output), indent=2))
