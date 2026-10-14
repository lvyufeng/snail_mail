"""Generate SnailMail/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

Flat-vector app icon built from the same palette as Sources/UI/Theme.swift and
Sources/Game/Sprites.swift. Requires Pillow + numpy:  python3 tools/make_app_icon.py
"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np, math, random

SS, S = 2, 1024
W = S*SS
random.seed(7)

INK=(26,12,44); BODYHI=(255,249,226); BODY=(253,236,190); BODYLO=(219,172,100)
SHELL=(196,152,255); SHELLMID=(170,118,252); SHELLD=(120,70,200); SHELLHI=(246,238,255)
METAL=(186,192,212); METALLO=(98,104,132); CYAN=(88,225,255)
GOLD=(255,206,84); ORANGE=(255,116,40); PALE=(255,246,204); MAGENTA=(172,58,154)

T_OUT = 23.0
SUBJ_C = (560, 520); ROT = math.radians(-17)

def X(v): return v*SS
def ell_pts(cx,cy,rx,ry,n=72):
    return [(cx+rx*math.cos(t), cy+ry*math.sin(t)) for t in np.linspace(0,2*math.pi,n)]
def rrect_pts(cx,cy,w,h,rad,n=10):
    x0,y0,x1,y1=cx-w/2,cy-h/2,cx+w/2,cy+h/2
    r=min(rad,min(w,h)/2); out=[]
    for ox,oy,a0 in [(x1-r,y1-r,0),(x0+r,y1-r,90),(x0+r,y0+r,180),(x1-r,y0+r,270)]:
        for a in np.linspace(math.radians(a0),math.radians(a0+90),n):
            out.append((ox+r*math.cos(a), oy+r*math.sin(a)))
    return out
def catmull_closed(pts, n=22):
    P=pts; out=[]
    for i in range(len(P)):
        p0,p1,p2,p3 = P[(i-1)%len(P)],P[i],P[(i+1)%len(P)],P[(i+2)%len(P)]
        for u in np.linspace(0,1,n,endpoint=False):
            u2,u3=u*u,u*u*u
            out.append((0.5*((2*p1[0])+(-p0[0]+p2[0])*u+(2*p0[0]-5*p1[0]+4*p2[0]-p3[0])*u2+(-p0[0]+3*p1[0]-3*p2[0]+p3[0])*u3),
                        0.5*((2*p1[1])+(-p0[1]+p2[1])*u+(2*p0[1]-5*p1[1]+4*p2[1]-p3[1])*u2+(-p0[1]+3*p1[1]-3*p2[1]+p3[1])*u3)))
    return out
def qbez(p0,p1,c,n=48):
    return [((1-u)**2*p0[0]+2*(1-u)*u*c[0]+u*u*p1[0],
             (1-u)**2*p0[1]+2*(1-u)*u*c[1]+u*u*p1[1]) for u in np.linspace(0,1,n)]
def plume(x0,x1,y0,y1,half,power=0.80,n=80):
    cs,rs=[],[]
    for u in np.linspace(0,1,n):
        cs.append((x0+(x1-x0)*u, y0+(y1-y0)*u))
        rs.append(half*math.sin(math.pi*u)**power)
    return cs,rs

def teardrop(x0,x1,y0,y1,half,power=0.66,n=70):
    cs,rs=[],[]
    for u in np.linspace(0,1,n):
        cs.append((x0+(x1-x0)*u, y0+(y1-y0)*u)); rs.append(max(0.0, half*(1-u)**power))
    return cs,rs

# ------------------------------------------------------------- geometry
BODY_PATH = [(152,664),(170,566),(300,594),(520,634),(700,610),(792,562),
             (840,482),(876,418),(944,398),(1004,452),(1012,542),(962,622),
             (884,666),(828,702),(840,750),(772,794),(420,802),(200,772),(152,724)]
BODY_SPLINE = catmull_closed(BODY_PATH, 26)

STALKS = [(qbez((878,436),(870,196),(818,300)),44),
          (qbez((948,450),(1016,212),(1040,318)),44)]
EYE = [(870,196,58),(1016,212,58)]

JET_R = [(256,566,156,236,62),(256,462,112,92,38)]
JET_BELL = [(178,672),(334,672),(362,786),(150,786)]
JET_INSET=(256,462,68,54,24)

FLAME  = plume(256, 86, 786, 884, 112, power=0.80)
FLAME2 = plume(256,152, 786, 862,  70, power=0.80)

SC,SR = (500,392), 250
SPIRAL=[]
for i in range(720):
    u=i/719
    r=26+(SR-72-26)*u
    th=-math.pi/2+u*2.10*2*math.pi
    SPIRAL.append((SC[0]+math.cos(th)*r, SC[1]+math.sin(th)*r))

# ------------------------------------------------------- fit + rotate
allp=list(BODY_SPLINE)
for cs,rs in (FLAME,FLAME2):
    allp += [(cx-r-T_OUT,cy-r-T_OUT) for (cx,cy),r in zip(cs,rs)]
    allp += [(cx+r+T_OUT,cy+r+T_OUT) for (cx,cy),r in zip(cs,rs)]
for cx,cy,r in EYE: allp += ell_pts(cx,cy,r+T_OUT,r+T_OUT,24)
for st,w in STALKS:
    for x,y in st: allp += [(x-w/2-T_OUT,y-w/2-T_OUT),(x+w/2+T_OUT,y+w/2+T_OUT)]
for e in [JET_R[0],JET_R[1]]: allp += ell_pts(*e[:4],24)
allp += JET_BELL
allp += ell_pts(SC[0],SC[1],SR+T_OUT,SR+T_OUT,24)

ca,sa=math.cos(ROT),math.sin(ROT)
rot=[((x-SUBJ_C[0])*ca-(y-SUBJ_C[1])*sa,(x-SUBJ_C[0])*sa+(y-SUBJ_C[1])*ca) for x,y in allp]
minx=min(p[0] for p in rot); maxx=max(p[0] for p in rot)
miny=min(p[1] for p in rot); maxy=max(p[1] for p in rot)
K=888.0/max(maxx-minx,maxy-miny)
OX=512-(minx+maxx)/2*K; OY=512-(miny+maxy)/2*K
def T(x,y):
    dx,dy=x-SUBJ_C[0],y-SUBJ_C[1]
    return (OX+(dx*ca-dy*sa)*K, OY+(dx*sa+dy*ca)*K)
def L(v): return v*K
def gw(g): return max(1,int(round(L(g)*SS*2)))

def draw_poly(dr, pts, grow=0.0):
    P=[(X(a),X(b)) for a,b in (T(x,y) for x,y in pts)]
    if grow>0: dr.line(P+[P[0]], fill=255, width=gw(grow), joint="curve")
    dr.polygon(P, fill=255)
def draw_disk(dr,cx,cy,r,grow=0.0):
    a,b=T(cx,cy); rr=X(L(r)+L(grow))
    dr.ellipse([X(a)-rr,X(b)-rr,X(a)+rr,X(b)+rr], fill=255)
def mask_of(builder,grow=0.0):
    m=Image.new("L",(W,W),0); builder(ImageDraw.Draw(m),grow); return m

def body_parts(dr,g):
    draw_poly(dr, BODY_SPLINE, g)
    for st,w in STALKS: draw_poly(dr, st, g+w/2)
    for cx,cy,r in EYE: draw_poly(dr, ell_pts(cx,cy,r,r), g)
def jet_parts(dr,g):
    for r in JET_R: draw_poly(dr, rrect_pts(*r), g)
    draw_poly(dr, JET_BELL, g)
def flame_parts(dr,g):
    for (cx,cy),r in zip(*FLAME): draw_disk(dr,cx,cy,r,g)
def shell_parts(dr,g): draw_disk(dr, SC[0], SC[1], SR, g)
def subj_parts(dr,g):
    body_parts(dr,g); jet_parts(dr,g); flame_parts(dr,g); shell_parts(dr,g)

# ------------------------------------------------------------- background
gy,gx=np.mgrid[0:W,0:W].astype(np.float32)
bgx,bgy=T(520,500)
d=np.clip(np.sqrt((gx-X(bgx))**2+(gy-X(bgy))**2)/X(920),0,1)
img=(np.array((120,60,200),np.float32)*(1-d**1.2)[:,:,None]
     + np.array((32,17,56),np.float32)*(d**1.2)[:,:,None])
def blob(cx,cy,r,col,st):
    dd=np.sqrt((gx-X(cx))**2+(gy-X(cy))**2)/X(r)
    return np.array(col,np.float32)*(np.clip(1-dd,0,1)**2*st)[:,:,None]
img=np.clip(img+blob(bgx,bgy,800,(255,152,74),0.42)+blob(140,150,540,MAGENTA,0.38)
                +blob(910,910,640,(48,112,232),0.44),0,255)
base=Image.fromarray(img.astype(np.uint8)).convert("RGBA")

subject_out = mask_of(subj_parts, T_OUT)
subj_a=np.asarray(subject_out,np.uint8)
stars=Image.new("RGBA",(W,W),(0,0,0,0)); sd=ImageDraw.Draw(stars)
placed=0
while placed<9:
    x,y=random.uniform(0.05*W,0.95*W), random.uniform(0.05*W,0.95*W)
    if subj_a[int(y),int(x)]>0: continue
    r=random.uniform(4.5,9.5)*SS
    sd.ellipse([x-r,y-r,x+r,y+r], fill=(255,255,255,random.randint(170,245))); placed+=1
for sx,sy,sz in [(178,196,46),(864,168,38),(158,812,36),(884,832,44)]:
    a0,b0=X(sx),X(sy); aa=sz*SS; bb=aa*0.20
    sd.polygon([(a0,b0-aa),(a0+bb,b0-bb),(a0+aa,b0),(a0+bb,b0+bb),
                (a0,b0+aa),(a0-bb,b0+bb),(a0-aa,b0),(a0-bb,b0-bb)], fill=(255,255,255,242))
base.alpha_composite(stars.filter(ImageFilter.GaussianBlur(2.6*SS)))
base.alpha_composite(stars.filter(ImageFilter.GaussianBlur(0.6*SS)))

# rim glow for silhouette separation
grow_out = mask_of(subj_parts, T_OUT+30)
glow = Image.fromarray(((np.asarray(grow_out)>0)&(np.asarray(subject_out)==0)).astype(np.uint8)*255)
glow = glow.filter(ImageFilter.GaussianBlur(17*SS)).point(lambda v:int(v*0.34))
base.paste((170,150,255), mask=glow)

# ---- body
base.paste(INK, mask=mask_of(body_parts, T_OUT))
body_in = mask_of(body_parts)
ys=np.broadcast_to(np.arange(W,dtype=np.float32)[:,None],(W,W))
y0,y1=T(0,560)[1]*SS, T(0,806)[1]*SS
gg=np.clip((ys-y0)/(y1-y0),0,1)
gg=(0.40*np.clip(gg*1.9,0,1)+0.60*np.clip((gg-0.45)*1.9,0,1))[:,:,None]
body_rgb=np.array(BODYHI,np.float32)*(1-gg)+np.array(BODYLO,np.float32)*gg
body_rgb=np.where(np.broadcast_to((np.asarray(body_in)>0)[:,:,None],(W,W,3)),
                  np.array(BODYHI,np.float32)*(1-gg*0.35)+np.array(BODYLO,np.float32)*(gg*0.35), body_rgb)
# main fill plus a soft lower band
band=np.clip((ys-y1+ -60*SS)/(-60*SS)*0+0,0,1)
base.paste(Image.fromarray(np.clip(body_rgb,0,255).astype(np.uint8),"RGB"), mask=body_in)
band_m = mask_of(lambda dr,g: draw_poly(dr, [ (x, y1/SS + 0) for x in np.linspace(0,1024,2)]) )
# belly shading: darker band along the bottom edge of the body
ye=np.asarray(body_in); rows=np.where(ye.any(1))[0]
yb=rows.max() if len(rows) else W-1
grad = np.clip((ys-(yb-46*SS))/(46*SS),0,1)[:,:,None]
sh = Image.fromarray((np.asarray(body_in)*grad[:,:,0]).astype(np.uint8)).filter(ImageFilter.GaussianBlur(7*SS))
base.paste(BODYLO, mask=sh.point(lambda v:int(v*0.75)))

# ---- flame (in front of the body, under the nozzle)
base.paste(INK, mask=mask_of(flame_parts, T_OUT))
base.paste(ORANGE, mask=mask_of(flame_parts))
base.paste(GOLD, mask=mask_of(lambda dr,g:[draw_disk(dr,c[0],c[1],r,g) for c,r in zip(*FLAME2)]))
base.paste(PALE, mask=mask_of(lambda dr,g:[draw_disk(dr,c[0],c[1],r*0.52,g) for c,r in zip(*FLAME2)]))

# ---- jetpack on top of the body, tucked under the shell
base.paste(INK, mask=mask_of(jet_parts, T_OUT))
base.paste(METAL, mask=mask_of(jet_parts))
base.paste(METALLO, mask=mask_of(lambda dr,g: draw_poly(dr, rrect_pts(*JET_R[1]), g)))
base.paste(METAL, mask=mask_of(lambda dr,g: draw_poly(dr, rrect_pts(*JET_INSET), g)))
base.paste(CYAN, mask=mask_of(lambda dr,g: draw_poly(dr, rrect_pts(256,592,156,34,10), g)))
base.paste(METALLO, mask=mask_of(lambda dr,g: draw_poly(dr, JET_BELL)))

# ---- eyes
for cx,cy,r in EYE:
    base.paste(INK, mask=mask_of(lambda dr,g,cx=cx,cy=cy,r=r: draw_poly(dr, ell_pts(cx,cy,r*1.14,r*1.14))))
    base.paste((255,252,246), mask=mask_of(lambda dr,g,cx=cx,cy=cy,r=r: draw_poly(dr, ell_pts(cx,cy,r*0.96,r*0.96))))
    base.paste(INK, mask=mask_of(lambda dr,g,cx=cx,cy=cy,r=r: draw_poly(dr, ell_pts(cx+r*0.24,cy+r*0.06,r*0.44,r*0.44))))
    hx,hy=T(cx-r*0.14,cy-r*0.34); rr=X(L(r*0.18)); hh=Image.new("L",(W,W),0)
    ImageDraw.Draw(hh).ellipse([X(hx)-rr,X(hy)-rr,X(hx)+rr,X(hy)+rr],fill=255)
    base.paste((255,255,255), mask=hh)

# ---- shell
base.paste(INK, mask=mask_of(shell_parts, T_OUT))
shell_in = mask_of(shell_parts)
p0=T(SC[0]-SR,SC[1]-SR); p1=T(SC[0]+SR,SC[1]+SR)
dg=np.clip(((gx-X(p0[0]))+(gy-X(p0[1])))/((X(p1[0])-X(p0[0]))+(X(p1[1])-X(p0[1]))),0,1)[:,:,None]
c_hi=np.array(SHELLHI,np.float32); c_sh=np.array(SHELLMID,np.float32); c_lo=np.array(SHELLD,np.float32)
grad=np.where(dg<0.5, c_hi+(c_sh-c_hi)*(dg/0.5), c_sh+(c_lo-c_sh)*((dg-0.5)/0.5))
base.paste(Image.fromarray(np.clip(grad,0,255).astype(np.uint8),"RGB"), mask=shell_in)

sp_ink=Image.new("L",(W,W),0); dsi=ImageDraw.Draw(sp_ink)
sp_in =Image.new("L",(W,W),0); dsn=ImageDraw.Draw(sp_in)
n=len(SPIRAL)
for i,(x,y) in enumerate(SPIRAL):
    u=i/(n-1)
    rr=L(30)*1.0
    a,b=T(x,y)
    dsi.ellipse([X(a)-X(rr),X(b)-X(rr),X(a)+X(rr),X(b)+X(rr)],fill=255)
    r2=X(rr)*0.50
    dsn.ellipse([X(a)-r2,X(b)-r2,X(a)+r2,X(b)+r2],fill=255)
base.paste(INK, mask=sp_ink)
base.paste(SHELLHI, mask=sp_in)

# ------------------------------------------------------------- vignette
vig=np.clip(np.sqrt((gx-X(512))**2+(gy-X(512))**2)/X(780),0,1)
a2=np.asarray(base.convert("RGB"),np.float32)*(1-0.30*vig**2)[:,:,None]
icon=Image.fromarray(np.clip(a2,0,255).astype(np.uint8),"RGB").resize((S,S),Image.LANCZOS)
out="/Users/baai/Project/snail_mail/SnailMail/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
icon.save(out,"PNG"); print("wrote",out,icon.size)
