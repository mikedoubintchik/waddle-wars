"""Source-only Z14: a fuller neck and broader, lower-crowned smiling bill.

The complete continuous Z13 paint, orbital geometry, maps and stage are kept.
This is a sculpture review, not a registered export or runtime replacement.
"""
from __future__ import annotations

import ast
from contextlib import contextmanager
import math
import sys

import hero_penguin_v12_face_z09 as anatomy
import hero_penguin_v12_face_z13 as prior
import hero_penguin_v12_source_study as study

PROFILE = "fuller-throat-smile-z14"
PARENT_PROFILE = prior.PROFILE
THROAT_INWARD_M = .020
SMILE_RISE_M = .039
BILL_UPPER = (
    (-.385, .105, .071, 1.337), (-.424, .150, .089, 1.329),
    (-.465, .148, .095, 1.320), (-.507, .120, .073, 1.312),
    (-.550, .077, .041, 1.305), (-.578, .035, .016, 1.300),
    (-.589, .003, .002, 1.298),
)
BILL_LOWER = (
    (-.387, .102, .018, 1.337), (-.424, .140, .037, 1.329),
    (-.465, .132, .050, 1.320), (-.504, .103, .043, 1.312),
    (-.538, .059, .025, 1.307), (-.562, .026, .010, 1.304),
    (-.574, .002, .001, 1.302),
)
apply_material_changes = prior.apply_material_changes
install_continuous_paint = prior.install_continuous_paint


def bill_smile(y, width, cosine):
    return SMILE_RISE_M * abs(cosine) ** 2.2 * min(1., width / .080) * anatomy.smooth(-.580, -.430, y)


def bill_height(y, width, height, seam, cosine, sine, lobe=""):
    smile = bill_smile(y, width, cosine)
    if lobe == "upper":
        roof = max(0., sine)
        return seam + .0024 + height * roof ** 1.10 + smile * (1. - roof) - height * .018 * max(0., -sine)
    if lobe == "lower":
        return seam - .0024 - height * max(0., -sine) ** 1.10 + smile + height * .018 * max(0., sine)
    return seam + sine * height + smile


def nostril_center(side):
    """Register to the same authored bill section rather than a stale height.

    This is the unsubdivided section surface, not a final clearance assertion;
    the actual subdivided sculpture still needs side/three-quarter review.
    """
    y, width, height, seam = BILL_UPPER[2]
    x = side * .039
    cosine = x / width
    sine = math.sqrt(1. - cosine * cosine)
    return x, y, bill_height(y, width, height, seam, cosine, sine, "upper") - .0005


def fresh_design():
    selected, parent_record = prior.fresh_design()
    baseline, _ = study.fresh_design(anatomy.PARENT_PROFILE)
    # Z09's 20 mm waist, not Z10's additional 45 mm inward neck warp.
    # This replacement is complete before the immutable eye-frame cache runs.
    selected.base_body_field = lambda points: baseline.base_body_field(anatomy.warp_points(points))
    selected.BILL_UPPER_SECTIONS, selected.BILL_LOWER_SECTIONS = BILL_UPPER, BILL_LOWER
    selected.bill_section_height, selected.bill_smile_offset = bill_height, bill_smile
    if selected.eye_surface_frame.cache_info().currsize:
        raise RuntimeError("Z14 requires unevaluated eye anchors before shape replacement")
    return selected, {"parent_design_record": parent_record,
                      "z14_total_throat_inward_m": THROAT_INWARD_M,
                      "z14_smile_rise_m": SMILE_RISE_M,
                      "z14_neck_field": "juvenile-socket-z06 base with original Z09 20mm throat/cheek warp",
                      "selected_design_constants": study.constants(selected)}


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
    tree, parent_record = prior.renderer_syntax(path)
    bill = study.function_node(tree, "add_bill")
    nostril = study.assignment(bill, "nostril").value.args[1]
    if ast.dump(nostril) != ast.dump(ast.parse("(side * .040, -.465, 1.422)", mode="eval").body):
        raise ValueError("Z14 parent nostril registration changed")
    study.assignment(bill, "nostril").value.args[1] = ast.parse("_z14_nostril_center(side)", mode="eval").body
    tree.body.insert(tree.body.index(bill), ast.parse(
        "from hero_penguin_v12_face_z14 import nostril_center as _z14_nostril_center").body[0])
    ast.fix_missing_locations(tree)
    return tree, {"parent_renderer_record": parent_record,
                  "z14_renderer_change": "nostrils registered to lower bill crown; all other renderer functions unchanged",
                  "selected_renderer_ast_sha256": study.ast_digest(tree)}


def source_only_declarations():
    return {"schema_version": 1, "study_profile": PROFILE, "parent_profile": PARENT_PROFILE,
            "source_only": True, "production_ready": False, "source_fidelity_approved": False,
            "geometry_approved": False, "candidate_export_allowed": False, "runtime_rig_or_glb_created": False,
            "export_policy": "Unregistered sculpture study; reject candidate/atlas export.",
            "scope": "Fuller bounded throat, broader lower-crowned bill, raised corners; Z13 continuous paint retained.",
            "approval_policy": "Three-view image review required; construction tests do not grant fidelity approval."}
