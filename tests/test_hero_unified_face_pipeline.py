"""Host-only R2 policy, literal eye paint and scratch shader wiring contracts.

No Blender, engine, source regeneration or source/runtime artifact writes.
Graph fixtures model Blender's shallow shared-group/image material copies.
"""
import ast
import copy
from contextlib import redirect_stdout
import importlib.util
import io
import json
import math
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools/art" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ADAPTER = load("unified_candidate_test", "build_hero_penguin_v12_candidate.py")
ATLAS = load("unified_atlas_test", "bake_hero_penguin_v12_atlas.py")


def binding_fixture():
    # Immutable registration values from the reviewed saved R2 contract.
    frames = {
        "-1.0": [[-.245, -.36081859627229274, 1.48],
                 [.8832897167470283, -.4688275549591284, 0.],
                 [-.44733128105570763, -.842789883735028, .29933248547886937],
                 [.14033531728689713, .26439730631181446, .9541488684356558]],
        "1.0": [[.245, -.36081859627229274, 1.48],
                [.8832897167470283, .4688275549591284, 0.],
                [.44733128105570763, -.842789883735028, .29933248547886937],
                [-.14033531728689713, .26439730631181446, .9541488684356558]],
    }
    return {"study_profile": ADAPTER.UNIFIED_PROFILE, "production_ready": False,
            "source_fidelity_approved": False,
            "record": {"study_profile": ADAPTER.UNIFIED_PROFILE,
                       "continuous_paint_input": {
                           "program_sha256": ADAPTER.UNIFIED_PROGRAM_SHA256,
                           "body_material": ADAPTER.UNIFIED_GROUP + "_FeatherMaterial",
                           "body_vertex_color_dependency": False,
                           "eye_frames": frames, "eye_radii": [.13, .10, .17]}}}


class Sockets(list):
    def __getitem__(self, key):
        return next(socket for socket in self if socket.name == key) if isinstance(key, str) else super().__getitem__(key)


class Node:
    def __init__(self, kind, inputs=(), outputs=()):
        self.type = kind
        self.inputs = Sockets(SimpleNamespace(name=name, node=self, links=[], default_value=0.) for name in inputs)
        self.outputs = Sockets(SimpleNamespace(name=name, node=self, links=[], default_value=0.) for name in outputs)
        self.is_active_output = True
        self.node_tree = None
        self.object = None
        self.name = kind


class Nodes(list):
    def new(self, kind):
        if kind == "ShaderNodeVectorMath":
            node = Node("VECT_MATH", ("Vector", "Vector_001", "Vector_002", "Scale"), ("Vector", "Value"))
        elif kind == "ShaderNodeEmission":
            node = Node("EMISSION", ("Color", "Strength"), ("Emission",))
        else:
            raise AssertionError("unexpected scratch node: " + kind)
        self.append(node)
        return node


class Links(list):
    def new(self, source, target):
        edge = SimpleNamespace(from_socket=source, from_node=source.node, to_socket=target, to_node=target.node)
        self.append(edge)
        source.links.append(edge)
        target.links.append(edge)
        return edge

    def remove(self, edge):
        super().remove(edge)
        edge.from_socket.links.remove(edge)
        edge.to_socket.links.remove(edge)


class Graph:
    def __init__(self, nodes=()):
        self.nodes = Nodes(nodes)
        self.links = Links()

    def shallow_group_copy(self):
        result = Graph()
        sockets = {}
        for original in self.nodes:
            node = copy.copy(original)
            node.inputs, node.outputs = Sockets(), Sockets()
            for key in ("inputs", "outputs"):
                for old in getattr(original, key):
                    socket = SimpleNamespace(name=old.name, node=node, links=[], default_value=copy.copy(old.default_value))
                    getattr(node, key).append(socket)
                    sockets[id(old)] = socket
            # node_tree and images deliberately stay shared, as in Blender.
            result.nodes.append(node)
        for edge in self.links:
            result.links.new(sockets[id(edge.from_socket)], sockets[id(edge.to_socket)])
        return result


class Material(dict):
    def __init__(self, name, graph):
        super().__init__()
        self.name = name
        self.use_nodes = True
        self.node_tree = graph
        self.diffuse_color = (.9, .2, .1, 1.)

    def copy(self):
        material = Material(self.name.split(".", 1)[0] + ".001", self.node_tree.shallow_group_copy())
        material.update(self)
        return material


class Group(dict):
    def __init__(self, name, graph):
        super().__init__()
        self.name, self.nodes, self.links = name, graph.nodes, graph.links


class Matrix(list):
    @staticmethod
    def Diagonal(values):
        return Matrix([[value if row == column else 0. for column in range(4)] for row, value in enumerate(values)])

    def identity(self):
        self[:] = Matrix.Diagonal((1., 1., 1., 1.))


class Attributes(dict):
    def __init__(self, *args, count=3, **kwargs):
        super().__init__(*args, **kwargs)
        self.count = count
        self.created = []

    def new(self, name, type, domain):
        self.created.append(name)
        result = SimpleNamespace(data_type=type, domain=domain,
                                 data=[SimpleNamespace(color=(0., 0., 0., 0.)) for _ in range(self.count)])
        self[name] = result
        return result


class Mesh:
    def __init__(self, material, colors):
        self.materials = [material]
        self.vertices = [SimpleNamespace(index=index, co=point) for index, point in enumerate(
            ((.23, -.40, 1.60), (.24, -.38, 1.50), (.25, -.39, 1.45)))]
        self.color_attributes = Attributes(PreviewColor=SimpleNamespace(domain="POINT", data_type="FLOAT_COLOR",
            data=[SimpleNamespace(color=value) for value in colors]))

    def copy(self):
        result = copy.copy(self)
        result.materials = list(self.materials)
        result.vertices = copy.deepcopy(self.vertices)
        result.color_attributes = copy.deepcopy(self.color_attributes)
        return result

    def transform(self, matrix):
        for vertex in self.vertices:
            point = (*vertex.co, 1.)
            vertex.co = tuple(sum(value * coordinate for value, coordinate in zip(row, point)) for row in matrix[:3])

    def flip_normals(self):
        self.flipped = True

    def update(self):
        pass


class Source(dict):
    def __init__(self, name, material, colors):
        super().__init__()
        self.name = name
        self.data = Mesh(material, colors)
        self.matrix_world = Matrix.Diagonal((1., 1., 1., 1.))

    def copy(self):
        result = copy.copy(self)
        result.matrix_world = copy.deepcopy(self.matrix_world)
        return result


def eye_fixture():
    vertex = Node("VERTEX_COLOR", outputs=("Color", "Alpha"))
    vertex.layer_name = "PreviewColor"
    bsdf = Node("BSDF_PRINCIPLED", ("Base Color",), ("BSDF",))
    output = Node("OUTPUT_MATERIAL", ("Surface",))
    graph = Graph((vertex, bsdf, output))
    graph.links.new(vertex.outputs["Color"], bsdf.inputs["Base Color"])
    graph.links.new(bsdf.outputs[0], output.inputs["Surface"])
    colors = [(0.003, .006, .010, 1.), (.086, .217, .297, 1.), (.97, .965, .92, 1.)]
    source = Source("EmbeddedSclera+1", Material("JuvenileSeatedEyeSurface", graph), colors)
    source["eye_surface_contract"] = ADAPTER.UNIFIED_EYE_CONTRACT
    return source, colors


def body_fixture():
    pigment = Node("COMBINE_COLOR", ("Red", "Green", "Blue"), ("Color",))
    pigment.mode = "RGB"
    masks = Node("COMBINE_COLOR", ("Red", "Green", "Blue"), ("Color",))
    masks.mode = "RGB"
    output = Node("GROUP_OUTPUT", ("Color", "SemanticMasks", "FeatherRegion", "Hood"))
    output.inputs["FeatherRegion"].default_value = 1.
    graph = Graph((pigment, masks, output))
    graph.links.new(pigment.outputs[0], output.inputs["Color"])
    graph.links.new(masks.outputs[0], output.inputs["SemanticMasks"])
    group = Group(ADAPTER.UNIFIED_GROUP, graph)
    group["semantic_mask_contract"] = ATLAS.CONTINUOUS_MASK_CONTRACT
    instance = Node("GROUP", ("Position",), ("Color", "SemanticMasks", "FeatherRegion", "Hood"))
    instance.node_tree = group
    coordinates = Node("TEX_COORD", outputs=("Object", "Generated"))
    diagnostic = Node("VERTEX_COLOR", outputs=("Color",))
    diagnostic.layer_name = "PreviewColor"
    bsdf = Node("BSDF_PRINCIPLED", ("Base Color",), ("BSDF",))
    surface = Node("OUTPUT_MATERIAL", ("Surface",))
    image = Node("TEX_IMAGE", outputs=("Color",))
    image.image = object()
    material_graph = Graph((instance, coordinates, diagnostic, bsdf, surface, image))
    material_graph.links.new(coordinates.outputs["Object"], instance.inputs["Position"])
    material_graph.links.new(instance.outputs["Color"], bsdf.inputs["Base Color"])
    material_graph.links.new(bsdf.outputs[0], surface.inputs["Surface"])
    material = Material(ADAPTER.UNIFIED_GROUP + "_FeatherMaterial", material_graph)
    material["z13_continuous_body_pigment"] = ADAPTER.UNIFIED_PROFILE
    source = Source("HeroBodyV12SmoothField", material, [(.01, .02, .03, 1.)] * 3)
    source["source_pigment_authority"] = ADAPTER.UNIFIED_GROUP + ": Color and SemanticMasks shading outputs"
    source["source_mask_contract"] = "feather-palette-weights-v1"
    source.data.color_attributes["SourceSemanticMasks"] = SimpleNamespace(domain="POINT", data_type="FLOAT_COLOR",
        data=[SimpleNamespace(color=(.20, .30, .10, 1.)) for _ in range(3)])
    return source, group


def graph_edges(graph):
    return [(id(edge.from_socket), id(edge.to_socket)) for edge in graph.links]


class UnifiedPolicyTests(unittest.TestCase):
    def test_versioned_budget_uses_whole_integrated_eye(self):
        policy = ADAPTER.UNIFIED_GEOMETRY_POLICY
        self.assertEqual(ADAPTER.component_target("HeroBodyV12SmoothField", 0, policy), 14000)
        self.assertEqual(ADAPTER.component_target("HeroBodyV12SmoothField", 1, policy), 6440)
        self.assertEqual(ADAPTER.component_target("EmbeddedSclera+1", 0, policy), 1100)
        self.assertEqual(ADAPTER.component_target("EmbeddedSclera-1", 1, policy), 506)
        self.assertEqual(ADAPTER.component_target("EmbeddedSclera+1", 0, "source-cover-v2"), 700)
        self.assertEqual(ADAPTER.LOD_RANGES, ((20000, 25000), (8000, 12000)))

    def test_binding_never_aliases_or_executes_mutable_design(self):
        binding = binding_fixture()
        original = copy.deepcopy(binding)
        frames = ADAPTER.unified_eye_frames(binding)
        frames[-1.] = tuple((0., 0., 0.) for _ in range(4))
        self.assertEqual(binding, original)
        for module in (ADAPTER, ATLAS):
            tree = ast.parse(Path(module.__file__).read_text())
            imports = [node.module or "" for node in ast.walk(tree) if isinstance(node, ast.ImportFrom)]
            imports += [alias.name for node in ast.walk(tree) if isinstance(node, ast.Import) for alias in node.names]
            self.assertFalse(any(name.startswith(("hero_penguin_face_sculpt", "hero_penguin_v12_face_z")) for name in imports))

    def test_binding_rejects_wrong_profile_program_or_contract(self):
        for defect in ("profile", "record", "program", "material", "vertex", "radii", "approval", "fidelity"):
            binding = binding_fixture()
            paint = binding["record"]["continuous_paint_input"]
            if defect == "profile": binding["study_profile"] = "juvenile-socket-z06"
            elif defect == "record": binding["record"]["study_profile"] = "other"
            elif defect == "program": paint["program_sha256"] = "a" * 64
            elif defect == "material": paint["body_material"] = "different"
            elif defect == "vertex": paint["body_vertex_color_dependency"] = True
            elif defect == "radii": paint["eye_radii"][1] = .11
            elif defect == "approval": binding["production_ready"] = True
            else: binding["source_fidelity_approved"] = True
            with self.subTest(defect=defect), self.assertRaises(RuntimeError): ADAPTER.unified_eye_frames(binding)

    def test_binding_rejects_missing_nonfinite_nonorthogonal_or_remote_frames(self):
        for defect in ("missing", "nan", "bool", "short", "scaled", "parallel", "remote"):
            binding = binding_fixture()
            frames = binding["record"]["continuous_paint_input"]["eye_frames"]
            if defect == "missing": del frames["-1.0"]
            elif defect == "nan": frames["1.0"][0][0] = float("nan")
            elif defect == "bool": frames["1.0"][0][0] = True
            elif defect == "short": frames["1.0"].pop()
            elif defect == "scaled": frames["1.0"][1][0] *= 2
            elif defect == "parallel": frames["1.0"][2] = list(frames["1.0"][1])
            else: frames["1.0"][0][2] = 1.648
            with self.subTest(defect=defect), self.assertRaises(RuntimeError): ADAPTER.unified_eye_frames(binding)

    def test_new_source_cannot_use_legacy_cover_recipe(self):
        binding = binding_fixture()
        for policy in ("legacy", "source-cover-v1", "source-cover-v2"):
            with self.subTest(policy=policy), self.assertRaisesRegex(RuntimeError, "legacy X/Y"):
                ADAPTER.validate_geometry_binding(policy, binding)
        for binding in (None, {}, {"study_profile": "juvenile-socket-z06"}):
            with self.assertRaises(RuntimeError): ADAPTER.validate_geometry_binding(ADAPTER.UNIFIED_GEOMETRY_POLICY, binding)

    def point(self, frame, x, depth, z):
        origin, across, normal, up = frame
        return tuple(origin[i] + x * across[i] + depth * normal[i] + z * up[i] for i in range(3))

    def test_narrow_aperture_edge_pins_use_actual_bilateral_frames(self):
        frames = ADAPTER.unified_eye_frames(binding_fixture())
        for side, frame in frames.items():
            x = -side * ADAPTER.UNIFIED_APERTURE["nasal"]
            vertical = ADAPTER.UNIFIED_APERTURE["upper"] * math.sqrt(1. - .018 ** 2)
            z = vertical + .006 - .040 * side * x
            self.assertAlmostEqual(ADAPTER.unified_aperture_distance(x, z, side), 0.)
            point = self.point(frame, x, -.02, z)
            self.assertTrue(ADAPTER.unified_aperture_source_pin(point, frames))
            self.assertFalse(ADAPTER.orbital_source_pin(point, near_lod=True))
            self.assertFalse(ADAPTER.unified_aperture_source_pin(self.point(frame, x, -.08, z), frames))
            self.assertFalse(ADAPTER.unified_aperture_source_pin(self.point(frame, x, -.02, z + .02), frames))
            self.assertFalse(ADAPTER.unified_aperture_source_pin(self.point(frame, 0., 0., 0.), frames))
        self.assertFalse(ADAPTER.unified_aperture_source_pin((0., .40, 1.60), frames))
        with self.assertRaises(ValueError): ADAPTER.unified_aperture_source_pin((0., 0., float("inf")), frames)

    def test_new_scope_explicitly_not_whole_cover_or_approval(self):
        scope = ADAPTER.unified_source_scope(binding_fixture())
        self.assertEqual(scope["geometry_policy"], ADAPTER.UNIFIED_GEOMETRY_POLICY)
        self.assertEqual(scope["aperture_field_band_m"], .002)
        for key in ("whole_source_cover_proven", "production_ready", "source_fidelity_approved"):
            self.assertIs(scope[key], False)
        self.assertNotIn("source_cover_x_band", scope)

    def test_replay_policy_requires_same_unified_binding(self):
        audit = {"geometry_policy": ADAPTER.UNIFIED_GEOMETRY_POLICY, "source_study_binding": binding_fixture()}
        self.assertEqual(ATLAS.candidate_geometry_policy(audit), ADAPTER.UNIFIED_GEOMETRY_POLICY)
        for invalid in ({"geometry_policy": ADAPTER.UNIFIED_GEOMETRY_POLICY},
                        {"geometry_policy": "source-cover-v2", "source_study_binding": binding_fixture()},
                        {"source_study_binding": binding_fixture()}):
            with self.assertRaises(RuntimeError): ATLAS.candidate_geometry_policy(invalid)

    def replay_fixture(self):
        vertices = [SimpleNamespace(index=i, co=point) for i, point in enumerate(((0., 0., 0.), (1., 0., 0.), (0., 1., 0.)))]
        mesh = SimpleNamespace(data=SimpleNamespace(vertices=vertices, polygons=[SimpleNamespace(vertices=(0, 1, 2))]))
        source = SimpleNamespace(name="HeroBodyTest")
        reduced = SimpleNamespace(data=SimpleNamespace(vertices=vertices))
        audit = {"geometry_policy": ADAPTER.UNIFIED_GEOMETRY_POLICY, "source_study_binding": binding_fixture(),
                 "components": [{"lod": 0, "source": source.name, "target": 14000, "after": 1}],
                 "lods": [{"sole_fit": {"constant_foot_toe_offset_z_m": 0.}}]}
        reducer = Mock(return_value=(reduced, 3, 1))
        adapter = SimpleNamespace(reduce_component=reducer, component_spec=ADAPTER.component_spec,
            component_target=ADAPTER.component_target, canonical_position=tuple,
            validate_geometry_binding=ADAPTER.validate_geometry_binding)
        return mesh, source, audit, reducer, adapter

    def test_replay_forwards_exact_recorded_binding(self):
        mesh, source, audit, reducer, adapter = self.replay_fixture()
        bpy = SimpleNamespace(data=SimpleNamespace(objects=SimpleNamespace(remove=Mock())))
        with patch.object(ATLAS, "adapter", adapter, create=True), patch.object(ATLAS, "bpy", bpy, create=True):
            self.assertEqual(ATLAS.recover_components(mesh, [source], 0, audit, "scratch"), ([0, 0, 0], [0]))
        reducer.assert_called_once_with(source, 14000, "scratch", geometry_policy=ADAPTER.UNIFIED_GEOMETRY_POLICY,
                                        study_binding=audit["source_study_binding"])
        self.assertIs(reducer.call_args.kwargs["study_binding"], audit["source_study_binding"])

    def test_replay_rejects_malformed_binding_and_changed_target_before_reducer(self):
        for defect in ("frames", "target"):
            mesh, source, audit, reducer, adapter = self.replay_fixture()
            if defect == "frames": audit["source_study_binding"]["record"]["continuous_paint_input"]["eye_frames"] = {}
            else: audit["components"][0]["target"] = 15000
            with patch.object(ATLAS, "adapter", adapter, create=True), self.assertRaises(RuntimeError):
                ATLAS.recover_components(mesh, [source], 0, audit, "scratch")
            reducer.assert_not_called()


class UnifiedRetopologyBakeTests(unittest.TestCase):
    def audit_fixture(self):
        return {"geometry_policy": "unified-retopo-r2-v1", "source_study_binding": binding_fixture(),
                "retopology_helper": {"path": "/synthetic/frozen_retopology.py", "sha256": "a" * 64}}

    def test_named_policy_requires_same_unified_binding_without_legacy_alias(self):
        audit = self.audit_fixture()
        self.assertEqual(ATLAS.candidate_geometry_policy(audit), "unified-retopo-r2-v1")
        self.assertNotEqual(ATLAS.UNIFIED_RETOPO_POLICY, ATLAS.UNIFIED_GEOMETRY_POLICY)
        for changed in ({"geometry_policy": ATLAS.UNIFIED_RETOPO_POLICY},
                        dict(audit, source_study_binding=None),
                        dict(audit, source_study_binding={"study_profile": "juvenile-socket-z06"}),
                        dict(audit, geometry_policy="unified-retopo-r2-v2"),
                        dict(audit, geometry_policy="legacy")):
            with self.subTest(audit=changed), self.assertRaises(RuntimeError):
                ATLAS.candidate_geometry_policy(changed)
        self.assertEqual(ATLAS.candidate_geometry_policy({}), "legacy")

    def recovery_fixture(self):
        events = []
        mesh, sources, audit = object(), [object(), object()], self.audit_fixture()
        recovered = ([0, 0, 1, 1], [0, 1])
        adapter = SimpleNamespace(
            validate_geometry_binding=Mock(side_effect=lambda *_: events.append("binding")),
            verify_retopology_helper=Mock(side_effect=lambda _: events.append("helper") or audit["retopology_helper"]),
            recover_stored_components=Mock(side_effect=lambda *_: events.append("stored") or recovered),
            reduce_component=Mock(side_effect=AssertionError("retopology solver replay forbidden")))
        return mesh, sources, audit, recovered, adapter, events

    def test_recovery_verifies_binding_helper_then_returns_stored_membership_no_solver(self):
        mesh, sources, audit, recovered, adapter, events = self.recovery_fixture()
        with patch.object(ATLAS, "adapter", adapter, create=True):
            self.assertIs(ATLAS.recover_components(mesh, sources, 1, audit, "unused scratch"), recovered)
        self.assertEqual(events, ["binding", "helper", "stored"])
        adapter.validate_geometry_binding.assert_called_once_with(ATLAS.UNIFIED_RETOPO_POLICY, audit["source_study_binding"])
        adapter.verify_retopology_helper.assert_called_once_with(audit)
        adapter.recover_stored_components.assert_called_once_with(mesh, sources, 1, audit)
        adapter.reduce_component.assert_not_called()

    def test_binding_or_helper_rejection_precedes_stored_recovery(self):
        for stage in ("validate_geometry_binding", "verify_retopology_helper"):
            mesh, sources, audit, _recovered, adapter, _events = self.recovery_fixture()
            getattr(adapter, stage).side_effect = RuntimeError("frozen retopology contract changed")
            with patch.object(ATLAS, "adapter", adapter, create=True), \
                    self.subTest(stage=stage), self.assertRaisesRegex(RuntimeError, "contract changed"):
                ATLAS.recover_components(mesh, sources, 0, audit, "unused scratch")
            adapter.recover_stored_components.assert_not_called()
            adapter.reduce_component.assert_not_called()
            if stage == "validate_geometry_binding":
                adapter.verify_retopology_helper.assert_not_called()

    def test_geometry_or_membership_rejection_never_falls_back_to_solver(self):
        mesh, sources, audit, _recovered, adapter, events = self.recovery_fixture()
        adapter.recover_stored_components.side_effect = RuntimeError("saved ordered geometry digest mismatch")
        with patch.object(ATLAS, "adapter", adapter, create=True), \
                self.assertRaisesRegex(RuntimeError, "ordered geometry digest"):
            ATLAS.recover_components(mesh, sources, 0, audit, "unused scratch")
        self.assertEqual(events, ["binding", "helper"])
        adapter.recover_stored_components.assert_called_once_with(mesh, sources, 0, audit)
        adapter.reduce_component.assert_not_called()

    def test_main_freezes_helper_in_inputs_report_binding_and_explicit_source_scope(self):
        source = Path(ATLAS.__file__).read_text()
        tree = ast.parse(source)
        main = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "main")
        code = ast.unparse(main)
        self.assertLess(code.index("adapter.verify_retopology_helper(prior)"), code.index("recover_components("))
        self.assertIn("inputs[retopology_helper['path']] = retopology_helper['sha256']", code)
        self.assertIn("report['retopology_helper'] = dict(retopology_helper)", code)
        self.assertIn("binding['retopology_helper'] = dict(retopology_helper)", code)
        self.assertIn("binding['geometry_policy'] = geometry_policy", code)
        self.assertIn("adapter.unified_source_scope(study_binding, geometry_policy)", code)
        self.assertIn("sha(Path(path)) != digest for path, digest in inputs.items()", code)
        self.assertNotIn("quadriflow", code.lower())


class UnifiedPinCleanupTests(unittest.TestCase):
    def test_impossible_exact_source_cage_rejects_before_reduction(self):
        with self.assertRaisesRegex(RuntimeError, "81814.*whole-character maximum 25000.*retopology required"):
            ADAPTER.require_feasible_source_pins("HeroBodyV12SmoothField", ADAPTER.UNIFIED_GEOMETRY_POLICY, 81814)
        self.assertEqual(ADAPTER.LOD_RANGES, ((20000, 25000), (8000, 12000)))

    def test_necessary_pin_budget_check_does_not_change_legacy_or_grant_lod_acceptance(self):
        for policy in ("legacy", "source-cover-v1", "source-cover-v2"):
            self.assertIsNone(ADAPTER.require_feasible_source_pins("HeroBody", policy, 81814))
        for count in (0, 12000, 25000):
            self.assertIsNone(ADAPTER.require_feasible_source_pins("HeroBody", ADAPTER.UNIFIED_GEOMETRY_POLICY, count))
        for count in (-1, True, 25000., "25000"):
            with self.assertRaises(ValueError):
                ADAPTER.require_feasible_source_pins("HeroBody", ADAPTER.UNIFIED_GEOMETRY_POLICY, count)
        with self.assertRaises(ValueError):
            ADAPTER.require_feasible_source_pins("HeroBody", "unknown", 0)

    def triangle_fixture(self):
        points = ((.2, -.4, 1.5), (.21, -.4, 1.5), (.2, -.41, 1.5))
        return points, {ADAPTER.oriented_face_key(points)}

    def test_exact_state_accepts_cyclic_face_rotation_not_vertex_repair(self):
        points, faces = self.triangle_fixture()
        state = ADAPTER.pinned_geometry_state(points, [points[1:] + points[:1]], points, faces)
        self.assertTrue(state["exact"])
        self.assertEqual(state["actual_vertices"], 3)
        self.assertEqual(state["actual_triangles"], 1)
        self.assertEqual(state["missing_pinned_vertices"], 0)
        self.assertEqual(state["missing_pinned_triangles"], 0)

    def test_small_float_drift_or_reversed_face_still_fails_exact_gate(self):
        points, faces = self.triangle_fixture()
        moved = [(points[0][0] + 1e-9, *points[0][1:]), *points[1:]]
        drift = ADAPTER.pinned_geometry_state(moved, [moved], points, faces)
        self.assertFalse(drift["exact"])
        self.assertEqual(drift["missing_pinned_vertices"], 1)
        self.assertEqual(drift["missing_pinned_triangles"], 1)
        reversed_state = ADAPTER.pinned_geometry_state(points, [tuple(reversed(points))], points, faces)
        self.assertEqual(reversed_state["missing_pinned_vertices"], 0)
        self.assertEqual(reversed_state["missing_pinned_triangles"], 1)

    def test_phase_failure_names_component_phase_counts_and_coordinates(self):
        points, faces = self.triangle_fixture()
        stream = io.StringIO()
        with redirect_stdout(stream), self.assertRaises(RuntimeError) as caught:
            ADAPTER.record_pin_phase("HeroBodyV12SmoothField", ADAPTER.UNIFIED_GEOMETRY_POLICY, 14000,
                "post-decimation-before-cleanup", points[:2], [], points, faces)
        line = stream.getvalue().strip()
        self.assertTrue(line.startswith("[v12-candidate-pin] "))
        state = json.loads(line.split(" ", 1)[1])
        self.assertEqual(state["component"], "HeroBodyV12SmoothField")
        self.assertEqual(state["phase"], "post-decimation-before-cleanup")
        self.assertEqual(state["target_triangles"], 14000)
        self.assertEqual(state["missing_pinned_vertices"], 1)
        self.assertEqual(state["missing_pinned_triangles"], 1)
        self.assertEqual(state["first_missing_source_positions"], [list(points[2])])
        self.assertIn("post-decimation-before-cleanup", str(caught.exception))
        self.assertIn("HeroBodyV12SmoothField", str(caught.exception))

    def test_phase_success_produces_unapproved_geometry_evidence_only(self):
        points, faces = self.triangle_fixture()
        with redirect_stdout(io.StringIO()):
            state = ADAPTER.record_pin_phase("HeroBodyV12SmoothField", ADAPTER.UNIFIED_GEOMETRY_POLICY,
                14000, "post-pin-aware-weld", points, [points], points, faces)
        self.assertTrue(state["exact"])
        self.assertNotIn("production_ready", state)
        self.assertNotIn("source_fidelity_approved", state)

    def cleanup_fixture(self):
        protected = SimpleNamespace(co=(.2, -.4, 1.5))
        first, second, third = [SimpleNamespace(co=point) for point in ((.21, -.4, 1.5), (.22, -.4, 1.5), (.23, -.4, 1.5))]
        boundary_face = SimpleNamespace(verts=(protected, first, second))
        remote_face = SimpleNamespace(verts=(first, second, third))
        touches_pin = SimpleNamespace(verts=(protected, first), link_faces=[boundary_face])
        opposite_pin_face = SimpleNamespace(verts=(first, second), link_faces=[boundary_face, remote_face])
        unrelated = SimpleNamespace(verts=(second, third), link_faces=[remote_face])
        wire = SimpleNamespace(verts=(first, third), link_faces=[])
        edit = SimpleNamespace(verts=[protected, first, second, third], edges=[touches_pin, opposite_pin_face, unrelated, wire])
        return edit, protected, touches_pin, opposite_pin_face, unrelated, wire

    def test_cleanup_keeps_pins_and_their_face_neighborhood_out_of_mutation_lists(self):
        edit, protected, touches_pin, opposite_pin_face, unrelated, wire = self.cleanup_fixture()
        vertices, edges = ADAPTER.unified_cleanup_inputs(edit, [protected.co])
        self.assertNotIn(protected, vertices)
        self.assertEqual(vertices, edit.verts[1:])
        self.assertNotIn(touches_pin, edges)
        self.assertNotIn(opposite_pin_face, edges)
        self.assertEqual(edges, [unrelated, wire])
        # Helper chooses inputs only: no source coordinate/face mutation.
        self.assertEqual(protected.co, (.2, -.4, 1.5))
        self.assertEqual(len(edit.edges), 4)

    def test_cleanup_protects_every_exact_pin_not_only_initial_aperture_seeds(self):
        edit, protected, *_rest = self.cleanup_fixture()
        positions = [vertex.co for vertex in edit.verts[:3]]
        vertices, edges = ADAPTER.unified_cleanup_inputs(edit, positions)
        self.assertEqual(vertices, [edit.verts[3]])
        self.assertEqual(edges, [])
        self.assertEqual(len(positions), 3)

    def test_empty_protection_retains_original_all_vertex_edge_inputs(self):
        edit, *_rest = self.cleanup_fixture()
        vertices, edges = ADAPTER.unified_cleanup_inputs(edit, [])
        self.assertEqual(vertices, edit.verts)
        self.assertEqual(edges, edit.edges)

    def test_nearby_coordinate_is_not_silently_promoted_to_exact_pin(self):
        edit, protected, *_rest = self.cleanup_fixture()
        nearby = SimpleNamespace(co=(protected.co[0] + 1e-9, *protected.co[1:]))
        edit.verts.append(nearby)
        vertices, _edges = ADAPTER.unified_cleanup_inputs(edit, [protected.co])
        self.assertNotIn(protected, vertices)
        self.assertIn(nearby, vertices)


class UnifiedEyeTests(unittest.TestCase):
    def test_single_eye_literal_linear_pigment_preserved(self):
        source, colors = eye_fixture()
        self.assertEqual(ADAPTER.source_colors(source), colors)
        source.name = "EmbeddedSclera-1.001"
        self.assertEqual(ADAPTER.source_colors(source), colors)
        self.assertNotEqual(ADAPTER.paint_summary(colors)["linear_float_sha256"],
                            ADAPTER.paint_summary([source.data.materials[0].diffuse_color] * 3)["linear_float_sha256"])

    def test_integrated_eye_malformed_contract_never_falls_back(self):
        for defect in ("contract", "component", "missing", "domain", "storage", "count", "material", "slot",
                       "layer", "socket", "output", "indirect", "nan", "range", "alpha"):
            source, _colors = eye_fixture()
            material = source.data.materials[0]
            vertex, bsdf, output = material.node_tree.nodes
            pigment = source.data.color_attributes["PreviewColor"]
            if defect == "contract": del source["eye_surface_contract"]
            elif defect == "component": source.name = "Iris+1"
            elif defect == "missing": source.data.color_attributes.clear()
            elif defect == "domain": pigment.domain = "CORNER"
            elif defect == "storage": pigment.data_type = "BYTE_COLOR"
            elif defect == "count": pigment.data.pop()
            elif defect == "material": material.name = "WarmSclera"
            elif defect == "slot": source.data.materials.append(material)
            elif defect == "layer": vertex.layer_name = "UnrelatedMasks"
            elif defect == "socket": bsdf.inputs["Base Color"].links[0].from_socket.name = "Alpha"
            elif defect == "output": output.is_active_output = False
            elif defect == "indirect": vertex.type = "MIX_RGB"
            elif defect == "nan": pigment.data[0].color = (float("nan"), 0., 0., 1.)
            elif defect == "range": pigment.data[0].color = (2., 0., 0., 1.)
            else: pigment.data[0].color = (0., 0., 0., 0.)
            with self.subTest(defect=defect), self.assertRaises(RuntimeError): ADAPTER.source_colors(source)


class UnifiedShaderTests(unittest.TestCase):
    def test_recognizes_exact_continuous_source_without_touching_it(self):
        source, group = body_fixture()
        material = source.data.materials[0]
        before = graph_edges(material.node_tree), graph_edges(group)
        recognized, instance = ATLAS.continuous_body_group(source)
        self.assertIs(recognized, material)
        self.assertIs(instance.node_tree, group)
        self.assertEqual(before, (graph_edges(material.node_tree), graph_edges(group)))

    def test_malformed_continuous_contract_fails_closed(self):
        for defect in ("body", "marker", "authority", "material", "maskcontract", "mode", "outputs", "feather",
                       "linkedfeather", "position", "foreignobject", "vertexdependency"):
            source, group = body_fixture()
            material = source.data.materials[0]
            instance, coordinates, diagnostic, bsdf, _output, _image = material.node_tree.nodes
            if defect == "body": source.name = "PaddleWing+1"
            elif defect == "marker": material["z13_continuous_body_pigment"] = "different"
            elif defect == "authority": source["source_pigment_authority"] = "diagnostic-only"
            elif defect == "material": material.name = "Unrecognized"
            elif defect == "maskcontract": group["semantic_mask_contract"] = "estimated"
            elif defect == "mode": group.nodes[1].mode = "HSV"
            elif defect == "outputs": group.nodes[-1].is_active_output = False
            elif defect == "feather": group.nodes[-1].inputs["FeatherRegion"].default_value = 0.
            elif defect == "linkedfeather": group.links.new(group.nodes[0].outputs[0], group.nodes[-1].inputs["FeatherRegion"])
            elif defect == "position": instance.inputs["Position"].links[0].from_socket.name = "Generated"
            elif defect == "foreignobject": coordinates.object = object()
            else: material.node_tree.links.new(diagnostic.outputs[0], bsdf.inputs["Base Color"])
            with self.subTest(defect=defect), self.assertRaises(RuntimeError): ATLAS.continuous_body_group(source)

    def test_diagnostics_validated_but_not_promoted_or_copied(self):
        source, _group = body_fixture()
        original = copy.deepcopy([item.color for item in source.data.color_attributes["SourceSemanticMasks"].data])
        with patch.object(ATLAS, "adapter", ADAPTER, create=True):
            self.assertIsNone(ATLAS.source_semantics(source, binding_fixture()))
        self.assertEqual(source.data.color_attributes.created, [])
        self.assertNotIn("AuthoritativeAtlasMasks", source.data.color_attributes)
        self.assertEqual(original, [item.color for item in source.data.color_attributes["SourceSemanticMasks"].data])

    def test_continuous_semantics_requires_binding_and_valid_diagnostics(self):
        for defect in ("binding", "diagnostics"):
            source, _group = body_fixture()
            binding = binding_fixture()
            if defect == "binding": binding = None
            else: source.data.color_attributes["SourceSemanticMasks"].data[0].color = (.8, .8, 0., 1.)
            with patch.object(ATLAS, "adapter", ADAPTER, create=True), self.assertRaises(RuntimeError):
                ATLAS.source_semantics(source, binding)
            self.assertNotIn("AuthoritativeAtlasMasks", source.data.color_attributes)

    def test_canonical_scratch_copy_reflects_object_input_only_once(self):
        source, group = body_fixture()
        original = source.data.materials[0]
        before = graph_edges(original.node_tree), graph_edges(group)
        material = ATLAS.canonical_continuous_material(source)
        self.assertIsNot(material, original)
        _material, instance = ATLAS.continuous_body_group(source, material, reflected=True)
        self.assertIs(instance.node_tree, group)
        correction = instance.inputs["Position"].links[0].from_node
        self.assertEqual(correction.operation, "MULTIPLY")
        self.assertEqual(tuple(correction.inputs[1].default_value), (1., -1., 1.))
        self.assertEqual(correction.inputs[0].links[0].from_socket.name, "Object")
        self.assertEqual(before, (graph_edges(original.node_tree), graph_edges(group)))
        self.assertIs(original.node_tree.nodes[-1].image, material.node_tree.nodes[-2].image)
        # Canonical geometric reflection followed by shader correction yields
        # exactly the saved source coordinate, not its opposite side.
        point = (.245, -.36, 1.48)
        reflected = ADAPTER.canonical_position(point)
        self.assertEqual(tuple(a * b for a, b in zip(reflected, correction.inputs[1].default_value)), point)

    def test_nonidentity_source_shader_transform_is_not_assumed(self):
        source, _group = body_fixture()
        source.matrix_world[0][3] = .02
        with self.assertRaisesRegex(RuntimeError, "identity transform"): ATLAS.canonical_continuous_material(source)

    def test_canonical_high_reflects_geometry_and_only_clones_new_body_material(self):
        source, group = body_fixture()
        original_material = source.data.materials[0]
        points = [vertex.co for vertex in source.data.vertices]
        collection = SimpleNamespace(objects=SimpleNamespace(link=Mock()))
        with patch.object(ATLAS, "adapter", ADAPTER, create=True), patch.object(ATLAS, "Matrix", Matrix, create=True):
            high = ATLAS.canonical_high(source, 0., collection)
            self.assertEqual([vertex.co for vertex in high.data.vertices], [ADAPTER.canonical_position(point) for point in points])
            self.assertTrue(high.data.flipped)
            self.assertIsNot(high.data.materials[0], original_material)
            self.assertIs(ATLAS.continuous_body_group(high, reflected=True)[1].node_tree, group)
            self.assertEqual([vertex.co for vertex in source.data.vertices], points)
            self.assertIs(source.data.materials[0], original_material)
            wing = Source("PaddleWing+1", Material("PreviewBodyFeatherSurface", Graph()), [(.1, .2, .3, 1.)] * 3)
            wing_high = ATLAS.canonical_high(wing, 0., collection)
            self.assertIs(wing_high.data.materials[0], wing.data.materials[0])

    def test_mask_copy_emits_exact_same_group_not_diagnostic_attributes(self):
        source, group = body_fixture()
        high = source.copy()
        high.data = source.data.copy()
        high.data.materials[0] = ATLAS.canonical_continuous_material(source)
        original = high.data.materials[0]
        before = graph_edges(original.node_tree), graph_edges(group)
        masks = ATLAS.continuous_mask_material(high)
        self.assertIsNot(masks, original)
        output = next(node for node in masks.node_tree.nodes if node.type == "OUTPUT_MATERIAL")
        emission = output.inputs["Surface"].links[0].from_node
        edge = emission.inputs["Color"].links[0]
        self.assertEqual(edge.from_socket.name, "SemanticMasks")
        self.assertIs(edge.from_node.node_tree, group)
        self.assertEqual(before, (graph_edges(original.node_tree), graph_edges(group)))
        self.assertEqual(group.nodes[-1].inputs["FeatherRegion"].default_value, 1.)

    def test_mask_copy_rejects_unfixed_or_twice_reflected_position(self):
        source, _group = body_fixture()
        with self.assertRaises(RuntimeError): ATLAS.continuous_mask_material(source)
        source.data.materials[0] = ATLAS.canonical_continuous_material(source)
        correction = next(node for node in source.data.materials[0].node_tree.nodes if node.type == "VECT_MATH")
        correction.inputs[1].default_value = (1., 1., 1.)
        with self.assertRaises(RuntimeError): ATLAS.continuous_mask_material(source)

    def bake_fixture(self):
        source, _group = body_fixture()
        high = source.copy()
        high.data = source.data.copy()
        high.data.materials[0] = ATLAS.canonical_continuous_material(source)
        high.select_set = Mock()
        low = Source("AtlasBakeTarget", Material("Low", Graph()), [(.1, .1, .1, 1.)] * 3)
        low["original_corner_normal_maximum_error"] = 0.
        node = SimpleNamespace(image=None)
        maps = {name: name for name in ("albedo", "normal", "roughness", "ao", "masks", "hits", "coverage")}
        removed = Mock()
        bpy = SimpleNamespace(data=SimpleNamespace(materials=SimpleNamespace(remove=removed)),
                              ops=SimpleNamespace(object=SimpleNamespace(bake=Mock())))
        return high, low, node, maps, removed, bpy

    def test_bake_uses_continuous_masks_keeps_projection_and_coverage_gates(self):
        high, low, node, maps, removed, bpy = self.bake_fixture()
        original = high.data.materials[0]
        captured = []
        def capture(**kwargs): captured.append((node.image, list(high.data.materials), kwargs))
        bpy.ops.object.bake.side_effect = capture
        adapter = SimpleNamespace(activate=Mock())
        with patch.object(ATLAS, "adapter", adapter, create=True), patch.object(ATLAS, "bpy", bpy, create=True), \
                patch.object(ATLAS, "MASK_MATERIAL", "diagnostic-mask", create=True), patch.object(ATLAS, "HIT_MATERIAL", "hit", create=True):
            report = ATLAS.bake_component(high, low, node, maps, margin=8)
        self.assertEqual([row[0] for row in captured], list(maps))
        mask_material = captured[4][1][0]
        self.assertIsInstance(mask_material, Material)
        self.assertIsNot(mask_material, original)
        self.assertEqual(captured[4][2]["margin"], 8)
        self.assertEqual(captured[5][2]["margin"], 0)
        self.assertEqual(captured[6][2]["margin"], 0)
        self.assertFalse(captured[6][2]["use_selected_to_active"])
        self.assertEqual(report["max_ray_distance_m"], .04)
        self.assertEqual(report["cage_extrusion_m"], .012)
        self.assertIn("SemanticMasks", report["semantic_mask_authority"])
        self.assertEqual(high.data.materials, [original])
        removed.assert_called_once_with(mask_material)

    def test_mask_bake_failure_restores_material_and_removes_scratch_copy(self):
        high, low, node, maps, removed, bpy = self.bake_fixture()
        original = high.data.materials[0]
        def fail(**_kwargs):
            if node.image == "masks": raise RuntimeError("projection failed")
        bpy.ops.object.bake.side_effect = fail
        with patch.object(ATLAS, "adapter", SimpleNamespace(activate=Mock()), create=True), \
                patch.object(ATLAS, "bpy", bpy, create=True), patch.object(ATLAS, "MASK_MATERIAL", "mask", create=True), \
                patch.object(ATLAS, "HIT_MATERIAL", "hit", create=True), self.assertRaisesRegex(RuntimeError, "projection failed"):
            ATLAS.bake_component(high, low, node, maps, margin=8)
        self.assertEqual(high.data.materials, [original])
        removed.assert_called_once()


if __name__ == "__main__":
    unittest.main()
