"""One saved-source BODY QuadriFlow QA cage, not authored deformation topology.

No source-design imports, rig/anatomy changes, solver retries or fallback.
The source shader remains texture authority; transferred colors are diagnostic
literal preview data only. Root owns artifact provenance and motion approval.
"""
from __future__ import annotations

from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import struct

POLICY = "unified-body-quadriflow-project-v1"
SIZING_POLICY = "fixed-request-three-sevenths-final-triangle-cap-v1"
SEED = 37
LIMITS = {"whole_body_surface_m": .006, "aperture_surface_m": .003,
          "aabb_m": .003, "bottom_contact_m": .002}
# Fixed review region in the immutable source eye frames, not old X/Y bands.
APERTURE_REGION = {"abs_x_m": .160, "abs_z_m": .200, "depth_min_m": -.065, "depth_max_m": .080}
BOTTOM_BAND_M = .050
DIAGNOSTIC_FIELDS = ("PreviewColor", "SourceSemanticMasks")
CONDITIONING_POLICY = "private-solver-copy-power2-units-4096-v1"
SOLVER_UNIT_SCALE = 4096
BLENDER_EDGE_EPSILON = struct.unpack("<f", struct.pack("<f", .0001))[0]
TOOL_SHA256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


def vector(value):
    result = tuple(float(channel) for channel in value)
    if len(result) != 3 or not all(math.isfinite(channel) for channel in result):
        raise ValueError("retopology needs finite three-dimensional coordinates")
    return result


def sub(a, b): return tuple(x - y for x, y in zip(a, b))
def dot(a, b): return sum(x * y for x, y in zip(a, b))
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def quadriflow_settings(target_triangles):
    if type(target_triangles) is not int or not 1000 <= target_triangles <= 14000:
        raise ValueError("BODY triangle target must be an integer in 1000..14000")
    return {"mode": "FACES", "target_faces": target_triangles * 3 // 7, "seed": SEED,
            "use_mesh_symmetry": False, "use_preserve_sharp": True, "use_preserve_boundary": True,
            "preserve_attributes": False, "smooth_normals": True}


def validate_eye_frames(eye_frames):
    if not isinstance(eye_frames, dict) or set(eye_frames) != {-1., 1.}:
        raise ValueError("BODY retopology requires both immutable eye frames keyed by -1.0 and 1.0")
    frames = {}
    for side, frame in eye_frames.items():
        if len(frame) != 4:
            raise ValueError("eye frame must contain origin, across, normal and up")
        origin, across, normal, up = tuple(vector(axis) for axis in frame)
        axes = across, normal, up
        if (any(abs(dot(axis, axis) - 1.) > 1e-6 for axis in axes)
                or any(abs(dot(axes[i], axes[j])) > 1e-6 for i in range(3) for j in range(i))):
            raise ValueError("immutable eye frame axes must be orthonormal")
        frames[side] = origin, across, normal, up
    return frames


def in_aperture_region(point, eye_frames):
    for origin, across, normal, up in eye_frames.values():
        relative = sub(point, origin)
        if (abs(dot(relative, across)) <= APERTURE_REGION["abs_x_m"]
                and abs(dot(relative, up)) <= APERTURE_REGION["abs_z_m"]
                and APERTURE_REGION["depth_min_m"] <= dot(relative, normal) <= APERTURE_REGION["depth_max_m"]):
            return True
    return False


def barycentric_weights(point, triangle):
    point, (a, b, c) = vector(point), tuple(vector(value) for value in triangle)
    first, second, relative = sub(b, a), sub(c, a), sub(point, a)
    normal = cross(first, second)
    denominator = dot(normal, normal)
    if denominator <= 1e-30:
        raise ValueError("cannot interpolate a degenerate source triangle")
    beta, gamma = dot(cross(relative, second), normal) / denominator, dot(cross(first, relative), normal) / denominator
    raw = 1. - beta - gamma, beta, gamma
    # BVH nearest positions use float32; clamp only roundoff whose reconstructed
    # physical position is within 1 micrometer, never a distant/off-plane point.
    clipped = tuple(max(0., min(1., weight)) for weight in raw)
    total = sum(clipped)
    if not total:
        raise ValueError("invalid barycentric source projection")
    weights = tuple(weight / total for weight in clipped)
    reconstructed = tuple(sum(weight * vertex[axis] for weight, vertex in zip(weights, (a, b, c))) for axis in range(3))
    if math.dist(point, reconstructed) > 1e-6:
        raise ValueError("nearest projection does not lie on its source triangle")
    return weights


def interpolate_diagnostic(colors, weights, *, masks=False):
    if len(colors) != 3 or len(weights) != 3:
        raise ValueError("diagnostic interpolation needs three source corners")
    for value in colors:
        if (len(value) != 4 or any(not math.isfinite(channel) or not 0 <= channel <= 1 for channel in value)
                or value[3] != 1. or (masks and sum(value[:3]) > 1.0000001)):
            raise ValueError("invalid source diagnostic color/mask")
    if any(not math.isfinite(weight) or weight < 0 or weight > 1 for weight in weights) or abs(sum(weights) - 1.) > 1e-12:
        raise ValueError("diagnostic interpolation requires convex barycentric weights")
    return tuple(sum(weight * color[channel] for weight, color in zip(weights, colors)) for channel in range(3)) + (1.,)


def mesh_topology(points, triangles):
    points = [vector(point) for point in points]
    edges, direction = Counter(), Counter()
    parents = list(range(len(points)))
    used, faces, degenerate = set(), set(), 0
    volume = 0.
    def root(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index
    for triangle in triangles:
        if (len(triangle) != 3 or any(type(index) is not int or not 0 <= index < len(points) for index in triangle)
                or len(set(triangle)) != 3):
            raise ValueError("invalid retopology triangle indices")
        a, b, c = (points[index] for index in triangle)
        area = math.sqrt(dot(cross(sub(b, a), sub(c, a)), cross(sub(b, a), sub(c, a)))) * .5
        degenerate += int(area < 1e-14)
        volume += dot(a, cross(b, c)) / 6.
        used.update(triangle)
        faces.add(tuple(sorted(triangle)))
        for first, second in zip(triangle, (*triangle[1:], triangle[0])):
            key = tuple(sorted((first, second)))
            edges[key] += 1
            direction[key] += 1 if first < second else -1
            parents[root(first)] = root(second)
    return {"vertices": len(points), "triangles": len(triangles), "edges": len(edges),
            "boundary_edges": sum(count == 1 for count in edges.values()),
            "nonmanifold_edges": sum(count > 2 for count in edges.values()),
            "inconsistent_orientation_edges": sum(count == 2 and direction[key] != 0 for key, count in edges.items()),
            "loose_vertices": len(points) - len(used), "duplicate_triangles": len(triangles) - len(faces),
            "degenerate_triangles": degenerate, "connected_components": len({root(index) for index in used}),
            "euler_characteristic": len(used) - len(edges) + len(triangles), "signed_volume_m3": volume}


def require_closed(topology, *, source=False):
    keys = ("boundary_edges", "nonmanifold_edges", "inconsistent_orientation_edges", "loose_vertices", "duplicate_triangles")
    if (any(topology[key] for key in keys) or topology["connected_components"] != 1
            or not math.isfinite(topology["signed_volume_m3"]) or abs(topology["signed_volume_m3"]) < 1e-12
            or (not source and topology["degenerate_triangles"])):
        raise RuntimeError("BODY must remain closed, nondegenerate and consistently oriented: " + json.dumps(topology, sort_keys=True))


def aabb(points):
    if not points:
        raise ValueError("empty BODY bounds")
    return {"min": [min(point[axis] for point in points) for axis in range(3)],
            "max": [max(point[axis] for point in points) for axis in range(3)]}


def quad_statistics(mesh):
    faces = [tuple(face.vertices) for face in mesh.polygons]
    edges = {tuple(sorted((first, second))) for face in faces for first, second in zip(face, (*face[1:], face[0]))}
    degree = Counter(index for edge in edges for index in edge)
    return {"faces": len(faces), "quads": sum(len(face) == 4 for face in faces),
            "triangles": sum(len(face) == 3 for face in faces), "ngons": sum(len(face) > 4 for face in faces),
            "triangulated_triangle_count": sum(len(face) - 2 for face in faces),
            "pole_vertices": sum(value != 4 for value in degree.values()),
            "vertex_valence_histogram": dict(sorted(Counter(degree.values()).items()))}


def blender_input_predicate(points, edges, corners):
    """Pinned 5.2 mesh_is_manifold_consistent, including float32 edge compare.

    Audit every stored edge/corner; triangle-derived topology is a separate gate.
    Normals are deliberately absent: Blender's pre-solver predicate never reads them.
    """
    points = [vector(point) for point in points]
    counts, starts = [0] * len(edges), [-1] * len(edges)
    first_rejection, flipped_corners = None, 0
    for edge in edges:
        if (len(edge) != 2 or any(type(index) is not int or not 0 <= index < len(points) for index in edge)):
            raise ValueError("invalid stored solver edge")
    for corner_index, (vertex, edge_index) in enumerate(corners):
        if (type(vertex) is not int or type(edge_index) is not int or not 0 <= edge_index < len(edges)
                or vertex not in edges[edge_index]):
            raise ValueError("invalid stored solver corner")
        counts[edge_index] += 1
        if counts[edge_index] > 2 and first_rejection is None:
            first_rejection = {"kind": "edge_more_than_two_faces", "edge": edge_index, "corner": corner_index}
        if starts[edge_index] == -1:
            starts[edge_index] = vertex
        elif starts[edge_index] == vertex:
            flipped_corners += 1
            if first_rejection is None:
                first_rejection = {"kind": "same_corner_start_vertex", "edge": edge_index, "corner": corner_index}
    short_edges, minimum_length = 0, None
    for index, (first, second) in enumerate(edges):
        length = math.dist(points[first], points[second])
        minimum_length = length if minimum_length is None else min(minimum_length, length)
        # Stored Blender coordinates and each C subtraction are float32.
        differences = [abs(struct.unpack("<f", struct.pack("<f", a - b))[0])
                       for a, b in zip(points[first], points[second])]
        short = all(value <= BLENDER_EDGE_EPSILON for value in differences)
        short_edges += int(short)
        if first_rejection is None and (counts[index] == 0 or short):
            first_rejection = {"kind": "wire_edge" if counts[index] == 0 else "coordinate_close_edge", "edge": index}
    return {"stored_edges": len(edges), "stored_corners": len(corners),
            "overused_edges": sum(count > 2 for count in counts), "same_start_orientation_corners": flipped_corners,
            "wire_edges": counts.count(0), "boundary_edges": counts.count(1), "coordinate_close_edges": short_edges,
            "minimum_stored_edge_units": minimum_length, "float32_per_axis_epsilon_units": BLENDER_EDGE_EPSILON,
            "first_rejection": first_rejection, "passed": first_rejection is None,
            "primary_source": "https://github.com/blender/blender/blob/v5.2.0/source/blender/editors/object/object_remesh.cc#L630-L683"}


def stored_input_report(mesh):
    return blender_input_predicate([tuple(vertex.co) for vertex in mesh.vertices],
                                  [tuple(edge.vertices) for edge in mesh.edges],
                                  [(corner.vertex_index, corner.edge_index) for corner in mesh.loops])


def float32(value):
    try:
        result = struct.unpack("<f", struct.pack("<f", value))[0]
    except (OverflowError, struct.error) as error:
        raise ValueError("solver unit conversion exceeds finite float32") from error
    if not math.isfinite(result):
        raise ValueError("solver unit conversion needs finite float32")
    return result


def scale_solver_points(points):
    """Fixed exact power-of-two conversion, with bit-exact inverse proof."""
    scaled, restored = [], []
    for point in points:
        original = tuple(float32(value) for value in vector(point))
        result = tuple(float32(value * SOLVER_UNIT_SCALE) for value in original)
        inverse = tuple(float32(value / SOLVER_UNIT_SCALE) for value in result)
        if struct.pack("<3f", *original) != struct.pack("<3f", *inverse):
            raise RuntimeError("private BODY solver unit conversion is not bit-exactly reversible")
        scaled.append(result)
        restored.append(inverse)
    return scaled, restored


def stored_topology_guard(mesh):
    digest = hashlib.sha256()
    digest.update(struct.pack("<4I", len(mesh.vertices), len(mesh.edges), len(mesh.polygons), len(mesh.loops)))
    for edge in mesh.edges:
        digest.update(struct.pack("<2I", *edge.vertices))
    for face in mesh.polygons:
        digest.update(struct.pack("<I", len(face.vertices)))
        digest.update(struct.pack("<" + "I" * len(face.vertices), *face.vertices))
    for corner in mesh.loops:
        digest.update(struct.pack("<2I", corner.vertex_index, corner.edge_index))
    return digest.hexdigest()


def condition_solver_copy(obj, high_points, high_triangles, source_topology, report):
    """Change numerical solver units only; no weld/dissolve/topology cleanup."""
    detail = {"policy": CONDITIONING_POLICY, "solver_units_per_meter": SOLVER_UNIT_SCALE,
              "power_of_two_exponent": 12, "topology_cleanup_performed": False,
              "source_projection_authority_unchanged": True, "solver_units_restored": False, "passed": False}
    report["conditioning"] = detail
    detail["before_predicate"] = stored_input_report(obj.data)
    if any(detail["before_predicate"][key] for key in
           ("overused_edges", "same_start_orientation_corners", "wire_edges", "boundary_edges")):
        raise RuntimeError("private BODY input has stored topology defects; unit conversion cannot repair them")
    detail["stored_topology_before_sha256"] = stored_topology_guard(obj.data)
    original_points = [vector(vertex.co) for vertex in obj.data.vertices]
    if (len(original_points) != len(high_points)
            or any(struct.pack("<3f", *actual) != struct.pack("<3f", *expected)
                   for actual, expected in zip(original_points, high_points))):
        raise RuntimeError("private BODY copy differs from immutable high coordinates before unit conversion")
    scaled_points, _restored = scale_solver_points(original_points)
    for vertex, point in zip(obj.data.vertices, scaled_points):
        vertex.co = point
    obj.data.update()
    obj.data.calc_loop_triangles()
    actual_scaled = [vector(vertex.co) for vertex in obj.data.vertices]
    actual_restored = [tuple(float32(value / SOLVER_UNIT_SCALE) for value in point) for point in actual_scaled]
    detail["inverse_float32_coordinate_identity"] = (len(actual_restored) == len(high_points)
        and all(struct.pack("<3f", *actual) == struct.pack("<3f", *expected)
                for actual, expected in zip(actual_restored, high_points)))
    detail["stored_topology_after_sha256"] = stored_topology_guard(obj.data)
    detail["stored_topology_unchanged"] = detail["stored_topology_before_sha256"] == detail["stored_topology_after_sha256"]
    detail["triangle_indices_unchanged"] = [tuple(triangle.vertices) for triangle in obj.data.loop_triangles] == high_triangles
    detail["after_predicate"] = stored_input_report(obj.data)
    print("[v12-retopology-private-input] " + json.dumps(detail, sort_keys=True, allow_nan=False), flush=True)
    if not all(detail[key] for key in ("inverse_float32_coordinate_identity", "stored_topology_unchanged", "triangle_indices_unchanged")):
        raise RuntimeError("private BODY unit conversion changed inverse coordinates or stored topology")
    if not detail["after_predicate"]["passed"]:
        raise RuntimeError("fixed private BODY unit conversion still violates pinned Blender input predicate")
    # Identical inverse float32 coordinates plus identical ordered triangles prove
    # the entire indexed source surface unchanged, not merely sampled proximity.
    detail["topology_in_meters"] = mesh_topology(actual_restored, high_triangles)
    detail["topology"] = detail["topology_in_meters"]
    require_closed(detail["topology"])
    if detail["topology"] != source_topology:
        raise RuntimeError("private BODY unit conversion changed closed source topology or orientation")
    detail["shape_in_meters"] = {"source_bounds": aabb(high_points), "inverse_conditioned_bounds": aabb(actual_restored),
        "exact_indexed_surface_identity": True, "whole_body_surface_error_m": 0., "aperture_surface_error_m": 0.,
        "aabb_error_m": 0., "bottom_contact_error_m": 0., "limits_m": LIMITS.copy(),
        "measurement": "bit-exact inverse coordinates and identical ordered triangles; final cage remains subject to paired BVH limits"}
    detail["passed"] = True


def restore_solver_units(obj, report):
    detail = report["conditioning"]
    if (detail["policy"] != CONDITIONING_POLICY or detail["solver_units_per_meter"] != SOLVER_UNIT_SCALE
            or not detail["passed"] or detail["solver_units_restored"]):
        raise RuntimeError("BODY solver unit restoration requires one passed fixed-scale input")
    for vertex in obj.data.vertices:
        scaled = vector(vertex.co)
        restored = tuple(float32(value / SOLVER_UNIT_SCALE) for value in scaled)
        if struct.pack("<3f", *scaled) != struct.pack("<3f", *(float32(value * SOLVER_UNIT_SCALE) for value in restored)):
            raise RuntimeError("BODY solver output cannot return bit-exactly to world meters")
        vertex.co = restored
    obj.data.update()
    detail["solver_units_restored"] = True
    detail["solver_output_coordinate_units"] = "world meters"


def invoke_quadriflow_once(bpy, settings, report):
    report["operator_calls"] += 1
    report["solver_entry"] = "unknown_until_finished"
    result = bpy.ops.object.quadriflow_remesh(**settings)
    report["operator_result"] = sorted(result)
    if result != {"FINISHED"}:
        raise RuntimeError("single BODY QuadriFlow solve did not finish: " + repr(result))
    report["solver_calls"] += 1
    report["solver_entry"] = "confirmed_finished"


def nearest_hit(tree, point, triangle_count):
    position, _normal, index, distance = tree.find_nearest(point)
    if (position is None or type(index) is not int or not 0 <= index < triangle_count
            or distance is None or not math.isfinite(distance) or distance < 0):
        raise RuntimeError("BODY projection has no valid paired source triangle")
    position = vector(position)
    return position, index, math.dist(point, position)


def surface_samples(points, triangles, *, edge_midpoints=False):
    yield from points
    for triangle in triangles:
        corners = [points[index] for index in triangle]
        yield tuple(sum(point[axis] for point in corners) / 3. for axis in range(3))
        if edge_midpoints:
            for first, second in zip(corners, (*corners[1:], corners[0])):
                yield tuple((a + b) * .5 for a, b in zip(first, second))


def surface_error(samples, tree, triangle_count, eye_frames, *, bottom_z=None):
    report = {"samples": 0, "maximum_m": 0., "aperture_samples": 0, "aperture_maximum_m": 0.,
              "bottom_samples": 0, "bottom_maximum_m": 0.}
    squared = 0.
    for point in samples:
        position, _index, distance = nearest_hit(tree, point, triangle_count)
        report["samples"] += 1
        report["maximum_m"] = max(report["maximum_m"], distance)
        squared += distance * distance
        if in_aperture_region(point, eye_frames) or in_aperture_region(position, eye_frames):
            report["aperture_samples"] += 1
            report["aperture_maximum_m"] = max(report["aperture_maximum_m"], distance)
        if bottom_z is not None and point[2] <= bottom_z + BOTTOM_BAND_M:
            report["bottom_samples"] += 1
            report["bottom_maximum_m"] = max(report["bottom_maximum_m"], distance)
    if not report["samples"]:
        raise RuntimeError("BODY surface error check had no samples")
    report["rms_m"] = math.sqrt(squared / report["samples"])
    return report


def require_shape(source_bounds, low_bounds, source_to_low, low_to_source):
    deltas = {key: [abs(a - b) for a, b in zip(source_bounds[key], low_bounds[key])] for key in ("min", "max")}
    report = {"source_bounds": source_bounds, "candidate_bounds": low_bounds, "aabb_deltas_m": deltas,
              "source_to_low": source_to_low, "low_to_source": low_to_source,
              "bottom_min_z_delta_m": abs(source_bounds["min"][2] - low_bounds["min"][2]),
              "bottom_envelope_band_m": BOTTOM_BAND_M,
              "surface_measurement": "all source vertices/triangle centroids; all low vertices/triangle centroids/edge midpoints; sampled, not certified Hausdorff"}
    failures = []
    for direction, metric in (("source_to_low", source_to_low), ("low_to_source", low_to_source)):
        if metric["maximum_m"] > LIMITS["whole_body_surface_m"]: failures.append(direction + ":whole_body")
        if not metric["aperture_samples"] or metric["aperture_maximum_m"] > LIMITS["aperture_surface_m"]:
            failures.append(direction + ":aperture")
    if max(value for values in deltas.values() for value in values) > LIMITS["aabb_m"]: failures.append("aabb")
    if (not source_to_low["bottom_samples"] or source_to_low["bottom_maximum_m"] > LIMITS["bottom_contact_m"]
            or report["bottom_min_z_delta_m"] > LIMITS["bottom_contact_m"]): failures.append("bottom_contact_envelope")
    report["failures"] = failures
    report["passed"] = not failures
    return report


def _plain(value):
    if value is None or type(value) in (str, int, float, bool): return value
    if hasattr(value, "items"): return {str(key): _plain(item) for key, item in value.items()}
    return [_plain(item) for item in value]


def source_guard(source):
    digest = hashlib.sha256()
    for vertex in source.data.vertices: digest.update(struct.pack("<3d", *vertex.co))
    for face in source.data.polygons:
        digest.update(struct.pack("<I", len(face.vertices)))
        digest.update(struct.pack("<" + "I" * len(face.vertices), *face.vertices))
    for name in DIAGNOSTIC_FIELDS:
        attribute = source.data.color_attributes.get(name)
        if (attribute is None or attribute.domain != "POINT" or attribute.data_type != "FLOAT_COLOR"
                or len(attribute.data) != len(source.data.vertices)):
            raise RuntimeError("BODY requires source FLOAT_COLOR POINT " + name)
        digest.update(name.encode())
        for item in attribute.data: digest.update(struct.pack("<4d", *item.color))
    materials = []
    for material in source.data.materials:
        tree = material.node_tree
        materials.append({"identity": material.as_pointer(), "name": material.name,
                          "properties": _plain(dict(material.items())),
                          "links": [(edge.from_node.name, edge.from_socket.identifier, edge.to_node.name, edge.to_socket.identifier)
                                    for edge in tree.links] if tree is not None else [],
                          "groups": [(node.name, node.node_tree.as_pointer()) for node in tree.nodes if node.type == "GROUP"] if tree else [],
                          "images": [(node.name, node.image.as_pointer() if node.image else None) for node in tree.nodes if node.type == "TEX_IMAGE"] if tree else []})
    digest.update(json.dumps({"properties": _plain(dict(source.items())), "materials": materials,
                              "matrix_world": [list(row) for row in source.matrix_world]}, sort_keys=True, allow_nan=False).encode())
    return digest.hexdigest()


def build_body(source, target_triangles, collection, eye_frames):
    """Return one projected triangulated BODY object, source count, cage count."""
    settings = quadriflow_settings(target_triangles)
    frames = validate_eye_frames(eye_frames)
    import bpy
    import bmesh
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    if tuple(bpy.app.version) != (5, 2, 0):
        raise RuntimeError("BODY retopology requires pinned Blender 5.2.0")
    if (source.type != "MESH" or not source.name.startswith("HeroBody") or len(source.data.materials) != 1
            or len(source.modifiers) or source.data.shape_keys is not None
            or source.get("source_mask_contract") != "feather-palette-weights-v1"):
        raise RuntimeError("BODY retopology accepts only the saved unmodified one-material body")
    before_guard = source_guard(source)
    source.data.calc_loop_triangles()
    high_points = [vector(source.matrix_world @ vertex.co) for vertex in source.data.vertices]
    high_triangles = [tuple(triangle.vertices) for triangle in source.data.loop_triangles]
    before = len(high_triangles)
    report = {"policy": POLICY, "tool_sha256": TOOL_SHA256, "source_component": source.name,
              "method": "automated QuadriFlow QA retopology plus immutable source-surface BVH projection; not hand-authored",
              "production_ready": False, "source_fidelity_approved": False, "deformation_approved": False,
              "source_shader_is_texture_authority": True, "diagnostic_fields_are_texture_authority": False,
              "limits_m": LIMITS.copy(), "aperture_region": APERTURE_REGION.copy(),
              "eye_frames": {str(side): [list(axis) for axis in frame] for side, frame in frames.items()},
              "solver_settings": settings, "operator_calls": 0, "solver_calls": 0,
              "solver_sizing": {"policy": SIZING_POLICY, "requested_faces": settings["target_faces"],
                                "actual_final_triangle_cap": target_triangles, "requested_faces_are_approximate": True,
                                "primary_source": "https://github.com/blender/blender/blob/v5.2.0/source/blender/editors/object/object_remesh.cc#L1119-L1127"},
              "solver_entry": "not_invoked", "solver_call_accounting": "confirmed FINISHED solver returns; non-FINISHED entry is not observable",
              "source_triangles": before,
              "target_triangles": target_triangles, "triangulation": {"quad_method": "FIXED", "ngon_method": "EAR_CLIP"},
              "source_guard_before": before_guard, "passed": False,
              "limitations": ["No hand-authored edge-flow, deformation, footplant or full-rig contact approval.",
                              "Surface bounds are measured samples, not a certified continuous Hausdorff bound.",
                              "No mouth, eye surface, anatomy or visual-fidelity improvement is implied."]}
    obj = None
    try:
        report["source_topology"] = mesh_topology(high_points, high_triangles)
        print("[v12-retopology-source] " + json.dumps(report["source_topology"], sort_keys=True, allow_nan=False), flush=True)
        require_closed(report["source_topology"], source=True)
        colors = {name: [tuple(item.color) for item in source.data.color_attributes[name].data] for name in DIAGNOSTIC_FIELDS}
        for name, values in colors.items():
            for color in values: interpolate_diagnostic((color, color, color), (1., 0., 0.), masks=name == "SourceSemanticMasks")
        high_tree = BVHTree.FromPolygons(high_points, high_triangles, all_triangles=True, epsilon=0.)
        obj = source.copy()
        obj.data = source.data.copy()
        collection.objects.link(obj)
        obj.data.transform(source.matrix_world)
        obj.matrix_world.identity()
        condition_solver_copy(obj, high_points, high_triangles, report["source_topology"], report)
        bpy.ops.object.select_all(action="DESELECT")
        obj.hide_set(False)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        invoke_quadriflow_once(bpy, settings, report)
        restore_solver_units(obj, report)
        report["quad_cage"] = quad_statistics(obj.data)
        if not report["quad_cage"]["faces"] or report["quad_cage"]["triangulated_triangle_count"] > target_triangles:
            raise RuntimeError("single BODY QuadriFlow solve exceeds its triangle budget: " + json.dumps(report["quad_cage"], sort_keys=True))
        transferred = {name: [] for name in DIAGNOSTIC_FIELDS}
        displacement = []
        for vertex in obj.data.vertices:
            location, index, distance = nearest_hit(high_tree, vector(vertex.co), len(high_triangles))
            indices = high_triangles[index]
            weights = barycentric_weights(location, [high_points[value] for value in indices])
            for name in DIAGNOSTIC_FIELDS:
                transferred[name].append(interpolate_diagnostic([colors[name][value] for value in indices], weights,
                                                               masks=name == "SourceSemanticMasks"))
            vertex.co = location
            displacement.append(distance)
        report["projection"] = {"vertices": len(displacement), "maximum_preprojection_displacement_m": max(displacement),
                                "rms_preprojection_displacement_m": math.sqrt(sum(value * value for value in displacement) / len(displacement))}
        obj.data.materials.clear()
        obj.data.materials.append(source.data.materials[0])
        for name in DIAGNOSTIC_FIELDS:
            existing = obj.data.color_attributes.get(name)
            if existing is not None: obj.data.color_attributes.remove(existing)
            attribute = obj.data.color_attributes.new(name=name, type="FLOAT_COLOR", domain="POINT")
            for item, color in zip(attribute.data, transferred[name]): item.color = color
        edit = bmesh.new()
        try:
            edit.from_mesh(obj.data)
            bmesh.ops.triangulate(edit, faces=list(edit.faces), quad_method="FIXED", ngon_method="EAR_CLIP")
            edit.to_mesh(obj.data)
        finally:
            edit.free()
        obj.data.update()
        obj.data.calc_loop_triangles()
        low_points = [vector(vertex.co) for vertex in obj.data.vertices]
        low_triangles = [tuple(face.vertices) for face in obj.data.polygons]
        report["candidate_topology"] = mesh_topology(low_points, low_triangles)
        after = len(low_triangles)
        require_closed(report["candidate_topology"])
        if after > target_triangles or report["candidate_topology"]["euler_characteristic"] != report["source_topology"]["euler_characteristic"]:
            raise RuntimeError("BODY triangulation changed the budget or closed source topology")
        if report["candidate_topology"]["signed_volume_m3"] * report["source_topology"]["signed_volume_m3"] <= 0:
            raise RuntimeError("BODY cage reverses source orientation")
        low_tree = BVHTree.FromPolygons(low_points, low_triangles, all_triangles=True, epsilon=0.)
        high_bounds, low_bounds = aabb(high_points), aabb(low_points)
        forward = surface_error(surface_samples(high_points, high_triangles), low_tree, after, frames, bottom_z=high_bounds["min"][2])
        reverse = surface_error(surface_samples(low_points, low_triangles, edge_midpoints=True), high_tree, before, frames)
        report["shape"] = require_shape(high_bounds, low_bounds, forward, reverse)
        if not report["shape"]["passed"]:
            raise RuntimeError("BODY cage exceeds frozen shape/contact limits: " + json.dumps(report["shape"], sort_keys=True))
        for name in DIAGNOSTIC_FIELDS:
            attribute = obj.data.color_attributes.get(name)
            if (attribute is None or attribute.domain != "POINT" or attribute.data_type != "FLOAT_COLOR"
                    or len(attribute.data) != len(low_points)):
                raise RuntimeError("BODY triangulation lost diagnostic field " + name)
            for item in attribute.data:
                interpolate_diagnostic((tuple(item.color),) * 3, (1., 0., 0.), masks=name == "SourceSemanticMasks")
        for face in obj.data.polygons: face.use_smooth = True
        report["actual_triangles"] = after
        report["passed"] = True
        return obj, before, after
    except Exception as error:
        report["rejection"] = str(error)
        raise
    finally:
        report["source_guard_after"] = source_guard(source)
        report["source_unchanged"] = report["source_guard_after"] == before_guard
        if not report["source_unchanged"]:
            report["passed"] = False
            report["rejection"] = "saved BODY source properties, geometry, materials or diagnostic fields changed"
        if obj is not None:
            obj["candidate_retopology_json"] = json.dumps(report, sort_keys=True, allow_nan=False)
        print("[v12-retopology] " + json.dumps(report, sort_keys=True, allow_nan=False), flush=True)
        if not report["source_unchanged"]:
            raise RuntimeError(report["rejection"])
