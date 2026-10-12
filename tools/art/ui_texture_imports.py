#!/usr/bin/env python3
"""Bounded UI WebP import experiment; source images never change.

Prepare an isolated project from an immutable deployed PCK, import/decode it
with Godot, compare exact decoded pixels, and publish an admitted profile.
Requires numpy and Pillow for analysis, not for preparation/profile output.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import struct

ROOT = Path(__file__).resolve().parents[2]
SCOPES = ("assets/art/ui/wardrobe_outfits_v1", "assets/art/ui/menu")
MIN_SSIM = 0.995
MIN_PSNR = 35.0


def sha(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def allowed(path: str) -> bool:
    p = Path(path)
    return not p.is_absolute() and ".." not in p.parts and p.suffix == ".webp" and any(
        p.is_relative_to(Path(scope)) for scope in SCOPES)


def set_quality(text: str, quality: float) -> str:
    if not 0.9 <= quality <= 1.0:
        raise ValueError("Quality must be between 0.90 and 1.00")
    if len(re.findall(r"^compress/mode=[01]$", text, re.M)) != 1:
        raise ValueError("Expected exactly one non-VRAM import mode")
    if len(re.findall(r"^compress/lossy_quality=[0-9.]+$", text, re.M)) != 1:
        raise ValueError("Expected exactly one import quality")
    text = re.sub(r"^compress/mode=[01]$", "compress/mode=1", text, flags=re.M)
    return re.sub(r"^compress/lossy_quality=[0-9.]+$", f"compress/lossy_quality={quality:g}", text, flags=re.M)


def non_quality_settings(text: str) -> str:
    return re.sub(r"^compress/(mode|lossy_quality)=.*\n?", "", text, flags=re.M)


def pack_entries(path: Path) -> dict:
    with path.open("rb") as stream:
        magic, version, _major, _minor, _patch, flags, base, directory = struct.unpack("<6I2Q", stream.read(40))
        if magic != 0x43504447 or version != 4 or flags != 2:
            raise ValueError("Expected unencrypted Godot4 PCK v4")
        stream.seek(directory)
        entries = {}
        for _ in range(struct.unpack("<I", stream.read(4))[0]):
            length = struct.unpack("<I", stream.read(4))[0]
            name = stream.read(length).rstrip(b"\0").decode()
            offset, size = struct.unpack("<QQ", stream.read(16))
            digest = stream.read(16).hex()
            stream.read(4)
            if offset + base + size > directory or name in entries:
                raise ValueError("Invalid PCK directory")
            entries[name] = {"offset": offset + base, "bytes": size, "md5": digest}
        return entries


DECODE_SCRIPT = '''extends SceneTree
func _initialize() -> void:
 var rows = JSON.parse_string(FileAccess.get_file_as_string("res://entries.json"))
 var report: Array = []
 var output = ProjectSettings.globalize_path("res://../decoded")
 DirAccess.make_dir_recursive_absolute(output)
 for entry in rows:
  var row = entry.duplicate()
  for kind in ["baseline", "candidate"]:
   var texture: Texture2D = load(entry[kind])
   if texture == null:
    push_error("Missing texture: " + entry[kind]); quit(1); return
   var image = texture.get_image()
   row[kind + "_width"] = image.get_width()
   row[kind + "_height"] = image.get_height()
   row[kind + "_mipmaps"] = image.has_mipmaps()
   image.convert(Image.FORMAT_RGBA8)
   image.clear_mipmaps()
   if image.save_png(output + "/%d-%s.png" % [int(entry.id), kind]) != OK:
    push_error("Decode output failed"); quit(1); return
  report.append(row)
 var file = FileAccess.open("res://../decode-report.json", FileAccess.WRITE)
 file.store_string(JSON.stringify(report, "  ")); file.close()
 print("Decoded ", report.size(), " baseline/candidate texture pairs")
 quit()
'''


def prepare(root: Path, pack: Path, output: Path, quality: float) -> dict:
    if output.exists():
        raise ValueError("Use a new isolated output directory")
    entries = pack_entries(pack)
    paths = sorted(p.relative_to(root).as_posix() for scope in SCOPES for p in (root / scope).rglob("*.webp"))
    if not paths or len(paths) > 700:
        raise ValueError("Unexpected scope size")
    project = output / "project"
    project.mkdir(parents=True)
    rows = []
    with pack.open("rb") as stream:
        for index, name in enumerate(paths):
            if not allowed(name):
                raise ValueError("Asset outside permitted UI scope")
            source = root / name
            sidecar = source.with_name(source.name + ".import")
            settings = sidecar.read_text()
            imported = re.search(r'^path="res://([^"\n]+)"$', settings, re.M)[1]
            baseline = entries[imported]
            stream.seek(baseline["offset"])
            payload = stream.read(baseline["bytes"])
            if hashlib.md5(payload).hexdigest() != baseline["md5"]:
                raise ValueError("Baseline payload digest mismatch")
            destination = project / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            destination.with_name(destination.name + ".import").write_text(set_quality(settings, quality))
            before = project / f"baseline/{index}.ctex"
            before.parent.mkdir(exist_ok=True)
            before.write_bytes(payload)
            rows.append({"id": index, "source": name, "source_sha256": sha(source),
                         "before_import_sha256": sha(sidecar), "before_import_text": settings,
                         "baseline": f"res://baseline/{index}.ctex", "candidate": "res://" + name,
                         "imported": imported, "baseline_bytes": len(payload),
                         "mipmaps": "mipmaps/generate=true" in settings})
    (project / "entries.json").write_text(json.dumps(rows, indent=2) + "\n")
    (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="UI import quality audit"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    (project / "decode.gd").write_text(DECODE_SCRIPT)
    receipt = {"source_root": str(root.resolve()), "baseline_pack": str(pack.resolve()),
               "baseline_pack_sha256": sha(pack), "quality": quality, "count": len(rows)}
    (output / "preparation.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def pixel_metrics(before: Path, after: Path) -> dict:
    import numpy as np
    from PIL import Image

    a = np.asarray(Image.open(before).convert("RGBA"), dtype=np.float64)
    b = np.asarray(Image.open(after).convert("RGBA"), dtype=np.float64)
    if a.shape != b.shape:
        raise ValueError("Decoded dimensions changed")
    alpha = a[:, :, 3:] / 255.0
    visible = alpha[:, :, 0] > 0.05
    if not visible.any():
        raise ValueError("Empty source image")
    rgb = (a - b)[:, :, :3][visible]
    mse = float(np.mean(rgb * rgb))

    def mean(x, width=11):
        x = np.pad(x, ((width // 2, width // 2), (width // 2, width // 2)), mode="reflect")
        x = np.pad(x, ((1, 0), (1, 0)))
        integral = x.cumsum(0, dtype=np.float64).cumsum(1, dtype=np.float64)
        return (integral[width:, width:] - integral[:-width, width:] - integral[width:, :-width] + integral[:-width, :-width]) / (width * width)

    def ssim(x, y):
        mx, my = mean(x), mean(y)
        vx, vy = np.maximum(0, mean(x * x) - mx * mx), np.maximum(0, mean(y * y) - my * my)
        cov = mean(x * y) - mx * my
        return float(np.mean(((2 * mx * my + 6.5025) * (2 * cov + 58.5225)) / ((mx * mx + my * my + 6.5025) * (vx + vy + 58.5225))))

    scores = []
    for background in (0, 255):
        x = (a[:, :, :3] * alpha + (1 - alpha) * background) @ np.array([0.299, 0.587, 0.114])
        y = (b[:, :, :3] * alpha + (1 - alpha) * background) @ np.array([0.299, 0.587, 0.114])
        scores.append(ssim(x, y))
    return {"alpha_max_error": int(np.abs(a[:, :, 3] - b[:, :, 3]).max()),
            "visible_rgb_max_error": int(np.abs(rgb).max()),
            "visible_rgb_psnr_db": 999.0 if mse == 0 else 10 * math.log10(255 * 255 / mse),
            "ssim_black": scores[0], "ssim_white": scores[1]}


def analyze(output: Path) -> dict:
    project = output / "project"
    rows = json.loads((output / "decode-report.json").read_text())
    expected = json.loads((project / "entries.json").read_text())
    if len(rows) != len(expected) or [r["source"] for r in rows] != [r["source"] for r in expected]:
        raise ValueError("Decode report does not cover exact preparation inventory")
    for row, original in zip(rows, expected):
        for key in original:
            if row[key] != original[key]:
                raise ValueError("Decode report identity mismatch")
        candidate = project / row["source"]
        sidecar = candidate.with_name(candidate.name + ".import")
        settings = sidecar.read_text()
        if sha(candidate) != row["source_sha256"] or non_quality_settings(settings) != non_quality_settings(row["before_import_text"]):
            raise ValueError("Only compression mode and quality may change")
        image_id = str(int(row["id"]))
        if not (output / f"decoded/{image_id}-baseline.png").exists():
            image_id = str(float(row["id"]))  # Earlier diagnostic serialization.
        row.update(pixel_metrics(output / f'decoded/{image_id}-baseline.png', output / f'decoded/{image_id}-candidate.png'))
        row["candidate_bytes"] = (project / row["imported"]).stat().st_size
        row["candidate_import_text"] = settings
        row["candidate_import_sha256"] = sha(sidecar)
        row["candidate_texture_sha256"] = sha(project / row["imported"])
        row["pass"] = (row["alpha_max_error"] == 0 and min(row["ssim_black"], row["ssim_white"]) >= MIN_SSIM
                       and row["visible_rgb_psnr_db"] >= MIN_PSNR
                       and row["baseline_width"] == row["candidate_width"]
                       and row["baseline_height"] == row["candidate_height"]
                       and row["baseline_mipmaps"] == row["candidate_mipmaps"] == row["mipmaps"])
    result = {"method": "Luminance SSIM11x11 uniform window, reflect border, black/white alpha composites; visible RGB PSNR for alpha>0.05",
              "thresholds": {"min_ssim": MIN_SSIM, "min_psnr_db": MIN_PSNR, "max_alpha_error": 0},
              "count": len(rows), "passed": sum(r["pass"] for r in rows),
              "baseline_bytes": sum(r["baseline_bytes"] for r in rows),
              "candidate_bytes": sum(r["candidate_bytes"] for r in rows), "rows": rows}
    (output / "quality.json").write_text(json.dumps(result, indent=2) + "\n")
    return {key: value for key, value in result.items() if key != "rows"}


def write_profile(root: Path, output: Path) -> dict:
    report = json.loads((output / "quality.json").read_text())
    expected = json.loads((output / "project/entries.json").read_text())
    if report["count"] != len(expected) or report["passed"] != len(expected) or not expected:
        raise ValueError("All prepared candidates must pass admission")
    if report["thresholds"] != {"min_ssim": MIN_SSIM, "min_psnr_db": MIN_PSNR, "max_alpha_error": 0}:
        raise ValueError("Quality gate cannot be relaxed")
    assets = []
    for row, original in zip(report["rows"], expected):
        if not row["pass"] or row["source"] != original["source"] or not allowed(row["source"]):
            raise ValueError("Invalid or out-of-scope admitted asset")
        source = root / row["source"]
        sidecar = source.with_name(source.name + ".import")
        candidate = output / "project" / (row["source"] + ".import")
        if sha(source) != original["source_sha256"] or sha(sidecar) != original["before_import_sha256"] or sha(candidate) != row["candidate_import_sha256"]:
            raise ValueError("Source/import changed after audit")
        if non_quality_settings(candidate.read_text()) != non_quality_settings(sidecar.read_text()):
            raise ValueError("Unexpected non-compression mutation")
        if row["alpha_max_error"] != 0 or min(row["ssim_black"], row["ssim_white"]) < MIN_SSIM or row["visible_rgb_psnr_db"] < MIN_PSNR:
            raise ValueError("Pixel metrics fail admission")
        texture = output / "project" / row["imported"]
        if sha(texture) != row["candidate_texture_sha256"]:
            raise ValueError("Candidate import changed after decode audit")
        quality = float(re.search(r"^compress/lossy_quality=([0-9.]+)$", candidate.read_text(), re.M)[1])
        if not 0.9 <= quality <= 1.0 or "compress/mode=1\n" not in candidate.read_text():
            raise ValueError("Profile accepts only high-quality lossy WebP imports")
        assets.append({"path": row["source"], "source_sha256": row["source_sha256"], "quality": quality,
                       "mipmaps": row["mipmaps"], "width": row["candidate_width"], "height": row["candidate_height"],
                       "sampler_settings_sha256": hashlib.sha256(non_quality_settings(sidecar.read_text()).encode()).hexdigest(),
                       "imported_path": row["imported"], "imported_sha256": row["candidate_texture_sha256"],
                       "imported_bytes": row["candidate_bytes"], "alpha_max_error": row["alpha_max_error"],
                       "min_ssim": min(row["ssim_black"], row["ssim_white"]), "visible_rgb_psnr_db": row["visible_rgb_psnr_db"]})
    result = {"schema_version": 1, "helper_sha256": sha(root / "tools/release/web_import_profile.py"),
              "pack_memory_helper_sha256": sha(root / "tools/release/web_pack_memory.py"),
              "quality_gate": report["thresholds"], "quality_receipt_sha256": sha(output / "quality.json"),
              "max_pack_bytes": 220_000_000,
              "budget_reason": "High-quality599-texture profile retains every runtime asset, original dimensions, exact alpha and existing mipmap policy. Estimated207.5MB pack plus bounded13MB headroom;150MB would require more scope or lower admitted quality.",
              "source_images_changed": False, "assets": assets}
    destination = root / "data/web/ui_import_profile.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, indent=2) + "\n")
    return {"profile": str(destination), "sha256": sha(destination), "count": len(assets), "max_pack_bytes": result["max_pack_bytes"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("prepare", "analyze", "profile"))
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--pack", type=Path)
    parser.add_argument("--quality", type=float, default=0.95)
    args = parser.parse_args()
    if args.operation == "prepare":
        if args.pack is None:
            parser.error("prepare requires immutable --pack")
        result = prepare(args.root.resolve(), args.pack.resolve(), args.output.resolve(), args.quality)
    elif args.operation == "analyze":
        result = analyze(args.output.resolve())
    else:
        result = write_profile(args.root.resolve(), args.output.resolve())
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
