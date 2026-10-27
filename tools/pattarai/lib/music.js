// Isai's music: scales (western and Carnatic), the notation a part is
// written in, and the band that plays a song into samples. Everything here
// runs in the browser and in node (tests/test_pattarai.py).

export const RATE = 44100;
// The rate the song in hand is rendered at (its `rate`, or RATE): chiptune
// is often made at 8,000 or 11,025 for small files.
let SR = RATE;
export const RATES = [8000, 11025, 22050, 44100];

// ---- scales -----------------------------------------------------------------
// A scale is its notes in semitones above the tonic, going up; a Carnatic
// raga may also have its own way down (avarohanam) and a crooked (vakra)
// way up, kept for showing; the notes it may use are the union.

export const WESTERN = {
  "major (Ionian)": [0, 2, 4, 5, 7, 9, 11],
  "natural minor (Aeolian)": [0, 2, 3, 5, 7, 8, 10],
  "harmonic minor": [0, 2, 3, 5, 7, 8, 11],
  "melodic minor": [0, 2, 3, 5, 7, 9, 11],
  "Dorian": [0, 2, 3, 5, 7, 9, 10],
  "Phrygian": [0, 1, 3, 5, 7, 8, 10],
  "Lydian": [0, 2, 4, 6, 7, 9, 11],
  "Mixolydian": [0, 2, 4, 5, 7, 9, 10],
  "Locrian": [0, 1, 3, 5, 6, 8, 10],
  "major pentatonic": [0, 2, 4, 7, 9],
  "minor pentatonic": [0, 3, 5, 7, 10],
  "blues": [0, 3, 5, 6, 7, 10],
  "whole tone": [0, 2, 4, 6, 8, 10],
  "chromatic": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
};

// The 72 melakartas, in order: each is made from its number (the
// Katapayadi scheme): Ma1 for 1-36, Ma2 for 37-72; within each half, six
// chakras of six; the chakra picks Ri and Ga, the place in it Dha and Ni.
const MELA_NAMES = [
  "Kanakangi", "Ratnangi", "Ganamurti", "Vanaspati", "Manavati", "Tanarupi",
  "Senavati", "Hanumatodi", "Dhenuka", "Natakapriya", "Kokilapriya", "Rupavati",
  "Gayakapriya", "Vakulabharanam", "Mayamalavagowla", "Chakravakam", "Suryakantam", "Hatakambari",
  "Jhankaradhvani", "Natabhairavi", "Keeravani", "Kharaharapriya", "Gourimanohari", "Varunapriya",
  "Mararanjani", "Charukesi", "Sarasangi", "Harikambhoji", "Dheerasankarabharanam", "Naganandini",
  "Yagapriya", "Ragavardhini", "Gangeyabhushani", "Vagadheeswari", "Shulini", "Chalanata",
  "Salagam", "Jalarnavam", "Jhalavarali", "Navaneetam", "Pavani", "Raghupriya",
  "Gavambhodi", "Bhavapriya", "Shubhapantuvarali", "Shadvidamargini", "Suvarnangi", "Divyamani",
  "Dhavalambari", "Namanarayani", "Kamavardhini", "Ramapriya", "Gamanashrama", "Vishwambari",
  "Shamalangi", "Shanmukhapriya", "Simhendramadhyamam", "Hemavati", "Dharmavati", "Neetimati",
  "Kantamani", "Rishabhapriya", "Latangi", "Vachaspati", "Mechakalyani", "Chitrambari",
  "Sucharitra", "Jyotiswarupini", "Dhatuvardhani", "Nasikabhushani", "Kosalam", "Rasikapriya",
];
const PAIRS_LOW = [[1, 2], [1, 3], [1, 4], [2, 3], [2, 4], [3, 4]];      // Ri, Ga
const PAIRS_HIGH = [[8, 9], [8, 10], [8, 11], [9, 10], [9, 11], [10, 11]]; // Dha, Ni

export function melakarta(n) {
  const i = n - 1, half = i % 36;
  const [r, g] = PAIRS_LOW[Math.floor(half / 6)], [d, ni] = PAIRS_HIGH[half % 6];
  return [0, r, g, i < 36 ? 5 : 6, 7, d, ni];
}

// Janya ragas: up, then down (both include the Sa above).
const JANYA = {
  "Mohanam": [[0, 2, 4, 7, 9, 12], [12, 9, 7, 4, 2, 0], 28],
  "Hindolam": [[0, 3, 5, 8, 10, 12], [12, 10, 8, 5, 3, 0], 20],
  "Madhyamavati": [[0, 2, 5, 7, 10, 12], [12, 10, 7, 5, 2, 0], 22],
  "Shivaranjani": [[0, 2, 3, 7, 9, 12], [12, 9, 7, 3, 2, 0], 22],
  "Revati": [[0, 1, 5, 7, 10, 12], [12, 10, 7, 5, 1, 0], 2],
  "Hamsadhwani": [[0, 2, 4, 7, 11, 12], [12, 11, 7, 4, 2, 0], 29],
  "Abhogi": [[0, 2, 3, 5, 9, 12], [12, 9, 5, 3, 2, 0], 22],
  "Sriranjani": [[0, 2, 3, 5, 9, 10, 12], [12, 10, 9, 5, 3, 2, 0], 22],
  "Abheri": [[0, 3, 5, 7, 10, 12], [12, 10, 9, 7, 5, 3, 2, 0], 22],
  "Anandabhairavi": [[0, 3, 2, 3, 5, 7, 9, 7, 12], [12, 10, 9, 7, 5, 3, 2, 0], 22],
  "Bilahari": [[0, 2, 4, 7, 9, 12], [12, 11, 9, 7, 5, 4, 2, 0], 29],
  "Kalyani": [[0, 2, 4, 6, 7, 9, 11, 12], [12, 11, 9, 7, 6, 4, 2, 0], 65],
  "Todi": [[0, 1, 3, 5, 7, 8, 10, 12], [12, 10, 8, 7, 5, 3, 1, 0], 8],
  "Sankarabharanam": [[0, 2, 4, 5, 7, 9, 11, 12], [12, 11, 9, 7, 5, 4, 2, 0], 29],
};

// Every scale by name, as {system, notes, up, down, parent}.
export const SCALES = (() => {
  const all = {};
  for (const [name, notes] of Object.entries(WESTERN))
    all[name] = { system: "western", notes, up: [...notes, 12], down: [12, ...notes.slice().reverse()] };
  MELA_NAMES.forEach((name, i) => {
    const notes = melakarta(i + 1);
    all[name] = { system: "carnatic", mela: i + 1, notes, up: [...notes, 12], down: [12, ...notes.slice().reverse()] };
  });
  for (const [name, [up, down, parent]] of Object.entries(JANYA)) {
    const notes = [...new Set([...up, ...down].map((s) => s % 12))].sort((a, b) => a - b);
    all[name] = { system: "carnatic", notes, up, down, parent };
  }
  return all;
})();

// ---- naming the notes -------------------------------------------------------

const SHARP = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
const FLAT = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"];
export const KEYS = SHARP;

// Which swara each note of a raga is: the lower of two notes from 1-4 is
// Ri and the higher Ga; a note alone there is Ri at 1-2 and Ga at 3-4. The
// same for Dha and Ni between 8 and 11.
export function swaraNames(notes) {
  const names = {};
  const pair = (lo, hi, a, b, va, vb) => {
    const here = notes.filter((s) => s >= lo && s <= hi);
    if (here.length >= 2) { names[here[0]] = a + va[here[0]]; names[here[1]] = b + vb[here[1]]; }
    else if (here.length === 1) {
      const s = here[0];
      names[s] = s - lo < 2 ? a + va[s] : b + vb[s];
    }
  };
  names[0] = "S";
  pair(1, 4, "R", "G", { 1: 1, 2: 2, 3: 3 }, { 2: 1, 3: 2, 4: 3 });
  for (const s of notes) if (s === 5) names[s] = "M1"; else if (s === 6) names[s] = "M2";
  if (notes.includes(7)) names[7] = "P";
  pair(8, 11, "D", "N", { 8: 1, 9: 2, 10: 3 }, { 9: 1, 10: 2, 11: 3 });
  return names;
}

export function noteName(semi, song) {
  const oct = Math.floor(semi / 12), s = ((semi % 12) + 12) % 12;
  if (song.system === "carnatic") {
    const n = swaraNames(SCALES[song.scale].notes)[s] ||
      ["S", "R1", "R2", "G2", "G3", "M1", "M2", "P", "D1", "D2", "N2", "N3"][s];
    return n + (oct > 0 ? "'".repeat(oct) : ".".repeat(-oct));
  }
  const key = KEYS.indexOf(song.key);
  const abs = semi + key;
  const names = /b/.test(song.key) || [5, 10, 3, 8, 1, 6].includes(key) ? FLAT : SHARP;
  return names[((abs % 12) + 12) % 12] + (song.octave + Math.floor(abs / 12));
}

// ---- notation -----------------------------------------------------------------
// A part is written one token a step (a step is 1/`steps` of a beat):
//   carnatic: S R G M P D N, the raga's own variant; R1, G3, M2... for a
//             note from outside it; ' after for the octave above, . for the
//             one below (S' P. N..)
//   western:  C D E F G A B with # or b and an octave number (C4, F#3, Bb5);
//             the octave can be left out, and is then the song's octave
//   both:     , holds the note before one more step; ; holds it two;
//             - (or _) is a rest; | is a bar line and is skipped;
//             a gamaka mark after a note: ~ shakes it (kampita), / slides up
//             into it, \ slides down into it;
//             {0,4,7} after a note (and its mark) cycles it through those
//             semitones above it, fast: chiptune's arpeggio chord;
//             !1 to !9 at the very end sets the note's volume (9, or
//             nothing, is full): echoes, accents, fades;
//             // starts a comment, to the end of the line.
// Returns {notes: [{at, len, semi, mark}], steps} or throws with the token.

const LETTER = { S: 0, R: 1, G: 2, M: 3, P: 4, D: 5, N: 6 };
const EXPLICIT = { S: 0, R1: 1, R2: 2, R3: 3, G1: 2, G2: 3, G3: 4, M1: 5, M2: 6, P: 7, D1: 8, D2: 9, D3: 10,
                   N1: 9, N2: 10, N3: 11 };

export function parseNotation(text, song) {
  const notes = [];
  let at = 0;
  const swaras = song.system === "carnatic" ? swaraNames(SCALES[song.scale].notes) : null;
  const byLetter = {};
  if (swaras) for (const [s, n] of Object.entries(swaras)) byLetter[n[0]] = +s;
  const tokens = text.replace(/\/\/[^\n]*/g, "").split(/\s+/).filter((t) => t);
  for (let tok of tokens) {
    if (tok === "|" || tok === "||") continue;
    let arp = null, vol = null;
    const bang = tok.match(/^(.+)!([1-9])$/);
    if (bang) { tok = bang[1]; vol = +bang[2]; }
    else if (/!/.test(tok)) throw new Error(`cannot read "${tok}": a volume is !1 to !9 at the end`);
    const brace = tok.match(/^(.*?)\{(-?\d+(?:,-?\d+)*)\}$/);
    if (brace) { tok = brace[1]; arp = brace[2].split(",").map(Number); }
    else if (tok.includes("{")) throw new Error(`cannot read "${tok}": an arpeggio is written {0,4,7}`);
    if (tok === "," || tok === ";") {
      const n = tok === "," ? 1 : 2;
      if (notes.length && notes[notes.length - 1].at + notes[notes.length - 1].len === at)
        notes[notes.length - 1].len += n;
      at += n;
      continue;
    }
    if (tok === "-" || tok === "_") { at += 1; continue; }
    let semi, m;
    if (song.system === "carnatic") {
      m = tok.match(/^([SRGMPDN])([123]?)([.']*)([~/\\]?)$/);
      if (!m) throw new Error(`cannot read "${tok}"`);
      if (m[2]) {
        semi = EXPLICIT[m[1] + m[2]];
        if (semi === undefined) throw new Error(`there is no ${m[1]}${m[2]}`);
      } else if (m[1] === "S") semi = 0;
      else if (m[1] === "P") semi = 7;
      else {
        semi = byLetter[m[1]];
        if (semi === undefined) throw new Error(`${m[1]} is not in ${song.scale}; write which, such as ${m[1]}2`);
      }
      semi += 12 * ((m[3].match(/'/g) || []).length - (m[3].match(/\./g) || []).length);
      m = [null, null, null, null, m[4]];
    } else {
      m = tok.match(/^([A-Ga-g])([#b]?)(-?\d?)([~/\\]?)$/);
      if (!m) throw new Error(`cannot read "${tok}"`);
      const pitch = SHARP.indexOf(m[1].toUpperCase()) + (m[2] === "#" ? 1 : m[2] === "b" ? -1 : 0);
      const octave = m[3] === "" ? song.octave : +m[3];
      semi = pitch + 12 * (octave - song.octave) - KEYS.indexOf(song.key);
    }
    const note = { at, len: 1, semi, mark: m[4] || "" };
    if (arp) note.arp = arp;
    if (vol) note.vol = vol;
    notes.push(note);
    at += 1;
  }
  return { notes, steps: at };
}

// The other way: notes back to a part's text, `perBar` steps between bar
// lines. Used when notes are placed on the roll.
const arpText = (n) => (n.arp ? "{" + n.arp.join(",") + "}" : "") + (n.vol && n.vol < 9 ? "!" + n.vol : "");

export function writeNotation(notes, steps, song, perBar) {
  const out = [];
  const sorted = [...notes].sort((a, b) => a.at - b.at);
  let at = 0, i = 0;
  const token = (n) => {
    if (song.system === "carnatic") {
      const s = ((n.semi % 12) + 12) % 12, oct = Math.floor(n.semi / 12);
      const own = swaraNames(SCALES[song.scale].notes)[s];
      const name = own ? (own.length > 1 ? own[0] : own) : noteName(s, song).replace(/[.']/g, "");
      return name + (oct > 0 ? "'".repeat(oct) : ".".repeat(-oct)) + n.mark + arpText(n);
    }
    return noteName(n.semi, song) + n.mark + arpText(n);
  };
  while (at < steps) {
    if (perBar && at && at % perBar === 0) out.push("|");
    const n = sorted[i];
    if (n && n.at === at) {
      out.push(token(n));
      for (let k = 1; k < n.len && at + k < steps; k++) {
        if (perBar && (at + k) % perBar === 0) out.push("|");
        out.push(",");
      }
      at += Math.max(1, n.len);
      i++;
      while (sorted[i] && sorted[i].at < at) i++;           // overlapped: one note at a time a part
    } else { out.push("-"); at++; }
  }
  return out.join(" ");
}

// ---- talas and time -----------------------------------------------------------
// beats a cycle and the beats where its groups begin (the strong ones).
export const TALAS = {
  carnatic: {
    "Adi (8)": [8, [0, 4, 6]], "Rupaka (3)": [3, [0, 1]], "Misra Chapu (7)": [7, [0, 3, 5]],
    "Khanda Chapu (5)": [5, [0, 2]], "Tisra Triputa (7)": [7, [0, 3, 5]], "Jhampa (10)": [10, [0, 7, 8]],
  },
  western: { "4/4": [4, [0, 2]], "3/4": [3, [0]], "2/4": [2, [0]], "6/8": [6, [0, 3]], "5/4": [5, [0, 3]],
             "7/8": [7, [0, 2, 4]] },
};

export function cycleOf(song) {
  const [beats, strong] = TALAS[song.system][song.tala] || [4, [0]];
  return { beats, strong };
}

// ---- a new song -------------------------------------------------------------

export function newSong(system = "carnatic") {
  const c = system === "carnatic";
  return {
    format: "isai-song", version: 1, system,
    scale: c ? "Mayamalavagowla" : "major (Ionian)",
    sa: 138.6,                       // carnatic: Sa in Hz (138.6 is C#3, a common sruti)
    key: "C", octave: 4, a4: 440,    // western: the key, the octave its tonic is in, tuning
    tala: c ? "Adi (8)" : "4/4", tempo: 90, steps: 2, cycles: 4,
    rate: RATE, mono: false, arpRate: 30,  // the WAV made: samples a second, one channel or two
    loopCycle: 0,                          // the cycle it loops back to: 0 its start, or past an intro
    drone: c, drums: c ? "mridangam" : "kit", swing: 0,
    parts: [
      { name: "lead", instrument: c ? "nadaswaram" : "piano", octave: 0, gain: 0.9, pan: 0.1,
        text: c ? "S , R G M , P , | D , P M G R S ," : "C , D E F , G , | A , G F E D C ," },
      { name: "bass", instrument: c ? "harmonium" : "bass", octave: -1, gain: 0.5, pan: -0.2,
        text: c ? "S ; ; ; , P ; ; ; ," : "C3 ; ; ; , G2 ; ; ; ," },
    ],
  };
}

// A chiptune to start from, in the manner of the old consoles (and of
// Manickam's music): a thin pulse lead, a triangle bass, noise drums,
// mono at 11,025 samples a second.
export function newChipSong(system = "carnatic") {
  const c = system === "carnatic";
  return { ...newSong(system), scale: c ? "Mohanam" : "major pentatonic", drone: false, drums: "chip",
    tempo: 120, steps: 2, rate: 11025, mono: true,
    parts: [
      { name: "lead", instrument: "pulse25", octave: 1, gain: 0.8, pan: 0,
        text: c ? "S , G P D , P G | R , S R G , - - | S{0,4,7} ; ; ; , | P. , D. , S ; ," :
                  "C , E G A , G E | D , C D E , - - | C{0,4,7} ; ; ; , | G3 , A3 , C ; ," },
      { name: "bass", instrument: "triangle", octave: -1, gain: 0.8, pan: 0,
        text: c ? "S , S' , S , S' , | P. , P , P. , P , | S , S' , S , S' , | P. , P , S ; ," :
                  "C3 , C4 , C3 , C4 , | G2 , G3 , G2 , G3 , | C3 , C4 , C3 , C4 , | G2 , G3 , C3 ; ," },
    ] };
}

// ---- the band ---------------------------------------------------------------

export const INSTRUMENTS = {
  carnatic: ["nadaswaram", "venu", "veena", "harmonium", "violin"],
  western: ["piano", "strings", "flute", "bass", "pluck"],
  chip: ["square", "pulse25", "pulse12", "triangle", "saw", "noise"],
};
export const KITS = ["mridangam", "thavil", "kanjira", "kit", "chip", "none"];
const CHIP = new Set(INSTRUMENTS.chip);

function rng(seed) {
  let s = seed >>> 0 || 1;
  return () => { s ^= s << 13; s ^= s >>> 17; s ^= s << 5; return ((s >>> 0) / 4294967296) * 2 - 1; };
}

export function freqOf(semi, song) {
  if (song.system === "carnatic") return song.sa * 2 ** (semi / 12);
  const tonic = song.a4 * 2 ** ((KEYS.indexOf(song.key) - 9) / 12 + (song.octave - 4));
  return tonic * 2 ** (semi / 12);
}

// One note of a melodic voice into out (stereo, adds). arp: semitones to
// cycle the note through, chiptune's chords, `arpRate` times a second.
// The chip voices are plain: no vibrato, a hard start, a short end.
function voice(out, inst, start, dur, f, mark, gain, pan, seed, arp = null, arpRate = 30) {
  const [L, R] = out;
  const pluck = ["veena", "piano", "pluck", "bass"].includes(inst);
  const chip = CHIP.has(inst);
  const tail = pluck ? (inst === "bass" ? 0.6 : 1.4) : chip ? 0.02 : 0.08;
  const n = Math.floor((dur + tail) * SR), i0 = Math.floor(start * SR);
  const noise = rng(seed);
  let ph = 0, lp = 0;
  const gl = gain * Math.cos((pan + 1) * Math.PI / 4), gr = gain * Math.sin((pan + 1) * Math.PI / 4);
  const held = Math.floor(dur * SR);
  for (let k = 0; k < n && i0 + k < L.length; k++) {
    const t = k / SR;
    let cents = 0;
    if (mark === "~" && t > 0.08) cents += 100 * (0.5 - 0.5 * Math.cos(2 * Math.PI * 5.5 * (t - 0.08)));
    if (mark === "/") cents -= 200 * Math.exp(-t * 14);
    if (mark === "\\") cents += 200 * Math.exp(-t * 14);
    const vib = pluck || chip ? 0 : 6 * Math.sin(2 * Math.PI * 5.2 * t) * Math.min(1, t * 3);
    if (arp && arp.length) cents += 100 * arp[Math.floor(t * arpRate) % arp.length];
    const fr = f * 2 ** ((cents + vib) / 1200);
    ph += 2 * Math.PI * fr / SR;
    let env;
    if (pluck) env = Math.min(1, t * 400) * Math.exp(-t * (inst === "bass" ? 3 : inst === "piano" ? 2.2 : 2.8)) *
      (k > held ? Math.exp(-(k - held) / SR * 12) : 1);
    else if (chip) env = (k > held ? Math.max(0, 1 - (k - held) / (tail * SR)) : 1) * Math.min(1, t * 2000);
    else {
      const a = inst === "harmonium" || inst === "strings" ? 0.06 : 0.025;
      env = Math.min(1, t / a) * (k > held ? Math.max(0, 1 - (k - held) / (tail * SR)) : 1) * 0.92;
    }
    let s = 0;
    switch (inst) {
      case "nadaswaram": {                          // a double reed: bright, a formant near 1.6 kHz
        for (let h = 1; h <= 16 && fr * h < SR * 0.45; h++)
          s += h ** -0.55 * (1 + 2.2 * Math.exp(-(((fr * h - 1600) / 900) ** 2))) * Math.sin(h * ph);
        lp += 0.2 * (noise() - lp);
        s = s * 0.2 + lp * 0.15;
        break;
      }
      case "venu": case "flute":
        lp += 0.1 * (noise() - lp);
        s = Math.sin(ph) + 0.28 * Math.sin(2 * ph) + 0.12 * Math.sin(3 * ph) + lp * 0.5 * (0.4 + env);
        s *= 0.5;
        break;
      case "harmonium": {                           // two reeds a little apart
        for (let h = 1; h <= 12 && fr * h < SR * 0.45; h++)
          s += h ** -0.9 * (h % 2 ? 1.4 : 1) * (Math.sin(h * ph) + 0.8 * Math.sin(h * ph * 1.0025));
        s *= 0.12;
        break;
      }
      case "violin": case "strings": {              // a bowed saw, softened
        for (let h = 1; h <= 14 && fr * h < SR * 0.45; h++) s += Math.sin(h * ph) / h * (inst === "strings" ? 0.8 : 1);
        if (inst === "strings") for (let h = 1; h <= 8; h++) s += Math.sin(h * ph * 1.004) / h * 0.6;
        s *= 0.18;
        break;
      }
      case "veena": {                               // a stretched pluck
        for (let h = 1; h <= 10; h++) s += Math.sin(h * ph * (1 + 0.0007 * h * h)) * Math.exp(-t * h * 0.9) / h;
        s *= 0.5;
        break;
      }
      case "piano":
        for (let h = 1; h <= 8; h++) s += Math.sin(h * ph * (1 + 0.0004 * h * h)) * Math.exp(-t * h * 0.7) / (h * h * 0.6 + 0.4);
        s *= 0.45;
        break;
      case "pluck":
        s = (Math.sin(ph) + 0.5 * Math.sin(2 * ph) * Math.exp(-t * 6)) * 0.5;
        break;
      case "bass":
        s = (Math.sin(ph) + 0.3 * Math.sin(2 * ph) * Math.exp(-t * 4)) * 0.7;
        break;
      case "square": case "pulse25": case "pulse12": {    // a pulse, high for this part of each cycle
        const p = (ph / (2 * Math.PI)) % 1;
        s = (p < { square: 0.5, pulse25: 0.25, pulse12: 0.125 }[inst] ? 1 : -1) * 0.22;
        break;
      }
      case "triangle": {                            // stepped in 16 levels, as the old consoles' was
        const p = (ph / (2 * Math.PI)) % 1;
        s = (Math.round((p < 0.5 ? 4 * p - 1 : 3 - 4 * p) * 7.5) / 7.5) * 0.45;
        break;
      }
      case "saw": s = (((ph / (2 * Math.PI)) % 1) * 2 - 1) * 0.2; break;
      case "noise": {                               // a new random level at the note's rate: pitched hiss
        const p = (ph / (2 * Math.PI)) % 1, was = lp;
        if (p < 0.5 !== was > 0 || k === 0) lp = noise() > 0 ? 1 : -1;
        s = lp * 0.18;
        break;
      }
      default: s = Math.sin(ph) * 0.5;
    }
    s *= env;
    L[i0 + k] += s * gl;
    R[i0 + k] += s * gr;
  }
}

function hit(out, start, kind, vel, f0, pan, seed) {
  const [L, R] = out;
  const i0 = Math.floor(start * SR), noise = rng(seed);
  const n = Math.floor(0.6 * SR);
  let ph = 0, lp = 0;
  const gl = vel * Math.cos((pan + 1) * Math.PI / 4), gr = vel * Math.sin((pan + 1) * Math.PI / 4);
  for (let k = 0; k < n && i0 + k < L.length; k++) {
    const t = k / SR;
    let s = 0;
    switch (kind) {
      case "thom": ph += 2 * Math.PI * f0 * 0.5 * (1 + 0.6 * Math.exp(-t * 30)) / SR;
        s = Math.sin(ph) * Math.exp(-t * 9); break;                       // the left (bass) head
      case "nam": ph += 2 * Math.PI * f0 * 2 / SR;                      // the right head, ringing
        s = (Math.sin(ph) + 0.5 * Math.sin(ph * 2.76)) * Math.exp(-t * 14) * 0.6 + noise() * Math.exp(-t * 90) * 0.3; break;
      case "ki": lp += 0.5 * (noise() - lp); s = lp * Math.exp(-t * 60) * 0.8; break;
      case "din": ph += 2 * Math.PI * f0 * 2 / SR; s = Math.sin(ph) * Math.exp(-t * 6) * 0.5; break;
      case "kick": ph += 2 * Math.PI * (50 + 90 * Math.exp(-t * 25)) / SR; s = Math.sin(ph) * Math.exp(-t * 7); break;
      case "snare": ph += 2 * Math.PI * 190 / SR; s = (Math.sin(ph) * 0.4 + noise() * 0.6) * Math.exp(-t * 18); break;
      case "hat": lp += 0.9 * (noise() - lp); s = (noise() - lp) * Math.exp(-t * 45) * 0.4; break;
      case "ckick": ph += 2 * Math.PI * (40 + 160 * Math.exp(-t * 40)) / SR;           // a triangle dropping
        s = (Math.round(((((ph / (2 * Math.PI)) % 1) < 0.5 ? 4 * ((ph / (2 * Math.PI)) % 1) - 1 : 3 - 4 * ((ph / (2 * Math.PI)) % 1))) * 7.5) / 7.5) * Math.exp(-t * 12); break;
      case "csnare": if (k % 3 === 0) lp = noise(); s = lp * Math.exp(-t * 16) * 0.7; break;   // noise, coarse
      case "chat": s = (noise() > 0 ? 1 : -1) * Math.exp(-t * 70) * 0.25; break;              // noise, short
      case "jingle": s = noise() * Math.exp(-t * 20) * (0.6 + 0.4 * Math.sin(t * 2 * Math.PI * 7000)) * 0.4; break;
    }
    L[i0 + k] += s * gl;
    R[i0 + k] += s * gr;
  }
}

const KIT_STROKES = {
  mridangam: { strong: "thom", beat: "nam", off: "ki", ring: "din" },
  thavil: { strong: "kick", beat: "snare", off: "ki", ring: "snare" },
  kanjira: { strong: "din", beat: "jingle", off: "jingle", ring: "nam" },
  kit: { strong: "kick", beat: "snare", off: "hat", ring: "hat" },
  chip: { strong: "ckick", beat: "csnare", off: "chat", ring: "chat" },
};

// The song's length: its cycles, or longer if a part runs past them.
export function songSteps(song) {
  const { beats } = cycleOf(song);
  const per = beats * song.steps;
  let most = song.cycles * per;
  for (const p of song.parts) {
    try { most = Math.max(most, parseNotation(p.text, song).steps); } catch (e) { /* shown by the editor */ }
  }
  return Math.ceil(most / per) * per;
}

// The frame the song loops back to: the start of cycle `loopCycle`.
export function loopFrame(song) {
  const { beats } = cycleOf(song);
  const per = beats * song.steps, steps = songSteps(song);
  const at = Math.min(Math.max(0, song.loopCycle | 0) * per, steps - per);
  return Math.round(at * 60 / song.tempo / song.steps * (song.rate || RATE));
}

// Plays the whole song into two Float32Arrays (left, right). It loops
// without a seam: what rings past the end is folded back onto the start.
export function render(song) {
  SR = song.rate || RATE;
  const { beats, strong } = cycleOf(song);
  const stepSec = 60 / song.tempo / song.steps;
  const steps = songSteps(song);
  const len = Math.round(steps * stepSec * SR), tail = 2 * SR;
  const out = [new Float32Array(len + tail), new Float32Array(len + tail)];
  const tonic = freqOf(0, song);
  let seed = 1;
  if (song.drone) {                                  // a tanpura: Pa Sa Sa Sa-below, over and over
    const notes = SCALES[song.scale].notes;
    const fifth = notes.includes(7) ? 7 : 5;
    const pattern = [fifth - 12, 0, 0, -12];
    for (let t = 0, n = 0; t < len / SR; n++) {
      voice(out, "veena", t, 0.4, tonic * 2 ** (pattern[n % 4] / 12), "", 0.25, n % 2 ? -0.5 : 0.5, seed++);
      t += n % 4 === 3 ? 1.3 : 0.9;
    }
  }
  for (const p of song.parts) {
    const { notes } = parseNotation(p.text, song);
    for (const n of notes) {
      const swing = song.swing && n.at % 2 ? song.swing * stepSec * 0.5 : 0;
      voice(out, p.instrument, n.at * stepSec + swing, n.len * stepSec * (CHIP.has(p.instrument) ? 0.9 : 0.97),
            freqOf(n.semi + 12 * p.octave, song), n.mark, p.gain * (n.vol ? n.vol / 9 : 1), p.pan, seed++, n.arp,
            song.arpRate || 30);
    }
  }
  const kit = KIT_STROKES[song.drums];
  if (kit) {
    const per = beats * song.steps;
    for (let s = 0; s < steps; s++) {
      const b = Math.floor((s % per) / song.steps), sub = s % song.steps;
      const fill = Math.floor(s / per) % 4 === 3 && b >= beats - 1;
      let kind = null, vel = 0.7;
      if (sub === 0) { kind = strong.includes(b) ? kit.strong : kit.beat; vel = strong.includes(b) ? 1 : 0.75; }
      else if (fill || (sub === song.steps / 2) || song.drums === "kit" || song.drums === "chip") { kind = kit.off; vel = 0.5; }
      if (kind) hit(out, s * stepSec, kind, vel * 0.8, tonic, kind === kit.strong ? 0 : 0.15, seed++);
    }
  }
  const L = out[0].subarray(0, len), R = out[1].subarray(0, len);
  const from = loopFrame(song);                     // what rings past the end goes on at the loop point
  for (let i = 0; i < tail && from + i < len; i++) { L[from + i] += out[0][len + i]; R[from + i] += out[1][len + i]; }
  let peak = 0;
  for (let i = 0; i < len; i++) peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
  const g = peak > 0 ? 0.8 / peak : 1;
  for (let i = 0; i < len; i++) { L[i] *= g; R[i] *= g; }
  return [L, R];
}
