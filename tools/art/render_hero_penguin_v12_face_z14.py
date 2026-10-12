#!/usr/bin/env python3
"""Render the quarantined Z14 sculpture using the unchanged Z13 paint hook."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hero_penguin_v12_face_z14 as face
import render_hero_penguin_v12_face_z13 as render

if __name__ == "__main__":
    render.main(face_module=face, launcher_path=Path(__file__).resolve())
