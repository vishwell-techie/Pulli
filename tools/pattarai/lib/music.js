// Isai's music: scales (western and Carnatic), the notation a part is
// written in, and the band that plays a song into samples. Everything here
// runs in the browser and in node (tests/test_pattarai.py).

import * as X from "./exact.js";

// The engine's version: a song records the one that made its WAV, and the
// same song makes the same WAV, to the bit, with the same version. Raised
// whenever a change alters a song's sound (tests/isai.sha256 holds each
// example song's fingerprint for it).
export const ENGINE = 2;

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
  "Chintamani": [[0, 3, 2, 3, 6, 7, 8, 7, 12], [12, 10, 8, 7, 6, 3, 2, 0], 56],
  "Atana": [[0, 2, 5, 7, 11, 12], [12, 11, 9, 7, 5, 7, 4, 2, 0], 29],
  "Malayamarutam": [[0, 1, 4, 7, 9, 10, 12], [12, 10, 9, 7, 4, 1, 0], 16],
  "Kadanakutuhalam": [[0, 2, 5, 9, 11, 4, 7, 12], [12, 11, 9, 7, 5, 4, 2, 0], 29],
  "Amritavarshini": [[0, 4, 6, 7, 11, 12], [12, 11, 7, 6, 4, 0], 66],
  "Nattai": [[0, 3, 4, 5, 7, 11, 12], [12, 11, 7, 5, 3, 0], 36],
  "Arabhi": [[0, 2, 5, 7, 9, 12], [12, 11, 9, 7, 5, 4, 2, 0], 29],
  "Jaganmohini": [[0, 4, 5, 7, 11, 12], [12, 11, 7, 5, 4, 1, 0], 15],
  "Saveri": [[0, 1, 5, 7, 8, 12], [12, 11, 8, 7, 5, 4, 1, 0], 15],
  "Pantuvarali": [[0, 1, 4, 6, 7, 8, 11, 12], [12, 11, 8, 7, 6, 4, 1, 0], 51],
  "Hamsanadam": [[0, 2, 6, 7, 11, 12], [12, 11, 7, 6, 2, 0], 60],
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
// The keys as musicians name them; a song saved with C#, D#, G# or A#
// still reads (keyIndex).
export const KEYS = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"];
export const keyIndex = (k) => (KEYS.includes(k) ? KEYS.indexOf(k) : SHARP.indexOf(k) >= 0 ? SHARP.indexOf(k) : FLAT.indexOf(k));

// A note spelled from the key, as a musician would write it: the scale's
// own notes with the key's sharps or flats, the lowered 2nd, 3rd, 6th and
// 7th as flats and the raised 4th as a sharp (in G: Bb, not A#).
const NATURAL = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
const DEGREE = [[0, 0], [1, -1], [1, 0], [2, -1], [2, 0], [3, 0], [3, 1], [4, 0], [5, -1], [5, 0], [6, -1], [6, 0]];
const RAISED = { 1: 0, 3: 1, 6: 3, 8: 4, 10: 5 };          // written raised: di ri fi si li, or with a #
const LOWERED = { 1: 1, 3: 2, 6: 4, 8: 5, 10: 6 };         // written lowered: ra me se le te, or with a b
function spell(semi, song, way = "") {
  const k = keyIndex(song.key), name = KEYS[k];
  const s = ((semi % 12) + 12) % 12;
  const deg = way === "up" && s in RAISED ? RAISED[s] : way === "down" && s in LOWERED ? LOWERED[s] : DEGREE[s][0];
  const letter = "CDEFGAB"["CDEFGAB".indexOf(name[0]) + deg > 6 ? "CDEFGAB".indexOf(name[0]) + deg - 7 : "CDEFGAB".indexOf(name[0]) + deg];
  const abs = k + semi;                                   // semitones above the C of the song's octave
  let acc = (((abs - NATURAL[letter]) % 12) + 12) % 12;
  if (acc > 6) acc -= 12;
  const octave = song.octave + Math.floor((abs - acc - NATURAL[letter]) / 12);
  return { letter, acc: acc > 0 ? "#".repeat(acc) : "b".repeat(-acc), octave };
}
const SOLF_OF = { C: "do", D: "re", E: "mi", F: "fa", G: "sol", A: "la", B: "si" };

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

// Solfège. Movable do (do-based, as in Kodály and Berklee teaching): do is
// the song's key note, the chromatic syllables raise (di ri fi si li) or
// lower (ra me se le te) a step. Fixed do (as in France, Italy, Spain): do
// is always C, si is B, with # and b and an octave number like the letters.
const MOVABLE = { do: 0, di: 1, ra: 1, re: 2, ri: 3, me: 3, mi: 4, fa: 5, fi: 6, se: 6, so: 7, sol: 7, si: 8, le: 8,
                  la: 9, li: 10, te: 10, ti: 11 };
const FIXED = { do: 0, re: 2, mi: 4, fa: 5, sol: 7, so: 7, la: 9, si: 11, ti: 11 };
const MOVABLE_OUT = ["do", "ra", "re", "me", "mi", "fa", "fi", "so", "le", "la", "te", "ti"];
const MOVABLE_UP = { 1: "di", 3: "ri", 6: "fi", 8: "si", 10: "li" };
const SYLLABLE = /^(sol|do|di|ra|re|ri|me|mi|fa|fi|se|so|si|le|la|li|te|ti)(##|bb|[#b]?)(-?\d?)([.']*)([~/\\]?)$/i;
export const NOTE_NAMES = { letters: "letters (C D E)", movable: "movable do", fixed: "fixed do" };

export function noteName(semi, song, way = "") {
  const oct = Math.floor(semi / 12), s = ((semi % 12) + 12) % 12;
  if (song.system === "carnatic") {
    const n = swaraNames(SCALES[song.scale].notes)[s] ||
      ["S", "R1", "R2", "G2", "G3", "M1", "M2", "P", "D1", "D2", "N2", "N3"][s];
    return n + (oct > 0 ? "'".repeat(oct) : ".".repeat(-oct));
  }
  if (song.solfa === "movable")
    return (way === "up" && MOVABLE_UP[s] ? MOVABLE_UP[s] : way === "down" && s === 6 ? "se" : MOVABLE_OUT[s]) +
      (oct > 0 ? "'".repeat(oct) : ".".repeat(-oct));
  const n = spell(semi, song, way);
  return (song.solfa === "fixed" ? SOLF_OF[n.letter] : n.letter) + n.acc + n.octave;
}

// ---- notation -----------------------------------------------------------------
// A part is written one token a step (a step is 1/`steps` of a beat):
//   carnatic: S R G M P D N, the raga's own variant; R1, G3, M2... for a
//             note from outside it; ' after for the octave above, . for the
//             one below (S' P. N..), or a dot above or below the letter as
//             written by hand (Ṡ, Ṇ). Small letters (s r g m p d n) are one
//             step too; when the song's `longCaps` is set, as it is in new
//             Carnatic songs, a capital is two steps (two aksharas) and a
//             small letter one, the way lines are written out by hand:
//             "S , r G P D Ṡ N D |" 
//   western:  C D E F G A B with # or b and an octave number (C4, F#3, Bb5);
//             the octave can be left out, and is then the song's octave, or
//             marked ' above it and . below (E' D'# B.); or
//             solfège: do re mi fa so la ti, movable (do is the key note,
//             di ri fi si li raise a step, ra me se le te lower one, ' and .
//             for octaves), or fixed when the song's `solfa` is "fixed" (do
//             is C, si is B, with # b and an octave number: sol4, sib3)
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
    let semi, m, long = false, way = "";
    if (song.system === "carnatic") {
      // a dot above or below the letter (Ṡ, ṇ) reads as ' or .
      const t = tok.normalize("NFD").replace(/^(.)\u0307/, "$1'").replace(/^(.)\u0323/, "$1.");
      m = t.match(/^([SRGMPDNsrgmpdn])([123]?)([.']*)([~/\\]?)$/);
      if (!m) throw new Error(`cannot read "${tok}"`);
      long = song.longCaps && m[1] === m[1].toUpperCase();
      m[1] = m[1].toUpperCase();
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
    } else if ((m = tok.match(SYLLABLE))) {
      // solfège: movable unless the song says fixed; ' and . for octaves
      const syl = m[1].toLowerCase(), acc = m[2].length ? (m[2][0] === "#" ? 1 : -1) * m[2].length : 0;
      way = m[2][0] === "#" ? "up" : m[2][0] === "b" ? "down" : song.solfa === "fixed" ? ""
        : ["di", "ri", "fi", "si", "li"].includes(syl) ? "up" : ["ra", "me", "se", "le", "te"].includes(syl) ? "down" : "";
      const ticks = (m[4].match(/'/g) || []).length - (m[4].match(/\./g) || []).length;
      if (song.solfa === "fixed") {
        if (!(syl in FIXED)) throw new Error(`"${tok}" is movable do; in fixed do write do re mi fa sol la si, with # or b`);
        const octave = m[3] === "" ? song.octave : +m[3];
        semi = FIXED[syl] + acc + 12 * (octave - song.octave + ticks) - keyIndex(song.key);
      } else {
        if (m[3] !== "") throw new Error(`"${tok}": in movable do an octave is marked ' above or . below (do', so.)`);
        if (!(syl in MOVABLE)) throw new Error(`cannot read "${tok}"`);
        semi = MOVABLE[syl] + acc + 12 * ticks;
      }
      m = [null, null, null, null, m[5]];
    } else {
      // a letter, its octave marks (' up, . down, before or after a sharp
      // or flat: E' D'# Bb.), or an octave number: C4 F#3
      m = tok.match(/^([A-Ga-g])([.']*)(##|bb|[#b]?)([.']*)(-?\d?)([~/\\]?)$/);
      if (!m) throw new Error(`cannot read "${tok}"`);
      const marks = m[2] + m[4];
      if (marks && m[5] !== "") throw new Error(`"${tok}": give an octave number or ' and ., not both`);
      const pitch = NATURAL[m[1].toUpperCase()] + (m[3].length ? (m[3][0] === "#" ? 1 : -1) * m[3].length : 0);
      way = m[3][0] === "#" ? "up" : m[3][0] === "b" ? "down" : "";
      const ticks = (marks.match(/'/g) || []).length - (marks.match(/\./g) || []).length;
      const octave = m[5] === "" ? song.octave + ticks : +m[5];
      semi = pitch + 12 * (octave - song.octave) - keyIndex(song.key);
      m = [null, null, null, null, m[6]];
    }
    const note = { at, len: long ? 2 : 1, semi, mark: m[4] || "" };
    if (arp) note.arp = arp;
    if (vol) note.vol = vol;
    if (way) note.way = way;                // written raised or lowered: spelled so when written back
    notes.push(note);
    at += note.len;
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
  const token = (n, small) => {
    if (song.system === "carnatic") {
      const s = ((n.semi % 12) + 12) % 12, oct = Math.floor(n.semi / 12);
      const own = swaraNames(SCALES[song.scale].notes)[s];
      let name = own ? (own.length > 1 ? own[0] : own) : noteName(s, song).replace(/[.']/g, "");
      if (small) name = name.toLowerCase();
      return name + (oct > 0 ? "'".repeat(oct) : ".".repeat(-oct)) + n.mark + arpText(n);
    }
    return noteName(n.semi, song, n.way) + n.mark + arpText(n);
  };
  while (at < steps) {
    if (perBar && at && at % perBar === 0) out.push("|");
    const n = sorted[i];
    if (n && n.at === at) {
      // with long capitals: a capital for two steps (unless a bar line falls
      // between them), a small letter for one
      const capital = song.longCaps && song.system === "carnatic" && n.len >= 2 && at + 1 < steps &&
        !(perBar && (at + 1) % perBar === 0);
      out.push(token(n, song.longCaps && song.system === "carnatic" && !capital));
      for (let k = capital ? 2 : 1; k < n.len && at + k < steps; k++) {
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
  western: { "4/4": [4, [0, 2]], "3/4": [3, [0]], "2/4": [2, [0]], "3/8": [3, [0]], "6/8": [6, [0, 3]],
             "9/8": [9, [0, 3, 6]], "12/8": [12, [0, 3, 6, 9]], "5/4": [5, [0, 3]], "7/8": [7, [0, 2, 4]] },
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
    longCaps: c,                           // carnatic: capitals two aksharas, small letters one
    rate: RATE, mono: false, arpRate: 30,  // the WAV made: samples a second, one channel or two
    loopCycle: 0,                          // the cycle it loops back to: 0 its start, or past an intro
    drone: c, drums: c ? "mridangam" : "kit", swing: 0,
    parts: [
      { name: "lead", instrument: c ? "nadaswaram" : "piano", octave: 0, gain: 0.9, pan: 0.1,
        text: c ? "S r g M P | D p m g r S" : "C , D E F , G , | A , G F E D C ," },
      { name: "bass", instrument: c ? "harmonium" : "bass", octave: -1, gain: 0.5, pan: -0.2,
        text: c ? "S ; ; ; P ; ; ;" : "C3 ; ; ; , G2 ; ; ; ," },
    ],
  };
}

// A chiptune to start from, in the manner of the old consoles (and of
// Manickam's music): a thin pulse lead, a triangle bass, noise drums,
// mono at 11,025 samples a second.
export function newChipSong(system = "carnatic") {
  const c = system === "carnatic";
  return { ...newSong(system), longCaps: false, scale: c ? "Mohanam" : "major pentatonic", drone: false, drums: "chip",
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
  western: ["piano", "strings", "flute", "bass", "pluck", "brass", "organ"],
  chip: ["square", "pulse25", "pulse12", "triangle", "saw", "noise"],
  drums: ["drums"],
};
export const KITS = ["mridangam", "thavil", "kanjira", "kit", "orchestra", "chip", "none"];
const CHIP = new Set(INSTRUMENTS.chip);

function rng(seed) {
  let s = seed >>> 0 || 1;
  return () => { s ^= s << 13; s ^= s >>> 17; s ^= s << 5; return ((s >>> 0) / 4294967296) * 2 - 1; };
}

export function freqOf(semi, song) {
  if (song.system === "carnatic") return song.sa * X.pow(2, semi / 12);
  const tonic = song.a4 * X.pow(2, (keyIndex(song.key) - 9) / 12 + (song.octave - 4));
  return tonic * X.pow(2, semi / 12);
}

// sin(h·x) for h = 1..n into S, each from the two before it (sin hx =
// 2 cos x · sin (h-1)x − sin (h-2)x): two sines a sample, not one a harmonic
const S = new Float64Array(20), S2 = new Float64Array(20);
function harmonics(into, x, n) {
  const s1 = X.sin(x), c2 = 2 * X.cos(x);
  into[1] = s1; into[2] = c2 * s1;
  for (let h = 3; h <= n; h++) into[h] = c2 * into[h - 1] - into[h - 2];
}
// each harmonic's level, the same for every sample
const REED = Array.from({ length: 17 }, (_, h) => (h ? X.pow(h, -0.55) : 0));
const REEDS = Array.from({ length: 13 }, (_, h) => (h ? X.pow(h, -0.9) * (h % 2 ? 1.4 : 1) : 0));

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
  let ph = 0, lp = 0, hp = 0;
  const BREATH = 1 - X.exp(-2 * Math.PI * 1500 / SR);
  const gl = gain * X.cos((pan + 1) * Math.PI / 4), gr = gain * X.sin((pan + 1) * Math.PI / 4);
  const held = Math.floor(dur * SR);
  for (let k = 0; k < n && i0 + k < L.length; k++) {
    const t = k / SR;
    let cents = 0;
    if (mark === "~" && t > 0.08) cents += 100 * (0.5 - 0.5 * X.cos(2 * Math.PI * 5.5 * (t - 0.08)));
    if (mark === "/") cents -= 200 * X.exp(-t * 14);
    if (mark === "\\") cents += 200 * X.exp(-t * 14);
    const vib = pluck || chip || inst === "organ" ? 0 : 6 * X.sin(2 * Math.PI * 5.2 * t) * Math.min(1, t * 3);
    if (arp && arp.length) cents += 100 * arp[Math.floor(t * arpRate) % arp.length];
    const fr = f * X.pow(2, (cents + vib) / 1200);
    ph += 2 * Math.PI * fr / SR;
    let env;
    if (pluck) env = Math.min(1, t * 400) * X.exp(-t * (inst === "bass" ? 3 : inst === "piano" ? 2.2 : 2.8)) *
      (k > held ? X.exp(-(k - held) / SR * 12) : 1);
    else if (chip) env = (k > held ? Math.max(0, 1 - (k - held) / (tail * SR)) : 1) * Math.min(1, t * 2000);
    else {
      const a = inst === "harmonium" || inst === "strings" ? 0.06 : inst === "brass" ? 0.045 : inst === "organ" ? 0.012 : 0.025;
      env = Math.min(1, t / a) * (k > held ? Math.max(0, 1 - (k - held) / (tail * SR)) : 1) * 0.92;
    }
    let s = 0;
    switch (inst) {
      case "nadaswaram": {                          // a double reed: bright, a formant near 1.6 kHz
        harmonics(S, ph, 16);
        for (let h = 1; h <= 16 && fr * h < SR * 0.45; h++)
          { const q = (fr * h - 1600) / 900; s += REED[h] * (1 + 2.2 * X.exp(-q * q)) * S[h]; }
        lp += 0.2 * (noise() - lp);
        s = s * 0.2 + lp * 0.15;
        break;
      }
      case "venu": case "flute": {                  // breath: a puff as the note starts, then a little air,
        lp += BREATH * (noise() - lp);               // kept below about 1.5 kHz whatever the rate
        hp += BREATH * (lp - hp);
        harmonics(S, ph, 3);
        s = S[1] + 0.28 * S[2] + 0.12 * S[3] + hp * (0.3 * X.exp(-t * 30) + 0.03);
        s *= 0.5;
        break;
      }
      case "harmonium": {                           // two reeds a little apart
        harmonics(S, ph, 12); harmonics(S2, ph * 1.0025, 12);
        for (let h = 1; h <= 12 && fr * h < SR * 0.45; h++) s += REEDS[h] * (S[h] + 0.8 * S2[h]);
        s *= 0.12;
        break;
      }
      case "violin": case "strings": {              // a bowed saw, softened
        harmonics(S, ph, 14);
        for (let h = 1; h <= 14 && fr * h < SR * 0.45; h++) s += S[h] / h * (inst === "strings" ? 0.8 : 1);
        if (inst === "strings") { harmonics(S2, ph * 1.004, 8); for (let h = 1; h <= 8; h++) s += S2[h] / h * 0.6; }
        s *= 0.18;
        break;
      }
      case "brass": {                               // a horn section: brighter as the breath builds
        const open = Math.min(1, 0.35 + t * 5);
        harmonics(S, ph, 14);
        for (let h = 1; h <= 14 && fr * h < SR * 0.45; h++) s += S[h] * X.pow(h, -0.7 - 1.6 * (1 - open));
        harmonics(S2, ph * 0.997, 6);
        for (let h = 1; h <= 6; h++) s += S2[h] / (h * 2);
        s *= 0.16;
        break;
      }
      case "organ": {                               // pipes at 8', 4', 2 2/3' and 2': no vibrato, steady
        harmonics(S, ph, 8);
        s = (S[1] + 0.7 * S[2] + 0.45 * S[3] + 0.4 * S[4] + 0.15 * S[6] + 0.12 * S[8]) * 0.22;
        break;
      }
      case "veena": {                               // a stretched pluck
        const fade = X.exp(-t * 0.9);                // each harmonic fades as this to the power h
        for (let h = 1, f = fade; h <= 10; h++, f *= fade) s += X.sin(h * ph * (1 + 0.0007 * h * h)) * f / h;
        s *= 0.5;
        break;
      }
      case "piano":
        { const fade = X.exp(-t * 0.7);
          for (let h = 1, f = fade; h <= 8; h++, f *= fade) s += X.sin(h * ph * (1 + 0.0004 * h * h)) * f / (h * h * 0.6 + 0.4); }
        s *= 0.45;
        break;
      case "pluck":
        s = (X.sin(ph) + 0.5 * X.sin(2 * ph) * X.exp(-t * 6)) * 0.5;
        break;
      case "bass":
        s = (X.sin(ph) + 0.3 * X.sin(2 * ph) * X.exp(-t * 4)) * 0.7;
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
      default: s = X.sin(ph) * 0.5;
    }
    s *= env;
    L[i0 + k] += s * gl;
    R[i0 + k] += s * gr;
  }
}

const RINGS = { bell: 2.5, conch: 1.7, jalra: 1.2, timp: 1.6, cymbal: 2.2, tri: 1.2 };          // seconds a stroke sounds, if not 0.6

function hit(out, start, kind, vel, f0, pan, seed) {
  const [L, R] = out;
  const i0 = Math.floor(start * SR), noise = rng(seed);
  const n = Math.floor((RINGS[kind] || 0.6) * SR);
  let ph = 0, lp = 0, hp = 0;
  const gl = vel * X.cos((pan + 1) * Math.PI / 4), gr = vel * X.sin((pan + 1) * Math.PI / 4);
  for (let k = 0; k < n && i0 + k < L.length; k++) {
    const t = k / SR;
    let s = 0;
    switch (kind) {
      case "thom": ph += 2 * Math.PI * f0 * 0.5 * (1 + 0.6 * X.exp(-t * 30)) / SR;
        s = X.sin(ph) * X.exp(-t * 9); break;                       // the left (bass) head
      case "nam": ph += 2 * Math.PI * f0 * 2 / SR;                      // the right head, ringing
        s = (X.sin(ph) + 0.5 * X.sin(ph * 2.76)) * X.exp(-t * 14) * 0.6 + noise() * X.exp(-t * 90) * 0.3; break;
      case "ki": lp += 0.5 * (noise() - lp); s = lp * X.exp(-t * 60) * 0.8; break;
      case "din": ph += 2 * Math.PI * f0 * 2 / SR; s = X.sin(ph) * X.exp(-t * 6) * 0.5; break;
      case "kick": ph += 2 * Math.PI * (50 + 90 * X.exp(-t * 25)) / SR; s = X.sin(ph) * X.exp(-t * 7); break;
      case "snare": ph += 2 * Math.PI * 190 / SR; s = (X.sin(ph) * 0.4 + noise() * 0.6) * X.exp(-t * 18); break;
      case "hat": lp += 0.9 * (noise() - lp); s = (noise() - lp) * X.exp(-t * 45) * 0.4; break;
      case "ckick": ph += 2 * Math.PI * (40 + 160 * X.exp(-t * 40)) / SR;           // a triangle dropping
        s = (Math.round(((((ph / (2 * Math.PI)) % 1) < 0.5 ? 4 * ((ph / (2 * Math.PI)) % 1) - 1 : 3 - 4 * ((ph / (2 * Math.PI)) % 1))) * 7.5) / 7.5) * X.exp(-t * 12); break;
      case "csnare": if (k % 3 === 0) lp = noise(); s = lp * X.exp(-t * 16) * 0.7; break;   // noise, coarse
      case "chat": s = (noise() > 0 ? 1 : -1) * X.exp(-t * 70) * 0.25; break;              // noise, short
      case "jingle": s = noise() * X.exp(-t * 20) * (0.6 + 0.4 * X.sin(t * 2 * Math.PI * 7000)) * 0.4; break;
      case "timp": ph += 2 * Math.PI * f0 * 0.5 * (1 + 0.04 * X.exp(-t * 20)) / SR;       // a kettledrum on the tonic
        s = (X.sin(ph) + 0.35 * X.sin(ph * 1.5) * X.exp(-t * 3) + noise() * X.exp(-t * 60) * 0.25) * X.exp(-t * 2.6) * 0.9; break;
      case "field": ph += 2 * Math.PI * 160 / SR;                                         // a field drum: rattling, fuller than a snare
        lp += 0.4 * (noise() - lp); s = (X.sin(ph) * 0.5 + lp * 0.9) * X.exp(-t * 11); break;
      case "tri": ph += 2 * Math.PI * 4200 / SR;                                          // a triangle: one bright ring
        s = (X.sin(ph) + 0.4 * X.sin(ph * 2.3)) * X.exp(-t * 3.5) * 0.12 * (t < 0.001 ? t / 0.001 : 1); break;
      case "cymbal": { const x = noise(); hp = x - lp; lp += 0.15 * (x - lp);             // a clash, washing out
        s = hp * X.exp(-t * 2.2) * 0.35; break; }
      case "bell": {                                 // a temple bell: partials that are not harmonics
        ph += 2 * Math.PI * f0 * 4 / SR;
        s = (X.sin(ph) + 0.6 * X.sin(ph * 2.01) * X.exp(-t * 1.5) + 0.4 * X.sin(ph * 2.76) * X.exp(-t * 3)
             + 0.25 * X.sin(ph * 5.4) * X.exp(-t * 6)) * X.exp(-t * 1.6) * 0.35 * (t < 0.002 ? t / 0.002 : 1);
        break;
      }
      case "conch": {                                // a sangu: a blown horn, swelling, with breath
        ph += 2 * Math.PI * f0 * 2 * (1 + 0.01 * X.sin(t * 2 * Math.PI * 4.5)) / SR;
        const env = (t < 0.25 ? t / 0.25 : 1) * (t > 1.2 ? X.exp(-(t - 1.2) * 8) : 1);
        lp += 0.1 * (noise() - lp);
        s = (X.sin(ph) + 0.5 * X.sin(ph * 2) + 0.3 * X.sin(ph * 3) + 0.15 * X.sin(ph * 4) + lp * 0.3) * env * 0.3;
        break;
      }
      case "jalra": {                                // small hand cymbals: bright noise, ringing
        const x = noise();
        hp = x - lp; lp += 0.3 * (x - lp);
        s = hp * (0.6 + 0.4 * X.sin(t * 2 * Math.PI * 5200)) * X.exp(-t * 7) * 0.3;
        break;
      }
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
  orchestra: { strong: "timp", beat: "field", off: "tri", ring: "cymbal" },
  chip: { strong: "ckick", beat: "csnare", off: "chat", ring: "chat" },
};

// ---- drum parts ---------------------------------------------------------------
// A part whose instrument is "drums" is written in strokes, one a step, and
// played on the song's kit (mridangam when it has none, or a western kit in
// a western song). Each stroke is one of four kinds, which every kit has:
//   strong  the deep, accented stroke: thom dhom tom, kick bd
//   beat    the main stroke:           tha ta nam na, snare sd
//   off     the light, quick stroke:   ki ka ti, hat hh
//   ring    the ringing stroke:        dhi din di tham, open oh
// Any kit also has bell (a temple bell), conch (a sangu) and jalra (small
// cymbals), written by name.
// a+b plays two at once (kick+hat); - or , is a step with no stroke, ; two;
// | is a bar line; !1 to !9 at the end sets the stroke's volume.
export const STROKE_KIND = {
  thom: "strong", dhom: "strong", tom: "strong", kick: "strong", bd: "strong",
  tha: "beat", ta: "beat", nam: "beat", na: "beat", snare: "beat", sd: "beat",
  ki: "off", ka: "off", ti: "off", hat: "off", hh: "off",
  dhi: "ring", din: "ring", di: "ring", tham: "ring", open: "ring", oh: "ring",
  bell: "bell", conch: "conch", jalra: "jalra",
};
const KIND_LOUD = { strong: 1, beat: 0.75, off: 0.5, ring: 0.75, bell: 0.8, conch: 0.8, jalra: 0.6 };
export const KIND_ORDER = ["strong", "beat", "off", "ring", "bell", "jalra", "conch"];
// how each kind is written back: konnakol in a Carnatic song, kit names in a western one
const OWN = { bell: "bell", jalra: "jalra", conch: "conch" };   // the same on every kit
const KIND_WORD = { carnatic: { strong: "thom", beat: "tha", off: "ki", ring: "dhi", ...OWN },
                    western: { strong: "kick", beat: "snare", off: "hat", ring: "open", ...OWN } };
export const drumWord = (kind, song) => KIND_WORD[song.system][kind];
export const kitOf = (song) => KIT_STROKES[song.drums] ? song.drums : song.system === "carnatic" ? "mridangam" : "kit";

export function parseDrums(text, song) {
  const hits = [];
  let at = 0;
  for (let tok of text.replace(/\/\/[^\n]*/g, "").split(/\s+/).filter((t) => t)) {
    if (tok === "|" || tok === "||") continue;
    if (tok === "-" || tok === "," || tok === "_") { at += 1; continue; }
    if (tok === ";") { at += 2; continue; }
    let vol = null;
    const bang = tok.match(/^(.+)!([1-9])$/);
    if (bang) { tok = bang[1]; vol = +bang[2]; }
    for (const word of tok.toLowerCase().split("+")) {
      const kind = STROKE_KIND[word];
      if (!kind) throw new Error(`"${word}" is not a stroke: write thom tha ki dhi, or kick snare hat open`);
      hits.push(vol ? { at, kind, vol } : { at, kind });
    }
    at += 1;
  }
  return { hits, steps: at };
}

export function writeDrums(hits, steps, song, perBar) {
  const out = [];
  for (let at = 0; at < steps; at++) {
    if (perBar && at && at % perBar === 0) out.push("|");
    const here = hits.filter((x) => x.at === at).sort((a, b) => KIND_ORDER.indexOf(a.kind) - KIND_ORDER.indexOf(b.kind));
    if (!here.length) { out.push("-"); continue; }
    const vol = here.find((x) => x.vol)?.vol;
    out.push([...new Set(here.map((x) => drumWord(x.kind, song)))].join("+") + (vol && vol < 9 ? "!" + vol : ""));
  }
  return out.join(" ");
}

// The automatic pattern, as hits: the tala's (or time's) strong beats, the
// others, a light stroke between, and a fill at the end of every fourth
// cycle. The same pattern plays when the song's drum pattern is automatic,
// and + Drum part writes it out to start from.
export function autoHits(song, steps) {
  const { beats, strong } = cycleOf(song);
  const per = beats * song.steps, hits = [];
  const busy = song.drums === "kit" || song.drums === "chip";
  for (let st = 0; st < steps; st++) {
    const b = Math.floor((st % per) / song.steps), sub = st % song.steps;
    const fill = Math.floor(st / per) % 4 === 3 && b >= beats - 1;
    if (sub === 0) hits.push({ at: st, kind: strong.includes(b) ? "strong" : "beat" });
    else if (fill || sub === song.steps / 2 || busy) hits.push({ at: st, kind: "off" });
  }
  return hits;
}

// each stroke's own noise, the same whether the pattern or a part plays it
const strokeSeed = (x) => 7001 + x.at * 4 + KIND_ORDER.indexOf(x.kind);

// The steps a part runs to, whatever it is written in.
export function partSteps(p, song) {
  return p.instrument === "drums" ? parseDrums(p.text, song).steps : parseNotation(p.text, song).steps;
}

// The song's length: its cycles, or longer if a part runs past them.
export function songSteps(song) {
  const { beats } = cycleOf(song);
  const per = beats * song.steps;
  let most = song.cycles * per;
  for (const p of song.parts) {
    try { most = Math.max(most, partSteps(p, song)); } catch (e) { /* shown by the editor */ }
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
// A hall, after Schroeder: four echoes feeding back, in parallel, then two
// that smear them; the right channel's a little longer than the left's.
// `amount` 0-1 is how much of it is heard and how long it rings.
function reverb(x, amount, right) {
  const scale = SR / 44100, spread = right ? 23 : 0;
  const combs = [1557, 1617, 1491, 1422].map((d) => new Float32Array(Math.round((d + spread) * scale)));
  const passes = [556, 441].map((d) => new Float32Array(Math.round((d + spread) * scale)));
  const fb = 0.7 + 0.18 * amount, damp = 0.25, wet = 0.35 * amount;
  const ci = [0, 0, 0, 0], low = [0, 0, 0, 0], pi = [0, 0];
  for (let i = 0; i < x.length; i++) {
    const dry = x[i];
    let y = 0;
    for (let c = 0; c < 4; c++) {
      const buf = combs[c], out = buf[ci[c]];
      low[c] = out * (1 - damp) + low[c] * damp;
      buf[ci[c]] = dry * 0.25 + low[c] * fb;
      ci[c] = ci[c] + 1 === buf.length ? 0 : ci[c] + 1;
      y += out;
    }
    for (let a = 0; a < 2; a++) {
      const buf = passes[a], b = buf[pi[a]];
      buf[pi[a]] = y + b * 0.5;
      y = b - y * 0.5;
      pi[a] = pi[a] + 1 === buf.length ? 0 : pi[a] + 1;
    }
    x[i] = dry + y * wet;
  }
}

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
      voice(out, "veena", t, 0.4, tonic * X.pow(2, pattern[n % 4] / 12), "", 0.25, n % 2 ? -0.5 : 0.5, seed++);
      t += n % 4 === 3 ? 1.3 : 0.9;
    }
  }
  const kitNow = KIT_STROKES[kitOf(song)];
  for (const p of song.parts) {
    let read;                                        // a part that cannot be read is left out; the editor says why
    try { read = p.instrument === "drums" ? parseDrums(p.text, song) : parseNotation(p.text, song); } catch (e) { continue; }
    if (p.instrument === "drums") {                  // a drum part: strokes on the song's kit
      for (const x of read.hits)
        hit(out, x.at * stepSec, OWN[x.kind] || kitNow[x.kind], (x.vol ? x.vol / 9 : KIND_LOUD[x.kind]) * 0.8 * p.gain / 0.9, tonic,
            x.kind === "strong" ? 0 : p.pan, strokeSeed(x));
      continue;
    }
    const { notes } = read;
    for (const n of notes) {
      const swing = song.swing && n.at % 2 ? song.swing * stepSec * 0.5 : 0;
      voice(out, p.instrument, n.at * stepSec + swing, n.len * stepSec * (CHIP.has(p.instrument) ? 0.9 : 0.97),
            freqOf(n.semi + 12 * p.octave, song), n.mark, p.gain * (n.vol ? n.vol / 9 : 1), p.pan, seed++, n.arp,
            song.arpRate || 30);
    }
  }
  const kit = KIT_STROKES[song.drums];
  if (kit && song.drumPattern !== "own") {           // the automatic pattern, unless the song has its own
    for (const x of autoHits(song, steps))
      hit(out, x.at * stepSec, kit[x.kind], KIND_LOUD[x.kind] * 0.8, tonic, x.kind === "strong" ? 0 : 0.15, strokeSeed(x));
  }
  if (song.reverb > 0) for (const ch of out) reverb(ch, song.reverb, ch === out[1]);
  const L = out[0].subarray(0, len), R = out[1].subarray(0, len);
  const from = loopFrame(song);                     // what rings past the end goes on at the loop point
  for (let i = 0; i < tail && from + i < len; i++) { L[from + i] += out[0][len + i]; R[from + i] += out[1][len + i]; }
  let peak = 0;
  for (let i = 0; i < len; i++) peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
  const g = peak > 0 ? 0.8 / peak : 1;
  for (let i = 0; i < len; i++) { L[i] *= g; R[i] *= g; }
  return [L, R];
}
