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
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    return repr(v)


def op(name, *args):
    """Queue an API call. Numbers reach the reference the way api.c passes them on."""
    method = {"clip": "set_clip"}.get(name, name)

    def apply(g):
        conv = [a if isinstance(a, (str, bool)) else api_int(a) for a in args]
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
    t.check("the Tamil font draws every vowel, consonant and syllable, and ஸ்ரீ", need <= set(ta),
            sorted(need - set(ta))[:20])
    build_scene()
    g = reference()
    fb = bytes(g.fb)
    rgb = struct.pack(f"<{W * H}H", *g.scanout())

    t.check("framebuffer is exactly 76800 bytes", len(fb) == W * H == 76800)

    # clip must have confined the fullscreen fill to its rectangle
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

    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
