# Draws brand/preview.png, the overview at the top of BRAND.md, from the kit that build_brand.py wrote.
# Usage (from the brand/ folder, after build_brand.py):  python3 source/preview.py
# Needs python3 with Pillow and the DejaVu Sans font (falls back to Pillow's default font without it).
import os
from PIL import Image, ImageDraw, ImageFont
BRAND=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def font(px,bold=False):
    try: return ImageFont.truetype('DejaVuSans%s.ttf'%('-Bold' if bold else ''),px)
    except OSError: return ImageFont.load_default()
def png(name): return Image.open(os.path.join(BRAND,'png',name)).convert('RGBA')
def res(name): return Image.open(os.path.join(BRAND,'android','res',name)).convert('RGBA')
T=230; BG=(0x11,0x12,0x14); CARD=(0x1E,0x1F,0x24); INK=(0xE6,0xE6,0xEA); DIM=(0xA0,0xA0,0xA8)
COB=(0x1A,0x5A,0xD7,255)
def card(bg,im,size=T):
    c=Image.new('RGBA',(T,T),bg); im=im.resize((size,size),Image.LANCZOS); c.alpha_composite(im,((T-size)//2,(T-size)//2)); return c
def masked(im,kind):
    m=Image.new('L',(T*4,T*4),0); d=ImageDraw.Draw(m)
    if kind=='circle': d.ellipse((0,0,T*4-1,T*4-1),fill=255)
    else: d.rounded_rectangle((0,0,T*4-1,T*4-1),radius=int(T*4*.3),fill=255)
    out=Image.new('RGBA',(T,T),CARD); out.paste(im.resize((T,T),Image.LANCZOS),(0,0),m.resize((T,T),Image.LANCZOS)); return out
def adaptive(fg,bg):
    full=Image.new('RGBA',fg.size,bg); full.alpha_composite(fg); s=fg.size[0]; return full.crop((s//6,s//6,s-s//6,s-s//6))
def tint(im,rgb):
    t=Image.new('RGBA',im.size,rgb+(255,)); t.putalpha(im.getchannel('A')); return t
fg=res('mipmap-xxxhdpi/ic_launcher_foreground.png'); mono=res('mipmap-xxxhdpi/ic_launcher_monochrome.png')
ico=Image.open(os.path.join(BRAND,'windows','tray_icon.ico')); ico.size=(256,256); ico.load(); tray=ico.convert('RGBA')
cells=[
 (masked(adaptive(fg,COB),'circle'),'App icon, circle'),
 (masked(adaptive(fg,COB),'squircle'),'App icon, squircle'),
 (masked(adaptive(tint(mono,(0xC4,0xD4,0xFF)),(0x2A,0x2E,0x3A,255)),'circle'),'Themed icon'),
 (card(CARD,png('seam-mark-512.png')),'Mark, dark backgrounds'),
 (card((255,255,255,255),png('seam-mark-on-light-512.png')),'Mark, light backgrounds'),
 (card((0,0,0,255),png('seam-glyph-white-512.png')),'Glyph, white'),
 (card((0xF0,0xF1,0xF4,255),png('seam-glyph-dark-512.png')),'Glyph, dark'),
 (card((0,0,0,255),tray,64),'Notification and tray glyph'),
]
swatches=[((0x1A,0x5A,0xD7),'Seam Cobalt  #1A5AD7'),((0x9A,0xBA,0xF0),'Seam Pale  #9ABAF0'),((0x5F,0x8C,0xE3),'Pale on light  #5F8CE3'),
          ((255,255,255),'White  #FFFFFF'),((0x1F,0x1F,0x1F),'Glyph dark  #1F1F1F')]
W=20+4*(T+20); H=150+2*(T+48)+20
im=Image.new('RGBA',(W,H),BG+(255,)); d=ImageDraw.Draw(im)
d.text((20,20),'Seam',font=font(26,True),fill=INK); d.text((20,56),'Where your threads meet.',font=font(15),fill=DIM)
x=20
for rgb,label in swatches:
    d.rounded_rectangle((x,94,x+32,126),radius=6,fill=rgb,outline=(0x3A,0x3B,0x40)); d.text((x+40,102),label,font=font(12),fill=INK)
    x+=40+int(d.textlength(label,font=font(12)))+18
for i,(c,label) in enumerate(cells):
    x=20+(i%4)*(T+20); y=160+(i//4)*(T+48)
    im.alpha_composite(c,(x,y)); d.text((x,y+T+10),label,font=font(15),fill=INK)
im.convert('RGB').save(os.path.join(BRAND,'preview.png'))
print('wrote',os.path.join(BRAND,'preview.png'))
