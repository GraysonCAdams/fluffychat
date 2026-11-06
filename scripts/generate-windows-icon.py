#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Build windows/runner/resources/app_icon.ico from assets/logo/vector/logo.svg.

The logo artwork is clipped to a rounded square inset on Microsoft's 48x48
icon grid, with transparent corners, and rendered separately at every size
Windows 11 asks for, so Windows never scales a bitmap up.

Requires: pip install cairosvg pillow
Usage:    python3 scripts/generate-windows-icon.py
"""

import io
import re
from pathlib import Path

import cairosvg
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / 'assets' / 'logo' / 'vector' / 'logo.svg'
ICO = ROOT / 'windows' / 'runner' / 'resources' / 'app_icon.ico'

# The minimum set from Microsoft's app icon construction guide (16, 24, 32,
# 48, 256) plus every other scale-factor size its table lists.
SIZES = [16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80, 96, 256]

# Plate geometry in 48x48 grid units.
PADDING = 3
CORNER_RADIUS = 6


def plated_svg() -> str:
    source = LOGO.read_text()
    inner = re.sub(r'^.*?<svg[^>]*>', '', source, flags=re.S).rsplit('</svg>', 1)[0]
    plate = 48 - 2 * PADDING
    radius = CORNER_RADIUS * 200 / plate  # logo.svg uses a 200x200 viewBox
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <svg x="{PADDING}" y="{PADDING}" width="{plate}" height="{plate}" viewBox="0 0 200 200">
    <defs><clipPath id="plate"><rect width="200" height="200" rx="{radius}" ry="{radius}"/></clipPath></defs>
    <g clip-path="url(#plate)">{inner}</g>
  </svg>
</svg>'''


def main() -> None:
    svg = plated_svg().encode()
    images = [
        Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg, output_width=s, output_height=s))).convert('RGBA')
        for s in SIZES
    ]
    largest = images[-1]
    largest.save(ICO, format='ICO', sizes=[(s, s) for s in SIZES], append_images=images[:-1])
    print(f'Wrote {ICO.relative_to(ROOT)} with sizes {SIZES}')


if __name__ == '__main__':
    main()
