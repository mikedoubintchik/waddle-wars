#!/usr/bin/env python3
"""Renderer-free V12 implicit sculpt contract.

V12 replaces the rejected radial lathe construction. Blender will realize this
field as fused metaball/voxel-remeshed topology only after static art approval.
Every cream face/bib region is paint on the continuous body field; the only
separate forms are recessed eyes, bill volumes, rigged paddles, tail, and feet.
"""

from __future__ import annotations


Volume = tuple[tuple[float, float, float], tuple[float, float, float]]

SCULPT_VERSION = "V12"
BODY_SMOOTH_RADIUS = 0.055
CHEEK_RELIEF_METERS = 0.026

# Neutral young silhouette: one pear torso, a distinct rounded cranium, then
# shallow cheek/chin relief. All forms overlap enough for one continuous remesh.
BODY_VOLUMES: tuple[Volume, ...] = (
    ((0.0, 0.035, 0.700), (0.495, 0.405, 0.610)),
    ((0.0, 0.018, 1.080), (0.425, 0.355, 0.440)),
    ((0.0, 0.010, 1.470), (0.385, 0.338, 0.345)),
    ((0.0, -0.005, 1.345), (0.365, 0.325, 0.275)),
)

# Relief extends only 2–4 cm past the cranium envelope. It changes highlight
# flow and catches cheek light without creating a lateral muzzle/moustache.
CHEEK_VOLUMES: tuple[Volume, ...] = (
    ((-0.165, -0.315, 1.425), (0.200, 0.033, 0.170)),
    ((0.165, -0.315, 1.425), (0.200, 0.033, 0.170)),
    ((0.0, -0.318, 1.303), (0.235, 0.031, 0.150)),
)

# Partial ellipsoids sit behind shallow sockets. Their perimeter intersects the
# remeshed hood/cheek surface; only a modest warm sclera lens remains visible.
EYE_CENTER_X = 0.120
EYE_CENTER_Y = -0.330
EYE_CENTER_Z = 1.535
EYE_RADII = (0.094, 0.042, 0.119)
SOCKET_CENTER_Y = -0.365
SOCKET_RADII = (0.086, 0.044, 0.105)

# One dark upper-lid cushion per eye. These join the hood field and occlude only
# the top 12–16% of the eye; there is intentionally no cream brow/lid geometry.
UPPER_LID_CENTER_Z = 1.635
UPPER_LID_RADII = (0.108, 0.056, 0.030)

# y, half-width, half-height, center-z. Upper and lower remain distinct convex
# volumes, with thin dark mouth seam at their meeting plane.
BILL_UPPER_SECTIONS = (
    (-0.380, 0.112, 0.040, 1.402),
    (-0.415, 0.110, 0.044, 1.403),
    (-0.458, 0.101, 0.041, 1.402),
    (-0.500, 0.079, 0.033, 1.399),
    (-0.535, 0.052, 0.024, 1.396),
    (-0.555, 0.028, 0.014, 1.393),
)
BILL_LOWER_SECTIONS = (
    (-0.383, 0.094, 0.021, 1.356),
    (-0.418, 0.091, 0.024, 1.357),
    (-0.460, 0.082, 0.022, 1.359),
    (-0.501, 0.064, 0.018, 1.363),
    (-0.535, 0.041, 0.012, 1.369),
    (-0.553, 0.023, 0.007, 1.376),
)

# Thick rounded paddles. Root is buried ~7 cm into torso field. A shared local
# basis is required later so jump/slide pose both broad planes predictably.
WING_ROOT = (0.305, 0.010, 1.185)
WING_TIP = (0.575, 0.018, 0.555)
WING_HALF_WIDTH = 0.145
WING_HALF_THICKNESS = 0.052

TAIL_VOLUMES: tuple[Volume, ...] = (
    ((-0.112, 0.380, 0.430), (0.130, 0.105, 0.072)),
    ((0.0, 0.397, 0.412), (0.136, 0.112, 0.075)),
    ((0.112, 0.380, 0.430), (0.130, 0.105, 0.072)),
)

FOOT_CENTER_X = 0.215
FOOT_CENTER_Y = -0.100
FOOT_CENTER_Z = 0.105
FOOT_RADII = (0.142, 0.170, 0.075)
