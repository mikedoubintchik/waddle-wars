#!/usr/bin/env python3
"""Plan, preserve and package complete ImageGen outfits. No model/API calls.

The agent calls the built-in image tool once per complete outfit. This tool
records that output and performs ordinary runtime WebP encoding only.
"""
from pathlib import Path
import argparse
import fcntl
import hashlib
import itertools
import json
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_src/ui/wardrobe_outfits_v1"
RUNTIME = ROOT / "assets/art/ui/wardrobe_outfits_v1"
JOBS = SOURCE / "jobs.json"
CATALOG = ROOT / "data/wardrobe/outfits_v1.json"
BODIES = {
    "body_classic": ("emperor", "Emperor", "round cheerful face, navy-black feather cap, ivory cheeks, blue eyes and orange smiling beak"),
    "body_adelie": ("adelie", "Adelie", "compact dark tuxedo, narrow white eye rings, small orange-and-dark bill"),
    "body_gentoo": ("gentoo", "Gentoo", "broad white headband above both eyes and long orange bill"),
    "body_chinstrap": ("chinstrap", "Chinstrap", "white face and unmistakable thin black curved chin strap"),
    "body_snowy": ("little_blue", "Little Blue", "smallest round body, slate-blue plumage, soft white face, short beak"),
    "body_midnight": ("king", "King", "taller upright body, dark face, vivid orange cheek patches and golden throat, long narrow bill"),
    "body_rockhopper": ("rockhopper", "Rockhopper", "compact body, dark face, bold wild outward golden eyebrow crests, cheeky expression"),
    "body_macaroni": ("macaroni", "Macaroni", "dark face and long drooping golden crest that falls down either side of forehead"),
}
HATS = {
    "none": "NO headwear; natural feather crown or species crest fully visible",
    "hat_beanie": "one snug coral-red knitted beanie with ribbed cuff and fluffy red pompom",
    "hat_earwarmers": "one pair of sky-blue padded ear warmers with a slim matching band over the head",
    "hat_headset": "one amber-orange research communications headset, dark padded ear cups and a small microphone beside the beak",
    "hat_crown": "one polished warm-gold crown with simple rounded points, fitted around the top of the head",
}
EYEWEAR = {
    "none": "NO eyewear; original eyes and eye markings fully unobstructed",
    "goggles_ski": "cyan ski goggles properly worn over both eyes, pale rim, clear icy-blue reflective lenses and fitted strap behind head",
    "goggles_aviator": "gold-framed aviator sunglasses worn correctly over both eyes, smoky blue lenses and fitted thin temples",
}
NECKWEAR = {
    "none": "NO neckwear; natural throat and chest plumage fully visible",
    "scarf_red": "one richly textured coral-red knitted scarf wrapping naturally around neck, two soft fringed ends resting over chest",
    "scarf_rainbow": "one knitted rainbow-striped scarf around neck, clearly visible red orange yellow green blue violet stripes and short fringed ends",
    "scarf_bowtie": "one neatly tied cobalt-blue fabric bow tie, centered at neck, small natural knot and two balanced loops",
}


def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def job_prompt(body, hat, eyes, neck):
    species, name, features = BODIES[body]
    equipped = [description for identifier, description in [(hat, HATS[hat]), (eyes, EYEWEAR[eyes]), (neck, NECKWEAR[neck])] if identifier != "none"]
    items = "; ".join(equipped) if equipped else "nothing: keep the natural penguin completely unadorned"
    return f"""Use case: identity-preserve. Edit target: attached {name} penguin. Keep this exact species, face, body, feather markings, pose and lighting.
Add ONLY these accessories: {items}.
Head requirement: {HATS[hat]}. Eye requirement: {EYEWEAR[eyes]}. Neck requirement: {NECKWEAR[neck]}.
Render accessories naturally fitted on this complete character, with fabric folds and contact shadows. Leave its belly, flippers and feet as natural feathers and skin. NO shirt, sweater, jacket, vest, pants, shoes or additional accessories.
One full-body penguin, premium animated-film illustration, same friendly three-quarter pose as reference. Keep entire silhouette inside portrait 2:3 canvas with generous clear margins. Genuine transparent background. No scenery, ground, text or watermark."""


def initialize():
    if JOBS.exists():
        return
    entries = []
    for body, hat, eyes, neck in itertools.product(BODIES, HATS, EYEWEAR, NECKWEAR):
        key = "__".join([body, hat, eyes, neck])
        entries.append({"key": key, "body": body, "hat": hat, "goggles": eyes,
                        "scarf": neck, "reference": str(ROOT / f"assets/art/ui/menu/{BODIES[body][0]}_fullbody_v1.webp"),
                        "prompt": job_prompt(body, hat, eyes, neck), "status": "queued"})
    assert len(entries) == 480 and len({x["key"] for x in entries}) == 480
    save_json(JOBS, {"version": 1, "expected": 480, "jobs": entries})


def ingest(key, generated_path, reuse=False):
    lock = ROOT / "qa_shots/tests/wardrobe-library-v1/ingest.lock"
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open("a") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        return ingest_locked(key, generated_path, reuse)


def ingest_locked(key, generated_path, reuse=False):
    plan = json.loads(JOBS.read_text())
    job = next(x for x in plan["jobs"] if x["key"] == key)
    original = Path(generated_path).resolve()
    if not original.is_file() or original.suffix.lower() != ".png":
        raise ValueError("ImageGen output must be an existing PNG")
    source = SOURCE / (key + ".png")
    if source.exists() and sha(source) != sha(original):
        raise ValueError("Existing outfit differs; preserve it and use explicit repair workflow")
    staging_source = source.with_suffix(".pending")
    shutil.copy2(original, staging_source)
    staging_source.replace(source)
    (SOURCE / (key + ".prompt.md")).write_text(
        ("# Complete wardrobe outfit\n\nExisting project ImageGen artwork reused unchanged. Below is catalog specification, not a new generation prompt.\n" if reuse else "# Complete wardrobe outfit\n\nBuilt-in ImageGen, 2026-10-07; model/build identifier not exposed.\n")
        + f"Identity reference: `{job['reference']}`. Original: `{original}`.\n\n" + job["prompt"] + "\n")
    width, height = struct.unpack(">II", source.read_bytes()[16:24])
    runtime = RUNTIME / (key + ".webp")
    # Runtime encoding only. Preserve the untouched generated original above.
    staging_runtime = runtime.with_suffix(".encoding")
    subprocess.run(["/opt/homebrew/bin/cwebp", "-quiet", "-q", "88", "-m", "6",
                    "-resize", "512", "0", str(source), "-o", str(staging_runtime)], check=True)
    staging_runtime.replace(runtime)
    job.update(status="generated", reused_existing=reuse, source=str(source.relative_to(ROOT)),
               runtime="res://" + str(runtime.relative_to(ROOT)),
               source_sha256=sha(source), runtime_sha256=sha(runtime),
               dimensions=[width, height], original=str(original),
               runtime_bytes=runtime.stat().st_size)
    save_json(JOBS, plan)
    rebuild_catalog(plan)
    return {"key": key, "status": "generated", "runtime_bytes": runtime.stat().st_size}


def rebuild_catalog(plan):
    catalog = {"version": 1, "expected": 480, "entries": {}}
    for entry in plan["jobs"]:
        if entry["status"] == "reviewed":
            catalog["entries"][entry["key"]] = {k: entry[k] for k in (
                "body", "hat", "goggles", "scarf", "runtime", "runtime_sha256")}
    save_json(CATALOG, catalog)


def review(key, approved, note):
    lock = ROOT / "qa_shots/tests/wardrobe-library-v1/ingest.lock"
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open("a") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        plan = json.loads(JOBS.read_text())
        job = next(x for x in plan["jobs"] if x["key"] == key)
        if job["status"] not in ("generated", "reviewed"):
            raise ValueError("Review requires a generated output")
        if approved:
            job.update(status="reviewed", review=note)
        else:
            archive = SOURCE / "rejected" / key / str(len(job.get("rejected", [])) + 1)
            archive.mkdir(parents=True, exist_ok=True)
            for file in (SOURCE / (key + ".png"), SOURCE / (key + ".prompt.md")):
                if file.exists():
                    shutil.move(file, archive / file.name)
            runtime = ROOT / job["runtime"].removeprefix("res://")
            if runtime.exists():
                shutil.move(runtime, archive / runtime.name)
            job.setdefault("rejected", []).append({"reason": note, "archive": str(archive.relative_to(ROOT)), "sha256": job["source_sha256"]})
            for field in ("source", "runtime", "source_sha256", "runtime_sha256", "dimensions", "original", "runtime_bytes", "review", "reused_existing"):
                job.pop(field, None)
            job["status"] = "queued"
            job["prompt"] = job_prompt(job["body"], job["hat"], job["goggles"], job["scarf"])
        save_json(JOBS, plan)
        rebuild_catalog(plan)
        return {"key": key, "status": job["status"]}


def register_art(plan):
    fragment = {"concepts": [], "generated_assets": [], "runtime_assets": [], "source_exports": []}
    for job in plan["jobs"]:
        identifier = "wardrobe_v1_" + job["key"]
        common = {"generated_on": "2026-10-07", "generator": "Codex built-in ImageGen (model/build identifier not exposed)", "license_id": "project_original"}
        if job["status"] in ("generated", "reviewed"):
            fragment["generated_assets"].append(dict(common, id="imagegen_" + identifier,
                path=job["source"], prompt_path=job["source"].replace(".png", ".prompt.md"),
                dimensions=job["dimensions"], sha256=job["source_sha256"], status="production_source"))
            fragment["runtime_assets"].append({"id": identifier, "kind": "texture",
                "path": job["runtime"], "sha256": job["runtime_sha256"],
                "license_id": "project_original", "source_export_id": "imagegen_" + identifier,
                "groups": ["frontend", "menu", "wardrobe"], "production_ready": job["status"] == "reviewed"})
        for index, rejected in enumerate(job.get("rejected", [])):
            source = ROOT / rejected["archive"] / (job["key"] + ".png")
            width, height = struct.unpack(">II", source.read_bytes()[16:24])
            fragment["concepts"].append(dict(common, id="rejected_" + identifier + "_" + str(index + 1),
                path=str(source.relative_to(ROOT)), prompt_path=str(source.with_suffix(".prompt.md").relative_to(ROOT)),
                dimensions=[width, height], sha256=rejected["sha256"], status="art_direction_only"))
    for entries in fragment.values():
        entries.sort(key=lambda entry: entry["id"])
    save_json(ROOT / "data/art/fragments/wardrobe_outfits_v1.json", fragment)
    return {key: len(value) for key, value in fragment.items()}


def audit(plan, allow_partial=False):
    errors = []
    expected = {"__".join(parts) for parts in itertools.product(BODIES, HATS, EYEWEAR, NECKWEAR)}
    if {job["key"] for job in plan["jobs"]} != expected or len(plan["jobs"]) != 480:
        errors.append("Job matrix must contain exactly480 unique catalog combinations")
    catalog = json.loads(CATALOG.read_text())
    reviewed = {job["key"] for job in plan["jobs"] if job["status"] == "reviewed"}
    if set(catalog["entries"]) != reviewed:
        errors.append("Runtime catalog differs from reviewed set")
    if not allow_partial and reviewed != expected:
        errors.append(f"Only{len(reviewed)}/480 reviewed entries")
    for job in plan["jobs"]:
        if job["status"] not in ("generated", "reviewed"):
            continue
        for role in ("source", "runtime"):
            path = ROOT / job[role].removeprefix("res://")
            if not path.is_file() or sha(path) != job[role + "_sha256"]:
                errors.append(f"{job['key']}: missing/stale {role}")
        data = (ROOT / job["source"]).read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n" or data[25] != 6:
            errors.append(f"{job['key']}: source must preserve RGBA PNG")
        if job["status"] == "reviewed" and not job.get("review"):
            errors.append(f"{job['key']}: missing visual review")
        if not (ROOT / job["source"]).with_suffix(".prompt.md").is_file():
            errors.append(f"{job['key']}: missing prompt provenance")
    return {"expected": 480, "reviewed": len(reviewed), "complete": reviewed == expected,
            "runtime_bytes": sum(job.get("runtime_bytes", 0) for job in plan["jobs"]),
            "errors": errors}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["init", "next", "ingest", "status", "approve", "reject", "refresh-prompts", "register", "audit"])
    parser.add_argument("--count", type=int, default=4)
    parser.add_argument("--body")
    parser.add_argument("--key")
    parser.add_argument("--source")
    parser.add_argument("--baselines", action="store_true")
    parser.add_argument("--reuse", action="store_true")
    parser.add_argument("--allow-partial", action="store_true")
    parser.add_argument("--note", default="")
    args = parser.parse_args()
    initialize()
    if args.action == "ingest":
        print(json.dumps(ingest(args.key, args.source, args.reuse)))
        return
    if args.action in ("approve", "reject"):
        if not args.note:
            parser.error("Review requires --note")
        print(json.dumps(review(args.key, args.action == "approve", args.note)))
        return
    plan = json.loads(JOBS.read_text())
    jobs = plan["jobs"]
    if args.action == "refresh-prompts":
        for job in jobs:
            if job["status"] == "queued":
                job["prompt"] = job_prompt(job["body"], job["hat"], job["goggles"], job["scarf"])
        save_json(JOBS, plan)
        rebuild_catalog(plan)
    if args.action == "register":
        print(json.dumps(register_art(plan)))
        return
    if args.action == "audit":
        result = audit(plan, args.allow_partial)
        print(json.dumps(result))
        raise SystemExit(bool(result["errors"]))
    if args.action == "next":
        matches = [x for x in jobs if x["status"] == "queued"
                   and (not args.body or x["body"] == args.body)
                   and (not args.baselines or x["hat"] == x["goggles"] == x["scarf"] == "none")]
        print(json.dumps(matches[:args.count]))
    else:
        print(json.dumps({"expected": len(jobs), "counts": {state: sum(x["status"] == state for x in jobs) for state in ("queued", "generated", "reviewed")},
                          "runtime_bytes": sum(x.get("runtime_bytes", 0) for x in jobs)}))


if __name__ == "__main__":
    main()
