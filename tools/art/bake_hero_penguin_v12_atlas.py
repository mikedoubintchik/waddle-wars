#!/usr/bin/env python3
"""CPU-only, quarantined unique-UV/high-to-low V12 atlas authoring.

Saved sculpt and rigged candidate are immutable inputs. No production path,
approval flag, geometry, skin, action, or species shape is changed. Run with
Blender 5.2.0; generated GLBs and atlases are self-contained QA candidates.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import shutil
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL_SHA256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
QA_ROOT = ROOT / "qa_shots/hero"
ATLAS_UV = "HeroAtlasUV"
PALETTE = {"dorsal": (0.017, 0.027, 0.040), "ventral": (0.76, 0.665, 0.490),
           "gold": (0.63, 0.270, 0.037), "identity": (0.065, 0.34, 0.38)}
# UV area per unit of physical surface area. Pack all charts jointly after
# weighting, so many small toe/eye islands cannot overflow a fixed rectangle.
UV_WEIGHTS = {"face": 4.0, "head_back": 1.5, "torso": 1.0, "wing": 1.2, "foot": 0.9, "tail": 0.7}
MAP_NAMES = ("albedo", "normal", "orm", "masks")
MOUTH_SCRATCH_NORMAL_LIMIT_DEGREES = 0.1
# Recorded geometry recipes, not the candidate CLI's evolving default. Frozen
# M audits predate this field and must retain the original reduction exactly.
UNIFIED_GEOMETRY_POLICY = "unified-face-r2-v1"
UNIFIED_RETOPO_POLICY = "unified-retopo-r2-v1"
UNIFIED_GEOMETRY_POLICIES = (UNIFIED_GEOMETRY_POLICY, UNIFIED_RETOPO_POLICY)
UNIFIED_PROFILE = "unified-juvenile-face"
UNIFIED_GROUP = "JuvenileFace_ContinuousPigment_SourceOnly"
CONTINUOUS_MASK_CONTRACT = "R=ventral,G=gold,B=identity-cyan,A=feather(1); exclusive exact analytic compositing weights"
REPLAY_GEOMETRY_POLICIES = ("legacy", "source-cover-v1", "source-cover-v2", *UNIFIED_GEOMETRY_POLICIES)


class UVOverlapError(RuntimeError):
    def __init__(self, pairs, maximum):
        self.faces = sorted({face for pair in pairs for face in pair})
        super().__init__(f"UV overlaps in polygons {pairs}; maximum area {maximum}")


LIMITATIONS = [
    "QA-only; the explicitly bound source shape, component-aware reduction and canonical rig fit are unchanged.",
    "Source feather normals are derived review maps, not scanned or hand-sculpted individual feathers.",
    "Cycles sheen, subsurface response and lighting are not included in the standard glTF PBR approximation.",
    "Albedo retains the original source pigment; masks support palette ratios, not new species marking designs.",
    "Eight species shapes and 23 clips are preserved, not newly approved in motion or with cosmetics.",
    "Unique per-LOD atlases are QA evidence; production should consider a shared atlas to reduce memory.",
    "No runner/browser/mobile performance acceptance or full-app premium approval is implied.",
]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def candidate_geometry_policy(audit: dict) -> str:
    """Resolve only supported, explicitly versioned candidate replay recipes."""
    if not isinstance(audit, dict):
        raise RuntimeError("candidate audit must be an object")
    policy = audit["geometry_policy"] if "geometry_policy" in audit else "legacy"
    if not isinstance(policy, str) or policy not in REPLAY_GEOMETRY_POLICIES:
        raise RuntimeError(f"unsupported candidate geometry_policy for exact replay: {policy!r}")
    binding = audit.get("source_study_binding")
    unified = isinstance(binding, dict) and binding.get("study_profile") == UNIFIED_PROFILE
    if (policy in UNIFIED_GEOMETRY_POLICIES) != unified:
        raise RuntimeError("candidate geometry_policy does not match its immutable unified source binding")
    return policy


def projection_gate(missing_pixels: int, *, rejection_hash=None):
    """Rejected diagnostic exports cannot accidentally acquire a passing gate."""
    if type(missing_pixels) is not int or missing_pixels < 0:
        raise ValueError("projection miss count must be a nonnegative integer")
    gate = {"passed": missing_pixels == 0, "missing_pixels": missing_pixels}
    if rejection_hash is not None:
        if missing_pixels == 0 or len(rejection_hash) != 64 or any(c not in "0123456789abcdef" for c in rejection_hash):
            raise ValueError("rejected review requires positive misses and exact rejection SHA256")
        gate["source_rejection_sha256"] = rejection_hash
    return gate


def png_storage(path: Path):
    header = path.read_bytes()[:29]
    if len(header) != 29 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError("atlas output is not a PNG with IHDR")
    width, height, depth, color_type = struct.unpack_from(">IIBB", header, 16)
    return {"width": width, "height": height, "channel_bits": depth,
            "png_color_type": color_type, "file_bytes": path.stat().st_size}


def scratch_normal_roundtrip(expected, actual):
    if len(expected) != len(actual) or not expected:
        raise ValueError("scratch normal audit needs complete matching corner arrays")
    errors = []
    for first, second in zip(expected, actual):
        cross_product = (first[1] * second[2] - first[2] * second[1],
                         first[2] * second[0] - first[0] * second[2],
                         first[0] * second[1] - first[1] * second[0])
        cross_length = math.sqrt(sum(value * value for value in cross_product))
        dot = sum(a * b for a, b in zip(first, second))
        if sum(value * value for value in first) < 0.5 or sum(value * value for value in second) < 0.5:
            raise RuntimeError("invalid zero/nonunit scratch normal")
        errors.append(math.degrees(math.atan2(cross_length, dot)))
    audit = {"maximum_degrees": max(errors), "rms_degrees": math.sqrt(sum(e * e for e in errors) / len(errors)),
             "limit_degrees": MOUTH_SCRATCH_NORMAL_LIMIT_DEGREES, "corners": len(errors),
             "exact": False, "scope": "QA-only mouth scratch target; final runtime normals unchanged"}
    if audit["maximum_degrees"] > MOUTH_SCRATCH_NORMAL_LIMIT_DEGREES:
        raise RuntimeError(f"scratch split-normal roundtrip exceeds explicit QA-only angular limit: {audit}")
    return audit


def safe_output(value: str) -> Path:
    path = Path(value).resolve()
    if path == QA_ROOT.resolve() or not path.is_relative_to(QA_ROOT.resolve()):
        raise ValueError("atlas output must be a dedicated qa_shots/hero child")
    if path.exists() and any(path.iterdir()):
        raise ValueError("preserve earlier evidence; atlas output must be empty")
    return path


def smoothstep(low: float, high: float, value: float) -> float:
    value = max(0.0, min(1.0, (value - low) / (high - low)))
    return value * value * (3.0 - 2.0 * value)


def analytic_masks(point, *, feather=True, waterline=0.0):
    """Exact M pigment construction, separated before compositing, not RGB inference."""
    if not feather:
        return 0.0, 0.0, 0.0, 0.0
    x, y, z = point
    front = -y / max(0.001, math.hypot(x, y))
    angle = abs(math.atan2(x, -y))
    def ellipse(cx, cz, rx, rz):
        return ((x - cx) / rx) ** 2 + ((z - cz) / rz) ** 2
    cheek = min(ellipse(-0.185, 1.375, 0.262, 0.172), ellipse(0.185, 1.375, 0.262, 0.172))
    chin, chest = ellipse(0, 1.225, 0.308, 0.244), ellipse(0, 0.768, 0.464, 0.698)
    orbit = min(ellipse(-0.202, 1.557, 0.132, 0.157), ellipse(0.202, 1.557, 0.132, 0.157))
    bib = (1 - smoothstep(0.94, 1.045, min(chest, chin))) * smoothstep(0.30, 0.39, front)
    face = (1 - smoothstep(0.94, 1.045, min(cheek, orbit))) * smoothstep(-0.02, 0.09, front)
    bridge = (1 - smoothstep(0.027, 0.050, abs(x))) * smoothstep(1.442 + 0.75 * abs(x), 1.470 + 0.75 * abs(x), z)
    cream = max(bib, face) * (1 - bridge)
    ear = 1 - smoothstep(0.86, 1.10, ((angle - 1.46) / 0.40) ** 2 + ((z - 1.411) / 0.078) ** 2)
    u = (angle - 1.52) / 0.45
    width = 0.015 * math.sqrt(max(0.0, 1 - u * u))
    stripe_z = 1.232 + 0.040 * (angle - 1.10) + 0.017 * math.sin((angle - 1.10) * 3.3)
    stripe = (1 - smoothstep(max(0.0, width - 0.003), width + 0.002, abs(z - stripe_z)))
    stripe *= 1 - smoothstep(0.91, 1, abs(u))
    return (cream * (1 - ear) * (1 - stripe) * (1 - waterline),
            ear * (1 - stripe) * (1 - waterline), stripe * (1 - waterline), 1.0)


def recompose(mask):
    r, g, b = mask[:3]
    return tuple(PALETTE["dorsal"][i] * (1 - r - g - b) + PALETTE["ventral"][i] * r
                 + PALETTE["gold"][i] * g + PALETTE["identity"][i] * b for i in range(3))


def wing_cream(ring: int, segment: int, thick_y: float) -> float:
    """Saved M's 45x48 parametric cream edge, from geometry rather than paint."""
    t, angle = ring / 44.0, math.tau * segment / 48
    return ((1 - smoothstep(-0.90, -0.58, math.cos(angle)))
            * smoothstep(0.14, 0.27, t) * (1 - smoothstep(0.84, 0.98, t))
            * smoothstep(0.0, 0.6, -thick_y * math.sin(angle)))


def uv_region(zone: str, center) -> str:
    if zone in {"eye", "bill", "brow"}:
        return "face"
    if zone == "body":
        return ("face" if center[1] > 0.02 else "head_back") if center[2] > 1.17 else "torso"
    if zone in {"foot", "toe"}:
        return "foot"
    if zone in {"wing", "tail"}:
        return zone
    raise ValueError(f"unclassified atlas component: {zone}")


def cross(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def triangle_overlap_area(first, second):
    """Positive-area triangle intersection; touching shared UV edges is legal."""
    clip = list(second) if cross(*second) >= 0 else list(reversed(second))
    polygon = list(first)
    for index in range(3):
        a, b = clip[index], clip[(index + 1) % 3]
        output = []
        for offset, p in enumerate(polygon):
            q = polygon[(offset + 1) % len(polygon)]
            dp, dq = cross(a, b, p), cross(a, b, q)
            if dp >= 0:
                output.append(p)
            if (dp >= 0) != (dq >= 0):
                factor = dp / (dp - dq)
                output.append((p[0] + (q[0] - p[0]) * factor, p[1] + (q[1] - p[1]) * factor))
        polygon = output
        if not polygon:
            return 0.0
    return abs(sum(polygon[i][0] * polygon[(i + 1) % len(polygon)][1]
                   - polygon[i][1] * polygon[(i + 1) % len(polygon)][0]
                   for i in range(len(polygon)))) * 0.5


def preservation_digest(obj):
    digest = hashlib.sha256()
    for vertex in obj.data.vertices:
        digest.update(struct.pack("<3f", *vertex.co))
        for group in vertex.groups:
            digest.update(struct.pack("<If", group.group, group.weight))
    for polygon in obj.data.polygons:
        digest.update(struct.pack("<" + "I" * len(polygon.vertices), *polygon.vertices))
        digest.update(bytes((int(polygon.use_smooth), polygon.material_index)))
    for key in obj.data.shape_keys.key_blocks:
        digest.update(key.name.encode())
        for vertex in key.data:
            digest.update(struct.pack("<3f", *vertex.co))
    return digest.hexdigest()


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def recover_components(mesh, sources, lod, audit, collection):
    """Replay the immutable adapter recipe solely to recover exact membership."""
    geometry_policy = candidate_geometry_policy(audit)
    replay_binding = audit.get("source_study_binding")
    if geometry_policy in UNIFIED_GEOMETRY_POLICIES:
        adapter.validate_geometry_binding(geometry_policy, replay_binding)
    if geometry_policy == UNIFIED_RETOPO_POLICY:
        # The saved membership and ordered geometry digest are authoritative.
        # Never rerun the retopology solver to reconstruct a frozen candidate.
        adapter.verify_retopology_helper(audit)
        return adapter.recover_stored_components(mesh, sources, lod, audit)
    lookup = {}
    for vertex in mesh.data.vertices:
        lookup.setdefault(struct.pack("<3f", *vertex.co), []).append(vertex.index)
    assigned = [-1] * len(mesh.data.vertices)
    records = [row for row in audit["components"] if row["lod"] == lod]
    offset = audit["lods"][lod]["sole_fit"]["constant_foot_toe_offset_z_m"]
    for component, source in enumerate(sources):
        print(f"[v12-atlas] LOD{lod} exact component replay {component + 1}/{len(sources)} {source.name}", flush=True)
        record = next(row for row in records if row["source"] == source.name)
        if geometry_policy == UNIFIED_GEOMETRY_POLICY and record["target"] != adapter.component_target(source.name, lod, geometry_policy):
            raise RuntimeError("unified replay target differs from its versioned component budget")
        kwargs = {"study_binding": replay_binding} if geometry_policy == UNIFIED_GEOMETRY_POLICY else {}
        reduced, _before, after = adapter.reduce_component(source, record["target"], collection,
                                                          geometry_policy=geometry_policy, **kwargs)
        if after != record["after"]:
            raise RuntimeError(f"reduction replay differs ({geometry_policy}): {source.name}")
        zone = adapter.component_spec(source.name)[0]
        for vertex in reduced.data.vertices:
            point = adapter.canonical_position(vertex.co)
            if zone in {"foot", "toe"}:
                point = point[0], point[1], point[2] + offset
            matches = lookup.get(struct.pack("<3f", *point), [])
            if len(matches) != 1 or assigned[matches[0]] != -1:
                raise RuntimeError(f"ambiguous or missing exact candidate membership ({geometry_policy}): {source.name}/{vertex.index}")
            assigned[matches[0]] = component
        bpy.data.objects.remove(reduced, do_unlink=True)
    if min(assigned) < 0:
        raise RuntimeError("component reconstruction did not cover every candidate vertex")
    faces = []
    for polygon in mesh.data.polygons:
        choices = {assigned[index] for index in polygon.vertices}
        if len(choices) != 1:
            raise RuntimeError("candidate face bridges separate source components")
        faces.append(choices.pop())
    return assigned, faces


def unwrap_unique(mesh, sources, face_components, size, gutter):
    import bmesh
    adapter.activate(mesh)
    uv = mesh.data.uv_layers.get(ATLAS_UV) or mesh.data.uv_layers.new(name=ATLAS_UV)
    mesh.data.uv_layers.active = uv
    uv.active_render = True
    regions = []
    for polygon, component in zip(mesh.data.polygons, face_components):
        center = sum((mesh.data.vertices[index].co for index in polygon.vertices), Vector()) / len(polygon.vertices)
        regions.append(uv_region(adapter.component_spec(sources[component].name)[0], center))
    counts = {}
    bpy.context.tool_settings.use_uv_select_sync = True
    bpy.context.tool_settings.mesh_select_mode = (False, False, True)
    for group_number, (group, importance) in enumerate(UV_WEIGHTS.items()):
        print(f"[v12-atlas] unwrap allocation {group}", flush=True)
        selected = [index for index, region in enumerate(regions) if region == group]
        if not selected:
            raise RuntimeError(f"empty expected UV allocation: {group}")
        bpy.ops.object.mode_set(mode="EDIT")
        edit = bmesh.from_edit_mesh(mesh.data)
        edit.faces.ensure_lookup_table()
        for face in edit.faces:
            face.select_set(regions[face.index] == group)
        edit.select_flush_mode()
        bmesh.update_edit_mesh(mesh.data, loop_triangles=False, destructive=False)
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.0,
                                 area_weight=0.0, correct_aspect=False, scale_to_bounds=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        uv = mesh.data.uv_layers[ATLAS_UV]
        mesh.data.calc_loop_triangles()
        uv_area = sum(abs(cross(*[tuple(uv.data[index].uv) for index in triangle.loops])) * 0.5
                      for triangle in mesh.data.loop_triangles if regions[triangle.polygon_index] == group)
        physical_area = sum(mesh.data.polygons[index].area for index in selected)
        factor = math.sqrt(physical_area * importance / max(1e-12, uv_area))
        for index in selected:
            for loop in mesh.data.polygons[index].loop_indices:
                u, v = uv.data[loop].uv
                uv.data[loop].uv = (u * factor + group_number * 10, v * factor)
        counts[group] = {"polygons": len(selected), "physical_area_m2": physical_area, "relative_texel_area": importance}
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(udim_source="ACTIVE_UDIM", rotate=True, rotate_method="ANY", scale=True,
                            merge_overlap=False, margin_method="FRACTION", margin=gutter / size, shape_method="CONCAVE")
    bpy.ops.object.mode_set(mode="OBJECT")
    # Shader UV must mean this atlas, not the preceding repeating review UV.
    for layer in list(mesh.data.uv_layers):
        if layer.name != ATLAS_UV:
            mesh.data.uv_layers.remove(layer)
    uv = mesh.data.uv_layers[ATLAS_UV]
    for group in UV_WEIGHTS:
        area = sum(abs(cross(*[tuple(uv.data[index].uv) for index in triangle.loops])) * 0.5
                   for triangle in mesh.data.loop_triangles if regions[triangle.polygon_index] == group)
        counts[group]["actual_uv_area"] = area
        counts[group]["interior_texel_area"] = area * size * size
    mesh.data.update()
    mesh.data.calc_tangents(uvmap=ATLAS_UV)
    if any(loop.tangent.length < 0.5 for loop in mesh.data.loops):
        raise RuntimeError("unique atlas produced invalid tangents; do not change geometry to hide this")
    return counts


def uv_audit(mesh, face_components, size):
    import numpy as np
    mesh.data.calc_loop_triangles()
    uv = mesh.data.uv_layers[ATLAS_UV]
    triangles = [[tuple(uv.data[index].uv) for index in triangle.loops] for triangle in mesh.data.loop_triangles]
    bins, checked = {}, set()
    overlaps, maximum = [], 0.0
    owner = np.full((size, size), -1, dtype=np.int32)
    area_sum = 0.0
    for index, points in enumerate(triangles):
        area = abs(cross(*points)) * 0.5
        if area < 1e-15:
            raise RuntimeError(f"degenerate UV triangle {index}")
        area_sum += area
        if any(not -1e-7 <= channel <= 1 + 1e-7 for point in points for channel in point):
            raise RuntimeError("UV outside unique atlas")
        lower = [min(point[axis] for point in points) for axis in range(2)]
        upper = [max(point[axis] for point in points) for axis in range(2)]
        for x in range(max(0, int(lower[0] * 64)), min(63, int(upper[0] * 64)) + 1):
            for y in range(max(0, int(lower[1] * 64)), min(63, int(upper[1] * 64)) + 1):
                bucket = bins.setdefault((x, y), [])
                for other in bucket:
                    pair = other, index
                    if pair in checked:
                        continue
                    checked.add(pair)
                    overlap = triangle_overlap_area(points, triangles[other])
                    maximum = max(maximum, overlap)
                    if overlap > 1e-12:
                        overlaps.append((mesh.data.loop_triangles[other].polygon_index,
                                         mesh.data.loop_triangles[index].polygon_index))
                bucket.append(index)
        # Pixel-center ownership is independent of bake alpha, used for ray
        # miss and feather alpha checks. Boundary pixels can belong to either
        # adjacent face in the same source component.
        x0, y0 = max(0, int(lower[0] * size)), max(0, int(lower[1] * size))
        x1, y1 = min(size, math.ceil(upper[0] * size)), min(size, math.ceil(upper[1] * size))
        xx, yy = np.meshgrid((np.arange(x0, x1) + 0.5) / size, (np.arange(y0, y1) + 0.5) / size)
        sign = 1 if cross(*points) > 0 else -1
        inside = np.ones(xx.shape, dtype=bool)
        for p, q in zip(points, points[1:] + points[:1]):
            inside &= sign * ((q[0] - p[0]) * (yy - p[1]) - (q[1] - p[1]) * (xx - p[0])) >= -1e-12
        component = face_components[mesh.data.loop_triangles[index].polygon_index]
        current = owner[y0:y1, x0:x1]
        if np.any(inside & (current >= 0) & (current != component)):
            raise RuntimeError("different source components overlap in atlas pixels")
        current[inside] = component
    if overlaps:
        raise UVOverlapError(overlaps, maximum)
    return owner, {"triangle_pairs_checked": len(checked), "overlap_pairs": len(overlaps),
                   "maximum_overlap_area": maximum, "occupied_uv_area": area_sum,
                   "interior_pixels": int((owner >= 0).sum()), "triangles": len(triangles)}


def compact_uv_triangle_staging(triangles):
    """Rigidly stage separate charts without far-origin float32 cancellation.

    Smallest charts go nearest U=0, outside the existing [0,1] atlas. Each
    longest edge lies on V=0, preserving even very small triangle altitudes.
    Only rotation/translation occurs; chart area and relative density do not
    change. Returned coordinates are the actual float32 values Blender stores.
    """
    charts = []
    for index, points in enumerate(triangles):
        if len(points) != 3 or any(len(point) != 2 or not all(map(math.isfinite, point)) for point in points):
            raise RuntimeError("fold chart staging requires three finite UV points")
        signed_area = cross(*points) * 0.5
        if abs(signed_area) < 1e-15:
            raise RuntimeError("degenerate UV triangle before fold staging")
        first, second = max(((0, 1), (1, 2), (2, 0)),
                            key=lambda pair: math.dist(points[pair[0]], points[pair[1]]))
        third = 3 - first - second
        length = math.dist(points[first], points[second])
        dx, dy = (points[second][axis] - points[first][axis] for axis in (0, 1))
        tx, ty = (points[third][axis] - points[first][axis] for axis in (0, 1))
        along = (tx * dx + ty * dy) / length
        altitude = (dx * ty - dy * tx) / length
        charts.append((length, index, first, second, third, along, altitude, signed_area))
    staged = [None] * len(charts)
    cursor = 0.0
    for length, index, first, second, third, along, altitude, signed_area in sorted(charts):
        # A chart-relative gap separates islands without a fixed translation
        # that would swallow the smallest charts in float32 ULPs.
        right = -(cursor + length * .125)
        left = right - length
        points = [None] * 3
        points[first], points[second], points[third] = (left, 0.0), (right, 0.0), (left + along, altitude)
        points = [struct.unpack("<2f", struct.pack("<2f", *point)) for point in points]
        stored_area = cross(*points) * 0.5
        if abs(stored_area) < 1e-15 or not math.isclose(stored_area, signed_area, rel_tol=1e-4, abs_tol=0.0):
            raise RuntimeError(f"float32 fold staging lost triangle area: chart {index}")
        staged[index] = points
        cursor += length * 1.125
    return staged


def detach_folded_uv_faces(mesh, faces, size, gutter):
    """Rechart proven folded triangles, never delete geometry or ignore overlap."""
    uv = mesh.data.uv_layers[ATLAS_UV]
    charts = []
    for index in faces:
        polygon = mesh.data.polygons[index]
        if len(polygon.vertices) != 3:
            raise RuntimeError("fold repair needs an explicit triangulated candidate")
        old = [tuple(uv.data[loop].uv) for loop in polygon.loop_indices]
        area = abs(cross(*old)) * 0.5
        origin, second, third = [mesh.data.vertices[vertex].co for vertex in polygon.vertices]
        tangent = (second - origin).normalized()
        across = polygon.normal.cross(tangent).normalized()
        points = [(0.0, 0.0), ((second - origin).length, 0.0),
                  ((third - origin).dot(tangent), (third - origin).dot(across))]
        factor = math.sqrt(area / max(1e-16, abs(cross(*points)) * 0.5))
        charts.append([(u * factor, v * factor) for u, v in points])
    for index, points in zip(faces, compact_uv_triangle_staging(charts)):
        for loop, point in zip(mesh.data.polygons[index].loop_indices, points):
            uv.data[loop].uv = point
    adapter.activate(mesh)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(udim_source="ACTIVE_UDIM", rotate=True, rotate_method="ANY", scale=True,
                            merge_overlap=False, margin_method="FRACTION", margin=gutter / size, shape_method="CONCAVE")
    bpy.ops.object.mode_set(mode="OBJECT")
    mesh.data.calc_tangents(uvmap=ATLAS_UV)
    if any(loop.tangent.length < 0.5 for loop in mesh.data.loops):
        raise RuntimeError("fold chart repair introduced invalid tangents")


def saved_semantic_values(source):
    """Read explicit source-authored weights; never reverse-engineer pigment.

    Legacy M has neither field nor contract and retains its exact analytic
    construction below. New sources store compositing weights before changing
    ivory gradients or lid pigment. Partial/malformed contracts fail closed.
    """
    contract = source.get("source_mask_contract")
    saved = source.data.color_attributes.get("SourceSemanticMasks")
    if contract is None and saved is None:
        return None
    if (contract != "feather-palette-weights-v1" or saved is None
            or saved.domain != "POINT" or saved.data_type != "FLOAT_COLOR"
            or len(saved.data) != len(source.data.vertices)):
        raise RuntimeError(f"invalid explicit source mask contract: {source.name}")
    values = [tuple(item.color) for item in saved.data]
    if any(len(value) != 4 or any(not math.isfinite(channel) or not 0 <= channel <= 1 for channel in value)
           or sum(value[:3]) > 1.0000001 or value[3] != 1.0 for value in values):
        raise RuntimeError(f"invalid source feather palette weights: {source.name}")
    return values


def continuous_body_group(source, material=None, *, reflected=False):
    """Recognize only the saved unified R2 shader; diagnostic fields are not it.

    The bound source hash validates the program itself. These checks validate
    its input/output wiring before a scratch copy, without executing sculpt or
    paint helpers and without changing the shared node group.
    """
    authority = source.get("source_pigment_authority")
    materials = source.data.materials
    material = material if material is not None else (materials[0] if len(materials) == 1 else None)
    marker = material.get("z13_continuous_body_pigment") if material is not None else None
    if authority != UNIFIED_GROUP + ": Color and SemanticMasks shading outputs" and marker != UNIFIED_PROFILE:
        return None
    if (not source.name.startswith("HeroBody") or len(materials) != 1
            or authority != UNIFIED_GROUP + ": Color and SemanticMasks shading outputs"
            or marker != UNIFIED_PROFILE or material.name.split(".", 1)[0] != UNIFIED_GROUP + "_FeatherMaterial"
            or not material.use_nodes or material.node_tree is None):
        raise RuntimeError("unified continuous pigment requires the exact body/material contract")
    nodes = material.node_tree.nodes
    instances = [node for node in nodes if node.type == "GROUP" and node.node_tree is not None
                 and node.node_tree.name.split(".", 1)[0] == UNIFIED_GROUP]
    if len(instances) != 1:
        raise RuntimeError("unified continuous pigment requires one recognized source group")
    instance = instances[0]
    group = instance.node_tree
    if group.get("semantic_mask_contract") != CONTINUOUS_MASK_CONTRACT:
        raise RuntimeError("unified continuous group has an unknown semantic contract")
    outputs = [node for node in group.nodes if node.type == "GROUP_OUTPUT" and node.is_active_output]
    if len(outputs) != 1:
        raise RuntimeError("unified continuous group requires one active output")
    output = outputs[0]
    for name in ("Color", "SemanticMasks"):
        edges = list(output.inputs[name].links)
        if (len(edges) != 1 or edges[0].from_node.type != "COMBINE_COLOR"
                or edges[0].from_node.mode != "RGB" or edges[0].from_socket.name != "Color"
                or {socket.name for socket in edges[0].from_node.inputs} != {"Red", "Green", "Blue"}):
            # ShaderNodeCombineColor has three RGB inputs, no alpha socket in
            # pinned Blender 5.2. Feather membership is independently one.
            raise RuntimeError("unified continuous outputs require the reviewed RGB combine")
    if output.inputs["FeatherRegion"].links or output.inputs["FeatherRegion"].default_value != 1.:
        raise RuntimeError("unified continuous FeatherRegion must remain explicitly one")
    if any(node.type == "VERTEX_COLOR" and node.layer_name == "PreviewColor" and node.outputs["Color"].links
           for node in nodes):
        raise RuntimeError("unified body still depends on diagnostic vertex pigment")
    position = list(instance.inputs["Position"].links)
    if len(position) != 1:
        raise RuntimeError("unified continuous pigment requires one Object-space Position input")
    edge = position[0]
    if reflected:
        correction = edge.from_node
        if (correction.type != "VECT_MATH" or correction.operation != "MULTIPLY"
                or edge.from_socket.name != "Vector" or correction.inputs[1].links
                or tuple(correction.inputs[1].default_value) != (1., -1., 1.)
                or material.get("atlas_source_coordinate_correction") != "reflect-Y-once-v1"):
            raise RuntimeError("canonical unified pigment lacks its scratch-only Y correction")
        incoming = list(correction.inputs[0].links)
        if len(incoming) != 1:
            raise RuntimeError("canonical unified pigment requires one original Object coordinate input")
        edge = incoming[0]
    if (edge.from_node.type != "TEX_COORD" or edge.from_socket.name != "Object"
            or getattr(edge.from_node, "object", None) is not None):
        raise RuntimeError("unified continuous pigment Position must use this source's Object coordinates")
    return material, instance


def canonical_continuous_material(source):
    recognized = continuous_body_group(source)
    if recognized is None:
        return None
    # The reviewed shader is source Object-space, not arbitrary world-space.
    # Reject transforms rather than silently assuming this reflection suffices.
    if any(abs(float(value) - (1. if row == column else 0.)) > 1e-8
           for row, values in enumerate(source.matrix_world) for column, value in enumerate(values)):
        raise RuntimeError("unified source Object-space shader requires its reviewed identity transform")
    original, _instance = recognized
    material = original.copy()
    _material, instance = continuous_body_group(source, material)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    previous = instance.inputs["Position"].links[0]
    origin = previous.from_socket
    links.remove(previous)
    correction = nodes.new("ShaderNodeVectorMath")
    correction.operation = "MULTIPLY"
    correction.label = "Scratch-only canonical +Y -> saved source -Y pigment position"
    correction.inputs[1].default_value = (1., -1., 1.)
    links.new(origin, correction.inputs[0])
    links.new(correction.outputs["Vector"], instance.inputs["Position"])
    material["atlas_source_coordinate_correction"] = "reflect-Y-once-v1"
    continuous_body_group(source, material, reflected=True)
    return material


def continuous_mask_material(high):
    recognized = continuous_body_group(high, reflected=True)
    if recognized is None:
        return None
    original, _instance = recognized
    material = original.copy()
    _material, instance = continuous_body_group(high, material, reflected=True)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    outputs = [node for node in nodes if node.type == "OUTPUT_MATERIAL" and node.is_active_output]
    if len(outputs) != 1:
        raise RuntimeError("unified mask scratch material requires one active surface output")
    output = outputs[0]
    for edge in list(output.inputs["Surface"].links):
        links.remove(edge)
    emission = nodes.new("ShaderNodeEmission")
    links.new(instance.outputs["SemanticMasks"], emission.inputs["Color"])
    links.new(emission.outputs[0], output.inputs["Surface"])
    return material


def source_semantics(source, study_binding=None):
    zone = adapter.component_spec(source.name)[0]
    if continuous_body_group(source) is not None:
        adapter.validate_geometry_binding(UNIFIED_GEOMETRY_POLICY, study_binding)
        saved_semantic_values(source)  # Validate diagnostics, never bake them.
        return None  # No vertex-sample equality claim for a continuous shader.
    explicit = saved_semantic_values(source)
    attribute = source.data.color_attributes.new(name="AuthoritativeAtlasMasks", type="FLOAT_COLOR", domain="POINT")
    if explicit is not None:
        if zone not in {"body", "brow", "wing", "tail"}:
            raise RuntimeError(f"feather masks attached to a hard surface: {source.name}")
        for index, value in enumerate(explicit):
            attribute.data[index].color = value
            if tuple(attribute.data[index].color) != value:
                raise RuntimeError("source semantic field changed during copy")
        return 0.0
    saved = source.data.color_attributes.get("PreviewColor")
    maximum_error = 0.0
    for vertex in source.data.vertices:
        point = source.matrix_world @ vertex.co
        if zone in {"body", "brow"}:
            waterline = 0.0
            if zone == "brow":
                if len(source.data.vertices) != 480:
                    raise RuntimeError("M orbital ring topology changed; analytic waterline requires review")
                waterline = 1 - smoothstep(0.03, 0.30, (vertex.index // 80) / 5)
            mask = analytic_masks(point, waterline=waterline)
            # The authored waterline uses its own darker pigment; validate its
            # exact construction separately, not by changing semantic palettes.
            expected = recompose(analytic_masks(point))
            if waterline:
                expected = tuple(value * (1 - waterline) + dark * waterline
                                 for value, dark in zip(expected, (0.016, 0.022, 0.030)))
            if saved is None or saved.domain != "POINT":
                raise RuntimeError("authoritative source body/rim paint unavailable")
            maximum_error = max(maximum_error, max(abs(a - b) for a, b in zip(expected, saved.data[vertex.index].color[:3])))
        elif zone == "wing":
            if len(source.data.vertices) != 2162 or saved is None or saved.domain != "POINT":
                raise RuntimeError("wing topology/paint changed; authoritative 45x48 parameterization needs review")
            cream = 0.0
            if vertex.index < 2160:
                ring, segment = divmod(vertex.index, 48)
                thick = (source.data.vertices[ring * 48 + 12].co - source.data.vertices[ring * 48 + 36].co).normalized()
                cream = wing_cream(ring, segment, thick.y)
            mask = cream, 0, 0, 1
            maximum_error = max(maximum_error, max(abs(a - b) for a, b in zip(recompose(mask), saved.data[vertex.index].color[:3])))
        else:
            mask = (0, 0, 0, 1 if zone in {"wing", "tail"} else 0)
        attribute.data[vertex.index].color = mask
    if maximum_error > 2e-6:
        raise RuntimeError(f"analytic mask formula differs from saved M pigment: {source.name} {maximum_error}")
    return maximum_error


def canonical_high(source, offset, collection):
    continuous_material = canonical_continuous_material(source)
    high = source.copy()
    high.data = source.data.copy()
    if continuous_material is not None:
        high.data.materials[0] = continuous_material
    collection.objects.link(high)
    high.data.transform(source.matrix_world)
    high.matrix_world.identity()
    high.data.transform(Matrix.Diagonal((1, -1, 1, 1)))
    high.data.flip_normals()
    if adapter.component_spec(source.name)[0] in {"foot", "toe"}:
        for vertex in high.data.vertices:
            vertex.co.z += offset
    high.data.update()
    high.hide_render = False
    return high


def low_component(mesh, component, face_components, collection, *, split_faces=False):
    polygons = [face for face in mesh.data.polygons if face_components[face.index] == component]
    indices = sorted({index for face in polygons for index in face.vertices})
    mapping = {index: local for local, index in enumerate(indices)}
    data = bpy.data.meshes.new("AtlasBakeTarget")
    if split_faces:
        # Scratch-only triangle duplication permits independent face-directed
        # cages. Request original smooth corner normals, not flat shading.
        # Blender's INT16_2D storage is lossy: measure the explicitly approved
        # QA-only <=0.1 degree roundtrip. Final runtime normals stay unchanged.
        if any(len(face.vertices) != 3 for face in polygons):
            raise RuntimeError("explicit face cage requires final triangulation")
        data.from_pydata([mesh.data.vertices[index].co for face in polygons for index in face.vertices], [],
                         [tuple(range(index * 3, index * 3 + 3)) for index in range(len(polygons))])
    else:
        data.from_pydata([mesh.data.vertices[index].co for index in indices], [],
                         [tuple(mapping[index] for index in face.vertices) for face in polygons])
    uv = data.uv_layers.new(name=ATLAS_UV)
    for target, original in zip(data.polygons, polygons):
        target.use_smooth = original.use_smooth
        for target_loop, original_loop in zip(target.loop_indices, original.loop_indices):
            uv.data[target_loop].uv = mesh.data.uv_layers[ATLAS_UV].data[original_loop].uv
    normal_error = 0.0
    normal_audit = None
    if split_faces:
        normals = [mesh.data.corner_normals[index].vector.copy() for face in polygons for index in face.loop_indices]
        data.normals_split_custom_set(normals)
        data.update()
        normal_error = max((actual.vector - expected).length for actual, expected in zip(data.corner_normals, normals))
        normal_audit = scratch_normal_roundtrip(normals, [normal.vector for normal in data.corner_normals])
    obj = bpy.data.objects.new(data.name, data)
    collection.objects.link(obj)
    material = bpy.data.materials.new("AtlasBakeTargetMaterial")
    material.use_nodes = True
    image_node = material.node_tree.nodes.new("ShaderNodeTexImage")
    emission = material.node_tree.nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (1, 1, 1, 1)
    material.node_tree.links.new(emission.outputs[0], material.node_tree.nodes.get("Material Output").inputs["Surface"])
    material.node_tree.nodes.active = image_node
    image_node.select = True
    data.materials.append(material)
    obj["original_corner_normal_maximum_error"] = normal_error
    if normal_audit:
        obj["scratch_normal_roundtrip_json"] = json.dumps(normal_audit, sort_keys=True)
    return obj, image_node


def explicit_face_cage(low, collection, distance=0.012):
    """Scratch positions only; original low tangent normals are not modified."""
    used = [index for face in low.data.polygons for index in face.vertices]
    if len(used) != len(set(used)) or len(used) != len(low.data.vertices):
        raise RuntimeError("face cage requires unshared scratch triangle vertices")
    cage = bpy.data.objects.new("ExplicitMouthFaceCage", low.data.copy())
    collection.objects.link(cage)
    for face in low.data.polygons:
        for index in face.vertices:
            cage.data.vertices[index].co = low.data.vertices[index].co + face.normal * distance
    cage.data.update()
    cage.hide_render = True
    return cage


def new_image(name, size, color, *, srgb=False):
    image = bpy.data.images.new(name, width=size, height=size, alpha=True, float_buffer=True)
    image.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
    image.generated_color = color
    return image


def pixels(image):
    import numpy as np
    result = np.empty(len(image.pixels), dtype=np.float32)
    image.pixels.foreach_get(result)
    return result.reshape(image.size[1], image.size[0], 4)


def set_pixels(image, values):
    image.pixels.foreach_set(values.reshape(-1))
    image.update()


def load_working_pngs(maps, directory):
    """Saved PNGs are canonical; an older packed checkpoint may be stale."""
    hashes = {}
    for kind, image in maps.items():
        path = directory / f"working_{kind}.png"
        if not path.is_file():
            raise RuntimeError(f"missing canonical working map: {path}")
        if image.packed_file:
            image.unpack(method="REMOVE")
        image.filepath_raw = str(path)
        image.source = "FILE"
        image.colorspace_settings.name = "sRGB" if kind == "albedo" else "Non-Color"
        image.reload()
        hashes[kind] = sha(path)
    return hashes


def save_pack_exact(image, path):
    """Replace existing packed bytes explicitly; image.pack() alone keeps stale data."""
    # A reloaded FILE image is lazy. Materialize and dirty the exact unchanged
    # pixels before changing its filename, otherwise save can read the new
    # (not yet existing) path and report no image data.
    set_pixels(image, pixels(image))
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    raw = path.read_bytes()
    if image.packed_file:
        image.unpack(method="REMOVE")
    image.source = "FILE"
    image.filepath_raw = str(path)
    image.reload()
    image.pack(data=raw, data_len=len(raw))
    if bytes(image.packed_file.data) != raw:
        raise RuntimeError(f"packed image bytes differ from saved canonical PNG: {path}")


def emission_material(name, attribute=None):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (1, 1, 1, 1)
    if attribute:
        color = nodes.new("ShaderNodeVertexColor")
        color.layer_name = attribute
        links.new(color.outputs["Color"], emission.inputs["Color"])
    links.new(emission.outputs[0], output.inputs["Surface"])
    return material


def bake_component(high, low, image_node, maps, margin, *, explicit_cage=None, normal_space="TANGENT",
                   cage_distance_m=0.012, ray_distance_m=0.04):
    adapter.activate(low)
    high.select_set(True)
    # Measured small-cage trial increased mouth misses 26 -> 283 without
    # improving eye boundaries. Keep the known baseline until an explicit
    # directional cage is validated; ray length is not a projection waiver.
    cage, ray = cage_distance_m, ray_distance_m
    settings = dict(use_selected_to_active=True, target="IMAGE_TEXTURES", save_mode="INTERNAL",
                    uv_layer=ATLAS_UV, margin=margin, margin_type="EXTEND", use_clear=False,
                    cage_extrusion=cage, max_ray_distance=ray)
    if explicit_cage is not None:
        settings.update(use_cage=True, cage_object=explicit_cage.name, cage_extrusion=0.0)
    for name, kind in (("albedo", "DIFFUSE"), ("normal", "NORMAL"), ("roughness", "ROUGHNESS"), ("ao", "AO")):
        image_node.image = maps[name]
        image_node.select = True
        low.data.materials[0].node_tree.nodes.active = image_node
        extras = {"pass_filter": {"COLOR"}} if kind == "DIFFUSE" else {}
        if kind == "NORMAL":
            extras.update(normal_space=normal_space, normal_r="POS_X", normal_g="POS_Y", normal_b="POS_Z")
        bpy.ops.object.bake(type=kind, **settings, **extras)
    original_materials = list(high.data.materials)
    continuous_masks = continuous_mask_material(high)
    try:
        for name, material in (("masks", continuous_masks if continuous_masks is not None else MASK_MATERIAL), ("hits", HIT_MATERIAL)):
            high.data.materials.clear()
            high.data.materials.append(material)
            image_node.image = maps[name]
            # A dilated coverage pass can hide genuine source-projection holes.
            # Only material maps receive gutters; hit evidence stays undilated.
            emission_settings = dict(settings)
            if name == "hits":
                emission_settings["margin"] = 0
            bpy.ops.object.bake(type="EMIT", **emission_settings)
    finally:
        high.data.materials.clear()
        for material in original_materials:
            high.data.materials.append(material)
        if continuous_masks is not None:
            bpy.data.materials.remove(continuous_masks)
    # Same low geometry/UV/sample coverage, without source projection. This
    # separates real misses from the external pixel-center rasterizer's edge
    # convention, without allowing gutter dilation to fill missing hits.
    high.select_set(False)
    image_node.image = maps["coverage"]
    coverage_settings = dict(settings)
    coverage_settings.update(use_selected_to_active=False, margin=0, use_cage=False, cage_object="")
    bpy.ops.object.bake(type="EMIT", **coverage_settings)
    return {"cage_extrusion_m": cage, "max_ray_distance_m": ray, "coverage_margin_px": 0,
            "semantic_mask_authority": (UNIFIED_GROUP + ":SemanticMasks; FeatherRegion=1"
                                        if continuous_masks is not None else "AuthoritativeAtlasMasks vertex field"),
            "projection_strategy": "explicit_triangle_face_cage" if explicit_cage else "interpolated_smooth_normal",
            "normal_coordinate_space": normal_space,
            "scratch_split_normal_maximum_error": low["original_corner_normal_maximum_error"],
            "scratch_normal_roundtrip": json.loads(low.get("scratch_normal_roundtrip_json", "null"))}


def clear_component_maps(maps, owner, component, margin):
    """A partial re-bake must not inherit old successful hits at new misses."""
    import numpy as np
    selected = owner == component
    for _ in range(margin + 1):
        before = selected.copy()
        selected[1:, :] |= before[:-1, :]
        selected[:-1, :] |= before[1:, :]
        selected[:, 1:] |= before[:, :-1]
        selected[:, :-1] |= before[:, 1:]
    selected &= (owner < 0) | (owner == component)
    defaults = {"normal": (0.5, 0.5, 1, 1), "ao": (1, 1, 1, 1),
                "roughness": (0.8, 0.8, 0.8, 1), "orm": (1, 0.8, 0, 1), "masks": (0, 0, 0, 0)}
    for name, image in maps.items():
        values = pixels(image)
        values[selected] = defaults.get(name, (0, 0, 0, 1))
        set_pixels(image, values)


def component_scope_hashes(maps, owner, component, margin):
    """Audit no changes outside paired component plus its bounded empty gutter."""
    import numpy as np
    allowed = owner == component
    for _ in range(margin + 2):
        before = allowed.copy()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            nearby = np.roll(before, (dy, dx), axis=(0, 1))
            if dy:
                nearby[0 if dy == 1 else -1, :] = False
            if dx:
                nearby[:, 0 if dx == 1 else -1] = False
            allowed |= nearby
    allowed &= (owner < 0) | (owner == component)
    return {name: hashlib.sha256(pixels(image)[~allowed].tobytes()).hexdigest() for name, image in maps.items()}


def complementary_mouth_projection(maps, mesh, owner, sources, checkpoint):
    """Copy only genuine baseline misses having a real paired secondary hit."""
    import numpy as np
    checkpoint = checkpoint.resolve()
    settings_path = checkpoint.parent / "projection_settings.json"
    rejection_path = checkpoint.parent / "projection_rejected.json"
    settings = json.loads(settings_path.read_text())
    mouth_settings = settings.get("BillMouthSeam", {})
    if set(settings) != {"BillMouthSeam"} or mouth_settings.get("projection_strategy") != "explicit_triangle_face_cage":
        raise RuntimeError("complementary source must be the explicit paired mouth-only cage bake")
    if not mouth_settings.get("outside_component_gutter_unchanged") or mouth_settings["scratch_normal_roundtrip"]["maximum_degrees"] > MOUTH_SCRATCH_NORMAL_LIMIT_DEGREES:
        raise RuntimeError("complementary source failed scope or scratch normal gate")
    with bpy.data.libraries.load(str(checkpoint), link=False) as (available, requested):
        # Load mesh data only: loading its Object would recursively append a
        # second armature/actions through parent and modifier dependencies.
        requested.meshes = [mesh.data.name]
    other_data = requested.meshes[0]
    other_mesh = bpy.data.objects.new("ComplementaryProjectionGeometryCheck", other_data)
    if preservation_digest(other_mesh) != preservation_digest(mesh):
        raise RuntimeError("complementary checkpoint geometry/skin/morphs differ")
    primary_uv = [tuple(point.uv) for point in mesh.data.uv_layers[ATLAS_UV].data]
    if primary_uv != [tuple(point.uv) for point in other_mesh.data.uv_layers[ATLAS_UV].data]:
        raise RuntimeError("complementary checkpoint atlas coordinates differ")
    fallback = {name: bpy.data.images.load(str(checkpoint.parent / f"working_{name}.png"), check_existing=False)
                for name in maps}
    for name, image in fallback.items():
        image.colorspace_settings.name = "sRGB" if name == "albedo" else "Non-Color"
    if any(tuple(fallback[name].size) != tuple(image.size) for name, image in maps.items()):
        raise RuntimeError("complementary checkpoint map dimensions differ")
    coverage, hits = pixels(maps["coverage"])[..., 0], pixels(maps["hits"])[..., 0]
    second_coverage, second_hits = pixels(fallback["coverage"])[..., 0], pixels(fallback["hits"])[..., 0]
    missing = (coverage > 1e-5) & (hits + 1e-5 < coverage)
    component = next(index for index, source in enumerate(sources) if source.name == "BillMouthSeam")
    selected = missing & (owner == component) & (second_coverage > 1e-5) & (second_hits + 1e-5 >= second_coverage)
    if not np.any(selected) or np.any(selected & (np.abs(coverage - second_coverage) > 1e-7)):
        raise RuntimeError("complementary mouth source lacks matching actual coverage: " + str({
            "baseline_missing": int(missing.sum()), "baseline_mouth_missing": int((missing & (owner == component)).sum()),
            "selected": int(selected.sum()), "coverage_delta_max": float(np.abs(coverage[selected] - second_coverage[selected]).max()) if np.any(selected) else None,
            "secondary_missing": int(((second_coverage > 1e-5) & (second_hits + 1e-5 < second_coverage)).sum())}))
    valid = (coverage > 1e-5) & ~missing
    before_valid, after_valid, before_unselected, after_unselected = {}, {}, {}, {}
    for name, image in maps.items():
        original, secondary = pixels(image), pixels(fallback[name])
        before_valid[name] = hashlib.sha256(original[valid].tobytes()).hexdigest()
        before_unselected[name] = hashlib.sha256(original[~selected].tobytes()).hexdigest()
        original[selected] = secondary[selected]
        set_pixels(image, original)
        actual = pixels(image)
        after_valid[name] = hashlib.sha256(actual[valid].tobytes()).hexdigest()
        after_unselected[name] = hashlib.sha256(actual[~selected].tobytes()).hexdigest()
        if not np.array_equal(actual[selected], secondary[selected]):
            raise RuntimeError("secondary projection channels were not copied exactly together")
    if before_valid != after_valid or before_unselected != after_unselected:
        raise RuntimeError("complementary projection changed valid baseline or unselected pixels")
    result = {"method": "actual_same_component_complementary_projection", "component": "BillMouthSeam",
              "copied_pixels": int(selected.sum()), "channels_copied_together": list(maps),
              "baseline_valid_pixels_exactly_unchanged": True, "all_unselected_pixels_exactly_unchanged": True,
              "baseline_valid_map_hashes": before_valid, "unselected_map_hashes": before_unselected,
              "secondary_checkpoint_sha256": sha(checkpoint), "secondary_settings_sha256": sha(settings_path),
              "secondary_rejection_sha256": sha(rejection_path), "secondary_projection_settings": mouth_settings,
              "canonical_secondary_working_pngs": {name: sha(checkpoint.parent / f"working_{name}.png") for name in maps},
              "copied_pixels_xy": [[int(x), int(y)] for y, x in np.argwhere(selected)]}
    for image in fallback.values():
        bpy.data.images.remove(image)
    bpy.data.objects.remove(other_mesh, do_unlink=True)
    bpy.data.meshes.remove(other_data)
    return result


def preserve_working_bake(maps, output):
    for name, image in maps.items():
        save_pack_exact(image, output / f"working_{name}.png")
        image.use_fake_user = True
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "bake_checkpoint.blend"), check_existing=False, compress=True, copy=True)
    with bpy.data.libraries.load(str(output / "bake_checkpoint.blend"), link=False) as (available, requested):
        requested.images = [image.name for image in maps.values()]
    checks = {}
    for (kind, original), reopened in zip(maps.items(), requested.images):
        path = output / f"working_{kind}.png"
        if reopened is original or not reopened.packed_file or bytes(reopened.packed_file.data) != path.read_bytes():
            raise RuntimeError(f"checkpoint packed PNG roundtrip failed: {kind}")
        # Packed byte equality plus actual decoded buffer equality verifies the
        # saved checkpoint, not merely its filename or current in-memory image.
        import numpy as np
        difference = float(np.max(np.abs(pixels(reopened) - pixels(original))))
        if difference != 0.0:
            raise RuntimeError(f"checkpoint decoded pixel roundtrip failed: {kind}/{difference}")
        checks[kind] = {"sha256": sha(path), "decoded_pixel_maximum_difference": difference}
        bpy.data.images.remove(reopened)
    (output / "checkpoint_png_roundtrip.json").write_text(json.dumps(checks, indent=2, sort_keys=True) + "\n")


def finish_maps(maps, owner, sources, output, margin, *, rejected_review=False):
    import numpy as np
    interior = owner >= 0
    hits = pixels(maps["hits"])[..., 0]
    coverage = pixels(maps["coverage"])[..., 0]
    missing = (coverage > 1e-5) & (hits + 1e-5 < coverage)
    miss_count = int(missing.sum())
    if miss_count:
        coords = np.argwhere(missing)
        diagnostic = {"production_ready": False, "rejected": True,
                      "projected_pixels": int((coverage > 1e-5).sum()), "missing_pixels": miss_count,
                      "pixel_center_only_disagreement": int((interior & (coverage < 0.9)).sum()),
                      "missing_components": {source.name: int((missing & (owner == component)).sum())
                                             for component, source in enumerate(sources)},
                      "boundary_pixels_without_center_owner": int((missing & (owner < 0)).sum()),
                      "first_missing_pixels_xy": [[int(x), int(y)] for y, x in coords[:100]]}
        (output / "projection_rejected.json").write_text(json.dumps(diagnostic, indent=2, sort_keys=True) + "\n")
        debug = new_image("RejectedProjectionCoverage", owner.shape[0], (0, 0, 0, 1))
        data = pixels(debug)
        data[..., 0], data[..., 1], data[..., 2], data[..., 3] = missing.astype(np.float32), coverage, hits, 1
        set_pixels(debug, data)
        debug.filepath_raw = str(output / "projection_rejected.png")
        debug.file_format = "PNG"
        debug.save()
        if not rejected_review:
            raise RuntimeError(f"high-to-low projection missed {miss_count} interior pixels")
    # Extend explicit component membership with the same bounded gutter as
    # texture baking; no color inference and no propagation across another chart.
    extended = owner.copy()
    for _ in range(margin):
        previous = extended.copy()
        for axis, shift in ((0, 1), (0, -1), (1, 1), (1, -1)):
            nearby = np.roll(previous, shift, axis=axis)
            if axis == 0:
                nearby[0 if shift == 1 else -1, :] = -1
            else:
                nearby[:, 0 if shift == 1 else -1] = -1
            take = (extended < 0) & (nearby >= 0)
            extended[take] = nearby[take]
    masks = pixels(maps["masks"])
    masks[..., 3] = 0
    for component, source in enumerate(sources):
        if adapter.component_spec(source.name)[0] in {"body", "brow", "wing", "tail"}:
            masks[extended == component, 3] = 1
    masks[..., :3] = np.clip(masks[..., :3], 0, 1)
    if np.any(masks[interior, :3].sum(axis=1) > 1.0001):
        raise RuntimeError("semantic mask exclusive weight sum exceeds one")
    set_pixels(maps["masks"], masks)
    orm = pixels(maps["orm"])
    orm[..., 0] = np.clip(pixels(maps["ao"])[..., 0], 0, 1)
    orm[..., 1] = np.clip(pixels(maps["roughness"])[..., 0], 0, 1)
    orm[..., 2] = 0
    orm[..., 3] = 1
    set_pixels(maps["orm"], orm)
    paths = {}
    for name in MAP_NAMES:
        image = maps[name]
        if name == "albedo":
            values = pixels(image)
            values[..., 3] = 1
            set_pixels(image, values)
        path = output / f"hero_penguin_v12_atlas_{name}.png"
        save_pack_exact(image, path)
        paths[name] = path
    return paths, {"projection_missed_interior_pixels": miss_count,
                   "projection_gate_passed": miss_count == 0,
                   "validated_projection_pixels": int((coverage > 1e-5).sum()),
                   "pixel_center_only_disagreement": int((interior & (coverage < 0.9)).sum()),
                   "mask_feather_interior_pixels": int((masks[..., 3][interior] > 0.5).sum())}


def atlas_material(name, maps):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = ATLAS_UV
    textures = {}
    for kind in ("albedo", "normal", "orm"):
        node = nodes.new("ShaderNodeTexImage")
        node.image = maps[kind]
        node.extension = "EXTEND"
        links.new(uv.outputs["UV"], node.inputs["Vector"])
        textures[kind] = node
    links.new(textures["albedo"].outputs["Color"], bsdf.inputs["Base Color"])
    normal = nodes.new("ShaderNodeNormalMap")
    normal.uv_map = ATLAS_UV
    links.new(textures["normal"].outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])
    channels = nodes.new("ShaderNodeSeparateColor")
    links.new(textures["orm"].outputs["Color"], channels.inputs["Color"])
    links.new(channels.outputs["Green"], bsdf.inputs["Roughness"])
    links.new(channels.outputs["Blue"], bsdf.inputs["Metallic"])
    group = bpy.data.node_groups.get("glTF Material Output")
    if group is None:
        group = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        group.interface.new_socket(name="Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    extra = nodes.new("ShaderNodeGroup")
    extra.node_tree = group
    links.new(channels.outputs["Red"], extra.inputs["Occlusion"])
    return material


def exported_atlas_contract(path, mesh, paths):
    """Assert the real serialized UV0/paint/rig contract, not exporter settings."""
    raw = Path(path).read_bytes()
    length = struct.unpack_from("<I", raw, 12)[0]
    document = json.loads(raw[20:20 + length])
    binary = 28 + length
    expected = {}
    if len(mesh.data.uv_layers) != 1 or mesh.data.uv_layers[0].name != ATLAS_UV:
        raise RuntimeError("atlas export must contain exactly its unique UV layer")
    uv = mesh.data.uv_layers[0]
    for loop in mesh.data.loops:
        point = mesh.data.vertices[loop.vertex_index].co
        u, v = uv.data[loop.index].uv
        expected.setdefault(struct.pack("<3f", point.x, point.z, -point.y), set()).add(struct.pack("<2f", u, 1 - v))
    found, vertices = {}, 0
    def floats(index, count):
        accessor = document["accessors"][index]
        view = document["bufferViews"][accessor["bufferView"]]
        if accessor["componentType"] != 5126:
            raise RuntimeError("unexpected quantized position/UV; explicit mapping audit needed")
        offset = binary + view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        stride = view.get("byteStride", count * 4)
        return [raw[offset + i * stride:offset + i * stride + count * 4] for i in range(accessor["count"])]
    surfaces = 0
    for data in document["meshes"]:
        for primitive in data["primitives"]:
            attributes = primitive["attributes"]
            if any(name.startswith("COLOR_") for name in attributes) or "TEXCOORD_1" in attributes:
                raise RuntimeError("old vertex paint or repeating secondary UV exported")
            positions, coordinates = floats(attributes["POSITION"], 3), floats(attributes["TEXCOORD_0"], 2)
            if len(positions) != len(coordinates):
                raise RuntimeError("position/atlas UV accessor count mismatch")
            if len(primitive.get("targets", [])) != 8:
                raise RuntimeError("eight species shapes not preserved in exported atlas")
            for point, coordinate in zip(positions, coordinates):
                if coordinate not in expected.get(point, set()):
                    raise RuntimeError("serialized UV0 differs from exact unique atlas coordinate")
                found.setdefault(point, set()).add(coordinate)
                vertices += 1
            surfaces += 1
    if found != expected:
        raise RuntimeError("some unique atlas source coordinates were not exported")
    texture_indices = {}
    for material in document["materials"]:
        pbr = material["pbrMetallicRoughness"]
        for info in (pbr["baseColorTexture"], pbr["metallicRoughnessTexture"], material["normalTexture"], material["occlusionTexture"]):
            if info.get("texCoord", 0) != 0 or info.get("extensions", {}).get("KHR_texture_transform", {}).get("texCoord", 0) != 0:
                raise RuntimeError("PBR texture reads another UV channel")
        for kind, info in (("albedo", pbr["baseColorTexture"]), ("normal", material["normalTexture"]),
                           ("orm", pbr["metallicRoughnessTexture"])):
            texture_indices.setdefault(kind, set()).add(info["index"])
        if material["occlusionTexture"]["index"] != pbr["metallicRoughnessTexture"]["index"]:
            raise RuntimeError("embedded AO does not share the packed ORM texture")
    import numpy as np
    embedded_dir = path.parent / "embedded_texture_audit"
    embedded_dir.mkdir()
    texture_checks = {}
    for kind, indices in texture_indices.items():
        image_indices = {document["textures"][index]["source"] for index in indices}
        sampler_indices = {document["textures"][index].get("sampler") for index in indices}
        # Two material texture descriptors may legally reference the same
        # image and sampler. Audit resolved images, not descriptor indices.
        if len(image_indices) != 1 or len(sampler_indices) != 1:
            raise RuntimeError("two atlas surfaces unexpectedly use different images")
        source = document["images"][next(iter(image_indices))]
        if source.get("mimeType") != "image/png":
            raise RuntimeError("embedded atlas image is not a PNG")
        view = document["bufferViews"][source["bufferView"]]
        start = binary + view.get("byteOffset", 0)
        embedded_path = embedded_dir / f"{kind}.png"
        embedded_path.write_bytes(raw[start:start + view["byteLength"]])
        actual = bpy.data.images.load(str(embedded_path), check_existing=False)
        expected_image = bpy.data.images.load(str(paths[kind]), check_existing=False)
        actual.colorspace_settings.name = expected_image.colorspace_settings.name = "Non-Color"
        if tuple(actual.size) != tuple(expected_image.size):
            raise RuntimeError("embedded/external texture dimensions differ")
        maximum = float(np.max(np.abs(pixels(actual)[..., :3] - pixels(expected_image)[..., :3])))
        if maximum != 0.0:
            raise RuntimeError(f"embedded {kind} pixels differ from canonical atlas: {maximum}")
        texture_checks[kind] = {"embedded_sha256": sha(embedded_path), "external_sha256": sha(paths[kind]),
                                "decoded_rgb_maximum_difference": maximum}
        bpy.data.images.remove(actual)
        bpy.data.images.remove(expected_image)
    bones = len(document["skins"][0]["joints"])
    clips = [animation["name"] for animation in document["animations"]]
    if surfaces != 2 or bones != 15 or len(clips) != 23:
        raise RuntimeError("exported surface, skeleton or animation count changed")
    return {"uv_contract": "unique-nonoverlapping-v1", "all_pbr_texcoord": 0,
            "serialized_uv0_vertices_exactly_matched": vertices, "no_vertex_color": True,
            "surfaces": surfaces, "bones": bones, "clips": clips, "species_shapes": 8,
            "embedded_texture_pixels": texture_checks}


def main():
    global bpy, adapter, legacy, Vector, Matrix, MASK_MATERIAL, HIT_MATERIAL
    import bpy
    from mathutils import Vector, Matrix
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import hero_penguin_v12_study_provenance as study_provenance
    adapter = load_module("v12_candidate_for_atlas", Path(__file__).with_name("build_hero_penguin_v12_candidate.py"))
    legacy = load_module("v1_for_atlas", Path(__file__).with_name("build_hero_penguin_v1.py"))
    export_art = load_module("export_for_atlas", Path(__file__).with_name("export_art.py"))
    exporter = load_module("blender_export_for_atlas", Path(__file__).with_name("blender_export.py"))
    adapter.bpy, adapter.legacy = bpy, legacy
    legacy.require_version()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-blend", type=Path, required=True)
    parser.add_argument("--candidate-dir", type=Path, required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--size", type=int, default=2048)
    parser.add_argument("--lod1-size", type=int, default=1024)
    parser.add_argument("--samples", type=int, default=16)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--lods", choices=("0", "1", "both"), default="both")
    parser.add_argument("--repair-checkpoint", type=Path,
                        help="re-bake only explicitly rejected components from a saved QA checkpoint")
    parser.add_argument("--review-rejected", action="store_true",
                        help="export checkpoint for visual diagnosis only; preserve failed gate and exit nonzero")
    parser.add_argument("--mouth-face-cage", action="store_true",
                        help="repair only mouth projection with a scratch face-directed cage; preserve other failures")
    parser.add_argument("--complementary-mouth-checkpoint", type=Path,
                        help="fill only failed mouth pixels from a verified real complementary face-cage bake")
    parser.add_argument("--nearest-eye-probes", action="store_true",
                        help="sample only failed eye/rim texels on paired high geometry within0.25mm")
    parser.add_argument("--paired-mouth-probes", action="store_true",
                        help="sample only failed mouth texels on facing-compatible paired source triangles within1.25mm")
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parser.parse_args(values)
    if args.review_rejected and not args.repair_checkpoint:
        raise ValueError("rejected review requires an explicit rejected checkpoint")
    if args.mouth_face_cage and (not args.repair_checkpoint or args.review_rejected):
        raise ValueError("mouth face cage requires an explicit repair checkpoint, not a diagnostic-only export")
    if args.complementary_mouth_checkpoint and (not args.repair_checkpoint or args.review_rejected or args.mouth_face_cage):
        raise ValueError("complementary mouth projection requires only an explicit baseline repair checkpoint")
    if args.nearest_eye_probes and (not args.repair_checkpoint or args.review_rejected or args.mouth_face_cage or args.complementary_mouth_checkpoint):
        raise ValueError("nearest eye probes require only an explicit baseline repair checkpoint")
    if args.paired_mouth_probes and (not args.repair_checkpoint or args.review_rejected or args.mouth_face_cage
                                    or args.complementary_mouth_checkpoint or args.nearest_eye_probes):
        raise ValueError("paired mouth probes require only an explicit baseline repair checkpoint")
    if args.size not in (512, 1024, 2048) or args.lod1_size not in (512, 1024, 2048) or not 1 <= args.threads <= 4:
        raise ValueError("power-of-two 512..2048 maps and at most four CPU threads required")
    output = safe_output(args.output_dir)
    source = args.source_blend.resolve()
    candidate_dir = args.candidate_dir.resolve()
    candidate = candidate_dir / "hero_penguin_v12_candidate.blend"
    candidate_audit = candidate_dir / "candidate_audit.json"
    prior = json.loads(candidate_audit.read_text())
    geometry_policy = candidate_geometry_policy(prior)
    if sha(source) != prior["source_sha256"] or sha(candidate) != prior["outputs"][candidate.name]:
        raise RuntimeError("immutable source/candidate audit hash mismatch")
    inputs = {str(source): sha(source), str(candidate): sha(candidate),
              str(candidate_audit): sha(candidate_audit)}
    if args.nearest_eye_probes:
        helper_path = Path(__file__).with_name("hero_v12_projection_probes.py")
        inputs[str(helper_path)] = sha(helper_path)
    if args.paired_mouth_probes:
        for name in ("hero_v12_mouth_projection.py", "hero_v12_projection_probes.py"):
            helper_path = Path(__file__).with_name(name)
            inputs[str(helper_path)] = sha(helper_path)
    if args.complementary_mouth_checkpoint:
        complementary = args.complementary_mouth_checkpoint.resolve()
        if not complementary.is_relative_to(QA_ROOT) or not complementary.is_file():
            raise ValueError("complementary checkpoint must be an existing QA artifact")
        for artifact in (complementary, complementary.parent / "projection_settings.json", complementary.parent / "projection_rejected.json"):
            inputs[str(artifact)] = sha(artifact)
    output.mkdir(parents=True)
    bpy.ops.wm.open_mainfile(filepath=str(candidate))
    # Before replay or checkpoint use: source scene JSON, sidecars, study
    # declaration and the exact adapter that produced this candidate must agree.
    study_binding = study_provenance.validate_candidate_study(
        source, bpy.context.scene, prior, Path(adapter.__file__))
    adapter.validate_geometry_binding(geometry_policy, study_binding)
    retopology_helper = None
    if geometry_policy == UNIFIED_RETOPO_POLICY:
        retopology_helper = adapter.verify_retopology_helper(prior)
        inputs[retopology_helper["path"]] = retopology_helper["sha256"]
    inputs.update(study_provenance.binding_input_hashes(source, study_binding))
    expected_preservation = [preservation_digest(bpy.data.objects[name]) for name in ("HeroPenguinMesh", "HeroPenguinLOD1")]
    rejection = None
    if args.repair_checkpoint:
        checkpoint = args.repair_checkpoint.resolve()
        if not checkpoint.is_relative_to(QA_ROOT) or not checkpoint.is_file() or args.lods == "both":
            raise ValueError("repair requires an existing QA checkpoint and exactly one LOD")
        rejection_path = checkpoint.parent / "projection_rejected.json"
        rejection = json.loads(rejection_path.read_text())
        inputs[str(checkpoint)] = sha(checkpoint)
        inputs[str(rejection_path)] = sha(rejection_path)
        for artifact in checkpoint.parent.glob("working_*.png"):
            inputs[str(artifact)] = sha(artifact)
        if args.complementary_mouth_checkpoint:
            for artifact in args.complementary_mouth_checkpoint.resolve().parent.glob("working_*.png"):
                inputs[str(artifact)] = sha(artifact)
        bpy.ops.wm.open_mainfile(filepath=str(checkpoint))
        study_provenance.validate_candidate_study(source, bpy.context.scene, prior, Path(adapter.__file__))
    meshes = [bpy.data.objects[name] for name in ("HeroPenguinMesh", "HeroPenguinLOD1")]
    armature = bpy.data.objects["PenguinSkeleton"]
    rig_objects = [armature, *[bpy.data.objects[name] for name in adapter.SOCKETS]]
    if args.repair_checkpoint:
        for obj in list(bpy.data.objects):
            if obj not in [*meshes, *rig_objects]:
                bpy.data.objects.remove(obj, do_unlink=True)
    legacy.reset_pose(armature)
    armature.animation_data.action = None
    action_hashes = {action.name: legacy.action_digest(action) for action in bpy.data.actions}
    rest_hash = adapter.rest_digest(armature)
    preservation = [preservation_digest(mesh) for mesh in meshes]
    if preservation != expected_preservation:
        raise RuntimeError("checkpoint geometry, skin or species differs from immutable candidate")
    scratch = bpy.data.collections.new("AtlasSourceAndBakeScratch")
    bpy.context.scene.collection.children.link(scratch)
    with bpy.data.libraries.load(str(source), link=False) as (available, requested):
        requested.objects = [name for name in available.objects if name != "NeutralGrayFloor"
                             and any(name.startswith(prefix) for prefix, _zone, _budget in adapter.COMPONENTS)]
    sources = sorted(requested.objects, key=lambda obj: obj.name)
    for obj in sources:
        scratch.objects.link(obj)
        obj.hide_render = True
        study_provenance.require_component_masks(study_binding, obj)
    semantic_errors = {obj.name: source_semantics(obj, study_binding) for obj in sources}
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = max(1, args.samples)
    scene.cycles.use_denoising = False
    scene.render.threads_mode = "FIXED"
    scene.render.threads = args.threads
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    MASK_MATERIAL = emission_material("AuthoritativeSemanticBake", "AuthoritativeAtlasMasks")
    HIT_MATERIAL = emission_material("ProjectionCoverageBake")
    report = {"schema_version": 1, "production_ready": False, "source_fidelity_approved": False, "candidate_only": True,
              "inputs": inputs, "tool_sha256": TOOL_SHA256, "palette_linear": PALETTE,
              "geometry_policy": geometry_policy,
              "source_mask_maximum_errors": semantic_errors, "limitations": LIMITATIONS,
              "source_mask_contracts": {obj.name: obj.get("source_mask_contract", "legacy-M-analytic") for obj in sources},
              "source_mask_authorities": {obj.name: (UNIFIED_GROUP + ":SemanticMasks; FeatherRegion=1; diagnostics not baked"
                                                     if continuous_body_group(obj) is not None
                                                     else "explicit saved vertex masks or frozen legacy analytic masks") for obj in sources},
              "uv_contract": "unique-nonoverlapping-v1", "cpu_threads": args.threads,
              "cycles_samples": args.samples, "lods": [], "provenance": []}
    if study_binding is not None:
        report["source_study_binding"] = study_binding
        if geometry_policy == UNIFIED_RETOPO_POLICY:
            report["source_cover_scope"] = adapter.unified_source_scope(study_binding, geometry_policy)
        else:
            report["source_cover_scope"] = (adapter.unified_source_scope(study_binding) if geometry_policy == UNIFIED_GEOMETRY_POLICY
                                            else study_provenance.PIN_SCOPE.copy())
    if retopology_helper is not None:
        report["retopology_helper"] = dict(retopology_helper)
    for filename in ("hero_penguin_feather_dark_source_v1.prompt.md", "hero_penguin_feather_cream_source_v1.prompt.md"):
        path = ROOT / "art_src/characters/material_sources" / filename
        shutil.copy2(path, output / filename)
        report["provenance"].append({"path": str(path), "sha256": sha(path), "copied_verbatim": True})
    for lod in ([0, 1] if args.lods == "both" else [int(args.lods)]):
        mesh, size = meshes[lod], args.size if lod == 0 else args.lod1_size
        lod_dir = output / f"lod{lod}"
        lod_dir.mkdir()
        gutter = 4 if size == 512 else (12 if size == 1024 else 16)
        bake_margin = gutter // 2
        _vertices, face_components = recover_components(mesh, sources, lod, prior, scratch)
        allocation = ({"inherited_from_checkpoint": str(args.repair_checkpoint)} if args.repair_checkpoint
                      else unwrap_unique(mesh, sources, face_components, size, gutter=gutter))
        repaired_faces = []
        for attempt in range(3):
            try:
                owner, validation = uv_audit(mesh, face_components, size)
                break
            except UVOverlapError as error:
                if attempt == 2:
                    raise
                print(f"[v12-atlas] rechart proven folds: {error}", flush=True)
                repaired_faces.extend(error.faces)
                detach_folded_uv_faces(mesh, error.faces, size, gutter)
        validation["folded_polygons_recharted"] = sorted(set(repaired_faces))
        print(f"[v12-atlas] LOD{lod} unique UV validated: {validation}", flush=True)
        for obj in meshes:
            obj.hide_render = True
        offset = prior["lods"][lod]["sole_fit"]["constant_foot_toe_offset_z_m"]
        highs = [canonical_high(source_obj, offset, scratch) for source_obj in sources]
        neutral = {"normal": (0.5, 0.5, 1, 1), "ao": (1, 1, 1, 1),
                   "roughness": (0.8, 0.8, 0.8, 1), "orm": (1, 0.8, 0, 1), "masks": (0, 0, 0, 0)}
        map_names = (*MAP_NAMES, "roughness", "ao", "hits", "coverage")
        maps = ({name: bpy.data.images[f"LOD{lod}_{name}"] for name in map_names} if args.repair_checkpoint else
                {name: new_image(f"LOD{lod}_{name}", size, neutral.get(name, (0, 0, 0, 1)), srgb=name == "albedo") for name in map_names})
        if any(tuple(image.size) != (size, size) for image in maps.values()):
            raise RuntimeError("checkpoint texture resolution differs from requested atlas")
        canonical_input_pngs = load_working_pngs(maps, args.repair_checkpoint.resolve().parent) if args.repair_checkpoint else None
        projection_settings = {}
        if args.nearest_eye_probes:
            probes = load_module("v12_projection_probes", Path(__file__).with_name("hero_v12_projection_probes.py"))
            projection_settings["nearest_eye_probes"] = probes.repair(sys.modules[__name__], mesh, maps, owner, sources,
                                                                       highs, face_components, scratch, lod_dir)
        if args.paired_mouth_probes:
            probes = load_module("v12_mouth_probes", Path(__file__).with_name("hero_v12_mouth_projection.py"))
            projection_settings["paired_mouth_probes"] = probes.repair(sys.modules[__name__], mesh, maps, owner, sources,
                                                                       highs, face_components, scratch, lod_dir)
        if args.complementary_mouth_checkpoint:
            projection_settings["BillMouthSeam"] = complementary_mouth_projection(maps, mesh, owner, sources,
                                                                                args.complementary_mouth_checkpoint)
            projection_settings["BillMouthSeam"]["canonical_baseline_working_pngs"] = canonical_input_pngs
            projection_settings["BillMouthSeam"]["baseline_checkpoint_sha256"] = sha(args.repair_checkpoint.resolve())
            (lod_dir / "complementary_projection.json").write_text(json.dumps(projection_settings, indent=2, sort_keys=True) + "\n")
        for component, high in enumerate(highs):
            if args.review_rejected or args.complementary_mouth_checkpoint or args.nearest_eye_probes or args.paired_mouth_probes:
                continue
            if args.mouth_face_cage and sources[component].name != "BillMouthSeam":
                continue
            if rejection is not None and rejection["missing_components"].get(sources[component].name, 0) == 0:
                continue
            scope_before = component_scope_hashes(maps, owner, component, bake_margin) if args.mouth_face_cage else None
            if rejection is not None:
                clear_component_maps(maps, owner, component, bake_margin)
            low, image_node = low_component(mesh, component, face_components, scratch, split_faces=args.mouth_face_cage)
            face_cage = explicit_face_cage(low, scratch) if args.mouth_face_cage else None
            print(f"[v12-atlas] LOD{lod} bake {component + 1}/{len(highs)} {sources[component].name}", flush=True)
            projection_settings[sources[component].name] = bake_component(high, low, image_node, maps, margin=bake_margin,
                                                                        explicit_cage=face_cage)
            if face_cage:
                bpy.data.objects.remove(face_cage, do_unlink=True)
            bpy.data.objects.remove(low, do_unlink=True)
            if scope_before:
                scope_after = component_scope_hashes(maps, owner, component, bake_margin)
                projection_settings[sources[component].name]["outside_component_gutter_unchanged"] = scope_before == scope_after
                projection_settings[sources[component].name]["outside_component_map_hashes_before"] = scope_before
                projection_settings[sources[component].name]["outside_component_map_hashes_after"] = scope_after
                if scope_before != scope_after:
                    preserve_working_bake(maps, lod_dir)
                    (lod_dir / "projection_settings.json").write_text(json.dumps(projection_settings, indent=2, sort_keys=True) + "\n")
                    raise RuntimeError("mouth repair modified maps outside its component and bounded empty gutter")
        (lod_dir / "projection_settings.json").write_text(json.dumps(projection_settings, indent=2, sort_keys=True) + "\n")
        preserve_working_bake(maps, lod_dir)
        paths, bake_audit = finish_maps(maps, owner, sources, lod_dir, margin=bake_margin, rejected_review=args.review_rejected)
        for high in highs:
            bpy.data.objects.remove(high, do_unlink=True)
        if len(mesh.data.materials) != 2:
            raise RuntimeError("expected preserved two-surface candidate")
        for slot, family in enumerate(("Feathers", "SmoothDetails")):
            mesh.data.materials[slot] = atlas_material(f"V12AtlasLOD{lod}{family}", maps)
        mesh.hide_render = False
        # Keep existing two surface assignments; no COLOR_0 is exported and no
        # candidate vertex-paint shader is needed for standard imported PBR.
        if preservation_digest(mesh) != preservation[lod]:
            raise RuntimeError("atlas authoring changed immutable mesh/skin/species data")
        path = lod_dir / "hero_penguin_v12_atlas.glb"
        exporter.validate_transforms([mesh, *rig_objects])
        exporter.validate_modifiers([mesh, *rig_objects])
        exporter.select_only([mesh, *rig_objects])
        settings = exporter.exporter_kwargs(path, True)
        settings.update(export_materials="EXPORT", export_image_format="AUTO", export_vertex_color="NONE", export_all_vertex_colors=False)
        bpy.ops.export_scene.gltf(**settings)
        exported_contract = exported_atlas_contract(path, mesh, paths)
        validation_process = subprocess.run([str(export_art.find_node()), str(ROOT / "tools/art/validate_glb.mjs"), str(path)],
                                            capture_output=True, text=True, check=False)
        print(validation_process.stdout + validation_process.stderr, flush=True)
        if validation_process.returncode:
            raise RuntimeError("Khronos validation failed after real atlas export")
        binding = {"schema_version": 1, "glb_sha256": sha(path), "uv_contract": "unique-nonoverlapping-v1",
                   "textures": {kind: sha(texture) for kind, texture in paths.items()}}
        binding["projection_gate"] = projection_gate(bake_audit["projection_missed_interior_pixels"])
        if study_binding is not None:
            binding["source_study_binding"] = study_binding
            binding["production_ready"] = False
            binding["source_fidelity_approved"] = False
        if retopology_helper is not None:
            binding["geometry_policy"] = geometry_policy
            binding["retopology_helper"] = dict(retopology_helper)
        if args.review_rejected:
            original_rejection = args.repair_checkpoint.resolve().parent / "projection_rejected.json"
            if rejection["missing_pixels"] != bake_audit["projection_missed_interior_pixels"]:
                raise RuntimeError("rejected review maps no longer match the original rejection count")
            shutil.copy2(original_rejection, lod_dir / "projection_rejected.json")
            binding["projection_gate"] = projection_gate(bake_audit["projection_missed_interior_pixels"],
                                                        rejection_hash=sha(original_rejection))
            (lod_dir / "REJECTED_REVIEW.md").write_text(
                "# REJECTED — visual diagnostic only\n\n"
                f"Projection gate failed: {bake_audit['projection_missed_interior_pixels']} genuine missing high-to-low pixels.\n"
                "This export does not waive the failed gate. No production promotion or completed-bake claim.\n"
                "Original rejection report copied verbatim; binding retains its exact hash.\n"
                "Geometry/skin/animation parity and material appearance are separate review questions.\n")
        (lod_dir / "atlas_binding.json").write_text(json.dumps(binding, indent=2, sort_keys=True) + "\n")
        report["lods"].append({"lod": lod, "size": size, "unique_uv": validation, "allocation": allocation,
                               "requested_pack_gutter_px": gutter, "bake_extension_px": bake_margin,
                               "bake": bake_audit, "binding": binding, "mesh_skin_shapes_preserved": True,
                               "projection_settings_this_run": projection_settings, "prior_rejection": rejection,
                               "canonical_working_input_pngs": canonical_input_pngs,
                               "serialized_contract": exported_contract,
                               "png_storage": {kind: png_storage(texture) for kind, texture in paths.items()},
                               "memory_estimate_note": "RGBA8 estimate only; PNG precision and actual Godot compression/storage are separately audited.",
                               "rgba8_bytes_four_maps_with_mips": round(size * size * 4 * 4 * 4 / 3),
                               "khronos": validation_process.stdout + validation_process.stderr})
        (output / "atlas_audit_in_progress.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    for obj in list(scratch.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    if rest_hash != adapter.rest_digest(armature) or action_hashes != {action.name: legacy.action_digest(action) for action in bpy.data.actions}:
        raise RuntimeError("atlas process changed canonical rest rig or clips")
    if any(sha(Path(path)) != digest for path, digest in inputs.items()):
        raise RuntimeError("immutable input changed during atlas bake")
    report.update(inputs_unchanged=True, rest_rig_preserved=True, all_23_clips_preserved=True)
    bpy.context.preferences.filepaths.save_version = 0
    blend = output / "hero_penguin_v12_atlas_candidate.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), check_existing=False, compress=True)
    report["blend_sha256"] = sha(blend)
    (output / "atlas_audit.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    if args.review_rejected:
        print(f"[v12-atlas] REJECTED REVIEW {output}; projection gate remains FAILED", flush=True)
        raise SystemExit(3)
    print(f"[v12-atlas] COMPLETE {output}; production_ready=false", flush=True)


if __name__ == "__main__":
    main()
