// Shapes and materials for Kolam: draw a part as a shape (a limb, a
// polygon, an ellipse), give it a material, and it is filled and shaded on
// its own for light from the upper left, the way the game's figures are
// drawn (tests/plates_ref.py, Pic.plate): the shadow side
// edged in the material's darkest shade, never ink; the lit side with no
// line at all, its first pixels lit; a band of shadow inside the shadow
// edge; the rest the base, with the material's printed pattern if it has
// one. Nothing here touches the page: kolam.js lays what it gives on the
// sheet.
//
// A material: { name, edge, shade, base, lit } (palette indices), and
// optionally dots: [colour, across, down] (a dot every `across` pixels in
// every `down`th row, each row moved on by half of `across`).

export const MATERIALS = [
  { name: "skin", edge: 36, shade: 37, base: 4, lit: 5 },
  { name: "red silk", edge: 41, shade: 42, base: 10, lit: 11 },
  { name: "red, gold dots", edge: 41, shade: 42, base: 10, lit: 11, dots: [13, 5, 4] },
  { name: "gold", edge: 37, shade: 45, base: 13, lit: 14 },
  { name: "saffron", edge: 44, shade: 44, base: 12, lit: 13 },
  { name: "white cloth", edge: 39, shade: 40, base: 7, lit: 8 },
  { name: "blue", edge: 47, shade: 15, base: 16, lit: 17 },
  { name: "green", edge: 51, shade: 51, base: 19, lit: 19 },
  { name: "steel", edge: 50, shade: 50, base: 18, lit: 8 },
  { name: "leather", edge: 35, shade: 3, base: 4, lit: 5 },
  { name: "hair", edge: 33, shade: 34, base: 2, lit: 2 },
];

// ---- shapes: each is inside(x, y) for a point -----------------------------------
export function limb(ax, ay, bx, by, r0, r1 = r0) {
  const dx = bx - ax, dy = by - ay, L = dx * dx + dy * dy || 1;
  return (x, y) => {
    const t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / L));
    const px = ax + t * dx, py = ay + t * dy, r = r0 + (r1 - r0) * t;
    return (x - px) ** 2 + (y - py) ** 2 <= r * r;
  };
}
export function polygon(pts) {
  return (x, y) => {
    let c = false;
    for (let i = 0; i < pts.length; i++) {
      const [x1, y1] = pts[i], [x2, y2] = pts[(i + 1) % pts.length];
      if ((y1 > y) !== (y2 > y) && x < x1 + (y - y1) * (x2 - x1) / (y2 - y1)) c = !c;
    }
    return c;
  };
}
export function ellipse(cx, cy, rx, ry) {
  return (x, y) => ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 < 1;
}

// The pixels of a w x h frame a shape covers (tested at each pixel's middle).
export function mask(inside, w, h) {
  const m = new Uint8Array(w * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (inside(x + 0.5, y + 0.5)) m[y * w + x] = 1;
  return m;
}

// The colour of each covered pixel: [index, colour] pairs, for kolam.js to lay on.
export function shade(m, w, h, mat) {
  const on = (x, y) => x >= 0 && y >= 0 && x < w && y < h && m[y * w + x] === 1;
  const out = [];
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (!on(x, y)) continue;
    let c;
    if (!on(x + 1, y) || !on(x, y + 1)) c = mat.edge;                     // the shadow side's edge
    else if (!on(x - 1, y) || !on(x, y - 1) || (!on(x - 2, y) && !on(x, y - 2))) c = mat.lit;   // the lit side
    else if (!on(x + 2, y) || !on(x, y + 2)) c = mat.shade;
    else {
      c = mat.base;
      const d = mat.dots;
      if (d && (x + Math.floor(y / d[2]) * Math.floor(d[1] / 2)) % d[1] === 0 && y % d[2] === 0) c = d[0];
    }
    out.push([y * w + x, c]);
  }
  return out;
}

// ---- frames that need not be square -------------------------------------------
export const FRAME_SIZES = [[8, 8], [16, 16], [32, 32], [64, 64], [16, 24], [24, 32], [32, 48], [48, 56], [48, 64],
                            [64, 64], [96, 128], [128, 128]].filter((s, i, a) => a.findIndex((t) => t.join() === s.join()) === i);

// The top left of frame k of an animation that starts at (x, y) on a sheet
// sw wide and sh high, frames fw x fh: along the row, then on to the next
// row of frames at the sheet's left edge. null past either end.
export function frameAt(sw, sh, x, y, fw, fh, k) {
  for (; k > 0; k--) { x += fw; if (x + fw > sw) { x = 0; y += fh; } }
  for (; k < 0; k++) { x -= fw; if (x < 0) { x = Math.floor(sw / fw - 1) * fw; y -= fh; } }
  return y < 0 || y + fh > sh || x < 0 ? null : [x, y];
}

// A material read back from what is kept in the game's folder, or a
// reason it cannot be: four palette indices 0-63 and a name.
export function checkMaterial(m) {
  const ok = (n) => Number.isInteger(n) && n > 0 && n < 64;
  if (!m || typeof m.name !== "string" || !m.name) return "a material needs a name";
  for (const k of ["edge", "shade", "base", "lit"]) if (!ok(m[k])) return `${m.name}: ${k} is not a colour 1-63`;
  if (m.dots && !(m.dots.length === 3 && ok(m.dots[0]) && m.dots[1] > 0 && m.dots[2] > 0)) return `${m.name}: its dots are [colour, across, down]`;
  return null;
}
