"""Renderer-free, opt-in source studies; baseline files remain immutable.

Studies change explicit scoped AST literals before executing fresh design and
renderer modules. Assigning imported constants afterwards leaves aliases,
function defaults and cached design functions in inconsistent configurations.
No profile is art approval or a live runtime promotion.
"""
from __future__ import annotations

import ast
from contextlib import contextmanager
import hashlib
import json
import math
from pathlib import Path
import sys
from types import ModuleType

DESIGN_PATH = Path(__file__).with_name("hero_penguin_v12_design.py")
DESIGN_MODULE = "hero_penguin_v12_design"
PARAMETER = "EYE_BURY_DEPTH"
BASELINE_DEPTH = 0.069
# Each edit is (top-level design assignment, tuple indices, exact old literal,
# selected literal). No external expression or arbitrary text patch is allowed.
PROFILE_OVERRIDES = {
    "baseline": (),
    "eye-aperture-z01": ((PARAMETER, (), 0.069, 0.064),),
    "face-paddles-z02": (
        (PARAMETER, (), 0.069, 0.064),
        ("BILL_UPPER_SECTIONS", (0, 2), 0.087, 0.105),
        ("BILL_UPPER_SECTIONS", (1, 2), 0.090, 0.108),
        ("BILL_LOWER_SECTIONS", (1, 1), 0.120, 0.108),
    ),
    "orbital-heading-z03": (
        (PARAMETER, (), 0.069, 0.064),
        ("BILL_UPPER_SECTIONS", (0, 2), 0.087, 0.105),
        ("BILL_UPPER_SECTIONS", (1, 2), 0.090, 0.108),
        ("BILL_LOWER_SECTIONS", (1, 1), 0.120, 0.108),
        ("EYE_ORBITAL_HEADING_FACTOR", (), 1.35, 2.0),
    ),
    "orbital-saddle-z04": (
        (PARAMETER, (), 0.069, 0.064),
        ("BILL_UPPER_SECTIONS", (0, 2), 0.087, 0.105),
        ("BILL_UPPER_SECTIONS", (1, 2), 0.090, 0.108),
        ("BILL_LOWER_SECTIONS", (1, 1), 0.120, 0.108),
        ("EYE_CENTER_X", (), 0.181, 0.225),
    ),
    # One coordinated silhouette/face pass. The crown/feet stay in the old
    # height envelope; the cranium grows downward into a fuller shoulder and
    # cheek mass. Eye, paint, mouth and paddle changes belong to this cohort.
    "juvenile-sculpt-z05": (
        ("BODY_SMOOTH_RADIUS", (), 0.105, 0.125),
        ("TORSO_RADII", (0,), 0.526, 0.550),
        ("TORSO_RADII", (1,), 0.427, 0.446),
        ("TORSO_UPPER_EXPONENT", (), 2.1, 2.45),
        ("BODY_VOLUMES", (0, 1, 0), 0.375, 0.420),
        ("BODY_VOLUMES", (0, 1, 1), 0.345, 0.373),
        ("BODY_VOLUMES", (0, 1, 2), 0.368, 0.389),
        ("BODY_VOLUMES", (1, 0, 2), 1.441, 1.375),
        ("BODY_VOLUMES", (1, 1, 0), 0.400, 0.438),
        ("BODY_VOLUMES", (1, 1, 1), 0.365, 0.391),
        ("BODY_VOLUMES", (1, 1, 2), 0.365, 0.427),
        ("BODY_VOLUMES", (2, 0, 2), 1.280, 1.235),
        ("BODY_VOLUMES", (2, 1, 0), 0.357, 0.402),
        ("BODY_VOLUMES", (2, 1, 1), 0.332, 0.364),
        ("BODY_VOLUMES", (2, 1, 2), 0.257, 0.290),
        ("CHEEK_VOLUMES", (0, 0, 0), -0.162, -0.182),
        ("CHEEK_VOLUMES", (1, 0, 0), 0.162, 0.182),
        *(("CHEEK_VOLUMES", (side, 0, 2), 1.394, 1.333) for side in (0, 1)),
        *(("CHEEK_VOLUMES", (side, 1, 0), 0.222, 0.250) for side in (0, 1)),
        *(("CHEEK_VOLUMES", (side, 1, 1), 0.203, 0.216) for side in (0, 1)),
        *(("CHEEK_VOLUMES", (side, 1, 2), 0.146, 0.174) for side in (0, 1)),
        ("CHEEK_VOLUMES", (2, 0, 2), 1.277, 1.200),
        ("CHEEK_VOLUMES", (2, 1, 0), 0.227, 0.263),
        ("CHEEK_VOLUMES", (2, 1, 1), 0.185, 0.200),
        ("CHEEK_VOLUMES", (2, 1, 2), 0.184, 0.217),
        ("EYE_CENTER_X", (), 0.181, 0.215),
        ("EYE_CENTER_Z", (), 1.548, 1.480),
        ("EYE_RADII", (0,), 0.108, 0.147),
        ("EYE_RADII", (1,), 0.089, 0.100),
        ("EYE_RADII", (2,), 0.146, 0.176),
        (PARAMETER, (), 0.069, 0.074),
        ("EYE_ORBITAL_HEADING_FACTOR", (), 1.35, 1.70),
        ("EYE_GAZE_TARGET", (2,), 2.45, 1.68),
        ("EYE_GAZE_HORIZONTAL_SCALE", (), 0.60, 0.20),
        ("UPPER_FOLD_APERTURE_HEIGHT", (), 0.083, 0.097),
        ("UPPER_FOLD_APERTURE_WIDTH", (), 0.080, 0.105),
        ("LIMBAL_RADII", (0,), 0.067, 0.080),
        ("LIMBAL_RADII", (1,), 0.087, 0.102),
        ("IRIS_RADII", (0,), 0.061, 0.073),
        ("IRIS_RADII", (1,), 0.081, 0.093),
        ("PUPIL_RADII", (0,), 0.037, 0.044),
        ("PUPIL_RADII", (1,), 0.050, 0.059),
        # Lower the entire mouth with the cheeks, broaden the shoulder dome,
        # and tuck the lower jaw inside the upper bill's rounded taper.
        *(("BILL_UPPER_SECTIONS", (row, col), old, new)
          for row, (before, after) in enumerate(zip(
              ((-0.351, .100, .087, 1.389), (-0.397, .125, .090, 1.378),
               (-0.431, .117, .084, 1.371), (-0.466, .087, .067, 1.372),
               (-0.500, .050, .042, 1.380), (-0.526, .023, .022, 1.388),
               (-0.538, .003, .002, 1.392)),
              ((-0.389, .118, .105, 1.331), (-0.431, .147, .119, 1.320),
               (-0.471, .135, .109, 1.309), (-0.508, .097, .078, 1.306),
               (-0.540, .058, .046, 1.311), (-0.562, .026, .021, 1.321),
               (-0.571, .003, .002, 1.326))))
          for col, (old, new) in enumerate(zip(before, after)) if old != new),
        *(("BILL_LOWER_SECTIONS", (row, col), old, new)
          for row, (before, after) in enumerate(zip(
              ((-0.354, .098, .013, 1.389), (-0.397, .120, .031, 1.378),
               (-0.431, .110, .034, 1.371), (-0.463, .079, .026, 1.373),
               (-0.488, .044, .016, 1.382), (-0.507, .017, .004, 1.389),
               (-0.512, .002, .001, 1.392)),
              ((-0.392, .112, .018, 1.331), (-0.431, .133, .038, 1.320),
               (-0.469, .119, .041, 1.310), (-0.502, .088, .031, 1.307),
               (-0.526, .048, .019, 1.315), (-0.545, .019, .006, 1.323),
               (-0.550, .002, .001, 1.326))))
          for col, (old, new) in enumerate(zip(before, after)) if old != new),
        ("WING_ROOT", (0,), 0.310, 0.345),
        ("WING_ROOT", (2,), 1.225, 1.200),
        ("WING_CONTROL", (0,), 0.615, 0.640),
        ("WING_CONTROL", (2,), 0.987, 0.940),
        ("WING_TIP", (0,), 0.705, 0.690),
        ("WING_TIP", (2,), 0.484, 0.460),
        ("WING_HALF_WIDTH", (), 0.128, 0.147),
        ("WING_HALF_THICKNESS", (), 0.045, 0.050),
    ),
}
BASELINE_WIDTH_KEYS = ((0.0, 0.055), (0.18, 0.102), (0.40, 0.095),
                       (0.65, 0.065), (0.84, 0.039), (0.93, 0.026),
                       (0.97, 0.017), (1.0, 0.004))
BASELINE_ORBIT_EXPRESSION = (
    "min(ellipse(-EYE_CENTER_X, EYE_CENTER_Z - 0.019, 0.120, 0.125), "
    "ellipse(EYE_CENTER_X, EYE_CENTER_Z - 0.019, 0.120, 0.125))")
BASELINE_LID_EXPRESSION = "smooth(-0.002, 0.001, edge) * (1.0 - smooth(0.010, 0.025, edge))"
SADDLE_LID_EXPRESSION = "smooth(-0.002, 0.001, edge)"
SADDLE_ORBIT_EXPRESSION = "saddle_orbit_field(point, eye_surface_frame)"
SADDLE_IMPORT = "from hero_penguin_v12_orbital_saddle import saddle_orbit_field"
JUVENILE_PROFILE = "juvenile-sculpt-z05"
SOCKET_PROFILE = "juvenile-socket-z06"
JUVENILE_PROFILES = (JUVENILE_PROFILE, SOCKET_PROFILE)
# Register the attentive gaze in the actual tilted orbital frame. Z05's low
# world target displaced each iris 52 mm downward into its lower cheek.
PROFILE_OVERRIDES[SOCKET_PROFILE] = tuple(
    (name, indices, old, 2.40 if name == "EYE_GAZE_TARGET" and indices == (2,) else new)
    for name, indices, old, new in PROFILE_OVERRIDES[JUVENILE_PROFILE])
JUVENILE_IMPORT = "from hero_penguin_v12_source_study import juvenile_orbit_field"
JUVENILE_ORBIT_EXPRESSION = "juvenile_orbit_field(point, eye_surface_frame)"
SOCKET_IMPORT = "from hero_penguin_v12_source_study import juvenile_socket_relief"
SOCKET_RELIEF_RECIPE = {
    "maximum_inward_m": .020,
    "outer_center_m": .025,
    "vertical_center_m": -.055,
    "half_width_m": .150,
    "half_height_m": .140,
    "depth_fade_m": [-.070, -.020],
    "upper_fade_m": [-.025, .030],
    "globe_or_burial_changed": False,
    "source_fidelity_approved": False,
}
SHARED_FUNCTIONS = ("sculpt_body_field", "eye_surface_frame", "eye_gaze_center",
                    "upper_lid_pigment_weight", "project_eye_patch", "bill_section_height",
                    "paddle_cross_section")


def sha_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def constants(module: ModuleType) -> dict:
    return {key: value for key, value in vars(module).items() if key.isupper()}


def ast_digest(tree) -> str:
    return sha_bytes(ast.dump(tree, include_attributes=False).encode())


def assignment(scope, name, *, top_level=False):
    found = []
    for node in ast.walk(scope):
        targets = node.targets if isinstance(node, ast.Assign) else (
            [node.target] if isinstance(node, (ast.AnnAssign, ast.AugAssign, ast.NamedExpr)) else [])
        if any(isinstance(target, ast.Name) and target.id == name for target in targets):
            found.append(node)
    if len(found) != 1 or not isinstance(found[0], (ast.Assign, ast.AnnAssign)) \
            or (isinstance(found[0], ast.Assign) and len(found[0].targets) != 1) \
            or (top_level and found[0] not in scope.body):
        raise ValueError(f"source study requires exactly one scoped assignment: {name}")
    return found[0]


def tuple_literal(node, indices):
    for index in indices:
        if not isinstance(node, ast.Tuple) or not 0 <= index < len(node.elts):
            raise ValueError("source study tuple anchor changed")
        node = node.elts[index]
    return node


def literal_plan(node, expected, selected, anchor):
    # Negative tuple coordinates are represented by a UnaryOp in Python's AST.
    # Keep the sign operator intact and change only its validated float leaf.
    if (isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub)
            and isinstance(node.operand, ast.Constant)
            and type(node.operand.value) is float and -node.operand.value == expected
            and expected < 0.0 and selected < 0.0):
        return node.operand, -selected, {"anchor": anchor, "baseline": expected, "selected": selected}
    if not isinstance(node, ast.Constant) or type(node.value) is not float or node.value != expected:
        raise ValueError(f"source study literal anchor changed: {anchor}")
    return node, selected, {"anchor": anchor, "baseline": expected, "selected": selected}


def function_node(tree, name):
    found = [node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef) and node.name == name]
    if len(found) != 1 or found[0] not in tree.body:
        raise ValueError(f"source study requires exactly one top-level function: {name}")
    return found[0]


def expression_plan(node, expected, selected, anchor):
    original = ast.parse(expected, mode="eval").body
    if ast.dump(node.value, include_attributes=False) != ast.dump(original, include_attributes=False):
        raise ValueError("source study expression anchor changed: " + anchor)
    return node, ast.parse(selected, mode="eval").body, {"anchor": anchor, "baseline": expected, "selected": selected}


def juvenile_orbit_field(point, frame_for_side):
    """Paint a wide eye opening that flows downward into the cheek.

    This is a pigment field on the shared sculpt, never an annular eye mesh.
    The upper lid joins the hood; the lower opening fans into the cheek so
    increasing the eye does not produce an isolated cream badge/ring.
    """
    if point[2] < 1.08 or point[2] > 1.77 or abs(point[0]) > .53 or point[1] > .10:
        return 8.0

    def smooth(low, high, value):
        value = max(0.0, min(1.0, (value - low) / (high - low)))
        return value * value * (3.0 - 2.0 * value)

    result = 8.0
    for side in (-1.0, 1.0):
        origin, across, normal, up = frame_for_side(side)
        relative = tuple(point[i] - origin[i] for i in range(3))
        x, depth, z = (sum(relative[i] * axis[i] for i in range(3))
                       for axis in (across, normal, up))
        lower = smooth(.015, .180, -z)
        width = .129 + .035 * lower
        center = -side * .040 * lower
        vertical = z + .029
        radius = .189 if vertical < 0.0 else .139
        field = abs((x - center) / width) ** 1.8 + (vertical / radius) ** 2
        field += 4.0 * (1.0 - smooth(-.100, -.035, depth))
        result = min(result, field)
    return result


def juvenile_socket_relief(points, base, frame_for_side):
    """A shallow continuous lower socket carved into the same body surface.

    This raises the field (removes at most 20 mm), never adds a rim or pushes
    the globe out. The squared compact bowl reaches zero with zero slope;
    depth/upper fades preserve the back of the head and original upper fold.
    The anatomical frame is sampled from the pre-socket field, avoiding a
    recursive eye anchor or a camera-dependent correction.
    """
    import numpy as np

    points = np.asarray(points)
    amount = np.zeros_like(base)

    def smooth(low, high, value):
        value = np.clip((value - low) / (high - low), 0.0, 1.0)
        return value * value * (3.0 - 2.0 * value)

    recipe = SOCKET_RELIEF_RECIPE
    for side in (-1.0, 1.0):
        origin, across, normal, up = map(np.asarray, frame_for_side(side))
        relative = points - origin
        x, depth, z = relative @ across, relative @ normal, relative @ up
        q = ((x - side * recipe["outer_center_m"]) / recipe["half_width_m"]) ** 2
        q += ((z - recipe["vertical_center_m"]) / recipe["half_height_m"]) ** 2
        bowl = np.maximum(0.0, 1.0 - q) ** 2
        bowl *= smooth(*recipe["depth_fade_m"], depth)
        bowl *= 1.0 - smooth(*recipe["upper_fade_m"], z)
        amount = np.maximum(amount, recipe["maximum_inward_m"] * bowl)
    return base + amount


def renderer_syntax(profile, path):
    """Validate renderer-local scope before publishing/executing either cohort."""
    if profile not in PROFILE_OVERRIDES:
        raise ValueError(f"unknown source study profile: {profile!r}")
    path = Path(path).resolve(strict=True)
    raw = path.read_bytes()
    tree = ast.parse(raw, filename=str(path))
    original_ast = ast_digest(tree)
    plans = []
    expressions = []
    if profile in {"face-paddles-z02", "orbital-heading-z03", "orbital-saddle-z04"}:
        orbit = assignment(function_node(tree, "body_paint"), "orbit")
        expected = ast.parse(BASELINE_ORBIT_EXPRESSION, mode="eval").body
        if ast.dump(orbit.value, include_attributes=False) != ast.dump(expected, include_attributes=False):
            raise ValueError("source study body_paint.orbit expression anchor changed")
        if profile == "orbital-saddle-z04":
            if any(isinstance(node, ast.Name) and node.id == "saddle_orbit_field" or
                   isinstance(node, ast.alias) and node.name == "saddle_orbit_field" for node in ast.walk(tree)):
                raise ValueError("source saddle helper name already exists")
            expressions.append(expression_plan(orbit, BASELINE_ORBIT_EXPRESSION, SADDLE_ORBIT_EXPRESSION,
                                                "body_paint.orbit"))
        else:
            for side, ellipse in enumerate(orbit.value.args):
                plans.append(literal_plan(ellipse.args[2], .120, .108, f"body_paint.orbit.ellipse[{side}].rx"))
                plans.append(literal_plan(ellipse.args[3], .125, .118, f"body_paint.orbit.ellipse[{side}].rz"))
        widths = assignment(function_node(tree, "add_paddle"), "width_keys")
        expected_widths = ast.parse(repr(BASELINE_WIDTH_KEYS), mode="eval").body
        if ast.dump(widths.value, include_attributes=False) != ast.dump(expected_widths, include_attributes=False):
            raise ValueError("source study add_paddle.width_keys anchor changed")
        for index, expected_width, selected_width in ((4, .039, .050), (5, .026, .036), (6, .017, .025)):
            plans.append(literal_plan(tuple_literal(widths.value, (index, 1)), expected_width, selected_width,
                                      f"add_paddle.width_keys[t={BASELINE_WIDTH_KEYS[index][0]}].width"))
    if profile in JUVENILE_PROFILES:
        if any((isinstance(node, ast.Name) and node.id == "juvenile_orbit_field") or
               (isinstance(node, ast.alias) and node.name == "juvenile_orbit_field") for node in ast.walk(tree)):
            raise ValueError("source juvenile helper name already exists")
        paint = function_node(tree, "body_paint")
        for name, before, after in (
            ("orbit", BASELINE_ORBIT_EXPRESSION, JUVENILE_ORBIT_EXPRESSION),
            ("cheek", "min(ellipse(-0.162, 1.394, 0.235, 0.159), ellipse(0.162, 1.394, 0.235, 0.159))",
             "min(ellipse(-0.182, 1.333, 0.265, 0.182), ellipse(0.182, 1.333, 0.265, 0.182))"),
            ("chin", "ellipse(0.0, 1.225, 0.308, 0.244)", "ellipse(0.0, 1.180, 0.337, 0.260)"),
            ("ear_field", "((angle - 1.46) / 0.40) ** 2 + ((point.z - 1.411) / 0.078) ** 2",
             "((angle - 1.46) / 0.40) ** 2 + ((point.z - 1.350) / 0.092) ** 2"),
            ("stripe_z", "1.232 + 0.040 * (angle - 1.10) + 0.017 * math.sin((angle - 1.10) * 3.3)",
             "1.188 + 0.040 * (angle - 1.10) + 0.017 * math.sin((angle - 1.10) * 3.3)"),
        ):
            expressions.append(expression_plan(assignment(paint, name), before, after, "body_paint." + name))
        bridge = [node for node in ast.walk(paint) if isinstance(node, ast.AugAssign)
                  and isinstance(node.target, ast.Name) and node.target.id == "bridge"]
        if len(bridge) != 1 or not isinstance(bridge[0].op, ast.Mult):
            raise ValueError("source juvenile requires one bridge-height multiplier")
        expressions.append(expression_plan(bridge[0],
            "smoothstep(1.442 + 0.75 * abs(point.x), 1.470 + 0.75 * abs(point.x), point.z)",
            "smoothstep(1.384 + 0.75 * abs(point.x), 1.412 + 0.75 * abs(point.x), point.z)",
            "body_paint.bridge_height"))
        widths = assignment(function_node(tree, "add_paddle"), "width_keys")
        expressions.append(expression_plan(widths, repr(BASELINE_WIDTH_KEYS),
            repr(((0.0, .055), (.18, .110), (.40, .104), (.65, .076),
                  (.84, .050), (.93, .036), (.97, .025), (1.0, .004))), "add_paddle.width_keys"))
        nostril = assignment(function_node(tree, "add_bill"), "nostril").value
        if (not isinstance(nostril, ast.Call) or not isinstance(nostril.func, ast.Name)
                or nostril.func.id != "add_ico_ellipsoid" or len(nostril.args) != 5):
            raise ValueError("source juvenile nostril constructor changed")
        placement = nostril.args[1]
        if (not isinstance(placement, ast.Tuple) or len(placement.elts) != 3
                or ast.dump(placement.elts[0], include_attributes=False)
                != ast.dump(ast.parse("side * 0.042", mode="eval").body, include_attributes=False)):
            raise ValueError("source juvenile nostril placement changed")
        plans.extend((
            literal_plan(placement.elts[0].right, .042, .047, "add_bill.nostril.x"),
            literal_plan(placement.elts[1], -.408, -.448, "add_bill.nostril.y"),
            literal_plan(placement.elts[2], 1.456, 1.429, "add_bill.nostril.z"),
        ))
        refinement = function_node(tree, "refine_orbital_surface")
        near = [node for node in ast.walk(refinement) if isinstance(node, ast.FunctionDef) and node.name == "near_eye"]
        if len(near) != 1 or len(near[0].body) != 1 or not isinstance(near[0].body[0], ast.Return):
            raise ValueError("source juvenile orbital refinement region changed")
        expressions.append(expression_plan(near[0].body[0],
            "0.045 < abs(point.x) < 0.40 and point.y < -0.19 and 1.43 < point.z < 1.77",
            "0.045 < abs(point.x) < 0.43 and point.y < -0.19 and 1.32 < point.z < 1.77",
            "refine_orbital_surface.near_eye"))
    # Every anchor is validated before any mutation. Only seven exact leaves
    # differ in Z02; all colors, centers, gaze and surrounding code stay intact.
    for node, value, _record in plans:
        node.value = value
    for node, value, _record in expressions:
        node.value = ast.copy_location(value, node.value)
    if profile == "orbital-saddle-z04":
        tree.body.insert(tree.body.index(function_node(tree, "body_paint")), ast.parse(SADDLE_IMPORT).body[0])
        ast.fix_missing_locations(tree)
    if profile in JUVENILE_PROFILES:
        tree.body.insert(tree.body.index(function_node(tree, "body_paint")), ast.parse(JUVENILE_IMPORT).body[0])
        ast.fix_missing_locations(tree)
    record = {"baseline_renderer_path": str(path), "baseline_renderer_sha256": sha_bytes(raw),
              "baseline_renderer_ast_sha256": original_ast, "selected_renderer_ast_sha256": ast_digest(tree),
              "renderer_literal_overrides": [item[2] for item in plans]}
    if profile == "orbital-saddle-z04":
        import hero_penguin_v12_orbital_saddle as saddle
        record.update(renderer_expression_overrides=[item[2] for item in expressions],
                      renderer_added_imports=[SADDLE_IMPORT], orbital_saddle_recipe=saddle.RECIPE.copy(),
                      orbital_saddle_helper_sha256=sha_bytes(Path(saddle.__file__).read_bytes()))
    if profile in JUVENILE_PROFILES:
        record.update(renderer_expression_overrides=[item[2] for item in expressions],
                      renderer_added_imports=[JUVENILE_IMPORT],
                      juvenile_orbit_helper_sha256=sha_bytes(Path(__file__).read_bytes()))
    return tree, record


def fresh_design(profile: str = "baseline", path: Path = DESIGN_PATH) -> tuple[ModuleType, dict]:
    """Validate fully before publishing any module or touching existing caches."""
    if profile not in PROFILE_OVERRIDES:
        raise ValueError(f"unknown source study profile: {profile!r}")
    edits = PROFILE_OVERRIDES[profile]
    path = path.resolve(strict=True)
    raw = path.read_bytes()
    tree = ast.parse(raw, filename=str(path))
    try:
        eye = assignment(tree, PARAMETER, top_level=True)
        literal_plan(eye.value, BASELINE_DEPTH, BASELINE_DEPTH, PARAMETER)
    except ValueError as error:
        raise ValueError("baseline eye-depth literal changed; source study must be reviewed again") from error
    plans = []
    expressions = []
    seen = set()
    for name, indices, old, new in edits:
        if (name, indices) in seen:
            raise ValueError("duplicate source study design edit")
        seen.add((name, indices))
        anchor = name + "".join(f"[{index}]" for index in indices)
        node = tuple_literal(assignment(tree, name, top_level=True).value, indices)
        plans.append(literal_plan(node, old, new, anchor))
    if profile in {"orbital-saddle-z04", *JUVENILE_PROFILES}:
        # This function intentionally has one later `upper *= ...` side/depth
        # gate. Change only its unique initial Assign, preserving that gate.
        initial = [node for node in ast.walk(function_node(tree, "upper_lid_pigment_weight"))
                   if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == "upper"
                                                          for target in node.targets)]
        if len(initial) != 1 or len(initial[0].targets) != 1:
            raise ValueError("source saddle requires one initial upper-lid assignment")
        upper = initial[0]
        expressions.append(expression_plan(upper, BASELINE_LID_EXPRESSION, SADDLE_LID_EXPRESSION,
                                            "upper_lid_pigment_weight.upper"))
    if profile in JUVENILE_PROFILES:
        lid = function_node(tree, "upper_lid_pigment_weight")
        gate = [node for node in ast.walk(lid) if isinstance(node, ast.AugAssign)
                and isinstance(node.target, ast.Name) and node.target.id == "upper"]
        if len(gate) != 1 or not isinstance(gate[0].op, ast.Mult):
            raise ValueError("source juvenile requires one upper-lid width/depth gate")
        expressions.append(expression_plan(gate[0],
            "smooth(-0.030, -0.005, depth) * (1.0 - smooth(0.075, 0.100, abs(x)))",
            "smooth(-0.030, -0.005, depth) * (1.0 - smooth(0.098, 0.130, abs(x)))",
            "upper_lid_pigment_weight.width_gate"))
        expressions.append(expression_plan(assignment(function_node(tree, "bill_smile_offset"), "blend"),
            "min(1.0, max(0.0, (y + 0.480) / 0.085))",
            "min(1.0, max(0.0, (y + 0.520) / 0.090))", "bill_smile_offset.depth_registration"))
    if profile == SOCKET_PROFILE:
        if any((isinstance(node, ast.Name) and node.id == "juvenile_socket_relief") or
               (isinstance(node, ast.alias) and node.name == "juvenile_socket_relief") for node in ast.walk(tree)):
            raise ValueError("source juvenile socket helper name already exists")
        expressions.append(expression_plan(assignment(function_node(tree, "sculpt_body_field"), "base"),
            "base_body_field(points)", "juvenile_socket_relief(points, base_body_field(points), eye_surface_frame)",
            "sculpt_body_field.base"))

    def execute(syntax: ast.Module) -> ModuleType:
        module = ModuleType(DESIGN_MODULE)
        module.__file__ = str(path)
        module.__package__ = ""
        exec(compile(syntax, str(path), "exec"), module.__dict__)
        return module

    baseline = execute(tree)
    baseline_constants = constants(baseline)
    baseline_ast = ast_digest(tree)
    for node, value, _record in plans:
        node.value = value
    for node, value, _record in expressions:
        node.value = ast.copy_location(value, node.value)
    if profile == SOCKET_PROFILE:
        tree.body.insert(tree.body.index(function_node(tree, "sculpt_body_field")), ast.parse(SOCKET_IMPORT).body[0])
    ast.fix_missing_locations(tree)
    selected = execute(tree)
    selected_constants = constants(selected)
    expected = dict(baseline_constants)
    def replaced(value, indices, new):
        if not indices:
            return new
        items = list(value)
        items[indices[0]] = replaced(items[indices[0]], indices[1:], new)
        return tuple(items)

    for name, indices, _old, new in edits:
        expected[name] = replaced(expected[name], indices, new)
    if selected_constants != expected:
        raise RuntimeError("study changed a design constant outside its explicit declared scope")
    # All actual design functions share this fresh namespace. Their default
    # arguments are captured from the selected literal during module creation.
    if selected.eye_tangent_aperture_radii.__defaults__ != (selected.EYE_RADII, selected.EYE_BURY_DEPTH):
        raise RuntimeError("study analytical defaults disagree with selected eye depth")
    if selected.eye_surface_frame.cache_info().currsize != 0:
        raise RuntimeError("study cannot reuse evaluated design geometry/cache state")
    for name in SHARED_FUNCTIONS:
        function = getattr(selected, name)
        underlying = getattr(function, "__wrapped__", function)
        if underlying.__globals__ is not selected.__dict__:
            raise RuntimeError(f"study design function has a different global configuration: {name}")
    base_aperture = baseline.eye_tangent_aperture_radii()
    study_aperture = selected.eye_tangent_aperture_radii()
    ratio = study_aperture[0] / base_aperture[0]
    if not math.isfinite(ratio):
        raise RuntimeError("nonfinite analytical study aperture")
    record = {"schema_version": 1, "study_profile": profile, "source_only": True,
        "production_ready": False, "source_fidelity_approved": False,
        "baseline_design_path": str(path), "baseline_design_sha256": sha_bytes(raw),
        "profile_helper_sha256": sha_bytes(Path(__file__).read_bytes()),
        "baseline_design_ast_sha256": baseline_ast, "selected_design_ast_sha256": ast_digest(tree),
        "application": "declared scoped AST literals before fresh design/renderer module execution",
        "parameter_overrides": {name: {"baseline": baseline_constants[name], "selected": selected_constants[name]}
                                for name in sorted({item[0] for item in edits})},
        "design_literal_overrides": [item[2] for item in plans],
        "baseline_design_constants": baseline_constants, "selected_design_constants": selected_constants,
        "analytical_tangent_half_aperture_m": {"baseline": base_aperture, "selected": study_aperture},
        "analytical_linear_aperture_ratio": ratio,
        "prediction_only": "Tangent-plane aperture calculation; actual curved skull/lid appearance is unapproved.",
        "gaze_contract": "Target and horizontal scale unchanged; existing gaze formula uses selected burial consistently.",
        "body_paint_contract": ("Only orbital ellipse rx/rz change; centers and pigment colors remain unchanged."
                                if profile in {"face-paddles-z02", "orbital-heading-z03"} else
                                "Shared-frame almond/teardrop surround and hood-connected lid; cheek/bib fields and palette unchanged."
                                if profile == "orbital-saddle-z04" else
                                "Existing paint function unchanged; colors at moved surface points may consequently differ."),
        "runtime_rig_or_glb_created": False}
    if profile == "orbital-saddle-z04":
        record["design_expression_overrides"] = [item[2] for item in expressions]
        record["gaze_contract"] = "Target and horizontal scale unchanged; globe, fold, gaze and paint share the relocated surface-derived frame."
    if profile in JUVENILE_PROFILES:
        record["design_expression_overrides"] = [item[2] for item in expressions]
        record["gaze_contract"] = "Lower attentive target and reduced nasal iris displacement, fixed anatomically for all views."
        record["body_paint_contract"] = "Broader local-frame eye opening flows into lowered full cheeks; upper lid joins hood, never a cream ring."
        record["sculpt_intent"] = "One juvenile proportion/face cohort: lower broader head, full shoulders and cheeks, larger recessed eyes, domed compact bill, soft paddles."
        record["future_export_constraints"] = "Source height envelope retained; canonical rig/bone fit, source coverage and runtime budgets require separate export review."
    if profile == SOCKET_PROFILE:
        record["design_added_imports"] = [SOCKET_IMPORT]
        record["socket_relief_recipe"] = SOCKET_RELIEF_RECIPE.copy()
        record["gaze_contract"] = "Fixed target registered to tilted orbital frame: near-centered local iris, independent of camera."
        record["socket_contract"] = "Shallow continuous lower/outer socket relief in shared body field; unchanged globe/burial and original upper fold."
    # Fail before module publication if a future constant is not JSON-safe.
    json.dumps(record, allow_nan=False)
    return selected, record


@contextmanager
def installed_design(profile: str = "baseline", path: Path = DESIGN_PATH):
    """Atomically install the fresh cohort, restoring any prior module on exit."""
    module, record = fresh_design(profile, path)
    previous = sys.modules.get(DESIGN_MODULE)
    sys.modules[DESIGN_MODULE] = module
    try:
        yield module, record
    finally:
        if previous is None:
            sys.modules.pop(DESIGN_MODULE, None)
        else:
            sys.modules[DESIGN_MODULE] = previous


def require_renderer_cohort(renderer: ModuleType, selected: ModuleType) -> None:
    """Reject stale from-import aliases, before any geometry/cache evaluation."""
    for name, value in constants(selected).items():
        if hasattr(renderer, name) and getattr(renderer, name) != value:
            raise RuntimeError(f"renderer and design study disagree on {name}")
    if not hasattr(renderer, PARAMETER) or renderer.EYE_BURY_DEPTH != selected.EYE_BURY_DEPTH:
        raise RuntimeError("renderer lacks the selected eye-depth import")
    for name in SHARED_FUNCTIONS:
        if getattr(renderer, name, None) is not getattr(selected, name):
            raise RuntimeError(f"renderer holds stale design function: {name}")
    if selected.eye_surface_frame.cache_info().currsize != 0:
        raise RuntimeError("renderer evaluated geometry before study configuration was verified")
