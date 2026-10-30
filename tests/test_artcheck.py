#!/usr/bin/env python3
"""Supplied art: tools/artcheck.py passes a sheet pack would keep as it is,
and fails, with where and why, one pack would have to change.

Run: python3 tests/test_artcheck.py
"""
import os, struct, subprocess, sys, tempfile, zlib

from harness import Suite, pulli

sys.path.insert(0, os.path.dirname(pulli.__file__))
import artcheck   # noqa: E402

PAL = pulli.palette()
TOOL = os.path.join(os.path.dirname(pulli.__file__), "artcheck.py")


def rgba_png(w, h, pixels):
    """A colour-type-6 PNG from (r, g, b, a) tuples, row by row."""
    raw = b"".join(b"\0" + b"".join(bytes(p) for p in pixels[y * w:(y + 1) * w]) for y in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def sheet(w, h, frame, feet, colour=7):
    """Frames of see-through with a solid 4-wide bar standing on row `feet`."""
    px = [(0, 0, 0, 0)] * (w * h)
    for fy in range(0, h, frame[1]):
        for fx in range(0, w, frame[0]):
            for y in range(feet - 9, feet + 1):
                for x in range(frame[0] // 2 - 2, frame[0] // 2 + 2):
                    px[(fy + y) * w + fx + x] = (*PAL[colour], 255)
    return px


def main():
    t = Suite("Supplied art: tools/artcheck.py")
    F = (48, 56)
    good = sheet(96, 112, F, 55)

    r = artcheck.check(rgba_png(96, 112, good), PAL, F, feet=55)
    t.check("a sheet in exact shared colours, alpha 0 or 255, passes", not r["errors"], r["errors"])
    t.check("it finds four 48x56 frames with their feet on row 55 and their middle at x 23.5",
            [(f["feet"], f["middle"]) for f in r["frames"]] == [(55, 23.5)] * 4, r["frames"])
    t.check("each frame's spr number counts 8x8 cells across the whole sheet",
            [f["cell"] for f in r["frames"]] == [0, 6, 84, 90], r["frames"])
    t.check("it counts the colours used", r["indices"] == {"7": 4 * 40}, r["indices"])

    off = list(good)
    off[10 * 96 + 24] = (1, 2, 3, 255)
    r = artcheck.check(rgba_png(96, 112, off), PAL, F)
    t.check("a colour not in the palette fails, with where it is and the nearest allowed colours",
            len(r["errors"]) == 1 and "#010203 is not in the palette" in r["errors"][0]
            and "(24,10)" in r["errors"][0] and "nearest allowed: 48 #170d0b, 49 #09101d, 50 #25121e" in r["errors"][0], r["errors"])

    off = list(good)
    off[50 * 96 + 22] = (*PAL[7], 128)
    r = artcheck.check(rgba_png(96, 112, off), PAL, F)
    t.check("a part see-through pixel fails",
            any("part see-through" in e and "(22,50)" in e for e in r["errors"]), r["errors"])

    r = artcheck.check(rgba_png(96, 112, sheet(96, 112, F, 55, colour=25)), PAL, F)
    t.check("a place's own colour (25) fails on a character",
            any("is colour 25, which is not allowed" in e for e in r["errors"]), r["errors"])
    r = artcheck.check(rgba_png(96, 112, sheet(96, 112, F, 55, colour=25)), PAL, F, allow=set(range(1, 64)))
    t.check("... and passes when every colour is allowed", not r["errors"], r["errors"])

    r = artcheck.check(rgba_png(96, 112, sheet(96, 112, F, 55, colour=32)), PAL, F)
    t.check("solid black fails: pack keeps it as colour 32, which is not shared",
            any("#000000" in e for e in r["errors"]), r["errors"])

    r = artcheck.check(rgba_png(96, 112, sheet(96, 112, F, 50)), PAL, F, feet=55)
    t.check("--feet fails each frame whose feet are on another row",
            sum("feet on row 50, not 55" in e for e in r["errors"]) == 4, r["errors"])

    r = artcheck.check(rgba_png(100, 112, [(0, 0, 0, 0)] * (100 * 112)), PAL, F)
    t.check("a width that is not a multiple of 8, or not whole frames, fails",
            any("multiples of 8" in e for e in r["errors"]) and any("whole number" in e for e in r["errors"]),
            r["errors"])
    r = artcheck.check(rgba_png(96, 112, good), PAL, F, count=5)
    t.check("more frames than the sheet holds fails", any("do not fit" in e for e in r["errors"]), r["errors"])
    r = artcheck.check(rgba_png(512, 264, [(0, 0, 0, 0)] * (512 * 264)), PAL)
    t.check("a sheet over the engine's limit fails", any("at most" in e for e in r["errors"]), r["errors"])
    r = artcheck.check(b"not a png", PAL)
    t.check("a file that is not a PNG fails, saying so", any("does not read" in e for e in r["errors"]), r["errors"])
    r = artcheck.check(rgba_png(96, 112, [(0, 0, 0, 0)] * (96 * 112)), PAL, F)
    t.check("an empty frame is a warning, not a failure",
            not r["errors"] and len(r["warnings"]) == 4, r)

    data = rgba_png(96, 112, good)
    t.check("a sheet that passes packs to the same colours, none moved",
            pulli.kolam_from_png(data, "s", notes := [], PAL) and not notes, notes)
    w, h, _ = pulli.read_png(artcheck.preview(data, 4, F))
    t.check("the preview is the sheet at four times its size", (w, h) == (384, 448), (w, h))

    with tempfile.TemporaryDirectory() as d:
        ok, bad = os.path.join(d, "ok.png"), os.path.join(d, "bad.png")
        open(ok, "wb").write(data)
        open(bad, "wb").write(rgba_png(96, 112, sheet(96, 112, F, 55, colour=25)))
        man = os.path.join(d, "m.json")
        a = subprocess.run([sys.executable, TOOL, ok, "--frame", "48x56", "--feet", "55",
                            "--manifest", man, "--preview", os.path.join(d, "p.png")],
                           capture_output=True, text=True)
        b = subprocess.run([sys.executable, TOOL, bad, "--frame", "48x56"], capture_output=True, text=True)
        import json
        m = json.load(open(man))
        t.check("from the command line: 0 for a pass, 1 for a fail, and a manifest written",
                a.returncode == 0 and b.returncode == 1 and m["passes"] and m["frame"] == [48, 56]
                and os.path.isfile(os.path.join(d, "p.png")), a.stdout + b.stdout)
    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
