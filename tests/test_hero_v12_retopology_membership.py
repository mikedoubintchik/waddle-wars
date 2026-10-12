"""Stored QA cage membership, not solver, geometry or appearance acceptance."""
import copy
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("retopology_membership_test", ROOT / "tools/art/build_hero_penguin_v12_candidate.py")
ADAPTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ADAPTER)


class Cage(dict):
    pass


class StoredMembershipTests(unittest.TestCase):
    def fixture(self):
        mesh = Cage()
        mesh.data = SimpleNamespace(
            vertices=[SimpleNamespace(co=point) for point in ((0., 0., 0.), (1., 0., 0.), (0., 1., 0.),
                                                            (2., 0., 0.), (3., 0., 0.), (2., 1., 0.))],
            polygons=[SimpleNamespace(vertices=(0, 1, 2)), SimpleNamespace(vertices=(3, 4, 5))])
        names = ["HeroBodyV12SmoothField", "EmbeddedSclera+1"]
        assigned = [0, 0, 0, 1, 1, 1]
        mesh[ADAPTER.COMPONENT_MEMBERSHIP_FIELD] = json.dumps({"sources": names, "vertices": assigned})
        rows, _faces = ADAPTER.component_geometry_signatures(mesh.data, assigned, names)
        helper = Path(ADAPTER.__file__).with_name("hero_penguin_v12_retopology.py").resolve()
        audit = {"geometry_policy": ADAPTER.RETOPOLOGY_GEOMETRY_POLICY,
                 "retopology_helper": {"path": str(helper), "sha256": "a" * 64},
                 "lods": [{"source_component_geometry": rows}],
                 "components": [{"lod": 0, "source": name, "after": 1,
                                 "target": ADAPTER.component_target(name, 0, ADAPTER.RETOPOLOGY_GEOMETRY_POLICY)}
                                for name in names]}
        return mesh, [SimpleNamespace(name=name) for name in names], audit

    def recover(self, mesh, sources, audit):
        with patch.object(ADAPTER, "file_sha256", return_value="a" * 64):
            return ADAPTER.recover_stored_components(mesh, sources, 0, audit)

    def test_saved_cage_recovery_preserves_exact_membership_without_solver(self):
        mesh, sources, audit = self.fixture()
        before = copy.deepcopy(audit)
        self.assertEqual(self.recover(mesh, sources, audit), ([0, 0, 0, 1, 1, 1], [0, 1]))
        self.assertEqual(audit, before)

    def test_current_helper_hash_and_fixed_path_are_required(self):
        for defect in ("missing", "hash", "path", "policy"):
            mesh, sources, audit = self.fixture()
            if defect == "missing": del audit["retopology_helper"]
            elif defect == "hash": audit["retopology_helper"]["sha256"] = "b" * 64
            elif defect == "path": audit["retopology_helper"]["path"] = "/different/helper.py"
            else: audit["geometry_policy"] = ADAPTER.UNIFIED_GEOMETRY_POLICY
            with self.subTest(defect=defect), self.assertRaisesRegex(RuntimeError, "helper binding"):
                self.recover(mesh, sources, audit)

    def test_rest_geometry_or_triangle_winding_change_rejects(self):
        for defect in ("position", "winding", "faces", "audit"):
            mesh, sources, audit = self.fixture()
            if defect == "position": mesh.data.vertices[0].co = (.00001, 0., 0.)
            elif defect == "winding": mesh.data.polygons[0].vertices = (0, 2, 1)
            elif defect == "faces": mesh.data.polygons.pop()
            else: audit["lods"][0]["source_component_geometry"][0]["ordered_geometry_sha256"] = "c" * 64
            with self.subTest(defect=defect), self.assertRaisesRegex(RuntimeError, "geometry differs"):
                self.recover(mesh, sources, audit)

    def test_component_order_counts_targets_and_labels_are_not_guessed(self):
        for defect in ("order", "count", "target", "boolean", "range", "bridge", "missing"):
            mesh, sources, audit = self.fixture()
            saved = json.loads(mesh[ADAPTER.COMPONENT_MEMBERSHIP_FIELD])
            if defect == "order": sources.reverse()
            elif defect == "count": audit["components"][0]["after"] = 2
            elif defect == "target": audit["components"][0]["target"] = 15000
            elif defect == "boolean": saved["vertices"][0] = False
            elif defect == "range": saved["vertices"][0] = 2
            elif defect == "bridge": saved["vertices"][0] = 1
            elif defect == "missing": saved["vertices"].pop()
            mesh[ADAPTER.COMPONENT_MEMBERSHIP_FIELD] = json.dumps(saved)
            with self.subTest(defect=defect), self.assertRaises(RuntimeError):
                self.recover(mesh, sources, audit)

    def test_nontriangular_or_nonfinite_cage_rejects(self):
        mesh, sources, audit = self.fixture()
        mesh.data.polygons[0].vertices = (0, 1, 2, 0)
        with self.assertRaisesRegex(RuntimeError, "non-triangular"):
            self.recover(mesh, sources, audit)
        mesh, sources, audit = self.fixture()
        mesh.data.vertices[0].co = (float("nan"), 0., 0.)
        with self.assertRaisesRegex(RuntimeError, "nonfinite"):
            self.recover(mesh, sources, audit)


if __name__ == "__main__":
    unittest.main()
