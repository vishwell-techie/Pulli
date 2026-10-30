// A picture kept as a .kolam, as the console reads it (SPEC §2): "KLM1",
// its width and height (16 bits each, low byte first), then a palette
// index for each pixel, row by row; 0 is see-through.

export function readKolam(bytes) {
  const b = new Uint8Array(bytes), d = new DataView(b.buffer, b.byteOffset, b.byteLength);
  if (b.length < 8 || String.fromCharCode(...b.subarray(0, 4)) !== "KLM1") throw new Error("not a .kolam picture");
  const width = d.getUint16(4, true), height = d.getUint16(6, true);
  if (b.length !== 8 + width * height) throw new Error(`a ${width}×${height} .kolam should be ${8 + width * height} bytes`);
  return { width, height, pixels: b.slice(8), moved: 0 };
}

export function writeKolam(pic) {
  const out = new Uint8Array(8 + pic.width * pic.height), d = new DataView(out.buffer);
  out.set([75, 76, 77, 49]);
  d.setUint16(4, pic.width, true); d.setUint16(6, pic.height, true);
  out.set(pic.pixels, 8);
  return out;
}
