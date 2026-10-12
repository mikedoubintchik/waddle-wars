"""Renderer-free, fail-closed handoff of saved QA source-study provenance.

The saved sculpt is authoritative. This reader never imports or executes the
design/renderer, or reapplies a study to geometry. AST hashes are declarations
bound to the immutable scene and its two sidecars, not a fresh geometry proof.
Historical Z01 did not record renderer AST hashes; that absence stays explicit.
"""
from __future__ import annotations

import copy
import hashlib
import json
import math
from pathlib import Path
import re

SCENE_FIELDS = ("source_study_profile", "source_study_json", "source_study_production_ready")
BINDING_FIELD = "candidate_source_study_binding_json"
JUVENILE_PROFILES = ("juvenile-sculpt-z05", "juvenile-socket-z06")
PROFILES = ("baseline", "eye-aperture-z01", "face-paddles-z02", "orbital-heading-z03", "orbital-saddle-z04",
            *JUVENILE_PROFILES)
# This is not a member of PROFILES. Its saved source needs a separate adjacent
# review contract; validate_record and all historical defaults remain closed.
UNIFIED_PROFILE = "unified-juvenile-face"
UNIFIED_CONSTRUCTION_SHA256 = "ebcf05f6cfe7d02611c3f7e4316d59329acb84eec920eb69a7e6908ebfb55d85"
UNIFIED_PAINT_PROGRAM_SHA256 = "25980d468bb5d613a2220de17f85c792dfa527d874e4db2108204de8db1e416b"
UNIFIED_QA_SCOPE = "candidate-only budgeted textured shared-rig review; no runtime or production promotion"
UNIFIED_CAPTURE_TOOLS = (
    "hero_penguin_v12_design.py", "render_hero_penguin_v12_source_proof.py",
    "hero_penguin_v12_source_study.py", "render_hero_penguin_v12_source_study.py",
    "hero_penguin_v12_materials.py", "hero_penguin_v12_feather_detail_recipe.py",
    "hero_penguin_eye_pigment.py", "hero_penguin_face_sculpt.py",
    "render_hero_penguin_face_sculpt.py", "render_hero_penguin_v12_face_z13.py",
    *(f"hero_penguin_v12_face_z{number:02d}.py" for number in range(9, 14)),
)
UNIFIED_CAPTURE_TILES = tuple(f"hero_penguin_v11_{region}_{kind}_tile.png"
                              for region in ("dark", "cream") for kind in ("albedo", "normal", "orm"))
UNIFIED_IMAGES = tuple(f"hero_penguin_v12_blender_{view}.png" for view in ("front", "threequarter", "true_side"))
UNIFIED_REVIEW_FIELDS = {
    "schema_version", "study_profile", "review_scope", "source_only", "candidate_only_budgeted_review",
    "production_ready", "source_fidelity_approved", "geometry_approved", "runtime_rig_or_glb_created",
    "source_blend_filename", "source_blend_sha256", "source_study_inputs_sha256", "source_study_audit_sha256",
    "selected_construction_source_sha256", "continuous_paint_program_sha256", "capture_dependencies",
    "inspected_image_filenames", "image_outputs",
}
FULL_COHORT_FIELDS = ("baseline_design_ast_sha256", "design_literal_overrides",
                     "baseline_renderer_path", "baseline_renderer_sha256",
                     "baseline_renderer_ast_sha256", "selected_renderer_ast_sha256",
                     "renderer_literal_overrides")
PIN_SCOPE = {
    "coordinate_bands_origin": "X/Y source-space measurements only",
    "exact_pin_preservation_meaning": "Selected vertices/faces only; not full orbital cover or aperture validation",
    "study_source_cover_approved": False,
    "source_fidelity_approved": False,
    "production_ready": False,
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _reject(message):
    raise RuntimeError("source study provenance: " + message)


def _object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            _reject("duplicate JSON key: " + key)
        value[key] = item
    return value


def parse_json(raw):
    if not isinstance(raw, str):
        _reject("scene metadata must be JSON text")
    try:
        result = json.loads(raw, object_pairs_hook=_object,
                            parse_constant=lambda token: _reject("nonfinite JSON: " + token))
        json.dumps(result, allow_nan=False)
    except (TypeError, ValueError) as error:
        _reject("invalid JSON: " + str(error))
    if not isinstance(result, dict):
        _reject("metadata must be an object")
    return result


def _same(left, right):
    # JSON type equality matters: bool and int must not alias approval fields.
    return json.dumps(left, sort_keys=True, allow_nan=False) == json.dumps(right, sort_keys=True, allow_nan=False)


def _digest(value, label):
    if not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None:
        _reject("invalid SHA256: " + label)
    return value


def _design_edits(profile):
    if profile in JUVENILE_PROFILES:
        return _juvenile_design_edits(profile)
    edits = [] if profile == "baseline" else [("EYE_BURY_DEPTH", (), .069, .064)]
    if profile in {"face-paddles-z02", "orbital-heading-z03", "orbital-saddle-z04"}:
        edits += [("BILL_UPPER_SECTIONS", (0, 2), .087, .105),
                  ("BILL_UPPER_SECTIONS", (1, 2), .090, .108),
                  ("BILL_LOWER_SECTIONS", (1, 1), .120, .108)]
    if profile == "orbital-heading-z03":
        edits += [("EYE_ORBITAL_HEADING_FACTOR", (), 1.35, 2.0)]
    if profile == "orbital-saddle-z04":
        edits += [("EYE_CENTER_X", (), .181, .225)]
    return edits


def _renderer_edits(profile):
    if profile in JUVENILE_PROFILES:
        return [{"anchor": "add_bill.nostril." + axis, "baseline": old, "selected": new}
                for axis, old, new in (("x", .042, .047), ("y", -.408, -.448), ("z", 1.456, 1.429))]
    if profile not in {"face-paddles-z02", "orbital-heading-z03", "orbital-saddle-z04"}:
        return []
    orbit = [] if profile == "orbital-saddle-z04" else [
        {"anchor": f"body_paint.orbit.ellipse[{side}].{axis}", "baseline": old, "selected": new}
        for side in (0, 1) for axis, old, new in (("rx", .120, .108), ("rz", .125, .118))]
    return orbit + [
        {"anchor": f"add_paddle.width_keys[t={t}].width", "baseline": old, "selected": new}
        for t, old, new in ((.84, .039, .050), (.93, .026, .036), (.97, .017, .025))]


def _juvenile_design_edits(profile):
    """Frozen declarations, never imported from or applied to design geometry.

    Z06 inherits the Z05 literals except its attentive gaze target. Keeping this
    independent of mutable source-study code lets older saved scenes validate
    against their own hash-bound declaration cohort.
    """
    edits = [
        ("BODY_SMOOTH_RADIUS", (), .105, .125),
        ("TORSO_RADII", (0,), .526, .550), ("TORSO_RADII", (1,), .427, .446),
        ("TORSO_UPPER_EXPONENT", (), 2.1, 2.45),
        ("BODY_VOLUMES", (0, 1, 0), .375, .420), ("BODY_VOLUMES", (0, 1, 1), .345, .373),
        ("BODY_VOLUMES", (0, 1, 2), .368, .389), ("BODY_VOLUMES", (1, 0, 2), 1.441, 1.375),
        ("BODY_VOLUMES", (1, 1, 0), .400, .438), ("BODY_VOLUMES", (1, 1, 1), .365, .391),
        ("BODY_VOLUMES", (1, 1, 2), .365, .427), ("BODY_VOLUMES", (2, 0, 2), 1.280, 1.235),
        ("BODY_VOLUMES", (2, 1, 0), .357, .402), ("BODY_VOLUMES", (2, 1, 1), .332, .364),
        ("BODY_VOLUMES", (2, 1, 2), .257, .290),
        ("CHEEK_VOLUMES", (0, 0, 0), -.162, -.182), ("CHEEK_VOLUMES", (1, 0, 0), .162, .182),
        *(("CHEEK_VOLUMES", (side, 0, 2), 1.394, 1.333) for side in (0, 1)),
        *(("CHEEK_VOLUMES", (side, 1, 0), .222, .250) for side in (0, 1)),
        *(("CHEEK_VOLUMES", (side, 1, 1), .203, .216) for side in (0, 1)),
        *(("CHEEK_VOLUMES", (side, 1, 2), .146, .174) for side in (0, 1)),
        ("CHEEK_VOLUMES", (2, 0, 2), 1.277, 1.200), ("CHEEK_VOLUMES", (2, 1, 0), .227, .263),
        ("CHEEK_VOLUMES", (2, 1, 1), .185, .200), ("CHEEK_VOLUMES", (2, 1, 2), .184, .217),
        ("EYE_CENTER_X", (), .181, .215), ("EYE_CENTER_Z", (), 1.548, 1.480),
        ("EYE_RADII", (0,), .108, .147), ("EYE_RADII", (1,), .089, .100),
        ("EYE_RADII", (2,), .146, .176), ("EYE_BURY_DEPTH", (), .069, .074),
        ("EYE_ORBITAL_HEADING_FACTOR", (), 1.35, 1.70),
        ("EYE_GAZE_TARGET", (2,), 2.45, 2.40 if profile == "juvenile-socket-z06" else 1.68),
        ("EYE_GAZE_HORIZONTAL_SCALE", (), .60, .20),
        ("UPPER_FOLD_APERTURE_HEIGHT", (), .083, .097), ("UPPER_FOLD_APERTURE_WIDTH", (), .080, .105),
        ("LIMBAL_RADII", (0,), .067, .080), ("LIMBAL_RADII", (1,), .087, .102),
        ("IRIS_RADII", (0,), .061, .073), ("IRIS_RADII", (1,), .081, .093),
        ("PUPIL_RADII", (0,), .037, .044), ("PUPIL_RADII", (1,), .050, .059),
    ]
    for name, before, after in (
        ("BILL_UPPER_SECTIONS",
         ((-.351, .100, .087, 1.389), (-.397, .125, .090, 1.378), (-.431, .117, .084, 1.371),
          (-.466, .087, .067, 1.372), (-.500, .050, .042, 1.380), (-.526, .023, .022, 1.388),
          (-.538, .003, .002, 1.392)),
         ((-.389, .118, .105, 1.331), (-.431, .147, .119, 1.320), (-.471, .135, .109, 1.309),
          (-.508, .097, .078, 1.306), (-.540, .058, .046, 1.311), (-.562, .026, .021, 1.321),
          (-.571, .003, .002, 1.326))),
        ("BILL_LOWER_SECTIONS",
         ((-.354, .098, .013, 1.389), (-.397, .120, .031, 1.378), (-.431, .110, .034, 1.371),
          (-.463, .079, .026, 1.373), (-.488, .044, .016, 1.382), (-.507, .017, .004, 1.389),
          (-.512, .002, .001, 1.392)),
         ((-.392, .112, .018, 1.331), (-.431, .133, .038, 1.320), (-.469, .119, .041, 1.310),
          (-.502, .088, .031, 1.307), (-.526, .048, .019, 1.315), (-.545, .019, .006, 1.323),
          (-.550, .002, .001, 1.326))),
    ):
        edits.extend((name, (row, column), old, new)
                     for row, (old_row, new_row) in enumerate(zip(before, after))
                     for column, (old, new) in enumerate(zip(old_row, new_row)) if old != new)
    return edits + [
        ("WING_ROOT", (0,), .310, .345), ("WING_ROOT", (2,), 1.225, 1.200),
        ("WING_CONTROL", (0,), .615, .640), ("WING_CONTROL", (2,), .987, .940),
        ("WING_TIP", (0,), .705, .690), ("WING_TIP", (2,), .484, .460),
        ("WING_HALF_WIDTH", (), .128, .147), ("WING_HALF_THICKNESS", (), .045, .050),
    ]


def juvenile_declarations(profile):
    """Exact recorded expressions/imports; their text is validated, not executed."""
    design = saddle_declarations()["design_expression_overrides"] + [
        {"anchor": "upper_lid_pigment_weight.width_gate",
         "baseline": "smooth(-0.030, -0.005, depth) * (1.0 - smooth(0.075, 0.100, abs(x)))",
         "selected": "smooth(-0.030, -0.005, depth) * (1.0 - smooth(0.098, 0.130, abs(x)))"},
        {"anchor": "bill_smile_offset.depth_registration",
         "baseline": "min(1.0, max(0.0, (y + 0.480) / 0.085))",
         "selected": "min(1.0, max(0.0, (y + 0.520) / 0.090))"},
    ]
    renderer = [{"anchor": "body_paint.orbit",
        "baseline": saddle_declarations()["renderer_expression_overrides"][0]["baseline"],
        "selected": "juvenile_orbit_field(point, eye_surface_frame)"}]
    renderer += [{"anchor": anchor, "baseline": old, "selected": new} for anchor, old, new in (
        ("body_paint.cheek", "min(ellipse(-0.162, 1.394, 0.235, 0.159), ellipse(0.162, 1.394, 0.235, 0.159))",
         "min(ellipse(-0.182, 1.333, 0.265, 0.182), ellipse(0.182, 1.333, 0.265, 0.182))"),
        ("body_paint.chin", "ellipse(0.0, 1.225, 0.308, 0.244)", "ellipse(0.0, 1.180, 0.337, 0.260)"),
        ("body_paint.ear_field", "((angle - 1.46) / 0.40) ** 2 + ((point.z - 1.411) / 0.078) ** 2",
         "((angle - 1.46) / 0.40) ** 2 + ((point.z - 1.350) / 0.092) ** 2"),
        ("body_paint.stripe_z", "1.232 + 0.040 * (angle - 1.10) + 0.017 * math.sin((angle - 1.10) * 3.3)",
         "1.188 + 0.040 * (angle - 1.10) + 0.017 * math.sin((angle - 1.10) * 3.3)"),
        ("body_paint.bridge_height", "smoothstep(1.442 + 0.75 * abs(point.x), 1.470 + 0.75 * abs(point.x), point.z)",
         "smoothstep(1.384 + 0.75 * abs(point.x), 1.412 + 0.75 * abs(point.x), point.z)"),
        ("add_paddle.width_keys", "((0.0, 0.055), (0.18, 0.102), (0.4, 0.095), (0.65, 0.065), (0.84, 0.039), (0.93, 0.026), (0.97, 0.017), (1.0, 0.004))",
         "((0.0, 0.055), (0.18, 0.11), (0.4, 0.104), (0.65, 0.076), (0.84, 0.05), (0.93, 0.036), (0.97, 0.025), (1.0, 0.004))"),
        ("refine_orbital_surface.near_eye", "0.045 < abs(point.x) < 0.40 and point.y < -0.19 and 1.43 < point.z < 1.77",
         "0.045 < abs(point.x) < 0.43 and point.y < -0.19 and 1.32 < point.z < 1.77"),
    )]
    result = {"design_expression_overrides": design, "renderer_expression_overrides": renderer,
              "renderer_added_imports": ["from hero_penguin_v12_source_study import juvenile_orbit_field"]}
    if profile == "juvenile-socket-z06":
        design.append({"anchor": "sculpt_body_field.base", "baseline": "base_body_field(points)",
                       "selected": "juvenile_socket_relief(points, base_body_field(points), eye_surface_frame)"})
        result["design_added_imports"] = ["from hero_penguin_v12_source_study import juvenile_socket_relief"]
        result["socket_relief_recipe"] = {"maximum_inward_m": .020, "outer_center_m": .025,
            "vertical_center_m": -.055, "half_width_m": .150, "half_height_m": .140,
            "depth_fade_m": [-.070, -.020], "upper_fade_m": [-.025, .030],
            "globe_or_burial_changed": False, "source_fidelity_approved": False}
    return result


def saddle_declarations():
    """Explicit source-only expression contract; no design/helper execution."""
    return {
        "design_expression_overrides": [{"anchor": "upper_lid_pigment_weight.upper",
            "baseline": "smooth(-0.002, 0.001, edge) * (1.0 - smooth(0.010, 0.025, edge))",
            "selected": "smooth(-0.002, 0.001, edge)"}],
        "renderer_expression_overrides": [{"anchor": "body_paint.orbit",
            "baseline": "min(ellipse(-EYE_CENTER_X, EYE_CENTER_Z - 0.019, 0.120, 0.125), ellipse(EYE_CENTER_X, EYE_CENTER_Z - 0.019, 0.120, 0.125))",
            "selected": "saddle_orbit_field(point, eye_surface_frame)"}],
        "renderer_added_imports": ["from hero_penguin_v12_orbital_saddle import saddle_orbit_field"],
        "orbital_saddle_recipe": {"contract": "orbital-saddle-paint-v1", "half_width_m": .108,
            "lower_width_gain_m": .025, "lower_nasal_sweep_m": .035, "vertical_center_m": -.026,
            "upper_radius_m": .120, "lower_radius_m": .170, "almond_horizontal_power": 1.75,
            "depth_fade_m": [-.085, -.040], "geometry_created": False, "source_fidelity_approved": False},
    }


def validate_record(record):
    """Check recorded profile and cohort without consulting mutable live tools."""
    if type(record.get("schema_version")) is not int or record["schema_version"] != 1:
        _reject("unsupported record schema")
    profile = record.get("study_profile")
    if not isinstance(profile, str) or profile not in PROFILES:
        _reject("unknown study profile")
    for field, expected in (("source_only", True), ("production_ready", False),
                            ("source_fidelity_approved", False), ("runtime_rig_or_glb_created", False),
                            ("renderer_cohort_verified_before_geometry", True)):
        if record.get(field) is not expected:
            _reject("invalid explicit status: " + field)
    if not isinstance(record.get("prediction_only"), str) or "unapproved" not in record["prediction_only"]:
        _reject("analytical aperture must remain explicitly unapproved")
    baseline = record.get("baseline_design_constants")
    selected = record.get("selected_design_constants")
    if not isinstance(baseline, dict) or not isinstance(selected, dict):
        _reject("missing design constant cohort")
    expected = copy.deepcopy(baseline)
    edits = _design_edits(profile)
    literal_records = []
    try:
        for name, indices, old, new in edits:
            parent = expected
            keys = (name, *indices)
            for key in keys[:-1]:
                parent = parent[key]
            if type(parent[keys[-1]]) is not float or parent[keys[-1]] != old:
                _reject("declared baseline literal changed: " + name)
            parent[keys[-1]] = new
            literal_records.append({"anchor": name + "".join(f"[{index}]" for index in indices),
                                    "baseline": old, "selected": new})
    except (KeyError, IndexError, TypeError):
        _reject("invalid design override anchor")
    if not _same(selected, expected):
        _reject("selected constants differ outside declared study edits")
    overrides = {name: {"baseline": baseline[name], "selected": selected[name]}
                 for name in sorted({edit[0] for edit in edits})}
    if not _same(record.get("parameter_overrides"), overrides):
        _reject("parameter overrides disagree with selected constants")
    inputs = record.get("inputs")
    if not isinstance(inputs, dict) or not inputs:
        _reject("missing source tool/input hashes")
    for path, digest in inputs.items():
        if not isinstance(path, str) or not Path(path).is_absolute():
            _reject("source input paths must be absolute")
        _digest(digest, path)
    design_path, renderer_path = record.get("baseline_design_path"), record.get("source_renderer")
    if (not isinstance(design_path, str) or not isinstance(renderer_path, str)
            or inputs.get(design_path) != _digest(record.get("baseline_design_sha256"), "design")
            or renderer_path not in inputs):
        _reject("design/renderer input binding mismatch")
    helpers = [digest for path, digest in inputs.items() if Path(path).name == "hero_penguin_v12_source_study.py"]
    if helpers != [_digest(record.get("profile_helper_sha256"), "profile helper")]:
        _reject("profile helper input binding mismatch")
    _digest(record.get("selected_design_ast_sha256"), "selected design AST")
    present = [key in record for key in FULL_COHORT_FIELDS]
    if any(present) and not all(present):
        _reject("partial AST cohort metadata")
    if not any(present):
        # Only the saved original Z01 launcher emitted this narrower schema.
        if (profile != "eye-aperture-z01" or record.get("application") !=
                "one literal override before fresh design module execution and renderer import"):
            _reject("full AST cohort required for this study")
        ast_status = "historical-z01: selected design AST recorded; renderer AST not recorded"
    else:
        for field in ("baseline_design_ast_sha256", "baseline_renderer_ast_sha256", "selected_renderer_ast_sha256"):
            _digest(record.get(field), field)
        if (record["baseline_renderer_path"] != renderer_path
                or record["baseline_renderer_sha256"] != inputs[renderer_path]):
            _reject("renderer cohort hash mismatch")
        if not _same(record["design_literal_overrides"], literal_records):
            _reject("design AST edit declarations mismatch")
        if not _same(record["renderer_literal_overrides"], _renderer_edits(profile)):
            _reject("renderer AST edit declarations mismatch")
        if (record["baseline_design_ast_sha256"] == record["selected_design_ast_sha256"]) != (not edits):
            _reject("design AST mutation disagrees with profile")
        if (record["baseline_renderer_ast_sha256"] == record["selected_renderer_ast_sha256"]) != (not _renderer_edits(profile)):
            _reject("renderer AST mutation disagrees with profile")
        ast_status = "full recorded design/renderer AST cohort; not re-executed"
    declarations = saddle_declarations()
    if profile == "orbital-saddle-z04":
        for field, value in declarations.items():
            if not _same(record.get(field), value):
                _reject("saddle expression/recipe mismatch: " + field)
        if baseline.get("EYE_ORBITAL_HEADING_FACTOR") != 1.35 or selected.get("EYE_ORBITAL_HEADING_FACTOR") != 1.35:
            _reject("saddle must retain unexaggerated orbital heading")
        helper_hashes = [digest for path, digest in inputs.items()
                         if Path(path).name == "hero_penguin_v12_orbital_saddle.py"]
        if helper_hashes != [_digest(record.get("orbital_saddle_helper_sha256"), "saddle helper")]:
            _reject("saddle helper input binding mismatch")
    elif profile in JUVENILE_PROFILES:
        for field, value in juvenile_declarations(profile).items():
            if not _same(record.get(field), value):
                _reject("juvenile expression/recipe mismatch: " + field)
        if helpers != [_digest(record.get("juvenile_orbit_helper_sha256"), "juvenile helper")]:
            _reject("juvenile helper input binding mismatch")
        if any(field in record for field in ("orbital_saddle_recipe", "orbital_saddle_helper_sha256")):
            _reject("undeclared saddle edits in juvenile profile")
        if profile == "juvenile-sculpt-z05" and any(field in record for field in
                ("design_added_imports", "socket_relief_recipe", "socket_contract")):
            _reject("undeclared socket edits in juvenile-sculpt-z05")
    elif any(field in record for field in (*declarations, "orbital_saddle_helper_sha256",
            "juvenile_orbit_helper_sha256", "design_added_imports", "socket_relief_recipe", "socket_contract")):
        _reject("undeclared saddle edits in another profile")
    command = record.get("command")
    if (not isinstance(command, list) or not all(isinstance(item, str) for item in command)
            or command.count("--study-profile") != 1
            or command[-1:] == ["--study-profile"]
            or command[command.index("--study-profile") + 1] != profile):
        _reject("command profile disagrees with metadata")
    return ast_status


def _unified_file(path, label):
    path = Path(path)
    if (not path.is_absolute() or path.is_symlink() or not path.is_file()
            or str(path) != str(path.resolve())):
        _reject("missing or noncanonical unified QA file: " + label)
    return sha(path)


def _unified_status(record, *, review=False):
    if type(record.get("schema_version")) is not int or record["schema_version"] != 1:
        _reject("unsupported unified QA schema")
    statuses = [("source_only", True), ("production_ready", False), ("source_fidelity_approved", False),
                ("runtime_rig_or_glb_created", False)]
    if review:
        statuses += [("geometry_approved", False), ("candidate_only_budgeted_review", True)]
    for key, expected in statuses:
        if record.get(key) is not expected:
            _reject("invalid unified QA explicit status: " + key)


def _read_unified_review(source, record, audit, raw_inputs, raw_audit):
    """Admit only this reviewed construction for isolated candidate QA.

    Hashes bind the original saved scene, metadata, capture dependencies and
    actual inspected images. No design imports, AST replay, scene mutation or
    production/appearance approval occurs here.
    """
    review_path = source.with_name("source_qa_review.json")
    _unified_file(review_path, "source_qa_review.json")
    raw_review = review_path.read_bytes()
    review = parse_json(raw_review.decode("utf-8"))
    if set(review) != UNIFIED_REVIEW_FIELDS:
        _reject("incomplete or extended unified QA review contract")
    _unified_status(review, review=True)
    _unified_status(record)
    if (review["study_profile"] != UNIFIED_PROFILE or record.get("study_profile") != UNIFIED_PROFILE
            or review["review_scope"] != UNIFIED_QA_SCOPE or record.get("parent_profile") != "juvenile-socket-z06"):
        _reject("unified QA profile/scope mismatch")
    for key, expected in (("geometry_approved", False), ("candidate_export_allowed", False),
                          ("renderer_cohort_verified_before_geometry", True)):
        if record.get(key) is not expected:
            _reject("invalid unified source explicit status: " + key)
    expected_hashes = {"source_blend_sha256": _unified_file(source, source.name),
                       "source_study_inputs_sha256": hashlib.sha256(raw_inputs).hexdigest(),
                       "source_study_audit_sha256": hashlib.sha256(raw_audit).hexdigest(),
                       "selected_construction_source_sha256": UNIFIED_CONSTRUCTION_SHA256,
                       "continuous_paint_program_sha256": UNIFIED_PAINT_PROGRAM_SHA256}
    if review["source_blend_filename"] != source.name:
        _reject("unified QA source filename mismatch")
    for key, expected in expected_hashes.items():
        if _digest(review[key], key) != expected:
            _reject("unified QA review hash mismatch: " + key)
    inputs = record.get("inputs")
    if not isinstance(inputs, dict) or not _same(review["capture_dependencies"], inputs):
        _reject("unified QA capture dependencies mismatch")
    helper, launcher, material_dir = (record.get(key) for key in ("selected_helper", "selected_launcher", "material_dir"))
    if any(not isinstance(path, str) or not Path(path).is_absolute() for path in (helper, launcher, material_dir)):
        _reject("unified QA tool/material paths must be absolute")
    tool_dir = Path(helper).parent
    expected_inputs = {str(tool_dir / name) for name in UNIFIED_CAPTURE_TOOLS}
    expected_inputs.update(str(Path(material_dir) / name) for name in UNIFIED_CAPTURE_TILES)
    if (set(inputs) != expected_inputs or Path(helper).name != "hero_penguin_face_sculpt.py"
            or launcher != str(tool_dir / "render_hero_penguin_face_sculpt.py")
            or record.get("source_renderer") != str(tool_dir / "render_hero_penguin_v12_source_proof.py")
            or inputs.get(helper) != UNIFIED_CONSTRUCTION_SHA256):
        _reject("incomplete or relabelled unified QA capture dependencies")
    for path, digest in inputs.items():
        if _digest(digest, path) != _unified_file(path, path):
            _reject("unified QA capture dependency SHA changed: " + path)
    _digest(record.get("selected_renderer_ast_sha256"), "unified renderer AST")
    design = record.get("selected_design_record")
    parent_renderer = record.get("parent_renderer_record")
    if (not isinstance(design, dict) or not isinstance(parent_renderer, dict)
            or not isinstance(design.get("selected_design_constants"), dict)
            or not isinstance(design.get("support_volumes"), list)
            or not isinstance(design.get("aperture_landmarks"), dict)
            or design.get("old_orbital_sculpt_and_separate_hood_overlay_retired") is not True
            or not isinstance(design.get("parent_design_record"), dict)):
        _reject("missing unified QA construction cohort")
    parent = design["parent_design_record"]
    _unified_status(parent)
    if parent.get("study_profile") != "juvenile-socket-z06":
        _reject("unified QA parent profile mismatch")
    for field in ("baseline_design_ast_sha256", "selected_design_ast_sha256"):
        _digest(parent.get(field), field)
    for field in ("baseline_renderer_ast_sha256", "selected_renderer_ast_sha256"):
        _digest(parent_renderer.get(field), field)
    for cohort, path_key, hash_key, expected_path in (
            (parent, "baseline_design_path", "baseline_design_sha256", tool_dir / "hero_penguin_v12_design.py"),
            (parent_renderer, "baseline_renderer_path", "baseline_renderer_sha256", tool_dir / "render_hero_penguin_v12_source_proof.py")):
        if cohort.get(path_key) != str(expected_path) or cohort.get(hash_key) != inputs[str(expected_path)]:
            _reject("unified QA parent input binding mismatch")
    paint = record.get("continuous_paint_input")
    if not isinstance(paint, dict) or paint.get("program_sha256") != UNIFIED_PAINT_PROGRAM_SHA256:
        _reject("unified QA continuous paint program mismatch")
    for key, expected in (("visual_approval", False), ("geometry_changed", False),
                          ("runtime_procedural_shader_added", False), ("body_vertex_color_dependency", False),
                          ("wing_material_and_paint_unchanged", True), ("material_response_recipe_preserved", True)):
        if paint.get(key) is not expected:
            _reject("invalid unified QA paint status: " + key)
    command = record.get("command")
    if (not isinstance(command, list) or not all(isinstance(value, str) for value in command)
            or command.count("--python") != 1 or command[-1:] == ["--python"]
            or Path(command[command.index("--python") + 1]).name != Path(launcher).name
            or "--study-profile" in command):
        _reject("unified QA launcher command mismatch")
    images = review["image_outputs"]
    if (review["inspected_image_filenames"] != list(UNIFIED_IMAGES) or not isinstance(images, dict)
            or set(images) != set(UNIFIED_IMAGES) or set(audit["outputs"]) != {source.name, *UNIFIED_IMAGES}):
        _reject("unified QA inspected image cohort mismatch")
    for name in UNIFIED_IMAGES:
        if (_digest(images[name], name) != audit["outputs"].get(name)
                or images[name] != _unified_file(source.with_name(name), name)):
            _reject("unified QA inspected image SHA mismatch: " + name)
    # Preserve the exact raw contract hash, not a lossy normalized substitute.
    if _unified_file(review_path, "source_qa_review.json") != hashlib.sha256(raw_review).hexdigest():
        _reject("unified QA review changed during read")
    return review, hashlib.sha256(raw_review).hexdigest()


def read_source_study(source, scene):
    """Return hash-bound provenance, or None only for wholly absent legacy data.

    During bake, the candidate's preserved original scene fields are checked
    against the original source sidecars. The candidate itself is SHA-bound by
    its audit before this call; no source scene import or geometry replay occurs.
    """
    source = Path(source).resolve()
    paths = [source.with_name(name) for name in ("source_study_inputs.json", "source_study_audit.json")]
    fields = [field in scene for field in SCENE_FIELDS]
    sides = [path.exists() for path in paths]
    review_exists = source.with_name("source_qa_review.json").exists()
    if not any(fields + sides) and BINDING_FIELD not in scene and not review_exists:
        return None
    if not all(fields + sides):
        _reject("partial scene/sidecar metadata; legacy fallback forbidden")
    raw_inputs, raw_audit = (path.read_bytes() for path in paths)
    record = parse_json(raw_inputs.decode("utf-8"))
    audit = parse_json(raw_audit.decode("utf-8"))
    if not _same(record, parse_json(scene["source_study_json"])):
        _reject("saved scene and input sidecar disagree")
    if scene["source_study_profile"] != record.get("study_profile") or scene["source_study_production_ready"] is not False:
        _reject("saved scene profile/status disagree")
    extras = {"inputs_unchanged", "outputs", "rendered_views"}
    if not _same(record, {key: value for key, value in audit.items() if key not in extras}):
        _reject("completed audit and input sidecar disagree")
    if audit.get("inputs_unchanged") is not True or audit.get("rendered_views") != ["front", "threequarter", "true_side"]:
        _reject("source study has no complete three-view audit")
    outputs = audit.get("outputs")
    digest = sha(source)
    required_outputs = {source.name, *(f"hero_penguin_v12_blender_{view}.png" for view in audit["rendered_views"])}
    if (not isinstance(outputs, dict) or outputs.get(source.name) != digest
            or not required_outputs <= outputs.keys()):
        _reject("source blend SHA mismatch")
    for name, value in outputs.items():
        _digest(value, name)
    review = None
    if record.get("study_profile") == UNIFIED_PROFILE:
        review, review_hash = _read_unified_review(source, record, audit, raw_inputs, raw_audit)
        ast_status = "reviewed candidate-only unified source cohort; design/renderer not re-executed"
    else:
        if review_exists:
            _reject("unified QA review cannot relabel a legacy profile")
        ast_status = validate_record(record)
    binding = {"schema_version": 1, "study_profile": record["study_profile"],
            "metadata_reader_sha256": sha(Path(__file__)),
            "source_blend_sha256": digest,
            "source_study_inputs_sha256": hashlib.sha256(raw_inputs).hexdigest(),
            "source_study_audit_sha256": hashlib.sha256(raw_audit).hexdigest(), "record": record,
            "ast_evidence": ast_status, "source_cover_scope": copy.deepcopy(PIN_SCOPE),
            "production_ready": False, "source_fidelity_approved": False}
    if review is not None:
        binding.update(source_qa_review_sha256=review_hash, source_qa_review=review,
                       geometry_approved=False, candidate_only_budgeted_review=True)
    return binding


def binding_input_hashes(source, binding):
    if binding is None:
        return {}
    source = Path(source).resolve()
    hashes = {str(source): binding["source_blend_sha256"],
            str(source.with_name("source_study_inputs.json")): binding["source_study_inputs_sha256"],
            str(source.with_name("source_study_audit.json")): binding["source_study_audit_sha256"]}
    if binding.get("study_profile") == UNIFIED_PROFILE:
        hashes[str(source.with_name("source_qa_review.json"))] = binding["source_qa_review_sha256"]
        hashes.update(binding["source_qa_review"]["capture_dependencies"])
        hashes.update({str(source.with_name(name)): digest
                       for name, digest in binding["source_qa_review"]["image_outputs"].items()})
    return hashes


def validate_candidate_study(source, scene, audit, adapter_path):
    binding = read_source_study(source, scene)
    if binding is None:
        if "source_study_binding" in audit:
            _reject("candidate binding exists without source study")
        return None
    if (not _same(audit.get("source_study_binding"), binding) or BINDING_FIELD not in scene
            or not _same(parse_json(scene[BINDING_FIELD]), binding)):
        _reject("candidate scene/report source study binding mismatch")
    if audit.get("production_ready") is not False or audit.get("source_fidelity_approved") is not False:
        _reject("candidate study must remain unapproved")
    if audit.get("adapter_sha256") != sha(adapter_path):
        _reject("candidate adapter SHA changed; reconstruction forbidden")
    return binding


def require_component_masks(binding, source):
    """Study body/wings may not silently use the historical M analytic mask."""
    if binding is None or not source.name.startswith(("HeroBody", "PaddleWing")):
        return
    layer = source.data.color_attributes.get("SourceSemanticMasks")
    if (source.get("source_mask_contract") != "feather-palette-weights-v1" or layer is None
            or layer.domain != "POINT" or layer.data_type != "FLOAT_COLOR"
            or len(layer.data) != len(source.data.vertices) or not len(layer.data)):
        _reject("explicit body/wing source masks required: " + source.name)
    for item in layer.data:
        values = tuple(item.color)
        if (len(values) != 4 or any(not math.isfinite(value) or not 0 <= value <= 1 for value in values)
                or sum(values[:3]) > 1.0000001 or values[3] != 1.0):
            _reject("invalid study source mask weights: " + source.name)
