"""Quarantined Z11: a thin upper lid lofted into the existing hood surface.

This deforms the existing head field; it does not union an upper tube or a
closed eye-ring mesh. Z10's lower fold, sockets, eyes, materials, bill, throat
and rounded bib remain unchanged. Construction checks are not art approval.
"""
from __future__ import annotations

import ast
from contextlib import contextmanager
from functools import lru_cache
import math
import sys

import hero_penguin_v12_face_z10 as prior
import hero_penguin_v12_source_study as study

PROFILE = "hood-connected-upper-lid-z11"
PARENT_PROFILE = prior.PROFILE
LID = {
    "lip_clearance_m": .0025,
    "minimum_hood_return_m": .045,
    "beyond_globe_return_m": .010,
    "below_aperture_blend_m": .004,
    "endpoint_taper_start_beyond_globe_m": .003,
    "endpoint_taper_end_beyond_globe_m": .020,
    "depth_floor_blend_m": .001,
    "pigment_edge_half_width_m": .0015,
    "surface_grid_samples": 65,
    "surface_grid_lower_z_m": -.035,
    "surface_grid_upper_padding_m": .015,
    "surface_ray_inside_m": -.320,
    "surface_ray_outside_m": .180,
    "surface_ray_iterations": 32,
}
apply_material_changes = prior.apply_material_changes
chest_mask = prior.chest_mask
warp_points = prior.warp_points


def upper_aperture_z(x, side):
    """The actual Z09/Z10 upper socket contour, not a second brow arch."""
    import numpy as np
    p = prior.prior.ORBIT
    x = np.asarray(x, dtype=float)
    u = (x + side * p["nasal_offset"]) / p["opening_x"]
    return (p["center_z"] - p["outer_corner_drop"] * side * x
            + p["opening_upper"] * np.sqrt(np.maximum(0., 1. - u * u)))


def smootherstep(value):
    import numpy as np
    t = np.clip(value, 0., 1.)
    return t * t * t * (t * (t * 6. - 15.) + 10.)


def lid_coordinates(x, z, side, eye_radii):
    """Shared sculpt/paint edge, hood-return coordinate and endpoint taper.

    The return may exceed 45 mm when necessary to pass the upper globe
    silhouette. It never stops a deformation while a globe still projects
    through it. Taper begins *outside* the globe, not over the visible iris.
    """
    import numpy as np
    x, z = np.broadcast_arrays(np.asarray(x, dtype=float), np.asarray(z, dtype=float))
    rx, _, rz = eye_radii
    edge = upper_aperture_z(x, side)
    globe_top = rz * np.sqrt(np.maximum(0., 1. - (x / rx) ** 2))
    outer = np.maximum(edge + LID["minimum_hood_return_m"],
                       globe_top + LID["beyond_globe_return_m"])
    t = (z - edge) / (outer - edge)
    endpoint = 1. - smootherstep((np.abs(x) - rx - LID["endpoint_taper_start_beyond_globe_m"])
                                / (LID["endpoint_taper_end_beyond_globe_m"]
                                   - LID["endpoint_taper_start_beyond_globe_m"]))
    inner = smootherstep((z - edge + LID["below_aperture_blend_m"])
                         / LID["below_aperture_blend_m"])
    return edge, outer, t, endpoint, inner


def globe_front_depth(x, z, eye_radii, burial):
    """Unchanged real ellipsoid front; validity is returned separately."""
    import numpy as np
    rx, ry, rz = eye_radii
    q = 1. - (np.asarray(x) / rx) ** 2 - (np.asarray(z) / rz) ** 2
    return -burial + ry * np.sqrt(np.maximum(q, 0.)), q >= 0.


@lru_cache(maxsize=4)
def head_surface_grid(base_field, frame, eye_radii):
    """Small source-head ray table; no geometry/eye-frame mutation.

    This is explicitly a bilinear approximation of the pre-lid head depth,
    not an exact surface/clearance certification. Final sculpture still uses
    the real base field. The 65x65 table avoids ray-solving a full voxel grid.
    The function object is part of the cache key, so cohorts cannot share it.
    """
    import numpy as np
    origin, across, normal, up = map(np.asarray, frame)
    half_width = eye_radii[0] + LID["endpoint_taper_end_beyond_globe_m"] + .001
    xs = np.linspace(-half_width, half_width, LID["surface_grid_samples"])
    zs = np.linspace(LID["surface_grid_lower_z_m"],
                     eye_radii[2] + LID["surface_grid_upper_padding_m"], LID["surface_grid_samples"])
    x, z = np.meshgrid(xs, zs, indexing="ij")
    centers = origin + x[..., None] * across + z[..., None] * up
    low = np.full(x.shape, LID["surface_ray_inside_m"])
    high = np.full(x.shape, LID["surface_ray_outside_m"])
    low_values, high_values = base_field(centers + low[..., None] * normal), base_field(centers + high[..., None] * normal)
    if (not np.all(np.isfinite(low_values)) or not np.all(np.isfinite(high_values))
            or np.any(low_values >= 0.) or np.any(high_values <= 0.)):
        raise ValueError("Z11 upper-hood head ray is not bracketed; refuse guessed attachment")
    for _ in range(LID["surface_ray_iterations"]):
        mid = (low + high) * .5
        inside = base_field(centers + mid[..., None] * normal) <= 0.
        low, high = np.where(inside, mid, low), np.where(inside, high, mid)
    depths = (low + high) * .5
    for value in (xs, zs, depths):
        value.setflags(write=False)
    return xs, zs, depths


def sample_head_depth(grid, x, z):
    import numpy as np
    xs, zs, depths = grid
    x, z = np.broadcast_arrays(np.asarray(x), np.asarray(z))
    if np.any(x < xs[0] - 1e-12) or np.any(x > xs[-1] + 1e-12) or np.any(z < zs[0] - 1e-12) or np.any(z > zs[-1] + 1e-12):
        raise ValueError("Z11 head sample outside declared table")
    fx = np.clip((x - xs[0]) / (xs[-1] - xs[0]) * (len(xs) - 1), 0., len(xs) - 1)
    fz = np.clip((z - zs[0]) / (zs[-1] - zs[0]) * (len(zs) - 1), 0., len(zs) - 1)
    ix, iz = np.minimum(fx.astype(int), len(xs) - 2), np.minimum(fz.astype(int), len(zs) - 2)
    tx, tz = fx - ix, fz - iz
    return ((1. - tx) * ((1. - tz) * depths[ix, iz] + tz * depths[ix, iz + 1])
            + tx * ((1. - tz) * depths[ix + 1, iz] + tz * depths[ix + 1, iz + 1]))


def lid_lift(x, z, side, eye_radii, burial, head_here, head_at_edge):
    """Thin aperture lip -> existing hood, with a zero-slope outer return.

    The true globe is only a clearance floor in this *upper* loft; it is not
    an additive globe envelope. Nothing wraps below the socket or creates a
    closed ring. A 1 mm smooth maximum avoids a crease where floor and loft
    meet. This numeric recipe still requires actual image review.
    """
    import numpy as np
    edge, _, t, endpoint, inner = lid_coordinates(x, z, side, eye_radii)
    lip, lip_valid = globe_front_depth(x, edge, eye_radii, burial)
    return_weight = 1. - smootherstep(t)
    rise = np.where(lip_valid, np.maximum(0., lip + LID["lip_clearance_m"] - head_at_edge), 0.)
    loft = rise * return_weight
    globe, valid = globe_front_depth(x, z, eye_radii, burial)
    floor = np.where(valid, np.maximum(0., globe + LID["lip_clearance_m"] * return_weight - head_here), 0.)
    width = LID["depth_floor_blend_m"]
    h = np.maximum(width - np.abs(loft - floor), 0.) / width
    # The correction vanishes when both branches vanish; no all-over offset.
    largest = np.maximum(loft, floor)
    blended = largest + h * h * width * .25 * return_weight * smootherstep(largest / width)
    return blended * endpoint * inner * (t < 1.)


def sculpt_face(points, base_field, eye_frame, eye_radii, burial):
    import numpy as np
    points = np.asarray(points, dtype=float)
    flat = points.reshape((-1, 3))
    warped = flat.copy()
    cavities, lower = [], []

    def smin(a, b, width):
        h = np.maximum(width - np.abs(a - b), 0.) / width
        return np.minimum(a, b) - h * h * width * .25

    def smax(a, b, width):
        return -smin(-a, -b, width)

    for side in (-1., 1.):
        frame = eye_frame(side)
        origin, across, normal, up = map(np.asarray, frame)
        relative = flat - origin
        x, depth, z = relative @ across, relative @ normal, relative @ up
        edge, outer, _, endpoint, _ = lid_coordinates(x, z, side, eye_radii)
        selected = ((endpoint > 0.) & (z >= edge - LID["below_aperture_blend_m"])
                    & (z < outer) & (depth > -.160) & (depth < .160))
        if np.any(selected):
            grid = head_surface_grid(base_field, tuple(tuple(v) for v in frame), tuple(eye_radii))
            xx, zz = x[selected], z[selected]
            head = sample_head_depth(grid, xx, zz)
            edge_head = sample_head_depth(grid, xx, edge[selected])
            lift = lid_lift(xx, zz, side, eye_radii, burial, head, edge_head)
            # Warp only the front shell, not the far side/interior of the head.
            depth_gate = smootherstep((depth[selected] - head + .040) / .025)
            warped[selected] -= (lift * depth_gate)[:, None] * normal
        opening = prior.prior.opening_field(x, z, side)
        cavities.append(smax(opening, -depth - prior.prior.ORBIT["socket_back_depth"], .003))
        p = prior.FOLDS["lower"]
        u = (x + side * .006) / p["width"]
        arch = p["center_z"] + p["arch_curve"] * u * u - .018 * side * x
        center_depth = p["center_depth"] - p["corner_recession"] * u * u
        q = u ** 8 + ((depth - center_depth) / p["depth_radius"]) ** 2 + ((z - arch) / p["height_radius"]) ** 2
        lower.append((np.sqrt(q) - 1.) * min(p["depth_radius"], p["height_radius"]))
    carved = smax(base_field(warped), -np.minimum(cavities[0], cavities[1]), .003)
    return smin(carved, np.minimum(lower[0], lower[1]), prior.FOLDS["lower"]["join"]).reshape(points.shape[:-1])


def body_paint(point, eye_frame, eye_radii):
    """Keep all Z10 paint except the upper lid, using the actual sculpt edge."""
    pigment, masks = prior.body_paint(point, eye_frame)
    hood = 0.
    for side in (-1., 1.):
        origin, across, normal, up = eye_frame(side)
        relative = tuple(point[i] - origin[i] for i in range(3))
        x, depth, z = (sum(relative[i] * axis[i] for i in range(3)) for axis in (across, normal, up))
        # Scalar equivalent of lid_coordinates: paint runs once per source
        # vertex, so do not allocate NumPy arrays for this small calculation.
        p = prior.prior.ORBIT
        u = (x + side * p["nasal_offset"]) / p["opening_x"]
        edge = p["center_z"] - p["outer_corner_drop"] * side * x + p["opening_upper"] * math.sqrt(max(0., 1. - u * u))
        globe_top = eye_radii[2] * math.sqrt(max(0., 1. - (x / eye_radii[0]) ** 2))
        outer = max(edge + LID["minimum_hood_return_m"], globe_top + LID["beyond_globe_return_m"])
        t = (z - edge) / (outer - edge)
        taper = max(0., min(1., (abs(x) - eye_radii[0] - LID["endpoint_taper_start_beyond_globe_m"])
                            / (LID["endpoint_taper_end_beyond_globe_m"] - LID["endpoint_taper_start_beyond_globe_m"])))
        endpoint = 1. - taper ** 3 * (taper * (taper * 6. - 15.) + 10.)
        width = LID["pigment_edge_half_width_m"]
        lip = prior.prior.smooth(-width, width, z - edge)
        # Merge into the pre-existing dark hood, rather than painting a stripe.
        upper_return = 1. - prior.prior.smooth(.80, 1., t)
        front = prior.prior.smooth(-.080, -.020, depth)
        hood = max(hood, lip * endpoint * upper_return * front)
    dark = (.017, .027, .040, 1.)
    return tuple(a + (b - a) * hood for a, b in zip(pigment, dark)), tuple(v * (1. - hood) for v in masks[:3]) + (masks[3],)


def fresh_design():
    selected, parent_record = prior.fresh_design()
    selected.__dict__["_z11_sculpt"] = sculpt_face
    source = '''def sculpt_body_field(points):
    return _z11_sculpt(points, base_body_field, eye_surface_frame, EYE_RADII, EYE_BURY_DEPTH)
'''
    exec(compile(source, __file__, "exec"), selected.__dict__)
    if selected.eye_surface_frame.cache_info().currsize:
        raise RuntimeError("Z11 requires fresh unchanged eye anchors")
    return selected, {"parent_design_record": parent_record, "z11_lid_parameters": LID.copy(),
                      "z11_sculpt_replacement": source, "selected_design_constants": study.constants(selected),
                      "head_surface_lookup": "65x65 bilinear depth approximation; actual base field deformation; no exact-surface approval"}


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
    imports = [node for node in tree.body if isinstance(node, ast.ImportFrom) and node.module == "hero_penguin_v12_face_z10"]
    if len(imports) != 1 or [(a.name, a.asname) for a in imports[0].names] != [("body_paint", "_z10_body_paint")]:
        raise ValueError("Z11 parent paint import changed")
    imports[0].module = "hero_penguin_v12_face_z11"
    imports[0].names[0].asname = "_z11_body_paint"
    paint = study.function_node(tree, "body_paint")
    if ast.dump(ast.Module(body=paint.body, type_ignores=[])) != ast.dump(ast.parse("return _z10_body_paint(point, eye_surface_frame)")):
        raise ValueError("Z11 parent paint delegate changed")
    paint.body = ast.parse("return _z11_body_paint(point, eye_surface_frame, EYE_RADII)").body
    ast.fix_missing_locations(tree)
    return tree, {"parent_renderer_record": parent_record,
                  "z11_body_paint_helper": "hero_penguin_v12_face_z11.body_paint",
                  "selected_renderer_ast_sha256": study.ast_digest(tree)}


def source_only_declarations():
    return {"schema_version": 1, "study_profile": PROFILE, "parent_profile": PARENT_PROFILE,
            "source_only": True, "production_ready": False, "source_fidelity_approved": False,
            "geometry_approved": False, "candidate_export_allowed": False, "runtime_rig_or_glb_created": False,
            "export_policy": "Unregistered source-only study; reject candidate/atlas export.",
            "scope": "Replace only upper tube by hood-connected thin lid loft and matching upper-edge pigment.",
            "z10_eyes_gaze_lower_fold_bill_bib_throat_materials_cameras_lights_preserved": True,
            "material_callback_recipe": prior.prior.MATERIALS,
            "approval_policy": "Three-view visual review required; construction tests never grant fidelity approval."}
