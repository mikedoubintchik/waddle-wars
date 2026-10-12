"""Pure host contract tests; do not launch any engine or claim rendered success."""
import copy
import hashlib
import importlib.util
from pathlib import Path
import struct
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("rim", ROOT / "tools/art/run_hero_v12_runner_rim_study.py")
R = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R)


def exact(value, raw):
    return {"state": value, "state_bytes_hex": raw.hex(), "sha256": hashlib.sha256(raw).hexdigest()}


def fixture():
    energy = struct.unpack("<f", struct.pack("<f", .812))[0]
    stronger = struct.unpack("<f", struct.pack("<f", 2.1))[0]
    before = {key: exact(key, key.encode()) for key in ("world", "pose", "camera", "material")}
    before["engine_time_scale"] = 0.0
    light = [["/RunnerGame/PlayerRim", "transform", {"class": "OmniLight3D", "light_energy": energy,
              "light_color": "warm", "shadow_enabled": False, "omni_range": 6.4}]]
    raw = b"fixture-light" + struct.pack("<If", 3, energy)
    before["lighting_environment"] = exact(light, raw)
    changed = copy.deepcopy(before)
    changed_light = copy.deepcopy(light)
    changed_light[0][2]["light_energy"] = stronger
    changed["lighting_environment"] = exact(changed_light, raw.replace(struct.pack("<If", 3, energy),
                                                                        struct.pack("<If", 3, stronger)))
    binding = {"candidate_sha256": "candidate", "shader_sha256": "shader",
               "route": "actual-runner-rim-energy-pair-v1", "variants": R.LABELS,
               "rim_energy": 2.1, "freeze_after_running_seconds": 1.0}
    report = {"passed": True, "production_ready": False, "source_fidelity_approved": False,
        "performance_measured": False, "original_rim_restored": True,
        "candidate_sha256": "candidate", "shader_sha256": "shader",
        "state_before": before, "state_variant": changed, "state_after_restore": copy.deepcopy(before),
        "rim_energy_change": {"light_path": light[0][0], "before": energy, "after": stronger},
        "key_context": {"seed": 20260907, "biome": 0, "distance": 15.5, "elapsed": 1.03},
        "frames": [{"variant": R.LABELS[0], "state": copy.deepcopy(before)},
                   {"variant": R.LABELS[1], "state": copy.deepcopy(changed)}]}
    return binding, report


def fill_fixture(diffuse=False):
    binding, report = fixture()
    binding.update(hero_fill_study=True, hero_fill_layer=R.HERO_FILL_LAYER,
                   hero_fill_y_offset=.9, variants=R.LABELS + R.FILL_LABELS)
    if diffuse:
        binding.update(hero_fill_diffuse_study=True, hero_fill_diffuse_energy=4.2, hero_fill_specular=0.0)
        binding["variants"] += [R.DIFFUSE_LABEL]
    path = "/RunnerGame/AuthoredHeroPenguin/Mesh"
    rim = report["rim_energy_change"]["light_path"]
    before = report["state_before"]
    world = [["/RunnerGame", 4], [path, "heroLocal", "heroGlobal", True, [3, 1, "material", None]],
             [rim, "rimLocal", "rimGlobal", True]]
    before["world"] = exact(world, b"worldbefore")
    before["world_scope"] = "fixture"
    original_light = before["lighting_environment"]["state"][0][2]
    original_light.update(light_cull_mask=1048575, transform="rimLocal", light_specular=.7)
    original = {"hero_layers": {path: 3}, "rim_energy": report["rim_energy_change"]["before"],
        "rim_cull_mask": 1048575, "rim_local_position": [-1.5, 2.3499999046325684, 1.7000000476837158],
        "rim_global_position": [-1.5, 2.3499999046325684, 1.7000000476837158],
        "rim_specular": .7,
        "rim_local_basis": exact("basis", b"basis"), "rim_global_basis": exact("basis", b"basis"),
        "player_global_y": 0.0}
    report["layer_audit"] = {"private_bit": R.HERO_FILL_LAYER, "occupied_before": 0,
        "geometry_inventory": {path: 3, "/RunnerGame/Deck": 1}, "hero_paths": [path],
        "camera_cull_mask": 1048575}
    report["original_controls"] = original
    frames = []
    for index, label in enumerate(binding["variants"]):
        state, controls = copy.deepcopy(before), copy.deepcopy(original)
        light = state["lighting_environment"]["state"][0]
        raw = bytes.fromhex(before["lighting_environment"]["state_bytes_hex"])
        if index in (1, 3):
            controls["rim_energy"] = report["rim_energy_change"]["after"]
            light[2]["light_energy"] = controls["rim_energy"]
            raw = raw.replace(struct.pack("<If", 3, original["rim_energy"]), struct.pack("<If", 3, 2.1))
        if index == 4:
            controls["rim_energy"] = light[2]["light_energy"] = struct.unpack("<f", R.float32(4.2))[0]
            controls["rim_specular"] = light[2]["light_specular"] = 0.0
            raw = raw.replace(struct.pack("<If", 3, original["rim_energy"]), struct.pack("<If", 3, 4.2))
        if index >= 2:
            controls["hero_layers"][path] |= R.HERO_FILL_LAYER
            controls["rim_cull_mask"] = R.HERO_FILL_LAYER
            state["world"]["state"][1][4][0] |= R.HERO_FILL_LAYER
            light[2]["light_cull_mask"] = R.HERO_FILL_LAYER
            raw += b"mask"
        if index >= 3:
            controls["rim_global_position"][1] = controls["rim_local_position"][1] = struct.unpack("<f", R.float32(.9))[0]
            state["world"]["state"][2][1:3] = ["lowLocal", "lowGlobal"]
            light[1], light[2]["transform"] = "lowGlobal", "lowLocal"
            raw += b"low"
        state["lighting_environment"] = exact(state["lighting_environment"]["state"], raw)
        if index >= 2:
            state["world"] = exact(state["world"]["state"], f"world{index}".encode())
        frames.append({"variant": label, "state": state, "normalized_state": copy.deepcopy(before), "controls": controls})
    report["frames"] = frames
    report["state_variant"] = copy.deepcopy(frames[1]["state"])
    report["state_after_restore"] = copy.deepcopy(before)
    return binding, report


class RunnerRimStudyTests(unittest.TestCase):
    def test_parser_disables_inherited_watchdog_before_deferred_quit(self):
        source = (ROOT / R.SCRIPT).read_text()
        branch = source.split('if DisplayServer.get_name() == "headless"', 1)[1]
        branch = branch.split('\n\tvar parsed:', 1)[0]
        self.assertLess(branch.index('set_process(false)'), branch.index('get_tree().quit(0)'))
        self.assertLess(branch.index('set_physics_process(false)'), branch.index('get_tree().quit(0)'))

    def test_valid_actual_runner_pair_contract(self):
        binding, report = fixture()
        R.validate_report(report, binding)

    def test_optional_hero_only_pair_contract(self):
        binding, report = fill_fixture()
        R.validate_report(report, binding)

    def test_diffuse_fifth_frame_preserves_first_four(self):
        old_binding, old_report = fill_fixture()
        binding, report = fill_fixture(True)
        self.assertEqual(report["frames"][:4], old_report["frames"])
        self.assertEqual(binding["variants"][:4], old_binding["variants"])
        R.validate_report(report, binding)

    def test_diffuse_recipe_requires_explicit_energy_and_specular(self):
        for key, value in (("hero_fill_diffuse_energy", 8.4), ("hero_fill_specular", .3)):
            binding, report = fill_fixture(True)
            binding[key] = value
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "diffuse4.2"):
                R.validate_report(report, binding)

    def test_diffuse_keeps_hero_material_and_other_light_controls(self):
        for key, value in (("rim_specular", .7), ("rim_energy", 2.1)):
            binding, report = fill_fixture(True)
            report["frames"][4]["controls"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                R.validate_report(report, binding)

    def test_diffuse_actual_light_specular_must_match_control(self):
        binding, report = fill_fixture(True)
        report["frames"][4]["state"]["lighting_environment"]["state"][0][2]["light_specular"] = .7
        with self.assertRaisesRegex(ValueError, "Actual rim specular"):
            R.validate_report(report, binding)

    def test_original_specular_preserved_in_first_four(self):
        binding, report = fill_fixture(True)
        report["frames"][3]["controls"]["rim_specular"] = 0.0
        with self.assertRaises(ValueError):
            R.validate_report(report, binding)

    def test_resource_bearing_capture_scope_unwinds_before_teardown(self):
        source = (ROOT / R.SCRIPT).read_text()
        capture = source.split("func _capture()", 1)[1].split("func _finish_rim_capture", 1)[0]
        self.assertNotIn("await _finish_capture", capture)
        self.assertIn('call_deferred("_finish_rim_capture",', capture)
        self.assertNotIn("Engine.time_scale = original_time_scale", capture)
        cleanup = source.split("func _finish_rim_capture", 1)[1].split("func _reject", 1)[0]
        self.assertIn("Engine.time_scale = original_time_scale", cleanup)
        self.assertIn("_finish_capture(code)", cleanup)
        self.assertNotIn("await _finish_capture", cleanup)

    def test_private_bit_must_be_unoccupied(self):
        binding, report = fill_fixture()
        report["layer_audit"]["geometry_inventory"]["/RunnerGame/Deck"] |= R.HERO_FILL_LAYER
        with self.assertRaisesRegex(ValueError, "occupancy"):
            R.validate_report(report, binding)

    def test_only_actual_authored_hero_subtree_allowed(self):
        binding, report = fill_fixture()
        report["layer_audit"]["hero_paths"] = ["/RunnerGame/Deck"]
        with self.assertRaisesRegex(ValueError, "subtree"):
            R.validate_report(report, binding)

    def test_existing_layer_bits_preserved(self):
        binding, report = fill_fixture()
        path = report["layer_audit"]["hero_paths"][0]
        report["frames"][2]["controls"]["hero_layers"][path] = R.HERO_FILL_LAYER
        with self.assertRaisesRegex(ValueError, "original layer bits"):
            R.validate_report(report, binding)

    def test_hero_only_control_preserves_original_energy_and_position(self):
        for key, value in (("rim_energy", 2.1), ("rim_global_position", [-1.5, .9, 1.7])):
            binding, report = fill_fixture()
            report["frames"][2]["controls"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                R.validate_report(report, binding)

    def test_low_fill_changes_only_vertical_offset(self):
        binding, report = fill_fixture()
        report["frames"][3]["controls"]["rim_global_position"][0] = -.5
        with self.assertRaisesRegex(ValueError, "vertical offset"):
            R.validate_report(report, binding)

    def test_low_fill_basis_is_unchanged(self):
        binding, report = fill_fixture()
        report["frames"][3]["controls"]["rim_global_basis"] = exact("rotated", b"rotated")
        with self.assertRaisesRegex(ValueError, "basis"):
            R.validate_report(report, binding)

    def test_unrelated_normalized_state_must_be_exact(self):
        binding, report = fill_fixture()
        report["frames"][3]["normalized_state"]["pose"] = "changed"
        with self.assertRaisesRegex(ValueError, "Normalized bytes"):
            R.validate_report(report, binding)

    def test_actual_unrelated_light_is_not_hidden_by_normalization(self):
        binding, report = fill_fixture()
        state = report["frames"][3]["state"]
        state["lighting_environment"]["state"][0][2]["light_color"] = "blue"
        with self.assertRaisesRegex(ValueError, "unrelated lighting"):
            R.validate_report(report, binding)

    def test_actual_unrelated_world_is_not_hidden_by_normalization(self):
        binding, report = fill_fixture()
        report["frames"][3]["state"]["world"]["state"][1][3] = False
        with self.assertRaisesRegex(ValueError, "unrelated world"):
            R.validate_report(report, binding)

    def test_hero_fill_flag_required_for_extra_frames(self):
        binding, report = fill_fixture()
        binding["hero_fill_study"] = False
        with self.assertRaisesRegex(ValueError, "explicitly bound"):
            R.validate_report(report, binding)

    def test_actual_float32_energy_representation(self):
        self.assertEqual(R.float32(2.0999999046325684), R.float32(2.1))
        for bad in (None, True, "2.1"):
            with self.assertRaises(ValueError):
                R.float32(bad)

    def test_wrong_candidate_shader_or_approval_claim_fails(self):
        for key, value in (("candidate_sha256", "wrong"), ("shader_sha256", "other"),
                           ("passed", False), ("production_ready", True),
                           ("source_fidelity_approved", True), ("performance_measured", True)):
            binding, report = fixture()
            report[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                R.validate_report(report, binding)

    def test_wrong_bound_recipe_fails(self):
        for key, value in (("rim_energy", 3.0), ("freeze_after_running_seconds", 4),
                           ("variants", list(reversed(R.LABELS)))):
            binding, report = fixture()
            binding[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                R.validate_report(report, binding)

    def test_world_pose_material_camera_are_immutable(self):
        for key in ("world", "pose", "material", "camera"):
            binding, report = fixture()
            report["state_variant"][key] = "changed"
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "Runner world"):
                R.validate_report(report, binding)

    def test_lighting_may_change_only_existing_rim_energy(self):
        for key, value in (("shadow_enabled", True), ("light_color", "blue"), ("omni_range", 9)):
            binding, report = fixture()
            report["state_variant"]["lighting_environment"]["state"][0][2][key] = value
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "besides rim energy"):
                R.validate_report(report, binding)

    def test_target_must_be_named_existing_player_rim(self):
        binding, report = fixture()
        report["rim_energy_change"]["light_path"] = "/RunnerGame/OtherOmni"
        with self.assertRaisesRegex(ValueError, "PlayerRim"):
            R.validate_report(report, binding)

    def test_baseline_energy_must_be_measured_positive_and_below_target(self):
        for value in (None, True, 0, -1, 2.1, 4, float("nan")):
            binding, report = fixture()
            report["rim_energy_change"]["before"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                R.validate_report(report, binding)

    def test_no_change_hidden_in_lighting_bytes(self):
        binding, report = fixture()
        report["state_variant"]["lighting_environment"]["state_bytes_hex"] += "00"
        with self.assertRaisesRegex(ValueError, "Exact lighting bytes"):
            R.validate_report(report, binding)

    def test_exact_state_hashes_verified(self):
        binding, report = fixture()
        for state in [report["state_before"], report["state_variant"], report["state_after_restore"],
                      *[row["state"] for row in report["frames"]]]:
            state["camera"]["sha256"] = "forged"
        with self.assertRaisesRegex(ValueError, "state hash mismatch"):
            R.validate_report(report, binding)

    def test_second_frame_must_actually_use_changed_state(self):
        binding, report = fixture()
        report["frames"][1]["state"] = copy.deepcopy(report["state_before"])
        with self.assertRaisesRegex(ValueError, "ordered"):
            R.validate_report(report, binding)

    def test_restore_is_mandatory(self):
        binding, report = fixture()
        report["state_after_restore"] = copy.deepcopy(report["state_variant"])
        with self.assertRaisesRegex(ValueError, "not restored"):
            R.validate_report(report, binding)

    def test_actual_sequential_day_context_required(self):
        for key, value in (("seed", 1), ("biome", 2), ("distance", 360), ("elapsed", 4)):
            binding, report = fixture()
            report["key_context"][key] = value
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "sequential day"):
                R.validate_report(report, binding)

    def test_prepare_reuses_strict_package_and_runner_route(self):
        with patch.object(R.route, "prepare", side_effect=ValueError("projection rejected")) as prepare:
            with self.assertRaisesRegex(ValueError, "projection rejected"):
                R.prepare(Path("source"), Path("output"))
            prepare.assert_called_once_with(Path("source"), Path("output"), "Y03-runner-rim-study", "atlas")

    def test_scene_inherits_real_runner_without_gameplay_or_material_substitution(self):
        source = (ROOT / R.SCRIPT).read_text()
        self.assertTrue(source.startswith('extends "res://tests/hero_v12_atlas_runner_capture.gd"'))
        for forbidden in ("func _build_stage", "func _place_camera", "set_shader_parameter", "shadows_disabled",
                          "player.position =", "player.distance =", "light_color =", "shadow_enabled ="):
            self.assertNotIn(forbidden, source)
        self.assertIn("Engine.time_scale = 0.0", source)
        self.assertIn("Engine.time_scale = original_time_scale", source)
        self.assertIn("rim.light_energy = original_energy", source)
        self.assertIn("no raster/lighting proof", source)
        self.assertIn("Private hero-fill layer already occupied", source)
        self.assertIn("original | HERO_FILL_LAYER", source)
        self.assertNotIn("camera.cull_mask =", source)


if __name__ == "__main__":
    unittest.main()
