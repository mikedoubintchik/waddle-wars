"""Behavioral isolation and immutable-package tests; no engine/browser required."""
from __future__ import annotations

import importlib.util
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load_tool(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


export = load_tool("hero_candidate_export_tests", "tools/qa/hero_candidate_export.py")
common = load_tool("hero_candidate_review_tests", "tools/art/run_hero_v12_runner_review.py")


def write(path: Path, content: str | bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content.encode() if isinstance(content, str) else content)


def inventory(path: Path) -> dict[str, bytes]:
    return {item.relative_to(path).as_posix(): item.read_bytes()
            for item in path.rglob("*") if item.is_file()}


def fixture(folder: Path) -> tuple[Path, Path]:
    source, project = folder / "source", folder / "project"
    # Host installation binds bytes; engine import validation is a separate gate.
    write(source / export.MODEL, b"canonical-host-fixture-glb")
    write(source / (export.MODEL + ".import"),
          '[remap]\npath="res://.godot/imported/source.scn"\n\n[params]\n'
          'nodes/use_name_suffixes=false\nskins/use_named_skins=true\n')
    write(source / export.WRAPPER,
          '[gd_scene load_steps=3 format=3]\n'
          '[ext_resource type="Script" path="res://scripts/characters/hero_penguin_rig.gd" id="1"]\n'
          f'[ext_resource type="PackedScene" path="res://{export.MODEL}" id="2"]\n'
          '[node name="HeroPenguinRig" type="Node3D"]\nscript = ExtResource("1")\n'
          '[node name="ImportedRig" parent="." instance=ExtResource("2")]\n')
    for name in export.RESOURCES:
        write(source / name, "unchanged runtime resource: " + name)
    write(source / "scripts/characters/hero_penguin_rig.gd", "extends Node3D\n# production controller\n")
    write(source / "scripts/characters/penguin_visual.gd",
          "extends Node3D\nstatic var use_authored_backend_for_qa: bool = false\n")
    write(source / "tools/qa/hero_candidate_browser.gd", "extends Node\n# isolated observer\n")
    write(source / "project.godot", '[application]\nconfig/name="Waddle Wars"\n[autoload]\n[display]\n')
    write(source / "export_presets.cfg", '[preset.0]\ninclude_filter="data/wardrobe/*.json"\n')
    shutil.copytree(source, project)
    (project / "_qa_local").mkdir()
    write(project / "project.godot", '[application]\nconfig/name="Waddle QA"\n'
          'config/use_custom_user_dir=true\nconfig/custom_user_dir_name="waddle-chrome-reference-test"\n'
          '[autoload]\nChromeReferenceQA="*res://_qa_local/chrome_reference_bridge.gd"\n'
          '[qa]\nroute_token="fixture-token"\n[display]\nwindow/size/viewport_width=1280\n')
    write(project / "export_presets.cfg", '[preset.0]\n'
          'include_filter="data/wardrobe/*.json,data/commerce/*.json,_qa_local/*.js"\n'
          'exclude_filter="tests/*,qa_shots/*,art_src/*"\nscript_export_mode=2\n')
    return source, project


class HeroCandidateExportTests(unittest.TestCase):
    def test_install_preserves_source_and_actual_production_rig_materials(self):
        with tempfile.TemporaryDirectory() as temp:
            source, project = fixture(Path(temp))
            original = inventory(source)
            prepared = inventory(project)
            receipt = export.install(source, project)
            self.assertEqual(inventory(source), original)
            for name in (*export.RESOURCES, export.MODEL,
                         "scripts/characters/hero_penguin_rig.gd", "scripts/characters/penguin_visual.gd"):
                self.assertEqual((project / name).read_bytes(), prepared[name])
            self.assertEqual((project / "qa_hero/candidate.glb").read_bytes(), original[export.MODEL])
            wrapper = (project / export.WRAPPER).read_text()
            self.assertIn('path="res://scripts/characters/hero_penguin_rig.gd"', wrapper)
            self.assertIn('path="res://qa_hero/candidate.glb"', wrapper)
            self.assertIn('[node name="Model"', wrapper)
            self.assertNotIn('path="res://tests/', wrapper)
            self.assertEqual((project / "_qa_local/hero_candidate_browser.gd").read_bytes(),
                             original["tools/qa/hero_candidate_browser.gd"])
            self.assertFalse(receipt["gallery_eligible"])

    def test_only_prepared_config_enables_candidate_and_production_filters_survive(self):
        with tempfile.TemporaryDirectory() as temp:
            source, project = fixture(Path(temp))
            before_config = (project / "project.godot").read_text()
            before_preset = (project / "export_presets.cfg").read_text()
            export.install(source, project)
            config = (project / "project.godot").read_text()
            self.assertEqual(config.count('HeroCandidateQA="*res://_qa_local/hero_candidate_browser.gd"'), 1)
            self.assertEqual(config.count("hero_candidate_enabled=true"), 1)
            self.assertEqual(config.replace('HeroCandidateQA="*res://_qa_local/hero_candidate_browser.gd"\n', "")
                             .replace("hero_candidate_enabled=true\n", ""), before_config)
            self.assertEqual((project / "export_presets.cfg").read_text()
                             .replace(",qa_hero/*.json", ""), before_preset)
            self.assertNotIn("HeroCandidateQA", (source / "project.godot").read_text())
            self.assertIn("use_authored_backend_for_qa: bool = false",
                          (project / "scripts/characters/penguin_visual.gd").read_text())

    def test_receipt_binds_actual_model_resources_wrapper_and_helper(self):
        with tempfile.TemporaryDirectory() as temp:
            source, project = fixture(Path(temp))
            receipt = export.install(source, project)
            binding = json.loads((project / "qa_hero/candidate_binding.json").read_text())
            self.assertEqual(receipt["binding"], binding)
            self.assertEqual(binding["glb_sha256"], export.sha(project / "qa_hero/candidate.glb"))
            self.assertEqual(binding["runtime_resources"], {name: export.sha(project / name) for name in export.RESOURCES})
            self.assertEqual(receipt["wrapper_sha256"], export.sha(project / export.WRAPPER))
            self.assertEqual(receipt["helper_sha256"], export.sha(project / "_qa_local/hero_candidate_browser.gd"))
            self.assertEqual(receipt["controls_sha256"], hashlib.sha256(export.review_controls().encode()).hexdigest())
            self.assertEqual(binding["material_mode"], "runtime")
            self.assertEqual(binding["color_contract"], "runtime-semantic-COLOR_0")
            self.assertFalse(binding["production_ready"])
            self.assertFalse(binding["source_fidelity_approved"])

    def test_canonical_import_parameters_remain_exact(self):
        with tempfile.TemporaryDirectory() as temp:
            source, project = fixture(Path(temp))
            export.install(source, project)
            original = (source / (export.MODEL + ".import")).read_text()
            copied = (project / "qa_hero/candidate.glb.import").read_text()
            self.assertEqual(copied.split("[params]", 1)[1], original.split("[params]", 1)[1])
            self.assertNotIn("res://.godot/imported/source.scn", copied)

    def test_same_source_and_symlink_alias_are_rejected_without_changes(self):
        with tempfile.TemporaryDirectory() as temp:
            source, _project = fixture(Path(temp))
            original = inventory(source)
            alias = Path(temp) / "source-alias"
            alias.symlink_to(source, target_is_directory=True)
            for target in (source, alias):
                with self.subTest(target=target), self.assertRaisesRegex(ValueError, "separate prepared QA project"):
                    export.install(source, target)
            self.assertEqual(inventory(source), original)

    def test_reinstall_rejected_before_existing_evidence_is_modified(self):
        with tempfile.TemporaryDirectory() as temp:
            source, project = fixture(Path(temp))
            export.install(source, project)
            original = inventory(project)
            with self.assertRaisesRegex(ValueError, "already installed"):
                export.install(source, project)
            self.assertEqual(inventory(project), original)

    def test_unisolated_project_rejected_before_candidate_creation(self):
        for invalid in ("identity", "bridge", "directory"):
            with self.subTest(invalid=invalid), tempfile.TemporaryDirectory() as temp:
                source, project = fixture(Path(temp))
                if invalid == "directory":
                    (project / "_qa_local").rmdir()
                else:
                    text = (project / "project.godot").read_text()
                    text = text.replace("waddle-chrome-reference-test", "production") if invalid == "identity" \
                        else text.replace('ChromeReferenceQA="*res://_qa_local/chrome_reference_bridge.gd"', "")
                    (project / "project.godot").write_text(text)
                original = inventory(project)
                with self.assertRaises(ValueError):
                    export.install(source, project)
                self.assertEqual(inventory(project), original)

    def test_divergent_copied_model_controller_wrapper_or_materials_are_rejected(self):
        for name in (export.MODEL, export.WRAPPER, export.CONTROLLER, *export.RESOURCES):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp:
                source, project = fixture(Path(temp))
                with (project / name).open("ab") as stream:
                    stream.write(b"copied resource drift")
                original_source, original_project = inventory(source), inventory(project)
                with self.assertRaisesRegex(ValueError, "Prepared runtime resource differs from source"):
                    export.install(source, project)
                self.assertEqual(inventory(source), original_source)
                self.assertEqual(inventory(project), original_project)
                self.assertFalse((project / "qa_hero").exists())

    def test_malformed_config_rejected_without_partial_install(self):
        mutations = (
            lambda text: text.replace("config/use_custom_user_dir=true", "config/use_custom_user_dir=false"),
            lambda text: text.replace("[qa]\n", "[different]\n"),
            lambda text: text.replace("[qa]\n", "[qa]\n[qa]\n"),
            lambda text: text.replace("[qa]\n", "[qa]\nhero_candidate_enabled=false\n"),
            lambda text: text.replace("[autoload]\n", "[other]\n"),
            lambda text: text.replace("[autoload]\n", '[autoload]\nconfig/custom_user_dir_name="another"\n'),
            lambda text: text.replace("[autoload]\n", "[autoload]\nconfig/use_custom_user_dir=false\n"),
        )
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index), tempfile.TemporaryDirectory() as temp:
                source, project = fixture(Path(temp))
                config = project / "project.godot"
                config.write_text(mutate(config.read_text()))
                original_source, original_project = inventory(source), inventory(project)
                with self.assertRaises(ValueError):
                    export.install(source, project)
                self.assertEqual(inventory(source), original_source)
                self.assertEqual(inventory(project), original_project)
                self.assertFalse((project / "qa_hero").exists())

    def test_malformed_wrapper_importer_or_filter_rejected_before_any_writes(self):
        for invalid in ("wrapper_model", "wrapper_node", "wrapper_controller", "importer", "filter", "duplicate_filter", "missing_helper"):
            with self.subTest(invalid=invalid), tempfile.TemporaryDirectory() as temp:
                source, project = fixture(Path(temp))
                if invalid.startswith("wrapper_"):
                    content = (source / export.WRAPPER).read_text()
                    if invalid == "wrapper_model":
                        content = content.replace(export.MODEL, "missing.glb")
                    elif invalid == "wrapper_node":
                        content = content.replace('[node name="ImportedRig"', '[node name="Other"')
                    else:
                        content = content.replace(export.CONTROLLER, "tests/replacement.gd")
                    # Both frozen copies agree, but neither satisfies canonical contract.
                    (source / export.WRAPPER).write_text(content)
                    (project / export.WRAPPER).write_text(content)
                elif invalid == "importer":
                    (source / (export.MODEL + ".import")).write_text("[remap]\n# no parameters\n")
                elif invalid == "missing_helper":
                    (source / export.HELPER).unlink()
                else:
                    presets = project / "export_presets.cfg"
                    content = presets.read_text()
                    content = content.replace(",_qa_local/*.js", "") if invalid == "filter" else content + 'include_filter="duplicate"\n'
                    presets.write_text(content)
                original_source, original_project = inventory(source), inventory(project)
                with self.assertRaises((ValueError, FileNotFoundError)):
                    export.install(source, project)
                self.assertEqual(inventory(source), original_source)
                self.assertEqual(inventory(project), original_project)
                self.assertFalse((project / "qa_hero").exists())

    def test_symlinked_destination_cannot_modify_source(self):
        for name in (export.WRAPPER, "project.godot", "export_presets.cfg"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp:
                source, project = fixture(Path(temp))
                (project / name).unlink()
                (project / name).symlink_to(source / name)
                original_source, original_project = inventory(source), inventory(project)
                with self.assertRaisesRegex(ValueError, "unsafe prepared project file"):
                    export.install(source, project)
                self.assertEqual(inventory(source), original_source)
                self.assertEqual(inventory(project), original_project)

    def test_existing_candidate_files_preserved_before_partial_install(self):
        for name in ("qa_hero/evidence.json", "_qa_local/hero_candidate_browser.gd"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp:
                source, project = fixture(Path(temp))
                write(project / name, "existing evidence")
                original_project = inventory(project)
                with self.assertRaisesRegex(ValueError, "Candidate files already exist"):
                    export.install(source, project)
                self.assertEqual(inventory(project), original_project)


class CandidateReviewControlsTests(unittest.TestCase):
    def test_candidate_only_markup_has_six_accessible_controls_and_no_network(self):
        markup = export.review_controls()
        self.assertEqual(markup.count('data-candidate-view="'), 3)
        self.assertEqual(markup.count('data-candidate-pose="'), 3)
        self.assertIn('aria-live="polite"', markup)
        self.assertIn('aria-label="Candidate preview controls" hidden', markup)
        self.assertIn('window.__wwQABuild?.hero_candidate', markup)
        for forbidden in ('fetch(', 'XMLHttpRequest', 'WebSocket', '<iframe', 'https://', 'http://'):
            self.assertNotIn(forbidden, markup)

    def test_controls_wait_for_frozen_frames_and_hash_only_after_actions(self):
        script = re.search(r'<script>(.*?)</script>', export.review_controls(), re.S)[1]
        harness = r'''
const vm = require('node:vm');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const script = fs.readFileSync(0, 'utf8');
function makeEnvironment(enabled = true) {
  const queue = [], handlers = new Map(), counts = {reads:0, views:[], routes:[]};
  const stage = {status:'ready', route:'main_menu', tree_paused:false, settled_frames:0, submitted_frames:0};
  let activeView = 'chase', failure = false;
  const buttons = (kind, values) => values.map(value => ({dataset:{[kind]:value}, disabled:false,
    setAttribute(name, next) { this[name] = next; }, addEventListener(_name, callback) { handlers.set(value, callback); }}));
  const views = buttons('candidateView', ['chase','front','side']);
  const poses = buttons('candidatePose', ['runner_hud','runner_jump','runner_slide']);
  const panel = {hidden:true,dataset:{},querySelectorAll(selector) { return selector.includes('view') ? views : poses; }};
  const status = {textContent:''};
  const window = {__wwQABuild:enabled ? {hero_candidate:{}} : {},
    __wwQA:{read(){return {...stage};},route(route){counts.routes.push(route);stage.route=route;stage.tree_paused=true;stage.settled_frames=0;activeView='chase';}},
    __wwHeroCandidate:{read(){counts.reads++; assert.equal(stage.tree_paused,true); assert.ok(stage.settled_frames>=2);
      return {status:failure?'error':'ready',tree_paused:true,settled_frames:stage.settled_frames,view:activeView,active_renderer:{signature:'frozen',errors:[]}};},
      view(view){counts.views.push(view);assert.equal(stage.tree_paused,true);assert.ok(stage.settled_frames>=2);activeView=view;}}};
  const context = {window,location:{hostname:'localhost',search:'?qa_token=test'},URLSearchParams,Date,
    document:{getElementById(id){return id==='ww-candidate-review'?panel:status;}},
    setTimeout(callback){queue.push(callback);},requestAnimationFrame(callback){queue.push(callback);}};
  vm.runInNewContext(script,context);
  async function drain(){for(let i=0;i<100;i++){await Promise.resolve();if(queue.length){stage.submitted_frames++;stage.settled_frames++;queue.shift()();}
    if(panel.dataset.state==='verified'||panel.dataset.state==='error') {await Promise.resolve(); return;}}
    throw new Error('controls never settled');}
  return {panel,status,stage,counts,handlers,drain,queue,setFailure(){failure=true;}};
}
(async () => {
  const disabled=makeEnvironment(false);
  assert.equal(disabled.panel.hidden,true);assert.equal(disabled.counts.reads,0);assert.equal(disabled.queue.length,0);
  const env=makeEnvironment();
  assert.equal(env.panel.hidden,false);assert.equal(env.counts.reads,0);
  await env.drain();
  assert.equal(env.status.textContent,'Verified');assert.deepEqual(env.counts.routes,['runner_hud']);assert.equal(env.counts.reads,1);
  assert.equal(env.queue.length,0,'no recurring fingerprint polling after verification');
  env.handlers.get('front')(); await env.drain();
  assert.deepEqual(env.counts.views,['front']);assert.equal(env.counts.reads,2);
  env.handlers.get('runner_jump')(); await env.drain();
  assert.deepEqual(env.counts.routes,['runner_hud','runner_jump']);assert.equal(env.counts.reads,3);
  env.setFailure();env.handlers.get('side')();await env.drain();
  assert.equal(env.panel.dataset.state,'error');assert.equal(env.status.textContent,'Verification failed');
})().catch(error => {console.error(error);process.exitCode=1;});
'''
        result = subprocess.run(['node', '-e', harness], input=script, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)


class CandidateFixtureIntegrityTests(unittest.TestCase):
    def make_fixture(self, folder: Path):
        files = {
            "project.godot": "[application]\nconfig/use_custom_user_dir=true\n",
            "tests/hero_candidate_session.gd": "extends RefCounted\n# guarded selection\n",
            "assets/art/characters/hero_penguin_v1_material.tres": "[resource]\nshader_parameter/rim_strength=0.055\n",
            "scripts/shaders/hero_penguin_v1.gdshader": "shader_type spatial;\n",
            "qa_hero/candidate.glb.import": "[params]\nnodes/use_name_suffixes=false\n",
            "qa_hero/candidate_binding.json": '{"material_mode":"runtime"}\n',
        }
        for name, content in files.items():
            write(folder / name, content)
        return files, {"fixture_hashes": common.fixture_hashes(folder)}

    def test_frozen_fixture_accepts_exact_files(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            files, state = self.make_fixture(project)
            self.assertEqual(set(state["fixture_hashes"]), set(files))
            common.verify_fixture(project, state)

    def test_changed_helper_material_shader_import_or_binding_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            files, state = self.make_fixture(project)
            for name, content in files.items():
                with self.subTest(name=name):
                    (project / name).write_text(content + "changed\n")
                    with self.assertRaisesRegex(ValueError, "Prepared fixture changed"):
                        common.verify_fixture(project, state)
                    (project / name).write_text(content)

    def test_missing_and_additional_runtime_inputs_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            files, state = self.make_fixture(project)
            name = "tests/hero_candidate_session.gd"
            (project / name).unlink()
            with self.assertRaises(ValueError):
                common.verify_fixture(project, state)
            write(project / name, files[name])
            write(project / "tests/unbound_helper.gd", "extends Node\n")
            with self.assertRaises(ValueError):
                common.verify_fixture(project, state)

    def test_import_cache_and_python_cache_do_not_invalidate_source_binding(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            _files, state = self.make_fixture(project)
            write(project / ".godot/imported/cache.scn", b"generated import bytes")
            write(project / "tests/__pycache__/helper.cpython-314.pyc", b"generated bytecode")
            common.verify_fixture(project, state)

    def test_missing_or_empty_inventory_never_counts_as_verified(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            self.make_fixture(project)
            for state in ({}, {"fixture_hashes": {}}, {"fixture_hashes": []}):
                with self.subTest(state=state), self.assertRaises(ValueError):
                    common.verify_fixture(project, state)


if __name__ == "__main__":
    unittest.main()
