#!/usr/bin/env python3
"""Render the unified juvenile face through the existing fixed proof stage."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hero_penguin_face_sculpt as face
import render_hero_penguin_v12_face_z13 as renderer

if __name__ == "__main__":
    renderer.main(face_module=face, launcher_path=Path(__file__).resolve())
