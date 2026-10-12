#!/usr/bin/env python3
"""Build deterministic Waddle Wars hero penguin Blender source.

Run only through Blender 5.2.0:
  blender --background --factory-startup --python tools/art/build_hero_penguin_v1.py -- \
    --output art_src/characters/hero_penguin_v1.blend

Runtime export remains tools/art/blender_export.py's responsibility. This file
creates source geometry, skin, species seams, sockets, and named actions only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hero_penguin_v11_design import (  # noqa: E402
    BILL_LOWER_SECTIONS,
    BILL_UPPER_SECTIONS,
    BODY_ORIGIN,
    BODY_VOLUMES,
    EYE_CENTER_X,
    EYE_CENTER_Y,
    EYE_CENTER_Z,
    EYE_RADII,
    IRIS_RADII,
    PUPIL_RADII,
    WING_CROSS_SEGMENTS,
    WING_DROP,
    WING_LONGITUDINAL_RINGS,
    WING_MAX_HALF_THICKNESS,
    WING_MAX_HALF_WIDTH,
    WING_OUTWARD,
    WING_ROOT_X,
    WING_ROOT_Y,
    WING_ROOT_Z,
    body_position as v11_body_position,
)

import bpy
from mathutils import Vector


EXPECTED_BLENDER = (5, 2, 0)
COLLECTION_NAME = "hero_penguin_v1"
LOD1_COLLECTION_NAME = "hero_penguin_v1_lod1"
LOD1_TARGET_TRIANGLES = 10_000
REQUIRED_ACTIONS = (
    "celebration",
    "countdown_idle",
    "defeat",
    "fidget",
    "hit_left",
    "hit_right",
    "jump_air",
    "jump_land",
    "jump_takeoff",
    "lean_left",
    "lean_right",
    "ramp_flip",
    "ramp_land",
    "ramp_launch",
    "recover",
    "run",
    "shove",
    "slide_enter",
    "slide_exit",
    "slide_loop",
    "stumble",
    "swim",
    "wipeout",
)
SPECIES = (
    "emperor",
    "king",
    "adelie",
    "gentoo",
    "chinstrap",
    "rockhopper",
    "macaroni",
    "little_blue",
)


def parse_args() -> argparse.Namespace:
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--update-run-only", action="store_true",
                        help="replace only run action in an existing canonical source")
    parser.add_argument("--animation-source", help="existing .blend for animation-only update; defaults to output")
    parser.add_argument("--motion-report", help="write evaluated run contact and bone metrics JSON")
    return parser.parse_args(values)


def require_version() -> None:
    if tuple(bpy.app.version[:3]) != EXPECTED_BLENDER:
        found = ".".join(str(piece) for piece in bpy.app.version[:3])
        raise RuntimeError(f"expected Blender 5.2.0, found {found}")


def reset_scene() -> bpy.types.Collection:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (
        bpy.data.meshes,
        bpy.data.armatures,
        bpy.data.materials,
        bpy.data.actions,
        bpy.data.collections,
    ):
        for item in list(block):
            if block is bpy.data.collections and item.name == "Collection":
                continue
            block.remove(item)
    root = bpy.context.scene.collection
    for child in list(root.children):
        root.children.unlink(child)
    collection = bpy.data.collections.new(COLLECTION_NAME)
    root.children.link(collection)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 30
    scene.frame_start = 1
    scene.frame_end = 60
    scene.world.color = (0.015, 0.025, 0.05)
    return collection


Color = tuple[float, float, float, float]
Weights = dict[str, float]


@dataclass
class MeshBuilder:
    vertices: list[tuple[float, float, float]] = field(default_factory=list)
    faces: list[tuple[int, ...]] = field(default_factory=list)
    face_materials: list[int] = field(default_factory=list)
    colors: list[Color] = field(default_factory=list)
    weights: list[Weights] = field(default_factory=list)
    zones: list[str] = field(default_factory=list)

    def vertex(self, position: tuple[float, float, float], color: Color,
               weights: Weights, zone: str) -> int:
        index = len(self.vertices)
        self.vertices.append(position)
        self.colors.append(color)
        total = sum(max(0.0, value) for value in weights.values())
        if total <= 0.0:
            weights = {"root": 1.0}
            total = 1.0
        normalized = {
            name: max(0.0, value) / total
            for name, value in weights.items()
            if value > 1e-6
        }
        if len(normalized) > 4:
            normalized = dict(sorted(normalized.items(), key=lambda item: item[1], reverse=True)[:4])
            renorm = sum(normalized.values())
            normalized = {name: value / renorm for name, value in normalized.items()}
        self.weights.append(normalized)
        self.zones.append(zone)
        return index

    def face(self, indices: tuple[int, ...], material: int) -> None:
        self.faces.append(indices)
        self.face_materials.append(material)


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    if edge0 == edge1:
        return 0.0
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def torso_profile(z: float) -> tuple[float, float]:
    # Low-frequency semantic-mask envelope only. V9 geometry comes from fused
    # volume construction in add_body_head(), not this legacy lathe profile.
    if z >= 1.58:
        # Elliptical crown, sampled densely by add_body_head's cosine rings.
        # Multi-vertex flat micro-cap below removes single apex entirely.
        vertical = max(-1.0, min(1.0, (z - 1.390) / 0.370))
        crown = math.sqrt(max(0.0, 1.0 - vertical * vertical))
        return 0.495 * crown, 0.425 * crown
    controls = (
        (0.10, 0.04, 0.04),
        (0.16, 0.26, 0.21),
        (0.30, 0.44, 0.34),
        (0.51, 0.56, 0.43),
        (0.74, 0.575, 0.45),
        (0.96, 0.535, 0.435),
        (1.13, 0.475, 0.405),
        (1.28, 0.455, 0.395),
        (1.43, 0.485, 0.425),
        (1.58, 0.425, 0.365),
    )
    for index in range(len(controls) - 1):
        a = controls[index]
        b = controls[index + 1]
        if z <= b[0]:
            t = smoothstep(a[0], b[0], z)
            return (a[1] + (b[1] - a[1]) * t,
                    a[2] + (b[2] - a[2]) * t)
    return controls[-1][1], controls[-1][2]


def torso_masks(position: tuple[float, float, float], theta: float) -> Color:
    x, y, z = position
    front = max(0.0, -math.sin(theta))
    side = abs(math.cos(theta))
    # Keep dark flanks visible around the cream bib. A near-silhouette cream
    # fill made the torso read as a flat white capsule instead of plush pear.
    belly_edge = 0.41 + 0.12 * smoothstep(1.05, 0.35, z)
    belly = smoothstep(belly_edge, belly_edge + 0.19, front)
    belly *= 1.0 - smoothstep(1.24, 1.40, z)
    # Gold is a tiny cranial side wedge only. Earlier semantic-green collar
    # painted a broad orange neck band and fought the cream face/bib junction.
    patch = 0.0
    # Blue-gray dorsal mantle gives chase-camera value separation.
    mantle = smoothstep(0.42, 0.88, y / max(0.12, torso_profile(z)[1]))
    mantle *= smoothstep(0.38, 0.63, z) * (1.0 - smoothstep(1.08, 1.29, z))
    # Baked curvature/contact response: subtle, broad gradients only. Previous
    # high-frequency sine detail formed diagonal bands after interpolation.
    under_flipper = smoothstep(0.27, 0.45, abs(x))
    under_flipper *= smoothstep(0.42, 0.68, z) * (1.0 - smoothstep(1.08, 1.28, z))
    base_curve = 0.925 + 0.035 * smoothstep(0.12, 1.34, z)
    chest_lift = 0.018 * front * smoothstep(0.38, 0.88, z)
    ao = max(0.82, min(0.985, base_curve + chest_lift - under_flipper * 0.075))
    # Identity seam lives on cranial side planes where topology is denser. No
    # torso/neck accent: coarse torso rings made even soft masks read as tags.
    return (belly, patch, mantle * 0.46, ao)


def head_masks(position: tuple[float, float, float]) -> Color:
    x, y, z = position
    front = max(0.0, min(1.0, -y / 0.45))
    side = max(0.0, min(1.0, abs(x) / 0.48))
    # Cream follows actual fused cheek lobes. Narrow upper bridge leaves navy
    # hood between/above eyes; lower cheek/chin mass broadens into chest.
    cheek_l = math.exp(-(((x + 0.205) / 0.194) ** 2
                         + ((z - 1.420) / 0.192) ** 2))
    cheek_r = math.exp(-(((x - 0.205) / 0.194) ** 2
                         + ((z - 1.420) / 0.192) ** 2))
    muzzle = math.exp(-((x / 0.205) ** 2 + ((z - 1.355) / 0.145) ** 2))
    chin = math.exp(-((x / 0.230) ** 2 + ((z - 1.275) / 0.178) ** 2))
    face = smoothstep(0.10, 0.50, max(cheek_l, cheek_r, muzzle * 0.72, chin))
    face *= smoothstep(0.30, 0.86, front)
    face *= 1.0 - 0.96 * smoothstep(1.555, 1.665, z)
    # Navy bridge visibly separates eye/cheek lobes instead of one white mask.
    hood_notch = math.exp(-((x / 0.082) ** 2 + ((z - 1.570) / 0.118) ** 2))
    face *= 1.0 - 0.64 * hood_notch
    patch_l = math.exp(-(((x + 0.390) / 0.042) ** 2 + ((z - 1.425) / 0.062) ** 2))
    patch_r = math.exp(-(((x - 0.390) / 0.042) ** 2 + ((z - 1.425) / 0.062) ** 2))
    patch = smoothstep(0.38, 0.82, max(patch_l, patch_r))
    patch *= smoothstep(0.30, 0.74, front) * 0.52
    seam_height = smoothstep(1.285, 1.325, z) * (1.0 - smoothstep(1.375, 1.425, z))
    seam_side = smoothstep(0.58, 0.76, side) * (1.0 - smoothstep(0.91, 0.99, side))
    seam_front = smoothstep(0.06, 0.40, front) * (1.0 - smoothstep(0.67, 0.88, front))
    identity = seam_height * seam_side * seam_front * 0.060
    crown_lift = 0.022 * smoothstep(1.43, 1.73, z)
    face_curve = 0.018 * front * (1.0 - side)
    ao = max(0.86, min(0.99, 0.945 + crown_lift + face_curve))
    return (max(face, identity), max(patch, identity), identity, ao)


def torso_weights(position: tuple[float, float, float]) -> Weights:
    z = position[2]
    if z < 0.42:
        t = smoothstep(0.18, 0.42, z)
        return {"pelvis": 1.0 - t, "spine_lower": t}
    if z < 0.93:
        t = smoothstep(0.42, 0.93, z)
        return {"spine_lower": 1.0 - t, "spine_upper": t}
    if z < 1.30:
        t = smoothstep(0.93, 1.30, z)
        return {"spine_upper": 1.0 - t, "neck": t}
    t = smoothstep(1.30, 1.50, z)
    return {"neck": 1.0 - t, "head": t}


FusedVolume = tuple[
    tuple[float, float, float],
    tuple[float, float, float],
]


def ray_ellipsoid_far(origin: tuple[float, float, float],
                      direction: tuple[float, float, float],
                      volume: FusedVolume) -> float | None:
    """Return positive outer ray hit for one deterministic sculpt volume."""
    center, radii = volume
    offset = tuple(origin[index] - center[index] for index in range(3))
    inverse_squared = tuple(1.0 / (radius * radius) for radius in radii)
    quadratic = sum(direction[index] * direction[index] * inverse_squared[index]
                    for index in range(3))
    linear = 2.0 * sum(offset[index] * direction[index] * inverse_squared[index]
                       for index in range(3))
    constant = sum(offset[index] * offset[index] * inverse_squared[index]
                   for index in range(3)) - 1.0
    discriminant = linear * linear - 4.0 * quadratic * constant
    if discriminant < 0.0:
        return None
    root = math.sqrt(max(0.0, discriminant))
    far = (-linear + root) / (2.0 * quadratic)
    return far if far > 0.0 else None


def smooth_outer_radius(values: list[float], blend_radius: float = 0.055) -> float:
    """Polynomial smooth maximum: fused lobes, no disconnected shell seams."""
    if not values:
        raise RuntimeError("fused hero sculpt ray missed every source volume")
    result = min(values)
    for value in sorted(values)[1:]:
        distance = abs(result - value)
        if distance >= blend_radius:
            result = max(result, value)
            continue
        transition = (blend_radius - distance) / blend_radius
        result = max(result, value) + transition * transition * blend_radius * 0.25
    return result


def add_body_head(builder: MeshBuilder) -> None:
    """Build one fused skinned sculpt from distinct plush character volumes.

    Spherical rays sample analytic union of torso, cranium, cheek, muzzle and
    hood volumes. Result remains one deterministic manifold/surface while its
    planes and silhouette come from actual overlapping forms—not shallow
    displacement on one elongated lathe.
    """
    segments = 80
    ring_count = 63
    origin = BODY_ORIGIN
    volumes = BODY_VOLUMES

    def fused_position(direction: tuple[float, float, float]) -> tuple[float, float, float]:
        return v11_body_position(direction)

    def semantic_color(position: tuple[float, float, float], theta: float) -> Color:
        torso = torso_masks(position, theta)
        head = head_masks(position)
        head_mix = smoothstep(1.08, 1.36, position[2])
        return (
            torso[0] + (head[0] - torso[0]) * head_mix,
            torso[1] + (head[1] - torso[1]) * head_mix,
            torso[2] + (head[2] - torso[2]) * head_mix,
            torso[3] + (head[3] - torso[3]) * head_mix,
        )

    bottom_position = fused_position((0.0, 0.0, -1.0))
    bottom = builder.vertex(bottom_position,
                            torso_masks(bottom_position, -math.pi * 0.5),
                            {"pelvis": 1.0}, "body")
    rings: list[list[int]] = []
    for ring in range(1, ring_count + 1):
        latitude = -math.pi * 0.5 + math.pi * ring / (ring_count + 1)
        latitude_cosine = math.cos(latitude)
        values: list[int] = []
        for segment in range(segments):
            theta = math.tau * segment / segments
            direction = (latitude_cosine * math.cos(theta),
                         latitude_cosine * math.sin(theta),
                         math.sin(latitude))
            position = fused_position(direction)
            x, y, z = position
            if z >= 1.235 and y < -0.245 and abs(x) < 0.455:
                zone = "cheek"
            else:
                zone = "head" if z >= 1.185 else "body"
            values.append(builder.vertex(position, semantic_color(position, theta),
                                          torso_weights(position), zone))
        rings.append(values)
    for segment in range(segments):
        nxt = (segment + 1) % segments
        builder.face((bottom, rings[0][nxt], rings[0][segment]), 0)
    for ring in range(len(rings) - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            builder.face((rings[ring][segment], rings[ring][nxt],
                          rings[ring + 1][nxt], rings[ring + 1][segment]), 0)
    # Last cosine-spaced ring is a 3–4 cm rounded crown micro-cap. Triangulate
    # coplanar boundary vertices only: no central apex and no exporter N-gon.
    for segment in range(1, segments - 1):
        builder.face((rings[-1][0], rings[-1][segment],
                      rings[-1][segment + 1]), 0)


def add_ellipsoid(builder: MeshBuilder, center: tuple[float, float, float],
                  radii: tuple[float, float, float], segments: int, rings: int,
                  color_fn: Callable[[tuple[float, float, float]], Color],
                  weight_fn: Callable[[tuple[float, float, float]], Weights],
                  zone: str, material: int = 0,
                  rotation_z: float = 0.0) -> None:
    def transform(local: tuple[float, float, float]) -> tuple[float, float, float]:
        x, y, z = local
        cosine = math.cos(rotation_z)
        sine = math.sin(rotation_z)
        return (center[0] + x * cosine - z * sine,
                center[1] + y,
                center[2] + x * sine + z * cosine)

    bottom_pos = transform((0.0, 0.0, -radii[2]))
    bottom = builder.vertex(bottom_pos, color_fn(bottom_pos), weight_fn(bottom_pos), zone)
    latitude_rings: list[list[int]] = []
    for ring in range(1, rings):
        phi = -math.pi * 0.5 + math.pi * ring / rings
        values: list[int] = []
        for segment in range(segments):
            theta = math.tau * segment / segments
            local = (
                math.cos(phi) * math.cos(theta) * radii[0],
                math.cos(phi) * math.sin(theta) * radii[1],
                math.sin(phi) * radii[2],
            )
            position = transform(local)
            values.append(builder.vertex(position, color_fn(position), weight_fn(position), zone))
        latitude_rings.append(values)
    top_pos = transform((0.0, 0.0, radii[2]))
    top = builder.vertex(top_pos, color_fn(top_pos), weight_fn(top_pos), zone)
    for segment in range(segments):
        nxt = (segment + 1) % segments
        builder.face((bottom, latitude_rings[0][nxt], latitude_rings[0][segment]), material)
    for ring in range(len(latitude_rings) - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            builder.face((latitude_rings[ring][segment], latitude_rings[ring][nxt],
                          latitude_rings[ring + 1][nxt], latitude_rings[ring + 1][segment]), material)
    for segment in range(segments):
        nxt = (segment + 1) % segments
        builder.face((latitude_rings[-1][segment], latitude_rings[-1][nxt], top), material)


def feather_mask(mask: tuple[float, float, float], ao: float = 0.93) -> Callable[[tuple[float, float, float]], Color]:
    return lambda _position: (mask[0], mask[1], mask[2], ao)


def solid_color(color: tuple[float, float, float], ao: float = 1.0,
                keratin_tag: float = 0.25) -> Callable[[tuple[float, float, float]], Color]:
    # Alpha below 0.5 tags painted keratin inside shared single-surface shader.
    # Its subrange also carries response: eye=.10–.12, bill=.18–.20, feet=.24.
    # Feather masks reserve alpha 0.68..1.0 for authored ambient occlusion.
    return lambda _position: (color[0], color[1], color[2],
                              min(0.45, ao * keratin_tag))


def rigid(bone: str) -> Callable[[tuple[float, float, float]], Weights]:
    return lambda _position: {bone: 1.0}


def add_wings(builder: MeshBuilder) -> None:
    for side, bone in ((-1.0, "wing.L"), (1.0, "wing.R")):
        # Shoulder-buried rounded paddle: broad flattened plane, sustained
        # width through blunt end, soft semicircular cap. No tube/fin tip.
        segments = 20
        ring_count = 20
        rings: list[list[int]] = []
        centers: list[tuple[float, float, float]] = []
        for ring_index in range(ring_count):
            t = ring_index / (ring_count - 1)
            cx = side * (0.300 + 0.285 * t - 0.018 * math.sin(math.pi * t))
            cy = -0.006 + 0.012 * math.sin(math.pi * t)
            cz = 1.100 - 0.680 * t
            centers.append((cx, cy, cz))
            blade_profile = math.sin(math.pi * t) ** 0.72
            width = (0.095 * (1.0 - t) + 0.092 * t
                     + 0.108 * blade_profile)
            depth = 0.020 + 0.015 * (math.sin(math.pi * t) ** 0.80)
            dx = side * (0.285 - 0.018 * math.pi * math.cos(math.pi * t))
            dz = -0.680
            tangent_length = math.sqrt(dx * dx + dz * dz)
            nx = -dz / tangent_length
            nz = dx / tangent_length
            ring_values: list[int] = []
            for segment in range(segments):
                angle = math.tau * segment / segments
                radial = math.cos(angle) * width
                depth_sine = math.sin(angle)
                beveled_depth = math.copysign(abs(depth_sine) ** 0.45, depth_sine) * depth
                position = (
                    cx + nx * radial,
                    cy + beveled_depth,
                    cz + nz * radial,
                )
                if t < 0.38:
                    wing_weight = 0.20 + 0.80 * smoothstep(0.0, 0.38, t)
                    weights = {"spine_upper": 1.0 - wing_weight, bone: wing_weight}
                else:
                    weights = {bone: 1.0}
                ventral = smoothstep(0.05, 0.62, -depth_sine)
                ventral *= smoothstep(0.08, 0.32, t) * (1.0 - smoothstep(0.94, 1.0, t))
                color = (ventral * 0.78, 0.0, 0.075, 0.94)
                ring_values.append(builder.vertex(position, color, weights, "wing"))
            rings.append(ring_values)
        tangent_x = side * 0.285
        tangent_z = -0.680
        tangent_length = math.sqrt(tangent_x * tangent_x + tangent_z * tangent_z)
        tangent_unit_x = tangent_x / tangent_length
        tangent_unit_z = tangent_z / tangent_length
        normal_x = -tangent_unit_z
        normal_z = tangent_unit_x
        original_end = centers[-1]
        # Cosine-spaced rings trace a true semicircular paddle cap. Final tiny
        # ring closes with an N-gon—no explicit pole or visible tip triangles.
        cap_radius = 0.092
        for cap_angle in (math.radians(30.0), math.radians(55.0),
                          math.radians(72.0), math.radians(84.0)):
            offset = cap_radius * math.sin(cap_angle)
            width = cap_radius * math.cos(cap_angle)
            depth = max(0.006, 0.020 * math.sqrt(max(0.0, math.cos(cap_angle))))
            center = (original_end[0] + tangent_unit_x * offset,
                      original_end[1], original_end[2] + tangent_unit_z * offset)
            centers.append(center)
            ring_values = []
            for segment in range(segments):
                angle = math.tau * segment / segments
                radial = math.cos(angle) * width
                depth_sine = math.sin(angle)
                position = (center[0] + normal_x * radial,
                            center[1] + depth_sine * depth,
                            center[2] + normal_z * radial)
                ventral = smoothstep(0.05, 0.62, -depth_sine)
                color = (ventral * 0.70, 0.0, 0.075, 0.95)
                ring_values.append(builder.vertex(position, color, {bone: 1.0}, "wing"))
            rings.append(ring_values)
        for ring_index in range(len(rings) - 1):
            for segment in range(segments):
                nxt = (segment + 1) % segments
                builder.face((rings[ring_index][segment], rings[ring_index][nxt],
                              rings[ring_index + 1][nxt], rings[ring_index + 1][segment]), 0)
        root = builder.vertex(centers[0], feather_mask((0.0, 0.0, 0.075), 0.92)(centers[0]),
                              {"spine_upper": 0.72, bone: 0.28}, "wing")
        for segment in range(segments):
            nxt = (segment + 1) % segments
            builder.face((root, rings[0][nxt], rings[0][segment]), 0)
        # Boundary-only fan keeps cap planar and tangent-safe without pole.
        for segment in range(1, segments - 1):
            builder.face((rings[-1][0], rings[-1][segment + 1],
                          rings[-1][segment]), 0)


def add_almond_lens(builder: MeshBuilder, side: float) -> None:
    """Create closed smooth almond lens fully above fused face surface."""
    segments = 32
    center_x = 0.145 * side
    center_z = 1.550
    radius_x = 0.127
    radius_z = 0.105
    rotation = -side * math.radians(5.0)
    cosine_rotation = math.cos(rotation)
    sine_rotation = math.sin(rotation)
    color = (0.88, 0.82, 0.68, 0.12)
    front_ring: list[int] = []
    back_ring: list[int] = []
    for segment in range(segments):
        angle = math.tau * segment / segments
        cosine = math.cos(angle)
        sine = math.sin(angle)
        local_x = cosine * radius_x
        # Wider corners and compressed poles form an actual almond rather than
        # the near-circular sclera that read as an assembled googly disk.
        local_z = sine * radius_z * (0.82 + 0.18 * math.sqrt(abs(cosine)))
        rotated_x = local_x * cosine_rotation - local_z * sine_rotation
        rotated_z = local_x * sine_rotation + local_z * cosine_rotation
        front = (center_x + rotated_x, -0.575, center_z + rotated_z)
        back = (center_x + rotated_x * 0.82,
                -0.553,
                center_z + rotated_z * 0.82)
        front_ring.append(builder.vertex(front, color, {"head": 1.0}, "eye"))
        back_ring.append(builder.vertex(back, color, {"head": 1.0}, "eye"))
    front_center_position = (center_x, -0.600, center_z - 0.004)
    back_center_position = (center_x, -0.548, center_z)
    front_center = builder.vertex(front_center_position, color, {"head": 1.0}, "eye")
    back_center = builder.vertex(back_center_position, color, {"head": 1.0}, "eye")
    for segment in range(segments):
        nxt = (segment + 1) % segments
        builder.face((front_center, front_ring[segment], front_ring[nxt]), 1)
        builder.face((front_ring[segment], back_ring[segment], back_ring[nxt],
                      front_ring[nxt]), 1)
        builder.face((back_center, back_ring[nxt], back_ring[segment]), 1)


def add_wings_v11(builder: MeshBuilder) -> None:
    """Build thick shoulder-buried paddles in explicit rest-local planes.

    Previous wing was a narrow swept tube with a separately tapered end. Its
    action projection collapsed into dorsal fins. V11 keeps broad planform for
    70% of length, meaningful thickness, and one continuous rounded cap.
    """
    for side, bone in ((-1.0, "wing.L"), (1.0, "wing.R")):
        rings: list[list[int]] = []
        centers: list[tuple[float, float, float]] = []
        for ring_index in range(WING_LONGITUDINAL_RINGS):
            # Stop just short of analytic endpoint: final 3.6 cm-wide ring is a
            # blunt micro-cap, never a visible single-vertex triangle.
            t = 0.995 * ring_index / (WING_LONGITUDINAL_RINGS - 1)
            center = (
                side * (WING_ROOT_X + WING_OUTWARD * (t ** 0.90)),
                WING_ROOT_Y + 0.014 * math.sin(math.pi * t),
                WING_ROOT_Z - WING_DROP * (t ** 0.94),
            )
            centers.append(center)
            if t < 0.20:
                width = 0.118 + (WING_MAX_HALF_WIDTH - 0.118) * smoothstep(0.0, 0.20, t)
            elif t < 0.70:
                width = WING_MAX_HALF_WIDTH * (1.0 - 0.035 * smoothstep(0.20, 0.70, t))
            else:
                cap_t = min(0.999, (t - 0.70) / 0.30)
                width = WING_MAX_HALF_WIDTH * 0.965 * math.sqrt(max(0.0, 1.0 - cap_t * cap_t))
            thickness = WING_MAX_HALF_THICKNESS * (
                0.72 + 0.28 * math.sin(math.pi * min(0.96, max(0.04, t))) ** 0.65
            )
            if t > 0.76:
                thickness *= 0.48 + 0.52 * math.sqrt(max(0.0, 1.0 - ((t - 0.76) / 0.24) ** 2))

            derivative_x = side * WING_OUTWARD * 0.90 * max(0.02, t) ** -0.10
            derivative_z = -WING_DROP * 0.94 * max(0.02, t) ** -0.06
            tangent_length = math.sqrt(derivative_x * derivative_x + derivative_z * derivative_z)
            normal_x = -derivative_z / tangent_length
            normal_z = derivative_x / tangent_length
            values: list[int] = []
            for segment in range(WING_CROSS_SEGMENTS):
                angle = math.tau * segment / WING_CROSS_SEGMENTS
                plane = math.cos(angle) * width
                depth_sine = math.sin(angle)
                depth = math.copysign(abs(depth_sine) ** 0.72, depth_sine) * thickness
                position = (
                    center[0] + normal_x * plane,
                    center[1] + depth,
                    center[2] + normal_z * plane,
                )
                if t < 0.34:
                    wing_weight = 0.15 + 0.85 * smoothstep(0.0, 0.34, t)
                    weights = {"spine_upper": 1.0 - wing_weight, bone: wing_weight}
                else:
                    weights = {bone: 1.0}
                # Cream underside is physical plane response. Dark leading and
                # trailing bevel remain visible at all action-camera angles.
                ventral = smoothstep(0.03, 0.64, -depth_sine)
                ventral *= smoothstep(0.08, 0.28, t) * (1.0 - smoothstep(0.92, 1.0, t))
                color = (ventral * 0.74, 0.0, 0.070, 0.94)
                values.append(builder.vertex(position, color, weights, "wing"))
            rings.append(values)

        for ring_index in range(len(rings) - 1):
            for segment in range(WING_CROSS_SEGMENTS):
                nxt = (segment + 1) % WING_CROSS_SEGMENTS
                builder.face((rings[ring_index][segment], rings[ring_index][nxt],
                              rings[ring_index + 1][nxt], rings[ring_index + 1][segment]), 0)
        root = builder.vertex(centers[0], feather_mask((0.0, 0.0, 0.070), 0.92)(centers[0]),
                              {"spine_upper": 0.82, bone: 0.18}, "wing")
        for segment in range(WING_CROSS_SEGMENTS):
            nxt = (segment + 1) % WING_CROSS_SEGMENTS
            builder.face((root, rings[0][nxt], rings[0][segment]), 0)
        # Boundary fan closes tiny blunt ellipse; no isolated pole.
        for segment in range(1, WING_CROSS_SEGMENTS - 1):
            builder.face((rings[-1][0], rings[-1][segment + 1],
                          rings[-1][segment]), 0)


def add_upper_lid(builder: MeshBuilder, side: float) -> None:
    """Closed navy crescent hides lens top without intersecting body topology."""
    segments = 18
    center_x = 0.145 * side
    center_z = 1.550
    radius_x = 0.132
    radius_z = 0.108
    rotation = -side * math.radians(5.0)
    cosine_rotation = math.cos(rotation)
    sine_rotation = math.sin(rotation)
    color = feather_mask((0.0, 0.0, 0.060), 0.95)((0.0, 0.0, 0.0))
    outer_front: list[int] = []
    inner_front: list[int] = []
    outer_back: list[int] = []
    inner_back: list[int] = []
    for index in range(segments):
        # Stop above side corners: upper lid crescent, never horseshoe/ring.
        u = -0.78 + 1.56 * index / (segments - 1)
        arch = math.sqrt(max(0.0, 1.0 - u * u))
        outer_z = radius_z * arch * (0.84 + 0.16 * math.sqrt(abs(u)))
        band = 0.006 + 0.009 * arch
        inner_z = outer_z - band

        def transform(local_z: float, y: float) -> tuple[float, float, float]:
            local_x = u * radius_x
            return (center_x + local_x * cosine_rotation - local_z * sine_rotation,
                    y,
                    center_z + local_x * sine_rotation + local_z * cosine_rotation)

        outer_front.append(builder.vertex(transform(outer_z, -0.603), color,
                                          {"head": 1.0}, "eye_socket"))
        inner_front.append(builder.vertex(transform(inner_z, -0.605), color,
                                          {"head": 1.0}, "eye_socket"))
        outer_back.append(builder.vertex(transform(outer_z, -0.578), color,
                                         {"head": 1.0}, "eye_socket"))
        inner_back.append(builder.vertex(transform(inner_z, -0.580), color,
                                         {"head": 1.0}, "eye_socket"))
    for index in range(segments - 1):
        nxt = index + 1
        builder.face((outer_front[index], outer_front[nxt], inner_front[nxt],
                      inner_front[index]), 0)
        builder.face((outer_back[nxt], outer_back[index], inner_back[index],
                      inner_back[nxt]), 0)
        builder.face((outer_front[index], outer_back[index], outer_back[nxt],
                      outer_front[nxt]), 0)
        builder.face((inner_front[nxt], inner_back[nxt], inner_back[index],
                      inner_front[index]), 0)
    for index in (0, segments - 1):
        builder.face((outer_front[index], inner_front[index], inner_back[index],
                      outer_back[index]), 0)


def add_face(builder: MeshBuilder) -> None:
    # Recessed ellipsoidal eyeballs intersect body-native socket cavities. Hood
    # and cheek manifold therefore occlude their upper/lower perimeter as true
    # lids; no white plane, disk, floating ring, or separate brow slab.
    for side in (-1.0, 1.0):
        add_ellipsoid(builder,
                      (EYE_CENTER_X * side, EYE_CENTER_Y, EYE_CENTER_Z),
                      EYE_RADII, 40, 20,
                      solid_color((0.80, 0.77, 0.68), 1.0, 0.12), rigid("head"),
                      "eye", 1)
        iris_y = EYE_CENTER_Y - EYE_RADII[1] + 0.005
        add_ellipsoid(builder, (EYE_CENTER_X * side, iris_y, EYE_CENTER_Z - 0.006),
                      IRIS_RADII,
                      24, 12, solid_color((0.20, 0.38, 0.50), 1.0, 0.11), rigid("gaze"),
                      "eye", 1)
        add_ellipsoid(builder,
                      (EYE_CENTER_X * side, iris_y - 0.017, EYE_CENTER_Z - 0.010),
                      PUPIL_RADII,
                      18, 10, solid_color((0.008, 0.012, 0.018), 1.0, 0.10), rigid("gaze"),
                      "eye", 1)
        add_ellipsoid(builder,
                      ((EYE_CENTER_X - 0.014) * side, iris_y - 0.029,
                       EYE_CENTER_Z + 0.038),
                      (0.010, 0.004, 0.014),
                      12, 8, solid_color((0.98, 0.97, 0.90), 1.0, 0.10), rigid("gaze"),
                      "eye", 1)


def add_bill(builder: MeshBuilder) -> None:
    # Compact convex upper wedge plus tucked lower mandible. An asymmetric
    # decagonal section gives each part a broad crown, tucked underside and
    # blunt tip; circular ring lofts made the previous bill read as two pucks.
    profile = (
        (1.00, -0.08), (0.80, 0.58), (0.32, 1.00),
        (-0.32, 1.00), (-0.80, 0.58), (-1.00, -0.08),
        (-0.82, -0.62), (-0.34, -1.00), (0.34, -1.00), (0.82, -0.62),
    )
    segments = len(profile)

    def mandible(sections: tuple[tuple[float, float, float, float], ...],
                 upper_part: bool) -> None:
        rings: list[list[int]] = []
        mandible_weights = {"head": 1.0} if upper_part else {"bill": 1.0}
        for y, width, height, center_z in sections:
            ring: list[int] = []
            for profile_x, profile_z in profile:
                z_offset = profile_z * height
                light = smoothstep(-height, height, z_offset)
                if upper_part:
                    color = (0.94, 0.47 + 0.10 * light, 0.070, 0.18)
                else:
                    color = (0.82 + 0.07 * light, 0.30 + 0.08 * light, 0.035, 0.20)
                ring.append(builder.vertex((profile_x * width, y, center_z + z_offset),
                                           color, mandible_weights, "bill"))
            rings.append(ring)
        for section_index in range(len(rings) - 1):
            for segment in range(segments):
                nxt = (segment + 1) % segments
                builder.face((rings[section_index][segment], rings[section_index][nxt],
                              rings[section_index + 1][nxt], rings[section_index + 1][segment]), 1)
        base_color = ((0.94, 0.52, 0.07, 0.18) if upper_part
                      else (0.86, 0.34, 0.035, 0.20))
        base = builder.vertex((0.0, sections[0][0], sections[0][3]), base_color,
                              mandible_weights, "bill")
        tip = builder.vertex((0.0, sections[-1][0], sections[-1][3]), base_color,
                             mandible_weights, "bill")
        for segment in range(segments):
            nxt = (segment + 1) % segments
            # Base faces toward hood (+Y); tip faces camera/front (-Y). These
            # windings keep both caps visible under production backface culling.
            builder.face((base, rings[0][nxt], rings[0][segment]), 1)
            builder.face((tip, rings[-1][segment], rings[-1][nxt]), 1)

    mandible(BILL_UPPER_SECTIONS, True)
    mandible(BILL_LOWER_SECTIONS, False)

    # Six-sided tapered prism follows upper/lower junction. Back portion is
    # buried in cheek volume; exposed front becomes a thin stable mouth line.
    seam_color = (0.22, 0.055, 0.018, 0.26)
    seam_points = (
        (-0.124, -0.558, 1.372), (0.124, -0.558, 1.372),
        (-0.124, -0.558, 1.379), (0.124, -0.558, 1.379),
        (-0.026, -0.674, 1.377), (0.026, -0.674, 1.377),
        (-0.026, -0.674, 1.384), (0.026, -0.674, 1.384),
    )
    seam = [builder.vertex(point, seam_color, {"head": 1.0}, "bill")
            for point in seam_points]
    for face in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
                 (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        builder.face(tuple(seam[index] for index in face), 1)


def add_feet(builder: MeshBuilder) -> None:
    foot_color = solid_color((0.94, 0.49, 0.075), 0.96)
    toe_color = solid_color((0.89, 0.39, 0.045), 0.98)
    for side, bone in ((-1.0, "foot.L"), (1.0, "foot.R")):
        center = (0.205 * side, -0.050, 0.078)
        add_ellipsoid(builder, center, (0.185, 0.170, 0.070), 40, 14,
                      foot_color, rigid(bone), "foot", 1,
                      rotation_z=-side * math.radians(4.0))
        for toe_index in range(3):
            spread = (toe_index - 1) * 0.058
            toe_bone = "toe.L" if side < 0.0 else "toe.R"
            toe_length = 0.112 if toe_index == 1 else 0.100
            toe_y = -0.205 - (0.012 if toe_index == 1 else 0.0)
            add_ellipsoid(builder, (center[0] + spread, toe_y, 0.044),
                          (0.052, toe_length, 0.034), 16, 8, toe_color,
                          rigid(toe_bone), "toe", 1)
            claw_y = toe_y - toe_length + 0.010
            add_ellipsoid(builder, (center[0] + spread, claw_y, 0.045),
                          (0.032, 0.034, 0.018), 10, 6,
                          solid_color((0.34, 0.105, 0.025), 0.98),
                          rigid(toe_bone), "toe", 1)


def add_tail(builder: MeshBuilder) -> None:
    # Five tapered lobes grow from one buried rump root along authoring +Y.
    # Side/slide views therefore keep physical overlap instead of showing an
    # egg-shaped island, while chase still sees a scalloped feather fan.
    segments = 12
    path_rings = 8
    for feather_index in range(5):
        offset = feather_index - 2
        spread = offset * 0.082
        rings: list[list[int]] = []
        for ring_index in range(path_rings):
            t = ring_index / (path_rings - 1)
            cx = spread * (t ** 0.82)
            # Extended fan balances the projected blunt bill around the
            # ground-center pivot and strengthens the chase/rear bird read.
            cy = 0.255 + 0.350 * t
            cz = 0.380 - 0.145 * t - abs(offset) * 0.010 * t
            width = 0.032 + 0.074 * (math.sin(math.pi * (0.08 + 0.88 * t)) ** 0.72)
            thickness = 0.026 + 0.046 * (math.sin(math.pi * (0.08 + 0.88 * t)) ** 0.78)
            values: list[int] = []
            for segment in range(segments):
                angle = math.tau * segment / segments
                position = (cx + math.cos(angle) * width,
                            cy + math.sin(angle) * thickness,
                            cz + math.sin(angle) * thickness * 0.28)
                tail_weight = smoothstep(0.08, 0.72, t)
                values.append(builder.vertex(position,
                              feather_mask((0.0, 0.0, 0.12 + 0.018 * (2 - abs(offset))), 0.94)(position),
                              {"pelvis": 1.0 - tail_weight, "tail": tail_weight}, "tail"))
            rings.append(values)
        for ring_index in range(path_rings - 1):
            for segment in range(segments):
                nxt = (segment + 1) % segments
                builder.face((rings[ring_index][segment], rings[ring_index][nxt],
                              rings[ring_index + 1][nxt], rings[ring_index + 1][segment]), 0)
        root_position = (0.0, 0.255, 0.380)
        tip_position = (spread, 0.605, 0.235 - abs(offset) * 0.012)
        root = builder.vertex(root_position, feather_mask((0.0, 0.0, 0.12), 0.92)(root_position),
                              {"pelvis": 1.0}, "tail")
        tip = builder.vertex(tip_position, feather_mask((0.0, 0.0, 0.12), 0.95)(tip_position),
                             {"tail": 1.0}, "tail")
        for segment in range(segments):
            nxt = (segment + 1) % segments
            builder.face((root, rings[0][nxt], rings[0][segment]), 0)
            builder.face((tip, rings[-1][segment], rings[-1][nxt]), 0)


def create_material(name: str, roughness: float, metallic: float = 0.0) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = (0.45, 0.55, 0.68, 1.0) if name.startswith("Feather") else (0.85, 0.34, 0.12, 1.0)
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    if principled is not None:
        principled.inputs["Roughness"].default_value = roughness
        principled.inputs["Metallic"].default_value = metallic
        vertex_color = material.node_tree.nodes.new("ShaderNodeVertexColor")
        vertex_color.layer_name = "COLOR_0"
        material.node_tree.links.new(vertex_color.outputs["Color"], principled.inputs["Base Color"])
        texture_dir = Path(__file__).resolve().parents[2] / "art_src/characters/textures"
        for map_name, colorspace in (
            ("hero_penguin_v1_albedo.png", "sRGB"),
            ("hero_penguin_v1_normal.png", "Non-Color"),
            ("hero_penguin_v1_orm.png", "Non-Color"),
        ):
            texture_path = texture_dir / map_name
            if not texture_path.is_file():
                raise RuntimeError(
                    f"missing {texture_path}; run tools/art/generate_hero_penguin_textures.py"
                )
            image = bpy.data.images.load(str(texture_path), check_existing=True)
            image.colorspace_settings.name = colorspace
            image.pack()
            texture_node = material.node_tree.nodes.new("ShaderNodeTexImage")
            texture_node.name = map_name.removesuffix(".png")
            texture_node.label = map_name
            texture_node.image = image
    return material


def create_armature(collection: bpy.types.Collection) -> bpy.types.Object:
    data = bpy.data.armatures.new("PenguinSkeleton")
    armature = bpy.data.objects.new("PenguinSkeleton", data)
    collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    def bone(name: str, head: tuple[float, float, float], tail: tuple[float, float, float],
             parent: str | None = None, deform: bool = True):
        value = data.edit_bones.new(name)
        value.head = head
        value.tail = tail
        value.use_deform = deform
        if parent:
            value.parent = data.edit_bones[parent]
        return value

    bone("root", (0.0, 0.0, 0.0), (0.0, 0.0, 0.15))
    bone("pelvis", (0.0, 0.0, 0.15), (0.0, 0.0, 0.43), "root")
    bone("spine_lower", (0.0, 0.0, 0.43), (0.0, 0.0, 0.82), "pelvis")
    bone("spine_upper", (0.0, 0.0, 0.82), (0.0, 0.0, 1.18), "spine_lower")
    bone("neck", (0.0, 0.0, 1.18), (0.0, 0.0, 1.40), "spine_upper")
    bone("head", (0.0, 0.0, 1.40), (0.0, 0.0, 1.67), "neck")
    wing_l = bone("wing.L", (-WING_ROOT_X, -WING_ROOT_Y, WING_ROOT_Z),
                  (-(WING_ROOT_X + WING_OUTWARD), -WING_ROOT_Y,
                   WING_ROOT_Z - WING_DROP), "spine_upper")
    wing_r = bone("wing.R", (WING_ROOT_X, -WING_ROOT_Y, WING_ROOT_Z),
                  (WING_ROOT_X + WING_OUTWARD, -WING_ROOT_Y,
                   WING_ROOT_Z - WING_DROP), "spine_upper")
    # Explicit shared roll basis: local Z faces character front for both sides.
    # Mirrored wing Euler hacks are no longer necessary for action posing.
    wing_l.align_roll(Vector((0.0, 1.0, 0.0)))
    wing_r.align_roll(Vector((0.0, 1.0, 0.0)))
    bone("foot.L", (-0.18, 0.0, 0.18), (-0.20, 0.18, 0.08), "pelvis")
    bone("foot.R", (0.18, 0.0, 0.18), (0.20, 0.18, 0.08), "pelvis")
    bone("toe.L", (-0.20, 0.18, 0.08), (-0.20, 0.38, 0.06), "foot.L")
    bone("toe.R", (0.20, 0.18, 0.08), (0.20, 0.38, 0.06), "foot.R")
    bone("tail", (0.0, -0.18, 0.42), (0.0, -0.48, 0.32), "pelvis")
    bone("bill", (0.0, 0.20, 1.48), (0.0, 0.50, 1.45), "head")
    bone("gaze", (0.0, 0.20, 1.58), (0.0, 0.40, 1.58), "head")
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.data.display_type = "STICK"
    armature.show_in_front = True
    armature.select_set(False)
    return armature


def create_mesh(collection: bpy.types.Collection, armature: bpy.types.Object) -> tuple[bpy.types.Object, MeshBuilder]:
    builder = MeshBuilder()
    add_body_head(builder)
    add_wings_v11(builder)
    add_face(builder)
    add_bill(builder)
    add_feet(builder)
    add_tail(builder)
    # Authoring front is Blender +Y, which glTF's Y-up conversion maps to
    # Godot -Z. Mirror geometry built in ergonomic front-negative coordinates.
    builder.vertices = [(x, -y, z) for x, y, z in builder.vertices]
    builder.faces = [tuple(reversed(face)) for face in builder.faces]
    mesh = bpy.data.meshes.new("HeroPenguinMesh")
    mesh.from_pydata(builder.vertices, [], builder.faces)
    mesh.update(calc_edges=True)
    obj = bpy.data.objects.new("HeroPenguinMesh", mesh)
    collection.objects.link(obj)
    mesh.materials.append(create_material("FeatherSurface", 0.67))
    for polygon in mesh.polygons:
        # One semantic vertex-painted surface: fewer draws and avoids split-
        # primitive color loss in Blender placeholder-material GLB exports.
        polygon.material_index = 0
        polygon.use_smooth = True
    color_attribute = mesh.color_attributes.new(name="COLOR_0", type="BYTE_COLOR", domain="CORNER")
    for loop in mesh.loops:
        color_attribute.data[loop.index].color = builder.colors[loop.vertex_index]
    # Shared sampled maps provide feather grain/normal/ORM over semantic
    # species colors. Cylindrical UVs stay compact and generated maps tile.
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        cap_z = [builder.vertices[index][2] for index in polygon.vertices]
        crown_cap = min(cap_z) > 1.745 and max(cap_z) - min(cap_z) < 1e-5
        for loop_index in polygon.loop_indices:
            loop = mesh.loops[loop_index]
            x, y, z = builder.vertices[loop.vertex_index]
            if crown_cap:
                # Planar loop UV gives crown-cap triangles non-zero tangent area.
                uv_layer.data[loop.index].uv = (0.5 + x / 0.18, 0.5 + y / 0.18)
            else:
                # Authoring +Y is character front. atan2(X, Y) places cylindrical
                # discontinuity exactly down rear—not across cream face/chest.
                u = (math.atan2(x, y) + math.pi) / math.tau
                uv_layer.data[loop.index].uv = (u, max(0.0, min(1.0, z / 1.90)))
    zone_attribute = mesh.attributes.new(name="_species_zone", type="FLOAT", domain="POINT")
    zone_values = {"body": 0.1, "head": 0.2, "wing": 0.3, "patch": 0.4,
                   "cheek": 0.45, "eye": 0.5, "eye_socket": 0.55,
                   "brow": 0.6, "bill": 0.7, "foot": 0.8,
                   "toe": 0.85, "tail": 0.9}
    for index, zone in enumerate(builder.zones):
        zone_attribute.data[index].value = zone_values.get(zone, 0.0)
    for bone in armature.data.bones:
        if not bone.use_deform:
            continue
        group = obj.vertex_groups.new(name=bone.name)
        assignments: list[tuple[int, float]] = []
        for index, weights in enumerate(builder.weights):
            if bone.name in weights:
                assignments.append((index, weights[bone.name]))
        for index, weight in assignments:
            group.add([index], weight, "REPLACE")
    modifier = obj.modifiers.new(name="PenguinSkeleton", type="ARMATURE")
    modifier.object = armature
    obj.parent = armature
    obj.matrix_parent_inverse.identity()
    create_species_shapes(obj, builder)
    return obj, builder


def create_species_shapes(obj: bpy.types.Object, builder: MeshBuilder) -> None:
    obj.shape_key_add(name="Basis", from_mix=False)
    profiles = {
        "emperor": (1.00, 1.00, 1.00, 0.00),
        "king": (0.94, 1.055, 0.97, 0.00),
        "adelie": (0.92, 0.91, 1.04, 0.015),
        "gentoo": (1.02, 0.98, 1.02, -0.010),
        "chinstrap": (0.95, 0.94, 1.00, 0.008),
        # Keep crested species' profile distinction in height/head shift while
        # preventing deep V8 cheek + larger rump fan from breaking 1.30 m depth.
        "rockhopper": (0.92, 0.88, 1.04, 0.022),
        "macaroni": (0.98, 0.93, 1.04, 0.018),
        "little_blue": (0.80, 0.74, 0.90, 0.026),
    }
    for species in SPECIES:
        key = obj.shape_key_add(name=f"species_{species}", from_mix=False)
        width, height, depth, head_shift = profiles[species]
        for index, source in enumerate(builder.vertices):
            x, y, z = source
            zone = builder.zones[index]
            if zone in {"head", "cheek", "eye", "eye_socket", "brow", "bill"}:
                head_factor = 1.0
            elif zone in {"body", "patch"}:
                head_factor = smoothstep(1.12, 1.32, z)
            else:
                head_factor = 0.0
            local_width = width + head_factor * (depth - width) * 0.32
            local_depth = depth
            # Species silhouettes vary through the plush cranium and torso;
            # rigid keratin bill variants keep their authored projection. This
            # prevents a depth profile from breaking the 1.30 m hero bound.
            if zone == "bill":
                local_depth = 1.0
            new_z = z * height
            if zone in {"foot", "toe"}:
                new_z = z
            elif zone == "tail":
                new_z = z * (0.88 + 0.12 * height)
            new_x = x * local_width
            new_y = y * local_depth
            new_z += head_shift * head_factor
            key.data[index].co = (new_x, new_y, new_z)
        key.value = 0.0
        key.slider_min = 0.0
        key.slider_max = 1.0


def create_lod1_collection(source: bpy.types.Object,
                           armature: bpy.types.Object) -> bpy.types.Object:
    """Author deterministic skinned RACER LOD1 without runtime decimation.

    Godot does not expose generated LOD index dictionaries for imported
    blend-shape skinned ArrayMesh resources. Keep LOD0's species seams for the
    hero, while a separately exported mesh retains the exact skeleton, skin
    groups, semantic colors, UV atlas and material in a 8–12k triangle budget.
    Racers still receive species palette; close-up proportion seams remain a
    HERO-only detail.
    """
    collection = bpy.data.collections.new(LOD1_COLLECTION_NAME)
    bpy.context.scene.collection.children.link(collection)
    collection.objects.link(armature)
    for child in list(armature.children):
        if child.type == "EMPTY":
            collection.objects.link(child)

    lod = source.copy()
    lod.name = "HeroPenguinLOD1"
    lod.data = source.data.copy()
    lod.data.name = "HeroPenguinLOD1"
    collection.objects.link(lod)
    # Shape keys prevent Blender's deterministic Decimate apply. LOD1 keeps
    # rig/palette identity and drops only close-up silhouette proportion seams.
    if lod.data.shape_keys is not None:
        for key in list(reversed(lod.data.shape_keys.key_blocks)):
            lod.shape_key_remove(key)
    for modifier in list(lod.modifiers):
        lod.modifiers.remove(modifier)
    lod.select_set(True)
    bpy.context.view_layer.objects.active = lod
    lod.data.calc_loop_triangles()
    source_triangles = len(lod.data.loop_triangles)
    decimate = lod.modifiers.new(name="AuthoredRacerLOD1", type="DECIMATE")
    decimate.decimate_type = "COLLAPSE"
    decimate.ratio = LOD1_TARGET_TRIANGLES / max(1, source_triangles)
    decimate.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    skin = lod.modifiers.new(name="PenguinSkeleton", type="ARMATURE")
    skin.object = armature
    lod.parent = armature
    lod.matrix_parent_inverse.identity()
    lod.select_set(False)
    lod.data.calc_loop_triangles()
    triangles = len(lod.data.loop_triangles)
    if not 8_000 <= triangles <= 12_000:
        raise RuntimeError(f"LOD1 triangle budget failed: {triangles}")
    return lod


def create_sockets(collection: bpy.types.Collection, armature: bpy.types.Object) -> None:
    definitions = {
        "head_socket": ("head", (0.0, 0.0, 0.28)),
        "face_socket": ("head", (0.0, 0.30, 0.13)),
        "neck_socket": ("neck", (0.0, 0.02, 0.04)),
        "trail_socket": ("pelvis", (0.0, -0.38, 0.10)),
    }
    for name, (bone_name, location) in definitions.items():
        socket = bpy.data.objects.new(name, None)
        socket.empty_display_type = "PLAIN_AXES"
        socket.empty_display_size = 0.08
        collection.objects.link(socket)
        socket.parent = armature
        socket.parent_type = "BONE"
        socket.parent_bone = bone_name
        socket.location = location


def reset_pose(armature: bpy.types.Object) -> None:
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "XYZ"
        pose_bone.location = (0.0, 0.0, 0.0)
        pose_bone.rotation_euler = (0.0, 0.0, 0.0)
        pose_bone.scale = (1.0, 1.0, 1.0)


def pose_values(**values: tuple[float, float, float]) -> dict[str, tuple[float, float, float]]:
    return values


def key_action(armature: bpy.types.Object, name: str, length: int,
               poses: dict[int, dict[str, tuple[float, float, float]]]) -> None:
    reset_pose(armature)
    action = bpy.data.actions.new(name=name)
    # Actions-mode glTF export needs every contract clip to survive source save
    # even though no single action stays assigned to armature at rest.
    action.use_fake_user = True
    armature.animation_data_create()
    armature.animation_data.action = action
    for frame in sorted(poses):
        reset_pose(armature)
        for bone_name, rotation in poses[frame].items():
            pose_bone = armature.pose.bones[bone_name]
            pose_bone.rotation_euler = tuple(math.radians(value) for value in rotation)
        # Explicit identity root channel proves root-motion-free contract.
        root = armature.pose.bones["root"]
        root.location = (0.0, 0.0, 0.0)
        root.rotation_euler = (0.0, 0.0, 0.0)
        root.keyframe_insert(data_path="location", frame=frame, group="root")
        root.keyframe_insert(data_path="rotation_euler", frame=frame, group="root")
        for bone_name in poses[frame]:
            bone = armature.pose.bones[bone_name]
            bone.keyframe_insert(data_path="rotation_euler", frame=frame, group=bone_name)
    action.frame_start = 1
    action.frame_end = length
    armature.animation_data.action = None


def action_curves(action: bpy.types.Action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                yield from bag.fcurves


def source_structure_digest() -> str:
    """Geometry/skin/species/rest-rig guard for animation-only source updates."""
    digest = hashlib.sha256()
    for obj in sorted(bpy.data.objects, key=lambda item: item.name):
        if obj.type == "MESH":
            digest.update(obj.name.encode())
            for vertex in obj.data.vertices:
                digest.update(repr((tuple(vertex.co), tuple((g.group, g.weight) for g in vertex.groups))).encode())
            for polygon in obj.data.polygons:
                digest.update(repr((tuple(polygon.vertices), polygon.material_index)).encode())
            for layer in obj.data.uv_layers:
                for value in layer.data:
                    digest.update(repr(tuple(value.uv)).encode())
            for attribute in obj.data.color_attributes:
                for value in attribute.data:
                    digest.update(repr(tuple(value.color)).encode())
            if obj.data.shape_keys:
                for key in obj.data.shape_keys.key_blocks:
                    digest.update(key.name.encode())
                    for value in key.data:
                        digest.update(repr(tuple(value.co)).encode())
        elif obj.type == "ARMATURE":
            for bone in obj.data.bones:
                digest.update(repr((bone.name, bone.parent.name if bone.parent else None,
                                   tuple(tuple(row) for row in bone.matrix_local), bone.use_deform)).encode())
    return digest.hexdigest()


def action_digest(action: bpy.types.Action) -> str:
    values = [(curve.data_path, curve.array_index,
               [(tuple(key.co), tuple(key.handle_left), tuple(key.handle_right), key.interpolation)
                for key in curve.keyframe_points]) for curve in action_curves(action)]
    return hashlib.sha256(repr(values).encode()).hexdigest()


def foot_vertex_indices(mesh_obj: bpy.types.Object, side: str) -> list[int]:
    groups = {mesh_obj.vertex_groups[name].index for name in (f"foot.{side}", f"toe.{side}")}
    return [vertex.index for vertex in mesh_obj.data.vertices
            if sum(group.weight for group in vertex.groups if group.group in groups) > 0.98]


def evaluated_vertices(mesh_obj: bpy.types.Object, indices: list[int]) -> list[Vector]:
    bpy.context.view_layer.update()
    evaluated = mesh_obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return [evaluated.matrix_world @ evaluated.data.vertices[index].co for index in indices]


def create_run_action(armature: bpy.types.Object, mesh_obj: bpy.types.Object) -> dict:
    """Coherent whole-body waddle; feet follow the pelvis without ankle motion.

    Root remains identity. Pelvis local offsets are presentation deformation;
    gameplay still supplies all character translation and speed authority. The
    lowest evaluated sole sets one vertical offset for the entire character,
    never an independent stride, lift, or compensation for either foot.
    """
    if armature.animation_data:
        armature.animation_data.action = None
    existing = bpy.data.actions.get("run")
    if existing:
        bpy.data.actions.remove(existing)
    reset_pose(armature)
    bpy.context.view_layer.update()
    foot_indices = {side: foot_vertex_indices(mesh_obj, side) for side in ("L", "R")}
    if any(not indices for indices in foot_indices.values()):
        raise RuntimeError("run contact validation needs authored foot/toe skin groups")
    action = bpy.data.actions.new(name="run")
    action.use_fake_user = True
    armature.animation_data_create()
    armature.animation_data.action = action
    combined_foot_indices = foot_indices["L"] + foot_indices["R"]
    sole_height = 0.012
    for frame in range(1, 25):
        bpy.context.scene.frame_set(frame)
        reset_pose(armature)
        phase = (frame - 1) / 23.0
        angle = math.tau * phase
        c, s = math.cos(angle), math.sin(angle)
        rotations = {
            "pelvis": (-2.0 - 0.7 * math.cos(angle * 2.0), 1.5 * s, -11.0 * c),
            "spine_lower": (-3.0, -0.4 * s, 2.0 * c),
            "spine_upper": (-4.0, -0.4 * math.sin(angle - 0.2), 1.5 * math.cos(angle - 0.25)),
            "neck": (0.8, 0.35 * math.sin(angle - 0.3), 0.65 * math.cos(angle - 0.35)),
            "head": (2.0 + 0.4 * math.cos(angle * 2.0 - 0.4),
                     1.5 * math.sin(angle - 0.55), 2.0 * math.cos(angle - 0.6)),
            "wing.L": (9.0 * s, -2.0 * math.sin(angle + 0.2), -9.0 - 3.0 * c),
            "wing.R": (-9.0 * s, 2.0 * math.sin(angle + 0.2), 9.0 - 3.0 * c),
            "tail": (1.5 * math.cos(angle * 2.0), 0.0, 1.5 * math.cos(angle - 0.25)),
        }
        for name, rotation in rotations.items():
            armature.pose.bones[name].rotation_euler = tuple(math.radians(value) for value in rotation)
        bpy.context.view_layer.update()
        pelvis = armature.pose.bones["pelvis"]
        pelvis_matrix = pelvis.matrix.copy()
        pelvis_matrix.translation += Vector((-0.022 * c, 0.0, 0.0))
        pelvis.matrix = pelvis_matrix
        bpy.context.view_layer.update()
        # Feet and toes retain identity local transforms from reset_pose. The
        # body rock alone raises the unweighted side. Evaluate actual skinned
        # soles and move only the pelvis to keep the supporting side on snow.
        for _step in range(2):
            minimum = min(point.z for point in evaluated_vertices(mesh_obj, combined_foot_indices))
            desired = pelvis.matrix.copy()
            desired.translation.z += sole_height - minimum
            pelvis.matrix = desired
            bpy.context.view_layer.update()
        for bone in armature.pose.bones:
            bone.keyframe_insert(data_path="rotation_euler", frame=frame, group=bone.name)
            bone.keyframe_insert(data_path="location", frame=frame, group=bone.name)
        # Full sampling uses linear curves to prevent Bezier undershoot through
        # the floor between contact samples. Other clips retain their curves.
    for curve in action_curves(action):
        for key in curve.keyframe_points:
            key.interpolation = "LINEAR"
    action.frame_start = 1
    action.frame_end = 24
    report = validate_run_motion(armature, mesh_obj, foot_indices, sole_height)
    armature.animation_data.action = None
    reset_pose(armature)
    bpy.context.view_layer.update()
    return report


def validate_run_motion(armature: bpy.types.Object, mesh_obj: bpy.types.Object,
                        foot_indices: dict[str, list[int]], sole_height: float) -> dict:
    samples = []
    for sample in range(93):
        frame = 1.0 + sample / 4.0
        bpy.context.scene.frame_set(int(frame), subframe=frame % 1.0)
        bpy.context.view_layer.update()
        root = armature.pose.bones["root"].matrix_basis
        if any(abs(root[row][column] - (1.0 if row == column else 0.0)) > 1e-5
               for row in range(4) for column in range(4)):
            raise RuntimeError("run action applies root motion")
        record = {"frame": frame}
        for name in ("pelvis", "spine_upper", "head"):
            bone = armature.pose.bones[name]
            deformation = bone.matrix @ bone.bone.matrix_local.inverted()
            up = deformation.to_3x3() @ Vector((0.0, 0.0, 1.0))
            record[name] = {
                "roll_degrees": math.degrees(math.atan2(-up.x, up.z)),
                "pitch_degrees": math.degrees(math.atan2(up.y, up.z)),
            }
        for side in ("L", "R"):
            for name in (f"foot.{side}", f"toe.{side}"):
                basis = armature.pose.bones[name].matrix_basis
                if any(abs(basis[row][column] - (1.0 if row == column else 0.0)) > 1e-5
                       for row in range(4) for column in range(4)):
                    raise RuntimeError(f"run independently animates {name} at frame {frame}")
            points = evaluated_vertices(mesh_obj, foot_indices[side])
            minimum = min(point.z for point in points)
            record[f"sole_{side}"] = minimum
            if minimum < 0.003:
                raise RuntimeError(f"run foot {side} penetrates ground at frame {frame}: {minimum}")
        samples.append(record)
    extrema = {}
    for name in ("pelvis", "spine_upper", "head"):
        extrema[name] = {axis: [min(sample[name][axis] for sample in samples),
                                max(sample[name][axis] for sample in samples)]
                         for axis in ("roll_degrees", "pitch_degrees")}
    report = {"clip": "run", "frame_range": [1, 24], "source_fps": 30,
              "evaluated_samples": len(samples), "sole_target_m": sole_height,
              "minimum_sole_m": min(sample[f"sole_{side}"] for sample in samples for side in ("L", "R")),
              "maximum_support_sole_m": max(min(sample["sole_L"], sample["sole_R"]) for sample in samples),
              "maximum_sole_by_side_m": {side: max(sample[f"sole_{side}"] for sample in samples)
                                          for side in ("L", "R")},
              "independent_foot_motion": False,
              "root_motion": False, "extrema": extrema, "samples": samples}
    print("[hero-run] " + json.dumps({key: value for key, value in report.items() if key != "samples"}, sort_keys=True))
    return report


def create_actions(armature: bpy.types.Object) -> None:
    p = pose_values
    definitions: dict[str, tuple[int, dict[int, dict[str, tuple[float, float, float]]]]] = {
        "countdown_idle": (60, {1: p(spine_lower=(0, 0, -1), head=(0, 0, 0)),
                                30: p(spine_lower=(1.5, 0, 1), head=(-2, 5, -1), wing_L=(0, 0, 0)),
                                60: p(spine_lower=(0, 0, -1), head=(0, 0, 0))}),
        "fidget": (45, {1: p(head=(0, 0, 0)), 12: p(head=(-8, 16, 5), **{"wing.L": (5, -6, -14)}),
                        27: p(head=(3, -12, -4), **{"foot.R": (-12, 0, 8)}), 45: p(head=(0, 0, 0))}),
        "lean_left": (18, {1: p(pelvis=(0, 0, 0)), 9: p(pelvis=(0, -4, 24), spine_upper=(0, 5, 12), head=(0, -9, -18),
                                                              **{"wing.L": (0, 0, -42), "wing.R": (0, 0, 14)}),
                            18: p(pelvis=(0, -4, 24), spine_upper=(0, 5, 12), head=(0, -9, -18),
                                  **{"wing.L": (0, 0, -42), "wing.R": (0, 0, 14)})}),
        "lean_right": (18, {1: p(pelvis=(0, 0, 0)), 9: p(pelvis=(0, 4, -24), spine_upper=(0, -5, -12), head=(0, 9, 18),
                                                               **{"wing.L": (0, 0, -14), "wing.R": (0, 0, 42)}),
                             18: p(pelvis=(0, 4, -24), spine_upper=(0, -5, -12), head=(0, 9, 18),
                                   **{"wing.L": (0, 0, -14), "wing.R": (0, 0, 42)})}),
        "jump_takeoff": (12, {1: p(pelvis=(8, 0, 0), spine_upper=(12, 0, 0), **{"wing.L": (0, 0, -18), "wing.R": (0, 0, 18)}),
                              6: p(pelvis=(-16, 0, 0), spine_upper=(-14, 0, 0), head=(12, 0, 0),
                                   **{"wing.L": (-18, 0, -62), "wing.R": (18, 0, 62), "foot.L": (18, 0, 0), "foot.R": (18, 0, 0)}),
                              12: p(pelvis=(-8, 0, 0), spine_upper=(-9, 0, 0), head=(6, 0, 0),
                                    **{"wing.L": (-12, 0, -74), "wing.R": (12, 0, 74)})}),
        "jump_air": (30, {1: p(pelvis=(-18, 0, 0), spine_upper=(-16, 0, 0), head=(12, 0, 0),
                                  **{"wing.L": (0, 0, -102), "wing.R": (0, 0, 102), "foot.L": (-26, 0, 0), "foot.R": (-26, 0, 0)}),
                           15: p(pelvis=(-8, 0, 6), spine_upper=(-10, 0, -3), head=(6, 0, -3),
                                 **{"wing.L": (0, 0, -96), "wing.R": (0, 0, 96), "foot.L": (10, 0, 0), "foot.R": (10, 0, 0)}),
                           30: p(pelvis=(-18, 0, 0), spine_upper=(-16, 0, 0), head=(12, 0, 0),
                                 **{"wing.L": (0, 0, -102), "wing.R": (0, 0, 102), "foot.L": (-26, 0, 0), "foot.R": (-26, 0, 0)})}),
        "jump_land": (16, {1: p(pelvis=(-8, 0, 0), **{"wing.L": (-12, 0, -70), "wing.R": (12, 0, 70)}),
                           7: p(pelvis=(18, 0, 0), spine_lower=(14, 0, 0), head=(-12, 0, 0),
                                **{"wing.L": (22, 0, -35), "wing.R": (-22, 0, 35), "foot.L": (20, 0, 0), "foot.R": (20, 0, 0)}),
                           16: p(pelvis=(0, 0, 0), spine_lower=(0, 0, 0), head=(0, 0, 0))}),
        "slide_enter": (14, {1: p(spine_upper=(-8, 0, 0)), 8: p(pelvis=(-44, 0, 0), spine_lower=(-24, 0, 0), spine_upper=(-3, 0, 0), head=(30, 0, 0), tail=(44, 0, 0),
                                                                        **{"wing.L": (46, -4, -30), "wing.R": (46, 4, 58), "foot.L": (42, 0, 0), "foot.R": (42, 0, 0)}),
                              14: p(pelvis=(-62, 0, 0), spine_lower=(-12, 0, 0), spine_upper=(-4, 0, 0), head=(52, 0, 0), tail=(62, 0, 0),
                                    **{"wing.L": (54, -4, -40), "wing.R": (54, 4, 72), "foot.L": (62, 0, 0), "foot.R": (62, 0, 0)})}),
        "slide_loop": (24, {1: p(pelvis=(-62, 0, -3), spine_lower=(-12, 0, 0), spine_upper=(-4, 0, 0), head=(52, 0, 3), tail=(62, 0, 0),
                                    **{"wing.L": (54, -3, -40), "wing.R": (54, 3, 72), "foot.L": (62, 0, 0), "foot.R": (62, 0, 0)}),
                             12: p(pelvis=(-62, 0, 3), spine_lower=(-10, 0, 0), spine_upper=(-4, 0, 0), head=(50, 0, -3), tail=(58, 0, 0),
                                   **{"wing.L": (52, -2, -36), "wing.R": (52, 2, 68), "foot.L": (58, 0, 0), "foot.R": (58, 0, 0)}),
                             24: p(pelvis=(-62, 0, -3), spine_lower=(-12, 0, 0), spine_upper=(-4, 0, 0), head=(52, 0, 3), tail=(62, 0, 0),
                                   **{"wing.L": (54, -3, -40), "wing.R": (54, 3, 72), "foot.L": (62, 0, 0), "foot.R": (62, 0, 0)})}),
        "slide_exit": (16, {1: p(pelvis=(-62, 0, 0), spine_lower=(-12, 0, 0), spine_upper=(-4, 0, 0), head=(52, 0, 0), tail=(62, 0, 0),
                                  **{"wing.L": (54, -3, -40), "wing.R": (54, 3, 72), "foot.L": (62, 0, 0), "foot.R": (62, 0, 0)}),
                             9: p(pelvis=(-22, 0, 0), spine_lower=(-8, 0, 0), spine_upper=(-3, 0, 0), head=(18, 0, 0), tail=(24, 0, 0),
                                  **{"wing.L": (22, 0, -18), "wing.R": (22, 0, 28), "foot.L": (25, 0, 0), "foot.R": (25, 0, 0)}),
                             16: p(pelvis=(0, 0, 0), spine_lower=(0, 0, 0), head=(0, 0, 0))}),
        "ramp_launch": (14, {1: p(pelvis=(9, 0, 0)), 7: p(pelvis=(-18, 0, 0), spine_upper=(-20, 0, 0),
                                                                  **{"wing.L": (-25, 0, -82), "wing.R": (25, 0, 82)}),
                              14: p(pelvis=(-12, 0, 0), spine_upper=(-10, 0, 0), head=(8, 0, 0),
                                    **{"wing.L": (-8, 0, -75), "wing.R": (8, 0, 75)})}),
        "ramp_flip": (30, {1: p(pelvis=(-10, 0, 0), **{"wing.L": (0, 0, -78), "wing.R": (0, 0, 78)}),
                            10: p(pelvis=(-118, 0, 0), spine_upper=(-18, 0, 0), head=(22, 0, 0),
                                  **{"wing.L": (20, 0, -88), "wing.R": (-20, 0, 88)}),
                            20: p(pelvis=(-242, 0, 0), spine_upper=(-14, 0, 0), head=(18, 0, 0),
                                  **{"wing.L": (-20, 0, -88), "wing.R": (20, 0, 88)}),
                            30: p(pelvis=(-360, 0, 0), spine_upper=(-10, 0, 0), head=(8, 0, 0),
                                  **{"wing.L": (0, 0, -78), "wing.R": (0, 0, 78)})}),
        "ramp_land": (16, {1: p(pelvis=(-12, 0, 0)), 8: p(pelvis=(18, 0, 0), spine_lower=(12, 0, 0), head=(-10, 0, 0),
                                                                **{"wing.L": (15, 0, -30), "wing.R": (-15, 0, 30)}),
                            16: p(pelvis=(0, 0, 0), spine_lower=(0, 0, 0), head=(0, 0, 0))}),
        "swim": (32, {1: p(pelvis=(-65, 0, -4), spine_upper=(-12, 0, 0), head=(25, 0, 4),
                              **{"wing.L": (-42, 15, -88), "wing.R": (42, -15, 88)}),
                       16: p(pelvis=(-65, 0, 4), spine_upper=(-10, 0, 0), head=(22, 0, -4),
                             **{"wing.L": (48, -20, -35), "wing.R": (-48, 20, 35)}),
                       32: p(pelvis=(-65, 0, -4), spine_upper=(-12, 0, 0), head=(25, 0, 4),
                             **{"wing.L": (-42, 15, -88), "wing.R": (42, -15, 88)})}),
        "shove": (18, {1: p(spine_upper=(-8, 0, 0)), 6: p(pelvis=(-14, 0, 0), spine_upper=(-28, 0, 0), head=(14, 0, 0),
                                                                **{"wing.L": (-54, -30, -24), "wing.R": (-54, 30, 24)}),
                       11: p(pelvis=(-8, 0, 0), spine_upper=(-15, 0, 0), head=(8, 0, 0),
                             **{"wing.L": (-30, -15, -18), "wing.R": (-30, 15, 18)}),
                       18: p(spine_upper=(-8, 0, 0))}),
        "hit_left": (18, {1: p(pelvis=(0, 0, 0)), 5: p(pelvis=(12, 18, -28), spine_upper=(14, -12, -18), head=(-20, 25, 18),
                                                             **{"wing.L": (25, 0, -82), "wing.R": (-15, 0, 58)}),
                          11: p(pelvis=(-4, -8, 12), head=(8, -12, -8)), 18: p(pelvis=(0, 0, 0), head=(0, 0, 0))}),
        "hit_right": (18, {1: p(pelvis=(0, 0, 0)), 5: p(pelvis=(12, -18, 28), spine_upper=(14, 12, 18), head=(-20, -25, -18),
                                                              **{"wing.L": (-15, 0, -58), "wing.R": (25, 0, 82)}),
                           11: p(pelvis=(-4, 8, -12), head=(8, 12, 8)), 18: p(pelvis=(0, 0, 0), head=(0, 0, 0))}),
        "stumble": (30, {1: p(pelvis=(8, 0, -20), head=(-10, 0, 15), **{"wing.L": (10, 0, -74), "wing.R": (-10, 0, 74)}),
                          10: p(pelvis=(-8, 0, 23), head=(12, 0, -18), **{"wing.L": (-18, 0, -50), "wing.R": (18, 0, 50)}),
                          20: p(pelvis=(5, 0, -13), head=(-8, 0, 10), **{"wing.L": (8, 0, -65), "wing.R": (-8, 0, 65)}),
                          30: p(pelvis=(0, 0, 0), head=(0, 0, 0))}),
        "recover": (24, {1: p(pelvis=(18, 0, 12), spine_lower=(16, 0, 0), head=(-18, 0, -8),
                                  **{"wing.L": (20, 0, -70), "wing.R": (-20, 0, 70)}),
                          12: p(pelvis=(-4, 0, -4), spine_lower=(-6, 0, 0), head=(8, 0, 3)),
                          24: p(pelvis=(0, 0, 0), spine_lower=(0, 0, 0), head=(0, 0, 0))}),
        "wipeout": (42, {1: p(pelvis=(0, 0, 0)), 12: p(pelvis=(-70, 20, 95), spine_lower=(-25, 0, 0), head=(30, -15, -35),
                                                             **{"wing.L": (35, 0, -95), "wing.R": (-35, 0, 95)}),
                          27: p(pelvis=(-105, -15, 185), spine_lower=(-18, 0, 0), head=(22, 10, -20)),
                          42: p(pelvis=(-92, 0, 265), spine_lower=(-10, 0, 0), head=(15, 0, -8))}),
        "defeat": (45, {1: p(pelvis=(0, 0, 0)), 18: p(pelvis=(22, 0, 10), spine_lower=(18, 0, 0), head=(-22, 0, -8),
                                                            **{"wing.L": (12, 0, -8), "wing.R": (-12, 0, 8)}),
                         45: p(pelvis=(28, 0, 14), spine_lower=(22, 0, 0), head=(-28, 0, -12),
                               **{"wing.L": (18, 0, -12), "wing.R": (-18, 0, 12)})}),
        "celebration": (36, {1: p(pelvis=(-8, 0, -8), head=(8, 0, 8), **{"wing.L": (-15, 0, -110), "wing.R": (15, 0, 110)}),
                              10: p(pelvis=(6, 0, 8), head=(-5, 0, -8), **{"wing.L": (15, 0, -155), "wing.R": (-15, 0, 155), "foot.L": (-18, 0, 0)}),
                              19: p(pelvis=(-10, 0, -8), head=(10, 0, 8), **{"wing.L": (-15, 0, -118), "wing.R": (15, 0, 118), "foot.R": (-18, 0, 0)}),
                              28: p(pelvis=(6, 0, 8), head=(-5, 0, -8), **{"wing.L": (15, 0, -155), "wing.R": (-15, 0, 155), "foot.L": (-18, 0, 0)}),
                              36: p(pelvis=(-8, 0, -8), head=(8, 0, 8), **{"wing.L": (-15, 0, -110), "wing.R": (15, 0, 110)})}),
    }
    # Python keyword syntax cannot contain dots; normalize one optional alias.
    for action_name, (length, frames) in definitions.items():
        for values in frames.values():
            if "wing_L" in values:
                values["wing.L"] = values.pop("wing_L")
        key_action(armature, action_name, length, frames)
    mesh_obj = next(child for child in armature.children if child.type == "MESH")
    create_run_action(armature, mesh_obj)
    missing = sorted(set(REQUIRED_ACTIONS) - set(definitions) - {"run"})
    if missing:
        raise RuntimeError(f"missing action definitions: {', '.join(missing)}")
    reset_pose(armature)


def validate_source(mesh_obj: bpy.types.Object, armature: bpy.types.Object,
                    builder: MeshBuilder) -> None:
    mesh_obj.data.calc_loop_triangles()
    triangles = len(mesh_obj.data.loop_triangles)
    deform_bones = sum(1 for bone in armature.data.bones if bone.use_deform)
    max_influences = max(len(weights) for weights in builder.weights)
    if not 18_000 <= triangles <= 25_000:
        raise RuntimeError(f"triangle budget failed: {triangles}")
    if deform_bones > 36:
        raise RuntimeError(f"bone budget failed: {deform_bones}")
    if max_influences > 4:
        raise RuntimeError(f"skin influence budget failed: {max_influences}")
    # Asset ceiling allows two surfaces only when cosmetics require it. Shared
    # hero/racer body stays exactly one atlas/material to protect 8-racer draws.
    if len(mesh_obj.data.materials) != 1:
        raise RuntimeError(f"one-surface contract failed: {len(mesh_obj.data.materials)}")
    actions = {action.name for action in bpy.data.actions}
    if actions != set(REQUIRED_ACTIONS):
        raise RuntimeError(f"clip contract mismatch: {sorted(actions)}")
    print(
        f"[hero-penguin] source metrics triangles={triangles} "
        f"deform_bones={deform_bones} max_influences={max_influences} "
        f"materials={len(mesh_obj.data.materials)} clips={len(actions)} "
        f"vertices={len(mesh_obj.data.vertices)}"
    )


def main() -> None:
    require_version()
    random.seed(11037)
    args = parse_args()
    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    if args.update_run_only:
        source = Path(args.animation_source or args.output).resolve()
        if not source.is_file():
            raise RuntimeError(f"animation-only source missing: {source}")
        bpy.ops.wm.open_mainfile(filepath=str(source))
        armature = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
        mesh_obj = bpy.data.objects["HeroPenguinMesh"]
        before_structure = source_structure_digest()
        before_actions = {action.name: action_digest(action) for action in bpy.data.actions if action.name != "run"}
        report = create_run_action(armature, mesh_obj)
        if source_structure_digest() != before_structure:
            raise RuntimeError("animation-only update changed geometry, skin, species, or rest rig")
        after_actions = {action.name: action_digest(action) for action in bpy.data.actions if action.name != "run"}
        if before_actions != after_actions:
            raise RuntimeError("animation-only update changed another clip")
        report["structure_sha256"] = before_structure
        report["other_clips_preserved"] = sorted(before_actions)
        if args.motion_report:
            report_path = Path(args.motion_report).resolve()
            report_path.parent.mkdir(parents=True, exist_ok=True)
            report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        # Caller retains an explicit source checkpoint; do not replace the
        # artist's existing .blend1 while updating animation.
        bpy.context.preferences.filepaths.save_version = 0
        bpy.context.scene.frame_set(1)
        bpy.ops.wm.save_as_mainfile(filepath=str(output), check_existing=False, compress=True)
        print(f"[hero-run] preserved geometry/rest rig/species and {len(before_actions)} other clips; saved {output}")
        return
    collection = reset_scene()
    armature = create_armature(collection)
    mesh_obj, builder = create_mesh(collection, armature)
    create_sockets(collection, armature)
    create_actions(armature)
    lod1_obj = create_lod1_collection(mesh_obj, armature)
    validate_source(mesh_obj, armature, builder)
    lod1_obj.data.calc_loop_triangles()
    print(f"[hero-penguin] LOD1 triangles={len(lod1_obj.data.loop_triangles)}")
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(output), check_existing=False, compress=True)
    print(f"[hero-penguin] saved {output}")


if __name__ == "__main__":
    main()
