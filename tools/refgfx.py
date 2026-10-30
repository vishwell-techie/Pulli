#!/usr/bin/env python3
"""refgfx.py — reference implementation of the Pulli rasterizer.

This exists so we can catch the class of bug that otherwise only shows up
after the firmware port: the C engine and the device quietly disagreeing
about where a pixel goes. Every primitive in runtime/gfx.c is mirrored here
in the most obvious possible way, and the conformance harness renders the
same scene through both and compares byte-for-byte.

Slow and readable is the whole point. Do not optimise this file.
"""
import math, os, struct, zlib

W, H = 320, 240
CELL = 8
COLORS = 256         # palette length, the hard cap (a pixel is a byte); colour indices wrap modulo this
SHADE_LIGHTS = 64    # shade() takes this many lights; the rest are left out
SHADE_EDGE = 32      # and dots no more than this many pixels of each edge

_FONT_TXT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "..", "runtime", "font.txt")


ICON_FIRST, ICON_NAMES = 0xE000, ("left", "right", "up", "down", "a", "b", "x", "y", "l", "r",
                                   "start", "select")


def _parse_font(path):
    """runtime/font.txt: {code: [rows]} for ASCII, each row 8 '.'/'#'
    cells, and {code point: [rows]} for the button icons."""
    glyphs, icons, rows = {}, {}, None
    for n, line in enumerate(open(path, encoding="ascii"), 1):
        line = line.rstrip("\n")
        if not line or line.startswith(";"):
            continue
        if line.startswith("= U+"):
            rows = []
            icons[int(line.split()[1][2:], 16)] = rows
        elif line.startswith("="):
            rows = []
            glyphs[int(line.split()[1])] = rows
        elif rows is not None and line and set(line) <= set(".#") and (not rows or len(line) == len(rows[0])):
            rows.append(line)
        else:
            raise ValueError(f"{path}:{n}: not a glyph row: {line!r}")
    return glyphs, icons


def load_font(path=_FONT_TXT):
    """Parse runtime/font.txt into 96 glyphs of 8 row bytes (bit 7 = left)."""
    glyphs, _ = _parse_font(path)
    if sorted(glyphs) != list(range(32, 128)) or any(len(r) != 8 or len(r[0]) != 8 for r in glyphs.values()):
        raise ValueError(f"{path}: need exactly 8 rows of 8 for each of codes 32..127")
    return [[sum(0x80 >> i for i, ch in enumerate(row) if ch == "#") for row in glyphs[c]] for c in range(32, 128)]


def load_icons(path=_FONT_TXT):
    """The button icons in runtime/font.txt, in button order: (width, rows)
    for U+E000 onwards, each 8 rows of '.' and '#'."""
    _, icons = _parse_font(path)
    want = list(range(ICON_FIRST, ICON_FIRST + len(ICON_NAMES)))
    if sorted(icons) != want or any(len(r) != 8 or len(r[0]) > 32 for r in icons.values()):
        raise ValueError(f"{path}: need 8 rows, at most 32 wide, for each of U+E000..U+E00B")
    return [(len(icons[c][0]), icons[c]) for c in want]


_ICONS = None


def icons():
    global _ICONS
    if _ICONS is None:
        _ICONS = load_icons()
    return _ICONS


_FONT_TA_TXT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "..", "runtime", "font_ta.txt")
_FONT_TA_SMALL_TXT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                  "..", "runtime", "font_ta_small.txt")


class TamilFont:
    """runtime/font_ta.txt: whole Tamil syllables as pixels (SPEC §3, "Text").
    rows: every glyph's height; above: how many of those rows are above row
    0 of an English letter; glyphs: {letters: (width, kern, advance, rows)}."""

    def __init__(self, path=_FONT_TA_TXT):
        self.rows = self.above = None
        self.glyphs = {}
        name = None
        for n, line in enumerate(open(path, encoding="utf-8"), 1):
            line = line.rstrip("\n")
            if not line or line.startswith(";"):
                continue
            if line.startswith("! "):
                fields = dict(f.split("=") for f in line[2:].split())
                self.rows, self.above = int(fields["rows"]), int(fields["above"])
            elif line.startswith("= "):
                parts = line[2:].split(" ")
                name, attrs = parts[0], dict(a.split("=") for a in parts[1:])
                if name in self.glyphs:
                    raise ValueError(f"{path}:{n}: {name} is drawn twice")
                if not 1 <= len(name) <= 4 or set(attrs) != {"adv", "kern"}:
                    raise ValueError(f"{path}:{n}: a glyph needs 1 to 4 letters, adv= and kern=")
                self.glyphs[name] = [int(attrs["kern"]), int(attrs["adv"]), []]
            elif name is not None and line and set(line) <= set(".#"):
                rows = self.glyphs[name][2]
                if rows and len(line) != len(rows[0]):
                    raise ValueError(f"{path}:{n}: rows of {name} differ in width")
                rows.append(line)
            else:
                raise ValueError(f"{path}:{n}: not part of a glyph: {line!r}")
        if self.rows is None:
            raise ValueError(f"{path}: no '! rows= above=' line")
        for name, (kern, adv, rows) in list(self.glyphs.items()):
            if len(rows) != self.rows or not 1 <= len(rows[0]) <= 255:
                raise ValueError(f"{path}: {name} must be {self.rows} rows of 1 to 255 columns")
            self.glyphs[name] = (len(rows[0]), kern, adv, rows)


def utf8_next(data, i):
    """The character starting at byte i of `data` and its length in bytes.
    A byte that does not start a well-formed character gives (-1, 1)."""
    b = data[i]
    if b < 0x80:
        return b, 1
    if 0xC2 <= b <= 0xDF:
        n, cp = 2, b & 0x1F
    elif 0xE0 <= b <= 0xEF:
        n, cp = 3, b & 0x0F
    elif 0xF0 <= b <= 0xF4:
        n, cp = 4, b & 0x07
    else:
        return -1, 1
    if i + n > len(data):
        return -1, 1
    for k in range(1, n):
        if not 0x80 <= data[i + k] <= 0xBF:
            return -1, 1
        cp = (cp << 6) | (data[i + k] & 0x3F)
    return cp, n


def _pieces(ta, cps):
    """One line of characters as ("en", code), ("icon", n) and ("ta",
    letters) pieces. Tamil is matched longest first, so a syllable comes out
    whole."""
    out, i = [], 0
    while i < len(cps):
        cp = cps[i]
        if 0 <= cp < 128:
            if cp >= 32:
                out.append(("en", cp))
            i += 1
            continue
        if ICON_FIRST <= cp < ICON_FIRST + len(ICON_NAMES):
            out.append(("icon", cp - ICON_FIRST))
            i += 1
            continue
        for n in range(min(4, len(cps) - i), 0, -1):
            seq = cps[i:i + n]
            if min(seq) >= 0 and "".join(map(chr, seq)) in ta.glyphs:
                out.append(("ta", "".join(map(chr, seq))))
                i += n
                break
        else:
            out.append(("en", ord("?")))      # a character the fonts do not have
            i += 1
    return out


def layout(ta, data):
    """Lay out `data` (bytes) as the engine does. Yields, line by line,
    ("en", code, x, y), ("icon", n, x, y) and ("ta", letters, x, y) for each
    glyph, giving where
    its top-left goes, then ("end", x, height) where the line ends. x and y
    are offsets from where the text starts. A line holding Tamil is ta.rows
    tall, its digits come from the Tamil font, and its other English is
    lowered to share the baseline; any other is 8."""
    cps, i = [], 0
    while i < len(data):
        cp, n = utf8_next(data, i)
        cps.append(cp)
        i += n
    lines, line = [], []
    for cp in cps:
        if cp == 10:
            lines.append(line)
            line = []
        else:
            line.append(cp)
    lines.append(line)
    y = 0
    for line in lines:
        pieces = _pieces(ta, line)
        tamil = any(kind == "ta" for kind, _ in pieces)
        if tamil:                       # a number on a Tamil line is drawn at the Tamil size
            pieces = [("ta", chr(what)) if kind == "en" and 48 <= what <= 57 and chr(what) in ta.glyphs
                      else (kind, what) for kind, what in pieces]
        height, lower = (ta.rows, ta.above) if tamil else (CELL, 0)
        x = 0
        for kind, what in pieces:
            if kind == "en":
                yield ("en", what, x, y + lower)
                x += CELL
            elif kind == "icon":
                yield ("icon", what, x, y + lower)
                x += icons()[what][0]
            else:
                width, kern, adv, _ = ta.glyphs[what]
                yield ("ta", what, x + kern, y)
                x += adv
        yield ("end", x, height)
        y += height


def text_size(ta, data):
    """The width of the widest line of `data` (bytes) and the height of all
    its lines, in pixels."""
    ends = [item for item in layout(ta, data) if item[0] == "end"]
    return max(e[1] for e in ends), sum(e[2] for e in ends)


class RefGfx:
    def __init__(self):
        self.fb = bytearray(W * H)
        self.palette = [0] * COLORS
        self.pal_map = list(range(COLORS))
        self.transparent = [False] * COLORS
        self.transparent[0] = True
        self.fade_k = 32                 # 32 = full brightness, 0 = black
        self.cam = (0, 0)
        self.clip = (0, 0, W, H)
        self.atlas = None
        self.atlas_w = 0
        self.atlas_h = 0
        self.backdrop = None        # W*H indexed pixels cls() starts from (backdrop())
        self.font_en = load_font()
        self.fonts_ta = {"normal": TamilFont(), "small": TamilFont(_FONT_TA_SMALL_TXT)}
        self.font_ta = self.fonts_ta["normal"]
        default_palette(self)

    # -- single choke point, mirrors put() in gfx.c --
    def _put(self, x, y, c):
        x -= self.cam[0]
        y -= self.cam[1]
        cx, cy, cw, ch = self.clip
        if not (cx <= x < cx + cw and cy <= y < cy + ch):
            return
        self.fb[y * W + x] = self.pal_map[c % COLORS]

    def cls(self, c=None):
        """Clear to colour c; with no colour and a backdrop set, start the
        frame from the backdrop, each pixel through pal()."""
        if c is None and self.backdrop is not None:
            for i in range(W * H):
                self.fb[i] = self.pal_map[self.backdrop[i] % COLORS]
            return
        v = self.pal_map[(c or 0) % COLORS]
        for i in range(W * H):
            self.fb[i] = v

    def pset(self, x, y, c):
        self._put(x, y, c)

    def pget(self, x, y):
        x -= self.cam[0]
        y -= self.cam[1]
        if not (0 <= x < W and 0 <= y < H):
            return 0
        return self.fb[y * W + x]

    def line(self, x0, y0, x1, y1, c):
        dx, dy = x1 - x0, y1 - y0
        sx = 1 if dx >= 0 else -1
        sy = 1 if dy >= 0 else -1
        dx, dy = abs(dx), abs(dy)
        err = dx - dy
        while True:
            self._put(x0, y0, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = err * 2
            if e2 > -dy:
                err -= dy
                x0 += sx
            if e2 < dx:
                err += dx
                y0 += sy

    def rect(self, x, y, w, h, c):
        if w <= 0 or h <= 0:
            return
        for i in range(w):
            self._put(x + i, y, c)
            self._put(x + i, y + h - 1, c)
        for j in range(1, h - 1):
            self._put(x, y + j, c)
            self._put(x + w - 1, y + j, c)

    def rectfill(self, x, y, w, h, c):
        for j in range(h):
            for i in range(w):
                self._put(x + i, y + j, c)

    def circ(self, cx, cy, r, c):
        x, y, err = r, 0, 1 - r
        while x >= y:
            for px, py in ((cx+x, cy+y), (cx+y, cy+x), (cx-y, cy+x), (cx-x, cy+y),
                           (cx-x, cy-y), (cx-y, cy-x), (cx+y, cy-x), (cx+x, cy-y)):
                self._put(px, py, c)
            y += 1
            if err < 0:
                err += 2 * y + 1
            else:
                x -= 1
                err += 2 * (y - x) + 1

    def circfill(self, cx, cy, r, c):
        for y in range(-r, r + 1):
            for x in range(-r, r + 1):
                if x * x + y * y <= r * r:
                    self._put(cx + x, cy + y, c)

    def shade(self, c=0, lights=(), edge=0):
        lights = list(lights)[:SHADE_LIGHTS * 3]
        lights = [lights[i:i + 3] for i in range(0, len(lights) - 2, 3)]
        edge = max(0, min(SHADE_EDGE, edge))
        cx, cy, cw, ch = self.clip
        ox, oy = self.cam
        for sy in range(cy, cy + ch):
            y = sy + oy
            # where each light crosses the row: the circfill pixels
            spans = []
            for lx, ly, r in lights:
                if r >= 0 and abs(y - ly) <= r:
                    hw = math.isqrt(r * r - (y - ly) ** 2)
                    spans.append([lx - hw, lx + hw])
            spans.sort(key=lambda s: s[0])
            joined = []
            for a, b in spans:
                if joined and a <= joined[-1][1] + 1:
                    joined[-1][1] = max(joined[-1][1], b)
                else:
                    joined.append([a, b])
            for sx in range(cx, cx + cw):
                x = sx + ox
                dark = True
                for a, b in joined:
                    if a <= x <= b:
                        w = min(edge, (b - a + 1) // 2)
                        dark = (x < a + w or x > b - w) and (x + y) % 2 == 0
                        break
                if dark:
                    self._put(x, y, c)

    def spr(self, n, x, y, cw=1, ch=1, flip_x=False, flip_y=False):
        if not self.atlas or self.atlas_w <= 0:
            return
        if cw <= 0:
            cw = 1
        if ch <= 0:
            ch = 1
        per_row = self.atlas_w // CELL
        if per_row <= 0 or n < 0:
            return
        ax = (n % per_row) * CELL
        ay = (n // per_row) * CELL
        pw, ph = cw * CELL, ch * CELL
        for j in range(ph):
            sy = ay + (ph - 1 - j if flip_y else j)
            if not (0 <= sy < self.atlas_h):
                continue
            for i in range(pw):
                sx = ax + (pw - 1 - i if flip_x else i)
                if not (0 <= sx < self.atlas_w):
                    continue
                c = self.atlas[sy * self.atlas_w + sx] % COLORS
                if self.transparent[c]:
                    continue
                self._put(x + i, y + j, c)

    def sspr(self, sx, sy, sw, sh, dx, dy, dw, dh, flip_x=False, flip_y=False):
        if not self.atlas or sw <= 0 or sh <= 0 or dw <= 0 or dh <= 0:
            return
        for j in range(dh):
            ty = sy + ((dh - 1 - j if flip_y else j) * sh) // dh
            if not (0 <= ty < self.atlas_h):
                continue
            for i in range(dw):
                tx = sx + sw - 1 - (i * sw) // dw if flip_x else sx + (i * sw) // dw
                if not (0 <= tx < self.atlas_w):
                    continue
                c = self.atlas[ty * self.atlas_w + tx] % COLORS
                if self.transparent[c]:
                    continue
                self._put(dx + i, dy + j, c)

    def map_draw(self, cells, w, h, sx=0, sy=0):
        """One layer of a map (SPEC §3): `cells` row by row, each a tile
        number plus 0x8000 to flip it left-right and 0x4000 up-down. The
        layer's corner is at (-sx, -sy), under the camera. Tile 0 is empty."""
        for my in range(h):
            for mx in range(w):
                c = cells[my * w + mx]
                if c & 0x3FFF:
                    self.spr(c & 0x3FFF, mx * CELL - sx, my * CELL - sy, 1, 1,
                             bool(c & 0x8000), bool(c & 0x4000))

    def print(self, text, x, y, c):
        """Draw text, UTF-8 when given bytes. Returns where the next letter
        would go on the last line."""
        data = text.encode("utf-8") if isinstance(text, str) else bytes(text)
        end = x
        for item in layout(self.font_ta, data):
            if item[0] == "en":
                glyph = self.font_en[item[1] - 32]
                for j in range(CELL):
                    for i in range(CELL):
                        if glyph[j] & (0x80 >> i):
                            self._put(x + item[2] + i, y + item[3] + j, c)
            elif item[0] == "icon":
                for j, row in enumerate(icons()[item[1]][1]):
                    for i, ch in enumerate(row):
                        if ch == "#":
                            self._put(x + item[2] + i, y + item[3] + j, c)
            elif item[0] == "ta":
                rows = self.font_ta.glyphs[item[1]][3]
                for j, row in enumerate(rows):
                    for i, ch in enumerate(row):
                        if ch == "#":
                            self._put(x + item[2] + i, y + item[3] + j, c)
            else:
                end = x + item[1]
        return end

    def font(self, size="normal"):
        """The size Tamil is drawn and measured at: "normal" or "small"."""
        self.font_ta = self.fonts_ta[size]

    def camera(self, x=0, y=0):
        self.cam = (x, y)

    def set_clip(self, x=0, y=0, w=0, h=0):
        if w <= 0 or h <= 0:
            self.clip = (0, 0, W, H)
            return
        if x < 0:
            w += x
            x = 0
        if y < 0:
            h += y
            y = 0
        w = min(w, W - x)
        h = min(h, H - y)
        self.clip = (x, y, max(w, 0), max(h, 0))

    def pal(self, a=-1, b=0):
        if a < 0:
            self.pal_map = list(range(COLORS))
        else:
            self.pal_map[a % COLORS] = b % COLORS

    def palt(self, c=-1, t=True):
        if c < 0:
            self.transparent = [False] * COLORS
            self.transparent[0] = True
        else:
            self.transparent[c % COLORS] = t

    def set_colour(self, c, r, g, b):
        """palette(c, r, g, b): colour c from red, green, blue 0..255."""
        r, g, b = (min(max(v, 0), 255) for v in (r, g, b))
        self.palette[c % COLORS] = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)

    def load_palette(self, colours):
        """A whole palette, as 64 (red, green, blue): what palette.pal gives."""
        for i, (r, g, b) in enumerate(colours):
            self.palette[i] = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)

    def colour(self, c):
        """palette(c): what colour c looks like now, widened back to 0..255."""
        p = self.palette[c % COLORS]
        r, g, b = (p >> 11) & 0x1F, (p >> 5) & 0x3F, p & 0x1F
        return (r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)

    def fade(self, amount):
        # The engine receives a 32-bit float; round the same way before use.
        amount = struct.unpack("<f", struct.pack("<f", amount))[0]
        amount = min(max(amount, 0.0), 1.0)
        self.fade_k = 32 - int(amount * 32.0 + 0.5)

    def shown_palette(self):
        """The palette as it reaches the screen: base colours with fade applied."""
        out = []
        for p in self.palette:
            r, g, b = (p >> 11) & 0x1F, (p >> 5) & 0x3F, p & 0x1F
            k = self.fade_k
            out.append((((r * k) >> 5) << 11) | (((g * k) >> 5) << 5) | ((b * k) >> 5))
        return out

    def scanout(self):
        shown = self.shown_palette()
        return [shown[v] for v in self.fb]

    # -- PNG export so a human can eyeball a golden image --
    def write_png(self, path, scale=1):
        write_png(path, self.scanout(), W, H, scale)


def write_png(path, rgb565, w, h, scale=1):
    rows = bytearray()
    for y in range(h):
        row = bytearray()
        for x in range(w):
            p = rgb565[y * w + x]
            r = ((p >> 11) & 0x1F) << 3
            g = ((p >> 5) & 0x3F) << 2
            b = (p & 0x1F) << 3
            row += bytes((r, g, b)) * scale
        rows += (b"\0" + row) * scale

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n" +
           chunk(b"IHDR", struct.pack(">IIBBBBB", w * scale, h * scale, 8, 2, 0, 0, 0)) +
           chunk(b"IDAT", zlib.compress(bytes(rows), 6)) +
           chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


# The Pulli palette: four blocks of 64, each 32 base hues and then the same
# hues at 9/16 brightness. Shadow pairs sit exactly 32 apart, so
# `pal(c, c+32)` darkens any sprite in one call and a whole scene can be
# dimmed without touching a pixel. The first block is the original 64; the
# second adds skin and earth, brass, maroons, greens, blues, purples, greys;
# the third saffron, teal, indigo, rose and olive ramps; the fourth sand,
# wood, moss, sea, sky, crimson, gold and cool greys.
_BASE = [
    0x000000, 0x1D2B53, 0x7E2553, 0x008751, 0xAB5236, 0x5F574F, 0xC2C3C7, 0xFFF1E8,
    0xFF004D, 0xFFA300, 0xFFEC27, 0x00E436, 0x29ADFF, 0x83769C, 0xFF77A8, 0xFFCCAA,
    0x291814, 0x111D35, 0x422136, 0x125359, 0x742F29, 0x49333B, 0xA28879, 0xF3EF7D,
    0xBE1250, 0xFF6C24, 0xA8E72E, 0x00B543, 0x065AB5, 0x754665, 0xFF6E59, 0xFF9D81,
]
_BASE2 = [
    0xF6D2B5, 0xE8B08A, 0xD08C5E, 0xB06E44, 0x8C5232, 0x6A3C24, 0x4C2A1A, 0x2E1A10,
    0xFFE7A0, 0xF2C14E, 0xC8962A, 0x9A6B1C, 0xE84A3C, 0xB0202E, 0x7A1028, 0x4E0A1E,
    0x9ED36A, 0x5FA845, 0x2F7A3A, 0x14492A, 0x8FD3FF, 0x4A8FE0, 0x2E4BB0, 0x1E2470,
    0xC27BE0, 0x8A3FB0, 0xF4A6C8, 0xD0607A, 0xF4F4F0, 0xB8B4AC, 0x7A7670, 0x3E3A38,
]
_BASE3 = [
    0xFFD27A, 0xFFB03A, 0xE58A12, 0xB8640A, 0x9CF0E0, 0x3CC8B4, 0x1A8C84, 0x0E5458,
    0xB4B8FF, 0x7078E8, 0x4040B8, 0x24207A, 0xFFC4D0, 0xF0889C, 0xC84868, 0x8A2444,
    0xE4E89A, 0xB8C055, 0x868C30, 0x565A1C, 0xFFF4D8, 0xE0D4B8, 0xA89C88, 0x6C6458,
    0xE8C8F8, 0xB890E0, 0x7C58B0, 0x4A2C78, 0xFFE8C0, 0xF8C890, 0xE0A070, 0xB87850,
]
_BASE4 = [
    0xF0DCA8, 0xD8BC80, 0xB89A5C, 0x8C7040, 0xC08858, 0x985E34, 0x6E3E20, 0x4A2814,
    0xBCE08C, 0x84B858, 0x5A8C38, 0x3A6024, 0x7CE0F0, 0x38A8D0, 0x1C70A8, 0x10447A,
    0xD8F0FF, 0xA8D4F8, 0xFF4040, 0xC8102C, 0xFFE060, 0xE0B020, 0xDCE4EC, 0x9CA8B8,
    0x707C8C, 0x404858, 0xF8F0B0, 0xD8C870, 0x60C0A0, 0x2E8A6C, 0xA03018, 0x601808,
]


def _shade(c, num=9, den=16):
    r, g, b = (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
    return ((r * num // den) << 16) | ((g * num // den) << 8) | (b * num // den)


DEFAULT_PALETTE = [c for b in (_BASE, _BASE2, _BASE3, _BASE4) for c in b + [_shade(x) for x in b]]


def rgb565(c):
    return (((c >> 16) & 0xFF) >> 3) << 11 | (((c >> 8) & 0xFF) >> 2) << 5 | ((c & 0xFF) >> 3)


def default_palette(g):
    for i in range(COLORS):
        g.palette[i] = rgb565(DEFAULT_PALETTE[i])
