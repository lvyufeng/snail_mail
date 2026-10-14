#!/usr/bin/env python3
"""Rebuild the retail build's menu lettering as a font iOS can register.

`OBJECTS/FONT/FONT-MENU-HOVER.TGA` is the 2005 game's only shipped text art:
a single strip holding one row of glyphs, white on transparent, that the
original draws its menu labels and hover highlights with. Everything else it
lettered with is the 3-D extruded font (`FONT3D/LETTER.TGA`), one mesh per
glyph, which is not a texture atlas and cannot be reflowed.

The strip is a bitmap font, so it is turned back into outlines here: every
glyph's ink is thresholded at half coverage — the 50% contour is the shape the
original's own antialiasing was rendering — decomposed into rectangles, and
written out as a TrueType face. A real font means the remake keeps SwiftUI's
ordinary `Text` layout, wrapping, tinting and CJK fallback instead of needing a
hand-rolled text view, and the letterforms are the retail ones rather than a
lookalike.

The strip reads, left to right:

    a-z A-Z 0-9 " ' : ( ) ! @ # $ % < > * + = - / \\ , . ` |

Digits come out of the original at a fixed 24 px pitch, which is preserved.

Usage:
    python3 tools/make_font.py in.png out.ttf
"""

import struct
import sys

from PIL import Image

# The strip's glyph order. Index 0 is column run 0 of the ink; see the module
# docstring for how it was read off.
CHARS = (
    "abcdefghijklmnopqrstuvwxyz"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "0123456789"
    "\"':()!@#$%<>*+=-/\\,.`|"
)

# The sample line's own metrics, in strip pixels.
INK_FLOOR = 16        # alpha above this is ink; the row above the caps is a border
COVERAGE = 128        # half coverage: the glyph's true outline
BASELINE = 27.0       # rows 7..26 are caps, so their lower edge sits here
EM_TOP = 4.0          # the tallest ink (`(`, `$`, `/`) reaches row 4
DESCENT = 32.0        # the deepest (`g`, `p`, `q`, `y`, `j`)

DIGIT_PITCH = 24.0    # the strip lays 0-9 out on a fixed pitch
DIGIT_ORIGIN = 983.0

# Past the glyphs the strip carries a coloured legend the game draws as a
# hover highlight; it is not part of the lettering.
LEGEND_FROM = 1630

UPEM = 2048
UNITS_PER_PX = UPEM / (DESCENT - EM_TOP)

FAMILY = "Snail Mail Retail"


def _runs(rows):
    """Column runs of a boolean bitmap, in x order."""
    width = len(rows[0]) if rows else 0
    out, start = [], None
    for x in range(width):
        filled = any(row[x] for row in rows)
        if filled and start is None:
            start = x
        elif not filled and start is not None:
            out.append((start, x - 1))
            start = None
    if start is not None:
        out.append((start, width - 1))
    return out


def _rects(mask):
    """Decompose a boolean bitmap into rectangles.

    Row runs that line up with the row above are extended instead of starting a
    new rectangle, so a glyph costs a handful of rectangles rather than one per
    scanline.
    """
    rects = []
    for y in range(len(mask)):
        row = mask[y]
        spans, start = [], None
        for x, filled in enumerate(row):
            if filled and start is None:
                start = x
            elif not filled and start is not None:
                spans.append([start, x])
                start = None
        if start is not None:
            spans.append([start, len(row)])
        for span in spans:
            for rect in rects:
                if rect[3] == y and rect[0] == span[0] and rect[1] == span[1]:
                    rect[3] = y + 1
                    break
            else:
                rects.append([span[0], span[1], y, y + 1])
    return [tuple(r) for r in rects]


def _median(values):
    values = sorted(values)
    return values[len(values) // 2] if values else 0.0


def read_strip(path):
    """Measure the strip into `(char, x0, top, bottom, lsb, advance)` tuples.

    All positions are in strip pixels. The side bearings come from the spacing
    the sample line itself uses rather than from a guessed metric: the gap
    before and after each glyph is split in half, which reproduces the line's
    own rhythm while still leaving each glyph a sane bearing of its own.
    """
    alpha = Image.open(path).convert("RGBA").getchannel("A")
    width, height = alpha.size
    ink = [[alpha.getpixel((x, y)) >= INK_FLOOR and y >= 3
            for x in range(width)] for y in range(height)]
    solid = [[alpha.getpixel((x, y)) >= COVERAGE and y >= 3
              for x in range(width)] for y in range(height)]

    columns = [(x0, x1) for x0, x1 in _runs(ink) if x1 >= 8 and x0 < LEGEND_FROM]
    if len(columns) != len(CHARS):
        raise SystemExit("expected %d glyph runs in the strip, found %d"
                         % (len(CHARS), len(columns)))

    boxes = []
    for x0, x1 in columns:
        rows = [y for y in range(height)
                if any(solid[y][x] for x in range(x0, x1 + 1))]
        boxes.append((x0, x1, min(rows), max(rows) + 1))

    gaps_in = [boxes[i][0] - boxes[i - 1][1] - 1 for i in range(1, len(boxes))]
    gaps_out = [boxes[i + 1][0] - boxes[i][1] - 1 for i in range(len(boxes) - 1)]
    typical_in = max(0.0, _median(gaps_in))
    typical_out = max(0.0, _median(gaps_out))

    glyphs = []
    for i, (x0, x1, top, bottom) in enumerate(boxes):
        width = x1 - x0 + 1
        if CHARS[i].isdigit():
            # Fixed pitch, exactly as the strip lays the digits out.
            advance = DIGIT_PITCH
            lsb = x0 - (DIGIT_ORIGIN + DIGIT_PITCH * int(CHARS[i]))
        else:
            gap_in = gaps_in[i - 1] if i > 0 else typical_in
            gap_out = gaps_out[i] if i < len(gaps_out) else typical_out
            lsb = min(5.0, max(0.0, round(gap_in / 2)))
            advance = lsb + width + min(5.0, max(0.0, round(gap_out / 2)))
        glyphs.append((CHARS[i], x0, x1, top, bottom, lsb, advance))
    return glyphs


def _outline(alpha, x0, x1, top, bottom, lsb):
    """Rectangles of one glyph in font units, x measured from the pen."""
    cell = alpha.crop((x0, top, x1 + 1, bottom))
    mask = [[cell.getpixel((x, y)) >= COVERAGE for x in range(cell.width)]
            for y in range(cell.height)]

    def px_x(x):
        return round(lsb * UNITS_PER_PX + x * UNITS_PER_PX)

    def px_y(y):
        return round((BASELINE - (top + y)) * UNITS_PER_PX)

    out = []
    for rx0, rx1, ry0, ry1 in _rects(mask):
        left, right_ = px_x(rx0), px_x(rx1)
        low, high = px_y(ry1), px_y(ry0)
        # Clockwise in font space (y up), which is the winding TrueType wants.
        out.append([(left, low), (left, high), (right_, high), (right_, low)])
    return out


def _glyf_data(rects):
    """One glyph's outlines. `rects` is a flat list of 4-point contours."""
    points, ends, flags = [], [], []
    for rect in rects:
        for x, y in rect:
            points.append((x, y))
            flags.append(1)
        ends.append(len(points) - 1)
    xs = [p[0] for p in points] or [0]
    ys = [p[1] for p in points] or [0]
    data = struct.pack(">hhhhh", len(rects), min(xs), min(ys), max(xs), max(ys))
    if not rects:
        return data
    data += struct.pack(">%dH" % len(ends), *ends)
    data += struct.pack(">H", 0)                       # no instructions
    data += bytes(flags)
    px = 0
    for x, _ in points:
        data += struct.pack(">h", x - px)
        px = x
    py = 0
    for _, y in points:
        data += struct.pack(">h", y - py)
        py = y
    if len(data) % 2:
        data += b"\0"
    return data


def _cmap(mapping):
    entries = sorted(mapping.items())
    segs = []
    for code, gid in entries:
        if (segs and segs[-1][1] == code - 1
                and gid - code == segs[-1][2] - segs[-1][0]):
            segs[-1][1] = code
        else:
            segs.append([code, code, gid])
    segs.append([0xFFFF, 0xFFFF, 0])

    # Every segment is a straight `idDelta` run, so the glyph id array stays
    # empty and each segment is eight bytes.
    id_deltas = []
    for start, end, gid in segs:
        id_deltas.append((gid - start) & 0xFFFF)

    seg_count = len(segs)
    length = 16 + seg_count * 8
    power = 2 ** (seg_count.bit_length() - 1)
    search_range = power * 2
    sub = struct.pack(">HHHHHHH", 4, length, 0, seg_count * 2,
                      search_range, power.bit_length() - 1,
                      seg_count * 2 - search_range)
    sub += struct.pack(">%dH" % seg_count, *[s[1] for s in segs])
    sub += struct.pack(">H", 0)
    sub += struct.pack(">%dH" % seg_count, *[s[0] for s in segs])
    sub += struct.pack(">%dH" % seg_count, *id_deltas)
    sub += struct.pack(">%dH" % seg_count, *([0] * seg_count))

    # 3/1 (Windows BMP) and 0/3 (Unicode) both point at the same subtable,
    # which sits right behind the two encoding records.
    at = 4 + 2 * 8
    header = struct.pack(">HHHHI", 0, 2, 3, 1, at) + struct.pack(">HHI", 0, 3, at)
    return header + sub


def _name(records):
    encoded, strings = [], b""
    for name_id, value in records:
        raw = value.encode("utf-16-be")
        encoded.append((3, 1, 0x409, name_id, len(raw), len(strings)))
        strings += raw
    header = struct.pack(">HHH", 0, len(encoded), 6 + len(encoded) * 12)
    body = b"".join(struct.pack(">HHHHHH", *r) for r in encoded)
    return header + body + strings


def build(path, out):
    glyphs = read_strip(path)
    alpha = Image.open(path).convert("RGBA").getchannel("A")

    order = [("space", None)] + [(c, g) for c, *g in glyphs]
    # (char, x0, top, bottom, lsb, advance)
    contours, metrics, mapping = [], [], {}
    for gid, (char, glyph) in enumerate(order):
        if glyph is None:
            contours.append([])
            metrics.append((round(0.5 * DIGIT_PITCH * UNITS_PER_PX), 0))
            continue
        x0, x1, top, bottom, lsb, advance = glyph
        contours.append(_outline(alpha, x0, x1, top, bottom, lsb))
        metrics.append((round(advance * UNITS_PER_PX),
                        round(lsb * UNITS_PER_PX)))
        mapping[ord(char)] = gid

    glyf, loca, offset = b"", [0], 0
    for contour in contours:
        data = _glyf_data(contour)
        glyf += data
        offset += len(data)
        loca.append(offset)
    loca_bytes = struct.pack(">%dI" % len(loca), *loca)

    max_points = max((4 * len(c) for c in contours), default=0)
    max_contours = max((len(c) for c in contours), default=0)
    xs = [point[0] for glyph in contours for rect in glyph for point in rect] or [0]
    ys = [point[1] for glyph in contours for rect in glyph for point in rect] or [0]
    ascent = round((BASELINE - EM_TOP) * UNITS_PER_PX)
    descent = -round((DESCENT - BASELINE) * UNITS_PER_PX)

    cap_height = round((BASELINE - 7) * UNITS_PER_PX)
    head = struct.pack(
        ">" + "IIII" + "HH" + "QQ" + "hhhh" + "HH" + "hhh",
        0x00010000, 0x00010000, 0, 0x5F0F3CF5, 3, UPEM, 0, 0,
        min(xs), min(ys), max(xs), max(ys), 0, 8, 2, 1, 0)
    hhea = struct.pack(
        ">" + "I" + "hhh" + "H" + "hhhhhh" + "hhhhh" + "H",
        0x00010000, ascent, descent, 0, max(m[0] for m in metrics),
        min(m[1] for m in metrics), 0, max(xs), 1, 0, 0, 0, 0, 0, 0, 0, len(metrics))
    maxp = struct.pack(
        ">" + "I" + "H" * 14,
        0x00010000, len(metrics), max_points, max_contours,
        0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0)
    os2 = struct.pack(
        ">" + "HhHHH" + "h" * 10 + "h" + "10s" + "IIII" + "4s"
        + "HHH" + "hhh" + "HH" + "II" + "hh" + "HHH",
        4, 500, 400, 5, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, b"\0" * 10,
        1, 0, 0, 0, b"SNML", 0x40, ord(" "), ord("~"),
        ascent, descent, 0, ascent, -descent, 0, 0, 0, cap_height,
        0, ord(" "), 1)

    tables = {}
    tables["head"] = head
    tables["hhea"] = hhea
    tables["maxp"] = maxp
    tables["OS/2"] = os2
    tables["hmtx"] = b"".join(struct.pack(">Hh", *m) for m in metrics)
    tables["cmap"] = _cmap(mapping)
    tables["glyf"] = glyf
    tables["loca"] = loca_bytes
    tables["name"] = _name([
        (1, FAMILY), (2, "Regular"), (3, FAMILY),
        (4, FAMILY + " Regular"), (6, "SnailMailRetail"),
    ])
    tables["post"] = struct.pack(">IIhhIIIII", 0x00030000, 0, 0, 0, 0, 0, 0, 0, 0)

    names = sorted(tables)
    count = len(names)
    power = 2 ** (count.bit_length() - 1)
    header = struct.pack(">IHHHH", 0x00010000, count,
                         power * 16, power.bit_length() - 1, count * 16 - power * 16)
    offset = 12 + count * 16
    directory, body = b"", b""
    for name in names:
        data = tables[name]
        padded = data + b"\0" * (-len(data) % 4)
        directory += name.encode("latin-1").ljust(4, b" ") + struct.pack(
            ">III", _checksum(data), offset, len(data))
        body += padded
        offset += len(padded)

    font = bytearray(header + directory + body)
    head_offset = struct.unpack_from(">I", font, 12 + names.index("head") * 16 + 8)[0]
    struct.pack_into(">I", font, head_offset + 8, 0)     # zero it before summing
    adjustment = (0xB1B0AFBA - _checksum(bytes(font))) & 0xFFFFFFFF
    struct.pack_into(">I", font, head_offset + 8, adjustment)
    with open(out, "wb") as fh:
        fh.write(bytes(font))
    return len(metrics)


def _checksum(data):
    data = data + b"\0" * (-len(data) % 4)
    total = 0
    for i in range(0, len(data), 4):
        total = (total + struct.unpack(">I", data[i:i + 4])[0]) & 0xFFFFFFFF
    return total


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__.strip().splitlines()[-1].strip())
    count = build(sys.argv[1], sys.argv[2])
    print("wrote %s (%d glyphs)" % (sys.argv[2], count))


if __name__ == "__main__":
    main()
