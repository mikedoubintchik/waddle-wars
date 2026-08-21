#!/usr/bin/env python3
"""Validate Waddle Wars authored-art manifests without third-party packages."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import struct
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
RUNTIME_MANIFEST = ROOT / "assets/art/art_manifest.json"
SOURCE_MANIFEST = ROOT / "art_src/runner/source_manifest.json"
BLENDER_VERSION_FILE = ROOT / "art_src/runner/BLENDER_VERSION"
RUNTIME_SCHEMA = ROOT / "assets/art/art_manifest.schema.json"
SOURCE_SCHEMA = ROOT / "art_src/runner/source_manifest.schema.json"
ART_PACKAGE = ROOT / "tools/art/package.json"
ART_PACKAGE_LOCK = ROOT / "tools/art/package-lock.json"
GLTF_VALIDATOR_SCRIPT = ROOT / "tools/art/validate_glb.mjs"
CHARACTER_LOOK_SCRIPT = ROOT / "scripts/art/character_look.gd"

SCHEMA_VERSION = 1
BLENDER_VERSION = "5.2.0"
GLTF_VALIDATOR_VERSION = "2.0.0-dev.3.10"
ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
ALLOWED_KINDS = {
    "scene",
    "animation_library",
    "material",
    "texture",
    "mesh",
    "resource",
}
EXPECTED_BUDGETS: dict[str, int] = {
    "character_deform_bones_max": 36,
    "character_lod0_triangles_max": 25_000,
    "character_lod0_triangles_min": 18_000,
    "character_skin_influences_max": 4,
    "character_surfaces_max": 2,
    "distinct_shader_signatures_max": 16,
    "draw_calls_high_average_max": 250,
    "draw_calls_high_peak_max": 300,
    "draw_calls_low_average_max": 190,
    "draw_calls_low_peak_max": 225,
    "draw_calls_medium_average_max": 205,
    "draw_calls_medium_peak_max": 250,
    "landmark_lod0_triangles_max": 30_000,
    "landmark_lod0_triangles_min": 10_000,
    "landmark_surfaces_max": 3,
    "obstacle_lod0_triangles_max": 5_000,
    "obstacle_lod0_triangles_min": 1_500,
    "obstacle_surfaces_max": 1,
    "regular_texture_size_max": 2_048,
    "repeated_prop_lod0_triangles_max": 1_500,
    "repeated_prop_lod0_triangles_min": 300,
    "repeated_prop_surfaces_max": 1,
    "runner_authored_compressed_mib_max": 40,
    "runner_texture_vram_mib_max": 64,
    "runner_vertical_slice_compressed_mib_max": 15,
    "total_authored_art_compressed_mib_max": 120,
    "visible_primitives_high_max": 100_000,
    "visible_primitives_low_max": 50_000,
    "visible_primitives_medium_max": 75_000,
}
ASSET_CLASS_BUDGETS: dict[str, dict[str, int]] = {
    "character": {
        "lod0_triangles_min": 18_000,
        "lod0_triangles_max": 25_000,
        "surfaces_max": 2,
    },
    "obstacle": {
        "lod0_triangles_min": 1_500,
        "lod0_triangles_max": 5_000,
        "surfaces_max": 1,
    },
    "repeated_prop": {
        "lod0_triangles_min": 300,
        "lod0_triangles_max": 1_500,
        "surfaces_max": 1,
    },
    "landmark": {
        "lod0_triangles_min": 10_000,
        "lod0_triangles_max": 30_000,
        "surfaces_max": 3,
    },
}
CHARACTER_REQUIRED_ANIMATIONS = sorted(
    {
        "celebration",
        "countdown_idle",
        "defeat",
        "fidget",
        "hit_left",
        "hit_right",
        "jump_air",
        "jump_land",
        "jump_takeoff",
        "lean_left",
        "lean_right",
        "ramp_flip",
        "ramp_land",
        "ramp_launch",
        "recover",
        "run",
        "shove",
        "slide_enter",
        "slide_exit",
        "slide_loop",
        "stumble",
        "swim",
        "wipeout",
    }
)
CHARACTER_REQUIRED_SOCKETS = ["face_socket", "head_socket", "neck_socket", "trail_socket"]
INFRASTRUCTURE_FILES = {
    "README.md",
    "LICENSES.md",
    "art_manifest.json",
    "art_manifest.schema.json",
}
KIND_EXTENSIONS = {
    "scene": {".glb", ".gltf", ".tscn", ".scn"},
    "animation_library": {".glb", ".gltf", ".tres", ".res"},
    "material": {".tres", ".res"},
    "texture": {".png", ".webp", ".jpg", ".jpeg", ".svg"},
    "mesh": {".glb", ".gltf", ".tres", ".res"},
    "resource": {".tres", ".res"},
}


def canonical_json(data: Any) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def png_dimensions(path: Path) -> tuple[int, int] | None:
    try:
        header = path.read_bytes()[:24]
    except OSError:
        return None
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", header[16:24])


def res_path_to_file(value: str) -> Path | None:
    if not value.startswith("res://"):
        return None
    candidate = (ROOT / value.removeprefix("res://")).resolve()
    try:
        candidate.relative_to(ROOT.resolve())
    except ValueError:
        return None
    return candidate


def strict_int(value: Any) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def positive_number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    return number if math.isfinite(number) and number > 0.0 else None


def gdscript_string_array(path: Path, constant_name: str) -> list[str] | None:
    try:
        source = path.read_text(encoding="utf-8")
    except OSError:
        return None
    match = re.search(
        rf"const\s+{re.escape(constant_name)}\s*:\s*PackedStringArray\s*=\s*\[(.*?)\n\]",
        source,
        re.DOTALL,
    )
    if match is None:
        return None
    return re.findall(r'"([a-z][a-z0-9_]*)"', match.group(1))


def gdscript_int_constant(path: Path, constant_name: str) -> int | None:
    try:
        source = path.read_text(encoding="utf-8")
    except OSError:
        return None
    match = re.search(
        rf"^const\s+{re.escape(constant_name)}\s*:\s*int\s*=\s*([0-9][0-9_]*)\s*$",
        source,
        re.MULTILINE,
    )
    return int(match.group(1).replace("_", "")) if match is not None else None


class ArtValidator:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.notes: list[str] = []
        self.runtime: dict[str, Any] = {}
        self.source: dict[str, Any] = {}

    def error(self, message: str) -> None:
        self.errors.append(message)

    def note(self, message: str) -> None:
        self.notes.append(message)

    def load_json(self, path: Path, label: str) -> dict[str, Any]:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            self.error(f"{label} missing: {path.relative_to(ROOT)}")
            return {}
        except (OSError, json.JSONDecodeError) as exc:
            self.error(f"{label} cannot be read: {exc}")
            return {}
        if not isinstance(data, dict):
            self.error(f"{label} root must be an object")
            return {}
        return data

    def validate(self) -> bool:
        for schema, label in ((RUNTIME_SCHEMA, "runtime schema"), (SOURCE_SCHEMA, "source schema")):
            self.load_json(schema, label)
        self.runtime = self.load_json(RUNTIME_MANIFEST, "runtime manifest")
        self.source = self.load_json(SOURCE_MANIFEST, "source manifest")
        if self.runtime:
            self._validate_runtime()
        if self.source:
            self._validate_source()
        self._validate_cross_manifest()
        self._validate_repository_contract()
        return not self.errors

    def format_manifests(self) -> None:
        for path in (RUNTIME_MANIFEST, SOURCE_MANIFEST):
            data = self.load_json(path, str(path.relative_to(ROOT)))
            if data:
                path.write_text(canonical_json(data), encoding="utf-8")

    def _validate_canonical(self, path: Path, data: dict[str, Any], label: str) -> None:
        try:
            actual = path.read_text(encoding="utf-8")
        except OSError as exc:
            self.error(f"{label} cannot be reread: {exc}")
            return
        if actual != canonical_json(data):
            self.error(f"{label} is not canonical; run tools/art/validate_art.py --format")

    def _validate_runtime(self) -> None:
        data = self.runtime
        self._validate_canonical(RUNTIME_MANIFEST, data, "runtime manifest")
        if data.get("schema_version") != SCHEMA_VERSION:
            self.error(f"runtime schema_version must be {SCHEMA_VERSION}")
        if not ID_RE.fullmatch(str(data.get("catalog_id", ""))):
            self.error("runtime catalog_id must be lower_snake_case")

        toolchain = data.get("toolchain")
        if not isinstance(toolchain, dict):
            self.error("runtime toolchain must be an object")
        else:
            if toolchain.get("blender") != BLENDER_VERSION:
                self.error(f"runtime Blender pin must be {BLENDER_VERSION}")
            if toolchain.get("godot") != "4.7.1":
                self.error("runtime Godot pin must be 4.7.1")

        renderer = data.get("renderer_contract")
        if not isinstance(renderer, dict):
            self.error("renderer_contract must be an object")
        else:
            required = renderer.get("required", [])
            if renderer.get("web") != "gl_compatibility":
                self.error("web renderer contract must be gl_compatibility")
            if renderer.get("native") != "mobile":
                self.error("native renderer contract must be mobile")
            if not isinstance(required, list) or not {"gl_compatibility", "mobile"}.issubset(required):
                self.error("renderer required list must contain gl_compatibility and mobile")
            elif required != sorted(set(required)):
                self.error("renderer required list must be sorted and unique")

        budgets = data.get("budgets")
        if not isinstance(budgets, dict):
            self.error("budgets must be an object")
        else:
            for key, expected in EXPECTED_BUDGETS.items():
                if budgets.get(key) != expected:
                    self.error(f"budget {key} must be {expected}, got {budgets.get(key)!r}")
            unknown = sorted(set(budgets) - set(EXPECTED_BUDGETS))
            if unknown:
                self.error(f"unknown budget keys: {', '.join(unknown)}")

        license_ids: set[str] = set()
        licenses = data.get("licenses")
        if not isinstance(licenses, list) or not licenses:
            self.error("licenses must be a non-empty array")
        else:
            for entry in licenses:
                if not isinstance(entry, dict):
                    self.error("license entry must be an object")
                    continue
                license_id = str(entry.get("id", ""))
                if not ID_RE.fullmatch(license_id):
                    self.error(f"invalid license ID: {license_id!r}")
                if license_id in license_ids:
                    self.error(f"duplicate license ID: {license_id}")
                license_ids.add(license_id)
                notice = res_path_to_file(str(entry.get("notice_path", "")))
                if notice is None or not notice.is_file():
                    self.error(f"license {license_id} notice_path is missing or unsafe")

        assets = data.get("assets")
        if not isinstance(assets, list):
            self.error("assets must be an array")
            return
        ids: list[str] = []
        paths: set[str] = set()
        for entry in assets:
            if not isinstance(entry, dict):
                self.error("asset entry must be an object")
                continue
            asset_id = str(entry.get("id", ""))
            ids.append(asset_id)
            if not ID_RE.fullmatch(asset_id):
                self.error(f"invalid asset ID: {asset_id!r}")
            kind = str(entry.get("kind", ""))
            if kind not in ALLOWED_KINDS:
                self.error(f"asset {asset_id} has invalid kind {kind!r}")
            path_value = str(entry.get("path", ""))
            path = res_path_to_file(path_value)
            if path is None or not path_value.startswith("res://assets/art/"):
                self.error(f"asset {asset_id} path must stay below res://assets/art/")
            elif not path.is_file():
                self.error(f"asset {asset_id} file missing: {path_value}")
            else:
                allowed_ext = KIND_EXTENSIONS.get(kind, set())
                if path.suffix.lower() not in allowed_ext:
                    self.error(f"asset {asset_id} extension {path.suffix} invalid for {kind}")
                expected_hash = str(entry.get("sha256", ""))
                if not SHA_RE.fullmatch(expected_hash):
                    self.error(f"asset {asset_id} has invalid sha256")
                elif file_sha256(path) != expected_hash:
                    self.error(f"asset {asset_id} sha256 does not match file")
            if path_value in paths:
                self.error(f"multiple asset IDs use path {path_value}")
            paths.add(path_value)
            groups = entry.get("groups")
            if not isinstance(groups, list) or any(not ID_RE.fullmatch(str(group)) for group in groups):
                self.error(f"asset {asset_id} groups must be lower_snake_case array")
            elif groups != sorted(set(groups)):
                self.error(f"asset {asset_id} groups must be sorted and unique")
            if kind == "texture" and isinstance(groups, list) and "frontend" in groups \
                    and path is not None and path.is_file():
                import_path = path.with_name(path.name + ".import")
                try:
                    import_settings = import_path.read_text(encoding="utf-8")
                except OSError:
                    self.error(f"frontend texture {asset_id} is missing Godot import settings")
                else:
                    if "compress/mode=2" not in import_settings:
                        self.error(f"frontend texture {asset_id} must use VRAM compression")
                    if "mipmaps/generate=true" not in import_settings:
                        self.error(f"frontend texture {asset_id} must generate mipmaps")
            if str(entry.get("license_id", "")) not in license_ids:
                self.error(f"asset {asset_id} uses unknown license_id")
            if entry.get("production_ready") is not True:
                self.error(f"asset {asset_id} must be production_ready=true before registration")
            if not ID_RE.fullmatch(str(entry.get("source_export_id", ""))):
                self.error(f"asset {asset_id} source_export_id is invalid")
        if ids != sorted(ids):
            self.error("runtime assets must be sorted by ID")
        if len(ids) != len(set(ids)):
            self.error("runtime asset IDs must be unique")

        registered_files = {res_path_to_file(value) for value in paths}
        for path in (ROOT / "assets/art").rglob("*"):
            if not path.is_file() or path.name in INFRASTRUCTURE_FILES:
                continue
            if path.suffix in {".import", ".uid"}:
                continue
            if path not in registered_files:
                self.error(f"unregistered runtime art file: {path.relative_to(ROOT)}")

    def _validate_source(self) -> None:
        data = self.source
        self._validate_canonical(SOURCE_MANIFEST, data, "source manifest")
        if data.get("schema_version") != SCHEMA_VERSION:
            self.error(f"source schema_version must be {SCHEMA_VERSION}")
        if data.get("blender_version") != BLENDER_VERSION:
            self.error(f"source Blender pin must be {BLENDER_VERSION}")

        exports = data.get("exports")
        if not isinstance(exports, list):
            self.error("source exports must be an array")
            exports = []
        export_ids: list[str] = []
        source_files: set[Path] = set()
        output_files: set[Path] = set()
        runtime_license_ids = {
            str(entry.get("id", ""))
            for entry in self.runtime.get("licenses", [])
            if isinstance(entry, dict)
        }
        for job in exports:
            if not isinstance(job, dict):
                self.error("source export job must be an object")
                continue
            job_id = str(job.get("id", ""))
            export_ids.append(job_id)
            if not ID_RE.fullmatch(job_id):
                self.error(f"invalid export job ID: {job_id!r}")
            asset_class = str(job.get("asset_class", ""))
            if asset_class not in ASSET_CLASS_BUDGETS:
                self.error(f"export {job_id} has invalid asset_class {asset_class!r}")
            if job.get("forward_axis") != "-Z":
                self.error(f"export {job_id} forward_axis must be -Z")
            if str(job.get("license_id", "")) not in runtime_license_ids:
                self.error(f"export {job_id} uses unknown license_id")
            collection = str(job.get("collection", ""))
            if not ID_RE.fullmatch(collection):
                self.error(f"export {job_id} collection must be lower_snake_case")
            source = (ROOT / str(job.get("source", ""))).resolve()
            output = (ROOT / str(job.get("output", ""))).resolve()
            try:
                source.relative_to((ROOT / "art_src").resolve())
            except ValueError:
                self.error(f"export {job_id} source must stay below art_src")
            if source.suffix.lower() != ".blend" or not source.is_file():
                self.error(f"export {job_id} source .blend is missing")
            else:
                source_hash = str(job.get("source_sha256", ""))
                if not SHA_RE.fullmatch(source_hash) or file_sha256(source) != source_hash:
                    self.error(f"export {job_id} source_sha256 is invalid or stale")
            try:
                output.relative_to((ROOT / "assets/art").resolve())
            except ValueError:
                self.error(f"export {job_id} output must stay below assets/art")
            if output.suffix.lower() != ".glb":
                self.error(f"export {job_id} output must be .glb")
            if output in output_files:
                self.error(f"duplicate export output: {output.relative_to(ROOT)}")
            source_files.add(source)
            output_files.add(output)
            expected = job.get("expected")
            if not isinstance(expected, dict):
                self.error(f"export {job_id} expected budgets must be an object")
            else:
                triangle_min = strict_int(expected.get("lod0_triangles_min"))
                triangle_max = strict_int(expected.get("lod0_triangles_max"))
                if triangle_min is None or triangle_max is None \
                        or triangle_min <= 0 or triangle_max < triangle_min:
                    self.error(f"export {job_id} triangle range is invalid")
                surfaces_max = strict_int(expected.get("surfaces_max"))
                if surfaces_max is None or surfaces_max <= 0:
                    self.error(f"export {job_id} surfaces_max must be positive")
                influences_max = strict_int(expected.get("skin_influences_max", 0))
                if influences_max is None or influences_max < 0 or influences_max > 4:
                    self.error(f"export {job_id} skin_influences_max exceeds 4")
                contract = ASSET_CLASS_BUDGETS.get(asset_class, {})
                for key, value in contract.items():
                    if strict_int(expected.get(key)) != value:
                        self.error(f"export {job_id} {key} must be {value} for {asset_class}")
                bounds = expected.get("bounds_meters_max")
                if not isinstance(bounds, list) or len(bounds) != 3 \
                        or any(positive_number(value) is None for value in bounds):
                    self.error(f"export {job_id} bounds_meters_max must be three positive values")
                if expected.get("pivot_policy") not in {"center", "ground_center"}:
                    self.error(f"export {job_id} pivot_policy is invalid")
                if positive_number(expected.get("pivot_tolerance_m")) is None:
                    self.error(f"export {job_id} pivot_tolerance_m must be positive")
                texture_max = strict_int(expected.get("texture_size_max"))
                if texture_max is None or texture_max <= 0 or texture_max > 2_048 \
                        or texture_max & (texture_max - 1):
                    self.error(f"export {job_id} texture_size_max must be power-of-two <= 2048")
                for list_key in ("required_animations", "required_sockets"):
                    values = expected.get(list_key, [])
                    if not isinstance(values, list) \
                            or any(not ID_RE.fullmatch(str(value)) for value in values) \
                            or values != sorted(set(values)):
                        self.error(f"export {job_id} {list_key} must be sorted and unique")
                if bool(job.get("export_animations", False)) \
                        and not expected.get("required_animations"):
                    self.error(f"export {job_id} animations require required_animations")
                if asset_class == "character":
                    if job.get("export_animations") is not True:
                        self.error(f"export {job_id} character must export animations")
                    if strict_int(expected.get("deform_bones_max")) != 36:
                        self.error(f"export {job_id} character deform_bones_max must be 36")
                    if strict_int(expected.get("skin_influences_max")) != 4:
                        self.error(f"export {job_id} character skin_influences_max must be 4")
                    if expected.get("required_animations") != CHARACTER_REQUIRED_ANIMATIONS:
                        self.error(
                            f"export {job_id} character required_animations must match CharacterLook"
                        )
                    if expected.get("required_sockets") != CHARACTER_REQUIRED_SOCKETS:
                        self.error(
                            f"export {job_id} character required_sockets must match CharacterLook"
                        )
        if export_ids != sorted(export_ids):
            self.error("source exports must be sorted by ID")
        if len(export_ids) != len(set(export_ids)):
            self.error("source export IDs must be unique")
        for path in (ROOT / "art_src").rglob("*.blend"):
            if path.resolve() not in source_files:
                self.error(f"unregistered Blender source: {path.relative_to(ROOT)}")

        concepts = data.get("concepts")
        if not isinstance(concepts, list):
            self.error("source concepts must be an array")
            concepts = []
        concept_ids: list[str] = []
        concept_files: set[Path] = set()
        for entry in concepts:
            if not isinstance(entry, dict):
                self.error("concept entry must be an object")
                continue
            concept_id = str(entry.get("id", ""))
            concept_ids.append(concept_id)
            if not ID_RE.fullmatch(concept_id):
                self.error(f"invalid concept ID: {concept_id!r}")
            path = (ROOT / str(entry.get("path", ""))).resolve()
            prompt_path = (ROOT / str(entry.get("prompt_path", ""))).resolve()
            # Concepts may sit beside the source they direct (runner kit,
            # characters, UI studies). The schema already permits any art_src
            # path, so runtime validation must enforce the same safe root instead
            # of hard-coding the first runner concept directory.
            concept_root = (ROOT / "art_src").resolve()
            for candidate, label in ((path, "path"), (prompt_path, "prompt_path")):
                try:
                    candidate.relative_to(concept_root)
                except ValueError:
                    self.error(f"concept {concept_id} {label} must stay below art_src")
            if not path.is_file():
                self.error(f"concept {concept_id} image is missing")
            else:
                expected_hash = str(entry.get("sha256", ""))
                if not SHA_RE.fullmatch(expected_hash) or file_sha256(path) != expected_hash:
                    self.error(f"concept {concept_id} sha256 is invalid or stale")
                dimensions = entry.get("dimensions")
                actual_dimensions = png_dimensions(path)
                if not isinstance(dimensions, list) or tuple(dimensions) != actual_dimensions:
                    self.error(f"concept {concept_id} dimensions do not match PNG")
            if not prompt_path.is_file():
                self.error(f"concept {concept_id} prompt provenance is missing")
            if entry.get("status") != "art_direction_only":
                self.error(f"concept {concept_id} must remain art_direction_only")
            if not DATE_RE.fullmatch(str(entry.get("generated_on", ""))):
                self.error(f"concept {concept_id} generated_on must be ISO date")
            if not str(entry.get("generator", "")).strip():
                self.error(f"concept {concept_id} generator is required")
            if str(entry.get("license_id", "")) not in runtime_license_ids:
                self.error(f"concept {concept_id} uses unknown license_id")
            concept_files.add(path)
        if concept_ids != sorted(concept_ids):
            self.error("source concepts must be sorted by ID")
        if len(concept_ids) != len(set(concept_ids)):
            self.error("source concept IDs must be unique")
        # A sibling `.prompt.md` marks a non-runtime PNG as a generated concept.
        # UI production images are audited separately below; texture sources do
        # not carry prompt records and therefore are not misclassified here.
        for path in (ROOT / "art_src").rglob("*.png"):
            if path.is_relative_to(ROOT / "art_src/ui"):
                continue
            prompt = path.with_suffix(".prompt.md")
            if prompt.is_file() and path.resolve() not in concept_files:
                self.error(f"unregistered concept image: {path.relative_to(ROOT)}")

        # Production 2D art has no Blender export job, but it still needs the
        # same immutable source/prompt/hash/license chain as a GLB. Keep those
        # records explicit instead of inventing fake Blender collections just
        # to satisfy the runtime manifest's historical source_export_id name.
        generated_assets = data.get("generated_assets")
        if not isinstance(generated_assets, list):
            self.error("generated_assets must be an array")
            generated_assets = []
        generated_ids: list[str] = []
        generated_files: set[Path] = set()
        generated_root = (ROOT / "art_src/ui").resolve()
        for entry in generated_assets:
            if not isinstance(entry, dict):
                self.error("generated asset entry must be an object")
                continue
            generated_id = str(entry.get("id", ""))
            generated_ids.append(generated_id)
            if not ID_RE.fullmatch(generated_id):
                self.error(f"invalid generated asset ID: {generated_id!r}")
            path = (ROOT / str(entry.get("path", ""))).resolve()
            prompt_path = (ROOT / str(entry.get("prompt_path", ""))).resolve()
            for candidate, label in ((path, "path"), (prompt_path, "prompt_path")):
                try:
                    candidate.relative_to(generated_root)
                except ValueError:
                    self.error(
                        f"generated asset {generated_id} {label} must stay below art_src/ui"
                    )
            if not path.is_file():
                self.error(f"generated asset {generated_id} image is missing")
            else:
                expected_hash = str(entry.get("sha256", ""))
                if not SHA_RE.fullmatch(expected_hash) or file_sha256(path) != expected_hash:
                    self.error(f"generated asset {generated_id} sha256 is invalid or stale")
                dimensions = entry.get("dimensions")
                actual_dimensions = png_dimensions(path)
                if not isinstance(dimensions, list) or tuple(dimensions) != actual_dimensions:
                    self.error(
                        f"generated asset {generated_id} dimensions do not match PNG"
                    )
            if not prompt_path.is_file():
                self.error(f"generated asset {generated_id} prompt provenance is missing")
            if entry.get("status") != "production_source":
                self.error(f"generated asset {generated_id} must be production_source")
            if not DATE_RE.fullmatch(str(entry.get("generated_on", ""))):
                self.error(f"generated asset {generated_id} generated_on must be ISO date")
            if not str(entry.get("generator", "")).strip():
                self.error(f"generated asset {generated_id} generator is required")
            if str(entry.get("license_id", "")) not in runtime_license_ids:
                self.error(f"generated asset {generated_id} uses unknown license_id")
            generated_files.add(path)
        if generated_ids != sorted(generated_ids):
            self.error("generated asset IDs must be sorted")
        if len(generated_ids) != len(set(generated_ids)):
            self.error("generated asset IDs must be unique")
        for path in (ROOT / "art_src/ui").rglob("*.png"):
            if path.resolve() not in generated_files:
                self.error(f"unregistered generated source: {path.relative_to(ROOT)}")

    def _validate_cross_manifest(self) -> None:
        if not self.runtime or not self.source:
            return
        source_ids = {
            str(job.get("id", ""))
            for job in self.source.get("exports", [])
            if isinstance(job, dict)
        }
        source_ids.update(
            str(entry.get("id", ""))
            for entry in self.source.get("generated_assets", [])
            if isinstance(entry, dict)
        )
        for entry in self.runtime.get("assets", []):
            if not isinstance(entry, dict):
                continue
            source_export_id = str(entry.get("source_export_id", ""))
            if source_export_id not in source_ids:
                self.error(
                    f"runtime asset {entry.get('id')} references unknown source {source_export_id}"
                )

    def _validate_repository_contract(self) -> None:
        try:
            pinned = BLENDER_VERSION_FILE.read_text(encoding="utf-8").strip()
        except OSError as exc:
            self.error(f"Blender version pin cannot be read: {exc}")
        else:
            if pinned != BLENDER_VERSION:
                self.error(f"BLENDER_VERSION must be exactly {BLENDER_VERSION}")
        if not (ROOT / "art_src/.gdignore").is_file():
            self.error("art_src/.gdignore is required")
        attributes_path = ROOT / ".gitattributes"
        try:
            attributes = attributes_path.read_text(encoding="utf-8")
        except OSError:
            self.error(".gitattributes is required for authored source LFS")
        else:
            for pattern in ("art_src/**/*.blend", "art_src/**/*.kra", "art_src/**/*.exr", "art_src/**/*.png"):
                if pattern not in attributes or "filter=lfs" not in attributes:
                    self.error(f"Git LFS pattern missing: {pattern}")
        package = self.load_json(ART_PACKAGE, "art validator package")
        lock = self.load_json(ART_PACKAGE_LOCK, "art validator package lock")
        if package.get("dependencies", {}).get("gltf-validator") != GLTF_VALIDATOR_VERSION:
            self.error(f"gltf-validator dependency must pin {GLTF_VALIDATOR_VERSION}")
        locked = lock.get("packages", {}).get("node_modules/gltf-validator", {})
        if locked.get("version") != GLTF_VALIDATOR_VERSION:
            self.error(f"package lock must pin gltf-validator {GLTF_VALIDATOR_VERSION}")
        if not GLTF_VALIDATOR_SCRIPT.is_file():
            self.error("tools/art/validate_glb.mjs is required")
        character_animations = gdscript_string_array(
            CHARACTER_LOOK_SCRIPT, "REQUIRED_ANIMATIONS"
        )
        if character_animations is None:
            self.error("CharacterLook REQUIRED_ANIMATIONS cannot be read")
        elif len(character_animations) != len(set(character_animations)) \
                or sorted(character_animations) != CHARACTER_REQUIRED_ANIMATIONS:
            self.error("CharacterLook REQUIRED_ANIMATIONS drifted from art source contract")
        character_sockets = gdscript_string_array(CHARACTER_LOOK_SCRIPT, "REQUIRED_SOCKETS")
        if character_sockets is None:
            self.error("CharacterLook REQUIRED_SOCKETS cannot be read")
        elif len(character_sockets) != len(set(character_sockets)) \
                or sorted(character_sockets) != CHARACTER_REQUIRED_SOCKETS:
            self.error("CharacterLook REQUIRED_SOCKETS drifted from art source contract")
        character_budget_constants = {
            "MAX_DEFORM_BONES": "character_deform_bones_max",
            "MAX_LOD0_TRIANGLES": "character_lod0_triangles_max",
            "MAX_SKIN_INFLUENCES": "character_skin_influences_max",
            "MAX_SURFACES": "character_surfaces_max",
            "MIN_LOD0_TRIANGLES": "character_lod0_triangles_min",
        }
        for constant_name, budget_name in character_budget_constants.items():
            value = gdscript_int_constant(CHARACTER_LOOK_SCRIPT, constant_name)
            if value != EXPECTED_BUDGETS[budget_name]:
                self.error(
                    f"CharacterLook {constant_name} must be {EXPECTED_BUDGETS[budget_name]}"
                )
        runtime_schema = self.load_json(RUNTIME_SCHEMA, "runtime schema")
        source_schema = self.load_json(SOURCE_SCHEMA, "source schema")
        runtime_budget_schema = runtime_schema.get("properties", {}).get("budgets", {})
        schema_budget_keys = set(runtime_budget_schema.get("properties", {})) \
            if isinstance(runtime_budget_schema, dict) else set()
        if schema_budget_keys != set(EXPECTED_BUDGETS):
            self.error("runtime schema budget keys must exactly match validator budgets")
        export_item = source_schema.get("properties", {}).get("exports", {}).get("items", {})
        if isinstance(export_item, dict):
            export_properties = export_item.get("properties", {})
            export_required = export_item.get("required", [])
            if not isinstance(export_properties, dict) or not isinstance(export_required, list) \
                    or not set(export_required).issubset(export_properties):
                self.error("source schema export required fields must all be declared properties")
            asset_enum = export_properties.get("asset_class", {}).get("enum", []) \
                if isinstance(export_properties, dict) else []
            if asset_enum != sorted(ASSET_CLASS_BUDGETS):
                self.error("source schema asset_class enum drifted from validator")
            schema_class_contracts: dict[str, dict[str, Any]] = {}
            for condition in export_item.get("allOf", []):
                if not isinstance(condition, dict):
                    continue
                asset_class = condition.get("if", {}).get("properties", {}) \
                    .get("asset_class", {}).get("const")
                expected_properties = condition.get("then", {}).get("properties", {}) \
                    .get("expected", {}).get("properties", {})
                if isinstance(asset_class, str) and isinstance(expected_properties, dict):
                    schema_class_contracts[asset_class] = expected_properties
            for asset_class, contract in ASSET_CLASS_BUDGETS.items():
                schema_contract = schema_class_contracts.get(asset_class, {})
                for key, expected in contract.items():
                    if schema_contract.get(key, {}).get("const") != expected:
                        self.error(
                            f"source schema {asset_class} {key} must be const {expected}"
                        )
            character_schema = schema_class_contracts.get("character", {})
            if character_schema.get("required_animations", {}).get("const") \
                    != CHARACTER_REQUIRED_ANIMATIONS:
                self.error("source schema character clips drifted from CharacterLook")
            if character_schema.get("required_sockets", {}).get("const") \
                    != CHARACTER_REQUIRED_SOCKETS:
                self.error("source schema character sockets drifted from CharacterLook")
        else:
            self.error("source schema exports.items must be an object")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--format", action="store_true", help="canonicalize both manifests before validation")
    parser.add_argument("--quiet", action="store_true", help="only print failures and final result")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    validator = ArtValidator()
    if args.format:
        validator.format_manifests()
        validator.errors.clear()
    ok = validator.validate()
    if not args.quiet:
        for note in validator.notes:
            print(f"[art] NOTE {note}")
    for error in validator.errors:
        print(f"[art] FAIL {error}", file=sys.stderr)
    if ok:
        asset_count = len(validator.runtime.get("assets", []))
        export_count = len(validator.source.get("exports", []))
        concept_count = len(validator.source.get("concepts", []))
        generated_count = len(validator.source.get("generated_assets", []))
        print(
            f"[art] PASS assets={asset_count} exports={export_count} "
            f"generated={generated_count} concepts={concept_count}"
        )
        if asset_count == 0:
            print("[art] NOTE foundation only; no authored runtime assets registered")
        return 0
    print(f"[art] RESULT FAIL ({len(validator.errors)} error(s))", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
