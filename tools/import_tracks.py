#!/usr/bin/env python3
"""Regenerate SnailMail/Sources/Game/TrackData.swift from the retail game data.

The retail installer carries `SnailMail.dat`, a plain archive of level and
segment scripts XOR-obfuscated with a 256-byte repeating key. This tool undoes
that, reads the level routes (`LEVELS/*.txt`) and the eight-cell-per-row track
pieces (`SEGMENTS/*.txt`), and writes the Swift tables the game plays back.
Only configuration data is read; no artwork, textures or audio is touched.

Usage:
    python3 tools/import_tracks.py path/to/SnailMail.dat
    python3 tools/import_tracks.py path/to/蜗牛竞速.zip      # .dat inside the zip
"""

import argparse
import io
import os
import re
import struct
import sys
import textwrap
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "SnailMail", "Sources", "Game", "TrackData.swift")

# The obfuscation key.  The installer XORs the archive with a fixed 256-byte
# keystream that repeats for the whole file; the table below was recovered by
# comparing the installer blob against a known-good decode and then verified to
# reproduce it byte-for-byte.  It has a clear internal structure (every byte is
# even, and K[i + 128] == K[i] ^ 0x80), so it is a real generated key rather
# than random padding, but the generator is not worth reverse-engineering when
# the recovered table is this small and stable.
_KEY_HEX = """
00 02 02 00 1c 16 36 24 58 4a 7a 58 b4 8e ee cc
30 12 72 50 ac 86 a6 54 08 3a ea 88 44 1e de 9c
60 22 e2 a0 7c 36 d6 84 38 ea 9a b8 14 6e ce 2c
90 f2 52 b0 0c 66 c6 74 e8 1a 8a 28 a4 3e be 3c
c0 42 c2 40 dc 56 f6 64 98 0a ba 18 74 ce 2e 8c
f0 52 b2 10 6c c6 e6 94 48 fa aa 48 04 de 9e 5c
20 e2 a2 60 3c f6 96 44 78 2a da f8 d4 2e 0e 6c
50 b2 92 f0 cc 26 06 34 28 5a 4a 68 64 7e 7e 7c
80 82 82 80 9c 96 b6 a4 d8 ca fa d8 34 0e 6e 4c
b0 92 f2 d0 2c 06 26 d4 88 ba 6a 08 c4 9e 5e 1c
e0 a2 62 20 fc b6 56 04 b8 6a 1a 38 94 ee 4e ac
10 72 d2 30 8c e6 46 f4 68 9a 0a a8 24 be 3e bc
40 c2 42 c0 5c d6 76 e4 18 8a 3a 98 f4 4e ae 0c
70 d2 32 90 ec 46 66 14 c8 7a 2a c8 84 5e 1e dc
a0 62 22 e0 bc 76 16 c4 f8 aa 5a 78 54 ae 8e ec
d0 32 12 70 4c a6 86 b4 a8 da ca e8 e4 fe fe fc
"""
KEY = bytes.fromhex(_KEY_HEX)

# A `Ring=` row draws a pickup ring, but the glyph sitting in the grid
# (`>`, `<`, `{`, `}`, `(`, `)`, `R`) only describes how it is oriented on the
# road. The attribute names the effect, so fold every glyph to a token the
# renderer can act on: power-up, slow, blast, a plain scoring ring, and a
# decorative arch that does nothing.
RING_GLYPHS = set("><{}()R")
RING = {"powerup": "+", "slow": "~", "explode": ">", "explosive": ">",
        "normal": "!", "none": "o"}

def deobfuscate(data):
    return bytes(b ^ KEY[i % 256] for i, b in enumerate(data))


def tutorial_message(raw):
    """Turn a retail `Message=` string into the text the remake shows.

    `>` is the retail hard line break: the script wraps each sentence onto
    three lines by hand rather than letting the banner lay it out, and the
    spaces the wrap leaves behind are tidied off the fronts of the lines.

    The inline icon glyphs the script drops into the prose (`{ } ~ [ ] ^ _ ;`)
    are kept verbatim: the retail build draws the sprite the glyph names inline
    with the words, so the banner draws the same icon in the same place.
    """
    text = raw.replace(">", "\n")
    return "\n".join(line.strip() for line in text.split("\n")).strip()


def load_archive(path):
    """Return the deobfuscated bytes of SnailMail.dat, from a raw file or a zip."""
    with open(path, "rb") as fh:
        head = fh.read(4)
        fh.seek(0)
        blob = fh.read()
    if head[:2] == b"PK":
        with zipfile.ZipFile(io.BytesIO(blob)) as zf:
            name = next((n for n in zf.namelist()
                         if os.path.basename(n).lower() == "snailmail.dat"), None)
            if name is None:
                sys.exit("no SnailMail.dat inside %s" % path)
            blob = zf.read(name)
    return deobfuscate(blob)


def carve(blob):
    """Split the archive into its named blobs.

    The archive opens with a u32 count, then one 12-byte record per file —
    (name offset, data offset, size) — followed by a NUL-separated name table.
    """
    count = struct.unpack_from("<I", blob, 0)[0]
    files = {}
    for i in range(count):
        name_off, data_off, size = struct.unpack_from("<III", blob, 4 + i * 12)
        end = blob.find(b"\x00", name_off, name_off + 256)
        if end < 0:
            end = min(name_off + 256, len(blob))
        name = blob[name_off:end].decode("latin-1").replace("\\", "/")
        files[name] = blob[data_off:data_off + size]
    return files


def by_folder(files, folder, suffix):
    """Map lower-cased base name -> text for `folder/*` blobs ending in `suffix`."""
    out = {}
    for name, data in files.items():
        upper = name.upper()
        if upper.startswith(folder.upper() + "/") and upper.endswith(suffix.upper()):
            out[os.path.basename(name).lower()] = data.decode("latin-1")
    return out


def parse_level(txt):
    txt = re.sub(r"/\*.*?\*/", "", txt, flags=re.S)
    segs, script, voices = [], [], []
    body = re.search(r"Segments Begin:(.*?)Segments End:", txt, flags=re.S)
    if body:
        for line in body.group(1).splitlines():
            line = line.strip()
            if not line:
                continue
            m = re.match(r"^(.*?\.txt)\s*(.*)$", line, re.I)
            if m:
                name = os.path.basename(m.group(1))
                attrs = dict(re.findall(r"(\w+)=(-?[\d.]+)", m.group(2)))
                segs.append((name, attrs))
                # The tutorial scripts an on-screen line per pool entry; every
                # other level leaves the list empty.  A line also names the
                # voice-over that reads it (`Sample="Voice/tutN.ogg"`), which
                # the blank entries leave out.
                msg = re.search(r'Message="([^"]*)"', m.group(2))
                script.append(tutorial_message(msg.group(1)) if msg else "")
                sample = re.search(r'Sample="Voice/(\w+)\.ogg"', m.group(2), re.I)
                voices.append(sample.group(1).lower() if sample else None)
    first = re.search(r"First:.*?\n\s*(.*?\.txt)", txt, flags=re.S)
    last = re.search(r"Last:.*?\n\s*(.*?\.txt)", txt, flags=re.S)
    return (os.path.basename(first.group(1)) if first else "Start.txt",
            segs,
            os.path.basename(last.group(1)) if last else "Finish.txt",
            script,
            voices,
            parse_briefing(txt))


def parse_briefing(txt):
    """The `GalaxyText:` blurb a level file carries.

    The retail build prints this paragraph, the snail's own log entry or an
    IPS (Intergalactic Postal Service) notice, over the route before a race
    starts; its "IPS WARNING" lines warn about gaps, ramps and corkscrews. The
    block sits in braces and wraps across lines, so the wrapped lines are
    joined back into one paragraph.
    """
    m = re.search(r"GalaxyText\s*:\s*\{(.*?)\}", txt, flags=re.S)
    if not m:
        return ""
    lines = [ln.strip() for ln in m.group(1).splitlines()]
    return "\n".join(ln for ln in lines if ln)


def parse_slides(txt):
    """Split an intro/credits script into the text screens it shows.

    The script marks a picture insert as `*texturename.tga(Width,Height)`; only
    the words are kept, since no artwork is bundled. A blank line separates one
    screen from the next.
    """
    body = txt.split("Text Start:", 1)[-1].split("Text End:", 1)[0]
    body = re.sub(r"^\s*Duration\s*:.*$", "", body, flags=re.M)
    body = re.sub(r"\*[^\s]*\.tga\s*\([^)]*\)", "", body)
    slides, current = [], []
    for line in body.splitlines():
        line = line.strip()
        if line:
            current.append(line)
        elif current:
            slides.append("\n".join(current))
            current = []
    if current:
        slides.append("\n".join(current))
    return slides


def parse_segment(txt):
    """Return (grid, paths, jetpack_off, signs, parcels, bands, no_fall).

    `grid` is the rows, `paths` the `Path=` families the piece names, in the
    order the file writes them, and `jetpack_off` whether any row is tagged
    `JetPack=Off` — the piece that switches off a jetpack the player picked up
    earlier (see `Jetpack.txt` and `JetpackOff.txt`).

    A piece may name more than one path. `Twister.txt` marks the left half of
    its split road `Path=TwisterA` and the right half `Path=TwisterB`, and
    `Under Over.txt` marks its two branches `Path=Hump` and `Path=Dump` — the
    hump and the dip of the crossing. Keeping only the last tag loses the
    manoeuvre the piece is named for, so every tag is kept in order and the
    reader picks the first one it can play (see `TrackBuilder.pathFamily`).

    `signs` is the list of roadside signs the piece hangs with a
    `3DModel=<name>.x (x,y,z)` tag, each as `(row, model, x)` where `row`
    counts the rows that lay road, the way the reader numbers the slices.  A
    row tagged `Ring=<effect>` is folded so each of its orientation glyphs
    becomes the token naming that ring's effect (see `RING`).

    `parcels` is the list of parcels the piece hangs with a
    `Parcel=<set>,(x,y,z)` tag, each as `(row, x)`.  A parcel is not drawn as
    a glyph in the grid, so without this table the `Parcel=` rows are invisible
    and their parcels are simply missing: `Hump.txt` hangs one over the crest a
    snail flies across, `Cage2.txt` one inside its cage, and every
    `Loop the Loop*.txt` a trail of five up the loop.  Only `x` — the lateral
    placement — has a meaning the flat grid can carry, so the parcels keep
    their rows and the `y`/`z` offset is dropped rather than invented.

    `bands` is the list of `(row, start, end)` marks the `P`/`p` row of a
    piece lays down, and `no_fall` the rows a `NoFall` (or `No Fall`) tag
    exempts.

    The `P`/`p` row is the piece's own declaration of where its road runs
    while the family carries it off the grid.  `P` sits on exactly the columns
    the row above lays road on and `p` on the columns it leaves blank, so the
    run of `P` is the road's band — `Twister3.txt` marks `PPPppppp` under a
    crest that only laid three columns, `Toad.txt` `PPPP....` under a road it
    splits in half, and a piece that crosses the whole grid (`Worm.txt`,
    `Valley.txt`) marks all eight.  Reading the row as ordinary cells instead
    would stretch every one of those bands to the eight columns of the marker
    row itself.  A `NoFall` row is one the build lets the snail cross without
    dropping it: every one of them is a trampoline piece, where the bounce
    throws the snail out over the void and has to bring it back.
    """
    rows, paths, jetpack_off, signs, parcels = [], [], False, [], []
    bands, no_fall = [], []
    laid = 0
    for line in txt.splitlines():
        m = re.match(r"^@(.{8})@(.*)$", line)
        if m:
            row, attr = m.group(1), m.group(2)
            if re.search(r"JetPack\s*=\s*Off", attr, re.I):
                jetpack_off = True
            nofall = re.match(r"\s*No\s*Fall", attr, re.I)
            if nofall:
                no_fall.append(laid)
            ring = re.search(r"Ring=(\w+)", attr)
            if ring:
                token = RING.get(ring.group(1).lower(), "-")
                row = "".join(token if c in RING_GLYPHS else c for c in row)
            # The `P`/`p` row: the run of `P` is the road's band, the `p`s
            # beside it the columns the road has left.  A row with no `P` at
            # all (there is none in the retail grids) declares nothing.
            if "P" in row:
                cols = [i for i, c in enumerate(row) if c == "P"]
                if cols:
                    bands.append((laid, cols[0], cols[-1]))
            # A row of nothing but `@` is the seam between pieces, not road:
            # the reader drops it, so the sign row index has to drop it too.
            if row != "@" * 8:
                sign = re.search(r"3DModel\s*=\s*(\w+)\.x\s*\(\s*([-\d.]+)", attr)
                if sign:
                    signs.append((laid, sign.group(1).lower(), float(sign.group(2))))
                parcel = re.search(
                    r"Parcel\s*=\s*\d+\s*,\s*\(\s*([-\d.]+)\s*,[^)]*\)", attr)
                if parcel:
                    parcels.append((laid, float(parcel.group(1))))
                laid += 1
            rows.append(row)
        p = re.search(r"Path=(\S+)", line)
        if p and p.group(1) not in paths:
            paths.append(p.group(1))
    return "".join(rows), paths, jetpack_off, signs, parcels, bands, no_fall


def swift_string(s):
    return ('"' + s.replace("\\", "\\\\").replace('"', '\\"')
            .replace("\n", "\\n") + '"')


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("archive", help="SnailMail.dat, or the installer .zip holding it")
    ap.add_argument("--out", default=OUT, help="where to write TrackData.swift")
    args = ap.parse_args()

    files = carve(load_archive(args.archive))
    levels = by_folder(files, "levels", ".txt")
    segments = by_folder(files, "segments", ".txt")

    # The background scripts.  Each one tints its picture with a `Fog:(r,g,b)`
    # colour — the same colour the sky behind the highway takes — and streams
    # it past at its own `Distort:` rate, so both numbers have to be read out
    # of the file rather than kept as a second copy in the app.
    backgrounds = {}
    for name, text in by_folder(files, "backgrounds", ".txt").items():
        fog = re.search(r"Fog:\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)", text)
        if not fog:
            continue
        dist = re.search(r"Distort:\s*([-\d.]+)", text)
        backgrounds[name[:-4]] = (int(fog.group(1)), int(fog.group(2)),
                                  int(fog.group(3)),
                                  float(dist.group(1)) if dist else 0.0)

    # Level routes: arcade0..arcade50, tutorial and challenge.
    routes, need, random_keys, scripts, briefings = {}, set(), set(), {}, {}
    voicesMap = {}
    for key, name in ([(f"arcade{i}", f"arcade{i:03d}.txt") for i in range(51)]
                      + [("tutorial", "tutorial.txt"), ("challenge", "challenge000.txt")]):
        if name not in levels:
            print("warning: missing level %s" % name, file=sys.stderr)
            continue
        if re.search(r"Random:\s*yes", levels[name], re.I):
            random_keys.add(key)
        first, segs, last, script, voices, briefing = parse_level(levels[name])
        routes[key] = (first, segs, last)
        scripts[key] = script
        if any(v is not None for v in voices):
            voicesMap[key] = voices
        if briefing:
            briefings[key] = briefing
        need.update([first.lower(), last.lower()])
        need.update(n.lower() for n, _ in segs)

    # The opening crawl and the credits are their own scripts (`INTRO/*.txt`),
    # each a sequence of text screens separated by blank lines.
    intro = by_folder(files, "intro", ".txt")
    intro_slides = parse_slides(intro["intro.txt"]) if "intro.txt" in intro else []
    credits_slides = parse_slides(intro["credits.txt"]) if "credits.txt" in intro else []

    grids, paths, jetpacks_off, sign_map, parcel_map = {}, {}, set(), {}, {}
    band_map, nofall_map = {}, {}
    for key in sorted(need):
        if key not in segments:
            continue
        (grid, seg_paths, jetpack_off, signs, parcels,
         bands, no_fall) = parse_segment(segments[key])
        grids[key] = grid
        if seg_paths:
            paths[key] = seg_paths
        if jetpack_off:
            jetpacks_off.add(key)
        if signs:
            sign_map[key] = signs
        if parcels:
            parcel_map[key] = parcels
        if bands:
            band_map[key] = bands
        if no_fall:
            nofall_map[key] = no_fall

    def encode(route):
        first, segs, last = route
        # Keep the file name intact — the grid and path tables are keyed the
        # same way, so the reader can look a piece up without guessing a
        # suffix back on to the end of the name.
        out = [first.lower()]
        for name, attrs in segs:
            entry = name.lower()
            if "Angle" in attrs:
                entry += "@" + attrs["Angle"]
            out.append(entry)
        out.append(last.lower())
        return out

    encoded = {k: encode(v) for k, v in routes.items()}

    lines = [
        "// TrackData.swift",
        "//",
        "// GENERATED — do not edit by hand. Run tools/import_tracks.py against",
        "// the retail game's SnailMail.dat. Source: the level (*.txt routes) and",
        "// segment (*.txt grids) configuration files. Only that configuration",
        "// data is used; no original artwork, textures or audio is bundled.",
        "//",
        "// The grids are 8 columns wide per row, concatenated into one string per",
        "// segment (so `grid[key]!.count / 8` is the row count).  Characters:",
        "//   `.`/`_` road (smooth/rough), `@` side wall, ` ` off-road/airborne gap,",
        "//   `#` pit, `s` salt, `M` meteor, `&` slug, `0`-`9` a solid one-cell block,",
        "//   `$` parcel, `>` blast ring, `+` power-up ring, `~` slow ring,",
        "//   `!` plain scoring ring, `o` decorative arch, `<`/`R` ramp,",
        "//   `(` trampoline, `J` jetpack, `[` highway enemy,",
        "//   `|`/`=`/`-`/`{`/`}` fence or wall pieces, `P`/`p` path-centre markers.",
        "",
        "enum TrackData {",
        "",
        "    /// Concatenated grid rows for every segment the campaign references,",
        "    /// keyed by lower-cased file name (including the `.txt` suffix).",
        "    static let grid: [String: String] = [",
    ]
    lines += [f"        {swift_string(k)}: {swift_string(grids[k])}," for k in sorted(grids)]
    lines += ["    ]", "",
              "    /// One `BACKGROUNDS/*.TXT` script: the fog colour a level's",
              "    /// backdrop is tinted with, and the rate its picture streams",
              "    /// past at.",
              "    struct Background {",
              "        /// The `Fog:(r,g,b)` of the script, which is also the colour",
              "        /// the sky behind the highway takes.",
              "        let fogR: Int, fogG: Int, fogB: Int",
              "        /// The script's `Distort:` rate; a higher number streams the",
              "        /// backdrop past faster.",
              "        let distort: Double",
              "    }",
              "",
              "    /// Background scripts keyed the way `grid` is — lower-cased file",
              "    /// name without its suffix, so `SpacePurple` is `\"spacepurple\"`.",
              "    static let background: [String: Background] = ["]
    for k in sorted(backgrounds):
        r, g, b, distort = backgrounds[k]
        lines.append(f"        {swift_string(k)}: Background(fogR: {r}, fogG: {g},"
                     f" fogB: {b}, distort: {distort}),")
    lines += ["    ]", "",
              "    /// The `Path=` shape names of a segment, where it declares any,",
              "    /// in the order the file writes them.  A piece can name more",
              "    /// than one — `Under Over.txt` tags its branches `Hump` and",
              "    /// `Dump` — and the first name is the piece's own manoeuvre, so",
              "    /// the reader plays the first one it has a profile for.",
              "    static let path: [String: [String]] = ["]
    lines += [f"        {swift_string(k)}: [{', '.join(swift_string(v) for v in paths[k])}],"
              for k in sorted(paths)]
    lines += ["    ]", "",
              "    /// Segments that switch the jetpack back off.  A level hands one",
              "    /// out on a `Jetpack` piece and takes it back with a `JetPackOff`",
              "    /// piece a few segments later, so the flight lasts exactly as far",
              "    /// as the gaps it has to clear instead of a fixed spell.",
              "    static let jetpackOff: Set<String> = ["]
    lines += [f"        {swift_string(k)}," for k in sorted(jetpacks_off)]
    lines += ["    ]", "",
              "    /// A roadside sign a piece hangs with a `3DModel=<name>.x",
              "    /// (x, y, z)` tag.  `row` numbers the rows that lay road, the way",
              "    /// the reader slices a piece (the all-`@` seams are dropped), and",
              "    /// `x` is the lateral placement in the engine's own units — the",
              "    /// road is 9 wide there, so `x / 4.5` is where it sits across the",
              "    /// road.  The retail build draws the sign from a little 3-D model",
              "    /// (`X/signBang.x`, `signConstruction.x`, `signStop.x`); the remake",
              "    /// keys off the name and draws a flat stand-in.",
              "    struct Sign {",
              "        let row: Int",
              "        let model: String",
              "        let x: Double",
              "    }",
              "    static let sign: [String: [Sign]] = ["]
    for k in sorted(sign_map):
        body = ", ".join(
            "Sign(row: %d, model: %s, x: %s)" % (r, swift_string(m), x)
            for r, m, x in sign_map[k])
        lines.append(f"        {swift_string(k)}: [{body}],")
    lines += ["    ]", "",
              "    /// A parcel a piece hangs in mid-air with a",
              "    /// `Parcel=<set>,(x, y, z)` tag.  These are the parcels that",
              "    /// are *not* drawn as `$` cells — one over the crest of a hump,",
              "    /// one inside a cage, five up a loop — so a piece that tags one",
              "    /// carries more pickups than its grid shows.  `row` numbers the",
              "    /// rows that lay road, the way `Sign` does, and `x` is the",
              "    /// lateral placement in the engine's own units (the road is 9",
              "    /// wide, so `x / 4.5` is where it sits across the road).",
              "    struct Parcel {",
              "        let row: Int",
              "        let x: Double",
              "    }",
              "    static let parcel: [String: [Parcel]] = ["]
    for k in sorted(parcel_map):
        body = ", ".join("Parcel(row: %d, x: %s)" % (r, x) for r, x in parcel_map[k])
        lines.append(f"        {swift_string(k)}: [{body}],")
    lines += ["    ]", "",
              "    /// The road band a piece's `P`/`p` row declares, as",
              "    /// `Band(row:start:end:)`.  `P` sits on exactly the columns the",
              "    /// row above lays road on and `p` on the columns it leaves",
              "    /// blank, so the run from `start` to `end` is where the road",
              "    /// runs while the piece's own family carries it off the grid: a",
              "    /// twister's crest is three columns, a toad's split road four,",
              "    /// and a piece that crosses the grid all eight.  `row` numbers",
              "    /// the rows that lay road, the way `Sign` and `Parcel` do.",
              "    struct Band {",
              "        let row: Int",
              "        let start: Int",
              "        let end: Int",
              "    }",
              "    static let band: [String: [Band]] = ["]
    for k in sorted(band_map):
        body = ", ".join("Band(row: %d, start: %d, end: %d)" % (r, a, b)
                         for r, a, b in band_map[k])
        lines.append(f"        {swift_string(k)}: [{body}],")
    lines += ["    ]", "",
              "    /// Rows a piece tags `NoFall`, in the same numbering `Sign`",
              "    /// and `Parcel` use.  The tag is the build saying a snail may",
              "    /// cross the row without dropping off the road; every one of",
              "    /// them lies in a trampoline piece, where the bounce throws the",
              "    /// snail out over a void and has to bring it back.",
              "    static let noFall: [String: [Int]] = ["]
    for k in sorted(nofall_map):
        body = ", ".join(str(r) for r in nofall_map[k])
        lines.append(f"        {swift_string(k)}: [{body}],")
    lines += ["    ]", "",
              "    /// The tutorial's scripted lines, in the order its level file",
              "    /// lists them.  Entry `n` belongs to the piece the pool lays at",
              "    /// index `n`; an empty string leaves the previous line on",
              "    /// screen.  The retail script writes its hard line breaks as `>`",
              "    /// and drops inline sprite art into the prose with the glyphs",
              "    /// `{ } ~ [ ] ^ _ ;`; the breaks are `\\n` here and the glyphs are",
              "    /// kept verbatim so the banner can draw the same icons.",
              "    static let tutorialScript: [String] = ["]
    lines += [f"        {swift_string(t)}," for t in scripts.get("tutorial", [])]
    lines += ["    ]", "",
              "    /// The voice-over each tutorial line names, keyed by the same index",
              "    /// as `tutorialScript`.  The retail level file pairs line `n` with",
              "    /// `Sample=\"Voice/tutN.ogg\"` and, at index 6, an out-of-order",
              "    /// `tut18`; the blank lines carry no recording, so they are `nil`.",
              "    static let tutorialVoice: [String?] = ["]
    voiced = ", ".join(swift_string(v) if v else "nil"
                       for v in voicesMap.get("tutorial", [])) + ","
    lines += ["        " + line for line in textwrap.wrap(voiced, width=62)]
    lines += ["    ]", "",
              "    /// The `GalaxyText:` blurb every campaign level file carries: the",
              "    /// snail's log entry or an IPS (Intergalactic Postal Service) notice,",
              "    /// shown over the route before it starts. The prose is the retail",
              "    /// build's own, keyed the same way as `route`.",
              "    static let briefing: [String: String] = ["]
    for k in sorted(briefings, key=lambda s: (s.rstrip("0123456789"),
                                              int(s[len(s.rstrip("0123456789")):] or 0))):
        lines.append(f"        {swift_string(k)}: {swift_string(briefings[k])},")
    lines += ["    ]", "",
              "    /// The opening crawl (`INTRO/Intro.txt`), one string per text",
              "    /// screen. Picture inserts the retail script named here are",
              "    /// dropped, so the remake narrates the story in words alone.",
              "    static let introSlides: [String] = ["]
    lines += [f"        {swift_string(s)}," for s in intro_slides]
    lines += ["    ]", "",
              "    /// The credits screen (`INTRO/Credits.txt`), one string per",
              "    /// text screen.",
              "    static let creditsSlides: [String] = ["]
    lines += [f"        {swift_string(s)}," for s in credits_slides]
    lines += ["    ]", "",
              "    /// Ordered segment list for each level.  Level keys are `arcade0`-",
              "    /// `arcade50`, plus `tutorial` and `challenge`.  Each entry names a",
              "    /// grid the same way `grid` is keyed, and may carry an `@<angle>`",
              "    /// suffix holding the level's `Angle=` override (degrees).",
              "    static let route: [String: [String]] = ["]
    for k in sorted(encoded, key=lambda s: (s.rstrip("0123456789"),
                                            int(s[len(s.rstrip("0123456789")):] or 0))):
        body = ", ".join(swift_string(x) for x in encoded[k])
        lines.append(f"        {swift_string(k)}: [{body}],")
    lines += ["    ]", "",
              "    /// Routes whose level file sets `Random:yes`.  Their segment pool",
              "    /// is shuffled instead of played in order, so the challenge",
              "    /// gauntlet never lays out the same way twice.",
              "    static let random: Set<String> = ["]
    lines += [f"        {swift_string(k)}," for k in sorted(random_keys)]
    lines += ["    ]", "}", ""]

    with open(args.out, "w") as fh:
        fh.write("\n".join(lines))
    print("wrote %s: %d segments, %d routes" % (args.out, len(grids), len(encoded)))


if __name__ == "__main__":
    main()
