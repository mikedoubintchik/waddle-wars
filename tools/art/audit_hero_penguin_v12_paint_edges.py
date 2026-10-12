#!/usr/bin/env python3
"""Read-only saved-Z12 ray/material audit. Never renders or saves the blend.

Example (parent coordinates execution):
  Blender --background --factory-startup --threads 2 --python-exit-code 1 \
    --python tools/art/audit_hero_penguin_v12_paint_edges.py -- \
    --source-dir qa_shots/hero/v12_source_proof_z12 \
    --output qa_shots/hero/v12_source_proof_z12/paint_edge_ray_audit.json

Pixel origin is top-left; rays pass through pixel centers using the inverse
actual camera-data projection and the renderer's recorded front-view pose.
No camera, mesh, material or source file is edited. Evaluated mesh copies are
temporary and released. A fresh QA JSON is the only output.
"""
from __future__ import annotations

import argparse
import ast
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import hero_penguin_v12_face_z12 as face

REGIONS = {"outer_left_edge": (130, 185, 140, 172),
           "bridge_edge": (240, 274, 152, 176)}
CONTROLS = {"left_iris": (192, 160), "right_iris": (320, 160),
            "left_upper_sclera": (184, 141), "right_upper_sclera": (325, 141),
            "bill": (256, 206), "belly": (256, 370), "background": (32, 32)}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def vector(value):
    return [float(channel) for channel in value]


def front_pose(renderer_path):
    """Read the exact frozen render_views literal; never execute its renderer."""
    tree = ast.parse(renderer_path.read_text())
    functions = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "render_views"]
    if len(functions) != 1:
        raise ValueError("Expected one frozen render_views function")
    assignments = [n for n in functions[0].body if isinstance(n, ast.Assign)
                   and any(isinstance(t, ast.Name) and t.id == "views" for t in n.targets)]
    if len(assignments) != 1:
        raise ValueError("Frozen front-view literal missing or ambiguous")
    views = ast.literal_eval(assignments[0].value)
    location, target = map(Vector, views["front"])
    matrix = (target - location).to_track_quat("-Z", "Y").to_matrix().to_4x4()
    matrix.translation = location
    return matrix, {"location": vector(location), "target": vector(target)}


def pixel_ray(x, y, width, height, inverse_projection, world):
    ndc_x, ndc_y = 2. * (x + .5) / width - 1., 1. - 2. * (y + .5) / height

    def unproject(z):
        value = inverse_projection @ Vector((ndc_x, ndc_y, z, 1.))
        if abs(value.w) < 1e-12:
            raise ValueError("Camera inverse projection produced point at infinity")
        return world @ (value.xyz / value.w)

    near, far = unproject(-1.), unproject(1.)
    delta = far - near
    return near, delta.normalized(), delta.length


def barycentric(point, triangle):
    """Float64 dominant-plane barycentrics; avoid float32 thin-face dot products."""
    a, b, c = [tuple(float(value) for value in p) for p in triangle]
    p = tuple(float(value) for value in point)
    ab, ac = [b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)]
    normal = (ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0])
    length = math.sqrt(sum(v * v for v in normal))
    if length < 1e-18:
        return None
    axes = [i for i in range(3) if i != max(range(3), key=lambda i: abs(normal[i]))]
    i, j = axes
    determinant = ab[i] * ac[j] - ab[j] * ac[i]
    pb = ((p[i] - a[i]) * ac[j] - (p[j] - a[j]) * ac[i]) / determinant
    pc = (ab[i] * (p[j] - a[j]) - ab[j] * (p[i] - a[i])) / determinant
    weights = (1. - pb - pc, pb, pc)
    plane_distance = abs(sum((p[k] - a[k]) * normal[k] for k in range(3))) / length
    return weights, plane_distance


def actual_group_program(material, expected):
    """Read saved node operations/constants/links instead of trusting launcher logs."""
    groups = [node for node in material.node_tree.nodes if node.type == "GROUP" and node.node_tree
              and node.node_tree.name == face.GROUP_NAME]
    if len(groups) != 1:
        raise ValueError("Saved material does not contain exactly one Z12 group")
    group, saved_operations = groups[0], []
    max_constant_error = 0.
    for name, kind, first, second in expected["operations"]:
        node = group.node_tree.nodes.get(name)
        if node is None or node.type != "MATH" or node.operation != kind or node.use_clamp:
            raise ValueError(f"Saved hood node differs: {name}")
        values = []
        for index, wanted in enumerate((first, second)):
            socket = node.inputs[index]
            if isinstance(wanted, str):
                if len(socket.links) != 1:
                    raise ValueError(f"Saved hood node has missing/ambiguous input: {name}:{index}")
                link = socket.links[0]
                if link.from_node.type == "SEPXYZ":
                    value = link.from_socket.name.lower()
                else:
                    value = link.from_node.name
                if value != wanted:
                    raise ValueError(f"Saved hood input link differs: {name}:{index}")
                values.append(value)
            else:
                if socket.links:
                    raise ValueError(f"Saved hood constant unexpectedly linked: {name}:{index}")
                value = float(socket.default_value)
                max_constant_error = max(max_constant_error, abs(value - wanted))
                values.append(value)
        saved_operations.append((name, kind, *values))

    def incoming(name):
        links = group.inputs[name].links
        if len(links) != 1:
            raise ValueError(f"Saved Z12 group {name} is not linked once")
        link = links[0]
        return {"node_type": link.from_node.type, "node_name": link.from_node.name,
                "socket": link.from_socket.name,
                "color_attribute": getattr(link.from_node, "layer_name", None)}

    position, underpaint = incoming("Position"), incoming("Underpaint")
    if position["node_type"] != "TEX_COORD" or position["socket"] != "Object":
        raise ValueError("Saved hood Position is not the expected Object coordinate")
    if underpaint["node_type"] != "VERTEX_COLOR" or underpaint["color_attribute"] != "PreviewColor":
        raise ValueError("Saved hood Underpaint is not PreviewColor")
    info = {"position_input": position, "underpaint_input": underpaint,
            "color_consumers": [(link.to_node.name, link.to_socket.name) for link in group.outputs["Color"].links],
            "math_nodes": len(saved_operations), "maximum_saved_float_constant_error": max_constant_error,
            "evaluation_note": "CPU float64 evaluation of actual saved constants/links; not a Cycles shader sample"}
    return {**expected, "operations": saved_operations}, info


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--step", type=int, choices=(1, 2, 4), default=1)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    source_dir, output = args.source_dir.resolve(strict=True), args.output.resolve()
    if output.exists() or output.suffix != ".json" or not output.is_relative_to(ROOT / "qa_shots/hero"):
        raise ValueError("Audit requires a fresh JSON path under qa_shots/hero")
    audit_path, blend = source_dir / "source_study_audit.json", source_dir / "hero_penguin_v12_source_proof.blend"
    audit = json.loads(audit_path.read_text())
    before = {str(path): sha(path) for path in (audit_path, blend)}
    if audit["study_profile"] != face.PROFILE or audit["outputs"][blend.name] != before[str(blend)]:
        raise ValueError("Saved source is not the hash-bound completed Z12 study")
    for name, wanted in audit["inputs"].items():
        if sha(name) != wanted:
            raise ValueError(f"Frozen source tool/material input changed: {name}")
    frames = {float(side): tuple(tuple(axis) for axis in value) for side, value in audit["continuous_paint_input"]["eye_frames"].items()}
    radii = tuple(audit["continuous_paint_input"]["eye_radii"])
    program = face.hood_program(frames, radii)
    if hashlib.sha256(json.dumps(program, sort_keys=True).encode()).hexdigest() != audit["continuous_paint_input"]["program_sha256"]:
        raise ValueError("Reconstructed frozen-frame hood program does not match saved audit")
    world, pose = front_pose(Path(audit["source_renderer"]))
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    scene, depsgraph = bpy.context.scene, bpy.context.evaluated_depsgraph_get()
    width = round(scene.render.resolution_x * scene.render.resolution_percentage / 100.)
    height = round(scene.render.resolution_y * scene.render.resolution_percentage / 100.)
    if (width, height) != (512, 640) or scene.camera.data.type != "ORTHO":
        raise ValueError("Expected unchanged 512x640 orthographic proof camera")
    projection = scene.camera.calc_matrix_camera(depsgraph, x=width, y=height,
                                               scale_x=scene.render.pixel_aspect_x, scale_y=scene.render.pixel_aspect_y)
    inverse_projection = projection.inverted()
    meshes, materials, rows, errors = {}, {}, [], []
    counts = defaultdict(Counter)
    mesh_diagnostics = {}
    requests = [(name, x, y) for name, (x0, x1, y0, y1) in REGIONS.items()
                for y in range(y0, y1 + 1, args.step) for x in range(x0, x1 + 1, args.step)]
    requests += [("control:" + name, x, y) for name, (x, y) in CONTROLS.items()]
    try:
        for region, x, y in requests:
            origin, direction, distance = pixel_ray(x, y, width, height, inverse_projection, world)
            hit, point, normal, polygon_index, obj, matrix = scene.ray_cast(depsgraph, origin, direction, distance=distance)
            row = {"region": region, "pixel": [x, y], "hit": hit}
            if not hit:
                counts[region]["MISS"] += 1
                rows.append(row)
                continue
            local = matrix.inverted() @ point
            key = obj.name_full
            if key not in meshes:
                evaluated = obj.evaluated_get(depsgraph)
                mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph)
                mesh.calc_loop_triangles()
                by_polygon = defaultdict(list)
                for triangle in mesh.loop_triangles:
                    by_polygon[triangle.polygon_index].append(triangle)
                meshes[key] = (evaluated, mesh, by_polygon)
                mesh_diagnostics[key] = {"vertices": len(mesh.vertices), "triangles": len(mesh.loop_triangles),
                                         "matrix_world": [vector(line) for line in matrix], "hide_render": obj.hide_render}
            _, mesh, triangles = meshes[key]
            polygon = mesh.polygons[polygon_index]
            material = mesh.materials[polygon.material_index] if polygon.material_index < len(mesh.materials) else None
            material_name = material.name_full if material else "NONE"
            counts[region][key + " | " + material_name] += 1
            row.update(object=key, material=material_name, polygon=polygon_index,
                       world_point=vector(point), local_point=vector(local), world_normal=vector(normal))
            if key.startswith("HeroBodyV12SmoothField"):
                try:
                    color = mesh.color_attributes.get("PreviewColor")
                    if color is None or color.domain != "POINT" or color.data_type != "FLOAT_COLOR":
                        raise ValueError("Body PreviewColor contract differs from FLOAT_COLOR POINT")
                    candidates = []
                    for triangle in triangles[polygon_index]:
                        positions = [mesh.vertices[index].co for index in triangle.vertices]
                        found = barycentric(local, positions)
                        if found and min(found[0]) >= -1e-4 and found[1] <= 2e-5:
                            candidates.append((found[1], triangle, found[0]))
                    if not candidates:
                        raise ValueError("Ray hit has no matching evaluated triangle within explicit barycentric/plane tolerances")
                    plane_distance, triangle, weights = min(candidates, key=lambda value: value[0])
                    sampled = tuple(sum(weights[k] * color.data[index].color[channel] for k, index in enumerate(triangle.vertices))
                                    for channel in range(4))
                    analytical, _ = face.prior.prior.body_paint(tuple(local), lambda side: frames[side])
                    hood = face.evaluate_program(program, tuple(local))
                    final = face.composite_underpaint(sampled, hood)
                    exact = face.composite_underpaint(analytical, hood)
                    if material_name not in materials:
                        actual, info = actual_group_program(material, program)
                        materials[material_name] = (actual, info)
                    actual_program, _ = materials[material_name]
                    saved_hood = face.evaluate_program(actual_program, tuple(local))
                    row["body_paint"] = {"triangle": triangle.index, "vertices": list(triangle.vertices),
                        "barycentric": weights, "plane_distance_m": plane_distance,
                        "interpolated_PreviewColor": sampled, "analytic_Z10_underpaint": analytical,
                        "underpaint_max_abs_error": max(abs(a - b) for a, b in zip(sampled, analytical)),
                        "continuous_Z11_hood": hood, "saved_node_constant_hood": saved_hood,
                        "hood_constant_precision_difference": saved_hood - hood,
                        "reconstructed_Z12_pre_feather_rgb": final, "analytic_Z11_pre_feather_rgb": exact,
                        "remaining_pre_feather_max_abs_error": max(abs(a - b) for a, b in zip(final, exact)),
                        "scope": "Linear pigment only; lighting/normal/feather maps intentionally excluded"}
                except Exception as error:
                    row["body_audit_error"] = str(error)
                    errors.append({"pixel": [x, y], "error": str(error)})
            rows.append(row)
    finally:
        for evaluated, _, _ in meshes.values():
            evaluated.to_mesh_clear()
    after = {str(path): sha(path) for path in (audit_path, blend)}
    if before != after:
        raise RuntimeError("Read-only audit source hashes changed")
    body_rows = [row["body_paint"] for row in rows if "body_paint" in row]
    result = {"schema_version": 1, "source": before, "audit_script_sha256": sha(__file__),
              "read_only_source_hashes_unchanged": True, "rendered": False, "saved_blend": False,
              "visual_approval": False, "front_pose_from_frozen_renderer": pose,
              "projection": [vector(line) for line in projection], "width": width, "height": height,
              "pixel_centers": True, "pixel_origin": "top-left", "step": args.step,
              "regions": REGIONS, "controls": CONTROLS, "hit_counts": dict(counts),
              "material_graphs": {name: info for name, (_, info) in materials.items()},
              "meshes": mesh_diagnostics, "errors": errors,
              "summary": {"rays": len(rows), "body_samples": len(body_rows),
                          "maximum_underpaint_error": max((r["underpaint_max_abs_error"] for r in body_rows), default=0.),
                          "maximum_remaining_pigment_error": max((r["remaining_pre_feather_max_abs_error"] for r in body_rows), default=0.)},
              "rays": rows}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, sort_keys=True, allow_nan=False) + "\n")
    print(json.dumps({"output": str(output), "summary": result["summary"], "body_errors": len(errors),
                      "source_unchanged": True, "visual_approval": False}, sort_keys=True))
    if errors:
        raise RuntimeError(f"Saved source audit retained {len(errors)} body-sample errors; inspect JSON")


if __name__ == "__main__":
    main()
