#!/usr/bin/env python3
"""Check native ELF alignment; require bundletool for AAB packaging evidence.

This is a structural gate, not proof of correct gameplay, billing, signing, or
runtime compatibility. A real 16-KB Android device/emulator run remains required.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import struct
import subprocess
import sys
import zipfile

PAGE_SIZE = 16384
ADDRESS_LIMIT = 1 << 64


def elf_failures(data: bytes) -> list[str]:
    if len(data) < 64 or data[:4] != b"\x7fELF":
        return ["not an ELF library"]
    if data[4] != 2 or data[5] != 1:
        return ["expected 64-bit little-endian ELF"]
    if struct.unpack_from("<H", data, 18)[0] != 183:
        return ["expected AArch64 ELF"]
    offset = struct.unpack_from("<Q", data, 32)[0]
    entry_size, count = struct.unpack_from("<HH", data, 54)
    if entry_size < 56 or count < 1 or offset + entry_size * count > len(data):
        return ["invalid program-header bounds"]
    failures = []
    loads = []
    relros = []
    for index in range(count):
        kind, flags, file_offset, address, _, file_size, mem_size, alignment = struct.unpack_from("<IIQQQQQQ", data, offset + index * entry_size)
        if kind == 1:  # PT_LOAD
            loads.append((index, flags, address, address + mem_size))
            if alignment < PAGE_SIZE or alignment & (alignment - 1):
                failures.append(f"LOAD[{index}] alignment {alignment} is below 16 KB or invalid")
            if file_offset % PAGE_SIZE != address % PAGE_SIZE:
                failures.append(f"LOAD[{index}] file/virtual offsets disagree at 16 KB")
            if file_offset + file_size > len(data) or file_size > mem_size:
                failures.append(f"LOAD[{index}] invalid segment size")
            if address + mem_size >= ADDRESS_LIMIT:
                failures.append(f"LOAD[{index}] virtual range overflows ELF64")
        if kind == 0x6474E552:  # PT_GNU_RELRO
            relros.append((index, address, address + mem_size))
            if not mem_size or file_size > mem_size or file_offset + file_size > len(data):
                failures.append(f"RELRO[{index}] invalid segment size")
            if address + mem_size >= ADDRESS_LIMIT:
                failures.append(f"RELRO[{index}] virtual range overflows ELF64")
    if not loads:
        failures.append("no LOAD segments")
    for index, start, end in relros:
        containing = [load for load in loads if load[1] & 2 and load[2] <= start < end <= load[3]]
        if len(containing) != 1:
            failures.append(f"RELRO[{index}] must be contained in one writable LOAD")
        # Bionic protects every 16-KB page touched by RELRO, not just its raw
        # byte range. A whole-LOAD RELRO can legitimately end off a page boundary:
        # https://android.googlesource.com/platform/bionic/+/android16-qpr2-release/linker/linker_phdr_16kib_compat.cpp#427
        # Its padding is safe only if no still-mutable/executable LOAD bytes are
        # caught in the rounded protection (including neighbouring segments).
        page_start = start // PAGE_SIZE * PAGE_SIZE
        page_end = (end + PAGE_SIZE - 1) // PAGE_SIZE * PAGE_SIZE
        for load_index, flags, load_start, load_end in loads:
            overlap_start = max(page_start, load_start)
            overlap_end = min(page_end, load_end)
            if overlap_start >= overlap_end:
                continue
            if flags & 2 and (overlap_start < start or overlap_end > end):
                failures.append(f"RELRO[{index}] rounded protection includes mutable bytes in LOAD[{load_index}]")
            if flags & 1:
                failures.append(f"RELRO[{index}] rounded protection overlaps executable LOAD[{load_index}]")
    return failures


def check(path: Path, bundletool: Path | None = None, zipalign: Path | None = None) -> dict:
    failures = []
    libraries = {}
    with zipfile.ZipFile(path) as artifact:
        names = artifact.namelist()
        arm64 = [name for name in names if "/arm64-v8a/" in name and name.endswith(".so")]
        if not arm64:
            failures.append("No arm64-v8a shared libraries")
        for name in arm64:
            libraries[name] = elf_failures(artifact.read(name))
            failures.extend(f"{name}: {error}" for error in libraries[name])
    packaging = None
    if path.suffix == ".aab":
        if not bundletool or not bundletool.is_file():
            failures.append("AAB packaging not checked: supply --bundletool path/to/bundletool.jar")
        else:
            result = subprocess.run(["java", "-jar", str(bundletool), "dump", "config", "--bundle=" + str(path)], capture_output=True, text=True, check=False)
            packaging = result.stdout.strip()
            if result.returncode or "PAGE_ALIGNMENT_16K" not in packaging:
                failures.append("AAB does not prove PAGE_ALIGNMENT_16K")
    elif path.suffix == ".apk":
        if not zipalign or not zipalign.is_file():
            failures.append("APK packaging not checked: supply --zipalign SDK/build-tools/version/zipalign")
        else:
            result = subprocess.run([str(zipalign), "-c", "-P", "16", "4", str(path)], capture_output=True, text=True, check=False)
            packaging = result.stdout.strip()
            if result.returncode:
                failures.append("APK zipalign 16-KB check failed")
    else:
        failures.append("Expected an .aab or .apk artifact")
    return {"structural_gate_passed": not failures, "store_ready": False, "libraries": libraries, "packaging": packaging, "failures": failures}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--bundletool", type=Path)
    parser.add_argument("--zipalign", type=Path)
    args = parser.parse_args()
    try:
        report = check(args.artifact, args.bundletool, args.zipalign)
        print(json.dumps(report, indent=2))
        return 0 if report["structural_gate_passed"] else 1
    except (OSError, zipfile.BadZipFile) as error:
        print(f"check_android_artifact: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
