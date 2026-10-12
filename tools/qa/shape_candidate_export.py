"""Prepare an explicitly unrigged rear-shape candidate in an isolated QA copy.

This gate preserves the actual runner camera/course and imported plain PBR.
It does not satisfy, bypass, or modify the complete authored-character gate.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import re
import struct

IMPORTER = '''[remap]
importer="scene"
type="PackedScene"

[params]
nodes/use_name_suffixes=false
nodes/use_node_type_suffixes=false
nodes/apply_root_scale=true
nodes/root_scale=1.0
meshes/ensure_tangents=true
meshes/generate_lods=false
meshes/create_shadow_meshes=false
animation/import=false
animation/import_rest_as_RESET=false
gltf/embedded_image_handling=1
'''


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


SURFACE_CONTRACT = "rear-surface-pbr-v1"
SURFACE_IMPORTER = IMPORTER.replace("gltf/embedded_image_handling=1", 'gltf/embedded_image_handling=3\nimport_script/path="res://qa_shape/surface_post_import.gd"')
V9_SHA = "94f30dc898acb8abb85230ddad569e8e9530e8fca9bfe84a05a2ac8a34732fd1"


def importer_for(binding: dict) -> str:
    return SURFACE_IMPORTER if binding.get("material_contract") == SURFACE_CONTRACT else IMPORTER


def glb_data(glb: bytes) -> tuple[dict, bytes]:
    if len(glb) < 20 or struct.unpack_from("<4sII", glb) != (b"glTF", 2, len(glb)):
        raise ValueError("Surface model must be a complete glTF 2 GLB")
    chunks, offset = [], 12
    while offset < len(glb):
        if offset + 8 > len(glb):
            raise ValueError("Truncated GLB chunk")
        size, kind = struct.unpack_from("<II", glb, offset)
        if size % 4 or offset + 8 + size > len(glb):
            raise ValueError("Invalid GLB chunk length")
        chunks.append((kind, glb[offset + 8:offset + 8 + size])); offset += 8 + size
    if [kind for kind, _ in chunks] != [0x4E4F534A, 0x004E4942]:
        raise ValueError("Surface GLB requires exactly JSON and embedded BIN chunks")
    return json.loads(chunks[0][1]), chunks[1][1]


def accessor_values(doc: dict, binary: bytes, index: int) -> list:
    try:
        a = doc["accessors"][index]
        fmt, size = {5126: ("f", 4), 5125: ("I", 4), 5123: ("H", 2)}[a["componentType"]]
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        view = doc["bufferViews"][a["bufferView"]]
        if a.get("sparse") or a.get("normalized") or view.get("buffer", 0) != 0 or a["count"] <= 0:
            raise ValueError("Unsupported accessor")
        stride = view.get("byteStride", size * width)
        start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        end = start + (a["count"] - 1) * stride + size * width
        if stride < size * width or end > min(len(binary), view.get("byteOffset", 0) + view["byteLength"]):
            raise ValueError("Accessor exceeds embedded buffer")
        rows = [struct.unpack_from("<" + fmt * width, binary, start + n * stride) for n in range(a["count"])]
        if not all(math.isfinite(x) for row in rows for x in row):
            raise ValueError("Nonfinite surface geometry")
        return rows
    except (KeyError, IndexError, TypeError, struct.error) as error:
        raise ValueError("Malformed surface accessor") from error


def geometry_signature(doc: dict, binary: bytes) -> str:
    nodes = doc.get("nodes", [])
    if len(nodes) != 1 or nodes[0].get("mesh") != 0 or nodes[0].get("children") \
            or nodes[0].get("translation", [0, 0, 0]) != [0, 0, 0] \
            or nodes[0].get("rotation", [0, 0, 0, 1]) != [0, 0, 0, 1] \
            or nodes[0].get("scale", [1, 1, 1]) != [1, 1, 1] or "matrix" in nodes[0] \
            or len(doc.get("meshes", [])) != 1 or len(doc["meshes"][0]["primitives"]) != 1:
        raise ValueError("Surface gate requires one identity-root mesh/surface")
    primitive = doc["meshes"][0]["primitives"][0]
    positions = accessor_values(doc, binary, primitive["attributes"]["POSITION"])
    normals = accessor_values(doc, binary, primitive["attributes"]["NORMAL"])
    indices = [row[0] for row in accessor_values(doc, binary, primitive["indices"])]
    if len(positions) != len(normals) or len(indices) % 3 or any(type(i) is not int or not 0 <= i < len(positions) for i in indices):
        raise ValueError("Invalid surface triangle topology")
    vertices = [tuple(round(v * 1000000) for v in p + n) for p, n in zip(positions, normals)]
    triangles = []
    for i in range(0, len(indices), 3):
        triangle = tuple(vertices[index] for index in indices[i:i + 3])
        triangles.append(min(triangle, triangle[1:] + triangle[:1], triangle[2:] + triangle[:2]))
    return digest(json.dumps(sorted(triangles), separators=(",", ":")).encode())


def png_rgba(data: bytes) -> tuple[int, int, bytes]:
    """Bounded PNG8 RGB/RGBA decoder; hash canonical texels independently of Godot."""
    import zlib
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Surface maps must be embedded PNG")
    offset, idat, header, ended = 8, bytearray(), None, False
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError("Truncated PNG")
        size = struct.unpack_from(">I", data, offset)[0]
        kind, payload = data[offset + 4:offset + 8], data[offset + 8:offset + 8 + size]
        if offset + size + 12 > len(data) or zlib.crc32(kind + payload) != struct.unpack_from(">I", data, offset + size + 8)[0]:
            raise ValueError("PNG chunk checksum mismatch")
        if kind == b"IHDR":
            if header is not None or size != 13:
                raise ValueError("Invalid PNG header")
            header = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT": idat.extend(payload)
        elif kind == b"IEND": ended = True
        offset += size + 12
    if header is None or not ended:
        raise ValueError("Incomplete PNG")
    w, h, bits, color, compression, filtering, interlace = header
    if not 1 <= w <= 4096 or not 1 <= h <= 4096 or bits != 8 or color not in (2, 6) or compression or filtering or interlace:
        raise ValueError("Surface maps require noninterlaced RGB/RGBA8, up to4096")
    channels = 3 if color == 2 else 4; stride = w * channels
    decoder = zlib.decompressobj(); raw = decoder.decompress(bytes(idat), (stride + 1) * h + 1)
    if len(raw) != (stride + 1) * h or not decoder.eof:
        raise ValueError("PNG pixel data size mismatch")
    previous = bytearray(stride); output = bytearray()
    for y in range(h):
        start = y * (stride + 1); filter_type = raw[start]; row = bytearray(raw[start + 1:start + 1 + stride])
        if filter_type not in range(5): raise ValueError("Invalid PNG filter")
        for x in range(stride):
            a = row[x - channels] if x >= channels else 0; b = previous[x]; c = previous[x - channels] if x >= channels else 0
            if filter_type == 1: prediction = a
            elif filter_type == 2: prediction = b
            elif filter_type == 3: prediction = (a + b) // 2
            elif filter_type == 4:
                p = a + b - c; distances = (abs(p - a), abs(p - b), abs(p - c)); prediction = (a, b, c)[distances.index(min(distances))]
            else: prediction = 0
            row[x] = (row[x] + prediction) & 255
        if channels == 4: output.extend(row)
        else:
            for x in range(0, stride, 3): output.extend(row[x:x + 3]); output.append(255)
        previous = row
    return w, h, bytes(output)


B21_SHA = "b21ca5327a7798b31b1b5b7aa098a4452c623db2c95044244aa490fb72fc7484"
LOCAL_GEOMETRY_CONTRACT = "tail-flippers-only-v1"
PART_RANGES = {"continuous_body_head": [0, 2258], "flipper_L": [2258, 2740],
               "flipper_R": [2740, 3222], "foot_L": [3222, 5144],
               "foot_R": [5144, 7066], "short_tail_fan": [7066, 7372]}
PROTECTED_PARTS = {"continuous_body_head", "foot_L", "foot_R"}
ATLAS_RECTS = {"continuous_body_head": [8, 8, 632, 1016], "flipper_L": [648, 520, 816, 1016],
               "flipper_R": [832, 520, 1000, 1016], "foot_L": [648, 264, 816, 504],
               "foot_R": [832, 264, 1000, 504], "tail_top": [648, 136, 816, 248],
               "tail_bottom": [832, 136, 1000, 248], "tail_edge": [648, 8, 1000, 120]}


def surface_components(doc: dict, binary: bytes) -> dict:
    """Independently label closed welded components; never trust candidate ranges."""
    geometry_signature(doc, binary)  # Identity root, primitive and index validation.
    primitive = doc["meshes"][0]["primitives"][0]; attrs = primitive["attributes"]
    positions = accessor_values(doc, binary, attrs["POSITION"])
    normals = accessor_values(doc, binary, attrs["NORMAL"])
    uv = accessor_values(doc, binary, attrs["TEXCOORD_0"])
    tangents = accessor_values(doc, binary, attrs["TANGENT"])
    if any(len(row) != 3 for row in positions + normals) or len(uv) != len(positions) or any(len(row) != 2 for row in uv):
        raise ValueError("Scoped geometry requires float3 positions/normals and float2 UV")
    if len(tangents) != len(positions) or any(len(row) != 4 for row in tangents):
        raise ValueError("Scoped geometry tangent frame mismatch")
    if any(abs(sum(v*v for v in row) - 1) > .002 for row in normals):
        raise ValueError("Scoped geometry normals must remain unit length")
    indices = [row[0] for row in accessor_values(doc, binary, primitive["indices"])]
    if set(indices) != set(range(len(positions))):
        raise ValueError("Scoped geometry has unreferenced vertices")
    unique, inverse = {}, []
    for p in positions:
        if p not in unique: unique[p] = len(unique)
        inverse.append(unique[p])
    parent = list(range(len(unique)))
    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]; i = parent[i]
        return i
    triangles, edges, faces = [], {}, set()
    for i in range(0, len(indices), 3):
        tri = indices[i:i+3]; welded = tuple(inverse[j] for j in tri)
        key = tuple(sorted(welded))
        if len(set(welded)) != 3 or key in faces:
            raise ValueError("Scoped geometry has degenerate or duplicate triangles")
        faces.add(key)
        a, b, c = [positions[j] for j in tri]
        ab, ac = [b[k]-a[k] for k in range(3)], [c[k]-a[k] for k in range(3)]
        cross = [ab[1]*ac[2]-ab[2]*ac[1], ab[2]*ac[0]-ab[0]*ac[2], ab[0]*ac[1]-ab[1]*ac[0]]
        if sum(v*v for v in cross) <= 1e-24:
            raise ValueError("Scoped geometry has zero-area triangles")
        for u, v in [(welded[0], welded[1]), (welded[1], welded[2]), (welded[2], welded[0])]:
            key = min(u,v), max(u,v); counts = edges.setdefault(key, [0,0]); counts[0] += 1; counts[1] += 1 if u < v else -1
            parent[root(v)] = root(u)
        triangles.append(tri)
    if any(count != 2 or direction != 0 for count, direction in edges.values()):
        raise ValueError("Scoped geometry must remain closed with consistent winding")
    groups = {}
    for p, index in unique.items(): groups.setdefault(root(index), []).append(p)
    result = {}
    for group_id, points in groups.items():
        choices = [name for name, (start,end) in PART_RANGES.items() if len(points) == end-start
                   and (not name.endswith('_L') or sum(p[0] for p in points) < 0)
                   and (not name.endswith('_R') or sum(p[0] for p in points) > 0)]
        if len(choices) != 1 or choices[0] in result:
            raise ValueError("Scoped geometry component count/side is ambiguous")
        name = choices[0]; records, uv_records = [], []
        for tri in triangles:
            if root(inverse[tri[0]]) != group_id: continue
            vertices = [struct.pack('<12f', *(positions[j]+normals[j]+uv[j]+tangents[j])) for j in tri]
            uv_vertices = [struct.pack('<2f', *uv[j]) for j in tri]
            records.append(min(b''.join(vertices[n:]+vertices[:n]) for n in range(3)))
            uv_records.append(min(b''.join(uv_vertices[n:]+uv_vertices[:n]) for n in range(3)))
        result[name] = {"unique_positions": len(points), "triangles": len(records),
                        "position_normal_uv_tangent_sha256": digest(b''.join(sorted(records))),
                        "oriented_uv_triangles_sha256": digest(b''.join(sorted(uv_records))),
                        "bounds_min": [min(p[k] for p in points) for k in range(3)],
                        "bounds_max": [max(p[k] for p in points) for k in range(3)]}
    if set(result) != set(PART_RANGES): raise ValueError("Scoped geometry requires all six baseline components")
    return result


def validate_local_geometry(doc: dict, binary: bytes, before_doc: dict, before_binary: bytes, metadata: dict) -> dict:
    if metadata.get("geometry_contract") != LOCAL_GEOMETRY_CONTRACT or metadata.get("parts_vertex_ranges") != PART_RANGES:
        raise ValueError("Scoped geometry contract/ranges must be explicit and unchanged")
    current, baseline = surface_components(doc, binary), surface_components(before_doc, before_binary)
    for name in PART_RANGES:
        after, before = current[name], baseline[name]
        if after["triangles"] != before["triangles"] or after["oriented_uv_triangles_sha256"] != before["oriented_uv_triangles_sha256"]:
            raise ValueError("Scoped component triangle/UV topology changed: " + name)
        if name in PROTECTED_PARTS and after["position_normal_uv_tangent_sha256"] != before["position_normal_uv_tangent_sha256"]:
            raise ValueError("Protected body/feet positions, normals, UV or tangents changed: " + name)
    source_height = max(v["bounds_max"][1] for v in current.values()) - min(v["bounds_min"][1] for v in current.values())
    if abs(source_height - 1.6931614875793457) > 1e-7 or abs(metadata.get("source_height_m", 0) - source_height) > 1e-7:
        raise ValueError("Scoped edit changed the preserved source height")
    return {"contract": LOCAL_GEOMETRY_CONTRACT, "protected_parts": sorted(PROTECTED_PARTS),
            "editable_parts": sorted(set(PART_RANGES)-PROTECTED_PARTS), "components": current,
            "baseline_components": baseline, "policy": "Exact float32 protected POSITION/NORMAL/UV/TANGENT oriented triangles; closed six-component mesh and unchanged UV triangle topology"}


def validate_protected_pixels(doc, binary, before_doc, before_binary, metadata, maps):
    if metadata.get("atlas", {}).get("size") != 1024 or metadata["atlas"].get("rectangles") != ATLAS_RECTS:
        raise ValueError("Scoped surface edit must retain baseline atlas layout")
    old_mat = before_doc["materials"][0]; old_pbr = old_mat["pbrMetallicRoughness"]
    slots = {"base_color": old_pbr["baseColorTexture"], "normal": old_mat["normalTexture"], "metallic_roughness": old_pbr["metallicRoughnessTexture"]}
    def pixels(document, buffer, image_index):
        image = document["images"][image_index]; view = document["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset",0); w,h,data = png_rgba(buffer[start:start+view["byteLength"]])
        if (w,h) != (1024,1024): raise ValueError("Scoped surface atlas dimensions changed")
        return data
    proof = {}
    for name, source in slots.items():
        old_index = before_doc["textures"][source["index"]]["source"]
        before = pixels(before_doc,before_binary,old_index); after = pixels(doc,binary,maps[name]["image_index"])
        proof[name] = {}
        for part in sorted(PROTECTED_PARTS):
            x0,y0,x1,y1 = ATLAS_RECTS[part]
            old = b''.join(before[(y*1024+x0)*4:(y*1024+x1)*4] for y in range(1024-y1,1024-y0))
            new = b''.join(after[(y*1024+x0)*4:(y*1024+x1)*4] for y in range(1024-y1,1024-y0))
            if old != new: raise ValueError("Protected body/feet map pixels changed: " + name + "/" + part)
            proof[name][part] = digest(new)
    return proof


def validate_surface(doc: dict, binary: bytes, metadata: dict, reference: Path | None = None) -> dict:
    if doc.get("extensionsUsed") or doc.get("extensionsRequired") or any("uri" in b for b in doc.get("buffers", [])):
        raise ValueError("Surface gate forbids extensions and external resources")
    signature = geometry_signature(doc, binary)
    baseline = metadata.get("geometry_reference", {})
    localized = metadata.get("gate") == "rear-surface-v2"
    wanted_sha = B21_SHA if localized else V9_SHA
    wanted_path = "art_src/characters/penguin_rear_surface_v1/candidate.glb" if localized else "art_src/characters/penguin_rear_blockout_v1/candidate.glb"
    if baseline.get("glb_sha256") != wanted_sha or baseline.get("path") != wanted_path:
        raise ValueError("Surface geometry must explicitly bind " + ("b21 localized baseline" if localized else "unchanged V9"))
    reference = reference or Path(__file__).resolve().parents[2] / baseline["path"]
    reference_bytes = reference.read_bytes()
    if digest(reference_bytes) != wanted_sha:
        raise ValueError("Surface geometry reference changed")
    before_doc, before_binary = glb_data(reference_bytes)
    scoped = validate_local_geometry(doc, binary, before_doc, before_binary, metadata) if localized else None
    if not localized and geometry_signature(before_doc, before_binary) != signature:
        raise ValueError("Surface pass changed V9 positions, normals or triangle topology")
    primitive = doc["meshes"][0]["primitives"][0]; attrs = primitive["attributes"]
    if not {"POSITION", "NORMAL", "TANGENT", "TEXCOORD_0"}.issubset(attrs):
        raise ValueError("Surface requires exported normals, tangents and UV0")
    count = len(accessor_values(doc, binary, attrs["POSITION"]))
    for name, kind in [("TANGENT", "VEC4"), ("TEXCOORD_0", "VEC2")]:
        accessor = doc["accessors"][attrs[name]]
        if accessor.get("type") != kind or accessor.get("componentType") != 5126:
            raise ValueError("Surface UV/tangent accessor format mismatch")
        if len(accessor_values(doc, binary, attrs[name])) != count:
            raise ValueError("Surface UV/tangent count mismatch")
    if "COLOR_0" in attrs and any(any(abs(c - 1) > 1e-6 for c in row) for row in accessor_values(doc, binary, attrs["COLOR_0"])):
        raise ValueError("Surface paint cannot be multiplied by nonwhite vertex colors")
    materials, textures, images = doc.get("materials", []), doc.get("textures", []), doc.get("images", [])
    if len(materials) != 1 or primitive.get("material") != 0 or len(textures) != 3 or len(images) != 3:
        raise ValueError("Surface requires one PBR material and exactly three embedded maps")
    material = materials[0]; pbr = material.get("pbrMetallicRoughness", {})
    if material.get("alphaMode", "OPAQUE") != "OPAQUE" or material.get("emissiveFactor", [0, 0, 0]) != [0, 0, 0] \
            or material.get("extensions") or pbr.get("baseColorFactor", [1, 1, 1, 1]) != [1, 1, 1, 1] \
            or pbr.get("metallicFactor", 1) != 1 or pbr.get("roughnessFactor", 1) != 1 \
            or any("Texture" in k for k in material if k != "normalTexture") \
            or any("Texture" in k for k in pbr if k not in ["baseColorTexture", "metallicRoughnessTexture"]):
        raise ValueError("Surface must use opaque white-factor standard three-map PBR")
    normal_scale = material.get("normalTexture", {}).get("scale", 1)
    if localized and (normal_scale != before_doc["materials"][0].get("normalTexture", {}).get("scale", 1)
                      or bool(material.get("doubleSided", False)) != bool(before_doc["materials"][0].get("doubleSided", False))):
        raise ValueError("Scoped edit changed global material settings")
    if type(normal_scale) not in (int, float) or not math.isfinite(normal_scale) or not 0 < normal_scale <= 1:
        raise ValueError("Surface normal scale must be finite and within0..1")
    maps = {}; used = set()
    slots = {"base_color": (pbr.get("baseColorTexture"), "srgb"), "normal": (material.get("normalTexture"), "linear"),
             "metallic_roughness": (pbr.get("metallicRoughnessTexture"), "linear")}
    if set(metadata.get("surface_maps", {})) != set(slots):
        raise ValueError("Surface map metadata must declare all three maps")
    for name, (info, color_space) in slots.items():
        if not isinstance(info, dict) or info.get("texCoord", 0) != 0 or info.get("extensions") or type(info.get("index")) is not int or not 0 <= info["index"] < 3:
            raise ValueError("Missing or unsupported surface texture: " + name)
        texture = textures[info["index"]]
        sampler_index = texture.get("sampler")
        if type(sampler_index) is not int or not 0 <= sampler_index < len(doc.get("samplers", [])):
            raise ValueError("Surface textures require an explicit sampler")
        sampler = doc["samplers"][sampler_index]
        if sampler.get("minFilter") != 9987 or sampler.get("magFilter") != 9729 \
                or sampler.get("wrapS", 10497) != 33071 or sampler.get("wrapT", 10497) != 33071:
            raise ValueError("Surface atlas requires linear mip filtering and clamp-to-edge")
        index = texture.get("source")
        if type(index) is not int or not 0 <= index < 3 or index in used or texture.get("extensions"):
            raise ValueError("Surface maps must reference separate embedded images")
        used.add(index); image = images[index]
        if image.get("mimeType") != "image/png" or "uri" in image or type(image.get("bufferView")) is not int:
            raise ValueError("Surface images must use embedded PNG buffer views")
        view = doc["bufferViews"][image["bufferView"]]; start = view.get("byteOffset", 0); end = start + view["byteLength"]
        if view.get("buffer", 0) != 0 or start < 0 or end > len(binary): raise ValueError("Surface image buffer outside GLB")
        encoded = binary[start:end]; width, height, pixels = png_rgba(encoded)
        expected = metadata["surface_maps"][name]
        actual = {"image_index": index, "sha256": digest(encoded), "width": width, "height": height, "color_space": color_space}
        if any(expected.get(k) != v for k, v in actual.items()): raise ValueError("Surface map metadata/hash mismatch: " + name)
        if any(alpha != 255 for alpha in pixels[3::4]): raise ValueError("Surface map alpha must remain opaque")
        if name == "metallic_roughness" and (any(pixels[2::4]) or min(pixels[1::4]) < 128):
            raise ValueError("Surface MR requires zero metallic B and matte roughness G")
        maps[name] = {**actual, "rgba8_sha256": digest(pixels), "texcoord": 0}
    if localized:
        scoped["protected_map_regions"] = validate_protected_pixels(doc, binary, before_doc, before_binary, metadata, maps)
    return {**({"geometry_scope": scoped} if localized else {}), "surface_maps": maps, "geometry_reference": baseline, "geometry_signature": signature,
            "normal_scale": normal_scale, "double_sided": bool(material.get("doubleSided", False))}


def validate_package(package: Path) -> dict:
    package = package.resolve(strict=True)
    files = {}
    for name in ("metadata.json", "candidate.glb", "source.blend"):
        path = package / name
        if path.is_symlink() or not path.is_file() or path.resolve().parent != package:
            raise ValueError("Missing or unsafe shape package file: " + name)
        files[name] = path.read_bytes()
    metadata = json.loads(files["metadata.json"])
    if not isinstance(metadata, dict) or type(metadata.get("schema_version")) is not int \
            or metadata["schema_version"] != 1 or (metadata.get("gate"), metadata.get("material_contract")) not in [("rear-shape-v1", "plain-literal-COLOR_0"), ("rear-surface-v1", SURFACE_CONTRACT), ("rear-surface-v2", SURFACE_CONTRACT)] \
            or metadata.get("unrigged") is not True or metadata.get("production_ready") is not False \
            or metadata.get("animation_ready") is not False:
        raise ValueError("Package must explicitly declare the unrigged rear-shape gate")
    if metadata.get("glb_sha256") != digest(files["candidate.glb"]) \
            or metadata.get("source_sha256") != digest(files["source.blend"]):
        raise ValueError("Shape source/model hash mismatch")
    for field in ("source_height_m", "gameplay_height_m"):
        value = metadata.get(field)
        if type(value) not in (int, float) or not math.isfinite(value) or not 0.1 <= value <= 5.0:
            raise ValueError("Explicit finite shape height required: " + field)
    if abs(metadata["gameplay_height_m"] - 1.05) > 1e-6:
        raise ValueError("Rear-shape gate retains the documented 1.05m nominal game envelope")
    glb = files["candidate.glb"]
    if len(glb) < 20 or struct.unpack_from("<4sII", glb) != (b"glTF", 2, len(glb)):
        raise ValueError("Shape model must be a complete glTF 2 GLB")
    length, kind = struct.unpack_from("<II", glb, 12)
    if kind != 0x4E4F534A or 20 + length > len(glb):
        raise ValueError("Shape GLB JSON chunk missing")
    document = json.loads(glb[20:20 + length])
    is_surface = metadata["material_contract"] == SURFACE_CONTRACT
    if document.get("skins") or document.get("animations") or (not is_surface and (document.get("images") or document.get("textures"))) \
            or any("skin" in node for node in document.get("nodes", [])):
        raise ValueError("Shape gate requires unrigged geometry without clips or texture maps")
    primitives = [p for mesh in document.get("meshes", []) for p in mesh.get("primitives", [])]
    materials = document.get("materials", [])
    if not primitives or not materials or any("JOINTS_0" in p.get("attributes", {}) \
            or "WEIGHTS_0" in p.get("attributes", {}) or p.get("targets") \
            or not ({"POSITION", "NORMAL"} if is_surface else {"POSITION", "NORMAL", "COLOR_0"}).issubset(p.get("attributes", {})) \
            or p.get("mode", 4) != 4 or not isinstance(p.get("material"), int) \
            or not 0 <= p["material"] < len(materials) for p in primitives):
        raise ValueError("Shape surfaces require unskinned triangle normals and literal COLOR_0 PBR")
    surface = validate_surface(*glb_data(glb), metadata) if is_surface else {}
    material_contracts = []
    for material in materials:
        pbr = material.get("pbrMetallicRoughness", {})
        roughness = pbr.get("roughnessFactor", 1.0)
        if is_surface:
            material_contracts.append({"name": material.get("name", ""), "roughness": 1.0, "metallic": 1.0, "normal_scale": surface["normal_scale"], "double_sided": surface["double_sided"]})
            continue
        if type(roughness) not in (int, float) or not math.isfinite(roughness) or not 0.8 <= roughness <= 1.0 \
                or pbr.get("metallicFactor", 1.0) != 0 \
                or pbr.get("baseColorFactor", [1, 1, 1, 1]) != [1, 1, 1, 1] \
                or material.get("alphaMode", "OPAQUE") != "OPAQUE" \
                or any("Texture" in key for key in (*material.keys(), *pbr.keys())):
            raise ValueError("Shape material must preserve white-factor matte nonmetallic literal paint")
        material_contracts.append({"name": material.get("name", ""), "roughness": roughness, "metallic": 0.0})
    scale = metadata["gameplay_height_m"] / metadata["source_height_m"]
    if "gameplay_scale" in metadata and not math.isclose(metadata["gameplay_scale"], scale, rel_tol=1e-6):
        raise ValueError("Shape gameplay scale disagrees with source height")
    return {"metadata": metadata, "files": files, "materials": material_contracts,
            "surface_count": len(primitives), "gameplay_scale": scale, **surface}


def install(source: Path, project: Path, package: Path) -> dict:
    source, project = source.resolve(), project.resolve()
    validated = validate_package(package)
    if source == project or not (project / "_qa_local").is_dir() or (project / "_qa_local").is_symlink():
        raise ValueError("Shape review requires a separate prepared QA project")
    for filename in ("project.godot", "export_presets.cfg"):
        path = project / filename
        if path.is_symlink() or not path.resolve().is_relative_to(project):
            raise ValueError("Unsafe shape review destination")
    config = (project / "project.godot").read_text()
    bridge = 'ChromeReferenceQA="*res://_qa_local/chrome_reference_bridge.gd"'
    if not re.search(r'^config/custom_user_dir_name="waddle-chrome-reference-[^"\n]+"$', config, re.M) \
            or 'config/use_custom_user_dir=true' not in config or config.count(bridge) != 1 \
            or config.count('[qa]\n') != 1 or "HeroCandidateQA=" in config \
            or "ShapeCandidateQA=" in config or "hero_shape_enabled=" in config:
        raise ValueError("Shape review requires unique isolated bridge config without another candidate")
    presets = (project / "export_presets.cfg").read_text()
    if presets.count(',_qa_local/*.js"') != 1:
        raise ValueError("Shape QA include filter missing")
    helper = (source / "tools/qa/shape_candidate_browser.gd").read_bytes()
    folder = project / "qa_shape"
    helper_path = project / "_qa_local/shape_candidate_browser.gd"
    if folder.exists() or folder.is_symlink() or helper_path.exists() or helper_path.is_symlink():
        raise ValueError("Shape candidate files already exist; prepare a fresh review")
    metadata = validated["metadata"]
    post_import = (source / "tools/qa/surface_candidate_post_import.gd").read_bytes() if metadata["material_contract"] == SURFACE_CONTRACT else None
    importer = importer_for(metadata)
    is_surface = metadata["material_contract"] == SURFACE_CONTRACT
    binding = {"schema_version": 1, "gate": metadata["gate"], "unrigged": True,
        "glb_sha256": metadata["glb_sha256"], "source_sha256": metadata["source_sha256"],
        "metadata_sha256": digest(validated["files"]["metadata.json"]),
        "importer_sha256": digest(importer.encode()), "materials": validated["materials"],
        "material_contract": metadata["material_contract"], "surface_count": validated["surface_count"],
        "vertex_color_policy": "GLB remains linear; gl_compatibility alone encodes a private mesh copy to sRGB before its built-in albedo decode",
        "source_height_m": metadata["source_height_m"], "gameplay_height_m": metadata["gameplay_height_m"],
        "gameplay_scale": validated["gameplay_scale"], "animation_ready": False, "production_ready": False,
        "camera_policy": "Preserve normal-game rear camera; optional separately labeled rear detail only",
        "scope": "Shape review; animation and material detail pending; not a shipping character"}
    if is_surface:
        binding.update({key: validated[key] for key in ["surface_maps", "geometry_reference", "geometry_signature"]})
        if "geometry_scope" in validated:
            binding["geometry_scope"] = validated["geometry_scope"]
        binding["post_import_sha256"] = digest(post_import)
        binding["texture_import_policy"] = "Embedded uncompressed PNG; source-preserving mipmaps, normalized tangent normal mips; exact RGBA8 base pixels"
        binding["vertex_color_policy"] = "Imported PBR maps unchanged; no vertex color transfer"
        binding["scope"] = "Rear surface review; animation/front review pending; not a shipping character"
    folder.mkdir()
    if post_import is not None:
        (folder / "surface_post_import.gd").write_bytes(post_import)
    (folder / "candidate.glb").write_bytes(validated["files"]["candidate.glb"])
    (folder / "candidate.glb.import").write_text(importer)
    (folder / "candidate_binding.json").write_text(json.dumps(binding, indent=2) + '\n')
    helper_path.write_bytes(helper)
    config = config.replace(bridge, bridge + '\nShapeCandidateQA="*res://_qa_local/shape_candidate_browser.gd"', 1)
    config = config.replace('[qa]\n', '[qa]\nhero_shape_enabled=true\n', 1)
    (project / "project.godot").write_text(config)
    (project / "export_presets.cfg").write_text(presets.replace(',_qa_local/*.js"', ',_qa_local/*.js,qa_shape/*.json"', 1))
    return {"binding": binding, "binding_sha256": digest((folder / "candidate_binding.json").read_bytes()),
            "helper_sha256": digest(helper), "controls_sha256": digest(review_controls().encode()),
            "gallery_eligible": False, "scope": binding["scope"]}


def review_controls() -> str:
    return '''
<style>
#ww-shape-review{position:fixed;z-index:2147483646;left:50%;bottom:max(8px,env(safe-area-inset-bottom));transform:translateX(-50%);width:min(410px,calc(100vw - 16px));box-sizing:border-box;padding:10px 12px;border:1px solid #7298a3;border-radius:14px;background:rgba(12,29,42,.96);color:#f1f8fa;font:13px/1.4 system-ui,sans-serif;box-shadow:0 3px 18px #0007}#ww-shape-review[hidden]{display:none}#ww-shape-review strong{font-size:14px}#ww-shape-review small{display:block;color:#b5cdd8;margin-bottom:7px}#ww-shape-review button{width:49%;min-height:36px;border:1px solid #668696;border-radius:8px;background:#203c50;color:inherit;font:inherit;touch-action:manipulation;cursor:pointer}#ww-shape-review button[aria-pressed="true"]{background:#d0eff2;color:#102e3a}#ww-shape-review button:disabled{opacity:.5}#ww-shape-status{float:right;color:#b5d7c5}#ww-shape-review[data-state="error"] #ww-shape-status{color:#ffc3b2}
</style>
<section id="ww-shape-review" aria-label="Shape review controls" hidden>
<strong>Shape review</strong><span id="ww-shape-status" role="status" aria-live="polite">Preparing…</span>
<small>Shape review • animation/material detail pending</small>
<button type="button" data-shape-view="rear" aria-pressed="true">In-game rear</button>
<button type="button" data-shape-view="rear_detail" aria-pressed="false">Rear detail</button>
</section>
<script>(() => {
const panel=document.getElementById('ww-shape-review');
if(!panel || !window.__wwQABuild?.hero_shape || !['localhost','127.0.0.1','[::1]'].includes(location.hostname) || !new URLSearchParams(location.search).get('qa_token')) return;
const status=document.getElementById('ww-shape-status'),buttons=[...panel.querySelectorAll('[data-shape-view]')];
let busy=false;
const delay=()=>new Promise(resolve=>setTimeout(resolve,160));
function lock(value){busy=value;buttons.forEach(button=>button.disabled=value);}
function show(state,label){panel.dataset.state=state;status.textContent=label;}
async function ready(route=null,minimum=0){const deadline=Date.now()+180000;while(Date.now()<deadline){if(window.__wwQA&&window.__wwShapeCandidate){const stage=window.__wwQA.read();if(stage.status==='error')throw Error('Preview unavailable');if(stage.status==='ready'&&stage.settled_frames>=2&&stage.submitted_frames>=minimum&&(!route||(stage.route===route&&stage.tree_paused)))return stage;}await delay();}throw Error('Preview unavailable');}
async function verify(){const deadline=Date.now()+5000;while(Date.now()<deadline){const state=window.__wwShapeCandidate.status();if(state.status==='error')throw Error('Verification failed');if(state.status==='ready'){const receipt=window.__wwShapeCandidate.read();if(receipt.status!=='ready'||!receipt.active_renderer?.signature||receipt.active_renderer.errors?.length)throw Error('Verification failed');if(['rear-surface-v1','rear-surface-v2'].includes(receipt.gate)){panel.setAttribute('aria-label','Surface review controls');panel.querySelector('strong').textContent='Surface review';panel.querySelector('small').textContent=receipt.view==='rear_detail'?'Rear surface detail • pickup overlay hidden; animation/front review pending':'Surface review • animation/front review pending';}buttons.forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.shapeView===receipt.view)));show('verified','Verified');return;}await delay();}throw Error('Preview unavailable');}
async function view(name){if(busy)return;lock(true);show('pending','Preparing…');try{const stage=await ready('runner_hud');window.__wwShapeCandidate.view(name);await ready('runner_hud',stage.submitted_frames+2);await verify();}catch(error){show('error',error.message);}finally{lock(false);}}
buttons.forEach(button=>button.addEventListener('click',()=>view(button.dataset.shapeView)));
panel.hidden=false;lock(true);(async()=>{try{const stage=await ready();if(stage.route!=='runner_hud')window.__wwQA.route('runner_hud');await ready('runner_hud');await verify();}catch(error){show('error',error.message);}finally{lock(false);}})();
})();</script>
'''
