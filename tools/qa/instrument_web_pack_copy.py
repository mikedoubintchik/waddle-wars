#!/usr/bin/env python3
"""QA-only timing for generated Godot Web loader; never ship this JS."""

import argparse
from pathlib import Path

SOURCE = 'FS.writeFile(path,new Uint8Array(buffer))'
OPTIMIZED = 'FS.writeFile(path,new Uint8Array(buffer),{canOwn:path.endsWith(".pck")})'


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("script", type=Path)
    args = parser.parse_args()
    text = args.script.read_text(encoding="utf-8")
    copy = OPTIMIZED if OPTIMIZED in text else SOURCE
    if text.count(copy) != 1:
        raise SystemExit("expected one copy_to_fs call")
    text = text.replace(
        copy,
        'var __wwCopyMs=performance.now();' + copy + ';'
        + 'console.log("[ww-pack-qa] copy_ms="+(performance.now()-__wwCopyMs).toFixed(1)' \
        + '+" bytes="+buffer.byteLength);',
        1,
    )
    call_main = "me.rtenv['callMain'](me.config.args);"
    if text.count(call_main) != 1:
        raise SystemExit("expected one callMain call")
    text = text.replace(
        call_main,
        "const __wwMainMs=performance.now();" + call_main
        + 'console.log("[ww-pack-qa] callmain_ms="+'
        + '(performance.now()-__wwMainMs).toFixed(1))',
        1,
    )
    args.script.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
