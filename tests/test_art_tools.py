#!/usr/bin/env python3
"""Standard-library tests for authored-art manifests and CLI failure modes."""

from __future__ import annotations

import importlib.util
import json
import re
import subprocess
import sys
import unittest
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

	def test_repository_manifests_validate(self) -> None:
		validator = self.validator_module.ArtValidator()
		self.assertTrue(validator.validate(), "\n".join(validator.errors))

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
