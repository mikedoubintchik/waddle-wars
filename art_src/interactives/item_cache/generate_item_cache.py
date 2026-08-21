#!/usr/bin/env python3
"""Build project-original expedition item-cache art in Blender 5.2 LTS.

Creates two visual-only export collections sharing one opaque painted material.
The cache is a cream/cyan split expedition capsule, not a box or drum: three
asymmetric protective fins make a diamond/tri-lobed outline around an exposed
violet faceted power core. Gameplay collision and item logic remain in Godot.
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

ROLE_TILE = {
    "shell": 0,
    "shell_lift": 1,
    "frost": 2,
    "violet": 3,
    "violet_rim": 4,
    "brass": 5,
    "rubber": 6,
    "steel": 7,
    "frost_high": 8,
    "violet_recess": 9,
    "steel_mid": 10,
    "brass_edge": 11,
    "seam": 12,
    "violet_mid": 13,
    "frost_metal": 14,
    "rubber_mid": 15,
}


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
    world = bpy.data.worlds.new("item_cache_authoring_world")
    world.color = (0.025, 0.060, 0.125)
    scene.world = world
    scene["waddle_wars_toolchain"] = "Blender 5.2.0 LTS"
    scene["waddle_wars_forward"] = "-Z"
    scene["waddle_wars_units"] = "metres"
    scene["waddle_wars_asset_family"] = "expedition_item_cache"
    scene["waddle_wars_semantic_color"] = "violet_powerup"
    scene["waddle_wars_shape_cue"] = "split_capsule_three_fin_faceted_core"
    scene["waddle_wars_license"] = "project_original"
    for role in ("albedo", "normal", "orm", "emission"):
        path = texture_root / f"item_cache_{role}_v1.png"
        if not path.is_file():
            raise RuntimeError(f"missing generated texture {path}")
        image = bpy.data.images.load(str(path), check_existing=False)
        image.name = f"item_cache_{role}_v1"
        image.colorspace_settings.name = "sRGB" if role == "albedo" else "Non-Color"
        image.pack()
        image.use_fake_user = True
        PACKED_TEXTURES[role] = image


def material() -> bpy.types.Material:
    existing = bpy.data.materials.get("item_cache_painted_atlas_v1")
    if existing is not None:
        return existing
    mat = bpy.data.materials.new("item_cache_painted_atlas_v1")
    mat.use_nodes = True
    mat.diffuse_color = (0.34, 0.16, 0.62, 1.0)
    mat.roughness = 0.52
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
    multiply = nodes.new("ShaderNodeMixRGB")
    multiply.blend_type = "MULTIPLY"
    multiply.inputs[0].default_value = 1.0
    normal_tex = nodes.new("ShaderNodeTexImage")
    normal_tex.image = PACKED_TEXTURES["normal"]
    normal_tex.interpolation = "Linear"
    normal = nodes.new("ShaderNodeNormalMap")
    normal.inputs["Strength"].default_value = 0.56
    orm = nodes.new("ShaderNodeTexImage")
    orm.image = PACKED_TEXTURES["orm"]
    orm.interpolation = "Linear"
    channels = nodes.new("ShaderNodeSeparateColor")
    emission = nodes.new("ShaderNodeTexImage")
    emission.image = PACKED_TEXTURES["emission"]
    emission.interpolation = "Linear"
    shader.inputs["Specular IOR Level"].default_value = 0.34
    links.new(albedo.outputs["Color"], multiply.inputs[1])
    links.new(vertex.outputs["Color"], multiply.inputs[2])
    links.new(multiply.outputs["Color"], shader.inputs["Base Color"])
    links.new(normal_tex.outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], shader.inputs["Normal"])
    links.new(orm.outputs["Color"], channels.inputs["Color"])
    links.new(channels.outputs["Green"], shader.inputs["Roughness"])
    links.new(channels.outputs["Blue"], shader.inputs["Metallic"])
    links.new(emission.outputs["Color"], shader.inputs["Emission Color"])
    shader.inputs["Emission Strength"].default_value = 0.38
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return mat


def collection(name: str) -> bpy.types.Collection:
    result = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(result)
    return result


def move_to_collection(obj: bpy.types.Object, target: bpy.types.Collection) -> None:
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    target.objects.link(obj)


def apply_transform(obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False)


def assign_role_uv(obj: bpy.types.Object, role: str) -> None:
    mesh = obj.data
    while len(mesh.uv_layers) > 0:
        mesh.uv_layers.remove(mesh.uv_layers[0])
    uv_layer = mesh.uv_layers.new(name="UVMap")
    tile = ROLE_TILE[role]
    tile_size = 0.25
    gutter = 0.075
    for polygon in mesh.polygons:
        normal = polygon.normal
        for loop_index in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            if abs(normal.z) >= abs(normal.x) and abs(normal.z) >= abs(normal.y):
                raw_u, raw_v = vertex.x * 1.7, vertex.y * 1.7
            elif abs(normal.y) >= abs(normal.x):
                raw_u, raw_v = vertex.x * 1.7, vertex.z * 1.7
            else:
                raw_u, raw_v = vertex.y * 1.7, vertex.z * 1.7
            local_u = (raw_u - math.floor(raw_u)) * (1.0 - gutter * 2.0) + gutter
            local_v = (raw_v - math.floor(raw_v)) * (1.0 - gutter * 2.0) + gutter
            # PNG scanlines are top-origin while Blender UV tiles are
            # bottom-origin. Mirror atlas row explicitly; without this, shell
            # navy sampled the seam tile, cream frost sampled violet, and the
            # intended violet compass aperture sampled cream.
            atlas_row = 3 - tile // 4
            uv_layer.data[loop_index].uv = (
                (tile % 4 + local_u) * tile_size,
                (atlas_row + local_v) * tile_size,
            )


def bake_ao_curvature(obj: bpy.types.Object) -> None:
    mesh = obj.data
    old = mesh.color_attributes.get("Color")
    if old is not None:
        mesh.color_attributes.remove(old)
    attr = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
    mesh.color_attributes.active_color = attr
    for polygon in mesh.polygons:
        normal = polygon.normal
        light = 0.83 + max(normal.z, 0.0) * 0.15 + max(-normal.y, 0.0) * 0.035
        if normal.z < -0.18:
            light *= 0.80
        for loop_index in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index]
            grain = math.sin(vertex.co.x * 12.7 + vertex.co.y * 9.1
                             + vertex.co.z * 14.3) * 0.018
            shade = max(0.64, min(1.0, light + grain))
            attr.data[loop_index].color = (shade, shade, shade, 1.0)


def finish_part(obj: bpy.types.Object, target: bpy.types.Collection,
                role: str, smooth: bool = True) -> bpy.types.Object:
    apply_transform(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = smooth
    obj.data.materials.clear()
    obj.data.materials.append(material())
    assign_role_uv(obj, role)
    bake_ao_curvature(obj)
    move_to_collection(obj, target)
    return obj


def cylinder(target: bpy.types.Collection, name: str, center, radius: float,
             depth: float, vertices: int, role: str,
             rotation=(0.0, 0.0, 0.0), smooth: bool = True) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth,
        location=center, rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    return finish_part(obj, target, role, smooth)


def sphere(target: bpy.types.Collection, name: str, center, radius: float,
           segments: int, rings: int, scale, role: str) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=rings, radius=radius, location=center,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    return finish_part(obj, target, role, True)


def ico(target: bpy.types.Collection, name: str, center, radius: float,
        subdivisions: int, scale, role: str, smooth: bool = True) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=subdivisions, radius=radius, location=center,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    return finish_part(obj, target, role, smooth)


def torus(target: bpy.types.Collection, name: str, center, major: float,
          minor: float, major_segments: int, minor_segments: int, role: str,
          normal: Vector = Vector((0.0, 0.0, 1.0))) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major, minor_radius=minor,
        major_segments=major_segments, minor_segments=minor_segments,
        location=center,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(normal)
    return finish_part(obj, target, role, True)


def bevel_box(target: bpy.types.Collection, name: str, center, size,
              rotation_z: float, role: str, bevel: float = 0.025) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=center, rotation=(0.0, 0.0, rotation_z))
    obj = bpy.context.object
    obj.name = name
    obj.scale = Vector(size) * 0.5
    apply_transform(obj)
    if bevel > 0.0:
        modifier = obj.modifiers.new("rolled_cache_edge", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        modifier.affect = "EDGES"
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)
    return finish_part(obj, target, role, False)


def radial_cylinder(target: bpy.types.Collection, name: str, center,
                    axis: Vector, radius: float, depth: float,
                    vertices: int, role: str) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=center,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(axis)
    return finish_part(obj, target, role, True)


def star_prism(target: bpy.types.Collection, name: str, angle: float,
               center_radius: float, z: float, radius: float, depth: float,
               role: str) -> bpy.types.Object:
    radial = Vector((math.cos(angle), math.sin(angle), 0.0))
    tangent = Vector((-math.sin(angle), math.cos(angle), 0.0))
    center = radial * center_radius + Vector((0.0, 0.0, z))
    perimeter = []
    for index in range(8):
        theta = math.tau * index / 8.0 + math.pi * 0.5
        local_radius = radius if index % 2 == 0 else radius * 0.43
        perimeter.append(tangent * (math.cos(theta) * local_radius)
                         + Vector((0.0, 0.0, math.sin(theta) * local_radius)))
    vertices = []
    for side in (-1.0, 1.0):
        vertices.extend(tuple(center + point + radial * depth * 0.5 * side)
                        for point in perimeter)
    faces = []
    faces.append(tuple(range(7, -1, -1)))
    faces.append(tuple(range(8, 16)))
    for index in range(8):
        nxt = (index + 1) % 8
        faces.append((index, nxt, 8 + nxt, 8 + index))
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    target.objects.link(obj)
    return finish_part(obj, target, role, False)


def capsule_cap(target: bpy.types.Collection, name: str, upper: bool,
                segments: int, role: str) -> bpy.types.Object:
    """One tapered half-shell; equatorial opening exposes the power core."""
    direction = 1.0 if upper else -1.0
    levels = [
        (direction * 0.145, 0.455),
        (direction * 0.315, 0.430),
        (direction * 0.485, 0.320),
        (direction * 0.610, 0.155),
    ]
    vertices = []
    for z, radius in levels:
        for index in range(segments):
            angle = math.tau * index / segments
            vertices.append((math.cos(angle) * radius,
                             math.sin(angle) * radius, z))
    tip_index = len(vertices)
    vertices.append((0.0, 0.0, direction * 0.665))
    faces = []
    for ring in range(len(levels) - 1):
        for index in range(segments):
            nxt = (index + 1) % segments
            a = ring * segments + index
            b = ring * segments + nxt
            c = (ring + 1) * segments + nxt
            d = (ring + 1) * segments + index
            faces.append((a, b, c, d) if upper else (a, d, c, b))
    last = (len(levels) - 1) * segments
    for index in range(segments):
        nxt = (index + 1) % segments
        faces.append((last + index, last + nxt, tip_index)
                     if upper else (last + index, tip_index, last + nxt))
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    target.objects.link(obj)
    return finish_part(obj, target, role, True)


def diamond_prism(target: bpy.types.Collection, name: str, angle: float,
                  center_radius: float, z: float, width: float, height: float,
                  depth: float, role: str) -> bpy.types.Object:
    """Raised faceted lozenge repeated on three approach faces."""
    radial = Vector((math.cos(angle), math.sin(angle), 0.0))
    tangent = Vector((-math.sin(angle), math.cos(angle), 0.0))
    center = radial * center_radius + Vector((0.0, 0.0, z))
    perimeter = [
        Vector((0.0, 0.0, height * 0.5)),
        tangent * width * 0.5,
        Vector((0.0, 0.0, -height * 0.5)),
        tangent * -width * 0.5,
    ]
    back = [center + point - radial * depth * 0.5 for point in perimeter]
    front = [center + point + radial * depth * 0.5 for point in perimeter]
    front_center = center + radial * depth * 0.82
    vertices = [tuple(value) for value in back + front + [front_center]]
    faces = [(0, 3, 2, 1)]
    faces.extend((4 + index, 4 + (index + 1) % 4, 8) for index in range(4))
    faces.extend((index, (index + 1) % 4,
                  4 + (index + 1) % 4, 4 + index) for index in range(4))
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    target.objects.link(obj)
    return finish_part(obj, target, role, False)


def beam(target: bpy.types.Collection, name: str, start, end,
         width: float, role: str, bevel: float) -> bpy.types.Object:
    a = Vector(start)
    b = Vector(end)
    direction = b - a
    bpy.ops.mesh.primitive_cube_add(location=(a + b) * 0.5)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (width * 0.5, width * 0.5, direction.length * 0.5)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(
        direction.normalized())
    apply_transform(obj)
    if bevel > 0.0:
        modifier = obj.modifiers.new("forged_fin_edge", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        modifier.affect = "EDGES"
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)
    return finish_part(obj, target, role, False)


def build_cache(name: str, high: bool) -> bpy.types.Collection:
    target = collection(name)
    body_segments = 18 if high else 12
    if high:
        cylinder(target, "pressure_shell", (0.0, 0.0, 0.0), 0.465, 0.92,
                 body_segments, "shell", smooth=True)
        sphere(target, "frost_crown", (0.0, 0.0, 0.405), 0.49,
               24, 12, (1.0, 1.0, 0.49), "frost")
        sphere(target, "pressure_keel", (0.0, 0.0, -0.405), 0.49,
               24, 12, (1.0, 1.0, 0.49), "shell_lift")
        loop_segments = (20, 6)
        collar_segments = (24, 6)
        rivet_count = 12
    else:
        cylinder(target, "pressure_shell", (0.0, 0.0, 0.0), 0.465, 0.92,
                 body_segments, "shell", smooth=True)
        ico(target, "frost_crown", (0.0, 0.0, 0.405), 0.49,
            2, (1.0, 1.0, 0.49), "frost")
        ico(target, "pressure_keel", (0.0, 0.0, -0.405), 0.49,
            2, (1.0, 1.0, 0.49), "shell_lift")
        loop_segments = (12, 4)
        collar_segments = (12, 4)
        rivet_count = 0

    torus(target, "violet_equator", (0.0, 0.0, 0.0), 0.475, 0.057,
          collar_segments[0], collar_segments[1], "violet_recess")

    # Three cage loops define a non-box silhouette from every yaw. Each loop
    # lives in a radial/vertical plane and sits partly behind the shell.
    for side in range(3):
        angle = math.tau * side / 3.0
        radial = Vector((math.cos(angle), math.sin(angle), 0.0))
        tangent = Vector((-math.sin(angle), math.cos(angle), 0.0))
        loop_center = radial * 0.285
        torus(target, f"carry_cage_{side}", tuple(loop_center), 0.355, 0.052,
              loop_segments[0], loop_segments[1], "steel", tangent)
        grip_center = radial * 0.285 + Vector((0.0, 0.0, 0.355))
        radial_cylinder(target, f"rubber_grip_{side}", tuple(grip_center), radial,
                        0.058, 0.31, 12 if high else 8, "rubber")

        # Raised four-point compass aperture. Geometry—not hue—carries the
        # power-up cue in silhouette and in colorblind modes.
        star_prism(target, f"compass_aperture_{side}", angle, 0.505, 0.025,
                   0.275, 0.052, "violet_rim")
        star_prism(target, f"violet_core_{side}", angle, 0.548, 0.025,
                   0.165, 0.065, "violet")

        latch_center = radial * 0.485 + Vector((0.0, 0.0, -0.30))
        bevel_box(target, f"brass_latch_{side}", tuple(latch_center),
                  (0.20, 0.075, 0.12), angle, "brass", 0.018 if high else 0.0)

    if high:
        for index in range(rivet_count):
            angle = math.tau * index / rivet_count
            z = 0.245 if index % 2 == 0 else -0.245
            center = Vector((math.cos(angle), math.sin(angle), 0.0)) * 0.477
            center.z = z
            ico(target, f"shell_fastener_{index}", tuple(center), 0.035,
                1, (1.0, 1.0, 0.55), "brass_edge")
        # Broken snow pillow silhouette prevents a perfect manufactured dome.
        for index, angle in enumerate((0.20, 2.18, 4.42)):
            center = Vector((math.cos(angle) * 0.20, math.sin(angle) * 0.20, 0.625))
            ico(target, f"frost_pillow_{index}", tuple(center), 0.16,
                1, (1.35, 0.82, 0.34), "frost_high")
    return target


def finalize(target: bpy.types.Collection) -> tuple[int, int]:
    objects = [obj for obj in target.objects if obj.type == "MESH"]
    if not objects:
        raise RuntimeError(f"empty collection {target.name}")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = target.name
    for polygon in obj.data.polygons:
        polygon.material_index = 0
    obj.data.materials.clear()
    obj.data.materials.append(material())
    triangulate = obj.modifiers.new("runtime_triangles", "TRIANGULATE")
    triangulate.keep_custom_normals = True
    bpy.ops.object.modifier_apply(modifier=triangulate.name)
    points = [vertex.co for vertex in obj.data.vertices]
    minimum = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    maximum = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    shift = -(minimum + maximum) * 0.5
    for vertex in obj.data.vertices:
        vertex.co += shift
    obj.data.update()
    obj.location = (0.0, 0.0, 0.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)
    obj["asset_id"] = target.name
    obj["forward_axis"] = "-Z"
    obj["units"] = "metres"
    obj["visual_only"] = True
    obj["semantic_color"] = "violet_powerup"
    obj["shape_cue"] = "three_lobed_pod_four_point_aperture"
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles), len(obj.data.materials)


def main() -> int:
    if bpy.app.version[:3] != EXPECTED_VERSION:
        raise RuntimeError(f"expected Blender {EXPECTED_VERSION}, got {bpy.app.version[:3]}")
    args = parse_args()
    reset(Path(args.texture_root).resolve())
    metrics = []
    for name, high, minimum, maximum in (
        ("item_cache_lod0_v1", True, 1500, 5000),
        ("item_cache_lod1_v1", False, 250, 1100),
    ):
        target = build_cache(name, high)
        triangles, surfaces = finalize(target)
        if triangles < minimum or triangles > maximum or surfaces != 1:
            raise RuntimeError(
                f"{name}: triangles={triangles} expected={minimum}..{maximum} surfaces={surfaces}"
            )
        metrics.append((name, triangles, surfaces))
    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output), compress=True, check_existing=False)
    for name, triangles, surfaces in metrics:
        print(f"[item-cache] {name} triangles={triangles} surfaces={surfaces}")
    print(f"[item-cache] saved {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
