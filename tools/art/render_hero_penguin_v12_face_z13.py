#!/usr/bin/env python3
"""Render Z13 full pigment study; default retains the exact Z12 sculpture."""
from __future__ import annotations

import json
from pathlib import Path
import sys
from types import ModuleType

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hero_penguin_v12_face_z13 as default_face
import hero_penguin_v12_source_study as study
import render_hero_penguin_v12_source_study as base


def frozen_tool_paths(face, launcher):
    """Pin selected construction and this launcher's imported paint helper.

    A selected design need not expose a ``prior`` chain. The imported default
    helper still supplies paint evaluation/material installation, so always
    bind it explicitly rather than relying on the selected design's ancestry.
    """
    paths = [Path(__file__).with_name(name).resolve(strict=True) for name in base.INPUT_TOOLS]
    paths += [Path(__file__).resolve(strict=True), Path(launcher).resolve(strict=True)]
    for root in (face, default_face):
        module, seen = root, set()
        while module is not None:
            if module in seen:
                raise ValueError("Source helper prior chain contains a cycle")
            seen.add(module)
            paths.append(Path(module.__file__).resolve(strict=True))
            module = getattr(module, "prior", None)
    return tuple(dict.fromkeys(paths))


def main(face_module=default_face, launcher_path=None):
    """Optional explicit source-study module/launcher; default is only Z13."""
    face = face_module
    launcher = Path(launcher_path or __file__).resolve(strict=True)
    original_argv = list(sys.argv)
    args = base.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if args.study_profile != "baseline":
        raise ValueError("Source launcher fixes its profile; omit --study-profile")
    output = base.output_path(args.output_dir)
    material_dir = args.material_dir.resolve(strict=True)
    if not 1 <= args.threads <= 4 or not 1 <= args.samples <= 1024:
        raise ValueError("Source pigment study requires 1..4 CPU threads and 1..1024 samples")
    paths = frozen_tool_paths(face, launcher)
    tiles = sorted(material_dir.glob("hero_penguin_v11_*_tile.png"))
    if len(tiles) != 6 or any(path.is_symlink() for path in tiles):
        raise ValueError("Source pigment study requires six original feather tiles")
    input_hashes = {str(path): base.sha(path) for path in [*paths, *tiles]}
    renderer_tree, renderer_record = face.renderer_syntax(base.RENDERER)
    with face.installed_design() as (design, design_record):
        renderer = ModuleType("v12_continuous_pigment_renderer")
        renderer.__file__, renderer.__package__ = str(base.RENDERER), ""
        exec(compile(renderer_tree, str(base.RENDERER), "exec"), renderer.__dict__)
        study.require_renderer_cohort(renderer, design)
        record = {**face.source_only_declarations(), "selected_design_record": design_record, **renderer_record,
                  "inputs": input_hashes, "source_renderer": str(base.RENDERER),
                  "selected_helper": str(Path(face.__file__).resolve()), "selected_launcher": str(launcher),
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
                raise RuntimeError("Source materials must be created exactly once")
            materials = original_materials(directory)
            record["applied_material_changes"] = face.apply_material_changes(materials)
            state["materials"], state["material_calls"] = materials, 1
            persist_record()
            return materials

        def audited_stage():
            if state["paint_calls"] or state["materials"] is None:
                raise RuntimeError("Source paint hook order/call count invalid")
            bodies = [obj for obj in renderer.bpy.context.scene.objects if obj.name == "HeroBodyV12SmoothField"]
            if len(bodies) != 1:
                raise RuntimeError("Continuous pigment requires the single source body")
            body = bodies[0]
            original_material = state["materials"]["body_vertex"]
            wings = [obj for obj in renderer.bpy.context.scene.objects if obj.name.startswith("PaddleWing")]
            wing_slots = {obj.name: tuple(obj.data.materials) for obj in wings}
            record["continuous_paint_input"] = face.install_continuous_paint(
                body, original_material, design.eye_surface_frame, design.EYE_RADII, renderer.bpy)
            if len(wings) != 2 or any(tuple(obj.data.materials) != wing_slots[obj.name] for obj in wings):
                raise RuntimeError("Continuous body pigment unexpectedly changed wing materials")
            state["paint_calls"] = 1
            persist_record()
            return original_stage()

        renderer.create_materials, renderer.setup_stage = audited_materials, audited_stage
        sys.argv = [original_argv[0], "--", "--output-dir", str(output), "--material-dir", str(material_dir),
                    "--feather-recipe", args.feather_recipe, "--threads", str(args.threads), "--samples", str(args.samples)]
        try:
            renderer.main()
            if state["material_calls"] != 1 or state["paint_calls"] != 1 or any(base.sha(path) != digest for path, digest in input_hashes.items()):
                raise RuntimeError("Source callback count or frozen input integrity failed")
            files = [output / "hero_penguin_v12_source_proof.blend",
                     *[output / f"hero_penguin_v12_blender_{view}.png" for view in ("front", "threequarter", "true_side")]]
            if not all(path.is_file() for path in files):
                raise RuntimeError("Source study did not produce its blend and all three proof views")
            record.update(inputs_unchanged=True, outputs={path.name: base.sha(path) for path in files},
                          rendered_views=["front", "threequarter", "true_side"])
            (output / "source_study_audit.json").write_text(json.dumps(record, indent=2, sort_keys=True, allow_nan=False) + "\n")
            print(f"[v12-continuous-pigment] {face.PROFILE}; fidelity/export approval=false; {output}")
        finally:
            sys.argv = original_argv
            renderer.create_materials, renderer.setup_stage = original_materials, original_stage


if __name__ == "__main__":
    main()
