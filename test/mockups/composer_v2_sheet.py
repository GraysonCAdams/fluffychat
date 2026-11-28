"""Lays the shots from composer_v2_test.dart out as one labelled sheet per
theme, with each variant's measured paddings under its name:

    python3 test/mockups/composer_v2_sheet.py build/composer_v2 OUT_DIR

writes OUT_DIR/sheet_dark.png and OUT_DIR/sheet_light.png.
"""

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT = "assets/fonts/google_sans_flex/GoogleSansFlex-{}.ttf"
VARIANTS = {
    "today": "Today (integration2 head)",
    "a": "A  (+) leading, emoji as trailing icon before send",
    "b": "B  (+) and emoji as one leading cluster",
    "c": "C  (+) leading only, emoji via (+) menu or Win+.",
}
NOTES = {
    "today": "",
    "a": "Phone: no emoji button (no system picker on Android).",
    "b": "Phone: (+) only, emoji hidden.",
    "c": "",
}
WIDTHS = [1000, 412]
SCALE = 2


def paddings(m):
    """Edge-to-icon, icon-to-icon and icon-to-text gaps, in dp."""
    icons = m["icons"]
    text_left, text_right = m["text"]
    lead = [i for i in icons if i[1] <= text_left + 0.1]
    trail = [i for i in icons if i[0] >= text_left + 0.1]
    parts = []
    if lead:
        parts.append(f"edge-to-icon {lead[0][0]:g}")
        for a, b in zip(lead, lead[1:]):
            parts.append(f"icon-to-icon {b[0] - a[1]:g}")
        parts.append(f"icon-to-text {text_left - lead[-1][1]:g}")
    if len(trail) > 1:
        # The last trailing icon is the send arrow inside its 40 circle.
        parts.append(f"text-to-emoji {trail[0][0] - text_right:g}")
        parts.append(f"emoji-to-send-icon {trail[1][0] - trail[0][1]:g}")
    return ", ".join(parts)


def main(src, out):
    src, out = Path(src), Path(out)
    out.mkdir(parents=True, exist_ok=True)
    metrics = json.loads((src / "metrics.json").read_text())
    title = ImageFont.truetype(FONT.format("Medium"), 34)
    label = ImageFont.truetype(FONT.format("Medium"), 28)
    small = ImageFont.truetype(FONT.format("Regular"), 22)
    for theme in ["dark", "light"]:
        bg, fg, dim = (
            ((20, 20, 24), (230, 230, 235), (150, 150, 160))
            if theme == "dark"
            else ((250, 250, 252), (25, 25, 30), (100, 100, 110))
        )
        shot = lambda v, w, s: Image.open(src / f"{theme}_{v}_{w}_{s}.png")
        col_w = [shot("today", w, "empty").width for w in WIDTHS]
        shot_h = shot("today", 1000, "empty").height
        gap, margin = 40, 48
        row_h = 70 + 2 * shot_h + 16 + 34 + 30
        width = margin * 2 + sum(col_w) + gap
        height = 120 + len(VARIANTS) * (row_h + 30)
        sheet = Image.new("RGB", (width, height), bg)
        d = ImageDraw.Draw(sheet)
        d.text((margin, 30), f"Seam composer, emoji and attach layouts ({theme})",
               font=title, fill=fg)
        x1 = margin + col_w[0] + gap
        d.text((margin, 78), "Windows, 1000 dp window (pill capped at 760)",
               font=small, fill=dim)
        d.text((x1, 78), "Phone, 412 dp", font=small, fill=dim)
        y = 120
        for v, name in VARIANTS.items():
            d.text((margin, y), name, font=label, fill=fg)
            y += 44
            x = margin
            for w, cw in zip(WIDTHS, col_w):
                for i, s in enumerate(["empty", "typing"]):
                    sheet.paste(shot(v, w, s), (x, y + i * (shot_h + 16)))
                x += cw + gap
            yy = y + 2 * shot_h + 16 + 8
            d.text((margin, yy),
                   "1000: " + paddings(metrics[f"{theme}_{v}_1000_empty"]),
                   font=small, fill=dim)
            d.text((x1, yy),
                   "412: " + paddings(metrics[f"{theme}_{v}_412_empty"]),
                   font=small, fill=dim)
            if NOTES[v]:
                d.text((x1, yy + 30), NOTES[v], font=small, fill=dim)
            y += row_h - 44 + 30 + 44
        sheet = sheet.crop((0, 0, width, y))
        sheet.save(out / f"sheet_{theme}.png")
        print(out / f"sheet_{theme}.png", sheet.size)


if __name__ == "__main__":
    main(*sys.argv[1:])
