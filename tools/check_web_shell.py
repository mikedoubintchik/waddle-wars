#!/usr/bin/env python3
"""Validate the web export's HTML head include.

Everything the browser build needs before the engine exists lives in one
escaped string inside export_presets.cfg: the audio unlock, the device-pixel
budget, the canvas sizing, the PWA metadata and the WebGL context-loss screen.
A single unbalanced brace in there produces a page that loads, runs no
JavaScript at all, and shows a black rectangle -- with nothing in the Godot
output to say why, because Godot never sees it. Nothing else in the suite
reads that string, so it is checked here.

Requires node for the syntax pass; without it the structural checks still run
and the syntax pass is reported as skipped.

Exit 0 when the shell is sound, 1 otherwise.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PRESETS = REPO / "export_presets.cfg"

# Behaviour the browser build depends on. Each entry is a marker that must
# survive any edit to the shell, paired with what breaks when it does not.
REQUIRED = [
    ("__ww_silent_keepalive", "iOS silent-switch audio unlock"),
    ("manifest.webmanifest", "installable PWA manifest link"),
    ("apple-touch-icon", "home-screen icon"),
    ("viewport-fit=cover", "canvas reaching under the notch"),
    ("interactive-widget=resizes-content", "keyboard not resizing the canvas"),
    ("devicePixelRatio", "phone pixel budget"),
    ("webglcontextlost", "graphics-loss recovery screen"),
    ("__wwGraphicsAdvice", "conservative graphics support advice after engine boot"),
]


def head_include(text: str) -> str:
    match = re.search(r'html/head_include="(.*?)"\n', text, re.S)
    if match is None:
        raise SystemExit("check_web_shell: no html/head_include in export_presets.cfg")
    raw = match.group(1)
    # Reverse the cfg escaping, innermost first.
    return raw.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")


def main() -> int:
    shell = head_include(PRESETS.read_text())
    failures: list[str] = []

    open_tags = shell.count("<script>")
    close_tags = shell.count("</script>")
    if open_tags != close_tags:
        failures.append(f"{open_tags} <script> vs {close_tags} </script>")

    for marker, why in REQUIRED:
        if marker not in shell:
            failures.append(f"missing {marker!r} ({why})")

    scripts = re.findall(r"<script>(.*?)</script>", shell, re.S)
    if not scripts:
        failures.append("no <script> blocks found")

    node = shutil.which("node")
    if node is None:
        print("[web-shell] SKIP syntax pass (node not installed)")
    else:
        with tempfile.TemporaryDirectory() as tmp:
            for index, body in enumerate(scripts):
                path = Path(tmp) / f"head_{index}.js"
                path.write_text(body)
                result = subprocess.run(
                    [node, "--check", str(path)], capture_output=True, text=True
                )
                if result.returncode != 0:
                    first = result.stderr.strip().splitlines()
                    detail = first[0] if first else "syntax error"
                    failures.append(f"script {index} does not parse: {detail}")

    if failures:
        for line in failures:
            print(f"[web-shell] FAIL {line}")
        return 1

    print(f"[web-shell] PASS {len(scripts)} scripts parse, "
          f"{len(REQUIRED)} behaviours present")
    return 0


if __name__ == "__main__":
    sys.exit(main())
