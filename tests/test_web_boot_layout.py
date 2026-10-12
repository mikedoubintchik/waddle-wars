#!/usr/bin/env python3
"""Check extracted boot CSS against painted-asset bounds; no browser/engine.

This is a flex-box geometry contract, not a screenshot or browser font test.
Real Chrome remains the final visual gate. Override WW_BOOT_PRESET to exercise
an archived export preset as a negative control.
"""
import ast
import math
import os
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
PRESET = Path(os.environ.get("WW_BOOT_PRESET", ROOT / "export_presets.cfg"))
SOURCE = PRESET.read_text()
STYLE = next(x for x in re.findall(r"<style>(.*?)</style>", SOURCE, re.S)
             if "#ww-boot-card" in x)
STYLE = re.sub(r"/\*.*?\*/", "", STYLE, flags=re.S)
# Measured source pixels: courier 768x512, alpha bounds (60,8)-(677,492).
# Card's central ivory begins below ~12% and ends above its lower ~11% rim.
COURIER_ASPECT = 768 / 512
PROFILES = [(320, 568), (360, 640), (375, 667), (390, 844), (480, 854),
            (568, 320), (667, 375), (844, 390), (1280, 720), (1920, 1080)]


def rules(text, width, height):
    """Read actual qualified rules, including the short-landscape cascade."""
    result = {}
    pos = 0
    while pos < len(text):
        opening = text.find("{", pos)
        if opening < 0:
            break
        selector = text[pos:opening].strip()
        end, depth = opening + 1, 1
        while depth:
            depth += (text[end] == "{") - (text[end] == "}")
            end += 1
        body = text[opening + 1:end - 1]
        if selector.startswith("@media"):
            max_height = re.search(r"max-height:\s*(\d+)px", selector)
            aspect = re.search(r"min-aspect-ratio:\s*(\d+)\s*/\s*(\d+)", selector)
            active = bool(max_height and aspect and height <= int(max_height[1])
                          and width / height >= int(aspect[1]) / int(aspect[2]))
            if active:
                for key, values in rules(body, width, height).items():
                    result.setdefault(key, {}).update(values)
        elif selector.startswith("#"):
            values = dict(part.strip().split(":", 1) for part in body.split(";")
                          if ":" in part)
            result.setdefault(selector, {}).update({k: v.strip() for k, v in values.items()})
        pos = end
    return result


def length(value, width, height, percent=0, font=16, safe_bottom=0):
    value = re.sub(r"env\(safe-area-inset-bottom\)", str(safe_bottom), value)
    units = {"px": 1, "vw": width / 100, "vh": height / 100,
             "%": percent / 100, "em": font}
    value = re.sub(r"([\d.]+)(px|vw|vh|em|%)",
                   lambda m: str(float(m[1]) * units[m[2]]), value)
    tree = ast.parse(value, mode="eval")
    allowed = (ast.Expression, ast.Call, ast.Name, ast.Load, ast.Constant,
               ast.BinOp, ast.UnaryOp, ast.Add, ast.Sub, ast.Mult, ast.Div, ast.USub)
    assert all(isinstance(node, allowed) for node in ast.walk(tree)), value
    return eval(compile(tree, "<css-length>", "eval"), {"__builtins__": {}},
                {"min": min, "max": max, "clamp": lambda lo, x, hi: max(lo, min(x, hi)),
                 "calc": lambda x: x})


def box_values(value):
    words, word, depth = [], "", 0
    for char in value + " ":
        depth += (char == "(") - (char == ")")
        if char.isspace() and depth == 0:
            if word:
                words.append(word)
                word = ""
        else:
            word += char
    if len(words) == 1:
        return words * 4
    if len(words) == 2:
        return words * 2
    if len(words) == 3:
        return words + [words[1]]
    return words


def geometry(width, height, retry=False, safe_bottom=0):
    css = rules(STYLE, width, height)
    layer, card, mascot, title, message, track, button = (
        css[k] for k in ["#ww-boot-layer", "#ww-boot-card", "#ww-boot-mascot",
                        "#ww-boot-title", "#ww-boot-message", "#ww-progress-track", "#ww-boot-retry"])
    px = lambda value, percent=0, font=16: length(value, width, height, percent, font, safe_bottom)
    card_w = px(card["width"])
    top, right, bottom, left = [px(x, width) for x in box_values(card["padding"])]
    content_w = card_w - left - right
    if mascot["height"] != "auto":
        mascot_h = px(mascot["height"])
        mascot_w = min(mascot_h * COURIER_ASPECT, px(mascot.get("max-width", "100%"), content_w))
        mascot_h = mascot_w / COURIER_ASPECT
    else:
        mascot_w = px(mascot["width"], content_w)
        mascot_h = mascot_w / COURIER_ASPECT
    font = px(message["font-size"])
    line_h = font * float(message.get("line-height", "1.4"))
    message_h = max(line_h * (2 if retry else 1), px(message.get("min-height", "0"), font=font))
    gap = px(card["gap"])
    mascot_margin = px(mascot.get("margin-top", "0"))
    button_after = px(button.get("margin-bottom", "0")) if retry else 0
    button_h = 44 + px(button.get("margin-top", "0")) + button_after if retry else 0
    card_h = top + mascot_margin + mascot_h + px(track["height"]) + message_h + gap * (3 if retry else 2) + button_h + bottom
    title_w = px(title["width"], card_w)
    title_h = px(title["height"]) if "height" in title else title_w / px(title["aspect-ratio"])
    title_top = px(title.get("top", "0"))
    translate = re.search(r"translateY\(([^)]+)\)", title.get("transform", ""))
    if translate:
        title_top += px(translate[1], title_h)
    layer_pad = [px(x, width) for x in box_values(layer.get("padding", "0"))]
    free_height = height - layer_pad[0] - layer_pad[2] - card_h
    if layer.get("justify-content") == "center":
        card_top = layer_pad[0] + free_height / 2
    else:
        card_top = layer_pad[0] + max(0, free_height / 2)
    # Movement envelope includes full -5px bob plus the 1-degree rotation.
    mascot_ink_top = top + mascot_margin + mascot_h * 8 / 512 - 5 - math.sin(math.radians(1)) * mascot_w / 2
    return {"css": css, "card_w": card_w, "card_h": card_h,
            "title_top": title_top, "title_bottom": title_top + title_h,
            "visible_title_top": card_top + title_top,
            "mascot_ink_top": mascot_ink_top, "bottom_clearance": bottom + button_after - card_h * .11,
            "layer_pad": layer_pad}


class BootLayoutTests(unittest.TestCase):
    def test_real_dom_order_and_progress_authority_stay_intact(self):
        order = re.findall(r"card\.appendChild\((\w+)\)", SOURCE)
        self.assertEqual(order, ["title", "mascot", "track", "message", "retry"])
        self.assertIn("loaded / total", SOURCE)
        self.assertIn("window.__wwBootReady = finish", SOURCE)

    def test_mascot_clears_logo_and_painted_upper_rim(self):
        for width, height in PROFILES:
            with self.subTest(viewport=(width, height)):
                g = geometry(width, height)
                self.assertGreaterEqual(g["mascot_ink_top"] - g["title_bottom"], 6)
                self.assertGreaterEqual(g["mascot_ink_top"] - g["card_h"] * .12, 8)

    def test_caption_and_retry_clear_painted_lower_rim(self):
        for width, height in PROFILES:
            for retry in [False, True]:
                with self.subTest(viewport=(width, height), retry=retry):
                    self.assertGreaterEqual(geometry(width, height, retry)["bottom_clearance"], 6)

    def test_normal_layout_and_overlapping_logo_fit_viewport(self):
        for width, height in PROFILES:
            with self.subTest(viewport=(width, height)):
                g = geometry(width, height)
                self.assertLessEqual(g["card_w"] + g["layer_pad"][1] + g["layer_pad"][3], width)
                self.assertGreaterEqual(g["visible_title_top"], 2)
                self.assertLessEqual(g["card_h"] + g["layer_pad"][0] + g["layer_pad"][2], height)

    def test_long_retry_remains_scroll_accessible_with_safe_area(self):
        g = geometry(568, 320, retry=True, safe_bottom=34)
        self.assertGreater(g["card_h"] + sum(g["layer_pad"][::2]), 320)
        self.assertEqual(g["css"]["#ww-boot-layer"].get("overflow-y"), "auto")
        self.assertEqual(g["css"]["#ww-boot-layer"].get("justify-content"), "flex-start")
        self.assertEqual(g["css"]["#ww-boot-card"].get("flex-shrink"), "0")
        self.assertGreaterEqual(g["layer_pad"][0] + g["title_top"], 2)
        self.assertGreaterEqual(g["layer_pad"][2], 34)

    def test_reduced_motion_keeps_nonanimated_mascot(self):
        reduced = STYLE.split("@media (prefers-reduced-motion: reduce)", 1)[1]
        self.assertIn("#ww-boot-mascot { animation: none; }", reduced)
        self.assertIn("#ww-progress-fill { transition: none; }", reduced)


if __name__ == "__main__":
    unittest.main(verbosity=2)
