// WAV files: 16-bit PCM, what `pulli pack` reads for sfx/ and music/.

// channels: an array of Float32Array (one for mono, two for stereo), -1..1.
export function encodeWAV(channels, rate) {
  const n = channels[0].length, c = channels.length;
  const out = new ArrayBuffer(44 + n * c * 2);
  const v = new DataView(out);
  const text = (at, s) => { for (let i = 0; i < 4; i++) v.setUint8(at + i, s.charCodeAt(i)); };
  text(0, "RIFF"); v.setUint32(4, 36 + n * c * 2, true); text(8, "WAVE");
  text(12, "fmt "); v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, c, true);
  v.setUint32(24, rate, true); v.setUint32(28, rate * c * 2, true); v.setUint16(32, c * 2, true);
  v.setUint16(34, 16, true);
  text(36, "data"); v.setUint32(40, n * c * 2, true);
  let at = 44;
  for (let i = 0; i < n; i++) {
    for (let k = 0; k < c; k++) {
      const s = Math.max(-1, Math.min(1, channels[k][i]));
      v.setInt16(at, Math.round(s * 32767), true);
      at += 2;
    }
  }
  return new Uint8Array(out);
}
