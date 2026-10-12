"""Quarantined continuous cheek/muzzle study on the frozen Z06 eye cohort.

No new profile registration, live asset, rig, texture or export acceptance.
The front-only invertible warp reshapes the existing closed field; it does not
add cheek shells, rings, floating brows or independent facial meshes.
"""
from __future__ import annotations

import ast
from contextlib import contextmanager
import sys

import hero_penguin_v12_source_study as study

PROFILE = "juvenile-cheeks-z08"
PARENT_PROFILE = "juvenile-socket-z06"
SHAPE = {
    "cheek_center_x": .205, "cheek_center_z": 1.315,
    "cheek_radius_x": .220, "cheek_radius_z": .145, "cheek_forward_m": .027,
    "muzzle_center_z": 1.295, "muzzle_radius_x": .280,
    "muzzle_radius_z": .130, "muzzle_forward_m": .006,
    "orbital_fade_z": [1.350, 1.405],
    "waist_center_z": 1.115, "waist_radius_x": .430,
    "waist_radius_z": .155, "waist_inward_m": .016,
    "front_depth_fade_m": [.100, .300],
}
CONSTANT_CHANGES = (
    ("UPPER_FOLD_RADIAL_MARGIN", (.003, .004, .003), (.002, .001, .002)),
    ("UPPER_FOLD_BLEND", .006, .018),
)
PAINT_CHANGES = (
    ("cheek", "min(ellipse(-0.182, 1.333, 0.265, 0.182), ellipse(0.182, 1.333, 0.265, 0.182))",
     "min(ellipse(-0.205, 1.325, 0.285, 0.185), ellipse(0.205, 1.325, 0.285, 0.185))"),
    ("chin", "ellipse(0.0, 1.180, 0.337, 0.260)", "ellipse(0.0, 1.170, 0.277, 0.225)"),
    ("chest", "ellipse(0.0, 0.768, 0.464, 0.698)", "ellipse(0.0, 0.755, 0.454, 0.676)"),
    ("ear_field", "((angle - 1.46) / 0.40) ** 2 + ((point.z - 1.350) / 0.092) ** 2",
     "((angle - 1.49) / 0.30) ** 2 + ((point.z - 1.355) / 0.095) ** 2"),
    ("ear", "1.0 - smoothstep(0.86, 1.10, ear_field)",
     "(1.0 - smoothstep(0.76, 1.20, ear_field)) * (1.0 - face)"),
)


def warp_points(points):
    """Return pre-image coordinates for the same smooth, closed body field.

    x/z stay fixed. The maximum signed shift is 33 mm forward or 16 mm
    inward. The depth gate has slope <=7.5/m, so dy_query/dy >=0.7525:
    each front/back ray remains monotonic and this warp cannot fold itself.
    Compact squared ellipses and cubic fades have zero slope at their bounds.
    """
    import numpy as np
    points = np.asarray(points, dtype=float)
    x, y, z = points[..., 0], points[..., 1], points[..., 2]

    def smooth(low, high, value):
        t = np.clip((value - low) / (high - low), 0., 1.)
        return t * t * (3. - 2. * t)

    def cushion(center_x, center_z, radius_x, radius_z):
        q = ((x - center_x) / radius_x) ** 2 + ((z - center_z) / radius_z) ** 2
        return np.maximum(0., 1. - q) ** 2

    p = SHAPE
    left = cushion(-p["cheek_center_x"], p["cheek_center_z"],
                   p["cheek_radius_x"], p["cheek_radius_z"])
    right = cushion(p["cheek_center_x"], p["cheek_center_z"],
                    p["cheek_radius_x"], p["cheek_radius_z"])
    cheeks = (1. - (1. - left) * (1. - right)) * p["cheek_forward_m"]
    muzzle = cushion(0., p["muzzle_center_z"], p["muzzle_radius_x"],
                     p["muzzle_radius_z"]) * p["muzzle_forward_m"]
    forward = (cheeks + muzzle) * (1. - smooth(*p["orbital_fade_z"], z))
    waist = cushion(0., p["waist_center_z"], p["waist_radius_x"],
                    p["waist_radius_z"]) * p["waist_inward_m"]
    shift = (forward - waist) * smooth(*p["front_depth_fade_m"], -y)
    result = points.copy()
    result[..., 1] += shift
    return result


def fresh_design():
    selected, parent_record = study.fresh_design(PARENT_PROFILE)
    before = study.constants(selected)
    changes = []
    for name, old, new in CONSTANT_CHANGES:
        if getattr(selected, name) != old:
            raise ValueError(f"Z08 parent fold constant changed: {name}")
        setattr(selected, name, new)
        changes.append({"anchor": name, "baseline": old, "selected": new})
    original_field = selected.base_body_field

    def continuous_face_field(points):
        return original_field(warp_points(points))

    selected.base_body_field = continuous_face_field
    after = study.constants(selected)
    if {name for name in after if after[name] != before[name]} != {item[0] for item in CONSTANT_CHANGES}:
        raise RuntimeError("Z08 changed a constant outside the two fold controls")
    if selected.eye_surface_frame.cache_info().currsize:
        raise RuntimeError("Z08 requires an unevaluated anatomical eye frame")
    return selected, {"parent_design_record": parent_record,
                      "z08_constant_changes": changes, "selected_design_constants": after,
                      "z08_body_field": "original Z06 base_body_field(warp_points(points)); original socket then upper-fold union",
                      "shape_parameters": SHAPE.copy()}


@contextmanager
def installed_design():
    selected, record = fresh_design()
    previous = sys.modules.get(study.DESIGN_MODULE)
    sys.modules[study.DESIGN_MODULE] = selected
    try:
        yield selected, record
    finally:
        if previous is None:
            sys.modules.pop(study.DESIGN_MODULE, None)
        else:
            sys.modules[study.DESIGN_MODULE] = previous


def renderer_syntax(path):
    tree, parent_record = study.renderer_syntax(PARENT_PROFILE, path)
    paint = study.function_node(tree, "body_paint")
    plans = [study.expression_plan(study.assignment(paint, name), old, new, "body_paint." + name)
             for name, old, new in PAINT_CHANGES]
    for node, value, _record in plans:
        node.value = ast.copy_location(value, node.value)
    ast.fix_missing_locations(tree)
    return tree, {"parent_renderer_record": parent_record,
                  "z08_renderer_expression_changes": [item[2] for item in plans],
                  "selected_renderer_ast_sha256": study.ast_digest(tree)}


def source_only_declarations():
    return {"schema_version": 1, "study_profile": PROFILE, "parent_profile": PARENT_PROFILE,
            "source_only": True, "production_ready": False, "source_fidelity_approved": False,
            "geometry_approved": False, "candidate_export_allowed": False,
            "runtime_rig_or_glb_created": False,
            "export_policy": "Unregistered continuous-face study; reject candidate/atlas export.",
            "scope": "Continuous cheek/muzzle projection and throat waist; connected upper folds; cheek/jaw/bib flow and warm side crescent.",
            "z06_eyes_bill_crown_feet_cameras_lights_textures_preserved": True,
            "field_warp_minimum_jacobian_bound": .7525,
            "visual_review_required": "Three fixed views against user reference; numeric bounds are not fidelity approval."}
