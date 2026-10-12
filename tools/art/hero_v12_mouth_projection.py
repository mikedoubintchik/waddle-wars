"""QA-only missing-mouth microprojection; no runtime mesh or valid pixel edits.

The mouth ribbon has opposing sheets: nearest-component sampling is insufficient.
Require an outward-compatible source *triangle*, then prove the actual float32
first ray and evaluate all channels with the existing Blender bake evaluator.
The separately approved 1.25 mm mouth cap does not alter the 0.25 mm eye cap.
"""
import hashlib
import importlib.util
import json
import math
import struct
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location("mouth_shared_probe_math", Path(__file__).with_name("hero_v12_projection_probes.py"))
P = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(P)
MAX_MOUTH_SOURCE_DISTANCE_M = 0.00125
MIN_FACE_ALIGNMENT = 0.5
MAX_MISSING_MOUTH_PIXELS = 32
MAX_SHADER_NORMAL_ERROR_DEGREES = 0.1


def enforce_distance(distance):
    if not math.isfinite(distance) or not 0 <= distance <= MAX_MOUTH_SOURCE_DISTANCE_M:
        raise ValueError(f"mouth source distance exceeds {MAX_MOUTH_SOURCE_DISTANCE_M}m: {distance}")


def facing_candidates(candidates, low_face_normal):
    """BVH tuples: point, outward face normal, triangle index, distance."""
    valid = [hit for hit in candidates if hit[0] is not None
             and math.isfinite(hit[3]) and 0 <= hit[3] <= MAX_MOUTH_SOURCE_DISTANCE_M
             and P.dot(P.normalized(hit[1]), P.normalized(low_face_normal)) >= MIN_FACE_ALIGNMENT]
    if not valid:
        raise ValueError("no outward-compatible paired mouth triangle inside distance cap")
    return sorted(valid, key=lambda hit: (hit[3], hit[2]))


def select_facing_candidate(candidates, low_face_normal):
    return facing_candidates(candidates, low_face_normal)[0]


def probe_radius(edge_clearance):
    # Farthest equilateral probe corner is 2r. Hence 0.4 leaves at least
    # 20% of measured edge clearance, including on narrow source ribbons.
    radius = edge_clearance * .4
    if not math.isfinite(radius) or radius < 5e-7:
        raise ValueError("paired mouth interior too narrow for stable float32 probe")
    return radius


def validate_scope(names):
    if not 1 <= len(names) <= MAX_MISSING_MOUTH_PIXELS or any(name != "BillMouthSeam" for name in names):
        raise ValueError("mouth repair requires 1..32 genuine misses, all exactly BillMouthSeam")


def normal_error_degrees(expected, actual):
    value = max(-1.0, min(1.0, P.dot(P.normalized(expected), P.normalized(actual))))
    error = math.degrees(math.acos(value))
    if error > MAX_SHADER_NORMAL_ERROR_DEGREES:
        raise ValueError(f"baked source shading normal differs by {error} degrees")
    return error


def barycentric(point, first, second, third):
    """Float64 dominant-axis signed areas; thin source ribbons cancel Gram dots."""
    u = tuple(float(second[i]) - float(first[i]) for i in range(3))
    v = tuple(float(third[i]) - float(first[i]) for i in range(3))
    w = tuple(float(point[i]) - float(first[i]) for i in range(3))
    if not all(math.isfinite(value) for row in (u, v, w) for value in row):
        raise ValueError("nonfinite mouth triangle/sample")
    normal = P.cross(u, v)
    axis = max(range(3), key=lambda i: abs(normal[i]))
    if abs(normal[axis]) < 1e-25:
        raise ValueError("degenerate mouth triangle")
    b = P.cross(w, v)[axis] / normal[axis]
    c = P.cross(u, w)[axis] / normal[axis]
    return 1 - b - c, b, c


def packed_orm(ao, roughness, metallic):
    if metallic != 0.0 or not all(math.isfinite(v) and 0 <= v <= 1 for v in (ao, roughness)):
        raise ValueError("mouth ORM requires actual finite bake values and verified nonmetallic source")
    return ao, roughness, metallic, 1.0


def _mesh_digest(mesh):
    """Actual geometry, transforms, UV, source paint, normals and target TBN."""
    digest = hashlib.sha256()
    for row in mesh.matrix_world:
        digest.update(struct.pack("<4f", *row))
    for vertex in mesh.data.vertices:
        digest.update(struct.pack("<3f", *vertex.co))
    for face in mesh.data.polygons:
        digest.update(struct.pack("<I", len(face.vertices)))
        digest.update(struct.pack("<" + "I" * len(face.vertices), *face.vertices))
        digest.update(struct.pack("<?I", face.use_smooth, face.material_index))
    for normal in mesh.data.corner_normals:
        digest.update(struct.pack("<3f", *normal.vector))
    for uv in mesh.data.uv_layers:
        digest.update(uv.name.encode())
        for item in uv.data:
            digest.update(struct.pack("<2f", *item.uv))
    for attr in mesh.data.color_attributes:
        digest.update((attr.name + attr.domain + attr.data_type).encode())
        for item in attr.data:
            digest.update(struct.pack("<4f", *item.color))
    for loop in mesh.data.loops:
        digest.update(struct.pack("<4f", *loop.tangent, loop.bitangent_sign))
    return digest.hexdigest()


def _probe_candidate(a, high, source_face, bvh, low_point, low_face_normal, nearest, distance):
    """Accept only an unoccluded actual float32 footprint on one source face."""
    from mathutils import Vector
    triangle = high.data.loop_triangles[source_face]
    points = [high.data.vertices[i].co.copy() for i in triangle.vertices]
    near_weights = barycentric(nearest, *points)
    inner = [max(.01, weight) for weight in near_weights]
    inner = [weight / sum(inner) for weight in inner]
    center = sum((point * w for point, w in zip(points, inner)), Vector())
    enforce_distance((center - low_point).length)
    source_normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
    source_tangent = (points[1] - points[0]).normalized()
    source_bitangent = source_normal.cross(source_tangent)
    radius = probe_radius(min((center - p).cross(q - p).length / (q - p).length
                              for p, q in zip(points, points[1:] + points[:1])))
    data = a.bpy.data.meshes.new("PairedMouthMicroProbe")
    try:
        offsets = [(-1, -1), (1, -1), (0, 2)]
        data.from_pydata([center - source_normal * 1e-5 + (source_tangent * u + source_bitangent * v) * radius
                          for u, v in offsets], [], [(0, 1, 2)])
        stage_uv = data.uv_layers.new(name=a.ATLAS_UV)
        for item, (u, v) in zip(stage_uv.data, offsets):
            item.uv = (8.5 / 16 + u * .2, 8.5 / 16 + v * .2)
        data.update()
        stage_weights = barycentric(Vector((8.5 / 16, 8.5 / 16, 0)),
                                    *[Vector((*item.uv, 0)) for item in stage_uv.data])
        actual_low = sum((v.co * w for v, w in zip(data.vertices, stage_weights)), Vector())
        actual_normal = data.polygons[0].normal.copy()
        cage, ray = .00003, .00005
        ray_audits = []
        for label, target in [("sample_center", actual_low), *[(f"corner_{i}", v.co.copy()) for i, v in enumerate(data.vertices)]]:
            origin = target + actual_normal * cage
            hit, hit_normal, hit_face, hit_distance = bvh.ray_cast(origin, -actual_normal, ray)
            if hit is None or hit_face != source_face:
                raise ValueError(f"actual float32 {label} first triangle {hit_face}, intended {source_face}")
            enforce_distance((hit - low_point).length)
            hit_weights = barycentric(hit, *points)
            if min(hit_weights) <= 0 or hit_normal.dot(low_face_normal) < MIN_FACE_ALIGNMENT:
                raise ValueError(f"actual float32 {label} leaves intended interior/outward sheet")
            ray_audits.append({"sample": label, "probe_point": list(target), "origin": list(origin),
                               "direction": list(-actual_normal), "hit_point": list(hit), "first_triangle": hit_face,
                               "ray_length_m": hit_distance, "source_barycentric": list(hit_weights),
                               "source_distance_m": (hit-low_point).length,
                               "face_alignment": float(hit_normal.dot(low_face_normal))})
        sample = ray_audits[0]
        expected_normal = sum((high.data.corner_normals[i].vector * w
                               for i, w in zip(triangle.loops, sample["source_barycentric"])), Vector()).normalized()
        if expected_normal.dot(source_normal) <= 0:
            raise ValueError("paired source shading normal faces opposite selected sheet")
        audit = dict(source_triangle=source_face, source_nearest_distance_m=distance,
                     source_face_normal=list(source_normal), source_face_alignment=float(source_normal.dot(low_face_normal)),
                     source_nearest_barycentric=list(near_weights), source_sample_barycentric=inner,
                     source_sample_point=list(center), intended_source_distance_m=(center-low_point).length,
                     probe_radius_m=radius, actual_probe_point=list(actual_low), actual_probe_normal=list(actual_normal),
                     actual_ray_origin=sample["origin"], actual_ray_direction=sample["direction"],
                     actual_ray_first_triangle=sample["first_triangle"], actual_ray_length_m=sample["ray_length_m"],
                     actual_ray_maximum_m=ray, actual_ray_cage_extrusion_m=cage,
                     actual_ray_hit_point=sample["hit_point"], actual_ray_source_barycentric=sample["source_barycentric"],
                     actual_source_distance_m=sample["source_distance_m"], actual_first_hit_gate_passed=True,
                     expected_source_shading_normal=list(expected_normal), actual_float32_footprint_rays=ray_audits,
                     actual_float32_footprint_same_triangle_interior=True)
        return data, expected_normal, audit
    except Exception:
        a.bpy.data.meshes.remove(data)
        raise


def repair(a, mesh, maps, owner, sources, highs, face_components, collection, output):
    import numpy as np
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    bpy = a.bpy
    coverage, hits = a.pixels(maps["coverage"])[..., 0], a.pixels(maps["hits"])[..., 0]
    missing = (coverage > 1e-5) & (hits + 1e-5 < coverage)
    coords = np.argwhere(missing)
    validate_scope([sources[int(owner[y, x])].name if owner[y, x] >= 0 else "UNOWNED" for y, x in coords])
    untouched = ~missing
    before = {name: hashlib.sha256(a.pixels(image)[untouched].tobytes()).hexdigest() for name, image in maps.items()}
    mesh.data.calc_tangents(uvmap=a.ATLAS_UV)
    component = int(owner[tuple(coords[0])])
    high = highs[component]
    if not mesh.matrix_world.is_identity or not high.matrix_world.is_identity:
        raise RuntimeError("mouth probe requires original canonical identity transforms")
    materials = list(high.data.materials)
    if len(materials) != 1:
        raise RuntimeError("paired mouth source must have its one original material")
    bsdf = [node for node in materials[0].node_tree.nodes if node.type == "BSDF_PRINCIPLED"]
    if len(bsdf) != 1 or bsdf[0].inputs["Normal"].is_linked or bsdf[0].inputs["Metallic"].is_linked:
        raise RuntimeError("mouth normal/material audit requires original unmodified solid source shader")
    metallic = float(bsdf[0].inputs["Metallic"].default_value)
    packed_orm(1.0, 0.72, metallic)
    immutable_before = {"target": _mesh_digest(mesh), "paired_high": _mesh_digest(high),
                        "target_skin_morphs": a.preservation_digest(mesh)}
    high.data.calc_loop_triangles()
    triangles = list(high.data.loop_triangles)
    bvh = BVHTree.FromPolygons([v.co for v in high.data.vertices], [tuple(t.vertices) for t in triangles], all_triangles=True)
    uv = mesh.data.uv_layers[a.ATLAS_UV]
    rows, plans = [], []
    stage_root = output / "paired_mouth_probes"
    stage_root.mkdir()
    # Complete geometric preflight before starting any bake or copying pixels.
    for y, x in coords:
        row = {"pixel_xy": [int(x), int(y)], "passed": False, "source_object": sources[component].name}
        rows.append(row)
        sample_uv = Vector(((x + .5) / owner.shape[1], (y + .5) / owner.shape[0], 0))
        candidates = []
        for face in mesh.data.polygons:
            if face_components[face.index] != component:
                continue
            if len(face.vertices) != 3:
                raise RuntimeError("mouth target must retain original final triangulation")
            weights = barycentric(sample_uv, *[Vector((*uv.data[i].uv, 0)) for i in face.loop_indices])
            if min(weights) >= -1e-6:
                candidates.append((face, weights))
        try:
            if len(candidates) != 1:
                raise ValueError(f"ambiguous original UV triangle: {len(candidates)}")
            face, weights = candidates[0]
            low_point = sum((mesh.data.vertices[i].co * w for i, w in zip(face.vertices, weights)), Vector())
            raw = bvh.find_nearest(low_point)
            row.update(low_triangle=face.index, low_barycentric=list(weights), low_point=list(low_point),
                       low_face_normal=list(face.normal), raw_nearest_triangle=raw[2], raw_nearest_distance_m=raw[3],
                       raw_nearest_face_normal=list(raw[1]), raw_nearest_alignment=float(raw[1].dot(face.normal)))
            rejected_candidates = []
            row["rejected_geometric_candidates"] = rejected_candidates
            for nearest, source_normal, source_face, distance in facing_candidates(
                    bvh.find_nearest_range(low_point, MAX_MOUTH_SOURCE_DISTANCE_M), face.normal):
                try:
                    probe_data, expected_normal, audit = _probe_candidate(
                        a, high, source_face, bvh, low_point, face.normal, nearest, distance)
                except ValueError as error:
                    rejected_candidates.append({"source_triangle": source_face, "nearest_distance_m": distance,
                                                "face_alignment": float(source_normal.dot(face.normal)), "reason": str(error)})
                else:
                    break
            else:
                raise ValueError("no facing-compatible source triangle has stable in-cap unoccluded footprint")
            normal = sum((mesh.data.corner_normals[i].vector * w for i, w in zip(face.loop_indices, weights)), Vector())
            tangent = sum((mesh.data.loops[i].tangent * w for i, w in zip(face.loop_indices, weights)), Vector())
            signs = [mesh.data.loops[i].bitangent_sign for i in face.loop_indices]
            if max(signs) != min(signs):
                raise ValueError("inconsistent target mirrored-UV handedness")
            sign = 1 if signs[0] > 0 else -1
            row.update(audit)
            row.update(target_tangent=list(tangent), target_normal=list(normal), handedness=sign)
            plans.append((row, int(x), int(y), probe_data, normal, tangent, sign, expected_normal))
        except ValueError as error:
            row["skip"] = str(error)
    report = {"method": "paired_outward_mouth_actual_material_microprobe", "qa_only": True,
              "source_distance_cap_m": MAX_MOUTH_SOURCE_DISTANCE_M,
              "unchanged_eye_source_distance_cap_m": P.MAX_SOURCE_DISTANCE_M,
              "minimum_outward_face_alignment": MIN_FACE_ALIGNMENT,
              "selection_rule": "nearest same-mouth triangle with normal dot original low face normal >=0.5 admitting stable in-cap unoccluded float32 footprint, then triangle ID",
              "probe_radius_to_edge_clearance_ratio": .4,
              "normal_conversion": "Existing Blender5.2 bake.cc928-956 inverse original interpolated TBN; mirrored sign preserved",
              "normal_source": "actual OBJECT bake, checked against same source triangle interpolated original corner normals",
              "maximum_shader_normal_error_degrees": MAX_SHADER_NORMAL_ERROR_DEGREES,
              "attempted": len(rows), "rows": rows,
              "scope": "Only originally missing mouth texels; all other texels, including repaired eyes, byte guarded before final map packing"}
    (output / "paired_mouth_preflight.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    if len(plans) != len(rows):
        raise RuntimeError("paired mouth geometric preflight failed; no bake/pixel copy performed")
    for row, x, y, probe_data, normal, tangent, sign, expected_normal in plans:
        print(f"[v12-mouth-probe] {x},{y} distance={row['actual_source_distance_m']:.9f}m face={row['source_triangle']}", flush=True)
        low, image_node = a.low_component(mesh, component, face_components, collection)
        probe_data.materials.append(low.data.materials[0])
        old_data, low.data = low.data, probe_data
        bpy.data.meshes.remove(old_data)
        stage = {name: a.new_image(f"Mouth_{x}_{y}_{name}", 16, (0, 0, 0, 1), srgb=name == "albedo") for name in maps}
        row["bake"] = a.bake_component(high, low, image_node, stage, margin=0, normal_space="OBJECT",
                                      cage_distance_m=.00003, ray_distance_m=.00005)
        values = {name: a.pixels(image)[8, 8].copy() for name, image in stage.items()}
        row.update(actual_probe_coverage=float(values["coverage"][0]), actual_probe_hit=float(values["hits"][0]))
        if values["coverage"][0] < .99 or values["hits"][0] + 1e-5 < values["coverage"][0]:
            raise RuntimeError("actual paired mouth material bake missed; no coverage waiver")
        world = P.normalized(tuple((float(v) - .5 - P.NORMAL_ENCODE_BIAS) * 2 for v in values["normal"][:3]))
        row["source_shader_normal_error_degrees"] = normal_error_degrees(expected_normal, world)
        values["orm"] = np.array(packed_orm(float(values["ao"][0]), float(values["roughness"][0]), metallic), dtype=np.float32)
        orm_pixels = a.pixels(stage["orm"])
        orm_pixels[8, 8] = values["orm"]
        a.set_pixels(stage["orm"], orm_pixels)
        stage_dir = stage_root / f"{x}_{y}"
        stage_dir.mkdir()
        for name, image in stage.items():
            a.save_pack_exact(image, stage_dir / f"{name}.png")
        target = P.world_to_tangent(world, tangent, normal, sign)
        values["normal"][:3] = [max(0, min(1, v * .5 + .5 + P.NORMAL_ENCODE_BIAS)) for v in target]
        values["hits"] = np.array((coverage[y, x],) * 3 + (1,), dtype=np.float32)
        # Target coverage never changes: hit certification comes from the
        # real same-source bake, not synthetic coverage/outpainting.
        for name, image in maps.items():
            if name == "coverage":
                continue
            array = a.pixels(image)
            array[y, x] = values[name]
            a.set_pixels(image, array)
        row.update(passed=True, source_shading_normal=list(world), target_tangent_normal=list(target),
                   packed_orm=[float(v) for v in values["orm"]])
        bpy.data.objects.remove(low, do_unlink=True)
        bpy.data.meshes.remove(probe_data)
        for image in stage.values():
            bpy.data.images.remove(image)
    after = {name: hashlib.sha256(a.pixels(image)[untouched].tobytes()).hexdigest() for name, image in maps.items()}
    immutable_after = {"target": _mesh_digest(mesh), "paired_high": _mesh_digest(high),
                       "target_skin_morphs": a.preservation_digest(mesh)}
    report.update(passed=sum(row["passed"] for row in rows), original_unselected_pixels_exactly_unchanged=before == after,
                  unselected_map_hashes_before=before, unselected_map_hashes_after=after,
                  geometry_normals_uv_paint_skin_morphs_unchanged=immutable_before == immutable_after,
                  immutable_hashes_before=immutable_before, immutable_hashes_after=immutable_after,
                  maximum_actual_source_distance_m=max(row["actual_source_distance_m"] for row in rows))
    (output / "paired_mouth_projection.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    if before != after or immutable_before != immutable_after or list(high.data.materials) != materials:
        raise RuntimeError("mouth repair changed unselected pixels or original mesh/material state")
    return report
