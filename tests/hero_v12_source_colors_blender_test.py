"""Read-only saved-source proof for the candidate's literal-color adapter.

Run with Blender --background --disable-autoexec --threads 1 --python this.py
-- --source-blend V.blend --legacy-blend M.blend --output fresh_qa_report.json.
No mesh editing, reduction, rendering, source save, or runtime export occurs.
"""

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

import bpy


ROOT = Path(__file__).resolve().parents[1]
ADAPTER_PATH = ROOT / "tools/art/build_hero_penguin_v12_candidate.py"
SPEC = importlib.util.spec_from_file_location("candidate_color_adapter", ADAPTER_PATH)
ADAPTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ADAPTER)


def previous_source_colors(obj):
    """Exact pre-IrisPigment behavior, retained solely as the legacy oracle."""
    attribute = obj.data.color_attributes.get("PreviewColor")
    if attribute is not None and attribute.domain == "POINT":
        return [tuple(value.color) for value in attribute.data]
    if attribute is not None and attribute.domain == "CORNER":
        values = [(0.0, 0.0, 0.0, 1.0)] * len(obj.data.vertices)
        for loop in obj.data.loops:
            values[loop.vertex_index] = tuple(attribute.data[loop.index].color)
        return values
    material = obj.data.materials[0] if obj.data.materials else None
    color = tuple(material.diffuse_color) if material is not None else (0.1, 0.1, 0.1, 1.0)
    return [color] * len(obj.data.vertices)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect_source(path, *, expect_pigment):
    bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False)
    irises, legacy_objects = [], []
    for obj in sorted(bpy.context.scene.objects, key=lambda item: item.name):
        if obj.type != "MESH" or obj.name == "NeutralGrayFloor":
            continue
        actual, previous = ADAPTER.source_colors(obj), previous_source_colors(obj)
        pigment = obj.data.color_attributes.get("IrisPigment")
        if pigment is not None:
            assert expect_pigment, "legacy M unexpectedly contains the new paint contract"
            expected = [tuple(value.color) for value in pigment.data]
            assert actual == expected, "saved linear iris data changed in adapter"
            assert actual != previous, "iris still resolves to the old flat diffuse swatch"
            assert len(set(actual)) > 8, "saved iris pigment has lost its authored variation"
            irises.append({"object": obj.name, "vertices": len(actual),
                           "attribute": pigment.name, "domain": pigment.domain,
                           "storage": pigment.data_type, "exact_linear_values": True,
                           "paint": ADAPTER.paint_summary(actual)})
        else:
            assert actual == previous, "legacy source-color behavior changed: " + obj.name
            legacy_objects.append(obj.name)
    assert len(irises) == (2 if expect_pigment else 0), "unexpected painted iris count"
    assert len(legacy_objects) >= 20, "source inspection did not cover the character components"
    return {"path": str(path), "painted_irises": irises,
            "legacy_objects_exact": legacy_objects, "legacy_object_count": len(legacy_objects)}


def main():
    args_parser = argparse.ArgumentParser(description=__doc__)
    args_parser.add_argument("--source-blend", type=Path, required=True)
    args_parser.add_argument("--legacy-blend", type=Path, required=True)
    args_parser.add_argument("--output", type=Path, required=True)
    args = args_parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    source, legacy, output = args.source_blend.resolve(), args.legacy_blend.resolve(), args.output.resolve()
    qa = (ROOT / "qa_shots/hero").resolve()
    if not output.is_relative_to(qa) or output.exists():
        raise ValueError("source-color report must be a fresh QA file")
    before = {str(path): digest(path) for path in (source, legacy)}
    report = {"schema_version": 1, "source": inspect_source(source, expect_pigment=True),
              "legacy": inspect_source(legacy, expect_pigment=False)}
    after = {str(path): digest(path) for path in (source, legacy)}
    assert before == after, "read-only inspection changed a saved source file"
    report.update(passed=True, source_sha256=before, source_files_unchanged=True,
                  adapter_sha256=digest(ADAPTER_PATH), blender_version=bpy.app.version_string,
                  production_ready=False, rendered=False, reduced=False, exported=False)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("[source-color-adapter] PASS", output)


if __name__ == "__main__":
    main()
