// The built-in 256 colours (SPEC §8.3) as 0xRRGGBB, the same list as
// tools/refgfx.py DEFAULT_PALETTE; tests/test_pattarai.py checks they agree.
export const BUILTIN = [
  0x000000, 0x1d2b53, 0x7e2553, 0x008751, 0xab5236, 0x5f574f, 0xc2c3c7, 0xfff1e8,
  0xff004d, 0xffa300, 0xffec27, 0x00e436, 0x29adff, 0x83769c, 0xff77a8, 0xffccaa,
  0x291814, 0x111d35, 0x422136, 0x125359, 0x742f29, 0x49333b, 0xa28879, 0xf3ef7d,
  0xbe1250, 0xff6c24, 0xa8e72e, 0x00b543, 0x065ab5, 0x754665, 0xff6e59, 0xff9d81,
  0x000000, 0x10182e, 0x46142e, 0x004b2d, 0x602e1e, 0x35302c, 0x6d6d6f, 0x8f8782,
  0x8f002b, 0x8f5b00, 0x8f8415, 0x00801e, 0x17618f, 0x494257, 0x8f425e, 0x8f725f,
  0x170d0b, 0x09101d, 0x25121e, 0x0a2e32, 0x411a17, 0x291c21, 0x5b4c44, 0x888646,
  0x6a0a2d, 0x8f3c14, 0x5e8119, 0x006525, 0x033265, 0x412738, 0x8f3d32, 0x8f5848,
  0xf6d2b5, 0xe8b08a, 0xd08c5e, 0xb06e44, 0x8c5232, 0x6a3c24, 0x4c2a1a, 0x2e1a10,
  0xffe7a0, 0xf2c14e, 0xc8962a, 0x9a6b1c, 0xe84a3c, 0xb0202e, 0x7a1028, 0x4e0a1e,
  0x9ed36a, 0x5fa845, 0x2f7a3a, 0x14492a, 0x8fd3ff, 0x4a8fe0, 0x2e4bb0, 0x1e2470,
  0xc27be0, 0x8a3fb0, 0xf4a6c8, 0xd0607a, 0xf4f4f0, 0xb8b4ac, 0x7a7670, 0x3e3a38,
  0x8a7665, 0x82634d, 0x754e34, 0x633d26, 0x4e2e1c, 0x3b2114, 0x2a170e, 0x190e09,
  0x8f815a, 0x886c2b, 0x705417, 0x563c0f, 0x822921, 0x631219, 0x440916, 0x2b0510,
  0x58763b, 0x355e26, 0x1a4420, 0x0b2917, 0x50768f, 0x29507e, 0x192a63, 0x10143f,
  0x6d457e, 0x4d2363, 0x895d70, 0x753644, 0x898987, 0x676560, 0x44423f, 0x22201f,
  0xffd27a, 0xffb03a, 0xe58a12, 0xb8640a, 0x9cf0e0, 0x3cc8b4, 0x1a8c84, 0x0e5458,
  0xb4b8ff, 0x7078e8, 0x4040b8, 0x24207a, 0xffc4d0, 0xf0889c, 0xc84868, 0x8a2444,
  0xe4e89a, 0xb8c055, 0x868c30, 0x565a1c, 0xfff4d8, 0xe0d4b8, 0xa89c88, 0x6c6458,
  0xe8c8f8, 0xb890e0, 0x7c58b0, 0x4a2c78, 0xffe8c0, 0xf8c890, 0xe0a070, 0xb87850,
  0x8f7644, 0x8f6320, 0x804d0a, 0x673805, 0x57877e, 0x217065, 0x0e4e4a, 0x072f31,
  0x65678f, 0x3f4382, 0x242467, 0x141244, 0x8f6e75, 0x874c57, 0x70283a, 0x4d1426,
  0x808256, 0x676c2f, 0x4b4e1b, 0x30320f, 0x8f8979, 0x7e7767, 0x5e574c, 0x3c3831,
  0x82708b, 0x67517e, 0x453163, 0x291843, 0x8f826c, 0x8b7051, 0x7e5a3f, 0x67432d,
  0xf0dca8, 0xd8bc80, 0xb89a5c, 0x8c7040, 0xc08858, 0x985e34, 0x6e3e20, 0x4a2814,
  0xbce08c, 0x84b858, 0x5a8c38, 0x3a6024, 0x7ce0f0, 0x38a8d0, 0x1c70a8, 0x10447a,
  0xd8f0ff, 0xa8d4f8, 0xff4040, 0xc8102c, 0xffe060, 0xe0b020, 0xdce4ec, 0x9ca8b8,
  0x707c8c, 0x404858, 0xf8f0b0, 0xd8c870, 0x60c0a0, 0x2e8a6c, 0xa03018, 0x601808,
  0x877b5e, 0x796948, 0x675633, 0x4e3f24, 0x6c4c31, 0x55341d, 0x3d2212, 0x29160b,
  0x697e4e, 0x4a6731, 0x324e1f, 0x203614, 0x457e87, 0x1f5e75, 0x0f3f5e, 0x092644,
  0x79878f, 0x5e778b, 0x8f2424, 0x700918, 0x8f7e36, 0x7e6312, 0x7b8084, 0x575e67,
  0x3f454e, 0x242831, 0x8b8763, 0x79703f, 0x366c5a, 0x194d3c, 0x5a1b0d, 0x360d04,
];

// How many colours a game may choose to make its own (SPEC §8.3); past
// them, the built-in ones stay.
export const SIZES = [64, 128, 256];

// The fewest of SIZES that hold n colours.
export const sizeFor = (n) => SIZES.find((s) => s >= n) ?? 256;

// A game's own palette: palette.hex (one rrggbb a line) or palette.gpl, all
// 256 colours, its own first. ownColours gives how many are its own.
export const ownColours = (text) => parsePalette(text, true);
export function parsePalette(text, count = false) {
  const out = [];
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || /^(GIMP|Name:|Columns:|\/\/|;)/.test(line)) continue;
    let m = line.match(/^#?([0-9a-fA-F]{6})$/);
    if (line.startsWith("#") && !m) continue;          // a comment in a .gpl
    if (m) { out.push(parseInt(m[1], 16)); continue; }
    m = line.match(/^(\d+)\s+(\d+)\s+(\d+)/);
    if (m) out.push((+m[1] << 16) | (+m[2] << 8) | +m[3]);
  }
  // the game's choice of 64, 128 or 256: those take the first places, the rest built in
  if (!SIZES.includes(out.length)) throw new Error("a palette has 64, 128 or 256 colours, this one has " + out.length);
  if (count) return out.length;
  return [...out, ...BUILTIN.slice(out.length)];
}

// The colours in a palette file brought in from elsewhere, as 0xRRGGBB:
// .hex (one rrggbb a line, as Lospec gives), .gpl (GIMP, Aseprite, Krita),
// .pal (JASC, as Paint Shop Pro and many tools write; or Pulli's own PAL1),
// .txt (paint.net: aarrggbb a line, ; comments). Any number of colours; a
// picture's colours are read by the page (paletteOfPixels).
export function readPaletteFile(name, bytes) {
  const b = new Uint8Array(bytes);
  if (b.length >= 4 && String.fromCharCode(...b.subarray(0, 4)) === "PAL1") {
    const out = [];
    for (let i = 4; i + 2 < b.length; i += 3) out.push((b[i] << 16) | (b[i + 1] << 8) | b[i + 2]);
    return out;
  }
  const text = new TextDecoder().decode(b);
  const lines = text.split(/\r?\n/).map((l) => l.trim());
  if (lines[0] === "JASC-PAL") {
    return lines.slice(3).map((l) => l.match(/^(\d+)\s+(\d+)\s+(\d+)/)).filter(Boolean)
      .map((m) => (+m[1] << 16) | (+m[2] << 8) | +m[3]);
  }
  const out = [];
  for (const line of lines) {
    if (!line || /^(GIMP|Name:|Columns:|\/\/|;)/.test(line)) continue;
    let m = line.match(/^#?(?:[0-9a-fA-F]{2})?([0-9a-fA-F]{6})$/);       // rrggbb, or paint.net's aarrggbb
    if (m && !(line.startsWith("#") && line.length !== 7)) { out.push(parseInt(m[1], 16)); continue; }
    m = line.match(/^(\d+)\s+(\d+)\s+(\d+)/);
    if (m) out.push((+m[1] << 16) | (+m[2] << 8) | +m[3]);
  }
  if (!out.length) throw new Error(`${name}: no colours found`);
  return out;
}

// The distinct colours of a picture, in the order met (a palette image: a
// strip or grid of swatches). rgba as from a canvas.
export function paletteOfPixels(rgba) {
  const seen = new Set(), out = [];
  for (let i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    const c = (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
    if (!seen.has(c)) { seen.add(c); out.push(c); }
    if (out.length > 256) break;
  }
  return out;
}

// 256 colours from those brought in: they take the first places, the rest
// kept from `current`. More than 256 cannot be a game's palette.
export function fitPalette(colours, current) {
  if (colours.length > 256) throw new Error(`a palette has at most 256 colours; this one has ${colours.length}`);
  return [...colours, ...current.slice(colours.length)];
}

// A palette as palette.hex (one rrggbb a line), or as palette.gpl.
export function writePalette(pal, gpl = false) {
  const hex = (c) => c.toString(16).padStart(6, "0");
  if (!gpl) return pal.map(hex).join("\n") + "\n";
  return "GIMP Palette\nName: game\nColumns: 8\n#\n" +
    pal.map((c) => `${(c >> 16) & 255} ${(c >> 8) & 255} ${c & 255}\t${hex(c)}`).join("\n") + "\n";
}

export const css = (c) => "#" + c.toString(16).padStart(6, "0");

// The nearest of colours 1 and up (0 is see-through in sprites), as pack
// matches a picture's colours.
export function nearest(rgb, palette) {
  let best = 1, bd = Infinity;
  for (let i = 1; i < palette.length; i++) {
    const c = palette[i];
    const d = ((c >> 16) - (rgb >> 16)) ** 2 + (((c >> 8) & 255) - ((rgb >> 8) & 255)) ** 2 + ((c & 255) - (rgb & 255)) ** 2;
    if (d < bd) { bd = d; best = i; }
  }
  return best;
}

// RGBA pixels as palette indices: 0 where less than half opaque, the rest
// the nearest colour. dither: a 4x4 ordered pattern first, so a shade
// between two colours comes out as a fine mix of them. `moved` counts the
// pixels whose colour was not one of the palette's.
export function quantiseTo(rgba, width, height, palette, dither = false) {
  const pixels = new Uint8Array(width * height);
  const cache = new Map();
  let moved = 0;
  const bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
  const own = new Map(palette.map((c, i) => [c, i]).filter(([, i]) => i > 0).reverse());
  for (let i = 0; i < pixels.length; i++) {
    if (rgba[i * 4 + 3] < 128) continue;
    let r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
    const exact = (r << 16) | (g << 8) | b;
    if (own.has(exact)) { pixels[i] = own.get(exact); continue; }   // already one of the colours: kept, never dithered
    if (dither) {
      const t = (bayer[(Math.floor(i / width) % 4) * 4 + (i % width) % 4] / 16 - 0.5) * 40;
      r = Math.max(0, Math.min(255, Math.round(r + t))); g = Math.max(0, Math.min(255, Math.round(g + t)));
      b = Math.max(0, Math.min(255, Math.round(b + t)));
    }
    const rgb = (r << 16) | (g << 8) | b;
    if (!cache.has(rgb)) cache.set(rgb, nearest(rgb, palette));
    pixels[i] = cache.get(rgb);
    if (palette[pixels[i]] !== exact) moved++;
  }
  return { width, height, pixels, moved };
}
