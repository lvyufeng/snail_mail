#!/usr/bin/env python3
"""Bake the retail build's 3D objects down to flat billboards.

The 2005 game draws its snail, salt shakers, turret pillars, roadside signs and
the post office from small DirectX `.x` meshes (the archive's `X/*.x2` blobs)
with a toon-shaded software pipeline. iOS's SpriteKit has no such pipeline, so
this module rasterises each mesh once, off-line, from the same viewing angle the
game's chase camera uses, and writes a transparent PNG. The app then billboards
that PNG exactly like the original billboards its sprites.

The rasteriser is deliberately simple: orthographic projection, painter's
algorithm, flat per-face colour sampled from the mesh's own texture map and a
single toon light. That reproduces the flat, unlit look of the source art
without needing a real GPU.

Usage (normally driven by `tools/import_art.py`):
    python3 tools/bake_meshes.py --x /tmp/snail/X --tex /tmp/retail/Art/Textures \
        --out /tmp/retail/Art/Baked
"""

import argparse
import math
import os
import re


def parse(path):
    """Read one ASCII .x mesh into (texture name, uv list, vertices, faces)."""
    text = open(path, errors="replace").read()
    tex = None
    m = re.search(r'TextureFilename\s*\{\s*"([^"]+)"', text)
    if m:
        tex = m.group(1)

    tc = re.search(r"MeshTextureCoords\s*\{\s*(\d+);(.*?)\}", text, re.S)
    n = int(tc.group(1))
    nums = [float(x) for x in
            re.findall(r"-?\d*\.?\d+(?:[eE][-+]?\d+)?", tc.group(2))]
    uvs = [(nums[i * 2], nums[i * 2 + 1]) for i in range(n)]

    mesh = re.search(r"Mesh\s+\S+\s*\{\s*(\d+);(.*)", text, re.S)
    nv = int(mesh.group(1))
    rest = mesh.group(2)
    vnums = [float(x) for x in
             re.findall(r"-?\d*\.?\d+(?:[eE][-+]?\d+)?", rest)]
    verts = [(vnums[i * 3], vnums[i * 3 + 1], vnums[i * 3 + 2])
             for i in range(nv)]

    fm = re.search(r"\n\s*(\d+);\s*\n(.*)", rest, re.S)
    nf = int(fm.group(1))
    faces = []
    for line in fm.group(2).split("\n"):
        mm = re.match(r"(\d+);([\d,\s]+);", line.strip())
        if not mm:
            continue
        faces.append([int(x) for x in mm.group(2).split(",") if x.strip()])
    return tex, uvs, verts, faces[:nf]


def _find_texture(tex, texdir):
    from PIL import Image
    want = os.path.splitext(os.path.basename(tex))[0].lower()
    for fn in os.listdir(texdir):
        if os.path.splitext(fn)[0].lower() == want:
            return Image.open(os.path.join(texdir, fn)).convert("RGBA")
    return None


def render(path, texdir, size=256, yaw=0.0, pitch=0.0, roll=0.0,
           backface=0.55, light=(0.35, -0.45, -0.82), oversample=3, zoom=1.04,
           tex_override=None, frame=None):
    """Rasterise one mesh to an RGBA image, framed to its own bounds.

    Orthographic projection, a per-pixel depth buffer for hidden-surface removal
    and barycentric texture interpolation, with one toon light baked in per face
    so the result keeps the flat, cel-shaded look of the source art.

    `frame` is an optional `(cx, cy, span)` window to render inside instead of
    the mesh's own bounds. Every pose of one clip must share a window or the
    billboard drifts as the frames swap, so the animation table below passes
    `SNAIL_FRAME` for all of Turbo's poses.
    """
    import numpy as np
    from PIL import Image

    tex, uvs, verts, faces = parse(path)
    if tex_override:
        tex = tex_override
    timg = _find_texture(tex, texdir) if tex else None
    tarr = np.asarray(timg, dtype=np.float32) if timg is not None else None
    th, tw = (tarr.shape[:2] if tarr is not None else (0, 0))

    def rot(p):
        x, y, z = p
        cy, sy = math.cos(yaw), math.sin(yaw)
        x, z = cy * x + sy * z, -sy * x + cy * z
        cp, sp = math.cos(pitch), math.sin(pitch)
        y, z = cp * y - sp * z, sp * y + cp * z
        cr, sr = math.cos(roll), math.sin(roll)
        x, y = cr * x - sr * y, sr * x + cr * y
        return (x, y, z)

    rv = np.array([rot(v) for v in verts], dtype=np.float64)
    if frame is not None:
        centre = np.array(frame[:2], dtype=np.float64)
        span = float(frame[2])
    else:
        mn = rv[:, :2].min(axis=0)
        mx = rv[:, :2].max(axis=0)
        centre = (mn + mx) / 2
        span = max(mx[0] - mn[0], mx[1] - mn[1]) or 1.0
    ss = size * oversample
    scale = ss / span * zoom

    # screen space: x right, y down, z = camera depth (larger = nearer)
    sx = ss / 2 + (rv[:, 0] - centre[0]) * scale
    sy = ss / 2 - (rv[:, 1] - centre[1]) * scale
    sz = rv[:, 2]

    colour = np.zeros((ss, ss, 3), dtype=np.float32)
    alpha = np.zeros((ss, ss), dtype=np.float32)
    zbuf = np.full((ss, ss), -1e18, dtype=np.float64)

    for f in faces:
        if len(f) < 3:
            continue
        s = _shade(rv, f, light, backface)
        for k in range(1, len(f) - 1):
            _raster((f[0], f[k], f[k + 1]), sx, sy, sz, uvs, colour, alpha,
                    zbuf, s, tarr, tw, th, ss)

    out = np.zeros((ss, ss, 4), dtype=np.float32)
    out[..., :3] = colour
    out[..., 3] = alpha * 255.0
    img = Image.fromarray(np.clip(out, 0, 255).astype("uint8"), "RGBA")
    return img.resize((size, size), Image.LANCZOS)


def _shade(rv, f, light, backface):
    """One toon-lighting factor for a face, from its geometric normal."""
    import numpy as np
    a, b, c = rv[f[0]], rv[f[1]], rv[f[2]]
    n = np.cross(b - a, c - a)
    ln = np.linalg.norm(n) or 1.0
    n = n / ln
    lam = abs(float(np.dot(n, light)))
    s = max(0.48, min(1.0, 0.55 + 0.6 * lam))
    if n[2] > 0:
        s *= backface
    return s


def _raster(tri, sx, sy, sz, uvs, colour, alpha, zbuf, shade, tarr, tw, th, ss):
    """Fill one triangle, interpolating texture UVs under a depth test."""
    import numpy as np

    xs = np.array([sx[i] for i in tri])
    ys = np.array([sy[i] for i in tri])
    zs = np.array([sz[i] for i in tri])
    x0, x1 = int(max(0, math.floor(xs.min()))), int(min(ss - 1, math.ceil(xs.max())))
    y0, y1 = int(max(0, math.floor(ys.min()))), int(min(ss - 1, math.ceil(ys.max())))
    if x1 < x0 or y1 < y0:
        return

    area = (xs[1] - xs[0]) * (ys[2] - ys[0]) - (xs[2] - xs[0]) * (ys[1] - ys[0])
    if abs(area) < 1e-9:
        return

    px, py = np.meshgrid(np.arange(x0, x1 + 1) + 0.5,
                         np.arange(y0, y1 + 1) + 0.5)
    w0 = ((xs[1] - px) * (ys[2] - py) - (xs[2] - px) * (ys[1] - py)) / area
    w1 = ((xs[2] - px) * (ys[0] - py) - (xs[0] - px) * (ys[2] - py)) / area
    w2 = 1.0 - w0 - w1
    inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
    if not inside.any():
        return

    z = w0 * zs[0] + w1 * zs[1] + w2 * zs[2]
    sub_z = zbuf[y0:y1 + 1, x0:x1 + 1]
    mask = inside & (z > sub_z)
    if not mask.any():
        return

    if tarr is not None:
        uu = w0 * uvs[tri[0]][0] + w1 * uvs[tri[1]][0] + w2 * uvs[tri[2]][0]
        vv = w0 * uvs[tri[0]][1] + w1 * uvs[tri[1]][1] + w2 * uvs[tri[2]][1]
        tx = np.clip((uu * (tw - 1)).round().astype(np.int32), 0, tw - 1)
        ty = np.clip(((1.0 - vv) * (th - 1)).round().astype(np.int32), 0, th - 1)
        texel = tarr[ty, tx]
        tex_a = texel[..., 3] / 255.0
    else:
        texel = np.zeros(px.shape + (4,), dtype=np.float32)
        texel[..., :3] = 200.0
        tex_a = np.ones(px.shape, dtype=np.float32)

    m = mask & (tex_a > 0.02)
    if not m.any():
        return
    sub_z[m] = z[m]
    colour[y0:y1 + 1, x0:x1 + 1][m] = texel[..., :3][m] * shade
    alpha[y0:y1 + 1, x0:x1 + 1][m] = tex_a[m]



def trim(img, path, margin=2):
    """Crop to the opaque bounds (keeping a little air) and save."""
    bbox = img.split()[3].getbbox()
    if bbox:
        bbox = (max(0, bbox[0] - margin), max(0, bbox[1] - margin),
                min(img.width, bbox[2] + margin), min(img.height, bbox[3] + margin))
        img = img.crop(bbox)
    img.save(path)


# The one window all eight pillars are rendered in: `(centre x, centre y,
# span)` in projected model units, with the model drawn at unit zoom so the
# canvas is exactly this many units across. Every pillar spans y -1.000...7.273
# and differs only in half-width 0.520...3.999, so this window holds the tallest
# and widest of them with a little air while leaving the tier-1 post the same
# pixel height the trimmed `pillar.png` billboard used to carry.
PILLAR_FRAME = (0.0, 3.0455, 8.6)

# model file -> (output name, view). The angles were chosen by eye so each
# object shows the face the chase camera sees: signs and the post office look
# straight at the player, the snail and props are tipped to match the road's
# downward view.
BAKE = [
    ("turbo-base-000.x", "snail", dict(yaw=0.0, pitch=-0.34)),
    ("turbo-damaged-000.x", "snail-damage", dict(yaw=0.0, pitch=-0.34)),
    ("turbo-base-000.x", "snail-invincible", dict(yaw=0.0, pitch=-0.34)),
    ("salt.x", "salt", dict(yaw=-0.5, pitch=-0.5)),
    # The eight pillar meshes the build ships (`X/PILLAR1..8.X2`) are the same
    # post modelled at eight widths, which is how a course turns a slim turret
    # into one big enough to close the road. They are drawn inside one shared
    # window so the same node width keeps every tier the same height and lets
    # each tier's own model decide how far it reaches across the road.
    ("pillar1.x", "pillar-1", dict(yaw=0.0, pitch=-0.18, zoom=1.0, frame=PILLAR_FRAME)),
    ("pillar2.x", "pillar-2", dict(yaw=0.0, pitch=-0.18, zoom=1.0, frame=PILLAR_FRAME)),
    ("pillar3.x", "pillar-3", dict(yaw=0.0, pitch=-0.18, zoom=1.0, frame=PILLAR_FRAME)),
    ("pillar4.x", "pillar-4", dict(yaw=0.0, pitch=-0.18, zoom=1.0, frame=PILLAR_FRAME)),
    ("pillar5.x", "pillar-5", dict(yaw=0.0, pitch=-0.18, zoom=1.0, frame=PILLAR_FRAME)),
    ("pillar6.x", "pillar-6", dict(yaw=0.0, pitch=-0.18, zoom=1.0, frame=PILLAR_FRAME)),
    ("pillar7.x", "pillar-7", dict(yaw=0.0, pitch=-0.18, zoom=1.0, frame=PILLAR_FRAME)),
    ("pillar8.x", "pillar-8", dict(yaw=0.0, pitch=-0.18, zoom=1.0, frame=PILLAR_FRAME)),
    ("tramp.x", "tramp", dict(yaw=0.0, pitch=-0.55)),
    ("postofficestop.x", "postoffice", dict(yaw=0.0, pitch=-0.12)),
    ("signbang.x", "signbang", dict(yaw=0.0, pitch=-0.1)),
    ("signconstruction.x", "signconstruction", dict(yaw=0.0, pitch=-0.1)),
    ("signstop.x", "signstop", dict(yaw=0.0, pitch=-0.1)),
    ("rocket-base-000.x", "rocket", dict(yaw=0.0, pitch=0.0)),
]

# Baked output name -> the texture the mesh should use instead of its own
# (the invincible snail is the same geometry with the gold texture).
OVERRIDE_TEX = {"snail-invincible": "snail-turbo-invincible"}

# Turbo's animation clips, exactly as `X/ANIMATION.TXT` lists them: the model
# stem, the frame numbers the clip plays, and the texture override for the one
# clip whose frames wear another texture (the invincible pose).
SNAIL_CLIPS = [
    ("snail-base", "turbo-base", [0], None),
    ("snail-invincible", "turbo-base", [0], "snail-turbo-invincible"),
    ("snail-move", "turbo-move", [0, 1], None),
    ("snail-bobalong", "turbo-bobalong", [0, 1, 2, 3, 4], None),
    ("snail-damaged", "turbo-damaged", [0, 1], None),
    ("snail-fall", "turbo-fall", [0, 1], None),
    ("snail-lookbackleft", "turbo-lookbackleft", [0, 1, 2, 3, 4], None),
    ("snail-lookbackright", "turbo-lookbackright", [0, 1, 2, 3, 4], None),
    ("snail-talk", "turbo-talk", list(range(13)), None),
    ("snail-skidstop", "turbo-skidstop",
     [0, 1, 2, 3, 4, 5, 8, 10, 12, 13, 14, 15, 16, 17], None),
    ("snail-intoshell", "turbo-intoshell", list(range(8)), None),
]

# The one window every Turbo pose is rendered inside: `(centre x, centre y,
# span)` in the projected model space the `pitch` above produces. The poses
# range over x -0.68...0.74, y -0.66...0.99, so this window holds them all with
# a little air. Framing each pose to its own bounds instead would rescale and
# recentre every frame, and the billboard would jitter as the clip played.
# The poses are rendered at unit zoom (see `bake_clips`), so the 1.76-unit
# window is exactly 1.76 units of canvas: the widest pose covers 81 % of it and
# the tallest leaves ~7 % of bare canvas top and bottom.
SNAIL_FRAME = (0.034, 0.165, 1.76)

# The animation frames are stored whole, not trimmed, so that every pose lines
# up on the same canvas; 384px over 1.76 units is 218 pixels per model unit,
# close to the 226 the single trimmed `snail.png` billboard already carried.
SNAIL_SIZE = 384


# The gear the retail build bolts onto Turbo, in the order the build's own
# `X/_ANIMATION.TXT` lists it. Each mesh is modelled in Turbo's own space
# already — the blaster sits on his shell top, the jetpack hangs off his sides —
# so rendering it through the same camera and the same `SNAIL_FRAME` window as
# his poses puts it exactly where the original's 3D pipeline drew it, and the
# app can lay the result straight over his billboard.
#
#   tier      the weapon the pickup ladder climbs through
#   jetpack   the pack, and the plume it burns
#   aura      the shell of light the invincibility power-up wraps him in
TURBO_GEAR = [
    ("snail-blaster-top", "blastertop-base-000.x"),
    ("snail-blaster-left", "blasterleft-base-000.x"),
    ("snail-blaster-right", "blasterright-base-000.x"),
    ("snail-laser-left", "laserleft-base-000.x"),
    ("snail-laser-right", "laserright-base-000.x"),
    ("snail-rocket", "rocketlauncher-base-000.x"),
    ("snail-jetpack", "jetpack-base-000.x"),
]

# Gear that cycles rather than holds still, as `(output stem, model stem, frame
# numbers, texture override)`. The plume and the aura loop for as long as they
# are on screen, so the app plays them the same way it plays Turbo's clips.
TURBO_GEAR_CLIPS = [
    ("snail-jetpack-thrust", "jetpackthrust-base", [0, 1, 2], None),
    ("snail-aura", "invincible-base", [0, 1, 2, 3], None),
]


def bake_gear(x_dir, tex_dir, out_dir, size=SNAIL_SIZE, log=print):
    """Rasterise the meshes the build straps onto Turbo.

    They share Turbo's own window and unit zoom, so every piece lands on the
    same canvas his poses use and overlays him without a scrap of guesswork
    about where a weapon or a jetpack belongs.
    """
    os.makedirs(out_dir, exist_ok=True)
    written = 0
    for name, model in TURBO_GEAR:
        src = os.path.join(x_dir, model)
        if not os.path.exists(src):
            log("bake: missing %s" % model)
            continue
        try:
            img = render(src, tex_dir, size=size, yaw=0.0, pitch=-0.34,
                         zoom=1.0, frame=SNAIL_FRAME)
            img.save(os.path.join(out_dir, name + ".png"))
            written += 1
        except Exception as exc:                      # noqa: BLE001
            log("bake: %s failed: %s" % (model, exc))
    for stem, model, nums, tc in TURBO_GEAR_CLIPS:
        for n in nums:
            src = os.path.join(x_dir, "%s-%03d.x" % (model, n))
            if not os.path.exists(src):
                log("bake: %s-%03d.x missing, skipping" % (model, n))
                continue
            dst = os.path.join(out_dir, "%s-%03d.png" % (stem, n))
            try:
                img = render(src, tex_dir, size=size, yaw=0.0, pitch=-0.34,
                             zoom=1.0, frame=SNAIL_FRAME, tex_override=tc)
                img.save(dst)
                written += 1
            except Exception as exc:                  # noqa: BLE001
                log("bake: %s-%03d.x failed: %s" % (model, n, exc))
    return written


def bake_all(x_dir, tex_dir, out_dir, size=256, log=print):
    os.makedirs(out_dir, exist_ok=True)
    written = 0
    for model, name, view in BAKE:
        src = os.path.join(x_dir, model)
        if not os.path.exists(src):
            log("bake: missing %s" % model)
            continue
        try:
            img = render(src, tex_dir, size=size,
                         tex_override=OVERRIDE_TEX.get(name), **view)
            dst = os.path.join(out_dir, name + ".png")
            # Anything drawn inside an explicit `frame` is saved whole: the
            # window is what gives the picture its scale, so cropping it to the
            # model's own bounds would undo the shared framing.
            if view.get("frame") is None:
                trim(img, dst)
            else:
                img.save(dst)
            written += 1
        except Exception as exc:                      # noqa: BLE001
            log("bake: %s failed: %s" % (model, exc))
    written += bake_clips(x_dir, tex_dir, out_dir, log=log)
    written += bake_gear(x_dir, tex_dir, out_dir, log=log)
    return written


def bake_clips(x_dir, tex_dir, out_dir, size=SNAIL_SIZE, log=print):
    """Rasterise Turbo's animation poses, whole and untrimmed.

    Each pose is drawn inside the one shared `SNAIL_FRAME` window and saved as
    the full square canvas, so every frame of every clip agrees on where the
    snail sits. The app swaps these at the clip's own rate; trimming would
    rescale and recentre each pose and make the animation crawl around the
    screen.
    """
    os.makedirs(out_dir, exist_ok=True)
    written = 0
    for stem, model, nums, tc in SNAIL_CLIPS:
        for n in nums:
            src = os.path.join(x_dir, "%s-%03d.x" % (model, n))
            if not os.path.exists(src):
                log("bake: %s-%03d.x missing, skipping" % (model, n))
                continue
            dst = os.path.join(out_dir, "%s-%03d.png" % (stem, n))
            try:
                # Unit zoom: the shared window is then a fixed number of model
                # units across, so the app can size the billboard from the
                # window alone instead of from whatever the strip happened to
                # frame to.
                img = render(src, tex_dir, size=size, yaw=0.0, pitch=-0.34,
                             zoom=1.0, frame=SNAIL_FRAME, tex_override=tc)
                img.save(dst)
                written += 1
            except Exception as exc:                  # noqa: BLE001
                log("bake: %s-%03d.x failed: %s" % (model, n, exc))
    return written


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--x", required=True, help="folder holding the *.x meshes")
    ap.add_argument("--tex", required=True, help="folder holding the decoded PNG textures")
    ap.add_argument("--out", required=True, help="where to write the baked billboards")
    ap.add_argument("--size", type=int, default=256)
    args = ap.parse_args()
    n = bake_all(args.x, args.tex, args.out, size=args.size)
    print("baked %d billboards to %s" % (n, args.out))


if __name__ == "__main__":
    main()
