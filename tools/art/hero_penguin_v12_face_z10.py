"""Z10 open-arch eyelids, cheek/throat silhouette and rounded anatomical bib.

No whole-oval/globe lid envelope is used. Two differently shaped soft folds
join the existing head and cheek. Frozen Z09 eye materials and bill are kept.
This is an independent source proposal, not a candidate/export registration.
"""
from __future__ import annotations

import ast
from contextlib import contextmanager
import math
import sys

import hero_penguin_v12_face_z09 as prior
import hero_penguin_v12_source_study as study

PROFILE = "soft-fold-face-z10"
PARENT_PROFILE = prior.PROFILE
THROAT_INWARD_M = .065
FOLDS = {
    "upper": {"width": .140, "depth_radius": .040, "height_radius": .037,
              "center_z": .133, "arch_curve": -.037, "center_depth": -.014,
              "corner_recession": .055, "join": .030},
    "lower": {"width": .123, "depth_radius": .035, "height_radius": .019,
              "center_z": -.111, "arch_curve": .032, "center_depth": -.025,
              "corner_recession": .028, "join": .022},
}
apply_material_changes = prior.apply_material_changes


def warp_points(points):
    """Keep Z09 cheek/muzzle, adding the same compact waist to total 65 mm."""
    import numpy as np
    points = np.asarray(points, dtype=float)
    result = prior.warp_points(points)
    x, y, z = points[..., 0], points[..., 1], points[..., 2]
    p = prior.SHAPE
    waist = np.maximum(0., 1. - (x / p["waist_rx"]) ** 2
                       - ((z - p["waist_z"]) / p["waist_rz"]) ** 2) ** 2
    low, high = p["depth_fade"]
    t = np.clip((-y - low) / (high - low), 0., 1.)
    gate = t * t * (3. - 2. * t)
    result[..., 1] -= (THROAT_INWARD_M - p["waist_inward"]) * waist * gate
    return result


def sculpt_face(points, base_field, eye_frame):
    """Closed shallow sockets plus separate broad upper/short lower folds.

    Each fold is a capped swept arch, not an ellipse wrapped around the globe.
    Its depth recedes toward the corners, with a smooth union into head/cheek.
    The lower fold is thinner, shorter and more recessed than the upper brow.
    """
    import numpy as np
    points = np.asarray(points, dtype=float)

    def smin(a, b, width):
        h = np.maximum(width - np.abs(a - b), 0.) / width
        return np.minimum(a, b) - h * h * width * .25

    def smax(a, b, width):
        return -smin(-a, -b, width)

    cavities, upper, lower = [], [], []
    for side in (-1., 1.):
        origin, across, normal, up = map(np.asarray, eye_frame(side))
        relative = points - origin
        x, depth, z = relative @ across, relative @ normal, relative @ up
        opening = prior.opening_field(x, z, side)
        cavities.append(smax(opening, -depth - prior.ORBIT["socket_back_depth"], .003))
        for name, target in (("upper", upper), ("lower", lower)):
            p = FOLDS[name]
            u = (x + side * .006) / p["width"]
            arch = p["center_z"] + p["arch_curve"] * u * u - .018 * side * x
            center_depth = p["center_depth"] - p["corner_recession"] * u * u
            # An eighth-power horizontal cap keeps a broad central fold and
            # closes its ends smoothly; it never makes a closed eye ring.
            q = u ** 8 + ((depth - center_depth) / p["depth_radius"]) ** 2
            q += ((z - arch) / p["height_radius"]) ** 2
            target.append((np.sqrt(q) - 1.) * min(p["depth_radius"], p["height_radius"]))
    carved = smax(base_field(points), -np.minimum(cavities[0], cavities[1]), .003)
    joined = smin(carved, np.minimum(upper[0], upper[1]), FOLDS["upper"]["join"])
    return smin(joined, np.minimum(lower[0], lower[1]), FOLDS["lower"]["join"])


def chest_mask(point):
    """Rounded world-space belly cap, narrowing only toward the throat.

    Its mathematical bottom lies below the visible belly base. Unlike the old
    angle/height ellipse, the cream region does not collapse to a visible V.
    """
    x, y, z = point
    width = .475 - .160 * prior.smooth(.880, 1.270, z)
    q = (x / width) ** 2 + ((z - .710) / .725) ** 2
    front = -y / max(.001, math.hypot(x, y))
    return (1. - prior.smooth(.90, 1.12, q)) * prior.smooth(.05, .25, front)


def body_paint(point, eye_frame):
    x, y, z = point
    smooth = prior.smooth
    angle = abs(math.atan2(x, -y))
    cheek_center = 1.333 + .018 * math.cos(angle * .9)
    cheek_q = ((angle - .63) / 1.04) ** 2 + ((z - cheek_center) / .172) ** 2
    cheek = 1. - smooth(.88, 1.12, cheek_q)
    chin = 1. - smooth(.88, 1.12, (angle / .85) ** 2 + ((z - 1.210) / .190) ** 2)
    orbit, lash = 0., 0.
    for side in (-1., 1.):
        origin, across, normal, up = eye_frame(side)
        relative = tuple(point[i] - origin[i] for i in range(3))
        local_x, depth, local_z = (sum(relative[i] * axis[i] for i in range(3))
                                    for axis in (across, normal, up))
        gate = smooth(-.075, -.015, depth)
        lower_flow = smooth(.015, .120, -local_z)
        width = .133 + .038 * lower_flow
        q = (local_x / width) ** 2 + ((local_z + .022) / .150) ** 2
        # Cream follows the lower lip of the upper brow, then blends into the
        # navy hood. Lower orbital paint opens widely into the cheek.
        hood = smooth(.102, .137, local_z + .025 * (local_x / .130) ** 2)
        orbit = max(orbit, (1. - smooth(.88, 1.12, q)) * gate * (1. - hood))
        p = prior.ORBIT
        vertical = local_z - p["center_z"] + p["outer_corner_drop"] * side * local_x
        radius_z = p["opening_upper"] if vertical >= 0. else p["opening_lower"]
        edge = (math.sqrt(((local_x + side * p["nasal_offset"]) / p["opening_x"]) ** 2
                          + (vertical / radius_z) ** 2) - 1.) * p["opening_distance_scale"]
        upper_line = .75 * smooth(.025, .050, local_z)
        lower_line = .10 * (1. - smooth(-.070, -.035, local_z)) * (1. - smooth(.060, .090, abs(local_x)))
        lash = max(lash, math.exp(-((edge - .0015) / .003) ** 2) * gate * (upper_line + lower_line))
    cream = max(cheek, chin, chest_mask(point), orbit)
    bridge = (1. - smooth(.034, .066, abs(x))) * smooth(1.384, 1.454, z)
    cream *= 1. - bridge
    face_light = smooth(1.25, 1.43, z)
    ivory = tuple(a + (b - a) * face_light for a, b in zip((.73, .62, .445, 1.), (.82, .75, .595, 1.)))
    throat = .12 * math.exp(-((z - 1.205) / .065) ** 2)
    ivory = tuple(a + (b - a) * throat for a, b in zip(ivory, (.84, .56, .255, 1.)))
    pigment = tuple(a + (b - a) * cream for a, b in zip((.017, .027, .040, 1.), ivory))
    pigment = tuple(a + (b - a) * lash for a, b in zip(pigment, (.022, .032, .040, 1.)))
    ear_q = ((angle - 1.45) / .31) ** 2 + ((z - 1.360) / .115) ** 2
    ear = (1. - smooth(.80, 1.18, ear_q)) * (1. - smooth(.12, .90, cheek))
    stroke_u = (angle - 1.52) / .45
    stroke_width = .015 * math.sqrt(max(0., 1. - stroke_u * stroke_u))
    stripe_z = 1.188 + .040 * (angle - 1.10) + .017 * math.sin((angle - 1.10) * 3.3)
    stripe = (1. - smooth(max(0., stroke_width - .003), stroke_width + .002, abs(z - stripe_z)))
    stripe *= 1. - smooth(.91, 1., abs(stroke_u))
    pigment = tuple(a + (b - a) * ear for a, b in zip(pigment, (.63, .270, .037, 1.)))
    pigment = tuple(a + (b - a) * stripe for a, b in zip(pigment, (.065, .34, .38, 1.)))
    return pigment, (cream * (1. - ear) * (1. - stripe), ear * (1. - stripe), stripe, 1.)


def fresh_design():
    selected, parent_record = prior.fresh_design()
    baseline, _ = study.fresh_design(prior.PARENT_PROFILE)
    selected.base_body_field = lambda points: baseline.base_body_field(warp_points(points))
    selected.__dict__["_z10_sculpt"] = sculpt_face
    source = '''def sculpt_body_field(points):
    return _z10_sculpt(points, base_body_field, eye_surface_frame)
'''
    exec(compile(source, __file__, "exec"), selected.__dict__)
    if selected.eye_surface_frame.cache_info().currsize:
        raise RuntimeError("Z10 requires fresh eye anchors")
    return selected, {"parent_design_record": parent_record, "z10_fold_parameters": FOLDS,
                      "z10_total_throat_inward_m": THROAT_INWARD_M,
                      "z10_sculpt_replacement": source,
                      "selected_design_constants": study.constants(selected)}


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
    tree, parent_record = prior.renderer_syntax(path)
    imports = [node for node in tree.body if isinstance(node, ast.ImportFrom)
               and node.module == "hero_penguin_v12_face_z09"]
    if len(imports) != 1 or [(alias.name, alias.asname) for alias in imports[0].names] != [("body_paint", "_z09_body_paint")]:
        raise ValueError("Z10 parent paint import changed")
    imports[0].module = "hero_penguin_v12_face_z10"
    imports[0].names[0].asname = "_z10_body_paint"
    paint = study.function_node(tree, "body_paint")
    if ast.dump(ast.Module(body=paint.body, type_ignores=[])) != ast.dump(ast.parse("return _z09_body_paint(point, eye_surface_frame)")):
        raise ValueError("Z10 parent paint delegate changed")
    paint.body = ast.parse("return _z10_body_paint(point, eye_surface_frame)").body
    ast.fix_missing_locations(tree)
    return tree, {"parent_renderer_record": parent_record,
                  "z10_body_paint_helper": "hero_penguin_v12_face_z10.body_paint",
                  "selected_renderer_ast_sha256": study.ast_digest(tree)}


def source_only_declarations():
    return {"schema_version": 1, "study_profile": PROFILE, "parent_profile": PARENT_PROFILE,
            "source_only": True, "production_ready": False, "source_fidelity_approved": False,
            "geometry_approved": False, "candidate_export_allowed": False, "runtime_rig_or_glb_created": False,
            "export_policy": "Unregistered source-only study; reject candidate/atlas export.",
            "scope": "Open upper/lower soft folds with receding corners, deeper bounded throat, round belly bib and connected orbital paint.",
            "z09_eye_dimensions_frame_materials_bill_feet_cameras_lights_maps_preserved": True,
            "material_callback_recipe": prior.MATERIALS,
            "approval_policy": "Three-view visual review required; construction tests never grant fidelity approval."}
