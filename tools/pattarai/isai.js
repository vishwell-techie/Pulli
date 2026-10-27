// Isai: the music editor. A song is written in parts, one line of notation
// each, in a western scale or a Carnatic raga (lib/music.js), and played by
// a synthesised band. It is kept as music/<name>.json and made into
// music/<name>.wav, which `pulli pack` puts in music.isai; music(n) plays
// the WAV files in order of name.
import { api, h, shared, status, refreshFiles, CHANNEL_NOTE } from "./app.js";
import * as M from "./lib/music.js";
import { encodeWAV } from "./lib/wav.js";

const SRUTI = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];

export function isai(root) {
  let song = M.newSong("carnatic"), path = "", dirty = false, partIndex = 0;
  let audio = null, source = null, playStart = 0, playLen = 0, raf = 0;

  const files = h("select", { title: "Songs in the game's music folder" });
  const head = h("div", { className: "bar" });
  const scaleBox = h("div", { className: "box" });
  const partsBox = h("div");
  const roll = h("canvas", { style: "cursor:crosshair" });
  const playBtn = h("button", { className: "", onclick: togglePlay }, "▶ Play");

  root.append(
    h("div", { className: "bar" }, files,
      h("button", { onclick: open }, "Open"),
      h("button", { onclick: () => create("carnatic") }, "New Carnatic"),
      h("button", { onclick: () => create("western") }, "New western"),
      h("button", { title: "Pulse lead, triangle bass, noise drums, small mono WAV", onclick: () => create("carnatic", true) }, "New chiptune"),
      h("button", { onclick: save }, "Save"),
      h("button", { title: "Write music/<name>.wav, the file the game plays", onclick: exportWav }, "Make WAV"),
      h("span", { className: "sep" }), playBtn),
    head,
    h("div", { className: "cols" },
      h("div", { className: "wide" }, partsBox,
        h("button", { onclick: addPart }, "+ Part"),
        h("p", { className: "muted", style: "font-size:12px;max-width:720px" },
          "The parts are mixed into one track; the game plays it with music(n), " + CHANNEL_NOTE.slice(CHANNEL_NOTE.indexOf("Music is") ).replace("Music is", "one track at a time, mixed") )),
      h("div", { className: "box", style: "max-width:100%" }, h("h3", {}, "Roll: the part in hand"),
        h("p", { className: "muted", style: "margin:0 0 6px" },
          "Click to place a note (drag right to hold it), click a note to remove it."),
        h("div", { className: "scroll", style: "max-height:420px" }, roll)),
      scaleBox));

  // ---- the song's settings ----------------------------------------------------
  function field(label, input) { return h("label", {}, label, input); }
  function changed() {
    const was = dirty;
    dirty = true;
    stop();
    if (!was) drawHead();
  }

  function drawHead() {
    const c = song.system === "carnatic";
    const scales = Object.entries(M.SCALES).filter(([, s]) => s.system === song.system);
    const scaleSel = h("select", { onchange: (e) => { song.scale = e.target.value; changed(); drawAll(); } },
      ...(c ? [h("optgroup", { label: "Janya ragas" }, ...scales.filter(([, s]) => !s.mela).map(([n]) => h("option", { value: n }, n))),
               h("optgroup", { label: "Melakartas" }, ...scales.filter(([, s]) => s.mela).map(([n, s]) => h("option", { value: n }, `${s.mela}. ${n}`)))]
            : scales.map(([n]) => h("option", { value: n }, n))));
    scaleSel.value = song.scale;
    const talaSel = h("select", { onchange: (e) => { song.tala = e.target.value; changed(); drawAll(); } },
      ...Object.keys(M.TALAS[song.system]).map((n) => h("option", { value: n }, n)));
    talaSel.value = song.tala;
    const num = (key, min, max, stepBy = 1) => h("input", { type: "number", min, max, step: stepBy, value: song[key],
      onchange: (e) => { const v = +e.target.value; if (v >= min && v <= max) { song[key] = v; changed(); drawAll(); } } });
    const tonic = c
      ? field("Sa", h("select", { onchange: (e) => { song.sa = +e.target.value; changed(); drawScale(); } },
          ...[2, 3].flatMap((o) => SRUTI.map((n, i) => {
            const hz = +(440 * 2 ** ((i - 9) / 12 + (o - 4))).toFixed(1);
            return h("option", { value: hz, selected: Math.abs(hz - song.sa) < 0.5 }, `${n}${o} (${hz} Hz)`);
          }))))
      : h("span", {}, field("key", h("select", { onchange: (e) => { song.key = e.target.value; changed(); drawAll(); } },
          ...M.KEYS.map((k) => h("option", { value: k, selected: k === song.key }, k)))), " ",
          field("octave", num("octave", 1, 6)));
    head.replaceChildren(
      h("strong", {}, path || "(new song)", dirty ? " •" : ""),
      h("span", { className: "sep" }),
      field(c ? "raga" : "scale", scaleSel), tonic,
      field(c ? "tala" : "time", talaSel),
      field("tempo", num("tempo", 30, 300)),
      field("steps a beat", num("steps", 1, 8)),
      field("cycles", num("cycles", 1, 64)),
      field("drone", h("input", { type: "checkbox", checked: song.drone, onchange: (e) => { song.drone = e.target.checked; changed(); } })),
      field("drums", h("select", { onchange: (e) => { song.drums = e.target.value; changed(); } },
        ...M.KITS.map((k) => h("option", { value: k, selected: k === song.drums }, k)))),
      field("swing", h("input", { type: "range", min: 0, max: 0.6, step: 0.05, value: song.swing,
        onchange: (e) => { song.swing = +e.target.value; changed(); } })),
      field("arpeggio speed", num("arpRate", 4, 60)),
      h("span", { className: "sep" }),
      field("WAV", h("select", { title: "Samples a second in the WAV made: fewer is smaller and rougher, as chiptune was",
        onchange: (e) => { song.rate = +e.target.value; changed(); drawHead(); } },
        ...M.RATES.map((r) => h("option", { value: r, selected: r === song.rate }, `${r} Hz`)))),
      field("mono", h("input", { type: "checkbox", checked: song.mono, title: "One channel: half the size",
        onchange: (e) => { song.mono = e.target.checked; changed(); drawHead(); } })),
      h("span", { className: "muted", title: "The size of the WAV made, before pack squeezes music to a quarter" }, size()));
  }

  // pack squeezes music to 4 bits a sample (SPEC §2)
  function size() {
    const sec = M.songSteps(song) * 60 / song.tempo / song.steps;
    const samples = sec * song.rate * (song.mono ? 1 : 2);
    return `${song.mono ? "1 channel" : "2 channels"}: ${(samples * 2 / 1024).toFixed(0)} KB WAV, ` +
      `${(samples / 2 / 1024).toFixed(0)} KB packed`;
  }

  // The scale, up and down, with a key for each note to hear it.
  function drawScale() {
    const s = M.SCALES[song.scale];
    const name = (semi) => M.noteName(semi, song);
    const keys = (list) => h("div", { className: "keys" }, ...list.map((semi) =>
      h("button", { title: `${M.freqOf(semi, song).toFixed(1)} Hz`, onclick: () => audition(semi) }, name(semi))));
    scaleBox.replaceChildren(
      h("h3", {}, song.scale, s.mela ? ` · melakarta ${s.mela}` : s.parent ? ` · from ${Object.keys(M.SCALES).find((n) => M.SCALES[n].mela === s.parent)}` : ""),
      h("p", { className: "muted", style: "margin:0 0 4px" }, song.system === "carnatic" ? "Arohanam" : "Up"), keys(s.up),
      h("p", { className: "muted", style: "margin:8px 0 4px" }, song.system === "carnatic" ? "Avarohanam" : "Down"), keys(s.down),
      h("p", { className: "muted", style: "margin:10px 0 0;max-width:330px;font-size:12px" },
        song.system === "carnatic"
          ? "Write S R G M P D N (the raga's own), R1 G3 M2… for others; ' an octave up, . down; , holds; ; holds two; - rests; ~ shakes (kampita), / slides up into a note, \\ down; {0,4,7} after a note plays it as an arpeggio."
          : "Write C D# Bb… with an octave (C4) or without (the song's); , holds; ; holds two; - rests; | bar lines are skipped; ~ / \\ bend a note; {0,4,7} after a note plays it as an arpeggio."));
  }

  // ---- parts --------------------------------------------------------------------
  function drawParts() {
    partsBox.replaceChildren(...song.parts.map((p, i) => {
      const err = h("div", { className: "err" });
      const check = () => {
        try {
          const r = M.parseNotation(p.text, song);
          const per = M.cycleOf(song).beats * song.steps;
          err.className = "err muted";
          err.textContent = `${r.notes.length} notes, ${r.steps} steps (${(r.steps / per).toFixed(2).replace(/\.00$/, "")} cycles)`;
        } catch (e) { err.className = "err"; err.textContent = e.message; }
      };
      const text = h("textarea", { rows: 3, value: p.text, spellcheck: false,
        onfocus: () => { if (partIndex !== i) { partIndex = i; drawParts(); drawRoll(); } },
        oninput: (e) => { p.text = e.target.value; changed(); check(); drawRoll(); } });
      check();
      const inst = h("select", { onchange: (e) => { p.instrument = e.target.value; changed(); } },
        ...Object.entries(M.INSTRUMENTS).map(([group, list]) => h("optgroup", { label: group },
          ...list.map((n) => h("option", { value: n, selected: n === p.instrument }, n)))));
      const knob = (key, min, max, stepBy) => h("input", { type: "number", min, max, step: stepBy, value: p[key], style: "width:70px",
        onchange: (e) => { p[key] = +e.target.value; changed(); drawRoll(); } });
      return h("div", { className: "part" + (i === partIndex ? " on" : ""), onclick: () => { if (partIndex !== i) { partIndex = i; drawParts(); drawRoll(); } } },
        h("div", { className: "bar", style: "margin-bottom:6px" },
          h("input", { value: p.name, style: "width:110px", onchange: (e) => { p.name = e.target.value; changed(); } }),
          inst, field("octave", knob("octave", -3, 3, 1)), field("volume", knob("gain", 0, 1.5, 0.05)),
          field("pan", knob("pan", -1, 1, 0.1)),
          h("button", { title: "Hear this part alone", onclick: (e) => { e.stopPropagation(); play(i); } }, "▶"),
          h("button", { title: "Remove the part", onclick: (e) => {
            e.stopPropagation();
            if (song.parts.length > 1 && confirm(`Remove the part "${p.name}"?`)) {
              song.parts.splice(i, 1); partIndex = 0; changed(); drawParts(); drawRoll();
            } } }, "✕")),
        text, err);
    }));
  }
  function addPart() {
    song.parts.push({ name: "part " + (song.parts.length + 1), instrument: song.system === "carnatic" ? "veena" : "strings",
                      octave: 0, gain: 0.7, pan: -0.3, text: "" });
    partIndex = song.parts.length - 1;
    changed(); drawParts(); drawRoll();
  }

  // ---- the roll: steps across, the scale's notes up --------------------------
  const CW = 18, RH = 16, LABEL = 46;
  let rows = [], placing = null;
  function drawRoll() {
    const p = song.parts[partIndex];
    if (!p) return;
    const scale = M.SCALES[song.scale].notes;
    rows = [];
    for (let o = 1; o >= -1; o--) for (let k = scale.length - 1; k >= 0; k--) rows.push(scale[k] + 12 * o);
    rows.unshift(24);
    let parsed;
    try { parsed = M.parseNotation(p.text, song); } catch (e) { parsed = { notes: [], steps: 0 }; }
    for (const n of parsed.notes) if (!rows.includes(n.semi)) rows.push(n.semi);
    rows.sort((a, b) => b - a);
    const { beats, strong } = M.cycleOf(song);
    const per = beats * song.steps;
    const steps = Math.max(M.songSteps(song), parsed.steps + per);
    roll.width = LABEL + steps * CW; roll.height = rows.length * RH;
    const g = roll.getContext("2d");
    g.fillStyle = "#1b1c24"; g.fillRect(0, 0, roll.width, roll.height);
    g.font = "11px ui-monospace, monospace"; g.textBaseline = "middle";
    rows.forEach((semi, r) => {
      const tonic = ((semi % 12) + 12) % 12 === 0;
      g.fillStyle = tonic ? "#2b2a24" : r % 2 ? "#20222b" : "#1d1f27";
      g.fillRect(LABEL, r * RH, roll.width, RH);
      g.fillStyle = scale.includes(((semi % 12) + 12) % 12) ? "#c9c7c0" : "#e5604f";
      g.fillText(M.noteName(semi, song), 4, r * RH + RH / 2);
    });
    for (let s = 0; s <= steps; s++) {
      const beat = s % song.steps === 0, cyc = s % per === 0;
      const b = Math.floor((s % per) / song.steps);
      g.strokeStyle = cyc ? "#f0a33088" : beat && strong.includes(b) ? "#ffffff30" : beat ? "#ffffff18" : "#ffffff08";
      g.beginPath(); g.moveTo(LABEL + s * CW, 0); g.lineTo(LABEL + s * CW, roll.height); g.stroke();
    }
    for (const n of parsed.notes) {
      const r = rows.indexOf(n.semi);
      g.fillStyle = n.mark ? "#4fb3a9" : "#f0a330";
      g.fillRect(LABEL + n.at * CW + 1, r * RH + 2, n.len * CW - 2, RH - 4);
    }
    if (source) {
      const x = LABEL + ((audio.currentTime - playStart) % playLen) / playLen * M.songSteps(song) * CW;
      g.fillStyle = "#fff"; g.fillRect(x, 0, 2, roll.height);
    }
  }
  roll.addEventListener("mousedown", (e) => {
    const p = song.parts[partIndex];
    if (!p || e.offsetX < LABEL) return;
    let parsed;
    try { parsed = M.parseNotation(p.text, song); } catch (err) { return status("Mend the part's notation first: " + err.message, true); }
    const s = Math.floor((e.offsetX - LABEL) / CW), semi = rows[Math.floor(e.offsetY / RH)];
    const hitNote = parsed.notes.find((n) => s >= n.at && s < n.at + n.len && n.semi === semi);
    if (hitNote) parsed.notes.splice(parsed.notes.indexOf(hitNote), 1);
    else {
      parsed.notes = parsed.notes.filter((n) => !(s >= n.at && s < n.at + n.len));
      placing = { at: s, len: 1, semi, mark: "" };
      parsed.notes.push(placing);
      audition(semi + 12 * p.octave, p.instrument);
    }
    placing = placing && { note: placing, parsed };
    writeBack(parsed);
  });
  roll.addEventListener("mousemove", (e) => {
    if (!placing) return;
    const s = Math.floor((e.offsetX - LABEL) / CW);
    const len = Math.max(1, s - placing.note.at + 1);
    if (len === placing.note.len) return;
    placing.note.len = len;
    placing.parsed.notes = placing.parsed.notes.filter((n) => n === placing.note || n.at < placing.note.at || n.at >= placing.note.at + len);
    writeBack(placing.parsed);
  });
  addEventListener("mouseup", () => { placing = null; });
  function writeBack(parsed) {
    const p = song.parts[partIndex];
    const { beats } = M.cycleOf(song);
    const end = Math.max(...parsed.notes.map((n) => n.at + n.len), 0);
    p.text = M.writeNotation(parsed.notes, end, song, beats * song.steps);
    changed(); drawParts(); drawRoll();
  }

  // ---- sound ----------------------------------------------------------------------
  function ctx() {
    audio = audio || new AudioContext({ sampleRate: M.RATE });   // plays a song at any rate
    return audio;
  }
  function renderAsync(s) {
    return new Promise((resolve, reject) => {
      const w = new Worker(new URL("./render-worker.js", import.meta.url), { type: "module" });
      w.onmessage = (e) => { w.terminate(); e.data.error ? reject(new Error(e.data.error)) : resolve(e.data.channels); };
      w.onerror = (e) => { w.terminate(); reject(new Error(e.message)); };
      w.postMessage(s);
    });
  }
  // One note, rendered here (it is short), to hear a key of the scale or a
  // note placed on the roll.
  function audition(semi, instrument) {
    const one = { ...song, drone: false, drums: "none", cycles: 1, swing: 0, tempo: 100 / song.steps,
      parts: [{ name: "x", instrument: instrument || song.parts[partIndex]?.instrument || "veena", octave: 0, gain: 1,
                pan: 0, text: M.writeNotation([{ at: 0, len: 1, semi, mark: "" }], 1, song, 0) }] };
    const [L, R] = M.render(one);
    const rate = song.rate || M.RATE;
    const n = Math.min(L.length, Math.floor(0.9 * rate));
    const a = ctx(), b = a.createBuffer(2, n, rate);
    b.copyToChannel(L.subarray(0, n), 0); b.copyToChannel(R.subarray(0, n), 1);
    const src = a.createBufferSource(); src.buffer = b; src.connect(a.destination); src.start();
  }
  async function play(only = null) {
    stop();
    const s = only === null ? song : { ...song, parts: [song.parts[only]], drone: false, drums: "none" };
    try {
      status("Playing… (rendering)");
      const [L, R] = mix(await renderAsync(JSON.parse(JSON.stringify(s))));
      const a = ctx();
      await a.resume();
      const rate = song.rate || M.RATE;
      const b = a.createBuffer(2, L.length, rate);
      b.copyToChannel(L, 0); b.copyToChannel(R, 1);
      source = a.createBufferSource();
      source.buffer = b; source.loop = true; source.connect(a.destination);
      playStart = a.currentTime; playLen = L.length / rate;
      source.start();
      playBtn.textContent = "■ Stop"; playBtn.classList.add("on");
      status(`Playing ${path || "the new song"}: ${playLen.toFixed(1)} s, looping.`);
      const tick = () => { drawRoll(); raf = requestAnimationFrame(tick); };
      tick();
    } catch (e) { status(e.message, true); }
  }
  // a mono song is heard as it will be: both sides the same
  function mix([L, R]) {
    if (!song.mono) return [L, R];
    const m = new Float32Array(L.length);
    for (let i = 0; i < m.length; i++) m[i] = (L[i] + R[i]) / 2;
    return [m, m];
  }
  function stop() {
    if (source) { source.stop(); source = null; }
    cancelAnimationFrame(raf);
    playBtn.textContent = "▶ Play"; playBtn.classList.remove("on");
  }
  function togglePlay() { source ? stop() : play(); }

  // ---- files -------------------------------------------------------------------
  const wavOf = (p) => p.replace(/\.json$/, ".wav");
  async function open() {
    if (!files.value) return;
    if (dirty && !confirm(`${path || "The new song"} has changes that are not saved. Open another anyway?`)) return;
    try {
      const s = JSON.parse(await api.readText(files.value));
      if (s.format !== "isai-song") throw new Error("not an Isai song");
      song = { ...M.newSong(s.system), ...s };
      path = files.value; dirty = false; partIndex = 0;
      stop(); drawAll();
      status(`Opened ${path}.`);
    } catch (e) { status(`${files.value}: ${e.message}`, true); }
  }
  function create(system, chip = false) {
    if (dirty && !confirm("The song in hand has changes that are not saved. Start a new one anyway?")) return;
    song = chip ? M.newChipSong(system) : M.newSong(system); path = ""; dirty = true; partIndex = 0;
    stop(); drawAll();
  }
  async function ensurePath() {
    if (path) return true;
    const name = prompt("Name for the song (its files are music/<name>.json and music/<name>.wav; music(n) plays the WAVs in order of name)", "00-title");
    if (!name) return false;
    if (!/^[\w-]+$/.test(name)) { status("Use letters, digits, - and _ in the name.", true); return false; }
    path = `music/${name}.json`;
    if (shared.files.includes(path) && !confirm(`${path} exists. Replace it?`)) { path = ""; return false; }
    return true;
  }
  async function save() {
    if (!(await ensurePath())) return;
    try {
      await api.write(path, JSON.stringify(song, null, 1) + "\n");
      dirty = false;
      await refreshFiles();
      files.value = path;
      drawHead();
      status(`Saved ${path}.`);
    } catch (e) { status("Not saved: " + e.message, true); }
  }
  async function exportWav() {
    if (!(await ensurePath())) return;
    try {
      status("Making the WAV…");
      const ch = mix(await renderAsync(JSON.parse(JSON.stringify(song))));
      const wav = encodeWAV(song.mono ? [ch[0]] : ch, song.rate || M.RATE);
      await api.write(wavOf(path), wav);
      await save();
      status(`Made ${wavOf(path)} (${(ch[0].length / (song.rate || M.RATE)).toFixed(1)} s, ${Math.round(wav.length / 1024)} KB) and saved ${path}.`);
    } catch (e) { status("No WAV made: " + e.message, true); }
  }

  function drawAll() { drawHead(); drawScale(); drawParts(); drawRoll(); }
  shared.listeners.push((what) => {
    if (what !== "files") return;
    const was = files.value;
    files.replaceChildren(...shared.files.filter((f) => /^music\/[^/]+\.json$/.test(f)).map((f) => h("option", { value: f }, f)));
    if (was) files.value = was;
  });
  shared.dirtyChecks.push(() => dirty);
  drawAll();
}
