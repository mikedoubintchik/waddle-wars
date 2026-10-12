"""Unified juvenile face source: shared support, canthi, mask and inset eyes.

This replaces the Z09–Z14 orbital construction, not one of its numerical
variants. The complete face support precedes immutable eye registration.
No separate globe-derived hood band is painted over the face. Source-only
until actual views, budgeted export and shared-rig gameplay pass their gates.
"""
from __future__ import annotations

import ast
from contextlib import contextmanager
from functools import lru_cache
import math
import sys

import hero_penguin_eye_pigment as iris_paint
import hero_penguin_v12_face_z13 as paint_graph
import hero_penguin_v12_source_study as study

PROFILE = "unified-juvenile-face"
PARENT_PROFILE = "juvenile-socket-z06"
GROUP_NAME = "JuvenileFace_ContinuousPigment_SourceOnly"

SUPPORT = (
    ((0., .008, 1.422), (.448, .408, .410)),
    ((-.195, -.188, 1.327), (.248, .225, .184)),
    (( .195, -.188, 1.327), (.248, .225, .184)),
    ((0., -.185, 1.235), (.270, .230, .200)),
)
APERTURE = {"width": .105, "upper": .123, "lower": .104,
            "center_z": .006, "outer_drop": .040, "nasal": .005,
            "corner_rounding": .018, "depth": .055}
EYE_RADII = (.130, .100, .170)
EYE_BURIAL = .078
IRIS_ANGLE = .520
PUPIL_ANGLE = .345
LIMBAL_ANGLE = .550
IRIS_RECESS = .0012
PUPIL_RECESS = .0007
BILL_UPPER = (
    (-.400, .094, .064, 1.333), (-.425, .126, .084, 1.329),
    (-.462, .133, .085, 1.327), (-.499, .104, .064, 1.329),
    (-.531, .063, .036, 1.335), (-.551, .024, .012, 1.341),
    (-.559, .002, .001, 1.343),
)
BILL_LOWER = (
    (-.401, .092, .023, 1.333), (-.425, .117, .043, 1.329),
    (-.462, .121, .050, 1.327), (-.495, .091, .036, 1.329),
    (-.523, .048, .019, 1.335), (-.541, .017, .005, 1.341),
    (-.548, .002, .001, 1.343),
)


def smooth(low, high, value):
    t = min(1., max(0., (value - low) / (high - low)))
    return t * t * (3. - 2. * t)


def _smin(a, b, width):
    import numpy as np
    h = np.maximum(width - np.abs(a - b), 0.) / width
    return np.minimum(a, b) - h * h * width * .25


def support_field(points, original_base):
    """Brow, orbital cushion and cheek are one broad sculpt before seating."""
    import numpy as np
    points = np.asarray(points, dtype=float)
    field = original_base(points)
    volumes = []
    for center, radii in SUPPORT:
        p, r = points - np.asarray(center), np.asarray(radii)
        k0 = np.linalg.norm(p / r, axis=-1)
        k1 = np.linalg.norm(p / (r * r), axis=-1)
        distance = k0 * (k0 - 1.) / np.maximum(k1, 1e-8)
        volumes.append(distance)
    # Smooth union is not associative. Group mirrored pairs before combining
    # with the skull so processing order cannot bias the centerline/eye seat.
    for volume in (volumes[0], _smin(volumes[1], volumes[2], .052), volumes[3]):
        field = _smin(field, volume, .052)
    return field


def aperture_field(x, z, side):
    """Rounded canthi with paired parabolic arches, not a circular bore."""
    import numpy as np
    p = APERTURE
    vertical = np.asarray(z) - p["center_z"] + p["outer_drop"] * side * np.asarray(x)
    t = np.clip((vertical + .006) / .012, 0., 1.)
    radius = p["lower"] + (p["upper"] - p["lower"]) * t * t * (3. - 2. * t)
    u = (np.asarray(x) + side * p["nasal"]) / p["width"]
    q = u * u + np.sqrt((vertical / radius) ** 2 + p["corner_rounding"] ** 2)
    return (q - 1.) * .080


def sculpt_face(points, base_field, eye_frame):
    """One shared skin: broad orbital cushions merge into supporting cheeks.

    Smoothly joined cushions sit over the buried globe at the aperture edge;
    their wide footprint returns into the brow/cheek, never a narrow torus.
    Both eyes use the same shallow closed aperture registered to that skin.
    """
    import numpy as np
    points = np.asarray(points, dtype=float)
    field, sockets, cushions = base_field(points), [], []
    for side in (-1., 1.):
        origin, across, normal, up = map(np.asarray, eye_frame(side))
        relative = points - origin
        x, depth, z = relative @ across, relative @ normal, relative @ up
        local = np.stack((x, depth + .040, z - .015), axis=-1)
        r = np.asarray((.185, .078, .225))
        k0, k1 = np.linalg.norm(local / r, axis=-1), np.linalg.norm(local / (r * r), axis=-1)
        cushion = k0 * (k0 - 1.) / np.maximum(k1, 1e-8)
        cushions.append(cushion)
        opening = aperture_field(x, z, side)
        # Positive inside the aperture's finite forward-facing cavity.
        sockets.append(-_smin(-opening, depth + APERTURE["depth"], .004))
    field = _smin(field, _smin(cushions[0], cushions[1], .040), .040)
    cavity = np.minimum(sockets[0], sockets[1])
    return -_smin(-field, cavity, .004)


def bill_smile(y, width, cosine):
    return .029 * abs(cosine) ** 2.0 * min(1., width / .080) * smooth(-.551, -.425, y)


def bill_height(y, width, height, seam, cosine, sine, lobe=""):
    smile = bill_smile(y, width, cosine)
    if lobe == "upper":
        roof = max(0., sine)
        return seam + .0022 + height * roof ** .90 + smile * (1. - roof) - height * .025 * max(0., -sine)
    if lobe == "lower":
        return seam - .0022 - height * max(0., -sine) + smile + height * .025 * max(0., sine)
    return seam + sine * height + smile


def full_paint_program(eye_frames, eye_radii):
    """One coherent cheek/orbit/hood outline, no clamped-aperture hood strip."""
    operations = []

    def op(kind, a, b=0.):
        name = f"face_{len(operations):03d}"
        operations.append((name, kind, a, b))
        return name

    def add(a, b): return op("ADD", a, b)
    def sub(a, b): return op("SUBTRACT", a, b)
    def mul(a, b): return op("MULTIPLY", a, b)
    def div(a, b): return op("DIVIDE", a, b)
    def square(a): return mul(a, a)
    def maximum(a, b): return op("MAXIMUM", a, b)
    def mix(a, b, t): return add(a, mul(sub(b, a), t))
    def smooth_math(low, high, value):
        t = op("MINIMUM", maximum(div(sub(value, low), sub(high, low)), 0.), 1.)
        return mul(square(t), sub(3., mul(2., t)))

    x, y, z = "x", "y", "z"
    angle = op("ABSOLUTE", op("ARCTAN2", x, sub(0., y)))
    front = div(sub(0., y), maximum(.001, op("SQRT", add(square(x), square(y)))))
    width = sub(.484, mul(.124, smooth_math(.95, 1.32, z)))
    chest_q = add(square(div(x, width)), square(div(sub(z, .730), .770)))
    chest = mul(sub(1., smooth_math(.92, 1.08, chest_q)), smooth_math(.03, .23, front))
    cheek_q = add(square(div(sub(angle, .53), 1.13)), square(div(sub(z, 1.340), .211)))
    cheek = sub(1., smooth_math(.91, 1.07, cheek_q))
    chin_q = add(square(div(angle, .97)), square(div(sub(z, 1.225), .228)))
    chin = sub(1., smooth_math(.91, 1.07, chin_q))
    orbit = 0.
    for side in (-1., 1.):
        origin, across, normal, up = eye_frames[side]
        relative = [sub(name, float(value)) for name, value in zip((x, y, z), origin)]

        def dot(axis):
            return add(add(mul(relative[0], float(axis[0])), mul(relative[1], float(axis[1]))), mul(relative[2], float(axis[2])))

        local_x, depth, local_z = dot(across), dot(normal), dot(up)
        # The upper orbital cream merges into the cheek; no independent dark
        # strip continues beyond the eye opening into a rectangular plateau.
        q = add(square(div(add(local_x, side * .008), .157)), square(div(add(local_z, .041), .208)))
        weight = mul(sub(1., smooth_math(.91, 1.07, q)), smooth_math(-.115, -.025, depth))
        orbit = maximum(orbit, weight)
    cream = maximum(maximum(chest, chin), maximum(cheek, orbit))
    bridge = mul(sub(1., smooth_math(.024, .057, op("ABSOLUTE", x))), smooth_math(1.405, 1.535, z))
    cream = mul(cream, sub(1., bridge))
    face_light = smooth_math(1.20, 1.48, z)
    warm_throat = mul(.065, op("EXPONENT", sub(0., square(div(sub(z, 1.225), .075)))))
    ivory = [mix(mix(a, b, face_light), c, warm_throat)
             for a, b, c in zip((.74, .65, .49), (.84, .78, .65), (.85, .62, .33))]
    color = [mix(a, b, cream) for a, b in zip((.021, .035, .053), ivory)]
    ear_q = add(square(div(sub(angle, 1.48), .335)), square(div(sub(z, 1.377), .102)))
    ear = mul(sub(1., smooth_math(.87, 1.12, ear_q)), sub(1., smooth_math(.08, .84, cheek)))
    u = div(sub(angle, 1.53), .45)
    stroke_width = mul(.014, op("SQRT", maximum(0., sub(1., square(u)))))
    stroke_z = add(1.209, mul(.065, sub(angle, 1.10)))
    stripe = sub(1., smooth_math(maximum(0., sub(stroke_width, .002)), add(stroke_width, .002), op("ABSOLUTE", sub(z, stroke_z))))
    stripe = mul(stripe, sub(1., smooth_math(.90, 1., op("ABSOLUTE", u))))
    color = [mix(a, b, ear) for a, b in zip(color, (.67, .30, .047))]
    color = [mix(a, b, stripe) for a, b in zip(color, (.066, .36, .40))]
    masks = [mul(mul(cream, sub(1., ear)), sub(1., stripe)), mul(ear, sub(1., stripe)), stripe, 1.]
    return {"inputs": [x, y, z], "operations": operations,
            "outputs": {"color": [*color, 1.], "masks": masks, "hood": sub(1., cream)}}


def body_paint(point, eye_frame, eye_radii):
    # Source diagnostic attributes preserve this exact program, not old Z11
    # masks. Cache per immutable registration cohort; shader is authoritative.
    frames = {side: eye_frame(side) for side in (-1., 1.)}
    result = _paint_for_frames(tuple((side, frames[side]) for side in (-1., 1.)), tuple(eye_radii))
    values = paint_graph.evaluate_program(result, tuple(point))
    return values["color"], values["masks"]


@lru_cache(maxsize=4)
def _paint_for_frames(frames, radii):
    return full_paint_program(dict(frames), radii)


def evaluate_paint_batch(program, points):
    """Bounded vector evaluation for source attributes; same shader program."""
    import numpy as np
    points = np.asarray(points, dtype=float)
    if points.ndim != 2 or points.shape[1] != 3 or not np.all(np.isfinite(points)):
        raise ValueError("Face paint requires finite Nx3 source positions")
    values = dict(zip(program["inputs"], points.T))
    functions = {"ADD": np.add, "SUBTRACT": np.subtract, "MULTIPLY": np.multiply,
                 "DIVIDE": np.divide, "MAXIMUM": np.maximum, "MINIMUM": np.minimum,
                 "SQRT": lambda a, b: np.sqrt(a), "ABSOLUTE": lambda a, b: np.abs(a),
                 "ARCTAN2": np.arctan2, "EXPONENT": lambda a, b: np.exp(a)}
    with np.errstate(all="raise"):
        for name, kind, a, b in program["operations"]:
            if kind not in functions:
                raise ValueError("Unsupported unified face paint operation: " + kind)
            values[name] = functions[kind](values[a] if isinstance(a, str) else a,
                                           values[b] if isinstance(b, str) else b)
    output = {}
    for key in ("color", "masks"):
        output[key] = np.stack([np.broadcast_to(values[value] if isinstance(value, str) else value,
                                               (len(points),)) for value in program["outputs"][key]], axis=-1)
        if (not np.all(np.isfinite(output[key])) or np.any(output[key] < -1e-12)
                or np.any(output[key] > 1. + 1e-12)):
            raise RuntimeError("Unified face paint contains invalid channel values")
    if np.any(output["masks"][:, :3].sum(axis=1) > 1. + 1e-12):
        raise RuntimeError("Unified face semantic weights are not exclusive")
    return output


def assign_body_attributes(body, materials, eye_frame, eye_radii):
    """Author diagnostic paint/masks in bounded batches, not 696-node loops."""
    import numpy as np
    body.data.materials.clear()
    body.data.materials.append(materials["body_vertex"])
    count = len(body.data.vertices)
    positions = np.empty(count * 3, dtype=np.float64)
    body.data.vertices.foreach_get("co", positions)
    positions = positions.reshape((-1, 3))
    rgba, weights = np.empty((count, 4), dtype=np.float32), np.empty((count, 4), dtype=np.float32)
    program = full_paint_program({side: eye_frame(side) for side in (-1., 1.)}, eye_radii)
    for start in range(0, count, 8192):
        result = evaluate_paint_batch(program, positions[start:start + 8192])
        rgba[start:start + 8192], weights[start:start + 8192] = result["color"], result["masks"]
    for name, array in (("PreviewColor", rgba), ("SourceSemanticMasks", weights)):
        attribute = body.data.color_attributes.new(name=name, type="FLOAT_COLOR", domain="POINT")
        attribute.data.foreach_set("color", array.ravel())
    for polygon in body.data.polygons:
        polygon.material_index = 0
    body["source_mask_contract"] = "feather-palette-weights-v1"
    body["source_attribute_note"] = "Diagnostic samples of coherent face program; continuous shader remains exact bake authority"


def eye_pigment(theta, phi):
    radius = min(1., math.sin(theta) / math.sin(IRIS_ANGLE))
    iris = iris_paint.iris_linear_rgba(radius * math.cos(phi), radius * math.sin(phi))
    pupil = (.0018, .0032, .0050, 1.)
    limbal = (.012, .024, .035, 1.)
    sclera = (.78, .75, .66, 1.)
    pigment = tuple(a + (b - a) * smooth(PUPIL_ANGLE - .012, PUPIL_ANGLE + .012, theta)
                    for a, b in zip(pupil, iris))
    pigment = tuple(a + (b - a) * smooth(IRIS_ANGLE - .012, IRIS_ANGLE + .010, theta)
                    for a, b in zip(pigment, limbal))
    pigment = tuple(a + (b - a) * smooth(LIMBAL_ANGLE - .005, LIMBAL_ANGLE + .025, theta)
                    for a, b in zip(pigment, sclera))
    # Small original painted readability cue, never emissive or a claimed
    # reflection simulation. Real source key reflection remains in the BSDF.
    px, pz = radius * math.cos(phi), radius * math.sin(phi)
    catch_q = ((px + .23) / .070) ** 2 + ((pz - .34) / .110) ** 2
    catch = (1. - smooth(.35, 1., catch_q)) * (1. - smooth(.54, .60, theta))
    return tuple(a + (b - a) * catch for a, b in zip(pigment, (.86, .91, .96, 1.)))


def eye_surface(theta, phi, gaze, radii=EYE_RADII):
    """One continuous closed eye, shallow iris dish and inset pupil center."""
    import numpy as np
    rx, ry, rz = radii
    cx, cz = gaze
    q = max(0., 1. - (cx / rx) ** 2 - (cz / rz) ** 2)
    direction = np.asarray((cx / rx, math.sqrt(q), cz / rz))
    direction /= np.linalg.norm(direction)
    across = np.cross(direction, (0., 0., 1.))
    across /= np.linalg.norm(across)
    up = np.cross(across, direction)
    unit = direction * math.cos(theta) + (across * math.cos(phi) + up * math.sin(phi)) * math.sin(theta)
    point = unit * np.asarray(radii)
    normal = point / np.asarray(radii) ** 2
    normal /= np.linalg.norm(normal)
    recess = IRIS_RECESS * (1. - smooth(PUPIL_ANGLE, IRIS_ANGLE, theta))
    recess += PUPIL_RECESS * (1. - smooth(.10, PUPIL_ANGLE, theta))
    return tuple(point - normal * recess), recess


def add_eye_surfaces(materials, bpy, eye_frame, gaze_function, smooth_mesh):
    """No four coincident stacked eye pigment meshes; one actual eye surface."""
    import numpy as np
    material = materials["sclera"].copy()
    material.name = "JuvenileSeatedEyeSurface"
    nodes, links = material.node_tree.nodes, material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    pigment_node = nodes.new("ShaderNodeVertexColor")
    pigment_node.layer_name = "PreviewColor"
    links.new(pigment_node.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = .20
    bsdf.inputs["Specular IOR Level"].default_value = .40
    bsdf.inputs["IOR"].default_value = 1.40
    segments, rings = 96, 80
    for side in (-1., 1.):
        origin, across, normal, up = map(np.asarray, eye_frame(side))
        gaze = gaze_function(side)
        vertices, colors, faces = [], [], []

        def append(theta, phi):
            point, _ = eye_surface(theta, phi, gaze)
            x, depth, z = point
            vertices.append(tuple(origin + across * x + normal * (depth - EYE_BURIAL) + up * z))
            colors.append(eye_pigment(theta, phi))

        append(0., 0.)
        for ring in range(1, rings):
            theta = math.pi * ring / rings
            for segment in range(segments):
                append(theta, math.tau * segment / segments)
        append(math.pi, 0.)
        last = len(vertices) - 1
        for segment in range(segments):
            nxt = (segment + 1) % segments
            faces.append((0, 1 + nxt, 1 + segment))
            for ring in range(rings - 2):
                a, b = 1 + ring * segments + segment, 1 + ring * segments + nxt
                faces.append((a, b, b + segments, a + segments))
            start = 1 + (rings - 2) * segments
            faces.append((last, start + segment, start + nxt))
        mesh = bpy.data.meshes.new(f"EmbeddedSclera{side:+.0f}")
        mesh.from_pydata(vertices, [], faces)
        mesh.update(calc_edges=True)
        obj = bpy.data.objects.new(mesh.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        mesh.materials.append(material)
        pigment = mesh.color_attributes.new(name="PreviewColor", type="FLOAT_COLOR", domain="POINT")
        for index, rgba in enumerate(colors):
            pigment.data[index].color = rgba
        # Winding is recalculated on the one closed surface, not hidden by
        # double-sided lighting. Recess geometry is part of that same surface.
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(mesh)
        if any(not edge.is_manifold for edge in bm.edges):
            raise RuntimeError("Juvenile eye surface is not a closed manifold")
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(mesh)
        bm.free()
        smooth_mesh(obj)
        obj["eye_surface_contract"] = "continuous sclera/iris; 1.2mm iris dish + 0.7mm pupil recess; original painted catchlight"


def fresh_design():
    selected, parent = study.fresh_design(PARENT_PROFILE)
    original_base = selected.base_body_field
    selected.base_body_field = lambda points: support_field(points, original_base)
    selected.EYE_RADII, selected.EYE_BURY_DEPTH = EYE_RADII, EYE_BURIAL
    selected.EYE_CENTER_X = .245
    selected.EYE_ORBITAL_HEADING_FACTOR = 1.25
    selected.EYE_GAZE_HORIZONTAL_SCALE = .35
    selected.EYE_GAZE_TARGET = (0., -3.5, 2.00)
    selected.sculpt_body_field = lambda points: sculpt_face(points, selected.base_body_field, selected.eye_surface_frame)
    selected.bill_section_height, selected.bill_smile_offset = bill_height, bill_smile
    selected.BILL_UPPER_SECTIONS, selected.BILL_LOWER_SECTIONS = BILL_UPPER, BILL_LOWER
    if selected.eye_surface_frame.cache_info().currsize:
        raise RuntimeError("Unified facial support must precede eye registration")
    return selected, {"parent_design_record": parent, "support_volumes": SUPPORT,
                      "aperture_landmarks": APERTURE, "eye_surface": "single continuous inset iris/pupil surface",
                      "selected_design_constants": study.constants(selected),
                      "old_orbital_sculpt_and_separate_hood_overlay_retired": True}


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
    tree, parent = study.renderer_syntax(PARENT_PROFILE, path)
    paint = study.function_node(tree, "body_paint")
    paint.body = ast.parse("return _juvenile_paint(point, eye_surface_frame, EYE_RADII)").body
    tree.body.insert(tree.body.index(paint), ast.parse(
        "from hero_penguin_face_sculpt import body_paint as _juvenile_paint, add_eye_surfaces as _juvenile_eyes, assign_body_attributes as _juvenile_attributes").body[0])
    attributes = study.function_node(tree, "assign_body_materials")
    attributes.body = ast.parse("_juvenile_attributes(body, materials, eye_surface_frame, EYE_RADII)").body
    eyes = study.function_node(tree, "add_eye_set")
    eyes.body = ast.parse("_juvenile_eyes(materials, bpy, eye_frame, eye_gaze_center, smooth_mesh)").body
    bill = study.function_node(tree, "add_bill")
    nostril = study.assignment(bill, "nostril").value.args[1]
    if ast.dump(nostril) != ast.dump(ast.parse("(side * .047, -.448, 1.429)", mode="eval").body):
        raise ValueError("Unified face parent nostril anchor changed")
    nostril_call = ast.parse("_juvenile_nostril(side)", mode="eval").body
    study.assignment(bill, "nostril").value.args[1] = nostril_call
    tree.body.insert(tree.body.index(bill), ast.parse(
        "from hero_penguin_face_sculpt import nostril_center as _juvenile_nostril").body[0])
    ast.fix_missing_locations(tree)
    return tree, {"parent_renderer_record": parent, "selected_renderer_ast_sha256": study.ast_digest(tree),
                  "eye_registration": "single closed eye; no independent limbal/iris/pupil discs",
                  "body_paint": "unified coherent silhouette with no separate hood-strip composite"}


def nostril_center(side):
    y, width, height, seam = BILL_UPPER[2]
    x = side * .033
    cosine = x / width
    return x, y, bill_height(y, width, height, seam, cosine, math.sqrt(1. - cosine * cosine), "upper") - .0005


def apply_material_changes(materials):
    changes = []
    for name in ("bill_upper", "bill_lower"):
        bsdf = materials[name].node_tree.nodes.get("Principled BSDF")
        for control, value in (("Roughness", .45), ("Specular IOR Level", .28), ("IOR", 1.45)):
            old = bsdf.inputs[control].default_value
            bsdf.inputs[control].default_value = value
            changes.append({"material": name, "control": control, "baseline": old, "selected": value})
    return changes


def install_continuous_paint(body, material, eye_frame, radii, bpy):
    return paint_graph.install_continuous_paint(
        body, material, eye_frame, radii, bpy, program_factory=full_paint_program,
        group_name=GROUP_NAME, profile=PROFILE,
        source_description="Unified orbital/cheek mask; no old lid-hood overlay; Object-space continuous pigment/masks")


def source_only_declarations():
    return {"schema_version": 1, "study_profile": PROFILE, "parent_profile": PARENT_PROFILE,
            "source_only": True, "production_ready": False, "source_fidelity_approved": False,
            "geometry_approved": False, "candidate_export_allowed": False, "runtime_rig_or_glb_created": False,
            "export_policy": "New unregistered source design; reject candidate/atlas export until explicitly reviewed and registered.",
            "scope": "Unified face support/aperture/paint, continuous inset eyes and volumetric smiling bill; unchanged rest body/wing/foot/stage/feather recipe.",
            "approval_policy": "Actual front/three-quarter/side review, then budgeted textured shared-rig gameplay; no numeric appearance approval."}
