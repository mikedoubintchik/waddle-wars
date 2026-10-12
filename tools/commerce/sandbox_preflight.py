#!/usr/bin/env python3
"""Read-only, public-configuration guard. No credentials or provider API calls.

Requires Python 3.11+. Environment inspection uses key names only. A passing
report validates declarations, not deployment, secret contents or purchase E2E.
"""
from __future__ import annotations

import argparse
import base64
import binascii
import json
import os
from pathlib import Path
import re
import sys
import tomllib
from urllib.parse import urlsplit, urlunsplit
import uuid

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
MAX_PUBLIC_BYTES = 32768
REQUIRED_SECRET_NAMES = frozenset({"STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET"})
REQUIRED_EVENTS = frozenset({
    "checkout.session.completed", "checkout.session.async_payment_succeeded",
    "charge.refunded", "charge.dispute.created", "charge.dispute.closed",
})
ASSERTIONS = (
    "dedicated_database_confirmed", "leaderboard_schema_and_commerce_migrations_applied",
    "frontend_uses_sandbox_api_and_test_clerk", "backend_jwks_and_frontend_sign_in_verified",
    "two_distinct_test_accounts_available", "stripe_test_credentials_account_confirmed",
    "stripe_test_webhook_registration_confirmed",
)
CONFIG_FIELDS = frozenset({"name", "main", "compatibility_date", "workers_dev", "preview_urls", "d1_databases", "vars"})
VAR_FIELDS = frozenset({"COMMERCE_ENABLED", "COMMERCE_MODE", "COMMERCE_APPLE_SALES_ENABLED",
    "COMMERCE_GOOGLE_SALES_ENABLED", "APPLE_SERVER_NOTIFICATIONS_ENABLED", "COMMERCE_NATIVE_AUTH_ENABLED",
    "CLERK_ISSUER", "COMMERCE_ALLOWED_ORIGINS", "COMMERCE_SUCCESS_URL", "COMMERCE_CANCEL_URL", "COMMERCE_STRIPE_PRICES"})
POLICY_FIELDS = frozenset({"schema_version", "status", "worker_name", "worker_origin", "database_name",
    "database_id", "approved_web_origins", "approved_success_urls", "approved_cancel_urls", "clerk_test_issuer",
    "clerk_test_publishable_key", "stripe_test_account_id", "stripe_credentials_mode", "stripe_webhook_url",
    "stripe_webhook_events", "setup_assertions"})
PRODUCTION_FIELDS = frozenset({"name", "main", "compatibility_date", "account_id", "workers_dev", "d1_databases", "vars"})
PRODUCTION_VAR_FIELDS = frozenset({"CLERK_ISSUER", "COMMERCE_ENABLED", "COMMERCE_APPLE_SALES_ENABLED",
    "COMMERCE_GOOGLE_SALES_ENABLED", "APPLE_SERVER_NOTIFICATIONS_ENABLED"})
UNVERIFIED = [
    "Secret names alone do not prove nonempty values, test-key mode or provider account ownership.",
    "Operator setup assertions do not prove deployed bindings, schema, JWT acceptance or webhook delivery.",
    "Actual sandbox purchase, grant, fresh-session restore, refund, replay and account isolation remain required.",
    "No native billing or store-launch acceptance is included.",
]
PRODUCTION_ORIGINS = frozenset({"https://waddlewars.ninjaconsulting.ai",
    "https://waddle-wars-leaderboard.ninjaconsultingllc.workers.dev"})


def _dict(value):
    return value if isinstance(value, dict) else {}


def _https(value, *, origin_only=False):
    if not isinstance(value, str) or not value or value != value.strip() or len(value) > 2048:
        return None
    if any(ord(char) <= 32 or ord(char) == 127 for char in value) or "\\" in value:
        return None
    try:
        parts = urlsplit(value)
        if parts.scheme != "https" or not value.startswith("https://") or not parts.hostname or parts.username or parts.password or parts.fragment:
            return None
        if "*" in parts.netloc or "%" in parts.netloc or parts.port is not None or parts.netloc != parts.hostname:
            return None
        host = parts.hostname
        if not re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", host) or "." not in host or ".." in host:
            return None
        if any(len(label) > 63 or not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", label) for label in host.split(".")):
            return None
        if host in {"localhost", "127.0.0.1", "0.0.0.0"} or host.endswith(".localhost"):
            return None
        origin = urlunsplit((parts.scheme, parts.netloc, "", "", ""))
        if origin_only and value != origin:
            return None
        return origin
    except (ValueError, TypeError):
        return None


def _string_list(value):
    return isinstance(value, list) and bool(value) and all(isinstance(item, str) for item in value) and len(value) == len(set(value))


def _uuid(value):
    try:
        return isinstance(value, str) and str(uuid.UUID(value)) == value
    except (ValueError, TypeError, AttributeError):
        return False


def _test_key_matches_issuer(key, issuer):
    # Match this project's public Clerk-key host payload; not an auth proof.
    if not isinstance(key, str) or not re.fullmatch(r"pk_test_[A-Za-z0-9]+", key) or not _https(issuer, origin_only=True):
        return False
    try:
        payload = key.removeprefix("pk_test_")
        host = base64.b64decode(payload + "=" * (-len(payload) % 4), validate=True).decode("ascii")
        return host == f"{urlsplit(issuer).hostname}$"
    except (ValueError, UnicodeError, binascii.Error):
        return False


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate_public_key")
        result[key] = value
    return result


def _json(text):
    return json.loads(text, object_pairs_hook=_unique_object)


def production_public_preflight(config):
    """Copy gate for the explicitly reviewed tracked public Wrangler schema.

    Unknown fields, including quoted TOML secret keys and nested bindings, must
    be reviewed rather than copied into test snapshots. Never report values.
    """
    config = _dict(config)
    variables = _dict(config.get("vars"))
    bindings = config.get("d1_databases")
    bindings = bindings if isinstance(bindings, list) else []
    checks = [
        {"id": "reviewed_production_top_level_schema", "passed": set(config) == PRODUCTION_FIELDS},
        {"id": "reviewed_production_vars_schema", "passed": set(variables) == PRODUCTION_VAR_FIELDS},
        {"id": "reviewed_public_worker_fields", "passed":
            isinstance(config.get("name"), str) and bool(re.fullmatch(r"[a-z][a-z0-9-]{2,62}", config["name"]))
            and config.get("main") == "src/worker.js"
            and isinstance(config.get("compatibility_date"), str) and bool(re.fullmatch(r"\d{4}-\d{2}-\d{2}", config["compatibility_date"]))
            and isinstance(config.get("account_id"), str) and bool(re.fullmatch(r"[a-f0-9]{32}", config["account_id"]))
            and type(config.get("workers_dev")) is bool},
        {"id": "reviewed_public_d1_fields", "passed": len(bindings) == 1 and all(isinstance(db, dict)
            and set(db) == {"binding", "database_name", "database_id"} and db.get("binding") == "DB"
            and isinstance(db.get("database_name"), str) and bool(re.fullmatch(r"[a-z][a-z0-9-]{2,62}", db["database_name"]))
            and _uuid(db.get("database_id")) for db in bindings)},
        {"id": "reviewed_public_var_values", "passed": bool(_https(variables.get("CLERK_ISSUER"), origin_only=True))
            and all(variables.get(key) in ("true", "false") for key in PRODUCTION_VAR_FIELDS - {"CLERK_ISSUER"})},
    ]
    failed = [item["id"] for item in checks if not item["passed"]]
    return {"schema_version": 1, "status": "public_config_schema_passed" if not failed else "blocked",
        "public_config_schema_passed": not failed, "store_ready": False, "checks": checks,
        "failed_checks": failed, "secret_values_reported": False, "provider_calls_made": False}


def preflight(config, policy, production, observed, catalog, *, secret_names=frozenset(), config_path=None):
    """Accept public objects plus credential NAMES. Never accept credential values."""
    checks = []

    def check(identifier, passed):
        checks.append({"id": identifier, "passed": bool(passed)})

    config, policy, production, observed, catalog = map(_dict, (config, policy, production, observed, catalog))
    variables = _dict(config.get("vars"))
    check("production_reference_public_schema", production_public_preflight(production)["public_config_schema_passed"])
    check("public_schema_only", bool(config) and set(config) <= CONFIG_FIELDS and set(variables) == VAR_FIELDS
          and set(policy) == POLICY_FIELDS and policy.get("schema_version") == 1)
    check("prepared_undeployed_declaration", policy.get("status") == "prepared_undeployed")
    worker = config.get("name")
    check("dedicated_worker", isinstance(worker, str) and re.fullmatch(r"[a-z][a-z0-9-]{1,54}-sandbox", worker)
          and worker == policy.get("worker_name") and worker != production.get("name"))
    worker_origin = policy.get("worker_origin")
    check("sandbox_worker_origin", bool(_https(worker_origin, origin_only=True))
          and worker_origin not in PRODUCTION_ORIGINS and isinstance(worker, str)
          and urlsplit(worker_origin).hostname.split(".")[0] == worker)
    check("worker_endpoint_policy", config.get("workers_dev") is True and config.get("preview_urls") is False)
    runtime = ROOT / "leaderboard/src/worker.js"
    migrations = ROOT / "leaderboard/migrations"
    base = Path(config_path).resolve().parent if config_path else HERE
    try:
        main_correct = isinstance(config.get("main"), str) and (base / config["main"]).resolve() == runtime
    except (OSError, ValueError):
        main_correct = False
    check("canonical_worker_source", main_correct)
    check("canonical_compatibility_date", config.get("compatibility_date") == production.get("compatibility_date"))
    bindings = config.get("d1_databases")
    database = _dict(bindings[0]) if isinstance(bindings, list) and len(bindings) == 1 else {}
    production_dbs = production.get("d1_databases", [])
    production_dbs = production_dbs if isinstance(production_dbs, list) else []
    production_ids = {db.get("database_id") for db in production_dbs if isinstance(db, dict)}
    production_names = {db.get("database_name") for db in production_dbs if isinstance(db, dict)}
    name, identifier = database.get("database_name"), database.get("database_id")
    check("only_isolated_d1_binding", set(database) == {"binding", "database_name", "database_id", "migrations_dir"}
          and database.get("binding") == "DB" and _uuid(identifier) and identifier not in production_ids
          and identifier == policy.get("database_id") and isinstance(name, str)
          and re.fullmatch(r"[a-z][a-z0-9-]{1,54}-sandbox", name) and name not in production_names
          and name == policy.get("database_name"))
    try:
        migration_correct = isinstance(database.get("migrations_dir"), str) and (base / database["migrations_dir"]).resolve() == migrations
    except (OSError, ValueError):
        migration_correct = False
    check("canonical_migration_directory", migration_correct)
    check("web_test_mode_enabled", variables.get("COMMERCE_MODE") == "test" and variables.get("COMMERCE_ENABLED") == "true")
    check("native_flows_disabled", all(variables.get(name) == "false" for name in (
        "COMMERCE_APPLE_SALES_ENABLED", "COMMERCE_GOOGLE_SALES_ENABLED", "APPLE_SERVER_NOTIFICATIONS_ENABLED", "COMMERCE_NATIVE_AUTH_ENABLED")))
    origins = policy.get("approved_web_origins")
    valid_origins = _string_list(origins) and all(_https(item, origin_only=True) and item not in PRODUCTION_ORIGINS for item in origins)
    configured_origins = variables.get("COMMERCE_ALLOWED_ORIGINS")
    configured_origins = configured_origins.split(",") if isinstance(configured_origins, str) else []
    check("explicit_exact_origin_allowlist", valid_origins and len(configured_origins) == len(origins)
          and set(configured_origins) == set(origins) and len(set(configured_origins)) == len(configured_origins))
    for suffix, policy_name in (("SUCCESS", "approved_success_urls"), ("CANCEL", "approved_cancel_urls")):
        allowed = policy.get(policy_name)
        value = variables.get(f"COMMERCE_{suffix}_URL")
        check(f"exact_{suffix.lower()}_return_allowlist", valid_origins and _string_list(allowed)
              and all(_https(item) in origins for item in allowed) and value in allowed)
    issuer = variables.get("CLERK_ISSUER")
    publishable = policy.get("clerk_test_publishable_key")
    check("explicit_test_clerk_auth", bool(_https(issuer, origin_only=True)) and issuer == policy.get("clerk_test_issuer")
          and issuer.endswith(".clerk.accounts.dev") and _test_key_matches_issuer(publishable, issuer))
    expected = _dict(observed.get("products"))
    products = catalog.get("products", [])
    products = products if isinstance(products, list) else []
    valid_product_shapes = bool(products) and all(isinstance(product, dict)
        and isinstance(product.get("id"), str) and bool(product["id"])
        and product.get("currency") == "usd" and type(product.get("price_minor")) is int
        and product["price_minor"] > 0 for product in products)
    catalog_ids = {product["id"] for product in products} if valid_product_shapes else set()
    observed_valid = observed.get("mode") == "test" and observed.get("live_sales_enabled") is False
    observed_valid = observed_valid and valid_product_shapes and len(products) == len(catalog_ids) and set(expected) == catalog_ids
    observed_valid = observed_valid and isinstance(observed.get("account_id"), str) and bool(re.fullmatch(r"acct_[A-Za-z0-9]+", observed["account_id"]))
    observed_valid = observed_valid and all(isinstance(row, dict) and row.get("currency") == product.get("currency")
        and type(row.get("price_minor")) is int and row.get("price_minor") == product.get("price_minor")
        and isinstance(row.get("stripe_price_id"), str)
        and bool(re.fullmatch(r"price_[A-Za-z0-9]+", row.get("stripe_price_id", "")))
        for product in products if isinstance(product, dict) for row in [expected.get(product.get("id"), {})])
    check("observed_test_catalog_contract", observed_valid)
    try:
        prices = _json(variables.get("COMMERCE_STRIPE_PRICES", ""))
    except (ValueError, TypeError):
        prices = None
    check("exact_observed_test_prices", observed_valid and isinstance(prices, dict)
          and prices == {product_id: row["stripe_price_id"] for product_id, row in expected.items()})
    check("declared_test_stripe_account", observed_valid and policy.get("stripe_test_account_id") == observed.get("account_id")
          and policy.get("stripe_credentials_mode") == "test")
    check("credential_names_present_only", REQUIRED_SECRET_NAMES <= set(secret_names))
    check("exact_test_webhook_endpoint", bool(_https(worker_origin, origin_only=True))
          and policy.get("stripe_webhook_url") == f"{worker_origin}/api/commerce/stripe/webhook")
    events = policy.get("stripe_webhook_events")
    check("required_webhook_events", _string_list(events) and set(events) == REQUIRED_EVENTS)
    assertions = _dict(policy.get("setup_assertions"))
    check("setup_assertions_schema", set(assertions) == set(ASSERTIONS))
    for name in ASSERTIONS:
        check(name, assertions.get(name) is True)
    failed = [item["id"] for item in checks if not item["passed"]]
    return {"schema_version": 1,
        "status": "configuration_prerequisites_passed_not_e2e" if not failed else "blocked",
        "configuration_prerequisites_passed": not failed, "store_ready": False,
        "e2e_verified": False, "deployment_verified": False, "secret_values_read": False,
        "provider_calls_made": False, "checks": checks, "failed_checks": failed, "unverified": list(UNVERIFIED)}


def _public_file(path, suffix):
    """Only explicitly public-named config inputs; never .env/credential files."""
    path = Path(path)
    if not path.name.endswith(suffix) or path.is_symlink() or path.stat().st_size > MAX_PUBLIC_BYTES:
        raise ValueError("invalid_public_input")
    return path.read_text(encoding="utf-8")


def _production_public_file(path):
    path = Path(path)
    if path.name != "wrangler.toml" or path.is_symlink() or path.stat().st_size > MAX_PUBLIC_BYTES:
        raise ValueError("invalid_public_input")
    return path.read_text(encoding="utf-8")


def main(argv=None):
    class PublicArgumentParser(argparse.ArgumentParser):
        def error(self, _message):
            # Unexpected arguments might be accidentally pasted credentials.
            self.exit(2, "Invalid arguments; only public --config/--policy paths are accepted.\n")

    parser = PublicArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--policy", type=Path)
    parser.add_argument("--check-production-public-config", type=Path,
        help="Read-only schema gate before copying the explicitly public tracked wrangler.toml")
    args = parser.parse_args(argv)
    if args.check_production_public_config is not None:
        if args.config is not None or args.policy is not None:
            parser.error("conflicting modes")
        try:
            report = production_public_preflight(tomllib.loads(_production_public_file(args.check_production_public_config)))
        except (OSError, UnicodeError, ValueError, TypeError, KeyError):
            report = {"schema_version": 1, "status": "blocked", "public_config_schema_passed": False,
                "store_ready": False, "failed_checks": ["production_public_input_invalid"], "secret_values_reported": False}
        print(json.dumps(report, indent=2, sort_keys=True))
        return 0 if report.get("public_config_schema_passed") else 2
    args.config = args.config or HERE / "wrangler.public.sandbox.toml"
    args.policy = args.policy or HERE / "policy.public.sandbox.json"
    try:
        config = tomllib.loads(_public_file(args.config, ".public.sandbox.toml"))
        policy = _json(_public_file(args.policy, ".public.sandbox.json"))
        production = tomllib.loads(_production_public_file(ROOT / "leaderboard/wrangler.toml"))
        observed = _json((ROOT / "data/commerce/stripe_test_products.json").read_text(encoding="utf-8"))
        catalog = _json((ROOT / "data/commerce/catalog.json").read_text(encoding="utf-8"))
        report = preflight(config, policy, production, observed, catalog,
            secret_names=frozenset(os.environ), config_path=args.config)
    except (OSError, UnicodeError, ValueError, TypeError, KeyError):
        # Parser exceptions may contain input lines. Never emit their contents.
        report = {"schema_version": 1, "status": "blocked", "store_ready": False,
            "e2e_verified": False, "secret_values_read": False, "provider_calls_made": False,
            "failed_checks": ["public_input_or_reference_invalid"]}
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report.get("configuration_prerequisites_passed") else 2


if __name__ == "__main__":
    sys.exit(main())
