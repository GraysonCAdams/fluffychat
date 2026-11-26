#!/usr/bin/env python3
# Draws Play's two listing graphics from the brand kit, so neither can drift
# from the icon the app ships.
#
#   python3 android/store/make-graphics.py        # from the repo root
#
#   android/store/icon-512.png               512x512, 32-bit PNG with alpha
#   android/store/play/feature-graphic.png   1024x500, 24-bit PNG, no alpha
#
# The icon is brand/store/play-store-icon-512.png with an opaque alpha channel
# added, the format Play asks for. The feature graphic is the mark, the name
# and the tagline on Seam Cobalt, laid out in HTML and rendered by headless
# Chrome so the wordmark is set in Plus Jakarta Sans (brand/BRAND.md). Chrome
# fetches that font from Google Fonts, so run this online: offline, Chrome
# falls back to another sans-serif and the picture changes.
#
# Needs python3 with Pillow and google-chrome, the same as
# brand/source/build_brand.py. Re-run it whenever the brand kit is rebuilt.
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
BRAND = os.path.join(REPO, 'brand')

COBALT = '#1A5AD7'
PERIWINKLE = '#9ABAF0'
WIDTH, HEIGHT = 1024, 500


def icon512():
    src = Image.open(os.path.join(BRAND, 'store', 'play-store-icon-512.png'))
    if src.size != (512, 512):
        sys.exit(f'brand/store/play-store-icon-512.png is {src.size}, not 512x512')
    src.convert('RGBA').save(os.path.join(HERE, 'icon-512.png'), optimize=True)


def feature_graphic():
    with open(os.path.join(BRAND, 'svg', 'seam-mark.svg'), encoding='utf-8') as f:
        mark = f.read()
    page = f'''<!doctype html>
<html><head><meta charset="utf-8">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@500;800&display=block" rel="stylesheet">
<style>
  html, body {{ margin: 0; width: {WIDTH}px; height: {HEIGHT}px; overflow: hidden; background: {COBALT}; }}
  body {{ display: flex; align-items: center; justify-content: center; gap: 28px;
         font-family: 'Plus Jakarta Sans', sans-serif; }}
  .mark {{ width: 300px; height: 300px; }}
  .mark svg {{ width: 100%; height: 100%; display: block; }}
  .name {{ color: #fff; font-weight: 800; font-size: 148px; line-height: 1; letter-spacing: -3px; }}
  .tagline {{ color: {PERIWINKLE}; font-weight: 500; font-size: 38px; margin-top: 14px; }}
</style></head>
<body>
  <div class="mark">{mark}</div>
  <div><div class="name">Seam</div><div class="tagline">Where your threads meet.</div></div>
</body></html>'''
    work = tempfile.mkdtemp()
    try:
        html = os.path.join(work, 'feature.html')
        shot = os.path.join(work, 'feature.png')
        with open(html, 'w', encoding='utf-8') as f:
            f.write(page)
        subprocess.run(
            ['timeout', '120', 'google-chrome', '--headless=new', '--no-sandbox', '--disable-gpu',
             '--disable-dev-shm-usage', '--hide-scrollbars', f'--user-data-dir={work}/profile',
             '--virtual-time-budget=8000', f'--window-size={WIDTH},{HEIGHT}',
             f'--screenshot={shot}', 'file://' + html],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        image = Image.open(shot)
        if image.size != (WIDTH, HEIGHT):
            sys.exit(f'Chrome rendered {image.size}, not {WIDTH}x{HEIGHT}')
        out = os.path.join(HERE, 'play', 'feature-graphic.png')
        os.makedirs(os.path.dirname(out), exist_ok=True)
        image.convert('RGB').save(out, optimize=True)
    finally:
        shutil.rmtree(work, ignore_errors=True)


icon512()
feature_graphic()
print('wrote android/store/icon-512.png and android/store/play/feature-graphic.png')
