# SPDX-FileCopyrightText: 2026 Grayson Adams
#
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Makes the TTF fonts in test/parity/fonts from the web fonts the Seam
website ships, because Flutter cannot load woff2.

Needs fonttools and brotli. Usage:

    python make_fonts.py <roboto-latin-wght-normal.woff2> \
        <roboto-mono-latin-700-normal.woff2> <out dir>

The first file is @fontsource-variable/roboto (Roboto, variable weight); it
is cut into static instances at 400, 500, 600 and 700. The second is
@fontsource/roboto-mono at 700, the weight of avatar initials.
"""

import sys

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

src_var, src_mono, out = sys.argv[1:4]

for weight, name in [(400, "Regular"), (500, "Medium"), (600, "SemiBold"), (700, "Bold")]:
    font = TTFont(src_var)
    instance = instancer.instantiateVariableFont(font, {"wght": weight})
    # Flutter picks a face of a family by this weight.
    instance["OS/2"].usWeightClass = weight
    instance.flavor = None
    instance.save(f"{out}/Roboto-{name}.ttf")

mono = TTFont(src_mono)
mono.flavor = None
mono.save(f"{out}/RobotoMono-Bold.ttf")
