// The built-in 64 colours (SPEC §8.3) as 0xRRGGBB, the same list as
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
];

// A game's own palette: palette.hex (one rrggbb a line) or palette.gpl.
export function parsePalette(text) {
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
  if (out.length !== 64) throw new Error("a palette has 64 colours, this one has " + out.length);
  return out;
}

export const css = (c) => "#" + c.toString(16).padStart(6, "0");
