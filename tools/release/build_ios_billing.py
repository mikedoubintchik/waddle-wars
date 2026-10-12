#!/usr/bin/env python3
"""Build original StoreKit bridge against exact generated Godot 4.7.1 headers.

Requires an already configured Godot source checkout with its generated headers.
Does not compile/run Godot, install tools, sign, publish, or modify game settings.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

from native_release import ROOT, sha256
from install_ios_billing import SOURCES

SOURCE = ROOT / "native/ios/WaddleStoreKit"
LOCK = Path(__file__).with_name("billing_plugins.lock.json")
VARIANTS = {
    "device": ("iphoneos", "ios"),
    "simulator": ("iphonesimulator", "ios_simulator"),
}
ARCHITECTURES = ("arm64", "x86_64")


def output(command: list[str]) -> str:
    return subprocess.check_output(command, text=True).strip()


def build(headers: Path, destination: Path, lock: dict, *, variant: str = "device",
          architecture: str = "arm64") -> dict:
    if variant not in VARIANTS:
        raise ValueError("Build variant must be device or simulator")
    if architecture not in ARCHITECTURES:
        raise ValueError("Build architecture must be arm64 or x86_64")
    if variant == "device" and architecture != "arm64":
        raise ValueError("Device builds require arm64; x86_64 is simulator-only")
    sdk_name, platform = VARIANTS[variant]
    target_triple = architecture + "-apple-ios15.0" + ("-simulator" if variant == "simulator" else "")
    headers, destination = headers.resolve(), destination.resolve()
    if destination.exists():
        raise ValueError("Output directory must be new; existing plugin binaries are never overwritten")
    source_hashes = {name: sha256(SOURCE / name) for name in SOURCES}
    if output(["git", "-C", str(headers), "rev-parse", "HEAD"]) != lock["ios"]["godot_source_commit"]:
        raise ValueError("Godot source commit must match the exact pinned 4.7.1 export templates")
    required = ("core/extension/gdextension_interface.gen.h", "core/version_generated.gen.h", "core/disabled_classes.gen.h", "core/object/gdvirtual.gen.h")
    for name in required:
        if not (headers / name).is_file():
            raise ValueError(f"Generated Godot header missing: {name}. Configure the pinned Godot source build first.")
    sdk = output(["xcrun", "--sdk", sdk_name, "--show-sdk-path"])
    sdk_version = output(["xcrun", "--sdk", sdk_name, "--show-sdk-version"])
    if int(sdk_version.split(".")[0]) < 26:
        raise ValueError("iOS 26 SDK or newer required")
    swift = output(["xcrun", "--find", "swiftc"])
    clang = output(["xcrun", "--find", "clang++"])
    libtool = output(["xcrun", "--find", "libtool"])
    destination.mkdir(parents=True)
    compiled_defines = {}
    for mode in ("debug", "release"):
        work = destination / ("objects-" + mode)
        work.mkdir()
        swift_object = work / "storekit-swift.o"
        objc_header = work / "WaddleStoreKit-Swift.h"
        cpp_object = work / "storekit-cpp.o"
        swift_sources = [str(SOURCE / name) for name in SOURCES if name.endswith(".swift")]
        swift_args = [swift, "-swift-version", "5", "-parse-as-library", "-whole-module-optimization", "-module-name", "WaddleStoreKit", "-target", target_triple, "-sdk", sdk, "-emit-objc-header", "-emit-objc-header-path", str(objc_header), "-emit-object", "-o", str(swift_object), *swift_sources]
        swift_args.append("-Onone" if mode == "debug" else "-O")
        subprocess.run(swift_args, cwd=work, check=True)
        # Match the official threaded templates: THREADS_ENABLED changes Mutex
        # layout and cannot be omitted in a plugin sharing Godot's C++ objects.
        macros = ["IOS_ENABLED", "APPLE_EMBEDDED_ENABLED", "UNIX_ENABLED", "COREAUDIO_ENABLED", "THREADS_ENABLED", "NDEBUG"]
        if variant == "simulator":
            macros.append("IOS_SIMULATOR")
        if mode == "debug":
            macros.append("DEBUG_ENABLED")
        compiled_defines[mode] = macros
        cpp_args = [clang, "-std=c++17", "-target", target_triple, "-isysroot", sdk, "-fobjc-arc", "-fblocks", "-fmodules", "-fcxx-modules", "-fvisibility=hidden", "-I", str(headers), "-I", str(headers / "platform/ios"), "-I", str(work), "-c", str(SOURCE / "waddle_storekit.mm"), "-o", str(cpp_object)]
        cpp_args.extend("-D" + macro for macro in macros)
        cpp_args.extend(["-O0", "-g"] if mode == "debug" else ["-O2"])
        subprocess.run(cpp_args, cwd=work, check=True)
        subprocess.run([libtool, "-static", "-o", str(destination / f"WaddleStoreKit.{mode}.a"), str(swift_object), str(cpp_object)], cwd=work, check=True)
        symbols = output(["xcrun", "nm", "-g", str(destination / f"WaddleStoreKit.{mode}.a")])
        for entry in ("init_waddle_storekit", "deinit_waddle_storekit"):
            # Apple Mach-O prefixes '_' to the Itanium C++ mangled symbol.
            if not any(line.strip().endswith(" T __Z" + str(len(entry)) + entry + "v") for line in symbols.splitlines()):
                raise ValueError(f"Godot's generated C++ plugin entrypoint missing: {entry}")
    if source_hashes != {name: sha256(SOURCE / name) for name in SOURCES}:
        raise ValueError("Plugin sources changed during compilation")
    shutil.copy2(SOURCE / "WaddleStoreKit.gdip", destination / "WaddleStoreKit.gdip")
    receipt = {
        "state": "compiled_unverified", "plugin": "WaddleStoreKit", "version": lock["ios"]["version"],
        "godot_source_commit": lock["ios"]["godot_source_commit"], "ios_sdk": sdk_version,
        "platform": platform, "architecture": architecture, "entrypoint_linkage": "cplusplus",
        "variant": variant, "sdk_name": sdk_name, "target_triple": target_triple,
        "engine_cpp_defines": compiled_defines,
        "source_hashes": source_hashes,
        "artifacts": {path.name: sha256(path) for path in sorted(destination.iterdir()) if path.is_file()},
        "device_billing_passed": False,
        "device_authentication_passed": False,
        "store_ready": False,
    }
    (destination / "waddle_build_receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot-source", type=Path, required=True)
    parser.add_argument("--variant", choices=tuple(VARIANTS), default="device",
                        help="Build ARM64 device libraries (default) or isolated simulator libraries")
    parser.add_argument("--architecture", choices=ARCHITECTURES, default="arm64",
                        help="Target arm64 (default) or x86_64 for simulator-only libraries")
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(build(args.godot_source, args.destination, json.loads(LOCK.read_text()),
                               variant=args.variant, architecture=args.architecture), indent=2))
        return 0
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"build_ios_billing: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
