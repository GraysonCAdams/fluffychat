# Rebuilds every Seam brand asset from seam_mark.py: master SVGs, PNG sizes, Android launcher and
# notification icons, the Play Store icon and web icons.
# Usage (from the brand/ folder):  python3 source/build_brand.py
# Needs python3 with Pillow, and google-chrome (headless) to rasterise the SVGs.
import os,subprocess,sys,tempfile,shutil
from PIL import Image, ImageDraw
HERE=os.path.dirname(os.path.abspath(__file__)); BRAND=os.path.dirname(HERE)
SVG=os.path.join(BRAND,'svg'); PNG=os.path.join(BRAND,'png'); AND=os.path.join(BRAND,'android','res')
STORE=os.path.join(BRAND,'store'); WEB=os.path.join(BRAND,'web'); WIN=os.path.join(BRAND,'windows')
for d in (SVG,PNG,AND,STORE,WEB,WIN): os.makedirs(d,exist_ok=True)
subprocess.run([sys.executable,os.path.join(HERE,'seam_mark.py'),SVG],check=True)

# rasterise all masters at 1024 px in one headless-Chrome pass, on a transparent background
names=['seam-app-icon','seam-mark','seam-mark-on-light','seam-glyph-white','seam-glyph-dark','android-foreground','android-monochrome']
tmp=tempfile.mkdtemp()
html='<html><body style="margin:0;background:transparent;display:grid;grid-template-columns:repeat(4,1024px)">'+''.join(
    f'<img src="file://{SVG}/{n}.svg" width="1024" height="1024">' for n in names)+'</body></html>'
open(os.path.join(tmp,'sheet.html'),'w').write(html)
prof=tempfile.mkdtemp(); sheet=os.path.join(tmp,'sheet.png')
for attempt in range(2):
    subprocess.run(['timeout','120','google-chrome','--headless=new','--no-sandbox','--disable-gpu','--disable-dev-shm-usage',
        '--no-first-run','--hide-scrollbars','--allow-file-access-from-files',f'--user-data-dir={prof}',
        '--default-background-color=00000000','--window-size=4096,2048','--virtual-time-budget=5000',
        f'--screenshot={sheet}',f'file://{tmp}/sheet.html'],capture_output=True)
    if os.path.exists(sheet): break
    shutil.rmtree(prof); prof=tempfile.mkdtemp()      # a hung Chrome profile: retry once with a fresh one
if not os.path.exists(sheet): sys.exit('Chrome did not render the sheet')
S=Image.open(sheet).convert('RGBA'); big={n:S.crop(((i%4)*1024,(i//4)*1024,(i%4)*1024+1024,(i//4)*1024+1024)) for i,n in enumerate(names)}
shutil.rmtree(tmp); shutil.rmtree(prof)
def size(name,px): return big[name].resize((px,px),Image.LANCZOS)
def circle(im):
    m=Image.new('L',im.size,0); ImageDraw.Draw(m).ellipse((0,0,im.size[0]-1,im.size[1]-1),fill=255)
    o=Image.new('RGBA',im.size,(0,0,0,0)); o.paste(im,(0,0),m); return o

# general-purpose PNGs
for px in (16,24,32,48,64,96,128,192,256,512,1024):
    size('seam-app-icon',px).save(f'{PNG}/seam-app-icon-{px}.png')
    circle(size('seam-app-icon',px)).save(f'{PNG}/seam-app-icon-round-{px}.png')
for px in (64,128,256,512,1024):
    size('seam-mark',px).save(f'{PNG}/seam-mark-{px}.png'); size('seam-mark-on-light',px).save(f'{PNG}/seam-mark-on-light-{px}.png')
for px in (16,24,32,48,64,96,128,256,512):
    size('seam-glyph-white',px).save(f'{PNG}/seam-glyph-white-{px}.png'); size('seam-glyph-dark',px).save(f'{PNG}/seam-glyph-dark-{px}.png')

# Android: adaptive launcher icon (108 dp layers) + legacy icons (48 dp) + notification icon (24 dp)
dens={'mdpi':1,'hdpi':1.5,'xhdpi':2,'xxhdpi':3,'xxxhdpi':4}
for d,k in dens.items():
    md=f'{AND}/mipmap-{d}'; os.makedirs(md,exist_ok=True)
    size('android-foreground',int(108*k)).save(f'{md}/ic_launcher_foreground.png')
    size('android-monochrome',int(108*k)).save(f'{md}/ic_launcher_monochrome.png')
    size('seam-app-icon',int(48*k)).save(f'{md}/ic_launcher.png')
    circle(size('seam-app-icon',int(48*k))).save(f'{md}/ic_launcher_round.png')
    dd=f'{AND}/drawable-{d}'; os.makedirs(dd,exist_ok=True)
    size('seam-glyph-white',int(24*k)).save(f'{dd}/ic_stat_seam.png')
os.makedirs(f'{AND}/mipmap-anydpi-v26',exist_ok=True); os.makedirs(f'{AND}/values',exist_ok=True)
adaptive='''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
'''
for n in ('ic_launcher','ic_launcher_round'): open(f'{AND}/mipmap-anydpi-v26/{n}.xml','w').write(adaptive)
open(f'{AND}/values/ic_launcher_background.xml','w').write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#1A5AD7</color>\n</resources>\n')

# Play Store: 512 x 512, full square, no rounding or shadow (the store applies its own mask)
size('seam-app-icon',512).convert('RGB').save(f'{STORE}/play-store-icon-512.png')
# web
shutil.copy(f'{SVG}/seam-app-icon.svg',f'{WEB}/favicon.svg')
size('seam-app-icon',32).save(f'{WEB}/favicon-32.png')
size('seam-app-icon',180).convert('RGB').save(f'{WEB}/apple-touch-icon.png')
for px in (192,512): size('seam-app-icon',px).save(f'{WEB}/icon-{px}.png')
# Windows: the exe and taskbar use a rounded tile with the white mark (windows_tile); the title bar uses the bare mark, one per caption
# colour, so it sits on the caption instead of as a cobalt tile
ico=[(s,s) for s in (16,20,24,32,40,48,64,128,256)]
def windows_tile():
    # Windows 11 style tile for the exe, taskbar and Alt+Tab: a cobalt rounded square filling the
    # icon edge to edge, as other apps' tiles do in the taskbar, with the mark in solid white
    S=1024; m=0; r=int(S*0.22); t=Image.new('RGBA',(S,S),(0,0,0,0))
    ImageDraw.Draw(t).rounded_rectangle((m,m,S-1-m,S-1-m),radius=r,fill=(0x1A,0x5A,0xD7,255))
    g=big['seam-glyph-white']; x0,y0,x1,y1=g.getbbox(); g=g.crop((x0,y0,x1,y1))
    k=int(S*0.66)/max(g.size); g=g.resize((max(1,int(g.size[0]*k)),max(1,int(g.size[1]*k))),Image.LANCZOS)
    t.alpha_composite(g,((S-g.size[0])//2,(S-g.size[1])//2)); return t
windows_tile().save(f'{WIN}/app_icon.ico',sizes=ico)
big['seam-app-icon'].save(f'{WIN}/tray_icon.ico',sizes=ico)
def tight(im,margin=0.04):
    # crop to the mark itself (the 1024 masters keep the app icon's safe-zone padding) so it fills a
    # 16 to 24 px title-bar icon, then re-square it with a thin margin
    x0,y0,x1,y1=im.getbbox(); side=max(x1-x0,y1-y0); pad=int(side*margin); side+=2*pad
    sq=Image.new('RGBA',(side,side),(0,0,0,0)); sq.paste(im.crop((x0,y0,x1,y1)),(pad+(side-2*pad-(x1-x0))//2,pad+(side-2*pad-(y1-y0))//2))
    return sq.resize((1024,1024),Image.LANCZOS)
tight(big['seam-mark-on-light']).save(f'{WIN}/titlebar_light.ico',sizes=ico)
tight(big['seam-mark']).save(f'{WIN}/titlebar_dark.ico',sizes=ico)
print('brand assets rebuilt in',BRAND)
