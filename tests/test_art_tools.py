#!/usr/bin/env python3
"""Standard-library tests for authored-art manifests and CLI failure modes."""

from __future__ import annotations

import importlib.util
import copy
import json
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_tool(name: str):
	path = ROOT / f"tools/art/{name}.py"
	spec = importlib.util.spec_from_file_location(name, path)
	if spec is None or spec.loader is None:
		raise RuntimeError(f"cannot import {path}")
	module = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(module)
	return module


class ArtToolTests(unittest.TestCase):
	@classmethod
	def setUpClass(cls) -> None:
		cls.validator_module = load_tool("validate_art")
		cls.merger_module = load_tool("merge_art_fragments")

	def test_repository_authoring_inventory_validates(self) -> None:
		validator = self.validator_module.ArtValidator(include_review_fragments=True)
		self.assertTrue(validator.validate(), "\n".join(validator.errors))
		expected = sum(entry.get("production_ready") is False
			for entry in validator.runtime["assets"] if entry["id"] in validator.review_asset_ids)
		self.assertEqual(validator.unresolved_review_count, expected)

	def test_review_integrity_never_promotes_central_unapproved_asset(self) -> None:
		validator = self.validator_module.ArtValidator(include_review_fragments=True)
		original_load = validator.load_json
		def load_with_unapproved_central(path, label):
			data = original_load(path, label)
			if path == self.validator_module.RUNTIME_MANIFEST:
				data["assets"][0]["production_ready"] = False
			return data
		with patch.object(validator, "load_json", side_effect=load_with_unapproved_central):
			self.assertFalse(validator.validate())
		self.assertTrue(any("must be production_ready=true before registration" in error
			for error in validator.errors), validator.errors)

	def test_screen_space_sampling_policy_is_explicit_and_ui_only(self) -> None:
		module = self.validator_module
		with tempfile.TemporaryDirectory(prefix="waddle-art-sampling-") as directory:
			root = Path(directory).resolve()
			image = root / "assets/art/ui/menu/fish.png"
			image.parent.mkdir(parents=True)
			image.write_bytes((ROOT / "assets/art/ui/menu/home_fish_symbol_clean_v2.png").read_bytes())
			(root / "NOTICE.md").write_text("Project-original test fixture.")
			entry = {"id": "test_ui_fish", "kind": "texture", "groups": ["frontend"],
				"path": "res://assets/art/ui/menu/fish.png", "sha256": module.file_sha256(image),
				"license_id": "project_original", "production_ready": True,
				"source_export_id": "test_source", "sampling_policy": "screen_space_no_mipmaps"}
			validator = module.ArtValidator()
			validator.runtime = json.loads(module.RUNTIME_MANIFEST.read_text())
			validator.runtime["licenses"] = [{"id": "project_original", "notice_path": "res://NOTICE.md"}]
			def check(candidate, mipmaps, compression=0):
				validator.runtime["assets"] = [candidate]
				image.with_name(image.name + ".import").write_text(
					f"compress/mode={compression}\nmipmaps/generate={mipmaps}\n")
				validator.errors.clear()
				validator._validate_runtime()
				return list(validator.errors)
			with patch.object(module, "ROOT", root):
				self.assertEqual(check(entry, "false"), [])
				self.assertTrue(any("requires mipmaps/generate=false" in error
					for error in check(entry, "true")))
				default = {key: value for key, value in entry.items() if key != "sampling_policy"}
				self.assertTrue(any("must generate mipmaps" in error for error in check(default, "false")))
				self.assertEqual(check(default, "true"), [])
				self.assertTrue(any("must generate mipmaps" in error for error in check(default, "missing")))
				self.assertTrue(any("VRAM compressed" in error for error in check(entry, "false", 2)))
				for changes, message in (({"sampling_policy": "unknown"}, "unknown sampling_policy"),
						({"sampling_policy": None}, "unknown sampling_policy"),
						({"kind": "material"}, "restricted to frontend UI textures"),
						({"groups": ["runner"]}, "restricted to frontend UI textures"),
						({"path": "res://assets/art/runner/fish.png"}, "restricted to frontend UI textures"),
						({"path": "res://assets/art/ui/../runner/fish.png"}, "restricted to frontend UI textures")):
					with self.subTest(changes=changes):
						self.assertTrue(any(message in error for error in check(dict(entry, **changes), "false")))

	def test_strict_release_rejects_review_only_registration(self) -> None:
		review = self.validator_module.ArtValidator(include_review_fragments=True)
		self.assertTrue(review.validate(), "\n".join(review.errors))
		strict = self.validator_module.ArtValidator()
		strict.runtime = copy.deepcopy(review.runtime)
		# A rejected proof remains forbidden even if someone copies its record
		# into a production catalog. Strict validation has no review exemptions.
		strict.runtime["assets"][0]["production_ready"] = False
		strict._validate_runtime()
		self.assertTrue(any("must be production_ready=true before registration" in error
			for error in strict.errors), strict.errors)

	def test_review_inventory_still_rejects_orphans_hashes_and_licenses(self) -> None:
		validator = self.validator_module.ArtValidator(include_review_fragments=True)
		self.assertTrue(validator.validate(), "\n".join(validator.errors))
		original = copy.deepcopy(validator.runtime)
		for mutation, expected_error in (("orphan", "unregistered runtime art file"),
				("hash", "sha256 does not match file"), ("license", "uses unknown license_id"),
				("readiness_type", "must be production_ready=true before registration")):
			with self.subTest(mutation=mutation):
				validator.runtime = copy.deepcopy(original)
				validator.errors.clear()
				entry = next(asset for asset in validator.runtime["assets"]
					if asset["id"] in validator.review_asset_ids)
				if mutation == "orphan":
					validator.runtime["assets"].remove(entry)
				elif mutation == "hash":
					entry["sha256"] = "0" * 64
				elif mutation == "license":
					entry["license_id"] = "unapproved_test_license"
				else:
					entry["production_ready"] = "false"
				validator._validate_runtime()
				self.assertTrue(any(expected_error in error for error in validator.errors), validator.errors)

	def test_unverified_reference_is_source_only(self) -> None:
		validator = self.validator_module.ArtValidator(include_review_fragments=True)
		self.assertTrue(validator.validate(), "\n".join(validator.errors))
		self.assertEqual(
			next(item for item in validator.source["concepts"]
				if item["id"] == "hero_penguin_user_reference_2026_08_18")["license_id"],
			"reference_unverified",
		)
		validator.runtime["assets"][0]["license_id"] = "reference_unverified"
		validator.errors.clear()
		validator._validate_runtime()
		self.assertTrue(any("cannot use source-only reference license" in error
			for error in validator.errors), validator.errors)
		validator.source["exports"][0]["license_id"] = "reference_unverified"
		validator.errors.clear()
		validator._validate_source()
		self.assertTrue(any("cannot use source-only reference license" in error
			for error in validator.errors), validator.errors)

	def test_lod_contract_does_not_relax_character_budget(self) -> None:
		validator = self.validator_module.ArtValidator(include_review_fragments=True)
		self.assertTrue(validator.validate(), "\n".join(validator.errors))
		lod = next(job for job in validator.source["exports"] if job["id"] == "hero_penguin_v1_lod1")
		self.assertEqual(lod["asset_class"], "character_lod")
		lod["expected"]["lod0_triangles_max"] = 13000
		validator._validate_source()
		self.assertTrue(any("lod0_triangles_max must be 12000 for character_lod" in error
			for error in validator.errors), validator.errors)
		self.assertEqual(self.validator_module.ASSET_CLASS_BUDGETS["character"]["lod0_triangles_max"], 25000)

	def test_exporter_and_validator_share_asset_class_vocabulary(self) -> None:
		exporter = load_tool("export_art")
		self.assertEqual(exporter.ASSET_CLASSES, set(self.validator_module.ASSET_CLASS_BUDGETS))

	def test_concept_dimensions_and_hash(self) -> None:
		path = ROOT / "art_src/runner/style/concepts/runner_day_keyart_v1.png"
		self.assertEqual(self.validator_module.png_dimensions(path), (1024, 1536))
		self.assertEqual(
			self.validator_module.file_sha256(path),
			"4567688130ca91620948904f0e5aefd0100dc5e9f938d2dd6357127d91ffcad6",
		)

	def test_concept_schema_accepts_scoped_art_source_paths(self) -> None:
		schema = json.loads(
			(ROOT / "art_src/runner/source_manifest.schema.json").read_text(encoding="utf-8")
		)
		concept = schema["properties"]["concepts"]["items"]["properties"]
		for key in ("path", "prompt_path"):
			pattern = re.compile(concept[key]["pattern"])
			self.assertIsNotNone(pattern.match("art_src/characters/hero_reference.png"))
			self.assertIsNotNone(pattern.match("art_src/runner/day/trim_reference.png"))
			self.assertIsNone(pattern.match("assets/art/runtime.png"))
			self.assertIsNone(pattern.match("../art_src/escaped.png"))

	def test_generated_schema_accepts_only_ui_and_painted_runner_sources(self) -> None:
		schema = json.loads(
			(ROOT / "art_src/runner/source_manifest.schema.json").read_text(encoding="utf-8")
		)
		generated = schema["properties"]["generated_assets"]["items"]["properties"]
		for key in ("path", "prompt_path"):
			pattern = re.compile(generated[key]["pattern"])
			for value in ("art_src/ui/runner/icons.png", "art_src/runner/painted/ice.png"):
				self.assertIsNotNone(pattern.match(value), value)
			for value in ("art_src/runner/day/ice.png", "art_src/runner/painted_other/ice.png",
					"art_src/characters/ice.png", "assets/art/ice.png", "../art_src/ui/ice.png"):
				self.assertIsNone(pattern.match(value), value)

	def test_painted_runner_sources_keep_path_hash_license_and_orphan_checks(self) -> None:
		module = self.validator_module
		with tempfile.TemporaryDirectory(prefix="waddle-art-source-") as directory:
			root = Path(directory)
			painted = root / "art_src/runner/painted"
			painted.mkdir(parents=True)
			image = painted / "ice.png"
			image.write_bytes((ROOT / "art_src/runner/painted/runner_painted_ice_v1.png").read_bytes())
			prompt = painted / "ice.prompt.md"
			prompt.write_text("Test generated material source.", encoding="utf-8")
			entry = {
				"id": "test_painted_ice", "path": "art_src/runner/painted/ice.png",
				"prompt_path": "art_src/runner/painted/ice.prompt.md",
				"sha256": module.file_sha256(image), "dimensions": list(module.png_dimensions(image)),
				"generated_on": "2026-10-07", "generator": "test fixture",
				"license_id": "project_original", "status": "production_source",
			}
			validator = module.ArtValidator()
			validator.runtime = {"licenses": [{"id": "project_original"}]}
			validator.source = {"schema_version": module.SCHEMA_VERSION,
				"blender_version": module.BLENDER_VERSION, "exports": [], "concepts": [],
				"generated_assets": [entry]}
			with patch.object(module, "ROOT", root):
				validator._validate_source()
				self.assertEqual(validator.errors, [])
				mutations = (
					("path", "art_src/runner/painted/../ice.png", "must stay below"),
					("prompt_path", "art_src/runner/painted/../ice.prompt.md", "must stay below"),
					("sha256", "0" * 64, "sha256 is invalid or stale"),
					("license_id", "unapproved_test_license", "uses unknown license_id"),
				)
				for key, value, error in mutations:
					with self.subTest(mutation=key):
						validator.source["generated_assets"] = [dict(entry, **{key: value})]
						validator.errors.clear()
						validator._validate_source()
						self.assertTrue(any(error in item for item in validator.errors), validator.errors)
				validator.source["generated_assets"] = [entry]
				(painted / "unregistered.png").write_bytes(image.read_bytes())
				validator.errors.clear()
				validator._validate_source()
				self.assertIn("unregistered generated source: art_src/runner/painted/unregistered.png",
					validator.errors)

	def test_ui_direction_concepts_remain_registered_without_runtime_promotion(self) -> None:
		module = self.validator_module
		with tempfile.TemporaryDirectory(prefix="waddle-ui-concept-") as directory:
			root = Path(directory)
			folder = root / "art_src/ui/concepts"
			folder.mkdir(parents=True)
			image = folder / "outfit.png"
			image.write_bytes((ROOT / "art_src/ui/wardrobe_concepts/emperor_winter_v1.png").read_bytes())
			(folder / "outfit.prompt.md").write_text("Unapproved outfit direction.")
			entry = {"id": "test_outfit", "path": "art_src/ui/concepts/outfit.png",
				"prompt_path": "art_src/ui/concepts/outfit.prompt.md",
				"sha256": module.file_sha256(image), "dimensions": list(module.png_dimensions(image)),
				"generated_on": "2026-10-07", "generator": "test fixture",
				"license_id": "project_original", "status": "art_direction_only"}
			validator = module.ArtValidator()
			validator.runtime = {"licenses": [{"id": "project_original"}]}
			validator.source = {"schema_version": module.SCHEMA_VERSION,
				"blender_version": module.BLENDER_VERSION, "exports": [],
				"concepts": [entry], "generated_assets": []}
			with patch.object(module, "ROOT", root):
				validator._validate_source()
				self.assertEqual(validator.errors, [])
				entry["status"] = "production_source"
				validator._validate_source()
				self.assertIn("concept test_outfit must remain art_direction_only", validator.errors)
				entry["status"] = "art_direction_only"
				entry["sha256"] = "0" * 64
				validator.errors.clear()
				validator._validate_source()
				self.assertIn("concept test_outfit sha256 is invalid or stale", validator.errors)
				entry["sha256"] = module.file_sha256(image)
				(folder / "unregistered.png").write_bytes(image.read_bytes())
				validator.errors.clear()
				validator._validate_source()
				self.assertIn("unregistered generated source: art_src/ui/concepts/unregistered.png", validator.errors)

	def test_missing_blender_is_actionable(self) -> None:
		result = subprocess.run(
			[
				sys.executable,
				str(ROOT / "tools/art/export_art.py"),
				"--check-blender",
				"--blender",
				str(ROOT / "tests/fixtures/art/definitely_missing_blender"),
			],
			cwd=ROOT,
			capture_output=True,
			text=True,
			check=False,
		)
		self.assertEqual(result.returncode, 2)
		self.assertIn("Blender 5.2.0 LTS not found", result.stderr)
		self.assertIn("BLENDER_BIN", result.stderr)

	def test_export_dry_run_needs_no_blender(self) -> None:
		result = subprocess.run(
			[sys.executable, str(ROOT / "tools/art/export_art.py"), "--dry-run"],
			cwd=ROOT,
			capture_output=True,
			text=True,
			check=False,
		)
		self.assertEqual(result.returncode, 0, result.stderr)
		self.assertTrue(
			"no authored Blender export jobs registered" in result.stdout
			or "[art-export] JOB " in result.stdout,
			result.stdout,
		)

	def test_fragment_merge_is_idempotent(self) -> None:
		runtime = {"assets": []}
		source = {"exports": [], "generated_assets": [], "concepts": []}
		fragment = {
			"runtime_assets": [{"id": "sample", "path": "res://assets/art/sample.glb"}],
			"source_exports": [{"id": "sample_source", "output": "assets/art/sample.glb"}],
			"generated_assets": [],
			"concepts": [],
		}
		merged_runtime, merged_source, counts = self.merger_module.merge_documents(
			runtime, source, [fragment, fragment]
		)
		self.assertEqual([entry["id"] for entry in merged_runtime["assets"]], ["sample"])
		self.assertEqual([entry["id"] for entry in merged_source["exports"]], ["sample_source"])
		self.assertEqual(counts["runtime_assets"], 1)

	def test_fragment_merge_rejects_conflict(self) -> None:
		runtime = {"assets": [{"id": "sample", "path": "res://assets/art/a.glb"}]}
		source = {"exports": [], "generated_assets": [], "concepts": []}
		fragment = {
			"runtime_assets": [{"id": "sample", "path": "res://assets/art/b.glb"}],
			"source_exports": [],
			"generated_assets": [],
			"concepts": [],
		}
		with self.assertRaisesRegex(ValueError, "conflicting runtime_assets ID sample"):
			self.merger_module.merge_documents(runtime, source, [fragment])

	def test_khronos_validator_is_exactly_pinned(self) -> None:
		package = json.loads((ROOT / "tools/art/package.json").read_text(encoding="utf-8"))
		lock = json.loads((ROOT / "tools/art/package-lock.json").read_text(encoding="utf-8"))
		self.assertEqual(package["dependencies"]["gltf-validator"], "2.0.0-dev.3.10")
		self.assertEqual(
			lock["packages"]["node_modules/gltf-validator"]["version"],
			"2.0.0-dev.3.10",
		)


if __name__ == "__main__":
	unittest.main()
