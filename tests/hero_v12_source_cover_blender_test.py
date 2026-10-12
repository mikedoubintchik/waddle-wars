"""Read-only actual saved-source/candidate geometry regression; no renderer.

Run in Blender5.2 with --source --candidate-dir --baseline-dir --report.
This tests real first-hit geometry, not paint/material guesses or screenshots.
"""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def geometry(points, triangles):
    return {"points": [Vector(point) for point in points], "triangles": triangles,
            "bvh": BVHTree.FromPolygons(points, triangles, all_triangles=True)}


def surface_metrics(item, source=None):
    area, volume, maximum = 0.0, 0.0, 0.0
    edges = {}
    for triangle in item["triangles"]:
        a, b, c = (item["points"][index] for index in triangle)
        area += (b-a).cross(c-a).length*.5
        volume += a.dot(b.cross(c))/6
        for first, second in zip(triangle, triangle[1:]+triangle[:1]):
            edge = tuple(sorted((first, second)))
            edges[edge] = edges.get(edge, 0)+1
        if source:
            maximum = max(maximum, *(source["bvh"].find_nearest(point)[3]
                                    for point in (a, b, c, (a+b+c)/3)))
    return {"triangles": len(item["triangles"]), "area_m2": area, "signed_volume_m3": volume,
            "nonmanifold_edges": sum(count != 2 for count in edges.values()),
            "vertex_and_triangle_center_max_source_distance_m": maximum if source else None}


def triangle_identity(item):
    result = Counter()
    for triangle in item["triangles"]:
        values = tuple(tuple(item["points"][index]) for index in triangle)
        result[min(values[i:]+values[:i] for i in range(3))] += 1
    return result


def source_snapshot(path):
    bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False)
    parts = {}
    for obj in bpy.data.objects:
        if obj.type != "MESH" or obj.name == "NeutralGrayFloor":
            continue
        obj.data.calc_loop_triangles()
        points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
        points = [(point.x, -point.y, point.z) for point in points]
        triangles = [tuple(reversed(triangle.vertices)) for triangle in obj.data.loop_triangles]
        parts[obj.name] = geometry(points, triangles)
    return parts


def candidate_snapshot(directory, lod):
    audit = json.loads((directory / "candidate_audit.json").read_text())
    path = directory / "hero_penguin_v12_candidate.blend"
    if digest(path) != audit["outputs"][path.name]:
        raise RuntimeError("candidate input binding mismatch")
    bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False)
    mesh = bpy.data.objects["HeroPenguinMesh" if lod == 0 else "HeroPenguinLOD1"].data
    mesh.calc_loop_triangles()
    points = [vertex.co.copy() for vertex in mesh.vertices]
    triangles = [tuple(triangle.vertices) for triangle in mesh.loop_triangles]
    owners = [row["source"] for row in audit["components"] if row["lod"] == lod for _ in range(row["after"])]
    assert len(owners) == len(triangles)
    assert all(mesh.loop_triangles[i].polygon_index <= mesh.loop_triangles[i+1].polygon_index
               for i in range(len(triangles)-1))
    assert all(owners[i] == owners[i+1] or mesh.loop_triangles[i].polygon_index != mesh.loop_triangles[i+1].polygon_index
               for i in range(len(triangles)-1))
    whole = geometry(points, triangles)
    whole["owners"] = owners
    parts = {name: geometry(points, [triangle for triangle, owner in zip(triangles, owners) if owner == name])
             for name in set(owners)}
    return whole, parts, audit


def rays(source, candidate):
    camera = Vector((0, 4.05, 1.72))
    forward = (Vector((0, 0, .93))-camera).normalized()
    right = Vector((-1, 0, 0))
    up = right.cross(forward)
    scale = math.tan(math.radians(13.5))
    rows = []
    for x in (580, 585, 590, 690, 695, 700):
        y = 97
        direction = (forward+right*((x/1280*2-1)*(1280/720)*scale)
                     +up*((1-y/720*2)*scale)).normalized()
        high = sorted((hit[3], name, hit[0]) for name, item in source.items()
                      if (hit := item["bvh"].ray_cast(camera, direction))[0] is not None)
        low = candidate["bvh"].ray_cast(camera, direction)
        assert high and low[0] is not None
        high_distance, high_owner, high_position = high[0]
        low_owner = candidate["owners"][low[2]]
        rows.append({"pixel_xy": [x, y], "source_first_component": high_owner,
                     "candidate_first_component": low_owner,
                     "source_distance_m": high_distance, "candidate_distance_m": low[3],
                     "hit_position_distance_m": (high_position-low[0]).length,
                     "passed": high_owner.startswith("HeroBody") and low_owner == high_owner
                               and (high_position-low[0]).length <= .00025})
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--candidate-dir", type=Path, required=True)
    parser.add_argument("--baseline-dir", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    assert tuple(bpy.app.version[:3]) == (5, 2, 0)
    inputs = [args.source, args.candidate_dir / "hero_penguin_v12_candidate.blend",
              args.candidate_dir / "candidate_audit.json", args.baseline_dir / "hero_penguin_v12_candidate.blend",
              args.baseline_dir / "candidate_audit.json"]
    before = {str(path.resolve()): digest(path) for path in inputs}
    source = source_snapshot(args.source)
    source_mouth = surface_metrics(source["BillMouthSeam"])
    baseline, baseline_parts, _ = candidate_snapshot(args.baseline_dir, 0)
    baseline_rays = rays(source, baseline)
    baseline_mouth = surface_metrics(baseline_parts["BillMouthSeam"], source["BillMouthSeam"])
    baseline_parts_by_lod = {0: baseline_parts}
    _baseline_far, baseline_parts_by_lod[1], _ = candidate_snapshot(args.baseline_dir, 1)
    errors, results = [], []
    for lod in (0, 1):
        whole, parts, audit = candidate_snapshot(args.candidate_dir, lod)
        if audit["source_sha256"] != before[str(args.source.resolve())]:
            errors.append("candidate binds a different source")
        samples = rays(source, whole)
        mouth = surface_metrics(parts["BillMouthSeam"], source["BillMouthSeam"])
        mouth["source_area_ratio"] = mouth["area_m2"]/source_mouth["area_m2"]
        mouth["source_volume_ratio"] = mouth["signed_volume_m3"]/source_mouth["signed_volume_m3"]
        mouth["exact_baseline_oriented_triangle_multiset"] = (
            triangle_identity(parts["BillMouthSeam"]) == triangle_identity(baseline_parts_by_lod[lod]["BillMouthSeam"]))
        passed = all(row["passed"] for row in samples)
        if not passed:
            errors.append(f"LOD{lod} source-cover first-hit geometry differs")
        # Low quad strips may be less curved; require closed surface, same
        # volume orientation, >=95% source area and >=90% enclosed volume.
        # Distance is measured, not disguised as a projection acceptance gate.
        if not (mouth["nonmanifold_edges"] == 0 and .95 <= mouth["source_area_ratio"] <= 1.05
                and .90 <= mouth["source_volume_ratio"] <= 1.10):
            errors.append(f"LOD{lod} thin mouth lost surface/volume/closed topology")
        if audit["geometry_policy"] == "source-cover-v2" and not mouth["exact_baseline_oriented_triangle_multiset"]:
            errors.append(f"LOD{lod} original mouth was not preserved exactly")
        baseline_distance = surface_metrics(baseline_parts_by_lod[lod]["BillMouthSeam"], source["BillMouthSeam"])[
            "vertex_and_triangle_center_max_source_distance_m"]
        if mouth["vertex_and_triangle_center_max_source_distance_m"] > baseline_distance + 1e-7:
            errors.append(f"LOD{lod} mouth source-distance regressed versus original reduction")
        results.append({"lod": lod, "rays": samples, "mouth": mouth})
    if not (all(not row["passed"] for row in baseline_rays)
            and all(row["candidate_first_component"] == "EmbeddedSclera-1" for row in baseline_rays if row["pixel_xy"][0] >= 690)):
        errors.append("baseline did not reproduce three sclera hits plus mirrored cover deviations")
    if before != {str(path.resolve()): digest(path) for path in inputs}:
        errors.append("read-only input changed")
    report = {"passed": not errors, "errors": errors, "inputs": before,
              "script_sha256": digest(__file__), "command": sys.argv,
              "source_saved": False, "rendered": False, "source_mouth": source_mouth,
              "baseline_rays": baseline_rays, "baseline_mouth": baseline_mouth,
              "results": results,
              "omissions": ["Six fixed first-hit rays, not full-view pixel/silhouette acceptance.",
                            "Quad-mouth area/volume and point distances do not prove atlas projection coverage.",
                            "No rig deformation, renderer, runtime-material or performance approval."]}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps({"passed": not errors, "errors": errors, "results": results}, indent=2))
    if errors:
        raise RuntimeError("source-cover geometry regression failed")


if __name__ == "__main__":
    main()
