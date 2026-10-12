#!/usr/bin/env python3
"""QA-only: time autoload _ready() bodies in an isolated project copy."""

from __future__ import annotations

import argparse
from pathlib import Path


AUTOLOADS = {
    "SaveManager": "scripts/save/save_manager.gd",
    "SettingsManager": "scripts/save/settings_manager.gd",
    "AudioManager": "scripts/utilities/audio_manager.gd",
    "Progression": "scripts/progression/progression.gd",
    "SceneRouter": "scripts/utilities/scene_router.gd",
    "LeaderboardClient": "scripts/network/leaderboard_client.gd",
    "CommerceClient": "scripts/commerce/commerce_client.gd",
    "NativeAuthClient": "scripts/commerce/native_auth_client.gd",
    "AccountLifecycleClient": "scripts/network/account_lifecycle_client.gd",
}


def instrument(path: Path, name: str) -> None:
    lines = path.read_text().splitlines(keepends=True)
    marker = "func _ready() -> void:\n"
    first = lines.index(marker)
    end = first + 1
    while end < len(lines) and (not lines[end].strip() or lines[end][0] in "\t#"):
        end += 1
    lines.insert(end, f'\tprint("[ww-autoload-qa] {name} ready_ms=", '
             "(Time.get_ticks_usec() - __qa_ready_start) / 1000.0)\n")
    lines.insert(first + 1, "\tvar __qa_ready_start := Time.get_ticks_usec()\n")
    path.write_text("".join(lines))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("project_copy", type=Path)
    args = parser.parse_args()
    for name, relative in AUTOLOADS.items():
        instrument(args.project_copy / relative, name)


if __name__ == "__main__":
    main()
