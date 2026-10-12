"""Small real-GLB fixtures for the post-export atlas parity gate. No Blender."""

import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest


TOOL_PATH = Path(__file__).resolve().parents[1] / "tools/art/audit_hero_v12_atlas_export.py"
SPEC = importlib.util.spec_from_file_location("hero_v12_atlas_export", TOOL_PATH)
TOOL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TOOL)
IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


class Fixture:
    def __init__(self, seams=False):
        self.binary = bytearray()
        self.doc = {
            "asset": {"version": "2.0"}, "buffers": [{}], "bufferViews": [], "accessors": [],
            "nodes": [
                {"name": "root", "children": [1]},
                {"name": "head", "children": [2, 3, 4, 5], "translation": [0, 1, 0]},
                *({"name": name, "translation": [0, 0.1 * i, 0]} for i, name in enumerate(TOOL.SOCKETS)),
                {"name": "HeroPenguinMesh", "mesh": 0, "skin": 0},
            ],
            "scenes": [{"nodes": [0, 6]}], "scene": 0,
            "meshes": [{"name": "HeroPenguinMesh", "extras": {"targetNames": list(TOOL.MORPHS)},
                        "weights": [0] * 8, "primitives": []}],
            "skins": [{"name": "PenguinSkeleton", "joints": [0, 1]}],
            "animations": [], "materials": [{}, {}],
        }
        self.doc["skins"][0]["inverseBindMatrices"] = self.add([IDENTITY, IDENTITY], "MAT4")
        points = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)]
        # Same oriented triangles, reordered, cyclically rotated, separate
        # material primitives and duplicated seam vertices.
        groups = [([points[i] for i in (2, 3, 0)], [0, 1, 2]),
                  ([points[i] for i in (1, 2, 0)], [0, 1, 2])] if seams else [(points, [0, 1, 2, 0, 2, 3])]
        for number, (positions, indices) in enumerate(groups):
            attributes = {
                "POSITION": self.add(positions, "VEC3"),
                "JOINTS_0": self.add([(0, 1, 0, 0)] * len(positions), "VEC4", 5121),
                "WEIGHTS_0": self.add([(.4, .6, 0, 0)] * len(positions), "VEC4"),
                "NORMAL": self.add([(0, 0, 1)] * len(positions), "VEC3"),
                "TEXCOORD_0": self.add([(0, 0)] * len(positions), "VEC2"),
            }
            targets = [{"POSITION": self.add([(p[0] * m * .001, p[1] * .002, .003 * m)
                                               for p in positions], "VEC3")} for m in range(8)]
            self.doc["meshes"][0]["primitives"].append({"attributes": attributes, "targets": targets,
                                                        "indices": self.add([(i,) for i in indices], "SCALAR", 5123),
                                                        "material": number})
        for clip in TOOL.CLIPS:
            times = self.add([(0,), (0.5,), (1,)], "SCALAR")
            values = self.add([(0, 0, 0, 1), (0, .1, 0, (1 - .01) ** .5), (0, 0, 0, 1)], "VEC4")
            self.doc["animations"].append({"name": clip,
                "samplers": [{"input": times, "output": values, "interpolation": "LINEAR"}],
                "channels": [{"sampler": 0, "target": {"node": 1, "path": "rotation"}}]})

    def add(self, rows, kind, component=5126, normalized=False, stride_extra=0):
        while len(self.binary) % 4:
            self.binary.append(0)
        offset = len(self.binary)
        fmt, size = TOOL.COMPONENTS[component]
        width = TOOL.WIDTHS[kind]
        for row in rows:
            self.binary.extend(struct.pack("<" + fmt * width, *row))
            self.binary.extend(b"\0" * stride_extra)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(self.binary) - offset}
        if stride_extra:
            view["byteStride"] = size * width + stride_extra
        self.doc["bufferViews"].append(view)
        accessor = {"bufferView": len(self.doc["bufferViews"]) - 1, "count": len(rows),
                    "type": kind, "componentType": component}
        if normalized:
            accessor["normalized"] = True
        self.doc["accessors"].append(accessor)
        return len(self.doc["accessors"]) - 1

    def patch(self, accessor, row, component, value):
        a = self.doc["accessors"][accessor]
        view = self.doc["bufferViews"][a["bufferView"]]
        fmt, size = TOOL.COMPONENTS[a["componentType"]]
        offset = (view["byteOffset"] + a.get("byteOffset", 0)
                  + row * view.get("byteStride", TOOL.WIDTHS[a["type"]] * size) + component * size)
        struct.pack_into("<" + fmt, self.binary, offset, value)

    def write(self, path):
        self.doc["buffers"][0]["byteLength"] = len(self.binary)
        json_bytes = json.dumps(self.doc).encode()
        json_bytes += b" " * (-len(json_bytes) % 4)
        binary = bytes(self.binary) + b"\0" * (-len(self.binary) % 4)
        body = (struct.pack("<II", len(json_bytes), 0x4E4F534A) + json_bytes
                + struct.pack("<II", len(binary), 0x004E4942) + binary)
        path.write_bytes(struct.pack("<4sII", b"glTF", 2, len(body) + 12) + body)

    @property
    def primitive(self):
        return self.doc["meshes"][0]["primitives"][0]

    def reorder_nodes_and_joints(self):
        order = list(reversed(range(len(self.doc["nodes"]))))
        index = {old: new for new, old in enumerate(order)}
        self.doc["nodes"] = [self.doc["nodes"][i] for i in order]
        for node in self.doc["nodes"]:
            if "children" in node:
                node["children"] = [index[i] for i in reversed(node["children"])]
        self.doc["scenes"][0]["nodes"] = [index[i] for i in reversed(self.doc["scenes"][0]["nodes"])]
        self.doc["skins"][0]["joints"] = [index[1], index[0]]
        for animation in self.doc["animations"]:
            for channel in animation["channels"]:
                channel["target"]["node"] = index[channel["target"]["node"]]
        for primitive in self.doc["meshes"][0]["primitives"]:
            accessor = primitive["attributes"]["JOINTS_0"]
            for row in range(self.doc["accessors"][accessor]["count"]):
                for component, value in enumerate((1, 0, 1, 1)):
                    self.patch(accessor, row, component, value)


class AtlasExportAuditTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.before = Fixture()
        self.after = Fixture(seams=True)
        self.baseline = Path(self.directory.name) / "before.glb"
        self.candidate = Path(self.directory.name) / "after.glb"

    def compare(self, **kwargs):
        self.before.write(self.baseline)
        self.after.write(self.candidate)
        return TOOL.audit(self.baseline, self.candidate, **kwargs)

    def reject(self, expected):
        result = self.compare()
        self.assertFalse(result["passed"], result)
        self.assertIn(expected, " ".join(result["errors"]))

    def test_seams_reindex_material_split_and_logical_rig_reorder_pass(self):
        self.after.reorder_nodes_and_joints()
        self.after.doc["animations"].reverse()
        self.after.doc["nodes"][-1]["matrix"] = IDENTITY
        result = self.compare()
        self.assertTrue(result["passed"], result)
        self.assertEqual(result["baseline"]["geometry"]["exported_vertices"], 4)
        self.assertEqual(result["candidate"]["geometry"]["exported_vertices"], 6)
        self.assertEqual(result["animations"]["clip_count"], 23)
        self.assertEqual(result["triangle_multiset"]["missing_oriented_triangles"], 0)
        self.assertEqual(len(result["rig"]["sockets"]), 4)
        self.assertEqual(len(result["baseline"]["sha256"]), 64)

    def test_winding_reversal_fails(self):
        indices = self.after.primitive["indices"]
        self.after.patch(indices, 1, 0, 2)
        self.after.patch(indices, 2, 0, 1)
        self.reject("oriented triangle multiset changed")

    def test_duplicated_triangle_fails_even_with_same_vertex_set(self):
        self.after = Fixture()
        indices = self.after.primitive["indices"]
        self.after.patch(indices, 4, 0, 1)
        self.after.patch(indices, 5, 0, 2)
        self.reject("oriented triangle multiset changed")

    def test_position_change_fails(self):
        self.after.patch(self.after.primitive["attributes"]["POSITION"], 0, 2, .002)
        self.reject("position/skin/morph payload")

    def test_skin_assignment_change_fails(self):
        self.after.patch(self.after.primitive["attributes"]["WEIGHTS_0"], 0, 0, .5)
        self.after.patch(self.after.primitive["attributes"]["WEIGHTS_0"], 0, 1, .5)
        self.reject("position/skin/morph payload")

    def test_morph_delta_change_fails(self):
        self.after.patch(self.after.primitive["targets"][7]["POSITION"], 0, 2, .03)
        self.reject("position/skin/morph payload")

    def test_missing_morph_fails(self):
        self.after.primitive["targets"].pop()
        self.reject("missing species morphs")

    def test_named_morph_reordering_passes(self):
        mesh = self.after.doc["meshes"][0]
        mesh["extras"]["targetNames"].reverse()
        mesh["weights"].reverse()
        for primitive in mesh["primitives"]:
            primitive["targets"].reverse()
        self.assertTrue(self.compare()["passed"])

    def test_normal_uv_changes_intentionally_not_claimed(self):
        self.after.patch(self.after.primitive["attributes"]["NORMAL"], 0, 2, -1)
        self.after.patch(self.after.primitive["attributes"]["TEXCOORD_0"], 0, 1, 1)
        result = self.compare()
        self.assertTrue(result["passed"], result)
        self.assertTrue(any("normals and tangents" in text for text in result["omissions"]))

    def test_small_export_rounding_records_measured_delta(self):
        self.after.patch(self.after.primitive["attributes"]["POSITION"], 0, 2, .0000005)
        result = self.compare()
        self.assertTrue(result["passed"], result)
        self.assertGreater(result["measured_max_deltas"]["position"], 0)
        self.assertLessEqual(result["measured_max_deltas"]["position"], 1e-6)
        self.assertEqual(result["triangle_multiset"]["tolerance_matched_payloads"], 1)

    def test_tolerance_cannot_be_loosened(self):
        result = self.compare(tolerance=1e-5)
        self.assertFalse(result["passed"])
        self.assertIn("<=1e-6", result["errors"][0])

    def test_weight_slot_order_and_aggregation_are_logical(self):
        for primitive in self.after.doc["meshes"][0]["primitives"]:
            attrs = primitive["attributes"]
            for row in range(3):
                for component, value in enumerate((1, 0, 0, 0)):
                    self.after.patch(attrs["JOINTS_0"], row, component, value)
                for component, value in enumerate((.6, .2, .2, 0)):
                    self.after.patch(attrs["WEIGHTS_0"], row, component, value)
        self.assertTrue(self.compare()["passed"])

    def test_inverse_bind_change_fails(self):
        self.after.patch(self.after.doc["skins"][0]["inverseBindMatrices"], 1, 13, .1)
        self.reject("inverse_bind_matrix")

    def test_rest_transform_change_fails(self):
        self.after.doc["nodes"][1]["translation"][1] = 1.01
        self.reject("node_rest_matrix")

    def test_joint_parent_change_fails(self):
        self.after.doc["nodes"][0]["children"] = []
        self.reject("hierarchy changed")

    def test_missing_socket_fails(self):
        self.after.doc["nodes"][2]["name"] = "not_a_socket"
        self.reject("missing required cosmetic socket")

    def test_socket_parent_change_fails(self):
        self.after.doc["nodes"][1]["children"].remove(2)
        self.after.doc["nodes"][0]["children"].append(2)
        self.reject("hierarchy changed")

    def test_clip_removed_fails(self):
        self.after.doc["animations"].pop()
        self.reject("23-clip library")

    def test_animation_sample_time_change_fails(self):
        self.after.patch(self.after.doc["animations"][0]["samplers"][0]["input"], 1, 0, .51)
        self.reject("animation_sample_time")

    def test_animation_output_change_fails(self):
        sampler = self.after.doc["animations"][0]["samplers"][0]
        self.after.patch(sampler["output"], 1, 1, .2)
        self.after.patch(sampler["output"], 1, 3, (1 - .04) ** .5)
        self.reject("animation_rotation")

    def test_quaternion_sign_equivalence_passes(self):
        self.after.patch(self.after.doc["animations"][0]["samplers"][0]["output"], 0, 3, -1)
        self.assertTrue(self.compare()["passed"])

    def test_unsupported_interpolation_fails_closed(self):
        self.after.doc["animations"][0]["samplers"][0]["interpolation"] = "CUBICSPLINE"
        self.reject("unsupported animation interpolation")

    def test_accessor_unsupported_missing_and_bounds_fail_closed(self):
        for mutation, message in (
            (lambda a: a.update(type="MAT3"), "unsupported format"),
            (lambda a: a.pop("bufferView"), "missing bufferView"),
            (lambda a: a.update(sparse={"count": 1}), "unsupported sparse index format"),
            (lambda a: a.update(count=100000), "out-of-bounds"),
        ):
            with self.subTest(message=message):
                self.after = Fixture(seams=True)
                mutation(self.after.doc["accessors"][self.after.primitive["attributes"]["POSITION"]])
                self.reject(message)

    def test_sparse_morph_zero_base_and_dense_override_are_read(self):
        for dense_base in (False, True):
            with self.subTest(dense_base=dense_base):
                self.after = Fixture(seams=True)
                target = self.after.primitive["targets"][0]["POSITION"]
                indices = self.after.add([(0,), (1,)], "SCALAR", 5121)
                values = self.after.add([(0, .002, 0), (0, .002, 0)], "VEC3")
                accessor = self.after.doc["accessors"][target]
                if not dense_base:
                    accessor.pop("bufferView")
                accessor["sparse"] = {"count": 2,
                    "indices": {"bufferView": self.after.doc["accessors"][indices]["bufferView"], "componentType": 5121},
                    "values": {"bufferView": self.after.doc["accessors"][values]["bufferView"]}}
                result = self.compare()
                self.assertTrue(result["passed"], result)
                self.after.patch(indices, 1, 0, 0)
                self.reject("invalid sparse indices")

    def test_strided_accessor_is_read_correctly(self):
        self.after.primitive["attributes"]["POSITION"] = self.after.add(
            [(1, 1, 0), (0, 1, 0), (0, 0, 0)], "VEC3", stride_extra=4)
        self.assertTrue(self.compare()["passed"])

    def test_normalized_integer_weights_are_read_correctly(self):
        for primitive in self.after.doc["meshes"][0]["primitives"]:
            primitive["attributes"]["WEIGHTS_0"] = self.after.add(
                [(102, 153, 0, 0)] * 3, "VEC4", 5121, normalized=True)
        self.assertTrue(self.compare()["passed"])

    def test_geometry_extension_rejected_appearance_extension_allowed(self):
        self.after.doc["extensionsUsed"] = ["KHR_materials_ior"]
        self.assertTrue(self.compare()["passed"])
        self.after.doc["extensionsUsed"] = ["KHR_draco_mesh_compression"]
        self.reject("unsupported extension")

    def test_cli_failed_audit_exits_nonzero_and_retains_hashes(self):
        self.after.doc["animations"].pop()
        self.compare()
        process = subprocess.run([sys.executable, str(TOOL_PATH), "--baseline", str(self.baseline),
                                  "--candidate", str(self.candidate)], text=True, capture_output=True)
        self.assertEqual(process.returncode, 1, process.stderr)
        report = json.loads(process.stdout)
        self.assertFalse(report["passed"])
        self.assertEqual(len(report["candidate"]["sha256"]), 64)


if __name__ == "__main__":
    unittest.main()
