#!/usr/bin/env python3
"""artcheck.py — check a supplied sprite sheet before it is packed.

`pulli.py pack` turns any colour into the nearest palette colour and says
so in a note. Supplied art must not be changed like that, so this checks
it first and fails on anything that pack would have to change.

    python3 tools/artcheck.py <sheet.png> [--palette palette.hex]
        [--frame 48x56] [--count N] [--allow shared|all] [--feet ROW]
        [--preview out.png] [--scale 4] [--manifest out.json]

It checks that the PNG reads; that its size is a multiple of 8 and fits
in a sheet; that each pixel is fully see-through or fully solid; that each
solid pixel is exactly one of the allowed palette colours (`shared`, the
default, is colours 1-19 and 33-51, which every place keeps); and that the
frames tile the sheet. For each frame it reports the lowest solid row (the
feet) and the middle of the bottom rows, and with --feet fails a frame
whose feet are on another row. A wrong colour is reported with where it
is and the nearest allowed colours, for a person to decide.

It writes nothing unless asked: --preview writes a nearest-neighbour
enlargement with see-through shown as a checkerboard and the frames
outlined; --manifest writes what was found as JSON. Exit status 0 means
the sheet passes, 1 that it does not.
"""
import argparse, hashlib, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pulli   # noqa: E402

SHARED = set(range(1, 20)) | set(range(33, 52))
SHOWN = 8                                   # wrong pixels listed per colour


def check(png, colours, frame=None, count=None, allow=SHARED, feet=None):
    """Everything found about a sheet, as a dict; `errors` empty means it passes."""
    r = {"errors": [], "warnings": [], "frames": []}
    err = r["errors"].append
    try:
        w, h, pixels = pulli.read_png(png, "sheet")
    except pulli.PackageError as e:
        err(f"the PNG does not read: {e}")
        return r
    r["size"] = [w, h]
    if w % 8 or h % 8:
        err(f"{w}x{h}: width and height must be multiples of 8")
    if w * h > pulli.ATLAS_MAX:
        err(f"{w}x{h} is {w * h} pixels; a sheet holds at most {pulli.ATLAS_MAX}")

    # Where pack would put each exact colour: the lowest index with it.
    first = {}
    for i, c in enumerate(colours):
        if i:
            first.setdefault(tuple(c), i)
    used, wrong, part = {}, {}, []
    index = [0] * (w * h)
    for p, (cr, cg, cb, a) in enumerate(pixels):
        if a == 0:
            continue
        if a != 255:
            part.append(p)
            continue
        i = first.get((cr, cg, cb))
        if i is None or i not in allow:
            wrong.setdefault((cr, cg, cb), []).append(p)
            continue
        index[p] = i
        used[i] = used.get(i, 0) + 1
    r["indices"] = {str(i): n for i, n in sorted(used.items())}
    if part:
        err(f"{len(part)} pixel(s) are part see-through; alpha must be 0 or 255, first at "
            + ", ".join(f"({p % w},{p // w})" for p in part[:SHOWN]))
    for rgb, ps in sorted(wrong.items(), key=lambda kv: -len(kv[1])):
        near = sorted((sum((a - b) ** 2 for a, b in zip(rgb, colours[i])), i) for i in allow)[:3]
        why = (f"is colour {first[rgb]}, which is not allowed" if rgb in first
               else "is not in the palette")
        err(f"#{bytes(rgb).hex()} {why}: {len(ps)} pixel(s), at "
            + ", ".join(f"({p % w},{p // w})" for p in ps[:SHOWN]) + (" ..." if len(ps) > SHOWN else "")
            + "; nearest allowed: " + ", ".join(f"{i} #{bytes(colours[i]).hex()}" for _, i in near))

    if frame:
        fw, fh = frame
        if fw % 8 or fh % 8:
            err(f"frame {fw}x{fh}: must be multiples of 8")
        if w % fw or h % fh:
            err(f"{w}x{h} is not a whole number of {fw}x{fh} frames")
        across, down = w // fw, h // fh
        count = across * down if count is None else count
        if count > across * down:
            err(f"{count} frames do not fit; the sheet holds {across * down}")
        for k in range(min(count, across * down)):
            ox, oy = k % across * fw, k // across * fh
            rows = [y for y in range(fh) if any(index[(oy + y) * w + ox + x] or pixels[(oy + y) * w + ox + x][3]
                                                 for x in range(fw))]
            f = {"frame": k, "cell": k % across * (fw // 8) + k // across * (fh // 8) * (w // 8)}
            if not rows:
                f["empty"] = True
                r["warnings"].append(f"frame {k} is empty")
            else:
                low = rows[-1]
                xs = [x for y in range(max(0, low - 3), low + 1) for x in range(fw)
                      if pixels[(oy + y) * w + ox + x][3]]
                f.update(top=rows[0], feet=low, middle=round(sum(xs) / len(xs), 1))
                if feet is not None and low != feet:
                    err(f"frame {k}: feet on row {low}, not {feet}")
            r["frames"].append(f)
        r["frame"] = [fw, fh]
        r["count"] = count
    return r


def preview(png, scale=4, frame=None):
    """A nearest-neighbour enlargement as PNG bytes: see-through shown as a
    grey checkerboard, frame edges as a magenta line."""
    w, h, pixels = pulli.read_png(png, "sheet")
    W, H = w * scale, h * scale
    out = bytearray(W * H * 3)
    for y in range(H):
        for x in range(W):
            r, g, b, a = pixels[y // scale * w + x // scale]
            if a < 255:
                r = g = b = 0x55 if (x // 8 + y // 8) % 2 else 0x44
            if frame and (x % (frame[0] * scale) == 0 or y % (frame[1] * scale) == 0):
                r, g, b = 0xc0, 0x30, 0xc0
            o = (y * W + x) * 3
            out[o:o + 3] = bytes((r, g, b))
    return pulli.write_png(W, H, bytes(out))


def main():
    ap = argparse.ArgumentParser(description="Check a supplied sprite sheet against a palette.")
    ap.add_argument("png")
    ap.add_argument("--palette", help="palette.hex or .gpl (default: the Pulli palette)")
    ap.add_argument("--frame", help="frame size, WxH")
    ap.add_argument("--count", type=int, help="frames in the sheet (default: all it holds)")
    ap.add_argument("--allow", choices=("shared", "all"), default="shared")
    ap.add_argument("--feet", type=int, help="the row every frame's feet must be on")
    ap.add_argument("--preview")
    ap.add_argument("--scale", type=int, default=4)
    ap.add_argument("--manifest")
    a = ap.parse_args()

    data = open(a.png, "rb").read()
    pal = open(a.palette, "rb").read() if a.palette else None
    colours = pulli.read_palette(pal, a.palette)[:pulli.palette_size(pal, a.palette)] if pal else pulli.palette()
    frame = tuple(int(v) for v in a.frame.lower().split("x")) if a.frame else None
    allow = SHARED if a.allow == "shared" else set(range(1, len(colours)))
    r = check(data, colours, frame, a.count, allow, a.feet)

    print(f"{a.png}: {'x'.join(map(str, r.get('size', ['?'])))}"
          + (f", {r['count']} frame(s) of {frame[0]}x{frame[1]}" if frame and 'count' in r else ""))
    for f in r["frames"]:
        print(f"  frame {f['frame']:2} (spr {f['cell']}): " + ("empty" if f.get("empty") else
              f"rows {f['top']}-{f['feet']}, bottom middle at x {f['middle']}"))
    if "indices" in r:
        print("  colours used: " + (", ".join(f"{i} ({n})" for i, n in r["indices"].items()) or "none"))
    for m in r["warnings"]:
        print("  warning: " + m)
    for m in r["errors"]:
        print("  FAIL: " + m)
    print("PASS" if not r["errors"] else f"FAIL ({len(r['errors'])})")

    if a.preview and "size" in r:
        with open(a.preview, "wb") as f:
            f.write(preview(data, a.scale, frame))
    if a.manifest:
        r.update(file=os.path.basename(a.png), sha256=hashlib.sha256(data).hexdigest(),
                 palette=os.path.basename(a.palette) if a.palette else "pulli",
                 palette_sha256=hashlib.sha256(pal).hexdigest() if pal else None,
                 allow=a.allow, transparency="alpha 0", passes=not r["errors"])
        with open(a.manifest, "w") as f:
            json.dump(r, f, indent=1)
            f.write("\n")
    return 0 if not r["errors"] else 1


if __name__ == "__main__":
    sys.exit(main())
