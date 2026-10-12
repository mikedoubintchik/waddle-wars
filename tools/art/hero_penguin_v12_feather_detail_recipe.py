"""Source-only feather-detail candidate layered after apply_feather_review.

Reuses existing six image nodes, original UVs and authored tangent normal maps.
No image generation/writes, fur geometry, noise, albedo-as-bump, or new textures.
Mean calibration is tied to exact reviewed tile hashes. This is not a runtime
Compatibility implementation or visual acceptance assertion.
"""

from __future__ import annotations

import hashlib
import math
from pathlib import Path


RECIPE_ID = "v12_directional_feather_detail_01"
LUMA = (0.2126, 0.7152, 0.0722)
BASELINE_ALBEDO_WEIGHT = 0.72
SHEEN_WEIGHT = 0.04
REGIONS = {
    "dark": {
        "albedo_rgb_mean": (0.7285151852803924, 0.7801353252556771, 0.8466733259185572),
        "luma_mean": 0.7739649271444407,
        "detail_gain": 2.2,
        "normal_strength": 0.50,
        "orm_g_mean": 0.8505239972881244,
        "roughness_center": 0.60,
        "roughness_gain": 2.5,
        "measured_orm_g_range": (0.8196078431372549, 0.8627450980392157),
    },
    "cream": {
        "albedo_rgb_mean": (0.8798303169040189, 0.8398147159321836, 0.7598435511976679),
        "luma_mean": 0.8425481146033889,
        "detail_gain": 3.4,
        "normal_strength": 0.90,
        "orm_g_mean": 0.7902117860083488,
        "roughness_center": 0.74,
        "roughness_gain": 4.0,
        "measured_orm_g_range": (0.7686274509803922, 0.8117647058823529),
    },
}
TILE_SHA256 = {
    "hero_penguin_v11_dark_albedo_tile.png": "5da563d080e444fd87372ffde4e55ae0290b53c3708c3d2b94ee7c4a633d01dd",
    "hero_penguin_v11_dark_normal_tile.png": "cc9d89905bd4b1bac060002cba3416dba448850921e3994fc5e99ac64d3c60d9",
    "hero_penguin_v11_dark_orm_tile.png": "eb687e1321b4829e878b2fcdd4a6e99723c0374116024f895fcc8810e9438a94",
    "hero_penguin_v11_cream_albedo_tile.png": "f7cc8e53444a116febeba22cafcf57b57bd212c0c8e08ff381181df58733c251",
    "hero_penguin_v11_cream_normal_tile.png": "c16ca6579b05ad11242e4e951b2320172b30ca029055ec08c4caebc92fe29c1a",
    "hero_penguin_v11_cream_orm_tile.png": "3b6bd77061ed470bf5772e2494f3f86baaf245fa97d251d32120d14f6451f8a3",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def neutral_detail(rgb, region):
    values = REGIONS[region]
    require(len(rgb) == 3 and all(math.isfinite(v) for v in rgb), "non-finite albedo sample")
    luminance = sum(weight * value for weight, value in zip(LUMA, rgb))
    return 1.0 + values["detail_gain"] * (luminance / values["luma_mean"] - 1.0)


def baseline_mean_multiplier(region):
    return tuple(1.0 - BASELINE_ALBEDO_WEIGHT + BASELINE_ALBEDO_WEIGHT * value
                 for value in REGIONS[region]["albedo_rgb_mean"])


def roughness_response(raw_g, region):
    require(math.isfinite(raw_g), "non-finite roughness sample")
    values = REGIONS[region]
    return values["roughness_center"] + values["roughness_gain"] * (raw_g - values["orm_g_mean"])


def validate_tile_calibration(material_dir):
    paths = {}
    for filename, expected in TILE_SHA256.items():
        path = Path(material_dir) / filename
        require(path.is_file(), f"missing calibrated feather tile: {path}")
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        require(actual == expected, f"feather tile changed; remeasure neutral means before use: {filename}")
        paths[filename] = path
    return paths


def _set(links, socket, value):
    if isinstance(value, (int, float, tuple, list)):
        socket.default_value = value
    else:
        links.new(value, socket)


def _math(nodes, links, operation, first, second, label):
    node = nodes.new("ShaderNodeMath")
    node.operation = operation
    node.label = "Feather recipe: " + label
    node.use_clamp = False
    _set(links, node.inputs[0], first)
    _set(links, node.inputs[1], second)
    return node.outputs[0]


def _mix(nodes, links, first, second, factor, label, mode="MIX"):
    node = nodes.new("ShaderNodeMixRGB")
    node.blend_type = mode
    node.label = "Feather recipe: " + label
    node.use_clamp = False
    _set(links, node.inputs[0], factor)
    _set(links, node.inputs[1], first)
    _set(links, node.inputs[2], second)
    return node.outputs[0]


def _source(socket, description):
    require(len(socket.links) == 1, f"expected one source for {description}")
    return socket.links[0].from_socket


def _texture_nodes(material):
    result = {}
    for node in material.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image is not None:
            filename = Path(node.image.filepath).name
            require(filename not in result, f"duplicate material image node: {filename}")
            result[filename] = node
    require(set(result) == set(TILE_SHA256), "apply existing apply_feather_review first; require exactly six authored tiles")
    return result


def _apply_material(material):
    if material.get("feather_detail_recipe") == RECIPE_ID:
        return
    nodes, links = material.node_tree.nodes, material.node_tree.links
    images = _texture_nodes(material)
    principled = nodes.get("Principled BSDF")
    require(principled is not None, "missing Principled BSDF")
    old_grain = _source(principled.inputs["Base Color"], "baseline albedo").node
    require(old_grain.type == "MIX_RGB" and old_grain.blend_type == "MULTIPLY",
            "unexpected baseline albedo graph; refusing to infer paint ownership")
    require(abs(old_grain.inputs[0].default_value - BASELINE_ALBEDO_WEIGHT) < 1e-6,
            "baseline grain weight changed; mean calibration no longer applies")
    base = _source(old_grain.inputs[1], "semantic base color")
    mixed_albedo = _source(old_grain.inputs[2], "dark/cream albedo mix").node
    require(mixed_albedo.type == "MIX_RGB" and mixed_albedo.blend_type == "MIX",
            "unexpected region mix")
    factor_socket = mixed_albedo.inputs[0]
    factor = _source(factor_socket, "existing cream mask") if factor_socket.links else factor_socket.default_value
    normal_node = _source(principled.inputs["Normal"], "authored normal map").node
    require(normal_node.type == "NORMAL_MAP" and normal_node.space == "TANGENT",
            "require existing authored tangent NormalMap, never an albedo-derived Bump")
    original_normal_source = _source(normal_node.inputs["Color"], "normal-map RGB")
    original_uv_map = normal_node.uv_map
    image_count = len(images)
    detail, roughness = {}, {}
    for region, calibration in REGIONS.items():
        albedo = images[f"hero_penguin_v11_{region}_albedo_tile.png"].outputs["Color"]
        luminance = nodes.new("ShaderNodeVectorMath")
        luminance.operation = "DOT_PRODUCT"
        luminance.label = f"Feather recipe: {region} linear Rec709 luminance"
        links.new(albedo, luminance.inputs[0])
        luminance.inputs[1].default_value = LUMA
        residual = _math(nodes, links, "DIVIDE", luminance.outputs["Value"],
                         calibration["luma_mean"], region + " luminance / measured mean")
        residual = _math(nodes, links, "SUBTRACT", residual, 1.0, region + " zero-mean residual")
        residual = _math(nodes, links, "MULTIPLY", residual, calibration["detail_gain"], region + " detail gain")
        detail[region] = _math(nodes, links, "ADD", residual, 1.0, region + " neutral detail")
        separate = nodes.new("ShaderNodeSeparateColor")
        separate.mode = "RGB"
        separate.label = f"Feather recipe: {region} existing ORM roughness"
        links.new(images[f"hero_penguin_v11_{region}_orm_tile.png"].outputs["Color"], separate.inputs["Color"])
        centered = _math(nodes, links, "SUBTRACT", separate.outputs["Green"],
                         calibration["orm_g_mean"], region + " roughness residual")
        scaled = _math(nodes, links, "MULTIPLY", centered, calibration["roughness_gain"], region + " roughness contrast")
        roughness[region] = _math(nodes, links, "ADD", scaled, calibration["roughness_center"], region + " roughness center")

    mean = _mix(nodes, links, (*baseline_mean_multiplier("dark"), 1.0),
                (*baseline_mean_multiplier("cream"), 1.0), factor, "preserve original mean tint")
    pigment = _mix(nodes, links, base, mean, 1.0, "semantic base × original mean", "MULTIPLY")
    grain = _mix(nodes, links, detail["dark"], detail["cream"], factor, "blend neutral feather detail")
    result = _mix(nodes, links, pigment, grain, 1.0, "zero-mean detail color only", "MULTIPLY")
    links.new(result, principled.inputs["Base Color"])
    rough = _mix(nodes, links, roughness["dark"], roughness["cream"], factor, "region roughness")
    links.new(rough, principled.inputs["Roughness"])
    strength = nodes.new("ShaderNodeMapRange")
    strength.label = "Feather recipe: one authored-normal strength per region"
    strength.clamp = True
    strength.inputs["From Min"].default_value = 0.0
    strength.inputs["From Max"].default_value = 1.0
    strength.inputs["To Min"].default_value = REGIONS["dark"]["normal_strength"]
    strength.inputs["To Max"].default_value = REGIONS["cream"]["normal_strength"]
    _set(links, strength.inputs["Value"], factor)
    links.new(strength.outputs["Result"], normal_node.inputs["Strength"])
    principled.inputs["Sheen Weight"].default_value = SHEEN_WEIGHT
    require(_source(normal_node.inputs["Color"], "preserved authored normal") == original_normal_source
            and normal_node.uv_map == original_uv_map, "authored normal source or UV changed")
    require(len(_texture_nodes(material)) == image_count, "recipe added texture image nodes")
    material["feather_detail_recipe"] = RECIPE_ID
    material["feather_detail_recipe_scope"] = "source review only; maps/UV/IOR/specular unchanged; visual approval pending"


def apply_feather_detail_recipe(materials, material_dir):
    """Call immediately after apply_feather_review(materials, material_dir).

    Applies to body_vertex/dark/cream only. Keeps their existing authored region
    masks, image nodes, image pixels, tangent normal inputs and UV assignments.
    """
    validate_tile_calibration(material_dir)
    for key in ("body_vertex", "dark", "cream"):
        require(key in materials, f"missing feather material {key}")
        _apply_material(materials[key])
    print(f"[hero-v12-feather-detail] {RECIPE_ID}: neutral-mean color detail, original normal maps, existing six image nodes; source-only")
