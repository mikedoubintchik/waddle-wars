#!/usr/bin/env python3
"""Pure-data V11 hero sculpt contract shared by source build and static QA.

No Blender/Godot imports live here. Static review can therefore prove major
silhouette, socket, bill, and paddle decisions before occupying renderer slot.
Authoring coordinates face -Y; Blender export mirrors them to Godot -Z.
"""

from __future__ import annotations

import math


FusedVolume = tuple[
    tuple[float, float, float],
    tuple[float, float, float],
]

BODY_ORIGIN = (0.0, 0.0, 0.930)
BODY_BLEND_RADIUS = 0.043
BODY_VOLUMES: tuple[FusedVolume, ...] = (
    # Pear torso: low planted mass with a separate chest/shoulder transition.
    ((0.0, 0.035, 0.660), (0.500, 0.420, 0.580)),
    ((0.0, 0.045, 0.820), (0.475, 0.405, 0.550)),
    ((0.0, -0.025, 1.080), (0.430, 0.375, 0.470)),
    ((0.0, 0.000, 1.285), (0.375, 0.330, 0.350)),
    # Short, wide plush cranium. Neck bridge remains continuous but no sphere
    # appears perched on torso.
    ((0.0, 0.020, 1.515), (0.415, 0.355, 0.330)),
    ((0.0, -0.005, 1.405), (0.395, 0.345, 0.300)),
    # Cheek/muzzle volumes intentionally exceed cranium front/side envelope.
    # Their union changes silhouette and normals, not only semantic paint.
    ((-0.205, -0.292, 1.420), (0.265, 0.300, 0.245)),
    ((0.205, -0.292, 1.420), (0.265, 0.300, 0.245)),
    ((0.0, -0.335, 1.365), (0.225, 0.235, 0.185)),
    ((0.0, -0.245, 1.275), (0.300, 0.225, 0.205)),
    # Broad hood masses frame socket rims and keep dark bridge structural.
    ((-0.150, -0.170, 1.600), (0.215, 0.205, 0.145)),
    ((0.150, -0.170, 1.600), (0.215, 0.205, 0.145)),
)

EYE_CENTER_X = 0.150
EYE_CENTER_Y = -0.535
EYE_CENTER_Z = 1.545
EYE_RADII = (0.112, 0.098, 0.126)
EYE_SOCKET_RADII = (0.142, 0.138)
EYE_SOCKET_INSET = 0.047
EYE_UPPER_RIM = 0.021
EYE_LOWER_RIM = 0.013
IRIS_RADII = (0.058, 0.018, 0.074)
PUPIL_RADII = (0.032, 0.010, 0.047)

# y, half width, half height, center z. Six monotonic sections form rounded
# convex upper/lower wedges without circular puck cross-sections.
BILL_UPPER_SECTIONS = (
    (-0.520, 0.158, 0.054, 1.404),
    (-0.550, 0.154, 0.060, 1.404),
    (-0.585, 0.142, 0.058, 1.402),
    (-0.620, 0.112, 0.048, 1.399),
    (-0.650, 0.072, 0.034, 1.396),
    (-0.672, 0.034, 0.017, 1.394),
)
BILL_LOWER_SECTIONS = (
    (-0.525, 0.132, 0.025, 1.350),
    (-0.555, 0.128, 0.028, 1.352),
    (-0.590, 0.115, 0.027, 1.355),
    (-0.623, 0.090, 0.022, 1.360),
    (-0.651, 0.055, 0.015, 1.367),
    (-0.669, 0.028, 0.008, 1.376),
)

# Rest-space paddle contract. Root is buried 8–10 cm inside shoulder union;
# broad region remains nearly constant before a true rounded end cap.
WING_ROOT_X = 0.255
WING_ROOT_Y = -0.004
WING_ROOT_Z = 1.145
WING_OUTWARD = 0.355
WING_DROP = 0.655
WING_MAX_HALF_WIDTH = 0.205
WING_MAX_HALF_THICKNESS = 0.052
WING_LONGITUDINAL_RINGS = 28
WING_CROSS_SEGMENTS = 20


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    if edge0 == edge1:
        return 0.0
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def ray_ellipsoid_far(origin: tuple[float, float, float],
                      direction: tuple[float, float, float],
                      volume: FusedVolume) -> float | None:
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
    far = (-linear + math.sqrt(max(0.0, discriminant))) / (2.0 * quadratic)
    return far if far > 0.0 else None


def smooth_outer_radius(values: list[float],
                        blend_radius: float = BODY_BLEND_RADIUS) -> float:
    if not values:
        raise RuntimeError("V11 fused sculpt ray missed every source volume")
    result = min(values)
    for value in sorted(values)[1:]:
        distance = abs(result - value)
        if distance >= blend_radius:
            result = max(result, value)
            continue
        transition = (blend_radius - distance) / blend_radius
        result = max(result, value) + transition * transition * blend_radius * 0.25
    return result


def sculpt_eye_socket_radius(origin: tuple[float, float, float],
                             direction: tuple[float, float, float],
                             radius: float) -> float:
    """Carve sockets and raise body-native lid rims in radial manifold.

    Eyeballs later intersect this recessed surface. Body depth therefore hides
    their perimeter while upper/lower rims remain continuous cheek/hood mesh.
    """
    provisional = tuple(origin[index] + direction[index] * radius
                        for index in range(3))
    x, y, z = provisional
    if y > -0.08 or z < 1.395 or z > 1.705:
        return radius
    front_gate = smoothstep(0.08, 0.48, -direction[1])
    result = radius
    for side in (-1.0, 1.0):
        dx = (x - side * EYE_CENTER_X) / EYE_SOCKET_RADII[0]
        dz = (z - EYE_CENTER_Z) / EYE_SOCKET_RADII[1]
        q = math.sqrt(dx * dx + dz * dz)
        core = 1.0 - smoothstep(0.30, 0.96, q)
        inset = EYE_SOCKET_INSET * core * front_gate
        # Elliptical lip peaks around socket perimeter. Upper hood is stronger;
        # cream lower cheek rim stays softer and catches a separate highlight.
        ring = math.exp(-((q - 0.91) / 0.13) ** 2) * front_gate
        corner_fade = smoothstep(1.0, 0.40, abs(dx))
        upper = ring * smoothstep(-0.08, 0.38, dz) * corner_fade
        lower = ring * smoothstep(0.08, -0.40, dz) * corner_fade
        result += EYE_UPPER_RIM * upper + EYE_LOWER_RIM * lower - inset
    return result


def body_radius(direction: tuple[float, float, float]) -> float:
    hits = [hit for volume in BODY_VOLUMES
            if (hit := ray_ellipsoid_far(BODY_ORIGIN, direction, volume)) is not None]
    return sculpt_eye_socket_radius(
        BODY_ORIGIN, direction, smooth_outer_radius(hits))


def body_position(direction: tuple[float, float, float]) -> tuple[float, float, float]:
    radius = body_radius(direction)
    return tuple(BODY_ORIGIN[index] + direction[index] * radius
                 for index in range(3))

