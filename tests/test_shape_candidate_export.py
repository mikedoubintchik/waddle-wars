"""Gate 1 shape package/isolation contracts; no engine or browser launch."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import unittest

from tests.test_hero_candidate_export import fixture as project_fixture, inventory, write

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("shape_candidate_export", ROOT / "tools/qa/shape_candidate_export.py")
shape = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shape)


def document():
    return {"asset": {"version": "2.0"}, "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2}, "material": 0}]}],
        "materials": [{"name": "PlainMatte", "pbrMetallicRoughness": {
            "roughnessFactor": 0.9, "metallicFactor": 0, "baseColorFactor": [1, 1, 1, 1]}}]}


def package_fixture(folder: Path, doc=None):
    package = folder / "package"
    package.mkdir(exist_ok=True)
    encoded = json.dumps(doc or document()).encode()
    encoded += b" " * (-len(encoded) % 4)
    glb = struct.pack("<4sIIII", b"glTF", 2, 20 + len(encoded), len(encoded), 0x4E4F534A) + encoded
    write(package / "candidate.glb", glb)
    write(package / "source.blend", b"BLENDER host fixture")
    metadata = {"schema_version": 1, "gate": "rear-shape-v1", "unrigged": True,
        "production_ready": False, "animation_ready": False, "material_contract": "plain-literal-COLOR_0",
        "glb_sha256": shape.digest(glb), "source_sha256": shape.digest((package / "source.blend").read_bytes()),
        "source_height_m": 1.7, "gameplay_height_m": 1.05, "gameplay_scale": 1.05 / 1.7}
    write(package / "metadata.json", json.dumps(metadata))
    return package, metadata


class ShapePackageTests(unittest.TestCase):
    def test_plain_unrigged_package_admitted_without_authored_rig_contract(self):
        with tempfile.TemporaryDirectory() as temp:
            package, _metadata = package_fixture(Path(temp))
            result = shape.validate_package(package)
            self.assertEqual(result["surface_count"], 1)
            self.assertAlmostEqual(result["gameplay_scale"], 1.05 / 1.7)
            self.assertFalse(result["metadata"]["animation_ready"])

    def test_model_and_editable_source_hashes_are_required(self):
        for filename in ("candidate.glb", "source.blend"):
            with self.subTest(filename=filename), tempfile.TemporaryDirectory() as temp:
                package, _metadata = package_fixture(Path(temp))
                with (package / filename).open("ab") as stream:
                    stream.write(b"modified")
                with self.assertRaisesRegex(ValueError, "hash mismatch"):
                    shape.validate_package(package)

    def test_rigs_clips_maps_and_missing_literal_colors_rejected(self):
        mutations = (
            lambda doc: doc.update(skins=[{}]), lambda doc: doc.update(animations=[{}]),
            lambda doc: doc.update(images=[{}]), lambda doc: doc.update(textures=[{}]),
            lambda doc: doc["nodes"][0].update(skin=0),
            lambda doc: doc["meshes"][0]["primitives"][0]["attributes"].update(JOINTS_0=3),
            lambda doc: doc["meshes"][0]["primitives"][0]["attributes"].pop("COLOR_0"),
            lambda doc: doc["meshes"][0]["primitives"][0].update(targets=[{}]),
        )
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index), tempfile.TemporaryDirectory() as temp:
                doc = document(); mutate(doc)
                package, _metadata = package_fixture(Path(temp), doc)
                with self.assertRaises(ValueError):
                    shape.validate_package(package)

    def test_nonplain_materials_rejected(self):
        for key, value in (("metallicFactor", 1), ("roughnessFactor", .4), ("baseColorFactor", [.8, 1, 1, 1]),
                           ("baseColorTexture", {"index": 0})):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as temp:
                doc = document(); doc["materials"][0]["pbrMetallicRoughness"][key] = value
                package, _metadata = package_fixture(Path(temp), doc)
                with self.assertRaisesRegex(ValueError, "matte"):
                    shape.validate_package(package)

    def test_scope_and_scale_cannot_claim_production_or_animation_acceptance(self):
        mutations = {"gate": "full-rig", "unrigged": False, "production_ready": True, "animation_ready": True,
                     "source_height_m": 0, "gameplay_height_m": 2.0, "gameplay_scale": .54}
        for key, value in mutations.items():
            with self.subTest(key=key), tempfile.TemporaryDirectory() as temp:
                package, metadata = package_fixture(Path(temp))
                metadata[key] = value
                write(package / "metadata.json", json.dumps(metadata))
                with self.assertRaises(ValueError):
                    shape.validate_package(package)


class ShapeInstallTests(unittest.TestCase):
    def test_only_isolated_qa_files_change_no_production_wrapper_or_controller(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source, project = project_fixture(root)
            package, metadata = package_fixture(root)
            write(source / "tools/qa/shape_candidate_browser.gd", "extends Node\n# shape only\n")
            before_source, before_project, before_package = inventory(source), inventory(project), inventory(package)
            receipt = shape.install(source, project, package)
            self.assertEqual(inventory(source), before_source)
            self.assertEqual(inventory(package), before_package)
            for name, content in before_project.items():
                if name not in ("project.godot", "export_presets.cfg"):
                    self.assertEqual((project / name).read_bytes(), content, name)
            binding = json.loads((project / "qa_shape/candidate_binding.json").read_text())
            self.assertEqual(binding["glb_sha256"], metadata["glb_sha256"])
            self.assertEqual(binding["importer_sha256"], shape.digest((project / "qa_shape/candidate.glb.import").read_bytes()))
            self.assertEqual(receipt["controls_sha256"], shape.digest(shape.review_controls().encode()))
            self.assertFalse(receipt["gallery_eligible"])
            self.assertFalse((project / "qa_shape/source.blend").exists())
            config = (project / "project.godot").read_text()
            self.assertIn("hero_shape_enabled=true", config)
            self.assertNotIn("HeroCandidateQA=", config)
            self.assertIn("animation/import=false", (project / "qa_shape/candidate.glb.import").read_text())

    def test_invalid_package_same_root_and_reinstall_preserve_files(self):
        for case in ("hash", "same_root", "reinstall", "canonical_already_enabled", "filter"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                source, project = project_fixture(root)
                package, _metadata = package_fixture(root)
                write(source / "tools/qa/shape_candidate_browser.gd", "extends Node\n")
                if case == "hash":
                    write(package / "candidate.glb", b"changed")
                elif case == "same_root":
                    source = project
                elif case == "reinstall":
                    shape.install(source, project, package)
                elif case == "canonical_already_enabled":
                    with (project / "project.godot").open("a") as stream:
                        stream.write('HeroCandidateQA="*res://test.gd"\n')
                else:
                    write(project / "export_presets.cfg", "invalid")
                before = inventory(project)
                with self.assertRaises(ValueError):
                    shape.install(source, project, package)
                self.assertEqual(inventory(project), before)

    def test_runtime_helper_is_shape_only_and_preserves_normal_camera(self):
        source = (ROOT / "tools/qa/shape_candidate_browser.gd").read_text()
        for forbidden in ("HeroPenguinRig", "use_authored_backend_for_qa", "missing_contract_items", "trigger_event", "set_pose", "play_state"):
            self.assertNotIn(forbidden, source)
        self.assertIn('_original.visible = false', source)
        self.assertIn('_holder.transform = _original.transform', source)
        self.assertIn('_camera_after != _camera_before', source)
        self.assertIn('not _model.find_children("*", "Skeleton3D"', source)
        self.assertIn('not _model.find_children("*", "AnimationPlayer"', source)
        self.assertNotIn('_install(', source.split('func snapshot()', 1)[1])
        self.assertIn('args[0] not in ["rear", "rear_detail"]', source)

    def test_controls_are_rear_only_no_animation_claim_or_network(self):
        markup = shape.review_controls()
        self.assertIn('Shape review • animation/material detail pending', markup)
        self.assertEqual(markup.count('data-shape-view="'), 2)
        self.assertNotIn('runner_jump', markup)
        self.assertNotIn('runner_slide', markup)
        self.assertNotIn('data-shape-view="front"', markup)
        self.assertNotIn('fetch(', markup)
        script = re.search(r'<script>(.*?)</script>', markup, re.S)[1]
        checked = subprocess.run(['node', '--check'], input=script, text=True, capture_output=True)
        self.assertEqual(checked.returncode, 0, checked.stderr)
        # Execute the actual verification callback: both surface gates must use
        # surface labels, while the older plain shape gate retains its labels.
        verify = script[script.index('async function verify()'):script.index('async function view(')]
        harness = '''
const assert=require('assert');
let receipt,labels;
const window={__wwShapeCandidate:{status:()=>({status:'ready'}),read:()=>receipt}};
const panel={setAttribute:(key,value)=>labels[key]=value,querySelector:key=>labels[key]};
const buttons=[],show=()=>{},delay=()=>Promise.resolve();
''' + verify + '''
(async()=>{for(const gate of ['rear-shape-v1','rear-surface-v1','rear-surface-v2']){
  for(const view of ['rear','rear_detail']){
    labels={strong:{textContent:'Shape review'},small:{textContent:'Shape review • animation/material detail pending'}};
    receipt={gate,view,status:'ready',active_renderer:{signature:'bound',errors:[]}};
    await verify();
    if(gate==='rear-shape-v1'){assert.equal(labels.strong.textContent,'Shape review');}
    else{assert.equal(labels['aria-label'],'Surface review controls');assert.equal(labels.strong.textContent,'Surface review');
      assert(labels.small.textContent.includes('animation/front review pending'));
      assert.equal(labels.small.textContent.includes('pickup overlay hidden'),view==='rear_detail');}
  }
}})().catch(error=>{console.error(error);process.exit(1)});
'''
        checked = subprocess.run(['node'], input=harness, text=True, capture_output=True)
        self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_color_transfer_is_shape_only_explicit_and_renderer_gated(self):
        source = (ROOT / "tools/qa/shape_candidate_browser.gd").read_text()
        transfer = source.split('static func compatibility_color_mesh(', 1)[1].split('\n\nfunc ', 1)[0]
        self.assertIn('if renderer != "gl_compatibility":\n\t\treturn result', transfer)
        self.assertIn('var converted := ArrayMesh.new()', transfer)
        self.assertIn('colors[index] = colors[index].linear_to_srgb()', transfer)
        self.assertIn('converted.surface_set_material(surface, imported.surface_get_material(surface))', transfer)
        self.assertIn('active[index].srgb_to_linear()', transfer)
        self.assertIn('if maximum_error > 0.009:', transfer)
        self.assertIn('"vertex_color_transfers": _color_transfers', source)
        self.assertNotIn('compatibility_color_mesh', (ROOT / 'tools/qa/hero_candidate_browser.gd').read_text())

    def test_shape_stage_skips_only_synthetic_powers_and_rejects_natural_power_pickups(self):
        source = (ROOT / "tools/qa/chrome_reference_bridge.gd").read_text()
        stage = source.split('func _stage_runner(', 1)[1].split('\nfunc ', 1)[0]
        self.assertIn('var shape_only: bool = character_review or name == "runner_hud" and (ProjectSettings.get_setting("qa/hero_shape_enabled", false) == true or ProjectSettings.get_setting("qa/hero_motion_enabled", false) == true)', stage)
        self.assertIn('if not shape_only:\n\t\t\tfor id: StringName in RunnerConfig.POWERUP_IDS: game.player.grant_powerup(id)', stage)
        self.assertIn('elif not game.player.powerups.is_empty():', stage)
        loop = stage.split('while game.elapsed - start < 2.25', 1)[1].split('\n\t\tif game._dead:', 1)[0]
        self.assertIn('if shape_only and not game.player.powerups.is_empty():', loop)
        self.assertIn('_fail("Natural power-up pickup obscured the shape fixture; no capture accepted")', loop)
        self.assertIn('game.vfx._ribbon_acc', stage)
        self.assertIn('if not is_zero_approx(ribbon_accumulator):', stage)
        self.assertIn('"effects_cleared": false', stage)
        self.assertNotIn('vfx.clear()', stage)
        self.assertIn('Shape gate: synthetic power grants skipped;', stage)
        self.assertIn('Three synthetic power grants; real movement/timers', stage)


if __name__ == "__main__":
    unittest.main()
