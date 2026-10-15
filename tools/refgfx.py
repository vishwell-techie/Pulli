#!/usr/bin/env python3
"""refgfx.py — reference implementation of the Pulli rasterizer.

This exists so we can catch the class of bug that otherwise only shows up
after the firmware port: the C engine and the device quietly disagreeing
about where a pixel goes. Every primitive in runtime/gfx.c is mirrored here
in the most obvious possible way, and the conformance harness renders the
same scene through both and compares byte-for-byte.

Slow and readable is the whole point. Do not optimise this file.
"""
import os, struct, zlib

W, H = 320, 240
CELL = 8
COLORS = 64          # palette length; colour indices wrap modulo this

_FONT_TXT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "..", "runtime", "font.txt")


def load_font(path=_FONT_TXT):
    """Parse runtime/font.txt into 96 glyphs of 8 row bytes (bit 7 = left)."""
    glyphs, code, rows = {}, None, []
    for n, line in enumerate(open(path, encoding="ascii"), 1):
        line = line.rstrip("\n")
        if not line or line.startswith(";"):
            continue
        if line.startswith("="):
            code, rows = int(line.split()[1]), []
            glyphs[code] = rows
        elif len(line) == 8 and set(line) <= set(".#") and code is not None:
            rows.append(sum(0x80 >> i for i, ch in enumerate(line) if ch == "#"))
        else:
            raise ValueError(f"{path}:{n}: not a glyph row: {line!r}")
    if sorted(glyphs) != list(range(32, 128)) or any(len(r) != 8 for r in glyphs.values()):
        raise ValueError(f"{path}: need exactly 8 rows for each of codes 32..127")
    return [glyphs[c] for c in range(32, 128)]


_FONT_TA_TXT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "..", "runtime", "font_ta.txt")


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
    """One line of characters as ("en", code) and ("ta", letters) pieces.
    Tamil is matched longest first, so a syllable comes out whole."""
    out, i = [], 0
    while i < len(cps):
        cp = cps[i]
        if 0 <= cp < 128:
            if cp >= 32:
                out.append(("en", cp))
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
    ("en", code, x, y) and ("ta", letters, x, y) for each glyph, giving where
    its top-left goes, then ("end", x, height) where the line ends. x and y
    are offsets from where the text starts. A line holding Tamil is ta.rows
    tall and its English is lowered to share the baseline; any other is 8."""
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
        height, lower = (ta.rows, ta.above) if tamil else (CELL, 0)
        x = 0
        for kind, what in pieces:
            if kind == "en":
                yield ("en", what, x, y + lower)
                x += CELL
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
        self.font = load_font()
        self.font_ta = TamilFont()
        default_palette(self)

    # -- single choke point, mirrors put() in gfx.c --
    def _put(self, x, y, c):
        x -= self.cam[0]
        y -= self.cam[1]
        cx, cy, cw, ch = self.clip
        if not (cx <= x < cx + cw and cy <= y < cy + ch):
            return
        self.fb[y * W + x] = self.pal_map[c % COLORS]

    def cls(self, c=0):
        v = self.pal_map[c % COLORS]
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

    def sspr(self, sx, sy, sw, sh, dx, dy, dw, dh):
        if not self.atlas or sw <= 0 or sh <= 0 or dw <= 0 or dh <= 0:
            return
        for j in range(dh):
            ty = sy + (j * sh) // dh
            if not (0 <= ty < self.atlas_h):
                continue
            for i in range(dw):
                tx = sx + (i * sw) // dw
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
                glyph = self.font[item[1] - 32]
                for j in range(CELL):
                    for i in range(CELL):
                        if glyph[j] & (0x80 >> i):
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


# The 64-colour Pulli palette (spec v0.1): 32 base hues plus a shadow ramp of
# the same hues at 9/16 brightness. Shadow pairs sit exactly 32 apart, so
# `pal(c, c+32)` darkens any sprite in one call and a whole scene can be
# dimmed without touching a pixel.
_BASE = [
    0x000000, 0x1D2B53, 0x7E2553, 0x008751, 0xAB5236, 0x5F574F, 0xC2C3C7, 0xFFF1E8,
    0xFF004D, 0xFFA300, 0xFFEC27, 0x00E436, 0x29ADFF, 0x83769C, 0xFF77A8, 0xFFCCAA,
    0x291814, 0x111D35, 0x422136, 0x125359, 0x742F29, 0x49333B, 0xA28879, 0xF3EF7D,
    0xBE1250, 0xFF6C24, 0xA8E72E, 0x00B543, 0x065AB5, 0x754665, 0xFF6E59, 0xFF9D81,
]


def _shade(c, num=9, den=16):
    r, g, b = (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
    return ((r * num // den) << 16) | ((g * num // den) << 8) | (b * num // den)


DEFAULT_PALETTE = _BASE + [_shade(c) for c in _BASE]


def rgb565(c):
    return (((c >> 16) & 0xFF) >> 3) << 11 | (((c >> 8) & 0xFF) >> 2) << 5 | ((c & 0xFF) >> 3)


def default_palette(g):
    for i in range(COLORS):
        g.palette[i] = rgb565(DEFAULT_PALETTE[i])
