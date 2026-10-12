#!/usr/bin/env python3
"""Transfer immutable downloaded PCK ownership to MEMFS; fail closed on SDK drift.

Godot drops preloadedFiles immediately after copyToFS. MEMFS may own this PCK
ArrayBuffer because no remaining writer reuses it. Other files keep copy semantics.
No engine/WASM, resolution, asset or audio behavior changes.
"""
from pathlib import Path
import hashlib

TEMPLATE_SHA256 = '68586d6daafc93c6e697b3fb258976874aa7459b8931165ebb1dc3c9614cc42c'
ORIGINAL = 'FS.writeFile(path,new Uint8Array(buffer))'
OWNED = 'FS.writeFile(path,new Uint8Array(buffer),{canOwn:path.endsWith(".pck")})'


def optimize_text(text: str) -> str:
    if hashlib.sha256(text.encode()).hexdigest() != TEMPLATE_SHA256:
        raise ValueError('Unreviewed Godot Web loader: revalidate ownership against this SDK')
    if text.count(ORIGINAL) != 1:
        raise ValueError('Expected exactly one unmodified copy_to_fs call')
    if 'node.contents=buffer.subarray(offset,offset+length)' not in text:
        raise ValueError('MEMFS ownership contract changed')
    return text.replace(ORIGINAL, OWNED, 1)


def apply(script: Path) -> dict:
    before = script.read_bytes()
    after = optimize_text(before.decode()).encode()
    script.write_bytes(after)
    return {'input_sha256': hashlib.sha256(before).hexdigest(),
            'output_sha256': hashlib.sha256(after).hexdigest(),
            'operation': 'PCK ArrayBuffer ownership transferred to MEMFS; all other files still copied'}
