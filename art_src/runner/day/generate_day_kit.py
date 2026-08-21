#!/usr/bin/env python3
"""Build project-original runner DAY kit in Blender 5.2.0.

Invoked by tools/art/build_runner_day_kit.py. No external Python packages.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


EXPECTED_VERSION = (5, 2, 0)
PACKED_TEXTURES: dict[str, bpy.types.Image] = {}

# Palette is intentionally compact. One material + COLOR_0 per asset keeps
# Compatibility draw cost bounded while preserving authored value hierarchy.
# Values are authored for the bright DAY rig. Navy is reserved for recesses;
# primary hulls and obstacle frames live in the mid-value steel family so
# atlas modulation plus real shadow cannot crush whole silhouettes to black.
NAVY = (0.120, 0.275, 0.390, 1.0)
NAVY_2 = (0.390, 0.580, 0.650, 1.0)
STEEL = (0.500, 0.675, 0.735, 1.0)
STEEL_HI = (0.745, 0.855, 0.865, 1.0)
ICE = (0.865, 0.930, 0.925, 1.0)
SNOW = (0.965, 0.987, 0.972, 1.0)
GLASS = (0.105, 0.275, 0.350, 1.0)
ORANGE = (0.960, 0.255, 0.035, 1.0)
ORANGE_HI = (1.000, 0.420, 0.055, 1.0)
CYAN = (0.020, 0.880, 1.000, 1.0)
GREEN = (0.040, 0.960, 0.220, 1.0)
GOLD = (1.000, 0.820, 0.200, 1.0)
RUBBER = (0.090, 0.145, 0.205, 1.0)
# Working surfaces sit below snow value. Warm gray in red channel keeps this
# from becoming another blue-white ice corridor; cyan remains in green/blue.
DECK = (0.610, 0.735, 0.735, 1.0)
FROST = (0.805, 0.855, 0.825, 1.0)
# Lit interiors/lamp lenses. Warm but less saturated than semantic hazard
# orange, so a window can sell occupation without becoming a dodge cue.
WARM_WINDOW = (1.000, 0.610, 0.220, 1.0)


def parse_args() -> argparse.Namespace:
    raw = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--texture-root", required=True)
    return parser.parse_args(raw)


def reset(texture_root: Path) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.fps = 60
    scene.frame_start = 1
    scene.frame_end = 1
    world = bpy.data.worlds.new("runner_day_authoring_world")
    world.color = (0.05, 0.08, 0.12)
    scene.world = world
    scene["waddle_wars_toolchain"] = "Blender 5.2.0 LTS"
    scene["waddle_wars_forward"] = "-Z"
    scene["waddle_wars_units"] = "metres"
    for role, filename in {
        "albedo": "runner_day_surface_albedo_v1.png",
        "normal": "runner_day_surface_normal_v1.png",
        "orm": "runner_day_surface_orm_v1.png",
    }.items():
        path = texture_root / filename
        if not path.is_file():
            raise RuntimeError(f"missing generated texture {path}")
        image = bpy.data.images.load(str(path), check_existing=False)
        image.name = f"runner_day_surface_{role}_v1"
        image.colorspace_settings.name = "sRGB" if role == "albedo" else "Non-Color"
        image.pack()
        image.use_fake_user = True
        PACKED_TEXTURES[role] = image


def material() -> bpy.types.Material:
    existing = bpy.data.materials.get("day_kit_vertex_paint")
    if existing is not None:
        return existing
    mat = bpy.data.materials.new("day_kit_vertex_paint")
    mat.use_nodes = True
    mat.diffuse_color = (1.0, 1.0, 1.0, 1.0)
    mat.roughness = 0.68
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    colour = nodes.new("ShaderNodeVertexColor")
    colour.layer_name = "Color"
    albedo = nodes.new("ShaderNodeTexImage")
    albedo.image = PACKED_TEXTURES["albedo"]
    albedo.interpolation = "Linear"
    normal_tex = nodes.new("ShaderNodeTexImage")
    normal_tex.image = PACKED_TEXTURES["normal"]
    normal_tex.interpolation = "Linear"
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = 0.72
    orm = nodes.new("ShaderNodeTexImage")
    orm.image = PACKED_TEXTURES["orm"]
    orm.interpolation = "Linear"
    channels = nodes.new("ShaderNodeSeparateColor")
    multiply = nodes.new("ShaderNodeMixRGB")
    multiply.blend_type = "MULTIPLY"
    multiply.inputs[0].default_value = 1.0
    shader.inputs["Specular IOR Level"].default_value = 0.32
    links.new(albedo.outputs["Color"], multiply.inputs[1])
    links.new(colour.outputs["Color"], multiply.inputs[2])
    links.new(multiply.outputs["Color"], shader.inputs["Base Color"])
    links.new(normal_tex.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], shader.inputs["Normal"])
    links.new(orm.outputs["Color"], channels.inputs["Color"])
    links.new(channels.outputs["Green"], shader.inputs["Roughness"])
    links.new(channels.outputs["Blue"], shader.inputs["Metallic"])
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return mat


def collection(name: str) -> bpy.types.Collection:
    coll = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(coll)
    return coll


def move_to_collection(obj: bpy.types.Object, coll: bpy.types.Collection) -> None:
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    coll.objects.link(obj)


def paint(obj: bpy.types.Object, base: tuple[float, float, float, float], variation: float = 0.0) -> None:
    mesh = obj.data
    old = mesh.color_attributes.get("Color")
    if old is not None:
        mesh.color_attributes.remove(old)
    attr = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
    mesh.color_attributes.active_color = attr
    # Broad face response stands in for baked AO/curvature: undersides remain
    # dark, upward planes catch snow light, side planes keep saturated paint.
    for polygon in mesh.polygons:
        normal = polygon.normal
        light = 0.90 + max(normal.z, 0.0) * 0.10 + max(-normal.y, 0.0) * 0.025
        if normal.z < -0.25:
            # Real DAY lighting already supplies the contact shadow. Crushing
            # every underside here doubled that shadow and turned pale portals
            # into navy silhouettes in chase view.
            light *= 0.94
        for loop_index in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index]
            grain = math.sin(vertex.co.x * 3.17 + vertex.co.y * 2.31 + vertex.co.z * 4.09) * variation
            shade = max(0.76, min(1.06, light + grain))
            attr.data[loop_index].color = (
                min(base[0] * shade, 1.0),
                min(base[1] * shade, 1.0),
                min(base[2] * shade, 1.0),
                base[3],
            )
    if len(mesh.materials) == 0:
        mesh.materials.append(material())


def apply_transform(obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False)


def box(coll: bpy.types.Collection, name: str, center, size, colour, bevel=0.04, segments=2) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = Vector(size) * 0.5
    apply_transform(obj)
    if bevel > 0.0:
        mod = obj.modifiers.new("soft_field_edges", "BEVEL")
        mod.width = min(bevel, min(size) * 0.24)
        mod.segments = segments
        mod.affect = "EDGES"
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.select_set(False)
    paint(obj, colour, 0.018)
    move_to_collection(obj, coll)
    return obj


def cylinder(coll: bpy.types.Collection, name: str, center, radius, depth, colour,
             vertices=12, rotation=(0.0, 0.0, 0.0), bevel=0.025) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth,
                                       location=center, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    apply_transform(obj)
    if bevel > 0.0:
        mod = obj.modifiers.new("rolled_edges", "BEVEL")
        mod.width = min(bevel, radius * 0.22, depth * 0.12)
        mod.segments = 2
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.select_set(False)
    paint(obj, colour, 0.012)
    move_to_collection(obj, coll)
    return obj


def sphere(coll: bpy.types.Collection, name: str, center, radius, colour,
           segments=12, rings=6, scale=(1.0, 1.0, 1.0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    apply_transform(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    paint(obj, colour, 0.015)
    move_to_collection(obj, coll)
    return obj


def torus(coll: bpy.types.Collection, name: str, center, major, minor, colour,
          major_segments=16, minor_segments=6, rotation=(0.0, 0.0, 0.0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                    major_segments=major_segments, minor_segments=minor_segments,
                                    location=center, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    apply_transform(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    paint(obj, colour, 0.01)
    move_to_collection(obj, coll)
    return obj


def beam(coll: bpy.types.Collection, name: str, start, end, width, colour, bevel=0.025) -> bpy.types.Object:
    start_v = Vector(start)
    end_v = Vector(end)
    direction = end_v - start_v
    length = direction.length
    obj = box(coll, name, (0.0, 0.0, 0.0), (width, width, length), colour, bevel, 1)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized())
    obj.location = (start_v + end_v) * 0.5
    apply_transform(obj)
    # Repaint after rotation; baked face response must use final normals.
    paint(obj, colour, 0.015)
    return obj


def custom_mesh(coll: bpy.types.Collection, name: str, vertices, faces, colours) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    coll.objects.link(obj)
    attr = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
    mesh.color_attributes.active_color = attr
    for polygon, colour in zip(mesh.polygons, colours):
        for loop_index in polygon.loop_indices:
            attr.data[loop_index].color = colour
    mesh.materials.append(material())
    return obj


def flat_patch(coll: bpy.types.Collection, name: str, center, size, colour,
               phase: int = 0) -> bpy.types.Object:
    """Low irregular plate/frost patch; broad silhouette survives mipmaps."""
    cx, cy, cz = center
    sx, sy = size
    ring = [(-0.50, -0.18), (-0.31, -0.50), (0.17, -0.46),
            (0.50, -0.12), (0.39, 0.42), (-0.08, 0.50), (-0.48, 0.27)]
    ring = ring[phase % len(ring):] + ring[:phase % len(ring)]
    vertices = [(cx, cy, cz)] + [
        (cx + x * sx, cy + y * sy, cz) for x, y in ring]
    faces = [(0, index + 1, (index + 1) % len(ring) + 1)
             for index in range(len(ring))]
    return custom_mesh(coll, name, vertices, faces, [colour] * len(faces))


def faceted_ice(coll: bpy.types.Collection, name: str, center, scale,
                rotation=(0.0, 0.0, 0.0)) -> bpy.types.Object:
    """Fractured rounded iceberg mass with snow-facing and blue cut planes."""
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=2, radius=1.0, location=center, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    apply_transform(obj)
    mesh = obj.data
    attr = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
    mesh.color_attributes.active_color = attr
    for polygon in mesh.polygons:
        centre = polygon.center
        if polygon.normal.z > 0.36:
            base = SNOW
        elif polygon.normal.y < -0.38 or polygon.normal.x > 0.48:
            base = STEEL_HI
        else:
            base = ICE if (polygon.index + len(name)) % 3 else STEEL
        # Pre-fade this skyline family into the muted atmospheric value band;
        # fog then supplies depth instead of leaving white cut-outs on blue sky.
        fracture = 0.82 + 0.06 * math.sin(
            centre.x * 1.71 + centre.y * 2.13 + centre.z * 2.69)
        for loop_index in polygon.loop_indices:
            attr.data[loop_index].color = (
                min(base[0] * fracture, 1.0),
                min(base[1] * fracture, 1.0),
                min(base[2] * fracture, 1.0),
                1.0,
            )
    mesh.materials.append(material())
    move_to_collection(obj, coll)
    return obj


def wedge(coll: bpy.types.Collection, name: str, width: float, depth: float, height: float, colour) -> bpy.types.Object:
    x = width * 0.5
    y = depth * 0.5
    verts = [(-x, y, 0), (x, y, 0), (-x, -y, 0), (x, -y, 0),
             (-x, -y, height), (x, -y, height)]
    faces = [(0, 1, 3, 2), (0, 4, 5, 1), (0, 2, 4), (1, 5, 3), (2, 3, 5, 4)]
    return custom_mesh(coll, name, verts, faces, [RUBBER, colour, NAVY, NAVY, colour])


def arch_shell(coll: bpy.types.Collection, name: str, width=11.4, depth=6.0, height=5.3,
               thickness=0.34, segments=16) -> bpy.types.Object:
    verts = []
    faces = []
    colours = []
    half = width * 0.5
    spring = 2.05
    radii = [half, half + thickness]
    for y in (depth * 0.5, -depth * 0.5):
        for radius in radii:
            for i in range(segments + 1):
                angle = math.pi * i / segments
                verts.append((math.cos(angle) * radius, y, spring + math.sin(angle) * (height - spring)))
    ring = segments + 1
    front_inner = 0
    front_outer = ring
    back_inner = ring * 2
    back_outer = ring * 3
    for i in range(segments):
        # One face per physical side. Earlier source emitted every longitudinal
        # quad twice with opposite winding to fake two-sided rendering. Besides
        # z-fighting, that forced tunnel onto a unique cull-disabled pipeline.
        # Inner winding points into the vault; outer winding points away.
        faces.append((front_inner + i, back_inner + i,
                      back_inner + i + 1, front_inner + i + 1))
        colours.append(ICE)
        faces.append((front_outer + i, front_outer + i + 1,
                      back_outer + i + 1, back_outer + i))
        colours.append(STEEL)
        # Annular entrance/exit caps each face away from shell volume.
        faces.append((front_inner + i, front_inner + i + 1,
                      front_outer + i + 1, front_outer + i))
        colours.append(STEEL_HI)
        faces.append((back_inner + i, back_outer + i,
                      back_outer + i + 1, back_inner + i + 1))
        colours.append(NAVY_2)
    return custom_mesh(coll, name, verts, faces, colours)


def build_deck_variant(name: str, variant: int) -> bpy.types.Collection:
    """Six-metre expedition deck cassette with real panel relief.

    Three meshes share dimensions/pivot but not panel topology. Runtime can
    alternate them without moving gameplay floor or edge colliders.
    """
    c = collection(name)
    box(c, "deck_undertray", (0, 0, 0.075), (10.8, 6.0, 0.15), DECK, 0.055, 1)
    # Each topology uses a different panel rhythm. V5 merely shifted one
    # uniform 3x2 grid, which still read as stamped tiles across 360 m. These
    # six- and eight-panel arrangements keep gameplay lanes flat/clean while
    # changing the macro seam cadence every six metres.
    lane_centres = (-3.52, 0.0, 3.52)
    panel_widths = (
        (3.26, 3.34, 3.22),
        (3.18, 3.38, 3.16),
        (3.30, 3.26, 3.12),
    )[variant]
    layouts = (
        (
            ((-1.48, 2.72), (1.48, 2.72)),
            ((-1.48, 2.72), (1.48, 2.72)),
            ((-1.48, 2.72), (1.48, 2.72)),
        ),
        (
            ((-1.94, 1.72), (-0.03, 1.70), (1.93, 1.66)),
            ((-1.46, 2.76), (1.52, 2.58)),
            ((-1.84, 1.92), (0.22, 1.74), (2.02, 1.40)),
        ),
        (
            ((-1.58, 2.78), (1.61, 2.54)),
            ((0.02, 5.50),),
            ((-2.08, 1.42), (-0.33, 1.66), (1.72, 2.04)),
        ),
    )[variant]
    for lane, x in enumerate(lane_centres):
        for row, (y, depth) in enumerate(layouts[lane]):
            # Warm-gray/cyan working paint owns most surface area. Frost is a
            # broad tracked deposit, never default base; even direct sun keeps
            # panel seams and wear visible instead of clipping to pure white.
            tone = DECK if (lane + row + variant) % 3 else FROST
            box(c, f"lane_panel_{lane}_{row}", (x, y, 0.185),
                (panel_widths[lane], depth, 0.12), tone, 0.075, 1)
            # Broad cool repair plates interrupt only some bays. Different
            # sizes/offsets prevent another smaller stamp from replacing grid.
            if (lane * 3 + row + variant) % 4 == 0:
                patch_width = 0.92 + 0.17 * ((lane + variant) % 3)
                patch_depth = 0.64 + 0.20 * ((row + variant) % 2)
                flat_patch(c, f"wear_patch_{lane}_{row}",
                    (x + (-0.38 if (row + lane) % 2 == 0 else 0.34),
                     y + depth * 0.08, 0.253),
                    (patch_width, patch_depth),
                    FROST if variant != 2 else STEEL, lane + row + variant)
    # Translucent-looking blue-ice repairs remain value-only scenery: no green,
    # orange or gameplay-chevron silhouette. Their irregular perimeter and
    # differing angle are large enough to survive the chase mip.
    ice_patches = (
        ((-2.0, 0.70, 1.55, 0.72), (2.35, -1.84, 1.18, 0.58)),
        ((-2.62, 1.38, 1.28, 0.64), (1.25, -0.92, 1.72, 0.78)),
        ((-1.10, -1.88, 1.46, 0.62), (2.46, 1.42, 1.05, 0.82)),
    )[variant]
    for index, (x, y, width, depth) in enumerate(ice_patches):
        flat_patch(c, f"frost_track_{index}", (x, y, 0.255), (width, depth),
                   FROST if index == 0 else STEEL, variant * 2 + index)
    for side in (-1, 1):
        # Canonical corridor wall occupies x=5.40..5.95. Centering kerb here
        # preserves full 10.8 m play strip and gives sensor sleds real support;
        # previous x=5.125 pushed wall into deck and left props over drop.
        x = side * 5.675
        # Pale rounded kerbs now own this silhouette. Navy is confined to the
        # narrow service recess; no second procedural black wall sits on top.
        box(c, f"kerb_body_{side}", (x, 0, 0.72), (0.55, 6.0, 1.44),
            FROST, 0.11, 2)
        box(c, f"kerb_recess_{side}", (x - side * 0.285, 0, 0.62),
            (0.055, 4.92, 0.46), ORANGE, 0.0, 1)
        box(c, f"kerb_cap_{side}", (x, 0, 1.48), (0.70, 6.0, 0.14),
            SNOW, 0.065, 1)
        # Cliff-edge safety trim: only orange authored into deck family.
        for bay, y in enumerate((-2.30, -0.72, 0.86, 2.38)):
            colour = ORANGE_HI if (bay + variant) % 2 == 0 else GOLD
            box(c, f"edge_warning_{side}_{bay}", (side * 5.68, y, 1.558),
                (0.42, 0.64, 0.025), colour, 0.0, 1)
        # Irregular snow pillows break ruler-straight caps and create a soft
        # material transition before the hard equipment silhouettes.
        snow_y = (
            (-2.18, 0.24, 2.10),
            (-2.34, -0.62, 1.44, 2.46),
            (-1.84, 0.68, 2.30),
        )[variant]
        for bank, y in enumerate(snow_y):
            sphere(c, f"snow_bank_{side}_{bank}",
                (side * (5.65 + 0.03 * ((bank + variant) % 2)), y, 1.50),
                0.44 + 0.04 * ((bank + variant) % 2), SNOW, 8, 4,
                (0.70 + (bank % 3) * 0.08, 1.10 - (bank % 3) * 0.08,
                 0.15 + 0.025 * ((bank + variant) % 3)))

    if variant == 0:
        box(c, "service_hatch", (0, -0.18, 0.247), (1.62, 1.82, 0.016),
            STEEL, 0.12, 1)
        box(c, "service_hatch_inset", (0, -0.18, 0.257), (1.22, 1.36, 0.012),
            NAVY_2, 0.0, 1)
    elif variant == 1:
        for side in (-1, 1):
            box(c, f"inspection_door_{side}", (side * 2.55, side * 0.72, 0.247),
                (1.42, 1.18, 0.016), STEEL, 0.11, 1)
            box(c, f"door_inset_{side}", (side * 2.55, side * 0.72, 0.257),
                (0.98, 0.74, 0.012), NAVY_2, 0.0, 1)
    else:
        box(c, "utility_spine", (0, 0.12, 0.247), (0.52, 4.55, 0.016),
            STEEL, 0.10, 1)
        for y in (-1.72, -0.54, 0.64, 1.82):
            box(c, f"spine_lid_{y}", (0, y, 0.257), (0.34, 0.78, 0.012),
                NAVY_2, 0.0, 1)
    return c


def build_deck() -> bpy.types.Collection:
    return build_deck_variant("runner_day_deck_kerb_v1", 0)


def build_deck_b() -> bpy.types.Collection:
    return build_deck_variant("runner_day_deck_kerb_b_v1", 1)


def build_deck_c() -> bpy.types.Collection:
    return build_deck_variant("runner_day_deck_kerb_c_v1", 2)


def build_gantry() -> bpy.types.Collection:
    c = collection("runner_day_gantry_v1")
    for side in (-1, 1):
        x = side * 5.02
        box(c, f"rounded_foot_{side}", (x, 0, 0.14), (1.02, 1.28, 0.28),
            STEEL_HI, 0.13, 3)
        # Cream body owns the silhouette. Cyan steel is a side band; navy is
        # limited to palm-sized service recesses. This remains legible even
        # when the forward sun puts the portal underside in real shadow.
        box(c, f"portal_leg_{side}", (x, 0, 1.78), (0.88, 0.96, 3.42),
            ICE, 0.22, 5)
        box(c, f"cyan_leg_band_{side}", (x - side * 0.455, -0.02, 1.84),
            (0.09, 0.72, 2.48), STEEL, 0.038, 2)
        box(c, f"orange_bumper_{side}", (x - side * 0.44, 0.0, 0.66),
            (0.12, 0.78, 0.42), ORANGE_HI, 0.055, 2)
        for z in (1.32, 2.48):
            box(c, f"leg_access_{side}_{z}", (x - side * 0.445, -0.02, z),
                (0.055, 0.34, 0.28), NAVY, 0.035, 2)
        # One rounded service panel plus work lamp per leg. Large, sparse
        # authored features survive chase distance; rows of tiny greebles do not.
        box(c, f"route_panel_{side}", (x - side * 0.452, -0.02, 3.10),
            (0.065, 0.58, 0.46), STEEL_HI, 0.055, 2)
        sphere(c, f"warm_work_lamp_{side}",
               (x - side * 0.49, -0.31, 3.10), 0.12,
               WARM_WINDOW, 8, 4, (0.70, 0.48, 1.0))
    # Cyan low bar is the semantic duck instruction. Chunky cream/cyan portal
    # around it reads as architecture, not repeated black scaffolding.
    box(c, "duck_threshold", (0, 0, 1.08), (10.82, 0.76, 0.34),
        CYAN, 0.13, 4)
    box(c, "hazard_trim", (0, -0.405, 1.08), (9.45, 0.06, 0.13),
        ORANGE_HI, 0.025, 2)
    # Raised asymmetric-round crown restores open sky over the decision
    # horizon. V5's low dark underside dominated both portrait and compact.
    crown_points = [(-4.90, 3.48), (-2.62, 4.16), (0.0, 4.42),
                    (2.62, 4.16), (4.90, 3.48)]
    for index in range(len(crown_points) - 1):
        x0, z0 = crown_points[index]
        x1, z1 = crown_points[index + 1]
        beam(c, f"cream_crown_{index}", (x0, 0, z0), (x1, 0, z1),
             0.76, ICE, 0.18)
        beam(c, f"cyan_crown_inlay_{index}", (x0, -0.39, z0), (x1, -0.39, z1),
             0.14, CYAN, 0.035)
    for index, (x, z) in enumerate(crown_points):
        sphere(c, f"rounded_crown_joint_{index}", (x, 0, z), 0.43,
               ICE if index not in (1, 3) else STEEL_HI, 12, 6,
               (1.0, 0.82, 1.0))
    for x in (-3.72, -1.24, 1.24, 3.72):
        sphere(c, f"clearance_lamp_{x}", (x, -0.45, 1.08), 0.145,
               CYAN, 12, 6, (1.0, 0.62, 1.0))
    cylinder(c, "sensor_mast", (0, 0, 4.70), 0.14, 0.46, STEEL, 14)
    sphere(c, "sensor_head", (0, 0, 4.98), 0.26, ORANGE_HI, 14, 7,
           (1.0, 0.72, 0.72))
    return c


def build_lab() -> bpy.types.Collection:
    c = collection("runner_day_research_lab_v1")
    box(c, "module_body", (0, 0, 1.75), (7.2, 4.2, 3.5), ICE, 0.24, 2)
    box(c, "underframe", (0, 0, 0.32), (7.7, 4.5, 0.32), STEEL, 0.09, 1)
    box(c, "roof_spine", (0, 0, 3.58), (5.8, 1.25, 0.34), STEEL_HI, 0.12, 1)
    # Panels are modeled, not atlas-only lines. One-metre rhythm survives the
    # mid-band scale and stops the module reading as a white shipping cuboid.
    for side in (-1, 1):
        y = side * 2.125
        for x in (-3.05, -1.53, 0.0, 1.53, 3.05):
            box(c, f"panel_rib_{side}_{x}", (x, y, 1.72),
                (0.10, 0.075, 2.90), STEEL, 0.0, 1)
        box(c, f"lower_service_band_{side}", (0, y, 0.72),
            (6.72, 0.085, 0.20), STEEL_HI, 0.0, 1)
    for x in (-2.55, -0.85, 0.85, 2.55):
        box(c, f"window_front_{x}", (x, -2.17, 2.08),
            (1.14, 0.075, 0.84), WARM_WINDOW, 0.0, 1)
        box(c, f"window_back_{x}", (x, 2.17, 2.08),
            (1.14, 0.075, 0.84), WARM_WINDOW, 0.0, 1)
    for end in (-1, 1):
        box(c, f"airlock_frame_{end}", (end * 3.68, 0, 1.30),
            (0.14, 1.78, 2.42), ORANGE_HI, 0.030, 1)
        box(c, f"airlock_door_{end}", (end * 3.76, 0, 1.30),
            (0.045, 1.26, 1.92), STEEL_HI, 0.025, 1)
        box(c, f"door_window_{end}", (end * 3.785, -0.25, 1.62),
            (0.025, 0.52, 0.52), WARM_WINDOW, 0.025, 1)
    for x in (-2.8, 2.8):
        for y in (-1.52, 1.52):
            cylinder(c, f"stilt_{x}_{y}", (x, y, 0.36), 0.11, 0.72, STEEL, 10, bevel=0.0)
            box(c, f"pad_{x}_{y}", (x, y, 0.06), (0.56, 0.56, 0.12), STEEL_HI, 0.0, 1)
    cylinder(c, "roof_vent", (-1.8, 0, 4.02), 0.34, 0.72, STEEL, 12, bevel=0.0)
    torus(c, "roof_vent_cowl", (-1.8, 0, 4.34), 0.38, 0.07,
          ORANGE_HI, 12, 5)
    sphere(c, "weather_pod", (1.95, 0, 4.02), 0.40, SNOW, 12, 6, (1.0, 1.0, 0.68))
    cylinder(c, "antenna_mast", (0.65, 0, 4.24), 0.07, 1.10,
             STEEL, 10, bevel=0.0)
    beam(c, "antenna_crossbar", (-0.02, 0, 4.60), (1.32, 0, 4.60),
         0.065, CYAN, 0.012)
    for side in (-1, 1):
        box(c, f"solar_wing_{side}", (side * 4.48, 0, 2.72), (1.65, 3.35, 0.12), NAVY_2, 0.025, 1)
        for row in range(3):
            box(c, f"solar_cell_{side}_{row}",
                (side * 4.48, -1.05 + row * 1.05, 2.80),
                (1.35, 0.82, 0.025), GLASS, 0.0, 1)
    return c


def build_pylon() -> bpy.types.Collection:
    c = collection("runner_day_signal_pylon_v1")
    box(c, "sled", (0, 0, 0.12), (1.45, 1.95, 0.24), ORANGE_HI, 0.11, 2)
    for x in (-0.48, 0.48):
        cylinder(c, f"runner_{x}", (x, 0, 0.17), 0.10, 2.15, STEEL, 10,
                 (math.pi * 0.5, 0, 0), 0.0)
    box(c, "equipment_pod", (0, -0.12, 0.72), (0.86, 0.72, 0.82),
        ICE, 0.12, 2)
    box(c, "equipment_screen", (0, -0.495, 0.78), (0.48, 0.045, 0.32),
        GLASS, 0.0, 1)
    # Side-mounted route placard changes pylon silhouette and gives the port a
    # legible wayfinding language beyond repeated poles and coloured dots.
    box(c, "route_sign", (0.66, -0.02, 1.54), (0.82, 0.11, 0.46),
        FROST, 0.055, 2)
    box(c, "route_sign_mark", (0.66, -0.082, 1.54), (0.48, 0.02, 0.16),
        ORANGE_HI, 0.0, 1)
    cylinder(c, "mast", (0, 0, 1.78), 0.19, 3.0, STEEL_HI, 14, bevel=0.035)
    for z in (1.08, 1.72, 2.36):
        torus(c, f"mast_ring_{z}", (0, 0, z), 0.22, 0.045, ORANGE_HI, 12, 4)
    for side in (-1, 1):
        beam(c, f"brace_{side}", (side * 0.52, -0.62, 0.18), (0, 0, 1.26), 0.10, STEEL, 0.02)
        box(c, f"signal_fin_{side}", (side * 0.49, 0, 2.60), (0.82, 0.15, 0.64),
            ICE, 0.055, 1)
        box(c, f"signal_light_{side}", (side * 0.49, -0.09, 2.60),
            (0.38, 0.045, 0.22), CYAN, 0.0, 1)
    sphere(c, "beacon", (0, 0, 3.48), 0.38, GOLD, 14, 7, (1.0, 1.0, 0.72))
    torus(c, "beacon_guard", (0, 0, 3.48), 0.49, 0.055, STEEL, 14, 5)
    for angle_i in range(4):
        a = math.tau * angle_i / 4.0
        cylinder(c, f"sensor_{angle_i}", (math.cos(a) * 0.32, math.sin(a) * 0.32, 3.02),
                 0.045, 0.40, STEEL_HI, 8, bevel=0.0)
    return c


def build_snowcat() -> bpy.types.Collection:
    c = collection("runner_day_snowcat_v1")
    for side in (-1, 1):
        x = side * 0.92
        # Pale powder-coated track shell remains readable from the front; only
        # the inset belt is rubber. V5 made the complete running gear navy and
        # collapsed this obstacle into two black rectangles.
        box(c, f"track_{side}", (x, 0.04, 0.36), (0.40, 1.58, 0.60),
            STEEL_HI, 0.14, 3)
        box(c, f"track_belt_{side}", (x - side * 0.205, 0.04, 0.36),
            (0.045, 1.24, 0.38), RUBBER, 0.04, 2)
        for y in (-0.52, -0.18, 0.18, 0.52):
            torus(c, f"wheel_{side}_{y}", (x - side * 0.205, y, 0.37), 0.17, 0.055,
                  ORANGE_HI if abs(y) > 0.4 else ICE, 12, 5,
                  (0, math.pi * 0.5, 0))
        for y in (-0.62, -0.31, 0.0, 0.31, 0.62):
            box(c, f"cleat_{side}_{y}", (x, y, 0.68), (0.42, 0.12, 0.09),
                STEEL_HI, 0.022, 1)
        cylinder(c, f"rounded_track_nose_{side}", (x, -0.78, 0.38),
                 0.25, 0.12, STEEL_HI, 12, (math.pi * 0.5, 0, 0), 0.025)
    # Orange expedition body is the block/hazard semantic at maximum speed.
    box(c, "chassis", (0, 0.06, 0.82), (1.78, 1.30, 0.64),
        ORANGE, 0.18, 3)
    box(c, "front_hood", (0, -0.54, 1.08), (1.66, 0.62, 0.60),
        ORANGE_HI, 0.18, 3)
    box(c, "hood_cream_cap", (0, -0.56, 1.40), (1.34, 0.52, 0.10),
        ICE, 0.045, 2)
    box(c, "front_radiator", (0, -0.865, 1.04), (0.92, 0.055, 0.34),
        NAVY, 0.035, 2)
    # Cab, hazard body and glazing occupy three deliberately separated
    # mid-values. None relies on direct sun to describe the snowcat silhouette.
    box(c, "cab", (0, 0.12, 1.52), (1.50, 0.96, 1.06), STEEL, 0.22, 3)
    box(c, "windscreen", (0, -0.375, 1.66), (1.12, 0.055, 0.54),
        GLASS, 0.065, 2)
    for x in (-0.74, 0.74):
        box(c, f"side_window_{x}", (x, 0.02, 1.66), (0.055, 0.54, 0.48),
            GLASS, 0.045, 2)
        box(c, f"cab_door_{x}", (x, 0.37, 1.35), (0.06, 0.48, 0.50),
            ORANGE_HI, 0.035, 2)
        cylinder(c, f"door_handle_{x}",
            (x + (-0.035 if x > 0 else 0.035), 0.20, 1.39),
            0.035, 0.22, GOLD, 8, (0, math.pi * 0.5, 0), 0.0)
    # Front is -Y, preserving authored -Z runtime forward.
    verts = [(-1.22, -1.02, 0.08), (1.22, -1.02, 0.08), (-1.05, -1.02, 0.66),
             (1.05, -1.02, 0.66), (-0.88, -0.72, 0.58), (0.88, -0.72, 0.58)]
    faces = [(0, 1, 3, 2), (2, 3, 5, 4), (0, 2, 4), (1, 5, 3), (0, 4, 5, 1)]
    custom_mesh(c, "snow_plough", verts, faces,
                [ORANGE_HI, ORANGE_HI, STEEL, STEEL, NAVY_2])
    for x in (-0.48, 0.48):
        sphere(c, f"headlamp_{x}", (x, -0.905, 1.27), 0.15, GOLD,
               12, 6, (1.0, 0.55, 1.0))
    cylinder(c, "beacon_stem", (0, 0.18, 2.13), 0.07, 0.26,
             STEEL, 10, bevel=0.0)
    sphere(c, "beacon", (0, 0.18, 2.31), 0.17, ORANGE_HI,
           12, 6, (1.0, 1.0, 0.78))
    for x in (-0.82, 0.82):
        beam(c, f"roof_rail_{x}", (x, -0.30, 2.03), (x, 0.52, 2.03),
             0.065, STEEL, 0.015)
    return c


def build_cargo() -> bpy.types.Collection:
    c = collection("runner_day_cargo_stack_v1")
    box(c, "cargo_sled", (0, 0, 0.11), (3.55, 2.25, 0.22), STEEL_HI, 0.10, 1)
    placements = [(-0.92, -0.42, 0.72, 1.45, 1.20, 1.18),
                  (0.72, -0.48, 0.62, 1.45, 1.08, 0.98),
                  (0.15, 0.67, 0.68, 1.65, 0.92, 1.10)]
    for i, (x, y, z, sx, sy, sz) in enumerate(placements):
        crate_colour = ORANGE_HI if i == 0 else ICE if i == 1 else STEEL
        box(c, f"crate_{i}", (x, y, z), (sx, sy, sz), crate_colour, 0.12, 2)
        for edge in (-1, 1):
            box(c, f"strap_{i}_{edge}", (x + edge * sx * 0.32, y, z),
                (0.10, sy + 0.035, sz + 0.035), STEEL_HI, 0.0, 1)
        for cx in (-1, 1):
            for cy in (-1, 1):
                sphere(c, f"corner_{i}_{cx}_{cy}",
                       (x + cx * sx * 0.43, y + cy * sy * 0.43, z + sz * 0.42),
                       0.085, NAVY_2, 6, 3)
        box(c, f"crate_label_{i}", (x, y - sy * 0.515, z),
            (sx * 0.52, 0.025, sz * 0.28), GOLD if i == 0 else CYAN,
            0.0, 1)
    # Service cable reel makes this a working load, not three decorative
    # cubes. Coils are deliberately broad and low-poly so silhouette survives
    # mid-distance without creating another material or draw.
    reel = (1.34, 0.62, 0.55)
    for x in (reel[0] - 0.28, reel[0] + 0.28):
        cylinder(c, f"cable_reel_flange_{x}", (x, reel[1], reel[2]),
                 0.38, 0.08, ORANGE_HI, 10,
                 (0, math.pi * 0.5, 0), 0.0)
    cylinder(c, "cable_reel_axle", reel, 0.10, 0.68, STEEL_HI, 10,
             (0, math.pi * 0.5, 0), 0.0)
    for offset in (-0.08, 0.0, 0.08):
        torus(c, f"cable_coil_{offset}",
              (reel[0] + offset, reel[1], reel[2]), 0.27, 0.045,
              RUBBER, 12, 4, (0, math.pi * 0.5, 0))
    beam(c, "loose_cable_a", (reel[0], reel[1] + 0.26, reel[2] - 0.17),
         (0.58, 0.98, 0.18), 0.045, RUBBER, 0.0)
    beam(c, "loose_cable_b", (0.58, 0.98, 0.18),
         (-0.20, 0.92, 0.16), 0.045, RUBBER, 0.0)
    for x in (-1.35, 1.35):
        cylinder(c, f"sled_runner_{x}", (x, 0, 0.07), 0.10, 2.70, STEEL_HI, 10,
                 (math.pi * 0.5, 0, 0), 0.0)
    return c


def build_ramp() -> bpy.types.Collection:
    c = collection("runner_day_ramp_v1")
    wedge(c, "packed_snow_kicker", 2.55, 4.0, 1.55, SNOW)
    for side in (-1, 1):
        x = side * 1.18
        for i in range(6):
            t0 = i / 6.0
            t1 = (i + 1) / 6.0
            y0 = 2.0 - 4.0 * t0
            y1 = 2.0 - 4.0 * t1
            z0 = 1.55 * (t0 ** 1.32) + 0.14
            z1 = 1.55 * (t1 ** 1.32) + 0.14
            beam(c, f"rail_{side}_{i}", (x, y0, z0), (x, y1, z1), 0.12, NAVY, 0.025)
        for i in range(4):
            t = (i + 1) / 5.0
            y = 2.0 - 4.0 * t
            z = 1.55 * (t ** 1.32) + 0.075
            beam(c, f"green_chevron_l_{i}", (-0.86, y + 0.34, z), (0, y, z + 0.12), 0.14, GREEN, 0.02)
            beam(c, f"green_chevron_r_{i}", (0, y, z + 0.12), (0.86, y + 0.34, z), 0.14, GREEN, 0.02)
    box(c, "takeoff_lip", (0, -1.93, 1.60), (2.72, 0.25, 0.20), GREEN, 0.065, 3)
    for x in (-1.08, -0.54, 0, 0.54, 1.08):
        cylinder(c, f"lip_lamp_{x}", (x, -2.08, 1.66), 0.07, 0.06, GOLD, 10,
                 (math.pi * 0.5, 0, 0), 0.008)
    return c


def build_barrier() -> bpy.types.Collection:
    c = collection("runner_day_barrier_v1")
    for z, y in ((0.24, 0.22), (0.24, -0.22), (0.57, 0.0)):
        cylinder(c, f"heated_pipe_{z}_{y}", (0, y, z), 0.19, 2.52, ORANGE_HI, 16,
                 (0, math.pi * 0.5, 0), 0.035)
    for x in (-0.95, -0.32, 0.32, 0.95):
        box(c, f"pipe_clamp_{x}", (x, 0, 0.36), (0.12, 0.72, 0.70), STEEL_HI, 0.035, 2)
        cylinder(c, f"clamp_lamp_{x}", (x, -0.40, 0.64), 0.065, 0.055, ORANGE_HI, 10,
                 (math.pi * 0.5, 0, 0), 0.008)
    for y in (-0.36, 0.36):
        box(c, f"sled_foot_{y}", (0, y, 0.065), (2.75, 0.13, 0.13), RUBBER, 0.035, 2)
    for x in (-1.18, 1.18):
        sphere(c, f"end_cap_{x}", (x, 0, 0.57), 0.22, ORANGE_HI, 16, 8, (0.55, 1.0, 1.0))
        torus(c, f"end_guard_{x}", (x, 0, 0.57), 0.30, 0.045, NAVY, 16, 6,
              (0, math.pi * 0.5, 0))
    return c


def build_tunnel() -> bpy.types.Collection:
    c = collection("runner_day_tunnel_shell_v1")
    arch_shell(c, "ice_vault")
    # Ground the vault on four clean uprights. The arch spring starts at 2.05 m;
    # without supports final pivot normalization lowers the whole shell and turns
    # its 5.3 m crown into a cramped 3.5 m roof. Straight posts preserve height
    # and silhouette without bringing back the rejected diagonal lattice.
    for y in (-2.78, 2.78):
        for side in (-1, 1):
            box(c, f"vault_upright_{y}_{side}", (side * 5.62, y, 1.025),
                (0.34, 0.34, 2.05), STEEL_HI, 0.055, 2)
    for y in (-2.78, 2.78):
        for i in range(7):
            a = math.pi * i / 6.0
            x = math.cos(a) * 5.62
            z = 2.05 + math.sin(a) * 3.25
            torus(c, f"rib_joint_{y}_{i}", (x, y, z), 0.12, 0.035, STEEL_HI, 12, 5,
                  (math.pi * 0.5, 0, 0))
    for side in (-1, 1):
        x = side * 4.86
        box(c, f"cyan_wayfinder_{side}", (x, 0, 2.55), (0.10, 5.65, 0.16), CYAN, 0.035, 2)
        for y in (-2.1, -0.7, 0.7, 2.1):
            sphere(c, f"bay_lamp_{side}_{y}", (x - side * 0.06, y, 2.55), 0.105,
                   CYAN, 12, 6, (0.72, 1.0, 1.0))
    # The ice vault itself owns the entrance silhouette. Extra diagonal portal
    # braces previously created a second dark lattice when a gantry shared the
    # chunk; omit them and let the clean cyan wayfinding line frame the shell.
    box(c, "clean_cyan_crown", (0, 0, 5.18), (3.8, 5.7, 0.12), CYAN, 0.035, 2)
    return c


def build_radar_landmark() -> bpy.types.Collection:
    c = collection("runner_day_radar_landmark_v1")
    # Broad plinth stays mid-value; deep navy belongs only in braces/recesses.
    # Far fog otherwise turns this whole landmark into a black floating slab.
    box(c, "foundation", (0, 0, 0.40), (10.8, 8.6, 0.8), NAVY_2, 0.22, 4)
    box(c, "operations_block", (0, 0, 2.65), (8.8, 6.6, 4.0), ICE, 0.42, 5)
    for side in (-1, 1):
        x = side * 4.44
        box(c, f"airlock_frame_{side}", (x, 0, 2.10),
            (0.16, 1.72, 2.52), ORANGE_HI, 0.06, 2)
        box(c, f"airlock_door_{side}", (x + side * 0.09, 0, 2.08),
            (0.055, 1.20, 1.96), STEEL_HI, 0.025, 1)
    for side in (-1, 1):
        for i in range(7):
            box(c, f"window_{side}_{i}", (-3.45 + i * 1.15, side * 3.34, 3.1),
                (0.78, 0.08, 0.78), WARM_WINDOW, 0.08, 3)
        box(c, f"operations_band_{side}", (0, side * 3.37, 1.18),
            (7.9, 0.09, 0.24), STEEL, 0.025, 1)
    for x in (-3.15, -1.55, 0.0, 1.55, 3.15):
        box(c, f"facade_rib_{x}", (x, -3.38, 2.55),
            (0.12, 0.09, 3.35), STEEL_HI, 0.02, 1)
    for x in (-2.6, 2.6):
        cylinder(c, f"roof_air_handler_{x}", (x, 0.8, 5.10),
                 0.52, 1.10, STEEL, 16, bevel=0.06)
        torus(c, f"roof_air_handler_cowl_{x}", (x, 0.8, 5.58),
              0.55, 0.08, ORANGE_HI, 16, 6)
    cylinder(c, "tower", (0, 0, 7.3), 1.05, 5.6, STEEL, 32, bevel=0.10)
    for z in (5.0, 6.3, 7.6, 8.9):
        torus(c, f"tower_ring_{z}", (0, 0, z), 1.18, 0.10, ORANGE_HI, 32, 8)
    sphere(c, "radome", (0, 0, 11.15), 2.75, SNOW, 48, 24, (1.0, 1.0, 0.86))
    for latitude in (-1.25, -0.42, 0.42, 1.25):
        radius = math.sqrt(max(0.1, 2.75 * 2.75 - latitude * latitude))
        torus(c, f"radome_band_{latitude}", (0, 0, 11.15 + latitude), radius, 0.045,
              STEEL_HI, 48, 6)
    for angle_i in range(16):
        a = math.tau * angle_i / 16.0
        x, y = math.cos(a) * 4.75, math.sin(a) * 3.65
        cylinder(c, f"perimeter_beacon_{angle_i}", (x, y, 1.22), 0.10, 1.65,
                 NAVY_2, 12)
        sphere(c, f"perimeter_lamp_{angle_i}", (x, y, 2.12), 0.14,
               GOLD if angle_i % 2 == 0 else CYAN, 12, 6)
    for arm in range(4):
        a = math.tau * arm / 4.0
        start = (math.cos(a) * 1.0, math.sin(a) * 1.0, 7.4)
        end = (math.cos(a) * 4.15, math.sin(a) * 3.55, 4.7)
        beam(c, f"tower_brace_{arm}", start, end, 0.22, NAVY, 0.045)
    return c


def build_hub_landmark() -> bpy.types.Collection:
    c = collection("runner_day_research_hub_landmark_v1")
    box(c, "raised_platform", (0, 0, 0.5), (22.0, 14.0, 1.0), NAVY_2, 0.28, 4)
    module_centres = [(-6.2, -3.6), (0, -3.6), (6.2, -3.6), (-6.2, 3.6), (0, 3.6), (6.2, 3.6)]
    for idx, (x, y) in enumerate(module_centres):
        box(c, f"lab_module_{idx}", (x, y, 3.1), (5.4, 5.0, 4.4), ICE, 0.34, 4)
        box(c, f"lab_window_{idx}", (x, y - 2.53, 3.35),
            (3.7, 0.08, 1.12), WARM_WINDOW, 0.12, 3)
        box(c, f"lab_service_band_{idx}", (x, y - 2.57, 1.58),
            (4.52, 0.09, 0.30), STEEL, 0.025, 1)
        for rib in (-1.8, 0.0, 1.8):
            box(c, f"lab_rib_{idx}_{rib}", (x + rib, y - 2.58, 3.05),
                (0.13, 0.08, 3.78), STEEL_HI, 0.018, 1)
        box(c, f"airlock_frame_{idx}", (x + 2.73, y + 0.6, 2.45),
            (0.16, 1.62, 2.72), ORANGE_HI, 0.055, 2)
        box(c, f"airlock_door_{idx}", (x + 2.83, y + 0.6, 2.42),
            (0.05, 1.10, 2.08), STEEL_HI, 0.02, 1)
        box(c, f"roof_pack_{idx}", (x, y, 5.48), (3.8, 2.0, 0.52), STEEL, 0.14, 3)
        for corner in (-1, 1):
            cylinder(c, f"vent_{idx}_{corner}", (x + corner * 1.45, y, 6.2), 0.28,
                     1.22, STEEL, 16)
    cylinder(c, "central_core", (0, 0, 7.6), 2.25, 7.0, STEEL_HI, 40, bevel=0.14)
    sphere(c, "core_observatory", (0, 0, 11.2), 2.55, GLASS, 48, 24, (1.0, 1.0, 0.62))
    cylinder(c, "observatory_antenna", (0, 0, 13.12), 0.15,
             2.30, STEEL, 18, bevel=0.03)
    for z in (12.55, 13.45):
        beam(c, f"observatory_yard_{z}", (-1.35, 0, z), (1.35, 0, z),
             0.11, CYAN, 0.02)
    for z in (6.2, 8.0, 9.8):
        torus(c, f"core_ring_{z}", (0, 0, z), 2.42, 0.11, ORANGE_HI, 36, 8)
    for side in (-1, 1):
        x = side * 9.2
        box(c, f"solar_frame_{side}", (x, 0, 3.45), (4.2, 10.4, 0.20), NAVY_2, 0.08, 2)
        for row in range(8):
            for col in range(3):
                box(c, f"solar_cell_{side}_{row}_{col}",
                    (x + (col - 1) * 1.25, -4.35 + row * 1.24, 3.58),
                    (1.04, 0.98, 0.035), GLASS, 0.035, 2)
    for idx in range(len(module_centres)):
        a = math.tau * idx / len(module_centres)
        beam(c, f"core_walkway_{idx}", (math.cos(a) * 2.3, math.sin(a) * 2.3, 5.25),
             (module_centres[idx][0], module_centres[idx][1], 5.25), 0.24, NAVY, 0.045)
    return c


def build_icebreaker_landmark() -> bpy.types.Collection:
    c = collection("runner_day_icebreaker_landmark_v1")
    # Layered hull gives bow a readable wedge without transparency.
    levels = [(-2.0, 3.3, 13.0), (-0.9, 4.6, 15.2), (0.1, 5.7, 17.0), (1.1, 6.1, 18.0)]
    for idx, (z, width, length) in enumerate(levels):
        box(c, f"hull_band_{idx}", (0, 0.6, z + 2.05), (width * 2, length, 2.0),
            NAVY_2 if idx == 0 else STEEL if idx == 1 else ORANGE, 0.42, 5)
    box(c, "foredeck", (0, -4.0, 4.12), (10.7, 7.4, 0.52), STEEL_HI, 0.16, 3)
    box(c, "superstructure", (0, 2.2, 6.0), (8.2, 7.6, 4.1), ICE, 0.36, 4)
    box(c, "bridge", (0, -0.35, 8.72), (9.0, 3.2, 1.7), ICE, 0.28, 4)
    for side in (-1, 1):
        box(c, f"hull_service_band_{side}", (side * 5.72, 0.2, 3.15),
            (0.10, 12.2, 0.38), STEEL_HI, 0.04, 2)
        for y in (-3.6, -0.8, 2.0, 4.8):
            box(c, f"hull_access_{side}_{y}", (side * 5.78, y, 3.72),
                (0.06, 1.18, 0.86), NAVY_2, 0.045, 2)
            sphere(c, f"hull_port_{side}_{y}",
                   (side * 5.83, y, 3.72), 0.16, GOLD, 12, 6,
                   (0.32, 1.0, 1.0))
    for side in (-1, 1):
        for i in range(8):
            box(c, f"bridge_window_{side}_{i}", (-3.7 + i * 1.05, -1.98, 8.86 + side * 0.0),
                (0.72, 0.08, 0.58), WARM_WINDOW, 0.07, 3)
    cylinder(c, "funnel", (0, 4.0, 10.15), 1.0, 4.0, ORANGE_HI, 32, bevel=0.12)
    torus(c, "funnel_collar", (0, 4.0, 11.6), 1.05, 0.14, NAVY, 28, 8)
    cylinder(c, "mast", (0, -0.6, 12.15), 0.16, 6.2, NAVY, 16)
    sphere(c, "bridge_radar", (0, -0.4, 10.08), 0.58,
           STEEL_HI, 18, 9, (1.35, 0.38, 0.72))
    for z in (10.0, 11.8, 13.6):
        beam(c, f"yard_{z}", (-2.25, -0.6, z), (2.25, -0.6, z), 0.12, NAVY_2, 0.025)
        for x in (-2.1, -1.05, 0, 1.05, 2.1):
            sphere(c, f"mast_lamp_{z}_{x}", (x, -0.6, z), 0.10,
                   GOLD if int(abs(x) * 10) % 2 == 0 else CYAN, 12, 6)
    for side in (-1, 1):
        x = side * 4.45
        for y in (-4.8, -2.8, -0.8, 1.2, 3.2, 5.2):
            cylinder(c, f"rail_post_{side}_{y}", (x, y, 5.0), 0.055, 1.22, NAVY, 10)
        beam(c, f"rail_top_{side}", (x, -5.2, 5.58), (x, 5.7, 5.58), 0.065, NAVY, 0.012)
        cylinder(c, f"lifeboat_{side}", (side * 4.35, 2.3, 7.15), 0.68, 3.2,
                 ORANGE_HI, 24, (0, math.pi * 0.5, 0), 0.08)
    # Deck crane and cable cage.
    cylinder(c, "crane_pedestal", (-2.8, -4.3, 5.4), 0.48, 2.5, NAVY_2, 20, bevel=0.08)
    beam(c, "crane_boom", (-2.8, -4.3, 6.6), (3.5, -5.1, 11.0), 0.30, ORANGE, 0.06)
    for i in range(9):
        t = i / 8.0
        x = -2.8 + (3.5 + 2.8) * t
        y = -4.3 + (-5.1 + 4.3) * t
        z = 6.6 + (11.0 - 6.6) * t
        torus(c, f"boom_joint_{i}", (x, y, z), 0.24, 0.055, GOLD, 14, 6,
              (math.pi * 0.5, 0, 0))
    return c


def build_iceberg_cluster() -> bpy.types.Collection:
    """Authored fractured skyline family; replaces cheap triangular prisms."""
    c = collection("runner_day_iceberg_cluster_v1")
    masses = [
        ((-4.6, 0.2, 3.85), (3.25, 2.15, 3.45), (0.08, -0.18, 0.10)),
        ((-1.4, -0.5, 5.05), (2.85, 2.55, 4.65), (-0.12, 0.10, -0.16)),
        ((1.65, 0.15, 4.15), (3.55, 2.20, 3.75), (0.06, 0.22, 0.12)),
        ((4.65, -0.35, 2.90), (2.55, 1.75, 2.55), (-0.10, -0.15, -0.08)),
        ((0.15, 1.35, 2.15), (4.65, 1.60, 1.80), (0.03, 0.08, 0.0)),
    ]
    for index, (center, scale, rotation) in enumerate(masses):
        faceted_ice(c, f"fractured_mass_{index}", center, scale, rotation)
    # Broad near-water shelf unifies the cluster; top remains irregular and
    # every peak has several non-coplanar faces for atmospheric value fade.
    flat_patch(c, "waterline_shelf", (0.0, 0.1, 0.04), (11.8, 5.4),
               STEEL_HI, 3)
    return c


def triangle_count(coll: bpy.types.Collection) -> int:
    total = 0
    for obj in coll.objects:
        if obj.type == "MESH":
            obj.data.calc_loop_triangles()
            total += len(obj.data.loop_triangles)
    return total


def palette_stats(mesh: bpy.types.Mesh) -> dict[str, float]:
    """Surface-area weighted value/semantic coverage for source QA."""
    colour_attr = mesh.color_attributes.get("Color")
    if colour_attr is None:
        raise RuntimeError(f"{mesh.name}: missing Color attribute")
    totals = {"dark": 0.0, "orange": 0.0, "pale": 0.0,
              "white": 0.0, "total": 0.0}
    for polygon in mesh.polygons:
        colour = tuple(
            sum(float(colour_attr.data[index].color[channel])
                for index in polygon.loop_indices) / len(polygon.loop_indices)
            for channel in range(3)
        )
        area = max(float(polygon.area), 0.000001)
        value = colour[0] * 0.2126 + colour[1] * 0.7152 + colour[2] * 0.0722
        totals["total"] += area
        if value < 0.24:
            totals["dark"] += area
        if colour[0] > 0.72 and colour[0] > colour[1] * 1.55 and colour[2] < 0.20:
            totals["orange"] += area
        if value > 0.60:
            totals["pale"] += area
        if value > 0.90 and max(colour) - min(colour) < 0.10:
            totals["white"] += area
    total = totals.pop("total")
    return {key: value / total for key, value in totals.items()}


def validate_palette(name: str, stats: dict[str, float]) -> None:
    rules = {
        "runner_day_deck_kerb_v1": {
            "dark_max": 0.08, "pale_min": 0.68, "white_max": 0.28},
        "runner_day_deck_kerb_b_v1": {
            "dark_max": 0.08, "pale_min": 0.68, "white_max": 0.28},
        "runner_day_deck_kerb_c_v1": {
            "dark_max": 0.08, "pale_min": 0.68, "white_max": 0.28},
        "runner_day_gantry_v1": {"dark_max": 0.10, "pale_min": 0.48},
        "runner_day_snowcat_v1": {"dark_max": 0.18, "orange_min": 0.18},
        "runner_day_research_lab_v1": {"dark_max": 0.18, "pale_min": 0.52},
    }
    rule = rules.get(name)
    if rule is None:
        return
    for key, limit in rule.items():
        stat_name, direction = key.rsplit("_", 1)
        value = stats[stat_name]
        if direction == "max" and value > limit:
            raise RuntimeError(f"{name}: {stat_name} area {value:.3f} exceeds {limit:.3f}")
        if direction == "min" and value < limit:
            raise RuntimeError(f"{name}: {stat_name} area {value:.3f} below {limit:.3f}")


def assign_atlas_uv(mesh: bpy.types.Mesh) -> None:
    while len(mesh.uv_layers) > 0:
        mesh.uv_layers.remove(mesh.uv_layers[0])
    uv_layer = mesh.uv_layers.new(name="UVMap")
    colour_attr = mesh.color_attributes.get("Color")
    # Append V8 lived-in surfaces so all earlier semantic tile indices stay
    # stable. Atlas has sixteen slots; no new material/shader signature needed.
    palette = [NAVY, NAVY_2, STEEL, STEEL_HI, ICE, SNOW, GLASS, ORANGE,
               ORANGE_HI, CYAN, GREEN, GOLD, RUBBER, DECK, FROST,
               WARM_WINDOW]
    tile_scale = 1.0 / 4.0
    gutter = 0.07
    for polygon in mesh.polygons:
        normal = polygon.normal
        # One semantic tile per face. Selecting by loop let baked face shading
        # push adjacent corners across palette thresholds, interpolating UVs
        # through unrelated atlas tiles and producing diagonal colour smears.
        if colour_attr is not None:
            face_colour = tuple(
                sum(float(colour_attr.data[loop_index].color[channel])
                    for loop_index in polygon.loop_indices) / len(polygon.loop_indices)
                for channel in range(3)
            )
        else:
            face_colour = SNOW[:3]
        palette_index = min(range(len(palette)), key=lambda index: sum(
            (face_colour[channel] - palette[index][channel]) ** 2
            for channel in range(3)))
        for loop_index in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            if abs(normal.z) >= abs(normal.x) and abs(normal.z) >= abs(normal.y):
                raw_u, raw_v = vertex.x * 0.16, vertex.y * 0.16
            elif abs(normal.y) >= abs(normal.x):
                raw_u, raw_v = vertex.x * 0.16, vertex.z * 0.16
            else:
                raw_u, raw_v = vertex.y * 0.16, vertex.z * 0.16
            local_u = (raw_u - math.floor(raw_u)) * (1.0 - gutter * 2.0) + gutter
            local_v = (raw_v - math.floor(raw_v)) * (1.0 - gutter * 2.0) + gutter
            uv_layer.data[loop_index].uv = (
                (palette_index % 4 + local_u) * tile_scale,
                (palette_index // 4 + local_v) * tile_scale,
            )


def add_review_details(coll: bpy.types.Collection, minimum: int, maximum: int) -> None:
    # If major forms land below contract floor, add visible inspection bolts in
    # symmetric rows. They are authored scale/detail, not hidden topology.
    count = triangle_count(coll)
    index = 0
    while count < minimum:
        side = -1 if index % 2 == 0 else 1
        column = (index // 2) % 12
        row = (index // 24) % 4
        sphere(coll, f"inspection_bolt_{index}",
               (side * (0.22 + row * 0.16), -0.9 + column * 0.16, 0.22 + row * 0.18),
               0.045, GOLD if row == 3 else NAVY_2, 8, 4)
        count = triangle_count(coll)
        index += 1
        if index > 400:
            raise RuntimeError(f"cannot reach triangle floor for {coll.name}")
    if count > maximum:
        contributors = []
        for obj in coll.objects:
            if obj.type != "MESH":
                continue
            obj.data.calc_loop_triangles()
            contributors.append((len(obj.data.loop_triangles), obj.name))
        contributors.sort(reverse=True)
        summary = ", ".join(f"{name}:{triangles}" for triangles, name in contributors[:12])
        raise RuntimeError(
            f"{coll.name} triangles {count} exceed {maximum}; top={summary}")


def finalize(coll: bpy.types.Collection) -> tuple[int, int, dict[str, float]]:
    objects = [obj for obj in coll.objects if obj.type == "MESH"]
    if not objects:
        raise RuntimeError(f"empty collection {coll.name}")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = coll.name
    for polygon in obj.data.polygons:
        polygon.material_index = 0
    obj.data.materials.clear()
    obj.data.materials.append(material())
    tri = obj.modifiers.new("runtime_triangles", "TRIANGULATE")
    tri.keep_custom_normals = True
    bpy.ops.object.modifier_apply(modifier=tri.name)
    # Identity grounded pivot. Vertex translation, not object transform.
    points = [vertex.co for vertex in obj.data.vertices]
    minimum = Vector((min(v.x for v in points), min(v.y for v in points), min(v.z for v in points)))
    maximum = Vector((max(v.x for v in points), max(v.y for v in points), max(v.z for v in points)))
    shift = Vector((-(minimum.x + maximum.x) * 0.5, -(minimum.y + maximum.y) * 0.5, -minimum.z))
    for vertex in obj.data.vertices:
        vertex.co += shift
    obj.data.update()
    assign_atlas_uv(obj.data)
    obj.location = (0, 0, 0)
    obj.rotation_euler = (0, 0, 0)
    obj.scale = (1, 1, 1)
    obj["asset_id"] = coll.name
    obj["forward_axis"] = "-Z"
    obj["units"] = "metres"
    obj.data.calc_loop_triangles()
    stats = palette_stats(obj.data)
    validate_palette(coll.name, stats)
    return len(obj.data.loop_triangles), 1, stats


def main() -> int:
    if bpy.app.version[:3] != EXPECTED_VERSION:
        raise RuntimeError(f"expected Blender {EXPECTED_VERSION}, got {bpy.app.version[:3]}")
    args = parse_args()
    reset(Path(args.texture_root).resolve())
    builders = [
        (build_deck, 300, 1500),
        (build_deck_b, 300, 1500),
        (build_deck_c, 300, 1500),
        (build_gantry, 1500, 5000),
        (build_lab, 300, 1500),
        (build_pylon, 300, 1500),
        (build_snowcat, 1500, 5000),
        (build_cargo, 300, 1500),
        (build_ramp, 1500, 5000),
        (build_barrier, 1500, 5000),
        (build_tunnel, 1500, 5000),
        (build_iceberg_cluster, 300, 1500),
        (build_radar_landmark, 10000, 30000),
        (build_hub_landmark, 10000, 30000),
        (build_icebreaker_landmark, 10000, 30000),
    ]
    metrics = []
    for builder, minimum, maximum in builders:
        coll = builder()
        add_review_details(coll, minimum, maximum)
        triangles, surfaces, palette = finalize(coll)
        if triangles < minimum or triangles > maximum or surfaces != 1:
            raise RuntimeError(f"{coll.name}: triangles={triangles} surfaces={surfaces}")
        metrics.append((coll.name, triangles, surfaces, palette))
    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output), compress=True, check_existing=False)
    for name, triangles, surfaces, palette in metrics:
        print(f"[day-kit] {name} triangles={triangles} surfaces={surfaces} "
              f"dark={palette['dark']:.3f} orange={palette['orange']:.3f} "
              f"pale={palette['pale']:.3f} white={palette['white']:.3f}")
    print(f"[day-kit] saved {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
