"""Host guards for the tiny real-render diagnostic; no engine processes."""
import copy
import hashlib
import importlib.util
from pathlib import Path
import struct
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("diagnostic", ROOT / "tools/art/run_hero_v12_atlas_material_diagnostic.py")
D = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(D)


def report_fixture(receiver_shadow_study=False, key_energy_study=False):
    binding = {"candidate_sha256": "asset", "baseline_shader_sha256": "baseline",
               "hard_normal_zero_shader_sha256": "normal", "variants": list(D.LABELS)}
    if receiver_shadow_study:
        binding.update(receiver_shadow_study=True,
                       receiver_shadows_disabled_shader_sha256="receiver",
                       variants=list(D.LABELS + (D.RECEIVER_LABEL,)))
    if key_energy_study:
        binding.update(key_energy_study=True, receiver_shadows_disabled_shader_sha256="receiver",
                       key_energy_values={"before": .54, "after": .27})
        binding["variants"] += list(D.KEY_LABELS)
    uniforms = {"normal_strength": 1.0, "hard_specular": .5, "feather_specular": .4,
                "atlas_albedo": {"instance_id": 1, "file_sha256": "albedo"},
                "atlas_normal": {"instance_id": 2, "file_sha256": "normal"},
                "atlas_orm": {"instance_id": 3, "file_sha256": "orm"},
                "atlas_masks": {"instance_id": 4, "file_sha256": "masks"}}
    state = {"geometry_sha256": "mesh"}
    for key in ("pose", "lighting_environment", "camera"):
        raw = ("fixture:" + key).encode()
        state[key] = {"state_bytes_hex": raw.hex(), "sha256": hashlib.sha256(raw).hexdigest(), "state": key}
    change = {}
    half = {}
    if key_energy_study:
        energy = struct.unpack("<f", struct.pack("<f", .54))[0]
        reduced = struct.unpack("<f", struct.pack("<f", .27))[0]
        raw = b"fixture:lighting" + struct.pack("<If", 3, .54)
        state["lighting_environment"] = {"state_bytes_hex": raw.hex(),
            "sha256": hashlib.sha256(raw).hexdigest(),
            "state": [["/key", "transform", {"class": "DirectionalLight3D", "light_energy": energy,
                                              "shadow_enabled": True, "light_color": "warm"}]]}
        change = {"light_path": "/key", "before": energy, "after": reduced}
        half = copy.deepcopy(state)
        raw_half = raw.replace(struct.pack("<If", 3, .54), struct.pack("<If", 3, .27))
        half["lighting_environment"]["state"][0][2]["light_energy"] = reduced
        half["lighting_environment"].update(state_bytes_hex=raw_half.hex(),
            sha256=hashlib.sha256(raw_half).hexdigest())
    frames = [{"variant": label, "state": copy.deepcopy(state), "material": {
        "shader_sha256": "normal" if label == "hard_normal_zero" else (
            "receiver" if label in (D.RECEIVER_LABEL, D.KEY_LABELS[1]) else "baseline"),
        "uniforms": {"state": {**uniforms, "hard_specular": 0.0} if index == 2 else copy.deepcopy(uniforms)}}}
        for index, label in enumerate(binding["variants"])]
    for frame in frames:
        if frame["variant"] in D.KEY_LABELS:
            frame["state"] = copy.deepcopy(half)
    return binding, {"passed": True, "production_ready": False, "source_fidelity_approved": False,
        "performance_measured": False, "candidate_sha256": "asset", "original_material_restored": True,
        "geometry_lighting_camera_pose_unchanged": not key_energy_study,
        "geometry_camera_pose_unchanged": True, "state_before": state,
        "state_after_restore": copy.deepcopy(state), "frames": frames,
        "half_key_state": half, "key_energy_change": change,
        "frozen_pose": {"motion": "run", "fps": 30, "frame": 24, "fixed_steps_after_frame_zero": 24,
                        "automatic_animation_processing": False}}


class MaterialDiagnosticTests(unittest.TestCase):
    def test_variant_changes_only_exact_hard_normal_expression(self):
        original = (ROOT / D.route.SHADER).read_text()
        changed = D.normal_variant(original)
        self.assertEqual(changed.replace(D.NORMAL_DIAGNOSTIC, D.NORMAL_ANCHOR), original)
        self.assertEqual(changed.count(D.NORMAL_DIAGNOSTIC), 1)
        self.assertIn("SPECULAR = mix(hard_specular, feather_specular, feather);", changed)

    def test_missing_or_ambiguous_normal_anchor_fails(self):
        original = (ROOT / D.route.SHADER).read_text()
        for changed in (original.replace(D.NORMAL_ANCHOR, "NORMAL_MAP_DEPTH=0.;"), original + D.NORMAL_ANCHOR,
                        original.replace("float feather = smoothstep(0.25, 0.75, masks.a);", "float feather = 0.;")):
            with self.assertRaises(ValueError):
                D.normal_variant(changed)

    def test_receiver_variant_changes_only_render_mode(self):
        original = (ROOT / D.route.SHADER).read_text()
        changed = D.receiver_shadow_variant(original)
        self.assertEqual(changed.replace(D.RENDER_DIAGNOSTIC, D.RENDER_ANCHOR), original)
        self.assertEqual(changed.count("shadows_disabled"), 1)
        self.assertIn(D.NORMAL_ANCHOR, changed)
        self.assertIn("SPECULAR = mix(hard_specular, feather_specular, feather);", changed)

    def test_receiver_variant_rejects_missing_or_ambiguous_mode(self):
        original = (ROOT / D.route.SHADER).read_text()
        for changed in (original.replace(D.RENDER_ANCHOR, "render_mode unshaded;"),
                        original + D.RENDER_ANCHOR, original + "\nrender_mode shadows_disabled;"):
            with self.assertRaises(ValueError):
                D.receiver_shadow_variant(changed)

    def test_valid_three_frame_evidence(self):
        binding, report = report_fixture()
        D.validate_report(report, binding)

    def test_optional_four_frame_evidence(self):
        binding, report = report_fixture(True)
        D.validate_report(report, binding)
        self.assertEqual(D.variant_labels(binding), D.LABELS + (D.RECEIVER_LABEL,))

    def test_key_study_independent_or_combined_with_receiver_flag(self):
        for receiver in (False, True):
            binding, report = report_fixture(receiver, True)
            D.validate_report(report, binding)
            self.assertEqual(len(report["frames"]), 6 if receiver else 5)
            self.assertEqual(tuple(binding["variants"][-2:]), D.KEY_LABELS)

    def test_key_study_keeps_original_controls_exact(self):
        binding, report = report_fixture(True, True)
        for row in report["frames"][:4]:
            self.assertEqual(row["state"], report["state_before"])
        report["frames"][0]["state"] = copy.deepcopy(report["half_key_state"])
        with self.assertRaisesRegex(ValueError, "changed across frames"):
            D.validate_report(report, binding)

    def test_half_key_requires_exact_scalar_and_original_light(self):
        for key, value in (("before", .55), ("after", .26), ("after", True), ("light_path", "/rim")):
            binding, report = report_fixture(False, True)
            report["key_energy_change"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                D.validate_report(report, binding)

    def test_half_key_recipe_is_bound_not_an_arbitrary_exposure(self):
        binding, report = report_fixture(False, True)
        binding["key_energy_values"]["after"] = .1
        with self.assertRaisesRegex(ValueError, "exact bound"):
            D.validate_report(report, binding)

    def test_half_key_does_not_claim_all_lighting_unchanged(self):
        binding, report = report_fixture(False, True)
        report["geometry_lighting_camera_pose_unchanged"] = True
        with self.assertRaisesRegex(ValueError, "state/restoration"):
            D.validate_report(report, binding)

    def test_half_key_cannot_change_other_lighting_property(self):
        for key, value in (("shadow_enabled", False), ("light_color", "blue"), ("new_property", 1)):
            binding, report = report_fixture(False, True)
            report["half_key_state"]["lighting_environment"]["state"][0][2][key] = value
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "another lighting property"):
                D.validate_report(report, binding)

    def test_half_key_cannot_change_hidden_state_bytes(self):
        binding, report = report_fixture(False, True)
        evidence = report["half_key_state"]["lighting_environment"]
        raw = bytes.fromhex(evidence["state_bytes_hex"]) + b"extra"
        evidence.update(state_bytes_hex=raw.hex(), sha256=hashlib.sha256(raw).hexdigest())
        with self.assertRaisesRegex(ValueError, "exact state bytes"):
            D.validate_report(report, binding)

    def test_half_key_cannot_change_pose_geometry_camera(self):
        for key in ("pose", "camera", "geometry_sha256"):
            binding, report = report_fixture(False, True)
            report["half_key_state"][key] = "changed"
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "geometry, pose or camera"):
                D.validate_report(report, binding)

    def test_half_key_requires_actual_half_state_in_both_frames(self):
        binding, report = report_fixture(True, True)
        report["frames"][-1]["state"] = copy.deepcopy(report["state_before"])
        with self.assertRaisesRegex(ValueError, "changed across frames"):
            D.validate_report(report, binding)

    def test_half_key_keeps_baseline_material_uniforms(self):
        binding, report = report_fixture(True, True)
        report["frames"][-1]["material"]["uniforms"]["state"]["hard_specular"] = 0.0
        with self.assertRaisesRegex(ValueError, "unspecified material"):
            D.validate_report(report, binding)

    def test_half_key_restore_is_mandatory(self):
        binding, report = report_fixture(True, True)
        report["state_after_restore"] = copy.deepcopy(report["half_key_state"])
        with self.assertRaisesRegex(ValueError, "changed across frames"):
            D.validate_report(report, binding)

    def test_receiver_requires_explicit_flag_order_and_hash(self):
        for field, value in (("receiver_shadow_study", False), ("receiver_shadow_study", 1),
                             ("variants", list(D.LABELS)),
                             ("receiver_shadows_disabled_shader_sha256", None)):
            binding, report = report_fixture(True)
            binding[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                D.validate_report(report, binding)

    def test_receiver_does_not_change_any_uniform_or_feather_parameter(self):
        for key, value in (("hard_specular", 0.0), ("feather_specular", .1),
                           ("normal_strength", 0.0), ("atlas_masks", {"instance_id": 99})):
            binding, report = report_fixture(True)
            report["frames"][3]["material"]["uniforms"]["state"][key] = value
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "unspecified material"):
                D.validate_report(report, binding)

    def test_receiver_lighting_pose_camera_and_casting_state_stay_exact(self):
        for key in ("geometry_sha256", "lighting_environment", "camera", "pose"):
            binding, report = report_fixture(True)
            report["frames"][3]["state"][key] = "changed"
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "changed across frames"):
                D.validate_report(report, binding)

    def test_receiver_has_its_own_exact_shader_hash(self):
        binding, report = report_fixture(True)
        report["frames"][3]["material"]["shader_sha256"] = "baseline"
        with self.assertRaisesRegex(ValueError, "Shader changes"):
            D.validate_report(report, binding)

    def test_unrequested_fourth_frame_rejected(self):
        _, extra = report_fixture(True)
        binding, report = report_fixture()
        report["frames"].append(extra["frames"][3])
        with self.assertRaisesRegex(ValueError, "3 ordered"):
            D.validate_report(report, binding)

    def test_godot_float32_json_representation_is_not_a_uniform_change(self):
        binding, report = report_fixture()
        for row in report["frames"]:
            row["material"]["uniforms"]["state"]["feather_specular"] = 0.400000005960464
        D.validate_report(report, binding)
        for value in (True, None, "0.4", float("nan"), float("inf"), 0.400001, .41):
            with self.subTest(value=value):
                self.assertFalse(D.shader_float_matches(value, .4))

    def test_parser_only_gate_does_not_claim_material_or_raster_proof(self):
        scene = (ROOT / D.SCRIPT).read_text()
        self.assertIn("parsercheck=true", scene)
        self.assertIn("no raster/material test", scene)

    def test_wrong_asset_or_approval_claim_rejected(self):
        for key, value in (("candidate_sha256", "other"), ("production_ready", True),
                           ("source_fidelity_approved", True), ("performance_measured", True),
                           ("original_material_restored", False), ("passed", False)):
            binding, report = report_fixture()
            report[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                D.validate_report(report, binding)

    def test_changed_geometry_light_camera_or_pose_rejected(self):
        for key in ("geometry_sha256", "lighting_environment", "camera", "pose"):
            binding, report = report_fixture()
            report["frames"][1]["state"][key] = "changed"
            with self.subTest(key=key), self.assertRaises(ValueError):
                D.validate_report(report, binding)

    def test_fabricated_exact_state_hash_rejected(self):
        binding, report = report_fixture()
        for target in [report["state_before"], report["state_after_restore"], *[f["state"] for f in report["frames"]]]:
            target["camera"]["state_bytes_hex"] = "00"
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            D.validate_report(report, binding)

    def test_wrong_shader_variant_rejected(self):
        binding, report = report_fixture()
        report["frames"][2]["material"]["shader_sha256"] = "unrelated"
        with self.assertRaisesRegex(ValueError, "Shader changes"):
            D.validate_report(report, binding)

    def test_feather_texture_and_roughness_parameters_never_change(self):
        for key, value in (("feather_specular", .1), ("normal_strength", .35),
                           ("atlas_normal", {"instance_id": 9}), ("roughness_override", .9)):
            binding, report = report_fixture()
            report["frames"][1]["material"]["uniforms"]["state"][key] = value
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "unspecified material"):
                D.validate_report(report, binding)

    def test_extra_or_reordered_frames_fail(self):
        for operation in (lambda rows: rows.reverse(), lambda rows: rows.append(copy.deepcopy(rows[0]))):
            binding, report = report_fixture()
            operation(report["frames"])
            with self.assertRaisesRegex(ValueError, "3 ordered"):
                D.validate_report(report, binding)

    def test_changed_frozen_frame_fails(self):
        binding, report = report_fixture()
        report["frozen_pose"]["frame"] = 25
        with self.assertRaisesRegex(ValueError, "frame24"):
            D.validate_report(report, binding)

    def test_prepare_reuses_strict_existing_route(self):
        # Reject before a separate pipeline or engine can be created.
        with patch.object(D.route, "prepare", side_effect=ValueError("zero-miss gate")) as prepare:
            with self.assertRaisesRegex(ValueError, "zero-miss gate"):
                D.prepare(Path("rejected"), Path("unused"))
            prepare.assert_called_once_with(Path("rejected"), Path("unused"), "Y03-material-diagnostic", "atlas")

    def test_optional_prepare_still_reuses_existing_route(self):
        with patch.object(D.route, "prepare", side_effect=ValueError("zero-miss gate")) as prepare:
            with self.assertRaisesRegex(ValueError, "zero-miss gate"):
                D.prepare(Path("rejected"), Path("unused"), True)
            prepare.assert_called_once_with(Path("rejected"), Path("unused"), "Y03-material-diagnostic", "atlas")

    def test_scene_reuses_real_stage_and_manual_pose(self):
        scene = (ROOT / D.SCRIPT).read_text()
        self.assertTrue(scene.startswith('extends "res://tests/hero_penguin_capture.gd"'))
        self.assertNotIn("func _build_stage", scene)
        self.assertNotIn("func _configure_camera", scene)
        self.assertNotIn("func _step_motion", scene)
        self.assertIn("for _frame: int in 24:", scene)
        self.assertIn("_step_motion(1.0 / 30.0)", scene)
        self.assertIn('specular_off.set_shader_parameter("hard_specular", 0.0)', scene)
        self.assertIn("original_material_restored", scene)
        self.assertIn("baseline.shader.code.replace(RENDER_ANCHOR, RENDER_DIAGNOSTIC)", scene)
        self.assertIn('"cast_shadow": mesh.cast_shadow', scene)
        self.assertNotIn(".shadow_enabled =", scene)
        self.assertNotIn(".cast_shadow =", scene)


if __name__ == "__main__":
    unittest.main()
