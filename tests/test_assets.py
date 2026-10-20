#!/usr/bin/env python3
"""Pictures and maps: the PNG and Tiled importers, map.ooru, and the map API.

Run: python3 tests/test_assets.py

Map drawing is tested the way the other drawing is: tools/refgfx.py is the
reference and runtime/gfx.c must put the same pixels on the screen.
"""
import base64, gzip, os, random, struct, subprocess, sys, tempfile, zlib

from harness import Suite, ROOT, pulli

import refgfx   # noqa: E402  (tools/ is on the path once harness is imported)

MANIFEST = 'return { id = "test.assets", title = "Assets", spec = 1 }\n'


# ---- a PNG writer that can produce every kind the reader accepts ----------
def png(width, height, kind, depth, values, filters=(0,), colours=None, clear=None, interlace=0):
    """`values` holds one number per channel per pixel, row by row."""
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[kind]
    per_row = width * channels
    step = max(1, channels * depth // 8)
    rows, above = b"", bytes((per_row * depth + 7) // 8)
    for y in range(height):
        row_values = values[y * per_row:(y + 1) * per_row]
        if depth == 16:
            row = b"".join(struct.pack(">H", v) for v in row_values)
        elif depth == 8:
            row = bytes(row_values)
        else:
            bits = "".join(format(v, f"0{depth}b") for v in row_values)
            bits += "0" * (-len(bits) % 8)
            row = bytes(int(bits[i:i + 8], 2) for i in range(0, len(bits), 8))
        f, out = filters[y % len(filters)], bytearray()
        for i, v in enumerate(row):
            left = row[i - step] if i >= step else 0
            up = above[i]
            corner = above[i - step] if i >= step else 0
            p = left + up - corner
            paeth = min((abs(p - left), 0, left), (abs(p - up), 1, up), (abs(p - corner), 2, corner))[2]
            out.append((v - (0, left, up, (left + up) // 2, paeth)[f]) & 255)
        rows += bytes([f]) + bytes(out)
        above = row

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))
    body = chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, depth, kind, 0, 0, interlace))
    body += chunk(b"tEXt", b"Comment\0made by the test")            # a chunk to skip
    if colours is not None:
        body += chunk(b"PLTE", bytes(v for c in colours for v in c))
    if clear is not None:
        body += chunk(b"tRNS", bytes(clear))
    half = len(zlib.compress(rows)) // 2                             # the picture split across two chunks
    packed = zlib.compress(rows)
    return pulli.PNG_MAGIC + body + chunk(b"IDAT", packed[:half]) + chunk(b"IDAT", packed[half:]) + chunk(b"IEND", b"")


def rgba_png(width, height, pixels, **options):
    return png(width, height, 6, 8, [v for p in pixels for v in p], **options)


# ---- a Tiled map writer ------------------------------------------------------
def tmx(width, height, layers, encoding="csv", compression=None, tileset=None, tile=8, extra="", attrs=""):
    def data(gids):
        if encoding == "csv":
            return '<data encoding="csv">\n' + ",\n".join(
                ",".join(str(g) for g in gids[y * width:(y + 1) * width]) for y in range(height)) + "\n</data>"
        raw = struct.pack(f"<{len(gids)}I", *gids)
        if compression == "zlib":
            raw = zlib.compress(raw)
        elif compression == "gzip":
            raw = gzip.compress(raw)
        squeeze = f' compression="{compression}"' if compression else ""
        return f'<data encoding="base64"{squeeze}>\n   {base64.b64encode(raw).decode()}\n  </data>'
    tileset = tileset if tileset is not None else '<tileset firstgid="1" name="sprites" tilewidth="8" ' \
        'tileheight="8" tilecount="32" columns="8"><image source="sprites.png" width="64" height="32"/></tileset>'
    body = "".join(f'<layer id="{i + 1}" name="layer {i}" width="{width}" height="{height}">{data(g)}</layer>'
                   for i, g in enumerate(layers))
    return (f'<?xml version="1.0" encoding="UTF-8"?>\n<map version="1.10" orientation="orthogonal" '
            f'renderorder="right-down" width="{width}" height="{height}" tilewidth="{tile}" tileheight="{tile}" '
            f'infinite="0" {attrs}>{tileset}{body}{extra}</map>')


H, V, D = 0x80000000, 0x40000000, 0x20000000


def main():
    t = Suite("Pulli pictures and maps")
    colours = pulli.palette()

    def refuses(name, fn, *needles):
        try:
            fn()
            t.check(name, False, "accepted")
        except pulli.PackageError as e:
            t.check(name, all(n in str(e) for n in needles), str(e))

    # ---- reading PNG files --------------------------------------------------
    rng = random.Random(1)
    w, h = 16, 8
    picture = [tuple(rng.randrange(256) for _ in range(4)) for _ in range(w * h)]
    t.check("a PNG with red, green, blue and alpha is read exactly",
            pulli.read_png(rgba_png(w, h, picture)) == (w, h, picture))
    for f, label in enumerate(("none", "left", "up", "average", "Paeth")):
        t.check(f"PNG rows stored with the '{label}' filter are read exactly",
                pulli.read_png(rgba_png(w, h, picture, filters=(f,)))[2] == picture)
    t.check("a PNG that mixes filters row by row is read exactly",
            pulli.read_png(rgba_png(w, h, picture, filters=(4, 1, 3, 2, 0)))[2] == picture)
    solid = [p[:3] for p in picture]
    t.check("a PNG without alpha is fully solid",
            pulli.read_png(png(w, h, 2, 8, [v for p in solid for v in p], filters=(4,)))[2]
            == [p + (255,) for p in solid])
    t.check("a 16-bit PNG keeps its top 8 bits",
            pulli.read_png(png(w, h, 2, 16, [v * 257 for p in solid for v in p], filters=(3,)))[2]
            == [p + (255,) for p in solid])
    grey = [rng.randrange(256) for _ in range(w * h)]
    t.check("a grey PNG is read as grey",
            pulli.read_png(png(w, h, 0, 8, grey))[2] == [(g, g, g, 255) for g in grey])
    t.check("a grey PNG with alpha keeps its alpha",
            pulli.read_png(png(w, h, 4, 8, [v for g in grey for v in (g, 255 - g)]))[2]
            == [(g, g, g, 255 - g) for g in grey])
    t.check("a 1-bit PNG is black and white",
            pulli.read_png(png(11, 3, 0, 1, [i % 2 for i in range(33)]))[2]
            == [(255 * (i % 2),) * 3 + (255,) for i in range(33)])
    table = [(10 * i, 255 - 10 * i, 7 * i) for i in range(16)]
    for depth in (1, 2, 4, 8):
        n = min(16, 1 << depth)
        indexed = [rng.randrange(n) for _ in range(13 * 5)]         # 13 wide: rows end mid-byte
        t.check(f"a {depth}-bit PNG with a colour table is read through its table",
                pulli.read_png(png(13, 5, 3, depth, indexed, colours=table[:n], clear=[0, 128]))[2]
                == [table[i] + ((0, 128) + (255,) * 14)[i:i + 1] for i in indexed])
    refuses("a file that is not PNG is refused", lambda: pulli.read_png(b"GIF89a" + bytes(40), "a.png"), "a.png")
    refuses("an interlaced PNG is refused with advice",
            lambda: pulli.read_png(rgba_png(w, h, picture, interlace=1)), "interlac")
    refuses("a cut-off PNG is refused", lambda: pulli.read_png(rgba_png(w, h, picture)[:-40]), "damaged")
    refuses("a PNG whose size does not match its data is refused",
            lambda: pulli.read_png(rgba_png(w, h + 1, picture)), "damaged")
    t.check("a PNG written by the tool reads back the same",
            pulli.read_png(pulli.write_png(8, 8, bytes(v for c in colours for v in c)))[2]
            == [c + (255,) for c in colours])

    # ---- pictures into sprite sheets ------------------------------------------
    notes = []
    exact = [colours[i] + (255,) for i in range(64)]
    sheet = pulli.kolam_from_png(rgba_png(8, 8, exact), notes=notes)
    t.check("palette colours come through as themselves, and solid black as colour 32",
            sheet[:8] == b"KLM1" + struct.pack("<HH", 8, 8) and list(sheet[8:]) == [32] + list(range(1, 64))
            and notes == [])
    red = colours[8]
    clear = [red + (0,), red + (127,), red + (128,), (0, 0, 0, 255)] * 16
    t.check("see-through pixels become colour 0, whatever their colour",
            list(pulli.kolam_from_png(rgba_png(8, 8, clear), notes=notes)[8:12]) == [0, 0, 8, 32])
    notes = []
    off = [(colours[8][0] - 3, colours[8][1] + 2, colours[8][2] + 1, 255), (1, 1, 1, 255)] * 32
    t.check("other colours go to the nearest palette colour, and the developer is told",
            list(pulli.kolam_from_png(rgba_png(8, 8, off), "art.png", notes)[8:10]) == [8, 32]
            and len(notes) == 1 and "art.png" in notes[0] and "2 colour" in notes[0], notes)
    refuses("a sheet that is not a multiple of 8 pixels is refused",
            lambda: pulli.kolam_from_png(rgba_png(12, 8, exact[:60] + exact[:36]), "s.png"), "s.png", "multiples of 8")
    refuses("a sheet with more than 128 KB of pixels is refused",
            lambda: pulli.kolam_from_png(png(512, 264, 0, 1, [0] * (512 * 264)), "big.png"), "big.png", "at most")

    # ---- the palette for a paint program ---------------------------------------
    with tempfile.TemporaryDirectory() as tmp:
        for ext in ("gpl", "hex", "png"):
            subprocess.run([sys.executable, os.path.join(ROOT, "tools", "pulli.py"), "palette",
                            os.path.join(tmp, "p." + ext)], check=True, capture_output=True)
        gpl = open(os.path.join(tmp, "p.gpl")).read().splitlines()
        t.check("the palette is written for GIMP, Aseprite and Krita",
                gpl[0] == "GIMP Palette" and [tuple(int(v) for v in l.split()[:3]) for l in gpl[4:]] == colours)
        t.check("the palette is written as hex and as a picture",
                [tuple(bytes.fromhex(l)) for l in open(os.path.join(tmp, "p.hex")).read().split()] == colours
                and pulli.read_png(open(os.path.join(tmp, "p.png"), "rb").read())[2] == [c + (255,) for c in colours])

    # ---- a game's own palette ------------------------------------------------------
    mine = [((i * 4) % 256, (i * 9) % 256, (i * 17) % 256) for i in range(64)]
    hexfile = "".join("%02x%02x%02x\n" % c for c in mine).encode()
    gpl = ("GIMP Palette\nName: Mine\nColumns: 8\n# a comment\n" +
           "".join(f"{r:3} {g:3} {b:3}\tcolour {i}\n" for i, (r, g, b) in enumerate(mine))).encode()
    t.check("a palette.hex is read", pulli.read_palette(hexfile) == mine)
    t.check("a GIMP .gpl palette, as Aseprite and Krita write it, is read", pulli.read_palette(gpl) == mine)
    t.check("a hex palette may use # before each colour and blank lines",
            pulli.read_palette(b"\n".join(b"#" + l for l in hexfile.split()) + b"\n\n") == mine)
    refuses("a palette of 63 colours is refused", lambda: pulli.read_palette(b"\n".join(hexfile.split()[:63]), "p.hex"),
            "p.hex", "63", "exactly 64")
    refuses("a palette line that is not a colour is refused", lambda: pulli.read_palette(hexfile + b"purple\n", "p.hex"), "purple")
    refuses("a colour above 255 in a .gpl is refused", lambda: pulli.read_palette(gpl.replace(b"  4   9", b"400   9"), "p.gpl"), "400")
    t.check("a palette.pal entry holds the colours after a magic and nothing else",
            pulli.palette_entry(mine) == b"PAL1" + bytes(v for c in mine for v in c) and len(pulli.palette_entry(mine)) == 196)
    off = [mine[20] + (255,), mine[21] + (255,), (mine[22][0] + 2, mine[22][1], mine[22][2], 255), (0, 0, 0, 0)] * 16
    notes = []
    sheet = pulli.kolam_from_png(rgba_png(8, 8, off), "x.png", notes, mine)
    t.check("a picture is matched to the game's own palette: its colours come out as their numbers there",
            list(sheet[8:12]) == [20, 21, 22, 0] and len(notes) == 1 and "1 colour" in notes[0], (list(sheet[8:12]), notes))
    default_sheet = pulli.kolam_from_png(rgba_png(8, 8, off), "x.png", [])
    t.check("the same picture matched to the default palette gives other numbers", list(default_sheet[8:11]) != [20, 21, 22])
    with tempfile.TemporaryDirectory() as tmp:
        for name, data in (("manifest.lua", MANIFEST.encode()), ("main.lua", b"dbg(1)"), ("palette.hex", hexfile),
                           ("sprites.png", rgba_png(8, 8, [mine[30] + (255,)] * 64))):
            open(os.path.join(tmp, name), "wb").write(data)
        packed = dict(pulli.parse(pulli.build(tmp)))
        t.check("pack turns palette.hex into palette.pal, leaves the source out, and matches pictures to it",
                packed["palette.pal"] == pulli.palette_entry(mine) and "palette.hex" not in packed
                and set(packed["sprites.kolam"][8:]) == {30})
        os.remove(os.path.join(tmp, "palette.hex"))
        open(os.path.join(tmp, "palette.gpl"), "wb").write(gpl)
        t.check("a palette.gpl packs the same way", dict(pulli.parse(pulli.build(tmp)))["palette.pal"] == pulli.palette_entry(mine))
        open(os.path.join(tmp, "palette.hex"), "wb").write(hexfile)
        refuses("a game with both palette.hex and palette.gpl is refused", lambda: pulli.build(tmp), "palette.hex", "palette.gpl")
        os.remove(os.path.join(tmp, "palette.hex"))
        open(os.path.join(tmp, "palette.pal"), "wb").write(b"PAL1")
        refuses("a ready-made palette.pal beside a source is refused", lambda: pulli.build(tmp), "palette.pal", "palette.gpl")
        os.remove(os.path.join(tmp, "palette.gpl"))
        open(os.path.join(tmp, "palette.pal"), "wb").write(pulli.palette_entry(mine))
        packed = dict(pulli.parse(pulli.build(tmp)))
        t.check("a ready-made palette.pal is packed, and pictures are matched to it too",
                packed["palette.pal"] == pulli.palette_entry(mine) and set(packed["sprites.kolam"][8:]) == {30})
        open(os.path.join(tmp, "palette.pal"), "wb").write(b"PAL1" + bytes(10))
        refuses("a ready-made palette.pal that is not 64 colours is refused", lambda: pulli.build(tmp), "palette.pal")

        # The palette command, for a paint program: the standard colours, or a game's own.
        tool = [sys.executable, os.path.join(ROOT, "tools", "pulli.py"), "palette"]
        os.remove(os.path.join(tmp, "palette.pal"))
        open(os.path.join(tmp, "palette.hex"), "wb").write(hexfile)
        out = os.path.join(tmp, "out.gpl")
        r = subprocess.run(tool + [tmp, out], capture_output=True, text=True)
        t.check("pulli.py palette <game> writes the game's own colours",
                r.returncode == 0 and pulli.read_palette(open(out, "rb").read()) == mine and "own" in r.stdout, r.stdout + r.stderr)
        pkg = os.path.join(tmp, "game.pulli")
        open(pkg, "wb").write(pulli.build(tmp))
        for ext in ("gpl", "hex", "png"):
            out = os.path.join(tmp, "from-package." + ext)
            subprocess.run(tool + [pkg, out], capture_output=True)
            data = open(out, "rb").read()
            got = [p[:3] for p in pulli.read_png(data)[2]] if ext == "png" else pulli.read_palette(data)
            t.check(f"pulli.py palette <game.pulli> writes the game's own colours as .{ext}", got == mine)
        os.remove(os.path.join(tmp, "palette.hex"))
        r = subprocess.run(tool + [tmp, out], capture_output=True, text=True)
        t.check("for a game with no palette of its own, the standard colours are written, and it says so",
                [p[:3] for p in pulli.read_png(open(out, "rb").read())[2]] == colours and "no palette of its own" in r.stdout,
                r.stdout)

    # ---- maps from Tiled ---------------------------------------------------------
    with tempfile.TemporaryDirectory() as tmp:
        def imported(text, columns=8, notes=None, name="map.tmx"):
            open(os.path.join(tmp, name), "w").write(text)
            return pulli.read_ooru(pulli.ooru_from_tmx(os.path.join(tmp, name), columns, notes))

        gids = [0, 1, 2, 9, 3 | H, 4 | V, 5 | H | V, 32]
        want = [0, 0, 1, 8, 2 | pulli.FLIP_X, 3 | pulli.FLIP_Y, 4 | pulli.FLIP_X | pulli.FLIP_Y, 31]
        notes = []
        t.check("Tiled's tile numbers become sprite numbers, and its flips are kept",
                imported(tmx(4, 2, [gids]), notes=notes) == (4, 2, [want], b""))
        t.check("the developer is told when a map uses the sheet's first tile", len(notes) == 1 and "first tile" in notes[0])
        for encoding, squeeze in (("base64", None), ("base64", "zlib"), ("base64", "gzip")):
            t.check(f"a map saved as {encoding}{' + ' + squeeze if squeeze else ''} imports the same",
                    imported(tmx(4, 2, [gids], encoding, squeeze))[2] == [want])
        second = [7] * 8
        t.check("the first two tile layers become layers 0 and 1",
                imported(tmx(4, 2, [gids, second]))[2] == [want, [6] * 8])
        flagged = ('<tileset firstgid="1" name="s" tilewidth="8" tileheight="8" tilecount="32" columns="8">'
                   '<image source="sprites.png" width="64" height="32"/>'
                   '<tile id="3"><properties><property name="solid" type="bool" value="true"/></properties></tile>'
                   '<tile id="5"><properties><property name="flags" type="int" value="130"/>'
                   '<property name="solid" type="bool" value="true"/></properties></tile>'
                   '<tile id="9"><properties><property name="solid" type="bool" value="false"/></properties></tile>'
                   '</tileset>')
        t.check("tile properties 'solid' and 'flags' become the tile's flags",
                imported(tmx(4, 2, [gids], tileset=flagged))[3] == bytes([0, 0, 0, 1, 0, 131]))
        open(os.path.join(tmp, "tiles.tsx"), "w").write('<?xml version="1.0"?>' + flagged.replace(' firstgid="1"', ""))
        t.check("a tileset kept in its own file is followed",
                imported(tmx(4, 2, [gids], tileset='<tileset firstgid="1" source="tiles.tsx"/>'))[3]
                == bytes([0, 0, 0, 1, 0, 131]))
        notes = []
        imported(tmx(4, 2, [second], extra='<objectgroup id="9" name="things"/>'), notes=notes)
        t.check("object layers are left out, and the developer is told", len(notes) == 1 and "object" in notes[0])

        refuses("a rotated tile is refused", lambda: imported(tmx(4, 2, [[1 | D] * 8])), "map.tmx", "rotated")
        refuses("a map with tiles that are not 8x8 is refused", lambda: imported(tmx(4, 2, [second], tile=16)), "8x8")
        refuses("an infinite map is refused with advice",
                lambda: imported(tmx(4, 2, [second]).replace('infinite="0"', 'infinite="1"')), "Infinite")
        refuses("a map that is not on a square grid is refused",
                lambda: imported(tmx(4, 2, [second]).replace("orthogonal", "isometric")), "orthogonal")
        refuses("three tile layers are refused", lambda: imported(tmx(4, 2, [second] * 3)), "3 layers")
        refuses("two tilesets are refused",
                lambda: imported(tmx(4, 2, [second], tileset='<tileset firstgid="1" columns="8"/>'
                                                             '<tileset firstgid="33" columns="8"/>')), "2 tilesets")
        refuses("a tileset narrower than the sprite sheet is refused, since the numbers would not match",
                lambda: imported(tmx(4, 2, [second]), columns=16), "8 tiles wide", "16")
        refuses("a missing tileset file is refused",
                lambda: imported(tmx(4, 2, [second], tileset='<tileset firstgid="1" source="gone.tsx"/>')), "gone.tsx")
        refuses("a layer of the wrong size is refused", lambda: imported(tmx(4, 3, [second])), "8 tiles")
        refuses("a map too large for the console is refused", lambda: imported(tmx(200, 100, [[1] * 20000] * 2)),
                "at most")
        refuses("a file that is not a Tiled map is refused", lambda: imported("<svg/>"), "not a Tiled map")
        refuses("a layer format the importer cannot read is refused with advice",
                lambda: imported(tmx(4, 2, [second], "base64", "zstd")), "CSV")

    # ---- packing a game's folder -------------------------------------------------
    rng = random.Random(2)
    atlas = [rng.choice([0, 0] + list(range(1, 64))) for _ in range(64 * 32)]
    for i in range(64):
        atlas[(i // 8) * 64 + i % 8] = 0                           # tile 0 blank, as maps expect
    sheet_png = rgba_png(64, 32, [colours[c] + (255,) if c else (0, 0, 0, 0) for c in atlas])
    with tempfile.TemporaryDirectory() as tmp:
        for name, data in (("manifest.lua", MANIFEST.encode()), ("main.lua", b""), ("sprites.png", sheet_png),
                           ("map.tmx", tmx(4, 2, [[2] * 8], tileset='<tileset firstgid="1" source="tiles.tsx"/>').encode()),
                           ("cave.tmx", tmx(3, 3, [[3] * 9, [4] * 9]).encode()),
                           ("tiles.tsx", b'<tileset name="s" tilewidth="8" tileheight="8" columns="8"/>')):
            open(os.path.join(tmp, name), "wb").write(data)
        notes = []
        entries = dict(pulli.parse(pulli.build(tmp, notes=notes)))
        t.check("pack turns .png into .kolam and .tmx into .ooru, and leaves the sources out",
                sorted(entries) == ["cave.ooru", "main.lua", "manifest.lua", "map.ooru", "sprites.kolam"] and notes == [],
                (sorted(entries), notes))
        t.check("the packed sheet holds the picture's colours",
                entries["sprites.kolam"] == pulli.kolam(64, 32, bytes(atlas)))
        listing = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "pulli.py"), "pack", tmp,
                                  os.path.join(tmp, "out.pulli")], capture_output=True, text=True)
        listing = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "pulli.py"), "list",
                                  os.path.join(tmp, "out.pulli")], capture_output=True, text=True).stdout
        t.check("list describes sheets and maps", "64x32 pixels, sprites 0 to 31" in listing
                and "3x3 tiles, 2 layer(s)" in listing, listing)
        open(os.path.join(tmp, "wide.tmx"), "w").write(
            tmx(4, 2, [[2] * 8], tileset='<tileset firstgid="1" columns="16"/>'))
        refuses("pack checks each map's tileset against the sprite sheet", lambda: pulli.build(tmp), "wide.tmx", "16")
        os.remove(os.path.join(tmp, "wide.tmx"))
        open(os.path.join(tmp, "map.ooru"), "wb").write(b"ORU1")
        refuses("a ready-made file and its source side by side are refused", lambda: pulli.build(tmp),
                "map.ooru", "map.tmx")

    if not t.need_runtime("maps in the runtime"):
        return t.finish()

    # ---- a game's own palette in the runtime -----------------------------------------
    def px(res, x, y):
        return int.from_bytes(res.rgb[2 * (y * 320 + x):2 * (y * 320 + x) + 2], "little")
    def rgb565(c):
        return ((c[0] >> 3) << 11) | ((c[1] >> 2) << 5) | (c[2] >> 3)
    own = {"palette.pal": pulli.palette_entry(mine)}
    r = t.run_game("function draw() cls(0) rectfill(10, 10, 10, 10, 9) end", extra=own)
    t.check("a game with its own palette shows its colours",
            r.code == 0 and px(r, 0, 0) == rgb565(mine[0]) and px(r, 15, 15) == rgb565(mine[9]), r.err)
    r = t.run_game("function draw() cls(0) palette(0, 255, 255, 255) palette() rectfill(10, 10, 10, 10, 9) end", extra=own)
    t.check("palette() puts back the game's own colours, not the standard ones",
            r.code == 0 and px(r, 0, 0) == rgb565(mine[0]) and px(r, 15, 15) == rgb565(mine[9]), r.err)
    plain = t.run_game("function draw() cls(0) end")
    t.check("a game without one shows the standard colours", px(plain, 0, 0) == 0 and px(plain, 0, 0) != rgb565(mine[0]) or mine[0] == (0, 0, 0))
    expect_lines = lambda name, lua, lines, extra=None: t.check(
        name, (lambda r: r.code == 0 and r.lines == lines or print(r.lines, r.err))(t.run_game(lua, extra=extra)))
    std = refgfx.RefGfx()
    want = "\t".join(str(v) for v in std.colour(8))
    expect_lines("palette(c) tells what colour c looks like, to the precision the screen keeps",
                 "dbg(palette(8)) palette(9, 255, 0, 128) dbg(palette(9)) palette(73, 1, 2, 3) dbg(palette(9))"
                 " palette() dbg(palette(9)) dbg(palette(0)) dbg(palette(64 + 7))",
                 [want, "255\t0\t132", "0\t0\t0", "\t".join(str(v) for v in std.colour(9)), "0\t0\t0",
                  "\t".join(str(v) for v in std.colour(7))])
    ownref = refgfx.RefGfx()
    ownref.load_palette(mine)
    expect_lines("palette(c) reads a game's own colours too",
                 "dbg(palette(20))", ["\t".join(str(v) for v in ownref.colour(20))], own)

    # Palette changes against the reference rasterizer: what reaches the screen must match exactly.
    for label, files, base in (("the standard palette", {}, None), ("a game's own", own, mine)):
        ref = refgfx.RefGfx()
        if base:
            ref.load_palette(base)
        ref.cls(1)
        for i in range(64):
            ref.rectfill((i % 16) * 20, (i // 16) * 20, 18, 18, i)
        ref.set_colour(5, 250, 10, 99)
        ref.set_colour(70, 300, -4, 33)
        ref.pal(3, 5)
        ref.rectfill(0, 100, 320, 20, 3)
        ref.fade(0.3)
        lua = ("function draw() cls(1) for i = 0, 63 do rectfill((i % 16) * 20, (i // 16) * 20, 18, 18, i) end"
               " palette(5, 250, 10, 99) palette(70, 300, -4, 33) pal(3, 5) rectfill(0, 100, 320, 20, 3) fade(0.3) end")
        r = t.run_game(lua, extra=files)
        want_rgb = b"".join(p.to_bytes(2, "little") for p in ref.scanout())
        t.check(f"colours set while running, with pal() and fade(), match the reference exactly: {label}",
                r.code == 0 and r.rgb == want_rgb, r.err)

    for name, blob, why in (("one of the wrong length", b"PAL1" + bytes(100), "palette.pal"),
                            ("one with the wrong magic", b"XXXX" + bytes(192), "palette.pal")):
        r = t.run_game("", extra={"palette.pal": blob})
        t.check(f"a palette.pal {name} stops the game from starting", r.code == 1 and why in r.err, r.err)

    # ---- drawing: the runtime against the reference ---------------------------------
    rng = random.Random(3)
    mw, mh = 70, 50                                                # larger than the screen both ways
    def cells():
        out = []
        for _ in range(mw * mh):
            tile = rng.choice([0, 0, rng.randrange(1, 32), rng.randrange(1, 32), rng.randrange(1, 40)])
            out.append(tile | rng.choice([0, 0, pulli.FLIP_X, pulli.FLIP_Y, pulli.FLIP_X | pulli.FLIP_Y]) if tile else 0)
        return out
    layers = [cells(), cells()]
    game_files = {"sprites.kolam": pulli.kolam(64, 32, bytes(atlas)), "map.ooru": pulli.ooru(mw, mh, layers)}

    #  camera,       clip,                 map.draw calls as (layer, sx, sy)
    scenes = [
        ((0, 0),       None,               [(0, 0, 0)]),
        ((0, 0),       None,               [(0, 0, 0), (1, 0, 0)]),
        ((37, 21),     None,               [(0, 0, 0), (1, 0, 0)]),             # the camera moves both
        ((0, 0),       None,               [(0, 37, 21)]),                      # so does a scroll
        ((100, 60),    None,               [(0, 50, 30), (1, 0, 0)]),           # layers at different speeds
        ((-13, -5),    None,               [(0, 0, 0)]),                        # the map's top-left corner in view
        ((250, 170),   None,               [(0, 0, 0), (1, 3, 3)]),             # its bottom-right corner in view
        ((0, 0),       None,               [(0, -100, -90), (1, 600, 0)]),      # pushed right and down; pushed away
        ((-9, 400),    None,               [(1, 9, -9)]),
        ((16, 8),      (40, 30, 200, 100), [(0, 0, 0), (1, -4, 12)]),           # inside a clip window
        ((0, 0),       None,               [(0, 7, 7), (0, 0, 0), (2, 0, 0), (-1, 0, 0)]),   # no such layers
        ((-32768, 32767), None,            [(0, -32768, 32767), (1, 32767, -32768)]),        # the far corners
    ]
    for cam, clip, draws in scenes:
        ref = refgfx.RefGfx()
        ref.atlas, ref.atlas_w, ref.atlas_h = atlas, 64, 32
        ref.cls(1)
        ref.camera(*cam)
        lua = [f"function draw() cls(1) camera({cam[0]}, {cam[1]})"]
        if clip:
            ref.set_clip(*clip)
            lua.append(f"clip({', '.join(map(str, clip))})")
        for layer, sx, sy in draws:
            if 0 <= layer < 2:
                ref.map_draw(layers[layer], mw, mh, sx, sy)
            lua.append(f"map.draw({layer}, {sx}, {sy})")
        r = t.run_game(" ".join(lua + ["end"]), extra=game_files)
        drawn = sum(1 for v in ref.fb if v != 1)
        t.check(f"map drawn as the reference draws it: camera {cam}, clip {clip}, layers {draws} ({drawn} pixels)",
                r.code == 0 and r.fb == bytes(ref.fb), r.err)
    r = t.run_game("function draw() cls(1) map.draw(0) map.draw(1) end", extra=game_files)
    ref = refgfx.RefGfx()
    ref.atlas, ref.atlas_w, ref.atlas_h = atlas, 64, 32
    ref.cls(1)
    ref.map_draw(layers[0], mw, mh)
    ref.map_draw(layers[1], mw, mh)
    t.check("map.draw needs no scroll, and the scenes above are not blank",
            r.fb == bytes(ref.fb) and sum(1 for v in ref.fb if v != 1) > 20000)

    # ---- the map functions -----------------------------------------------------------
    def expect(name, lua, lines, extra=None):
        r = t.run_game(lua, extra=game_files if extra is None else extra)
        t.check(name, r.code == 0 and r.lines == lines, f"stdout: {r.lines}\nwanted: {lines}\nstderr: {r.err}")

    small = pulli.ooru(3, 2, [[1, 2 | pulli.FLIP_X, 3 | pulli.FLIP_Y, 0, 5, 16383], [9] * 6], bytes([0, 1, 0, 200]))
    two = {"map.ooru": small, "cave.ooru": pulli.ooru(5, 4, [[7] * 20])}
    expect("a game with a map.ooru starts with it loaded", "dbg(map.size()) dbg((map.get(0, 0, 0)), (map.get(1, 2, 1)))",
           ["3\t2", "1\t9"], two)
    expect("map.get gives the tile and how it is flipped",
           "dbg(map.get(0, 1, 0)) dbg(map.get(0, 2, 0)) dbg(map.get(0, 0, 1)) dbg(map.get(0, 2, 1))",
           ["2\ttrue\tfalse", "3\tfalse\ttrue", "0\tfalse\tfalse", "16383\tfalse\tfalse"], two)
    expect("outside the map, and on a layer that is not there, map.get gives 0",
           "dbg((map.get(0, 3, 0)), (map.get(0, 0, 2)), (map.get(0, -1, 0)), (map.get(2, 0, 0)), (map.get(-1, 0, 0)))",
           ["0\t0\t0\t0\t0"], two)
    expect("map.set changes a tile, with flips, and ignores what is outside the map",
           "map.set(0, 0, 0, 12) map.set(1, 1, 1, 4, true, true) map.set(0, 3, 0, 5) map.set(0, 0, 0, 99999)"
           " map.set(0, 1, 0, -1) map.set(2, 0, 0, 5)"
           " dbg(map.get(0, 0, 0)) dbg(map.get(1, 1, 1)) dbg(map.get(0, 1, 0))",
           ["12\tfalse\tfalse", "4\ttrue\ttrue", "2\ttrue\tfalse"], two)
    expect("map.flags gives a tile's flags, and 0 for a tile that has none",
           "dbg(map.flags(0), map.flags(1), map.flags(3), map.flags(4), map.flags(-1), map.flags(20000))",
           ["0\t1\t200\t0\t0\t0"], two)
    expect("map.load swaps in another map, and reloading undoes map.set",
           "map.load('cave.ooru') dbg(map.size()) dbg((map.get(0, 4, 3)), (map.get(1, 0, 0)), map.flags(1))"
           " map.load('map.ooru') map.set(0, 0, 0, 30) map.load() dbg((map.get(0, 0, 0)), map.flags(1))",
           ["5\t4", "7\t0\t0", "1\t1"], two)
    expect("with no map, the map functions are harmless",
           "function draw() map.draw(0) end dbg(map.size()) dbg((map.get(0, 0, 0)), map.flags(1)) map.set(0, 0, 0, 1)",
           ["0\t0", "0\t0"], {})
    r = t.run_game("map.load('nowhere.ooru')", extra=two)
    t.check("loading a map the package does not have is an error that names it",
            r.code == 1 and "nowhere.ooru" in r.err, r.err)
    r = t.run_game("map.load('main.lua')", extra=two)
    t.check("loading something that is not a map is an error", r.code == 1 and "not a map" in r.err, r.err)
    r = t.run_game("local f = 0 function update() f = f + 1 map.set(0, f % 3, 0, f) end"
                   " function draw() cls() map.draw(0) map.draw(1) end", extra=dict(game_files, **two), frames=30)
    t.check("a game can redraw a changing map every frame", r.code == 0, r.err)

    # ---- bad maps --------------------------------------------------------------------
    def bad(name, blob, *needles, entry="map.ooru"):
        r = t.run_game("" if entry == "map.ooru" else f"map.load('{entry}')", extra={entry: blob})
        t.check(name, r.code == 1 and entry in r.err and all(n in r.err for n in needles), f"exit {r.code}\n{r.err}")

    def patched(offset, fmt, value):
        b = bytearray(small)
        struct.pack_into(fmt, b, offset, value)
        return bytes(b)
    bad("a map with the wrong magic is refused", b"KLM1" + small[4:], "not a map")
    bad("a cut-off map is refused", small[:-1], "does not match")
    bad("a map with bytes left over is refused", small + b"\0", "does not match")
    bad("a map with three layers is refused", patched(8, "<B", 3), "one or two layers")
    bad("a map with no layers is refused", patched(8, "<B", 0), "one or two layers")
    bad("a map of no width is refused", patched(4, "<H", 0), "empty or too large")
    bad("a map past the console's limit is refused",
        b"ORU1" + struct.pack("<HHBBH", 200, 100, 2, 0, 0) + bytes(80000), "too large")
    bad("a bad map under any name stops the game when it is loaded", small[:-1], "does not match", entry="cave.ooru")
    r = t.run_game("", extra={"cave.ooru": small[:-1]})
    t.check("a bad map the game never loads is never read, so it does not stop the game", r.code == 0, r.err)
    limit = pulli.ooru(128, 128, [[1] * 16384, [2] * 16384], bytes(16384))
    r = t.run_game("dbg(map.size()) dbg((map.get(1, 127, 127)))", extra={"map.ooru": limit})
    t.check("the largest map the format allows loads", r.code == 0 and r.lines == ["128\t128", "2"], r.err)
    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
