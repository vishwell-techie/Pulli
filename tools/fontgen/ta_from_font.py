#!/usr/bin/env python3
"""ta_from_font.py — make runtime/font_ta.txt, Pulli's Tamil pixel font, from
an outline font.

    python3 tools/fontgen/ta_from_font.py            regenerate runtime/font_ta.txt
    python3 tools/fontgen/ta_from_font.py --sheet out.png   also draw every glyph

OPTIONAL. This is the only Pulli tool that needs more than the standard
library: Pillow built with raqm (text shaping). Nothing in the build or the
tests runs it. runtime/font_ta.txt, which it writes, is the source the build
uses (tools/mkfont.py turns it into runtime/font_ta.c); edit that file by
hand to touch up a glyph, or rerun this to start again from the font.

Every Tamil syllable is shaped and drawn whole, the way a Tamil reader
expects it: each consonant alone, with the pulli and with every vowel sign,
each vowel, and ஸ்ரீ; and the digits 0 to 9, which a line holding Tamil
draws at the Tamil size. The runtime then only has to look syllables up
(SPEC §3, "Text"). The source font is Noto Sans Tamil Medium, under the
SIL Open Font License 1.1 (third_party/noto-sans-tamil/), and so is the
pixel font made from it.

How the pixels are made, chosen for legibility at this size:
  - 17 pixels to the em: at this size the font's hinting gives firm strokes
    two pixels wide, and a line still holds about four words (15 is small for
    a handheld, 16 thin, 19 fits two or three words);
  - FreeType's monochrome rendering with the font's own hinting, which keeps
    the small loops of letters like ண and ஞ open better than thresholding a
    smoothed or supersampled picture does;
  - advances from the hinted font, so letters sit as the font spaces them.
"""
import argparse, os, sys

try:
    from PIL import Image, ImageDraw, ImageFont, features
except ImportError:
    sys.exit("ta_from_font.py needs Pillow (with raqm): pip install pillow")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
FONT = os.path.join(ROOT, "third_party", "noto-sans-tamil", "NotoSansTamil-Medium.ttf")
OUT = os.path.join(ROOT, "runtime", "font_ta.txt")
SIZE = 17
ENGLISH_BASELINE = 6         # the last row of an English capital in the 8x8 font

VOWELS = "அஆஇஈஉஊஎஏஐஒஓஔ"
CONSONANTS = "கஙசஜஞடணதநனபமயரறலளழவஶஷஸஹ"
SIGNS = "்ாிீுூெேைொோௌ"
OTHER = "ஃௗ௦௧௨௩௪௫௬௭௮௯ௐ"
DIGITS = "0123456789"        # numbers on a Tamil line, drawn at the Tamil size


def glyph_set():
    names = list(VOWELS) + list(CONSONANTS)
    names += [c + s for c in CONSONANTS for s in SIGNS]
    names += ["ஸ்ரீ"] + list(SIGNS) + list(OTHER) + list(DIGITS)
    return names


def render(font, text):
    """The text, shaped and drawn in pixels with its pen at x = 0 on the
    baseline. Returns (advance, {(x, y): ink}) with y counted up from the
    baseline as negative."""
    pad = 40
    im = Image.new("1", (160, 120), 0)
    d = ImageDraw.Draw(im)
    d.fontmode = "1"
    d.text((pad, 80), text, font=font, fill=1, anchor="ls", language="ta")
    advance = round(font.getlength(text, mode="1", language="ta"))
    ink = {(x - pad, y - 80) for y in range(im.height) for x in range(im.width) if im.getpixel((x, y))}
    return advance, ink


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--font", default=FONT)
    ap.add_argument("--size", type=int, default=SIZE)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--sheet", help="also write a picture of every glyph here")
    args = ap.parse_args()
    if not features.check("raqm"):
        sys.exit("this Pillow has no raqm, so it cannot shape Tamil")
    font = ImageFont.truetype(args.font, args.size, layout_engine=ImageFont.Layout.RAQM)

    shapes = {}
    for name in glyph_set():
        advance, ink = render(font, name)
        if not ink:
            sys.exit(f"{name}: the font drew nothing")
        shapes[name] = (advance, ink)

    top = min(y for _, ink in shapes.values() for _, y in ink)       # highest ink, above the baseline
    bottom = max(y for _, ink in shapes.values() for _, y in ink)    # lowest, below it
    rows = bottom - top + 1
    baseline_row = -1 - top            # the row holding the last ink above the baseline
    above = baseline_row - ENGLISH_BASELINE

    family, style = font.getname()
    out = [f"; Pulli Tamil font: syllables drawn from {family} {style} at {args.size} pixels to the em",
           "; by tools/fontgen/ta_from_font.py.",
           ";",
           "; Copyright 2022 The Noto Project Authors (https://github.com/notofonts/tamil).",
           "; This font is licensed under the SIL Open Font License, Version 1.1; see",
           "; third_party/noto-sans-tamil/OFL.txt. It is a Modified Version of Noto",
           "; Sans Tamil, and like it may be used, changed and shared, but not sold",
           "; on its own.",
           ";",
           "; \"= <letters> adv=A kern=K\" starts a glyph: what it draws, how far the pen",
           "; moves after it, and how many columns left of the pen its first column",
           "; is (negative: further left). Then one row of '.' and '#' for each of the",
           "; font's rows, as wide as the glyph. \"! rows=R above=B\" gives the rows of",
           "; every glyph and how many of them are above row 0 of an English letter.",
           "; Touch up a glyph here by hand; then run python3 tools/mkfont.py.",
           "",
           f"! rows={rows} above={above}",
           ""]
    sheet = []
    for name, (advance, ink) in shapes.items():
        x0 = min(x for x, _ in ink)
        x1 = max(x for x, _ in ink)
        out.append(f"= {name} adv={advance} kern={x0}")
        grid = []
        for y in range(top, bottom + 1):
            grid.append("".join("#" if (x, y) in ink else "." for x in range(x0, x1 + 1)))
        out += grid
        out.append("")
        sheet.append((name, grid))
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    widest = max(len(g[0]) for _, g in sheet)
    print(f"wrote {os.path.relpath(args.out)}: {len(shapes)} glyphs, {rows} rows, "
          f"{above} above an English letter, widest {widest}")

    if args.sheet:
        cols, cell_w, cell_h = 16, widest + 4, rows + 4
        lines = (len(sheet) + cols - 1) // cols
        im = Image.new("1", (cols * cell_w, lines * cell_h), 0)
        for i, (_, grid) in enumerate(sheet):
            ox, oy = (i % cols) * cell_w + 2, (i // cols) * cell_h + 2
            for y, row in enumerate(grid):
                for x, ch in enumerate(row):
                    if ch == "#":
                        im.putpixel((ox + x, oy + y), 1)
        im.resize((im.width * 3, im.height * 3), Image.NEAREST).save(args.sheet)


if __name__ == "__main__":
    main()
