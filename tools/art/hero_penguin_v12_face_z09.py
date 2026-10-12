"""Independent Z09 face construction, not a runtime/export-approved profile.

Closed shallow eye sockets and both lids belong to the shared head field.
Cheek/muzzle volume, curved facial markings and the two bill lobes are authored
together. Frozen studies, lights/cameras, feather maps, feet and rig stay intact.
"""
from __future__ import annotations

import ast
from contextlib import contextmanager
import math
import sys

import hero_penguin_v12_source_study as study

PROFILE = "integrated-face-z09"
PARENT_PROFILE = "juvenile-socket-z06"
SHAPE = {
    "cheek_x": .200, "cheek_z": 1.335, "cheek_rx": .210, "cheek_rz": .160,
    "cheek_forward": .031, "muzzle_z": 1.315, "muzzle_rx": .260,
    "muzzle_rz": .160, "muzzle_forward": .0125,
    "waist_z": 1.125, "waist_rx": .430, "waist_rz": .170, "waist_inward": .020,
    "orbital_fade": [1.365, 1.415], "depth_fade": [.100, .300],
}
ORBIT = {
    "opening_x": .105, "opening_upper": .095, "opening_lower": .093,
    "center_z": .006, "nasal_offset": .009, "outer_corner_drop": .025,
    "opening_distance_scale": .094, "socket_back_depth": .045,
    "lid_margin": [.003, .002, .003], "lid_join": .020,
    "socket_rounding": .003, "lid_edge_rounding": .002,
}
BILL_UPPER = (
    (-.397, .105, .091, 1.329), (-.438, .137, .100, 1.320),
    (-.478, .121, .123, 1.310), (-.516, .094, .098, 1.309),
    (-.548, .057, .049, 1.306), (-.571, .022, .018, 1.303),
    (-.578, .003, .002, 1.301),
)
BILL_LOWER = (
    (-.399, .102, .020, 1.329), (-.438, .127, .046, 1.320),
    (-.477, .108, .051, 1.310), (-.513, .077, .039, 1.309),
    (-.539, .039, .020, 1.307), (-.553, .016, .007, 1.305),
    (-.559, .002, .001, 1.304),
)
MATERIALS = {
    "iris": {"old_roughness": .32, "roughness": .34, "specular": .10, "ior": 1.33},
    "pupil": {"old_roughness": .28, "roughness": .16, "specular": .045, "ior": 1.33,
              "base_color": (.0015, .0030, .0050, 1.)},
    "sclera": {"old_roughness": .38, "roughness": .40, "specular": .20, "ior": 1.33},
    "bill_upper": {"old_roughness": .54, "roughness": .46, "specular": .28, "ior": 1.45},
    "bill_lower": {"old_roughness": .58, "roughness": .49, "specular": .28, "ior": 1.45},
}


def smooth(low, high, value):
    t = min(1., max(0., (value - low) / (high - low)))
    return t * t * (3. - 2. * t)


def warp_points(points):
    import numpy as np
    points = np.asarray(points, dtype=float)
    x, y, z = points[..., 0], points[..., 1], points[..., 2]

    def fade(low, high, value):
        t = np.clip((value - low) / (high - low), 0., 1.)
        return t * t * (3. - 2. * t)

    def cushion(cx, cz, rx, rz):
        return np.maximum(0., 1. - ((x - cx) / rx) ** 2 - ((z - cz) / rz) ** 2) ** 2

    p = SHAPE
    left = cushion(-p["cheek_x"], p["cheek_z"], p["cheek_rx"], p["cheek_rz"])
    right = cushion(p["cheek_x"], p["cheek_z"], p["cheek_rx"], p["cheek_rz"])
    forward = p["cheek_forward"] * (1. - (1. - left) * (1. - right))
    forward += p["muzzle_forward"] * cushion(0., p["muzzle_z"], p["muzzle_rx"], p["muzzle_rz"])
    forward *= 1. - fade(*p["orbital_fade"], z)
    waist = p["waist_inward"] * cushion(0., p["waist_z"], p["waist_rx"], p["waist_rz"])
    result = points.copy()
    result[..., 1] += (forward - waist) * fade(*p["depth_fade"], -y)
    return result


def opening_field(x, z, side):
    """Signed oval opening, positive outside; same contour for sculpt/paint."""
    import numpy as np
    p = ORBIT
    center = p["center_z"] - p["outer_corner_drop"] * side * x
    vertical = z - center
    radius_z = np.where(vertical >= 0., p["opening_upper"], p["opening_lower"])
    q = ((x + side * p["nasal_offset"]) / p["opening_x"]) ** 2 + (vertical / radius_z) ** 2
    return (np.sqrt(q) - 1.) * p["opening_distance_scale"]


def sculpt_face(points, base_field, eye_frame, eye_radii, burial):
    """One body field with shallow closed sockets and integrated paired lids.

    The cavity stops 45 mm behind the anatomical eye plane. Its opening and
    lid boundary share the same oval; the slightly enlarged globe envelope
    forms both lids and a broad smooth join into the original head. No separate
    ring mesh, through-head boolean, or view-dependent placement is involved.
    """
    import numpy as np
    points = np.asarray(points, dtype=float)

    def smin(a, b, width):
        h = np.maximum(width - np.abs(a - b), 0.) / width
        return np.minimum(a, b) - h * h * width * .25

    def smax(a, b, width):
        return -smin(-a, -b, width)

    lids, cavities = [], []
    p = ORBIT
    for side in (-1., 1.):
        origin, across, normal, up = map(np.asarray, eye_frame(side))
        relative = points - origin
        x, depth, z = relative @ across, relative @ normal, relative @ up
        aperture = opening_field(x, z, side)
        cavities.append(smax(aperture, -depth - p["socket_back_depth"], p["socket_rounding"]))
        local = np.stack((x, depth + burial, z), axis=-1)
        radius = np.asarray(eye_radii) + np.asarray(p["lid_margin"])
        k0 = np.linalg.norm(local / radius, axis=-1)
        k1 = np.linalg.norm(local / (radius * radius), axis=-1)
        envelope = k0 * (k0 - 1.) / np.maximum(k1, 1e-8)
        lids.append(smax(envelope, -aperture, p["lid_edge_rounding"]))
    cavity = np.minimum(cavities[0], cavities[1])
    carved = smax(base_field(points), -cavity, p["socket_rounding"])
    return smin(carved, np.minimum(lids[0], lids[1]), p["lid_join"])


def bill_smile(y, width, cosine):
    return .031 * abs(cosine) ** 2.0 * min(1., width / .080) * smooth(-.565, -.435, y)


def bill_height(y, width, height, seam, cosine, sine, lobe=""):
    smile = bill_smile(y, width, cosine)
    if lobe == "upper":
        roof = max(0., sine)
        return seam + .0024 + height * roof ** 1.25 + smile * (1. - roof) - height * .018 * max(0., -sine)
    if lobe == "lower":
        return seam - .0024 - height * max(0., -sine) ** 1.10 + smile + height * .018 * max(0., sine)
    return seam + sine * height + smile


def body_paint(point, eye_frame):
    """Curved anatomical masks; no constant front-angle cutoff on the cheek."""
    x, y, z = point
    angle = abs(math.atan2(x, -y))
    cheek_center = 1.333 + .018 * math.cos(angle * .9)
    cheek_q = ((angle - .63) / 1.04) ** 2 + ((z - cheek_center) / .172) ** 2
    cheek = 1. - smooth(.88, 1.12, cheek_q)
    chin = 1. - smooth(.88, 1.12, (angle / .85) ** 2 + ((z - 1.210) / .190) ** 2)
    chest = 1. - smooth(.90, 1.12, (angle / 1.03) ** 2 + ((z - .760) / .650) ** 2)
    orbit, lash = 0., 0.
    for side in (-1., 1.):
        origin, across, normal, up = eye_frame(side)
        relative = tuple(point[i] - origin[i] for i in range(3))
        local_x, depth, local_z = (sum(relative[i] * axis[i] for i in range(3))
                                    for axis in (across, normal, up))
        depth_gate = smooth(-.075, -.015, depth)
        q = (local_x / .145) ** 2 + ((local_z + .020) / .165) ** 2
        orbit = max(orbit, (1. - smooth(.88, 1.12, q)) * depth_gate)
        center_z = ORBIT["center_z"] - ORBIT["outer_corner_drop"] * side * local_x
        vertical = local_z - center_z
        rz = ORBIT["opening_upper"] if vertical >= 0. else ORBIT["opening_lower"]
        edge = (math.sqrt(((local_x + side * ORBIT["nasal_offset"]) / ORBIT["opening_x"]) ** 2
                          + (vertical / rz) ** 2) - 1.) * ORBIT["opening_distance_scale"]
        # Thin upper waterline, softer lower crease; neither forms a black ring.
        upper = smooth(-.015, .020, local_z)
        edge_weight = math.exp(-((edge - .0015) / .0030) ** 2)
        lash = max(lash, edge_weight * depth_gate * (.15 + .68 * upper))
    cream = max(cheek, chin, chest, orbit)
    bridge = (1. - smooth(.034, .066, abs(x))) * smooth(1.384, 1.454, z)
    cream *= 1. - bridge
    face_light = smooth(1.25, 1.43, z)
    ivory = tuple(a + (b - a) * face_light for a, b in
                  zip((.73, .62, .445, 1.), (.82, .75, .595, 1.)))
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
    selected, parent = study.fresh_design(PARENT_PROFILE)
    previous = {name: getattr(selected, name) for name in ("BILL_UPPER_SECTIONS", "BILL_LOWER_SECTIONS")}
    selected.BILL_UPPER_SECTIONS, selected.BILL_LOWER_SECTIONS = BILL_UPPER, BILL_LOWER
    original_base = selected.base_body_field
    selected.base_body_field = lambda points: original_base(warp_points(points))
    selected.__dict__.update(_z09_sculpt=sculpt_face, _z09_bill_height=bill_height, _z09_bill_smile=bill_smile)
    source = '''def sculpt_body_field(points):
    return _z09_sculpt(points, base_body_field, eye_surface_frame, EYE_RADII, EYE_BURY_DEPTH)
def bill_section_height(y, width, height, center_z, cosine, sine, lobe=""):
    return _z09_bill_height(y, width, height, center_z, cosine, sine, lobe)
def bill_smile_offset(y, width, cosine):
    return _z09_bill_smile(y, width, cosine)
'''
    exec(compile(source, __file__, "exec"), selected.__dict__)
    if selected.eye_surface_frame.cache_info().currsize:
        raise RuntimeError("Z09 requires a fresh unevaluated eye frame")
    return selected, {"parent_design_record": parent, "shape_parameters": SHAPE.copy(),
                      "orbital_construction": ORBIT.copy(), "z09_function_replacements": source,
                      "z09_constant_changes": [{"anchor": name, "baseline": old,
                                                 "selected": getattr(selected, name)} for name, old in previous.items()],
                      "selected_design_constants": study.constants(selected)}


@contextmanager
def installed_design():
    selected, record = fresh_design()
    old = sys.modules.get(study.DESIGN_MODULE)
    sys.modules[study.DESIGN_MODULE] = selected
    try:
        yield selected, record
    finally:
        if old is None:
            sys.modules.pop(study.DESIGN_MODULE, None)
        else:
            sys.modules[study.DESIGN_MODULE] = old


def renderer_syntax(path):
    tree, parent = study.renderer_syntax(PARENT_PROFILE, path)
    paint = study.function_node(tree, "body_paint")
    old_paint = study.ast_digest(ast.Module(body=[paint], type_ignores=[]))
    paint.body = ast.parse("return _z09_body_paint(point, eye_surface_frame)").body
    tree.body.insert(tree.body.index(paint), ast.parse(
        "from hero_penguin_v12_face_z09 import body_paint as _z09_body_paint").body[0])
    eye_set = study.function_node(tree, "add_eye_set")
    catches = [n for n in ast.walk(eye_set) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
               and n.func.id == "eye_paint_disc" and n.args and isinstance(n.args[0], ast.JoinedStr)
               and isinstance(n.args[0].values[0], ast.Constant) and n.args[0].values[0].value == "Catchlight"]
    if len(catches) != 1 or not isinstance(catches[0].args[3], ast.Tuple):
        raise ValueError("Z09 catchlight anchor changed")
    plans = [study.literal_plan(node, old, new, f"add_eye_set.catchlight.radii[{i}]")
             for i, (node, old, new) in enumerate(zip(catches[0].args[3].elts, (.008, .011), (.0055, .008)))]
    nostril = study.assignment(study.function_node(tree, "add_bill"), "nostril").value.args[1]
    if ast.dump(nostril) != ast.dump(ast.parse("(side * .047, -.448, 1.429)", mode="eval").body):
        raise ValueError("Z09 nostril location anchor changed")
    plans += [study.literal_plan(nostril.elts[0].right, .047, .040, "add_bill.nostril.x"),
              study.literal_plan(nostril.elts[1], -.448, -.465, "add_bill.nostril.y"),
              study.literal_plan(nostril.elts[2], 1.429, 1.422, "add_bill.nostril.z")]
    for node, value, _record in plans:
        node.value = value
    ast.fix_missing_locations(tree)
    return tree, {"parent_renderer_record": parent, "z09_body_paint_replaced_ast_sha256": old_paint,
                  "z09_body_paint_helper": "hero_penguin_v12_face_z09.body_paint",
                  "z09_renderer_literal_changes": [item[2] for item in plans],
                  "selected_renderer_ast_sha256": study.ast_digest(tree)}


def apply_material_changes(materials):
    targets = []
    for name, change in MATERIALS.items():
        shader = materials[name].node_tree.nodes.get("Principled BSDF")
        if shader is None:
            raise ValueError(f"Z09 missing Principled material: {name}")
        sockets = shader.inputs
        for key in ("Roughness", "Specular IOR Level", "IOR"):
            if sockets[key].is_linked:
                raise ValueError(f"Z09 unexpected linked material control: {name}/{key}")
        if abs(sockets["Roughness"].default_value - change["old_roughness"]) > 1e-6:
            raise ValueError(f"Z09 parent roughness changed: {name}")
        if "base_color" in change and sockets["Base Color"].is_linked:
            raise ValueError(f"Z09 cannot override linked pupil color: {name}")
        targets.append((name, change, sockets))
    receipt = []
    for name, change, sockets in targets:
        controls = {"Roughness": change["roughness"], "Specular IOR Level": change["specular"], "IOR": change["ior"]}
        if "base_color" in change:
            controls["Base Color"] = change["base_color"]
        for control, value in controls.items():
            old = sockets[control].default_value
            receipt.append({"material": name, "control": control,
                            "baseline": float(old) if isinstance(value, float) else tuple(old), "selected": value})
            sockets[control].default_value = value
    return receipt


def source_only_declarations():
    return {"schema_version": 1, "study_profile": PROFILE, "parent_profile": PARENT_PROFILE,
            "source_only": True, "production_ready": False, "source_fidelity_approved": False,
            "geometry_approved": False, "candidate_export_allowed": False, "runtime_rig_or_glb_created": False,
            "export_policy": "Unregistered independent source construction; reject candidate/atlas export.",
            "scope": "Shared-head upper/lower eyelids and sockets, cheek/muzzle/throat form, anatomical curved paint, expressive two-lobe bill, lit eye/bill materials.",
            "z06_eye_dimensions_frame_gaze_crown_feet_cameras_lights_maps_preserved": True,
            "material_callback_recipe": MATERIALS,
            "approval_policy": "No numeric predicate grants visual approval; inspect all three fixed views against reference."}
