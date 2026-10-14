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
    segs = []
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
    first = re.search(r"First:.*?\n\s*(.*?\.txt)", txt, flags=re.S)
    last = re.search(r"Last:.*?\n\s*(.*?\.txt)", txt, flags=re.S)
    return (os.path.basename(first.group(1)) if first else "Start.txt",
            segs,
            os.path.basename(last.group(1)) if last else "Finish.txt")


def parse_segment(txt):
    """Return (grid, path) for one segment: its rows plus its `Path=` family.

    A row tagged `Ring=<effect>` is folded so each of its orientation glyphs
    becomes the token naming that ring's effect (see `RING`). `Parcel=` rows
    carry a single parcel's 3D position as metadata on an otherwise blank row;
    the parcels the player actually grabs are the `$` cells in the grid, so
    the metadata row is left blank rather than expanded into a band of parcels.
    """
    rows, path = [], ""
    for line in txt.splitlines():
        m = re.match(r"^@(.{8})@(.*)$", line)
        if m:
            row, attr = m.group(1), m.group(2)
            ring = re.search(r"Ring=(\w+)", attr)
            if ring:
                token = RING.get(ring.group(1).lower(), "-")
                row = "".join(token if c in RING_GLYPHS else c for c in row)
            rows.append(row)
        p = re.search(r"Path=(\S+)", line)
        if p:
            path = p.group(1)
    return "".join(rows), path


def swift_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("archive", help="SnailMail.dat, or the installer .zip holding it")
    ap.add_argument("--out", default=OUT, help="where to write TrackData.swift")
    args = ap.parse_args()

    files = carve(load_archive(args.archive))
    levels = by_folder(files, "levels", ".txt")
    segments = by_folder(files, "segments", ".txt")

    # Level routes: arcade0..arcade50, tutorial and challenge.
    routes, need = {}, set()
    for key, name in ([(f"arcade{i}", f"arcade{i:03d}.txt") for i in range(51)]
                      + [("tutorial", "tutorial.txt"), ("challenge", "challenge000.txt")]):
        if name not in levels:
            print("warning: missing level %s" % name, file=sys.stderr)
            continue
        first, segs, last = parse_level(levels[name])
        routes[key] = (first, segs, last)
        need.update([first.lower(), last.lower()])
        need.update(n.lower() for n, _ in segs)

    grids, paths = {}, {}
    for key in sorted(need):
        if key not in segments:
            continue
        grid, path = parse_segment(segments[key])
        grids[key] = grid
        if path:
            paths[key] = path

    def encode(route):
        first, segs, last = route
        out = [first.lower().replace(".txt", "")]
        for name, attrs in segs:
            entry = name.lower().replace(".txt", "")
            if "Angle" in attrs:
                entry += "@" + attrs["Angle"]
            out.append(entry)
        out.append(last.lower().replace(".txt", ""))
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
        "//   `#` pit, `s` salt, `M` meteor, `&` slug, `0` turret, `1`-`3` enemies,",
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
              "    /// The `Path=` shape name of a segment, where it declares one.",
              "    static let path: [String: String] = ["]
    lines += [f"        {swift_string(k)}: {swift_string(paths[k])}," for k in sorted(paths)]
    lines += ["    ]", "",
              "    /// Ordered segment list for each level.  Level keys are `arcade0`-",
              "    /// `arcade50`, plus `tutorial` and `challenge`.  Entries may carry an",
              "    /// `@<angle>` suffix holding the level's `Angle=` override (degrees).",
              "    static let route: [String: [String]] = ["]
    for k in sorted(encoded, key=lambda s: (s.rstrip("0123456789"),
                                            int(s[len(s.rstrip("0123456789")):] or 0))):
        body = ", ".join(swift_string(x) for x in encoded[k])
        lines.append(f"        {swift_string(k)}: [{body}],")
    lines += ["    ]", "}", ""]

    with open(args.out, "w") as fh:
        fh.write("\n".join(lines))
    print("wrote %s: %d segments, %d routes" % (args.out, len(grids), len(encoded)))


if __name__ == "__main__":
    main()
