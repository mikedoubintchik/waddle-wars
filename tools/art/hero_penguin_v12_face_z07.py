"""Isolated Z07 face proposal; Z06 source and downstream bindings stay frozen.

This module deliberately does not register a profile with the production study
or provenance reader. Its saved scene is source-only and ineligible for the
candidate/atlas path until a separate review explicitly adds that support.
"""
from __future__ import annotations

import ast
from contextlib import contextmanager
import sys

import hero_penguin_v12_source_study as study

PROFILE = "juvenile-face-z07"
PARENT_PROFILE = "juvenile-socket-z06"
# The eye frame, globe, burial, socket and all non-face constants stay Z06.
CONSTANT_CHANGES = (
    ("LIMBAL_RADII", (0.080, 0.102), (0.069, 0.089)),
    ("IRIS_RADII", (0.073, 0.093), (0.066, 0.085)),
    ("PUPIL_RADII", (0.044, 0.059), (0.041, 0.055)),
)
# row, column, previous value, proposed value; columns are y/width/height/seam.
BILL_CHANGES = ((1, 1, .147, .133), (1, 2, .119, .100),
                (2, 2, .109, .125), (3, 2, .078, .092))
CATCHLIGHT_RADII = ((.008, .011), (.0055, .0075))
MATERIAL_CHANGES = {"iris": {"roughness": (.32, .40), "specular_ior_level": .25},
                    "pupil": {"roughness": (.28, .18), "specular_ior_level": .25}}


def fresh_design():
    selected, parent_record = study.fresh_design(PARENT_PROFILE)
    before = study.constants(selected)
    changes = []
    for name, old, new in CONSTANT_CHANGES:
        if getattr(selected, name) != old:
            raise ValueError(f"Z07 parent constant changed: {name}")
        setattr(selected, name, new)
        changes.append({"anchor": name, "baseline": old, "selected": new})
    sections = [list(section) for section in selected.BILL_UPPER_SECTIONS]
    for row, column, old, new in BILL_CHANGES:
        if sections[row][column] != old:
            raise ValueError(f"Z07 parent bill section changed: {row}/{column}")
        sections[row][column] = new
        changes.append({"anchor": f"BILL_UPPER_SECTIONS[{row}][{column}]",
                        "baseline": old, "selected": new})
    selected.BILL_UPPER_SECTIONS = tuple(tuple(section) for section in sections)
    after = study.constants(selected)
    permitted = {item[0] for item in CONSTANT_CHANGES} | {"BILL_UPPER_SECTIONS"}
    if {key for key in after if after[key] != before[key]} != permitted:
        raise RuntimeError("Z07 changed a constant outside the explicit face proposal")
    if selected.eye_surface_frame.cache_info().currsize:
        raise RuntimeError("Z07 requires an unevaluated Z06 eye frame")
    return selected, {"parent_design_record": parent_record,
                      "z07_constant_changes": changes,
                      "selected_design_constants": after}


@contextmanager
def installed_design():
    selected, record = fresh_design()
    previous = sys.modules.get(study.DESIGN_MODULE)
    sys.modules[study.DESIGN_MODULE] = selected
    try:
        yield selected, record
    finally:
        if previous is None:
            sys.modules.pop(study.DESIGN_MODULE, None)
        else:
            sys.modules[study.DESIGN_MODULE] = previous


def renderer_syntax(path):
    # Rebuild the complete Z06 renderer from its original, unedited AST first.
    tree, parent_record = study.renderer_syntax(PARENT_PROFILE, path)
    eye_set = study.function_node(tree, "add_eye_set")
    matches = [node for node in ast.walk(eye_set)
               if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
               and node.func.id == "eye_paint_disc" and node.args
               and isinstance(node.args[0], ast.JoinedStr)
               and isinstance(node.args[0].values[0], ast.Constant)
               and node.args[0].values[0].value == "Catchlight"]
    if len(matches) != 1 or len(matches[0].args) != 6:
        raise ValueError("Z07 requires exactly one original catchlight call")
    radius = matches[0].args[3]
    if not isinstance(radius, ast.Tuple) or len(radius.elts) != 2:
        raise ValueError("Z07 catchlight radius tuple changed")
    plans = [study.literal_plan(node, old, new, f"add_eye_set.catchlight.radii[{index}]")
             for index, (node, old, new) in enumerate(zip(
                 radius.elts, *CATCHLIGHT_RADII))]
    for node, new, _record in plans:
        node.value = new
    ast.fix_missing_locations(tree)
    return tree, {"parent_renderer_record": parent_record,
                  "z07_renderer_literal_changes": [item[2] for item in plans],
                  "selected_renderer_ast_sha256": study.ast_digest(tree)}


def apply_material_changes(materials):
    """Explicit post-create callback; no lights, textures or other materials."""
    targets = []
    # Validate every anchor before mutating any material.
    for name, change in MATERIAL_CHANGES.items():
        principled = materials[name].node_tree.nodes.get("Principled BSDF")
        if principled is None:
            raise ValueError(f"Z07 missing eye Principled material: {name}")
        roughness = principled.inputs["Roughness"]
        specular = principled.inputs["Specular IOR Level"]
        if roughness.is_linked or specular.is_linked:
            raise ValueError(f"Z07 requires unlinked eye material controls: {name}")
        if abs(roughness.default_value - change["roughness"][0]) > 1e-6:
            raise ValueError(f"Z07 parent eye roughness changed: {name}")
        targets.append((name, change, roughness, specular))
    receipt = []
    for name, change, roughness, specular in targets:
        receipt.append({"material": name,
                        "roughness": {"baseline": float(roughness.default_value),
                                      "selected": change["roughness"][1]},
                        "specular_ior_level": {"baseline": float(specular.default_value),
                                               "selected": change["specular_ior_level"]}})
        roughness.default_value = change["roughness"][1]
        specular.default_value = change["specular_ior_level"]
    return receipt


def source_only_declarations():
    return {"schema_version": 1, "study_profile": PROFILE, "parent_profile": PARENT_PROFILE,
            "source_only": True, "production_ready": False,
            "source_fidelity_approved": False, "geometry_approved": False,
            "candidate_export_allowed": False, "runtime_rig_or_glb_created": False,
            "export_policy": "Unregistered source-only face proposal; reject candidate/atlas export.",
            "scope": "Iris/limbal/pupil dimensions, small catchlight, eye materials, four upper-bill literals only.",
            "bill_ridge_added": False, "body_socket_cheeks_masks_cameras_lights_textures_changed": False,
            "material_callback_recipe": MATERIAL_CHANGES}
