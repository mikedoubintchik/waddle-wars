#!/usr/bin/env python3
"""Native preparation and ELF regressions; no engine, device or signing needed."""
from __future__ import annotations

from pathlib import Path
import json
import hashlib
import shutil
import struct
import subprocess
import tempfile
import unittest
import zipfile
import zlib
import xml.etree.ElementTree as ET
from html.parser import HTMLParser

from native_release import export_preset, prepare, read_config, runtime_files, replace_setting, validate_app_name, launcher_name, launch_edition, checked_ios_template, verify_ios_template_binding
from build_native import verify_snapshot
from check_android_artifact import elf_failures, check
from install_ios_billing import ARTIFACTS, verify_plugin
from build_web_worker import validate_template, verify_source_variant
from native_release import sha256


def elf(alignment: int = 16384, address: int = 0, file_offset: int = 0, relro: bool = False) -> bytes:
    data = bytearray(512)
    data[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<H", data, 18, 183)
    struct.pack_into("<Q", data, 32, 64)
    struct.pack_into("<HH", data, 54, 56, 2 if relro else 1)
    struct.pack_into("<IIQQQQQQ", data, 64, 1, 5, file_offset, address, 0, 128, 128, alignment)
    if relro:
        struct.pack_into("<IIQQQQQQ", data, 120, 0x6474E552, 4, 128, 0x1000, 0, 128, 128, 1)
    return bytes(data)


class NativeReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = read_config()
        # Historical free-offline fixture remains a distinct release contract.
        self.config["ios"]["accounts_enabled"] = False

    def test_optional_ios_accounts_production_and_branded_launch(self) -> None:
        config = read_config()
        self.assertIs(config["ios"]["accounts_enabled"], True)
        self.assertEqual(config["ios"]["clerk_issuer"], "https://clerk.waddlewars.io")
        preset = export_preset(config, "ios", "1.0.0", 41, "ABCDE12345")
        for value in ('custom_features="native_accounts"', 'plugins/WaddleStoreKit=true',
                      'storyboard/image_scale_mode=3',
                      'storyboard/custom_image@2x="res://assets/art/ui/menu/launch_screen_portrait_v1.png"',
                      'storyboard/custom_image@3x="res://assets/art/ui/menu/launch_screen_portrait_v1.png"'):
            self.assertIn(value, preset)
        self.assertNotIn(',ios/plugins/WaddleStoreKit/*', preset)
        self.assertIn(',addons/GodotGooglePlayBilling/*', preset)
        config["ios"]["clerk_issuer"] = "https://synthetic.clerk.accounts.dev"
        with self.assertRaisesRegex(ValueError, "production"):
            export_preset(config, "ios", "1.0.0", 41, "ABCDE12345")

    def test_android_aab_sdk_and_no_secret_preset(self) -> None:
        preset = export_preset(self.config, "android", "1.0.0", 17)
        for field in ('gradle_build/export_format=1', 'gradle_build/target_sdk="36"', 'version/code=17', 'architectures/arm64-v8a=true', 'permissions/internet=true', 'permissions/record_audio=false'):
            self.assertIn(field, preset)
        self.assertNotIn("keystore/release_password", preset)
        self.assertIn('package/name="Waddle Wars: Penguin Panic"', preset)

    def test_selected_display_title_does_not_rename_project_or_product_identity(self) -> None:
        self.assertEqual(self.config["app_name"], "Waddle Wars: Penguin Panic")
        self.assertEqual(launcher_name(self.config, "ios"), "Waddle Wars")
        self.assertEqual(launcher_name(self.config, "android"), self.config["app_name"])
        self.assertEqual(self.config["project_name"], "Waddle Wars")
        self.assertEqual(self.config["bundle_id"], "com.blubberandbyte.waddlewars")
        draft = json.loads(Path(__file__).with_name("store_listing.en-US.json").read_text())
        self.assertEqual(draft["app_name"], self.config["app_name"])
        self.assertTrue(all(item.startswith(self.config["bundle_id"] + ".") for item in self.config["products"]))

    def test_native_mvp_listing_limits_and_avalanche_copy(self) -> None:
        draft = json.loads(Path(__file__).with_name("store_listing.en-US.json").read_text())
        for field, limit in (("app_name", 30), ("ios_subtitle", 30),
                             ("play_short_description", 80), ("description", 4000)):
            with self.subTest(field=field):
                self.assertIsInstance(draft[field], str)
                self.assertTrue(draft[field].strip())
                self.assertLessEqual(len(draft[field]), limit)
        for field in ("ios_subtitle", "play_short_description", "description"):
            self.assertIn("avalanche", draft[field].casefold())
        self.assertIn("no in-app purchases", draft["description"])
        self.assertIn("offline", draft["description"])
        keywords = draft["keywords"]
        self.assertEqual(len(keywords), len({word.casefold() for word in keywords}))
        self.assertLessEqual(len(",".join(keywords).encode("utf-8")), 100)
        self.assertIn("support_email", draft)

    def test_native_store_icons_have_platform_specific_png_formats(self) -> None:
        draft = json.loads(Path(__file__).with_name("store_listing.en-US.json").read_text())
        root = Path(__file__).resolve().parents[2]
        receipt = json.loads((root / draft["icon_receipt"]).read_text())
        self.assertEqual(receipt["state"], "generated_unsubmitted")
        self.assertIs(receipt["store_ready"], False)
        for field, expected in (("source", "assets/icons/waddle_wars_app_icon_v4.png"),
                                ("generator", "tools/release/store_assets/export_premium_icon.gd")):
            self.assertEqual(receipt[field]["path"], expected)
            self.assertEqual(receipt[field]["sha256"], sha256(root / expected))
        outputs = {item["path"]: item for item in receipt["outputs"]}
        for field, size, color_type in (("app_store_1024_icon", 1024, 2), ("play_512_icon", 512, 6)):
            with self.subTest(field=field):
                self.assertIsInstance(draft[field], str)
                path = root / draft[field]
                self.assertEqual(path.parent.resolve(), Path(__file__).with_name("store_assets").resolve())
                data = path.read_bytes()
                self.assertEqual(outputs[draft[field]]["sha256"], sha256(path))
                self.assertIs(outputs[draft[field]]["opaque"], True)
                self.assertIs(outputs[draft[field]]["alpha"], color_type == 6)
                self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
                self.assertEqual(data[12:16], b"IHDR")
                self.assertEqual(struct.unpack_from(">II", data, 16), (size, size))
                self.assertEqual((data[24], data[25]), (8, color_type))
                offset, chunks = 8, []
                while offset + 12 <= len(data):
                    length = struct.unpack_from(">I", data, offset)[0]
                    chunks.append(data[offset + 4:offset + 8])
                    offset += length + 12
                    self.assertLessEqual(offset, len(data))
                    if chunks[-1] == b"IEND":
                        break
                self.assertEqual(offset, len(data))
                self.assertEqual(chunks[-1], b"IEND")
                self.assertNotIn(b"tRNS", chunks)
                if field == "play_512_icon":
                    self.assertLessEqual(len(data), 1024 * 1024)

    def test_play_screenshot_draft_matches_saved_listing_receipt(self) -> None:
        root = Path(__file__).resolve().parents[2]
        draft = json.loads(Path(__file__).with_name("store_listing.en-US.json").read_text())
        self.assertEqual(draft["status"], "draft_unsubmitted")
        receipt_path = root / draft["screenshot_draft_receipt"]
        self.assertEqual(receipt_path.parent.resolve(),
                         (root / "tools/release/store_assets/desktop-phone-current-20261008").resolve())
        receipt = json.loads(receipt_path.read_text())
        self.assertEqual(receipt["status"], "uploaded_saved_draft_reload_verified_6_phone_and_ai_labels")
        self.assertEqual(receipt["store"], "Google Play en-US default listing")
        paths = [item["file"] for item in receipt["order"]]
        self.assertEqual(paths, draft["screenshots"])
        self.assertEqual(len(paths), 6)
        self.assertEqual(len(paths), len(set(paths)))
        for item in receipt["order"]:
            with self.subTest(path=item["file"]):
                path = root / item["file"]
                self.assertEqual(path.parent.resolve(), receipt_path.parent.resolve())
                self.assertTrue(path.is_file())
                self.assertEqual(sha256(path), item["sha256"])
                self.assertGreaterEqual(item["width"], 941)
                self.assertGreaterEqual(item["height"], 1672)
                self.assertIn(item["source_kind"], {
                    "chrome_qa_original", "godot_frontend_shot_store_menu",
                    "godot_frontend_shot_missions", "godot_frontend_shot_customize",
                    "godot_runner_results_hud_sample_fixture", "godot_achievements_ui"})
        self.assertEqual(draft["portal_progress"]["build_uploads"], "none")
        self.assertEqual(draft["portal_progress"]["public_release"], "none")

    def test_mobile_pages_keep_publication_history_and_pin_prepared_account_delta(self) -> None:
        root = Path(__file__).resolve().parents[2]
        draft = json.loads(Path(__file__).with_name("store_listing.en-US.json").read_text())
        pages = draft["prepared_web_pages"]
        self.assertEqual(pages["state"], "published_verified")
        inventory = json.loads(Path(__file__).with_name("native_privacy_inventory.json").read_text())
        publication = inventory["public_pages_followup_20261009"]
        self.assertEqual(publication["state"], "published_https_readback_verified")
        self.assertIn("does not verify native runtime traffic", publication["scope"])
        # This is an immutable prior publication receipt, not proof that new
        # account-policy source has been published. The separate account upload
        # gate requires fresh exact HTTPS body evidence for all three pages.
        delta = json.loads(Path(__file__).with_name("native_account_policy_delta.json").read_text())
        self.assertEqual(delta["state"], "prepared_policy_delta")
        self.assertIs(delta["publication_verified_at_preparation"], False)
        self.assertEqual(delta["account_upload_gate"], "ios_account_release_audit.py")

        class PageTags(HTMLParser):
            def __init__(self) -> None:
                super().__init__()
                self.tags: list[tuple[str, dict[str, str | None]]] = []

            def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
                self.tags.append((tag, dict(attrs)))

        for name in ("privacy", "support"):
            with self.subTest(page=name):
                path = root / pages[name]["path"]
                self.assertEqual(path.parent.resolve(), (root / "web/native").resolve())
                self.assertEqual(pages[name]["proposed_url"],
                                 "https://waddlewars.io/native/" + path.name)
                html = path.read_text()
                parsed = PageTags()
                parsed.feed(html)
                parsed.close()
                self.assertNotIn("Unpublished draft", html)
                self.assertNotIn("[PUBLICATION_DATE]", html)
                self.assertNotIn("[CONFIRM_FINAL_BINARY_SDK_PRACTICES_AND_AGE_AUDIENCE_POLICY]", html)
                self.assertEqual(draft[name + "_url"], pages[name]["proposed_url"])
                observation = publication["pages"][name]
                self.assertEqual(observation["url"], draft[name + "_url"])
                self.assertEqual(observation["status"], 200)
                self.assertTrue(observation["public_body_exact_match"])
                change = delta["pages"][name]
                self.assertEqual(change["prior_published_sha256"], observation["source_sha256"])
                self.assertEqual(change["path"], str(path.relative_to(root)))
                self.assertEqual(change["url"], observation["url"])
                # The October 9 preparation receipt is immutable. Later policy
                # edits must not rewrite that historical source hash.
                self.assertRegex(change["prepared_sha256"], r"^[0-9a-f]{64}$")
                self.assertEqual(draft["support_email"], "support@waddlewars.io")
                self.assertEqual(draft["copyright_owner"], "Ninja Consulting LLC")

                self.assertIn(draft["support_email"], html)
                self.assertIn(draft["copyright_owner"], html)
                self.assertNotIn("[PUBLIC_SUPPORT_EMAIL]", html)
                self.assertNotIn("[LEGAL_PUBLISHER_NAME]", html)
                self.assertIn("browser", html.casefold())
                self.assertIn("local", html.casefold())
                self.assertTrue(any(tag == "html" and attrs.get("lang") == "en"
                                    for tag, attrs in parsed.tags))
                self.assertFalse(any(tag == "meta" and attrs.get("name") == "robots"
                                     and "noindex" in (attrs.get("content") or "")
                                     for tag, attrs in parsed.tags))
                ids = [attrs["id"] for _, attrs in parsed.tags if "id" in attrs]
                self.assertEqual(len(ids), len(set(ids)))
                self.assertIn("main", ids)
                self.assertEqual(sum(tag == "h1" for tag, _ in parsed.tags), 1)
                for tag, attrs in parsed.tags:
                    self.assertNotIn(tag, ("script", "iframe", "form", "input", "object", "embed"))
                    self.assertFalse(any(attr.startswith("on") for attr in attrs))
                    self.assertNotIn("src", attrs)  # No remote images, pixels, or embeds.
                    href = attrs.get("href")
                    if not href:
                        continue
                    if href.startswith("#"):
                        self.assertIn(href[1:], ids)
                    elif href.startswith("https://"):
                        if tag == "link" and attrs.get("rel") == "canonical":
                            self.assertEqual(href, observation["url"])
                            continue
                        allowed_https = {"https://play.waddlewars.io/",
                                         "https://policies.google.com/privacy"}
                        if name == "privacy":
                            allowed_https.add("https://www.cloudflare.com/privacypolicy/")
                            allowed_https.add("https://clerk.com/legal/privacy")
                            allowed_https.add("https://www.cloudflare.com/cloudflare-customer-dpa/")
                            allowed_https.add("https://developers.cloudflare.com/web-analytics/data-metrics/data-origin-and-collection/")
                            allowed_https.add("https://developers.cloudflare.com/web-analytics/data-metrics/dimensions/")
                        self.assertIn(href, allowed_https)
                    elif href.startswith("mailto:"):
                        self.assertEqual(href, "mailto:" + draft["support_email"])
                    elif tag == "link" and attrs.get("rel") == "icon":
                        self.assertEqual(href, "/favicon-48.png")
                        self.assertTrue((root / "web/favicon-48.png").is_file())
                    else:
                        target = path.parent / href
                        self.assertEqual(target.parent.resolve(), path.parent.resolve())
                        self.assertTrue(target.is_file())
                self.assertEqual(sum(tag == "style" for tag, _ in parsed.tags), 1)
                self.assertFalse(any(tag == "link" and attrs.get("rel") == "stylesheet"
                                     for tag, attrs in parsed.tags))
                self.assertIn(":focus-visible", html)
                self.assertIn("prefers-reduced-motion", html)
        css = (root / pages["stylesheet"]).read_text()
        self.assertNotIn("@import", css)
        self.assertNotIn("url(", css)
        self.assertIn(":focus-visible", css)
        self.assertIn("prefers-reduced-motion", css)

        deletion = pages["deletion"]
        deletion_path = root / deletion["path"]
        self.assertEqual(deletion_path.parent.resolve(), (root / "web/native").resolve())
        self.assertEqual(deletion["proposed_url"], draft["account_deletion_url"])
        self.assertEqual(deletion["proposed_url"],
                         "https://waddlewars.io/native/delete-data.html")
        deletion_observation = publication["pages"]["deletion"]
        self.assertEqual(deletion_observation["url"], draft["account_deletion_url"])
        self.assertEqual(deletion_observation["status"], 200)
        self.assertTrue(deletion_observation["public_body_exact_match"])
        self.assertEqual(delta["pages"]["deletion"]["prior_published_sha256"],
                         deletion_observation["source_sha256"])
        self.assertEqual(hashlib.sha256(deletion_path.read_bytes()).hexdigest(),
                         delta["pages"]["deletion"]["prepared_sha256"])

    def test_ios_account_policy_describes_sync_and_retention_without_changing_android(self) -> None:
        root = Path(__file__).resolve().parents[2]
        privacy = (root / "web/native/privacy.html").read_text()
        deletion = (root / "web/native/delete-data.html").read_text()
        support = (root / "web/native/support.html").read_text()
        for page in (privacy, deletion, support):
            self.assertIn("starting with build 41", page)
            self.assertIn("Android", page)
            self.assertIn("Account → Privacy &amp; Data → Delete Account", page)
            self.assertNotIn("This mobile version has no in-game account sign-in", page)
        for disclosure in ("Settings and time-trial ghost files remain local",
                           "not automatically published as your leaderboard name",
                           "short-lived authentication credentials", "hashed deletion recovery receipt",
                           "keeps earned offline progress", "Identity-provider cleanup can remain pending",
                           "These mobile editions have no in-app purchases"):
            self.assertIn(disclosure, privacy)
        self.assertIn("does not require an email to support", deletion)
        self.assertIn("Check status", deletion)
        self.assertIn("does not claim every retained record has been erased", deletion)
        self.assertIn("A separate Post Local Best action", privacy)

    def test_privacy_host_facts_do_not_claim_zero_provider_processing(self) -> None:
        root = Path(__file__).resolve().parents[2]
        html = (root / "web/native/privacy.html").read_text()
        self.assertIn("Workers Logs and Workers Traces were disabled", html)
        self.assertIn("October 2, 2026 hosting review", html)
        self.assertIn('href="https://www.cloudflare.com/privacypolicy/"', html)
        self.assertIn("does not mean Cloudflare processes no data", html)
        self.assertNotIn("[CONFIRM_PROVIDER_DATA_ACCESS_AND_DELETION_LIMITS]", html)
        self.assertIn("Provider logs, security records, and retention follow its practices", html)
        self.assertNotIn("[CONFIRM_SUPPORT_PROVIDER_ACCESS_AND_RETENTION]", html)
        self.assertNotIn("Unpublished draft", html)
        self.assertIn("Cloudflare Web Analytics beacon", html)
        self.assertIn("separate from native game play", html)
        self.assertNotIn("[CONFIRM_HOST_LOGGING_PURPOSES_DATA_ACCESS_AND_RETENTION]", html)

    def test_owner_support_retention_policy_is_consistent_and_not_automated(self) -> None:
        root = Path(__file__).resolve().parents[2]
        for name in ("privacy", "support"):
            with self.subTest(page=name):
                html = (root / "web/native" / (name + ".html")).read_text()
                self.assertIn("owner of Ninja Consulting LLC personally handles", html)
                self.assertIn("within 90 days after resolution", html)
                self.assertIn('href="https://policies.google.com/privacy"', html)
                self.assertIn("legal obligations", html)
                self.assertIn("fraud or security handling", html)
                self.assertIn("backup copies", html)
                self.assertNotIn("Unpublished draft", html)
        procedure = Path(__file__).with_name("support_retention.md").read_text()
        for boundary in ("not a mailbox change or automation",
                         "Keep unrelated Chancey and Ninja Consulting messages",
                         "within 90 days", "Review resolved Waddle cases monthly",
                         "Do not empty shared", "No blanket or undocumented holds"):
            self.assertIn(boundary, procedure)

    def test_provider_rights_route_keeps_limits_and_has_no_review_placeholders(self) -> None:
        root = Path(__file__).resolve().parents[2]
        html = (root / "web/native/privacy.html").read_text()
        for wording in (
            "start a privacy request with Ninja Consulting LLC",
            "Cloudflare's published policy directs users of customer applications to that customer",
            "identity verification",
            "cannot promise that every provider record can be located or erased",
            'href="https://www.cloudflare.com/cloudflare-customer-dpa/"',
            "Our Workers logging settings do not give us control over every provider-held record",
            "do not promise a fixed retention period or immediate deletion",
            "assistance to the extent it is able and in line with applicable law",
            "Mobile privacy policy effective October 11, 2026.",
            "We do not sell personal information",
            "A parent or guardian can contact us",
        ):
            with self.subTest(wording=wording):
                self.assertIn(wording, html)
        self.assertNotIn("[CONFIRM_PROVIDER_DATA_ACCESS_AND_DELETION_LIMITS]", html)
        self.assertNotIn("Service-specific provider access and deletion limits remain under review", html)
        self.assertNotIn("mailto:sar@cloudflare.com", html)
        self.assertNotIn("[PUBLICATION_DATE]", html)
        self.assertNotIn("[CONFIRM_FINAL_BINARY_SDK_PRACTICES_AND_AGE_AUDIENCE_POLICY]", html)
        self.assertNotIn("Unpublished draft", html)
        draft = json.loads(Path(__file__).with_name("store_listing.en-US.json").read_text())
        self.assertEqual(draft["privacy_url"], "https://waddlewars.io/native/privacy.html")
        self.assertEqual(draft["support_url"], "https://waddlewars.io/native/support.html")

    def test_play_feature_graphic_is_source_bound_rgb_and_unsubmitted(self) -> None:
        root = Path(__file__).resolve().parents[2]
        draft = json.loads(Path(__file__).with_name("store_listing.en-US.json").read_text())
        asset_dir = Path(__file__).with_name("store_assets")
        receipt = json.loads((asset_dir / "feature_graphic_receipt.json").read_text())
        self.assertEqual(receipt["state"], "generated_unsubmitted")
        self.assertIs(receipt["store_ready"], False)
        self.assertEqual(receipt["app_name"], draft["app_name"])
        self.assertEqual(receipt["scope"], "existing_vector_mark_and_glyph_with_shipped_font_lettering")
        inputs = receipt["inputs_sha256"]
        self.assertEqual(set(inputs), {
            "assets/icons/icon.svg", "assets/fonts/AtkinsonHyperlegibleNext-wght.ttf",
            "assets/fonts/AtkinsonHyperlegibleNext-OFL.txt", "scripts/ui/main_menu.gd",
            "tools/release/store_assets/feature_graphic.template.svg",
            "tools/release/store_assets/raster_feature_graphic.gd",
            "tools/release/store_assets/make_feature_graphic.py",
        })
        for name, digest in inputs.items():
            self.assertTrue((root / name).is_file(), name)
            if name != "scripts/ui/main_menu.gd":
                self.assertEqual(digest, sha256(root / name), name)
        output = receipt["output"]
        # V1 generation receipt remains immutable; the listing now uses V2.
        path = root / output["path"]
        self.assertEqual(path.parent.resolve(), asset_dir.resolve())
        self.assertEqual(output["sha256"], sha256(path))
        self.assertEqual((output["width"], output["height"], output["format"]), (1024, 500, "RGB8"))
        self.assertIs(output["opaque"], True)
        self.assertIs(output["alpha"], False)
        data = path.read_bytes()
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(data[12:16], b"IHDR")
        self.assertEqual(struct.unpack_from(">II", data, 16), (1024, 500))
        self.assertEqual((data[24], data[25]), (8, 2))
        offset, chunks = 8, []
        while offset + 12 <= len(data):
            length = struct.unpack_from(">I", data, offset)[0]
            chunks.append(data[offset + 4:offset + 8])
            offset += length + 12
            self.assertLessEqual(offset, len(data))
            if chunks[-1] == b"IEND":
                break
        self.assertEqual(offset, len(data))
        self.assertEqual(chunks[-1], b"IEND")
        self.assertNotIn(b"tRNS", chunks)
        current = root / draft["play_1024x500_feature_graphic"]
        self.assertEqual((current.read_bytes()[:8], current.read_bytes()[12:16]),
                         (b"\x89PNG\r\n\x1a\n", b"IHDR"))
        self.assertEqual(struct.unpack_from(">II", current.read_bytes(), 16), (1024, 500))
        self.assertEqual([row["text"] for row in receipt["typography"]],
                         ["Waddle Wars:", "Penguin Panic", "OUTRUN THE AVALANCHE"])

    def test_mobile_policy_host_content_types_and_revalidation(self) -> None:
        root = Path(__file__).resolve().parents[2]
        node = shutil.which("node")
        self.assertIsNotNone(node, "Node required for local static-host regression")
        program = r"""
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const {default: worker} = await import(pathToFileURL(process.argv[1]).href);
const cases = [
  ['/native/privacy.html', 'native/privacy.html', 'text/html; charset=utf-8', 'public, max-age=0, must-revalidate'],
  ['/native/support.html', 'native/support.html', 'text/html; charset=utf-8', 'public, max-age=0, must-revalidate'],
  ['/native/policy.css', 'native/policy.css', 'text/css; charset=utf-8', 'public, max-age=0, must-revalidate'],
  ['/', 'index.html', 'text/html; charset=utf-8', 'no-store'],
  ['/index.wasm', 'index.wasm', 'application/wasm', 'public, max-age=0, must-revalidate'],
  ['/index.pck?v=unchanged', 'index.pck', 'application/octet-stream', 'public, max-age=0, must-revalidate'],
  ['/icon-512.png', 'icon-512.png', 'image/png', 'public, max-age=86400'],
  ['/manifest.webmanifest', 'manifest.webmanifest', 'application/manifest+json', 'public, max-age=0, must-revalidate'],
];
for (const [route, expectedKey, type, cache] of cases) {
  const request = new Request('https://waddlewars.ninjaconsulting.ai' + route);
  const env = {SITE: {get: async (key, options) => {
    assert.equal(key, expectedKey);
    assert.equal(options.onlyIf, request.headers);
    return {body: 'local fixture only', httpEtag: '"fixture"'};
  }}};
  const response = await worker.fetch(request, env);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-type'), type, route);
  assert.equal(response.headers.get('cache-control'), cache, route);
  assert.equal(response.headers.get('etag'), '"fixture"');
  assert.equal(response.headers.get('cross-origin-opener-policy'), 'same-origin');
  assert.equal(response.headers.get('cross-origin-embedder-policy'), 'require-corp');
  assert.equal(await response.text(), 'local fixture only');
}
const missing = await worker.fetch(new Request('https://waddlewars.ninjaconsulting.ai/native/missing.html'),
  {SITE: {get: async () => null}});
assert.equal(missing.status, 404);
const conditional = new Request('https://waddlewars.ninjaconsulting.ai/native/policy.css',
  {headers: {'if-none-match': '"fixture"'}});
const cached = await worker.fetch(conditional, {SITE: {get: async (key, options) => {
  assert.equal(key, 'native/policy.css');
  assert.equal(options.onlyIf.get('if-none-match'), '"fixture"');
  return {httpEtag: '"fixture"'};
}}});
assert.equal(cached.status, 304);
assert.equal(cached.headers.get('etag'), '"fixture"');
assert.equal(cached.headers.get('cache-control'), 'public, max-age=0, must-revalidate');
assert.equal(await cached.text(), '');
console.log('10 local static-host cases passed; no network/R2 writes');
"""
        result = subprocess.run([node, "--input-type=module", "-e", program,
                                 str(root / "web-host/src/worker.js")],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("10 local static-host cases passed", result.stdout)

    def test_reject_invalid_public_display_titles(self) -> None:
        for title in (None, False, "", "   ", " padded", "padded ", "x" * 31, "bad\nname", "bad\x7fname"):
            with self.subTest(title=title), self.assertRaisesRegex(ValueError, "App display name"):
                validate_app_name(title)
        self.assertEqual(validate_app_name('Ice & "Snow"'), 'Ice & "Snow"')

    def test_ios_launcher_override_validated_and_legacy_title_retained(self) -> None:
        self.config["ios"].pop("display_name")
        self.assertEqual(launcher_name(self.config, "ios"), self.config["app_name"])
        for value in (None, False, "", " padded", "x" * 31, "bad\nname"):
            self.config["ios"]["display_name"] = value
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "App display name"):
                export_preset(self.config, "ios", "1.0.0", 42, "ABCDE12345")

    def test_ios_requires_real_team_format(self) -> None:
        for team in ("", "Ninja Consulting", "../oops", "ABCDE1234"):
            with self.assertRaises(ValueError):
                export_preset(self.config, "ios", "1.0.0", 17, team)
        self.assertIn('application/app_store_team_id="ABCDE12345"', export_preset(self.config, "ios", "1.0.0", 17, "ABCDE12345"))

    def test_ios_pins_reviewed_file_and_timer_reasons(self) -> None:
        # Godot a13da4feb uses 1 << index: C617.1 is index 1;
        # 35F9.1 is index 0. These are source-backed, not store approval.
        preset = export_preset(self.config, "ios", "1.0.0", 17, "ABCDE12345")
        for field in ("privacy/file_timestamp_access_reasons=2",
                      "privacy/system_boot_time_access_reasons=1",
                      "privacy/tracking_enabled=false"):
            with self.subTest(field=field):
                self.assertEqual(preset.splitlines().count(field), 1)
        android = export_preset(self.config, "android", "1.0.0", 17)
        self.assertNotIn("privacy/file_timestamp_access_reasons=", android)
        self.assertNotIn("privacy/system_boot_time_access_reasons=", android)

    def test_free_mvp_disables_native_billing_without_changing_legacy_contract(self) -> None:
        self.assertEqual(launch_edition(self.config), "free_offline_mvp")
        self.assertEqual(launch_edition({}), "commerce")
        for value in (None, False, "", "unknown"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                launch_edition({"launch_edition": value})
        mvp = export_preset(self.config, "ios", "1.0.0", 17, "ABCDE12345")
        self.assertIn("plugins/WaddleStoreKit=false", mvp)
        self.assertIn("addons/GodotGooglePlayBilling/*", mvp)
        legacy = {key: value for key, value in self.config.items() if key != "launch_edition"}
        historical = export_preset(legacy, "ios", "1.0.0", 17, "ABCDE12345")
        self.assertIn('custom_features="native_commerce"', historical)
        with_accounts = read_config()
        with_accounts["launch_edition"] = "commerce"
        commerce = export_preset(with_accounts, "ios", "1.0.0", 17, "ABCDE12345")
        self.assertIn("plugins/WaddleStoreKit=true", commerce)
        self.assertIn('custom_features="native_accounts,native_commerce"', commerce)
        self.assertIn('custom_features=""', export_preset(self.config, "android", "1.0.0", 17))
        self.assertIn('custom_features="native_commerce"',
                      export_preset(legacy, "android", "1.0.0", 17))

    def test_mvp_snapshot_omits_only_deferred_sdks_and_preserves_source(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            source = base / "source"
            source.mkdir()
            (source / "project.godot").write_text(
                '[application]\nconfig/name="Waddle Wars"\n[editor_plugins]\n'
                'enabled=PackedStringArray("res://addons/Other/plugin.cfg", '
                '"res://addons/GodotGooglePlayBilling/plugin.cfg")\n')
            sdk_files = ("addons/GodotGooglePlayBilling/BillingClient.gd",
                         "ios/plugins/WaddleStoreKit/WaddleStoreKit.gdip")
            for name in (*sdk_files, "addons/Other/plugin.cfg", "scripts/commerce/commerce_client.gd"):
                path = source / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("preserved fixture")
            original = {str(path.relative_to(source)): sha256(path) for path in runtime_files(source)}
            for platform in ("ios", "android"):
                receipt = prepare(source, base / platform, self.config, platform, "1.0.0", 17,
                                  "ABCDE12345" if platform == "ios" else "", None)
                project = base / platform / "project"
                self.assertEqual(receipt["launch_edition"], "free_offline_mvp")
                self.assertEqual(receipt["source_files"], original)
                self.assertEqual(receipt["omitted_deferred_sdk_files"], {name: original[name] for name in sdk_files})
                for name in sdk_files:
                    self.assertFalse((project / name).exists())
                self.assertTrue((project / "scripts/commerce/commerce_client.gd").is_file())
                self.assertTrue((project / "addons/Other/plugin.cfg").is_file())
                settings = (project / "project.godot").read_text()
                self.assertIn('enabled=PackedStringArray("res://addons/Other/plugin.cfg")', settings)
                self.assertNotIn('"res://addons/GodotGooglePlayBilling/plugin.cfg"', settings)
                verify_snapshot(project, receipt)
            self.assertEqual({str(path.relative_to(source)): sha256(path) for path in runtime_files(source)}, original)

    def test_custom_ios_template_is_copied_pinned_and_bound_to_preset(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder).resolve()
            source = base / "source"
            source.mkdir()
            (source / "project.godot").write_text('[application]\nconfig/name="Waddle Wars"\n')
            template = base / "reviewed.zip"
            with zipfile.ZipFile(template, "w") as archive:
                archive.writestr("ios_template/synthetic", b"fixture, not an engine")
            pin = sha256(template)
            candidate = base / "candidate"
            receipt = prepare(source, candidate, self.config, "ios", "1.0.0", 17, "ABCDE12345", None,
                              ios_template=template, ios_template_sha256=pin)
            self.assertEqual(receipt["app_name"], "Waddle Wars")
            self.assertEqual(receipt["project_name"], "Waddle Wars")
            self.assertEqual(receipt["ios_custom_template"], {"path": "inputs/ios-template.zip", "sha256": pin})
            self.assertEqual(verify_ios_template_binding(candidate, receipt), receipt["ios_custom_template"])
            self.assertNotIn("inputs/ios-template.zip", receipt["prepared_files"])
            self.assertIs(receipt["store_ready"], False)
            self.assertIsNone(receipt["ios_engine_capability_policy"])
            reviewed_config = json.loads(json.dumps(self.config))
            reviewed_config["ios"]["disk_capacity_disabled_template_sha256"] = pin
            reviewed = base / "reviewed-candidate"
            reviewed_receipt = prepare(source, reviewed, reviewed_config, "ios", "1.0.0", 18, "ABCDE12345", None,
                                       ios_template=template, ios_template_sha256=pin)
            self.assertEqual(reviewed_receipt["ios_engine_capability_policy"], {
                "policy": "disk-capacity-disabled-template-v1", "template_sha256": pin})
            self.assertEqual(verify_ios_template_binding(reviewed, reviewed_receipt), reviewed_receipt["ios_custom_template"])
            for removed in ("ios_engine_capability_policy", "ios_custom_template"):
                incomplete = dict(reviewed_receipt)
                incomplete.pop(removed)
                with self.subTest(removed=removed), self.assertRaises(ValueError):
                    verify_ios_template_binding(reviewed, incomplete)
            reviewed_preset = reviewed / "project/export_presets.cfg"
            reviewed_preset.write_text(reviewed_preset.read_text().replace("privacy/disk_space_access_reasons=0", "privacy/disk_space_access_reasons=3"))
            with self.assertRaises(ValueError):
                verify_ios_template_binding(reviewed, reviewed_receipt)
            template.write_bytes(b"source replacement cannot change the frozen copy")
            self.assertEqual(verify_ios_template_binding(candidate, receipt), receipt["ios_custom_template"])
            copied = candidate / "inputs/ios-template.zip"
            copied.write_bytes(b"mutated candidate template")
            with self.assertRaises(ValueError):
                verify_ios_template_binding(candidate, receipt)

    def test_custom_ios_template_rejects_bad_pins_and_non_ios_before_copy(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder).resolve()
            source = base / "source"
            source.mkdir()
            (source / "project.godot").write_text('[application]\nconfig/name="Waddle Wars"\n')
            template = base / "template.zip"
            with zipfile.ZipFile(template, "w") as archive:
                archive.writestr("fixture", b"fixture")
            for platform, selected, pin in (("ios", template, None), ("ios", None, sha256(template)),
                                            ("ios", template, "0" * 64), ("android", template, sha256(template))):
                candidate = base / "candidate"
                with self.subTest(platform=platform, selected=selected, pin=pin), self.assertRaises(ValueError):
                    prepare(source, candidate, self.config, platform, "1.0.0", 17, "ABCDE12345", None,
                            ios_template=selected, ios_template_sha256=pin)
                self.assertFalse(candidate.exists())

    def test_custom_ios_template_rejects_unsafe_archive_paths(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder).resolve()
            for index, names in enumerate((("../outside",), ("/absolute",), ("a\\b",),
                                           ("same", "SAME"), ("file", "file/child"), ("bad\nname",))):
                template = base / f"template-{index}.zip"
                with zipfile.ZipFile(template, "w") as archive:
                    for name in names:
                        archive.writestr(name, b"fixture")
                with self.subTest(names=names), self.assertRaises(ValueError):
                    checked_ios_template(template, sha256(template))

    def test_reject_invalid_version_build(self) -> None:
        for version, build in (("1.0-beta", 1), ("1.0.0", 0), ("1.0.0", 2100000001)):
            with self.assertRaises(ValueError):
                export_preset(self.config, "android", version, build)

    def test_setting_replacement_preserves_other_sections(self) -> None:
        before = '[application]\n\nconfig/name="Game"\nconfig/version="old"\n\n[display]\nwindow/handheld/orientation=6\n'
        after = replace_setting(before, "application", "config/version", '"1.0.0"')
        self.assertIn('config/name="Game"', after)
        self.assertIn('window/handheld/orientation=6', after)
        self.assertEqual(after.count("config/version="), 1)

    def test_prepare_isolated_and_source_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            source = base / "source"
            (source / "scripts/utilities").mkdir(parents=True)
            original = '[application]\nconfig/name="Waddle Wars"\nconfig/version="1.0.0"\n[display]\nwindow/handheld/orientation=6\n'
            (source / "project.godot").write_text(original)
            (source / "scripts/utilities/game_config.gd").write_text('const BUILD_ID: String = "dev"\n')
            (source / ".envrc").write_text("DO_NOT_READ_OR_COPY")
            (source / "art_src").mkdir()
            (source / "art_src/source.blend").write_bytes(b"AUTHOR_SOURCE")
            receipt = prepare(source, base / "candidate", self.config, "android", "1.1.0", 17, "", None)
            project = base / "candidate/project"
            self.assertEqual((source / "project.godot").read_text(), original)
            self.assertEqual((source / "scripts/utilities/game_config.gd").read_text(), 'const BUILD_ID: String = "dev"\n')
            self.assertFalse((project / ".envrc").exists())
            self.assertFalse((project / "art_src").exists())
            self.assertEqual(receipt["state"], "prepared_unbuilt")
            self.assertFalse(receipt["store_ready"])
            self.assertEqual(receipt["app_name"], self.config["app_name"])
            self.assertEqual(receipt["project_name"], "Waddle Wars")
            self.assertIn('config/name="Waddle Wars"', (project / "project.godot").read_text())
            self.assertNotIn('config/name="Waddle Wars: Penguin Panic"', (project / "project.godot").read_text())
            verify_snapshot(project, receipt)
            (project / "scripts/unreviewed.gd").write_text("extends Node\n")
            with self.assertRaises(ValueError):
                verify_snapshot(project, receipt)
            (project / "scripts/unreviewed.gd").unlink()
            (project / "scripts/utilities/game_config.gd").write_text("modified")
            with self.assertRaises(ValueError):
                verify_snapshot(project, receipt)
            with self.assertRaises(ValueError):
                prepare(source, base / "candidate", self.config, "android", "1.1.0", 18, "", None)
            with self.assertRaises(ValueError):
                prepare(source, source / "build/candidate", self.config, "android", "1.1.0", 18, "", None)

    def test_runtime_symlinks_and_private_files_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)
            (source / "project.godot").write_text("[application]\n")
            (source / "assets").mkdir()
            secret = source / "assets/upload.keystore"
            secret.write_text("must not copy")
            with self.assertRaises(ValueError):
                runtime_files(source)
            secret.unlink()
            (source / "assets/escape").symlink_to(source / "project.godot")
            with self.assertRaises(ValueError):
                runtime_files(source)

    def test_reject_top_level_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)
            (source / "project.godot").write_text("[application]\n")
            (source / "external").mkdir()
            (source / "assets").symlink_to(source / "external", target_is_directory=True)
            with self.assertRaises(ValueError):
                runtime_files(source)

    def test_good_elf_and_bad_alignment_offset_bounds(self) -> None:
        self.assertEqual(elf_failures(elf()), [])
        self.assertTrue(elf_failures(elf(4096)))
        self.assertTrue(elf_failures(elf(address=4096)))
        self.assertTrue(elf_failures(elf(relro=True)))
        self.assertTrue(elf_failures(b"not elf"))
        malformed = bytearray(elf())
        struct.pack_into("<Q", malformed, 32, 4096)
        self.assertTrue(elf_failures(bytes(malformed)))

    def test_good_elf_not_aab_packaging_pass(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            bundle = Path(folder) / "test.aab"
            with zipfile.ZipFile(bundle, "w") as artifact:
                artifact.writestr("base/lib/arm64-v8a/libgodot_android.so", elf())
            report = check(bundle)
            self.assertFalse(report["structural_gate_passed"])
            self.assertFalse(report["store_ready"])
            self.assertIn("AAB packaging not checked", report["failures"][0])

    def test_ios_compiled_receipt_and_artifacts_must_match(self) -> None:
        lock = json.loads(Path(__file__).with_name("billing_plugins.lock.json").read_text())
        with tempfile.TemporaryDirectory() as folder:
            plugin = Path(folder)
            for name in ARTIFACTS:
                (plugin / name).write_bytes(b"compiled-fixture")
            receipt = {"state": "compiled_unverified", "plugin": "WaddleStoreKit", "version": lock["ios"]["version"], "godot_source_commit": lock["ios"]["godot_source_commit"], "artifacts": {name: sha256(plugin / name) for name in ARTIFACTS}}
            expected = ["IOS_ENABLED", "APPLE_EMBEDDED_ENABLED", "UNIX_ENABLED", "COREAUDIO_ENABLED", "THREADS_ENABLED", "NDEBUG"]
            receipt.update({"platform": "ios", "architecture": "arm64", "entrypoint_linkage": "cplusplus", "engine_cpp_defines": {"debug": [*expected, "DEBUG_ENABLED"], "release": expected}})
            (plugin / "waddle_build_receipt.json").write_text(json.dumps(receipt))
            self.assertEqual(verify_plugin(plugin, lock)["state"], "compiled_unverified")
            (plugin / ARTIFACTS[1]).write_bytes(b"unexpected")
            with self.assertRaises(ValueError):
                verify_plugin(plugin, lock)

    def test_ios_auth_manifest_and_compilation_sources(self) -> None:
        source = Path(__file__).resolve().parents[2] / "native/ios/WaddleStoreKit"
        manifest = (source / "WaddleStoreKit.gdip").read_text()
        for framework in ("AuthenticationServices.framework", "UIKit.framework"):
            self.assertIn(framework, manifest)
        raw = next(line for line in manifest.splitlines() if line.startswith("CFBundleURLTypes:raw="))
        value = json.loads(raw.split("=", 1)[1])
        tree = ET.fromstring(value)
        schemes = tree.findall("./dict/array/string")
        self.assertEqual([element.text for element in schemes], ["com.blubberandbyte.waddlewars.auth"])
        from install_ios_billing import SOURCES
        self.assertIn("WWAuthenticationBridge.swift", SOURCES)
        self.assertIn("WWAuthenticationPolicy.swift", SOURCES)
        lock = json.loads(Path(__file__).with_name("billing_plugins.lock.json").read_text())
        self.assertEqual(lock["ios"]["version"], "1.2.0")

    def test_web_template_requires_real_wasm_and_both_runtime_files(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            artifact = Path(folder) / "worker.zip"
            with zipfile.ZipFile(artifact, "w") as archive:
                archive.writestr("godot.js", "runtime")
                archive.writestr("godot.wasm", b"\x00asm\x01\x00\x00\x00")
            validate_template(artifact)
            with zipfile.ZipFile(artifact, "w") as archive:
                archive.writestr("godot.js", "runtime")
                archive.writestr("godot.wasm", b"not wasm")
            with self.assertRaises(ValueError):
                validate_template(artifact)

    def test_web_variant_accepts_only_exact_reviewed_source(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)
            subprocess.run(["git", "init", "-q", str(source)], check=True)
            original = b"official source\n"
            patched = b"official source\nreviewed line\n"
            (source / "library.js").write_bytes(original)
            subprocess.run(["git", "-C", str(source), "add", "library.js"], check=True)
            subprocess.run(["git", "-C", str(source), "-c", "user.name=QA", "-c", "user.email=qa@example.invalid", "commit", "-qm", "fixture"], check=True)
            lock = json.loads(Path(__file__).with_name("web_worker_template.lock.json").read_text())
            patch = {**lock["qa_variants"]["eval_main_thread"], "source_file": "library.js", "before_sha256": hashlib.sha256(original).hexdigest(), "after_sha256": hashlib.sha256(patched).hexdigest()}
            fixture_lock = {"qa_variants": {"eval_main_thread": patch}}
            self.assertEqual(verify_source_variant(source, fixture_lock, "official")["id"], "official")
            with self.assertRaises(ValueError):
                verify_source_variant(source, fixture_lock, "eval_main_thread")
            (source / "library.js").write_bytes(patched)
            self.assertEqual(verify_source_variant(source, fixture_lock, "eval_main_thread")["patches"][0]["verified_after_sha256"], patch["after_sha256"])
            with self.assertRaises(ValueError):
                verify_source_variant(source, fixture_lock, "official")
            (source / "library.js").write_bytes(patched + b"unreviewed\n")
            with self.assertRaises(ValueError):
                verify_source_variant(source, fixture_lock, "eval_main_thread")
            (source / "library.js").write_bytes(patched)
            (source / "other.js").write_bytes(b"official other file\n")
            subprocess.run(["git", "-C", str(source), "add", "other.js"], check=True)
            with self.assertRaises(ValueError):
                verify_source_variant(source, fixture_lock, "eval_main_thread")
            subprocess.run(["git", "-C", str(source), "restore", "--staged", "other.js"], check=True)
            (source / "other.js").unlink()
            (source / "library.js").chmod(0o755)
            with self.assertRaises(ValueError):
                verify_source_variant(source, fixture_lock, "eval_main_thread")
            (source / "library.js").chmod(0o644)
            fixture_lock["qa_variants"]["eval_main_thread"]["patch_sha256"] = "0" * 64
            with self.assertRaises(ValueError):
                verify_source_variant(source, fixture_lock, "eval_main_thread")


if __name__ == "__main__":
    unittest.main()
