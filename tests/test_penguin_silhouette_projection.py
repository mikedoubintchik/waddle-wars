"""UV-seam-safe geometry labels; pure host tests, no engine or captures."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('silhouette_projection', ROOT / 'tools/art/penguin_silhouette_projection.py')
projection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(projection)


def fixture():
    vertices, triangles, labels, ranges = [], [], [], {}
    # Different closed bipyramids exercise counts, X-side pairing, and reordering.
    shapes = [('continuous_body_head', 5, [0, 0, 0]),
              ('flipper_L', 4, [-4, 0, 0]), ('flipper_R', 4, [4, 0, 0]),
              ('foot_L', 6, [-2, -3, 0]), ('foot_R', 6, [2, -3, 0]),
              ('short_tail_fan', 3, [0, 4, 0])]
    for name, size, origin in shapes:
        start = len(vertices)
        points = [[0, 0, .5], [0, 0, -.5]]
        points += [[.5*np.cos(i*2*np.pi/size), .5*np.sin(i*2*np.pi/size), 0] for i in range(size)]
        vertices.extend(np.array(points) + origin)
        for i in range(size):
            a, b = start + 2 + i, start + 2 + (i+1) % size
            triangles.extend([[start, a, b], [start+1, b, a]])
            labels.extend([name, name])
        ranges[name] = [start, len(vertices)]
    return np.array(vertices), np.array(triangles), np.array(labels), {
        'material_contract': 'rear-surface-pbr-v1', 'parts_vertex_ranges': ranges}


def split_and_reorder(vertices, triangles, labels):
    # Every face gets independent vertices, as an extreme UV-seam split.
    split = vertices[triangles].reshape(-1, 3)
    indices = np.arange(len(split)).reshape(-1, 3)
    rng = np.random.default_rng(173)
    order = rng.permutation(len(split))
    inverse = np.argsort(order)
    faces = rng.permutation(len(indices))
    return split[order], inverse[indices[faces]], labels[faces]


class SurfacePartTests(unittest.TestCase):
    def test_localized_surface_preserves_exact_baseline_semantics(self):
        package = ROOT / 'art_src/characters/penguin_rear_surface_v1'
        vertices, triangles, _ = projection.load_glb(package / 'candidate.glb')
        metadata = json.loads((package / 'metadata.json').read_text())
        original, _ = projection.identify_parts(vertices, triangles, metadata)
        metadata.update(gate='rear-surface-v2', geometry_contract='tail-flippers-only-v1')
        labels, reports = projection.identify_parts(vertices, triangles, metadata)
        np.testing.assert_array_equal(labels, original)
        self.assertEqual(len(reports), 6)

    def test_localized_metadata_cannot_relabel_parts_or_omit_contract(self):
        vertices, triangles, _, metadata = fixture()
        metadata['gate'] = 'rear-surface-v2'
        for contract in [None, 'tail-flippers-only-v1']:
            metadata['geometry_contract'] = contract
            with self.subTest(contract=contract), self.assertRaisesRegex(ValueError, 'fixed baseline component contract'):
                projection.identify_parts(vertices, triangles, metadata)

    def test_plain_path_and_unsplit_labels_remain_unchanged(self):
        vertices, triangles, expected, metadata = fixture()
        metadata['material_contract'] = 'plain-literal-COLOR_0'
        labels, reports = projection.identify_parts(vertices, triangles, metadata)
        np.testing.assert_array_equal(labels, expected)
        self.assertTrue(all(r['matched_by'] == 'connectivity, vertex count and X side' for r in reports))
        self.assertTrue(all('unique_positions' not in r for r in reports))
        split, faces, _ = split_and_reorder(vertices, triangles, expected)
        with self.assertRaisesRegex(ValueError, 'Ambiguous component'):
            projection.identify_parts(split, faces, metadata)

    def test_split_reordered_uv_mesh_has_identical_semantic_face_labels(self):
        vertices, triangles, expected, metadata = fixture()
        split, faces, expected = split_and_reorder(vertices, triangles, expected)
        original_vertices, original_faces = split.copy(), faces.copy()
        labels, reports = projection.identify_parts(split, faces, metadata)
        np.testing.assert_array_equal(labels, expected)
        np.testing.assert_array_equal(split, original_vertices)
        np.testing.assert_array_equal(faces, original_faces)
        self.assertEqual(len(reports), 6)
        for report in reports:
            start, end = metadata['parts_vertex_ranges'][report['name']]
            self.assertEqual(report['unique_positions'], end-start)
            self.assertGreater(report['vertices'], report['unique_positions'])
            self.assertIn('exact POSITION welding', report['matched_by'])

    def test_missing_face_and_inconsistent_winding_fail_closed_check(self):
        vertices, triangles, _, metadata = fixture()
        for faces in [triangles[1:], np.vstack([triangles[0, ::-1], triangles[1:]])]:
            with self.subTest(faces=faces.shape), self.assertRaisesRegex(ValueError, 'closed'):
                projection.identify_parts(vertices, faces, metadata)

    def test_duplicate_and_weld_degenerate_faces_fail(self):
        vertices, triangles, _, metadata = fixture()
        with self.assertRaisesRegex(ValueError, 'Duplicate surface triangle'):
            projection.identify_parts(vertices, np.vstack([triangles, triangles[0]]), metadata)
        bad = triangles.copy(); bad[0, 1] = bad[0, 0]
        with self.assertRaisesRegex(ValueError, 'Degenerate triangle'):
            projection.identify_parts(vertices, bad, metadata)

    def test_nearby_positions_are_not_approximately_welded(self):
        vertices, triangles, labels, metadata = fixture()
        vertices, triangles, _ = split_and_reorder(vertices, triangles, labels)
        vertices[0, 0] += 1e-8
        with self.assertRaisesRegex(ValueError, 'closed'):
            projection.identify_parts(vertices, triangles, metadata)

    def test_unique_count_and_side_ambiguity_fail(self):
        vertices, triangles, _, metadata = fixture()
        invalid = copy.deepcopy(metadata)
        invalid['parts_vertex_ranges']['short_tail_fan'] = [100, 107]
        with self.assertRaisesRegex(ValueError, 'Ambiguous component'):
            projection.identify_parts(vertices, triangles, invalid)
        start, end = metadata['parts_vertex_ranges']['foot_R']
        vertices[start:end, 0] -= 8
        with self.assertRaisesRegex(ValueError, 'Duplicate component'):
            projection.identify_parts(vertices, triangles, metadata)

    def test_cross_component_coincident_vertex_is_not_silently_accepted(self):
        vertices, triangles, _, metadata = fixture()
        start, _ = metadata['parts_vertex_ranges']['short_tail_fan']
        vertices[start] = vertices[0]
        with self.assertRaisesRegex(ValueError, 'Ambiguous component'):
            projection.identify_parts(vertices, triangles, metadata)

    def test_missing_semantic_component_and_unreferenced_vertex_fail(self):
        vertices, triangles, _, metadata = fixture()
        invalid = copy.deepcopy(metadata); invalid['parts_vertex_ranges'].pop('foot_R')
        with self.assertRaisesRegex(ValueError, 'six original components'):
            projection.identify_parts(vertices, triangles, invalid)
        with self.assertRaisesRegex(ValueError, 'unreferenced'):
            projection.identify_parts(np.vstack([vertices, [10, 10, 10]]), triangles, metadata)

    def test_invalid_geometry_and_noninteger_ranges_fail(self):
        vertices, triangles, _, metadata = fixture()
        for faces in [triangles.astype(float), triangles-100]:
            with self.subTest(dtype=faces.dtype), self.assertRaisesRegex(ValueError, 'Invalid surface geometry'):
                projection.identify_parts(vertices, faces, metadata)
        metadata['parts_vertex_ranges']['foot_L'] = [0, 8.0]
        with self.assertRaisesRegex(ValueError, 'Invalid original component'):
            projection.identify_parts(vertices, triangles, metadata)


if __name__ == '__main__':
    unittest.main()
