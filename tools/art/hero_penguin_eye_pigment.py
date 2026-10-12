"""Original, renderer-free blue-grey iris pigment for source art review.

``iris_linear_rgba(x, z)`` accepts coordinates on a normalized iris tangent
disk, before ellipsoid projection. Store its result as linear vertex color on
the existing iris mesh. It adds no geometry, material surface, texture, RNG,
lighting, baked catchlight, pupil or gaze behavior.

The warm inner blue and dark outer transition are broad pigment gradients.
Only second/third-order Cartesian harmonics vary sectors: no high-frequency
spokes, radial barcode, procedural noise or emissive/neon values. This bounded
math is not a claim of reference fidelity; actual lit eyes still need review.
"""

from __future__ import annotations

import math


# Linear-light values, not display/sRGB swatches. The inner color is warmer and
# less saturated than the middle blue-grey; all remain deliberately subdued.
INNER_LINEAR = (0.095, 0.150, 0.172)
MID_LINEAR = (0.075, 0.175, 0.232)
OUTER_LINEAR = (0.016, 0.032, 0.048)
SECTOR_STRENGTH = 0.060
DISK_ROUNDOFF_TOLERANCE = 1e-9


def _smoothstep(low: float, high: float, value: float) -> float:
    t = min(1.0, max(0.0, (value - low) / (high - low)))
    return t * t * (3.0 - 2.0 * t)


def iris_linear_rgba(x: float, z: float) -> tuple[float, float, float, float]:
    """Return opaque linear RGBA on the unit disk; reject invalid coordinates.

    Tiny trigonometric roundoff beyond radius one is projected to the boundary.
    Anything farther outside the disk is a caller error, not silently clamped
    material sampling. The Cartesian harmonic vanishes at the center and has
    no angular branch cut. No random state is read or changed.
    """
    if not math.isfinite(x) or not math.isfinite(z):
        raise ValueError("iris tangent coordinates must be finite")
    radius = math.hypot(x, z)
    if radius > 1.0 + DISK_ROUNDOFF_TOLERANCE:
        raise ValueError("iris tangent coordinates must lie inside the unit disk")
    if radius > 1.0:
        x, z = x / radius, z / radius
        radius = 1.0

    middle = _smoothstep(0.32, 0.74, radius)
    outer = _smoothstep(0.76, 1.0, radius)
    pigment = tuple(inner + (mid - inner) * middle
                    for inner, mid in zip(INNER_LINEAR, MID_LINEAR))
    pigment = tuple(value + (edge - value) * outer
                    for value, edge in zip(pigment, OUTER_LINEAR))

    # r² cos(2θ), r³ sin(3θ): broad sectors with a known frequency ceiling.
    # The envelope removes the variation at the pupil center and limbal edge.
    sector = 0.65 * (x * x - z * z) + 0.35 * (3.0 * x * x * z - z * z * z)
    envelope = _smoothstep(0.20, 0.48, radius) * (1.0 - _smoothstep(0.74, 1.0, radius))
    gain = 1.0 + SECTOR_STRENGTH * sector * envelope
    return tuple(value * gain for value in pigment) + (1.0,)
