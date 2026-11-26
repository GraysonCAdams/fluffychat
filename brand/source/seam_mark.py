# Seam brand mark: app icon, glyph and Android icon layers, all drawn from one geometry.
# A round speech bubble with a normal tail at the lower left, split by a gentle S seam (periwinkle above,
# white below) sewn with four running stitches. The thread starts as a free end hanging out and down from
# the first stitch hole at the left; the working thread runs from the last stitch at the right to the eye
# of a needle that sits behind the bubble with its eye out at the top right.
# Usage: seam_mark.py <out_dir> [scale] [tail]   (defaults: .81, down: the locked design)
import sys,os,math
out=sys.argv[1]; os.makedirs(out,exist_ok=True)
SCALE=float(sys.argv[2]) if len(sys.argv)>2 else .81
BG,W,P='#1A5AD7','#FFFFFF','#9ABAF0'
CX,CY,RX,RY=216,206,132,108
BODY=f'<ellipse cx="{CX}" cy="{CY}" rx="{RX}" ry="{RY}"/>'
TAIL='<path d="M112,262 C110,292 98,320 72,342 C118,340 156,320 180,294 Z"/>'
SHAPE=BODY+TAIL
SEAM=[(86,212),(150,226),(196,214),(230,200),(266,186),(316,178),(346,188)]
SEAM_D='M{0},{1} C{2},{3} {4},{5} {6},{7} C{8},{9} {10},{11} {12},{13}'.format(*[c for p in SEAM for c in p])
PALE=SEAM_D+' L470,188 L470,-20 L-20,-20 L-20,212 Z'
def bez(p0,p1,p2,p3,t): return tuple((1-t)**3*a+3*(1-t)**2*t*b+3*(1-t)*t**2*c+t**3*d for a,b,c,d in zip(p0,p1,p2,p3))
def seam_points(n):
    segs=[SEAM[0:4],SEAM[3:7]]; o=[]
    for i in range(n):
        u=i/(n-1)*2; s=min(int(u),1); o.append(bez(*segs[s],u-s))
    return o
PTS=seam_points(15)
# four stitches, each two point-steps long, with a two-step gap between them
STITCHES=''.join(f'<polyline points="{" ".join(f"{x:.1f},{y:.1f}" for x,y in PTS[a:b+1])}" fill="none"/>' for a,b in [(0,2),(4,6),(8,10),(12,14)])
FIRST,LAST=PTS[0],PTS[14]
# needle: eye end out at the top right, point hidden behind the bubble
NX1,NY1,NX2,NY2=392,58,284,166; NW=34
L=math.hypot(NX2-NX1,NY2-NY1); ANG=math.degrees(math.atan2(NY2-NY1,NX2-NX1)); UX,UY=(NX2-NX1)/L,(NY2-NY1)/L
h=NW/2; E=min(L*0.26,NW*1.3); ER=h*0.42
BLADE=(f"M-6,0 C-6,-{h} 10,-{h} 26,-{h*0.86:.1f} L{L*0.7:.1f},-{h*0.5:.1f} L{L:.1f},0 "
       f"L{L*0.7:.1f},{h*0.5:.1f} L26,{h*0.86:.1f} C10,{h} -6,{h} -6,0 Z")
EYE=f"M5,-{ER:.1f} H{E:.1f} A{ER:.1f},{ER:.1f} 0 0 1 {E:.1f},{ER:.1f} H5 A{ER:.1f},{ER:.1f} 0 0 1 5,-{ER:.1f} Z"
def needle(c): return f'<g transform="translate({NX1} {NY1}) rotate({ANG:.2f})"><path d="{BLADE} {EYE}" fill="{c}" fill-rule="evenodd"/></g>'
EX,EY=NX1+UX*(5+E)/2,NY1+UY*(5+E)/2          # centre of the eye
# working thread: from the eye, bowing out to the right, down to the last stitch
THREAD=f'M{EX:.1f},{EY:.1f} C{EX+30:.1f},{EY+26:.1f} {LAST[0]+34:.1f},{LAST[1]-40:.1f} {LAST[0]:.1f},{LAST[1]:.1f}'
# starting tail: curls up and out of the first stitch hole, away from the bubble's own tail
fx,fy=FIRST
TAIL_SHAPES={
 # curls up and out (reads as a raised arm when paired with the needle)
 'up':   f'M{fx:.1f},{fy:.1f} C{fx-30:.1f},{fy-2:.1f} {fx-48:.1f},{fy-22:.1f} {fx-42:.1f},{fy-50:.1f}',
 # variant C's original: curls out and down beside the bubble, a loose end hanging from the first stitch
 'down': f'M{fx:.1f},{fy:.1f} C{fx-34:.1f},{fy+2:.1f} {fx-46:.1f},{fy+34:.1f} {fx-30:.1f},{fy+62:.1f}',
 # lies out flat to the left with a slight droop, like a loose end resting on the cloth
 'flat': f'M{fx:.1f},{fy:.1f} C{fx-18:.1f},{fy+1:.1f} {fx-34:.1f},{fy+4:.1f} {fx-46:.1f},{fy+12:.1f}',
 # a short end that drops straight down, tucked between the bubble edge and its tail
 'drop': f'M{fx:.1f},{fy:.1f} C{fx-16:.1f},{fy+2:.1f} {fx-24:.1f},{fy+14:.1f} {fx-24:.1f},{fy+30:.1f}',
 # just a stub poking out of the first stitch hole
 'stub': f'M{fx:.1f},{fy:.1f} C{fx-10:.1f},{fy+1:.1f} {fx-18:.1f},{fy+4:.1f} {fx-24:.1f},{fy+9:.1f}',
}
TAILTHREAD=TAIL_SHAPES[sys.argv[3] if len(sys.argv)>3 else 'down']
GAP=30; TW=11
H='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 432 432">'
def mark(fill,pale):
    pl=f'<g clip-path="url(#b)"><path d="{PALE}" fill="{P}"/></g>' if pale else ''
    th=f'fill="none" stroke="{fill}" stroke-width="{TW}" stroke-linecap="round"'
    return f'''<defs><clipPath id="b">{SHAPE}</clipPath>
<clipPath id="ends"><circle cx="{FIRST[0]:.1f}" cy="{FIRST[1]:.1f}" r="22"/><circle cx="{LAST[0]:.1f}" cy="{LAST[1]:.1f}" r="22"/></clipPath>
<mask id="cut" maskUnits="userSpaceOnUse" x="0" y="0" width="432" height="432"><rect width="432" height="432" fill="#fff"/><g stroke="#000" stroke-width="16" stroke-linecap="round" stroke-linejoin="round">{STITCHES}</g></mask>
<mask id="behind" maskUnits="userSpaceOnUse" x="0" y="0" width="432" height="432"><rect width="432" height="432" fill="#fff"/><g fill="#000">{SHAPE}</g><g fill="none" stroke="#000" stroke-width="{GAP}" stroke-linejoin="round">{SHAPE}</g></mask></defs>
<g transform="translate(216 216) scale({SCALE}) translate(-216 -206)">
<g mask="url(#behind)">{needle(fill)}<path d="{THREAD}" {th}/><path d="{TAILTHREAD}" {th}/></g>
<g mask="url(#cut)"><g fill="{fill}">{SHAPE}</g>{pl}</g>
<g clip-path="url(#ends)"><path d="{THREAD}" {th}/><path d="{TAILTHREAD}" {th}/></g></g>'''
open(os.path.join(out,'seam-app-icon.svg'),'w').write(H+f'<rect width="432" height="432" fill="{BG}"/>'+mark(W,True)+'</svg>')
open(os.path.join(out,'seam-mark.svg'),'w').write(H+mark(W,True)+'</svg>')            # for dark or cobalt backgrounds
open(os.path.join(out,'seam-mark-on-light.svg'),'w').write(H+mark(BG,True)+'</svg>')   # for white or light backgrounds
ADAPT='<g transform="translate(216 216) scale(0.6667) translate(-216 -216)">{}</g>'
open(os.path.join(out,'android-foreground.svg'),'w').write(H+ADAPT.format(mark(W,True))+'</svg>')
open(os.path.join(out,'android-monochrome.svg'),'w').write(H+ADAPT.format(mark('#FFFFFF',False))+'</svg>')
for tag,c in (('','currentColor'),('-white','#FFFFFF'),('-dark','#1F1F1F')):
    open(os.path.join(out,f'seam-glyph{tag}.svg'),'w').write(H+mark(c,False)+'</svg>')
