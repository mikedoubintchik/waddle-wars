#!/usr/bin/env python3
"""Compare a projected candidate with traced reference pixels. No engine capture."""
import argparse
import importlib.util
import json
from pathlib import Path
import numpy as np
from PIL import Image

spec = importlib.util.spec_from_file_location("projection", Path(__file__).with_name("penguin_silhouette_projection.py"))
projection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(projection)


def read_mask(path):
    return np.asarray(Image.open(path).convert("L")) > 127


def extent(mask):
    y, x = np.where(mask)
    return {"area": int(mask.sum()), "bbox": [int(x.min()), int(y.min()), int(x.max()), int(y.max())]} if len(x) else {"area": 0, "bbox": None}


def metrics(actual, target):
    measured = projection.calibration(actual, target)
    return {key: measured[key] for key in ("intersection_over_union", "symmetric_boundary_mean_px",
            "symmetric_boundary_p95_px", "symmetric_boundary_max_px")}


def compare(reference_dir, candidate_dir):
    ref = read_mask(reference_dir / "reference-silhouette-mask.png")
    ref_feet = read_mask(reference_dir / "reference-feet-mask.png")
    candidate = read_mask(candidate_dir / "silhouette-aligned.png")
    labels = np.asarray(Image.open(candidate_dir / "visible-labels-aligned.png"))
    ids = json.loads((candidate_dir / "projection.json").read_text())["visible_label_ids"]
    feet = np.isin(labels, [ids["foot_L"], ids["foot_R"]])
    body = np.isin(labels, [ids["continuous_body_head"], ids["short_tail_fan"]])
    report = {"scope": "Numerical silhouette diagnostic, not visual or human approval",
              "full": metrics(candidate, ref),
              "feet": metrics(feet, ref_feet),
              "reference_feet": extent(ref_feet), "candidate_feet": extent(feet), "per_foot": {}, "rows": []}
    for side, label in (("left", "foot_L"), ("right", "foot_R")):
        target = read_mask(reference_dir / ("reference-" + side + "-foot-mask.png"))
        actual = labels == ids[label]
        report["per_foot"][side] = {"reference": extent(target), "candidate": extent(actual),
                                   "metrics": metrics(actual, target)}
    for y in [80, 100, 120, 140, 160, 180, 200, 220, 240, 260, 280, 300, 310, 320, 330, 340, 350, 360]:
        row = {"y": y}
        for name, mask in (("reference", ref), ("candidate", candidate), ("candidate_body", body)):
            x = np.where(mask[y])[0]
            row[name] = [int(x.min()), int(x.max())] if len(x) else None
        report["rows"].append(row)
    (candidate_dir / "reference-fit.json").write_text(json.dumps(report, indent=2) + "\n")
    rgba = np.full((443, 443, 3), [235, 242, 245], dtype=np.uint8)
    rgba[ref & candidate] = [153, 183, 179]
    rgba[ref & ~candidate] = [0, 210, 235]
    rgba[candidate & ~ref] = [255, 30, 130]
    Image.fromarray(rgba).save(candidate_dir / "reference-difference.png")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    args = parser.parse_args()
    result = compare(args.reference, args.candidate)
    print(json.dumps({"full_iou": result["full"]["intersection_over_union"],
                     "feet_iou": result["feet"]["intersection_over_union"],
                     "full_edge_mean_px": result["full"]["symmetric_boundary_mean_px"],
                     "feet_edge_mean_px": result["feet"]["symmetric_boundary_mean_px"],
                     "feet_area": result["candidate_feet"], "per_foot": result["per_foot"]}))
