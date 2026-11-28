# Rebuilds every Seam brand asset from seam_mark.py: the kit in brand/ (master SVGs, PNG sizes, Android
# launcher and notification icons, the Play Store icon, web, Windows and Apple icons), then copies each
# file the app ships to its place in the app (see INSTALL at the end, and brand/BRAND.md).
# Usage (from the brand/ folder):  python3 source/build_brand.py
# Needs python3 with Pillow, skia-pathops and fonttools, and google-chrome (headless) to rasterise the SVGs.
# The Play feature graphic is drawn by android/store/make-graphics.py; run it after this.
import os,subprocess,sys,tempfile,shutil
from PIL import Image, ImageDraw, ImageFilter
HERE=os.path.dirname(os.path.abspath(__file__)); BRAND=os.path.dirname(HERE); REPO=os.path.dirname(BRAND)
SVG=os.path.join(BRAND,'svg'); PNG=os.path.join(BRAND,'png'); AND=os.path.join(BRAND,'android','res')
STORE=os.path.join(BRAND,'store'); WEB=os.path.join(BRAND,'web'); WIN=os.path.join(BRAND,'windows')
APPLE=os.path.join(BRAND,'apple')
for d in (SVG,PNG,AND,STORE,WEB,WIN,APPLE): os.makedirs(d,exist_ok=True)
subprocess.run([sys.executable,os.path.join(HERE,'seam_mark.py'),SVG],check=True)

def rasterise(items):
    # items: (svg name, px). One headless-Chrome pass on a transparent background, each SVG drawn at its
    # own pixel size, so small sizes come straight from the vector instead of a downscale
    tmp=tempfile.mkdtemp(); x=y=rowh=0; pos=[]
    for n,px in items:
        if x+px>4096: x=0; y+=rowh; rowh=0
        pos.append((x,y)); x+=px; rowh=max(rowh,px)
    H=y+rowh
    html='<html><body style="margin:0;background:transparent">'+''.join(
        f'<img src="file://{SVG}/{n}.svg" width="{px}" height="{px}" style="position:absolute;left:{x}px;top:{y}px">'
        for (n,px),(x,y) in zip(items,pos))+'</body></html>'
    open(os.path.join(tmp,'sheet.html'),'w').write(html)
    prof=tempfile.mkdtemp(); sheet=os.path.join(tmp,'sheet.png')
    for attempt in range(2):
        subprocess.run(['timeout','120','google-chrome','--headless=new','--no-sandbox','--disable-gpu','--disable-dev-shm-usage',
            '--no-first-run','--hide-scrollbars','--allow-file-access-from-files',f'--user-data-dir={prof}',
            '--default-background-color=00000000',f'--window-size=4096,{H}','--virtual-time-budget=5000',
            f'--screenshot={sheet}',f'file://{tmp}/sheet.html'],capture_output=True)
        if os.path.exists(sheet): break
        shutil.rmtree(prof); prof=tempfile.mkdtemp()      # a hung Chrome profile: retry once with a fresh one
    if not os.path.exists(sheet): sys.exit('Chrome did not render the sheet')
    S=Image.open(sheet).convert('RGBA')
    out={(n,px):S.crop((x,y,x+px,y+px)) for (n,px),(x,y) in zip(items,pos)}
    shutil.rmtree(tmp); shutil.rmtree(prof); return out

names=['seam-app-icon','seam-mark','seam-mark-on-light','seam-glyph-white','seam-glyph-dark','android-foreground',
       'android-monochrome','web-maskable','tray-dark','tray-light','macos-icon']
small=[('macos-icon-small',16),('macos-icon-small',32),('macos-icon',32),('macos-icon',64)]
R=rasterise([(n,1024) for n in names]+small)
big={n:R[(n,1024)] for n in names}
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

# Android: adaptive launcher icon (108 dp layers) + legacy icons (48 dp) + the pre-Android 12 launch image
dens={'mdpi':1,'hdpi':1.5,'xhdpi':2,'xxhdpi':3,'xxxhdpi':4}
for d,k in dens.items():
    md=f'{AND}/mipmap-{d}'; os.makedirs(md,exist_ok=True)
    size('android-foreground',int(108*k)).save(f'{md}/ic_launcher_foreground.png')
    size('android-monochrome',int(108*k)).save(f'{md}/ic_launcher_monochrome.png')
    size('seam-app-icon',int(48*k)).save(f'{md}/ic_launcher.png')
    circle(size('seam-app-icon',int(48*k))).save(f'{md}/ic_launcher_round.png')
    dd=f'{AND}/drawable-{d}'; os.makedirs(dd,exist_ok=True)
    size('seam-mark',int(177*k)).save(f'{dd}/splash.png')     # 177 dp, centred on cobalt by launch_background.xml
# notification icon (24 dp): a vector drawable, so the status bar draws it sharp at every density
os.makedirs(f'{AND}/drawable',exist_ok=True)
subprocess.run([sys.executable,os.path.join(HERE,'notification_icon.py'),f'{AND}/drawable/ic_stat_seam.xml'],check=True)
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
# web: favicon.png is the 16 px icon (web/index.html declares it 16x16); maskable icons keep the mark
# inside the 80% safe circle
shutil.copy(f'{SVG}/seam-app-icon.svg',f'{WEB}/favicon.svg')
size('seam-app-icon',16).save(f'{WEB}/favicon.png')
size('seam-app-icon',180).convert('RGB').save(f'{WEB}/apple-touch-icon.png')
for px in (16,32,48,192,512): size('seam-app-icon',px).save(f'{WEB}/icon-{px}.png')
for px in (192,512): size('web-maskable',px).save(f'{WEB}/icon-maskable-{px}.png')
# Windows: the exe and taskbar use a rounded tile with the mark (windows_tile); the title bar uses the bare mark, one per caption
# colour, so it sits on the caption instead of as a cobalt tile
ico=[(s,s) for s in (16,20,24,32,40,48,64,128,256)]
def windows_tile():
    # Windows 11 style tile for the exe, taskbar and Alt+Tab: a cobalt rounded square filling the
    # icon edge to edge, as other apps' tiles do in the taskbar, with the two-tone mark
    S=1024; m=0; r=int(S*0.22); t=Image.new('RGBA',(S,S),(0,0,0,0))
    ImageDraw.Draw(t).rounded_rectangle((m,m,S-1-m,S-1-m),radius=r,fill=(0x1A,0x5A,0xD7,255))
    g=big['seam-mark']; x0,y0,x1,y1=g.getbbox(); g=g.crop((x0,y0,x1,y1))
    k=int(S*0.75)/max(g.size); g=g.resize((max(1,int(g.size[0]*k)),max(1,int(g.size[1]*k))),Image.LANCZOS)
    t.alpha_composite(g,((S-g.size[0])//2,(S-g.size[1])//2)); return t
windows_tile().save(f'{WIN}/app_icon.ico',sizes=ico)
def tight(im,margin=0.04):
    # crop to the mark itself (the 1024 masters keep the app icon's safe-zone padding) so it fills a
    # 16 to 24 px icon, then re-square it with a thin margin
    x0,y0,x1,y1=im.getbbox(); side=max(x1-x0,y1-y0); pad=int(side*margin); side+=2*pad
    sq=Image.new('RGBA',(side,side),(0,0,0,0)); sq.paste(im.crop((x0,y0,x1,y1)),(pad+(side-2*pad-(x1-x0))//2,pad+(side-2*pad-(y1-y0))//2))
    return sq.resize((1024,1024),Image.LANCZOS)
tight(big['seam-mark-on-light']).save(f'{WIN}/titlebar_light.ico',sizes=ico)
tight(big['seam-mark']).save(f'{WIN}/titlebar_dark.ico',sizes=ico)
# tray: the needle-free glyph, one icon per taskbar theme (the app picks by the taskbar's colour)
tight(big['tray-dark'],0.08).save(f'{WIN}/tray_icon.ico',sizes=ico)
tight(big['tray-light'],0.08).save(f'{WIN}/tray_icon_light_taskbar.ico',sizes=ico)

# iOS: one 1024 px icon per appearance (light: the full tile; dark: the two-tone mark on the system's dark
# backing; tinted: the one-colour glyph, which the system tints by its brightness), and the launch image,
# the tile at 192 pt
IOS=f'{APPLE}/ios'; MAC=f'{APPLE}/macos'; os.makedirs(IOS,exist_ok=True); os.makedirs(MAC,exist_ok=True)
size('seam-app-icon',1024).convert('RGB').save(f'{IOS}/AppIcon.png')
big['seam-mark'].save(f'{IOS}/AppIcon-Dark.png'); big['seam-glyph-white'].save(f'{IOS}/AppIcon-Tinted.png')
for k,sfx in ((1,''),(2,'@2x'),(3,'@3x')): size('seam-app-icon',192*k).convert('RGB').save(f'{IOS}/LaunchImage{sfx}.png')
# layers for Icon Composer (iOS 26 and later): background, the piece below the seam with the needle and
# thread, and the paler piece above; it builds the .icon from these on a Mac
os.makedirs(f'{APPLE}/icon-composer',exist_ok=True)
subprocess.run([sys.executable,os.path.join(HERE,'seam_mark.py'),f'{APPLE}/icon-composer','layers'],check=True)
# macOS: the tile on Apple's grid with its drop shadow. 1024 to 128 are downscales; 64 and 32 are drawn
# from the vector at their size, and 16 from the needle-free vector (macos-icon-small)
def mac_shadow(px):
    S=1024; o=100; m=Image.new('L',(S,S),0); ImageDraw.Draw(m).rounded_rectangle((o,o,o+823,o+823),radius=185.4,fill=255)
    sh=Image.new('RGBA',(S,S),(0,0,0,0)); sh.putalpha(m.point(lambda v:v*0.30).filter(ImageFilter.GaussianBlur(10)))
    return sh.transform((S,S),Image.AFFINE,(1,0,0,0,1,-10)).resize((px,px),Image.LANCZOS)
def mac_icon(face,px):
    t=mac_shadow(px); t.alpha_composite(face); return t
for px in (128,256,512,1024): mac_icon(big['macos-icon'].resize((px,px),Image.LANCZOS),px).save(f'{MAC}/app_icon_{px}.png')
mac_icon(R[('macos-icon',64)],64).save(f'{MAC}/app_icon_64.png')
mac_icon(R[('macos-icon',32)],32).save(f'{MAC}/app_icon_32.png')
mac_icon(R[('macos-icon-small',16)],16).save(f'{MAC}/app_icon_16.png')

# INSTALL: copy what the app ships to where the app loads it from
def put(src,dst):
    dst=os.path.join(REPO,dst); os.makedirs(os.path.dirname(dst),exist_ok=True); shutil.copyfile(src,dst)
RES='android/app/src/main/res'
for d in dens:
    put(f'{AND}/mipmap-{d}/ic_launcher_foreground.png',f'{RES}/drawable-{d}/ic_launcher_foreground.png')
    put(f'{AND}/mipmap-{d}/ic_launcher_monochrome.png',f'{RES}/drawable-{d}/ic_launcher_monochrome.png')
    put(f'{AND}/mipmap-{d}/ic_launcher.png',f'{RES}/mipmap-{d}/ic_launcher.png')
    put(f'{AND}/drawable-{d}/splash.png',f'{RES}/drawable-{d}/splash.png')
# the app's copy keeps its older name because the code loads it by that name
put(f'{AND}/drawable/ic_stat_seam.xml',f'{RES}/drawable/notifications_icon.xml')
put(f'{PNG}/seam-app-icon-512.png','assets/seam/seam_app_icon.png')
put(f'{PNG}/seam-glyph-white-512.png','assets/seam/seam_glyph.png')
put(f'{WIN}/tray_icon.ico','assets/seam/tray_icon.ico')
put(f'{WIN}/tray_icon_light_taskbar.ico','assets/seam/tray_icon_light_taskbar.ico')
put(f'{WIN}/app_icon.ico','windows/runner/resources/app_icon.ico')
put(f'{WEB}/favicon.png','web/favicon.png')
for px in (16,32,48,192,512): put(f'{WEB}/icon-{px}.png',f'web/icons/Icon-{px}.png')
for px in (192,512): put(f'{WEB}/icon-maskable-{px}.png',f'web/icons/Icon-maskable-{px}.png')
AI='ios/Runner/Assets.xcassets'
for n in ('AppIcon','AppIcon-Dark','AppIcon-Tinted'): put(f'{IOS}/{n}.png',f'{AI}/AppIcon.appiconset/{n}.png')
for sfx in ('','@2x','@3x'): put(f'{IOS}/LaunchImage{sfx}.png',f'{AI}/LaunchImage.imageset/LaunchImage{sfx}.png')
for px in (16,32,64,128,256,512,1024): put(f'{MAC}/app_icon_{px}.png',f'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{px}.png')
print('brand assets rebuilt in',BRAND,'and copied into the app')
