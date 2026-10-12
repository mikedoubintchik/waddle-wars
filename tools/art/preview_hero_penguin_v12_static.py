#!/usr/bin/env python3
"""Legacy V12 blockout preview without Blender or Godot.

The torso uses the shared field, but these simplified eyes/wings are not the
current sculpt. Use render_hero_penguin_v12_source_proof.py for art review.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import preview_hero_penguin_v11_static as render
from hero_penguin_v12_design import (
    BILL_LOWER_SECTIONS,
    BILL_UPPER_SECTIONS,
    sculpt_body_field,
    EYE_CENTER_X,
    EYE_CENTER_Y,
    EYE_CENTER_Z,
    EYE_RADII,
    FOOT_CENTER_X,
    FOOT_CENTER_Y,
    FOOT_CENTER_Z,
    FOOT_RADII,
    SOCKET_CENTER_Y,
    SOCKET_RADII,
    TAIL_VOLUMES,
    UPPER_LID_CENTER_Z,
    UPPER_LID_RADII,
    WING_HALF_THICKNESS,
    WING_HALF_WIDTH,
    WING_ROOT,
    WING_TIP,
)


OUTPUT = Path("/tmp/waddle-hero-penguin-v12-static/sculpt")
MATERIAL = Path("/tmp/waddle-hero-penguin-v11-static/material")

# Preview values stay bright enough for structural/material judgment on neutral
# gray. Runtime semantic palette remains untouched until the static gate passes.
render.NAVY = np.array((0.072, 0.128, 0.205), dtype=np.float32)
render.CREAM = np.array((0.835, 0.765, 0.640), dtype=np.float32)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=OUTPUT)
    parser.add_argument("--material-dir", type=Path, default=MATERIAL)
    return parser.parse_args()


def body_sdf(points: np.ndarray) -> np.ndarray:
    body = sculpt_body_field(points)
    for side in (-1.0, 1.0):
        socket = render.ellipsoid_sdf(
            points, (side * EYE_CENTER_X, SOCKET_CENTER_Y, EYE_CENTER_Z - 0.010), SOCKET_RADII,
        )
        body = render.smooth_max(body, -socket, 0.010)
        # Socket is intentionally smaller and slightly lower than eyeball. The
        # untouched cranium therefore becomes the integrated dark upper lid;
        # no separate brow/lid slab is added to the field.
    return body


def eyes_sdf(points: np.ndarray) -> np.ndarray:
    return np.minimum(
        render.ellipsoid_sdf(points, (-EYE_CENTER_X, EYE_CENTER_Y, EYE_CENTER_Z), EYE_RADII),
        render.ellipsoid_sdf(points, (EYE_CENTER_X, EYE_CENTER_Y, EYE_CENTER_Z), EYE_RADII),
    )


def bill_sdf(points: np.ndarray) -> np.ndarray:
    return np.minimum(render.loft_sdf(points, BILL_UPPER_SECTIONS),
                      render.loft_sdf(points, BILL_LOWER_SECTIONS))


def wing_sdf(points: np.ndarray) -> np.ndarray:
    distance = np.full(points.shape[0], 10.0, dtype=np.float32)
    for side in (-1.0, 1.0):
        root = np.asarray((side * WING_ROOT[0], WING_ROOT[1], WING_ROOT[2]), dtype=np.float32)
        tip = np.asarray((side * WING_TIP[0], WING_TIP[1], WING_TIP[2]), dtype=np.float32)
        axis = render.normalize((tip - root)[None, :])[0]
        broad = render.normalize(np.asarray(((side * -axis[2], 0.0, side * axis[0]),),
                                            dtype=np.float32))[0]
        thick = render.normalize(np.cross(axis, broad)[None, :])[0]
        axes = np.stack((axis, broad, thick), axis=0)
        for sample in range(19):
            t = sample / 18.0
            center = root * (1.0 - t) + tip * t
            if t < 0.20:
                width = 0.075 + (WING_HALF_WIDTH - 0.075) * (t / 0.20)
            elif t < 0.78:
                width = WING_HALF_WIDTH
            else:
                tail = (t - 0.78) / 0.22
                width = WING_HALF_WIDTH * (1.0 - 0.43 * tail * tail)
            piece = render.oriented_ellipsoid_sdf(
                points, center, axes,
                (0.057, width, WING_HALF_THICKNESS * (0.90 + 0.10 * min(1.0, t / 0.2))),
            )
            distance = render.smooth_min(distance, piece, 0.026)
    return distance


def tail_sdf(points: np.ndarray) -> np.ndarray:
    return render.union_ellipsoids(points, TAIL_VOLUMES, 0.025)


def feet_sdf(points: np.ndarray) -> np.ndarray:
    distance = np.full(points.shape[0], 10.0, dtype=np.float32)
    for side in (-1.0, 1.0):
        foot = render.ellipsoid_sdf(
            points, (side * FOOT_CENTER_X, FOOT_CENTER_Y, FOOT_CENTER_Z), FOOT_RADII,
        )
        distance = render.smooth_min(distance, foot, 0.020)
        for offset in (-0.060, 0.0, 0.060):
            toe = render.ellipsoid_sdf(
                points, (side * FOOT_CENTER_X + offset, FOOT_CENTER_Y - 0.150, 0.104),
                (0.050, 0.112, 0.046),
            )
            distance = render.smooth_min(distance, toe, 0.006)
    return distance


def scene_sdf(points: np.ndarray) -> np.ndarray:
    distance = body_sdf(points)
    distance = render.smooth_min(distance, wing_sdf(points), 0.010)
    distance = render.smooth_min(distance, tail_sdf(points), 0.012)
    distance = np.minimum(distance, eyes_sdf(points))
    distance = np.minimum(distance, bill_sdf(points))
    distance = np.minimum(distance, feet_sdf(points))
    return distance


def ellipsoid_score(points: np.ndarray, center: tuple[float, float, float],
                    radii: tuple[float, float, float]) -> np.ndarray:
    delta = (points - np.asarray(center, dtype=np.float32)) / np.asarray(radii, dtype=np.float32)
    return np.sum(delta * delta, axis=-1)


def classify_material(points: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    count = points.shape[0]
    colors = np.repeat(render.NAVY[None, :], count, axis=0)
    kinds = np.zeros(count, dtype=np.int8)

    eye_surface = np.abs(eyes_sdf(points)) < 0.012
    colors[eye_surface] = np.array((0.855, 0.825, 0.725), dtype=np.float32)
    kinds[eye_surface] = -1
    for side in (-1.0, 1.0):
        nx = (points[:, 0] - side * EYE_CENTER_X) / EYE_RADII[0]
        nz = (points[:, 2] - EYE_CENTER_Z) / EYE_RADII[2]
        front = points[:, 1] < EYE_CENTER_Y - EYE_RADII[1] * 0.74
        iris = eye_surface & front & ((nx / 0.63) ** 2 + (nz / 0.69) ** 2 < 1.0)
        pupil = eye_surface & front & ((nx / 0.35) ** 2 + ((nz + 0.01) / 0.46) ** 2 < 1.0)
        glint = eye_surface & front & (((nx + 0.15) / 0.095) ** 2
                                      + ((nz - 0.20) / 0.115) ** 2 < 1.0)
        colors[iris] = render.IRIS
        colors[pupil] = render.PUPIL
        colors[glint] = 0.97

    bill = np.abs(bill_sdf(points)) < 0.011
    colors[bill] = render.ORANGE
    kinds[bill] = -1
    mouth = bill & (points[:, 2] > 1.374) & (points[:, 2] < 1.383)
    colors[mouth] = np.array((0.16, 0.040, 0.018), dtype=np.float32)

    feet = np.abs(feet_sdf(points)) < 0.011
    colors[feet] = render.ORANGE
    kinds[feet] = -1
    claws = feet & (points[:, 1] < FOOT_CENTER_Y - 0.245) & (points[:, 2] < 0.103)
    colors[claws] = np.array((0.090, 0.055, 0.042), dtype=np.float32)

    body = np.abs(body_sdf(points)) < 0.014
    cheek_mask = np.minimum(
        ellipsoid_score(points, (-0.165, -0.260, 1.420), (0.235, 0.205, 0.190)),
        ellipsoid_score(points, (0.165, -0.260, 1.420), (0.235, 0.205, 0.190)),
    )
    chin_mask = ellipsoid_score(points, (0.0, -0.225, 1.265), (0.265, 0.220, 0.205))
    chest_mask = ellipsoid_score(points, (0.0, -0.210, 0.825), (0.405, 0.270, 0.555))
    cream = body & ((cheek_mask < 1.0) | (chin_mask < 1.0) | (chest_mask < 1.0))
    upper_hood = np.minimum(
        ellipsoid_score(points, (-EYE_CENTER_X, -0.285, 1.625), (0.138, 0.150, 0.082)),
        ellipsoid_score(points, (EYE_CENTER_X, -0.285, 1.625), (0.138, 0.150, 0.082)),
    )
    cream &= upper_hood >= 1.0
    dark_bridge = body & (np.abs(points[:, 0]) < 0.047) & (points[:, 2] > 1.445)
    cream &= ~dark_bridge
    colors[cream] = render.CREAM
    kinds[cream] = 1

    warm = body & (
        (ellipsoid_score(points, (-0.325, -0.285, 1.420), (0.043, 0.038, 0.070)) < 1.0)
        | (ellipsoid_score(points, (0.325, -0.285, 1.420), (0.043, 0.038, 0.070)) < 1.0)
    )
    colors[warm] = render.WARM
    kinds[warm] = -1

    cyan = body & (
        (ellipsoid_score(points, (-0.350, 0.000, 1.425), (0.027, 0.075, 0.026)) < 1.0)
        | (ellipsoid_score(points, (0.350, 0.000, 1.425), (0.027, 0.075, 0.026)) < 1.0)
    )
    colors[cyan] = render.CYAN
    kinds[cyan] = -1

    wing = np.abs(wing_sdf(points)) < 0.014
    underside = wing & (points[:, 1] < -0.030) & (np.abs(points[:, 0]) < 0.545)
    underside &= points[:, 2] < 1.035
    colors[underside] = render.CREAM * np.array((0.92, 0.94, 0.96), dtype=np.float32)
    kinds[underside] = 1
    return colors, kinds


def build_contact(output_dir: Path, views: list[Image.Image]) -> Path:
    margin, header, footer = 24, 78, 70
    width = margin * 4 + render.RENDER_WIDTH * 3
    height = header + render.RENDER_HEIGHT + footer
    contact = Image.new("RGB", (width, height), "#252c33")
    draw = ImageDraw.Draw(contact)
    draw.text((margin, 18), "HERO PENGUIN V12 — LEGACY BLOCKOUT (NOT ART APPROVAL)", fill="#f0f3f5")
    draw.text((margin, 43), "PRE-BLENDER IMPLICIT FIELD · PRODUCTION_READY=FALSE", fill="#9eb0bc")
    for index, view in enumerate(views):
        contact.paste(view, (margin + index * (render.RENDER_WIDTH + margin), header))
    note_y = header + render.RENDER_HEIGHT + 17
    draw.text((margin, note_y),
              "DISTINCT ROUND CRANIUM + PEAR TORSO  /  3.8 CM CHEEK RELIEF  /  PARTIAL RECESSED EYES",
              fill="#c9d5dc")
    draw.text((margin, note_y + 23),
              "DARK UPPER LID ONLY  /  COMPACT TWO-VOLUME WEDGE  /  BURIED ROUNDED PADDLES",
              fill="#c9d5dc")
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / "hero_penguin_v12_static_front_3q_side.png"
    contact.save(path, optimize=True)
    for name, view in zip(("front", "threequarter", "side"), views, strict=True):
        view.save(output_dir / f"hero_penguin_v12_static_{name}.png", optimize=True)
    return path


def main() -> None:
    args = parse_args()
    render.body_sdf = body_sdf
    render.eyes_sdf = eyes_sdf
    render.bill_sdf = bill_sdf
    render.wing_sdf = wing_sdf
    render.tail_sdf = tail_sdf
    render.feet_sdf = feet_sdf
    render.scene_sdf = scene_sdf
    render.classify_material = classify_material
    albedo, normal_map = render.load_material_maps(args.material_dir)
    final_width, final_height = render.RENDER_WIDTH, render.RENDER_HEIGHT
    render.RENDER_WIDTH, render.RENDER_HEIGHT = 456, 600
    high_resolution_views = [
        render.render_view("front", (0.0, -4.0, 1.0), (0.0, 0.0, 0.94), 1.58,
                           albedo, normal_map),
        render.render_view("three-quarter", (2.75, -3.70, 1.48), (0.0, 0.0, 0.96), 1.58,
                           albedo, normal_map),
        render.render_view("true side", (4.0, -0.05, 1.08), (0.0, 0.0, 0.94), 1.58,
                           albedo, normal_map),
    ]
    views = [view.resize((final_width, final_height), Image.Resampling.LANCZOS)
             for view in high_resolution_views]
    render.RENDER_WIDTH, render.RENDER_HEIGHT = final_width, final_height
    path = build_contact(args.output_dir, views)
    print(f"V12_STATIC_PREVIEW={path}")
    print("PRODUCTION_READY=false")


if __name__ == "__main__":
    main()
