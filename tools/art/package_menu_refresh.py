"""Encode accepted Imagegen outputs and inventory their Drive backup.

No image editing: format conversion only. Source PNGs remain untouched.
"""
from pathlib import Path
import csv
import hashlib
import json
import zipfile
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_src/ui/menu"
RUNTIME = ROOT / "assets/art/ui/menu"
NEW_ASSETS = ["base_camp_desktop_background_v2", "leaderboard_desktop_background_v2",
              "runner_results_desktop_background_v2", "runner_complete_wordmark_v2"]

for stem in NEW_ASSETS:
    image = Image.open(SOURCE / f"{stem}.png")
    # Atomic publish prevents an isolated QA snapshot copying a half-written
    # image while conversion runs. Existing source/runtime variants survive.
    temporary = RUNTIME / f"{stem}.encoding"
    image.save(temporary, format="WEBP", quality=92, method=6)
    temporary.replace(RUNTIME / f"{stem}.webp")
    print(f"Encoded {stem}: {image.size}, alpha={'A' in image.getbands()}")

references = ["waddle_wars_menu_rethink_portrait_v1", "base_camp_v1", "missions_v1",
              "account_v1", "penguins_v1", "leaderboard_v1", "achievements_v1",
              "shop_v1", "settings_v1", "controls_v1", "credits_v1",
              "runner_pause_v1", "runner_results_v1", "race_mode_select_v1",
              "race_pause_v1", "race_results_v1", "penguins_desktop_v1",
              "base_camp_desktop_v2", "leaderboard_desktop_v2",
              "runner_results_desktop_v2", "loader_theme_v2"]
runtime_files = sorted(p for p in (ROOT / "assets/art/ui").rglob("*")
                       if p.suffix.lower() in {".png", ".webp"})
source_stems = {p.stem for p in runtime_files}
source_files = sorted(p for p in (ROOT / "art_src/ui").rglob("*")
                      if p.suffix.lower() in {".png", ".webp"}
                      and (p.stem in source_stems or p.stem in references))
launch_files = [ROOT / path for path in [
    "art_src/ui/icon/waddle_wars_app_icon_v4_source.png",
    "art_src/ui/feature/waddle_wars_feature_v2_source.png",
    "art_src/ui/title/waddle_wars_wordmark_v4_source.png",
    "assets/art/runner/avalanche_front_v1.png",
    "art_src/runner/avalanche_front_v1.prompt.md",
    "art_src/runner/LICENSES.md", "assets/art/LICENSES.md"]]
selected = sorted(set(runtime_files + source_files + [p for p in launch_files if p.exists()]))
receipts = ROOT / "art_src/ui/drive_archive_20261007"
receipts.mkdir(exist_ok=True)
index = receipts / "ASSET_INDEX.csv"
with index.open("w", newline="") as stream:
    writer = csv.writer(stream)
    writer.writerow(["path", "role", "bytes", "sha256"])
    for path in selected:
        role = "runtime-catalog" if "assets/art" in str(path) else "editable-source"
        if path.stem in references:
            role = "design-reference"
        writer.writerow([str(path.relative_to(ROOT)), role, path.stat().st_size,
                         hashlib.sha256(path.read_bytes()).hexdigest()])
archive = receipts / "Waddle-Wars-Imagegen-Assets-20261007.zip"
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=4) as bundle:
    for path in selected:
        bundle.write(path, path.relative_to(ROOT))
    bundle.write(index, "ASSET_INDEX.csv")
    for path in SOURCE.glob("*.prompt.md"):
        bundle.write(path, path.relative_to(ROOT))
# Drive connector's upload limit is 100 MiB. Complete independent ZIPs, not
# binary split fragments: every part opens normally and includes the index.
groups = [[]]
weight = 0
for path in selected:
    size = path.stat().st_size
    if groups[-1] and weight + size > 64 * 1024 * 1024:
        groups.append([])
        weight = 0
    groups[-1].append(path)
    weight += size
parts = []
for number, group in enumerate(groups, 1):
    part = receipts / f"Waddle-Wars-Imagegen-Assets-20261007-part{number:02d}.zip"
    with zipfile.ZipFile(part, "w", zipfile.ZIP_DEFLATED, compresslevel=4) as bundle:
        for path in group:
            bundle.write(path, path.relative_to(ROOT))
        bundle.write(index, "ASSET_INDEX.csv")
    parts.append(str(part))
print(json.dumps({"files":len(selected), "references":len(references),
                  "zip":str(archive), "bytes":archive.stat().st_size, "parts":parts}))
