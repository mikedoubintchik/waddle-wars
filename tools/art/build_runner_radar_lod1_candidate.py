#!/usr/bin/env python3
"""QA-only, component-preserving radar LOD1 authoring with pinned Blender 5.2.0.

Imports the existing DAY builder read-only. No decimation, component pruning,
new material, triangle-floor padding, live export, or catalog mutation. Host mode
builds twice in independent Blender processes and validates both actual GLBs.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import importlib.util
import inspect
import json
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/art"))
BUILDER = ROOT / "art_src/runner/day/generate_day_kit.py"
EXPORTER = ROOT / "tools/art/blender_export.py"
LIVE = ROOT / "assets/art/runner/day/runner_day_radar_landmark_v1.glb"
TEXTURES = ROOT / "assets/art/runner/day/textures"
MATERIAL = ROOT / "assets/art/runner/day/materials/runner_day_shell_v1.tres"
ASSET_ID = "runner_day_radar_landmark_v1"
CANDIDATE = "runner_day_radar_landmark_lod1_candidate.glb"
VERSION = (5, 2, 0)
POSITION_QUANTUM = 1e-6
REGION_BOUNDS_TOLERANCE = 1e-5
MIN_REGION_AREA_RATIO = 0.90
ALLOWED_PARAMETERS = {
    "box": {"segments"},
    "cylinder": {"vertices", "bevel"},
    "sphere": {"segments", "rings"},
    "torus": {"major_segments", "minor_segments"},
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def safe_output(value):
    output = Path(value).resolve()
    qa = (ROOT / "qa_shots/runner").resolve()
    require(output.is_relative_to(qa) and output != qa,
            "output must be a child of qa_shots/runner, never a live asset path")
    return output


def candidate_parameters(kind, name, parameters):
    """Only subdivision/bevel resolution changes; shape/color inputs untouched."""
    require(kind in ALLOWED_PARAMETERS, f"unsupported primitive {kind}")
    result = dict(parameters)
    if kind == "box":
        result["segments"] = min(parameters["segments"],
                                 3 if name == "operations_block" else
                                 2 if name == "foundation" else 1)
    elif kind == "cylinder":
        result["vertices"] = min(parameters["vertices"], 20 if name == "tower" else 8)
        # Tiny poles retain their full radius/depth and end caps; rolled rim
        # subdivisions are not useful at this LOD's intended screen footprint.
        if name.startswith("perimeter_beacon_"):
            result["bevel"] = 0.0
    elif kind == "sphere":
        result["segments"] = min(parameters["segments"], 32 if name == "radome" else 8)
        result["rings"] = min(parameters["rings"], 16 if name == "radome" else 4)
    elif kind == "torus":
        result["major_segments"] = min(parameters["major_segments"],
                                       32 if name.startswith("radome_band_") else
                                       24 if name.startswith("tower_ring_") else 12)
        # Keep six-sided tube cross sections. Four sides lost >10% of thin
        # band area after preserving its original support bounds in trial02.
        result["minor_segments"] = min(parameters["minor_segments"], 6)
    require(set(result) == set(parameters), "primitive parameter keys changed")
    changed = {key for key in result if result[key] != parameters[key]}
    require(changed <= ALLOWED_PARAMETERS[kind], f"shape parameters changed: {changed}")
    return result


def oriented_key(triangle):
    require(len(triangle) == 3, "require triangle")
    corners = []
    for point in triangle:
        require(len(point) == 3 and all(math.isfinite(v) for v in point),
                "non-finite triangle position")
        corners.append(tuple(round(value / POSITION_QUANTUM) for value in point))
    corners = tuple(corners)
    return min(corners, corners[1:] + corners[:1], corners[2:] + corners[:2])


def fit_component_points(points, target_min, target_max):
    """Keep measured component support when a coarser bevel/ring samples it differently.

    This is a documented local authoring operation, not a relaxed bounds gate.
    The final Blender and actual-export bounds are checked separately afterward.
    """
    require(points and len(target_min) == len(target_max) == 3, "missing component bounds")
    minimum = [min(point[i] for point in points) for i in range(3)]
    maximum = [max(point[i] for point in points) for i in range(3)]
    require(all(maximum[i] > minimum[i] and target_max[i] > target_min[i] for i in range(3)),
            "cannot fit a degenerate component")
    scales = [(target_max[i] - target_min[i]) / (maximum[i] - minimum[i]) for i in range(3)]
    require(all(0.80 <= scale <= 1.20 for scale in scales),
            f"component support fit exceeds bounded correction: {scales}")
    fitted = [tuple(target_min[i] + (point[i] - minimum[i]) * scales[i] for i in range(3))
              for point in points]
    return fitted, scales


def validate_regions(baseline, candidate):
    require(set(baseline) == set(candidate), "named components were lost or added")
    records = []
    for name in sorted(baseline):
        before, after = baseline[name], candidate[name]
        require(after["triangles"] > 0, f"component has no triangles: {name}")
        error = max(abs(a - b) for field in ("bounds_min", "bounds_max")
                    for a, b in zip(before[field], after[field]))
        require(error <= REGION_BOUNDS_TOLERANCE,
                f"component bounds changed: {name} delta={error}")
        area_ratio = after["area"] / before["area"]
        require(MIN_REGION_AREA_RATIO <= area_ratio <= 1.10,
                f"component area collapsed or grew: {name} ratio={area_ratio}")
        records.append({"name": name, "baseline_triangles": before["triangles"],
                        "candidate_triangles": after["triangles"],
                        "max_bounds_delta_m": error, "surface_area_ratio": area_ratio,
                        "bounds_min_blender": after["bounds_min"],
                        "bounds_max_blender": after["bounds_max"]})
    return records


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def read_geometry(path):
    # Strict existing reader rejects unsupported formats/extensions.
    from audit_hero_v12_atlas_export import Glb
    glb = Glb(path)
    require(len(glb.nodes) == 1 and glb.nodes[0].get("mesh") == 0,
            "candidate must contain one untransformed mesh node")
    require(not any(key in glb.nodes[0] for key in ("matrix", "translation", "rotation", "scale")),
            "unexpected exported root transform")
    require(len(glb.doc["meshes"]) == 1, "require single mesh")
    primitives = glb.doc["meshes"][0]["primitives"]
    require(len(primitives) == 1 and primitives[0].get("mode", 4) == 4,
            "require one triangle surface")
    primitive = primitives[0]
    require({"POSITION", "NORMAL", "TANGENT", "TEXCOORD_0", "COLOR_0"}
            <= set(primitive["attributes"]), "missing shared atlas attributes")
    positions = glb.accessor(primitive["attributes"]["POSITION"], "VEC3", {5126})
    indices = [row[0] for row in glb.accessor(primitive["indices"], "SCALAR", {5121, 5123, 5125})]
    require(len(indices) % 3 == 0 and all(0 <= i < len(positions) for i in indices),
            "invalid triangle indices")
    triangles = Counter(oriented_key([positions[i] for i in indices[j:j + 3]])
                        for j in range(0, len(indices), 3))
    bounds = {"min": [min(p[i] for p in positions) for i in range(3)],
              "max": [max(p[i] for p in positions) for i in range(3)]}
    return glb, triangles, bounds


def canonical_index_order(indices):
    require(len(indices) % 3 == 0 and all(isinstance(i, int) and i >= 0 for i in indices),
            "canonical ordering requires nonnegative triangle indices")
    triangles = []
    for start in range(0, len(indices), 3):
        face = tuple(indices[start:start + 3])
        triangles.append(min(face, face[1:] + face[:1], face[2:] + face[:2]))
    return [index for face in sorted(triangles) for index in face]


def canonical_face_records(records):
    """Stable oriented face/paired-corner order before normal/tangent sums."""
    result = []
    for indices, smooth, colors in records:
        require(len(indices) == len(colors) == 3, "require paired triangle corners")
        rotations = [(tuple(indices[i:] + indices[:i]), bool(smooth), tuple(colors[i:] + colors[:i]))
                     for i in range(3)]
        result.append(min(rotations))
    return sorted(result)


def canonicalize_export_indices(path):
    """Stabilize triangle order only; keep all vertex payloads byte-exact.

    Trial04's two raw exports had identical JSON and every vertex attribute;
    only triangle order differed. Opaque single-surface geometry does not rely
    on draw order. Sorting preserves every triangle, multiplicity and winding.
    """
    glb, before, bounds = read_geometry(path)
    primitive = glb.doc["meshes"][0]["primitives"][0]
    accessor = glb.doc["accessors"][primitive["indices"]]
    view = glb.doc["bufferViews"][accessor["bufferView"]]
    require("sparse" not in accessor and "byteStride" not in view, "unsupported index storage")
    component = accessor["componentType"]
    fmt = {5121: "B", 5123: "H", 5125: "I"}[component]
    indices = [row[0] for row in glb.accessor(primitive["indices"])]
    raw = bytearray(path.read_bytes())
    json_length = struct.unpack_from("<I", raw, 12)[0]
    start = 12 + 8 + json_length + 8 + view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    index_bytes = len(indices) * struct.calcsize(fmt)
    require(start + index_bytes <= len(raw), "index payload out of bounds")
    for i, index in enumerate(canonical_index_order(indices)):
        struct.pack_into("<" + fmt, raw, start + i * struct.calcsize(fmt), index)
    path.write_bytes(raw)
    after_glb, after, after_bounds = read_geometry(path)
    require(before == after and bounds == after_bounds, "canonical ordering changed oriented geometry")
    for name, ai in primitive["attributes"].items():
        require(glb.accessor(ai) == after_glb.accessor(ai), f"canonical ordering changed {name}")


def fingerprint():
    inputs = [Path(__file__).resolve(), BUILDER, EXPORTER, LIVE, MATERIAL,
              MATERIAL.with_suffix(".gdshader")]
    inputs += [TEXTURES / f"runner_day_surface_{role}_v1.png"
               for role in ("albedo", "normal", "orm")]
    return {str(path.relative_to(ROOT)): sha256(path) for path in inputs}


def build_worker(output):
    import bpy
    from mathutils import Vector
    require(bpy.app.version[:3] == VERSION, f"expected Blender {VERSION}, found {bpy.app.version[:3]}")
    builder = load_module("radar_readonly_day_builder", BUILDER)
    exporter = load_module("radar_readonly_exporter", EXPORTER)
    original_functions = {kind: getattr(builder, kind) for kind in ALLOWED_PARAMETERS}

    def assemble_candidate(coll, objects, shift):
        # Blender join + keep_custom_normals gave repeat-dependent triangle
        # ordering and seven tiny corner-normal differences in trial03. Build
        # the same triangles in explicit name/face order instead. Candidate
        # normals derive from its own authored smooth/flat faces, not encoded
        # pre-simplification corner normals. No quantization of shading data.
        positions, records = [], []
        for obj in objects:
            offset = len(positions)
            positions.extend(tuple(vertex.co + shift) for vertex in obj.data.vertices)
            attribute = obj.data.color_attributes["Color"]
            for polygon in obj.data.polygons:
                require(len(polygon.vertices) == 3, "candidate component was not triangulated")
                records.append(([offset + index for index in polygon.vertices], polygon.use_smooth,
                                [tuple(attribute.data[index].color) for index in polygon.loop_indices]))
        records = canonical_face_records(records)
        faces = [record[0] for record in records]
        smooth = [record[1] for record in records]
        colors = [color for record in records for color in record[2]]
        for obj in objects:
            bpy.data.objects.remove(obj, do_unlink=True)
        mesh = bpy.data.meshes.new("radar_component_ordered_mesh")
        mesh.from_pydata(positions, [], faces)
        mesh.update()
        for polygon, use_smooth in zip(mesh.polygons, smooth):
            polygon.use_smooth = use_smooth
        attribute = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
        mesh.color_attributes.active_color = attribute
        for item, color in zip(attribute.data, colors):
            item.color = color
        mesh.materials.append(builder.material())
        builder.assign_atlas_uv(mesh)
        obj = bpy.data.objects.new(ASSET_ID, mesh)
        coll.objects.link(obj)
        return obj

    def build(limited, baseline_regions=None):
        builder.reset(TEXTURES)
        bpy.context.scene.render.threads_mode = "FIXED"
        bpy.context.scene.render.threads = 2
        calls = []
        for kind, original in original_functions.items():
            def wrapper(*args, _kind=kind, _original=original, **kwargs):
                bound = inspect.signature(_original).bind(*args, **kwargs)
                bound.apply_defaults()
                values = dict(bound.arguments)
                name = values["name"]
                chosen = candidate_parameters(_kind, name, values) if limited else values
                call = {"kind": _kind, "name": name,
                        "changed_parameters": {key: {"before": values[key], "after": chosen[key]}
                                               for key in values if values[key] != chosen[key]}}
                obj = _original(**chosen)
                if limited:
                    require(name in baseline_regions, f"unexpected component: {name}")
                    # Beams call box before their rotation. They keep the same
                    # one-segment geometry, so fit only after final transforms
                    # in the per-object pass below.
                calls.append(call)
                return obj
            setattr(builder, kind, wrapper)
        coll = builder.build_radar_landmark()
        objects = sorted(coll.objects, key=lambda obj: obj.name)
        require(all(obj.type == "MESH" for obj in objects), "unexpected nonmesh region")
        require(len({obj.name for obj in objects}) == len(objects), "duplicate region names")
        metrics, triangles = {}, {}
        for obj in objects:
            if limited:
                reference = baseline_regions[obj.name]
                points = [tuple(vertex.co) for vertex in obj.data.vertices]
                fitted, scales = fit_component_points(points, reference["bounds_min"], reference["bounds_max"])
                for vertex, point in zip(obj.data.vertices, fitted):
                    vertex.co = point
                obj.data.update()
                call = next(row for row in calls if row["name"] == obj.name)
                call["measured_support_fit_axis_scale"] = scales
                call["max_support_fit_vertex_displacement_m"] = max(
                    math.dist(before, after) for before, after in zip(points, fitted))
            # Fix triangulation before joining so per-region export checks do
            # not depend on an n-gon diagonal being picked a second time.
            bpy.context.view_layer.objects.active = obj
            modifier = obj.modifiers.new("qa_region_triangles", "TRIANGULATE")
            modifier.keep_custom_normals = not limited
            if limited:
                modifier.quad_method = "FIXED"
                modifier.ngon_method = "CLIP"
            bpy.ops.object.modifier_apply(modifier=modifier.name)
            obj.data.calc_loop_triangles()
            points = [tuple(obj.matrix_world @ vertex.co) for vertex in obj.data.vertices]
            metrics[obj.name] = {
                "triangles": len(obj.data.loop_triangles),
                "area": sum(float(tri.area) for tri in obj.data.loop_triangles),
                "bounds_min": [min(point[i] for point in points) for i in range(3)],
                "bounds_max": [max(point[i] for point in points) for i in range(3)],
            }
            triangles[obj.name] = [[points[i] for i in tri.vertices] for tri in obj.data.loop_triangles]
        if limited:
            # Preserve named, editable components in the QA source. No source
            # .blend, production resource, or manifest is written by this tool.
            bpy.context.scene["qa_only"] = True
            bpy.context.scene["qa_lod_policy"] = "component_preserving_no_floor_padding"
            bpy.ops.wm.save_as_mainfile(filepath=str(output / "radar_lod1_source.blend"), check_existing=False)
        minimum = [min(row["bounds_min"][i] for row in metrics.values()) for i in range(3)]
        maximum = [max(row["bounds_max"][i] for row in metrics.values()) for i in range(3)]
        shift = Vector((-(minimum[0] + maximum[0]) * 0.5,
                        -(minimum[1] + maximum[1]) * 0.5, -minimum[2]))
        expected = {}
        for name, faces in triangles.items():
            counter = Counter()
            for face in faces:
                transformed = []
                for point in face:
                    p = Vector(point) + shift
                    transformed.append((p.x, p.z, -p.y))
                counter[oriented_key(transformed)] += 1
            expected[name] = counter
        if limited:
            assemble_candidate(coll, objects, shift)
        else:
            builder.finalize(coll)
        # No add_review_details / LOD0 floor call on either path.
        objects = exporter.collection_objects(ASSET_ID)
        exporter.validate_transforms(objects)
        exporter.validate_modifiers(objects)
        exporter.select_only(objects)
        destination = output / (CANDIDATE if limited else "source_baseline.glb")
        bpy.ops.export_scene.gltf(**exporter.exporter_kwargs(destination, False))
        if limited:
            canonicalize_export_indices(destination)
        glb, exported, bounds = read_geometry(destination)
        union = Counter()
        for counter in expected.values():
            union.update(counter)
        require(exported == union, "actual export lost/reversed/changed region triangles")
        return metrics, calls, expected, glb, exported, bounds

    baseline, _, _, baseline_glb, baseline_faces, baseline_bounds = build(False)
    live_glb, live_faces, live_bounds = read_geometry(LIVE)
    require(baseline_faces == live_faces and baseline_bounds == live_bounds,
            "current builder no longer reproduces live radar oriented positions/bounds; stop for review")
    candidate, calls, expected, candidate_glb, candidate_faces, candidate_bounds = build(True, baseline)
    records = validate_regions(baseline, candidate)
    require(candidate_bounds == live_bounds, "global grounded bounds changed")
    require(sum(candidate_faces.values()) < sum(live_faces.values()), "candidate did not reduce triangles")
    for record in records:
        counter = expected[record["name"]]
        record["exported_region_triangles_retained"] = sum(counter.values())
        record["oriented_position_multiset_sha256"] = hashlib.sha256(
            repr(sorted(counter.items())).encode()).hexdigest()
    report = {
        "schema_version": 1, "qa_only": True, "production_ready": False,
        "blender": bpy.app.version_string, "threads": 2,
        "candidate_file": CANDIDATE, "candidate_sha256": candidate_glb.sha256,
        "live_glb_sha256": live_glb.sha256, "regenerated_baseline_sha256": baseline_glb.sha256,
        "live_geometry_anchor": "Regenerated source and current live GLB oriented POSITION triangle multisets + exact global bounds match; other vertex attributes not compared.",
        "position_quantum_m": POSITION_QUANTUM,
        "triangles": {"live_lod0": sum(live_faces.values()), "candidate": sum(candidate_faces.values())},
        "authoring_target_triangles": [5000, 8000],
        "within_authoring_target": 5000 <= sum(candidate_faces.values()) <= 8000,
        "bounds_gltf": candidate_bounds, "global_bounds_exact": True,
        "region_count": len(records), "regions": records, "primitive_changes": calls,
        "region_proof": "Every named pre-join component retains bounds and >=90% surface area. Union of candidate oriented region triangle positions equals actual single-surface GLB after grounded pivot/+Y glTF conversion. No semantic region was pruned; this does not prove equal rendered quality.",
        "support_fit": "After reducing subdivisions, component vertices are axis-fitted to original measured support bounds. This compensates changed bevel/ring extremum sampling; scales limited to0.80–1.20 and exact final bounds independently checked. Per-component scale/displacement retained in primitive_changes.",
        "deterministic_assembly": "Candidate triangulates with FIXED quads/CLIP ngons, concatenates named components and canonical oriented faces/corner-colors before normal/tangent calculation. Recalculates candidate face/smooth normals and uses Blender's original Mikk tangents. Post-export canonical index ordering preserves oriented triangles and every vertex attribute exactly. No unstable Blender object.join or encoded pre-simplification corner normals; no rounding/reconstruction of exported tangent attributes.",
        "material_contract": {"surface_count": 1, "source_material": "day_kit_vertex_paint",
                              "runtime_override": str(MATERIAL.relative_to(ROOT)),
                              "same_existing_atlas": True,
                              "export_mode": "PLACEHOLDER (same as existing DAY GLBs); no embedded texture/material payload"},
        "qa_import_contract": {"meshes/generate_lods": False,
                               "require_actual_imported_lod_count": 0,
                               "status": "NOT_YET_IMPORTED; capture harness must set and verify before rendering"},
        "omissions": ["No engine import, visual acceptance, FPS, GPU-time, collision or runtime selection policy proof.",
                      "Component AABBs/area and export membership are guards, not a screen-space silhouette equivalence test.",
                      "POSITION comparison quantized at 1e-6 m; normals, tangents, UVs and colors are not baseline-parity assertions."],
    }
    (output / "authoring_report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"[radar-lod1] {report['triangles']} regions={len(records)} all retained")


def host(output, blender):
    require(not output.exists(), "output exists; use a fresh QA child directory")
    output.mkdir(parents=True)
    repeat = output / "determinism_repeat"
    repeat.mkdir()
    inputs = fingerprint()
    environment = dict(os.environ, LC_ALL="C", LANG="C", PYTHONHASHSEED="0", TZ="UTC")
    reports = []
    for directory in (output, repeat):
        command = [str(blender), "--background", "--factory-startup", "--disable-autoexec",
                   "--threads", "2", "--python-exit-code", "1", "--python", str(Path(__file__).resolve()),
                   "--", "--worker", "--output", str(directory)]
        result = subprocess.run(command, cwd=ROOT, env=environment, text=True, capture_output=True)
        (directory / "blender.stdout").write_text(result.stdout)
        (directory / "blender.stderr").write_text(result.stderr)
        require(result.returncode == 0, f"Blender failed {result.returncode}; inspect {directory}")
        require(not result.stderr.strip(), f"Blender stderr not clean; inspect {directory}")
        reports.append(json.loads((directory / "authoring_report.json").read_text()))
        validation = subprocess.run([shutil.which("node") or "node", str(ROOT / "tools/art/validate_glb.mjs"),
                                     str(directory / CANDIDATE)], cwd=ROOT, text=True, capture_output=True)
        (directory / "khronos.stdout").write_text(validation.stdout)
        (directory / "khronos.stderr").write_text(validation.stderr)
        require(validation.returncode == 0 and not validation.stderr.strip(),
                f"Khronos validation failed; inspect {directory}")
    require(reports[0]["candidate_sha256"] == reports[1]["candidate_sha256"],
            "independent Blender rebuild changed actual candidate GLB bytes")
    require(inputs == fingerprint(), "task inputs changed during build; do not use mixed provenance")
    result = {"qa_only": True, "production_ready": False, "input_sha256": inputs,
              "candidate_sha256": reports[0]["candidate_sha256"],
              "independent_rebuild_byte_identical": True,
              "khronos": "Both actual candidate GLBs: errors=0 warnings=0; see logs",
              "authoring_report": "authoring_report.json", "engine_import_verified": False,
              "visual_quality_approved": False, "runtime_changed": False}
    (output / "build_report.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result, indent=2))


def main():
    raw = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--worker", action="store_true")
    parser.add_argument("--blender", default=shutil.which("blender") or "/opt/homebrew/bin/blender")
    args = parser.parse_args(raw)
    output = safe_output(args.output)
    if args.worker:
        require(output.is_dir(), "host must create QA output first")
        build_worker(output)
    else:
        host(output, Path(args.blender).resolve())


if __name__ == "__main__":
    main()
