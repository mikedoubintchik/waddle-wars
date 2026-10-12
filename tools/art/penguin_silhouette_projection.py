#!/usr/bin/env python3
"""Software geometry diagnostic, not a game render or visual approval.

Read the exact GLB and recorded Godot camera. Rasterize geometry, calibrate it
against captured pixels, and apply only one uniform scale plus translation
to place the crown/sole on a reference canvas. No engine/browser invocation.
Requires numpy and Pillow. See --help; functions are reusable by fit tools.
"""
from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
import math
from pathlib import Path
import re
import struct

import numpy as np
from PIL import Image, ImageFilter


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_glb(path: Path):
    """Return POSITION, triangle indices, JSON; fail on unsupported ambiguity."""
    raw = path.read_bytes()
    if len(raw) < 20 or struct.unpack_from('<4sII', raw) != (b'glTF', 2, len(raw)):
        raise ValueError('Incomplete glTF 2 binary')
    chunks, offset = {}, 12
    while offset < len(raw):
        size, kind = struct.unpack_from('<II', raw, offset)
        chunks[kind] = raw[offset + 8:offset + 8 + size]
        offset += 8 + size
    doc = json.loads(chunks[0x4E4F534A])
    binary = chunks[0x004E4942]
    if doc.get('skins') or doc.get('animations') or len(doc['nodes']) != 1:
        raise ValueError('Diagnostic currently requires one identity-root unrigged mesh')
    node = doc['nodes'][0]
    for key, expected in [('matrix', np.eye(4).ravel().tolist()), ('translation', [0, 0, 0]),
                          ('rotation', [0, 0, 0, 1]), ('scale', [1, 1, 1])]:
        if key in node and not np.allclose(node[key], expected, atol=1e-7):
            raise ValueError('Nonidentity GLB node transform: ' + key)
    primitives = doc['meshes'][node['mesh']]['primitives']
    if len(primitives) != 1 or primitives[0].get('mode', 4) != 4:
        raise ValueError('Expected exactly one triangle primitive')

    def accessor(index):
        item = doc['accessors'][index]
        if item.get('sparse') or item.get('normalized'):
            raise ValueError('Sparse/normalized position or indices unsupported')
        view = doc['bufferViews'][item['bufferView']]
        if view.get('buffer', 0) != 0:
            raise ValueError('External GLB buffers unsupported')
        dtype = np.dtype({5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1'}[item['componentType']])
        width = {'SCALAR': 1, 'VEC3': 3}[item['type']]
        stride = view.get('byteStride', dtype.itemsize * width)
        start = view.get('byteOffset', 0) + item.get('byteOffset', 0)
        last = start + (item['count'] - 1) * stride + width * dtype.itemsize
        if last > view.get('byteOffset', 0) + view['byteLength'] or last > len(binary):
            raise ValueError('Accessor exceeds binary buffer')
        return np.ndarray((item['count'], width), dtype=dtype, buffer=binary,
                          offset=start, strides=(stride, dtype.itemsize)).copy()

    primitive = primitives[0]
    vertices = accessor(primitive['attributes']['POSITION']).astype(np.float64)
    triangles = accessor(primitive['indices']).reshape(-1, 3).astype(np.int64)
    if not np.isfinite(vertices).all() or triangles.max() >= len(vertices):
        raise ValueError('Invalid geometry')
    return vertices, triangles, doc


def identify_parts(vertices, triangles, metadata):
    """Exporter may reorder vertices. Match connected components, never slices."""
    if metadata.get('material_contract') == 'rear-surface-pbr-v1':
        return _identify_surface_parts(vertices, triangles, metadata)
    parent = np.arange(len(vertices))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return int(i)

    for a, b, c in triangles:
        parent[root(b)] = root(a)
        parent[root(c)] = root(a)
    groups = {}
    for index in range(len(vertices)):
        groups.setdefault(root(index), []).append(index)
    names, reports = {}, []
    expected = {name: end - start for name, (start, end) in metadata['parts_vertex_ranges'].items()}
    for connected in groups.values():
        xyz = vertices[connected]
        choices = [name for name, count in expected.items() if count == len(connected)
                   and (not name.endswith('_L') or xyz[:, 0].mean() < 0)
                   and (not name.endswith('_R') or xyz[:, 0].mean() > 0)]
        if len(choices) != 1:
            raise ValueError(f'Ambiguous component: {len(connected)} vertices, candidates {choices}')
        name = choices[0]
        if name in names.values():
            raise ValueError('Duplicate component: ' + name)
        for index in connected:
            names[index] = name
        reports.append({'name': name, 'vertices': len(connected), 'glb_index_min': min(connected),
                        'glb_index_max': max(connected), 'bounds_min': xyz.min(0).tolist(),
                        'bounds_max': xyz.max(0).tolist(), 'matched_by': 'connectivity, vertex count and X side'})
    if set(names.values()) != set(expected):
        raise ValueError('Missing metadata components')
    face_parts = []
    for tri in triangles:
        label = names[int(tri[0])]
        if any(names[int(index)] != label for index in tri):
            raise ValueError('Triangle crosses component labels')
        face_parts.append(label)
    return np.array(face_parts), reports


def _identify_surface_parts(vertices, triangles, metadata):
    """UV seams split indices, not geometry. Weld exact positions for labels only.

    The surface package separately proves V9 identity or localized b21 invariants. Here require
    six closed, unambiguous components with the original unique-position counts;
    never approximate-weld a near miss or alter the triangles being rasterized.
    """
    required = {'continuous_body_head', 'flipper_L', 'flipper_R',
                'foot_L', 'foot_R', 'short_tail_fan'}
    ranges = metadata.get('parts_vertex_ranges', {})
    if metadata.get('gate') == 'rear-surface-v2':
        expected_ranges = {'continuous_body_head': [0, 2258], 'flipper_L': [2258, 2740],
                           'flipper_R': [2740, 3222], 'foot_L': [3222, 5144],
                           'foot_R': [5144, 7066], 'short_tail_fan': [7066, 7372]}
        if metadata.get('geometry_contract') != 'tail-flippers-only-v1' or ranges != expected_ranges:
            raise ValueError('Localized surface diagnostic requires the fixed baseline component contract')
    if set(ranges) != required:
        raise ValueError('Surface metadata must declare the six original components')
    if any(not isinstance(pair, (list, tuple)) or len(pair) != 2
           or any(type(value) is not int for value in pair)
           or pair[0] < 0 or pair[1] <= pair[0] for pair in ranges.values()):
        raise ValueError('Invalid original component vertex ranges')
    vertices, triangles = np.asarray(vertices), np.asarray(triangles)
    if (vertices.ndim != 2 or vertices.shape[1] != 3 or not len(vertices)
            or not np.isfinite(vertices).all() or triangles.ndim != 2
            or triangles.shape[1] != 3 or not len(triangles)
            or not np.issubdtype(triangles.dtype, np.integer)
            or triangles.min() < 0 or triangles.max() >= len(vertices)):
        raise ValueError('Invalid surface geometry')
    if len(np.unique(triangles)) != len(vertices):
        raise ValueError('Surface geometry contains unreferenced vertices')
    unique, inverse = np.unique(vertices, axis=0, return_inverse=True)
    welded = inverse[triangles]
    ordered = np.sort(welded, axis=1)
    if (np.diff(ordered, axis=1) == 0).any():
        raise ValueError('Degenerate triangle after exact POSITION welding')
    if len(np.unique(ordered, axis=0)) != len(ordered):
        raise ValueError('Duplicate surface triangle after exact POSITION welding')
    points = unique[welded]
    if (np.linalg.norm(np.cross(points[:, 1] - points[:, 0],
                               points[:, 2] - points[:, 0]), axis=1) == 0).any():
        raise ValueError('Zero-area surface triangle')
    edges = np.concatenate((welded[:, [0, 1]], welded[:, [1, 2]], welded[:, [2, 0]]))
    _edges, edge_ids, counts = np.unique(np.sort(edges, axis=1), axis=0,
                                        return_inverse=True, return_counts=True)
    directions = np.where(edges[:, 0] < edges[:, 1], 1, -1)
    if (counts != 2).any() or np.any(np.bincount(edge_ids, weights=directions) != 0):
        raise ValueError('Surface components must be closed with consistent triangle winding')
    plain_metadata = dict(metadata, material_contract='plain-literal-COLOR_0')
    face_parts, reports = identify_parts(unique, welded, plain_metadata)
    if len(reports) != 6:
        raise ValueError('Expected six closed surface components')
    for report in reports:
        component = np.unique(welded[face_parts == report['name']])
        original = np.flatnonzero(np.isin(inverse, component))
        report.update(unique_positions=report['vertices'], vertices=len(original),
                      glb_index_min=int(original.min()), glb_index_max=int(original.max()),
                      matched_by='exact POSITION welding, closed connectivity, unique vertex count and X side')
    return face_parts, reports


def parse_transform(text):
    # Godot VariantWriter serializes Basis.rows, not columns:
    # core/variant/variant_parser.cpp (4.7-stable), lines 1993-2007.
    match = re.fullmatch(r'Transform3D\((.*)\)', text)
    values = np.array([float(v) for v in match[1].split(',')]) if match else np.array([])
    if len(values) != 12 or not np.isfinite(values).all():
        raise ValueError('Invalid Godot Transform3D string')
    matrix = np.eye(4)
    matrix[:3, :3], matrix[:3, 3] = values[:9].reshape(3, 3), values[9:]
    return matrix


def camera_from_receipt(receipt, allow_source_identity=False):
    shape, qa = receipt['shape'], receipt['qa']
    camera = shape['camera']
    if shape['view'] != 'rear_detail' or shape['status'] != 'ready' or not qa['tree_paused']:
        raise ValueError('A ready frozen rear-detail receipt is required')
    if camera.get('projection', 0) != 0 or camera.get('keep_aspect', 1) != 1:
        raise ValueError('Only perspective KEEP_HEIGHT projection is supported')
    if camera.get('h_offset', 0) or camera.get('v_offset', 0):
        raise ValueError('Offset camera unsupported')
    if 'transforms' in shape:
        model = parse_transform(shape['transforms']['model_global'])
        provenance = 'captured model.global_transform'
    elif allow_source_identity:
        if qa['runner']['state'] != 0 or qa['runner']['invulnerable_for'] != 0 \
                or qa['runner']['hits_left'] != 3 or qa['camera']['player_position'][:2] != [0, 0]:
            raise ValueError('Old receipt does not establish straight grounded no-hit RUN')
        model = np.eye(4)
        model[:3, :3] *= shape['gameplay_scale']
        model[:3, 3] = qa['camera']['player_position']
        provenance = ('source-reconstructed identity player and PenguinVisual root: initial centered RUN, '
                      'no turn/jump/hit; runner_player.gd setup/_drive_visual and penguin_visual.gd drive_motion; '
                      'not directly captured, requires independent pixel calibration')
    else:
        raise ValueError('No captured model transform; explicit --allow-source-identity required')
    width, height = qa['canvas_backing']
    if not math.isclose(width / height, shape['logical_viewport'][0] / shape['logical_viewport'][1]):
        raise ValueError('Canvas and game viewport aspects disagree')
    return {'schema_version': 1, 'viewport': [width, height], 'vertical_fov_degrees': camera['fov'],
            'camera_global_matrix': parse_transform(camera['transform']).tolist(),
            'model_global_matrix': model.tolist(), 'model_transform_provenance': provenance,
            'near': camera.get('near', 0.05), 'keep_aspect': 'KEEP_HEIGHT',
            'baseline_gameplay_scale': shape['gameplay_scale'],
            'bound_glb_sha256': shape['bound_source']['glb_sha256']}


def project_vertices(vertices, camera, gameplay_scale=None):
    model = np.array(camera['model_global_matrix'])
    if gameplay_scale is not None:
        model[:3, :3] *= gameplay_scale / camera['baseline_gameplay_scale']
    view = np.linalg.inv(np.array(camera['camera_global_matrix']))
    local = np.c_[vertices, np.ones(len(vertices))] @ (view @ model).T
    depth = -local[:, 2]
    if (depth <= camera['near']).any():
        raise ValueError('Near-plane clipping needed; refusing inaccurate projection')
    width, height = camera['viewport']
    focal = height / (2 * math.tan(math.radians(camera['vertical_fov_degrees']) / 2))
    xy = np.c_[width / 2 + focal * local[:, 0] / depth,
               height / 2 - focal * local[:, 1] / depth]
    return xy, depth


def rasterize(xy, depth, triangles, face_parts, size, world_y=None, floor_y=None):
    """Pixel-center triangle coverage + perspective-correct depth; no antialiasing."""
    width, height = size
    labels = sorted(set(face_parts))
    parts = {name: np.zeros((height, width), bool) for name in labels}
    visible = np.zeros((height, width), np.uint8)
    zbuffer = np.full((height, width), np.inf)
    for tri, name in zip(triangles, face_parts):
        p = xy[tri]
        x0, y0 = np.maximum(np.ceil(p.min(0) - .5).astype(int), [0, 0])
        x1, y1 = np.minimum(np.floor(p.max(0) - .5).astype(int), [width - 1, height - 1])
        if x1 < x0 or y1 < y0:
            continue
        a, b, c = p
        denominator = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(denominator) < 1e-10:
            continue
        x, y = np.meshgrid(np.arange(x0, x1 + 1) + .5, np.arange(y0, y1 + 1) + .5)
        wa = ((b[1] - c[1]) * (x - c[0]) + (c[0] - b[0]) * (y - c[1])) / denominator
        wb = ((c[1] - a[1]) * (x - c[0]) + (a[0] - c[0]) * (y - c[1])) / denominator
        wc = 1 - wa - wb
        inside = (wa >= -1e-8) & (wb >= -1e-8) & (wc >= -1e-8)
        z = 1 / (wa / depth[tri[0]] + wb / depth[tri[1]] + wc / depth[tri[2]])
        if floor_y is not None:
            height_world = z * (wa * world_y[tri[0]] / depth[tri[0]]
                                + wb * world_y[tri[1]] / depth[tri[1]]
                                + wc * world_y[tri[2]] / depth[tri[2]])
            inside &= height_world >= floor_y
        parts[name][y0:y1 + 1, x0:x1 + 1] |= inside
        changed = inside & (z < zbuffer[y0:y1 + 1, x0:x1 + 1])
        zbuffer[y0:y1 + 1, x0:x1 + 1][changed] = z[changed]
        visible[y0:y1 + 1, x0:x1 + 1][changed] = labels.index(name) + 1
    return visible > 0, parts, visible, labels


def mask_image(mask):
    return Image.fromarray(mask.astype(np.uint8) * 255, 'L')


def boundary(mask):
    eroded = np.array(mask_image(mask).filter(ImageFilter.MinFilter(3))) > 0
    return mask & ~eroded


def bounds(mask):
    y, x = np.where(mask)
    return [int(x.min()), int(y.min()), int(x.max()), int(y.max())]


def captured_foreground(image, profile='v5'):
    """Independent RGB segmentation, restricted to manually reviewed ROI.

    No projected-mask input: dark neutral plumage or warm cream/orange pixels.
    Keep the largest connected object; course, shadow and HUD are excluded.
    The v5 profile remains byte-for-byte reproducible. rear-detail-wide uses
    the same fixed camera but includes the enlarged head and dark brown feet
    observed in the actual v6 screenshot; neither ROI comes from projection.
    """
    if image.size != (1280, 800):
        raise ValueError('Automatic RGB segmentation requires reviewed 1280x800 rear-detail view; supply an independent captured mask')
    if profile not in ('v5', 'rear-detail-wide'):
        raise ValueError('Unknown independent RGB segmentation profile')
    pixels = np.asarray(image.convert('RGB')).astype(int)
    r, g, b = pixels.transpose(2, 0, 1)
    eligible = ((r < 115) & (g < 140) & (b < 150)) \
        | ((r < 220) & (g < 225) & (b < 235) & (b - r < 45)) \
        | ((r > b + 8) & (r > 100))
    eligible[:370] = (((r < 220) & (g < 225) & (b < 235) & (b - r < 45))
                      | ((r > b + 8) & (r > 100)))[:370]
    if profile == 'rear-detail-wide':
        # Wider crop also sees pale blue course rails. A dark-neutral or warm
        # test includes the actual plumage/cream edge without joining rails.
        eligible[:370] = (((r < 150) & (g < 175) & (b < 185) & (b - r < 45))
                          | ((r > b + 8) & (r > 40)))[:370]
    eligible[628:] = (((r > b - 6) & (r > 110)) if profile == 'v5'
                     else ((r > b + 8) & (g > b + 4) & (r > 40)))[628:]
    roi = np.zeros(eligible.shape, bool)
    y0, y1, x0, x1, head_left, head_right = (255, 655, 470, 810, 565, 715) if profile == 'v5' \
        else (240, 665, 455, 825, 554, 730)
    roi[y0:y1, x0:x1] = True
    roi[y0:370, :head_left] = False
    roi[y0:370, head_right:] = False
    eligible &= roi
    seen = np.zeros(eligible.shape, bool)
    groups = []
    for sy, sx in zip(*np.where(eligible)):
        if seen[sy, sx]:
            continue
        queue, group = deque([(sy, sx)]), []
        seen[sy, sx] = True
        while queue:
            y, x = queue.popleft()
            group.append((y, x))
            for dy, dx in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
                ny, nx = y + dy, x + dx
                if 0 <= ny < eligible.shape[0] and 0 <= nx < eligible.shape[1] and eligible[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        groups.append(group)
    mask = np.zeros(eligible.shape, bool)
    if not groups:
        raise ValueError('Independent RGB segmentation found no foreground')
    largest = max(groups, key=len)
    ys, xs = np.array(largest).T
    mask[ys, xs] = True
    crop = mask[y0:y1, x0:x1]
    exterior = np.zeros(crop.shape, bool)
    queue = deque([(0, 0)])
    exterior[0, 0] = True
    while queue:
        y, x = queue.popleft()
        for dy, dx in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
            ny, nx = y + dy, x + dx
            if 0 <= ny < crop.shape[0] and 0 <= nx < crop.shape[1] and not crop[ny, nx] and not exterior[ny, nx]:
                exterior[ny, nx] = True
                queue.append((ny, nx))
    crop |= ~exterior
    return mask


def supplied_captured_mask(mask_path, receipt_path, screenshot_path, size):
    """Require a separately evidenced pixel mask, never an unlabelled model mask."""
    receipt = json.loads(receipt_path.read_text())
    if receipt.get('screenshot_sha256') != sha(screenshot_path) or receipt.get('mask_sha256') != sha(mask_path):
        raise ValueError('Independent captured-mask receipt hash mismatch')
    if receipt.get('independent_of_projection') is not True or not isinstance(receipt.get('method'), str) \
            or not receipt['method'].strip() or not isinstance(receipt.get('reviewer'), str) or not receipt['reviewer'].strip():
        raise ValueError('Captured-mask receipt must name independent pixel method and reviewer')
    with Image.open(mask_path) as image:
        if image.size != tuple(size) or image.mode not in ('1', 'L'):
            raise ValueError('Captured mask must be a full-resolution monochrome image')
        pixels = np.asarray(image.convert('L'))
    if not set(np.unique(pixels)).issubset({0, 255}) or not (pixels == 255).any():
        raise ValueError('Captured mask must contain nonempty binary 0/255 pixels')
    return pixels == 255, receipt


def calibration(projected, captured, edge_tolerance=2.0, method='color threshold in reviewed ROI; largest connected component'):
    if projected.shape != captured.shape or not projected.any() or not captured.any():
        raise ValueError('Calibration requires matching nonempty full-resolution masks')
    first, second = np.array(np.where(boundary(projected))).T, np.array(np.where(boundary(captured))).T
    distances = []
    for a, b in [(first, second), (second, first)]:
        chunks = [np.sqrt(((a[i:i + 128, None] - b[None]) ** 2).sum(2).min(1))
                  for i in range(0, len(a), 128)]
        distances.append(np.concatenate(chunks))
    both = np.concatenate(distances)
    iou = (projected & captured).sum() / (projected | captured).sum()
    return {'independent_pixel_mask_method': method,
            'projected_bounds': bounds(projected), 'captured_bounds': bounds(captured),
            'intersection_over_union': float(iou), 'symmetric_boundary_mean_px': float(both.mean()),
            'symmetric_boundary_p95_px': float(np.percentile(both, 95)),
            'symmetric_boundary_max_px': float(both.max()),
            'edge_tolerance_px': edge_tolerance,
            'calibrated': bool(iou >= .97 and np.percentile(both, 95) <= edge_tolerance),
            'limits': 'JPEG/antialiasing and color segmentation affect edge pixels; not a reference likeness score'}


def affine_for_mask(mask, target_crown=62., target_sole=366., center_x=226.):
    x0, y0, x1, y1 = bounds(mask)
    scale = (target_sole - target_crown) / (y1 - y0)
    return {'scale': scale, 'offset_x': center_x - scale * ((x0 + x1) / 2),
            'offset_y': target_crown - scale * y0, 'source_bounds': [x0, y0, x1, y1],
            'target_crown': target_crown, 'target_sole': target_sole, 'target_center_x': center_x,
            'policy': 'one uniform scale and translation; no per-part scaling or deformation'}


def apply_affine(image, affine, size=(443, 443), nearest=False):
    scale, ox, oy = affine['scale'], affine['offset_x'], affine['offset_y']
    return image.transform(size, Image.Transform.AFFINE, (1 / scale, 0, -ox / scale, 0, 1 / scale, -oy / scale),
                           resample=Image.Resampling.NEAREST if nearest else Image.Resampling.BICUBIC)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--metadata', type=Path, required=True)
    parser.add_argument('--receipt', type=Path)
    parser.add_argument('--camera-config', type=Path)
    parser.add_argument('--screenshot', type=Path)
    parser.add_argument('--segmentation-profile', choices=['v5', 'rear-detail-wide'], default='v5',
                        help='Independent RGB mask profile; v5 preserves original calibration, rear-detail-wide includes wider head/dark feet')
    parser.add_argument('--captured-mask', type=Path, help='Independent binary screenshot silhouette, not projected geometry')
    parser.add_argument('--captured-mask-receipt', type=Path,
                        help='JSON with screenshot_sha256, mask_sha256, independent_of_projection=true, method and reviewer')
    parser.add_argument('--allow-source-identity', action='store_true')
    parser.add_argument('--alignment', type=Path, help='Reuse fixed alignment; otherwise derive once from baseline')
    parser.add_argument('--center-x', type=float, default=226.)
    parser.add_argument('--floor-y', type=float, help='Explicit world-space opaque visual floor, not collision floor')
    parser.add_argument('--floor-evidence', help='Source or receipt explaining the visual floor height')
    parser.add_argument('--calibration-edge-tolerance', type=float, default=2.,
                        help='Explicit source-pixel boundary uncertainty; v5 independent audit establishes 3px JPEG/ice limit')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    if bool(args.captured_mask) != bool(args.captured_mask_receipt) or (args.captured_mask and not args.screenshot):
        parser.error('--captured-mask and --captured-mask-receipt require each other and --screenshot')
    metadata = json.loads(args.metadata.read_text())
    vertices, triangles, _doc = load_glb(args.candidate)
    face_parts, part_report = identify_parts(vertices, triangles, metadata)
    if sha(args.candidate) != metadata['glb_sha256']:
        raise ValueError('Metadata/GLB hash mismatch')
    if args.camera_config:
        camera = json.loads(args.camera_config.read_text())
    elif args.receipt:
        receipt = json.loads(args.receipt.read_text())
        camera = camera_from_receipt(receipt, args.allow_source_identity)
        if sha(args.candidate) != camera['bound_glb_sha256']:
            raise ValueError('Captured receipt/GLB hash mismatch')
    else:
        parser.error('--receipt or --camera-config required')
    xy, depth = project_vertices(vertices, camera, metadata['gameplay_scale'])
    geometry, _, _, _ = rasterize(xy, depth, triangles, face_parts, camera['viewport'])
    if args.floor_y is not None:
        if not args.floor_evidence:
            raise ValueError('--floor-y requires --floor-evidence')
        camera['visual_floor'] = {'world_y': args.floor_y, 'evidence': args.floor_evidence}
    model = np.array(camera['model_global_matrix'])
    model[:3, :3] *= metadata['gameplay_scale'] / camera['baseline_gameplay_scale']
    world_y = (np.c_[vertices, np.ones(len(vertices))] @ model.T)[:, 1]
    floor_y = camera.get('visual_floor', {}).get('world_y')
    full, parts, visible, labels = rasterize(xy, depth, triangles, face_parts, camera['viewport'], world_y, floor_y)
    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    mask_image(full).save(out / 'silhouette-full.png')
    mask_image(geometry).save(out / 'geometry-unoccluded-full.png')
    Image.fromarray(visible, 'L').save(out / 'visible-labels-full.png')
    report = {'diagnostic': 'software projection, not a new engine render', 'candidate_sha256': sha(args.candidate),
              'vertices': len(vertices), 'triangles': len(triangles), 'parts': part_report,
              'visible_label_ids': {name: index + 1 for index, name in enumerate(labels)},
              'projection_bounds_float': [*xy.min(0).tolist(), *xy.max(0).tolist()], 'camera': camera}
    report['mask_policy'] = ('silhouette includes model self-occlusion and declared floor; named part masks project each '
                             'component through other components; visible-* masks include z-buffer self-occlusion')
    report['visual_floor_occluded_pixels'] = int((geometry & ~full).sum())
    image = None
    if args.screenshot:
        image = Image.open(args.screenshot).convert('RGB')
        if list(image.size) != camera['viewport']:
            raise ValueError('Screenshot dimensions disagree with recorded canvas')
        if args.captured_mask:
            actual, mask_receipt = supplied_captured_mask(args.captured_mask, args.captured_mask_receipt,
                                                        args.screenshot, image.size)
            report['captured_mask_receipt'] = mask_receipt
            report['captured_mask_receipt_sha256'] = sha(args.captured_mask_receipt)
            method = mask_receipt['method']
        else:
            actual = captured_foreground(image, args.segmentation_profile)
            method = 'independent RGB threshold in reviewed fixed ROI; largest component; profile=' + args.segmentation_profile
        mask_image(actual).save(out / 'captured-pixel-mask.png')
        report['calibration'] = calibration(full, actual, args.calibration_edge_tolerance, method)
        report['screenshot_sha256'] = sha(args.screenshot)
        overlay = np.asarray(image).copy()
        overlay[boundary(actual)] = [255, 0, 255]
        overlay[boundary(full)] = [0, 255, 255]
        Image.fromarray(overlay).save(out / 'calibration-overlay.png')
    affine = json.loads(args.alignment.read_text()) if args.alignment else affine_for_mask(full, center_x=args.center_x)
    apply_affine(mask_image(full), affine, nearest=True).save(out / 'silhouette-aligned.png')
    apply_affine(Image.fromarray(visible, 'L'), affine, nearest=True).save(out / 'visible-labels-aligned.png')
    for name, mask in parts.items():
        mask_image(mask).save(out / (name + '-full.png'))
        apply_affine(mask_image(mask), affine, nearest=True).save(out / (name + '-aligned.png'))
        visible_part = visible == labels.index(name) + 1
        mask_image(visible_part).save(out / ('visible-' + name + '-full.png'))
        apply_affine(mask_image(visible_part), affine, nearest=True).save(out / ('visible-' + name + '-aligned.png'))
    for group, prefixes in [('body', ['continuous_body_head', 'short_tail_fan']),
                            ('flippers', ['flipper_']), ('feet', ['foot_'])]:
        mask = np.logical_or.reduce([value for name, value in parts.items() if any(name.startswith(p) for p in prefixes)])
        mask_image(mask).save(out / (group + '-full.png'))
        apply_affine(mask_image(mask), affine, nearest=True).save(out / (group + '-aligned.png'))
        ids = [index + 1 for index, name in enumerate(labels) if any(name.startswith(p) for p in prefixes)]
        visible_group = np.isin(visible, ids)
        mask_image(visible_group).save(out / ('visible-' + group + '-full.png'))
        apply_affine(mask_image(visible_group), affine, nearest=True).save(out / ('visible-' + group + '-aligned.png'))
    if image:
        apply_affine(image, affine).save(out / 'actual-pixels-aligned.png')
        rgba = image.convert('RGBA')
        rgba.putalpha(mask_image(full))
        apply_affine(rgba, affine).save(out / 'actual-pixels-cutout-aligned.png')
    for filename, data in [('camera.json', camera), ('alignment.json', affine), ('projection.json', report)]:
        (out / filename).write_text(json.dumps(data, indent=2) + '\n')
    print(json.dumps({'out': str(out), 'calibration': report.get('calibration'), 'bounds': bounds(full)}))
    if args.screenshot and not report['calibration']['calibrated']:
        raise SystemExit('Projection calibration FAILED; do not use for fitting')


if __name__ == '__main__':
    main()
