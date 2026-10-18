#!/usr/bin/env python3
"""Rasterizer conformance: the C engine against the Python reference.

Run: python3 tests/test_conformance.py [--update]

One scene, defined once below, is drawn two ways:

  * directly by tools/refgfx.py, the slow and obvious reference;
  * as a generated Lua game, packed and run by the real C runtime, so the
    package reader, the Lua bindings and their argument handling are all on
    the path, not just the rasterizer.

The two framebuffers and the two RGB565 screens must match byte for byte.
Any difference is a bug in the engine or a port. The reference itself is
pinned by tests/golden.sha256, so it cannot drift unnoticed; tests/golden.png
is the same picture for human eyes. After an intended change to drawing,
rerun with --update and review the new golden.png.
"""
import hashlib, math, os, struct, sys

from harness import Suite, TESTS, pulli
from refgfx import RefGfx, W, H, CELL

FRAMES = 3      # the scene is drawn three times over; state must not leak
SCENE = []      # (lua source, function applying the same thing to a RefGfx)


def api_int(v):
    """What runtime/api.c does to every coordinate: floor, then 16-bit clamp."""
    if isinstance(v, float):
        v = math.floor(struct.unpack("<f", struct.pack("<f", v))[0])
    return max(-32768, min(32767, v))


def lua(v):
    if v is True or v is False:
        return "true" if v else "false"
    if isinstance(v, list):
        return "{" + ", ".join(lua(x) for x in v) + "}"
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    return repr(v)


def op(name, *args):
    """Queue an API call. Numbers reach the reference the way api.c passes them on."""
    method = {"clip": "set_clip"}.get(name, name)

    def apply(g):
        conv = [a if isinstance(a, (str, bool)) else [api_int(x) for x in a]
                if isinstance(a, list) else api_int(a) for a in args]
        if name == "fade":
            conv = list(args)
        getattr(g, method)(*conv)
    SCENE.append((f"{name}({', '.join(lua(a) for a in args)})", apply))


def make_atlas():
    """4x2 grid of 8x8 cells: solid blocks + a transparent-corner sprite."""
    aw, ah = 32, 16
    a = bytearray(aw * ah)
    for cell in range(8):
        cx, cy = (cell % 4) * CELL, (cell // 4) * CELL
        color = 8 + cell
        if cell == 6:
            color += 64                    # past the palette: must wrap to 14
        for y in range(CELL):
            for x in range(CELL):
                # cell 7 has a transparent (index 0) top-left quadrant
                if cell == 7 and x < 4 and y < 4:
                    continue
                a[(cy + y) * aw + cx + x] = color
    return a, aw, ah


def build_scene():
    op("cls", 1)
    op("rectfill", 0, 0, W, 40, 2)
    op("rect", 4, 4, W - 8, 32, 7)
    op("line", 0, 40, W - 1, 40, 7)
    op("circfill", 60, 120, 30, 3)
    op("circ", 60, 120, 34, 11)
    op("line", 10, 60, 300, 200, 9)

    # sprites: plain, flipped, scaled, transparent-corner
    for i in range(8):
        op("spr", i, 120 + i * 10, 60)
    op("spr", 0, 120, 80, 2, 2)
    op("spr", 1, 160, 80, 1, 1, True, True)
    op("spr", 7, 200, 80)                      # transparency test
    op("sspr", 0, 0, 8, 8, 240, 60, 32, 32)

    # clip + camera interaction
    op("clip", 200, 120, 80, 60)
    op("rectfill", 0, 0, W, H, 10)
    op("clip")

    op("camera", -20, -10)
    op("rectfill", 0, 180, 40, 20, 12)
    op("camera", 0, 0)

    # palette remap
    op("pal", 14, 8)
    op("rectfill", 140, 200, 40, 20, 14)
    op("pal")

    # text, including descenders and a line break
    op("print", "Pulli 0123 gjpqy {}", 12, 16, 7)
    op("print", "AB\ncd", 100, 108, 10)
    # Tamil: whole syllables, vowel signs drawn before and around their
    # letter, u and uu shapes, the pulli, ஸ்ரீ, a character no font has, and
    # English sharing a Tamil line and following it (SPEC §3, "Text")
    op("print", "மாணிக்கம்", 196, 184, 7)
    op("print", "கொ கை ஸ்ரீ", 186, 208, 10)
    op("print", "கு பூ டூ", 64, 210, 12)
    op("print", "பு €\nA", 4, 150, 7)
    op("print", "Hi தமிழ்\nok", 2, 96, 9)
    # the button icons, on an English line and on a Tamil one, and Tamil at
    # its small size, which lowers its English less
    op("print", "Go " + "".join(chr(0xE000 + i) for i in range(12)), 150, 2, 7)
    op("print", "அ" + chr(0xE004) + "x\n" + chr(0xE00B), 260, 120, 8)
    op("font", "small")
    op("print", "சிறிய " + chr(0xE005) + " ok\nகொ", 110, 150, 11)
    # numbers: at the Tamil size on a Tamil line, at either size; 8x8 on an
    # English line
    op("print", "ஏழில் 3 / 7", 4, 46, 12)
    op("font")
    op("print", "தளம் 0123456789\n42", 4, 224, 14)

    # fractions round down, on both sides of zero
    op("rectfill", 100.9, 140.2, 10.5, 6.99, 9)
    op("line", 104.5, 160.5, 120.5, 170.5, 12)
    op("camera", -150.5, -100.5)
    op("pset", -0.5, -0.5, 7)
    op("camera")

    # colour indices wrap at 64
    op("rectfill", 100, 150, 10, 6, 64 + 11)
    op("pset", 98, 150, -1)

    # numbers far outside the screen are held to the 16-bit range
    op("rectfill", 290, 100, 100000, 4, 8)
    op("line", -40000, 230, 40, 230, 6)

    # transparency switched per colour, then reset
    op("palt", 15, True)
    op("spr", 7, 220, 84)
    op("palt")
    op("palt", 0, False)
    op("spr", 7, 232, 84)
    op("palt")

    # reading the screen back
    SCENE.append(("pset(300, 50, pget(60, 120))", lambda g: g.pset(300, 50, g.pget(60, 120))))

    # shapes that cross the screen edge
    op("circfill", 330, 250, 20, 13)
    op("spr", 2, -4, 100)
    op("rect", -10, -10, 20, 20, 7)

    # stretched and flipped blits
    op("sspr", 0, 0, 16, 16, 100, 180, 24, 12)
    op("spr", 0, 250, 104, 2, 1, True, False)

    # clip is in screen space, camera moves the world underneath it
    op("camera", 10, 5)
    op("clip", 120, 185, 30, 10)
    op("rectfill", 0, 0, W, H, 14)
    op("clip")
    op("camera")

    # degenerate sizes
    op("circ", 110, 200, 0, 7)
    op("circfill", 110, 206, 1, 7)
    op("rect", 114, 198, 1, 1, 7)
    op("rect", 118, 198, 2, 5, 7)
    op("rectfill", 124, 198, 0, 5, 7)
    op("rectfill", 124, 198, -3, 5, 7)

    # the fade level is set, not accumulated: three frames must look like one
    op("fade", 0.25)


def reference():
    g = RefGfx()
    g.atlas, g.atlas_w, g.atlas_h = make_atlas()
    for _ in range(FRAMES):
        for _, apply in SCENE:
            apply(g)
    return g


def random_scene(seed, count=600):
    """A long, seeded mix of the drawing calls with awkward arguments:
    sprites hanging off the screen and past the atlas, flipped and several
    cells wide; stretched and shrunk blits; fills and circles of every size,
    under moving cameras, clips and palette changes. The fast paths in
    runtime/gfx.c must draw exactly what the obvious reference does."""
    import random
    global SCENE
    rng = random.Random(seed)
    SCENE = []
    op("cls", 1)
    for _ in range(count):
        k = rng.randrange(40)
        r = rng.randrange
        if k == 0:
            op("camera", r(-60, 61), r(-60, 61))
        elif k == 1:
            if r(3):
                op("clip", r(-40, 300), r(-40, 220), r(-10, 260), r(-10, 200))
            else:
                op("clip")
        elif k == 2:
            if r(4):
                op("pal", r(64), r(64))
            else:
                op("pal")
        elif k == 3:
            if r(4):
                op("palt", r(64), bool(r(2)))
            else:
                op("palt")
        elif k in (4, 5, 6):
            op("spr", r(0, 10), r(-30, 330), r(-30, 250), r(0, 4), r(0, 4), bool(r(2)), bool(r(2)))
        elif k == 7:
            op("sspr", r(-8, 40), r(-8, 24), r(-2, 40), r(-2, 30), r(-40, 330), r(-40, 250), r(-2, 120), r(-2, 90))
        elif k == 8:
            op("rectfill", r(-40, 330), r(-40, 250), r(-10, 150), r(-10, 120), r(70))
        elif k == 9:
            op("circfill", r(-30, 350), r(-30, 270), r(-3, 50), r(70))
        elif k == 10:
            op("circ", r(-30, 350), r(-30, 270), r(-3, 50), r(70))
        elif k == 11:
            op("line", r(-30, 350), r(-30, 270), r(-30, 350), r(-30, 270), r(70))
        elif k == 12:
            op("shade", r(70), random_lights(rng), r(-2, 40))
        elif k in (13, 14):
            if r(3) == 0:
                op("font", rng.choice(("normal", "small")))
            op("print", rng.choice(TEXTS), r(-60, 330), r(-30, 250), r(70))
        else:
            continue
    op("font")
    op("camera", 0, 0)
    op("clip")
    op("pal")
    op("palt")


# Text for the random scenes: English, Tamil, both on one line, lines
# broken, and bytes that are not UTF-8.
TEXTS = ["Hello, Pulli!", "தாமரைக் குளம்", "Score 120 மதிப்பெண்", "ஸ்ரீ\nஒளி 3",
         "a\x80b\xffc", "கொ கௌ க்ஷ ஃ", "Press \ue004 or \ue00a", "அழுத்து \ue000\ue001\n\ue00b\ue00c"]


def random_lights(rng):
    """Lights for shade(): overlapping, touching, off the screen, of radius
    0 and below, now and then more than the 64 it takes, and a float or two."""
    out = []
    for _ in range(rng.choice((0, 1, 3, 8, 24, 70))):
        out += [rng.randrange(-60, 380), rng.randrange(-60, 300), rng.randrange(-2, 90)]
    if out and rng.randrange(2):
        out[0] += 0.75
    return out


def shade_scene(seed):
    """A busy picture, then darkness over it with lights cut out, under a
    random camera, clip and palette."""
    import random
    global SCENE
    rng = random.Random(seed)
    SCENE = []
    r = rng.randrange
    op("cls", 1)
    for _ in range(40):
        op("rectfill", r(-20, 320), r(-20, 240), r(1, 80), r(1, 60), r(64))
    op("camera", r(-50, 51), r(-50, 51))
    if r(2):
        op("clip", r(-20, 200), r(-20, 150), r(20, 300), r(20, 200))
    if r(2):
        op("pal", r(64), r(64))
    op("shade", r(64), random_lights(rng), r(-2, 40))
    op("camera", 0, 0)
    op("clip")
    op("pal")


def first_difference(a, b, unit):
    for i in range(0, min(len(a), len(b)), unit):
        if a[i:i + unit] != b[i:i + unit]:
            p = i // unit
            return f"first difference at x={p % W} y={p // W}: reference {a[i:i+unit].hex()}, engine {b[i:i+unit].hex()}"
    return f"lengths differ: reference {len(a)}, engine {len(b)}"


# What the Tamil font must draw (SPEC §3, "Text"): every syllable whole.
TA_VOWELS = "அஆஇஈஉஊஎஏஐஒஓஔ"
TA_CONSONANTS = "கஙசஜஞடணதநனபமயரறலளழவஶஷஸஹ"
TA_SIGNS = "்ாிீுூெேைொோௌ"


def main():
    t = Suite("Pulli rasterizer conformance")
    from refgfx import TamilFont
    ta = TamilFont().glyphs
    need = set(TA_VOWELS) | set(TA_CONSONANTS) | {c + v for c in TA_CONSONANTS for v in TA_SIGNS} | {"ஃ", "ஸ்ரீ"}
    need |= set("0123456789")
    t.check("the Tamil font draws every vowel, consonant and syllable, ஸ்ரீ, and the digits", need <= set(ta),
            sorted(need - set(ta))[:20])
    small = TamilFont(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "runtime", "font_ta_small.txt"))
    t.check("the small Tamil font draws the same", set(small.glyphs) == set(ta), sorted(set(ta) ^ set(small.glyphs))[:20])
    build_scene()
    g = reference()
    fb = bytes(g.fb)
    rgb = struct.pack(f"<{W * H}H", *g.scanout())

    t.check("framebuffer is exactly 76800 bytes", len(fb) == W * H == 76800)

    # clip must have confined the fullscreen fill to its rectangle
    # shade (SPEC §3): darkness everywhere but the lights, dotted edges
    sg = RefGfx()
    sg.cls(7)
    sg.shade(0, [100, 100, 10, 121, 100, 10, 250, 50, 0], 3)
    px = lambda x, y: sg.fb[y * W + x]
    lit = lambda x, y: (x - 100) ** 2 + (y - 100) ** 2 <= 100 or (x - 121) ** 2 + (y - 100) ** 2 <= 100
    t.check("shade leaves a light's middle alone", px(100, 100) == 7 and px(121, 103) == 7)
    t.check("shade darkens what no light reaches", px(0, 0) == 0 and px(200, 200) == 0 and px(100, 89) == 0)
    t.check("shade's lit area is circfill's",
            all((px(x, y) == 7) == lit(x, y) for y in range(88, 113) for x in range(86, 136) if (x + y) % 2))
    t.check("shade joins touching lights into one span: no dots between them", px(110, 100) == 7)
    t.check("shade dots edge pixels at each end of a span, where x + y is even",
            [px(x, 100) for x in range(89, 95)] == [0, 0, 7, 0, 7, 7]
            and [px(x, 100) for x in range(127, 133)] == [7, 7, 7, 0, 7, 0])
    t.check("shade: a light of radius 0 is one pixel, too narrow to dot", px(250, 50) == 7 and px(251, 50) == 0)

    t.check("clip contains the fill", fb[130 * W + 210] == 10)
    t.check("clip rejects pixels left of the region", fb[130 * W + 190] != 10)
    t.check("clip rejects pixels above the region", fb[110 * W + 210] != 10)

    # camera offset: rect drawn at (0,180) with camera(-20,-10) lands at (20,190)
    t.check("camera translates draws", fb[190 * W + 20] == 12)
    t.check("camera does not draw at untranslated position", fb[180 * W + 0] != 12)

    # transparency: cell 7's transparent quadrant must show the background
    t.check("sprite index 0 is transparent", fb[81 * W + 201] == fb[70 * W + 190])
    t.check("sprite opaque region drew", fb[86 * W + 206] == 15)
    t.check("palt() makes a colour transparent and resets", fb[90 * W + 226] != 15
            and fb[85 * W + 233] == 0 and fb[90 * W + 238] == 15)

    t.check("pal() remaps at draw time", fb[205 * W + 150] == 8)
    t.check("all indices within palette range", max(fb) < 64)
    t.check("sprite pixels past the palette wrap", fb[62 * W + 182] == 14)
    t.check("colour arguments wrap at 64", fb[152 * W + 105] == 11 and fb[150 * W + 98] == 63)
    t.check("fractional coordinates round down", fb[140 * W + 100] == 9 and fb[146 * W + 100] != 9
            and fb[140 * W + 110] != 9 and fb[100 * W + 150] == 7)
    t.check("text draws", fb[16 * W + 13] == 7 and fb[108 * W + 102] == 10)
    t.check("pget reads the screen", fb[50 * W + 300] == 3)
    t.check("fade darkens the screen, not the framebuffer",
            g.scanout()[0] != g.palette[fb[0]] and g.fade_k == 24)

    digest = hashlib.sha256(fb + rgb).hexdigest()
    golden = os.path.join(TESTS, "golden.sha256")
    if t.update:
        with open(golden, "w") as f:
            f.write(digest + "\n")
        g.write_png(os.path.join(TESTS, "golden.png"))
        print("  ....  wrote tests/golden.sha256 and tests/golden.png")
    pinned = open(golden).read().strip() if os.path.exists(golden) else "(missing)"
    t.check("reference output matches tests/golden.sha256", digest == pinned,
            "the reference renderer or the scene changed; if that was intended, rerun with --update")

    if t.need_runtime("C engine against the reference"):
        body = "\n".join("  " + src for src, _ in SCENE)
        atlas, aw, ah = make_atlas()
        r = t.run_game(f"function draw()\n{body}\nend\n", frames=FRAMES,
                       extra={"sprites.kolam": pulli.kolam(aw, ah, bytes(atlas))})
        if t.check("engine ran the scene", r.code == 0, r.err):
            t.check("engine framebuffer matches the reference", r.fb == fb,
                    first_difference(fb, r.fb, 1))
            t.check("engine screen (RGB565) matches the reference", r.rgb == rgb,
                    first_difference(rgb, r.rgb, 2))
        for seed in (1, 2, 3, 4):
            random_scene(seed)
            want = bytes(reference().fb)
            body = "\n".join("  " + src for src, _ in SCENE)
            r = t.run_game(f"function draw()\n{body}\nend\n", frames=1,
                           extra={"sprites.kolam": pulli.kolam(aw, ah, bytes(atlas))})
            t.check(f"engine matches the reference on 600 random calls (seed {seed})",
                    r.code == 0 and r.fb == want, r.err or first_difference(want, r.fb, 1))
        for seed in range(1, 9):
            shade_scene(seed)
            want = bytes(reference().fb)
            body = "\n".join("  " + src for src, _ in SCENE)
            r = t.run_game(f"function draw()\n{body}\nend\n", frames=1)
            t.check(f"engine shades like the reference (seed {seed})",
                    r.code == 0 and r.fb == want, r.err or first_difference(want, r.fb, 1))

    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
