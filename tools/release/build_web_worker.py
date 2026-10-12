#!/usr/bin/env python3
"""Compile a pinned QA-only worker template; never alter game/export settings."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import zipfile

from native_release import sha256


def git_head(folder: Path) -> str:
    return subprocess.check_output(["git", "-C", str(folder), "rev-parse", "HEAD"], text=True).strip()


def validate_template(path: Path) -> None:
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None or not {"godot.js", "godot.wasm"}.issubset(archive.namelist()):
            raise ValueError("Godot template archive is incomplete or corrupt")
        with archive.open("godot.wasm") as wasm:
            if wasm.read(8) != b"\x00asm\x01\x00\x00\x00":
                raise ValueError("Template does not contain a valid WebAssembly module header")


def validate_emitted_sdk_variant(path: Path, variant: str) -> dict:
    """Refuse a stale linked ZIP even when the installed SDK source is correct."""
    if variant not in ("official", "scissor_is_enabled"):
        raise ValueError("Unknown emitted QA SDK variant")
    with zipfile.ZipFile(path) as archive:
        source = archive.read("godot.js").decode("utf-8")
    matches = re.findall(
        r"blitOffscreenFramebuffer\s*:\s*(?:\([^)]*\)|\w+)\s*=>\s*\{\s*"
        r"var\s+\w+\s*=\s*\w+\.GLctx\s*;\s*var\s+prevScissorTest\s*=\s*"
        r"\w+\.(getParameter|isEnabled)\s*\(\s*3089\s*\)", source)
    expected = "getParameter" if variant == "official" else "isEnabled"
    if matches != [expected]:
        raise ValueError("Emitted ZIP does not contain the exact " + variant + " SDK presentation query; stale link is not accepted")
    return {"source_file": "godot.js", "sha256": hashlib.sha256(source.encode()).hexdigest(),
            "scissor_query": expected, "query_enum": 3089, "matching_blitters": len(matches)}


def validate_emitted_readback_variant(path: Path, variant: str) -> dict:
    """Check the actual linked readback function, not just its source input."""
    if variant not in ("official", "current_context"):
        raise ValueError("Unknown emitted QA readback variant")
    with zipfile.ZipFile(path) as archive:
        source = archive.read("godot.js").decode("utf-8")
    definitions = re.findall(
        r"function\s+_godot_webgl2_glGetBufferSubData\s*\(([^)]*)\)\s*"
        r"\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}", source)
    if len(definitions) != 1:
        raise ValueError("Emitted ZIP must contain exactly one WebGL readback function; stale link is not accepted")
    parameters, body = definitions[0]
    arguments = [argument.strip() for argument in parameters.split(",")]
    if len(arguments) != 4 or len(set(arguments)) != 4 or \
            any(not re.fullmatch(r"[A-Za-z_$][\w$]*", argument) for argument in arguments):
        raise ValueError("Emitted WebGL readback must preserve its four distinct arguments")
    ordered_arguments = r"\s*,\s*".join(re.escape(argument) for argument in arguments)
    sync_dispatch = re.match(
        r"\s*if\s*\(\s*ENVIRONMENT_IS_PTHREAD\s*\)\s*return\s+proxyToMainThread\s*"
        r"\(\s*\d+\s*,\s*0\s*,\s*1\s*,\s*" + ordered_arguments + r"\s*\)\s*;", body)
    if not sync_dispatch or len(re.findall(r"\bproxyToMainThread\s*\(", body)) != 1:
        raise ValueError("Emitted WebGL readback must preserve exactly one synchronous worker-to-main dispatch and argument order")
    tls_selector = re.search(r"const\s+\w+\s*=\s*_emscripten_webgl_get_current_context\s*\(\s*\)\s*;\s*"
                             r"const\s+\w+\s*=\s*GL\.getContext\s*\(\s*\w+\s*\)\s*;", body)
    current_selector = re.search(r"const\s+\w+\s*=\s*GL\.currentContext\s*;", body)
    expected = "pthread_tls" if variant == "official" else "GL.currentContext"
    if (variant == "official" and (not tls_selector or current_selector)) or \
            (variant == "current_context" and (not current_selector or tls_selector)) or \
            "getBufferSubData" not in body:
        raise ValueError("Emitted ZIP does not contain the exact " + variant + " WebGL readback selector; stale link is not accepted")
    return {"source_file": "godot.js", "function_sha256": hashlib.sha256(body.encode()).hexdigest(),
            "context_selector": expected, "matching_readbacks": len(definitions),
            "worker_dispatch": "proxyToMainThread", "synchronous_dispatch": True,
            "dispatch_arguments_preserved": True}


def archive_primary_js(source: Path, destination: Path, arch: str) -> dict | None:
    """Force relink, retaining the old exact JS target without touching objects/ZIPs."""
    primary = source / f"bin/godot.web.template_release.{arch}.js"
    if not primary.exists() and not primary.is_symlink():
        return None
    if not primary.is_file() or primary.is_symlink() or primary.parent.is_symlink():
        raise ValueError("Prelink primary JS target must be a regular file, not a symlink")
    archive = destination / "prelink-inputs" / primary.name
    if archive.exists() or archive.is_symlink():
        raise ValueError("Prelink archive target must be new")
    record = {"original_path": str(primary), "archive_path": str(archive),
              "sha256": sha256(primary), "bytes": primary.stat().st_size,
              "purpose": "Missing exact primary JS target forces relink; C++ objects and earlier ZIPs retained"}
    archive.parent.mkdir()
    shutil.move(str(primary), str(archive))
    if sha256(archive) != record["sha256"]:
        raise ValueError("Archived prelink JS hash changed")
    return record


def verify_source_variants(source: Path, lock: dict, variant: str,
                           readback_variant: str = "official") -> tuple[dict, dict]:
    """Accept only the explicitly selected, orthogonal reviewed Godot patches."""
    changed = subprocess.check_output(["git", "-C", str(source), "diff", "--name-status", "HEAD"], text=True).strip()
    results = [{"id": variant, "patches": []}, {"id": readback_variant, "patches": []}]
    selected = []
    for index, (name, inventory) in enumerate([(variant, "qa_variants"), (readback_variant, "qa_readback_variants")]):
        if name == "official":
            continue
        approved = lock.get(inventory, {}).get(name)
        if not approved:
            raise ValueError("Unknown QA source variant" if index == 0 else "Unknown QA readback variant")
        selected.append((index, approved))
    if not selected:
        if changed:
            raise ValueError("Tracked Godot source edits found; official QA variant requires clean source")
        return tuple(results)
    expected = {"M\t" + approved["source_file"] for _, approved in selected}
    if len(expected) != len(selected) or set(changed.splitlines()) != expected:
        raise ValueError("QA variants accept only their exact selected modified source files")
    if subprocess.check_output(["git", "-C", str(source), "diff", "--summary", "HEAD"], text=True).strip():
        raise ValueError("QA variant does not accept source mode, rename or other metadata changes")
    for index, approved in selected:
        name = approved["source_file"]
        patch_path = Path(__file__).parent / approved["patch_file"]
        if sha256(patch_path) != approved["patch_sha256"]:
            raise ValueError("Reviewed QA patch file hash mismatch")
        upstream = subprocess.check_output(["git", "-C", str(source), "show", "HEAD:" + name])
        before = hashlib.sha256(upstream).hexdigest()
        after = sha256(source / name)
        if before != approved["before_sha256"] or after != approved["after_sha256"]:
            raise ValueError("Godot source does not match the exact reviewed before/after patch hashes")
        results[index]["patches"].append({**approved, "verified_before_sha256": before, "verified_after_sha256": after})
    return tuple(results)


def verify_source_variant(source: Path, lock: dict, variant: str) -> dict:
    """Preserve the earlier single-source-variant API and its fail-closed default."""
    return verify_source_variants(source, lock, variant)[0]


def verify_sdk_variant(emsdk: Path, lock: dict, variant: str = "official") -> dict:
    """Hash reviewed installed SDK files; emsdk Git does not track this subtree."""
    reviewed = lock["emsdk"]["reviewed_source_files"]
    approved = None if variant == "official" else lock.get("qa_sdk_variants", {}).get(variant)
    if variant != "official" and not approved:
        raise ValueError("Unknown QA SDK variant")
    if approved and approved["source_file"] not in reviewed:
        raise ValueError("QA SDK patch is outside the reviewed installed source inventory")
    files = []
    patches = []
    for name, original_hash in reviewed.items():
        path = emsdk / name
        if not path.is_file() or path.is_symlink():
            raise ValueError("Reviewed installed SDK source must be a regular file: " + name)
        current_hash = sha256(path)
        expected_hash = approved["after_sha256"] if approved and name == approved["source_file"] else original_hash
        if current_hash != expected_hash:
            raise ValueError("Installed SDK source does not match exact " + variant + " hash: " + name)
        if approved and name == approved["source_file"]:
            patch_path = Path(__file__).parent / approved["patch_file"]
            if sha256(patch_path) != approved["patch_sha256"]:
                raise ValueError("Reviewed QA SDK patch file hash mismatch")
            before_text, after_text = approved["replace_before"], approved["replace_after"]
            candidate = path.read_bytes()
            if candidate.count(after_text.encode()) != 1 or candidate.count(before_text.encode()) != 0:
                raise ValueError("QA SDK variant requires exactly its single reviewed query replacement")
            upstream = candidate.replace(after_text.encode(), before_text.encode(), 1)
            before_hash = hashlib.sha256(upstream).hexdigest()
            if before_hash != original_hash or before_hash != approved["before_sha256"]:
                raise ValueError("Reconstructed SDK baseline does not match pinned original file hash")
            patches.append({**approved, "verified_before_sha256": before_hash,
                            "verified_after_sha256": current_hash,
                            "baseline_verification": "reverse exact one-line replacement, then hash whole file"})
        files.append({"source_file": name, "original_sha256": original_hash,
                      "verified_sha256": current_hash})
    return {"id": variant, "patches": patches, "reviewed_source_files": files,
            "coverage": "Explicit installed SDK file hashes; emsdk Git alone does not cover its installed subtree"}


def reviewed_source_hashes(source: Path, emsdk: Path, lock: dict) -> list[dict]:
    godot_file = lock["qa_variants"]["eval_main_thread"]["source_file"]
    readback_file = lock["qa_readback_variants"]["current_context"]["source_file"]
    return [{"owner": "godot", "source_file": godot_file, "sha256": sha256(source / godot_file)},
            {"owner": "godot", "source_file": readback_file, "sha256": sha256(source / readback_file)},
            *({"owner": "emsdk", "source_file": name, "sha256": sha256(emsdk / name)}
              for name in lock["emsdk"]["reviewed_source_files"])]


def build(source: Path, emsdk: Path, python: Path, destination: Path, arch: str,
          variant: str = "official", sdk_variant: str = "official", readback_variant: str = "official") -> dict:
    source, emsdk, destination = source.resolve(), emsdk.resolve(), destination.absolute()
    lock = json.loads(Path(__file__).with_name("web_worker_template.lock.json").read_text())
    if destination.exists() or destination.is_symlink():
        raise ValueError("QA output directory must be new; earlier templates are never overwritten")
    if source == destination or source in destination.parents or emsdk == destination or emsdk in destination.parents:
        raise ValueError("Keep QA output outside source/toolchain directories")
    if git_head(source) != lock["godot"]["source_commit"] or git_head(emsdk) != lock["emsdk"]["source_commit"]:
        raise ValueError("Only exact official source/toolchain commits are supported")
    source_variant, readback_source_variant = verify_source_variants(source, lock, variant, readback_variant)
    sdk_source_variant = verify_sdk_variant(emsdk, lock, sdk_variant)
    source_hashes = reviewed_source_hashes(source, emsdk, lock)
    contract_test = None
    if variant != "official":
        test_path = Path(__file__).with_name("test_web_eval_proxy.mjs")
        test_command = ["node", str(test_path), str(source / lock["qa_variants"][variant]["source_file"])]
        test = subprocess.run(test_command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
        if test.returncode:
            raise ValueError("QA JavaScript eval contract tests failed: " + test.stdout)
        contract_test = {"command": test_command, "exit_code": test.returncode, "test_sha256": sha256(test_path), "output": test.stdout}
    readback_contract_test = None
    if readback_variant != "official":
        approved = lock["qa_readback_variants"][readback_variant]
        test_path = Path(__file__).parent / approved["contract_test_file"]
        test_command = ["node", str(test_path), str(source / approved["source_file"])]
        test = subprocess.run(test_command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
        if test.returncode:
            raise ValueError("QA WebGL readback contract tests failed: " + test.stdout)
        readback_contract_test = {"command": test_command, "exit_code": test.returncode,
                                  "test_sha256": sha256(test_path), "output": test.stdout}
    sdk_contract_test = None
    if sdk_variant != "official":
        approved = lock["qa_sdk_variants"][sdk_variant]
        test_path = Path(__file__).parent / approved["contract_test_file"]
        test_command = ["node", str(test_path), str(emsdk / approved["source_file"])]
        test = subprocess.run(test_command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
        if test.returncode:
            raise ValueError("QA SDK presentation contract tests failed: " + test.stdout)
        sdk_contract_test = {"command": test_command, "exit_code": test.returncode,
                             "test_sha256": sha256(test_path), "output": test.stdout}
    if subprocess.check_output(["git", "-C", str(emsdk), "diff", "--name-only", "HEAD"], text=True).strip():
        raise ValueError("Tracked SDK edits found; preserve them and use a clean clone")
    configuration = emsdk / ".emscripten"
    if not configuration.is_file():
        raise ValueError("SDK must be installed/activated in its own directory first")
    env = os.environ.copy()
    env["EM_CONFIG"] = str(configuration)
    env["PATH"] = os.pathsep.join((str(emsdk / "upstream/emscripten"), str(emsdk / "upstream/bin"), env.get("PATH", "")))
    version = subprocess.check_output([str(emsdk / "upstream/emscripten/emcc"), "--version"], env=env, text=True)
    if not version.splitlines()[0].endswith(" " + lock["emsdk"]["version"] + " (" + lock["emsdk"]["compiler_source_commit"] + ")"):
        raise ValueError("Unexpected Emscripten binary version/commit")
    scons = subprocess.check_output([str(python.absolute()), "-c", "import SCons; print(SCons.__version__)"], text=True).strip()
    if scons != lock["scons"]["version"]:
        raise ValueError("Isolated SCons version mismatch")
    options = {**lock["required_options"], "arch": arch, "use_closure_compiler": "no"}
    command = [str(python.absolute()), "-m", "SCons", "-j4", *(f"{key}={value}" for key, value in options.items())]
    destination.mkdir(parents=True)
    receipt = {
        "state": "building_qa_only", "production_settings_changed": False,
        "performance_passed": False, "godot_source_commit": git_head(source),
        "qa_source_variant": source_variant,
        "qa_readback_variant": readback_source_variant,
        "qa_sdk_variant": sdk_source_variant,
        "reviewed_source_files": source_hashes,
        "javascript_contract_test": contract_test,
        "readback_contract_test": readback_contract_test,
        "sdk_contract_test": sdk_contract_test,
        "emsdk_source_commit": git_head(emsdk), "emcc_version": version.strip(),
        "scons_version": scons, "sdk_configuration_sha256": sha256(configuration),
        "command": command, "options": options,
        "started_utc": datetime.now(timezone.utc).isoformat(),
    }
    receipt_path = destination / "receipt.json"
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    receipt["prelink_input"] = archive_primary_js(source, destination, arch)
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    started = time.monotonic()
    with (destination / "build.log").open("w") as log:
        result = subprocess.run(command, cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT, check=False)
    receipt["elapsed_seconds"] = round(time.monotonic() - started, 3)
    receipt["completed_utc"] = datetime.now(timezone.utc).isoformat()
    receipt["exit_code"] = result.returncode
    generated = source / f"bin/godot.web.template_release.{arch}.zip"
    if result.returncode or not generated.is_file():
        receipt["state"] = "build_failed"
        receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
        raise ValueError(f"Worker template build failed; inspect {destination / 'build.log'}")
    try:
        after_source_hashes = reviewed_source_hashes(source, emsdk, lock)
        identities_match = (
            git_head(source) == lock["godot"]["source_commit"]
            and git_head(emsdk) == lock["emsdk"]["source_commit"]
            and verify_source_variants(source, lock, variant, readback_variant) == (source_variant, readback_source_variant)
            and verify_sdk_variant(emsdk, lock, sdk_variant) == sdk_source_variant
            and after_source_hashes == source_hashes
            and not subprocess.check_output(["git", "-C", str(emsdk), "diff", "--name-only", "HEAD"], text=True).strip()
        )
    except (ValueError, OSError, subprocess.CalledProcessError):
        identities_match = False
    if not identities_match:
        receipt["state"] = "source_changed_during_build"
        receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
        raise ValueError("Source identity changed during build; output is not an accepted QA candidate")
    receipt["reviewed_source_files_after_build"] = after_source_hashes
    try:
        receipt["emitted_webgl_readback"] = validate_emitted_readback_variant(generated, readback_variant)
    except (ValueError, KeyError, UnicodeDecodeError, zipfile.BadZipFile) as error:
        receipt["state"] = "readback_patch_not_emitted"
        receipt["emitted_readback_error"] = str(error)
        receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
        raise ValueError("Linked template failed readback identity; inspect receipt and relink") from error
    try:
        receipt["emitted_sdk_presentation"] = validate_emitted_sdk_variant(generated, sdk_variant)
    except (ValueError, KeyError, UnicodeDecodeError, zipfile.BadZipFile) as error:
        receipt["state"] = "sdk_patch_not_emitted"
        receipt["emitted_sdk_error"] = str(error)
        receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
        raise ValueError("Linked template failed SDK query identity; inspect receipt and relink") from error
    suffix = "" if variant == "official" else "-" + variant.replace("_", "-")
    if sdk_variant != "official":
        suffix += "-sdk-" + sdk_variant.replace("_", "-")
    if readback_variant != "official":
        suffix += "-readback-" + readback_variant.replace("_", "-")
    artifact = destination / f"godot-4.7.1-web-worker-{arch}{suffix}.zip"
    shutil.copy2(generated, artifact)
    validate_template(artifact)
    receipt["state"] = "compiled_qa_unverified"
    receipt["artifact"] = {"path": str(artifact), "sha256": sha256(artifact), "bytes": artifact.stat().st_size}
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot-source", type=Path, required=True)
    parser.add_argument("--emsdk", type=Path, required=True)
    parser.add_argument("--python", type=Path, required=True)
    parser.add_argument("--arch", choices=("wasm32", "wasm64"), default="wasm32")
    parser.add_argument("--qa-variant", choices=("official", "eval_main_thread"), default="official", help="Exact reviewed source patch only; never a production approval")
    parser.add_argument("--qa-sdk-variant", choices=("official", "scissor_is_enabled"), default="official", help="Exact reviewed installed SDK patch only; independent of Godot source variant")
    parser.add_argument("--qa-readback-variant", choices=("official", "current_context"), default="official", help="Exact reviewed Godot WebGL readback patch only; independent of eval and SDK variants")
    parser.add_argument("--compile", action="store_true", help="Explicitly authorize the CPU-intensive full QA template build")
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    if not args.compile:
        parser.error("Pass --compile only inside an authorized window without browser timing benchmarks")
    try:
        print(json.dumps(build(args.godot_source, args.emsdk, args.python, args.destination, args.arch, args.qa_variant, args.qa_sdk_variant, args.qa_readback_variant), indent=2))
        return 0
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"build_web_worker: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
