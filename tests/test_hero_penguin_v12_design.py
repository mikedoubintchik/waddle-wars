"""Source-sculpt shape guards; these are not a visual-acceptance test.

Run with Blender's bundled Python (NumPy), without launching Blender/Godot.
"""

from pathlib import Path
import sys
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools/art"))
from hero_penguin_v12_design import (
    BILL_LOWER_SECTIONS, BILL_UPPER_SECTIONS, EYE_RADII, EYE_BURY_DEPTH, WING_SECTION_ROLL_RADIANS,
    IRIS_RADII, LIMBAL_RADII, PUPIL_RADII,
    eye_patch_faces, eye_tangent_aperture_radii, eyelid_fractions, eyelid_waterline_weight,
    paddle_cross_section, project_eye_patch, sculpt_body_field,
    base_body_field, eye_surface_frame, UPPER_FOLD_BLEND, EYE_ORBITAL_PITCH_FACTOR, EYE_ORBITAL_HEADING_FACTOR, eye_gaze_center,
    upper_lid_pigment_weight, UPPER_FOLD_APERTURE_HEIGHT,
    bill_smile_offset, bill_section_height, TORSO_RADII, WING_TIP, WING_HALF_WIDTH,
)


def front_profile(heights):
    low = np.full_like(heights, -0.7)
    high = np.zeros_like(heights)
    for _ in range(35):
        middle = (low + high) * 0.5
        points = np.column_stack((np.zeros_like(heights), middle, heights))
        outside = sculpt_body_field(points) > 0.0
        low = np.where(outside, middle, low)
        high = np.where(outside, high, middle)
    return (low + high) * 0.5


class SculptShapeTests(unittest.TestCase):
    def test_stylized_gaze_retains_temporal_pigment_without_changing_globes(self):
        left, right = eye_gaze_center(-1.0), eye_gaze_center(1.0)
        self.assertAlmostEqual(left[0], -right[0])
        self.assertAlmostEqual(left[1], right[1])
        self.assertLess(right[0], 0.0)  # Still nasal, not outward from the orbit.
        self.assertGreater(right[0] + IRIS_RADII[0], 0.020)
        self.assertLess(right[0] + IRIS_RADII[0], 0.035)

    def test_upper_bill_roof_stays_domed_with_smiling_corners(self):
        for section in BILL_UPPER_SECTIONS:
            center = bill_section_height(*section, 0.0, 1.0, "upper")
            for angle in np.linspace(0.0, np.pi, 97):
                cosine, sine = np.cos(angle), np.sin(angle)
                roof = bill_section_height(*section, cosine, sine, "upper")
                self.assertLessEqual(roof, center + 1e-12)
                self.assertAlmostEqual(roof, bill_section_height(*section, -cosine, sine, "upper"))
            corner = bill_section_height(*section, 1.0, 0.0, "upper")
            self.assertAlmostEqual(corner, section[3] + 0.0024
                                   + bill_smile_offset(section[0], section[1], 1.0))
        section = BILL_UPPER_SECTIONS[1]
        self.assertGreater(bill_section_height(*section, 0.0, 1.0, "upper")
                           - bill_section_height(*section, 0.64, np.sqrt(1 - 0.64 ** 2), "upper"), 0.014)

    def test_bill_smile_lifts_roots_not_the_front_tip(self):
        self.assertAlmostEqual(bill_smile_offset(-0.351, 0.100, 1.0), 0.046)
        self.assertEqual(bill_smile_offset(-0.510, 0.100, 1.0), 0.0)
        self.assertEqual(bill_smile_offset(-0.351, 0.100, 0.0), 0.0)
        values = [bill_smile_offset(y, 0.1, 1.0) for y in np.linspace(-0.50, -0.35, 81)]
        self.assertTrue(all(a <= b for a, b in zip(values, values[1:])))
        for cosine in np.linspace(-1.0, 1.0, 65):
            self.assertAlmostEqual(bill_smile_offset(-0.41, 0.11, cosine),
                                   bill_smile_offset(-0.41, 0.11, -cosine))

    def test_pear_silhouette_and_flipper_spread_keep_authored_proportions(self):
        x = np.linspace(0.0, 0.60, 301)
        y = np.linspace(-0.50, 0.50, 201)
        widths = []
        for height in (0.70, 1.44):
            points = np.stack(np.meshgrid(x, y, [height], indexing="ij"), axis=-1)
            occupied = np.any(base_body_field(points) <= 0.0, axis=(1, 2))
            widths.append(x[np.flatnonzero(occupied)[-1]] * 2.0)
        self.assertGreater(widths[1] / widths[0], 0.73)
        self.assertLess(widths[1] / widths[0], 0.80)
        self.assertGreater(WING_TIP[0] / TORSO_RADII[0], 1.30)
        self.assertLess(WING_TIP[0] / TORSO_RADII[0], 1.40)
        self.assertGreater(WING_HALF_WIDTH, 0.12)

    def test_lid_pigment_is_upper_only_bilateral_and_bounded(self):
        origin, across, normal, up = map(np.asarray, eye_surface_frame(1.0))
        point = origin + normal * 0.015 + up * (UPPER_FOLD_APERTURE_HEIGHT + 0.003)
        self.assertGreater(upper_lid_pigment_weight(point), 0.9)
        self.assertAlmostEqual(upper_lid_pigment_weight(point),
                               upper_lid_pigment_weight(point * (-1.0, 1.0, 1.0)), places=10)
        for x in np.linspace(-0.07, 0.07, 31):
            for z in np.linspace(-0.14, 0.0, 17):
                self.assertEqual(upper_lid_pigment_weight(origin + across * x + normal * 0.01 + up * z), 0.0)
        self.assertEqual(upper_lid_pigment_weight(origin + normal * 0.015 + up * 0.12), 0.0)

    def test_eye_frames_follow_base_skull_without_moving_with_fold(self):
        mirror = np.asarray((-1.0, 1.0, 1.0))
        right = np.asarray(eye_surface_frame(1.0))
        left = np.asarray(eye_surface_frame(-1.0))
        np.testing.assert_allclose(right[1:] @ right[1:].T, np.eye(3), atol=1e-12)
        np.testing.assert_allclose(left[[0, 2, 3]], right[[0, 2, 3]] * mirror, atol=1e-10)
        np.testing.assert_allclose(left[1], -right[1] * mirror, atol=1e-10)
        self.assertLess(abs(float(base_body_field(right[0]))), 1e-9)
        self.assertGreater(right[2, 2], 0.25)
        self.assertLess(right[2, 2], 0.35)
        for epsilon in (1e-4, 1e-5, 1e-6):
            gradient = np.asarray([base_body_field(right[0] + axis * epsilon)
                                   - base_body_field(right[0] - axis * epsilon)
                                   for axis in np.eye(3)])
            gradient[0] *= EYE_ORBITAL_HEADING_FACTOR
            gradient[2] *= EYE_ORBITAL_PITCH_FACTOR
            gradient /= np.linalg.norm(gradient)
            np.testing.assert_allclose(right[2], gradient, atol=2e-6)
        with self.assertRaises(ValueError):
            eye_surface_frame(0)

    def test_whole_globe_perimeter_has_real_skull_bracket(self):
        for side in (-1.0, 1.0):
            origin, across, normal, up = map(np.asarray, eye_surface_frame(side))
            center = origin + normal * (EYE_RADII[1] - EYE_BURY_DEPTH)
            self.assertGreater(float(base_body_field(center)), 0.01)
            for angle in np.linspace(0.0, np.pi * 2.0, 81):
                edge = (origin + across * EYE_RADII[0] * np.cos(angle)
                        + up * EYE_RADII[2] * np.sin(angle) - normal * EYE_BURY_DEPTH)
                # R's authored pitch still gives every perimeter endpoint a
                # genuine interior bracket (at least 20 mm of field margin).
                self.assertLess(float(base_body_field(edge)), -0.02)

    def test_integrated_fold_only_covers_upper_eye_and_preserves_lower_join(self):
        origin, across, normal, up = map(np.asarray, eye_surface_frame(1.0))
        angles = np.linspace(0.0, np.pi * 2.0, 161)
        aperture = {}
        for evaluator in (base_body_field, sculpt_body_field):
            low, high = np.zeros(len(angles)), np.ones(len(angles))
            for _ in range(35):
                radius = (low + high) * 0.5
                points = (origin + (EYE_RADII[0] * np.cos(angles) * radius)[:, None] * across
                          + (EYE_RADII[2] * np.sin(angles) * radius)[:, None] * up
                          + (-EYE_BURY_DEPTH + EYE_RADII[1] * np.sqrt(1.0 - radius * radius))[:, None] * normal)
                outside = evaluator(points) > 0.0
                low = np.where(outside, radius, low)
                high = np.where(outside, high, radius)
            aperture[evaluator.__name__] = (low + high) * 0.5
        base, final = aperture.values()
        # U's narrower head/outward orbit closes the lower temporal corner
        # to radius .330; that is the unchanged base-skull join, not the lid.
        self.assertTrue(np.all(final > 0.30))
        self.assertGreater(base[40] - final[40], 0.15)
        np.testing.assert_allclose(base[80:], final[80:], atol=1e-10)
        self.assertLessEqual(UPPER_FOLD_BLEND * 0.25, 0.003)

    def test_upper_lid_never_leaves_an_exposed_white_island_above_it(self):
        origin, across, normal, up = map(np.asarray, eye_surface_frame(1.0))
        radius = np.linspace(0.0, 1.0, 257)
        for angle in np.linspace(0.0, np.pi, 81):
            points = (origin + (EYE_RADII[0] * np.cos(angle) * radius)[:, None] * across
                      + (EYE_RADII[2] * np.sin(angle) * radius)[:, None] * up
                      + (-EYE_BURY_DEPTH + EYE_RADII[1] * np.sqrt(1.0 - radius * radius))[:, None] * normal)
            covered = sculpt_body_field(points) <= 0.0
            self.assertFalse(covered[0])
            self.assertTrue(covered[-1])
            self.assertTrue(np.all(covered[np.argmax(covered):]), msg=f"disconnected aperture at {angle}")

    def test_attentive_gaze_central_pigment_remains_clear_of_skull(self):
        for side in (-1.0, 1.0):
            origin, across, normal, up = map(np.asarray, eye_surface_frame(side))
            gaze = eye_gaze_center(side)
            for radii, dz, offset in ((IRIS_RADII, 0.0, 0.0016), (PUPIL_RADII, -0.004, 0.0022)):
                cx, cz = gaze[0], gaze[1] + dz
                depth = EYE_RADII[1] * np.sqrt(1.0 - (cx / EYE_RADII[0]) ** 2 - (cz / EYE_RADII[2]) ** 2)
                center = np.asarray((cx, depth, cz))
                patch_normal = center / np.asarray(EYE_RADII) ** 2
                patch_normal /= np.linalg.norm(patch_normal)
                patch_across = np.cross(patch_normal, (0.0, 0.0, 1.0))
                patch_across /= np.linalg.norm(patch_across)
                patch_up = np.cross(patch_across, patch_normal)
                for radius in (0.0, 1.0 / 12, 2.0 / 12, 3.0 / 12):
                    for angle in np.linspace(0.0, np.pi * 2.0, 65):
                        point = center + patch_across * np.cos(angle) * radii[0] * radius + patch_up * np.sin(angle) * radii[1] * radius
                        x, d, z = project_eye_patch(point, offset)
                        world = origin + across * x + normal * (d - EYE_BURY_DEPTH) + up * z
                        self.assertGreater(float(sculpt_body_field(world)), 0.001)

    def test_eye_pigment_is_nested_and_keeps_visible_iris(self):
        for axis in (0, 1):
            self.assertLess(PUPIL_RADII[axis], IRIS_RADII[axis])
            self.assertLess(IRIS_RADII[axis], LIMBAL_RADII[axis])
            self.assertGreater(IRIS_RADII[axis] - PUPIL_RADII[axis], 0.015)
            self.assertTrue(0.60 <= PUPIL_RADII[axis] / IRIS_RADII[axis] <= 0.65)
        # The hidden globe grew to compensate deeper seating. Compare pigment
        # with the exposed tangent-plane lens, not its invisible full radius.
        aperture = eye_tangent_aperture_radii()
        self.assertGreater(IRIS_RADII[0] / aperture[0], 0.60)
        for axis in (0, 1):
            self.assertLess(IRIS_RADII[axis] / aperture[axis], 0.95)

    def test_deeper_eye_retains_tangent_aperture_without_protruding_dome(self):
        old_aperture = eye_tangent_aperture_radii((0.099, 0.089, 0.134), 0.061)
        aperture = eye_tangent_aperture_radii()
        for old, new in zip(old_aperture, aperture):
            self.assertGreater(new / old, 0.90)
            self.assertLessEqual(new, old)
        self.assertGreater(EYE_RADII[1] - EYE_BURY_DEPTH, 0.0)
        self.assertLess(EYE_RADII[1] - EYE_BURY_DEPTH, 0.023)
        for depth in (-0.001, 0.0, EYE_RADII[1]):
            with self.assertRaises(ValueError):
                eye_tangent_aperture_radii(bury_depth=depth)
        with self.assertRaises(ValueError):
            eye_tangent_aperture_radii((0.0, 0.089, 0.146))

    def test_upper_waterline_blends_without_an_outer_ring(self):
        for angle in np.linspace(0.0, 2.0 * np.pi, 161):
            values = [eyelid_waterline_weight(angle, v) for v in np.linspace(0.0, 1.0, 31)]
            self.assertEqual(values[0], 1.0)
            self.assertEqual(values[-1], 0.0)
            self.assertTrue(all(0.0 <= value <= 1.0 for value in values))
            self.assertTrue(all(a >= b for a, b in zip(values, values[1:])))
            self.assertAlmostEqual(eyelid_waterline_weight(angle, 0.4),
                                   eyelid_waterline_weight(np.pi - angle, 0.4), places=12)
        self.assertGreater(eyelid_waterline_weight(np.pi * 0.5, 0.4), 0.5)
        self.assertEqual(eyelid_waterline_weight(np.pi * 1.5, 0.4), 0.0)
        with self.assertRaises(ValueError):
            eyelid_waterline_weight(0.0, 1.1)

    def test_paddle_roll_is_side_facing_orthonormal_and_bilateral(self):
        mirror = np.asarray((-1.0, 1.0, 1.0))
        # Sample changing shoulder-to-tip direction, not just a vertical axis.
        for x in np.linspace(0.06, 0.27, 11):
            axis = np.asarray((x, -0.03, -0.40))
            axis /= np.linalg.norm(axis)
            broad, thick = map(np.asarray, paddle_cross_section(axis, 1.0))
            left_broad, left_thick = map(np.asarray, paddle_cross_section(axis * mirror, -1.0))
            base = np.asarray((-axis[2], 0.0, axis[0]))
            base /= np.linalg.norm(base)
            self.assertAlmostEqual(float(np.dot(base, broad)), np.cos(WING_SECTION_ROLL_RADIANS), places=12)
            self.assertGreater(abs(broad[1]), 0.70)
            frame = np.asarray((broad, thick, axis))
            np.testing.assert_allclose(frame @ frame.T, np.eye(3), atol=1e-12)
            np.testing.assert_allclose(np.cross(broad, thick), axis, atol=1e-12)
            np.testing.assert_allclose(left_broad, broad * mirror, atol=1e-12)
            np.testing.assert_allclose(left_thick, -thick * mirror, atol=1e-12)
        with self.assertRaises(ValueError):
            paddle_cross_section((0.0, 0.0, 0.0), 1.0)

    def test_lower_bill_is_tucked_ordered_and_shallower(self):
        for sections in (BILL_UPPER_SECTIONS, BILL_LOWER_SECTIONS):
            self.assertTrue(all(b[0] < a[0] for a, b in zip(sections, sections[1:])))
            self.assertTrue(all(width > 0.0 and height > 0.0 for _, width, height, _ in sections))
        retreat = BILL_LOWER_SECTIONS[-1][0] - BILL_UPPER_SECTIONS[-1][0]
        self.assertGreaterEqual(retreat, 0.02)
        self.assertLessEqual(retreat, 0.03)
        self.assertLessEqual(max(row[2] for row in BILL_LOWER_SECTIONS), 0.035)
        self.assertLess(max(row[2] for row in BILL_LOWER_SECTIONS),
                        max(row[2] for row in BILL_UPPER_SECTIONS) * 0.40)
        upper_y = np.asarray([row[0] for row in reversed(BILL_UPPER_SECTIONS)])
        upper_width = np.asarray([row[1] for row in reversed(BILL_UPPER_SECTIONS)])
        for y, width, _, _ in BILL_LOWER_SECTIONS:
            self.assertLess(width, float(np.interp(y, upper_y, upper_width)))

    def test_eyelid_arch_and_corners_are_bilateral_not_circular(self):
        for angle in np.linspace(0.0, np.pi * 2.0, 161):
            right = eyelid_fractions(angle, 1.0)
            left = eyelid_fractions(np.pi - angle, -1.0)
            np.testing.assert_allclose(right, left, atol=1e-12)
            self.assertTrue(0.70 < right[0] < 1.0 < right[1] < 1.09)
        outer_corner = eyelid_fractions(0.0, 1.0)[0]
        inner_corner = eyelid_fractions(np.pi, 1.0)[0]
        bottom = eyelid_fractions(np.pi * 1.5, 1.0)[0]
        top = eyelid_fractions(np.pi * 0.5, 1.0)[0]
        self.assertLess(outer_corner, inner_corner)
        self.assertLess(inner_corner, bottom - 0.08)
        self.assertLess(top, bottom - 0.18)

    def test_eye_annulus_matches_center_fan_winding(self):
        segments, rings = 64, 12
        points = [np.zeros(2)]
        for ring in range(1, rings + 1):
            for segment in range(segments):
                angle = np.pi * 2.0 * segment / segments
                points.append(np.asarray((np.cos(angle), np.sin(angle))) * ring / rings)
        triangles = 0
        for face in eye_patch_faces(segments, rings):
            a = points[face[0]]
            for index in range(1, len(face) - 1):
                b, c = points[face[index]] - a, points[face[index + 1]] - a
                self.assertGreater(float(b[0] * c[1] - b[1] * c[0]), 0.0)
                triangles += 1
        self.assertEqual(triangles, 1472)

    def test_turned_iris_stays_on_complete_globe(self):
        for x in np.linspace(-0.15, 0.15, 21):
            for z in np.linspace(-0.15, 0.15, 21):
                point = np.asarray((x, 0.04, z))
                surface = np.asarray(project_eye_patch(point))
                self.assertAlmostEqual(float(np.sum((surface / EYE_RADII) ** 2)), 1.0, places=12)
                raised = np.asarray(project_eye_patch(point, 0.0016))
                self.assertAlmostEqual(float(np.linalg.norm(raised - surface)), 0.0016, places=12)
        with self.assertRaises(ValueError):
            project_eye_patch((0.0, 0.0, 0.0))

    def test_lower_belly_has_no_secondary_curvature_band(self):
        heights = np.linspace(0.14, 0.65, 120)
        profile = front_profile(heights)
        # The front advances continuously toward the widest belly. A stacked
        # lower ellipsoid had a conspicuous inward ledge at the volume join.
        self.assertTrue(np.all(np.diff(profile) < 0.0))
        slopes = np.diff(profile) / np.diff(heights)
        self.assertTrue(np.all(np.diff(slopes) > -0.0001))

    def test_surface_is_bilateral_and_finite(self):
        rng = np.random.default_rng(12)
        points = rng.uniform((-0.7, -0.7, -0.05), (0.7, 0.7, 1.95), (4096, 3))
        field = sculpt_body_field(points)
        mirror = points * np.asarray((-1.0, 1.0, 1.0))
        self.assertTrue(np.all(np.isfinite(field)))
        np.testing.assert_allclose(field, sculpt_body_field(mirror), atol=1e-10)

    def test_torso_encloses_center_and_retains_ground_clearance(self):
        values = sculpt_body_field(np.asarray(((0.0, 0.022, 0.69),
                                               (0.0, 0.022, 0.02),
                                               (0.0, 0.022, 1.92),
                                               (0.7, 0.022, 0.69))))
        self.assertLess(values[0], 0.0)
        self.assertTrue(np.all(values[1:] > 0.0))


if __name__ == "__main__":
    unittest.main()
