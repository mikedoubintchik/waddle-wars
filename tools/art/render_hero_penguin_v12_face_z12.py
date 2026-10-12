#!/usr/bin/env python3
"""Render Z12 pigment sampling study; unchanged Z11 geometry, QA only."""
from __future__ import annotations

import json
from pathlib import Path
import sys
from types import ModuleType

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hero_penguin_v12_face_z12 as face
import hero_penguin_v12_source_study as study
import render_hero_penguin_v12_source_study as base


def main():
    original_argv = list(sys.argv)
    args = base.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if args.study_profile != "baseline":
        raise ValueError("Z12 launcher fixes its profile; omit --study-profile")
    output = base.output_path(args.output_dir)
    material_dir = args.material_dir.resolve(strict=True)
    if not 1 <= args.threads <= 4 or not 1 <= args.samples <= 1024:
        raise ValueError("Z12 requires 1..4 CPU threads and 1..1024 samples")
    paths = [Path(__file__).with_name(name) for name in base.INPUT_TOOLS]
    paths += [Path(__file__).resolve(), Path(face.__file__).resolve(), Path(face.prior.__file__).resolve(),
              Path(face.prior.prior.__file__).resolve(), Path(face.prior.prior.prior.__file__).resolve()]
    tiles = sorted(material_dir.glob("hero_penguin_v11_*_tile.png"))
    if len(tiles) != 6 or any(path.is_symlink() for path in tiles):
        raise ValueError("Z12 requires six original feather tiles")
    input_hashes = {str(path): base.sha(path) for path in [*paths, *tiles]}
    renderer_tree, renderer_record = face.renderer_syntax(base.RENDERER)
    with face.installed_design() as (design, design_record):
        renderer = ModuleType("v12_face_z12_renderer")
        renderer.__file__, renderer.__package__ = str(base.RENDERER), ""
        exec(compile(renderer_tree, str(base.RENDERER), "exec"), renderer.__dict__)
        study.require_renderer_cohort(renderer, design)
        record = {**face.source_only_declarations(), "unchanged_z11_design_record": design_record, **renderer_record,
                  "inputs": input_hashes, "source_renderer": str(base.RENDERER),
                  "command": original_argv, "output_dir": str(output), "material_dir": str(material_dir),
                  "feather_recipe": args.feather_recipe, "cpu_threads": args.threads,
                  "samples": args.samples, "renderer_cohort_verified_before_geometry": True}
        original_materials, original_stage = renderer.create_materials, renderer.setup_stage
        state = {"materials": None, "material_calls": 0, "paint_calls": 0}

        def persist_record():
            encoded = json.dumps(record, indent=2, sort_keys=True, allow_nan=False) + "\n"
            (output / "source_study_inputs.json").write_text(encoded)
            scene = renderer.bpy.context.scene
            scene["source_study_profile"] = face.PROFILE
            scene["source_study_json"] = encoded
            scene["source_study_production_ready"] = False
            scene["source_study_candidate_export_allowed"] = False

        def audited_materials(directory):
            if state["material_calls"]:
                raise RuntimeError("Z12 materials must be created exactly once")
            materials = original_materials(directory)
            record["applied_material_changes"] = face.apply_material_changes(materials)
            state["materials"], state["material_calls"] = materials, 1
            persist_record()
            return materials

        def audited_stage():
            # This hook runs AFTER the existing feather/detail recipe, before
            # the unchanged cameras/lights, saved .blend and three renders.
            if state["paint_calls"] or state["materials"] is None:
                raise RuntimeError("Z12 paint hook order/call count invalid")
            material = state["materials"]["body_vertex"]
            record["continuous_paint_input"] = face.install_continuous_paint(
                material, design.eye_surface_frame, design.EYE_RADII, renderer.bpy)
            state["paint_calls"] = 1
            persist_record()
            return original_stage()

        renderer.create_materials, renderer.setup_stage = audited_materials, audited_stage
        sys.argv = [original_argv[0], "--", "--output-dir", str(output), "--material-dir", str(material_dir),
                    "--feather-recipe", args.feather_recipe, "--threads", str(args.threads), "--samples", str(args.samples)]
        try:
            renderer.main()
            if state["material_calls"] != 1 or state["paint_calls"] != 1 or any(base.sha(path) != digest for path, digest in input_hashes.items()):
                raise RuntimeError("Z12 callback count or frozen input integrity failed")
            files = [output / "hero_penguin_v12_source_proof.blend",
                     *[output / f"hero_penguin_v12_blender_{view}.png" for view in ("front", "threequarter", "true_side")]]
            if not all(path.is_file() for path in files):
                raise RuntimeError("Z12 did not produce its blend and all three proof views")
            record.update(inputs_unchanged=True, outputs={path.name: base.sha(path) for path in files},
                          rendered_views=["front", "threequarter", "true_side"])
            (output / "source_study_audit.json").write_text(json.dumps(record, indent=2, sort_keys=True, allow_nan=False) + "\n")
            print(f"[v12-face-z12] source-only; fidelity/export approval=false; {output}")
        finally:
            sys.argv = original_argv
            renderer.create_materials, renderer.setup_stage = original_materials, original_stage


if __name__ == "__main__":
    main()
