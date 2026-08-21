#!/usr/bin/env python3
"""Build and render V12 fused-sculpt source proof in Blender 5.2.

This script intentionally creates no rig, runtime GLB, wrapper scene, or asset
overwrite. It saves one temporary source-only .blend and three PNG stills for
front/three-quarter/true-side art review before production integration.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hero_penguin_v12_design import (  # noqa: E402
    BILL_LOWER_SECTIONS,
    BILL_UPPER_SECTIONS,
    BODY_VOLUMES,
    CHEEK_VOLUMES,
    EYE_CENTER_X,
    EYE_CENTER_Y,
    EYE_CENTER_Z,
    EYE_RADII,
    FOOT_CENTER_X,
    FOOT_CENTER_Y,
    FOOT_CENTER_Z,
    FOOT_RADII,
    SOCKET_CENTER_Y,
    SOCKET_RADII,
    WING_HALF_THICKNESS,
    WING_HALF_WIDTH,
    WING_ROOT,
    WING_TIP,
)


EXPECTED_BLENDER = (5, 2, 0)
DEFAULT_OUTPUT = Path("/tmp/waddle-hero-penguin-v12-blender-proof")
DEFAULT_MATERIAL = Path("/tmp/waddle-hero-penguin-v11-static/material")


def parse_args() -> argparse.Namespace:
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--material-dir", type=Path, default=DEFAULT_MATERIAL)
    return parser.parse_args(values)


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials,
                       bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            datablocks.remove(datablock)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    # Blender 5.2 LTS exposes Eevee under the stable BLENDER_EEVEE enum.
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.render.use_file_extension = True
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.165, 0.185, 0.205, 1.0)
    background.inputs["Strength"].default_value = 0.72


def deselect_all() -> None:
    for obj in bpy.context.selected_objects:
        obj.select_set(False)


def activate(obj: bpy.types.Object) -> None:
    deselect_all()
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def smooth_mesh(obj: bpy.types.Object) -> None:
    for polygon in obj.data.polygons:
        polygon.use_smooth = True


def create_solid_material(name: str, color: tuple[float, float, float, float],
                          roughness: float, metallic: float = 0.0,
                          subsurface: float = 0.0) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = color
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Metallic"].default_value = metallic
    if "Subsurface Weight" in principled.inputs:
        principled.inputs["Subsurface Weight"].default_value = subsurface
    return material


def create_feather_material(name: str, base: tuple[float, float, float, float],
                            tile_path: Path, roughness: float) -> bpy.types.Material:
    if not tile_path.is_file():
        raise RuntimeError(f"missing reviewed derived tile: {tile_path}")
    material = create_solid_material(name, base, roughness)
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    principled = nodes.get("Principled BSDF")
    coordinates = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (3.6, 3.6, 3.6)
    image_node = nodes.new("ShaderNodeTexImage")
    image = bpy.data.images.load(str(tile_path), check_existing=True)
    image.colorspace_settings.name = "sRGB"
    image.pack()
    image_node.image = image
    image_node.projection = "BOX"
    image_node.projection_blend = 0.22
    image_node.extension = "REPEAT"
    multiply = nodes.new("ShaderNodeMixRGB")
    multiply.blend_type = "MULTIPLY"
    multiply.inputs[0].default_value = 1.0
    multiply.inputs[2].default_value = base
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.11
    bump.inputs["Distance"].default_value = 0.007
    links.new(coordinates.outputs["Generated"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], image_node.inputs["Vector"])
    links.new(image_node.outputs["Color"], multiply.inputs[1])
    links.new(multiply.outputs["Color"], principled.inputs["Base Color"])
    links.new(image_node.outputs["Color"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], principled.inputs["Normal"])
    return material


def create_vertex_feather_material(name: str, tile_path: Path) -> bpy.types.Material:
    """One interpolated body material; avoids polygon-step paint boundaries."""
    if not tile_path.is_file():
        raise RuntimeError(f"missing reviewed derived tile: {tile_path}")
    material = create_solid_material(name, (0.04, 0.08, 0.15, 1.0), 0.82)
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    principled = nodes.get("Principled BSDF")
    vertex_color = nodes.new("ShaderNodeVertexColor")
    vertex_color.layer_name = "PreviewColor"
    coordinates = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (3.8, 3.8, 3.8)
    texture = nodes.new("ShaderNodeTexImage")
    image = bpy.data.images.load(str(tile_path), check_existing=True)
    image.colorspace_settings.name = "sRGB"
    image.pack()
    texture.image = image
    texture.projection = "BOX"
    texture.projection_blend = 0.24
    texture.extension = "REPEAT"
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.09
    bump.inputs["Distance"].default_value = 0.005
    links.new(vertex_color.outputs["Color"], principled.inputs["Base Color"])
    links.new(coordinates.outputs["Generated"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], texture.inputs["Vector"])
    links.new(texture.outputs["Color"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], principled.inputs["Normal"])
    return material


def add_ico_ellipsoid(name: str, center: tuple[float, float, float],
                      radii: tuple[float, float, float], subdivisions: int = 3,
                      material: bpy.types.Material | None = None) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0,
                                          location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = radii
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    smooth_mesh(obj)
    if material is not None:
        obj.data.materials.append(material)
    return obj


def join_objects(objects: list[bpy.types.Object], name: str) -> bpy.types.Object:
    deselect_all()
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    result = bpy.context.object
    result.name = name
    # Active join object otherwise retains first ellipsoid's translated origin;
    # proof paint masks and later skin-weight fields require world-aligned local
    # coordinates after fusion.
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return result


def voxel_fuse_body() -> bpy.types.Object:
    pieces = [add_ico_ellipsoid(f"BodyVolume{index:02d}", center, radii)
              for index, (center, radii) in enumerate(BODY_VOLUMES + CHEEK_VOLUMES)]
    body = join_objects(pieces, "HeroBodyV12Fused")
    body.data.remesh_voxel_size = 0.011
    body.data.remesh_voxel_adaptivity = 0.0
    activate(body)
    if not bpy.ops.object.voxel_remesh.poll():
        raise RuntimeError("Blender object.voxel_remesh unavailable for V12 source proof")
    bpy.ops.object.voxel_remesh()
    smooth = body.modifiers.new("LowFrequencySculptSmooth", "SMOOTH")
    smooth.factor = 0.40
    smooth.iterations = 7
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    smooth_mesh(body)
    return body


def cut_eye_sockets(body: bpy.types.Object) -> None:
    for side in (-1.0, 1.0):
        cutter = add_ico_ellipsoid(
            f"EyeSocketCutter{side:+.0f}",
            (side * EYE_CENTER_X, SOCKET_CENTER_Y - 0.002, EYE_CENTER_Z - 0.010),
            (SOCKET_RADII[0] * 0.91, SOCKET_RADII[1] * 1.28, SOCKET_RADII[2] * 0.91),
            subdivisions=4,
        )
        activate(body)
        boolean = body.modifiers.new(f"RecessEye{side:+.0f}", "BOOLEAN")
        boolean.operation = "DIFFERENCE"
        boolean.solver = "EXACT"
        boolean.object = cutter
        bpy.ops.object.modifier_apply(modifier=boolean.name)
        bpy.data.objects.remove(cutter, do_unlink=True)
    bevel = body.modifiers.new("SocketMicroBevel", "BEVEL")
    bevel.width = 0.0035
    bevel.segments = 2
    bevel.limit_method = "ANGLE"
    bevel.angle_limit = math.radians(42.0)
    activate(body)
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    smooth_mesh(body)


def score(point: Vector, center: tuple[float, float, float],
          radii: tuple[float, float, float]) -> float:
    return sum(((point[index] - center[index]) / radii[index]) ** 2 for index in range(3))


def body_color(point: Vector) -> tuple[float, float, float, float]:
    cheek = min(score(point, (-0.165, -0.260, 1.420), (0.218, 0.195, 0.178)),
                score(point, (0.165, -0.260, 1.420), (0.218, 0.195, 0.178)))
    chin = score(point, (0.0, -0.225, 1.265), (0.265, 0.220, 0.205))
    chest = score(point, (0.0, -0.210, 0.825), (0.405, 0.270, 0.555))
    hood = min(score(point, (-EYE_CENTER_X, -0.285, 1.625), (0.138, 0.150, 0.082)),
               score(point, (EYE_CENTER_X, -0.285, 1.625), (0.138, 0.150, 0.082)))
    cream = (cheek < 1.0 or chin < 1.0 or chest < 1.0) and hood >= 1.0
    if abs(point.x) < 0.047 and point.z > 1.445:
        cream = False
    warm = min(score(point, (-0.325, -0.285, 1.420), (0.043, 0.038, 0.070)),
               score(point, (0.325, -0.285, 1.420), (0.043, 0.038, 0.070))) < 1.0
    cyan = min(score(point, (-0.350, 0.000, 1.425), (0.027, 0.075, 0.026)),
               score(point, (0.350, 0.000, 1.425), (0.027, 0.075, 0.026))) < 1.0
    if cyan:
        return (0.006, 0.068, 0.078, 1.0)
    if warm:
        return (0.46, 0.115, 0.018, 1.0)
    if cream:
        return (0.72, 0.62, 0.46, 1.0)
    return (0.018, 0.052, 0.110, 1.0)


def assign_body_materials(body: bpy.types.Object, materials: dict[str, bpy.types.Material]) -> None:
    body.data.materials.clear()
    body.data.materials.append(materials["body_vertex"])
    color = body.data.color_attributes.new(name="PreviewColor", type="BYTE_COLOR", domain="POINT")
    for vertex in body.data.vertices:
        color.data[vertex.index].color = body_color(vertex.co)
    for polygon in body.data.polygons:
        polygon.material_index = 0
    subdivision = body.modifiers.new("ProofSurfaceSubdivision", "SUBSURF")
    subdivision.subdivision_type = "CATMULL_CLARK"
    subdivision.levels = 1
    subdivision.render_levels = 1


def create_almond_lens(name: str, side: float, material: bpy.types.Material) -> bpy.types.Object:
    segments = 56
    rings = 12
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    vertices.append((side * EYE_CENTER_X, EYE_CENTER_Y - EYE_RADII[1], EYE_CENTER_Z))
    for ring in range(1, rings + 1):
        radius = ring / rings
        depth = EYE_RADII[1] * math.sqrt(max(0.0, 1.0 - radius * radius))
        for segment in range(segments):
            angle = math.tau * segment / segments
            cosine = math.cos(angle)
            sine = math.sin(angle)
            x = EYE_RADII[0] * radius * cosine
            # Pointed horizontal corners plus full vertical reach: unmistakable
            # upright almond, never a circular sclera ring.
            z = EYE_RADII[2] * radius * math.copysign(abs(sine) ** 1.35, sine)
            vertices.append((side * EYE_CENTER_X + x, EYE_CENTER_Y - depth,
                             EYE_CENTER_Z + z))
    for segment in range(segments):
        nxt = (segment + 1) % segments
        faces.append((0, 1 + segment, 1 + nxt))
    for ring in range(rings - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            a = 1 + ring * segments + segment
            b = 1 + ring * segments + nxt
            c = 1 + (ring + 1) * segments + nxt
            d = 1 + (ring + 1) * segments + segment
            faces.append((a, b, c, d))
    back = len(vertices)
    vertices.append((side * EYE_CENTER_X, EYE_CENTER_Y + 0.008, EYE_CENTER_Z))
    boundary = 1 + (rings - 1) * segments
    for segment in range(segments):
        nxt = (segment + 1) % segments
        faces.append((back, boundary + nxt, boundary + segment))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update(calc_edges=True)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(material)
    smooth_mesh(obj)
    return obj


def add_eye_set(materials: dict[str, bpy.types.Material]) -> None:
    for side in (-1.0, 1.0):
        create_almond_lens(f"AlmondSclera{side:+.0f}", side, materials["sclera"])
        front = EYE_CENTER_Y - EYE_RADII[1] - 0.003
        add_ico_ellipsoid(f"Iris{side:+.0f}",
                          (side * EYE_CENTER_X, front, EYE_CENTER_Z - 0.004),
                          (0.066, 0.008, 0.084), 4, materials["iris"])
        add_ico_ellipsoid(f"Pupil{side:+.0f}",
                          (side * EYE_CENTER_X, front - 0.008, EYE_CENTER_Z - 0.009),
                          (0.038, 0.005, 0.054), 4, materials["pupil"])
        add_ico_ellipsoid(f"Catchlight{side:+.0f}",
                          (side * (EYE_CENTER_X - 0.013), front - 0.013, EYE_CENTER_Z + 0.039),
                          (0.011, 0.004, 0.014), 3, materials["catchlight"])
        add_upper_lid(side, materials["lid"])


def add_upper_lid(side: float, material: bpy.types.Material) -> bpy.types.Object:
    segments = 30
    outer_front: list[int] = []
    inner_front: list[int] = []
    outer_back: list[int] = []
    inner_back: list[int] = []
    vertices: list[tuple[float, float, float]] = []
    for index in range(segments):
        u = -0.88 + 1.76 * index / (segments - 1)
        arch = math.sqrt(max(0.0, 1.0 - u * u))
        x = side * EYE_CENTER_X + u * EYE_RADII[0]
        outer_z = EYE_CENTER_Z + EYE_RADII[2] * arch * 0.91
        inner_z = outer_z - (0.020 + 0.014 * arch)
        front_y = EYE_CENTER_Y - EYE_RADII[1] * arch * 0.97 - 0.012
        back_y = front_y + 0.036
        outer_front.append(len(vertices)); vertices.append((x, front_y, outer_z))
        inner_front.append(len(vertices)); vertices.append((x, front_y - 0.001, inner_z))
        outer_back.append(len(vertices)); vertices.append((x, back_y, outer_z))
        inner_back.append(len(vertices)); vertices.append((x, back_y, inner_z))
    faces: list[tuple[int, ...]] = []
    for index in range(segments - 1):
        nxt = index + 1
        faces.extend(((outer_front[index], outer_front[nxt], inner_front[nxt], inner_front[index]),
                      (outer_back[nxt], outer_back[index], inner_back[index], inner_back[nxt]),
                      (outer_front[index], outer_back[index], outer_back[nxt], outer_front[nxt]),
                      (inner_front[nxt], inner_back[nxt], inner_back[index], inner_front[index])))
    for index in (0, segments - 1):
        faces.append((outer_front[index], inner_front[index], inner_back[index], outer_back[index]))
    mesh = bpy.data.meshes.new(f"IntegratedUpperLid{side:+.0f}")
    mesh.from_pydata(vertices, [], faces)
    mesh.update(calc_edges=True)
    lid = bpy.data.objects.new(mesh.name, mesh)
    bpy.context.scene.collection.objects.link(lid)
    lid.data.materials.append(material)
    smooth_mesh(lid)
    return lid


def create_loft(name: str, sections: tuple[tuple[float, float, float, float], ...],
                material: bpy.types.Material) -> bpy.types.Object:
    segments = 20
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for y, width, height, center_z in sections:
        for segment in range(segments):
            angle = math.tau * segment / segments
            cosine = math.cos(angle)
            sine = math.sin(angle)
            profile_x = math.copysign(abs(cosine) ** 0.66, cosine)
            profile_z = math.copysign(abs(sine) ** 0.66, sine)
            vertices.append((profile_x * width, y, center_z + profile_z * height))
    for ring in range(len(sections) - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            a = ring * segments + segment
            b = ring * segments + nxt
            c = (ring + 1) * segments + nxt
            d = (ring + 1) * segments + segment
            faces.append((a, b, c, d))
    base = len(vertices)
    tip = base + 1
    vertices.extend(((0.0, sections[0][0], sections[0][3]),
                     (0.0, sections[-1][0], sections[-1][3])))
    last = (len(sections) - 1) * segments
    for segment in range(segments):
        nxt = (segment + 1) % segments
        faces.append((base, nxt, segment))
        faces.append((tip, last + segment, last + nxt))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update(calc_edges=True)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(material)
    smooth_mesh(obj)
    activate(obj)
    bevel = obj.modifiers.new("RoundedWedgeEdges", "BEVEL")
    bevel.width = 0.0035
    bevel.segments = 2
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def add_bill(materials: dict[str, bpy.types.Material]) -> None:
    create_loft("UpperBillRoundedWedge", BILL_UPPER_SECTIONS, materials["bill_upper"])
    create_loft("LowerBillTuckedWedge", BILL_LOWER_SECTIONS, materials["bill_lower"])
    vertices = [(-0.098, -0.398, 1.376), (0.098, -0.398, 1.376),
                (-0.025, -0.548, 1.379), (0.025, -0.548, 1.379),
                (-0.098, -0.398, 1.382), (0.098, -0.398, 1.382),
                (-0.025, -0.548, 1.384), (0.025, -0.548, 1.384)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 2, 6, 4),
             (1, 5, 7, 3), (0, 4, 5, 1), (2, 3, 7, 6)]
    mesh = bpy.data.meshes.new("BillMouthSeam")
    mesh.from_pydata(vertices, [], faces)
    seam = bpy.data.objects.new("BillMouthSeam", mesh)
    bpy.context.scene.collection.objects.link(seam)
    seam.data.materials.append(materials["mouth"])


def add_paddle(side: float, materials: dict[str, bpy.types.Material]) -> bpy.types.Object:
    root = Vector((side * WING_ROOT[0], WING_ROOT[1], WING_ROOT[2]))
    end = Vector((side * WING_TIP[0], WING_TIP[1], WING_TIP[2]))
    axis = (end - root).normalized()
    broad = Vector((side * -axis.z, 0.0, side * axis.x)).normalized()
    thick = axis.cross(broad).normalized()
    segments = 40
    rings: list[list[int]] = []
    vertices: list[tuple[float, float, float]] = []
    ring_centers: list[Vector] = []
    ring_widths: list[float] = []
    for ring in range(28):
        t = ring / 27.0
        center = root.lerp(end, t)
        width = 0.075 + (WING_HALF_WIDTH - 0.075) * min(1.0, t / 0.20)
        ring_centers.append(center)
        ring_widths.append(width)
    for cap_angle in (24.0, 43.0, 60.0, 74.0, 84.0):
        angle = math.radians(cap_angle)
        ring_centers.append(end + axis * WING_HALF_WIDTH * math.sin(angle))
        ring_widths.append(WING_HALF_WIDTH * math.cos(angle))
    for center, width in zip(ring_centers, ring_widths, strict=True):
        values: list[int] = []
        thickness = max(0.012, WING_HALF_THICKNESS * (0.62 + 0.38 * width / WING_HALF_WIDTH))
        for segment in range(segments):
            angle = math.tau * segment / segments
            position = center + broad * math.cos(angle) * width + thick * math.sin(angle) * thickness
            values.append(len(vertices))
            vertices.append(tuple(position))
        rings.append(values)
    faces: list[tuple[int, ...]] = []
    for ring in range(len(rings) - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            faces.append((rings[ring][segment], rings[ring][nxt],
                          rings[ring + 1][nxt], rings[ring + 1][segment]))
    root_center = len(vertices)
    tip_center = root_center + 1
    vertices.extend((tuple(root), tuple(ring_centers[-1] + axis * 0.012)))
    for segment in range(segments):
        nxt = (segment + 1) % segments
        faces.append((root_center, rings[0][nxt], rings[0][segment]))
        faces.append((tip_center, rings[-1][segment], rings[-1][nxt]))
    mesh = bpy.data.meshes.new(f"PaddleWing{side:+.0f}")
    mesh.from_pydata(vertices, [], faces)
    mesh.update(calc_edges=True)
    obj = bpy.data.objects.new(mesh.name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(materials["dark"])
    obj.data.materials.append(materials["cream"])
    smooth_mesh(obj)
    for polygon in obj.data.polygons:
        center = polygon.center
        polygon.material_index = int(center.y < -0.020 and abs(center.x) < 0.560
                                     and center.z < 1.080)
    return obj


def add_tail_fan(materials: dict[str, bpy.types.Material]) -> None:
    for index in range(5):
        offset = index - 2
        root = Vector((0.0, 0.335, 0.440))
        tip = Vector((offset * 0.070, 0.590 - abs(offset) * 0.030,
                      0.365 + abs(offset) * 0.030))
        axis = (tip - root).normalized()
        broad = Vector((1.0, 0.0, 0.0))
        thick = axis.cross(broad).normalized()
        vertices: list[tuple[float, float, float]] = []
        rings: list[list[int]] = []
        segments = 14
        for ring in range(9):
            t = ring / 8.0
            center = root.lerp(tip, t)
            width = 0.025 + 0.062 * math.sin(math.pi * (0.05 + t * 0.90)) ** 0.70
            values: list[int] = []
            for segment in range(segments):
                angle = math.tau * segment / segments
                position = center + broad * math.cos(angle) * width + thick * math.sin(angle) * 0.025
                values.append(len(vertices))
                vertices.append(tuple(position))
            rings.append(values)
        faces: list[tuple[int, ...]] = []
        for ring in range(len(rings) - 1):
            for segment in range(segments):
                nxt = (segment + 1) % segments
                faces.append((rings[ring][segment], rings[ring][nxt],
                              rings[ring + 1][nxt], rings[ring + 1][segment]))
        root_center = len(vertices)
        tip_center = root_center + 1
        vertices.extend((tuple(root), tuple(tip + axis * 0.026)))
        for segment in range(segments):
            nxt = (segment + 1) % segments
            faces.append((root_center, rings[0][nxt], rings[0][segment]))
            faces.append((tip_center, rings[-1][segment], rings[-1][nxt]))
        mesh = bpy.data.meshes.new(f"TailFeather{index}")
        mesh.from_pydata(vertices, [], faces)
        mesh.update(calc_edges=True)
        feather = bpy.data.objects.new(mesh.name, mesh)
        bpy.context.scene.collection.objects.link(feather)
        feather.data.materials.append(materials["dark"])
        smooth_mesh(feather)


def add_feet(materials: dict[str, bpy.types.Material]) -> None:
    for side in (-1.0, 1.0):
        add_ico_ellipsoid(f"Foot{side:+.0f}",
                          (side * FOOT_CENTER_X, FOOT_CENTER_Y, FOOT_CENTER_Z),
                          FOOT_RADII, 4, materials["feet"])
        for toe in (-1, 0, 1):
            add_ico_ellipsoid(f"Toe{side:+.0f}_{toe:+d}",
                              (side * FOOT_CENTER_X + toe * 0.060,
                               FOOT_CENTER_Y - 0.150, 0.104),
                              (0.050, 0.112, 0.046), 3, materials["feet"])
            add_ico_ellipsoid(f"Claw{side:+.0f}_{toe:+d}",
                              (side * FOOT_CENTER_X + toe * 0.060,
                               FOOT_CENTER_Y - 0.252, 0.101),
                              (0.021, 0.030, 0.015), 2, materials["claw"])


def create_materials(material_dir: Path) -> dict[str, bpy.types.Material]:
    return {
        "body_vertex": create_vertex_feather_material(
            "PreviewBodyFeatherSurface", material_dir / "hero_penguin_v11_dark_albedo_tile.png"),
        "dark": create_feather_material(
            "DeepNavyFeather", (0.022, 0.060, 0.125, 1.0),
            material_dir / "hero_penguin_v11_dark_albedo_tile.png", 0.82),
        "cream": create_feather_material(
            "WarmCreamFeather", (0.72, 0.62, 0.46, 1.0),
            material_dir / "hero_penguin_v11_cream_albedo_tile.png", 0.78),
        "warm": create_solid_material("WarmCheekAccent", (0.62, 0.20, 0.035, 1.0), 0.72),
        "cyan": create_solid_material("RestrainedCyanPaint", (0.035, 0.28, 0.32, 1.0), 0.76),
        "sclera": create_solid_material("WarmSclera", (0.76, 0.69, 0.56, 1.0), 0.46, subsurface=0.025),
        "lid": create_solid_material("IntegratedNavyUpperLid", (0.014, 0.042, 0.095, 1.0), 0.72),
        "iris": create_solid_material("BlueGrayIris", (0.15, 0.36, 0.52, 1.0), 0.32),
        "pupil": create_solid_material("SoftBlackPupil", (0.005, 0.010, 0.017, 1.0), 0.28),
        "catchlight": create_solid_material("EyeCatchlight", (0.97, 0.98, 0.95, 1.0), 0.18),
        "bill_upper": create_solid_material("GoldenUpperBill", (0.95, 0.39, 0.035, 1.0), 0.54),
        "bill_lower": create_solid_material("TuckedLowerBill", (0.80, 0.25, 0.018, 1.0), 0.58),
        "mouth": create_solid_material("BillMouthSeam", (0.15, 0.026, 0.010, 1.0), 0.72),
        "feet": create_solid_material("OrangeFeet", (0.90, 0.36, 0.035, 1.0), 0.60),
        "claw": create_solid_material("ToeClaw", (0.11, 0.040, 0.020, 1.0), 0.72),
    }


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_area(name: str, location: tuple[float, float, float], power: float,
             size: float, color: tuple[float, float, float]) -> None:
    data = bpy.data.lights.new(name, "AREA")
    data.energy = power
    data.shape = "DISK"
    data.size = size
    data.color = color
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    look_at(obj, (0.0, 0.0, 0.90))


def setup_stage() -> bpy.types.Object:
    floor_material = create_solid_material("NeutralGrayFloor", (0.145, 0.160, 0.178, 1.0), 0.94)
    bpy.ops.mesh.primitive_plane_add(size=200.0, location=(0.0, 0.0, 0.020))
    floor = bpy.context.object
    floor.name = "NeutralGrayFloor"
    floor.data.materials.append(floor_material)
    add_area("SoftKey", (-3.2, -4.0, 4.8), 390.0, 4.5, (0.88, 0.94, 1.0))
    add_area("WarmFill", (3.2, -2.2, 2.8), 150.0, 4.0, (1.0, 0.82, 0.66))
    add_area("CoolRim", (0.5, 3.5, 4.0), 135.0, 4.0, (0.50, 0.72, 1.0))
    camera_data = bpy.data.cameras.new("ProofCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 2.14
    camera = bpy.data.objects.new("ProofCamera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    bpy.context.scene.camera = camera
    return camera


def render_views(camera: bpy.types.Object, output_dir: Path) -> None:
    views = {
        "front": ((0.0, -5.0, 1.08), (0.0, 0.0, 0.94)),
        "threequarter": ((3.2, -4.2, 1.55), (0.0, 0.0, 0.96)),
        "true_side": ((5.0, -0.04, 1.15), (0.0, 0.0, 0.94)),
    }
    for name, (location, target) in views.items():
        camera.location = location
        look_at(camera, target)
        bpy.context.scene.render.filepath = str(output_dir / f"hero_penguin_v12_blender_{name}.png")
        bpy.ops.render.render(write_still=True)
        print(f"[hero-v12-proof] rendered {name}")


def main() -> None:
    if tuple(bpy.app.version[:3]) != EXPECTED_BLENDER:
        raise RuntimeError(f"expected Blender 5.2.0, found {bpy.app.version_string}")
    args = parse_args()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    reset_scene()
    materials = create_materials(args.material_dir.resolve())
    body = voxel_fuse_body()
    cut_eye_sockets(body)
    assign_body_materials(body, materials)
    add_eye_set(materials)
    add_bill(materials)
    add_paddle(-1.0, materials)
    add_paddle(1.0, materials)
    add_tail_fan(materials)
    add_feet(materials)
    camera = setup_stage()
    activate(body)
    body.data.calc_loop_triangles()
    print(f"[hero-v12-proof] fused_body_triangles={len(body.data.loop_triangles)}")
    blend_path = output_dir / "hero_penguin_v12_source_proof.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=False, compress=True)
    render_views(camera, output_dir)
    print(f"[hero-v12-proof] source={blend_path}")
    print("PRODUCTION_READY=false")


if __name__ == "__main__":
    main()
