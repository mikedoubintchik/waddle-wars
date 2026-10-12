#!/usr/bin/env python3
"""Render source-only Z10 soft eyelid folds and cheek/throat silhouette."""
from __future__ import annotations

import json
from pathlib import Path
import sys
from types import ModuleType

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hero_penguin_v12_face_z10 as face
import hero_penguin_v12_source_study as study
import render_hero_penguin_v12_source_study as base


def main():
    original_argv = list(sys.argv)
    args = base.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if args.study_profile != "baseline":
        raise ValueError("Z10 launcher fixes its profile; omit --study-profile")
    output = base.output_path(args.output_dir)
    material_dir = args.material_dir.resolve(strict=True)
    if not 1 <= args.threads <= 4 or not 1 <= args.samples <= 1024:
        raise ValueError("Z10 requires 1..4 CPU threads and 1..1024 samples")
    paths = [Path(__file__).with_name(name) for name in base.INPUT_TOOLS]
    paths += [Path(__file__).resolve(), Path(face.__file__).resolve(), Path(face.prior.__file__).resolve()]
    tiles = sorted(material_dir.glob("hero_penguin_v11_*_tile.png"))
    if len(tiles) != 6 or any(path.is_symlink() for path in tiles):
        raise ValueError("Z10 requires six original feather tiles")
    input_hashes = {str(path): base.sha(path) for path in [*paths, *tiles]}
    renderer_tree, renderer_record = face.renderer_syntax(base.RENDERER)
    with face.installed_design() as (design, design_record):
        renderer = ModuleType("v12_face_z10_renderer")
        renderer.__file__ = str(base.RENDERER)
        renderer.__package__ = ""
        exec(compile(renderer_tree, str(base.RENDERER), "exec"), renderer.__dict__)
        study.require_renderer_cohort(renderer, design)
        record = {**face.source_only_declarations(), **design_record, **renderer_record,
                  "inputs": input_hashes, "source_renderer": str(base.RENDERER),
                  "command": original_argv, "output_dir": str(output), "material_dir": str(material_dir),
                  "feather_recipe": args.feather_recipe, "cpu_threads": args.threads,
                  "samples": args.samples, "renderer_cohort_verified_before_geometry": True}
        original_materials = renderer.create_materials
        calls = 0

        def audited_materials(directory):
            nonlocal calls
            if calls:
                raise RuntimeError("Z10 material callback must run exactly once")
            materials = original_materials(directory)
            record["applied_material_changes"] = face.apply_material_changes(materials)
            calls += 1
            encoded = json.dumps(record, indent=2, sort_keys=True, allow_nan=False) + "\n"
            (output / "source_study_inputs.json").write_text(encoded)
            scene = renderer.bpy.context.scene
            scene["source_study_profile"] = face.PROFILE
            scene["source_study_json"] = encoded
            scene["source_study_production_ready"] = False
            scene["source_study_candidate_export_allowed"] = False
            return materials

        renderer.create_materials = audited_materials
        sys.argv = [original_argv[0], "--", "--output-dir", str(output), "--material-dir", str(material_dir),
                    "--feather-recipe", args.feather_recipe, "--threads", str(args.threads), "--samples", str(args.samples)]
        try:
            renderer.main()
            if calls != 1 or any(base.sha(path) != digest for path, digest in input_hashes.items()):
                raise RuntimeError("Z10 callback count or frozen input integrity failed")
            files = [output / "hero_penguin_v12_source_proof.blend",
                     *[output / f"hero_penguin_v12_blender_{view}.png" for view in ("front", "threequarter", "true_side")]]
            if not all(path.is_file() for path in files):
                raise RuntimeError("Z10 did not produce its blend and all three proof views")
            record.update(inputs_unchanged=True, outputs={path.name: base.sha(path) for path in files},
                          rendered_views=["front", "threequarter", "true_side"])
            (output / "source_study_audit.json").write_text(json.dumps(record, indent=2, sort_keys=True, allow_nan=False) + "\n")
            print(f"[v12-face-z10] source-only; fidelity/export approval=false; {output}")
        finally:
            sys.argv = original_argv
            renderer.create_materials = original_materials


if __name__ == "__main__":
    main()
