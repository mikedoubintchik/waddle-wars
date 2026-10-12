#!/usr/bin/env python3
"""Isolated local Web runner export and write-once localhost report collector.

prepare copies sources without starting Godot or a browser. build imports and
exports that copy. serve exposes only exported files, bound to 127.0.0.1.
"""

import argparse
import configparser
from datetime import datetime, timezone
import functools
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import math
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ("assets", "data", "scenes", "scripts", "tests")
RUNNER_QA_ADAPTER_FILES = (
    "runner_perf_probe.gd", "runner_web_perf.gd", "runner_web_perf.tscn",
    "runner_web_clock.gd", "runner_web_mesh_preflight.gd",
)
MAX_REPORT_BYTES = 4 * 1024 * 1024
MAX_TRACE_BYTES = 32 * 1024 * 1024
CANVAS_POLICIES = ("fixed", "production")
ENTRY_MODES = ("runner", "app")
MAX_TEMPLATE_BYTES = 256 * 1024 * 1024
PRODUCTION_CANVAS_SCRIPTS = (
    ("// Phone browsers hand the page a viewport that changes size while you play:",
     "a38fe68851d30814af56e66bffe2dcfc8ea7f8fbfe3e2b9ae2f2ca08af8b3753"),
    ("// Canvas sizing, owned by the page.",
     "3f03a8f9d6cf3b74f74bbf4443a32241dbf248f58227aa59009b48ecd09f5bf6"),
    ("// Resolution policy, applied before the engine reads devicePixelRatio.",
     "3bc4c7c27d1a6e8c0cbd826a4f2f384314b464052fa7c193ddff47611f2eeccd"),
)
PRODUCTION_CANVAS_FORBIDDEN = (
    "<script src", "__ww_auth", "__ww_api", "Clerk", "Authorization",
    "fetch(", "webglcontextlost",
)


def write_json(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")


def fingerprint(project):
    entries = {}
    files = [project / "project.godot"]
    for name in RESOURCES:
        files.extend(path for path in (project / name).rglob("*") if path.is_file()
                     and ".godot" not in path.parts and "__pycache__" not in path.parts)
    for path in sorted(files):
        entries[path.relative_to(project).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    signature = "\n".join(f"{name}\t{digest}" for name, digest in entries.items())
    return {"sha256": hashlib.sha256(signature.encode()).hexdigest(), "entries": entries,
            "scope": "All copied assets/data/scenes/scripts/tests files and project.godot before import"}


def _preset_sections(text):
    matches = list(re.finditer(r"(?m)^\[(preset\.\d+(?:\.options)?)\]\s*$", text))
    sections = {}
    for index, match in enumerate(matches):
        name = match.group(1)
        if name in sections:
            raise SystemExit(f"duplicate [{name}] in source export preset")
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        sections[name] = text[match.end():end]
    return sections


def _literal_option(body, key):
    values = re.findall(rf"(?m)^{re.escape(key)}=([^\r\n]*)$", body)
    if len(values) > 1:
        raise SystemExit(f"ambiguous {key} in source export preset")
    return values[0] if values else None


def _quoted_multiline_option(body, key):
    starts = list(re.finditer(rf"(?m)^{re.escape(key)}=", body))
    if len(starts) != 1:
        raise SystemExit(f"expected exactly one {key} in production Web preset")
    cursor = starts[0].end()
    if cursor >= len(body) or body[cursor] != '"':
        raise SystemExit(f"{key} must be a quoted string")
    cursor += 1
    raw = []
    escaped = False
    while cursor < len(body):
        char = body[cursor]
        if char == '"' and not escaped:
            break
        raw.append(char)
        if escaped:
            escaped = False
        elif char == "\\":
            escaped = True
        cursor += 1
    if cursor >= len(body):
        raise SystemExit(f"unterminated {key} in production Web preset")
    line_end = body.find("\n", cursor + 1)
    if line_end < 0:
        line_end = len(body)
    if body[cursor + 1:line_end].strip():
        raise SystemExit(f"unexpected text after {key} quoted value")
    return "".join(raw).replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")


def extract_production_canvas_policy(source):
    preset_path = source / "export_presets.cfg"
    try:
        preset_bytes = preset_path.read_bytes()
        preset_text = preset_bytes.decode("utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise SystemExit("production canvas policy requires readable UTF-8 export_presets.cfg") from error
    sections = _preset_sections(preset_text)
    candidates = []
    for name, body in sections.items():
        if name.endswith(".options"):
            continue
        if (_literal_option(body, "name") == '"Web"'
                and _literal_option(body, "platform") == '"Web"'):
            candidates.append(name)
    if len(candidates) != 1:
        raise SystemExit("expected exactly one production Web export preset")
    options_name = candidates[0] + ".options"
    if options_name not in sections:
        raise SystemExit("production Web export preset options missing")
    head = _quoted_multiline_option(sections[options_name], "html/head_include")
    scripts = [match.group(1) for match in re.finditer(r"<script>([\s\S]*?)</script>", head)]
    selected = []
    selected_indices = []
    receipts = []
    for marker, expected_hash in PRODUCTION_CANVAS_SCRIPTS:
        matches = [(index, script) for index, script in enumerate(scripts)
                   if next((line.strip() for line in script.splitlines() if line.strip()), "") == marker]
        if len(matches) != 1:
            raise SystemExit(f"expected exactly one production canvas script: {marker}")
        index, script = matches[0]
        for forbidden in PRODUCTION_CANVAS_FORBIDDEN:
            if forbidden.lower() in script.lower():
                raise SystemExit(f"forbidden production head content in canvas script: {forbidden}")
        digest = hashlib.sha256(script.encode("utf-8")).hexdigest()
        if digest != expected_hash:
            raise SystemExit(f"production canvas script changed; review and update expected hash: {marker}")
        selected.append(script)
        selected_indices.append(index)
        receipts.append({"marker": marker, "sha256": digest})
    if selected_indices != sorted(selected_indices) or len(set(selected_indices)) != len(selected_indices):
        raise SystemExit("production canvas scripts changed order or overlap")
    fragment = "\n".join(f"<script>{script}</script>" for script in selected)
    return fragment, {
        "mode": "production",
        "source_path": "export_presets.cfg",
        "source_sha256": hashlib.sha256(preset_bytes).hexdigest(),
        "fragment_sha256": hashlib.sha256(fragment.encode("utf-8")).hexdigest(),
        "scripts": receipts,
        "scope": "Exact reviewed viewport, canvas sizing, and DPR policy only; no auth/API/audio/recovery scripts",
        "quality_governor": "Disabled by fixed-tier QA probe; controlled requested-tier workload",
        "complete_production": False,
    }


def read_release_template(path):
    """Read an explicit QA engine artifact, never install it globally."""
    try:
        if not path.is_file() or not 0 < path.stat().st_size <= MAX_TEMPLATE_BYTES:
            raise ValueError("template must be a nonempty ZIP no larger than 256 MiB")
        data = path.read_bytes()
        with zipfile.ZipFile(path) as archive:
            entries = archive.infolist()
            names = [entry.filename for entry in entries]
            if (len(names) != len(set(names)) or "godot.js" not in names
                    or "godot.wasm" not in names
                    or sum(entry.file_size for entry in entries) > MAX_TEMPLATE_BYTES
                    or any(entry.file_size < 0 for entry in entries)
                    or archive.testzip() is not None):
                raise ValueError("invalid or oversized Godot Web template")
    except (OSError, ValueError, RuntimeError, zipfile.BadZipFile) as error:
        raise SystemExit(f"invalid release template: {error}") from error
    return data


def prepare(args):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", args.label):
        raise SystemExit("label must contain 1–64 letters, digits, underscore or hyphen")
    if not (args.source / "project.godot").is_file():
        raise SystemExit("source must contain project.godot")
    try:
        source_project_text = (args.source / "project.godot").read_text()
    except (OSError, UnicodeDecodeError) as error:
        raise SystemExit("source project.godot must be readable UTF-8") from error
    source_names = re.findall(r'(?m)^config/name="([^"]+)"$', source_project_text)
    source_main_scenes = re.findall(r'(?m)^run/main_scene="([^"]+)"$', source_project_text)
    if len(source_names) != 1 or len(source_main_scenes) != 1:
        raise SystemExit("source project must declare exactly one config/name and run/main_scene")
    template_data = None
    if args.template_release is not None:
        if args.debug:
            raise SystemExit("a custom release template requires release mode")
        template_data = read_release_template(args.template_release)
    source_main_scene = source_main_scenes[0]
    canvas_fragment = ""
    canvas_receipt = {
        "mode": "fixed",
        "scope": "QA-owned fixed backing buffer",
        "quality_governor": "Disabled by fixed-tier QA probe",
        "complete_production": False,
    }
    if args.canvas_policy == "production":
        # Validate before creating a run directory. A changed or ambiguous
        # production policy must leave no half-prepared fixture behind.
        canvas_fragment, canvas_receipt = extract_production_canvas_policy(args.source)
    if args.entry == "app":
        canvas_receipt = {**canvas_receipt,
                          "quality_governor": "Original full-app governor preserved; no fixed-tier adapter"}
    parent = ROOT / "qa_shots" / "runner"
    parent.mkdir(parents=True, exist_ok=True)
    out = Path(tempfile.mkdtemp(prefix=f"chrome-{args.label}.", dir=parent))
    project = out / "project"
    project.mkdir()
    template_receipt = None
    if template_data is not None:
        with (out / "engine-template.zip").open("xb") as stream:
            stream.write(template_data)
        template_receipt = {"kind": "custom_release", "copied_path": "engine-template.zip",
                            "source_path": str(args.template_release.resolve()),
                            "sha256": hashlib.sha256(template_data).hexdigest(),
                            "bytes": len(template_data),
                            "scope": "QA-only copied engine ZIP; engine options require its separate build receipt"}
    for name in RESOURCES:
        shutil.copytree(args.source / name, project / name,
                        ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    shutil.copy2(args.source / "project.godot", project / "project.godot")
    source_fingerprint = fingerprint(project)
    run_id = "runner-web-" + uuid.uuid4().hex
    config = {"run_id": run_id, "entry": args.entry,
              "width": args.width, "height": args.height, "threads": args.threads,
              "canvas_policy": args.canvas_policy,
              "canvas_policy_source_sha256": canvas_receipt.get("source_sha256", ""),
              "canvas_policy_fragment_sha256": canvas_receipt.get("fragment_sha256", ""),
              "export_mode": "debug" if args.debug else "release"}
    if template_receipt is not None:
        config["engine_template_sha256"] = template_receipt["sha256"]
    if args.entry == "runner":
        config.update({"tier": args.tier, "warmup": args.warmup,
                       "seconds": args.seconds, "seed": args.seed,
                       "stream_trace": args.stream_trace, "census": args.census,
                       "msaa_override": args.msaa,
                       "render_scale_override": args.render_scale})
        # QA adapter comes from current harness even when runtime sources come
        # from a frozen snapshot. Full-app mode deliberately keeps source main.
        # Keep the adapter and its inherited guards/helpers together. A frozen
        # runtime snapshot must not pair a new adapter with an obsolete base
        # probe or silently omit the real WebGL readback preflight.
        for name in RUNNER_QA_ADAPTER_FILES:
            shutil.copy2(ROOT / "tests" / name, project / "tests" / name)
    else:
        config.update({"diagnostic_scope": "full_app_lifecycle",
                       "quality_governor": "preserved",
                       "performance_gate_applicable": False})
    write_json(project / "tests/runner_web_perf_config.json", config)
    text = (project / "project.godot").read_text()
    lines = [line for line in text.splitlines() if not line.startswith(
        ("config/use_custom_user_dir=", "config/custom_user_dir_name="))]
    updated = []
    for line in lines:
        if args.entry == "runner" and line.startswith("run/main_scene="):
            line = 'run/main_scene="res://tests/runner_web_perf.tscn"'
        if line.startswith("config/name="):
            updated.extend([f'config/name="{run_id}"', "config/use_custom_user_dir=true",
                            f'config/custom_user_dir_name="{run_id}"'])
        elif args.entry == "runner" and line.startswith("renderer/rendering_method="):
            updated.append('renderer/rendering_method="gl_compatibility"')
        else:
            updated.append(line)
    (project / "project.godot").write_text("\n".join(updated) + "\n")
    shell = (ROOT / "tools/qa/runner_web_perf_shell.html").read_text()
    for token in ("@@CANVAS_CSS@@", "@@CANVAS_ATTRIBUTES@@", "@@CANVAS_POLICY_HEAD@@",
                  "@@RUN_CONFIG@@"):
        if shell.count(token) != 1:
            raise SystemExit(f"QA shell must contain exactly one {token}")
    canvas_css = (f"canvas{{display:block;margin:auto;width:min(100vw,{args.width}px);"
                  f"height:auto;aspect-ratio:{args.width}/{args.height}}}")
    canvas_attributes = f' width="{args.width}" height="{args.height}"'
    if args.canvas_policy == "production":
        canvas_css = "canvas{display:block}"
        canvas_attributes = ""
    shell = shell.replace("@@CANVAS_CSS@@", canvas_css)
    shell = shell.replace("@@CANVAS_ATTRIBUTES@@", canvas_attributes)
    shell = shell.replace("@@CANVAS_POLICY_HEAD@@", canvas_fragment)
    shell = shell.replace("@@RUN_CONFIG@@", json.dumps(config))
    (project / "tests/runner_web_perf_shell.html").write_text(shell)
    (project / "export_presets.cfg").write_text(f'''[preset.0]
name="Web Probe"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter="tests/runner_web_perf_config.json,data/wardrobe/*.json,data/commerce/*.json"
exclude_filter=""
script_export_mode=1

[preset.0.options]
{('custom_template/release=' + json.dumps(str((out / 'engine-template.zip').resolve()))) if template_receipt else ''}
variant/extensions_support=false
variant/thread_support={str(config["threads"]).lower()}
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=true
html/custom_html_shell="res://tests/runner_web_perf_shell.html"
html/head_include=""
html/canvas_resize_policy=0
html/focus_canvas_on_start=true
progressive_web_app/enabled=false
''')
    exported_main_scene = ("res://tests/runner_web_perf.tscn"
                           if args.entry == "runner" else source_main_scene)
    manifest = {"prepared_at_utc": datetime.now(timezone.utc).isoformat(),
                "source": str(args.source.resolve()), "run_id": run_id, "config": config,
                "entry": {"mode": args.entry, "source_main_scene": source_main_scene,
                          "export_main_scene": exported_main_scene,
                          "quality_governor": "disabled_by_fixed_tier_adapter"
                              if args.entry == "runner" else "preserved",
                          "performance_gate_applicable": args.entry == "runner"},
                "source_fingerprint": source_fingerprint,
                "export_input_fingerprint": fingerprint(project),
                "export_presets_sha256": hashlib.sha256(
                    (project / "export_presets.cfg").read_bytes()).hexdigest(),
                "canvas_policy": canvas_receipt,
                "original_probe_unchanged": (project / "tests/runner_perf_probe.gd").read_bytes()
                    == (args.source / "tests/runner_perf_probe.gd").read_bytes(),
                "isolation": ("Fresh custom user:// identity; reviewed production canvas policy only; "
                              "no production auth/API bridge; localhost CSP; "
                              + ("original full-app main scene and governor preserved"
                                 if args.entry == "app" else "fixed-tier runner adapter"))
                    if args.canvas_policy == "production" else
                    "Fresh custom user:// identity; no production HTML/auth/API bridge; localhost CSP",
                "cache_scope": "Fresh imported project and user identity; browser/driver shader cache is not cleared"}
    if template_receipt is not None:
        manifest["engine_template"] = template_receipt
    write_json(out / "manifest.json", manifest)
    print(out)
    print("Build:", shlex.join([sys.executable, str(Path(__file__).resolve()), "build", str(out)]))
    print("Serve:", shlex.join([sys.executable, str(Path(__file__).resolve()), "serve", str(out)]))


def validate_export_preset(project, manifest):
    try:
        data = (project / "export_presets.cfg").read_bytes()
    except OSError as error:
        raise SystemExit("export preset unavailable; create a fresh run") from error
    digest = hashlib.sha256(data).hexdigest()
    has_saved_hash = "export_presets_sha256" in manifest
    if has_saved_hash and manifest["export_presets_sha256"] != digest:
        raise SystemExit("export preset changed since prepare; create a fresh run")
    threads = manifest["config"].get("threads", False)
    if type(threads) is not bool:
        raise SystemExit("manifest threads must be a boolean; create a fresh run")
    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = str
    try:
        parser.read_string(data.decode("utf-8"))
    except (UnicodeDecodeError, configparser.Error) as error:
        raise SystemExit("invalid export preset; create a fresh run") from error
    presets = [section for section in parser.sections()
               if re.fullmatch(r"preset\.\d+", section)
               and parser.get(section, "name", fallback=None) == '"Web Probe"']
    if (parser.defaults() or len(presets) != 1
            or parser.get(presets[0], "platform", fallback=None) != '"Web"'):
        raise SystemExit("export preset must identify one Web Probe Web preset; create a fresh run")
    actual = parser.get(presets[0] + ".options", "variant/thread_support", fallback=None)
    if actual != str(threads).lower():
        raise SystemExit("export preset thread mode differs from manifest; create a fresh run")
    custom_template = parser.get(presets[0] + ".options", "custom_template/release", fallback=None)
    template_receipt = manifest.get("engine_template")
    if template_receipt is None:
        if custom_template not in (None, '""') or "engine_template_sha256" in manifest["config"]:
            raise SystemExit("custom engine template is missing its receipt; create a fresh run")
    else:
        expected = (project.parent / "engine-template.zip").resolve()
        if (not isinstance(template_receipt, dict)
                or template_receipt.get("kind") != "custom_release"
                or template_receipt.get("copied_path") != "engine-template.zip"
                or manifest["config"].get("export_mode") != "release"
                or custom_template != json.dumps(str(expected))):
            raise SystemExit("custom engine template receipt or preset mismatch; create a fresh run")
        data = read_release_template(expected)
        digest_template = hashlib.sha256(data).hexdigest()
        if (template_receipt.get("sha256") != digest_template
                or template_receipt.get("bytes") != len(data)
                or manifest["config"].get("engine_template_sha256") != digest_template):
            raise SystemExit("custom engine template changed since prepare; create a fresh run")
    # Old manifests have no original preset hash. Do not imply their other
    # export settings are unchanged just because the thread flag still matches.
    return {"threads": threads, "export_presets_sha256": digest, "engine_template": template_receipt,
            "export_preset_integrity": "prepared_sha256_and_thread_mode" if has_saved_hash
                else "legacy_thread_mode_only"}


def validate_canvas_policy(manifest):
    config = manifest.get("config")
    if not isinstance(config, dict):
        raise SystemExit("manifest config missing; create a fresh run")
    mode = config.get("canvas_policy", "fixed")
    if mode not in CANVAS_POLICIES:
        raise SystemExit("manifest canvas policy invalid; create a fresh run")
    receipt = manifest.get("canvas_policy")
    if not isinstance(receipt, dict) or receipt.get("mode") != mode:
        raise SystemExit("manifest canvas policy receipt mismatch; create a fresh run")
    if receipt.get("complete_production") is not False:
        raise SystemExit("QA canvas policy must never claim complete production")
    source_hash = config.get("canvas_policy_source_sha256", "")
    fragment_hash = config.get("canvas_policy_fragment_sha256", "")
    if mode == "fixed":
        if source_hash != "" or fragment_hash != "":
            raise SystemExit("fixed canvas policy cannot declare production hashes")
    else:
        if (not re.fullmatch(r"[0-9a-f]{64}", str(source_hash))
                or not re.fullmatch(r"[0-9a-f]{64}", str(fragment_hash))
                or receipt.get("source_sha256") != source_hash
                or receipt.get("fragment_sha256") != fragment_hash):
            raise SystemExit("production canvas policy hashes invalid; create a fresh run")
        expected_scripts = [{"marker": marker, "sha256": digest}
                            for marker, digest in PRODUCTION_CANVAS_SCRIPTS]
        if receipt.get("scripts") != expected_scripts:
            raise SystemExit("production canvas script receipt invalid; create a fresh run")
    return receipt


def validate_entry(manifest, project):
    config = manifest.get("config")
    declared_mode = config.get("entry") if isinstance(config, dict) else None
    mode = declared_mode or "runner"
    if mode not in ENTRY_MODES:
        raise SystemExit("manifest entry mode invalid; create a fresh run")
    receipt = manifest.get("entry")
    if receipt is None and declared_mode is None and mode == "runner":
        return {"mode": "runner", "integrity": "legacy_default"}
    if not isinstance(receipt, dict) or receipt.get("mode") != mode:
        raise SystemExit("manifest entry receipt mismatch; create a fresh run")
    if mode == "app" and config.get("canvas_policy") != "production":
        raise SystemExit("app entry requires production canvas policy; create a fresh run")
    expected = ("res://tests/runner_web_perf.tscn" if mode == "runner"
                else receipt.get("source_main_scene"))
    if (not isinstance(expected, str) or not expected.startswith("res://")
            or receipt.get("export_main_scene") != expected
            or receipt.get("quality_governor") !=
                ("disabled_by_fixed_tier_adapter" if mode == "runner" else "preserved")
            or receipt.get("performance_gate_applicable") is not (mode == "runner")):
        raise SystemExit("manifest entry receipt invalid; create a fresh run")
    project_text = (project / "project.godot").read_text()
    declared = re.findall(r'(?m)^run/main_scene="([^"]+)"$', project_text)
    if declared != [expected]:
        raise SystemExit("project main scene differs from entry receipt; create a fresh run")
    return receipt


def build(args):
    out = args.run.resolve()
    manifest = json.loads((out / "manifest.json").read_text())
    project = out / "project"
    if fingerprint(project) != manifest["export_input_fingerprint"]:
        raise SystemExit("export inputs changed since prepare; create a fresh run")
    try:
        embedded_config = json.loads((project / "tests/runner_web_perf_config.json").read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit("embedded runner config invalid; create a fresh run") from error
    manifest_config = manifest.get("config")
    if not isinstance(embedded_config, dict) or not isinstance(manifest_config, dict):
        raise SystemExit("embedded runner config or manifest config invalid; create a fresh run")
    # Thread support predates canvas-policy receipts and was historically
    # optional (absent means false). Preserve that one documented default while
    # still rejecting every actual setting/provenance difference.
    comparable_embedded = {"threads": False, **embedded_config}
    comparable_manifest = {"threads": False, **manifest_config}
    if comparable_embedded != comparable_manifest:
        raise SystemExit("embedded runner config differs from manifest; create a fresh run")
    canvas_receipt = validate_canvas_policy(manifest)
    entry_receipt = validate_entry(manifest, project)
    preset_receipt = validate_export_preset(project, manifest)
    godot = args.godot or shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot"
    web = out / "web"
    web.mkdir()
    mode = "--export-debug" if manifest["config"]["export_mode"] == "debug" else "--export-release"
    commands = [[godot, "--headless", "--audio-driver", "Dummy", "--path", str(project), "--import"],
                [godot, "--headless", "--audio-driver", "Dummy", "--path", str(project), mode, "Web Probe", str(web / "index.html")]]
    for name, command in zip(("import", "export"), commands):
        print(shlex.join(command), flush=True)
        with (out / f"{name}.log").open("x") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=300)
        output = (out / f"{name}.log").read_text()
        if result.returncode or re.search(r"SCRIPT ERROR:|(?:^|\s)ERROR:|Failed loading resource", output):
            raise SystemExit(f"{name} failed; inspect {out / (name + '.log')}")
    write_json(out / "build.json", {"completed_at_utc": datetime.now(timezone.utc).isoformat(),
               "export_mode": manifest["config"]["export_mode"],
               "canvas_policy": canvas_receipt, "entry": entry_receipt,
               **preset_receipt, "commands": commands,
               "files": {path.name: {"bytes": path.stat().st_size,
                          "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                         for path in sorted(web.iterdir()) if path.is_file()}})
    print(f"Build complete: {out}", flush=True)


class Collector(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Content-Security-Policy", "default-src 'self'; connect-src 'self'; "
                         "script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval'; "
                         "style-src 'unsafe-inline'; img-src 'self' data:; worker-src 'self' blob:; "
                         "base-uri 'none'; frame-ancestors 'none'")
        super().end_headers()

    def list_directory(self, path):
        self.send_error(403)
        return None

    def do_POST(self):
        expected_origin = f"http://127.0.0.1:{self.server.server_port}"
        if self.path == "/trace":
            self._post_trace(expected_origin)
            return
        if self.path != "/report":
            self.send_error(404)
            return
        if self.headers.get("Origin") != expected_origin or self.headers.get("Host") != expected_origin[7:]:
            self.send_error(403, "Same-origin localhost report required")
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            size = 0
        if not 0 < size <= MAX_REPORT_BYTES or self.headers.get("Content-Type") != "application/json":
            self.send_error(413, "JSON report must be 1-4194304 bytes")
            return
        self.connection.settimeout(10)
        try:
            payload = json.loads(self.rfile.read(size))
            if not isinstance(payload, dict) or payload.get("run_id") != self.server.run_id:
                raise ValueError("run_id mismatch")
            if not isinstance(payload.get("browser"), dict):
                raise ValueError("browser metadata missing")
            if not isinstance(payload.get("report"), dict) and not isinstance(payload.get("error"), str):
                raise ValueError("report or error missing")
            entry = getattr(self.server, "entry", "runner")
            if entry == "app":
                report = payload.get("report")
                is_error = isinstance(payload.get("error"), str)
                expected_top = ({"run_id", "kind", "browser", "error", "error_source"}
                                if is_error else {"run_id", "kind", "browser", "report"})
                expected_report = {"schema_version", "measurement_kind", "scope",
                                   "performance_gate_applicable", "meets_gate",
                                   "engine_fps_report_present", "complete_production"}
                if (set(payload) != expected_top or payload.get("kind") != "app_lifecycle"
                        or (not is_error and
                            (not isinstance(report, dict) or set(report) != expected_report
                             or report.get("schema_version") != 1
                             or report.get("measurement_kind") != "app_lifecycle"
                             or report.get("performance_gate_applicable") is not False
                             or report.get("meets_gate") is not False
                             or report.get("engine_fps_report_present") is not False
                             or report.get("complete_production") is not False))):
                    raise ValueError("invalid app lifecycle report")
            elif payload.get("kind") == "app_lifecycle":
                raise ValueError("app lifecycle report sent to runner collector")
        except (ValueError, TimeoutError):
            self.send_error(400, "Invalid report")
            return
        try:
            # Exclusive file creation makes reloads and duplicate submissions
            # explicit conflicts rather than silently overwriting evidence.
            write_json(self.server.output / "browser_report.json", payload)
        except FileExistsError:
            self.send_error(409, "Run already recorded; prepare a new run")
            return
        if getattr(self.server, "entry", "runner") != "app" and isinstance(payload.get("report"), dict):
            write_json(self.server.output / "report.json", payload["report"])
            if "csv" in payload:
                with (self.server.output / "report.csv").open("x") as stream:
                    stream.write(str(payload["csv"]))
        self.send_response(201)
        self.end_headers()
        self.wfile.write(b'{"saved":true}')
        print(f"Saved {self.server.output / 'browser_report.json'}", flush=True)

    def _post_trace(self, expected_origin):
        if self.headers.get("Origin") != expected_origin or self.headers.get("Host") != expected_origin[7:]:
            self.send_error(403, "Same-origin localhost trace required")
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            size = 0
        if not 0 < size <= MAX_TRACE_BYTES or self.headers.get("Content-Type") != "application/json":
            self.send_error(413, "JSON trace must be 1-33554432 bytes")
            return
        self.connection.settimeout(10)
        try:
            payload = json.loads(self.rfile.read(size))
            if not isinstance(payload, dict) or payload.get("run_id") != self.server.run_id:
                raise ValueError("run_id mismatch")
            if set(payload) != {"run_id", "target_url", "renderer_pid", "traceEvents", "capture"}:
                raise ValueError("unexpected trace envelope fields")
            if payload.get("target_url") != expected_origin + "/index.html":
                raise ValueError("trace target differs from served page")
            renderer_pid = payload.get("renderer_pid")
            if type(renderer_pid) is not int or renderer_pid <= 0:
                raise ValueError("renderer_pid must be a positive integer")
            events = payload.get("traceEvents")
            if not isinstance(events, list) or any(
                    not isinstance(event, dict) or type(event.get("pid")) is not int
                    or event["pid"] != renderer_pid for event in events):
                raise ValueError("trace contains an event outside the declared renderer")
            if not isinstance(payload.get("capture"), dict):
                raise ValueError("capture metadata missing")
        except (ValueError, TimeoutError, RecursionError):
            self.send_error(400, "Invalid renderer-scoped trace")
            return
        try:
            write_json(self.server.output / "chrome_trace.json", payload)
        except FileExistsError:
            self.send_error(409, "Trace already recorded; prepare a new run")
            return
        self.send_response(201)
        self.end_headers()
        self.wfile.write(b'{"saved":true}')
        print(f"Saved {self.server.output / 'chrome_trace.json'}", flush=True)


def serve(args):
    out = args.run.resolve()
    manifest = json.loads((out / "manifest.json").read_text())
    if not (out / "build.json").is_file():
        raise SystemExit("build.json missing; finish a successful local build first")
    if (out / "browser_report.json").exists():
        raise SystemExit("run already recorded; prepare a fresh run")
    server = ThreadingHTTPServer(("127.0.0.1", args.port),
                                functools.partial(Collector, directory=str(out / "web")))
    server.run_id = manifest["run_id"]
    server.entry = manifest.get("config", {}).get("entry", "runner")
    if server.entry not in ENTRY_MODES:
        server.server_close()
        raise SystemExit("manifest entry mode invalid; create a fresh run")
    server.output = out
    url = f"http://127.0.0.1:{server.server_port}/index.html"
    print(f"Chrome URL: {url}", flush=True)
    print(f"Instrumented URL: {url}?webgltrace=1", flush=True)
    print("Keep tab visible; collector stays open until Ctrl-C.", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prep = commands.add_parser("prepare")
    prep.add_argument("label")
    prep.add_argument("--source", type=Path, default=ROOT)
    prep.add_argument("--entry", choices=ENTRY_MODES, default="runner",
                      help="Standalone runner performance probe (default) or offline full-app lifecycle")
    prep.add_argument("--tier", choices=("high", "medium", "low"), default="high")
    prep.add_argument("--msaa", choices=("default", "off"), default="default",
                      help="Keep tier MSAA request, or isolate its cost with an explicit off request")
    prep.add_argument("--render-scale", type=float, default=None,
                      help="QA-only main-viewport 3D scale override in the finite interval (0, 1]")
    prep.add_argument("--width", type=int, default=1920)
    prep.add_argument("--height", type=int, default=1080)
    prep.add_argument("--warmup", type=float, default=0)
    prep.add_argument("--seconds", type=float, default=60)
    prep.add_argument("--seed", type=int, default=20260907)
    prep.add_argument("--stream-trace", action="store_true")
    prep.add_argument("--census", action="store_true")
    prep.add_argument("--threads", action="store_true",
                      help="QA-only threaded Web export; default remains single-threaded")
    prep.add_argument("--template-release", type=Path,
                      help="Copy and pin an explicit QA-only custom Web release ZIP; no global installation")
    prep.add_argument("--canvas-policy", choices=CANVAS_POLICIES, default=None,
                      help="QA fixed backing or reviewed production canvas/DPR policy; defaults by entry")
    prep.add_argument("--debug", action="store_true", help="Enable review overlays; default release matches production")
    prep.set_defaults(action=prepare)
    builder = commands.add_parser("build")
    builder.add_argument("run", type=Path)
    builder.add_argument("--godot")
    builder.set_defaults(action=build)
    server = commands.add_parser("serve")
    server.add_argument("run", type=Path)
    server.add_argument("--port", type=int, default=0)
    server.set_defaults(action=serve)
    args = parser.parse_args()
    if args.command == "prepare":
        if args.canvas_policy is None:
            args.canvas_policy = "production" if args.entry == "app" else "fixed"
        if args.entry == "app" and args.canvas_policy != "production":
            parser.error("app entry requires reviewed production canvas policy")
        if args.entry == "app" and (args.tier != "high" or args.msaa != "default"
                or args.render_scale is not None or args.warmup != 0 or args.seconds != 60
                or args.seed != 20260907 or args.stream_trace or args.census):
            parser.error("app entry does not accept runner workload or performance-gate controls")
    if args.command == "prepare" and not (320 <= args.width <= 3840 and 320 <= args.height <= 2160
            and 0 <= args.warmup <= 60 and 1 <= args.seconds <= 180):
        parser.error("bounded probe: width 320–3840, height 320–2160, warmup 0–60, seconds 1–180")
    if (args.command == "prepare" and args.render_scale is not None
            and (not math.isfinite(args.render_scale)
                 or not 0.0 < args.render_scale <= 1.0)):
        parser.error("bounded probe: render-scale must be finite and greater than 0 through 1")
    args.action(args)


if __name__ == "__main__":
    main()
