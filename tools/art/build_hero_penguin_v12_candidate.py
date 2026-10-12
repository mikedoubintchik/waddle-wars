#!/usr/bin/env python3
"""Build isolated, budgeted, skinned V12 review assets; never promote live art.

Run through Blender 5.2.0 with an explicit saved sculpt snapshot. The canonical
rig is read-only input. Outputs must live below qa_shots/hero; they are not a
production export registration and must not replace the shipped hero.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import subprocess
import struct
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
QA_ROOT = ROOT / "qa_shots/hero"
DEFAULT_RIG = ROOT / "art_src/characters/hero_penguin_v1.blend"
SOCKETS = ("head_socket", "face_socket", "neck_socket", "trail_socket")
LOD_RANGES = ((20_000, 25_000), (8_000, 12_000))
UNIFIED_GEOMETRY_POLICY = "unified-face-r2-v1"
RETOPOLOGY_GEOMETRY_POLICY = "unified-retopo-r2-v1"
UNIFIED_GEOMETRY_POLICIES = (UNIFIED_GEOMETRY_POLICY, RETOPOLOGY_GEOMETRY_POLICY)
COMPONENT_MEMBERSHIP_FIELD = "candidate_component_membership_json"
UNIFIED_PROFILE = "unified-juvenile-face"
UNIFIED_GROUP = "JuvenileFace_ContinuousPigment_SourceOnly"
UNIFIED_PROGRAM_SHA256 = "25980d468bb5d613a2220de17f85c792dfa527d874e4db2108204de8db1e416b"
UNIFIED_EYE_CONTRACT = "continuous sclera/iris; 1.2mm iris dish + 0.7mm pupil recess; original painted catchlight"
GEOMETRY_POLICIES = ("legacy", "source-cover-v1", "source-cover-v2", *UNIFIED_GEOMETRY_POLICIES)
# Reviewed R2 aperture, frozen here rather than importing mutable sculpt code.
# Eye registration comes exclusively from the immutable candidate study binding.
UNIFIED_APERTURE = {"width": .105, "upper": .123, "lower": .104, "center_z": .006,
                    "outer_drop": .040, "nasal": .005, "corner_rounding": .018,
                    "depth": .055}
UNIFIED_APERTURE_PIN_M = .002
# Per-object, not whole-model decimation. Orbital rims and small details keep
# proportionally more geometry than the oversampled scalar-field body/feet.
COMPONENTS = (
    ("HeroBody", "body", 12_500),
    ("PaddleWing", "wing", 1_200),
    ("FusedWebbedFoot", "foot", 1_050),
    ("Claw", "toe", 60),
    ("EmbeddedSclera", "eye", 700),
    ("IntegratedOrbitalRim", "brow", 420),
    ("Iris", "eye", 96),
    ("LimbalRing", "eye", 96),
    ("Pupil", "eye", 96),
    ("Catchlight", "eye", 48),
    ("UpperBill", "bill", 600),
    ("LowerBill", "bill", 450),
    ("BillMouthSeam", "bill", 240),
    ("Nostril", "bill", 24),
    ("TailFeather", "tail", 140),
)
LIMITATIONS = [
    "Component-aware collapse is a review cage, not approved hand retopology; orbital and shoulder deformation need motion review.",
    "COLOR_0 is literal source paint for standalone PBR review. Provisional SemanticMasks remains in the .blend only; live semantic shader integration is still required.",
    "Semantic masks are estimated from saved paint colors; an explicit source mask bake is still required before production.",
    "Shared source feather tile is not a unique high-to-low atlas bake; cream uses the same neutral tile as dark plumage in this candidate.",
    "Feathers and smooth eyes/keratin use two PBR surfaces. Smooth details share one roughness proxy, not approved separate eye/bill/foot response.",
    "Cycles sheen and stage lighting are not reproduced; this is not proof of Compatibility material parity.",
    "Existing jaw/wing pivots and cosmetic sockets are preserved, not yet fitted to the changed sculpt.",
    "No collision-silhouette, cosmetic clipping, full motion, renderer, or performance approval is implied.",
]


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def component_spec(name: str) -> tuple[str, int]:
    for prefix, zone, triangles in COMPONENTS:
        if name.startswith(prefix):
            return zone, triangles
    raise ValueError(f"unclassified sculpt component: {name}")


def canonical_position(position) -> tuple[float, float, float]:
    """Proof -Y front -> existing Blender rig +Y front -> glTF/Godot -Z."""
    return float(position[0]), -float(position[1]), float(position[2])


def sole_fit_offset(policy: str, canonical_min: float, candidate_min: float) -> float:
    if policy == "none":
        return 0.0
    if policy != "canonical-rest":
        raise ValueError(f"unknown sole-fit policy: {policy}")
    return canonical_min - candidate_min


def smoothstep(low: float, high: float, value: float) -> float:
    t = max(0.0, min(1.0, (value - low) / (high - low)))
    return t * t * (3.0 - 2.0 * t)


def component_target(name: str, lod: int, policy: str) -> int:
    if policy not in GEOMETRY_POLICIES or lod not in (0, 1):
        raise ValueError("unsupported geometry policy or LOD")
    _zone, target = component_spec(name)
    if policy in UNIFIED_GEOMETRY_POLICIES:
        if name.startswith("HeroBody"):
            target = 14_000
        elif name.startswith("EmbeddedSclera"):
            # One integrated pigment/recess surface replaces separate iris,
            # pupil, catchlight and rim pieces; retain its whole color field.
            target = 1_100
    if policy in {"source-cover-v1", "source-cover-v2"}:
        if name.startswith("HeroBody"):
            target = 14_000
        elif policy == "source-cover-v1" and name.startswith("BillMouthSeam"):
            # Four unsubdivide iterations preserve the actual source's quad
            # ribbon instead of collapsing through its 4mm closed thickness.
            # Same mouth at both LODs; this is a target, never filler geometry.
            return 800
    return max(12, round(target * (1.0 if lod == 0 else 0.46)))


def unified_eye_frames(binding):
    """Read the reviewed source's immutable registration, never design code."""
    if (not isinstance(binding, dict) or binding.get("study_profile") != UNIFIED_PROFILE
            or binding.get("production_ready") is not False
            or binding.get("source_fidelity_approved") is not False):
        raise RuntimeError("unified geometry requires a bound, unapproved source study")
    record = binding.get("record")
    paint = record.get("continuous_paint_input") if isinstance(record, dict) else None
    if (not isinstance(record, dict) or record.get("study_profile") != UNIFIED_PROFILE
            or not isinstance(paint, dict) or paint.get("program_sha256") != UNIFIED_PROGRAM_SHA256
            or paint.get("body_material") != UNIFIED_GROUP + "_FeatherMaterial"
            or paint.get("body_vertex_color_dependency") is not False
            or paint.get("eye_radii") != [.13, .10, .17]):
        raise RuntimeError("unified geometry requires the reviewed R2 continuous-paint contract")
    raw = paint.get("eye_frames")
    if not isinstance(raw, dict) or set(raw) != {"-1.0", "1.0"}:
        raise RuntimeError("unified geometry requires both immutable eye frames")
    frames = {}
    for side in (-1., 1.):
        frame = raw[str(side)]
        if (not isinstance(frame, (list, tuple)) or len(frame) != 4
                or any(not isinstance(axis, (list, tuple)) or len(axis) != 3
                       or any(type(value) not in (int, float) or not math.isfinite(value) for value in axis)
                       for axis in frame)):
            raise RuntimeError("invalid immutable unified eye frame")
        origin, across, normal, up = tuple(tuple(float(value) for value in axis) for axis in frame)
        axes = (across, normal, up)
        if (any(abs(sum(value * value for value in axis) - 1.) > 1e-6 for axis in axes)
                or any(abs(sum(a * b for a, b in zip(axes[i], axes[j]))) > 1e-6
                       for i in range(3) for j in range(i))
                or not (.20 < side * origin[0] < .29 and -.42 < origin[1] < -.30
                        and 1.43 < origin[2] < 1.53 and across[0] > .5 and normal[1] < -.5 and up[2] > .8)):
            raise RuntimeError("immutable unified eye frame is outside the reviewed R2 contract")
        frames[side] = origin, across, normal, up
    return frames


def validate_geometry_binding(policy, binding):
    unified = isinstance(binding, dict) and binding.get("study_profile") == UNIFIED_PROFILE
    if policy in UNIFIED_GEOMETRY_POLICIES:
        unified_eye_frames(binding)
    elif unified:
        raise RuntimeError("unified source must not replay legacy X/Y source-cover bands")


def unified_aperture_coordinates(point, frame):
    if len(point) != 3 or not all(math.isfinite(value) for value in point):
        raise ValueError("unified aperture needs a finite source-space point")
    origin, across, normal, up = frame
    relative = tuple(a - b for a, b in zip(point, origin))
    return tuple(sum(a * b for a, b in zip(relative, axis)) for axis in (across, normal, up))


def unified_aperture_distance(x, z, side):
    p = UNIFIED_APERTURE
    vertical = z - p["center_z"] + p["outer_drop"] * side * x
    t = max(0., min(1., (vertical + .006) / .012))
    radius = p["lower"] + (p["upper"] - p["lower"]) * t * t * (3. - 2. * t)
    u = (x + side * p["nasal"]) / p["width"]
    return (u * u + math.sqrt((vertical / radius) ** 2 + p["corner_rounding"] ** 2) - 1.) * .080


def unified_aperture_source_pin(point, frames):
    for side, frame in frames.items():
        x, depth, z = unified_aperture_coordinates(point, frame)
        # Only the aperture edge and its shallow source wall, not an old cover
        # band, whole orbital cushion, or hidden back of the head.
        if (-UNIFIED_APERTURE["depth"] - .004 <= depth <= .060
                and abs(unified_aperture_distance(x, z, side)) <= UNIFIED_APERTURE_PIN_M):
            return True
    return False


def unified_aperture_collapse_weight(point, frames):
    importance = 0.
    for frame in frames.values():
        x, depth, z = unified_aperture_coordinates(point, frame)
        importance = max(importance, math.exp(-(x / .19) ** 2 - (z / .23) ** 2)
                         * smoothstep(-.10, -.02, depth))
    return max(.01, 1. - importance)


def unified_source_scope(binding, geometry_policy=UNIFIED_GEOMETRY_POLICY):
    frames = unified_eye_frames(binding)
    if geometry_policy not in UNIFIED_GEOMETRY_POLICIES:
        raise ValueError("unified scope requires an explicit supported policy")
    if geometry_policy == RETOPOLOGY_GEOMETRY_POLICY:
        return {"geometry_policy": geometry_policy,
                "derivation": "automated quad retopology, immutable source projection, deterministic triangulation",
                "source_coordinate_system": "saved source world space before canonical Y reflection",
                "eye_frames": {str(side): [list(axis) for axis in frame] for side, frame in frames.items()},
                "pin_scope": "no exact dense source patch; bounded source-surface error required",
                "whole_source_cover_proven": False, "production_ready": False,
                "geometry_approved": False, "source_fidelity_approved": False,
                "component_recovery": "immutable stored membership plus ordered rest-geometry digest; no solver replay"}
    return {"geometry_policy": geometry_policy,
            "source_coordinate_system": "immutable bilateral eye frames; source world space before Y reflection",
            "eye_frames": {str(side): [list(axis) for axis in frame] for side, frame in frames.items()},
            "aperture": UNIFIED_APERTURE.copy(), "aperture_field_band_m": UNIFIED_APERTURE_PIN_M,
            "depth_window_m": [-UNIFIED_APERTURE["depth"] - .004, .060],
            "pin_scope": "aperture edge and one incident source-face boundary only",
            "whole_source_cover_proven": False, "production_ready": False,
            "source_fidelity_approved": False}


def orbital_source_pin(point, *, near_lod: bool) -> bool:
    """Frozen X/Y source-coordinate bands around measured failed cover rays.

    Bilateral original head surface, not extra cover geometry or eye masking.
    Near LOD also retains the inner-orbit fold found by the strict Y bake.
    """
    if len(point) != 3 or not all(math.isfinite(value) for value in point):
        raise ValueError("orbital pin needs a finite source-space point")
    x, y, z = point
    upper_cover = 0.08 < abs(x) < 0.30 and -0.36 < y < -0.22 and abs(z - 1.648) < 0.006
    inner_fold = (near_lod and 0.075 < abs(x) < 0.115 and -0.35 < y < -0.27
                  and 1.585 < z < 1.620)
    return upper_cover or inner_fold


def orbital_collapse_weight(point) -> float:
    x, y, z = point
    importance = math.exp(-((abs(x)-0.17)/0.17)**2-((z-1.60)/0.16)**2)
    importance *= smoothstep(0.05, 0.23, -y)
    # Blender's weight is collapse permission, NOT protection: low values
    # increase edge cost; exactly zero hard-locks touching edges.
    return max(0.01, 1.0 - importance)


def oriented_face_key(points):
    points = tuple(tuple(point) for point in points)
    return min(points[index:] + points[:index] for index in range(len(points)))


def pinned_geometry_state(positions, faces, preserved_positions, preserved_faces):
    """Exact phase evidence; never substitute proximity or repaired vertices."""
    positions, faces = list(positions), list(faces)
    actual = {tuple(point) for point in positions}
    actual_faces = {oriented_face_key(points) for points in faces if len(points) == 3}
    expected = set(preserved_positions)
    missing = expected - actual
    missing_faces = preserved_faces - actual_faces
    return {"actual_vertices": len(positions), "actual_triangles": sum(len(face) == 3 for face in faces),
            "pinned_source_vertices": len(expected), "pinned_source_triangles": len(preserved_faces),
            "missing_pinned_vertices": len(missing), "missing_pinned_triangles": len(missing_faces),
            "first_missing_source_positions": [list(point) for point in sorted(missing)[:8]],
            "first_missing_source_triangles": [[list(point) for point in face] for face in sorted(missing_faces)[:4]],
            "exact": not missing and not missing_faces}


def record_pin_phase(component, policy, target, phase, positions, faces, preserved_positions, preserved_faces):
    state = pinned_geometry_state(positions, faces, preserved_positions, preserved_faces)
    state.update(component=component, geometry_policy=policy, target_triangles=target, phase=phase)
    print("[v12-candidate-pin] " + json.dumps(state, sort_keys=True, allow_nan=False), flush=True)
    if not state["exact"]:
        raise RuntimeError("hard-pinned source geometry changed: " + json.dumps(state, sort_keys=True, allow_nan=False))
    return state


def unified_cleanup_inputs(edit, preserved_positions):
    """Do not let cleanup erase Decimate's zero-weight endpoint protection.

    BMesh weld/dissolve operators do not read the Decimate vertex group. The
    reviewed pin coordinates and their triangle neighborhood stay out of both
    mutation lists; exact phase checks still reject any indirect change.
    """
    protected = set(preserved_positions)
    vertices = [vertex for vertex in edit.verts if tuple(vertex.co) not in protected]
    edges = [edge for edge in edit.edges
             if all(tuple(vertex.co) not in protected for vertex in edge.verts)
             and all(all(tuple(vertex.co) not in protected for vertex in face.verts) for face in edge.link_faces)]
    return vertices, edges


def require_feasible_source_pins(component, policy, pinned_triangles):
    """Reject an impossible exact-source cage before reduction or tangent work.

    The largest whole-character ceiling is an intentionally generous necessary
    condition, not a new component allowance or LOD acceptance. The final
    per-LOD mesh budgets remain mandatory. No pin is dropped to satisfy them.
    """
    if type(pinned_triangles) is not int or pinned_triangles < 0:
        raise ValueError("pinned source triangle count must be a nonnegative integer")
    if policy not in GEOMETRY_POLICIES:
        raise ValueError("unknown candidate geometry policy")
    ceiling = max(high for _low, high in LOD_RANGES)
    if policy == UNIFIED_GEOMETRY_POLICY and pinned_triangles > ceiling:
        raise RuntimeError(
            f"{component}: {pinned_triangles} exact protected source triangles exceed "
            f"whole-character maximum {ceiling}; budgeted retopology required, no pins waived")


def verify_retopology_helper(audit):
    """Baking may consume a saved cage, never a changed derivation helper."""
    path = Path(__file__).with_name("hero_penguin_v12_retopology.py").resolve()
    expected = {"path": str(path), "sha256": file_sha256(path)}
    if (audit.get("geometry_policy") != RETOPOLOGY_GEOMETRY_POLICY
            or audit.get("retopology_helper") != expected):
        raise RuntimeError("retopology helper binding changed or missing; reconstruction forbidden")
    return expected


def component_geometry_signatures(mesh, assignments, names):
    """Bind exact ordered rest geometry without rerunning a topology solver."""
    if (not names or len(set(names)) != len(names)
            or len(assignments) != len(mesh.vertices)
            or any(type(value) is not int or not 0 <= value < len(names) for value in assignments)):
        raise RuntimeError("invalid stored source component membership")
    rows, faces = [], []
    for polygon in mesh.polygons:
        members = {assignments[index] for index in polygon.vertices}
        if len(polygon.vertices) != 3 or len(members) != 1:
            raise RuntimeError("stored cage face is non-triangular or bridges source components")
        faces.append(next(iter(members)))
    for component, name in enumerate(names):
        indices = [i for i, member in enumerate(assignments) if member == component]
        if not indices:
            raise RuntimeError("stored component has no cage vertices: " + name)
        local = {index: i for i, index in enumerate(indices)}
        digest = hashlib.sha256()
        for index in indices:
            point = tuple(mesh.vertices[index].co)
            if len(point) != 3 or not all(math.isfinite(value) for value in point):
                raise RuntimeError("stored cage has nonfinite geometry")
            digest.update(struct.pack("<3f", *point))
        triangles = 0
        for polygon, member in zip(mesh.polygons, faces):
            if member == component:
                digest.update(struct.pack("<3I", *(local[index] for index in polygon.vertices)))
                triangles += 1
        rows.append({"source": name, "vertices": len(indices), "triangles": triangles,
                     "ordered_geometry_sha256": digest.hexdigest()})
    return rows, faces


def recover_stored_components(mesh, sources, lod, audit):
    """Recover only the exact audited cage; no proximity match or re-solve."""
    verify_retopology_helper(audit)
    try:
        saved = json.loads(mesh[COMPONENT_MEMBERSHIP_FIELD])
    except (KeyError, TypeError, ValueError) as error:
        raise RuntimeError("missing or malformed immutable cage membership") from error
    names = [source.name for source in sources]
    if (not isinstance(saved, dict) or set(saved) != {"sources", "vertices"}
            or saved["sources"] != names or not isinstance(saved["vertices"], list)):
        raise RuntimeError("stored cage source order or membership differs")
    rows, faces = component_geometry_signatures(mesh.data, saved["vertices"], names)
    if audit["lods"][lod].get("source_component_geometry") != rows:
        raise RuntimeError("stored cage geometry differs from immutable candidate audit")
    components = [row for row in audit["components"] if row["lod"] == lod]
    if ([row["source"] for row in components] != names
            or any(row["after"] != shape["triangles"]
                   or row["target"] != component_target(row["source"], lod, RETOPOLOGY_GEOMETRY_POLICY)
                   for row, shape in zip(components, rows))):
        raise RuntimeError("stored cage component audit differs")
    return saved["vertices"], faces


def uv_double_area(coords) -> float:
    a, b, c = coords[:3]
    return abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))


def stable_face_uvs(points, wing: bool):
    coords = [(0.5 + (abs(x) * 0.95 + z * 0.30) / 2.4, z / 1.80) if wing
              else (0.5 + math.atan2(x, -y) / math.tau, z / 1.80)
              for x, y, z in points]
    crossing = not wing and max(value[0] for value in coords) - min(value[0] for value in coords) > 0.5
    coords = [(2.0 * (u + (1.0 if crossing and u < 0.5 else 0.0)), 1.7 * v) for u, v in coords]
    if uv_double_area(coords) > 1e-10:
        return coords, False
    # Cylinders collapse on horizontal caps and tangential eye/bill faces.
    # Project each such face into the plane with greatest geometric area.
    # No fabricated zero tangents or post-export validator suppression.
    candidates = [[(0.5 + point[a], 0.5 + point[b]) for point in points]
                  for a, b in ((0, 1), (0, 2), (1, 2))]
    coords = max(candidates, key=uv_double_area)
    area = uv_double_area(coords)
    if area < 1e-16:
        raise RuntimeError("zero-area geometry reached UV generation")
    # Tiny eye paint fans need enough UV area to survive float32 export.
    # This explicitly changes detail scale only on otherwise collapsed faces.
    scale = max(1.0, math.sqrt(1e-7 / area))
    u0, v0 = coords[0]
    return [(0.25 + (u - u0) * scale, 0.25 + (v - v0) * scale) for u, v in coords], True


def estimate_semantic_mask(color, zone: str) -> tuple[float, float, float, float]:
    """Explicitly provisional mapping; do not disguise literal RGB as masks."""
    r, g, b = color[:3]
    if zone not in {"body", "wing", "brow", "tail"}:
        response = 0.11 if zone == "eye" else (0.24 if zone in {"foot", "toe"} else 0.19)
        return r, g, b, response
    cream = smoothstep(0.10, 0.62, min(r, g))
    warm = smoothstep(0.10, 0.38, r - b) * (1.0 - cream)
    identity = smoothstep(0.06, 0.23, min(g, b) - r) * 0.32
    return min(1.0, cream + identity), min(1.0, warm + identity), identity, 0.97


def safe_output_dir(value: str) -> Path:
    output = Path(value).resolve()
    if not output.is_relative_to(QA_ROOT.resolve()) or output == QA_ROOT.resolve():
        raise ValueError(f"candidate outputs must be in a dedicated child of {QA_ROOT}")
    if output.exists() and any(output.iterdir()):
        raise ValueError(f"output directory is not empty; preserve earlier evidence: {output}")
    return output


def parse_args() -> argparse.Namespace:
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-blend", type=Path, required=True)
    parser.add_argument("--rig-blend", type=Path, default=DEFAULT_RIG)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--sole-fit", choices=("none", "canonical-rest"), default="none",
                        help="optional constant foot/toe mesh Z fit; never changes bones or animation")
    parser.add_argument("--geometry-policy", choices=GEOMETRY_POLICIES, default="source-cover-v2",
                        help="explicit source-bound QA recipe; unified R2 requires an explicit unified policy; legacy recipes remain replayable")
    return parser.parse_args(values)


def triangle_count(obj) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def activate(obj) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def load_rig(path: Path):
    with bpy.data.libraries.load(str(path), link=False) as (source, target):
        wanted = ["PenguinSkeleton", *SOCKETS, "HeroPenguinMesh"]
        missing = set(wanted) - set(source.objects)
        if missing:
            raise RuntimeError(f"canonical rig missing objects: {sorted(missing)}")
        target.objects = wanted
        target.actions = list(legacy.REQUIRED_ACTIONS)
    objects = [obj for obj in target.objects if obj is not None]
    armature = next(obj for obj in objects if obj.type == "ARMATURE")
    canonical_mesh = next(obj for obj in objects if obj.type == "MESH")
    canonical_indices = legacy.foot_vertex_indices(canonical_mesh, "L") + legacy.foot_vertex_indices(canonical_mesh, "R")
    canonical_sole = min((canonical_mesh.matrix_world @ canonical_mesh.data.vertices[index].co).z
                         for index in canonical_indices)
    objects.remove(canonical_mesh)
    canonical_data = canonical_mesh.data
    bpy.data.objects.remove(canonical_mesh, do_unlink=True)
    if canonical_data.users == 0:
        bpy.data.meshes.remove(canonical_data)
    armature.animation_data_create()
    armature.animation_data.action = None
    legacy.reset_pose(armature)
    for action in target.actions:
        if action is None:
            raise RuntimeError("canonical animation library is incomplete")
        action.use_fake_user = True
    collection = bpy.data.collections.new("V12CandidateRig")
    bpy.context.scene.collection.children.link(collection)
    for obj in objects:
        collection.objects.link(obj)
    return armature, objects, canonical_sole


def rest_digest(armature) -> str:
    data = [(bone.name, bone.parent.name if bone.parent else None,
             tuple(tuple(row) for row in bone.matrix_local)) for bone in armature.data.bones]
    return hashlib.sha256(repr(data).encode()).hexdigest()


def reduce_component(source, target_triangles: int, collection, geometry_policy: str = "legacy", *, study_binding=None):
    if geometry_policy not in GEOMETRY_POLICIES:
        raise ValueError("unknown candidate geometry policy")
    validate_geometry_binding(geometry_policy, study_binding)
    if geometry_policy == RETOPOLOGY_GEOMETRY_POLICY and source.name.startswith("HeroBody"):
        from hero_penguin_v12_retopology import build_body
        return build_body(source, target_triangles, collection, unified_eye_frames(study_binding))
    frames = unified_eye_frames(study_binding) if geometry_policy == UNIFIED_GEOMETRY_POLICY else None
    import bmesh
    obj = source.copy()
    obj.data = source.data.copy()
    collection.objects.link(obj)
    activate(obj)
    # Apply the saved object's actual matrix before reflection, never current
    # design helpers: source E/F snapshots must remain independently repeatable.
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    before = triangle_count(obj)
    # Source eye paint fans contain coincident center-ring vertices. Weld
    # within this component only, removing genuine zero-area faces before
    # reduction/UV tangents; do not join or weld separate orbital layers.
    edit = bmesh.new()
    edit.from_mesh(obj.data)
    bmesh.ops.remove_doubles(edit, verts=list(edit.verts), dist=1e-5)
    bmesh.ops.dissolve_degenerate(edit, edges=list(edit.edges), dist=1e-6)
    invalid = [face for face in edit.faces if face.calc_area() < 1e-12]
    if invalid:
        bmesh.ops.delete(edit, geom=invalid, context="FACES_ONLY")
    loose = [vertex for vertex in edit.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(edit, geom=loose, context="VERTS")
    edit.to_mesh(obj.data)
    edit.free()
    cleaned = triangle_count(obj)
    obj["candidate_removed_degenerate_triangles"] = before - cleaned
    preserved_positions = []
    preserved_faces = set()
    if geometry_policy in {"source-cover-v1", "source-cover-v2", UNIFIED_GEOMETRY_POLICY} and source.name.startswith("HeroBody"):
        pinned = {vertex.index for vertex in obj.data.vertices
                  if (unified_aperture_source_pin(tuple(vertex.co), frames) if frames is not None
                      else orbital_source_pin(tuple(vertex.co), near_lod=target_triangles >= 10_000))}
        if frames is not None and not pinned:
            raise RuntimeError("unified body has no source vertices in its bound aperture-edge pin band")
        seed = set(pinned)
        # Pin each incident face's complete corner set so source topology in
        # the measured band is retained, with a one-face shared-edge boundary.
        faces = [face for face in obj.data.polygons if seed.intersection(face.vertices)]
        pinned.update(index for face in faces for index in face.vertices)
        preserved_positions = [tuple(obj.data.vertices[index].co) for index in sorted(pinned)]
        preserved_faces = {oriented_face_key(tuple(obj.data.vertices[index].co) for index in face.vertices)
                           for face in faces if len(face.vertices) == 3}
        obj["candidate_pinned_source_vertices"] = len(pinned)
        obj["candidate_pinned_source_triangles"] = len(preserved_faces)
        require_feasible_source_pins(source.name, geometry_policy, len(preserved_faces))
    if geometry_policy == "source-cover-v1" and source.name.startswith("BillMouthSeam"):
        modifier = obj.modifiers.new("PreserveSourceMouthQuadRibbon", "DECIMATE")
        modifier.decimate_type = "UNSUBDIV"
        modifier.iterations = 4
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj["candidate_mouth_reduction"] = "source quad unsubdivide 4; no cross-thickness collapse"
    elif cleaned > target_triangles:
        modifier = obj.modifiers.new("CandidateComponentReduction", "DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = target_triangles / cleaned
        modifier.use_collapse_triangulate = True
        if source.name.startswith("HeroBody"):
            protect = obj.vertex_groups.new(name="CandidateOrbitalProtection")
            for vertex in obj.data.vertices:
                x, y, z = vertex.co
                if geometry_policy in {"source-cover-v1", "source-cover-v2", UNIFIED_GEOMETRY_POLICY}:
                    weight = (0.0 if vertex.index in pinned else
                              unified_aperture_collapse_weight((x, y, z), frames) if frames is not None
                              else orbital_collapse_weight((x, y, z)))
                else:
                    orbital = math.exp(-((abs(x) - 0.15) / 0.15) ** 2 - ((z - 1.54) / 0.19) ** 2)
                    orbital *= smoothstep(0.05, 0.23, -y)
                    weight = max(0.01, orbital)
                protect.add([vertex.index], weight, "REPLACE")
            modifier.vertex_group = protect.name
            modifier.vertex_group_factor = 4.0
            modifier.invert_vertex_group = False
            # Pinned Blender 5.2 source: zero endpoint weight excludes edge;
            # nonzero cost uses (2-w1-w2)*factor. Previous high eye weights
            # accidentally made its millimeter cover cheaper to collapse.
            # https://github.com/blender/blender/blob/v5.2.0/source/blender/bmesh/tools/bmesh_decimate_collapse.cc#L224-L295
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    pin_phases = []
    if frames is not None and preserved_positions:
        pin_phases.append(record_pin_phase(source.name, geometry_policy, target_triangles, "post-decimation-before-cleanup",
            [tuple(vertex.co) for vertex in obj.data.vertices],
            [tuple(tuple(obj.data.vertices[index].co) for index in face.vertices) for face in obj.data.polygons],
            preserved_positions, preserved_faces))
    # Collapse may create new microscopic slivers. Weld within 10 micrometers
    # again, far below reviewed silhouette detail, before tangent generation.
    # Only unified R2 uses pin-aware cleanup. Legacy geometry recipes remain
    # byte-replayable, including their original all-vertex cleanup lists.
    edit = bmesh.new()
    edit.from_mesh(obj.data)
    if frames is not None and preserved_positions:
        vertices, _edges = unified_cleanup_inputs(edit, preserved_positions)
        bmesh.ops.remove_doubles(edit, verts=vertices, dist=1e-5)
        pin_phases.append(record_pin_phase(source.name, geometry_policy, target_triangles, "post-pin-aware-weld",
            [tuple(vertex.co) for vertex in edit.verts],
            [tuple(tuple(vertex.co) for vertex in face.verts) for face in edit.faces],
            preserved_positions, preserved_faces))
        _vertices, edges = unified_cleanup_inputs(edit, preserved_positions)
        bmesh.ops.dissolve_degenerate(edit, edges=edges, dist=1e-6)
        pin_phases.append(record_pin_phase(source.name, geometry_policy, target_triangles, "post-pin-aware-degenerate-cleanup",
            [tuple(vertex.co) for vertex in edit.verts],
            [tuple(tuple(vertex.co) for vertex in face.verts) for face in edit.faces],
            preserved_positions, preserved_faces))
    else:
        bmesh.ops.remove_doubles(edit, verts=list(edit.verts), dist=1e-5)
        bmesh.ops.dissolve_degenerate(edit, edges=list(edit.edges), dist=1e-6)
    edit.to_mesh(obj.data)
    edit.free()
    if pin_phases:
        pin_phases.append(record_pin_phase(source.name, geometry_policy, target_triangles, "post-cleanup-mesh-serialization",
            [tuple(vertex.co) for vertex in obj.data.vertices],
            [tuple(tuple(obj.data.vertices[index].co) for index in face.vertices) for face in obj.data.polygons],
            preserved_positions, preserved_faces))
        obj["candidate_pin_preservation_json"] = json.dumps(pin_phases, sort_keys=True, allow_nan=False)
    if preserved_positions:
        actual = {tuple(vertex.co) for vertex in obj.data.vertices}
        if not set(preserved_positions) <= actual:
            raise RuntimeError("reduction moved or removed hard-pinned source cover vertices")
        actual_faces = {oriented_face_key(tuple(obj.data.vertices[index].co) for index in face.vertices)
                        for face in obj.data.polygons if len(face.vertices) == 3}
        if not preserved_faces <= actual_faces:
            raise RuntimeError("reduction changed hard-pinned source cover triangles")
        obj["candidate_source_cover_exact"] = True
    for group in list(obj.vertex_groups):
        obj.vertex_groups.remove(group)
    return obj, before, triangle_count(obj)


def unified_eye_colors(obj):
    """Fail closed for the new single-surface eye; legacy paint is unchanged."""
    get = getattr(obj, "get", lambda _key: None)
    contract = get("eye_surface_contract")
    materials = obj.data.materials
    material = materials[0] if len(materials) == 1 else None
    recognized = material is not None and material.name.split(".", 1)[0] == "JuvenileSeatedEyeSurface"
    if contract is None and not recognized:
        return None
    pigment = obj.data.color_attributes.get("PreviewColor")
    if (contract != UNIFIED_EYE_CONTRACT or obj.name.split(".", 1)[0] not in {"EmbeddedSclera+1", "EmbeddedSclera-1"}
            or pigment is None or pigment.domain != "POINT" or pigment.data_type != "FLOAT_COLOR"
            or len(pigment.data) != len(obj.data.vertices)):
        raise RuntimeError("integrated unified eye requires its exact FLOAT_COLOR POINT PreviewColor contract")
    if not recognized or not material.use_nodes or material.node_tree is None:
        raise RuntimeError("integrated unified eye requires JuvenileSeatedEyeSurface")
    outputs = [node for node in material.node_tree.nodes if node.type == "OUTPUT_MATERIAL" and node.is_active_output]
    surface = list(outputs[0].inputs["Surface"].links) if len(outputs) == 1 else []
    bsdf = surface[0].from_node if len(surface) == 1 else None
    colors = list(bsdf.inputs["Base Color"].links) if bsdf is not None and bsdf.type == "BSDF_PRINCIPLED" else []
    if (len(colors) != 1 or colors[0].from_node.type != "VERTEX_COLOR"
            or colors[0].from_node.layer_name != "PreviewColor" or colors[0].from_socket.name != "Color"):
        raise RuntimeError("integrated unified eye PreviewColor must directly drive its active BSDF")
    values = [tuple(item.color) for item in pigment.data]
    if any(len(value) != 4 or any(not math.isfinite(channel) or not 0 <= channel <= 1 for channel in value)
           or value[3] != 1. for value in values):
        raise RuntimeError("integrated unified eye contains invalid linear pigment")
    return values


def source_colors(obj) -> list[tuple[float, ...]]:
    """Read literal linear source paint without replacing legacy precedence.

    IrisPigment is an explicit new source contract, not a generic search for
    any color layer. Its direct material binding must match the supported iris
    component; otherwise a diffuse fallback would silently erase authored art.
    """
    integrated = unified_eye_colors(obj)
    if integrated is not None:
        return integrated
    attribute = obj.data.color_attributes.get("PreviewColor")
    if attribute is not None and attribute.domain == "POINT":
        return [tuple(value.color) for value in attribute.data]
    if attribute is not None and attribute.domain == "CORNER":
        values = [(0.0, 0.0, 0.0, 1.0)] * len(obj.data.vertices)
        for loop in obj.data.loops:
            values[loop.vertex_index] = tuple(attribute.data[loop.index].color)
        return values
    pigment = obj.data.color_attributes.get("IrisPigment")
    if pigment is not None:
        if obj.name.split(".", 1)[0] not in {"Iris+1", "Iris-1"}:
            raise RuntimeError("IrisPigment is only supported on the bilateral iris components")
        if (pigment.domain != "POINT" or pigment.data_type != "FLOAT_COLOR"
                or len(pigment.data) != len(obj.data.vertices)):
            raise RuntimeError("IrisPigment requires FLOAT_COLOR POINT data for every iris vertex")
        materials = obj.data.materials
        material = materials[0] if len(materials) == 1 else None
        if (material is None or material.name.split(".", 1)[0] != "BlueGrayIris"
                or not material.use_nodes or material.node_tree is None):
            raise RuntimeError("IrisPigment requires the supported BlueGrayIris source material")
        outputs = [node for node in material.node_tree.nodes
                   if node.type == "OUTPUT_MATERIAL" and node.is_active_output]
        surface_links = list(outputs[0].inputs["Surface"].links) if len(outputs) == 1 else []
        bsdf = surface_links[0].from_node if len(surface_links) == 1 else None
        color_links = list(bsdf.inputs["Base Color"].links) if bsdf is not None and bsdf.type == "BSDF_PRINCIPLED" else []
        if (len(color_links) != 1 or color_links[0].from_node.type != "VERTEX_COLOR"
                or color_links[0].from_node.layer_name != "IrisPigment"
                or color_links[0].from_socket.name != "Color"):
            raise RuntimeError("IrisPigment must directly drive the active iris BSDF Base Color")
        # FLOAT_COLOR .color is already linear; never use .color_srgb, infer
        # from RGB, or multiply by the material's fallback diffuse swatch.
        return [tuple(value.color) for value in pigment.data]
    material = obj.data.materials[0] if obj.data.materials else None
    color = tuple(material.diffuse_color) if material is not None else (0.1, 0.1, 0.1, 1.0)
    return [color] * len(obj.data.vertices)


def paint_summary(colors) -> dict:
    """Keep literal color sentinels at every reduction/serialization boundary."""
    values = [tuple(float(channel) for channel in color) for color in colors]
    if not values:
        raise ValueError("candidate paint has no samples")
    return {"samples": len(values), "first": values[0],
            "minimum": [min(color[channel] for color in values) for channel in range(4)],
            "maximum": [max(color[channel] for color in values) for channel in range(4)],
            "mean": [sum(color[channel] for color in values) / len(values) for channel in range(4)],
            "linear_float_sha256": hashlib.sha256(b"".join(struct.pack("<4f", *color) for color in values)).hexdigest()}


def component_weights(name: str, zone: str, point):
    x, _y, z = point
    side = "L" if x < 0.0 else "R"
    if zone == "body":
        return legacy.torso_weights(point)
    if zone == "wing":
        # The root patch follows the chest, easing into the existing wing bone
        # over the upper 14 cm. No automatic envelope/nearest-bone ambiguity.
        wing = 1.0 - smoothstep(1.08, 1.22, z)
        return {"spine_upper": 1.0 - wing, f"wing.{side}": wing}
    if zone in {"foot", "toe"}:
        return {f"toe.{side}" if zone == "toe" else f"foot.{side}": 1.0}
    if zone == "tail":
        tail = smoothstep(0.31, 0.43, -point[1])
        return {"pelvis": 1.0 - tail, "tail": tail}
    return {"bill" if name.startswith("LowerBill") else "head": 1.0}


def joined_candidate(parts: list, collection, armature, name: str,
                     sole_policy: str, canonical_sole: float, component_sources=None):
    builder = legacy.MeshBuilder()
    component_names = []
    source_points = []
    literal_colors = []
    assignments = []
    if component_sources is not None and len(component_sources) != len(parts):
        raise RuntimeError("cage source order must cover every component")
    candidate_sole = min(vertex.co.z for part in parts if component_spec(part.name.split(".00")[0])[0] in {"foot", "toe"}
                         for vertex in part.data.vertices)
    foot_offset = sole_fit_offset(sole_policy, canonical_sole, candidate_sole)
    for component, obj in enumerate(parts):
        zone, _target = component_spec(obj.name.split(".00")[0])
        colors = source_colors(obj)
        start = len(builder.vertices)
        for vertex in obj.data.vertices:
            original = tuple(vertex.co)
            point = canonical_position(original)
            if zone in {"foot", "toe"}:
                point = point[0], point[1], point[2] + foot_offset
            color = colors[vertex.index]
            actual_zone = "head" if zone == "body" and point[2] > 1.19 else zone
            builder.vertex(point, estimate_semantic_mask(color, zone),
                           component_weights(obj.name, zone, point), actual_zone)
            literal_colors.append((*color[:3], 1.0))
            component_names.append(obj.name)
            source_points.append(original)
            assignments.append(component)
        for polygon in obj.data.polygons:
            builder.face(tuple(start + index for index in reversed(polygon.vertices)),
                         0 if zone in {"body", "wing", "brow", "tail"} else 1)
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(builder.vertices, [], builder.faces)
    mesh.update(calc_edges=True)
    obj = bpy.data.objects.new(name, mesh)
    if component_sources is not None:
        obj[COMPONENT_MEMBERSHIP_FIELD] = json.dumps({"sources": component_sources, "vertices": assignments},
                                                   sort_keys=True, allow_nan=False)
    collection.objects.link(obj)
    obj["candidate_sole_fit_policy"] = sole_policy
    obj["candidate_sole_original_m"] = candidate_sole
    obj["candidate_sole_canonical_m"] = canonical_sole
    obj["candidate_sole_offset_m"] = foot_offset
    paint = mesh.color_attributes.new(name="COLOR_0", type="FLOAT_COLOR", domain="CORNER")
    semantics = mesh.color_attributes.new(name="SemanticMasks", type="FLOAT_COLOR", domain="CORNER")
    uv = mesh.uv_layers.new(name="FeatherReviewUV")
    fallback_faces = 0
    for polygon in mesh.polygons:
        polygon.material_index = builder.face_materials[polygon.index]
        polygon.use_smooth = True
        coords, fallback = stable_face_uvs([source_points[index] for index in polygon.vertices],
                                           component_names[polygon.vertices[0]].startswith("PaddleWing"))
        fallback_faces += int(fallback)
        for loop_index, (u, v) in zip(polygon.loop_indices, coords):
            index = mesh.loops[loop_index].vertex_index
            paint.data[loop_index].color = literal_colors[index]
            semantics.data[loop_index].color = builder.colors[index]
            uv.data[loop_index].uv = (u, v)
    obj["candidate_uv_fallback_faces"] = fallback_faces
    mesh.color_attributes.active_color = paint
    mesh.color_attributes.render_color_index = 0
    repair_tangent_charts(obj)
    zones = mesh.attributes.new(name="_species_zone", type="FLOAT", domain="POINT")
    values = {"body": 0.1, "head": 0.2, "wing": 0.3, "eye": 0.5,
              "brow": 0.6, "bill": 0.7, "foot": 0.8, "toe": 0.85, "tail": 0.9}
    for index, zone in enumerate(builder.zones):
        zones.data[index].value = values[zone]
    for bone in armature.data.bones:
        group = obj.vertex_groups.new(name=bone.name)
        for index, weights in enumerate(builder.weights):
            if bone.name in weights:
                group.add([index], weights[bone.name], "REPLACE")
    modifier = obj.modifiers.new("PenguinSkeleton", "ARMATURE")
    modifier.object = armature
    obj.parent = armature
    obj.matrix_parent_inverse.identity()
    legacy.create_species_shapes(obj, builder)
    for part in parts:
        bpy.data.objects.remove(part, do_unlink=True)
    return obj, builder


def repair_tangent_charts(obj) -> None:
    """Resolve actual MikkTSpace singularities by making local UV charts.

    This changes authored UVs, not exported tangent values or validator limits.
    Narrow flipper edges can have valid 2D triangle area yet averaged cylinder
    derivatives cancel. Splitting their UV chart removes that singularity.
    """
    mesh = obj.data
    uv = mesh.uv_layers.active
    repaired = set()
    flat = set()
    for attempt in range(3):
        mesh.calc_tangents()
        bad_loops = {loop.index for loop in mesh.loops if loop.tangent.length < 0.5}
        if not bad_loops:
            obj["candidate_tangent_chart_faces"] = len(repaired)
            obj["candidate_flat_normal_faces"] = len(flat)
            return
        for polygon in mesh.polygons:
            if not bad_loops.intersection(polygon.loop_indices):
                continue
            points = [mesh.vertices[index].co for index in polygon.vertices]
            origin = points[0]
            tangent = max((point - origin for point in points[1:]), key=lambda value: value.length_squared).normalized()
            across = polygon.normal.cross(tangent).normalized()
            scale = max(1.0, 0.02 / max((point - origin).length for point in points[1:]))
            for loop_index, point in zip(polygon.loop_indices, points):
                offset = point - origin
                uv.data[loop_index].uv = (0.25 + offset.dot(tangent) * scale,
                                         0.25 + offset.dot(across) * scale)
            repaired.add(polygon.index)
            if attempt > 0:
                polygon.use_smooth = False
                flat.add(polygon.index)
        mesh.update()
    raise RuntimeError(f"unresolved source tangent chart singularity on {obj.name}")


def candidate_material(output: Path):
    """Two review PBR surfaces: feather detail never embosses the eyes/bill."""
    material = bpy.data.materials.new("V12CandidateUnapprovedFeathers")
    material.use_nodes = True
    material.use_backface_culling = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    principled = nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    principled.inputs["Roughness"].default_value = 0.79
    principled.inputs["Metallic"].default_value = 0.0
    source_images = {}
    for kind in ("albedo", "normal", "orm"):
        image_name = f"hero_penguin_v11_dark_{kind}_tile.png"
        image = bpy.data.images.get(image_name)
        if image is None or image.packed_file is None:
            raise RuntimeError(f"saved sculpt must contain packed map: {image_name}")
        target = output / image_name
        target.write_bytes(image.packed_file.data)
        node = nodes.new("ShaderNodeTexImage")
        node.image = image
        node.extension = "REPEAT"
        node.interpolation = "Linear"
        source_images[kind] = {"path": target.name, "sha256": file_sha256(target), "size": list(image.size)}
        if kind == "albedo":
            # glTF multiplies exported COLOR_0 by baseColorTexture. Blender's
            # source material uses the same multiply for review consistency.
            color = nodes.new("ShaderNodeVertexColor")
            color.layer_name = "COLOR_0"
            multiply = nodes.new("ShaderNodeMixRGB")
            multiply.blend_type = "MULTIPLY"
            multiply.inputs[0].default_value = 1.0
            links.new(color.outputs["Color"], multiply.inputs[1])
            links.new(node.outputs["Color"], multiply.inputs[2])
            links.new(multiply.outputs[0], principled.inputs["Base Color"])
        elif kind == "normal":
            normal = nodes.new("ShaderNodeNormalMap")
            normal.inputs["Strength"].default_value = 0.38
            links.new(node.outputs["Color"], normal.inputs["Color"])
            links.new(normal.outputs["Normal"], principled.inputs["Normal"])
        else:
            separate = nodes.new("ShaderNodeSeparateColor")
            links.new(node.outputs["Color"], separate.inputs["Color"])
            links.new(separate.outputs["Green"], principled.inputs["Roughness"])
    smooth = bpy.data.materials.new("V12CandidateUnapprovedSmoothDetails")
    smooth.use_nodes = True
    smooth.use_backface_culling = True
    smooth_bsdf = smooth.node_tree.nodes.get("Principled BSDF")
    smooth_bsdf.inputs["Roughness"].default_value = 0.38
    smooth_bsdf.inputs["Metallic"].default_value = 0.0
    smooth_color = smooth.node_tree.nodes.new("ShaderNodeVertexColor")
    smooth_color.layer_name = "COLOR_0"
    smooth.node_tree.links.new(smooth_color.outputs["Color"], smooth_bsdf.inputs["Base Color"])
    return [material, smooth], source_images


def mesh_audit(obj, builder) -> dict:
    obj.data.calc_loop_triangles()
    uv = obj.data.uv_layers.active
    degenerate_uv = 0
    for triangle in obj.data.loop_triangles:
        a, b, c = (uv.data[index].uv for index in triangle.loops)
        if abs((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) < 1e-12:
            degenerate_uv += 1
    return {
        "name": obj.name, "triangles": len(obj.data.loop_triangles),
        "vertices": len(obj.data.vertices), "materials": len(obj.data.materials),
        "max_skin_weights": max(len(weights) for weights in builder.weights),
        "unweighted_vertices": sum(not vertex.groups for vertex in obj.data.vertices),
        "species_shapes": [key.name for key in obj.data.shape_keys.key_blocks if key.name != "Basis"],
        "degenerate_uv_triangles": degenerate_uv,
        "planar_uv_fallback_faces": int(obj.get("candidate_uv_fallback_faces", 0)),
        "tangent_chart_faces": int(obj.get("candidate_tangent_chart_faces", 0)),
        "flat_normal_faces": int(obj.get("candidate_flat_normal_faces", 0)),
        "sole_fit": {"policy": obj["candidate_sole_fit_policy"],
                     "canonical_rest_min_m": obj["candidate_sole_canonical_m"],
                     "original_rest_min_m": obj["candidate_sole_original_m"],
                     "constant_foot_toe_offset_z_m": obj["candidate_sole_offset_m"]},
        "degenerate_geometry_triangles": sum(triangle.area < 1e-14 for triangle in obj.data.loop_triangles),
        "bounds_min": [min(vertex.co[axis] for vertex in obj.data.vertices) for axis in range(3)],
        "bounds_max": [max(vertex.co[axis] for vertex in obj.data.vertices) for axis in range(3)],
    }


def run_contact_audit(armature, obj) -> dict:
    armature.animation_data.action = bpy.data.actions["run"]
    indices = {side: legacy.foot_vertex_indices(obj, side) for side in ("L", "R")}
    rates = {}
    fixed_bones = ("root", "foot.L", "foot.R", "toe.L", "toe.R")
    for fps in (30, 60):
        samples = []
        for sample in range(round(23.0 * fps / 30.0) + 1):
            frame = 1.0 + sample * 30.0 / fps
            bpy.context.scene.frame_set(int(frame), subframe=frame % 1.0)
            row = {"frame": frame}
            for side in ("L", "R"):
                row[side] = min(vertex.z for vertex in legacy.evaluated_vertices(obj, indices[side]))
            for name in fixed_bones:
                basis = armature.pose.bones[name].matrix_basis
                if any(abs(basis[r][c] - (1.0 if r == c else 0.0)) > 1e-5 for r in range(4) for c in range(4)):
                    raise RuntimeError(f"run changed attached-foot/root local transform: {name}")
            samples.append(row)
        rates[str(fps)] = {"samples": samples,
                           "minimum_sole_m": min(row[side] for row in samples for side in ("L", "R")),
                           "maximum_support_sole_m": max(min(row["L"], row["R"]) for row in samples)}
    parity = max(abs(rates["30"]["samples"][index][side] - rates["60"]["samples"][index * 2][side])
                 for index in range(len(rates["30"]["samples"])) for side in ("L", "R"))
    armature.animation_data.action = None
    legacy.reset_pose(armature)
    return {"rates": rates, "minimum_sole_m": min(row["minimum_sole_m"] for row in rates.values()),
            "maximum_support_sole_m": max(row["maximum_support_sole_m"] for row in rates.values()),
            "aligned_30_60_max_error_m": parity, "root_and_attached_feet_local_identity": True,
            "run_clip_preserved_not_refitted": True}


def restore_authored_vertex_colors(path: Path, mesh_obj) -> dict:
    """Correct Blender 5.2 multi-material COLOR_0 whitening from source data.

    The exporter can set material-to-color-layer keys to a concatenated source
    name instead of COLOR_0, then deliberately fill that primitive with white.
    Restore only its existing COLOR_0 accessor using exact source positions and
    material names. Geometry, tangents, indices, skins, clips and textures are
    untouched. Ambiguous/unmatched source colors fail rather than guessing.
    """
    raw = bytearray(path.read_bytes())
    json_length, json_kind = struct.unpack_from("<II", raw, 12)
    if json_kind != 0x4E4F534A:
        raise RuntimeError("unexpected GLB JSON layout")
    document = json.loads(raw[20:20 + json_length])
    binary_start = 28 + json_length
    lookup = {}
    colors = mesh_obj.data.color_attributes["COLOR_0"]
    for polygon in mesh_obj.data.polygons:
        material_name = mesh_obj.data.materials[polygon.material_index].name
        for loop_index in polygon.loop_indices:
            vertex = mesh_obj.data.vertices[mesh_obj.data.loops[loop_index].vertex_index].co
            key = material_name, struct.pack("<3f", vertex.x, vertex.z, -vertex.y)
            color = tuple(float(value) for value in colors.data[loop_index].color)
            if key in lookup and any(abs(a - b) > 1e-6 for a, b in zip(lookup[key], color)):
                raise RuntimeError("ambiguous source paint at an exported material/position")
            lookup[key] = color

    def accessor_offset(index: int):
        accessor = document["accessors"][index]
        view = document["bufferViews"][accessor["bufferView"]]
        return accessor, view, binary_start + view.get("byteOffset", 0) + accessor.get("byteOffset", 0)

    restored, changed = 0, 0
    surfaces = []
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            name = document["materials"][primitive["material"]]["name"]
            positions, position_view, position_start = accessor_offset(primitive["attributes"]["POSITION"])
            values, color_view, color_start = accessor_offset(primitive["attributes"]["COLOR_0"])
            if positions["componentType"] != 5126 or positions["type"] != "VEC3" \
                    or values["count"] != positions["count"] or values["type"] not in {"VEC3", "VEC4"}:
                raise RuntimeError("unexpected candidate position/color accessor contract")
            channels = 4 if values["type"] == "VEC4" else 3
            if values["componentType"] not in (5123, 5126):
                raise RuntimeError("unsupported candidate color encoding")
            width = channels * (2 if values["componentType"] == 5123 else 4)
            original_colors, restored_colors = [], []
            for index in range(positions["count"]):
                position_offset = position_start + index * position_view.get("byteStride", 12)
                key = name, bytes(raw[position_offset:position_offset + 12])
                if key not in lookup:
                    raise RuntimeError("exported vertex has no exact source paint match")
                color = lookup[key][:channels]
                if values["componentType"] == 5123:
                    if not values.get("normalized", False):
                        raise RuntimeError("integer vertex color must be normalized")
                    encoded = struct.pack("<" + "H" * channels, *[max(0, min(65535, round(value * 65535))) for value in color])
                else:
                    encoded = struct.pack("<" + "f" * channels, *color)
                offset = color_start + index * color_view.get("byteStride", width)
                original = struct.unpack_from("<" + ("H" if values["componentType"] == 5123 else "f") * channels, raw, offset)
                divisor = 65535.0 if values["componentType"] == 5123 else 1.0
                original_colors.append(tuple(value / divisor for value in original) + ((1.0,) if channels == 3 else ()))
                restored_colors.append(tuple(color) + ((1.0,) if channels == 3 else ()))
                changed += int(raw[offset:offset + width] != encoded)
                raw[offset:offset + width] = encoded
                restored += 1
            surfaces.append({"material": name, "joined_source_and_restored_glb": paint_summary(restored_colors),
                             "original_exported_glb": paint_summary(original_colors)})
    path.write_bytes(raw)
    return {"source_attribute": "COLOR_0", "exact_source_vertices_matched": restored,
            "changed_exported_colors": changed, "geometry_or_animation_changed": False,
            "surface_paint_sentinels": surfaces,
            "reason": "Blender 5.2 multi-material vertex-color whitening; restore authoritative authored paint"}


def export_candidate(path: Path, objects) -> dict:
    exporter.validate_transforms(objects)
    exporter.validate_modifiers(objects)
    exporter.select_only(objects)
    settings = exporter.exporter_kwargs(path, True)
    # QA-only self-contained PBR export. Production uses placeholder materials
    # and a semantic shader; overriding that contract silently is forbidden.
    settings.update(export_materials="EXPORT", export_image_format="AUTO", export_vertex_color="NAME",
                    export_vertex_color_name="COLOR_0", export_all_vertex_colors=False)
    bpy.ops.export_scene.gltf(**settings)
    return restore_authored_vertex_colors(path, next(obj for obj in objects if obj.type == "MESH"))


def main() -> None:
    global bpy, legacy, exporter
    import bpy
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import build_hero_penguin_v1 as legacy
    import blender_export as exporter
    import export_art
    import hero_penguin_v12_study_provenance as study_provenance
    legacy.require_version()
    args = parse_args()
    source, rig_path = args.source_blend.resolve(), args.rig_blend.resolve()
    if not source.is_file() or not rig_path.is_file() or source == rig_path:
        raise ValueError("distinct existing sculpt and canonical rig sources are required")
    output = safe_output_dir(args.output_dir)
    source_hash, rig_hash = file_sha256(source), file_sha256(rig_path)
    output.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    study_binding = study_provenance.read_source_study(source, bpy.context.scene)
    validate_geometry_binding(args.geometry_policy, study_binding)
    study_inputs = study_provenance.binding_input_hashes(source, study_binding)
    sources = sorted([obj for obj in bpy.data.objects if obj.type == "MESH"
                      and obj.name != "NeutralGrayFloor"], key=lambda obj: obj.name)
    for obj in sources:
        component_spec(obj.name)
        study_provenance.require_component_masks(study_binding, obj)
        source_colors(obj)
    armature, rig_objects, canonical_sole = load_rig(rig_path)
    rest_before = rest_digest(armature)
    clips_before = {action.name: legacy.action_digest(action) for action in bpy.data.actions}
    materials, texture_report = candidate_material(output)
    report = {"production_ready": False, "source_fidelity_approved": False, "candidate_only": True,
              "geometry_policy": args.geometry_policy,
              "source_blend": str(source), "source_sha256": source_hash,
              "rig_blend": str(rig_path), "rig_sha256": rig_hash,
              "adapter_sha256": file_sha256(Path(__file__)),
              "handedness": "applied saved source world transforms, reflected Y and reversed winding once; exporter converts +Y forward to Godot -Z",
              "limitations": LIMITATIONS, "textures": texture_report, "lods": [],
              "components": [], "outputs": {}, "khronos": {}, "authored_color_restoration": {}}
    if args.geometry_policy == RETOPOLOGY_GEOMETRY_POLICY:
        helper = Path(__file__).with_name("hero_penguin_v12_retopology.py").resolve()
        report["retopology_helper"] = {"path": str(helper), "sha256": file_sha256(helper)}
        study_inputs[str(helper)] = report["retopology_helper"]["sha256"]
        report["limitations"] = [*LIMITATIONS,
            "Body is automated quad retopology and source projection, not hand-authored deformation topology or exact source-triangle preservation."]
    if study_binding is not None:
        report["source_study_binding"] = study_binding
        report["source_cover_scope"] = (unified_source_scope(study_binding, args.geometry_policy) if args.geometry_policy in UNIFIED_GEOMETRY_POLICIES
                                        else study_provenance.PIN_SCOPE.copy())
        bpy.context.scene[study_provenance.BINDING_FIELD] = json.dumps(study_binding, sort_keys=True, allow_nan=False)
    meshes = []
    for lod in (0, 1):
        collection = bpy.data.collections.new(f"hero_penguin_v12_candidate_lod{lod}")
        bpy.context.scene.collection.children.link(collection)
        parts = []
        for obj in sources:
            zone, target = component_spec(obj.name)
            target = component_target(obj.name, lod, args.geometry_policy)
            kwargs = {"study_binding": study_binding} if args.geometry_policy in UNIFIED_GEOMETRY_POLICIES else {}
            part, before, after = reduce_component(obj, target, collection, args.geometry_policy, **kwargs)
            parts.append(part)
            report["components"].append({"lod": lod, "source": obj.name, "zone": zone,
                                         "before": before, "target": target, "after": after,
                                         "source_paint": paint_summary(source_colors(obj)),
                                         "reduced_paint": paint_summary(source_colors(part)),
                                         "source_cover_exact": bool(part.get("candidate_source_cover_exact", False)),
                                         "pinned_source_vertices": int(part.get("candidate_pinned_source_vertices", 0)),
                                         "pinned_source_triangles": int(part.get("candidate_pinned_source_triangles", 0)),
                                         "pin_preservation_phases": json.loads(part.get("candidate_pin_preservation_json", "null")),
                                         "retopology": json.loads(part.get("candidate_retopology_json", "null")),
                                         "mouth_reduction": part.get("candidate_mouth_reduction", ""),
                                         "source_degenerate_triangles_removed": int(part.get("candidate_removed_degenerate_triangles", 0))})
        name = "HeroPenguinMesh" if lod == 0 else "HeroPenguinLOD1"
        names = [obj.name for obj in sources] if args.geometry_policy == RETOPOLOGY_GEOMETRY_POLICY else None
        mesh, builder = joined_candidate(parts, collection, armature, name, args.sole_fit, canonical_sole,
                                         component_sources=names)
        for material in materials:
            mesh.data.materials.append(material)
        metrics = mesh_audit(mesh, builder)
        if names is not None:
            saved = json.loads(mesh[COMPONENT_MEMBERSHIP_FIELD])
            metrics["source_component_geometry"], _faces = component_geometry_signatures(mesh.data, saved["vertices"], names)
        low, high = LOD_RANGES[lod]
        if not low <= metrics["triangles"] <= high:
            raise RuntimeError(f"candidate LOD{lod} triangles outside {low}..{high}: {metrics}")
        if not 1 <= metrics["materials"] <= 2 or metrics["max_skin_weights"] > 4 or metrics["unweighted_vertices"]:
            raise RuntimeError(f"candidate mesh contract failed: {metrics}")
        if metrics["degenerate_uv_triangles"] or metrics["degenerate_geometry_triangles"]:
            raise RuntimeError(f"candidate has invalid geometry/UVs: {metrics}")
        metrics["run_contact"] = run_contact_audit(armature, mesh)
        report["lods"].append(metrics)
        meshes.append(mesh)
        print("[v12-candidate] " + json.dumps({k: v for k, v in metrics.items() if k != "run_contact"}, sort_keys=True), flush=True)
    report["bones"] = [bone.name for bone in armature.data.bones]
    report["bone_parents"] = {bone.name: bone.parent.name if bone.parent else None for bone in armature.data.bones}
    report["bone_rest_matrices"] = {bone.name: [list(row) for row in bone.matrix_local] for bone in armature.data.bones}
    report["rest_rig_sha256"] = rest_before
    report["sockets"] = {name: {"bone": bpy.data.objects[name].parent_bone,
                                "local_position": list(bpy.data.objects[name].location)} for name in SOCKETS}
    report["rest_rig_preserved"] = rest_before == rest_digest(armature)
    report["clips"] = sorted(clips_before)
    report["clip_sha256"] = clips_before
    report["all_clips_preserved"] = clips_before == {action.name: legacy.action_digest(action) for action in bpy.data.actions}
    if not report["rest_rig_preserved"] or not report["all_clips_preserved"] or len(report["bones"]) != 15:
        raise RuntimeError("canonical rig/action preservation failed")
    # Source sculpt geometry remains an immutable external input, not duplicated
    # into the runtime candidate's saved scene or accidental export selection.
    for obj in list(bpy.data.objects):
        if obj not in [*meshes, *rig_objects]:
            bpy.data.objects.remove(obj, do_unlink=True)
    legacy.reset_pose(armature)
    bpy.context.scene.render.fps = 30
    bpy.context.scene.frame_set(1)
    bpy.context.preferences.filepaths.save_version = 0
    blend_path = output / "hero_penguin_v12_candidate.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=False, compress=True)
    report["outputs"][blend_path.name] = file_sha256(blend_path)
    for lod, mesh in enumerate(meshes):
        path = output / f"hero_penguin_v12_candidate_lod{lod}.glb"
        report["authored_color_restoration"][path.name] = export_candidate(path, [mesh, *rig_objects])
        report["outputs"][path.name] = file_sha256(path)
        validation = subprocess.run([str(export_art.find_node()), str(ROOT / "tools/art/validate_glb.mjs"), str(path)],
                                    capture_output=True, text=True, check=False)
        report["khronos"][path.name] = {"exit_code": validation.returncode,
                                       "output": validation.stdout + validation.stderr}
        print(validation.stdout + validation.stderr, flush=True)
        if validation.returncode:
            (output / "candidate_audit_failed.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            raise RuntimeError(f"candidate Khronos validation failed: {path.name}")
    if file_sha256(source) != source_hash or file_sha256(rig_path) != rig_hash:
        raise RuntimeError("read-only input changed during candidate conversion")
    if any(file_sha256(Path(path)) != digest for path, digest in study_inputs.items()):
        raise RuntimeError("source study sidecar changed during candidate conversion")
    report["inputs_unchanged"] = True
    (output / "candidate_audit.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"[v12-candidate] COMPLETE {output}; production_ready=false", flush=True)


if __name__ == "__main__":
    main()
