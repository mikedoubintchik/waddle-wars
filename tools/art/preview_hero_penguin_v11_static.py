#!/usr/bin/env python3
"""Render renderer-free V11 sculpt proofs from the shared design contract.

This is deliberately not a Blender/Godot substitute. It visualizes the fused
implicit construction, recessed eyes, bill volumes, and buried paddle roots so
art direction can reject structural decisions before an export slot is used.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

try:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont
except ImportError as exc:  # pragma: no cover - authoring-only dependency guard.
    raise SystemExit("V11 static preview needs authoring-only Pillow and NumPy") from exc

from hero_penguin_v11_design import (
    BILL_LOWER_SECTIONS,
    BILL_UPPER_SECTIONS,
    BODY_VOLUMES,
    EYE_CENTER_X,
    EYE_CENTER_Y,
    EYE_CENTER_Z,
    EYE_RADII,
    WING_DROP,
    WING_MAX_HALF_THICKNESS,
    WING_MAX_HALF_WIDTH,
    WING_OUTWARD,
    WING_ROOT_X,
    WING_ROOT_Y,
    WING_ROOT_Z,
)


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = Path("/tmp/waddle-hero-penguin-v11-static/sculpt")
DEFAULT_MATERIAL = Path("/tmp/waddle-hero-penguin-v11-static/material")
RENDER_WIDTH = 380
RENDER_HEIGHT = 500
EPSILON = 0.00145

NAVY = np.array((0.040, 0.086, 0.138), dtype=np.float32)
CREAM = np.array((0.775, 0.704, 0.575), dtype=np.float32)
ORANGE = np.array((0.930, 0.405, 0.055), dtype=np.float32)
WARM = np.array((0.665, 0.238, 0.055), dtype=np.float32)
CYAN = np.array((0.045, 0.330, 0.380), dtype=np.float32)
SCLERA = np.array((0.805, 0.785, 0.690), dtype=np.float32)
IRIS = np.array((0.205, 0.385, 0.525), dtype=np.float32)
PUPIL = np.array((0.009, 0.016, 0.024), dtype=np.float32)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--material-dir", type=Path, default=DEFAULT_MATERIAL)
    return parser.parse_args()


def normalize(values: np.ndarray) -> np.ndarray:
    return values / np.maximum(1e-8, np.linalg.norm(values, axis=-1, keepdims=True))


def ellipsoid_sdf(points: np.ndarray, center: tuple[float, float, float],
                  radii: tuple[float, float, float]) -> np.ndarray:
    offset = points - np.asarray(center, dtype=np.float32)
    radius = np.asarray(radii, dtype=np.float32)
    scaled = offset / radius
    k0 = np.linalg.norm(scaled, axis=-1)
    k1 = np.linalg.norm(offset / (radius * radius), axis=-1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-7)


def oriented_ellipsoid_sdf(points: np.ndarray, center: np.ndarray,
                           axes: np.ndarray, radii: tuple[float, float, float]) -> np.ndarray:
    local = (points - center) @ axes.T
    radius = np.asarray(radii, dtype=np.float32)
    scaled = local / radius
    k0 = np.linalg.norm(scaled, axis=-1)
    k1 = np.linalg.norm(local / (radius * radius), axis=-1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-7)


def smooth_min(first: np.ndarray, second: np.ndarray, radius: float) -> np.ndarray:
    blend = np.clip(0.5 + 0.5 * (second - first) / radius, 0.0, 1.0)
    return second * (1.0 - blend) + first * blend - radius * blend * (1.0 - blend)


def smooth_max(first: np.ndarray, second: np.ndarray, radius: float) -> np.ndarray:
    return -smooth_min(-first, -second, radius)


def union_ellipsoids(points: np.ndarray,
                     volumes: tuple[tuple[tuple[float, float, float],
                                          tuple[float, float, float]], ...],
                     blend: float) -> np.ndarray:
    distance = ellipsoid_sdf(points, *volumes[0])
    for center, radii in volumes[1:]:
        distance = smooth_min(distance, ellipsoid_sdf(points, center, radii), blend)
    return distance


def body_sdf(points: np.ndarray) -> np.ndarray:
    distance = union_ellipsoids(points, BODY_VOLUMES, 0.043)
    for side in (-1.0, 1.0):
        # Deep front-opening socket. Eye remains behind the opening, while the
        # body itself supplies rounded hood and cheek-side rim geometry.
        socket = ellipsoid_sdf(
            points, (side * EYE_CENTER_X, -0.590, EYE_CENTER_Z),
            (0.148, 0.128, 0.151),
        )
        distance = smooth_max(distance, -socket, 0.013)
        upper_lid = ellipsoid_sdf(
            points, (side * EYE_CENTER_X, -0.575, EYE_CENTER_Z + 0.083),
            (0.137, 0.074, 0.057),
        )
        lower_lid = ellipsoid_sdf(
            points, (side * EYE_CENTER_X, -0.568, EYE_CENTER_Z - 0.079),
            (0.126, 0.064, 0.036),
        )
        distance = smooth_min(distance, upper_lid, 0.018)
        distance = smooth_min(distance, lower_lid, 0.012)
    return distance


def eyes_sdf(points: np.ndarray) -> np.ndarray:
    left = ellipsoid_sdf(points, (-EYE_CENTER_X, EYE_CENTER_Y, EYE_CENTER_Z), EYE_RADII)
    right = ellipsoid_sdf(points, (EYE_CENTER_X, EYE_CENTER_Y, EYE_CENTER_Z), EYE_RADII)
    return np.minimum(left, right)


def loft_sdf(points: np.ndarray, sections: tuple[tuple[float, float, float, float], ...]) -> np.ndarray:
    y_positions = np.asarray([section[0] for section in sections], dtype=np.float32)
    order = np.argsort(y_positions)
    ys = y_positions[order]
    widths = np.asarray([sections[index][1] for index in order], dtype=np.float32)
    heights = np.asarray([sections[index][2] for index in order], dtype=np.float32)
    centers = np.asarray([sections[index][3] for index in order], dtype=np.float32)
    y = points[:, 1]
    width = np.interp(y, ys, widths)
    height = np.interp(y, ys, heights)
    center_z = np.interp(y, ys, centers)
    # Rounded-superellipse section gives a blunt wedge, not a circular puck.
    section_q = (
        np.power(np.abs(points[:, 0]) / np.maximum(width, 1e-4), 3.2)
        + np.power(np.abs(points[:, 2] - center_z) / np.maximum(height, 1e-4), 3.2)
    ) ** (1.0 / 3.2)
    radial = (section_q - 1.0) * np.minimum(width, height)
    cap = np.maximum(ys[0] - y, y - ys[-1])
    outside = np.sqrt(np.maximum(radial, 0.0) ** 2 + np.maximum(cap, 0.0) ** 2)
    inside = np.minimum(np.maximum(radial, cap), 0.0)
    return outside + inside - 0.003


def bill_sdf(points: np.ndarray) -> np.ndarray:
    return np.minimum(loft_sdf(points, BILL_UPPER_SECTIONS),
                      loft_sdf(points, BILL_LOWER_SECTIONS))


def wing_sdf(points: np.ndarray) -> np.ndarray:
    distance = np.full(points.shape[0], 10.0, dtype=np.float32)
    for side in (-1.0, 1.0):
        root = np.array((side * WING_ROOT_X, WING_ROOT_Y, WING_ROOT_Z), dtype=np.float32)
        tip = np.array((side * (WING_ROOT_X + WING_OUTWARD),
                        WING_ROOT_Y + 0.018, WING_ROOT_Z - WING_DROP), dtype=np.float32)
        axis = normalize((tip - root)[None, :])[0]
        broad = normalize(np.array((side * -axis[2], 0.0, side * axis[0]), dtype=np.float32)[None, :])[0]
        thick = normalize(np.cross(axis, broad)[None, :])[0]
        axes = np.stack((axis, broad, thick), axis=0)
        for sample in range(11):
            t = sample / 10.0
            center = root * (1.0 - t) + tip * t
            # Sustained paddle width and a semicircular final cap. Shoulder is
            # smaller only while buried well inside torso volume.
            width_factor = math.sin(math.pi * min(1.0, max(0.0, (t + 0.04) / 1.08))) ** 0.42
            width = max(0.090, WING_MAX_HALF_WIDTH * width_factor)
            if t > 0.82:
                width = WING_MAX_HALF_WIDTH * (0.94 - (t - 0.82) * 0.55)
            local = oriented_ellipsoid_sdf(
                points, center, axes,
                (0.096, width, WING_MAX_HALF_THICKNESS * (0.88 + 0.12 * width_factor)),
            )
            distance = smooth_min(distance, local, 0.024)
    return distance


def tail_sdf(points: np.ndarray) -> np.ndarray:
    volumes = (
        ((-0.145, 0.335, 0.445), (0.190, 0.255, 0.105)),
        ((0.0, 0.385, 0.420), (0.185, 0.275, 0.100)),
        ((0.145, 0.335, 0.445), (0.190, 0.255, 0.105)),
    )
    return union_ellipsoids(points, volumes, 0.030)


def feet_sdf(points: np.ndarray) -> np.ndarray:
    distance = np.full(points.shape[0], 10.0, dtype=np.float32)
    for side in (-1.0, 1.0):
        foot = ellipsoid_sdf(points, (side * 0.225, -0.125, 0.115), (0.180, 0.255, 0.080))
        distance = smooth_min(distance, foot, 0.026)
        for toe_offset, toe_angle in ((-0.075, -0.10), (0.0, 0.0), (0.075, 0.10)):
            center = np.array((side * 0.225 + toe_offset, -0.305, 0.095), dtype=np.float32)
            forward = normalize(np.array((toe_angle, -1.0, -0.08), dtype=np.float32)[None, :])[0]
            across = normalize(np.array((1.0, toe_angle, 0.0), dtype=np.float32)[None, :])[0]
            up = normalize(np.cross(forward, across)[None, :])[0]
            axes = np.stack((forward, across, up), axis=0)
            toe = oriented_ellipsoid_sdf(points, center, axes, (0.155, 0.054, 0.042))
            distance = smooth_min(distance, toe, 0.018)
    return distance


def scene_sdf(points: np.ndarray) -> np.ndarray:
    body = body_sdf(points)
    distance = smooth_min(body, wing_sdf(points), 0.012)
    distance = smooth_min(distance, tail_sdf(points), 0.016)
    distance = np.minimum(distance, eyes_sdf(points))
    distance = np.minimum(distance, bill_sdf(points))
    distance = np.minimum(distance, feet_sdf(points))
    return distance


def ellipse_score(points: np.ndarray, cx: float, cz: float,
                  rx: float, rz: float) -> np.ndarray:
    return ((points[:, 0] - cx) / rx) ** 2 + ((points[:, 2] - cz) / rz) ** 2


def classify_material(points: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    count = points.shape[0]
    color = np.repeat(NAVY[None, :], count, axis=0)
    feather_kind = np.zeros(count, dtype=np.int8)

    eye_distance = eyes_sdf(points)
    eye_mask = np.abs(eye_distance) < 0.012
    color[eye_mask] = SCLERA
    feather_kind[eye_mask] = -1
    for side in (-1.0, 1.0):
        x_normal = (points[:, 0] - side * EYE_CENTER_X) / EYE_RADII[0]
        z_normal = (points[:, 2] - EYE_CENTER_Z) / EYE_RADII[2]
        front = points[:, 1] < EYE_CENTER_Y - 0.078
        iris = eye_mask & front & ((x_normal / 0.55) ** 2 + (z_normal / 0.62) ** 2 < 1.0)
        pupil = eye_mask & front & ((x_normal / 0.29) ** 2 + ((z_normal + 0.01) / 0.39) ** 2 < 1.0)
        glint = eye_mask & front & (((x_normal + 0.16) / 0.105) ** 2
                                    + ((z_normal - 0.22) / 0.125) ** 2 < 1.0)
        color[iris] = IRIS
        color[pupil] = PUPIL
        color[glint] = 0.96

    bill = np.abs(bill_sdf(points)) < 0.012
    color[bill] = ORANGE
    feather_kind[bill] = -1
    # Geometry-level mouth seam remains thin and dark between mandibles.
    seam = bill & (points[:, 2] > 1.369) & (points[:, 2] < 1.380)
    color[seam] = np.array((0.18, 0.055, 0.025), dtype=np.float32)

    feet = np.abs(feet_sdf(points)) < 0.012
    color[feet] = ORANGE
    feather_kind[feet] = -1
    claws = feet & (points[:, 1] < -0.410) & (points[:, 2] < 0.115)
    color[claws] = np.array((0.10, 0.065, 0.050), dtype=np.float32)

    body = np.abs(body_sdf(points)) < 0.015
    front = points[:, 1] < -0.105
    cheek = np.minimum(
        ellipse_score(points, -0.205, 1.420, 0.272, 0.250),
        ellipse_score(points, 0.205, 1.420, 0.272, 0.250),
    )
    muzzle = ellipse_score(points, 0.0, 1.350, 0.235, 0.195)
    chin = ellipse_score(points, 0.0, 1.225, 0.305, 0.245)
    chest = ellipse_score(points, 0.0, 0.790, 0.350, 0.500)
    face_cream = body & front & ((cheek < 1.0) | (muzzle < 1.0) | (chin < 1.0))
    chest_cream = body & front & (chest < 1.0)
    cream = face_cream | chest_cream
    # Narrow dark bridge maintains hood continuity between recessed sockets.
    dark_bridge = body & (np.abs(points[:, 0]) < 0.060) & (points[:, 2] > 1.445)
    cream &= ~dark_bridge
    color[cream] = CREAM
    feather_kind[cream] = 1

    warm = body & front & (
        (ellipse_score(points, -0.362, 1.405, 0.052, 0.072) < 1.0)
        | (ellipse_score(points, 0.362, 1.405, 0.052, 0.072) < 1.0)
    )
    color[warm] = WARM
    feather_kind[warm] = -1

    # Painted identity seam only: low-saturation marks behind jaw, no cyan mesh.
    cyan = body & (points[:, 1] > -0.245) & (np.abs(np.abs(points[:, 0]) - 0.365) < 0.026)
    cyan &= (points[:, 2] > 1.440) & (points[:, 2] < 1.515)
    color[cyan] = CYAN
    feather_kind[cyan] = -1

    wing = np.abs(wing_sdf(points)) < 0.016
    wing_underside = wing & (points[:, 1] < -0.030) & (points[:, 2] < 1.035)
    color[wing_underside] = CREAM * np.array((0.90, 0.92, 0.94), dtype=np.float32)
    feather_kind[wing_underside] = 1
    return color, feather_kind


def load_material_maps(material_dir: Path) -> tuple[np.ndarray, np.ndarray]:
    albedo_path = material_dir / "hero_penguin_v1_albedo.png"
    normal_path = material_dir / "hero_penguin_v1_normal.png"
    if not albedo_path.is_file() or not normal_path.is_file():
        raise RuntimeError(
            "derive V11 review material before static sculpt preview: "
            f"{albedo_path} / {normal_path}"
        )
    albedo = np.asarray(Image.open(albedo_path).convert("RGB"), dtype=np.float32) / 255.0
    normal = np.asarray(Image.open(normal_path).convert("RGB"), dtype=np.float32) / 255.0
    return albedo, normal


def apply_feather_maps(points: np.ndarray, normals: np.ndarray, colors: np.ndarray,
                       kinds: np.ndarray, albedo: np.ndarray,
                       normal_map: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    feather = kinds >= 0
    if not np.any(feather):
        return normals, colors
    selected = points[feather]
    angle = np.arctan2(selected[:, 0], -selected[:, 1])
    u = np.mod(((angle / (2.0 * math.pi)) + 0.5) * 512.0, 512.0).astype(np.int32)
    v = np.mod((selected[:, 2] * 690.0 + selected[:, 0] * 46.0), 1024.0).astype(np.int32)
    atlas_u = u + np.where(kinds[feather] == 1, 512, 0)
    texel = albedo[v, atlas_u]
    luminance = texel @ np.array((0.2126, 0.7152, 0.0722), dtype=np.float32)
    half_mean = np.where(kinds[feather] == 1, 0.93, 0.90)
    modulation = np.clip(luminance / half_mean, 0.92, 1.08)
    colors[feather] *= modulation[:, None]

    sampled_normal = normal_map[v, atlas_u] * 2.0 - 1.0
    surface = normals[feather]
    tangent = normalize(np.stack((-selected[:, 1], selected[:, 0],
                                  np.zeros(selected.shape[0], dtype=np.float32)), axis=-1))
    vertical = np.repeat(np.array(((0.0, 0.0, 1.0),), dtype=np.float32), selected.shape[0], axis=0)
    perturbed = normalize(
        surface * np.clip(sampled_normal[:, 2:3], 0.55, 1.0)
        + tangent * sampled_normal[:, 0:1] * 0.18
        + vertical * sampled_normal[:, 1:2] * 0.13
    )
    normals[feather] = perturbed
    return normals, colors


def camera_basis(position: tuple[float, float, float],
                 target: tuple[float, float, float]) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    forward = normalize((np.asarray(target, dtype=np.float32)
                         - np.asarray(position, dtype=np.float32))[None, :])[0]
    right = normalize(np.cross(forward, np.array((0.0, 0.0, 1.0), dtype=np.float32))[None, :])[0]
    up = normalize(np.cross(right, forward)[None, :])[0]
    return forward, right, up


def render_view(name: str, camera: tuple[float, float, float],
                target: tuple[float, float, float], span_x: float,
                albedo: np.ndarray, normal_map: np.ndarray) -> Image.Image:
    forward, right, up = camera_basis(camera, target)
    xs = np.linspace(-span_x * 0.5, span_x * 0.5, RENDER_WIDTH, dtype=np.float32)
    span_y = span_x * RENDER_HEIGHT / RENDER_WIDTH
    ys = np.linspace(span_y * 0.5, -span_y * 0.5, RENDER_HEIGHT, dtype=np.float32)
    grid_x, grid_y = np.meshgrid(xs, ys)
    origins = (np.asarray(target, dtype=np.float32)[None, None, :] - forward * 3.0
               + grid_x[..., None] * right + grid_y[..., None] * up).reshape((-1, 3))
    directions = np.repeat(forward[None, :], origins.shape[0], axis=0)

    center = np.array((0.0, 0.0, 0.92), dtype=np.float32)
    radius = 1.18
    offset = origins - center
    b = np.sum(offset * directions, axis=-1)
    c = np.sum(offset * offset, axis=-1) - radius * radius
    discriminant = b * b - c
    active = discriminant >= 0.0
    distance = np.maximum(0.0, -b - np.sqrt(np.maximum(discriminant, 0.0)))
    far = -b + np.sqrt(np.maximum(discriminant, 0.0))
    hit = np.zeros(origins.shape[0], dtype=bool)

    for _step in range(150):
        indices = np.flatnonzero(active & ~hit & (distance <= far + 0.05))
        if indices.size == 0:
            break
        points = origins[indices] + directions[indices] * distance[indices, None]
        step_distance = scene_sdf(points)
        newly_hit = np.abs(step_distance) < EPSILON
        if np.any(newly_hit):
            hit[indices[newly_hit]] = True
        marching = ~newly_hit
        distance[indices[marching]] += np.clip(step_distance[marching] * 0.72, 0.0012, 0.095)

    yy = np.linspace(0.0, 1.0, RENDER_HEIGHT, dtype=np.float32)[:, None]
    background_top = np.array((0.255, 0.285, 0.315), dtype=np.float32)
    background_bottom = np.array((0.145, 0.165, 0.185), dtype=np.float32)
    background = background_top[None, None, :] * (1.0 - yy[..., None]) + background_bottom[None, None, :] * yy[..., None]
    image = np.repeat(background, RENDER_WIDTH, axis=1).reshape((-1, 3))

    hit_indices = np.flatnonzero(hit)
    points = origins[hit_indices] + directions[hit_indices] * distance[hit_indices, None]
    delta = 0.0022
    offsets = np.eye(3, dtype=np.float32) * delta
    gradient = np.stack(
        [scene_sdf(points + offsets[axis]) - scene_sdf(points - offsets[axis])
         for axis in range(3)], axis=-1,
    )
    normals = normalize(gradient)
    colors, kinds = classify_material(points)
    normals, colors = apply_feather_maps(points, normals, colors, kinds, albedo, normal_map)

    key = normalize(np.array(((-0.65, -0.75, 1.10),), dtype=np.float32))[0]
    fill = normalize(np.array(((0.55, -0.35, 0.45),), dtype=np.float32))[0]
    ndotl = np.clip(normals @ key, 0.0, 1.0)
    fill_term = np.clip(normals @ fill, 0.0, 1.0)
    view = -directions[hit_indices]
    half_vector = normalize(key[None, :] + view)
    specular = np.power(np.clip(np.sum(normals * half_vector, axis=-1), 0.0, 1.0), 34.0)
    rim = np.power(1.0 - np.clip(np.sum(normals * view, axis=-1), 0.0, 1.0), 2.2)
    light = 0.28 + ndotl * 0.64 + fill_term * 0.16
    shaded = colors * light[:, None] + specular[:, None] * 0.10 + rim[:, None] * np.array((0.045, 0.075, 0.095))
    image[hit_indices] = np.clip(shaded, 0.0, 1.0)

    rendered = Image.fromarray(
        np.rint(np.clip(image.reshape((RENDER_HEIGHT, RENDER_WIDTH, 3)), 0.0, 1.0) * 255.0).astype(np.uint8),
        mode="RGB",
    )
    draw = ImageDraw.Draw(rendered, "RGBA")
    draw.rounded_rectangle((12, 12, 119, 39), radius=9, fill=(21, 27, 34, 188))
    draw.text((23, 19), name.upper(), fill=(235, 240, 243, 255))
    return rendered


def build_contact(output_dir: Path, views: list[Image.Image]) -> Path:
    margin = 24
    header = 78
    footer = 70
    width = margin * 4 + RENDER_WIDTH * 3
    height = header + RENDER_HEIGHT + footer
    contact = Image.new("RGB", (width, height), "#252c33")
    draw = ImageDraw.Draw(contact)
    draw.text((margin, 18), "HERO PENGUIN V11 — STATIC STRUCTURE GATE", fill="#f0f3f5")
    draw.text((margin, 43), "PRE-EXPORT IMPLICIT PROOF · PRODUCTION_READY=FALSE", fill="#9eb0bc")
    for index, view in enumerate(views):
        contact.paste(view, (margin + index * (RENDER_WIDTH + margin), header))
    note_y = header + RENDER_HEIGHT + 17
    draw.text(
        (margin, note_y),
        "FUSED CRANIUM + PEAR TORSO  /  STRUCTURAL CHEEK LOBES  /  RECESSED EYES + BODY LIDS",
        fill="#c9d5dc",
    )
    draw.text(
        (margin, note_y + 23),
        "BLUNT TWO-VOLUME WEDGE BILL  /  BURIED THICK PADDLE ROOTS  /  PAINTED CYAN SEAM ONLY",
        fill="#c9d5dc",
    )
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / "hero_penguin_v11_static_front_3q_side.png"
    contact.save(path, optimize=True)
    for name, view in zip(("front", "threequarter", "side"), views, strict=True):
        view.save(output_dir / f"hero_penguin_v11_static_{name}.png", optimize=True)
    return path


def main() -> None:
    args = parse_args()
    albedo, normal_map = load_material_maps(args.material_dir)
    views = [
        render_view("front", (0.0, -4.0, 1.00), (0.0, 0.0, 0.94), 1.62, albedo, normal_map),
        render_view("three-quarter", (2.75, -3.70, 1.55), (0.0, 0.0, 0.96), 1.62, albedo, normal_map),
        render_view("true side", (4.0, -0.05, 1.10), (0.0, 0.0, 0.94), 1.62, albedo, normal_map),
    ]
    contact_path = build_contact(args.output_dir, views)
    print(f"V11_STATIC_PREVIEW={contact_path}")
    print("PRODUCTION_READY=false")


if __name__ == "__main__":
    main()
