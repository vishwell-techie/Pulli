// Oli's sound effects: a handful of numbers made into a short mono sound,
// the way the old arcade sound generators did. Runs in the browser and in
// node (tests/test_pattarai.py).

export const RATE = 22050;     // plenty for effects, and half the size of 44.1 kHz

export const WAVES = ["square", "saw", "triangle", "sine", "noise", "tabla"];

// Every setting, with its range: [name, min, max, step, label].
export const KNOBS = [
  ["attack", 0, 0.5, 0.005, "attack (s)"], ["sustain", 0, 1.5, 0.01, "hold (s)"],
  ["decay", 0.01, 2, 0.01, "fade (s)"], ["punch", 0, 1, 0.05, "punch"],
  ["freq", 30, 3000, 1, "pitch (Hz)"], ["slide", -8, 8, 0.05, "slide (octaves/s)"],
  ["slideAccel", -8, 8, 0.1, "slide speeds up"], ["minFreq", 20, 1000, 1, "lowest pitch"],
  ["vibDepth", 0, 1, 0.01, "vibrato depth"], ["vibSpeed", 0, 30, 0.5, "vibrato speed"],
  ["arpStep", -12, 12, 1, "jump (semitones)"], ["arpAt", 0, 1, 0.01, "jump at (0-1)"],
  ["duty", 0.05, 0.95, 0.01, "square width"], ["dutySlide", -1, 1, 0.05, "width slide"],
  ["repeat", 0, 20, 0.5, "repeat (times/s)"], ["lowpass", 100, 11000, 10, "low-pass (Hz)"],
  ["highpass", 0, 3000, 10, "high-pass (Hz)"], ["crush", 0, 1, 0.05, "bit-crush"],
  ["volume", 0, 1, 0.01, "volume"],
];

export function newSfx() {
  return { format: "oli-sfx", version: 1, wave: "square", attack: 0, sustain: 0.08, decay: 0.2, punch: 0.3,
    freq: 440, slide: 0, slideAccel: 0, minFreq: 20, vibDepth: 0, vibSpeed: 6, arpStep: 0, arpAt: 0.5,
    duty: 0.5, dutySlide: 0, repeat: 0, lowpass: 11000, highpass: 0, crush: 0, volume: 0.7, seed: 1 };
}

function rng(seed) {
  let s = (seed >>> 0) || 1;
  return () => { s ^= s << 13; s ^= s >>> 17; s ^= s << 5; return (s >>> 0) / 4294967296; };
}

// Ready-made starting points; each call to a preset with a new seed is a
// new variation on it.
export const PRESETS = {
  jump: (r) => ({ wave: "square", freq: 300 + r() * 200, slide: 1.5 + r() * 1.5, sustain: 0.06, decay: 0.15 + r() * 0.1, duty: 0.3 + r() * 0.3 }),
  coin: (r) => ({ wave: r() < 0.5 ? "square" : "sine", freq: 900 + r() * 500, arpStep: [4, 5, 7, 12][Math.floor(r() * 4)],
                  arpAt: 0.15 + r() * 0.2, sustain: 0.05, decay: 0.25 + r() * 0.15, punch: 0.5 }),
  hit: (r) => ({ wave: r() < 0.5 ? "noise" : "saw", freq: 200 + r() * 300, slide: -2 - r() * 2, sustain: 0.02, decay: 0.12 + r() * 0.1, punch: 0.6, lowpass: 3000 + r() * 4000 }),
  explosion: (r) => ({ wave: "noise", freq: 60 + r() * 120, slide: -0.5 - r(), sustain: 0.1 + r() * 0.2, decay: 0.6 + r() * 0.6, punch: 0.7, lowpass: 1200 + r() * 2000 }),
  laser: (r) => ({ wave: r() < 0.5 ? "saw" : "square", freq: 1200 + r() * 1200, slide: -3 - r() * 3, minFreq: 100, sustain: 0.05, decay: 0.15 + r() * 0.1, duty: 0.2 + r() * 0.3 }),
  powerup: (r) => ({ wave: "square", freq: 250 + r() * 200, slide: 1 + r(), repeat: 6 + r() * 6, sustain: 0.3, decay: 0.2, vibDepth: 0.1 }),
  blip: (r) => ({ wave: r() < 0.5 ? "square" : "triangle", freq: 500 + r() * 900, sustain: 0.03 + r() * 0.03, decay: 0.03 + r() * 0.04 }),
  hurt: (r) => ({ wave: "saw", freq: 400 + r() * 200, slide: -2.5, sustain: 0.03, decay: 0.2 + r() * 0.1, crush: 0.3 + r() * 0.3, punch: 0.4 }),
  tabla: (r) => ({ wave: "tabla", freq: 200 + r() * 250, slide: r() < 0.5 ? 0 : 0.3, sustain: 0, decay: 0.3 + r() * 0.4, punch: 0.4 }),
  bell: (r) => ({ wave: "sine", freq: 600 + r() * 700, sustain: 0, decay: 1 + r(), vibDepth: 0.02, vibSpeed: 5, punch: 0.2 }),
};

const clamp = (s) => {
  for (const [k, min, max] of KNOBS) s[k] = Math.min(max, Math.max(min, s[k]));
  return s;
};

export function preset(name, seed) {
  return clamp({ ...newSfx(), ...PRESETS[name](rng(seed * 7919 + name.length)), seed });
}

// A small change to every setting, for "more like this".
export function mutate(s, seed) {
  const r = rng(seed), out = { ...s, seed };
  for (const [k, min, max, step] of KNOBS) {
    if (k === "volume" || r() < 0.5) continue;
    const v = out[k] + (r() - 0.5) * (max - min) * 0.08;
    out[k] = Math.round(Math.min(max, Math.max(min, v)) / step) * step;
  }
  return out;
}

// The sound, as a Float32Array at RATE, -1..1.
export function render(s) {
  const len = Math.max(1, Math.floor((s.attack + s.sustain + s.decay) * RATE));
  const out = new Float32Array(len);
  const noise = rng(s.seed || 1);
  let phase = 0, noiseVal = 0, lp = 0, hpIn = 0, hpOut = 0, held = 0;
  const lpk = 1 - Math.exp(-2 * Math.PI * s.lowpass / RATE);
  const hpk = s.highpass > 0 ? Math.exp(-2 * Math.PI * s.highpass / RATE) : 0;
  const crushStep = s.crush > 0 ? Math.max(1, Math.round(s.crush * 16)) : 1;
  const levels = s.crush > 0 ? 2 ** Math.max(2, Math.round(16 - s.crush * 13)) : 0;
  const total = len / RATE;
  for (let i = 0; i < len; i++) {
    let t = i / RATE;
    if (s.repeat > 0) t %= 1 / s.repeat;
    // pitch: the start, slid (and the slide sped up), jumped, wobbled
    let f = s.freq * 2 ** (s.slide * t + 0.5 * s.slideAccel * t * t);
    if (s.arpStep && i / RATE >= s.arpAt * total) f *= 2 ** (s.arpStep / 12);
    f *= 2 ** (s.vibDepth * Math.sin(2 * Math.PI * s.vibSpeed * i / RATE) / 2);
    f = Math.min(RATE / 2.2, Math.max(s.minFreq, f));
    const before = phase;
    phase = (phase + f / RATE) % 1;
    const duty = Math.min(0.95, Math.max(0.05, s.duty + s.dutySlide * i / RATE));
    let v;
    switch (s.wave) {
      case "square": v = phase < duty ? 1 : -1; break;
      case "saw": v = 2 * phase - 1; break;
      case "triangle": v = phase < 0.5 ? 4 * phase - 1 : 3 - 4 * phase; break;
      case "sine": v = Math.sin(2 * Math.PI * phase); break;
      case "noise":                                   // a new random value each cycle of the pitch
        if (phase < before) noiseVal = noise() * 2 - 1;
        v = noiseVal; break;
      case "tabla": {                                 // a struck drum head: two rings and a slap
        const tt = i / RATE;
        v = Math.sin(2 * Math.PI * phase) * 0.7 + Math.sin(2 * Math.PI * phase * 2.76) * 0.3 * Math.exp(-tt * 18) +
            (noise() * 2 - 1) * Math.exp(-tt * 120) * 0.5;
        break;
      }
      default: v = 0;
    }
    // envelope: rise, hold (with a punch at its start), fade
    const at = i / RATE;
    let env;
    if (at < s.attack) env = at / s.attack;
    else if (at < s.attack + s.sustain) env = 1 + s.punch * (1 - (at - s.attack) / Math.max(1e-6, s.sustain));
    else env = Math.max(0, 1 - (at - s.attack - s.sustain) / s.decay) ** 2;
    v *= env / (1 + s.punch);
    lp += lpk * (v - lp);
    v = lp;
    if (hpk) { const o = hpk * (hpOut + v - hpIn); hpIn = v; hpOut = o; v = o; }
    if (crushStep > 1) { if (i % crushStep === 0) held = v; v = held; }
    if (levels) v = Math.round(v * levels / 2) / (levels / 2);
    out[i] = Math.max(-1, Math.min(1, v * s.volume));
  }
  return out;
}
