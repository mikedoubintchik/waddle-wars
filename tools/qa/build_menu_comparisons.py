"""Reference/capture contact sheets only; never modifies game artwork."""
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageOps

root = Path(__file__).resolve().parents[2]
captures, output = map(Path, sys.argv[1:3])
output.mkdir(parents=True, exist_ok=True)
references = {
    "main_menu": "waddle_wars_menu_rethink_portrait_v1.png",
    "base_camp": "base_camp_v1.png", "missions": "missions_v1.png",
    "customize": "penguins_v1.png", "account": "account_v1.png",
    "cosmetic_shop": "shop_v1.png", "settings": "settings_v1.png",
    "achievements": "achievements_v1.png", "leaderboard": "leaderboard_v1.png",
    "credits": "credits_v1.png", "controls": "controls_v1.png",
}
panels = []
for name, reference in references.items():
    capture = captures / f"menu-{name}-360x640.png"
    if not capture.exists():
        print(f"MISSING {name}: {capture}")
        continue
    panel = Image.new("RGB", (600, 580), "#14263c")
    draw = ImageDraw.Draw(panel)
    draw.text((12, 8), f"{name} — REFERENCE / ACTUAL", fill="white")
    for x, path in [(8, root / "art_src/ui/menu" / reference), (304, capture)]:
        thumbnail = ImageOps.contain(Image.open(path).convert("RGB"), (288, 550))
        panel.paste(thumbnail, (x + (288-thumbnail.width)//2, 26))
    panel.save(output / f"{name}-comparison.png")
    panels.append(panel)
for offset in range(0, len(panels), 4):
    sheet = Image.new("RGB", (1200, 1160), "#14263c")
    for i, panel in enumerate(panels[offset:offset+4]):
        sheet.paste(panel, ((i%2)*600, (i//2)*580))
    sheet.save(output / f"comparison-sheet-{offset//4+1}.png")
print(f"Compared {len(panels)}/{len(references)} pages; {output}")
