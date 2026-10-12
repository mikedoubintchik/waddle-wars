#!/usr/bin/env python3
"""Package a verified QA atlas as compact GLB + one shared external PNG set.

No Blender, mesh changes, bake changes or live asset promotion. Godot imports
both normal PBR and optional atlas-shader textures from the same resource paths.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]
QA = ROOT / "qa_shots/hero"
KINDS = ("albedo", "normal", "orm", "masks")
GLB_NAME = "hero_penguin_v12_atlas.glb"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load_auditor():
    path = Path(__file__).with_name("audit_hero_v12_atlas_export.py")
    spec = importlib.util.spec_from_file_location("atlas_export_auditor", path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def safe_output(value):
    path = Path(value).resolve()
    if path == QA.resolve() or not path.is_relative_to(QA.resolve()) or path.exists():
        raise ValueError("shared-texture output must be a fresh dedicated qa_shots/hero child")
    return path


def split_glb(raw):
    if len(raw) < 28 or struct.unpack_from("<4sII", raw) != (b"glTF", 2, len(raw)):
        raise ValueError("invalid GLB2 header")
    size, kind = struct.unpack_from("<II", raw, 12)
    if kind != 0x4E4F534A or size % 4:
        raise ValueError("expected aligned JSON chunk")
    binary_size, binary_kind = struct.unpack_from("<II", raw, 20 + size)
    if binary_kind != 0x004E4942 or binary_size % 4 or 28 + size + binary_size != len(raw):
        raise ValueError("expected one aligned BIN chunk")
    document = json.loads(raw[20:20 + size])
    if len(document.get("buffers", [])) != 1 or "uri" in document["buffers"][0]:
        raise ValueError("expected exactly one embedded geometry buffer")
    return document, raw[28 + size:28 + size + document["buffers"][0]["byteLength"]]


def join_glb(document, binary):
    encoded = json.dumps(document, sort_keys=True, separators=(",", ":")).encode()
    encoded += b" " * (-len(encoded) % 4)
    padded = binary + b"\0" * (-len(binary) % 4)
    return (struct.pack("<4sII", b"glTF", 2, 28 + len(encoded) + len(padded))
            + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
            + struct.pack("<II", len(padded), 0x004E4942) + padded)


def accessor_views(document):
    result = set()
    for accessor in document.get("accessors", []):
        if "bufferView" in accessor:
            result.add(accessor["bufferView"])
        if "sparse" in accessor:
            result.add(accessor["sparse"]["indices"]["bufferView"])
            result.add(accessor["sparse"]["values"]["bufferView"])
    return result


def externalize(raw, png_hashes):
    original, binary = split_glb(raw)
    document = copy.deepcopy(original)
    if any(not extension.startswith("KHR_materials_") and extension != "KHR_texture_transform"
           for extension in document.get("extensionsUsed", [])):
        raise ValueError("unsupported extension may contain unhandled bufferView references")
    image_views, external = set(), []
    digest_to_kind = {digest: kind for kind, digest in png_hashes.items()}
    for image in document.get("images", []):
        if "uri" in image or "bufferView" not in image or image.get("mimeType") != "image/png":
            raise ValueError("source images must be verified embedded PNGs")
        index = image["bufferView"]
        view = original["bufferViews"][index]
        if view.get("buffer", 0) != 0:
            raise ValueError("image references unexpected buffer")
        start, count = view.get("byteOffset", 0), view["byteLength"]
        digest = hashlib.sha256(binary[start:start + count]).hexdigest()
        kind = digest_to_kind.get(digest)
        if kind not in ("albedo", "normal", "orm"):
            raise ValueError("embedded image does not exactly match a bound canonical PNG")
        image.pop("bufferView")
        image["uri"] = f"hero_penguin_v12_atlas_{kind}.png"
        image_views.add(index)
        external.append({"image_name": image.get("name"), "uri": image["uri"], "sha256": digest, "removed_bytes": count})
    if {item["uri"] for item in external} != {f"hero_penguin_v12_atlas_{kind}.png" for kind in ("albedo", "normal", "orm")}:
        raise ValueError("expected the complete three-image PBR atlas")
    used = accessor_views(document)
    if used & image_views:
        raise ValueError("image storage aliases geometry/accessor storage")
    remap, new_views, compact = {}, [], bytearray()
    for index in sorted(used):
        view = copy.deepcopy(original["bufferViews"][index])
        if view.get("buffer", 0) != 0:
            raise ValueError("accessor references unexpected buffer")
        start, count = view.get("byteOffset", 0), view["byteLength"]
        if start < 0 or count < 0 or start + count > len(binary):
            raise ValueError("out-of-bounds source bufferView")
        compact.extend(b"\0" * (-len(compact) % 4))
        view["byteOffset"] = len(compact)
        compact.extend(binary[start:start + count])
        remap[index] = len(new_views)
        new_views.append(view)
    for accessor in document.get("accessors", []):
        if "bufferView" in accessor:
            accessor["bufferView"] = remap[accessor["bufferView"]]
        if "sparse" in accessor:
            for field in ("indices", "values"):
                accessor["sparse"][field]["bufferView"] = remap[accessor["sparse"][field]["bufferView"]]
    document["bufferViews"] = new_views
    document["buffers"][0]["byteLength"] = len(compact)
    # Stronger than geometry-only parity: exact retained raw bufferView bytes
    # prove normal/tangent/accessor storage survives this packaging operation.
    for old, new in remap.items():
        before, after = original["bufferViews"][old], new_views[new]
        if binary[before.get("byteOffset", 0):before.get("byteOffset", 0) + before["byteLength"]] != compact[after["byteOffset"]:after["byteOffset"] + after["byteLength"]]:
            raise RuntimeError("retained accessor bytes changed")
    if accessor_views(document) != set(range(len(new_views))):
        raise RuntimeError("unreferenced bufferView remains in packaged GLB")
    return join_glb(document, bytes(compact)), {
        "external_images": external, "source_bin_bytes": len(binary), "packaged_bin_bytes": len(compact),
        "removed_image_buffer_views": sorted(image_views), "retained_buffer_views": len(new_views),
        "removed_unreferenced_buffer_views": sorted(set(range(len(original["bufferViews"]))) - used - image_views),
        "all_retained_buffer_view_bytes_exact": True, "no_unreferenced_buffer_views": True,
        "embedded_image_bytes": 0,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-lod", type=Path, required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()
    source = args.source_lod.resolve()
    output = safe_output(args.output_dir)
    binding_path, source_glb = source / "atlas_binding.json", source / GLB_NAME
    binding = json.loads(binding_path.read_text())
    if binding.get("schema_version") != 1 or binding.get("uv_contract") != "unique-nonoverlapping-v1" or binding.get("projection_gate") != {"passed": True, "missing_pixels": 0}:
        raise ValueError("package requires the verified zero-miss atlas binding")
    if sha(source_glb) != binding["glb_sha256"]:
        raise ValueError("source GLB binding mismatch")
    pngs = {kind: source / f"hero_penguin_v12_atlas_{kind}.png" for kind in KINDS}
    if any(sha(path) != binding["textures"][kind] for kind, path in pngs.items()):
        raise ValueError("canonical atlas PNG binding mismatch")
    auditor = load_auditor()
    before = auditor.Glb(source_glb)
    packaged, audit = externalize(source_glb.read_bytes(), binding["textures"])
    lod = output / "lod0"
    lod.mkdir(parents=True)
    target = lod / GLB_NAME
    target.write_bytes(packaged)
    after = auditor.Glb(target)
    if len(before.doc["accessors"]) != len(after.doc["accessors"]) or any(before.accessor(i) != after.accessor(i) for i in range(len(before.doc["accessors"]))):
        raise RuntimeError("exact accessor parity failed, including normals/tangents")
    for key in ("meshes", "nodes", "skins", "animations", "materials", "textures", "samplers"):
        if before.doc.get(key) != after.doc.get(key):
            raise RuntimeError(f"packaging changed {key}")
    for kind, path in pngs.items():
        shutil.copy2(path, lod / path.name)
        profile = "normal_texture.import" if kind == "normal" else "data_texture.import"
        shutil.copy2(ROOT / "tests/fixtures/hero_v12_atlas_capture" / profile, lod / f"{path.name}.import")
    original_binding = copy.deepcopy(binding)
    binding["glb_sha256"] = sha(target)
    binding["texture_layout"] = "shared-external-v1"
    binding["source_embedded_glb_sha256"] = sha(source_glb)
    (lod / "atlas_binding.json").write_text(json.dumps(binding, indent=2, sort_keys=True) + "\n")
    (output / "source_atlas_binding.json").write_text(json.dumps(original_binding, indent=2, sort_keys=True) + "\n")
    for name in ("atlas_audit.json", "hero_penguin_feather_dark_source_v1.prompt.md", "hero_penguin_feather_cream_source_v1.prompt.md"):
        if (source.parent / name).is_file():
            shutil.copy2(source.parent / name, output / f"source_{name}")
    audit.update(schema_version=1, production_ready=False, qa_only=True,
                 source_glb_sha256=sha(source_glb), packaged_glb_sha256=sha(target), source_binding_sha256=sha(binding_path),
                 png_sha256=binding["textures"], source_glb_bytes=source_glb.stat().st_size, packaged_glb_bytes=target.stat().st_size,
                 exact_all_accessor_values_preserved=True, exact_mesh_rig_material_animation_json_preserved=True,
                 normal_build_requires_blender=False, godot_residency_gate="PENDING actual normal import",
                 limitations=["Packaging only; source shape/material fidelity remains unapproved.",
                              "One external image set does not prove Godot resource identity until actual import audit.",
                              "Stored compressed payload is not driver VRAM, FPS or a release approval."])
    node = shutil.which("node")
    if node is None:
        raise RuntimeError("Node.js is required for the authoring-only Khronos gate; normal Godot builds do not need it")
    validation = subprocess.run([node, str(Path(__file__).with_name("validate_external_glb.mjs")), str(target)],
                                capture_output=True, text=True, check=False)
    (output / "khronos_validation.json").write_text(validation.stdout)
    (output / "khronos_validation.stderr.log").write_text(validation.stderr)
    if validation.returncode:
        raise RuntimeError("external-image Khronos validation failed; QA output retained")
    audit["khronos"] = json.loads(validation.stdout)
    (output / "package_audit.json").write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
    print(f"[hero-shared-textures] BUILT {target}: {audit['source_glb_bytes']} -> {audit['packaged_glb_bytes']} GLB bytes; Godot reuse unverified")


if __name__ == "__main__":
    main()
