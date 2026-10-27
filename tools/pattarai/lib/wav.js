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

// A PCM WAV file's sound: {rate, channels: [Float32Array...], loop}, the
// samples as they are (no resampling, which the browser's own decoder does).
export function decodeWAV(bytes) {
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const tag = (at) => String.fromCharCode(...bytes.subarray(at, at + 4));
  if (bytes.length < 12 || tag(0) !== "RIFF" || tag(8) !== "WAVE") throw new Error("not a WAV file");
  let fmt = null, data = null, loop = null;
  for (let at = 12; at + 8 <= bytes.length;) {
    const id = tag(at), size = v.getUint32(at + 4, true), body = at + 8;
    if (id === "fmt ") fmt = { kind: v.getUint16(body, true), channels: v.getUint16(body + 2, true),
      rate: v.getUint32(body + 4, true), bits: v.getUint16(body + 14, true) };
    else if (id === "data") data = [body, Math.min(size, bytes.length - body)];
    else if (id === "smpl" && size >= 60 && v.getUint32(body + 28, true) >= 1) loop = v.getUint32(body + 44, true);
    at = body + size + (size & 1);
  }
  if (!fmt || !data) throw new Error("a WAV file with no sound in it");
  if (fmt.kind !== 1 && fmt.kind !== 0xfffe) throw new Error("only plain PCM WAV files can be read");
  const step = fmt.bits / 8, frames = Math.floor(data[1] / (step * fmt.channels));
  const chans = Array.from({ length: fmt.channels }, () => new Float32Array(frames));
  for (let i = 0; i < frames; i++) for (let c = 0; c < fmt.channels; c++) {
    const at = data[0] + (i * fmt.channels + c) * step;
    let s;
    if (fmt.bits === 8) s = (bytes[at] - 128) / 128;
    else if (fmt.bits === 16) s = v.getInt16(at, true) / 32768;
    else if (fmt.bits === 24) s = ((bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16)) << 8 >> 8) / 8388608;
    else if (fmt.bits === 32) s = v.getInt32(at, true) / 2147483648;
    else throw new Error(`${fmt.bits}-bit WAV files cannot be read`);
    chans[c][i] = s;
  }
  return { rate: fmt.rate, channels: chans, loop: loop !== null && loop < frames ? loop : null };
}
