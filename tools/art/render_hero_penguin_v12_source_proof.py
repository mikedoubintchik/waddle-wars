#!/usr/bin/env python3
"""Build and render V12 fused-sculpt source proof in Blender 5.2.

This script intentionally creates no rig, runtime GLB, wrapper scene, or asset
overwrite. It saves one durable source-only .blend and three PNG stills for
front/three-quarter/true-side art review before production integration.
Cycles is pinned to CPU with bounded threads so this proof can run alongside
Godot performance diagnostics without competing for GPU resources.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hero_penguin_v12_design import (  # noqa: E402
    BILL_LOWER_SECTIONS,
    BILL_UPPER_SECTIONS,
    bill_section_height,
    EYE_CENTER_X,
    EYE_CENTER_Z,
    EYE_BURY_DEPTH,
    EYE_RADII,
    FOOT_CENTER_X,
    FOOT_CENTER_Y,
    FOOT_CENTER_Z,
    FOOT_RADII,
    SCULPT_VERSION,
    eye_patch_faces,
    eye_surface_frame,
    eye_gaze_center,
    upper_lid_pigment_weight,
    LIMBAL_RADII,
    IRIS_RADII,
    PUPIL_RADII,
    paddle_cross_section,
    project_eye_patch,
    sculpt_body_field,
    WING_HALF_THICKNESS,
    WING_HALF_WIDTH,
    WING_ROOT,
    WING_CONTROL,
    WING_TIP,
)
from hero_penguin_v12_materials import apply_feather_review  # noqa: E402
from hero_penguin_eye_pigment import iris_linear_rgba  # noqa: E402
from hero_penguin_v12_feather_detail_recipe import apply_feather_detail_recipe  # noqa: E402


EXPECTED_BLENDER = (5, 2, 0)
ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "qa_shots/hero/v12_source_proof"
DEFAULT_MATERIAL = ROOT / "qa_shots/hero/material_v11"


def parse_args() -> argparse.Namespace:
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--material-dir", type=Path, default=DEFAULT_MATERIAL)
    parser.add_argument("--samples", type=int, default=48)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--feather-recipe", choices=("baseline", "detail-01"), default="baseline")
    return parser.parse_args(values)


def reset_scene(samples: int, threads: int) -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials,
                       bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            datablocks.remove(datablock)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = max(1, samples)
    scene.cycles.use_denoising = True
    scene.render.threads_mode = "FIXED"
    scene.render.threads = max(1, threads)
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
    # Neutralized 8-bit albedo is unsuitable as height: quantized pigment
    # creates broad false ridges. Evaluate silhouette with smooth normals.
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
    # Feather normal integration remains a later material gate; this source
    # proof must not mistake quantized albedo height for sculpt geometry.
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
    """Extract the smooth field itself instead of remeshing faceted spheres.

    A hard union of low-resolution icospheres preserved their broad facets and
    shoulder seams. Marching tetrahedra samples the V12 smooth union directly;
    edge deduplication leaves one closed, shared-vertex sculpt surface.
    """
    body = extract_field_mesh("HeroBodyV12SmoothField", body_field,
                              ((-0.66, 0.67), (-0.62, 0.59), (-0.02, 1.94)), 0.014)
    refine_orbital_surface(body)
    return body


def refine_orbital_surface(body: bpy.types.Object) -> None:
    """Refine shared head topology locally, then project onto the same field.

    Two edge subdivisions resolve the small lid join without a global 3.5 mm
    voxel grid. Border edges are shared: no separate patch or unwelded seam.
    """
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(body.data)

    def near_eye(point):
        return 0.045 < abs(point.x) < 0.40 and point.y < -0.19 and 1.43 < point.z < 1.77

    for _ in range(2):
        edges = [edge for edge in bm.edges if any(near_eye(v.co) for v in edge.verts)]
        bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=True)
        vertices = [vertex for vertex in bm.verts if near_eye(vertex.co)]
        points = np.asarray([tuple(vertex.co) for vertex in vertices])
        epsilon = np.eye(3) * 1e-5
        for _ in range(4):
            field = body_field(points)
            gradient = np.stack([(body_field(points + offset) - body_field(points - offset)) / 2e-5
                                 for offset in epsilon], axis=-1)
            move = field[:, None] * gradient / np.maximum(np.sum(gradient * gradient, axis=-1)[:, None], 1e-8)
            length = np.linalg.norm(move, axis=-1)
            move *= np.minimum(1.0, 0.008 / np.maximum(length, 1e-12))[:, None]
            points -= move
        for vertex, point in zip(vertices, points):
            vertex.co = point
    if any(not edge.is_manifold for edge in bm.edges):
        raise RuntimeError("orbital refinement broke closed shared body topology")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    smooth_mesh(body)


def extract_field_mesh(name: str, evaluator, bounds, step: float) -> bpy.types.Object:
    """Shared-edge, closed implicit surface; used for body and fused webbed feet."""
    axes = tuple(np.arange(low, high, step) for low, high in bounds)
    grid = np.stack(np.meshgrid(*axes, indexing="ij"), axis=-1)
    field = evaluator(grid)
    offsets = ((0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0),
               (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1))
    corners = np.stack([field[x:field.shape[0]-1+x, y:field.shape[1]-1+y,
                               z:field.shape[2]-1+z] for x, y, z in offsets])
    cells = np.argwhere((corners.min(axis=0) <= 0.0) & (corners.max(axis=0) >= 0.0))
    tetrahedra = ((0, 5, 1, 6), (0, 1, 2, 6), (0, 2, 3, 6),
                  (0, 3, 7, 6), (0, 7, 4, 6), (0, 4, 5, 6))
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int]] = []
    edge_vertices: dict[tuple[int, int], int] = {}
    shape = field.shape
    for cell in cells:
        positions = [tuple(int(cell[i]) + offset[i] for i in range(3)) for offset in offsets]
        values = [float(field[p]) for p in positions]
        points = [grid[p] for p in positions]
        ids = [(p[0] * shape[1] + p[1]) * shape[2] + p[2] for p in positions]

        def crossing(a: int, b: int) -> int:
            key = tuple(sorted((ids[a], ids[b])))
            if key not in edge_vertices:
                t = values[a] / (values[a] - values[b])
                edge_vertices[key] = len(vertices)
                vertices.append(tuple(points[a] + (points[b] - points[a]) * t))
            return edge_vertices[key]

        for tetra in tetrahedra:
            inside = [i for i in tetra if values[i] <= 0.0]
            outside = [i for i in tetra if values[i] > 0.0]
            if len(inside) in (0, 4):
                continue
            if len(inside) == 1:
                faces.append(tuple(crossing(inside[0], i) for i in outside))
            elif len(inside) == 3:
                faces.append(tuple(crossing(outside[0], i) for i in inside))
            else:
                a, b = inside
                c, d = outside
                ac, ad, bc, bd = crossing(a, c), crossing(a, d), crossing(b, c), crossing(b, d)
                faces.extend(((ac, ad, bd), (ac, bd, bc)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update(calc_edges=True)
    body = bpy.data.objects.new(mesh.name, mesh)
    bpy.context.scene.collection.objects.link(body)
    # Tetra cases above are deliberately independent of inside winding.
    # Recalculate consistent outward normals on the closed field manifold.
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    smooth_mesh(body)
    return body


def volumes_field(points: np.ndarray, volumes, smooth_radius: float) -> np.ndarray:
    field = np.full(points.shape[:-1], 100.0)
    for center, radii in volumes:
        p = points - np.asarray(center)
        r = np.asarray(radii)
        k0 = np.linalg.norm(p / r, axis=-1)
        k1 = np.linalg.norm(p / (r * r), axis=-1)
        distance = k0 * (k0 - 1.0) / np.maximum(k1, 1e-8)
        blend = np.maximum(smooth_radius - np.abs(field - distance), 0.0) / smooth_radius
        field = np.minimum(field, distance) - blend * blend * smooth_radius * 0.25
    return field


def body_field(points: np.ndarray) -> np.ndarray:
    return sculpt_body_field(points)


def body_front_y(x: float, z: float) -> float:
    low, high = -0.70, 0.05
    for _iteration in range(22):
        middle = (low + high) * 0.5
        if float(body_field(np.asarray((x, middle, z)))) > 0.0:
            low = middle
        else:
            high = middle
    return (low + high) * 0.5


def eye_frame(side: float) -> tuple[Vector, Vector, Vector, Vector]:
    """Frozen base-skull frame; the final implicit lid cannot move the eyes."""
    return tuple(Vector(value) for value in eye_surface_frame(side))


def frame_position(frame, x: float, depth: float, z: float) -> Vector:
    origin, across, normal, up = frame
    return origin + across * x + normal * depth + up * z


def surface_depth(frame, x: float, z: float) -> float:
    low, high = -0.24, 0.12
    for _iteration in range(18):
        middle = (low + high) * 0.5
        point = np.asarray(frame_position(frame, x, middle, z))
        if float(body_field(point)) > 0.0:
            high = middle
        else:
            low = middle
    return (low + high) * 0.5


def eye_depth(x: float, z: float) -> float:
    q = (x / EYE_RADII[0]) ** 2 + (z / EYE_RADII[2]) ** 2
    return -EYE_BURY_DEPTH + EYE_RADII[1] * math.sqrt(max(0.0, 1.0 - q))


def body_paint(point: Vector):
    # Paint follows continuous shape, not hard per-triangle material islands.
    front = -point.y / max(0.001, math.hypot(point.x, point.y))
    angle = abs(math.atan2(point.x, -point.y))

    def ellipse(x: float, z: float, rx: float, rz: float) -> float:
        return ((point.x - x) / rx) ** 2 + ((point.z - z) / rz) ** 2

    cheek = min(ellipse(-0.162, 1.394, 0.235, 0.159),
                ellipse(0.162, 1.394, 0.235, 0.159))
    chin = ellipse(0.0, 1.225, 0.308, 0.244)
    chest = ellipse(0.0, 0.768, 0.464, 0.698)
    orbit = min(ellipse(-EYE_CENTER_X, EYE_CENTER_Z - 0.019, 0.120, 0.125),
                ellipse(EYE_CENTER_X, EYE_CENTER_Z - 0.019, 0.120, 0.125))
    bib = (1.0 - smoothstep(0.94, 1.045, min(chest, chin))) * smoothstep(0.30, 0.39, front)
    face = (1.0 - smoothstep(0.94, 1.045, min(cheek, orbit))) * smoothstep(-0.02, 0.09, front)
    cream = max(bib, face)
    # The hood descends only as a narrow central bridge, not a heavy mask over
    # both eyes. Upper orbital cream belongs to the same painted skull surface.
    bridge = (1.0 - smoothstep(0.027, 0.050, abs(point.x)))
    bridge *= smoothstep(1.442 + 0.75 * abs(point.x), 1.470 + 0.75 * abs(point.x), point.z)
    cream *= 1.0 - bridge
    cream *= 1.0 - upper_lid_pigment_weight(point)
    face_light = smoothstep(1.25, 1.43, point.z)
    ivory = tuple(a + (b - a) * face_light for a, b in
                  zip((0.73, 0.62, 0.445, 1.0), (0.82, 0.75, 0.595, 1.0)))
    throat = 0.09 * math.exp(-((point.z - 1.250) / 0.075) ** 2)
    ivory = tuple(a + (b - a) * throat for a, b in zip(ivory, (0.84, 0.56, 0.255, 1.0)))
    result = tuple(dark + (light - dark) * cream for dark, light in
                   zip((0.017, 0.027, 0.040, 1.0), ivory))
    # Warm ear patches start on the side plane: no round orange frontal blush.
    ear_field = ((angle - 1.46) / 0.40) ** 2 + ((point.z - 1.411) / 0.078) ** 2
    ear = 1.0 - smoothstep(0.86, 1.10, ear_field)
    stroke_u = (angle - 1.52) / 0.45
    stroke_width = 0.015 * math.sqrt(max(0.0, 1.0 - stroke_u * stroke_u))
    stripe_z = 1.232 + 0.040 * (angle - 1.10) + 0.017 * math.sin((angle - 1.10) * 3.3)
    stripe = 1.0 - smoothstep(max(0.0, stroke_width - 0.003), stroke_width + 0.002,
                              abs(point.z - stripe_z))
    stripe *= 1.0 - smoothstep(0.91, 1.0, abs(stroke_u))
    result = tuple(a + (b - a) * ear for a, b in zip(result, (0.63, 0.270, 0.037, 1.0)))
    pigment = tuple(a + (b - a) * stripe for a, b in zip(result, (0.065, 0.34, 0.38, 1.0)))
    # Preserve the actual compositing weights before variable ivory/throat
    # pigments obscure them. The atlas must not infer species masks from RGB.
    masks = (cream * (1.0 - ear) * (1.0 - stripe), ear * (1.0 - stripe), stripe, 1.0)
    return pigment, masks


def body_color(point: Vector) -> tuple[float, float, float, float]:
    return body_paint(point)[0]


def assign_source_masks(obj, values) -> None:
    if len(values) != len(obj.data.vertices):
        raise RuntimeError("source semantic masks must cover every vertex")
    attribute = obj.data.color_attributes.new(name="SourceSemanticMasks", type="FLOAT_COLOR", domain="POINT")
    for index, value in enumerate(values):
        if (len(value) != 4 or any(not math.isfinite(channel) or not 0 <= channel <= 1 for channel in value)
                or sum(value[:3]) > 1.0000001):
            raise RuntimeError("invalid source semantic compositing weights")
        attribute.data[index].color = value
    obj["source_mask_contract"] = "feather-palette-weights-v1"


def smoothstep(low: float, high: float, value: float) -> float:
    t = min(1.0, max(0.0, (value - low) / (high - low)))
    return t * t * (3.0 - 2.0 * t)


def assign_body_materials(body: bpy.types.Object, materials: dict[str, bpy.types.Material]) -> None:
    body.data.materials.clear()
    body.data.materials.append(materials["body_vertex"])
    color = body.data.color_attributes.new(name="PreviewColor", type="FLOAT_COLOR", domain="POINT")
    masks = []
    for vertex in body.data.vertices:
        pigment, mask = body_paint(vertex.co)
        color.data[vertex.index].color = pigment
        masks.append(mask)
    assign_source_masks(body, masks)
    for polygon in body.data.polygons:
        polygon.material_index = 0


def create_almond_lens(name: str, side: float, material: bpy.types.Material) -> bpy.types.Object:
    """A genuinely rounded, mostly buried globe, not a surface-facing lens."""
    frame = eye_frame(side)
    origin, across, normal, up = frame
    globe = add_ico_ellipsoid(name, tuple(origin - normal * EYE_BURY_DEPTH), EYE_RADII,
                              5, material)
    globe.rotation_euler = Matrix((across, -normal, up)).transposed().to_euler()
    return globe


def eye_paint_disc(name: str, side: float, center: tuple[float, float],
                   radii: tuple[float, float], offset: float,
                   material: bpy.types.Material) -> bpy.types.Object:
    """Geodesic pigment patch on the ellipsoid, including turned-in gazes.

    Adding x/z radii to a shifted eye disc crosses the ellipsoid's front
    domain and clamps into broken flat slivers. Project a tangent-space patch
    radially onto the full globe instead; every vertex remains on its surface.
    """
    segments, rings = 64, 12
    frame = eye_frame(side)
    cx, cz = center
    ellipsoid = Vector(EYE_RADII)
    patch_center = Vector((cx, eye_depth(cx, cz) + EYE_BURY_DEPTH, cz))
    patch_normal = Vector(tuple(patch_center[i] / ellipsoid[i] ** 2 for i in range(3))).normalized()
    patch_across = patch_normal.cross(Vector((0.0, 0.0, 1.0))).normalized()
    patch_up = patch_across.cross(patch_normal).normalized()

    def patch_point(x: float, z: float) -> tuple[float, float, float]:
        point = patch_center + patch_across * x + patch_up * z
        point = Vector(project_eye_patch(point, offset))
        return tuple(frame_position(frame, point.x, point.y - EYE_BURY_DEPTH, point.z))

    vertices = [patch_point(0.0, 0.0)]
    iris_colors = [iris_linear_rgba(0.0, 0.0)] if name.startswith("Iris") else []
    faces = eye_patch_faces(segments, rings)
    for ring in range(1, rings + 1):
        radius = ring / rings
        for segment in range(segments):
            angle = math.tau * segment / segments
            x = radii[0] * radius * math.cos(angle)
            z = radii[1] * radius * math.sin(angle)
            vertices.append(patch_point(x, z))
            if iris_colors:
                iris_colors.append(iris_linear_rgba(radius * math.cos(angle), radius * math.sin(angle)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update(calc_edges=True)
    if iris_colors:
        pigment = mesh.color_attributes.new(name="IrisPigment", type="FLOAT_COLOR", domain="POINT")
        for index, rgba in enumerate(iris_colors):
            pigment.data[index].color = rgba
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(material)
    smooth_mesh(obj)
    mesh.calc_loop_triangles()
    globe_center = frame[0] - frame[2] * EYE_BURY_DEPTH
    for triangle in mesh.loop_triangles:
        a, b, c = (mesh.vertices[index].co for index in triangle.vertices)
        outward = ((a + b + c) / 3.0) - globe_center
        if (b - a).cross(c - a).dot(outward) <= 1e-12:
            raise RuntimeError(f"eye pigment triangle is degenerate or inward: {name}/{triangle.index}")
    return obj


def add_eye_set(materials: dict[str, bpy.types.Material]) -> None:
    for side in (-1.0, 1.0):
        create_almond_lens(f"EmbeddedSclera{side:+.0f}", side, materials["sclera"])
        # Globe heading and gaze stay independent. A shared attentive target
        # keeps both irises readable above the lower cheek; no per-view aim.
        gaze = eye_gaze_center(side)
        eye_paint_disc(f"LimbalRing{side:+.0f}", side, gaze, LIMBAL_RADII,
                       0.0010, materials["pupil"])
        eye_paint_disc(f"Iris{side:+.0f}", side, gaze, IRIS_RADII,
                       0.0016, materials["iris"])
        eye_paint_disc(f"Pupil{side:+.0f}", side, (gaze[0], gaze[1] - 0.004),
                       PUPIL_RADII, 0.0022, materials["pupil"])
        eye_paint_disc(f"Catchlight{side:+.0f}", side, (gaze[0] - 0.012, gaze[1] + 0.033),
                       (0.008, 0.011), 0.0028, materials["catchlight"])
        # Upper lid is part of HeroBodyV12SmoothField. Lower eye perimeter
        # intersects the cheek directly; no annular cover geometry remains.


def create_loft(name: str, sections: tuple[tuple[float, float, float, float], ...],
                material: bpy.types.Material, lobe: str = "") -> bpy.types.Object:
    segments = 48
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for y, width, height, center_z in sections:
        for segment in range(segments):
            angle = math.tau * segment / segments
            cosine = math.cos(angle)
            sine = math.sin(angle)
            z = bill_section_height(y, width, height, center_z, cosine, sine, lobe)
            vertices.append((cosine * width, y, z))
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
    subdivision = obj.modifiers.new("SoftBillSculpt", "SUBSURF")
    subdivision.levels = 2
    bpy.ops.object.modifier_apply(modifier=subdivision.name)
    return obj


def add_bill(materials: dict[str, bpy.types.Material]) -> None:
    create_loft("UpperBillRoundedWedge", BILL_UPPER_SECTIONS, materials["bill_upper"], "upper")
    create_loft("LowerBillTuckedWedge", BILL_LOWER_SECTIONS, materials["bill_lower"], "lower")
    seam_sections = tuple((y, width * 0.997, 0.0021, center_z)
                          for y, width, height, center_z in BILL_UPPER_SECTIONS)
    create_loft("BillMouthSeam", seam_sections, materials["mouth"])
    for side in (-1.0, 1.0):
        nostril = add_ico_ellipsoid(f"Nostril{side:+.0f}",
                                   (side * 0.042, -0.408, 1.456),
                                   (0.0045, 0.008, 0.0025), 3, materials["mouth"])
        nostril.rotation_euler.y = side * math.radians(12.0)


def add_paddle(side: float, materials: dict[str, bpy.types.Material]) -> bpy.types.Object:
    root = Vector((side * WING_ROOT[0], WING_ROOT[1], WING_ROOT[2]))
    end = Vector((side * WING_TIP[0], WING_TIP[1], WING_TIP[2]))
    control = Vector((side * WING_CONTROL[0], WING_CONTROL[1], WING_CONTROL[2]))
    segments = 48
    rings: list[list[int]] = []
    vertices: list[tuple[float, float, float]] = []
    colors: list[tuple[float, ...]] = []
    masks: list[tuple[float, ...]] = []
    for ring in range(45):
        t = ring / 44.0
        center = root * (1.0 - t) ** 2 + control * (2.0 * t * (1.0 - t)) + end * t * t
        axis = ((control - root) * (1.0 - t) + (end - control) * t).normalized()
        broad, thick = (Vector(value) for value in paddle_cross_section(tuple(axis), side))
        # Broad shoulder, gently bowed leading edge, long narrow distal half.
        width_keys = ((0.0, 0.055), (0.18, 0.102), (0.40, 0.095),
                      (0.65, 0.065), (0.84, 0.039), (0.93, 0.026),
                      (0.97, 0.017), (1.0, 0.004))
        width = 0.004
        for (t0, w0), (t1, w1) in zip(width_keys, width_keys[1:]):
            if t0 <= t <= t1:
                blend = smoothstep(t0, t1, t)
                width = w0 + (w1 - w0) * blend
                break
        width *= WING_HALF_WIDTH / 0.105
        thickness = max(0.003, WING_HALF_THICKNESS * (1.0 - t) ** 0.54)
        values: list[int] = []
        for segment in range(segments):
            angle = math.tau * segment / segments
            position = center + broad * math.cos(angle) * width + thick * math.sin(angle) * thickness
            values.append(len(vertices))
            vertices.append(tuple(position))
            # A restrained cream inner edge; never a large separate mitten.
            cream = (1.0 - smoothstep(-0.80, -0.25, math.cos(angle)))
            cream *= smoothstep(0.14, 0.27, t) * (1.0 - smoothstep(0.84, 0.98, t))
            cream *= smoothstep(0.0, 0.6, -thick.y * math.sin(angle))
            colors.append(tuple(dark + (light - dark) * cream for dark, light in
                                zip((0.017, 0.027, 0.040, 1.0), (0.76, 0.665, 0.490, 1.0))))
            masks.append((cream, 0.0, 0.0, 1.0))
        rings.append(values)
    faces: list[tuple[int, ...]] = []
    for ring in range(len(rings) - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            faces.append((rings[ring][segment], rings[ring][nxt],
                          rings[ring + 1][nxt], rings[ring + 1][segment]))
    root_center = len(vertices)
    tip_center = root_center + 1
    vertices.extend((tuple(root), tuple(end + axis * 0.004)))
    colors.extend(((0.017, 0.027, 0.040, 1.0), (0.017, 0.027, 0.040, 1.0)))
    masks.extend(((0.0, 0.0, 0.0, 1.0), (0.0, 0.0, 0.0, 1.0)))
    for segment in range(segments):
        nxt = (segment + 1) % segments
        faces.append((root_center, rings[0][nxt], rings[0][segment]))
        faces.append((tip_center, rings[-1][segment], rings[-1][nxt]))
    mesh = bpy.data.meshes.new(f"PaddleWing{side:+.0f}")
    mesh.from_pydata(vertices, [], faces)
    mesh.update(calc_edges=True)
    obj = bpy.data.objects.new(mesh.name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(materials["body_vertex"])
    color = mesh.color_attributes.new(name="PreviewColor", type="FLOAT_COLOR", domain="POINT")
    for index, value in enumerate(colors):
        color.data[index].color = value
    assign_source_masks(obj, masks)
    smooth_mesh(obj)
    return obj


def add_tail_fan(materials: dict[str, bpy.types.Material]) -> None:
    for index in range(5):
        offset = index - 2
        root = Vector((offset * 0.026, 0.330, 0.391))
        tip = Vector((offset * 0.062, 0.486 - abs(offset) * 0.009,
                      0.294 + abs(offset) * 0.018))
        axis = (tip - root).normalized()
        broad = Vector((1.0, 0.0, 0.0))
        thick = axis.cross(broad).normalized()
        vertices: list[tuple[float, float, float]] = []
        rings: list[list[int]] = []
        segments = 24
        for ring in range(23):
            t = ring / 22.0
            center = root.lerp(tip, t)
            center.z += 0.020 * math.sin(math.pi * t)
            width = 0.010 + 0.083 * (1.0 - t) ** 0.45
            values: list[int] = []
            for segment in range(segments):
                angle = math.tau * segment / segments
                thickness = 0.006 + 0.034 * (1.0 - t) ** 0.35
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
        vertices.extend((tuple(root), tuple(tip + axis * 0.007)))
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


def add_tapered_claw(name: str, center_x: float, toe_y: float,
                     material: bpy.types.Material) -> None:
    """A short down-curving tip emerges from the webbed toe, not a front button."""
    rings, segments = 9, 18
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for ring in range(rings):
        t = ring / (rings - 1)
        y = toe_y - 0.061 - 0.039 * t
        z = 0.073 - 0.025 * t * t
        width = max(0.0008, 0.013 * (1.0 - t) ** 0.65)
        height = max(0.0008, 0.008 * (1.0 - t) ** 0.65)
        for segment in range(segments):
            angle = math.tau * segment / segments
            vertices.append((center_x + width * math.cos(angle), y, z + height * math.sin(angle)))
    for ring in range(rings - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            faces.append((ring * segments + segment, ring * segments + nxt,
                          (ring + 1) * segments + nxt, (ring + 1) * segments + segment))
    faces.append(tuple(reversed(range(segments))))
    faces.append(tuple((rings - 1) * segments + index for index in range(segments)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update(calc_edges=True)
    claw = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(claw)
    claw.data.materials.append(material)
    smooth_mesh(claw)


def add_feet(materials: dict[str, bpy.types.Material]) -> None:
    for side in (-1.0, 1.0):
        center_x = side * FOOT_CENTER_X
        volumes = [((center_x, FOOT_CENTER_Y, FOOT_CENTER_Z), FOOT_RADII),
                   ((center_x, -0.174, 0.075), (0.130, 0.084, 0.035)),
                   ((center_x, 0.008, 0.129), (0.080, 0.079, 0.062))]
        for toe in (-1, 0, 1):
            toe_y = -0.238 - (0.019 if toe == 0 else 0.0)
            volumes.append(((center_x + toe * 0.075, toe_y, 0.073),
                            (0.042, 0.077, 0.038)))
            add_tapered_claw(f"Claw{side:+.0f}_{toe:+d}", center_x + toe * 0.075,
                             toe_y, materials["claw"])
        foot = extract_field_mesh(f"FusedWebbedFoot{side:+.0f}",
                                   lambda points: volumes_field(points, volumes, 0.015),
                                   ((center_x - 0.18, center_x + 0.18),
                                    (-0.38, 0.15), (0.0, 0.24)), 0.006)
        foot.data.materials.append(materials["feet"])


def create_materials(material_dir: Path) -> dict[str, bpy.types.Material]:
    materials = {
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
        "sclera": create_solid_material("WarmSclera", (0.91, 0.88, 0.77, 1.0), 0.38, subsurface=0.025),
        "lid": create_solid_material("IntegratedNavyUpperLid", (0.014, 0.042, 0.095, 1.0), 0.72),
        "iris": create_solid_material("BlueGrayIris", (0.09, 0.22, 0.29, 1.0), 0.32),
        "pupil": create_solid_material("SoftBlackPupil", (0.005, 0.010, 0.017, 1.0), 0.28),
        "catchlight": create_solid_material("EyeCatchlight", (0.97, 0.98, 0.95, 1.0), 0.18),
        "bill_upper": create_solid_material("GoldenUpperBill", (0.95, 0.39, 0.035, 1.0), 0.54),
        "bill_lower": create_solid_material("TuckedLowerBill", (0.80, 0.25, 0.018, 1.0), 0.58),
        "mouth": create_solid_material("BillMouthSeam", (0.15, 0.026, 0.010, 1.0), 0.72),
        "feet": create_solid_material("OrangeFeet", (0.90, 0.36, 0.035, 1.0), 0.60),
        "claw": create_solid_material("ToeClaw", (0.11, 0.040, 0.020, 1.0), 0.72),
    }
    iris = materials["iris"]
    pigment = iris.node_tree.nodes.new("ShaderNodeVertexColor")
    pigment.layer_name = "IrisPigment"
    iris.node_tree.links.new(pigment.outputs["Color"],
                             iris.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
    return materials


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
    if output_dir.exists() and any(output_dir.iterdir()):
        raise RuntimeError("Source proof output contains earlier evidence; choose a fresh directory")
    output_dir.mkdir(parents=True, exist_ok=True)
    reset_scene(args.samples, args.threads)
    materials = create_materials(args.material_dir.resolve())
    body = voxel_fuse_body()
    body["sculpt_version"] = SCULPT_VERSION
    body["production_ready"] = False
    # The continuous head occludes the buried eyes. Boolean cavities plus a
    # projected cover ring were the source of the rejected goggle-like face.
    assign_body_materials(body, materials)
    add_eye_set(materials)
    add_bill(materials)
    add_paddle(-1.0, materials)
    add_paddle(1.0, materials)
    add_tail_fan(materials)
    add_feet(materials)
    apply_feather_review(materials, args.material_dir.resolve())
    if args.feather_recipe == "detail-01":
        apply_feather_detail_recipe(materials, args.material_dir.resolve())
    body["source_feather_recipe"] = args.feather_recipe
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
