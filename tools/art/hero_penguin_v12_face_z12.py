"""Z12 source-only pigment sampling correction; exact Z11 sculpt retained.

Z11's 3 mm hood transition was sampled into POINT-domain vertex paint on a
14 mm marching grid (locally refined to roughly 3.5 mm, excluding the bridge).
This variant evaluates that SAME analytic hood at shading points. It changes
the paint-input graph, not geometry, BSDF response, feather maps or cameras.
Cycles source-to-atlas baking can evaluate these ordinary math nodes; no
procedural runtime shader/export approval is implied.
"""
from __future__ import annotations

import ast
import hashlib
import json
import math

import hero_penguin_v12_face_z11 as prior
import hero_penguin_v12_source_study as study

PROFILE = "continuous-hood-pigment-z12"
PARENT_PROFILE = prior.PROFILE
GROUP_NAME = "Z12_ContinuousHoodPigment_SourceOnly"
DARK = (.017, .027, .040, 1.)
apply_material_changes = prior.apply_material_changes
fresh_design = prior.fresh_design
installed_design = prior.installed_design


def vertex_underpaint(point, eye_frame, eye_radii):
    """Z10 is the exact underpaint used by Z11 before its hood composite.

    Preserve Z11 semantic weights at vertices. The saved group additionally
    exposes the continuous Hood output for any future approved mask bake;
    interpolated masks alone are NOT claimed to be per-fragment equivalents.
    """
    pigment, _ = prior.prior.body_paint(point, eye_frame)
    _, masks = prior.body_paint(point, eye_frame, eye_radii)
    return pigment, masks


def hood_program(eye_frames, eye_radii):
    """One small arithmetic program shared by host evaluation and nodes.

    Operation names are Blender Math operations. Inputs x/y/z are unmodified
    object-space shading positions. No camera/UV/image/normal dependence.
    """
    operations = []

    def op(kind, first, second=0.):
        name = f"hood_{len(operations):03d}"
        operations.append((name, kind, first, second))
        return name

    def add(a, b): return op("ADD", a, b)
    def sub(a, b): return op("SUBTRACT", a, b)
    def mul(a, b): return op("MULTIPLY", a, b)
    def div(a, b): return op("DIVIDE", a, b)
    def square(a): return mul(a, a)
    def clamp(a): return op("MINIMUM", op("MAXIMUM", a, 0.), 1.)

    def smooth(low, high, value):
        t = clamp(div(sub(value, low), high - low))
        return mul(square(t), sub(3., mul(2., t)))

    def smoother(t):
        return mul(mul(square(t), t), add(mul(t, sub(mul(t, 6.), 15.)), 10.))

    p, lid = prior.prior.prior.ORBIT, prior.LID
    if set(eye_frames) != {-1., 1.} or len(eye_radii) != 3 or not all(math.isfinite(v) and v > 0. for v in eye_radii):
        raise ValueError("Z12 requires both unchanged orbital frames and positive radii")
    hood = 0.
    for side in (-1., 1.):
        origin, across, normal, up = eye_frames[side]
        if any(not math.isfinite(v) for axis in eye_frames[side] for v in axis):
            raise ValueError("Z12 eye frame contains non-finite values")
        relative = [sub(name, float(value)) for name, value in zip(("x", "y", "z"), origin)]

        def dot(axis):
            return add(add(mul(relative[0], float(axis[0])), mul(relative[1], float(axis[1]))), mul(relative[2], float(axis[2])))

        x, depth, z = dot(across), dot(normal), dot(up)
        u = div(add(x, side * p["nasal_offset"]), p["opening_x"])
        root = op("SQRT", op("MAXIMUM", sub(1., square(u)), 0.))
        edge = add(sub(p["center_z"], mul(p["outer_corner_drop"] * side, x)), mul(p["opening_upper"], root))
        globe = mul(float(eye_radii[2]), op("SQRT", op("MAXIMUM", sub(1., square(div(x, float(eye_radii[0])))), 0.)))
        outer = op("MAXIMUM", add(edge, lid["minimum_hood_return_m"]), add(globe, lid["beyond_globe_return_m"]))
        t = div(sub(z, edge), sub(outer, edge))
        taper = clamp(div(sub(op("ABSOLUTE", x), float(eye_radii[0]) + lid["endpoint_taper_start_beyond_globe_m"]),
                          lid["endpoint_taper_end_beyond_globe_m"] - lid["endpoint_taper_start_beyond_globe_m"]))
        endpoint = sub(1., smoother(taper))
        width = lid["pigment_edge_half_width_m"]
        lip = smooth(-width, width, sub(z, edge))
        upper_return = sub(1., smooth(.80, 1., t))
        front = smooth(-.080, -.020, depth)
        hood = op("MAXIMUM", hood, mul(mul(mul(lip, endpoint), upper_return), front))
    return {"inputs": ["x", "y", "z"], "operations": operations, "output": hood}


def evaluate_program(program, point):
    """Renderer-free double-precision reference, not a GPU/Cycles parity claim."""
    if len(point) != 3 or not all(math.isfinite(v) for v in point):
        raise ValueError("Z12 requires a finite position")
    values = dict(zip(program["inputs"], point))
    functions = {"ADD": lambda a, b: a + b, "SUBTRACT": lambda a, b: a - b,
                 "MULTIPLY": lambda a, b: a * b, "DIVIDE": lambda a, b: a / b,
                 "MAXIMUM": max, "MINIMUM": min,
                 "SQRT": lambda a, b: math.sqrt(a), "ABSOLUTE": lambda a, b: abs(a)}
    for name, kind, first, second in program["operations"]:
        a = values[first] if isinstance(first, str) else first
        b = values[second] if isinstance(second, str) else second
        if kind not in functions:
            raise ValueError(f"Unsupported Z12 pigment operation: {kind}")
        values[name] = functions[kind](a, b)
    return values[program["output"]]


def composite_underpaint(pigment, hood):
    return tuple(a + (b - a) * hood for a, b in zip(pigment, DARK))


def install_continuous_paint(material, eye_frame, eye_radii, bpy_module):
    """Replace only outgoing PreviewColor links with continuous composite.

    Existing mean tint, feather detail, normal/roughness region interpolation,
    BSDF parameters and all images remain downstream and untouched. Shared
    wing consumers keep their original paint: the hood formula is zero there.
    """
    nodes, links = material.node_tree.nodes, material.node_tree.links
    sources = [node for node in nodes if node.type == "VERTEX_COLOR" and node.layer_name == "PreviewColor"]
    if len(sources) != 1 or material.get("z12_continuous_hood"):
        raise ValueError("Z12 requires exactly one unmodified PreviewColor source")
    source = sources[0].outputs["Color"]
    old_edges = list(source.links)
    if not old_edges or bpy_module.data.node_groups.get(GROUP_NAME) is not None:
        raise ValueError("Z12 source has no paint consumers or group already exists")
    image_ids = tuple(sorted(node.image.name_full for node in nodes if node.type == "TEX_IMAGE" and node.image))
    untouched_links = {(link.from_node.name, link.from_socket.identifier, link.to_node.name, link.to_socket.identifier)
                       for link in links if link.from_socket != source}
    frames = {side: eye_frame(side) for side in (-1., 1.)}
    program = hood_program(frames, tuple(eye_radii))
    group = bpy_module.data.node_groups.new(GROUP_NAME, "ShaderNodeTree")
    for name, direction, kind in (("Position", "INPUT", "NodeSocketVector"),
                                   ("Underpaint", "INPUT", "NodeSocketColor"),
                                   ("Color", "OUTPUT", "NodeSocketColor"),
                                   ("Hood", "OUTPUT", "NodeSocketFloat")):
        group.interface.new_socket(name=name, in_out=direction, socket_type=kind)
    inputs, output = group.nodes.new("NodeGroupInput"), group.nodes.new("NodeGroupOutput")
    separate = group.nodes.new("ShaderNodeSeparateXYZ")
    group.links.new(inputs.outputs["Position"], separate.inputs["Vector"])
    values = dict(zip(program["inputs"], (separate.outputs["X"], separate.outputs["Y"], separate.outputs["Z"])))
    for name, kind, first, second in program["operations"]:
        node = group.nodes.new("ShaderNodeMath")
        node.operation, node.name, node.label, node.use_clamp = kind, name, "Z11 analytic hood — " + name, False
        for index, value in enumerate((first, second)):
            if isinstance(value, str):
                group.links.new(values[value], node.inputs[index])
            else:
                node.inputs[index].default_value = float(value)
        values[name] = node.outputs[0]
    mix = group.nodes.new("ShaderNodeMixRGB")
    mix.blend_type, mix.use_clamp = "MIX", False
    mix.inputs[2].default_value = DARK
    group.links.new(values[program["output"]], mix.inputs[0])
    group.links.new(inputs.outputs["Underpaint"], mix.inputs[1])
    group.links.new(mix.outputs[0], output.inputs["Color"])
    group.links.new(values[program["output"]], output.inputs["Hood"])
    instance = nodes.new("ShaderNodeGroup")
    instance.node_tree, instance.label = group, "Z12 continuous hood pigment — source only"
    coordinates = nodes.new("ShaderNodeTexCoord")
    coordinates.label = "Unmodified object-space shading position; not Generated/UV"
    links.new(coordinates.outputs["Object"], instance.inputs["Position"])
    links.new(source, instance.inputs["Underpaint"])
    consumers = []
    for link in old_edges:
        destination = link.to_socket
        consumers.append((link.to_node.name, destination.identifier))
        links.remove(link)
        links.new(instance.outputs["Color"], destination)
    after_links = {(link.from_node.name, link.from_socket.identifier, link.to_node.name, link.to_socket.identifier) for link in links}
    if not untouched_links.issubset(after_links):
        raise RuntimeError("Z12 unexpectedly changed a non-paint material connection")
    if tuple(sorted(node.image.name_full for node in nodes if node.type == "TEX_IMAGE" and node.image)) != image_ids:
        raise RuntimeError("Z12 altered the existing feather image set")
    material["z12_continuous_hood"] = PROFILE
    return {"paint_input_graph_changed": True, "material_response_recipe_preserved": True,
            "geometry_changed": False, "program_sha256": hashlib.sha256(json.dumps(program, sort_keys=True).encode()).hexdigest(),
            "math_node_count": len(program["operations"]), "eye_frames": frames, "eye_radii": tuple(eye_radii),
            "source": "Object shading position + Z10 PreviewColor underpaint -> exact Z11 hood formula",
            "replaced_paint_consumers": consumers, "unchanged_image_names": image_ids,
            "semantic_masks": "Z11 vertex weights preserved; continuous Hood output must be used for a future exact mask bake",
            "runtime_procedural_shader_added": False, "visual_approval": False}


def renderer_syntax(path):
    tree, parent_record = prior.renderer_syntax(path)
    assign = study.function_node(tree, "assign_body_materials")
    anchors = [node for node in ast.walk(assign) if isinstance(node, ast.Assign)
               and ast.dump(node, include_attributes=False) == ast.dump(ast.parse("pigment, mask = body_paint(vertex.co)").body[0], include_attributes=False)]
    if len(anchors) != 1:
        raise ValueError("Z12 body pigment assignment anchor changed or duplicated")
    anchors[0].value = ast.parse("_z12_vertex_underpaint(vertex.co, eye_surface_frame, EYE_RADII)", mode="eval").body
    tree.body.insert(tree.body.index(assign), ast.parse("from hero_penguin_v12_face_z12 import vertex_underpaint as _z12_vertex_underpaint").body[0])
    ast.fix_missing_locations(tree)
    return tree, {"parent_renderer_record": parent_record,
                  "z12_only_renderer_change": "assign_body_materials: exact Z10 pre-hood pigment; original Z11 semantic weights",
                  "selected_renderer_ast_sha256": study.ast_digest(tree)}


def source_only_declarations():
    return {"schema_version": 1, "study_profile": PROFILE, "parent_profile": PARENT_PROFILE,
            "source_only": True, "production_ready": False, "source_fidelity_approved": False,
            "geometry_approved": False, "candidate_export_allowed": False, "runtime_rig_or_glb_created": False,
            "export_policy": "Unregistered source-only study; reject candidate/atlas export until separately reviewed.",
            "scope": "Per-shading-point Z11 hood pigment; unchanged sculpt, eyes, bill, masks, material response, maps, stage and cameras.",
            "paint_input_graph_changed": True, "entire_material_graph_unchanged": False,
            "z11_geometry_functions_and_constants_preserved": True,
            "approval_policy": "Actual three-view inspection required; numeric equivalence never grants art approval."}
