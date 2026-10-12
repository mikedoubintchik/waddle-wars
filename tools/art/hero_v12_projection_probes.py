"""QA-only paired-high boundary probes; Blender remains the material evaluator."""
import hashlib
import json
import math

MAX_SOURCE_DISTANCE_M = 0.00025
NORMAL_ENCODE_BIAS = 1e-5


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def normalized(value):
    length = math.sqrt(dot(value, value))
    if not math.isfinite(length) or length < 1e-10:
        raise ValueError("degenerate/nonfinite projection normal")
    return tuple(x / length for x in value)


def world_to_tangent(world, tangent, normal, sign):
    """Blender5.2 bake.cc928-956: inverse interpolated TBN, then normalize."""
    if sign not in (-1, 1):
        raise ValueError("invalid tangent handedness")
    binormal = tuple(x * sign for x in cross(normal, tangent))
    determinant = dot(tangent, cross(binormal, normal))
    if not math.isfinite(determinant) or abs(determinant) < 1e-8:
        raise ValueError("degenerate target TBN")
    value = (dot(world, cross(binormal, normal)) / determinant,
             dot(tangent, cross(world, normal)) / determinant,
             dot(tangent, cross(binormal, world)) / determinant)
    value = normalized(value)
    reconstructed = normalized(tuple(tangent[i] * value[0] + binormal[i] * value[1] + normal[i] * value[2] for i in range(3)))
    expected = normalized(world)
    if max(abs(a - b) for a, b in zip(reconstructed, expected)) > 1e-6:
        raise ValueError("target TBN roundtrip failed")
    return value


def enforce_distance(distance):
    if not math.isfinite(distance) or not 0 <= distance <= MAX_SOURCE_DISTANCE_M:
        raise ValueError(f"paired-source projection distance exceeds {MAX_SOURCE_DISTANCE_M}m: {distance}")


def barycentric(point, first, second, third):
    u, v, w = second - first, third - first, point - first
    uu, uv, vv, wu, wv = u.dot(u), u.dot(v), v.dot(v), w.dot(u), w.dot(v)
    denominator = uu * vv - uv * uv
    if abs(denominator) < 1e-25:
        raise ValueError("degenerate source triangle")
    b, c = (vv * wu - uv * wv) / denominator, (uu * wv - uv * wu) / denominator
    return 1 - b - c, b, c


def repair(a, mesh, maps, owner, sources, highs, face_components, collection, output):
    import numpy as np
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    bpy = a.bpy
    coverage, hits = a.pixels(maps["coverage"])[..., 0], a.pixels(maps["hits"])[..., 0]
    missing = (coverage > 1e-5) & (hits + 1e-5 < coverage)
    coords = np.argwhere(missing)
    if len(coords) > 32:
        raise RuntimeError("bounded eye probe cannot handle more than32 missing texels")
    untouched = ~missing
    before = {name: hashlib.sha256(a.pixels(image)[untouched].tobytes()).hexdigest() for name, image in maps.items()}
    mesh.data.calc_tangents(uvmap=a.ATLAS_UV)
    uv = mesh.data.uv_layers[a.ATLAS_UV]
    caches, rows = {}, []
    stage_root = output / "nearest_source_probes"
    stage_root.mkdir()
    for y, x in coords:
        row = {"pixel_xy": [int(x), int(y)], "passed": False}
        rows.append(row)
        component = int(owner[y, x])
        if component < 0 or not sources[component].name.startswith(("IntegratedOrbitalRim", "Iris", "LimbalRing", "Pupil", "Catchlight")):
            row["skip"] = "missing texel is not an explicitly allowed eye/rim component"
            continue
        source, high = sources[component], highs[component]
        row["source_object"] = source.name
        sample_uv = Vector(((x + 0.5) / owner.shape[1], (y + 0.5) / owner.shape[0], 0))
        candidates = []
        for face in mesh.data.polygons:
            if face_components[face.index] != component:
                continue
            vertices = [Vector((*uv.data[index].uv, 0)) for index in face.loop_indices]
            weights = barycentric(sample_uv, *vertices)
            if min(weights) >= -1e-6:
                candidates.append((face, weights))
        if len(candidates) != 1:
            row["skip"] = f"ambiguous original UV triangle: {len(candidates)}"
            continue
        face, weights = candidates[0]
        low_point = sum((mesh.data.vertices[index].co * weight for index, weight in zip(face.vertices, weights)), Vector())
        if component not in caches:
            high.data.calc_loop_triangles()
            triangles = [tuple(triangle.vertices) for triangle in high.data.loop_triangles]
            caches[component] = (BVHTree.FromPolygons([vertex.co for vertex in high.data.vertices], triangles, all_triangles=True), triangles)
        bvh, triangles = caches[component]
        nearest, _normal, high_triangle, distance = bvh.find_nearest(low_point)
        row.update(low_triangle=face.index, low_barycentric=list(weights), low_point=list(low_point),
                   source_triangle=high_triangle, nearest_distance_m=distance)
        try:
            enforce_distance(distance)
            points = [high.data.vertices[index].co.copy() for index in triangles[high_triangle]]
            near_weights = barycentric(nearest, *points)
            # Strictly interior, same triangle. The *actual* sampling point,
            # including this microscopic inset, must remain within the cap.
            inner = [max(0.01, weight) for weight in near_weights]
            inner = [weight / sum(inner) for weight in inner]
            center = sum((point * weight for point, weight in zip(points, inner)), Vector())
            actual_distance = (center - low_point).length
            enforce_distance(actual_distance)
            source_normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
            source_tangent = (points[1] - points[0]).normalized()
            source_bitangent = source_normal.cross(source_tangent)
            radius = min((center - p).cross(q - p).length / (q - p).length for p, q in zip(points, points[1:] + points[:1])) * 0.2
            if radius < 5e-7:
                raise ValueError("source triangle interior too narrow for a stable float32 probe")
            normal = sum((mesh.data.corner_normals[index].vector * weight for index, weight in zip(face.loop_indices, weights)), Vector())
            tangent = sum((mesh.data.loops[index].tangent * weight for index, weight in zip(face.loop_indices, weights)), Vector())
            signs = [mesh.data.loops[index].bitangent_sign for index in face.loop_indices]
            if max(signs) != min(signs):
                raise ValueError("target triangle has inconsistent mirrored-UV handedness")
            sign = 1 if signs[0] > 0 else -1
            row.update(source_nearest_barycentric=list(near_weights), source_sample_barycentric=inner,
                       source_sample_point=list(center), actual_source_distance_m=actual_distance,
                       probe_radius_m=radius, target_tangent=list(tangent), target_normal=list(normal), handedness=sign)
        except ValueError as error:
            row["skip"] = str(error)
            continue
        low, image_node = a.low_component(mesh, component, face_components, collection)
        probe_data = bpy.data.meshes.new("PairedSourceMicroProbe")
        offsets = [(-1, -1), (1, -1), (0, 2)]
        probe_points = [center - source_normal * 1e-5 + (source_tangent * u + source_bitangent * v) * radius for u, v in offsets]
        probe_data.from_pydata(probe_points, [], [(0, 1, 2)])
        stage_uv = probe_data.uv_layers.new(name=a.ATLAS_UV)
        for item, (u, v) in zip(stage_uv.data, offsets):
            item.uv = (8.5 / 16 + u * 0.2, 8.5 / 16 + v * 0.2)
        probe_data.materials.append(low.data.materials[0])
        old_data, low.data = low.data, probe_data
        bpy.data.meshes.remove(old_data)
        probe_data.update()
        # Audit the *actual float32 target* and Blender's exact first ray,
        # not merely the intended double-precision sample center. A tiny
        # triangle's geometric normal can differ after position rounding.
        stage_weights = barycentric(Vector((8.5 / 16, 8.5 / 16, 0)),
                                    *[Vector((*item.uv, 0)) for item in stage_uv.data])
        actual_low = sum((vertex.co * weight for vertex, weight in zip(probe_data.vertices, stage_weights)), Vector())
        actual_normal = probe_data.polygons[0].normal.copy()
        cage_distance, ray_distance = 0.00003, 0.00005
        ray_origin = actual_low + actual_normal * cage_distance
        hit_point, hit_normal, hit_triangle, hit_distance = bvh.ray_cast(ray_origin, -actual_normal, ray_distance)
        row.update(actual_probe_point=list(actual_low), actual_probe_normal=list(actual_normal),
                   actual_ray_origin=list(ray_origin), actual_ray_direction=list(-actual_normal),
                   actual_ray_first_triangle=hit_triangle, actual_ray_length_m=hit_distance,
                   actual_ray_maximum_m=ray_distance, actual_ray_cage_extrusion_m=cage_distance)
        try:
            if hit_point is None or hit_triangle != high_triangle:
                raise ValueError("actual first probe ray did not hit the intended paired source triangle")
            actual_ray_source_distance = (hit_point - low_point).length
            enforce_distance(actual_ray_source_distance)
            hit_weights = barycentric(hit_point, *points)
            if min(hit_weights) <= 0:
                raise ValueError("actual first hit is not strictly inside the intended source triangle")
            row.update(actual_ray_hit_point=list(hit_point), actual_ray_source_barycentric=list(hit_weights),
                       actual_ray_source_distance_m=actual_ray_source_distance, actual_first_hit_gate_passed=True)
        except ValueError as error:
            row["skip"] = str(error)
            bpy.data.objects.remove(low, do_unlink=True)
            bpy.data.meshes.remove(probe_data)
            continue
        stage = {name: a.new_image(f"Probe_{x}_{y}_{name}", 16, (0, 0, 0, 1), srgb=name == "albedo") for name in maps}
        row["bake"] = a.bake_component(high, low, image_node, stage, margin=0, normal_space="OBJECT",
                                      cage_distance_m=cage_distance, ray_distance_m=ray_distance)
        stage_dir = stage_root / f"{int(x)}_{int(y)}"
        stage_dir.mkdir()
        for name, image in stage.items():
            a.save_pack_exact(image, stage_dir / f"{name}.png")
        values = {name: a.pixels(image)[8, 8].copy() for name, image in stage.items()}
        row["actual_probe_coverage"] = float(values["coverage"][0])
        row["actual_probe_hit"] = float(values["hits"][0])
        if values["coverage"][0] < 0.99 or values["hits"][0] + 1e-5 < values["coverage"][0]:
            row["skip"] = "actual same-component material probe missed"
        else:
            world = normalized(tuple((float(value) - 0.5 - NORMAL_ENCODE_BIAS) * 2 for value in values["normal"][:3]))
            target = world_to_tangent(world, tangent, normal, sign)
            values["normal"][:3] = [max(0, min(1, value * 0.5 + 0.5 + NORMAL_ENCODE_BIAS)) for value in target]
            values["hits"] = values["coverage"] = np.array((coverage[y, x],) * 3 + (1,), dtype=np.float32)
            for name, image in maps.items():
                array = a.pixels(image)
                array[y, x] = values[name]
                a.set_pixels(image, array)
            row.update(passed=True, source_shading_normal=list(world), target_tangent_normal=list(target))
        bpy.data.objects.remove(low, do_unlink=True)
        bpy.data.meshes.remove(probe_data)
        for image in stage.values():
            bpy.data.images.remove(image)
    after = {name: hashlib.sha256(a.pixels(image)[untouched].tobytes()).hexdigest() for name, image in maps.items()}
    report = {"method": "paired_high_actual_material_microprobe", "source_distance_cap_m": MAX_SOURCE_DISTANCE_M,
              "normal_conversion": "Blender5.2 bake.cc928-956 inverse interpolated TBN, mirrored sign preserved",
              "attempted": len(rows), "passed": sum(row["passed"] for row in rows), "rows": rows,
              "actual_first_ray_source_gate_passed": all(row.get("actual_first_hit_gate_passed", False) for row in rows),
              "original_valid_pixels_exactly_unchanged": before == after, "valid_map_hashes": before}
    (output / "nearest_source_projection.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    if before != after:
        raise RuntimeError("nearest-source projection modified a valid baseline pixel")
    return report
