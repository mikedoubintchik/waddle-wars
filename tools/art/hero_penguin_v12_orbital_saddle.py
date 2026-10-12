"""Pure local-frame feather-paint field for the opt-in Z04 source study.

No renderer, geometry, camera, material color or shader dependency. The caller
supplies the same fresh eye_surface_frame used by globe, fold and gaze. Output
is a scalar field for the existing feather-mask smoothstep, not literal RGB.
"""
from __future__ import annotations

import math

RECIPE = {
    "contract": "orbital-saddle-paint-v1",
    "half_width_m": 0.108,
    "lower_width_gain_m": 0.025,
    "lower_nasal_sweep_m": 0.035,
    "vertical_center_m": -0.026,
    "upper_radius_m": 0.120,
    "lower_radius_m": 0.170,
    "almond_horizontal_power": 1.75,
    "depth_fade_m": [-0.085, -0.040],
    "geometry_created": False,
    "source_fidelity_approved": False,
}


def smooth(low, high, value):
    t = max(0.0, min(1.0, (value - low) / (high - low)))
    return t * t * (3.0 - 2.0 * t)


def local_field(x, depth, z, side):
    """Almond crown opening into a softer, nasal-directed lower teardrop."""
    if side not in (-1.0, 1.0) or not all(math.isfinite(value) for value in (x, depth, z)):
        raise ValueError("saddle requires finite local coordinates and anatomical side")
    lower = smooth(0.035, 0.185, -z)
    width = RECIPE["half_width_m"] + RECIPE["lower_width_gain_m"] * lower
    center_x = -side * RECIPE["lower_nasal_sweep_m"] * lower
    vertical = z - RECIPE["vertical_center_m"]
    radius = RECIPE["lower_radius_m"] if vertical < 0 else RECIPE["upper_radius_m"]
    almond = abs((x - center_x) / width) ** RECIPE["almond_horizontal_power"] + (vertical / radius) ** 2
    # No second patch on the back of the cranium from a 2-D projection.
    visibility = smooth(*RECIPE["depth_fade_m"], depth)
    return min(8.0, almond + 4.0 * (1.0 - visibility))


def saddle_orbit_field(point, frame_for_side):
    if len(point) != 3 or not all(math.isfinite(value) for value in point):
        raise ValueError("saddle requires a finite saved-source point")
    # Restrict work to the face. Chest/trail are outside this field; the caller
    # retains its original gold-ear and cyan-stripe compositing afterwards.
    if point[2] < 1.15 or point[2] > 1.76 or abs(point[0]) > 0.48 or point[1] > 0.10:
        return 8.0
    result = 8.0
    for side in (-1.0, 1.0):
        origin, across, normal, up = frame_for_side(side)
        relative = tuple(point[index] - origin[index] for index in range(3))
        x, depth, z = (sum(relative[index] * axis[index] for index in range(3))
                       for axis in (across, normal, up))
        result = min(result, local_field(x, depth, z, side))
    return result
