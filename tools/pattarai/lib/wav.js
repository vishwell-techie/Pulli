// WAV files: 16-bit PCM, what `pulli pack` reads for sfx/ and music/.

// channels: an array of Float32Array (one for mono, two for stereo), -1..1.
// loop: the frame a looping sound goes back to, kept in a "smpl" chunk as
// pack reads it (SPEC §2); none, and it loops from its start.
export function encodeWAV(channels, rate, loop = null) {
  const n = channels[0].length, c = channels.length;
  const smpl = loop ? 68 : 0;
  const out = new ArrayBuffer(44 + n * c * 2 + smpl);
  const v = new DataView(out);
  const text = (at, s) => { for (let i = 0; i < 4; i++) v.setUint8(at + i, s.charCodeAt(i)); };
  text(0, "RIFF"); v.setUint32(4, 36 + n * c * 2 + smpl, true); text(8, "WAVE");
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
  if (loop) {                                   // smpl: 36 bytes about the sampler, then one loop
    text(at, "smpl"); v.setUint32(at + 4, 60, true);
    v.setUint32(at + 8 + 12, Math.round(1e9 / rate), true);   // sample period, ns
    v.setUint32(at + 8 + 16, 60, true);                       // the note it is: middle C
    v.setUint32(at + 8 + 28, 1, true);                        // one loop
    v.setUint32(at + 8 + 44, loop, true);                     // from here
    v.setUint32(at + 8 + 48, n - 1, true);                    // to the end
  }
  return new Uint8Array(out);
}
