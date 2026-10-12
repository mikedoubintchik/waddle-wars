#!/usr/bin/env python3
"""Exact duplicate regression, without Blender or a rendering device.

Default: source primitive uniqueness, runtime triangle counts and hash integrity.
Optional --baseline-dir PATH additionally proves every unique triangle and all
its exported vertex attributes survived, while only duplicate copies vanished.
The baseline directory must contain the two original GLBs and generator source.
"""

from __future__ import annotations

import argparse
import ast
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import struct
import unittest


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "art_src/runner/day/generate_day_kit.py"
RUNTIME = ROOT / "assets/art/runner/day"
CASES = {
    "runner_day_ramp_v1": ("build_ramp", "green_chevron_", 8, 2456, 352),
    "runner_day_icebreaker_landmark_v1": ("build_icebreaker_landmark", "bridge_window_", 8, 15040, 1504),
}
BASELINE: Path | None = None


def freeze(value):
    if isinstance(value, dict):
        return tuple(sorted((key, freeze(item)) for key, item in value.items()))
    if isinstance(value, (list, tuple)):
        return tuple(freeze(item) for item in value)
    return value


def primitive_calls(path: Path, function_name: str):
    """Execute only the target builder with recording primitives, not bpy."""
    source = ast.parse(path.read_text(encoding="utf-8"))
    target = next(node for node in source.body
                  if isinstance(node, ast.FunctionDef) and node.name == function_name)
    target.returns = None
    calls = []
    namespace = {"math": math, "collection": lambda name: name}
    for node in source.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 \
                and isinstance(node.targets[0], ast.Name):
            try:
                namespace[node.targets[0].id] = ast.literal_eval(node.value)
            except (ValueError, TypeError):
                pass
    for kind in ("box", "beam", "wedge", "sphere", "cylinder", "torus"):
        def record(collection, name, *args, _kind=kind, **kwargs):
            calls.append((name, (_kind, freeze(args), freeze(kwargs))))
        namespace[kind] = record
    module = ast.fix_missing_locations(ast.Module(body=[target], type_ignores=[]))
    exec(compile(module, str(path), "exec"), namespace)
    namespace[function_name]()
    return calls


def glb_triangles(path: Path, *, include_attributes: bool):
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", raw)
    assert (magic, version, length) == (0x46546C67, 2, len(raw))
    chunks = {}
    offset = 12
    while offset < len(raw):
        size, kind = struct.unpack_from("<II", raw, offset)
        chunks[kind] = raw[offset + 8:offset + 8 + size]
        offset += size + 8
    document = json.loads(chunks[0x4E4F534A])
    binary = chunks[0x004E4942]

    def accessor(index):
        entry = document["accessors"][index]
        assert "sparse" not in entry
        view = document["bufferViews"][entry["bufferView"]]
        component = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}[entry["componentType"]]
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[entry["type"]]
        fmt = "<" + component * width
        stride = view.get("byteStride", struct.calcsize(fmt))
        start = view.get("byteOffset", 0) + entry.get("byteOffset", 0)
        return [struct.unpack_from(fmt, binary, start + i * stride) for i in range(entry["count"])]

    result = Counter()
    primitives = [primitive for mesh in document["meshes"] for primitive in mesh["primitives"]]
    assert len(primitives) == 1, "dedupe must not add material surfaces"
    for primitive in primitives:
        assert primitive.get("mode", 4) == 4
        names = sorted(primitive["attributes"]) if include_attributes else ["POSITION"]
        columns = [(name, accessor(primitive["attributes"][name])) for name in names]
        vertices = [tuple((name, values[index]) for name, values in columns)
                    for index in range(len(columns[0][1]))]
        indices = [index[0] for index in accessor(primitive["indices"])]
        assert len(indices) % 3 == 0
        for index in range(0, len(indices), 3):
            # Preserve winding; only cyclic corner rotation is equivalent.
            triangle = tuple(vertices[i] for i in indices[index:index + 3])
            key = min(triangle, triangle[1:] + triangle[:1], triangle[2:] + triangle[:2])
            result[key] += 1
    return result


class RunnerDayDuplicateTests(unittest.TestCase):
    def test_source_contains_each_visible_primitive_once(self):
        for asset_id, (builder, prefix, expected, _triangles, _removed) in CASES.items():
            with self.subTest(asset=asset_id):
                calls = primitive_calls(GENERATOR, builder)
                self.assertEqual(sum(name.startswith(prefix) for name, _key in calls), expected)
                counts = Counter(key for _name, key in calls)
                self.assertEqual(max(counts.values()), 1, "identical primitive emitted twice")

    def test_runtime_has_expected_unique_triangle_count(self):
        for asset_id, (_builder, _prefix, _expected, triangles, _removed) in CASES.items():
            with self.subTest(asset=asset_id):
                counts = glb_triangles(RUNTIME / f"{asset_id}.glb", include_attributes=False)
                self.assertEqual(sum(counts.values()), triangles)
                self.assertEqual(len(counts), triangles, "coincident triangle copies returned")

    def test_matching_fragment_hashes(self):
        fragment = json.loads((ROOT / "data/art/fragments/runner_day_kit_v1.json").read_text())
        for record in fragment["source_exports"]:
            with self.subTest(source=record["id"]):
                source = ROOT / record["source"]
                self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), record["source_sha256"])
        for record in fragment["runtime_assets"]:
            if record["id"] not in {name + "_mesh" for name in CASES}:
                continue
            runtime = ROOT / record["path"].removeprefix("res://")
            self.assertEqual(hashlib.sha256(runtime.read_bytes()).hexdigest(), record["sha256"])

    def test_baseline_unique_surfaces_preserved(self):
        if BASELINE is None:
            self.skipTest("pass --baseline-dir to prove exact before/after surface preservation")
        for asset_id, (builder, _prefix, _expected, _triangles, removed) in CASES.items():
            with self.subTest(asset=asset_id):
                before_calls = primitive_calls(BASELINE / GENERATOR.name, builder)
                after_calls = primitive_calls(GENERATOR, builder)
                self.assertEqual({key for _name, key in before_calls},
                                 {key for _name, key in after_calls})
                before = glb_triangles(BASELINE / f"{asset_id}.glb", include_attributes=True)
                after = glb_triangles(RUNTIME / f"{asset_id}.glb", include_attributes=True)
                self.assertEqual(set(before), set(after), "unique position/normal/tangent/UV/color changed")
                self.assertEqual(sum(before.values()) - sum(after.values()), removed)
                self.assertTrue(all(after[key] == 1 for key in after))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--baseline-dir", type=Path)
    args, remaining = parser.parse_known_args()
    BASELINE = args.baseline_dir
    unittest.main(argv=[__file__, *remaining])
