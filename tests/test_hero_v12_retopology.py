"""Concrete host math/API guards for one automated BODY QA cage; no Blender."""
import ast
import copy
import importlib.util
import io
from pathlib import Path
import struct
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("v12_body_retopology_test", ROOT / "tools/art/hero_penguin_v12_retopology.py")
ART = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ART)


def frames():
    return {side: ((side * .2, 0., 0.), (1., 0., 0.), (0., 1., 0.), (0., 0., 1.)) for side in (-1., 1.)}


def tetrahedron():
    return [(0., 0., 0.), (1., 0., 0.), (0., 1., 0.), (0., 0., 1.)], [(0, 2, 1), (0, 1, 3), (0, 3, 2), (1, 2, 3)]


def metric():
    return {"samples": 3, "maximum_m": .006, "aperture_samples": 1, "aperture_maximum_m": .003,
            "bottom_samples": 1, "bottom_maximum_m": .002}


def stored_tetrahedron():
    points, triangles = tetrahedron()
    edges, lookup, corners = [], {}, []
    for face in triangles:
        for first, second in zip(face, (*face[1:], face[0])):
            key = tuple(sorted((first, second)))
            if key not in lookup:
                lookup[key] = len(edges)
                edges.append(key)
            corners.append((first, lookup[key]))
    return points, edges, corners


class StoredMesh:
    """Small real-layout fixture: Blender coordinates serialized as float32."""
    def __init__(self, points, triangles, edges, corners, corrupt=None):
        self.vertices = [SimpleNamespace(co=tuple(ART.float32(value) for value in point)) for point in points]
        self.polygons = [SimpleNamespace(vertices=face) for face in triangles]
        self.loop_triangles = [SimpleNamespace(vertices=face) for face in triangles]
        self.edges = [SimpleNamespace(vertices=edge) for edge in edges]
        self.loops = [SimpleNamespace(vertex_index=vertex, edge_index=edge) for vertex, edge in corners]
        self.corrupt, self.updates = corrupt, 0

    def update(self):
        self.updates += 1
        for vertex in self.vertices:
            vertex.co = tuple(ART.float32(value) for value in vertex.co)
        if self.corrupt:
            self.corrupt(self)

    def calc_loop_triangles(self):
        pass


class RetopologyTests(unittest.TestCase):
    def test_settings_fixed_nonzero_seed_one_faces_solve_no_attribute_guessing(self):
        settings = ART.quadriflow_settings(14000)
        self.assertEqual(settings, {"mode": "FACES", "target_faces": 6000, "seed": 37,
            "use_mesh_symmetry": False, "use_preserve_sharp": True, "use_preserve_boundary": True,
            "preserve_attributes": False, "smooth_normals": True})
        self.assertEqual(ART.quadriflow_settings(6440)["target_faces"], 2760)
        self.assertEqual(ART.SIZING_POLICY, "fixed-request-three-sevenths-final-triangle-cap-v1")
        for invalid in (True, 999, 14001, 14000., "14000", None):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError): ART.quadriflow_settings(invalid)

    def test_no_solver_retry_or_mutable_source_design_import(self):
        tree = ast.parse(Path(ART.__file__).read_text())
        calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)
                 and isinstance(node.func, ast.Attribute) and node.func.attr == "quadriflow_remesh"]
        self.assertEqual(len(calls), 1)
        imports = [alias.name for node in ast.walk(tree) if isinstance(node, ast.Import) for alias in node.names]
        imports += [node.module or "" for node in ast.walk(tree) if isinstance(node, ast.ImportFrom)]
        self.assertFalse(any(name.startswith("hero_penguin") for name in imports))
        triangulation = next(node for node in ast.walk(tree) if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute) and node.func.attr == "triangulate")
        kwargs = {keyword.arg: keyword.value.value for keyword in triangulation.keywords if isinstance(keyword.value, ast.Constant)}
        self.assertEqual(kwargs, {"quad_method": "FIXED", "ngon_method": "EAR_CLIP"})

    def test_stored_edge_corner_predicate_passes_oriented_closed_mesh(self):
        points, edges, corners = stored_tetrahedron()
        report = ART.blender_input_predicate(points, edges, corners)
        self.assertTrue(report["passed"])
        self.assertEqual(report["stored_edges"], 6)
        self.assertEqual(report["stored_corners"], 12)
        self.assertEqual(report["coordinate_close_edges"], 0)
        self.assertEqual(report["same_start_orientation_corners"], 0)
        self.assertEqual(report["wire_edges"], 0)
        self.assertEqual(report["boundary_edges"], 0)

    def test_blender_rejection_is_float32_per_axis_not_euclidean_or_exact_duplicates(self):
        report = ART.blender_input_predicate([(0., 0., 0.), (.0001, .0001, .0001)], [(0, 1)], [(0, 0)])
        self.assertFalse(report["passed"])
        self.assertEqual(report["first_rejection"]["kind"], "coordinate_close_edge")
        self.assertEqual(report["coordinate_close_edges"], 1)
        self.assertGreater(report["minimum_stored_edge_units"], .0001)
        for point in ((.00010001, 0., 0.), (0., .00010001, 0.), (0., 0., .00010001)):
            with self.subTest(point=point):
                report = ART.blender_input_predicate([(0., 0., 0.), point], [(0, 1)], [(0, 0)])
                self.assertTrue(report["passed"])
        report = ART.blender_input_predicate([(0., 0., 0.), (1.228781230931777e-7, 0., 0.)], [(0, 1)], [(0, 0)])
        self.assertFalse(report["passed"])

    def test_exact_stored_predicate_rejects_wire_overused_and_same_start_corner(self):
        for defect in ("wire", "overused", "flipped"):
            points, edges, corners = stored_tetrahedron()
            if defect == "wire":
                edges.append((1, 2))
            elif defect == "overused":
                corners.append(corners[0])
            else:
                matching = [index for index, (_vertex, edge) in enumerate(corners) if edge == corners[0][1]]
                corners[matching[1]] = corners[matching[0]]
            with self.subTest(defect=defect):
                report = ART.blender_input_predicate(points, edges, corners)
                self.assertFalse(report["passed"])
                self.assertEqual(report["first_rejection"]["kind"],
                                 {"wire": "wire_edge", "overused": "edge_more_than_two_faces", "flipped": "same_corner_start_vertex"}[defect])

    def test_stored_api_uses_edges_and_corner_edges_without_normals_or_cache_assumptions(self):
        points, edges, corners = stored_tetrahedron()
        mesh = SimpleNamespace(vertices=[SimpleNamespace(co=point) for point in points],
                               edges=[SimpleNamespace(vertices=edge) for edge in edges],
                               loops=[SimpleNamespace(vertex_index=vertex, edge_index=edge) for vertex, edge in corners])
        self.assertTrue(ART.stored_input_report(mesh)["passed"])
        mesh.loops[0].edge_index = len(edges)
        with self.assertRaisesRegex(ValueError, "stored solver corner"): ART.stored_input_report(mesh)
        with self.assertRaisesRegex(ValueError, "stored solver edge"):
            ART.blender_input_predicate(points, [(0, len(points))], [])

    def test_fixed_private_units_no_weld_threshold_changes_or_retry_and_restore_before_projection(self):
        tree = ast.parse(Path(ART.__file__).read_text())
        conditioner = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "condition_solver_copy")
        forbidden = {"remove_doubles", "dissolve_degenerate", "dissolve_edges", "collapse", "delete"}
        self.assertFalse(any(isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                             and node.func.attr in forbidden for node in ast.walk(tree)))
        self.assertEqual(ART.SOLVER_UNIT_SCALE, 4096)
        self.assertEqual(ART.CONDITIONING_POLICY, "private-solver-copy-power2-units-4096-v1")
        self.assertEqual(ART.BLENDER_EDGE_EPSILON, struct.unpack("<f", struct.pack("<f", .0001))[0])
        self.assertFalse(any(isinstance(node, ast.While) for node in ast.walk(conditioner)))
        build = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "build_body")
        names = [(node.lineno, node.func.id) for node in ast.walk(build) if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)]
        lines = {name: line for line, name in names}
        self.assertLess(next(line for line, name in names if name == "condition_solver_copy"),
                        next(line for line, name in names if name == "invoke_quadriflow_once"))
        self.assertEqual(lines["restore_solver_units"], lines["invoke_quadriflow_once"] + 1)
        self.assertLess(lines["restore_solver_units"], lines["quad_statistics"])
        self.assertLess(lines["restore_solver_units"], lines["nearest_hit"])
        for name in ("require_closed", "stored_topology_guard", "stored_input_report"):
            self.assertTrue(any(isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == name
                                for node in ast.walk(conditioner)))

    def test_power2_unit_inverse_is_float32_bit_exact_including_subnormals_and_signed_zero(self):
        points = [(1.228781230931777e-7, -.3608185946941376, -0.), (1e-40, 1.48, .245)]
        scaled, restored = ART.scale_solver_points(points)
        for original, multiplied, inverse in zip(points, scaled, restored):
            self.assertEqual(struct.pack("<3f", *original), struct.pack("<3f", *inverse))
            self.assertEqual(tuple(ART.float32(ART.float32(value) * 4096) for value in original), multiplied)
        for defect in (float("inf"), float("nan"), 3.4028234663852886e38):
            with self.subTest(defect=defect), self.assertRaises(ValueError):
                ART.scale_solver_points([(defect, 0., 0.)])

    def test_private_units_preserve_indexed_high_mesh_and_report_zero_meter_error(self):
        points, edges, corners = stored_tetrahedron()
        points[1] = (1.228781230931777e-7, 0., 0.)
        triangles = tetrahedron()[1]
        mesh = StoredMesh(points, triangles, edges, corners)
        high = [tuple(vertex.co) for vertex in mesh.vertices]
        topology = ART.mesh_topology(high, triangles)
        report = {}
        with patch("sys.stdout", io.StringIO()):
            ART.condition_solver_copy(SimpleNamespace(data=mesh), high, triangles, topology, report)
        detail = report["conditioning"]
        self.assertTrue(detail["passed"])
        self.assertEqual(detail["before_predicate"]["coordinate_close_edges"], 1)
        self.assertEqual(detail["after_predicate"]["coordinate_close_edges"], 0)
        self.assertTrue(detail["inverse_float32_coordinate_identity"])
        self.assertTrue(detail["stored_topology_unchanged"])
        self.assertTrue(detail["triangle_indices_unchanged"])
        self.assertFalse(detail["topology_cleanup_performed"])
        self.assertEqual(high, [tuple(ART.float32(value / 4096) for value in vertex.co) for vertex in mesh.vertices])
        self.assertEqual(detail["topology_in_meters"], topology)
        self.assertEqual(detail["shape_in_meters"]["source_bounds"], detail["shape_in_meters"]["inverse_conditioned_bounds"])
        self.assertEqual(detail["shape_in_meters"]["whole_body_surface_error_m"], 0.)
        self.assertEqual(detail["shape_in_meters"]["limits_m"], ART.LIMITS)
        self.assertFalse(detail["solver_units_restored"])

    def test_unit_conversion_fails_closed_when_short_edge_remains_or_indices_coordinates_change(self):
        for defect in ("too_short", "coordinates", "indices"):
            points, edges, corners = stored_tetrahedron()
            points[1] = (2e-8 if defect == "too_short" else 1.228781230931777e-7, 0., 0.)
            triangles = tetrahedron()[1]
            def corrupt(mesh):
                if defect == "coordinates": mesh.vertices[0].co = (.2, 0., 0.)
                elif defect == "indices": mesh.polygons[0].vertices = tuple(reversed(mesh.polygons[0].vertices))
            mesh = StoredMesh(points, triangles, edges, corners, corrupt=corrupt)
            high = [tuple(vertex.co) for vertex in mesh.vertices]
            report = {"operator_calls": 0, "solver_calls": 0}
            with self.subTest(defect=defect), patch("sys.stdout", io.StringIO()), self.assertRaises(RuntimeError):
                ART.condition_solver_copy(SimpleNamespace(data=mesh), high, triangles, ART.mesh_topology(high, triangles), report)
            self.assertFalse(report["conditioning"]["passed"])
            self.assertEqual(report["operator_calls"], 0)
            self.assertEqual(report["solver_calls"], 0)

    def test_solver_output_restored_once_to_world_meters_before_geometry_checks(self):
        points, edges, corners = stored_tetrahedron()
        mesh = StoredMesh([(x * 4096, y * 4096, z * 4096) for x, y, z in points], tetrahedron()[1], edges, corners)
        detail = {"policy": ART.CONDITIONING_POLICY, "solver_units_per_meter": 4096,
                  "passed": True, "solver_units_restored": False}
        report = {"conditioning": detail}
        ART.restore_solver_units(SimpleNamespace(data=mesh), report)
        self.assertEqual([tuple(vertex.co) for vertex in mesh.vertices], points)
        self.assertTrue(detail["solver_units_restored"])
        self.assertEqual(detail["solver_output_coordinate_units"], "world meters")
        with self.assertRaisesRegex(RuntimeError, "restoration requires"):
            ART.restore_solver_units(SimpleNamespace(data=mesh), report)

    def test_operator_calls_and_confirmed_solver_calls_not_conflated(self):
        for result in ({"FINISHED"}, {"CANCELLED"}):
            called = []
            bpy = SimpleNamespace(ops=SimpleNamespace(object=SimpleNamespace(
                quadriflow_remesh=lambda **settings: called.append(settings) or result)))
            report = {"operator_calls": 0, "solver_calls": 0, "solver_entry": "not_invoked"}
            if result == {"FINISHED"}:
                ART.invoke_quadriflow_once(bpy, ART.quadriflow_settings(14000), report)
            else:
                with self.assertRaisesRegex(RuntimeError, "did not finish"):
                    ART.invoke_quadriflow_once(bpy, ART.quadriflow_settings(14000), report)
            self.assertEqual(len(called), 1)
            self.assertEqual(report["operator_calls"], 1)
            self.assertEqual(report["solver_calls"], int(result == {"FINISHED"}))
            self.assertEqual(report["solver_entry"], "confirmed_finished" if result == {"FINISHED"} else "unknown_until_finished")

    def test_eye_frame_region_uses_registration_and_fails_nonfinite_axes(self):
        original = frames()
        checked = ART.validate_eye_frames(original)
        self.assertEqual(original, frames())
        self.assertTrue(ART.in_aperture_region((.2, -.06, .19), checked))
        self.assertFalse(ART.in_aperture_region((.2, -.07, .19), checked))
        self.assertFalse(ART.in_aperture_region((.2, 0., .21), checked))
        for defect in ("missing", "nonfinite", "scaled", "parallel"):
            frame = copy.deepcopy(original)
            if defect == "missing": del frame[-1.]
            elif defect == "nonfinite": frame[1.] = ((float("nan"), 0., 0.), *frame[1.][1:])
            elif defect == "scaled": frame[1.] = (frame[1.][0], (2., 0., 0.), *frame[1.][2:])
            else: frame[1.] = (frame[1.][0], (1., 0., 0.), (1., 0., 0.), frame[1.][3])
            with self.subTest(defect=defect), self.assertRaises(ValueError): ART.validate_eye_frames(frame)

    def test_barycentric_exact_corners_and_linear_interpolation(self):
        triangle = ((0., 0., 0.), (2., 0., 0.), (0., 2., 0.))
        self.assertEqual(ART.barycentric_weights(triangle[1], triangle), (0., 1., 0.))
        weights = ART.barycentric_weights((.5, 1., 0.), triangle)
        self.assertEqual(weights, (.25, .25, .5))
        colors = ((.1, .2, .3, 1.), (.9, .6, .2, 1.), (.3, .4, .1, 1.))
        result = ART.interpolate_diagnostic(colors, weights)
        for actual, expected in zip(result, (.4, .4, .175, 1.)): self.assertAlmostEqual(actual, expected)
        self.assertEqual(result[3], 1.)

    def test_barycentric_nearest_roundoff_does_not_allow_distant_or_off_plane_points(self):
        triangle = ((0., 0., 0.), (1., 0., 0.), (0., 1., 0.))
        self.assertEqual(ART.barycentric_weights((-1e-7, .5, 0.), triangle)[1], 0.)
        for point in ((-.01, .5, 0.), (.2, .2, .001), (float("inf"), 0., 0.)):
            with self.assertRaises(ValueError): ART.barycentric_weights(point, triangle)
        with self.assertRaises(ValueError): ART.barycentric_weights((0., 0., 0.), ((0., 0., 0.),) * 3)

    def test_masks_convex_weights_remain_exclusive_and_alpha_is_exact_one(self):
        masks = ((1., 0., 0., 1.), (0., 1., 0., 1.), (0., 0., 1., 1.))
        result = ART.interpolate_diagnostic(masks, (.2, .3, .5), masks=True)
        self.assertEqual(result, (.2, .3, .5, 1.))
        self.assertEqual(sum(result[:3]), 1.)
        for invalid in (((.8, .8, 0., 1.),) * 3, ((float("nan"), 0., 0., 1.),) * 3, ((0., 0., 0., 0.),) * 3):
            with self.assertRaises(ValueError): ART.interpolate_diagnostic(invalid, (.2, .3, .5), masks=True)
        for weights in ((-.2, .7, .5), (.2, .3, .4), (float("nan"), .5, .5)):
            with self.assertRaises(ValueError): ART.interpolate_diagnostic(masks, weights, masks=True)

    def test_closed_tetrahedron_reports_actual_orientation_volume_and_euler(self):
        points, triangles = tetrahedron()
        topology = ART.mesh_topology(points, triangles)
        ART.require_closed(topology)
        self.assertEqual(topology["boundary_edges"], 0)
        self.assertEqual(topology["nonmanifold_edges"], 0)
        self.assertEqual(topology["inconsistent_orientation_edges"], 0)
        self.assertEqual(topology["connected_components"], 1)
        self.assertEqual(topology["euler_characteristic"], 2)
        self.assertAlmostEqual(topology["signed_volume_m3"], 1 / 6)

    def test_topology_rejects_open_duplicate_inconsistent_loose_disconnected_meshes(self):
        for defect in ("open", "duplicate", "flipped", "loose", "disconnected"):
            points, triangles = tetrahedron()
            if defect == "open": triangles.pop()
            elif defect == "duplicate": triangles.append(triangles[0])
            elif defect == "flipped": triangles[0] = tuple(reversed(triangles[0]))
            elif defect == "loose": points.append((2., 2., 2.))
            else:
                points += [(x + 3., y, z) for x, y, z in list(points)]
                triangles += [tuple(index + 4 for index in triangle) for triangle in list(triangles)]
            topology = ART.mesh_topology(points, triangles)
            with self.subTest(defect=defect), self.assertRaises(RuntimeError): ART.require_closed(topology)
        with self.assertRaises(ValueError): ART.mesh_topology([(0., 0., 0.)], [(0, 0, 0)])

    def test_degenerate_output_not_waived_by_closed_counts(self):
        points, triangles = tetrahedron()
        topology = ART.mesh_topology(points, triangles)
        topology["degenerate_triangles"] = 1
        with self.assertRaises(RuntimeError): ART.require_closed(topology)

    def test_quad_statistics_retained_before_fixed_triangulation(self):
        mesh = SimpleNamespace(polygons=[SimpleNamespace(vertices=(0, 1, 2, 3)), SimpleNamespace(vertices=(3, 2, 4, 5))])
        stats = ART.quad_statistics(mesh)
        self.assertEqual(stats["quads"], 2)
        self.assertEqual(stats["triangulated_triangle_count"], 4)
        self.assertEqual(stats["pole_vertices"], 6)
        self.assertEqual(stats["vertex_valence_histogram"], {2: 4, 3: 2})

    def test_nearest_api_requires_real_hit_valid_index_and_finite_distance(self):
        tree = SimpleNamespace(find_nearest=lambda point: ((point[0], point[1], 0.), (0., 0., 1.), 0, .002))
        self.assertEqual(ART.nearest_hit(tree, (.2, 0., .002), 1), ((.2, 0., 0.), 0, .002))
        for hit in ((None, None, None, None), ((0., 0., 0.), None, 1, 0.),
                    ((0., 0., 0.), None, 0, float("nan")), ((0., 0., 0.), None, True, 0.)):
            with self.assertRaises(RuntimeError): ART.nearest_hit(SimpleNamespace(find_nearest=lambda _point: hit), (0., 0., 0.), 1)

    def test_samples_check_every_source_vertex_and_centroid_low_adds_edge_midpoints(self):
        points = [(0., 0., 0.), (1., 0., 0.), (0., 1., 0.)]
        self.assertEqual(len(list(ART.surface_samples(points, [(0, 1, 2)]))), 4)
        self.assertEqual(len(list(ART.surface_samples(points, [(0, 1, 2)], edge_midpoints=True))), 7)
        tree = SimpleNamespace(find_nearest=lambda point: ((point[0], point[1], point[2] - .001), (0., 0., 1.), 0, .001))
        report = ART.surface_error([(.2, 0., 0.)], tree, 1, ART.validate_eye_frames(frames()), bottom_z=0.)
        self.assertEqual(report["aperture_samples"], 1)
        self.assertEqual(report["bottom_samples"], 1)
        self.assertAlmostEqual(report["maximum_m"], .001)
        with self.assertRaises(RuntimeError): ART.surface_error([], tree, 1, frames())

    def test_agreed_exact_error_limits_are_inclusive_and_cannot_drift(self):
        self.assertEqual(ART.LIMITS, {"whole_body_surface_m": .006, "aperture_surface_m": .003, "aabb_m": .003, "bottom_contact_m": .002})
        bounds = {"min": [0., 0., 0.], "max": [1., 1., 1.]}
        report = ART.require_shape(bounds, bounds, metric(), metric())
        self.assertTrue(report["passed"])
        self.assertIn("sampled", report["surface_measurement"])

    def test_shape_gate_rejects_each_actual_limit_or_missing_region(self):
        for defect in ("body", "aperture", "bounds", "bottom", "bottom_z", "noaperture", "nobottom"):
            source_bounds = {"min": [0., 0., 0.], "max": [1., 1., 1.]}
            low_bounds = copy.deepcopy(source_bounds)
            forward, reverse = metric(), metric()
            if defect == "body": reverse["maximum_m"] = .006001
            elif defect == "aperture": reverse["aperture_maximum_m"] = .003001
            elif defect == "bounds": low_bounds["max"][0] += .003001
            elif defect == "bottom": forward["bottom_maximum_m"] = .002001
            elif defect == "bottom_z": low_bounds["min"][2] = .002001
            elif defect == "noaperture": forward["aperture_samples"] = 0
            else: forward["bottom_samples"] = 0
            with self.subTest(defect=defect):
                report = ART.require_shape(source_bounds, low_bounds, forward, reverse)
                self.assertFalse(report["passed"])
                self.assertTrue(report["failures"])

    def test_pinned_blender_version_and_body_only_api_guards_before_solver(self):
        modules = {"bpy": SimpleNamespace(app=SimpleNamespace(version=(5, 1, 0))), "bmesh": SimpleNamespace(),
                   "mathutils": SimpleNamespace(Vector=tuple), "mathutils.bvhtree": SimpleNamespace(BVHTree=object)}
        with patch.dict("sys.modules", modules), self.assertRaisesRegex(RuntimeError, "Blender 5.2.0"):
            ART.build_body(None, 14000, None, frames())
        modules["bpy"].app.version = (5, 2, 0)
        source = SimpleNamespace(type="MESH", name="PaddleWing+1")
        with patch.dict("sys.modules", modules), self.assertRaisesRegex(RuntimeError, "saved unmodified"):
            ART.build_body(source, 14000, None, frames())


if __name__ == "__main__":
    unittest.main()
