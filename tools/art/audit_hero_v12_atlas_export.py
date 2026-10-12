#!/usr/bin/env python3
"""Read-only, stdlib-only parity gate for the two actual V12 GLB exports.

Atlas seams may duplicate/reindex vertices and repartition material primitives.
Compare an oriented triangle multiset of position, named-joint normalized weights,
and eight named POSITION morph deltas instead of comparing accessor byte layouts.
Float32 re-export/weight normalization may round; every compared component must
remain within the reported tolerance (never greater than 1e-6). This is not a
texture, normal, tangent, visual-fidelity, or renderer-performance acceptance gate.
"""

import argparse
from collections import Counter, defaultdict
import hashlib
from itertools import product
import json
import math
from pathlib import Path
import struct


MORPHS = (
    "species_emperor", "species_king", "species_adelie", "species_gentoo",
    "species_chinstrap", "species_rockhopper", "species_macaroni", "species_little_blue",
)
CLIPS = (
    "celebration", "countdown_idle", "defeat", "fidget", "hit_left", "hit_right",
    "jump_air", "jump_land", "jump_takeoff", "lean_left", "lean_right", "ramp_flip",
    "ramp_land", "ramp_launch", "recover", "run", "shove", "slide_enter",
    "slide_exit", "slide_loop", "stumble", "swim", "wipeout",
)
SOCKETS = ("head_socket", "face_socket", "neck_socket", "trail_socket")
COMPONENTS = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
              5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
OMISSIONS = [
    "UVs, materials, textures, COLOR and custom attributes are intentionally not compared.",
    "Base/morph normals and tangents are intentionally not compared; their parity is not proven.",
    "Vertex/accessor/primitive order and seam duplication are intentionally not compared.",
    "Unreferenced vertex payloads, cameras, lights, extras and scene names are not compared.",
    "No rendered appearance, collision, deformation sampling or performance acceptance is implied.",
]


class AuditError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise AuditError(message)


def finite(values, label):
    require(all(isinstance(v, (int, float)) and math.isfinite(v) for v in values),
            f"{label}: non-finite or non-numeric component")
    return tuple(values)


class Glb:
    """Small strict reader: uncompressed, one embedded buffer, dense or sparse."""

    def __init__(self, path):
        self.path = Path(path)
        data = self.path.read_bytes()
        self.sha256 = hashlib.sha256(data).hexdigest()
        require(len(data) >= 20, "truncated GLB")
        magic, version, length = struct.unpack_from("<4sII", data)
        require(magic == b"glTF" and version == 2 and length == len(data), "invalid GLB v2 header")
        chunks = []
        offset = 12
        while offset < len(data):
            require(offset + 8 <= len(data), "truncated GLB chunk header")
            size, kind = struct.unpack_from("<II", data, offset)
            offset += 8
            require(size % 4 == 0 and offset + size <= len(data), "invalid GLB chunk bounds")
            chunks.append((kind, data[offset:offset + size]))
            offset += size
        require(len(chunks) == 2 and [c[0] for c in chunks] == [0x4E4F534A, 0x004E4942],
                "unsupported GLB chunks; require JSON then one BIN")
        self.doc = json.loads(chunks[0][1])
        require(self.doc.get("asset", {}).get("version") == "2.0", "require glTF 2.0 asset")
        for extension in set(self.doc.get("extensionsUsed", []) + self.doc.get("extensionsRequired", [])):
            require(extension.startswith("KHR_materials_") or extension == "KHR_texture_transform",
                    f"unsupported extension: {extension}")
        buffers = self.doc.get("buffers", [])
        require(len(buffers) == 1 and "uri" not in buffers[0], "require one embedded buffer")
        size = buffers[0].get("byteLength", -1)
        require(0 <= size <= len(chunks[1][1]) <= size + 3, "invalid BIN buffer length")
        self.binary = chunks[1][1][:size]
        self.cache = {}
        # Validate even intentionally un-compared accessor storage: unsupported
        # formats must not silently turn into zeroes or skip a required payload.
        for index in range(len(self.doc.get("accessors", []))):
            self.accessor(index)
        self.nodes = self.doc.get("nodes", [])
        names = [node.get("name") for node in self.nodes]
        require(all(isinstance(n, str) and n for n in names) and len(set(names)) == len(names),
                "nodes require unique nonempty names")
        self.names = names
        self.parents = {name: None for name in names}
        for node in self.nodes:
            for child in node.get("children", []):
                require(isinstance(child, int) and 0 <= child < len(names), "invalid child node")
                require(self.parents[names[child]] is None, "multiple node parents")
                self.parents[names[child]] = node["name"]
        for name in names:
            seen = set()
            ancestor = name
            while ancestor is not None:
                require(ancestor not in seen, "cyclic node hierarchy")
                seen.add(ancestor)
                ancestor = self.parents[ancestor]

    def accessor(self, index, kind=None, components=None):
        accessors = self.doc.get("accessors", [])
        require(isinstance(index, int) and 0 <= index < len(accessors), f"invalid accessor {index}")
        a = accessors[index]
        require(not a.get("extensions"), f"accessor {index}: extension unsupported")
        require(a.get("type") in WIDTHS and a.get("componentType") in COMPONENTS,
                f"accessor {index}: unsupported format")
        if kind is not None:
            require(a["type"] == kind, f"accessor {index}: expected {kind}")
        if components is not None:
            require(a["componentType"] in components, f"accessor {index}: unsupported component type")
        normalized = a.get("normalized", False)
        require(not normalized or a["componentType"] in (5120, 5121, 5122, 5123),
                f"accessor {index}: unsupported normalized format")
        if index in self.cache:
            return self.cache[index]
        _, size = COMPONENTS[a["componentType"]]
        width = WIDTHS[a["type"]]
        require(a["type"] != "MAT4" or size == 4, "unsupported matrix component alignment")
        count = a.get("count", 0)
        require(isinstance(count, int) and 0 < count <= 10_000_000, f"accessor {index}: invalid count")
        if "bufferView" in a:
            result = self.rows(a["bufferView"], a.get("byteOffset", 0), count, a["componentType"], width)
        else:
            require("sparse" in a and a.get("byteOffset", 0) == 0, f"accessor {index}: missing bufferView")
            result = [(0,) * width] * count
        if "sparse" in a:
            sparse = a["sparse"]
            sparse_count = sparse.get("count", 0)
            require(isinstance(sparse_count, int) and 0 < sparse_count <= count, "invalid sparse count")
            si, sv = sparse.get("indices", {}), sparse.get("values", {})
            component = si.get("componentType")
            require(component in (5121, 5123, 5125), "unsupported sparse index format")
            indices = [v[0] for v in self.rows(si.get("bufferView"), si.get("byteOffset", 0),
                                             sparse_count, component, 1, sparse=True)]
            require(indices[-1] < count and all(a < b for a, b in zip(indices, indices[1:])),
                    "invalid sparse indices: require increasing in-bounds indices")
            values = self.rows(sv.get("bufferView"), sv.get("byteOffset", 0), sparse_count,
                               a["componentType"], width, sparse=True)
            for row, values in zip(indices, values):
                result[row] = values
        if normalized:
            maximum = {5120: 127, 5121: 255, 5122: 32767, 5123: 65535}[a["componentType"]]
            result = [tuple(max(-1.0, v / maximum) for v in row) for row in result]
        self.cache[index] = result
        return result

    def rows(self, vi, start, count, component, width, sparse=False):
        views = self.doc.get("bufferViews", [])
        require(isinstance(vi, int) and 0 <= vi < len(views), "missing bufferView")
        view = views[vi]
        require(view.get("buffer", 0) == 0 and not view.get("extensions"), "unsupported bufferView")
        require(not sparse or "byteStride" not in view, "sparse bufferView must be tightly packed")
        fmt, size = COMPONENTS[component]
        element = width * size
        stride = view.get("byteStride", element)
        view_start = view.get("byteOffset", 0)
        view_size = view.get("byteLength", -1)
        require(start >= 0 and view_start >= 0, "invalid accessor offset")
        require(stride >= element and stride % size == 0 and start % size == 0,
                "invalid accessor stride/alignment")
        require(view_size >= 0 and view_start + view_size <= len(self.binary)
                and start + (count - 1) * stride + element <= view_size,
                "out-of-bounds accessor data")
        unpack = struct.Struct("<" + fmt * width)
        result = []
        for row in range(count):
            values = unpack.unpack_from(self.binary, view_start + start + row * stride)
            result.append(finite(values, "accessor storage"))
        return result


def matrix(node):
    if "matrix" in node:
        require(not any(k in node for k in ("translation", "rotation", "scale")), "matrix and TRS both present")
        result = finite(node["matrix"], "node matrix")
        require(len(result) == 16, "invalid node matrix")
        return result
    t = finite(node.get("translation", (0, 0, 0)), "translation")
    q = finite(node.get("rotation", (0, 0, 0, 1)), "rotation")
    s = finite(node.get("scale", (1, 1, 1)), "scale")
    require(len(t) == 3 and len(q) == 4 and len(s) == 3, "invalid node TRS")
    norm = math.sqrt(sum(v * v for v in q))
    require(abs(norm - 1) <= 1e-4, "non-unit node quaternion")
    x, y, z, w = (v / norm for v in q)
    return ((1 - 2*y*y - 2*z*z)*s[0], (2*x*y + 2*z*w)*s[0], (2*x*z - 2*y*w)*s[0], 0,
            (2*x*y - 2*z*w)*s[1], (1 - 2*x*x - 2*z*z)*s[1], (2*y*z + 2*x*w)*s[1], 0,
            (2*x*z + 2*y*w)*s[2], (2*y*z - 2*x*w)*s[2], (1 - 2*x*x - 2*y*y)*s[2], 0,
            *t, 1)


def close(a, b, metric, report, tolerance):
    require(len(a) == len(b), f"{metric}: component count changed")
    delta = max((abs(x - y) for x, y in zip(a, b)), default=0.0)
    report["measured_max_deltas"][metric] = max(report["measured_max_deltas"].get(metric, 0), delta)
    require(delta <= tolerance, f"{metric}: max component delta {delta:.9g} exceeds {tolerance:g}")


def rig(glb):
    skins = glb.doc.get("skins", [])
    require(len(skins) == 1, "require exactly one skin")
    skin = skins[0]
    joints = skin.get("joints", [])
    require(joints and len(joints) <= 36 and len(set(joints)) == len(joints), "invalid joint list")
    require(all(isinstance(j, int) and 0 <= j < len(glb.nodes) for j in joints), "invalid joint index")
    names = [glb.names[j] for j in joints]
    binds = glb.accessor(skin.get("inverseBindMatrices"), "MAT4", (5126,))
    require(len(binds) == len(names), "inverse-bind count differs from joint count")
    meshes = glb.doc.get("meshes", [])
    instances = [n for n in glb.nodes if "mesh" in n]
    require(len(meshes) == 1 and len(instances) == 1 and instances[0]["mesh"] == 0
            and instances[0].get("skin") == 0, "require one mesh and one skinned instance")
    require(set(SOCKETS) <= set(glb.names), "missing required cosmetic socket")
    roots = []
    for scene in glb.doc.get("scenes", []):
        indices = scene.get("nodes", [])
        require(all(isinstance(i, int) and 0 <= i < len(glb.nodes) for i in indices), "invalid scene node")
        roots.append(tuple(sorted(glb.names[i] for i in indices)))
    require(len(roots) == 1, "require one scene")
    skeleton = skin.get("skeleton")
    require(skeleton is None or isinstance(skeleton, int) and 0 <= skeleton < len(glb.nodes),
            "invalid skin skeleton root")
    return {"joint_order": names, "binds": dict(zip(names, binds)), "scene_roots": roots,
            "skeleton": glb.names[skeleton] if skeleton is not None else None,
            "mesh_node": instances[0]["name"], "skin_name": skin.get("name")}


def geometry(glb, skeleton):
    mesh = glb.doc["meshes"][0]
    morphs = mesh.get("extras", {}).get("targetNames", [])
    require(len(morphs) == 8 and set(morphs) == set(MORPHS), "require eight named species morphs")
    defaults = mesh.get("weights", [0] * 8)
    require(len(defaults) == 8, "invalid default morph weights")
    node = next(n for n in glb.nodes if "mesh" in n)
    require("weights" not in node or len(node["weights"]) == 8, "invalid node morph weights")
    effective = node.get("weights", defaults)
    defaults_by_name = dict(zip(morphs, finite(effective, "default morph weights")))
    joint_order = skeleton["joint_order"]
    joint_slots = {name: i for i, name in enumerate(sorted(joint_order))}
    triangles = []
    stats = {"triangles": 0, "exported_vertices": 0, "unreferenced_vertices": 0,
             "primitives": 0, "morphs": sorted(morphs)}
    require(mesh.get("primitives"), "missing primitives")
    for primitive in mesh["primitives"]:
        require(primitive.get("mode", 4) == 4 and not primitive.get("extensions"), "require uncompressed TRIANGLES")
        attributes = primitive.get("attributes", {})
        require(not any(k.startswith(("JOINTS_", "WEIGHTS_")) and k not in ("JOINTS_0", "WEIGHTS_0")
                        for k in attributes), "more than four skin influences unsupported")
        positions = glb.accessor(attributes.get("POSITION"), "VEC3", (5126,))
        joints = glb.accessor(attributes.get("JOINTS_0"), "VEC4", (5121, 5123))
        weights = glb.accessor(attributes.get("WEIGHTS_0"), "VEC4", (5126, 5121, 5123))
        require(not glb.doc["accessors"][attributes["JOINTS_0"]].get("normalized", False), "normalized JOINTS unsupported")
        require(glb.doc["accessors"][attributes["WEIGHTS_0"]]["componentType"] == 5126
                or glb.doc["accessors"][attributes["WEIGHTS_0"]].get("normalized", False), "integer WEIGHTS must be normalized")
        count = len(positions)
        require(len(joints) == len(weights) == count, "skin/position counts differ")
        targets = primitive.get("targets", [])
        require(len(targets) == 8, "primitive missing species morphs")
        morph_values = {name: glb.accessor(target.get("POSITION"), "VEC3", (5126,))
                        for name, target in zip(morphs, targets)}
        require(all(len(v) == count for v in morph_values.values()), "morph/position counts differ")
        indices = ([row[0] for row in glb.accessor(primitive["indices"], "SCALAR", (5121, 5123, 5125))]
                   if "indices" in primitive else list(range(count)))
        require(len(indices) % 3 == 0 and all(isinstance(i, int) and 0 <= i < count for i in indices),
                "invalid triangle indices")
        payloads = {}
        for index in set(indices):
            assigned = [0.0] * len(joint_order)
            require(all(isinstance(j, int) and 0 <= j < len(joint_order) for j in joints[index]), "invalid vertex joint")
            require(all(0 <= w <= 1 for w in weights[index]), "invalid vertex weight")
            total = sum(weights[index])
            require(total > 0 and abs(total - 1) <= 1e-4, "invalid vertex weight sum")
            for j, w in zip(joints[index], weights[index]):
                assigned[joint_slots[joint_order[j]]] += w / total
            payloads[index] = (*positions[index], *assigned,
                               *(v for name in sorted(MORPHS) for v in morph_values[name][index]))
        triangles.extend(tuple(payloads[i] for i in indices[n:n + 3]) for n in range(0, len(indices), 3))
        stats["primitives"] += 1
        stats["exported_vertices"] += count
        stats["unreferenced_vertices"] += count - len(payloads)
    stats["triangles"] = len(triangles)
    return triangles, stats, tuple(defaults_by_name[n] for n in sorted(MORPHS))


def oriented(ids):
    a, b, c = ids
    return min((a, b, c), (b, c, a), (c, a, b))


def compare_triangles(before, after, joints, report, tolerance):
    require(len(before) == len(after), "triangle count changed")
    payload_ids = {}
    grid = defaultdict(list)
    def cell(payload):
        return tuple(math.floor(v / tolerance) for v in payload[:3])
    for tri in before:
        for payload in tri:
            if payload not in payload_ids:
                payload_ids[payload] = len(payload_ids)
                grid[cell(payload)].append(payload)
    expected = Counter(oriented(tuple(payload_ids[p] for p in tri)) for tri in before)
    cache = {}
    approximate = 0
    for tri in after:
        for payload in tri:
            if payload in cache:
                continue
            match = payload if payload in payload_ids else None
            if match is None:
                origin = cell(payload)
                matches = []
                for delta in product((-1, 0, 1), repeat=3):
                    for other in grid.get(tuple(a + b for a, b in zip(origin, delta)), []):
                        if all(abs(a - b) <= tolerance for a, b in zip(payload, other)):
                            matches.append(other)
                require(len(matches) == 1,
                        f"vertex position/skin/morph payload has {len(matches)} baseline matches; require exactly one")
                match = matches[0]
                approximate += 1
            close(payload[:3], match[:3], "position", report, tolerance)
            close(payload[3:3 + joints], match[3:3 + joints], "normalized_skin_weight", report, tolerance)
            close(payload[3 + joints:], match[3 + joints:], "morph_position_delta", report, tolerance)
            cache[payload] = payload_ids[match]
    actual = Counter(oriented(tuple(cache[p] for p in tri)) for tri in after)
    missing = sum((expected - actual).values())
    added = sum((actual - expected).values())
    report["triangle_multiset"] = {"baseline_unique_payloads": len(payload_ids),
                                   "candidate_unique_payloads": len(cache),
                                   "tolerance_matched_payloads": approximate,
                                   "missing_oriented_triangles": missing, "added_oriented_triangles": added}
    require(expected == actual, f"oriented triangle multiset changed: {missing} missing, {added} added")


def animations(glb):
    result = {}
    for animation in glb.doc.get("animations", []):
        name = animation.get("name")
        require(name in CLIPS and name not in result, "missing, duplicate or unexpected clip name")
        channels = {}
        samplers = animation.get("samplers", [])
        for channel in animation.get("channels", []):
            target = channel.get("target", {})
            node = target.get("node")
            require(isinstance(node, int) and 0 <= node < len(glb.nodes), "invalid animation target")
            path = target.get("path")
            require(path in ("translation", "rotation", "scale", "weights") and not target.get("extensions"),
                    "unsupported animation target")
            key = (glb.names[node], path)
            require(key not in channels, "duplicate animation target channel")
            si = channel.get("sampler")
            require(isinstance(si, int) and 0 <= si < len(samplers), "invalid animation sampler")
            sampler = samplers[si]
            interpolation = sampler.get("interpolation", "LINEAR")
            require(interpolation in ("LINEAR", "STEP"), f"unsupported animation interpolation: {interpolation}")
            times = [v[0] for v in glb.accessor(sampler.get("input"), "SCALAR", (5126,))]
            require(times[0] >= 0 and all(a < b for a, b in zip(times, times[1:])), "invalid animation sample times")
            kind = "VEC4" if path == "rotation" else "SCALAR" if path == "weights" else "VEC3"
            values = glb.accessor(sampler.get("output"), kind, (5126,))
            if path == "weights":
                require(glb.nodes[node].get("mesh") == 0 and len(values) == len(times) * 8,
                        "invalid animation morph output")
                names = glb.doc["meshes"][0].get("extras", {}).get("targetNames", [])
                require(len(names) == 8 and set(names) == set(MORPHS), "invalid animated morph names")
                values = [tuple(values[i + names.index(n)][0] for n in sorted(MORPHS))
                          for i in range(0, len(values), 8)]
            require(len(values) == len(times), "animation output/sample count differs")
            if path == "rotation":
                require(all(abs(sum(v*v for v in q) - 1) <= 2e-4 for q in values), "non-unit animation quaternion")
            channels[key] = (interpolation, times, values)
        require(channels, "empty animation")
        result[name] = channels
    require(set(result) == set(CLIPS), "23-clip library changed or missing")
    return result


def audit(baseline, candidate, tolerance=1e-6):
    report = {"schema_version": 1, "passed": False, "baseline": {"path": str(Path(baseline).resolve())},
              "candidate": {"path": str(Path(candidate).resolve())}, "tolerance": tolerance,
              "tolerance_reason": "Float32 re-export and per-vertex weight normalization rounding; absolute component bound.",
              "measured_max_deltas": {}, "omissions": OMISSIONS, "errors": []}
    try:
        require(math.isfinite(tolerance) and 0 < tolerance <= 1e-6, "tolerance must be >0 and <=1e-6")
        for side, path in (("baseline", baseline), ("candidate", candidate)):
            report[side]["sha256"] = hashlib.sha256(Path(path).read_bytes()).hexdigest()
        a, b = Glb(baseline), Glb(candidate)
        ra, rb = rig(a), rig(b)
        require(set(a.names) == set(b.names), "node names changed")
        require(a.parents == b.parents, "node/joint/socket hierarchy changed")
        for key in ("scene_roots", "skeleton", "mesh_node", "skin_name"):
            require(ra[key] == rb[key], f"rig {key} changed")
        require(set(ra["binds"]) == set(rb["binds"]), "joint names changed")
        b_nodes = {n["name"]: n for n in b.nodes}
        for node in a.nodes:
            close(matrix(node), matrix(b_nodes[node["name"]]), "node_rest_matrix", report, tolerance)
        for joint in ra["binds"]:
            close(ra["binds"][joint], rb["binds"][joint], "inverse_bind_matrix", report, tolerance)
        report["rig"] = {"joints": sorted(ra["binds"]), "joint_count": len(ra["binds"]),
                         "nodes": len(a.nodes), "sockets": sorted(SOCKETS)}
        ta, sa, wa = geometry(a, ra)
        tb, sb, wb = geometry(b, rb)
        report["baseline"]["geometry"] = sa
        report["candidate"]["geometry"] = sb
        close(wa, wb, "default_morph_weight", report, tolerance)
        compare_triangles(ta, tb, len(ra["binds"]), report, tolerance)
        aa, ab = animations(a), animations(b)
        samples = channels = 0
        for clip in sorted(aa):
            require(aa[clip].keys() == ab[clip].keys(), f"{clip}: animation channels changed")
            for key, (interpolation, times, values) in aa[clip].items():
                other_interpolation, other_times, other_values = ab[clip][key]
                require(interpolation == other_interpolation, f"{clip}/{key}: interpolation changed")
                close(times, other_times, "animation_sample_time", report, tolerance)
                require(len(values) == len(other_values), f"{clip}/{key}: sample count changed")
                for value, other in zip(values, other_values):
                    if key[1] == "rotation" and sum(x*y for x, y in zip(value, other)) < 0:
                        other = tuple(-v for v in other)  # q and -q encode the same rotation.
                    close(value, other, "animation_" + key[1], report, tolerance)
                samples += len(times)
                channels += 1
        report["animations"] = {"clips": sorted(aa), "clip_count": len(aa), "channels": channels, "samples": samples}
        report["passed"] = True
    except (AuditError, OSError, ValueError, KeyError, TypeError, struct.error, OverflowError) as error:
        report["errors"].append(str(error))
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--tolerance", type=float, default=1e-6)
    parser.add_argument("--output", type=Path, help="Optional explicit audit JSON destination")
    args = parser.parse_args()
    report = audit(args.baseline, args.candidate, args.tolerance)
    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(rendered)
    print(rendered, end="")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
