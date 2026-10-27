// Run by tests/test_pattarai.py: exercises Pattarai's libraries in node and
// prints what they make, as JSON, for the Python side to check against
// pulli.py (the reader of everything the editors write).
import * as M from "../tools/pattarai/lib/music.js";
import { parseTMX, writeTMX, newTMX, newTSX } from "../tools/pattarai/lib/tmx.js";
import { encodePNG } from "../tools/pattarai/lib/png.js";
import { encodeWAV } from "../tools/pattarai/lib/wav.js";
import { readFileSync } from "fs";
import * as O from "../tools/pattarai/lib/sfx.js";
import { API, highlight, callAt, numbered } from "../tools/pattarai/lib/lua.js";

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
const c = { ...M.newSong("carnatic"), scale: "Mayamalavagowla" };
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
  for (const inst of [...M.INSTRUMENTS.carnatic, ...M.INSTRUMENTS.western])
    for (const kit of M.KITS) {
      const [L] = M.render({ ...s, cycles: 1, parts: [{ ...s.parts[0], instrument: inst }], drums: kit });
      if (!L.every(Number.isFinite)) out.badRender = `${sys} ${inst} ${kit}`;
    }
}

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

// Vidhi
out.api = API;
out.calls = ["  spr(12, x, y)", "sfx(3) music(1, 500)", 'map.load("hall.ooru")', 'preload("sfx 7", "music 2")',
  "print(spr)", 'sheet.load("actors.kolam")'].map((l) => callAt(l, 2));
out.callFar = callAt("sfx(3) music(1, 500)", 9);
out.lit = highlight('local s = "a" -- c\nspr(1) x = 0x1f\n');
out.numbered = numbered(["sfx/b.wav", "sfx/a.WAV", "sfx/n.json", "sfx/x/y.wav", "music/z.wav", "sfx/10.wav"], "sfx");
console.log(JSON.stringify(out));
