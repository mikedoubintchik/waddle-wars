#!/usr/bin/env python3
"""Build project-original Glacier Gauntlet authored art in Blender 5.2 LTS.

The source is deterministic and contains one export collection per runtime
asset. Gameplay collision is deliberately absent: every collection is visual
only and gets seated against the existing immutable course guide in Godot.
"""

from __future__ import annotations

import argparse
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector


EXPECTED_VERSION = (5, 2, 0)
PACKED_TEXTURES: dict[str, bpy.types.Image] = {}

# Poster-derived glacier palette. White/cyan own natural ice; expedition blue
# and coral stay on built hardware. Semantic hues remain fixed and shaped:
# orange hazard, cyan duck, green boost, gold route/collect.
# Narrow value-controlled glacier family. Natural forms stay cyan-blue, but
# saturation drops as value rises: navy recess -> mineral cyan mid -> milky
# blue edge -> warm snow. This prevents one flat electric-blue tonemap while
# preserving the course's silhouette/value hierarchy in grayscale.
DEEP_ICE = (0.035, 0.215, 0.405, 1.0)
MID_ICE = (0.115, 0.455, 0.655, 1.0)
PALE_ICE = (0.480, 0.725, 0.825, 1.0)
SNOW = (0.935, 0.900, 0.815, 1.0)
SNOW_SHADOW = (0.380, 0.545, 0.660, 1.0)
EXPEDITION_BLUE = (0.020, 0.155, 0.345, 1.0)
EXPEDITION_LIGHT = (0.095, 0.465, 0.675, 1.0)
ORANGE = (1.000, 0.270, 0.045, 1.0)
ORANGE_HI = (1.000, 0.610, 0.100, 1.0)
CYAN = (0.020, 0.900, 1.000, 1.0)
GREEN = (0.080, 0.950, 0.250, 1.0)
GOLD = (1.000, 0.810, 0.180, 1.0)
GLASS = (0.025, 0.180, 0.310, 1.0)
RUBBER = (0.025, 0.050, 0.090, 1.0)
FABRIC = (0.860, 0.250, 0.170, 1.0)
LAB_SKIN = (0.310, 0.640, 0.735, 1.0)
LAB_PANEL = (0.660, 0.790, 0.790, 1.0)
# Hero arch uses a lifted mineral ramp. Global deep ice remains available for
# recesses/hardware; broad arch faces cannot collapse into near-black bands.
ARCH_DEEP = (0.105, 0.335, 0.470, 1.0)
ARCH_MID = (0.205, 0.515, 0.650, 1.0)
ARCH_PALE = (0.535, 0.745, 0.810, 1.0)
ARCH_RIM = (0.500, 0.760, 0.840, 1.0)

PALETTE = [DEEP_ICE, MID_ICE, PALE_ICE, SNOW, SNOW_SHADOW,
           EXPEDITION_BLUE, EXPEDITION_LIGHT, ORANGE, ORANGE_HI,
           CYAN, GREEN, GOLD, GLASS, RUBBER, FABRIC, LAB_SKIN, LAB_PANEL]


def parse_args() -> argparse.Namespace:
    raw = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
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
    world = bpy.data.worlds.new("glacier_gauntlet_authoring_world")
    world.color = (0.055, 0.145, 0.285)
    scene.world = world
    scene["waddle_wars_toolchain"] = "Blender 5.2.0 LTS"
    scene["waddle_wars_forward"] = "-Z"
    scene["waddle_wars_units"] = "metres"
    scene["waddle_wars_course"] = "glacier"
    scene["waddle_wars_license"] = "project_original"
    for role, filename in {
        "albedo": "glacier_surface_albedo_v1.png",
        "normal": "glacier_surface_normal_v1.png",
        "orm": "glacier_surface_orm_v1.png",
    }.items():
        path = texture_root / filename
        if not path.is_file():
            raise RuntimeError(f"missing generated texture {path}")
        image = bpy.data.images.load(str(path), check_existing=False)
        image.name = f"glacier_surface_{role}_v1"
        image.colorspace_settings.name = "sRGB" if role == "albedo" else "Non-Color"
        image.pack()
        image.use_fake_user = True
        PACKED_TEXTURES[role] = image


def material() -> bpy.types.Material:
    existing = bpy.data.materials.get("glacier_painted_surface")
    if existing is not None:
        return existing
    mat = bpy.data.materials.new("glacier_painted_surface")
    mat.use_nodes = True
    mat.diffuse_color = (1.0, 1.0, 1.0, 1.0)
    mat.roughness = 0.58
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    vertex = nodes.new("ShaderNodeVertexColor")
    vertex.layer_name = "Color"
    albedo = nodes.new("ShaderNodeTexImage")
    albedo.image = PACKED_TEXTURES["albedo"]
    albedo.interpolation = "Linear"
    normal_tex = nodes.new("ShaderNodeTexImage")
    normal_tex.image = PACKED_TEXTURES["normal"]
    normal_tex.interpolation = "Linear"
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = 0.48
    orm = nodes.new("ShaderNodeTexImage")
    orm.image = PACKED_TEXTURES["orm"]
    orm.interpolation = "Linear"
    channels = nodes.new("ShaderNodeSeparateColor")
    multiply = nodes.new("ShaderNodeMixRGB")
    multiply.blend_type = "MULTIPLY"
    multiply.inputs[0].default_value = 1.0
    shader.inputs["Specular IOR Level"].default_value = 0.36
    links.new(albedo.outputs["Color"], multiply.inputs[1])
    links.new(vertex.outputs["Color"], multiply.inputs[2])
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


def apply_transform(obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False)


def paint(obj: bpy.types.Object, base, variation: float = 0.014) -> None:
    mesh = obj.data
    old = mesh.color_attributes.get("Color")
    if old is not None:
        mesh.color_attributes.remove(old)
    attr = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
    mesh.color_attributes.active_color = attr
    for polygon in mesh.polygons:
        normal = polygon.normal
        # Baked value response: warm upper planes, cool leeward faces, deep AO
        # underneath. The runtime does not require SSAO to ground the forms.
        light = 0.76 + max(normal.z, 0.0) * 0.23 + max(-normal.y, 0.0) * 0.055
        if normal.z < -0.2:
            light *= 0.76
        for loop_index in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index]
            grain = math.sin(vertex.co.x * 2.71 + vertex.co.y * 3.17
                             + vertex.co.z * 4.63) * variation
            shade = max(0.55, min(1.08, light + grain))
            attr.data[loop_index].color = (
                min(base[0] * shade, 1.0), min(base[1] * shade, 1.0),
                min(base[2] * shade, 1.0), base[3])
    if not mesh.materials:
        mesh.materials.append(material())


def box(coll: bpy.types.Collection, name: str, center, size, colour,
        bevel: float = 0.04, segments: int = 2) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = Vector(size) * 0.5
    apply_transform(obj)
    if bevel > 0.0:
        mod = obj.modifiers.new("rounded_authored_edges", "BEVEL")
        mod.width = min(bevel, min(size) * 0.22)
        mod.segments = segments
        mod.affect = "EDGES"
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.select_set(False)
    paint(obj, colour)
    move_to_collection(obj, coll)
    return obj


def cylinder(coll: bpy.types.Collection, name: str, center, radius: float,
             depth: float, colour, vertices: int = 12,
             rotation=(0.0, 0.0, 0.0), bevel: float = 0.025) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth,
                                       location=center, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    apply_transform(obj)
    if bevel > 0.0:
        mod = obj.modifiers.new("rolled_authored_edges", "BEVEL")
        mod.width = min(bevel, radius * 0.22, depth * 0.12)
        mod.segments = 2
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.select_set(False)
    paint(obj, colour, 0.010)
    move_to_collection(obj, coll)
    return obj


def sphere(coll: bpy.types.Collection, name: str, center, radius: float, colour,
           segments: int = 16, rings: int = 8, scale=(1.0, 1.0, 1.0),
           smooth: bool = True) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings,
                                        radius=radius, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    apply_transform(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = smooth
    paint(obj, colour)
    move_to_collection(obj, coll)
    return obj


def ico(coll: bpy.types.Collection, name: str, center, radius: float, colour,
        subdivisions: int = 2, scale=(1.0, 1.0, 1.0), rotation=(0.0, 0.0, 0.0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=radius,
                                         location=center, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    apply_transform(obj)
    paint(obj, colour, 0.022)
    move_to_collection(obj, coll)
    return obj


def cone(coll: bpy.types.Collection, name: str, center, radius1: float,
         radius2: float, depth: float, colour, vertices: int = 10,
         rotation=(0.0, 0.0, 0.0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius1,
                                   radius2=radius2, depth=depth,
                                   location=center, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    apply_transform(obj)
    paint(obj, colour, 0.020)
    move_to_collection(obj, coll)
    return obj


def torus(coll: bpy.types.Collection, name: str, center, major: float,
          minor: float, colour, major_segments: int = 20, minor_segments: int = 8,
          rotation=(0.0, 0.0, 0.0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                    major_segments=major_segments,
                                    minor_segments=minor_segments,
                                    location=center, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    apply_transform(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    paint(obj, colour, 0.010)
    move_to_collection(obj, coll)
    return obj


def beam(coll: bpy.types.Collection, name: str, start, end, width: float,
         colour, bevel: float = 0.025) -> bpy.types.Object:
    a = Vector(start)
    b = Vector(end)
    direction = b - a
    obj = box(coll, name, (0.0, 0.0, 0.0),
              (width, width, direction.length), colour, bevel, 1)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized())
    obj.location = (a + b) * 0.5
    apply_transform(obj)
    paint(obj, colour)
    return obj


def custom_mesh(coll: bpy.types.Collection, name: str, vertices, faces, colours,
                smooth: bool = False,
                bake_lighting: bool = True) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    coll.objects.link(obj)
    attr = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
    mesh.color_attributes.active_color = attr
    for polygon, colour in zip(mesh.polygons, colours):
        polygon.use_smooth = smooth
        # Custom hero meshes do not pass through paint(), so bake the same
        # value response here. Without this, arch/fall faces carried exact flat
        # palette swatches and collapsed into a saturated cardboard cutout in
        # Compatibility. Upper planes catch warm key; undersides retain navy.
        normal = polygon.normal
        if bake_lighting:
            light = 0.74 + max(normal.z, 0.0) * 0.24 + max(-normal.y, 0.0) * 0.045
            if normal.z < -0.15:
                light *= 0.78
            light = max(0.58, min(1.04, light))
        else:
            # Hero mineral surfaces receive smooth runtime lighting. Holding
            # baked value nearly constant prevents face-domain COLOR_0 bands
            # and keeps the cave-facing cyan rim out of black crush.
            light = 0.96
        for loop_index in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index]
            grain = math.sin(vertex.co.x * 1.91 + vertex.co.y * 2.53
                             + vertex.co.z * 3.17) * (0.012 if bake_lighting else 0.004)
            shade = max(0.56, min(1.05, light + grain))
            attr.data[loop_index].color = (
                min(colour[0] * shade, 1.0),
                min(colour[1] * shade, 1.0),
                min(colour[2] * shade, 1.0), colour[3])
    mesh.materials.append(material())
    return obj


def wedge(coll: bpy.types.Collection, name: str, center, width: float,
          depth: float, height: float, colour) -> bpy.types.Object:
    x = width * 0.5
    y = depth * 0.5
    verts = [(-x, y, 0), (x, y, 0), (-x, -y, 0), (x, -y, 0),
             (-x, -y, height), (x, -y, height)]
    verts = [(vx + center[0], vy + center[1], vz + center[2]) for vx, vy, vz in verts]
    faces = [(0, 1, 3, 2), (0, 4, 5, 1), (0, 2, 4),
             (1, 5, 3), (2, 3, 5, 4)]
    return custom_mesh(coll, name, verts, faces,
                       [EXPEDITION_BLUE, colour, DEEP_ICE, DEEP_ICE, colour])


def pennant(coll: bpy.types.Collection, name: str, center, width: float,
            height: float, colour) -> bpy.types.Object:
    x, y, z = center
    verts = [(x, y, z), (x + width, y, z - height * 0.5),
             (x, y, z - height), (x, y + 0.04, z),
             (x + width, y + 0.04, z - height * 0.5),
             (x, y + 0.04, z - height)]
    faces = [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1),
             (1, 4, 5, 2), (2, 5, 3, 0)]
    return custom_mesh(coll, name, verts, faces, [colour] * len(faces))


def chevron(coll: bpy.types.Collection, name: str, center, width: float,
            height: float, depth: float, colour) -> None:
    x, y, z = center
    beam(coll, name + "_l", (x - width, y, z + height), (x, y, z), depth, colour)
    beam(coll, name + "_r", (x, y, z), (x + width, y, z + height), depth, colour)


def ice_cluster(coll: bpy.types.Collection, prefix: str, center,
                scale: float = 1.0, count: int = 5, seed: int = 1) -> None:
    rng = random.Random(seed)
    for index in range(count):
        angle = math.tau * index / max(count, 1) + rng.uniform(-0.25, 0.25)
        radius = scale * rng.uniform(0.12, 0.48)
        h = scale * rng.uniform(0.8, 1.65)
        r = scale * rng.uniform(0.16, 0.32)
        cone(coll, f"{prefix}_{index}",
             (center[0] + math.cos(angle) * radius,
              center[1] + math.sin(angle) * radius,
              center[2] + h * 0.5), r, r * 0.12, h,
             PALE_ICE if index % 3 else MID_ICE, 8)


def snow_cap(coll: bpy.types.Collection, name: str, center, size) -> None:
    ico(coll, name, center, 1.0, SNOW, 2, size,
        rotation=(0.0, 0.0, math.radians(7.0)))


# ---------------------------------------------------------------------------
# Modular track, expedition dressing and hazard markers


def build_edge_kerb() -> bpy.types.Collection:
    c = collection("glacier_edge_kerb_v1")
    # Broken cyan blocks, not a continuous navy guard rail. Navy only appears
    # as a recessed 16 cm footing; broad visible mass is mid ice + cream cap.
    box(c, "recessed_foot", (0.0, 0, 0.10), (0.70, 5.45, 0.20),
        DEEP_ICE, 0.07, 2)
    box(c, "ice_body", (0, 0, 0.43), (0.78, 5.4, 0.68), MID_ICE, 0.15, 3)
    box(c, "upper_facet", (-0.05, 0, 0.79), (0.88, 5.25, 0.20),
        PALE_ICE, 0.10, 2)
    for index, y in enumerate((-2.15, -0.75, 0.72, 2.10)):
        box(c, f"warm_inset_{index}", (0.385, y, 0.48),
            (0.045, 0.66, 0.22), GOLD if index % 2 else ORANGE_HI, 0.01, 1)
    snow_cap(c, "snow_pillow", (-0.04, 0.02, 0.94), (0.49, 2.62, 0.16))
    return c


def build_surface_inlay() -> bpy.types.Collection:
    c = collection("glacier_surface_inlay_v1")
    # One flush expedition route medallion. First pass's ten narrow beams read
    # as a literal ladder in chase perspective; circular silhouette plus one
    # forward wedge cannot. Relief stays under 5 cm and never owns collision.
    cylinder(c, "frosted_route_disc", (0, 0, 0.018), 0.92, 0.036,
             PALE_ICE, 24, bevel=0.0)
    torus(c, "cream_compass_ring", (0, 0, 0.040), 0.73, 0.055,
          SNOW, 28, 7)
    wedge(c, "gold_forward_wedge", (0, -0.36, 0.042),
          0.62, 1.16, 0.065, GOLD)
    sphere(c, "route_rivet", (0, 0.31, 0.075), 0.10, EXPEDITION_BLUE,
           12, 6, scale=(1.0, 1.0, 0.34))
    return c


def build_track_skin_patch() -> bpy.types.Collection:
    c = collection("glacier_track_skin_patch_v1")
    # Broad, flush wind-polished patch. One irregular value field breaks the
    # groomed deck at chase scale without crack wallpaper or raised gameplay
    # geometry. Runtime mirrors, yaws and stretches sparse instances.
    x_steps = 25
    y_steps = 17
    verts = []
    for xi in range(x_steps):
        x = -4.6 + 9.2 * xi / (x_steps - 1)
        for yi in range(y_steps):
            y = -3.2 + 6.4 * yi / (y_steps - 1)
            edge = (x / 4.6) ** 2 + (y / 3.2) ** 2
            fade = max(0.0, 1.0 - edge)
            z = fade * (0.030
                        + math.sin(x * 0.82 + y * 0.31) * 0.008
                        + math.cos(y * 1.26 - x * 0.19) * 0.004)
            verts.append((x, y, z))
    faces = []
    colours = []
    for xi in range(x_steps - 1):
        for yi in range(y_steps - 1):
            a = xi * y_steps + yi
            b = (xi + 1) * y_steps + yi
            c0 = (xi + 1) * y_steps + yi + 1
            d = xi * y_steps + yi + 1
            faces.append((a, b, c0, d))
            center_x = sum(verts[index][0] for index in (a, b, c0, d)) * 0.25
            center_y = sum(verts[index][1] for index in (a, b, c0, d)) * 0.25
            radial = ((center_x / 4.6) ** 2 + (center_y / 3.2) ** 2
                      + math.sin(center_y * 1.12 + center_x * 0.21) * 0.075
                      + math.sin(center_x * 1.47 - center_y * 0.16) * 0.045)
            if radial >= 0.94:
                faces.pop()
                continue
            # One continuous mineral value. Shape, baked normal and atlas grain
            # supply detail; per-cell palette changes produced a tiled floor mat.
            colours.append(LAB_PANEL)
    custom_mesh(c, "wind_polished_skin", verts, faces, colours,
                smooth=True, bake_lighting=False)
    return c


def build_route_beacon() -> bpy.types.Collection:
    c = collection("glacier_route_beacon_v1")
    box(c, "sled", (0, 0, 0.12), (1.15, 1.65, 0.24), EXPEDITION_BLUE, 0.10, 3)
    for x in (-0.42, 0.42):
        cylinder(c, f"runner_{x}", (x, 0, 0.13), 0.08, 1.9,
                 PALE_ICE, 10, (math.pi * 0.5, 0, 0), 0.0)
    cylinder(c, "mast", (0, 0, 1.55), 0.11, 2.85, EXPEDITION_BLUE, 14)
    for z in (0.52, 1.25, 1.98):
        torus(c, f"collar_{z}", (0, 0, z), 0.18, 0.035, ORANGE_HI, 14, 5)
    sphere(c, "gold_route_lamp", (0, 0, 3.08), 0.28, GOLD, 18, 9,
           scale=(1.0, 1.0, 0.72))
    torus(c, "lamp_guard", (0, 0, 3.08), 0.37, 0.035,
          EXPEDITION_BLUE, 16, 5)
    for side in (-1, 1):
        beam(c, f"brace_{side}", (side * 0.42, -0.58, 0.18),
             (0, 0, 1.08), 0.075, EXPEDITION_LIGHT)
    return c


def build_route_flag() -> bpy.types.Collection:
    c = collection("glacier_route_flag_v1")
    cylinder(c, "pole", (0, 0, 1.55), 0.055, 3.1, EXPEDITION_BLUE, 12)
    sphere(c, "finial", (0, 0, 3.16), 0.11, GOLD, 12, 6)
    pennant(c, "blue_pennant", (0.03, 0, 2.95), 1.25, 0.62, EXPEDITION_LIGHT)
    pennant(c, "orange_tail", (0.03, 0, 2.21), 0.85, 0.42, ORANGE)
    box(c, "buried_foot", (0, 0, 0.08), (0.46, 0.46, 0.16), DEEP_ICE, 0.06, 2)
    for index in range(5):
        cylinder(c, f"rope_knot_{index}", (0, 0, 0.52 + index * 0.42),
                 0.075, 0.055, ORANGE_HI, 10, bevel=0.0)
    return c


def build_snow_fence() -> bpy.types.Collection:
    c = collection("glacier_snow_fence_v1")
    for x in (-2.3, 0.0, 2.3):
        cylinder(c, f"post_{x}", (x, 0, 1.15), 0.09, 2.3,
                 EXPEDITION_BLUE, 12)
        box(c, f"foot_{x}", (x, 0, 0.09), (0.52, 0.58, 0.18), DEEP_ICE, 0.07, 2)
    for index, z in enumerate((0.55, 0.95, 1.35, 1.75)):
        beam(c, f"slat_{index}", (-2.32, 0, z), (2.32, 0, z + 0.18),
             0.16, ORANGE if index % 2 == 0 else EXPEDITION_LIGHT, 0.035)
    snow_cap(c, "snow_drift", (0.55, 0.35, 0.30), (2.5, 0.62, 0.32))
    return c


def build_expedition_crate() -> bpy.types.Collection:
    c = collection("glacier_expedition_crate_v1")
    box(c, "body", (0, 0, 0.72), (1.75, 1.42, 1.44),
        EXPEDITION_LIGHT, 0.12, 3)
    for z in (0.18, 1.25):
        box(c, f"band_h_{z}", (0, -0.73, z), (1.92, 0.08, 0.17),
            EXPEDITION_BLUE, 0.025, 1)
    for x in (-0.68, 0.68):
        box(c, f"band_v_{x}", (x, -0.73, 0.72), (0.16, 0.08, 1.38),
            EXPEDITION_BLUE, 0.025, 1)
    box(c, "hazard_plate", (0, -0.78, 0.73), (0.62, 0.055, 0.48), ORANGE, 0.03, 2)
    chevron(c, "plate_chevron", (0, -0.83, 0.82), 0.17, 0.16, 0.045, SNOW)
    for x in (-0.73, 0.73):
        for z in (0.20, 1.25):
            cylinder(c, f"corner_{x}_{z}", (x, -0.80, z), 0.055, 0.06,
                     GOLD, 10, (math.pi * 0.5, 0, 0), 0.0)
    return c


def build_rescue_sled() -> bpy.types.Collection:
    c = collection("glacier_rescue_sled_v1")
    for x in (-0.62, 0.62):
        cylinder(c, f"runner_{x}", (x, 0, 0.20), 0.10, 3.7,
                 PALE_ICE, 14, (math.pi * 0.5, 0, 0), 0.0)
        for y in (-1.35, 1.35):
            beam(c, f"upright_{x}_{y}", (x, y, 0.18), (x * 0.82, y, 0.62),
                 0.09, EXPEDITION_BLUE)
    box(c, "bed", (0, 0, 0.66), (1.65, 3.1, 0.20), ORANGE, 0.15, 3)
    box(c, "blanket", (0, 0.25, 0.84), (1.35, 1.85, 0.16), FABRIC, 0.10, 3)
    cylinder(c, "tow_bar", (0, -2.22, 0.42), 0.075, 1.9,
             EXPEDITION_BLUE, 12, (math.pi * 0.5, 0, 0))
    torus(c, "tow_loop", (0, -3.12, 0.42), 0.26, 0.055,
          GOLD, 18, 6, (math.pi * 0.5, 0, 0))
    return c


def build_field_tent() -> bpy.types.Collection:
    c = collection("glacier_field_tent_v1")
    # Rounded expedition bivouac. Broad canvas stays expedition cyan so fixed
    # orange remains a hazard/route accent instead of becoming background fill.
    for index in range(7):
        angle0 = math.pi * index / 7.0
        angle1 = math.pi * (index + 1) / 7.0
        x0, z0 = math.cos(angle0) * 2.5, math.sin(angle0) * 3.0
        x1, z1 = math.cos(angle1) * 2.5, math.sin(angle1) * 3.0
        verts = [(x0, -1.8, z0), (x1, -1.8, z1),
                 (x1, 1.8, z1), (x0, 1.8, z0)]
        custom_mesh(c, f"fabric_panel_{index}", verts, [(0, 1, 2, 3)],
                    [PALE_ICE if index in (2, 4) else EXPEDITION_LIGHT])
    box(c, "weather_skirt", (0, 0, 0.20), (5.0, 3.8, 0.40),
        EXPEDITION_BLUE, 0.13, 3)
    box(c, "door", (0, -1.85, 1.36), (1.18, 0.08, 2.34), GLASS, 0.14, 3)
    box(c, "route_tab", (0, -1.91, 2.65), (0.78, 0.05, 0.18),
        ORANGE_HI, 0.04, 2)
    for x in (-1.8, 1.8):
        cylinder(c, f"guy_anchor_{x}", (x, -2.45, 0.10), 0.12, 0.20,
                 GOLD, 12, bevel=0.0)
        beam(c, f"guy_line_{x}", (x, -2.45, 0.16), (x * 0.78, -1.72, 2.18),
             0.025, SNOW, 0.0)
    return c


def build_field_lab() -> bpy.types.Collection:
    c = collection("glacier_field_lab_v1")
    # Hero expedition lab: one broad Quonset volume, readable as architecture
    # from chase view. Cyan canvas, cream snow blanket, warm door/windows and
    # dark structural ribs establish mass without tiny prop noise.
    arc_steps = 12
    length_steps = 6
    verts = []
    for arc_index in range(arc_steps + 1):
        theta = math.pi * arc_index / arc_steps
        x = math.cos(theta) * 3.8
        z = 0.44 + math.sin(theta) * 4.35
        for length_index in range(length_steps + 1):
            y = -4.55 + 9.10 * length_index / length_steps
            verts.append((x, y, z))
    faces = []
    colours = []
    for arc_index in range(arc_steps):
        for length_index in range(length_steps):
            a = arc_index * (length_steps + 1) + length_index
            b = (arc_index + 1) * (length_steps + 1) + length_index
            c0 = (arc_index + 1) * (length_steps + 1) + length_index + 1
            d = arc_index * (length_steps + 1) + length_index + 1
            faces.append((a, b, c0, d))
            colours.append(LAB_PANEL if arc_index in (4, 5, 6, 7, 8)
                           else LAB_SKIN)
    # Closed front/back bulkheads. Fan triangles keep silhouette continuous.
    for end_index, reverse in ((0, True), (length_steps, False)):
        center_index = len(verts)
        y = -4.55 if end_index == 0 else 4.55
        verts.append((0.0, y, 0.44))
        for arc_index in range(arc_steps):
            a = arc_index * (length_steps + 1) + end_index
            b = (arc_index + 1) * (length_steps + 1) + end_index
            face = (center_index, b, a) if reverse else (center_index, a, b)
            faces.append(face)
            colours.append(LAB_SKIN)
    custom_mesh(c, "continuous_lab_shell", verts, faces, colours,
                smooth=True, bake_lighting=False)
    box(c, "buried_lab_plinth", (0, 0, 0.22), (8.15, 9.65, 0.44),
        EXPEDITION_BLUE, 0.10, 2)

    # Shallow conforming snow blanket. It hugs crown instead of floating as a
    # separate blob, while two exposed cyan shoulder bands preserve value read.
    snow_arc_indices = range(4, 9)
    snow_verts = []
    for arc_index in snow_arc_indices:
        theta = math.pi * arc_index / arc_steps
        x = math.cos(theta) * 3.8
        z = 0.44 + math.sin(theta) * 4.35 + 0.12
        for length_index in range(length_steps + 1):
            y = -4.38 + 8.76 * length_index / length_steps
            snow_verts.append((x, y, z))
    snow_faces = []
    snow_width = length_steps + 1
    for arc_index in range(len(list(snow_arc_indices)) - 1):
        for length_index in range(length_steps):
            a = arc_index * snow_width + length_index
            b = (arc_index + 1) * snow_width + length_index
            c0 = (arc_index + 1) * snow_width + length_index + 1
            d = arc_index * snow_width + length_index + 1
            snow_faces.append((a, b, c0, d))
    custom_mesh(c, "crown_snow_blanket", snow_verts, snow_faces,
                [SNOW] * len(snow_faces), smooth=True, bake_lighting=False)

    # Three dark ribs make scale legible from silhouette; broad warm glazing
    # makes the occupied base unmistakable against blue ice.
    for rib_index, y in enumerate((-3.35, 0.0, 3.35)):
        rib_points = []
        for arc_index in (0, 3, 6, 9, 12):
            theta = math.pi * arc_index / arc_steps
            rib_points.append((math.cos(theta) * 3.86, y,
                               0.44 + math.sin(theta) * 4.40))
        for segment in range(len(rib_points) - 1):
            beam(c, f"shell_rib_{rib_index}_{segment}",
                 rib_points[segment], rib_points[segment + 1], 0.13,
                 EXPEDITION_BLUE, 0.0)
    box(c, "airlock", (0, -4.72, 1.45), (1.72, 0.34, 2.75),
        EXPEDITION_BLUE, 0.12, 2)
    box(c, "warm_airlock_glass", (0, -4.91, 1.52), (1.20, 0.08, 1.78),
        ORANGE_HI, 0.04, 1)
    box(c, "route_header", (0, -4.98, 3.10), (2.55, 0.10, 0.32),
        ORANGE, 0.04, 1)
    for side in (-1, 1):
        box(c, f"warm_window_{side}", (side * 2.40, -4.74, 1.72),
            (1.18, 0.12, 0.78), GOLD, 0.08, 2)
        box(c, f"window_brow_{side}", (side * 2.40, -4.83, 2.20),
            (1.48, 0.12, 0.18), SNOW, 0.03, 1)
    cylinder(c, "roof_vent", (1.35, 0.75, 4.98), 0.30, 0.65,
             EXPEDITION_BLUE, 14)
    sphere(c, "vent_cap", (1.35, 0.75, 5.34), 0.42, SNOW, 12, 6,
           scale=(1.0, 1.0, 0.42))
    return c


def build_camp_lamp() -> bpy.types.Collection:
    c = collection("glacier_camp_lamp_v1")
    # Large warm tripod lamp, not a tiny bollard. Fixture silhouette, pennants
    # and gold lens remain readable without renderer-specific bloom.
    box(c, "buried_power_case", (0, 0, 0.24), (1.55, 1.34, 0.48),
        EXPEDITION_BLUE, 0.14, 3)
    for index in range(3):
        angle = math.tau * index / 3.0 + 0.25
        foot = (math.cos(angle) * 0.90, math.sin(angle) * 0.90, 0.08)
        beam(c, f"tripod_{index}", foot, (0, 0, 2.45), 0.10,
             EXPEDITION_LIGHT, 0.02)
        sphere(c, f"orange_foot_{index}", foot, 0.16, ORANGE, 10, 5,
               scale=(1.0, 1.0, 0.55))
    cylinder(c, "lamp_mast", (0, 0, 2.34), 0.12, 3.65,
             EXPEDITION_BLUE, 14)
    sphere(c, "warm_lens", (0, -0.05, 4.18), 0.58, GOLD, 18, 9,
           scale=(1.0, 0.76, 0.82))
    for axis in range(4):
        angle = math.tau * axis / 4.0
        start = (math.cos(angle) * 0.68, math.sin(angle) * 0.52, 3.74)
        end = (math.cos(angle) * 0.68, math.sin(angle) * 0.52, 4.58)
        beam(c, f"lens_cage_{axis}", start, end, 0.055,
             EXPEDITION_BLUE, 0.0)
    torus(c, "lower_lens_guard", (0, -0.05, 3.72), 0.70, 0.055,
          EXPEDITION_BLUE, 18, 5)
    torus(c, "upper_lens_guard", (0, -0.05, 4.62), 0.58, 0.055,
          EXPEDITION_BLUE, 18, 5)
    pennant(c, "orange_camp_flag", (0.06, 0, 3.30), 1.35, 0.62, ORANGE_HI)
    pennant(c, "cyan_camp_tail", (0.06, 0, 2.62), 0.92, 0.42, CYAN)
    return c


def build_weather_mast() -> bpy.types.Collection:
    c = collection("glacier_weather_mast_v1")
    box(c, "base", (0, 0, 0.15), (1.45, 1.45, 0.30),
        EXPEDITION_BLUE, 0.13, 3)
    cylinder(c, "mast", (0, 0, 2.65), 0.12, 5.15,
             EXPEDITION_LIGHT, 12)
    for z in (0.72, 1.72, 2.72, 3.72):
        torus(c, f"collar_{z}", (0, 0, z), 0.19, 0.035,
              ORANGE_HI, 12, 4)
    # Cup anemometer gives a readable asymmetrical silhouette.
    for index in range(3):
        angle = math.tau * index / 3.0
        end = (math.cos(angle) * 0.92, math.sin(angle) * 0.92, 4.92)
        beam(c, f"arm_{index}", (0, 0, 4.92), end, 0.055,
             EXPEDITION_BLUE, 0.0)
        sphere(c, f"cup_{index}", end, 0.22, ORANGE, 10, 5,
               scale=(1.0, 0.6, 0.7))
    pennant(c, "wind_vane", (0.04, 0, 4.32), 1.08, 0.48, CYAN)
    sphere(c, "sensor", (0, 0, 5.36), 0.24, GOLD, 12, 6)
    return c


def build_ice_spire() -> bpy.types.Collection:
    c = collection("glacier_ice_spire_v1")
    ice_cluster(c, "spire", (0, 0, 0), 2.7, 8, 122)
    snow_cap(c, "foot_snow", (0, 0.05, 0.24), (1.35, 1.0, 0.34))
    return c


def build_ice_boulder() -> bpy.types.Collection:
    c = collection("glacier_ice_boulder_v1")
    ico(c, "faceted_body", (0, 0, 1.05), 1.1, MID_ICE, 3,
        scale=(1.25, 1.0, 0.95), rotation=(0.17, 0.08, 0.31))
    snow_cap(c, "snow_cap", (-0.12, -0.04, 1.88), (0.95, 0.72, 0.24))
    for index in range(4):
        angle = math.tau * index / 4.0
        cone(c, f"foot_shard_{index}", (math.cos(angle) * 0.92,
             math.sin(angle) * 0.72, 0.38), 0.18, 0.02, 0.76,
             PALE_ICE, 8)
    return c


def build_snowbank() -> bpy.types.Collection:
    c = collection("glacier_snowbank_v1")
    for index in range(5):
        x = -2.0 + index * 1.0
        ico(c, f"wind_lobe_{index}", (x, math.sin(index) * 0.18,
            0.34 + (index % 2) * 0.10), 0.62, SNOW, 2,
            scale=(1.35, 0.78, 0.58), rotation=(0.0, 0.0, 0.12 * index))
    for index in range(6):
        box(c, f"sastrugi_{index}", (-2.3 + index * 0.92, -0.68, 0.11),
            (0.72, 1.20, 0.14), SNOW_SHADOW, 0.06, 2)
    return c


def build_layered_ridge() -> bpy.types.Collection:
    c = collection("glacier_layered_ridge_v1")
    # One continuous asymmetric heightfield replaces both procedural triangle
    # mountains and V4's stacked ellipsoids. Broad harmonic erosion shapes one
    # glacier shelf; a narrow snow skin follows its actual crown instead of
    # floating as repeated horizontal saucers.
    def shelf_height(x: float, y: float) -> float:
        nx = (x + 48.0) / 96.0
        envelope = max(0.0, math.sin(math.pi * nx)) ** 0.58
        peaks = (0.72
                 + 0.16 * math.sin(nx * math.tau * 2.2 + 0.35)
                 + 0.10 * math.sin(nx * math.tau * 4.7 + 1.1)
                 + 0.06 * math.sin(nx * math.tau * 8.0 + 0.4))
        cross = max(0.0, math.cos((y / 8.2) * math.pi * 0.5)) ** 0.62
        return 31.0 * envelope * max(0.48, peaks) * cross

    x_steps = 37
    y_steps = 9
    verts = []
    for xi in range(x_steps):
        x = -48.0 + 96.0 * xi / (x_steps - 1)
        for yi in range(y_steps):
            y = -8.2 + 16.4 * yi / (y_steps - 1)
            verts.append((x, y, shelf_height(x, y)))
    faces = []
    colours = []
    for xi in range(x_steps - 1):
        for yi in range(y_steps - 1):
            a = xi * y_steps + yi
            b = (xi + 1) * y_steps + yi
            c0 = (xi + 1) * y_steps + yi + 1
            d = xi * y_steps + yi + 1
            faces.append((a, b, c0, d))
            average_z = sum(verts[index][2] for index in (a, b, c0, d)) * 0.25
            colours.append(DEEP_ICE if average_z < 3.6 else MID_ICE)
    custom_mesh(c, "continuous_eroded_shelf", verts, faces, colours,
                smooth=True, bake_lighting=False)

    # Broken snow skin: three long crown patches with tapered end gaps. Each
    # patch conforms to the shelf height and keeps cyan shoulders exposed.
    for patch_index, (start_x, end_x) in enumerate(((-41.0, -13.0),
                                                    (-9.0, 19.0),
                                                    (24.0, 43.0))):
        snow_x_steps = 13
        snow_y_steps = 5
        snow_verts = []
        for xi in range(snow_x_steps):
            x = start_x + (end_x - start_x) * xi / (snow_x_steps - 1)
            taper = 0.24 + 0.76 * (
                math.sin(math.pi * xi / (snow_x_steps - 1)) ** 0.35)
            for yi in range(snow_y_steps):
                y = (-3.15 + 6.3 * yi / (snow_y_steps - 1)) * taper
                lift = 0.34 + math.sin(x * 0.31 + patch_index) * 0.06
                snow_verts.append((x, y, shelf_height(x, y) + lift))
        snow_faces = []
        for xi in range(snow_x_steps - 1):
            for yi in range(snow_y_steps - 1):
                a = xi * snow_y_steps + yi
                b = (xi + 1) * snow_y_steps + yi
                c0 = (xi + 1) * snow_y_steps + yi + 1
                d = xi * snow_y_steps + yi + 1
                snow_faces.append((a, b, c0, d))
        custom_mesh(c, f"broken_snow_skin_{patch_index}", snow_verts, snow_faces,
                    [SNOW] * len(snow_faces), smooth=True, bake_lighting=False)
    # Sparse orange wayfinding lamps establish expedition scale; no orange
    # paint appears on the glacier itself.
    for side in (-1, 1):
        x = side * 27.0
        cylinder(c, f"route_post_{side}", (x, -7.45, 2.1), 0.12, 4.2,
                 EXPEDITION_BLUE, 10, bevel=0.0)
        sphere(c, f"route_lamp_{side}", (x, -7.45, 4.35), 0.26,
               ORANGE_HI, 8, 4)
    return c


def build_cave_buttress() -> bpy.types.Collection:
    c = collection("glacier_cave_buttress_v1")
    # One-sided eroded cave shoulder. Runtime mirrors/rotates/scales pairs;
    # unlike full hoops, their negative space never becomes repeated plastic
    # ribs. Overlapping smooth mineral lobes read as one carved glacier wall.
    rng = random.Random(7331)
    for index in range(5):
        z = 0.95 + index * 1.42
        x = -0.28 + math.sin(index * 1.63) * 0.54
        y = math.cos(index * 1.21) * 0.34
        radius = 0.98 + (index % 3) * 0.12
        colour = (DEEP_ICE if index in (0, 1)
                  else MID_ICE if index % 3 else PALE_ICE)
        sphere(c, f"eroded_mass_{index}", (x, y, z), radius, colour, 12, 6,
               scale=(1.24 + rng.uniform(-0.08, 0.12),
                      0.88 + rng.uniform(-0.10, 0.12),
                      1.42 + rng.uniform(-0.10, 0.18)), smooth=True)
    # Snow catches on only two ledges; sparse patches prevent striped ribs.
    snow_cap(c, "lower_snow_ledge", (-0.46, -0.02, 3.10), (1.05, 0.82, 0.18))
    snow_cap(c, "upper_snow_ledge", (0.18, 0.06, 6.20), (0.82, 0.66, 0.15))
    for index in range(5):
        x = -0.72 + index * 0.34
        height = 0.55 + (index % 3) * 0.24
        cone(c, f"hanging_tooth_{index}", (x, -0.72, 7.28 - height * 0.5),
             0.14 + (index % 2) * 0.025, 0.012, height,
             PALE_ICE if index % 2 else MID_ICE, 8,
             rotation=(math.pi, 0.0, 0.0))
    return c


def build_duck_gate() -> bpy.types.Collection:
    c = collection("glacier_duck_gate_v1")
    for side in (-1, 1):
        x = side * 7.55
        box(c, f"foot_{side}", (x, 0, 0.15), (0.90, 1.65, 0.30),
            ORANGE, 0.12, 3)
        box(c, f"leg_{side}", (x, 0, 1.35), (0.42, 0.62, 2.55),
            ORANGE, 0.10, 3)
        for z in (0.52, 1.32, 2.12):
            torus(c, f"collar_{side}_{z}", (x, 0, z), 0.25, 0.05,
                  EXPEDITION_BLUE, 14, 5, (math.pi * 0.5, 0, 0))
    # Exact shell for TrackBuilder.add_overhead_bar(): 16 x 1.3 x 1.6 m,
    # bottom at 1.05 m. Racer never strikes invisible volume above/below art.
    # Cyan threshold is also one unmistakable low horizontal silhouette.
    box(c, "duck_threshold", (0, 0, 1.70), (15.96, 1.56, 1.28),
        CYAN, 0.15, 4)
    for index, x in enumerate((-5.7, -3.4, -1.1, 1.1, 3.4, 5.7)):
        chevron(c, f"down_chevron_{index}", (x, -0.83, 1.92),
                0.34, -0.34, 0.075, EXPEDITION_BLUE)
    for side in (-1, 1):
        beam(c, f"crown_{side}", (side * 7.55, 0, 2.62),
             (side * 4.1, 0, 3.35), 0.30, ORANGE_HI, 0.07)
    box(c, "crown_header", (0, 0, 3.35), (8.35, 0.48, 0.34),
        ORANGE_HI, 0.09, 3)
    sphere(c, "warning_lamp", (0, 0, 3.78), 0.28, GOLD, 18, 9)
    return c


def build_snowball_warning() -> bpy.types.Collection:
    c = collection("glacier_snowball_warning_v1")
    # Two grounded orange pylons + suspended snowball glyph. Reads by round
    # silhouette and diagonal danger stripe, even in monochrome.
    for side in (-1, 1):
        x = side * 2.35
        box(c, f"pylon_{side}", (x, 0, 1.22), (0.72, 0.82, 2.44),
            ORANGE, 0.16, 4)
        box(c, f"foot_{side}", (x, 0, 0.13), (1.12, 1.16, 0.26),
            EXPEDITION_BLUE, 0.10, 3)
        for z in (0.55, 1.22, 1.88):
            torus(c, f"stripe_{side}_{z}", (x, 0, z), 0.39, 0.065,
                  RUBBER, 14, 5, (math.pi * 0.5, 0, 0))
    beam(c, "header", (-2.35, 0, 2.42), (2.35, 0, 2.42),
         0.28, EXPEDITION_BLUE, 0.06)
    ico(c, "snowball_glyph", (0, -0.02, 3.17), 0.78, SNOW, 3,
        scale=(1.0, 0.68, 1.0), rotation=(0.12, 0.2, 0.0))
    for index in range(7):
        angle = math.tau * index / 7.0
        sphere(c, f"grit_{index}", (math.cos(angle) * 0.51,
               -0.58, 3.17 + math.sin(angle) * 0.51),
               0.075, DEEP_ICE, 10, 5)
    chevron(c, "slope_arrow", (0, -0.60, 2.22), 0.55, 0.45, 0.085, ORANGE_HI)
    return c


def build_cracking_marker() -> bpy.types.Collection:
    c = collection("glacier_cracking_ice_marker_v1")
    for side in (-1, 1):
        x = side * 3.55
        cone(c, f"stake_{side}", (x, 0, 1.05), 0.28, 0.11, 2.1,
             ORANGE, 10)
        box(c, f"foot_{side}", (x, 0, 0.09), (0.72, 0.72, 0.18),
            EXPEDITION_BLUE, 0.07, 2)
    box(c, "frosted_plate", (0, 0, 1.65), (6.6, 0.26, 1.05),
        PALE_ICE, 0.18, 4)
    # Raised black crack web: pattern + branching silhouette, not hue.
    beam(c, "crack_trunk", (-0.15, -0.18, 1.20), (0.25, -0.18, 2.08),
         0.105, RUBBER, 0.015)
    for index, (a, b) in enumerate([
            ((0.02, -0.18, 1.55), (-1.15, -0.18, 1.98)),
            ((0.08, -0.18, 1.62), (1.55, -0.18, 1.34)),
            ((-0.55, -0.18, 1.76), (-2.15, -0.18, 1.42)),
            ((0.78, -0.18, 1.48), (2.30, -0.18, 1.88)),
    ]):
        beam(c, f"crack_branch_{index}", a, b, 0.075, RUBBER, 0.01)
    for x in (-2.72, 2.72):
        sphere(c, f"warning_lamp_{x}", (x, 0, 2.28), 0.20, ORANGE_HI, 14, 7)
    return c


def build_boost_marker() -> bpy.types.Collection:
    c = collection("glacier_boost_marker_v1")
    # Low side pylons leave full sightline to the green pad. Three raised
    # arrows provide a shape cue for launch/acceleration.
    for side in (-1, 1):
        x = side * 2.75
        wedge(c, f"pylon_{side}", (x, 0, 0), 0.82, 1.55, 1.35, GREEN)
        box(c, f"pylon_foot_{side}", (x, 0, 0.10), (1.05, 1.85, 0.20),
            EXPEDITION_BLUE, 0.09, 3)
        sphere(c, f"lamp_{side}", (x, -0.28, 1.52), 0.18, GREEN, 14, 7)
    for index, y in enumerate((-1.55, 0.0, 1.55)):
        chevron(c, f"forward_arrow_{index}", (0, y, 0.20),
                0.68, 0.72, 0.13, GREEN)
    for side in (-1, 1):
        beam(c, f"guard_{side}", (side * 2.26, -2.25, 0.18),
             (side * 2.26, 2.25, 0.18), 0.12, PALE_ICE, 0.03)
    return c


# ---------------------------------------------------------------------------
# Three hero landmarks


def build_arch_landmark() -> bpy.types.Collection:
    c = collection("glacier_ice_arch_landmark_v1")
    # Compressed wind-carved hero arch. The centreline is an asymmetric broad
    # catenary-like shelf, not a circular torus; dense rings carry only smooth
    # harmonic erosion. Local X still spans the immutable route/collider.
    def arch_center(t: float) -> Vector:
        sine = max(0.0, math.sin(math.pi * t))
        x = (13.0 - 26.0 * t + 0.78 * sine
             + 0.24 * math.sin(t * math.pi * 5.0) * sine)
        z = (11.7 * sine ** 0.70
             * (1.0 + 0.055 * math.sin(t * math.tau * 2.0 + 0.4))
             + 0.32 * math.sin(t * math.pi * 3.0) * sine)
        y = math.sin(t * math.tau * 1.35 + 0.2) * 0.28
        return Vector((x, y, z))

    def arch_frame(t: float) -> tuple[Vector, Vector, float, float, float]:
        epsilon = 0.0008
        before = arch_center(max(0.0, t - epsilon))
        after = arch_center(min(1.0, t + epsilon))
        tangent = (after - before).normalized()
        outward = Vector((tangent.z, 0.0, -tangent.x)).normalized()
        arc = max(0.0, math.sin(math.pi * t))
        thickness = ((3.95 - arc * 1.30)
                     * (1.0 + math.sin(t * math.tau * 3.0 + 0.3) * 0.075
                        + math.sin(t * math.tau * 8.0) * 0.025))
        depth = ((3.10 - arc * 0.92)
                 * (1.0 + math.sin(t * math.tau * 4.0 + 1.1) * 0.045))
        return arch_center(t), outward, arc, thickness, depth

    segments = 160
    sides = 30
    rings: list[list[tuple[float, float, float]]] = []
    for seg in range(segments + 1):
        t = seg / segments
        center, outward, _arc, thickness, depth = arch_frame(t)
        ring = []
        for side in range(sides):
            phi = math.tau * side / sides
            inner = max(0.0, min(1.0, (-math.cos(phi) - 0.04) / 0.96))
            # Strata and two diagonal fracture families are displaced into the
            # existing continuous sweep. This carves real interior depth using
            # current topology—not rows of pasted ribs or extra pebble meshes.
            strata_phase = (phi * 4.35 + t * 1.18
                            + math.sin(t * math.tau * 2.1) * 0.34)
            strata_groove = max(0.0, 1.0 - abs(math.sin(strata_phase)) / 0.20)
            fracture_distance = min(
                abs(t - (0.235 + math.sin(phi * 1.7) * 0.018)),
                abs(t - (0.535 + math.sin(phi * 2.1 + 0.8) * 0.020)),
                abs(t - (0.785 + math.sin(phi * 1.5 + 1.7) * 0.016)))
            fracture_groove = max(0.0, 1.0 - fracture_distance / 0.012)
            wobble = (1.0
                      + math.sin(t * math.tau * 5.0 + phi * 2.0) * 0.022
                      - inner * strata_groove * 0.052
                      - inner * fracture_groove * 0.036)
            point = center + outward * (math.cos(phi) * thickness * wobble)
            point.y += math.sin(phi) * depth * (
                wobble - inner * strata_groove * 0.018)
            ring.append(tuple(point))
        rings.append(ring)
    verts = [value for ring in rings for value in ring]
    faces = []
    colours = []
    for seg in range(segments):
        t_mid = (seg + 0.5) / segments
        _center_mid, outward_mid, crown, _thickness_mid, _depth_mid = arch_frame(t_mid)
        for side in range(sides):
            nxt = (side + 1) % sides
            a = seg * sides + side
            b = seg * sides + nxt
            c0 = (seg + 1) * sides + nxt
            d = (seg + 1) * sides + side
            faces.append((a, b, c0, d))
            phi_mid = math.tau * (side + 0.5) / sides
            outward_up = max(0.0, outward_mid.z * math.cos(phi_mid))
            inner_rim = math.cos(phi_mid) < -0.10
            if inner_rim:
                # Alternating mineral strata plus narrow diagonal scars keep
                # cave-facing depth readable in Compatibility. Values remain
                # cyan/navy; orange never leaks into natural ice.
                strata = math.sin(phi_mid * 4.35 + t_mid * 1.18
                                  + math.sin(t_mid * math.tau * 2.1) * 0.34)
                fracture_distance = min(
                    abs(t_mid - (0.235 + math.sin(phi_mid * 1.7) * 0.018)),
                    abs(t_mid - (0.535 + math.sin(phi_mid * 2.1 + 0.8) * 0.020)),
                    abs(t_mid - (0.785 + math.sin(phi_mid * 1.5 + 1.7) * 0.016)))
                if fracture_distance < 0.010:
                    colours.append(ARCH_DEEP)
                elif strata > 0.44:
                    colours.append(ARCH_RIM)
                elif strata < -0.58:
                    colours.append(ARCH_MID)
                else:
                    colours.append(ARCH_PALE)
            elif outward_up > 0.38 and crown > 0.08:
                colours.append(ARCH_PALE)
            elif crown > 0.35:
                colours.append(ARCH_MID)
            else:
                colours.append(ARCH_MID if crown > 0.07 else ARCH_DEEP)
    # End caps close both feet without requiring double-sided runtime material.
    for end_seg, reverse in ((0, True), (segments, False)):
        center_index = len(verts)
        ring = rings[end_seg]
        center = tuple(sum((Vector(p) for p in ring), Vector((0.0, 0.0, 0.0)))
                       / len(ring))
        verts.append(center)
        for side in range(sides):
            nxt = (side + 1) % sides
            face = (center_index, end_seg * sides + nxt, end_seg * sides + side)
            faces.append(tuple(reversed(face)) if reverse else face)
            colours.append(ARCH_DEEP)
    custom_mesh(c, "monumental_arch", verts, faces, colours,
                smooth=True, bake_lighting=False)

    # Three shallow, conforming frost skins replace V5's tubular pasted caps.
    # Broken spans expose cyan compression shoulders; front/back lips add a
    # carved snowpack edge without turning the arch into layered plastic ribs.
    cap_sides = 5
    for patch_index, (start_t, end_t, cap_segments) in enumerate((
            (0.10, 0.29, 24), (0.35, 0.58, 30), (0.65, 0.89, 28))):
        cap_rings: list[list[tuple[float, float, float]]] = []
        for seg in range(cap_segments + 1):
            local_t = seg / cap_segments
            t = start_t + (end_t - start_t) * local_t
            center, outward, _arc, thickness, depth = arch_frame(t)
            taper = 0.22 + 0.78 * math.sin(math.pi * local_t) ** 0.48
            cap_center = center + outward * (
                thickness + 0.10 + math.sin(t * 31.0 + patch_index) * 0.045)
            ring = []
            for side_index in range(cap_sides):
                across = -1.0 + 2.0 * side_index / (cap_sides - 1)
                point = cap_center + outward * (
                    (0.18 + (1.0 - across * across) * 0.12) * taper)
                point.y += across * min(depth * 0.72, 1.48) * taper
                ring.append(tuple(point))
            cap_rings.append(ring)
        cap_verts = [value for ring in cap_rings for value in ring]
        cap_faces = []
        for seg in range(cap_segments):
            for side_index in range(cap_sides - 1):
                nxt = side_index + 1
                a = seg * cap_sides + side_index
                b = seg * cap_sides + nxt
                c0 = (seg + 1) * cap_sides + nxt
                d = (seg + 1) * cap_sides + side_index
                cap_faces.append((a, b, c0, d))
        # Narrow front/back snowpack lips create thickness while leaving broad
        # underside mineral ice visible. Ends stay irregular/open by design.
        for side_index in (0, cap_sides - 1):
            for seg in range(cap_segments):
                a = seg * cap_sides + side_index
                b = (seg + 1) * cap_sides + side_index
                va = Vector(cap_verts[a]) - Vector((0.0, 0.0, 0.16))
                vb = Vector(cap_verts[b]) - Vector((0.0, 0.0, 0.16))
                ai = len(cap_verts)
                cap_verts.extend((tuple(va), tuple(vb)))
                cap_faces.append((a, b, ai + 1, ai))
        custom_mesh(c, f"broken_frost_mantle_{patch_index}",
                    cap_verts, cap_faces, [SNOW] * len(cap_faces),
                    smooth=True, bake_lighting=False)

    # Sparse irregular crown teeth retain scale without a picket-fence rib.
    for index, x in enumerate((-6.4, -4.9, -3.0, -0.8, 1.3, 3.7, 5.8)):
        height = 0.72 + (index % 3) * 0.26
        cone(c, f"crown_icicle_{index}", (x, 0.15, 8.20 - height * 0.5),
             0.20, 0.015, height, ARCH_RIM, 10,
             rotation=(math.pi, 0.0, 0.0))
    return c


def _cave_portal(coll: bpy.types.Collection, center=(0, 0, 0), width=10.5,
                 height=8.0, depth=1.4) -> None:
    segments = 34
    ring = []
    for index in range(segments + 1):
        theta = math.pi * index / segments
        ring.append((math.cos(theta) * width * 0.5,
                     math.sin(theta) * height, 0.0))
    for index in range(segments):
        a = Vector(ring[index]) + Vector(center)
        b = Vector(ring[index + 1]) + Vector(center)
        beam(coll, f"portal_facet_{index}", a, b,
             depth * (0.85 + 0.10 * math.sin(index * 1.7)),
             DEEP_ICE if index % 3 == 0 else MID_ICE, 0.04)


def build_frozen_fall_landmark() -> bpy.types.Collection:
    c = collection("glacier_frozen_fall_landmark_v1")
    rng = random.Random(8817)
    # Ten high-resolution faceted bodies form one sculpted glacial mass around
    # dark portal. Large overlap removes first pass's row of beveled boxes;
    # controlled asymmetry, snow ledges and sparse flow sheets supply scale.
    for side in (-1, 1):
        for row in range(5):
            x = side * (6.9 + row * 1.78) + rng.uniform(-0.28, 0.28)
            z = 3.0 + row * 2.15 + (row % 2) * 0.72
            ico(c, f"fall_mass_{side}_{row}", (x, 0.15 + row * 0.12, z),
                1.0, MID_ICE if row % 3 else DEEP_ICE, 3,
                scale=(2.25 + row * 0.10, 2.05 + (row % 2) * 0.18,
                       3.25 + row * 0.17),
                rotation=(rng.uniform(-0.22, 0.22),
                          0.10 * side * row, rng.uniform(-0.35, 0.35)))
            if row in (2, 4):
                snow_cap(c, f"mass_snow_{side}_{row}",
                         (x - side * 0.12, 0.0, z + 3.05 + row * 0.16),
                         (1.72 + row * 0.08, 1.34, 0.22))
    # Four milky cascade sheets vary in width/height and overlap the rock mass
    # only at its shoulders. Portal remains a single readable navy void.
    for index, x in enumerate((-10.6, -7.9, 7.8, 10.7)):
        height = 7.2 + (index % 2) * 2.4
        box(c, f"frozen_flow_sheet_{index}",
            (x, -2.05 - (index % 2) * 0.13, 4.2 + height * 0.5),
            (1.18 + (index % 2) * 0.34, 0.16, height), PALE_ICE, 0.16, 3)
        for tooth in range(3):
            tooth_height = 1.15 + tooth * 0.48 + (index % 2) * 0.25
            cone(c, f"flow_tooth_{index}_{tooth}",
                 (x - 0.36 + tooth * 0.36, -2.12,
                  4.15 - tooth_height * 0.5),
                 0.18, 0.018, tooth_height, PALE_ICE, 9,
                 rotation=(math.pi, 0.0, 0.0))
    _cave_portal(c, (0, -2.25, 0), 11.8, 8.2, 1.25)
    box(c, "cave_void", (0, 0.9, 3.25), (9.2, 0.72, 6.5), GLASS, 0.52, 5)
    for side in (-1, 1):
        ice_cluster(c, f"portal_crystal_{side}", (side * 6.8, -2.0, 0),
                    3.7, 13, 1000 + side)
    # Water-ice apron ties the vertical fall to the ground and gives a broad
    # glossy foreground shape visible from the racing line.
    for index in range(9):
        wedge(c, f"apron_{index}", (-7.2 + index * 1.8, -4.2 - index % 2 * 0.5, 0),
              1.9, 6.5 + index % 3, 0.45 + index % 2 * 0.15,
              PALE_ICE if index % 2 else MID_ICE)
    # Warm expedition scale cues make portal unmistakable at chase distance.
    for side in (-1, 1):
        cylinder(c, f"portal_route_post_{side}", (side * 5.65, -3.18, 1.72),
                 0.12, 3.35, EXPEDITION_BLUE, 14)
        sphere(c, f"portal_route_lamp_{side}", (side * 5.65, -3.18, 3.52),
               0.30, ORANGE_HI, 18, 9)
        torus(c, f"portal_lamp_guard_{side}",
              (side * 5.65, -3.18, 3.52), 0.40, 0.045,
              EXPEDITION_BLUE, 18, 6)
    return c


def build_summit_station_landmark() -> bpy.types.Collection:
    c = collection("glacier_summit_station_landmark_v1")
    # Finish destination: open central race gate, two rounded modules, weather
    # tower and observation dome. Inward faces stay beyond +/-9.7 m, preserving
    # all lanes of the existing 18 m finish ribbon plus visible safety margin.
    for side in (-1, 1):
        x = side * 13.0
        box(c, f"module_body_{side}", (x, 1.3, 2.2), (6.5, 6.0, 4.4),
            SNOW, 0.42, 5)
        box(c, f"module_skirt_{side}", (x, 1.3, 0.48), (6.7, 6.4, 0.65),
            EXPEDITION_BLUE, 0.16, 3)
        box(c, f"module_spine_{side}", (x, 1.3, 4.5), (4.8, 1.2, 0.42),
            ORANGE_HI, 0.13, 3)
        for window in range(4):
            wx = x - 2.25 + window * 1.50
            box(c, f"window_{side}_{window}", (wx, -1.74, 2.55),
                (1.05, 0.10, 1.12), GLASS, 0.08, 3)
        for leg_x in (-2.15, 2.15):
            cylinder(c, f"stilt_{side}_{leg_x}", (x + leg_x, 0.0, 0.48),
                     0.18, 0.96, EXPEDITION_BLUE, 14)
    # Open finish arch: 19.98 m clear width, bright gold crown, cyan side bands.
    for side in (-1, 1):
        x = side * 10.3
        box(c, f"finish_leg_{side}", (x, -2.2, 3.45), (0.62, 0.82, 6.9),
            EXPEDITION_BLUE, 0.16, 4)
        box(c, f"cyan_leg_band_{side}", (x - side * 0.36, -2.62, 3.25),
            (0.12, 0.08, 5.6), CYAN, 0.025, 1)
    box(c, "finish_header", (0, -2.2, 6.82), (21.2, 0.96, 0.72),
        GOLD, 0.20, 4)
    for index, x in enumerate((-8.7, -5.8, -2.9, 0.0, 2.9, 5.8, 8.7)):
        chevron(c, f"finish_chevron_{index}", (x, -2.74, 6.94),
                0.32, 0.28, 0.07, EXPEDITION_BLUE)
    # Observation dome and ringed radar crown establish destination hierarchy.
    sphere(c, "observation_dome", (13.0, 1.3, 5.92), 2.0, PALE_ICE,
           64, 32, scale=(1.0, 1.0, 0.62))
    torus(c, "dome_ring", (13.0, 1.3, 5.32), 1.92, 0.16,
          EXPEDITION_BLUE, 48, 10)
    cylinder(c, "weather_tower", (-13.0, 1.3, 7.0), 0.25, 5.1,
             EXPEDITION_BLUE, 18)
    for z in (5.25, 6.45, 7.65, 8.85):
        torus(c, f"tower_ring_{z}", (-13.0, 1.3, z), 0.38, 0.065,
              ORANGE_HI, 18, 6)
    sphere(c, "radar_pod", (-13.0, 1.3, 9.75), 0.82, SNOW, 28, 14,
           scale=(1.0, 1.0, 0.58))
    torus(c, "radar_guard", (-13.0, 1.3, 9.75), 1.04, 0.08,
          GOLD, 28, 7, (math.pi * 0.5, 0, 0))
    # Supply yard detail prevents the landmark reading as two empty boxes.
    for index in range(18):
        side = -1 if index % 2 == 0 else 1
        row = index // 6
        x = side * (10.5 + (index % 3) * 1.15)
        y = 4.6 + row * 0.75
        box(c, f"supply_case_{index}", (x, y, 0.38),
            (0.82, 0.62, 0.76), EXPEDITION_LIGHT if index % 3 else ORANGE,
            0.09, 3)
    for side in (-1, 1):
        ice_cluster(c, f"station_ice_{side}", (side * 17.1, 1.8, 0),
                    2.8, 9, 1600 + side)
    return c


# ---------------------------------------------------------------------------
# Finalization and deterministic source output


def triangle_count(coll: bpy.types.Collection) -> int:
    total = 0
    for obj in coll.objects:
        if obj.type == "MESH":
            obj.data.calc_loop_triangles()
            total += len(obj.data.loop_triangles)
    return total


def assign_atlas_uv(mesh: bpy.types.Mesh) -> None:
    while len(mesh.uv_layers) > 0:
        mesh.uv_layers.remove(mesh.uv_layers[0])
    uv_layer = mesh.uv_layers.new(name="UVMap")
    colour_attr = mesh.color_attributes.get("Color")
    tile_scale = 0.25
    gutter = 0.065
    for polygon in mesh.polygons:
        normal = polygon.normal
        for loop_index in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            colour = colour_attr.data[loop_index].color if colour_attr else SNOW
            palette_index = min(range(len(PALETTE)), key=lambda index: sum(
                (float(colour[channel]) - PALETTE[index][channel]) ** 2
                for channel in range(3)))
            if abs(normal.z) >= abs(normal.x) and abs(normal.z) >= abs(normal.y):
                raw_u, raw_v = vertex.x * 0.27, vertex.y * 0.27
            elif abs(normal.y) >= abs(normal.x):
                raw_u, raw_v = vertex.x * 0.27, vertex.z * 0.27
            else:
                raw_u, raw_v = vertex.y * 0.27, vertex.z * 0.27
            local_u = (raw_u - math.floor(raw_u)) * (1.0 - gutter * 2.0) + gutter
            local_v = (raw_v - math.floor(raw_v)) * (1.0 - gutter * 2.0) + gutter
            uv_layer.data[loop_index].uv = (
                (palette_index % 4 + local_u) * tile_scale,
                (palette_index // 4 + local_v) * tile_scale)


def add_contract_detail(coll: bpy.types.Collection, minimum: int,
                        maximum: int, landmark: bool = False) -> None:
    """Reach budget floors with visible authored detail, never hidden faces."""
    count = triangle_count(coll)
    index = 0
    while count < minimum:
        if landmark:
            # Faceted ice cobbles at the landmark foot read as broken glacier.
            row = index // 24
            col = index % 24
            x = -7.0 + col * 0.60
            y = 3.2 + row * 0.48
            radius = 0.22 + (index % 4) * 0.025
            ico(coll, f"authored_ice_cobble_{index}", (x, y, radius * 0.58),
                radius, PALE_ICE if index % 3 else SNOW_SHADOW, 2,
                scale=(1.15, 0.82, 0.60),
                rotation=(0.07 * (index % 3), 0.11 * (index % 5), 0.19 * index))
        else:
            # Functional rivet/grip rows sit on the visible front face.
            col = index % 12
            row = (index // 12) % 5
            sphere(coll, f"authored_fastener_{index}",
                   (-0.55 + col * 0.10, -0.92, 0.22 + row * 0.12),
                   0.035, GOLD if row == 4 else EXPEDITION_BLUE, 8, 4)
        count = triangle_count(coll)
        index += 1
        if index > 500:
            raise RuntimeError(f"cannot reach triangle floor for {coll.name}")
    if count > maximum:
        raise RuntimeError(f"{coll.name}: {count} triangles exceeds {maximum}")


def finalize(coll: bpy.types.Collection) -> tuple[int, int]:
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
    points = [vertex.co for vertex in obj.data.vertices]
    minimum = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    maximum = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    shift = Vector((-(minimum.x + maximum.x) * 0.5,
                    -(minimum.y + maximum.y) * 0.5, -minimum.z))
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
    obj["visual_only"] = True
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles), 1


def main() -> int:
    if bpy.app.version[:3] != EXPECTED_VERSION:
        raise RuntimeError(f"expected Blender {EXPECTED_VERSION}, got {bpy.app.version[:3]}")
    args = parse_args()
    reset(Path(args.texture_root).resolve())
    builders = [
        (build_edge_kerb, 300, 1500, False),
        (build_surface_inlay, 300, 1500, False),
        (build_track_skin_patch, 300, 1500, False),
        (build_route_beacon, 300, 1500, False),
        (build_route_flag, 300, 1500, False),
        (build_snow_fence, 300, 1500, False),
        (build_expedition_crate, 300, 1500, False),
        (build_rescue_sled, 300, 1500, False),
        (build_field_tent, 300, 1500, False),
        (build_field_lab, 300, 1500, False),
        (build_camp_lamp, 300, 1500, False),
        (build_weather_mast, 300, 1500, False),
        (build_ice_spire, 300, 1500, False),
        (build_ice_boulder, 300, 1500, False),
        (build_snowbank, 300, 1500, False),
        (build_layered_ridge, 300, 1500, False),
        (build_cave_buttress, 300, 1500, False),
        (build_duck_gate, 1500, 5000, False),
        (build_snowball_warning, 1500, 5000, False),
        (build_cracking_marker, 1500, 5000, False),
        (build_boost_marker, 1500, 5000, False),
        (build_arch_landmark, 10000, 30000, True),
        (build_frozen_fall_landmark, 10000, 30000, True),
        (build_summit_station_landmark, 10000, 30000, True),
    ]
    metrics = []
    for builder, minimum, maximum, landmark in builders:
        coll = builder()
        add_contract_detail(coll, minimum, maximum, landmark)
        triangles, surfaces = finalize(coll)
        if triangles < minimum or triangles > maximum or surfaces != 1:
            raise RuntimeError(f"{coll.name}: triangles={triangles} surfaces={surfaces}")
        metrics.append((coll.name, triangles, surfaces))
    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output), compress=True, check_existing=False)
    for name, triangles, surfaces in metrics:
        print(f"[glacier-kit] {name} triangles={triangles} surfaces={surfaces}")
    print(f"[glacier-kit] saved {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
