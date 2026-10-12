"""Synthetic host fixtures only. No provider, deployment, credential or DB I/O.

All example.invalid origins, Clerk test host and 0000... UUIDs below are
fictional test bindings, not created or usable cloud resources.
"""
import base64
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
spec = importlib.util.spec_from_file_location("sandbox_preflight", HERE / "sandbox_preflight.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


def fixture():
    config = tomllib.loads((HERE / "wrangler.public.sandbox.toml").read_text())
    policy = json.loads((HERE / "policy.public.sandbox.json").read_text())
    config.update(name="fixture-commerce-sandbox")
    config["d1_databases"][0].update(database_name="fixture-commerce-sandbox",
        database_id="00000000-0000-4000-8000-000000000001")
    origin = "https://game.example.invalid"
    issuer = "https://fixture.clerk.accounts.dev"
    config["vars"].update(CLERK_ISSUER=issuer, COMMERCE_ALLOWED_ORIGINS=origin,
        COMMERCE_SUCCESS_URL=f"{origin}/?purchase=return", COMMERCE_CANCEL_URL=f"{origin}/?purchase=cancel")
    policy.update(status="prepared_undeployed", worker_name=config["name"],
        worker_origin="https://fixture-commerce-sandbox.example.invalid",
        database_name=config["d1_databases"][0]["database_name"], database_id=config["d1_databases"][0]["database_id"],
        approved_web_origins=[origin], approved_success_urls=[config["vars"]["COMMERCE_SUCCESS_URL"]],
        approved_cancel_urls=[config["vars"]["COMMERCE_CANCEL_URL"]], clerk_test_issuer=issuer,
        clerk_test_publishable_key="pk_test_" + base64.b64encode(b"fixture.clerk.accounts.dev$").decode().rstrip("="),
        stripe_webhook_url="https://fixture-commerce-sandbox.example.invalid/api/commerce/stripe/webhook",
        setup_assertions={key: True for key in helper.ASSERTIONS})
    return config, policy


class SandboxPreflightTests(unittest.TestCase):
    def setUp(self):
        self.config, self.policy = fixture()
        self.production = tomllib.loads((ROOT / "leaderboard/wrangler.toml").read_text())
        self.observed = json.loads((ROOT / "data/commerce/stripe_test_products.json").read_text())
        self.catalog = json.loads((ROOT / "data/commerce/catalog.json").read_text())

    def report(self, **extra):
        return helper.preflight(self.config, self.policy, self.production, self.observed, self.catalog,
            **{"secret_names": helper.REQUIRED_SECRET_NAMES, **extra})

    def blocked(self, identifier):
        result = self.report()
        self.assertFalse(result["configuration_prerequisites_passed"])
        self.assertIn(identifier, result["failed_checks"])
        self.assertFalse(result["store_ready"])

    def test_fictional_configuration_pass_never_claims_deployment_or_e2e(self):
        result = self.report()
        self.assertTrue(result["configuration_prerequisites_passed"])
        self.assertEqual(result["status"], "configuration_prerequisites_passed_not_e2e")
        for key in ("store_ready", "e2e_verified", "deployment_verified", "secret_values_read", "provider_calls_made"):
            self.assertIs(result[key], False)
        self.assertEqual(len(result["unverified"]), 4)

    def test_default_template_is_intentionally_blocked(self):
        self.config = tomllib.loads((HERE / "wrangler.public.sandbox.toml").read_text())
        self.policy = json.loads((HERE / "policy.public.sandbox.json").read_text())
        self.blocked("prepared_undeployed_declaration")
        self.assertIn("only_isolated_d1_binding", self.report()["failed_checks"])

    def test_current_production_config_is_rejected(self):
        self.config = deepcopy(self.production)
        self.blocked("dedicated_worker")

    def test_actual_production_public_schema_passes_copy_gate_only(self):
        result = helper.production_public_preflight(self.production)
        self.assertTrue(result["public_config_schema_passed"])
        self.assertFalse(result["store_ready"])
        self.assertNotIn(self.production["d1_databases"][0]["database_id"], json.dumps(result))

    def test_production_public_copy_gate_rejects_unknown_and_nested_keys(self):
        for key in ("env", "services", "secrets", "preview_urls"):
            with self.subTest(key=key):
                changed = deepcopy(self.production)
                changed[key] = {"PRIVATE_KEY": "fictional-copy-canary"}
                result = helper.production_public_preflight(changed)
                self.assertFalse(result["public_config_schema_passed"])
                self.assertNotIn("fictional-copy-canary", json.dumps(result))
        changed = deepcopy(self.production)
        changed["d1_databases"][0]["secret"] = "fictional-copy-canary"
        self.assertFalse(helper.production_public_preflight(changed)["public_config_schema_passed"])

    def test_extra_public_production_database_requires_review(self):
        self.production["d1_databases"].append(deepcopy(self.production["d1_databases"][0]))
        self.assertFalse(helper.production_public_preflight(self.production)["public_config_schema_passed"])

    def test_production_public_copy_gate_rejects_plain_quoted_and_nested_secret_keys(self):
        raw = (ROOT / "leaderboard/wrangler.toml").read_text()
        for suffix in ('STRIPE_SECRET_KEY = "fictional-copy-canary"\n',
                       '"STRIPE_SECRET_KEY" = "fictional-copy-canary"\n',
                       '[vars.private]\n"key" = "fictional-copy-canary"\n'):
            with self.subTest(suffix=suffix):
                result = helper.production_public_preflight(tomllib.loads(raw + suffix))
                self.assertFalse(result["public_config_schema_passed"])
                self.assertNotIn("fictional-copy-canary", json.dumps(result))

    def test_unreviewed_production_reference_blocks_sandbox_preflight(self):
        self.production["vars"]["UNKNOWN_KEY"] = "fictional-copy-canary"
        self.blocked("production_reference_public_schema")

    def test_production_database_id_rejected_even_with_sandbox_name(self):
        identifier = self.production["d1_databases"][0]["database_id"]
        self.config["d1_databases"][0]["database_id"] = identifier
        self.policy["database_id"] = identifier
        self.blocked("only_isolated_d1_binding")

    def test_production_database_name_rejected_even_with_new_id(self):
        name = self.production["d1_databases"][0]["database_name"]
        self.config["d1_databases"][0]["database_name"] = name
        self.policy["database_name"] = name
        self.blocked("only_isolated_d1_binding")

    def test_placeholder_and_mismatched_database_ids_rejected(self):
        for value in ("REPLACE_WITH_NEW_SANDBOX_D1_ID", "not-a-uuid", "00000000-0000-4000-8000-000000000002"):
            with self.subTest(value=value):
                self.config["d1_databases"][0]["database_id"] = value
                self.blocked("only_isolated_d1_binding")

    def test_extra_database_or_override_refused(self):
        self.config["d1_databases"].append(deepcopy(self.config["d1_databases"][0]))
        self.blocked("only_isolated_d1_binding")

    def test_worker_names_and_origins_must_match(self):
        for name in (self.production["name"], "fixture-production", "REPLACE_WITH_WORKER"):
            with self.subTest(name=name):
                self.config["name"] = name
                self.blocked("dedicated_worker")
        self.config, self.policy = fixture()
        self.policy["worker_origin"] = "https://different-sandbox.example.invalid"
        self.blocked("sandbox_worker_origin")

    def test_live_mode_and_disabled_commerce_block_e2e(self):
        for mode in ("live", "TEST", None):
            with self.subTest(mode=mode):
                self.config["vars"]["COMMERCE_MODE"] = mode
                self.blocked("web_test_mode_enabled")
        self.config, self.policy = fixture()
        self.config["vars"]["COMMERCE_ENABLED"] = "false"
        self.blocked("web_test_mode_enabled")

    def test_every_native_gate_must_be_explicitly_false(self):
        for gate in ("COMMERCE_APPLE_SALES_ENABLED", "COMMERCE_GOOGLE_SALES_ENABLED",
                     "APPLE_SERVER_NOTIFICATIONS_ENABLED", "COMMERCE_NATIVE_AUTH_ENABLED"):
            for value in ("true", False, None):
                with self.subTest(gate=gate, value=value):
                    self.config, self.policy = fixture()
                    self.config["vars"][gate] = value
                    self.blocked("native_flows_disabled")

    def test_unknown_bindings_nested_environment_and_inline_secrets_rejected(self):
        for key, value in (("services", [{"binding": "APPLE_RECEIPT_VERIFIER"}]), ("env", {"live": {}}),
                           ("routes", [{"pattern": "production.example.invalid/*"}])):
            with self.subTest(key=key):
                self.config, self.policy = fixture()
                self.config[key] = value
                self.blocked("public_schema_only")
        self.config, self.policy = fixture()
        self.config["vars"]["STRIPE_SECRET_KEY"] = "fictional-inline-value-never-output"
        self.blocked("public_schema_only")
        self.assertNotIn("fictional-inline-value-never-output", json.dumps(self.report()))

    def test_all_approved_origins_required_exactly_no_wildcards(self):
        for origins in ([], ["https://*.example.invalid"], ["http://game.example.invalid"],
                        ["https://game.example.invalid/path"], ["https://user:password@game.example.invalid"],
                        ["https://game.example.invalid:444"], ["https://game.example.invalid#fragment"],
                        ["https://game.example.invalid", "https://game.example.invalid"],
                        ["https://waddlewars.ninjaconsulting.ai"]):
            with self.subTest(origins=origins):
                self.policy["approved_web_origins"] = origins
                self.config["vars"]["COMMERCE_ALLOWED_ORIGINS"] = ",".join(origins)
                self.blocked("explicit_exact_origin_allowlist")

    def test_unapproved_duplicate_and_normalized_origin_changes_rejected(self):
        for configured in ("https://evil.example.invalid", "https://game.example.invalid,https://game.example.invalid",
                           " https://game.example.invalid", "https://game.example.invalid/"):
            with self.subTest(configured=configured):
                self.config["vars"]["COMMERCE_ALLOWED_ORIGINS"] = configured
                self.blocked("explicit_exact_origin_allowlist")

    def test_production_origin_case_and_default_port_aliases_do_not_bypass_guard(self):
        for origin in ("https://WADDLEWARS.ninjaconsulting.ai", "https://waddlewars.ninjaconsulting.ai:443",
                       "HTTPS://waddlewars.ninjaconsulting.ai", "https://game.example.invalid:443",
                       "https://-bad.example.invalid", "https://" + "a" * 64 + ".example.invalid"):
            with self.subTest(origin=origin):
                self.policy["approved_web_origins"] = [origin]
                self.config["vars"]["COMMERCE_ALLOWED_ORIGINS"] = origin
                self.blocked("explicit_exact_origin_allowlist")

    def test_return_urls_need_separate_exact_approvals(self):
        for name in ("SUCCESS", "CANCEL"):
            with self.subTest(name=name):
                self.config, self.policy = fixture()
                self.config["vars"][f"COMMERCE_{name}_URL"] = "https://game.example.invalid/other-path"
                self.blocked(f"exact_{name.lower()}_return_allowlist")

    def test_return_allowlist_cannot_include_unapproved_origins_or_credentials(self):
        for url in ("https://evil.example.invalid/return", "https://u:p@game.example.invalid/return",
                    "https://game.example.invalid/return#token", "javascript:alert(1)"):
            with self.subTest(url=url):
                self.config["vars"]["COMMERCE_SUCCESS_URL"] = url
                self.policy["approved_success_urls"] = [url]
                self.blocked("exact_success_return_allowlist")

    def test_auth_requires_matching_public_test_key_and_issuer(self):
        for key in ("pk_live_fixture", "pk_test_wronghost", "REPLACE_WITH_KEY", None):
            with self.subTest(key=key):
                self.policy["clerk_test_publishable_key"] = key
                self.blocked("explicit_test_clerk_auth")
        self.config, self.policy = fixture()
        self.config["vars"]["CLERK_ISSUER"] = "https://other.clerk.accounts.dev"
        self.blocked("explicit_test_clerk_auth")

    def test_each_setup_assertion_is_required_true(self):
        for key in helper.ASSERTIONS:
            for value in (False, "true", None):
                with self.subTest(key=key, value=value):
                    self.config, self.policy = fixture()
                    self.policy["setup_assertions"][key] = value
                    self.blocked(key)

    def test_setup_assertions_cannot_silently_add_new_claims(self):
        self.policy["setup_assertions"]["e2e_passed"] = True
        self.blocked("setup_assertions_schema")

    def test_every_observed_price_id_required_no_extra_products(self):
        prices = json.loads(self.config["vars"]["COMMERCE_STRIPE_PRICES"])
        for mutation in ("wrong", "missing", "extra"):
            with self.subTest(mutation=mutation):
                changed = deepcopy(prices)
                if mutation == "wrong": changed["cozy_expedition"] = "price_other"
                elif mutation == "missing": changed.pop("cozy_expedition")
                else: changed["unapproved"] = "price_extra"
                self.config["vars"]["COMMERCE_STRIPE_PRICES"] = json.dumps(changed)
                self.blocked("exact_observed_test_prices")

    def test_duplicate_or_malformed_price_json_rejected(self):
        prices = self.config["vars"]["COMMERCE_STRIPE_PRICES"]
        for value in ("not JSON", "[]", prices[:-1] + ',"cozy_expedition":"price_fake"}'):
            with self.subTest(value=value):
                self.config["vars"]["COMMERCE_STRIPE_PRICES"] = value
                self.blocked("exact_observed_test_prices")

    def test_observation_mode_amount_or_catalog_drift_rejected(self):
        self.observed["mode"] = "live"
        self.blocked("observed_test_catalog_contract")
        self.observed["mode"] = "test"
        self.observed["products"]["cozy_expedition"]["price_minor"] = 1
        self.blocked("observed_test_catalog_contract")

    def test_malformed_catalog_field_types_report_blocked_without_exception(self):
        observed = deepcopy(self.observed)
        catalog = deepcopy(self.catalog)
        for value in (17, None, {}, [], True):
            with self.subTest(price=value):
                self.observed = deepcopy(observed)
                self.observed["products"]["cozy_expedition"]["stripe_price_id"] = value
                self.blocked("observed_test_catalog_contract")
            with self.subTest(product_id=value):
                self.observed = deepcopy(observed)
                self.catalog = deepcopy(catalog)
                self.catalog["products"][0]["id"] = value
                self.blocked("observed_test_catalog_contract")
        self.catalog = deepcopy(catalog)
        for value in ("299", True, None, [], {}):
            with self.subTest(amount=value):
                self.observed = deepcopy(observed)
                self.observed["products"]["cozy_expedition"]["price_minor"] = value
                self.blocked("observed_test_catalog_contract")

    def test_stripe_account_and_declared_credential_mode_must_match(self):
        self.policy["stripe_test_account_id"] = "acct_other"
        self.blocked("declared_test_stripe_account")
        self.policy["stripe_test_account_id"] = self.observed["account_id"]
        self.policy["stripe_credentials_mode"] = "live"
        self.blocked("declared_test_stripe_account")

    def test_missing_secret_names_block_without_values(self):
        for names in (set(), {"STRIPE_SECRET_KEY"}, {"STRIPE_WEBHOOK_SECRET"}):
            with self.subTest(names=names):
                self.assertIn("credential_names_present_only", self.report(secret_names=names)["failed_checks"])

    def test_secret_values_never_accessed_or_reported(self):
        class NamesOnly(dict):
            def __getitem__(self, key):
                raise AssertionError("Credential value accessed")
            def get(self, key, default=None):
                raise AssertionError("Credential value accessed")
            def values(self):
                raise AssertionError("Credential value accessed")
            def items(self):
                raise AssertionError("Credential value accessed")
        names = NamesOnly({key: "fictional-canary-do-not-read" for key in helper.REQUIRED_SECRET_NAMES})
        result = self.report(secret_names=names)
        self.assertTrue(result["configuration_prerequisites_passed"])
        self.assertNotIn("fictional-canary-do-not-read", json.dumps(result))

    def test_webhook_requires_exact_worker_route(self):
        for url in ("https://production.example.invalid/api/commerce/stripe/webhook",
                    self.policy["worker_origin"] + "/wrong", self.policy["stripe_webhook_url"] + "?secret=fixture"):
            with self.subTest(url=url):
                self.policy["stripe_webhook_url"] = url
                self.blocked("exact_test_webhook_endpoint")

    def test_all_runtime_webhook_events_required(self):
        self.policy["stripe_webhook_events"].remove("charge.refunded")
        self.blocked("required_webhook_events")

    def test_canonical_runtime_and_migration_paths_required(self):
        self.config["main"] = "../../apple-verifier/src/worker.mjs"
        self.blocked("canonical_worker_source")
        self.config, self.policy = fixture()
        self.config["d1_databases"][0]["migrations_dir"] = "../../leaderboard"
        self.blocked("canonical_migration_directory")

    def test_compatibility_and_preview_settings_cannot_drift(self):
        self.config["compatibility_date"] = "2000-01-01"
        self.blocked("canonical_compatibility_date")
        self.config["preview_urls"] = True
        self.blocked("worker_endpoint_policy")

    def test_private_names_symlinks_and_oversized_files_refused_before_read(self):
        with tempfile.TemporaryDirectory(prefix="ww-commerce-public-fixture-") as temporary:
            directory = Path(temporary)
            private = directory / ".envrc"
            with patch.object(Path, "read_text", side_effect=AssertionError("must not read")):
                with self.assertRaises(ValueError): helper._public_file(private, ".public.sandbox.toml")
            large = directory / "large.public.sandbox.toml"
            large.write_text("x" * (helper.MAX_PUBLIC_BYTES + 1))
            with patch.object(Path, "read_text", side_effect=AssertionError("must not read")):
                with self.assertRaises(ValueError): helper._public_file(large, ".public.sandbox.toml")
            link = directory / "link.public.sandbox.toml"
            link.symlink_to(large)
            with self.assertRaises(ValueError): helper._public_file(link, ".public.sandbox.toml")

    def test_cli_undeployed_template_fails_without_echoing_fake_environment_values(self):
        result = subprocess.run([sys.executable, str(HERE / "sandbox_preflight.py")], capture_output=True, text=True,
            env={"STRIPE_SECRET_KEY": "fictional-cli-canary", "STRIPE_WEBHOOK_SECRET": "fictional-cli-canary"})
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stdout)["status"], "blocked")
        self.assertNotIn("fictional-cli-canary", result.stdout + result.stderr)

    def test_cli_production_public_schema_gate_passes_actual_public_file(self):
        result = subprocess.run([sys.executable, str(HERE / "sandbox_preflight.py"), "--check-production-public-config",
            str(ROOT / "leaderboard/wrangler.toml")], capture_output=True, text=True, env={})
        self.assertEqual(result.returncode, 0)
        self.assertTrue(json.loads(result.stdout)["public_config_schema_passed"])

    def test_cli_production_gate_secret_parse_errors_never_echo_lines(self):
        with tempfile.TemporaryDirectory(prefix="ww-commerce-public-fixture-") as temporary:
            file = Path(temporary) / "wrangler.toml"
            for suffix in ('"STRIPE_SECRET_KEY" = "fictional-copy-canary"\n',
                           '[vars.private]\nkey = "fictional-copy-canary"\n',
                           'bad = "fictional-copy-canary\n'):
                with self.subTest(suffix=suffix):
                    file.write_text((ROOT / "leaderboard/wrangler.toml").read_text() + suffix)
                    result = subprocess.run([sys.executable, str(HERE / "sandbox_preflight.py"),
                        "--check-production-public-config", str(file)], capture_output=True, text=True, env={})
                    self.assertEqual(result.returncode, 2)
                    self.assertFalse(json.loads(result.stdout)["public_config_schema_passed"])
                    self.assertNotIn("fictional-copy-canary", result.stdout + result.stderr)

    def test_cli_passes_fictional_public_inputs_without_reading_fake_secret_values(self):
        with tempfile.TemporaryDirectory(prefix="ww-commerce-public-fixture-") as temporary:
            directory = Path(temporary)
            config_path = directory / "fixture.public.sandbox.toml"
            policy_path = directory / "fixture.public.sandbox.json"
            config = deepcopy(self.config)
            config["main"] = str(ROOT / "leaderboard/src/worker.js")
            config["d1_databases"][0]["migrations_dir"] = str(ROOT / "leaderboard/migrations")
            def value(item):
                return str(item).lower() if type(item) is bool else json.dumps(item)
            lines = [f"{key} = {value(item)}" for key, item in config.items() if key not in {"d1_databases", "vars"}]
            lines += ["\n[[d1_databases]]"] + [f"{key} = {value(item)}" for key, item in config["d1_databases"][0].items()]
            lines += ["\n[vars]"] + [f"{key} = {value(item)}" for key, item in config["vars"].items()]
            config_path.write_text("\n".join(lines))
            policy_path.write_text(json.dumps(self.policy))
            result = subprocess.run([sys.executable, str(HERE / "sandbox_preflight.py"), "--config", str(config_path),
                "--policy", str(policy_path)], capture_output=True, text=True,
                env={"STRIPE_SECRET_KEY": "fictional-cli-canary", "STRIPE_WEBHOOK_SECRET": "fictional-cli-canary"})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(json.loads(result.stdout)["configuration_prerequisites_passed"])
            self.assertFalse(json.loads(result.stdout)["e2e_verified"])
            self.assertNotIn("fictional-cli-canary", result.stdout + result.stderr)

    def test_cli_unknown_arguments_and_parse_errors_do_not_echo_input(self):
        result = subprocess.run([sys.executable, str(HERE / "sandbox_preflight.py"), "--secret", "fictional-cli-canary"],
            capture_output=True, text=True, env={})
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("fictional-cli-canary", result.stdout + result.stderr)
        with tempfile.TemporaryDirectory(prefix="ww-commerce-public-fixture-") as temporary:
            config = Path(temporary) / "broken.public.sandbox.toml"
            config.write_text('bad = "fictional-cli-canary\n')
            result = subprocess.run([sys.executable, str(HERE / "sandbox_preflight.py"), "--config", str(config)],
                capture_output=True, text=True, env={})
            self.assertEqual(result.returncode, 2)
            self.assertNotIn("fictional-cli-canary", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
