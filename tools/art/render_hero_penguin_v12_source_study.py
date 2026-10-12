#!/usr/bin/env python3
"""Launch one quarantined source-only study without editing source files.

Blender invocation (parent must coordinate rendering):
  Blender --background --factory-startup --threads 2 --python-exit-code 1 \
    --python tools/art/render_hero_penguin_v12_source_study.py -- \
    --study-profile eye-aperture-z01 --feather-recipe detail-01 \
    --output-dir qa_shots/hero/v12_source_proof_z01 --threads 2 --samples 48

Default study is baseline. This launcher never exports a rig/runtime GLB and
never modifies the baseline design, renderer, saved source or live assets.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from types import ModuleType

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hero_penguin_v12_source_study as study

ROOT = Path(__file__).resolve().parents[2]
QA = ROOT / "qa_shots/hero"
RENDERER = Path(__file__).with_name("render_hero_penguin_v12_source_proof.py")
INPUT_TOOLS = ("hero_penguin_v12_design.py", "render_hero_penguin_v12_source_proof.py",
               "hero_penguin_v12_source_study.py", "render_hero_penguin_v12_source_study.py",
               "hero_penguin_v12_materials.py", "hero_penguin_v12_feather_detail_recipe.py",
               "hero_penguin_eye_pigment.py")


def parse_args(values=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--study-profile", choices=tuple(study.PROFILE_OVERRIDES), default="baseline")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--material-dir", type=Path, default=QA / "material_v11")
    parser.add_argument("--feather-recipe", choices=("baseline", "detail-01"), default="baseline")
    parser.add_argument("--samples", type=int, default=48)
    parser.add_argument("--threads", type=int, default=2)
    return parser.parse_args(values)


def output_path(path: Path) -> Path:
    result = path.resolve()
    if result == QA or not result.is_relative_to(QA) or result.exists():
        raise ValueError("source study requires a fresh dedicated qa_shots/hero child")
    if not (ROOT / "qa_shots/.gdignore").is_file():
        raise ValueError("QA source study must remain excluded from Godot imports")
    return result


def sha(path):
    return study.sha_bytes(Path(path).read_bytes())


def main():
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parse_args(values)
    output = output_path(args.output_dir)
    material_dir = args.material_dir.resolve(strict=True)
    if not 1 <= args.threads <= 4 or not 1 <= args.samples <= 1024:
        raise ValueError("source study requires 1..4 CPU threads and 1..1024 samples")
    input_paths = [Path(__file__).with_name(name) for name in INPUT_TOOLS]
    if args.study_profile == "orbital-saddle-z04":
        input_paths.append(Path(__file__).with_name("hero_penguin_v12_orbital_saddle.py"))
    tiles = sorted(material_dir.glob("hero_penguin_v11_*_tile.png"))
    if len(tiles) != 6 or any(path.is_symlink() for path in tiles):
        raise ValueError("expected the six explicit original feather tile files")
    input_hashes = {str(path): sha(path) for path in [*input_paths, *tiles]}
    original_argv = list(sys.argv)
    # Renderer anchors are validated before installing any selected design.
    # Baseline and Z01 return the exact original renderer AST, unmodified.
    renderer_tree, renderer_profile = study.renderer_syntax(args.study_profile, RENDERER)
    with study.installed_design(args.study_profile) as (design, profile):
        # Fresh execution after profile installation: renderer scalar aliases,
        # scoped literals and design body/fold/gaze functions are one cohort.
        renderer = ModuleType("v12_source_study_renderer")
        renderer.__file__ = str(RENDERER)
        renderer.__package__ = ""
        exec(compile(renderer_tree, str(RENDERER), "exec"), renderer.__dict__)
        study.require_renderer_cohort(renderer, design)
        record = {**profile, **renderer_profile, "inputs": input_hashes, "source_renderer": str(RENDERER),
            "command": original_argv, "output_dir": str(output), "material_dir": str(material_dir),
            "feather_recipe": args.feather_recipe, "cpu_threads": args.threads,
            "samples": args.samples, "renderer_cohort_verified_before_geometry": True}
        original_reset = renderer.reset_scene

        def audited_reset(samples, threads):
            # main() has already checked/created its empty output directory.
            # This hook changes metadata only, before any source geometry exists.
            original_reset(samples, threads)
            encoded = json.dumps(record, indent=2, sort_keys=True, allow_nan=False) + "\n"
            (output / "source_study_inputs.json").write_text(encoded)
            renderer.bpy.context.scene["source_study_profile"] = args.study_profile
            renderer.bpy.context.scene["source_study_json"] = encoded
            renderer.bpy.context.scene["source_study_production_ready"] = False

        renderer.reset_scene = audited_reset
        sys.argv = [original_argv[0], "--", "--output-dir", str(output), "--material-dir", str(material_dir),
                    "--feather-recipe", args.feather_recipe, "--threads", str(args.threads), "--samples", str(args.samples)]
        try:
            renderer.main()
            if any(sha(path) != digest for path, digest in input_hashes.items()):
                raise RuntimeError("source study inputs changed while rendering")
            files = [output / "hero_penguin_v12_source_proof.blend",
                     *[output / f"hero_penguin_v12_blender_{view}.png" for view in ("front", "threequarter", "true_side")]]
            if not all(path.is_file() for path in files):
                raise RuntimeError("source study did not produce its blend and three proof views")
            record.update(inputs_unchanged=True, outputs={path.name: sha(path) for path in files},
                          rendered_views=["front", "threequarter", "true_side"])
            (output / "source_study_audit.json").write_text(json.dumps(record, indent=2, sort_keys=True, allow_nan=False) + "\n")
            print(f"[v12-source-study] {args.study_profile} complete; geometry/fidelity approval=false; {output}")
        finally:
            sys.argv = original_argv
            renderer.reset_scene = original_reset


if __name__ == "__main__":
    main()
