#!/usr/bin/env python3
"""Apply audited Web texture imports only to an isolated export project.

Never launches Godot, edits source images, or changes the primary checkout.
Profile pins source bytes, sampler settings, this helper and resulting CTEXs.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / "data/web/ui_import_profile.json"
ALLOWED_ROOTS = ("assets/art/ui/wardrobe_outfits_v1", "assets/art/ui/menu")


def sha(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def non_quality_settings(text: str) -> str:
    return re.sub(r"^compress/(mode|lossy_quality)=.*\n?", "", text, flags=re.M)


def load_profile(profile_path: Path = PROFILE) -> dict:
    profile = json.loads(Path(profile_path).read_text())
    if profile.get("schema_version") != 1 or profile.get("helper_sha256") != sha(Path(__file__)):
        raise ValueError("Web import profile/helper identity mismatch")
    if profile.get("pack_memory_helper_sha256") != sha(ROOT / "tools/release/web_pack_memory.py"):
        raise ValueError("Web pack memory helper identity mismatch")
    if profile.get("quality_gate") != {"min_ssim": 0.995, "min_psnr_db": 35.0, "max_alpha_error": 0}:
        raise ValueError("Web import quality gate mismatch")
    rows = profile.get("assets", [])
    names = [row.get("path", "") for row in rows]
    if not rows or len(rows) > 700 or names != sorted(set(names)):
        raise ValueError("Web import inventory must be nonempty, unique and sorted")
    limit = profile.get("max_pack_bytes")
    if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 220_000_000:
        raise ValueError("Invalid Web pack size budget")
    for row in rows:
        path = Path(row["path"])
        if path.is_absolute() or ".." in path.parts or path.suffix != ".webp" or not any(path.is_relative_to(Path(root)) for root in ALLOWED_ROOTS):
            raise ValueError("Web import profile path outside audited UI scope")
        if not isinstance(row.get("quality"), (int, float)) or isinstance(row["quality"], bool) or not 0.9 <= row["quality"] <= 1:
            raise ValueError("Web import quality outside permitted range")
        if not isinstance(row.get("mipmaps"), bool):
            raise ValueError("Web import mipmap policy missing")
        for key in ("source_sha256", "sampler_settings_sha256", "imported_sha256"):
            if not re.fullmatch(r"[0-9a-f]{64}", row.get(key, "")):
                raise ValueError("Web import asset identity missing")
        imported = Path(row.get("imported_path", ""))
        if not imported.is_relative_to(Path(".godot/imported")) or ".." in imported.parts or imported.suffix != ".ctex":
            raise ValueError("Invalid imported texture path")
    return profile


def apply_to_project(project: Path, profile_path: Path = PROFILE, source_root: Path = ROOT) -> dict:
    project, source_root = Path(project).resolve(), Path(source_root).resolve()
    if project == source_root or project == ROOT.resolve():
        raise ValueError("Apply Web profile to an isolated export project only")
    if not (project / "project.godot").is_file():
        raise ValueError("Export project missing")
    profile = load_profile(profile_path)
    actual = sorted(p.relative_to(project).as_posix() for name in ALLOWED_ROOTS for p in (project / name).rglob("*.webp"))
    if actual != [row["path"] for row in profile["assets"]]:
        raise ValueError("Web UI asset inventory changed; re-audit import profile")
    pending = []
    for row in profile["assets"]:
        source = project / row["path"]
        sidecar = source.with_name(source.name + ".import")
        if source.is_symlink() or sidecar.is_symlink() or not source.resolve().is_relative_to(project) or not sidecar.resolve().is_relative_to(project):
            raise ValueError("Export texture paths must stay inside isolated project")
        if sha(source) != row["source_sha256"]:
            raise ValueError("Texture source changed after Web import audit: " + row["path"])
        text = sidecar.read_text()
        sampler = hashlib.sha256(non_quality_settings(text).encode()).hexdigest()
        if sampler != row["sampler_settings_sha256"]:
            raise ValueError("Texture sampler/import settings changed after Web audit: " + row["path"])
        if len(re.findall(r"^compress/mode=[01]$", text, re.M)) != 1 or len(re.findall(r"^compress/lossy_quality=[0-9.]+$", text, re.M)) != 1:
            raise ValueError("Only uncompressed-VRAM Web imports can use this profile")
        if ("mipmaps/generate=true" in text) != row["mipmaps"]:
            raise ValueError("Texture mipmap contract changed")
        text = re.sub(r"^compress/mode=[01]$", "compress/mode=1", text, flags=re.M)
        text = re.sub(r"^compress/lossy_quality=[0-9.]+$", f'compress/lossy_quality={row["quality"]:g}', text, flags=re.M)
        pending.append((sidecar, text))
    # Validate whole inventory first; a stale last row cannot partially apply it.
    for path, text in pending:
        path.write_text(text)
    return {"schema_version": 1, "profile_sha256": sha(Path(profile_path)),
            "helper_sha256": sha(Path(__file__)), "profiled_textures": len(pending),
            "source_images_changed": False, "dimensions_alpha_mipmaps_preserved": True,
            "max_pack_bytes": profile["max_pack_bytes"]}


def verify_pack(pack: Path, profile_path: Path = PROFILE) -> dict:
    pack = Path(pack)
    profile = load_profile(profile_path)
    if pack.stat().st_size > profile["max_pack_bytes"]:
        raise ValueError(f'Web pack exceeds audited budget: {pack.stat().st_size} > {profile["max_pack_bytes"]}')
    with pack.open("rb") as stream:
        magic, version, _major, _minor, _patch, flags, base, directory = struct.unpack("<6I2Q", stream.read(40))
        if magic != 0x43504447 or version != 4 or flags != 2:
            raise ValueError("Unsupported Web PCK format")
        stream.seek(directory)
        count = struct.unpack("<I", stream.read(4))[0]
        entries = {}
        for _ in range(count):
            length = struct.unpack("<I", stream.read(4))[0]
            name = stream.read(length).rstrip(b"\0").decode()
            offset, size = struct.unpack("<QQ", stream.read(16))
            digest = stream.read(16).hex()
            entry_flags = struct.unpack("<I", stream.read(4))[0]
            if offset + base + size > directory or name in entries or entry_flags:
                raise ValueError("Invalid Web PCK directory")
            entries[name] = (offset + base, size, digest)
        for row in profile["assets"]:
            if row["imported_path"] not in entries:
                raise ValueError("Profiled Web texture missing from pack: " + row["path"])
            offset, size, digest = entries[row["imported_path"]]
            stream.seek(offset)
            data = stream.read(size)
            if hashlib.md5(data).hexdigest() != digest or hashlib.sha256(data).hexdigest() != row["imported_sha256"]:
                raise ValueError("Web packed texture differs from admitted import: " + row["path"])
    return {"profile_sha256": sha(Path(profile_path)), "helper_sha256": sha(Path(__file__)),
            "pack_sha256": sha(pack), "pack_bytes": pack.stat().st_size,
            "max_pack_bytes": profile["max_pack_bytes"], "verified_textures": len(profile["assets"]),
            "pack_entries": count}
