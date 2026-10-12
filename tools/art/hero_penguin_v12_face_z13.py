"""Z13: complete continuous body pigment; exact Z12 sculpture retained.

Z12 ray audit found surviving vertex-underpaint errors at body pixels141,154
and133,158, where the hood was zero. ALL Z10 paint plus Z11 hood now evaluates
per shading point. Body-only material copy preserves original wing paint.
Cycles math nodes are bakeable; no runtime procedural shader/art approval.
"""
from __future__ import annotations

import hashlib
import json
import math

import hero_penguin_v12_face_z12 as prior

PROFILE = "continuous-full-body-pigment-z13"
PARENT_PROFILE = prior.PROFILE
GROUP_NAME = "Z13_ContinuousBodyPigment_SourceOnly"
apply_material_changes = prior.apply_material_changes
fresh_design = prior.fresh_design
installed_design = prior.installed_design
renderer_syntax = prior.renderer_syntax


def full_paint_program(eye_frames, eye_radii):
    """Exact Z10 formula + Z11 hood. Position-only inputs, separate color/masks."""
    hood_program = prior.hood_program(eye_frames, eye_radii)
    operations = list(hood_program["operations"])
    hood = hood_program["output"]

    def op(kind, first, second=0.):
        name = f"paint_{len(operations):03d}"
        operations.append((name, kind, first, second))
        return name

    def add(a, b): return op("ADD", a, b)
    def sub(a, b): return op("SUBTRACT", a, b)
    def mul(a, b): return op("MULTIPLY", a, b)
    def div(a, b): return op("DIVIDE", a, b)
    def square(a): return mul(a, a)
    def absolute(a): return op("ABSOLUTE", a)
    def maximum(a, b): return op("MAXIMUM", a, b)
    def clamp(a): return op("MINIMUM", maximum(a, 0.), 1.)
    def mix(a, b, weight): return add(a, mul(sub(b, a), weight))

    def smooth(low, high, value):
        # low/high are shader values for the cyan stroke's varying width.
        t = clamp(div(sub(value, low), sub(high, low)))
        return mul(square(t), sub(3., mul(2., t)))

    x, y, z = "x", "y", "z"
    angle = absolute(op("ARCTAN2", x, sub(0., y)))
    cheek_center = add(1.333, mul(.018, op("COSINE", mul(angle, .9))))
    cheek_q = add(square(div(sub(angle, .63), 1.04)), square(div(sub(z, cheek_center), .172)))
    cheek = sub(1., smooth(.88, 1.12, cheek_q))
    chin = sub(1., smooth(.88, 1.12, add(square(div(angle, .85)), square(div(sub(z, 1.210), .190)))))
    orbit, lash = 0., 0.
    orbit_parameters = prior.prior.prior.prior.ORBIT
    for side in (-1., 1.):
        origin, across, normal, up = eye_frames[side]
        relative = [sub(name, float(value)) for name, value in zip((x, y, z), origin)]

        def dot(axis):
            return add(add(mul(relative[0], float(axis[0])), mul(relative[1], float(axis[1]))), mul(relative[2], float(axis[2])))

        local_x, depth, local_z = dot(across), dot(normal), dot(up)
        gate = smooth(-.075, -.015, depth)
        lower_flow = smooth(.015, .120, sub(0., local_z))
        width = add(.133, mul(.038, lower_flow))
        q = add(square(div(local_x, width)), square(div(add(local_z, .022), .150)))
        old_hood = smooth(.102, .137, add(local_z, mul(.025, square(div(local_x, .130)))))
        orbit = maximum(orbit, mul(mul(sub(1., smooth(.88, 1.12, q)), gate), sub(1., old_hood)))
        p = orbit_parameters
        vertical = add(sub(local_z, p["center_z"]), mul(p["outer_corner_drop"] * side, local_x))
        radius_z = mix(p["opening_upper"], p["opening_lower"], op("LESS_THAN", vertical, 0.))
        edge_q = add(square(div(add(local_x, side * p["nasal_offset"]), p["opening_x"])), square(div(vertical, radius_z)))
        edge = mul(sub(op("SQRT", edge_q), 1.), p["opening_distance_scale"])
        upper_line = mul(.75, smooth(.025, .050, local_z))
        lower_line = mul(mul(.10, sub(1., smooth(-.070, -.035, local_z))), sub(1., smooth(.060, .090, absolute(local_x))))
        line = op("EXPONENT", sub(0., square(div(sub(edge, .0015), .003))))
        lash = maximum(lash, mul(mul(line, gate), add(upper_line, lower_line)))

    chest_width = sub(.475, mul(.160, smooth(.880, 1.270, z)))
    chest_q = add(square(div(x, chest_width)), square(div(sub(z, .710), .725)))
    front = div(sub(0., y), maximum(.001, op("SQRT", add(square(x), square(y)))))
    chest = mul(sub(1., smooth(.90, 1.12, chest_q)), smooth(.05, .25, front))
    cream = maximum(maximum(maximum(cheek, chin), chest), orbit)
    bridge = mul(sub(1., smooth(.034, .066, absolute(x))), smooth(1.384, 1.454, z))
    cream = mul(cream, sub(1., bridge))
    face_light = smooth(1.25, 1.43, z)
    throat = mul(.12, op("EXPONENT", sub(0., square(div(sub(z, 1.205), .065)))))
    ivory = [mix(mix(low, high, face_light), warm, throat)
             for low, high, warm in zip((.73, .62, .445), (.82, .75, .595), (.84, .56, .255))]
    pigment = [mix(dark, light, cream) for dark, light in zip(prior.DARK[:3], ivory)]
    pigment = [mix(channel, line, lash) for channel, line in zip(pigment, (.022, .032, .040))]
    ear_q = add(square(div(sub(angle, 1.45), .31)), square(div(sub(z, 1.360), .115)))
    ear = mul(sub(1., smooth(.80, 1.18, ear_q)), sub(1., smooth(.12, .90, cheek)))
    stroke_u = div(sub(angle, 1.52), .45)
    stroke_width = mul(.015, op("SQRT", maximum(0., sub(1., square(stroke_u)))))
    stripe_z = add(add(1.188, mul(.040, sub(angle, 1.10))), mul(.017, op("SINE", mul(sub(angle, 1.10), 3.3))))
    stripe = sub(1., smooth(maximum(0., sub(stroke_width, .003)), add(stroke_width, .002), absolute(sub(z, stripe_z))))
    stripe = mul(stripe, sub(1., smooth(.91, 1., absolute(stroke_u))))
    pigment = [mix(channel, gold, ear) for channel, gold in zip(pigment, (.63, .270, .037))]
    pigment = [mix(channel, cyan, stripe) for channel, cyan in zip(pigment, (.065, .34, .38))]
    pigment = [mix(channel, dark, hood) for channel, dark in zip(pigment, prior.DARK[:3])]
    masks = [mul(mul(mul(cream, sub(1., ear)), sub(1., stripe)), sub(1., hood)),
             mul(mul(ear, sub(1., stripe)), sub(1., hood)), mul(stripe, sub(1., hood)), 1.]
    return {"inputs": ["x", "y", "z"], "operations": operations,
            "outputs": {"color": [*pigment, 1.], "masks": masks, "hood": hood}}


def evaluate_program(program, point):
    """Float64 math reference, not a Cycles/pixel acceptance assertion."""
    if len(point) != 3 or not all(math.isfinite(v) for v in point):
        raise ValueError("Z13 requires a finite position")
    values = dict(zip(program["inputs"], point))
    functions = {"ADD": lambda a, b: a + b, "SUBTRACT": lambda a, b: a - b,
                 "MULTIPLY": lambda a, b: a * b, "DIVIDE": lambda a, b: a / b,
                 "MAXIMUM": max, "MINIMUM": min, "SQRT": lambda a, b: math.sqrt(a),
                 "ABSOLUTE": lambda a, b: abs(a), "ARCTAN2": math.atan2,
                 "COSINE": lambda a, b: math.cos(a), "SINE": lambda a, b: math.sin(a),
                 "EXPONENT": lambda a, b: math.exp(a), "LESS_THAN": lambda a, b: float(a < b)}
    for name, kind, first, second in program["operations"]:
        if kind not in functions:
            raise ValueError(f"Unsupported Z13 pigment operation: {kind}")
        values[name] = functions[kind](values[first] if isinstance(first, str) else first,
                                      values[second] if isinstance(second, str) else second)

    def resolve(value):
        if isinstance(value, (list, tuple)):
            return tuple(resolve(item) for item in value)
        return values[value] if isinstance(value, str) else value
    return {name: resolve(value) for name, value in program["outputs"].items()}


def install_continuous_paint(body, original_material, eye_frame, eye_radii, bpy_module,
                             *, program_factory=full_paint_program,
                             group_name=GROUP_NAME, profile=PROFILE,
                             source_description="Object shading position -> full Z10 body pigment/semantic weights -> Z11 hood composite"):
    """Body-only material copy; same downstream response/shared image instances."""
    if body.type != "MESH" or len(body.data.materials) != 1 or body.data.materials[0] != original_material:
        raise ValueError("Z13 requires the one original body material slot")
    if original_material.get("z12_continuous_hood") or bpy_module.data.node_groups.get(group_name):
        raise ValueError("Z13 requires untouched base material graph and a fresh group")
    frames = {side: eye_frame(side) for side in (-1., 1.)}
    program = program_factory(frames, tuple(eye_radii))
    material = original_material.copy()
    material.name = group_name + "_FeatherMaterial"
    nodes, links = material.node_tree.nodes, material.node_tree.links
    sources = [node for node in nodes if node.type == "VERTEX_COLOR" and node.layer_name == "PreviewColor"]
    if len(sources) != 1:
        raise ValueError("Z13 requires exactly one original PreviewColor source")
    source = sources[0].outputs["Color"]
    old_edges = list(source.links)
    if not old_edges:
        raise ValueError("Z13 source material has no pigment consumers")
    images_before = {node.name: node.image for node in original_material.node_tree.nodes if node.type == "TEX_IMAGE"}
    untouched = {(link.from_node.name, link.from_socket.identifier, link.to_node.name, link.to_socket.identifier)
                 for link in links if link.from_socket != source}
    group = bpy_module.data.node_groups.new(group_name, "ShaderNodeTree")
    for name, direction, kind in (("Position", "INPUT", "NodeSocketVector"),
                                   ("Color", "OUTPUT", "NodeSocketColor"),
                                   ("SemanticMasks", "OUTPUT", "NodeSocketColor"),
                                   ("FeatherRegion", "OUTPUT", "NodeSocketFloat"),
                                   ("Hood", "OUTPUT", "NodeSocketFloat")):
        group.interface.new_socket(name=name, in_out=direction, socket_type=kind)
    inputs, output = group.nodes.new("NodeGroupInput"), group.nodes.new("NodeGroupOutput")
    separate = group.nodes.new("ShaderNodeSeparateXYZ")
    group.links.new(inputs.outputs["Position"], separate.inputs["Vector"])
    values = dict(zip(program["inputs"], (separate.outputs["X"], separate.outputs["Y"], separate.outputs["Z"])))
    for name, kind, first, second in program["operations"]:
        node = group.nodes.new("ShaderNodeMath")
        node.operation, node.name, node.label, node.use_clamp = kind, name, "Continuous body paint — " + name, False
        for index, value in enumerate((first, second)):
            if isinstance(value, str):
                group.links.new(values[value], node.inputs[index])
            else:
                node.inputs[index].default_value = float(value)
        values[name] = node.outputs[0]
    for key, destination in (("color", "Color"), ("masks", "SemanticMasks")):
        combine = group.nodes.new("ShaderNodeCombineColor")
        combine.mode, combine.label = "RGB", destination + " (alpha is 1: feather body)"
        for channel, value in zip(("Red", "Green", "Blue"), program["outputs"][key][:3]):
            group.links.new(values[value], combine.inputs[channel])
        group.links.new(combine.outputs["Color"], output.inputs[destination])
    output.inputs["FeatherRegion"].default_value = 1.
    group.links.new(values[program["outputs"]["hood"]], output.inputs["Hood"])
    instance = nodes.new("ShaderNodeGroup")
    instance.node_tree, instance.label = group, profile + " — source only"
    coordinates = nodes.new("ShaderNodeTexCoord")
    coordinates.label = "Unmodified object-space shading position; not vertex paint/UV"
    links.new(coordinates.outputs["Object"], instance.inputs["Position"])
    consumers = []
    for link in old_edges:
        destination = link.to_socket
        consumers.append((link.to_node.name, destination.identifier))
        links.remove(link)
        links.new(instance.outputs["Color"], destination)
    after = {(link.from_node.name, link.from_socket.identifier, link.to_node.name, link.to_socket.identifier) for link in links}
    if not untouched.issubset(after) or source.links:
        raise RuntimeError("Z13 changed a non-paint link or retained body vertex-color dependency")
    for name, image in images_before.items():
        if nodes.get(name) is None or nodes[name].image != image:
            raise RuntimeError("Z13 did not retain the original shared image instance")
    body.data.materials[0] = material
    body["source_pigment_authority"] = group_name + ": Color and SemanticMasks shading outputs"
    body["source_vertex_paint_note"] = "Preserved diagnostic attributes; not authoritative per-shading-point color/masks"
    material["z13_continuous_body_pigment"] = profile
    group["semantic_mask_contract"] = "R=ventral,G=gold,B=identity-cyan,A=feather(1); exclusive exact analytic compositing weights"
    return {"paint_input_graph_changed": True, "body_material_copy_added": True,
            "original_material": original_material.name_full, "body_material": material.name_full,
            "wing_material_and_paint_unchanged": True, "material_response_recipe_preserved": True,
            "geometry_changed": False, "program_sha256": hashlib.sha256(json.dumps(program, sort_keys=True).encode()).hexdigest(),
            "math_node_count": len(program["operations"]), "eye_frames": frames, "eye_radii": tuple(eye_radii),
            "source": source_description,
            "body_vertex_color_dependency": False, "replaced_paint_consumers": consumers,
            "unchanged_shared_image_names": [image.name_full for image in images_before.values() if image],
            "semantic_masks": "Continuous SemanticMasks RGBA; FeatherRegion explicitly1; diagnostic vertex attributes are not an exact future mask bake",
            "runtime_procedural_shader_added": False, "visual_approval": False}


def source_only_declarations():
    return {"schema_version": 1, "study_profile": PROFILE, "parent_profile": PARENT_PROFILE,
            "source_only": True, "production_ready": False, "source_fidelity_approved": False,
            "geometry_approved": False, "candidate_export_allowed": False, "runtime_rig_or_glb_created": False,
            "export_policy": "Unregistered source-only study; reject candidate/atlas export until separately reviewed.",
            "scope": "Full continuous body pigment/masks, body-only material copy; unchanged Z12 sculpture, eyes, bill, response/maps and stage.",
            "paint_input_graph_changed": True, "entire_material_graph_unchanged": False,
            "z12_geometry_functions_and_constants_preserved": True,
            "approval_policy": "Actual three-view inspection required; numeric parity is not appearance approval."}
