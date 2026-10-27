// Run by tests/test_pattarai.py: exercises Pattarai's libraries in node and
// prints what they make, as JSON, for the Python side to check against
// pulli.py (the reader of everything the editors write).
import * as M from "../tools/pattarai/lib/music.js";
import { parseTMX, writeTMX, newTMX, newTSX, parseTSX, setTileFlags } from "../tools/pattarai/lib/tmx.js";
import { encodePNG } from "../tools/pattarai/lib/png.js";
import { encodeWAV, decodeWAV } from "../tools/pattarai/lib/wav.js";
import { readFileSync } from "fs";
import * as O from "../tools/pattarai/lib/sfx.js";
import { BUILTIN, quantiseTo } from "../tools/pattarai/lib/palette.js";
import { API, SIGS, highlight, callAt, numbered, complete, callHint, wordBefore } from "../tools/pattarai/lib/lua.js";

const [, , village] = process.argv;
const b64 = (u8) => Buffer.from(u8).toString("base64");
const out = {};

// scales
out.mela = Object.fromEntries([1, 8, 15, 20, 22, 28, 29, 36, 37, 56, 65, 72].map((n) => [n, M.melakarta(n)]));
const melas = Object.values(M.SCALES).filter((s) => s.mela);
out.melaCount = melas.length;
out.melaDistinct = new Set(melas.map((s) => s.notes.join())).size;
out.names = Object.fromEntries(["Mayamalavagowla", "Hindolam", "Mohanam", "Shivaranjani", "Revati", "Kalyani"]
  .map((n) => [n, M.swaraNames(M.SCALES[n].notes)]));
out.melaOf = Object.fromEntries(["Hanumatodi", "Mayamalavagowla", "Natabhairavi", "Kharaharapriya",
  "Dheerasankarabharanam", "Shanmukhapriya", "Mechakalyani"].map((n) => [n, M.SCALES[n].mela]));
out.janyaInParent = Object.entries(M.SCALES).filter(([, s]) => s.parent)
  .map(([n, s]) => [n, s.notes.every((x) => M.melakarta(s.parent).includes(x))]);

// notation
const c = { ...M.newSong("carnatic"), scale: "Mayamalavagowla", longCaps: false };   // one letter, one step
const text = "S , R G M ; P | D. N. S' S'' ~ - G3 M2/ P\\";
try { M.parseNotation(text, c); out.badTilde = false; } catch (e) { out.badTilde = true; }
const ok = "S , R G M ; P | D. N. S' S'' - G3 M2/ P\\ ,";
const p = M.parseNotation(ok, c);
out.carnatic = p;
out.carnaticAgain = M.parseNotation(M.writeNotation(p.notes, p.steps, c, 8), c);
try { M.parseNotation("R", { ...c, scale: "Hindolam" }); out.missing = null; } catch (e) { out.missing = e.message; }
const w = { ...M.newSong("western"), key: "D", octave: 4 };
const q = M.parseNotation("D4 , F#4 A A4~ - D5 Bb3 ;", w);
out.western = q;
out.westernNames = q.notes.map((n) => M.noteName(n.semi, w));
out.westernAgain = M.parseNotation(M.writeNotation(q.notes, q.steps, w, 4), w);
out.freqs = { a4: M.freqOf(7, { ...w, key: "D", octave: 4 }), sa: M.freqOf(12, c) };

// render: the same song twice is the same sound, as long as its cycles
const song = M.newSong("carnatic");
const r1 = M.render(song), r2 = M.render(song);
out.render = { len: r1[0].length, same: r1[0].every((v, i) => v === r2[0][i]) && r1[1].every((v, i) => v === r2[1][i]),
  peak: [...r1[0], ...r1[1]].reduce((m, v) => Math.max(m, Math.abs(v)), 0),
  steps: M.songSteps(song), tempo: song.tempo, perStep: song.steps };
for (const sys of ["carnatic", "western"]) {
  const s = M.newSong(sys);
  for (const inst of Object.values(M.INSTRUMENTS).flat().filter((i) => i !== "drums"))
    for (const kit of M.KITS) {
      const [L] = M.render({ ...s, cycles: 1, parts: [{ ...s.parts[0], instrument: inst }], drums: kit });
      if (!L.every(Number.isFinite)) out.badRender = `${sys} ${inst} ${kit}`;
    }
}

// chiptune: a song at 8,000 samples a second, arpeggios read and written
const chip = { ...M.newChipSong("western"), rate: 8000 };
const cr = M.render(chip);
out.chip = { len: cr[0].length, want: Math.round(M.songSteps(chip) * 60 / chip.tempo / chip.steps * 8000),
  finite: cr.every((c) => c.every(Number.isFinite)), parts: M.newChipSong("carnatic").parts.map((p) =>
    M.parseNotation(p.text, M.newChipSong("carnatic")).steps) };
const arp = M.parseNotation("C{0,4,7} , E~{0,12} G{0,-12}", chip);
out.arp = arp.notes.map((n) => [n.semi, n.len, n.mark, n.arp || null]);
out.arpAgain = M.parseNotation(M.writeNotation(arp.notes, arp.steps, chip, 0), chip).notes.map((n) => [n.semi, n.len, n.mark, n.arp || null]);
try { M.parseNotation("C{0 4", chip); out.arpBad = false; } catch (e) { out.arpBad = true; }
// the pitch an arpeggio is heard at: zero crossings of a plain square, a fifth of a second each
const probe = (arpNotes) => {
  const s = { ...M.newChipSong("western"), rate: 44100, mono: false, drums: "none", tempo: 60, steps: 1, cycles: 1, arpRate: 5,
    tala: "4/4", parts: [{ name: "x", instrument: "square", octave: 0, gain: 1, pan: 0, text: arpNotes }] };
  const [L] = M.render(s), seg = [];
  for (let k = 0; k < 3; k++) {
    let n = 0;
    for (let i = k * 8820 + 2000; i < (k + 1) * 8820 - 2000; i++) if (L[i - 1] < 0 && L[i] >= 0) n++;
    seg.push(n);
  }
  return seg;
};
out.arpHeard = probe("C4{0,12} ; ; ,");
out.chipWav = b64(encodeWAV([cr[0]], 8000));
// lines as written by hand: capitals two aksharas, small letters one, dots for octaves
const bil = { ...M.newSong("carnatic"), scale: "Bilahari" };
const handLine = "S  ,  r      G  P     D  Ṡ   N D     |    P  d  p    m g  r s      r s   ṇ  ḍ           S ;        ||";
const hp = M.parseNotation(handLine, bil);
out.hand = { steps: hp.steps, notes: hp.notes.map((n) => [n.semi, n.len]) };
const hw = M.writeNotation(hp.notes, hp.steps, bil, 16);
out.handAgain = M.parseNotation(hw, bil).notes.map((n) => [n.semi, n.len]);
out.handWritten = hw;
out.oldSong = M.parseNotation("S , R G s r", { ...bil, longCaps: undefined }).notes.map((n) => [n.at, n.len]);
const flat = { ...bil, longCaps: false }, flatText = M.writeNotation(hp.notes, hp.steps, flat, 16);
out.toggled = M.parseNotation(flatText, flat).notes.map((n) => [n.semi, n.len]);
out.starter = M.newSong("carnatic").parts.map((p) => M.parseNotation(p.text, M.newSong("carnatic")).steps);
out.dots = M.parseNotation("Ṡ ṡ Ṇ ṇ S' n.", { ...bil }).notes.map((n) => [n.semi, n.len]);

// solfège and spelling
const inKey = (key, text, solfa) => { const g = { ...M.newSong("western"), key, solfa };
  return M.parseNotation(text, g).notes.map((n) => M.noteName(n.semi, g, n.way)); };
out.solfa = {
  movableG: inKey("G", "do re mi fa so la ti do' so. di ri fi si li ra me se le te"),
  movableEb: inKey("Eb", "do re mi fa so la ti do'"),
  fixedG: inKey("G", "do re mi fa sol so la si ti do5 sib3 fa#", "fixed"),
  written: (() => { const g = { ...M.newSong("western"), key: "D", solfa: "movable" };
    const p = M.parseNotation("do , re mi fa' so. ti~ me!3 la{0,4,7}", g);
    return ["movable", "fixed", undefined].map((v) => { const h = { ...g, solfa: v }; const w = M.writeNotation(p.notes, p.steps, h, 0);
      const plain = (ns) => JSON.stringify(ns.map(({ way, ...n }) => n));
      return [w, plain(M.parseNotation(w, h).notes) === plain(p.notes)]; }); })(),
  spelled: ["C", "G", "D", "A", "E", "B", "F#", "F", "Bb", "Eb", "Ab", "Db"].map((k) => inKey(k, "do re mi fa so la ti").join(" ")),
  oldKey: inKey("A#", "do re mi"),
  letters: inKey("C", "C4 B#3 Cb4 E#4 Ebb4 F##4"),
  errors: [["do4", undefined], ["me", "fixed"], ["xo", undefined]].map(([t, v]) => {
    try { M.parseNotation(t, { ...M.newSong("western"), solfa: v }); return null; } catch (e) { return e.message; } }),
};

// letters with octave marks, as typed: the opening of Für Elise
const fe = { ...M.newSong("western"), key: "A", scale: "harmonic minor" };
out.elise = M.parseNotation("E' D'# E' D'# E' B D' C' | C E A B | E G# B C' | E. B.b Bb. A''", fe).notes
  .map((n) => M.noteName(n.semi, fe, n.way));
try { M.parseNotation("E'5", fe); out.markAndNumber = null; } catch (e) { out.markAndNumber = e.message; }

// drums: strokes, the automatic pattern written out, and played the same
const kd = M.newSong("carnatic");
const dp = M.parseDrums("thom ki tha ki | dhi - tha+ki ka!5 ; kick+hat , snare", kd);
out.drums = { steps: dp.steps, hits: dp.hits.map((x) => [x.at, x.kind, x.vol || null]) };
out.drumsAgain = M.parseDrums(M.writeDrums(dp.hits, dp.steps, kd, 4), kd).hits.map((x) => [x.at, x.kind, x.vol || null]);
out.drumsWritten = [M.writeDrums(M.autoHits(kd, 16), 16, kd, 8), M.writeDrums(M.autoHits(M.newSong("western"), 8), 8, M.newSong("western"), 8)];
try { M.parseDrums("boom", kd); out.drumBad = null; } catch (e) { out.drumBad = e.message; }
out.drumSame = [["carnatic", "mridangam"], ["carnatic", "kanjira"], ["western", "kit"], ["western", "chip"]].map(([sys, kit]) => {
  const base = { ...M.newSong(sys), drums: kit, drone: false, cycles: 4, parts: [] };
  const steps = M.songSteps(base), a = M.render(base)[0];
  const own = { ...base, drumPattern: "own", parts: [{ name: "d", instrument: "drums", octave: 0, gain: 0.9, pan: 0.15,
    text: M.writeDrums(M.autoHits(base, steps), steps, base, 0) }] };
  const b = M.render(own)[0];
  return a.length === b.length && a.every((v, i) => v === b[i]);
});
const silent = M.render({ ...M.newSong("carnatic"), drums: "mridangam", drumPattern: "own", drone: false,
  parts: [{ name: "x", instrument: "veena", octave: 0, gain: 0.9, pan: 0, text: "-" }] })[0];
out.ownSilent = silent.every((v) => v === 0);
const broken = M.render({ ...M.newSong("carnatic"), parts: [...M.newSong("carnatic").parts, { name: "x", instrument: "drums",
  octave: 0, gain: 0.9, pan: 0, text: "S r g" }] });
out.brokenPlays = broken[0].length > 0 && broken[0].some((v) => v !== 0);

// reading WAV files back, exactly
const back = decodeWAV(encodeWAV([new Float32Array([0, 0.5, -0.5, 0.25]), new Float32Array([1, -1, 0, 0])], 12345, 2));
out.decoded = { rate: back.rate, loop: back.loop, ch: back.channels.map((c) => [...c].map((v) => Math.round(v * 32768))) };
const real = decodeWAV(readFileSync(village.replace(/manickam\/[^/]*$/, "catch/sfx/0-catch.wav")));
out.real = { rate: real.rate, channels: real.channels.length, frames: real.channels[0].length,
  first: [...real.channels[0].subarray(0, 50)].map((v) => Math.round(v * 32768)) };
try { decodeWAV(new Uint8Array(20)); out.notWav = false; } catch (e) { out.notWav = true; }

// volume and the loop point
const vs = M.parseNotation("C!3 , E{0,4}!9 G~!1 A", chip);
out.vol = vs.notes.map((n) => n.vol || null);
out.volAgain = M.parseNotation(M.writeNotation(vs.notes, vs.steps, chip, 0), chip).notes.map((n) => n.vol || null);
try { M.parseNotation("C!0", chip); out.volBad = false; } catch (e) { out.volBad = true; }
const loud = (text) => { const [L] = M.render({ ...chip, drums: "none", parts: [{ ...chip.parts[0], gain: 0.5, text }] });
  return [...L].reduce((m, v) => Math.max(m, Math.abs(v)), 0); };
const two = { ...chip, drums: "none", cycles: 1, parts: [{ name: "a", instrument: "square", octave: 0, gain: 0.5, pan: 0, text: "C ; ; ; , - - - - - - - -" },
  { name: "b", instrument: "square", octave: 0, gain: 0.5, pan: 0, text: "- - - - - - - - E!3 ; ; ; ," }] };
const [tw] = M.render(two), half = tw.length / 2;
const peak = (a, b) => { let m = 0; for (let i = a; i < b; i++) m = Math.max(m, Math.abs(tw[i])); return m; };
out.volRatio = peak(half + 100, tw.length - 100) / peak(100, half - 100);
const intro = { ...chip, cycles: 4, loopCycle: 2 };
out.loop = { frame: M.loopFrame(intro), want: Math.round(2 * M.cycleOf(intro).beats * intro.steps * 60 / intro.tempo / intro.steps * intro.rate), none: M.loopFrame(chip),
  past: M.loopFrame({ ...chip, loopCycle: 99 }) };
out.loopWav = b64(encodeWAV([M.render(intro)[0]], intro.rate, M.loopFrame(intro)));

// files
const px = new Uint8Array(24 * 16 * 4);
for (let i = 0; i < 24 * 16; i++) px.set(i % 5 ? [i & 255, (i * 7) & 255, (i * 13) & 255, 255] : [0, 0, 0, 0], i * 4);
out.png = b64(await encodePNG(24, 16, px));
out.pngPixels = b64(px);
const wav = [new Float32Array([0, 0.5, -0.5, 1, -1, 2]), new Float32Array([0.25, 0, 0, 0, 0, -2])];
out.wav = b64(encodeWAV(wav, 22050));
const map = parseTMX(readFileSync(village, "utf8"));
out.mapSame = writeTMX(map);
map.layers[0].cells[0] = 5 | 0x8000;
map.layers[map.layers.length - 1].cells[map.width + 1] = 7 | 0x4000;
out.mapChanged = writeTMX(map);
out.mapSize = [map.width, map.height, map.layers.length];
const fresh = newTMX(10, 6, 2);
fresh.layers[1].cells[3] = 2;
out.fresh = writeTMX(fresh);
out.freshTSX = newTSX(64, 32);
const tsxText = readFileSync(village.replace(/[^/]*$/, "sprites.tsx"), "utf8");
out.tsxFlags = Object.fromEntries(parseTSX(tsxText).flags);
let flagged = setTileFlags(tsxText, 43, 5);            // has flags: changed
flagged = setTileFlags(flagged, 10, 3);                // has none: added in order
flagged = setTileFlags(flagged, 2000, 128);            // past the last: added at the end
flagged = setTileFlags(flagged, 44, 0);                // cleared
out.tsxChanged = flagged;
out.tsxSame = setTileFlags(tsxText, 43, parseTSX(tsxText).flags.get(43)) === tsxText && setTileFlags(tsxText, 999, 0) === tsxText;
const solid = '<tileset columns="4"><tile id="2"><properties><property name="solid" type="bool" value="true"/></properties></tile></tileset>';
out.solid = [Object.fromEntries(parseTSX(solid).flags), Object.fromEntries(parseTSX(setTileFlags(solid, 2, 6)).flags)];
// Oli
const o1 = O.render(O.preset("coin", 3)), o2 = O.render(O.preset("coin", 3));
out.oli = { same: o1.every((v, i) => v === o2[i]), len: o1.length, want: Math.floor((O.preset("coin", 3).attack +
  O.preset("coin", 3).sustain + O.preset("coin", 3).decay) * O.RATE), varies: O.render(O.preset("coin", 4)).length !== o1.length ||
  O.render(O.preset("coin", 4)).some((v, i) => v !== o1[i]) };
out.oliBad = [];
for (const name of Object.keys(O.PRESETS)) for (const seed of [1, 2, 3]) {
  const s = O.preset(name, seed);
  for (const wave of O.WAVES) for (const m of [s, O.mutate(s, seed + 9)]) {
    const v = O.render({ ...m, wave });
    if (!v.every((x) => Number.isFinite(x) && Math.abs(x) <= 1) || !v.some((x) => x !== 0)) out.oliBad.push(`${name} ${seed} ${wave}`);
  }
}
out.oliInRange = Object.keys(O.PRESETS).every((n) => O.KNOBS.every(([k, min, max]) => {
  const v = O.mutate(O.preset(n, 5), 6)[k]; return v >= min - 1e-9 && v <= max + 1e-9; }));
out.oliWav = b64(encodeWAV([O.render(O.preset("jump", 1))], O.RATE));

// backdrops: pictures put in the 64 colours
const px64 = new Uint8Array(64 * 4);
BUILTIN.forEach((c, i) => px64.set([c >> 16, (c >> 8) & 255, c & 255, i ? 255 : 0], i * 4));
out.exact = [...quantiseTo(px64, 64, 1, BUILTIN).pixels];
const a = BUILTIN[1], b = BUILTIN[12];
const mid = new Uint8Array(16 * 16 * 4);
for (let i = 0; i < 256; i++) mid.set([((a >> 16) + (b >> 16)) >> 1, (((a >> 8) & 255) + ((b >> 8) & 255)) >> 1, ((a & 255) + (b & 255)) >> 1, 255], i * 4);
out.plain = [...new Set(quantiseTo(mid, 16, 16, BUILTIN).pixels)];
out.dithered = [...new Set(quantiseTo(mid, 16, 16, BUILTIN, true).pixels)].sort((x, y) => x - y);
out.exactDithered = [...quantiseTo(px64, 64, 1, BUILTIN, true).pixels];
out.backdropCall = callAt('backdrop("bg_easy.kolam")', 3);

// Vidhi
out.api = API;
out.sigs = SIGS;
const src = "local function make_enemy(x) end\nlocal speed = 2\nma";
out.complete = [complete("ma", src), complete("sp", src), complete("m", src), complete("map.d", src)];
out.word = [wordBefore("x = map.lo", 10), wordBefore("x = ", 4)];
out.hints = [callHint("spr(12, x, ", 11), callHint("print(f(a, b), ", 15), callHint("foo(1, ", 7), callHint("x = 1", 5),
  callHint("map.set(0, 1, 2, ", 17)].map((c) => c && [c.name, c.arg]);
out.calls = ["  spr(12, x, y)", "sfx(3) music(1, 500)", 'map.load("hall.ooru")', 'preload("sfx 7", "music 2")',
  "print(spr)", 'sheet.load("actors.kolam")'].map((l) => callAt(l, 2));
out.callFar = callAt("sfx(3) music(1, 500)", 9);
out.lit = highlight('local s = "a" -- c\nspr(1) x = 0x1f\n');
out.numbered = numbered(["sfx/b.wav", "sfx/a.WAV", "sfx/n.json", "sfx/x/y.wav", "music/z.wav", "sfx/10.wav"], "sfx");
console.log(JSON.stringify(out));
