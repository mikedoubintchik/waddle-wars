#!/usr/bin/env python3
"""Renderer-free V12 implicit sculpt contract.

V12 replaces the rejected radial lathe construction. Blender realizes this
field as a closed, shared-edge source sculpt; runtime integration needs review.
Every cream face/bib region is paint on the continuous body field; the only
separate forms are recessed eyes, bill volumes, rigged paddles, tail, and feet.
"""

from __future__ import annotations

import math
from functools import lru_cache


Volume = tuple[tuple[float, float, float], tuple[float, float, float]]

SCULPT_VERSION = "V12X"
BODY_SMOOTH_RADIUS = 0.105
CHEEK_RELIEF_METERS = 0.026

# A single softly squared torso replaces the stacked lower-belly ellipsoid.
# The vertical exponent rounds the base without a second curvature band.
TORSO_CENTER = (0.0, 0.022, 0.691)
TORSO_RADII = (0.526, 0.427, 0.600)
TORSO_VERTICAL_EXPONENT = 2.8
TORSO_UPPER_EXPONENT = 2.1

# Neutral young silhouette: one pear torso, a distinct rounded cranium, then
# shallow cheek/chin relief. All forms overlap enough for one continuous remesh.
BODY_VOLUMES: tuple[Volume, ...] = (
    ((0.0, 0.010, 1.020), (0.375, 0.345, 0.368)),
    ((0.0, 0.010, 1.441), (0.400, 0.365, 0.365)),
    ((0.0, -0.006, 1.280), (0.357, 0.332, 0.257)),
)

# Relief extends only 2–4 cm past the cranium envelope. It changes highlight
# flow and catches cheek light without creating a lateral muzzle/moustache.
CHEEK_VOLUMES: tuple[Volume, ...] = (
    ((-0.162, -0.198, 1.394), (0.222, 0.203, 0.146)),
    ((0.162, -0.198, 1.394), (0.222, 0.203, 0.146)),
    ((0.0, -0.171, 1.277), (0.227, 0.185, 0.184)),
)

# Partial ellipsoids sit behind shallow sockets. Their perimeter intersects the
# remeshed hood/cheek surface; only a modest warm sclera lens remains visible.
EYE_CENTER_X = 0.181
EYE_CENTER_Y = -0.330
EYE_CENTER_Z = 1.548
EYE_RADII = (0.108, 0.089, 0.146)
EYE_BURY_DEPTH = 0.069
EYE_ORBITAL_PITCH_FACTOR = 0.50
EYE_ORBITAL_HEADING_FACTOR = 1.35
EYE_GAZE_TARGET = (0.0, -3.5, 2.45)
# Authored binocular stylization: retain temporal iris coverage in profile.
# This intentionally relaxes physical target convergence, never tracks camera.
EYE_GAZE_HORIZONTAL_SCALE = 0.60
SOCKET_CENTER_Y = -0.365
SOCKET_RADII = (0.090, 0.135, 0.121)

# Used by the actual globe/skull aperture in add_upper_lid. Corners close more
# than the lower lid; the outer corner closes slightly further, giving a
# bilateral upper arch instead of a complete raised ring.
EYELID_UPPER_COVER = 0.210
EYELID_CORNER_TAPER = 0.115
EYELID_OUTER_CORNER_BIAS = 0.18

# Upper lid belongs to the head's implicit surface, not an annular cover mesh.
# This millimeter-scale union is deliberately independent of the torso blend.
UPPER_FOLD_RADIAL_MARGIN = (0.003, 0.004, 0.003)
UPPER_FOLD_APERTURE_HEIGHT = 0.083
UPPER_FOLD_APERTURE_CURVE = 0.024
UPPER_FOLD_APERTURE_WIDTH = 0.080
UPPER_FOLD_BLEND = 0.006

# A larger iris leaves a readable warm sclera crescent, instead of a small
# black button pasted onto a white globe. These remain surface pigment patches.
LIMBAL_RADII = (0.067, 0.087)
IRIS_RADII = (0.061, 0.081)
PUPIL_RADII = (0.037, 0.050)

# y, half-width, lobe-height, seam-z. Both lobes share a curved smile line;
# the upper dome and tucked lower bill do not overlap into a capsule.
BILL_UPPER_SECTIONS = (
    (-0.351, 0.100, 0.087, 1.389),
    (-0.397, 0.125, 0.090, 1.378),
    (-0.431, 0.117, 0.084, 1.371),
    (-0.466, 0.087, 0.067, 1.372),
    (-0.500, 0.050, 0.042, 1.380),
    (-0.526, 0.023, 0.022, 1.388),
    (-0.538, 0.003, 0.002, 1.392),
)
BILL_LOWER_SECTIONS = (
    (-0.354, 0.098, 0.013, 1.389),
    (-0.397, 0.120, 0.031, 1.378),
    (-0.431, 0.110, 0.034, 1.371),
    (-0.463, 0.079, 0.026, 1.373),
    (-0.488, 0.044, 0.016, 1.382),
    (-0.507, 0.017, 0.004, 1.389),
    (-0.512, 0.002, 0.001, 1.392),
)

# Upper third carries the breadth. The distal half tapers continuously along a
# bowed centerline; the tip is a rounded feather point, never a capsule end.
WING_ROOT = (0.310, -0.015, 1.225)
WING_CONTROL = (0.615, 0.020, 0.987)
WING_TIP = (0.705, -0.080, 0.484)
WING_HALF_WIDTH = 0.128
WING_HALF_THICKNESS = 0.045
WING_SECTION_ROLL_RADIANS = math.radians(50.0)

TAIL_VOLUMES: tuple[Volume, ...] = (
    ((-0.112, 0.380, 0.430), (0.130, 0.105, 0.072)),
    ((0.0, 0.397, 0.412), (0.136, 0.112, 0.075)),
    ((0.112, 0.380, 0.430), (0.130, 0.105, 0.072)),
)

FOOT_CENTER_X = 0.230
FOOT_CENTER_Y = -0.073
FOOT_CENTER_Z = 0.090
FOOT_RADII = (0.132, 0.134, 0.055)


def eye_tangent_aperture_radii(radii=EYE_RADII, bury_depth=EYE_BURY_DEPTH):
    """Eye half-aperture against a tangent plane, not the curved skull/lid.

    This analytical guard separates the visible lens from the hidden globe.
    Actual eye/skull intersections and expression still require rendered review.
    """
    if len(radii) != 3 or any(not math.isfinite(r) or r <= 0.0 for r in radii):
        raise ValueError("eye radii must be three finite positive values")
    if not 0.0 < bury_depth < radii[1]:
        raise ValueError("burial must leave a positive exposed eye dome")
    scale = math.sqrt(1.0 - (bury_depth / radii[1]) ** 2)
    return radii[0] * scale, radii[2] * scale


def bill_smile_offset(y, width, cosine):
    """Raised mouth corners taper toward the compact bill tip, never a shelf."""
    blend = min(1.0, max(0.0, (y + 0.480) / 0.085))
    root_weight = blend * blend * (3.0 - 2.0 * blend)
    return 0.046 * abs(cosine) ** 1.6 * min(1.0, width / 0.080) * root_weight


def bill_section_height(y, width, height, center_z, cosine, sine, lobe=""):
    """Keep commissures raised without flattening the upper bill's dome.

    The smile belongs to the mouth edge. Applying its full displacement to
    the upper roof lifted intermediate angles above the central ridge, making
    the bill read as a rectangular button. Fade that displacement toward the
    roof while retaining the same seam, corners, and compact forward tip.
    """
    smile = bill_smile_offset(y, width, cosine)
    if lobe == "upper":
        roof = max(0.0, sine)
        return (center_z + 0.0024 + height * roof
                - height * 0.018 * max(0.0, -sine) + smile * (1.0 - roof))
    if lobe == "lower":
        return (center_z - 0.0024 - height * max(0.0, -sine)
                + height * 0.018 * max(0.0, sine) + smile)
    return center_z + sine * height + smile


def paddle_cross_section(axis, side):
    """Orthonormal ring frame with a mirrored 50-degree side-facing roll.

    Reflection reverses handedness, so the left wing needs the opposite roll
    sign. Returning broad and axis-cross-broad retains outward ring winding.
    """
    if side not in (-1.0, 1.0):
        raise ValueError("wing side must be -1 or +1")

    def normalized(value):
        length = math.sqrt(sum(component * component for component in value))
        if length < 1e-12:
            raise ValueError("wing frame requires a nondegenerate axis")
        return tuple(component / length for component in value)

    def cross(a, b):
        return (a[1] * b[2] - a[2] * b[1],
                a[2] * b[0] - a[0] * b[2],
                a[0] * b[1] - a[1] * b[0])

    axis = normalized(axis)
    broad = normalized((side * -axis[2], 0.0, side * axis[0]))
    thick = normalized(cross(axis, broad))
    roll = side * WING_SECTION_ROLL_RADIANS
    broad = normalized(tuple(b * math.cos(roll) + t * math.sin(roll)
                             for b, t in zip(broad, thick)))
    return broad, normalized(cross(axis, broad))


def eyelid_fractions(angle, side):
    """Inner/outer globe-intersection radii, mirrored by anatomical side."""
    if side not in (-1.0, 1.0):
        raise ValueError("eye side must be -1 or +1")
    cosine, sine = math.cos(angle), math.sin(angle)
    upper = max(0.0, sine)
    outward = side * cosine
    corner = abs(cosine) ** 6
    inner = 0.977 - EYELID_UPPER_COVER * upper ** 1.2
    inner -= EYELID_CORNER_TAPER * corner * (1.0 + EYELID_OUTER_CORNER_BIAS * outward)
    inner -= 0.016 * upper * outward
    outer = 1.018 + 0.055 * upper
    return inner, outer


def eyelid_waterline_weight(angle, radial_fraction):
    """Blend the upper lash edge into the lid, without a separate brow mesh.

    The lower waterline stays narrow. Upper pigment is broader, but reaches
    zero before the outer skull join so no dark geometric ring is introduced.
    """
    if not 0.0 <= radial_fraction <= 1.0:
        raise ValueError("eyelid radial fraction must be within [0, 1]")
    upper = max(0.0, math.sin(angle)) ** 0.65
    fade_end = 0.30 + 0.50 * upper
    value = min(1.0, max(0.0, (radial_fraction - 0.03) / (fade_end - 0.03)))
    return 1.0 - value * value * (3.0 - 2.0 * value)


def project_eye_patch(point, offset=0.0):
    """Project a tangent-patch point to the complete eye ellipsoid.

    Unlike clamping the front-facing square root, this remains valid for a
    turned-in iris whose patch crosses the globe's x/z silhouette.
    """
    length = math.sqrt(sum((point[i] / EYE_RADII[i]) ** 2 for i in range(3)))
    if length < 1e-12:
        raise ValueError("cannot project an eye patch from the globe center")
    surface = tuple(point[i] / length for i in range(3))
    normal = tuple(surface[i] / EYE_RADII[i] ** 2 for i in range(3))
    normal_length = math.sqrt(sum(value * value for value in normal))
    return tuple(surface[i] + normal[i] * offset / normal_length for i in range(3))


def eye_patch_faces(segments, rings):
    """Consistent center-fan and annulus winding for an outward eye patch."""
    if segments < 3 or rings < 1:
        raise ValueError("eye patch needs at least three segments and one ring")
    faces = [(0, 1 + segment, 1 + (segment + 1) % segments) for segment in range(segments)]
    for ring in range(rings - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            a = 1 + ring * segments + segment
            b = 1 + ring * segments + nxt
            c = 1 + (ring + 1) * segments + nxt
            d = 1 + (ring + 1) * segments + segment
            faces.append((a, d, c, b))
    return faces


def base_body_field(points):
    """Shared pre-eye implicit surface for Blender and the static shape probe.

    Import NumPy lazily so reading the scalar design contract requires no art
    runtime. The field's zero contour, not its interior magnitude, is authored.
    """
    import numpy as np

    points = np.asarray(points)
    p = (points - np.asarray(TORSO_CENTER)) / np.asarray(TORSO_RADII)
    # Broader grounded lower belly, softer narrower shoulder rise. Both sides
    # have a zero derivative at the equator, so there is no stacked-volume rim.
    power = np.where(p[..., 2] < 0.0, TORSO_VERTICAL_EXPONENT, TORSO_UPPER_EXPONENT)
    q = p[..., 0] ** 2 + p[..., 1] ** 2 + np.abs(p[..., 2]) ** power
    gradient = np.stack((2.0 * p[..., 0] / TORSO_RADII[0],
                         2.0 * p[..., 1] / TORSO_RADII[1],
                         power * np.abs(p[..., 2]) ** (power - 1.0) / TORSO_RADII[2]), axis=-1)
    torso = (q - 1.0) / np.maximum(np.linalg.norm(gradient, axis=-1), 2.0)

    def union(a, b):
        blend = np.maximum(BODY_SMOOTH_RADIUS - np.abs(a - b), 0.0) / BODY_SMOOTH_RADIUS
        return np.minimum(a, b) - blend * blend * BODY_SMOOTH_RADIUS * 0.25

    def volumes_field(volumes):
        field = np.full(points.shape[:-1], 100.0)
        for center, radii in volumes:
            local = points - np.asarray(center)
            radius = np.asarray(radii)
            k0 = np.linalg.norm(local / radius, axis=-1)
            k1 = np.linalg.norm(local / (radius * radius), axis=-1)
            distance = k0 * (k0 - 1.0) / np.maximum(k1, 1e-8)
            field = union(field, distance)
        return field

    # Smooth minimum is commutative but not associative. Union the mirrored
    # cheek pair together before the skull, otherwise evaluation order makes
    # left/right facial curvature differ by up to 2 mm.
    upper = union(volumes_field(BODY_VOLUMES), volumes_field(CHEEK_VOLUMES))
    return union(torso, upper)


@lru_cache(maxsize=2)
def eye_surface_frame(side):
    """Immutable frame from the pre-eye skull, never from the final fold field.

    The former nearly horizontal normal left the upper globe floating up to
    43 mm above the sloping skull. Base-field heading plus a shallower authored
    pitch seats the globe while keeping forward gaze clear of the lower cheek.
    Q's full gradient pitch buried the lower iris; pitch is an art parameter,
    independently guarded by actual perimeter intersections. Return immutable
    tuples, safe for cached callers.
    """
    import numpy as np

    if side not in (-1.0, 1.0):
        raise ValueError("eye side must be -1 or +1")
    low, high = -0.70, 0.05
    for _ in range(35):
        middle = (low + high) * 0.5
        if float(base_body_field((side * EYE_CENTER_X, middle, EYE_CENTER_Z))) > 0.0:
            low = middle
        else:
            high = middle
    origin = np.asarray((side * EYE_CENTER_X, (low + high) * 0.5, EYE_CENTER_Z))
    epsilon = np.eye(3) * 1e-5
    normal = np.asarray([float(base_body_field(origin + offset)
                               - base_body_field(origin - offset)) / 2e-5
                         for offset in epsilon])
    normal[0] *= EYE_ORBITAL_HEADING_FACTOR
    normal[2] *= EYE_ORBITAL_PITCH_FACTOR
    normal /= np.linalg.norm(normal)
    across = np.asarray((-normal[1], normal[0], 0.0))
    across /= np.linalg.norm(across)
    up = np.cross(normal, across)
    return tuple(tuple(float(value) for value in vector)
                 for vector in (origin, across, normal, up))


def sculpt_body_field(points):
    """One closed head/body surface including bilateral upper eyelid folds.

    No lower ring, socket subtraction, or recursively moving eye anchor. The
    two fold volumes are combined symmetrically before union with the skull.
    """
    import numpy as np

    points = np.asarray(points)
    base = base_body_field(points)
    folds = []
    for side in (-1.0, 1.0):
        origin, across, normal, up = map(np.asarray, eye_surface_frame(side))
        relative = points - origin
        local = np.stack((relative @ across, relative @ normal, relative @ up), axis=-1)
        centered = local + np.asarray((0.0, EYE_BURY_DEPTH, 0.0))
        radius = np.asarray(EYE_RADII) + np.asarray(UPPER_FOLD_RADIAL_MARGIN)
        k0 = np.linalg.norm(centered / radius, axis=-1)
        k1 = np.linalg.norm(centered / (radius * radius), axis=-1)
        envelope = k0 * (k0 - 1.0) / np.maximum(k1, 1e-8)
        # Clip the upper globe envelope with an arched aperture. Unlike Q/R's
        # small ellipsoid bump, this covers continuously to the real skull
        # join: no exposed white island above a detached transverse brow.
        lower_edge = (UPPER_FOLD_APERTURE_HEIGHT - UPPER_FOLD_APERTURE_CURVE
                      * (local[..., 0] / UPPER_FOLD_APERTURE_WIDTH) ** 2 - local[..., 2])
        width = 0.002
        blend = np.maximum(width - np.abs(envelope - lower_edge), 0.0) / width
        folds.append(np.maximum(envelope, lower_edge) + blend * blend * width * 0.25)
    fold = np.minimum(folds[0], folds[1])  # Widely separated; no bridge between eyes.
    blend = np.maximum(UPPER_FOLD_BLEND - np.abs(base - fold), 0.0) / UPPER_FOLD_BLEND
    return np.minimum(base, fold) - blend * blend * UPPER_FOLD_BLEND * 0.25


def eye_gaze_center(side):
    """Camera-independent pigment aim with a moderated nasal displacement.

    Exact ellipsoid-normal convergence to the shared target displaced the
    iris almost to the nasal aperture edge, leaving a thin white lens from
    the side. Keep the same globe and vertical aim, and art-direct horizontal
    placement. This is deliberately not physically exact binocular focus.
    """
    import numpy as np
    origin, across, normal, up = map(np.asarray, eye_surface_frame(side))
    direction = np.asarray(EYE_GAZE_TARGET) - (origin - normal * EYE_BURY_DEPTH)
    direction /= np.linalg.norm(direction)
    local = np.asarray((direction @ across, direction @ normal, direction @ up))
    denominator = float(np.linalg.norm(np.asarray(EYE_RADII) * local))
    return (EYE_GAZE_HORIZONTAL_SCALE * EYE_RADII[0] ** 2 * local[0] / denominator,
            EYE_RADII[2] ** 2 * local[2] / denominator)


def upper_lid_pigment_weight(point):
    """Upper-only feather pigmentation on the shared lid, not raised geometry."""
    if point[2] < 1.49 or point[2] > 1.73 or point[1] > -0.10 or abs(point[0]) > 0.40:
        return 0.0

    def smooth(low, high, value):
        t = min(1.0, max(0.0, (value - low) / (high - low)))
        return t * t * (3.0 - 2.0 * t)

    weight = 0.0
    for side in (-1.0, 1.0):
        origin, across, normal, up = eye_surface_frame(side)
        relative = tuple(point[i] - origin[i] for i in range(3))
        x, depth, z = (sum(relative[i] * axis[i] for i in range(3)) for axis in (across, normal, up))
        edge = z - UPPER_FOLD_APERTURE_HEIGHT + UPPER_FOLD_APERTURE_CURVE * (x / UPPER_FOLD_APERTURE_WIDTH) ** 2
        upper = smooth(-0.002, 0.001, edge) * (1.0 - smooth(0.010, 0.025, edge))
        upper *= smooth(-0.030, -0.005, depth) * (1.0 - smooth(0.075, 0.100, abs(x)))
        weight = max(weight, upper)
    return weight
