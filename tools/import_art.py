#!/usr/bin/env python3
"""Extract the retail game's own artwork and audio for the pixel-level remake.

The installer's `SnailMail.dat` is not only level scripts: alongside them sit
the 2005 build's textures (`*.TGA`), its models (ASCII DirectX `.x` files,
which is what the `X/*.x2` blobs really are) and its audio (Ogg Vorbis music,
effects and voice-over). This tool decodes that archive and writes the two
formats iOS reads natively:

    textures   TGA  -> PNG
    audio      Ogg  -> M4A (AAC), through macOS's `afconvert`
    models     .x2  -> `.x`, copied as they are (plain text)
    lettering  `FONT-MENU-HOVER.TGA` -> `SnailMailRetail.ttf`, through
               `make_font.py`, which rebuilds the shipped bitmap strip as a
               face iOS can register

Blobs are routed by their own extension rather than the folder they sit in,
because the archive mixes both kinds in the same place — `X/` holds the snail's
texture next to its meshes, and `SPRITES/` holds a `JETPACK.TXT` script next to
the `JETPACK000.TGA` frames.

The output lands in `SnailMail/Resources/Retail`, which is deliberately
untracked: it is the retail build's own content, so it stays on the machine
that owns a copy of the game instead of going into the repository. Run this
once after cloning, against your own installer, and the app picks the assets
up at launch (falling back to the procedural art when they are absent).

Usage:
    python3 tools/import_art.py path/to/蜗牛竞速.zip
    python3 tools/import_art.py path/to/SnailMail.dat --out /tmp/retail
"""

import argparse
import io
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import import_tracks as it  # noqa: E402  (shares the archive decoder)
import bake_meshes as bm  # noqa: E402  (turns the .x models into billboards)
import make_font as mf  # noqa: E402  (rebuilds the menu strip as a font)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "SnailMail", "Resources", "Retail")


def target(name):
    """Map one archive entry to (relative destination, kind), or None to skip.

    Only the three payload kinds are imported; the `*.TXT` scripts next to them
    are configuration, and `import_tracks.py` already compiles those into Swift.
    """
    parts = name.split("/")
    folder = parts[0].lower()
    stem = os.path.splitext(os.path.basename(name))[0].lower()
    ext = os.path.splitext(name)[1].lower()

    if ext == ".tga":
        if folder == "sprites":
            sub = "Art/Sprites"
        elif folder == "backgrounds":
            sub = "Art/Backgrounds"
        elif folder == "galaxy":
            sub = "Art/Galaxy"
        elif folder == "x":
            sub = "Art/Textures"
        elif folder == "objects":
            # OBJECTS nests one folder per model, and two of them (`LAZER`,
            # `VAPOURLAZER`) share a base name, so keep the folder in the name.
            group = parts[1].lower() if len(parts) > 2 else ""
            sub = "Art/Objects"
            if group and group not in ("world00", "universe"):
                stem = group + "_" + stem
        else:
            return None
        return sub + "/" + stem + ".png", "png"

    if ext == ".x2":
        return "Art/Models/" + stem + ".x", "raw"

    if ext == ".ogg":
        sub = {"music": "Audio/Music", "sfx2": "Audio/Sfx",
               "voice": "Audio/Voice"}.get(folder)
        return (sub + "/" + stem + ".m4a", "audio") if sub else None

    return None


def tga_to_png(data, path):
    """Re-encode one TGA blob as PNG (PIL reads every variant the game uses)."""
    from PIL import Image
    with Image.open(io.BytesIO(data)) as im:
        im.convert("RGBA").save(path, optimize=True)


def ogg_to_m4a(data, path):
    """Transcode one Ogg Vorbis blob to AAC-in-MP4 with macOS's own decoder."""
    afconvert = shutil.which("afconvert")
    if afconvert is None:
        return False
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "in.ogg")
        with open(src, "wb") as fh:
            fh.write(data)
        # AAC-in-CAF trips the converter's own property check ("Couldn't set
        # audio converter property ('!dat')"), and so does an explicit `-b`
        # bitrate; AAC-in-MP4 at VBR quality 127 round-trips cleanly and
        # AVAudioPlayer reads it just as well.
        cmd = [afconvert, "-f", "m4af", "-d", "aac", "-q", "127", src, path]
        done = subprocess.run(cmd, capture_output=True)
        return done.returncode == 0 and os.path.exists(path)


def write_splash_logo(out):
    """Lift the SNAIL MAIL lockup off the installer's loading screen.

    `SPRITES/LOADING.TGA` is the build's whole loading screen: the title art
    behind a progress bar, with the game's logo painted across the middle of
    it. The remake wants the lockup by itself, so key it out on the one thing
    the backdrop never is — its green channel stays under the purple-to-red
    ramp the screen is drawn in, while the lettering over it is white and
    cyan. Returns the path written, or None when the loader was not imported.
    """
    from PIL import Image
    import numpy as np

    src = os.path.join(out, "Art", "Sprites", "loading.png")
    if not os.path.exists(src):
        return None
    rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.float64)
    red, green, blue = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    key = np.maximum(green - 52, (blue - red) - 24)
    alpha = np.clip((key - 6) / 26, 0, 1)
    alpha[215:, :] = 0                       # the loader's own bar and label
    ys, xs = np.where(alpha > 0.15)
    if not len(xs):
        return None
    cut = Image.fromarray(np.dstack([rgb, alpha * 255]).astype(np.uint8))
    cut = cut.crop((int(xs.min()), int(ys.min()),
                    int(xs.max()) + 1, int(ys.max()) + 1))
    dest = os.path.join(out, "Art", "Baked", "splashlogo.png")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    cut.save(dest, optimize=True)
    return dest


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("archive", help="SnailMail.dat, or the installer .zip holding it")
    ap.add_argument("--out", default=OUT, help="where to write the assets")
    args = ap.parse_args()

    files = it.carve(it.load_archive(args.archive))
    written = skipped = 0
    audio_ok = shutil.which("afconvert") is not None

    for name, data in sorted(files.items()):
        dest = target(name)
        if dest is None:
            continue
        rel, kind = dest
        path = os.path.join(args.out, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        try:
            if kind == "png":
                tga_to_png(data, path)
            elif kind == "audio":
                if not audio_ok or not ogg_to_m4a(data, path):
                    skipped += 1
                    continue
            else:
                with open(path, "wb") as fh:
                    fh.write(data)
        except Exception as exc:                      # noqa: BLE001
            print("skipped %s: %s" % (name, exc), file=sys.stderr)
            skipped += 1
            continue
        written += 1

    print("wrote %d assets to %s (%d skipped)" % (written, args.out, skipped))
    if not audio_ok:
        print("warning: afconvert not found, no audio written", file=sys.stderr)

    # The meshes are useless to SpriteKit as they are, so rasterise each one to
    # the flat billboard the app actually draws. This needs the `.x` files and
    # the decoded textures that were just written above.
    baked = bm.bake_all(os.path.join(args.out, "Art", "Models"),
                        os.path.join(args.out, "Art", "Textures"),
                        os.path.join(args.out, "Art", "Baked"), log=lambda m: None)
    print("baked %d billboards" % baked)

    # The menu lettering is the strip the 3-D font is not; rebuild it as a face
    # the app can register, so labels can be set in the original letterforms.
    strip = os.path.join(args.out, "Art", "Objects", "font_font-menu-hover.png")
    if os.path.exists(strip):
        face = os.path.join(args.out, "Art", "Objects", "SnailMailRetail.ttf")
        print("wrote %d glyphs to %s" % (mf.build(strip, face), face))

    # The loading screen's own title lockup, lifted off the backdrop so the
    # launch splash can wear it on any screen.
    logo = write_splash_logo(args.out)
    if logo:
        print("wrote splash logo to %s" % logo)


if __name__ == "__main__":
    main()
