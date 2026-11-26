# SPDX-FileCopyrightText: 2026 Grayson Adams
#
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Makes test/parity/fonts/RobotoMono-Bold.ttf, the avatar initials' font,
from the web font the Seam website ships, because Flutter cannot load
woff2. The app's own font, Google Sans Flex, comes from its assets.

Needs fonttools and brotli. Usage:

    python make_fonts.py <roboto-mono-latin-700-normal.woff2> <out dir>

The input is @fontsource/roboto-mono at 700, the weight of avatar initials.
"""

import sys

from fontTools.ttLib import TTFont

src_mono, out = sys.argv[1:3]

mono = TTFont(src_mono)
mono.flavor = None
mono.save(f"{out}/RobotoMono-Bold.ttf")
