"""Read-only actual Z01/Z02 scene provenance and source-mask test.

Blender --background --factory-startup --disable-autoexec --threads 1
  --python-exit-code 1 --python tests/hero_v12_source_study_blender_test.py

No render, reduction, mutation, save, export or report-file write. JSON goes to
stdout for the caller to retain. This is integrity evidence, never art approval.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / "qa_shots/hero"
HELPER = ROOT / "tools/art/hero_penguin_v12_study_provenance.py"
SPEC = importlib.util.spec_from_file_location("source_study_provenance_read_only", HELPER)
PROVENANCE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROVENANCE)


def inspect_source(bpy, source, profile):
    bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False, use_scripts=False)
    binding = PROVENANCE.read_source_study(source, bpy.context.scene)
    if binding is None or binding["study_profile"] != profile:
        raise RuntimeError("actual saved scene is not the declared study: " + profile)
    body, wings, masks = [], [], []
    for obj in bpy.context.scene.objects:
        if obj.type == "ARMATURE":
            raise RuntimeError("source-only study unexpectedly contains a runtime rig")
        if obj.type != "MESH":
            continue
        if obj.name.startswith("HeroBody"):
            body.append(obj.name)
        elif obj.name.startswith("PaddleWing"):
            wings.append(obj.name)
        else:
            continue
        PROVENANCE.require_component_masks(binding, obj)
        attribute = obj.data.color_attributes["SourceSemanticMasks"]
        digest = hashlib.sha256()
        for item in attribute.data:
            digest.update(struct.pack("<4d", *item.color))
        masks.append({"object": obj.name, "attribute": attribute.name,
                      "domain": attribute.domain, "storage": attribute.data_type,
                      "vertices": len(attribute.data), "exact_saved_values_sha256": digest.hexdigest()})
    if len(body) != 1 or len(wings) != 2:
        raise RuntimeError(f"source mask coverage incomplete: body={body}, wings={wings}")
    return {"path": str(source), "study_profile": profile, "source_blend_sha256": PROVENANCE.sha(source),
            "real_saved_scene_validated": True, "source_study_binding": binding,
            "explicit_body_and_wing_masks": sorted(masks, key=lambda item: item["object"])}


def main():
    import bpy
    if tuple(bpy.app.version[:3]) != (5, 2, 0) or not bpy.app.background:
        raise RuntimeError("read-only source test requires background Blender 5.2.0")
    if "--disable-autoexec" not in sys.argv:
        raise RuntimeError("run source test with --disable-autoexec")
    parser = argparse.ArgumentParser(description=__doc__)
    for label in ("z01", "z02"):
        parser.add_argument(f"--{label}-blend", type=Path,
            default=QA / f"v12_source_proof_{label}/hero_penguin_v12_source_proof.blend")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    sources = [(args.z01_blend.resolve(), "eye-aperture-z01"),
               (args.z02_blend.resolve(), "face-paddles-z02")]
    if sources[0][0] == sources[1][0] or any(not path.is_file() or not path.is_relative_to(QA.resolve())
                                         for path, _ in sources):
        raise RuntimeError("two distinct existing quarantined saved sources required")
    inputs = [HELPER, Path(__file__), *(path for source, _ in sources for path in (
        source, source.with_name("source_study_inputs.json"), source.with_name("source_study_audit.json")))]
    before = {str(path): PROVENANCE.sha(path) for path in inputs}
    try:
        results = [inspect_source(bpy, source, profile) for source, profile in sources]
    finally:
        after = {str(path): PROVENANCE.sha(path) for path in inputs}
        if before != after:
            raise RuntimeError("read-only test input changed during inspection")
    print(json.dumps({"schema_version": 1, "integrity_passed": True, "read_only": True,
                      "inputs_unchanged": True, "input_sha256": before, "studies": results,
                      "blender_version": bpy.app.version_string, "rendered": False, "reduced": False,
                      "exported": False, "production_ready": False, "source_fidelity_approved": False},
                     sort_keys=True, allow_nan=False))
    print("[source-study-blender] PASS: actual Z01/Z02 scene metadata and source masks; art approval remains false")


if __name__ == "__main__":
    main()
