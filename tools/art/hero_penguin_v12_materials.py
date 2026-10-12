"""Source-only feather review materials using existing authored bitmap maps.

No generated shader noise or albedo-as-height shortcut. Mesh UVs orient the
existing normal field along the body, and the packed roughness is sampled.
This is a Blender shape/material proof, NOT a Compatibility acceptance result.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy


UV_LAYER = "FeatherReviewUV"


def assign_feather_uvs(obj: bpy.types.Object) -> None:
    """Cylindrical world-height UVs; unwrap seam per polygon before sampling.

    Texture repeat is native here (single tile per image), so seam duplicates
    outside [0,1] interpolate continuously without clamping or stretched faces.
    All components share physical feather scale instead of stretching one tile
    over each little cheek/lid/wing component's individual bounding box.
    """
    layer = obj.data.uv_layers.get(UV_LAYER) or obj.data.uv_layers.new(name=UV_LAYER)
    for polygon in obj.data.polygons:
        coords = []
        for index in polygon.vertices:
            vertex = obj.matrix_world @ obj.data.vertices[index].co
            if obj.name.startswith("PaddleWing"):
                # Thin broad paddles sit nearly tangent to the body's cylinder.
                # Cylindrical U collapses across that broad face and turns the
                # directional normal field into horizontal stretched bands.
                # A feather-scale blade projection retains width derivatives.
                coords.append((0.5 + (abs(vertex.x) * 0.95 + vertex.z * 0.30) / 2.4,
                               vertex.z / 1.80))
            else:
                coords.append((0.5 + math.atan2(vertex.x, -vertex.y) / math.tau,
                               vertex.z / 1.80))
        crossing = (not obj.name.startswith("PaddleWing")
                    and max(uv[0] for uv in coords) - min(uv[0] for uv in coords) > 0.5)
        for loop, (u, v) in zip(polygon.loop_indices, coords):
            # Short laid feathers, not large embossed tufts. Integer horizontal
            # repeats preserve the closed body's seam; height has no wrap join.
            layer.data[loop].uv = (3.0 * (u + (1.0 if crossing and u < 0.5 else 0.0)), 2.5 * v)


def image_texture(nodes, links, uv, path: Path, *, color: bool):
    if not path.is_file():
        raise RuntimeError(f"Missing source feather map: {path}")
    image = bpy.data.images.load(str(path), check_existing=True)
    image.colorspace_settings.name = "sRGB" if color else "Non-Color"
    image.pack()
    node = nodes.new("ShaderNodeTexImage")
    node.image = image
    node.extension = "REPEAT"
    node.interpolation = "Linear"
    links.new(uv, node.inputs["Vector"])
    return node.outputs["Color"]


def mix_rgb(nodes, links, first, second, factor, mode="MIX"):
    node = nodes.new("ShaderNodeMixRGB")
    node.blend_type = mode
    if isinstance(factor, (int, float)):
        node.inputs[0].default_value = factor
    else:
        links.new(factor, node.inputs[0])
    links.new(first, node.inputs[1])
    links.new(second, node.inputs[2])
    return node.outputs[0]


def configure_material(material: bpy.types.Material, material_dir: Path,
                       region: str, *, vertex_paint: bool) -> None:
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    principled = nodes.get("Principled BSDF")
    # Keep only the BSDF/output; previous disconnected trial nodes must not
    # obscure which textures are actually being evaluated in a saved proof.
    for node in list(nodes):
        if node.type not in {"BSDF_PRINCIPLED", "OUTPUT_MATERIAL"}:
            nodes.remove(node)
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = UV_LAYER
    uv_output = uv.outputs["UV"]
    base = nodes.new("ShaderNodeVertexColor" if vertex_paint else "ShaderNodeRGB")
    if vertex_paint:
        base.layer_name = "PreviewColor"
    else:
        base.outputs[0].default_value = material.diffuse_color
    base_output = base.outputs["Color"]
    if vertex_paint:
        value = nodes.new("ShaderNodeRGBToBW")
        links.new(base_output, value.inputs["Color"])
        cream = nodes.new("ShaderNodeMapRange")
        cream.clamp = True
        cream.inputs["From Min"].default_value = 0.14
        cream.inputs["From Max"].default_value = 0.48
        links.new(value.outputs[0], cream.inputs["Value"])
        cream_factor = cream.outputs["Result"]
    else:
        cream_factor = 1.0 if region == "cream" else 0.0

    maps = {}
    for kind in ("albedo", "normal", "orm"):
        dark = image_texture(nodes, links, uv_output,
                             material_dir / f"hero_penguin_v11_dark_{kind}_tile.png",
                             color=kind == "albedo")
        light = image_texture(nodes, links, uv_output,
                              material_dir / f"hero_penguin_v11_cream_{kind}_tile.png",
                              color=kind == "albedo")
        maps[kind] = mix_rgb(nodes, links, dark, light, cream_factor)

    grain = mix_rgb(nodes, links, base_output, maps["albedo"], 0.72, "MULTIPLY")
    links.new(grain, principled.inputs["Base Color"])
    normal = nodes.new("ShaderNodeNormalMap")
    normal.space = "TANGENT"
    normal.uv_map = UV_LAYER
    normal.inputs["Strength"].default_value = 0.35
    links.new(maps["normal"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], principled.inputs["Normal"])
    separate = nodes.new("ShaderNodeSeparateColor")
    links.new(maps["orm"], separate.inputs["Color"])
    roughness_regions = []
    for label, low, high in (("Dorsal feather roughness", 0.52, 0.68),
                             ("Cream down roughness", 0.74, 0.86)):
        roughness = nodes.new("ShaderNodeMapRange")
        roughness.label = label
        roughness.clamp = True
        roughness.inputs["From Min"].default_value = 0.74
        roughness.inputs["From Max"].default_value = 0.92
        roughness.inputs["To Min"].default_value = low
        roughness.inputs["To Max"].default_value = high
        links.new(separate.outputs["Green"], roughness.inputs["Value"])
        roughness_regions.append(roughness.outputs["Result"])
    roughness_mix = mix_rgb(nodes, links, *roughness_regions, cream_factor)
    links.new(roughness_mix, principled.inputs["Roughness"])
    principled.inputs["IOR"].default_value = 1.42
    principled.inputs["Specular IOR Level"].default_value = 0.42
    # Low broad fabric sheen for source review. Any runtime approximation must
    # pass Compatibility separately; do not imply shader parity from Cycles.
    principled.inputs["Sheen Weight"].default_value = 0.12
    principled.inputs["Sheen Roughness"].default_value = 0.76


def apply_feather_review(materials: dict[str, bpy.types.Material], material_dir: Path) -> None:
    feather_materials = {materials[key] for key in ("body_vertex", "dark", "cream")}
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH" and any(material in feather_materials for material in obj.data.materials):
            assign_feather_uvs(obj)
    configure_material(materials["body_vertex"], material_dir, "dark", vertex_paint=True)
    configure_material(materials["dark"], material_dir, "dark", vertex_paint=False)
    configure_material(materials["cream"], material_dir, "cream", vertex_paint=False)
    print("[hero-v12-material] authored albedo/normal/ORM connected; per-face seam-safe UVs; source review only")
