#!/usr/bin/env python3
"""Focused host guards; no compiler, engine, browser, or real source mutation."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import subprocess

from build_web_worker import (archive_primary_js, reviewed_source_hashes, validate_emitted_readback_variant,
                              validate_emitted_sdk_variant, verify_sdk_variant, verify_source_variant,
                              verify_source_variants)


class InstalledSDKGuards(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.sdk = Path(self.temporary.name) / "sdk"
        self.sdk.mkdir()
        self.lock = json.loads(Path(__file__).with_name("web_worker_template.lock.json").read_text())
        self.approved = self.lock["qa_sdk_variants"]["scissor_is_enabled"]
        self.original = ("// host fixture\n" + self.approved["replace_before"] + "\n").encode()
        self.candidate = self.original.replace(self.approved["replace_before"].encode(), self.approved["replace_after"].encode())
        self.approved["before_sha256"] = hashlib.sha256(self.original).hexdigest()
        self.approved["after_sha256"] = hashlib.sha256(self.candidate).hexdigest()
        self.lock["emsdk"]["reviewed_source_files"] = {self.approved["source_file"]: self.approved["before_sha256"]}
        self.source = self.sdk / self.approved["source_file"]
        self.source.parent.mkdir(parents=True)
        self.source.write_bytes(self.original)

    def test_official_hashes_installed_file_without_trusting_git_inventory(self):
        with patch("build_web_worker.subprocess.check_output", side_effect=AssertionError("Git must not establish installed SDK identity")):
            result = verify_sdk_variant(self.sdk, self.lock)
        self.assertEqual(result["id"], "official")
        self.assertEqual(result["reviewed_source_files"][0]["verified_sha256"], self.approved["before_sha256"])

    def test_official_rejects_candidate_even_when_sdk_git_would_be_clean(self):
        self.source.write_bytes(self.candidate)
        with patch("build_web_worker.subprocess.check_output", return_value=""):
            with self.assertRaisesRegex(ValueError, "exact official hash"):
                verify_sdk_variant(self.sdk, self.lock)

    def test_opted_candidate_has_exact_patch_and_reconstructed_whole_baseline(self):
        self.source.write_bytes(self.candidate)
        result = verify_sdk_variant(self.sdk, self.lock, "scissor_is_enabled")
        self.assertEqual(result["patches"][0]["verified_before_sha256"], self.approved["before_sha256"])
        self.assertEqual(result["patches"][0]["verified_after_sha256"], self.approved["after_sha256"])
        self.assertEqual(result["patches"][0]["changed_lines"], 1)

    def test_candidate_rejects_unpatched_source(self):
        with self.assertRaisesRegex(ValueError, "exact scissor_is_enabled hash"):
            verify_sdk_variant(self.sdk, self.lock, "scissor_is_enabled")

    def test_unrelated_installed_source_change_rejected_before_and_after_candidate(self):
        for variant, contents in [("official", self.original), ("scissor_is_enabled", self.candidate)]:
            self.source.write_bytes(contents + b"// unreviewed\n")
            with self.assertRaisesRegex(ValueError, "exact .* hash"):
                verify_sdk_variant(self.sdk, self.lock, variant)

    def test_unknown_variant_rejected_without_fallback(self):
        with self.assertRaisesRegex(ValueError, "Unknown QA SDK variant"):
            verify_sdk_variant(self.sdk, self.lock, "scissor_is_enable_typo")

    def test_patch_hash_mismatch_rejected(self):
        self.source.write_bytes(self.candidate)
        self.approved["patch_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "patch file hash mismatch"):
            verify_sdk_variant(self.sdk, self.lock, "scissor_is_enabled")

    def test_baseline_hash_mismatch_rejected(self):
        self.source.write_bytes(self.candidate)
        self.approved["before_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "Reconstructed SDK baseline"):
            verify_sdk_variant(self.sdk, self.lock, "scissor_is_enabled")

    def test_candidate_must_have_exactly_one_replacement(self):
        contents = self.candidate + self.approved["replace_after"].encode()
        self.source.write_bytes(contents)
        self.approved["after_sha256"] = hashlib.sha256(contents).hexdigest()
        with self.assertRaisesRegex(ValueError, "single reviewed query replacement"):
            verify_sdk_variant(self.sdk, self.lock, "scissor_is_enabled")

    def test_missing_or_symlink_source_rejected(self):
        target = self.source.with_suffix(".real")
        self.source.rename(target)
        with self.assertRaisesRegex(ValueError, "regular file"):
            verify_sdk_variant(self.sdk, self.lock)
        self.source.symlink_to(target)
        with self.assertRaisesRegex(ValueError, "regular file"):
            verify_sdk_variant(self.sdk, self.lock)

    def test_candidate_source_must_be_reviewed(self):
        self.approved["source_file"] = "unreviewed.js"
        with self.assertRaisesRegex(ValueError, "outside the reviewed"):
            verify_sdk_variant(self.sdk, self.lock, "scissor_is_enabled")


class EmittedSDKGuards(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.archive = self.folder / "template.zip"

    def emit(self, query, duplicate=False):
        code = f"blitOffscreenFramebuffer:context=>{{var gl=context.GLctx;var prevScissorTest=gl.{query}(3089);if(prevScissorTest)gl.disable(3089)}}"
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("godot.js", code + (code if duplicate else ""))

    def test_each_emitted_query_matches_only_its_explicit_variant(self):
        for variant, query, other in [("official", "getParameter", "scissor_is_enabled"), ("scissor_is_enabled", "isEnabled", "official")]:
            self.emit(query)
            self.assertEqual(validate_emitted_sdk_variant(self.archive, variant)["scissor_query"], query)
            with self.assertRaisesRegex(ValueError, "stale link"):
                validate_emitted_sdk_variant(self.archive, other)

    def test_unrecognized_or_duplicate_blitter_rejected(self):
        self.emit("unreviewedQuery")
        with self.assertRaisesRegex(ValueError, "exact .* query"):
            validate_emitted_sdk_variant(self.archive, "official")
        self.emit("isEnabled", duplicate=True)
        with self.assertRaisesRegex(ValueError, "exact .* query"):
            validate_emitted_sdk_variant(self.archive, "scissor_is_enabled")

    def test_unknown_emitted_variant_does_not_fall_back_to_candidate(self):
        self.emit("isEnabled")
        with self.assertRaisesRegex(ValueError, "Unknown emitted"):
            validate_emitted_sdk_variant(self.archive, "scissor_is_enable_typo")

    def test_prelink_move_is_exact_recoverable_and_preserves_other_outputs(self):
        source = self.folder / "source"
        destination = self.folder / "new-run"
        primary = source / "bin/godot.web.template_release.wasm32.js"
        primary.parent.mkdir(parents=True)
        destination.mkdir()
        primary.write_bytes(b"old engine glue")
        old_zip = primary.with_suffix(".zip")
        old_zip.write_bytes(b"old immutable output")
        object_file = source / "engine.o"
        object_file.write_bytes(b"compiled C++")
        record = archive_primary_js(source, destination, "wasm32")
        self.assertFalse(primary.exists())
        self.assertEqual(Path(record["archive_path"]).read_bytes(), b"old engine glue")
        self.assertEqual(record["sha256"], hashlib.sha256(b"old engine glue").hexdigest())
        self.assertEqual(old_zip.read_bytes(), b"old immutable output")
        self.assertEqual(object_file.read_bytes(), b"compiled C++")
        self.assertIsNone(archive_primary_js(source, destination, "wasm32"))

    def test_prelink_refuses_symlink_or_existing_archive_without_moving_source(self):
        source = self.folder / "source"
        destination = self.folder / "new-run"
        primary = source / "bin/godot.web.template_release.wasm32.js"
        primary.parent.mkdir(parents=True)
        destination.mkdir()
        target = primary.with_suffix(".real")
        target.write_bytes(b"old engine glue")
        primary.symlink_to(target)
        with self.assertRaisesRegex(ValueError, "regular file"):
            archive_primary_js(source, destination, "wasm32")
        primary.unlink()
        primary.write_bytes(b"old engine glue")
        archived = destination / "prelink-inputs" / primary.name
        archived.parent.mkdir()
        archived.write_bytes(b"keep prior archive")
        with self.assertRaisesRegex(ValueError, "must be new"):
            archive_primary_js(source, destination, "wasm32")
        self.assertEqual(primary.read_bytes(), b"old engine glue")
        self.assertEqual(archived.read_bytes(), b"keep prior archive")


class GodotSourceVariantGuards(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.source = Path(self.temporary.name) / "source"
        self.source.mkdir()
        self.lock = json.loads(Path(__file__).with_name("web_worker_template.lock.json").read_text())
        self.files = {}
        for inventory, name, source_file in [("qa_variants", "eval_main_thread", "eval.js"),
                                             ("qa_readback_variants", "current_context", "readback.js")]:
            approved = self.lock[inventory][name]
            original = f"official {name}\n".encode()
            candidate = original + f"reviewed {name}\n".encode()
            approved.update(source_file=source_file, before_sha256=hashlib.sha256(original).hexdigest(),
                            after_sha256=hashlib.sha256(candidate).hexdigest())
            file = self.source / source_file
            file.write_bytes(original)
            self.files[name] = (file, original, candidate)
        (self.source / "unrelated.js").write_bytes(b"keep upstream\n")
        subprocess.run(["git", "init", "-q", str(self.source)], check=True)
        subprocess.run(["git", "-C", str(self.source), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.source), "-c", "user.name=QA", "-c", "user.email=qa@example.invalid",
                        "commit", "-qm", "fixture"], check=True)

    def select(self, eval_variant="official", readback_variant="official"):
        for name, (file, original, candidate) in self.files.items():
            file.write_bytes(candidate if name in (eval_variant, readback_variant) else original)
        return verify_source_variants(self.source, self.lock, eval_variant, readback_variant)

    def test_all_four_orthogonal_godot_selections_and_legacy_api(self):
        for eval_variant in ("official", "eval_main_thread"):
            for readback_variant in ("official", "current_context"):
                result = self.select(eval_variant, readback_variant)
                self.assertEqual([item["id"] for item in result], [eval_variant, readback_variant])
                self.assertEqual([len(item["patches"]) for item in result],
                                 [int(eval_variant != "official"), int(readback_variant != "official")])
                if readback_variant == "official":
                    self.assertEqual(verify_source_variant(self.source, self.lock, eval_variant), result[0])
                else:
                    with self.assertRaises(ValueError):
                        verify_source_variant(self.source, self.lock, eval_variant)

    def test_must_explicitly_select_each_exact_dirty_patch(self):
        self.select("eval_main_thread", "current_context")
        for eval_variant, readback_variant in [("official", "official"), ("eval_main_thread", "official"),
                                                ("official", "current_context")]:
            with self.assertRaises(ValueError):
                verify_source_variants(self.source, self.lock, eval_variant, readback_variant)
        self.select()
        with self.assertRaisesRegex(ValueError, "selected modified source files"):
            verify_source_variants(self.source, self.lock, "official", "current_context")

    def test_unrelated_tracked_or_staged_source_change_is_rejected(self):
        self.select("eval_main_thread", "current_context")
        (self.source / "unrelated.js").write_bytes(b"unreviewed edit\n")
        for staged in (False, True):
            if staged:
                subprocess.run(["git", "-C", str(self.source), "add", "unrelated.js"], check=True)
            with self.assertRaisesRegex(ValueError, "selected modified source files"):
                verify_source_variants(self.source, self.lock, "eval_main_thread", "current_context")

    def test_each_godot_variant_whole_file_hash_is_required(self):
        for name, (file, original, candidate) in self.files.items():
            self.select("eval_main_thread", "current_context")
            file.write_bytes(candidate + b"// unrelated\n")
            with self.assertRaisesRegex(ValueError, "exact reviewed before/after"):
                verify_source_variants(self.source, self.lock, "eval_main_thread", "current_context")

    def test_readback_patch_file_and_upstream_hash_are_required(self):
        self.select("official", "current_context")
        approved = self.lock["qa_readback_variants"]["current_context"]
        original_hash = approved["patch_sha256"]
        approved["patch_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "patch file hash mismatch"):
            verify_source_variants(self.source, self.lock, "official", "current_context")
        approved["patch_sha256"] = original_hash
        approved["before_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "exact reviewed before/after"):
            verify_source_variants(self.source, self.lock, "official", "current_context")

    def test_readback_mode_change_is_rejected(self):
        self.select("official", "current_context")
        self.files["current_context"][0].chmod(0o755)
        with self.assertRaisesRegex(ValueError, "source mode"):
            verify_source_variants(self.source, self.lock, "official", "current_context")

    def test_unknown_or_overlapping_variants_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "Unknown QA readback variant"):
            verify_source_variants(self.source, self.lock, "official", "current_context_typo")
        with self.assertRaisesRegex(ValueError, "Unknown QA source variant"):
            verify_source_variants(self.source, self.lock, "eval_typo", "official")
        self.select("eval_main_thread", "current_context")
        self.lock["qa_readback_variants"]["current_context"]["source_file"] = "eval.js"
        with self.assertRaisesRegex(ValueError, "selected modified source files"):
            verify_source_variants(self.source, self.lock, "eval_main_thread", "current_context")

    def test_build_hash_inventory_includes_both_independent_godot_inputs(self):
        self.select("eval_main_thread", "current_context")
        sdk = Path(self.temporary.name) / "sdk"
        sdk.mkdir()
        (sdk / "gl.js").write_bytes(b"SDK fixture")
        self.lock["emsdk"]["reviewed_source_files"] = {"gl.js": "unused fixture hash"}
        inventory = reviewed_source_hashes(self.source, sdk, self.lock)
        self.assertEqual([(item["owner"], item["source_file"]) for item in inventory],
                         [("godot", "eval.js"), ("godot", "readback.js"), ("emsdk", "gl.js")])
        self.assertEqual(inventory[1]["sha256"], self.lock["qa_readback_variants"]["current_context"]["after_sha256"])


class EmittedReadbackGuards(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.archive = Path(self.temporary.name) / "template.zip"

    def emit(self, variant, duplicate=False):
        selector = "const handle=_emscripten_webgl_get_current_context();const gl=GL.getContext(handle);" \
            if variant == "official" else "const gl=GL.currentContext;"
        code = "function _godot_webgl2_glGetBufferSubData(target,offset,size,data){" \
            "if(ENVIRONMENT_IS_PTHREAD)return proxyToMainThread(189,0,1,target,offset,size,data);" \
            + selector + 'if(gl){gl.GLctx["getBufferSubData"](target,offset,(growMemViews(),HEAPU8),data,size)}}'
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("godot.js", code + (code if duplicate else ""))

    def test_each_linked_selector_matches_only_its_explicit_choice(self):
        for variant, selector, other in [("official", "pthread_tls", "current_context"),
                                          ("current_context", "GL.currentContext", "official")]:
            self.emit(variant)
            result = validate_emitted_readback_variant(self.archive, variant)
            self.assertEqual(result["context_selector"], selector)
            self.assertEqual(result["matching_readbacks"], 1)
            self.assertEqual(result["worker_dispatch"], "proxyToMainThread")
            self.assertTrue(result["synchronous_dispatch"])
            self.assertTrue(result["dispatch_arguments_preserved"])
            with self.assertRaisesRegex(ValueError, "stale link"):
                validate_emitted_readback_variant(self.archive, other)

    def test_duplicate_or_missing_readback_is_rejected(self):
        self.emit("current_context", duplicate=True)
        with self.assertRaisesRegex(ValueError, "exactly one"):
            validate_emitted_readback_variant(self.archive, "current_context")
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("godot.js", "no readback here")
        with self.assertRaisesRegex(ValueError, "exactly one"):
            validate_emitted_readback_variant(self.archive, "official")

    def test_unreviewed_cached_context_or_unknown_variant_is_rejected(self):
        self.emit("current_context")
        with zipfile.ZipFile(self.archive) as archive:
            source = archive.read("godot.js").decode().replace("GL.currentContext", "GL.cachedContext")
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("godot.js", source)
        with self.assertRaisesRegex(ValueError, "exact .* selector"):
            validate_emitted_readback_variant(self.archive, "current_context")
        with self.assertRaisesRegex(ValueError, "Unknown emitted QA readback"):
            validate_emitted_readback_variant(self.archive, "current_context_typo")

    def test_missing_or_async_dispatch_is_rejected_even_with_correct_selector(self):
        prefix = "if(ENVIRONMENT_IS_PTHREAD)return proxyToMainThread(189,0,1,target,offset,size,data);"
        for replacement in ("", prefix.replace("189,0,1", "189,0,0")):
            self.emit("current_context")
            with zipfile.ZipFile(self.archive) as archive:
                source = archive.read("godot.js").decode().replace(prefix, replacement)
            with zipfile.ZipFile(self.archive, "w") as archive:
                archive.writestr("godot.js", source)
            with self.assertRaisesRegex(ValueError, "synchronous worker-to-main dispatch"):
                validate_emitted_readback_variant(self.archive, "current_context")

    def test_wrong_thread_guard_or_changed_argument_order_is_rejected(self):
        for before, after in [("ENVIRONMENT_IS_PTHREAD", "ENVIRONMENT_IS_WORKER"),
                              ("189,0,1,target,offset,size,data", "189,0,1,target,size,offset,data"),
                              ("189,0,1,target,offset,size,data", "189,0,1,target,offset,size")]:
            self.emit("official")
            with zipfile.ZipFile(self.archive) as archive:
                source = archive.read("godot.js").decode().replace(before, after)
            with zipfile.ZipFile(self.archive, "w") as archive:
                archive.writestr("godot.js", source)
            with self.assertRaisesRegex(ValueError, "synchronous worker-to-main dispatch"):
                validate_emitted_readback_variant(self.archive, "official")

    def test_duplicate_proxy_or_changed_function_arguments_are_rejected(self):
        for before, after, error in [
                ("const gl=GL.currentContext;", "proxyToMainThread(189,0,0,target,offset,size,data);const gl=GL.currentContext;", "exactly one synchronous"),
                ("function _godot_webgl2_glGetBufferSubData(target,offset,size,data)",
                 "function _godot_webgl2_glGetBufferSubData(target,offset,size)", "four distinct arguments"),
                ("function _godot_webgl2_glGetBufferSubData(target,offset,size,data)",
                 "function _godot_webgl2_glGetBufferSubData(target,offset,size,size)", "four distinct arguments")]:
            self.emit("current_context")
            with zipfile.ZipFile(self.archive) as archive:
                source = archive.read("godot.js").decode().replace(before, after)
            with zipfile.ZipFile(self.archive, "w") as archive:
                archive.writestr("godot.js", source)
            with self.assertRaisesRegex(ValueError, error):
                validate_emitted_readback_variant(self.archive, "current_context")


if __name__ == "__main__":
    unittest.main(verbosity=2)
