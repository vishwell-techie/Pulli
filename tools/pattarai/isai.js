// Isai: the music editor. A song is written in parts, one line of notation
// each, in a western scale or a Carnatic raga (lib/music.js), and played by
// a synthesised band. It is kept as music/<name>.json and made into
// music/<name>.wav, which `pulli pack` puts in music.isai; music(n) plays
// the WAV files in order of name.
import { api, h, shared, status, refreshFiles, CHANNEL_NOTE, help } from "./app.js";
import * as M from "./lib/music.js";
import { wavOf as wavBytes, madeNote, refreshNote, needsWav } from "./lib/make.js";

const SRUTI = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];

export function isai(root) {
  let song = M.newSong("carnatic"), path = "", dirty = false, partIndex = 0;
  let audio = null, source = null, playStart = 0, playLen = 0, raf = 0;

  const files = h("select", { title: "Songs in the game's music folder", "data-empty": "no songs yet: New… or an example" });
  const examples = h("select", { title: "Example songs that come with Pattarai" }, h("option", { value: "" }, "Example songs…"));
  fetch(new URL("./songs/index.json", import.meta.url)).then((r) => r.json()).then((list) => {
    examples.append(...list.map((x) => h("option", { value: x.file, title: x.about }, x.title)));
  }).catch(() => {});
  const head = h("div");
  const scaleBox = h("div", { className: "box" });
  const partsBox = h("div");
  const roll = h("canvas", { style: "cursor:crosshair" });
  const rollName = h("span", { style: "text-transform:none;color:var(--accent)" });
  const rollTitle = h("h3", { style: "margin:0;display:flex;gap:8px" }, h("span", {}, "Roll"), rollName);
  const playBtn = h("button", { className: "", onclick: togglePlay }, "▶ Play");

  root.append(
    h("div", { className: "bar" }, files,
      h("button", { onclick: open }, "Open"),
      h("button", { onclick: () => create("carnatic") }, "New Carnatic"),
      h("button", { onclick: () => create("western") }, "New western"),
      h("button", { title: "Pulse lead, triangle bass, noise drums, small mono WAV", onclick: () => create("carnatic", true) }, "New chiptune"),
      h("span", { className: "sep" }), examples,
      h("button", { title: "Open an example song as a new, unsaved song", onclick: openExample }, "Open example"),
      h("button", { onclick: save }, "Save"),
      h("button", { title: "Write music/<name>.wav, the file the game plays", onclick: exportWav }, "Make WAV"),
      h("button", { title: "Make the WAV of every song in music/ that has none, or has changed since, or was made by an older Isai",
        onclick: makeAll }, "Make all WAVs"),
      h("span", { className: "sep" }), playBtn),
    head,
    h("div", { className: "box", style: "max-width:100%;margin-bottom:10px" },
      h("div", { className: "bar", style: "margin-bottom:6px" }, rollTitle,
        help("Click to place a note (drag right to hold it), click a note to remove it. On a drum part, click a lane to add or remove a stroke.")),
      h("div", { className: "scroll", style: "max-height:300px" }, roll)),
    h("div", { className: "cols" },
      h("div", { className: "wide" }, partsBox,
        h("div", { className: "bar" }, h("button", { onclick: addPart }, "+ Part"),
          h("button", { title: "A drum part of your own, starting from the automatic pattern written out", onclick: addDrumPart }, "+ Drum part"),
          help("The parts are mixed into one track, which the game plays with music(n). ", CHANNEL_NOTE))),
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
    const scaleSel = h("select", { onchange: (e) => setScale(e.target.value) },
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
          ...M.KEYS.map((k) => h("option", { value: k, selected: k === M.KEYS[M.keyIndex(song.key)] }, k.replace("b", "♭"))))), " ",
          field("octave", num("octave", 1, 6)), " ",
          field("note names", h("select", { title: "How notes are written back and labelled. Letters and solfège can both be typed in any song.",
            onchange: (e) => setNoteNames(e.target.value) },
            ...Object.entries(M.NOTE_NAMES).map(([v, label]) => h("option", { value: v, selected: v === (song.solfa || "letters") }, label)))));
    // a slider with its value beside it
    const slider = (key, max, title) => {
      const val = h("span", { className: "rangeval" }, (song[key] || 0).toFixed(2));
      return h("span", { style: "display:inline-flex;gap:6px;align-items:center" },
        h("input", { type: "range", min: 0, max, step: 0.05, value: song[key] || 0, title,
          oninput: (e) => { val.textContent = (+e.target.value).toFixed(2); },
          onchange: (e) => { song[key] = +e.target.value; changed(); } }), val);
    };
    // the arpeggio's speed matters only to a song that has one
    const arps = hasArps();
    const group = (title, ...kids) => h("div", { className: "group" }, h("b", {}, title), ...kids.filter((k) => k !== ""));
    head.replaceChildren(
      h("div", { className: "songhead" },
        h("strong", {}, path || "(new song)", dirty ? " •" : ""),
        path ? h("span", { className: song.made && song.made.current && song.made.engine === M.ENGINE ? "muted" : "warn",
          title: "The WAV the game plays" },
          !song.made ? "no WAV made here yet" : song.made.engine !== M.ENGINE ? `WAV from engine ${song.made.engine}`
            : song.made.current && !dirty ? "WAV up to date" : "WAV out of date: Make WAV") : ""),
      h("div", { className: "groups" },
        group(c ? "Raga and tala" : "Scale and time",
          field(c ? "raga" : "scale", scaleSel), tonic,
          field(c ? "tala" : "time", talaSel),
          field("tempo", num("tempo", 30, 300))),
        group("Rhythm",
          field("steps a beat", num("steps", 1, 8)),
          field("cycles", num("cycles", 1, 64)),
          c ? field("capitals long", h("input", { type: "checkbox", checked: !!song.longCaps,
            title: "As lines are written by hand: a capital is two aksharas, a small letter one. The parts are rewritten so they sound the same.",
            onchange: (e) => setLongCaps(e.target.checked) })) : "",
          field("drums", h("select", { onchange: (e) => { song.drums = e.target.value; changed(); } },
            ...M.KITS.map((k) => h("option", { value: k, selected: k === song.drums }, k)))),
          field("drum pattern", h("select", { title: "Automatic: the kit plays the tala's (or time's) pattern. My own: only the drum parts you write play.",
            onchange: (e) => { song.drumPattern = e.target.value; changed(); } },
            h("option", { value: "auto", selected: song.drumPattern !== "own" }, "automatic"),
            h("option", { value: "own", selected: song.drumPattern === "own" }, "my own"))),
          field("swing", slider("swing", 0.6, "Every other step a little late"))),
        group("Sound",
          field("drone", h("input", { type: "checkbox", checked: song.drone, title: "A tanpura under the band",
            onchange: (e) => { song.drone = e.target.checked; changed(); } })),
          field("reverb", slider("reverb", 1, "A hall around the band: 0 is none")),
          arps ? field("arpeggio speed", num("arpRate", 4, 60)) : ""),
        group("The WAV made",
          field("WAV", h("select", { title: "Samples a second in the WAV made: fewer is smaller and rougher, as chiptune was",
            onchange: (e) => { song.rate = +e.target.value; changed(); drawHead(); } },
            ...M.RATES.map((r) => h("option", { value: r, selected: r === song.rate }, `${r} Hz`)))),
          field("mono", h("input", { type: "checkbox", checked: song.mono, title: "One channel: half the size",
            onchange: (e) => { song.mono = e.target.checked; changed(); drawHead(); } })),
          field("loops from cycle", h("input", { type: "number", min: 0, max: 63, value: song.loopCycle || 0, style: "width:60px",
            title: "0: the whole song loops. 2: cycles 0 and 1 are an intro, played once, then it loops from cycle 2",
            onchange: (e) => { song.loopCycle = Math.max(0, +e.target.value | 0); changed(); drawRoll(); } })),
          h("span", { className: "muted", style: "font-size:12px", title: "The size of the WAV made, before pack squeezes music to a quarter" }, size()))));
  }

  // A new raga or scale: the parts keep their letters, which now name the
  // new scale's notes. A part with a letter the new scale has not (M in
  // Mohanam) would not play, so its notes are moved to the nearest note of
  // the new scale, and the status says which parts.
  function setScale(name) {
    const before = song.parts.map((p) => { try { return p.instrument === "drums" ? null : M.parseNotation(p.text, song); } catch (e) { return null; } });
    song.scale = name;
    const { beats } = M.cycleOf(song);
    const notes = M.SCALES[name].notes, moved = [];
    song.parts.forEach((p, i) => {
      if (!before[i]) return;
      try { M.parseNotation(p.text, song); return; } catch (e) { /* a letter the new scale lacks */ }
      let count = 0;
      const near = (semi) => {
        const pc = ((semi % 12) + 12) % 12;
        if (notes.includes(pc)) return semi;
        count++;
        const best = [...notes, 12].reduce((a, b) => (Math.abs(b - pc) < Math.abs(a - pc) ? b : a));
        return semi - pc + best;
      };
      const ns = before[i].notes.map((n) => ({ ...n, semi: near(n.semi), way: undefined }));
      p.text = M.writeNotation(ns, before[i].steps, song, beats * song.steps);
      moved.push(`${p.name} (${count} note${count === 1 ? "" : "s"})`);
    });
    changed(); drawAll();
    status(moved.length ? `${name}: notes not in it were moved to its nearest notes in ${moved.join(", ")}.` : `${name}.`);
  }

  const hasArps = () => song.parts.some((p) => p.instrument !== "drums" && /\{/.test(p.text));

  // pack squeezes music to 4 bits a sample (SPEC §2)
  function size() {
    const sec = M.songSteps(song) * 60 / song.tempo / song.steps;
    const samples = sec * song.rate * (song.mono ? 1 : 2);
    return `${song.mono ? "1 channel" : "2 channels"}: ${(samples * 2 / 1024).toFixed(0)} KB WAV, ` +
      `${(samples / 2 / 1024).toFixed(0)} KB packed`;
  }

  // Switching how capitals are read keeps the music: each part is read the
  // old way and written out the new way.
  function setLongCaps(on) {
    const { beats } = M.cycleOf(song);
    const parsed = song.parts.map((p) => { try { return M.parseNotation(p.text, song); } catch (e) { return null; } });
    song.longCaps = on;
    song.parts.forEach((p, i) => { if (parsed[i]) p.text = M.writeNotation(parsed[i].notes, parsed[i].steps, song, beats * song.steps); });
    changed(); drawAll();
    status(on ? "Capitals are two aksharas, small letters one; the parts were rewritten to sound the same."
              : "Every letter is one step; the parts were rewritten to sound the same.");
  }

  // Letters, movable do or fixed do: the parts are read the old way and
  // written the new way, so they sound the same.
  function setNoteNames(v) {
    const { beats } = M.cycleOf(song);
    const parsed = song.parts.map((p) => { try { return M.parseNotation(p.text, song); } catch (e) { return null; } });
    song.solfa = v === "letters" ? undefined : v;
    song.parts.forEach((p, i) => { if (parsed[i]) p.text = M.writeNotation(parsed[i].notes, parsed[i].steps, song, beats * song.steps); });
    changed(); drawAll();
    status(`Notes are now written as ${M.NOTE_NAMES[v]}; the parts were rewritten to sound the same.`);
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
      h("div", { style: "margin-top:10px" }, h("span", { className: "muted", style: "font-size:12px;margin-right:6px" }, "How to write notes"), help(
        ...(song.system === "carnatic"
          ? [song.longCaps ? "Capitals are two aksharas, small letters one: S , r G P D Ṡ N D |. " : "",
            "Write S R G M P D N (the raga's own), R1 G3 M2… for others; ' or a dot above (Ṡ) an octave up, . or a dot below (Ṇ) down; , holds; ; holds two; - rests; ~ shakes (kampita), / slides up into a note, \\ down; {0,4,7} after a note plays it as an arpeggio; !1 to !9 at the end sets its volume."]
          : [...(song.solfa === "fixed"
              ? ["Write fixed do: do re mi fa sol la si, with # or b and an octave (sol4) or without; or letters C D# Bb…; "]
              : ["Write letters C D# Bb… with an octave (C4) or without (the song's), or movable do: do re mi fa so la ti, do being the key note; ",
                "di ri fi si li raise a step, ra me se le te lower one, ' and . for octaves (do' so.); "]),
            ", holds; ; holds two; - rests; | bar lines are skipped; ~ / \\ bend a note; {0,4,7} after a note plays it as an arpeggio; !1 to !9 at the end sets its volume."]))));
  }

  // ---- parts --------------------------------------------------------------------
  function drawParts() {
    partsBox.replaceChildren(...song.parts.map((p, i) => {
      const err = h("div", { className: "err" });
      const check = () => {
        try {
          const drums = p.instrument === "drums";
          const r = drums ? M.parseDrums(p.text, song) : M.parseNotation(p.text, song);
          const per = M.cycleOf(song).beats * song.steps;
          err.className = "err muted";
          err.textContent = `${drums ? r.hits.length + " strokes on the " + M.kitOf(song) : r.notes.length + " notes"}, ` +
            `${r.steps} steps (${(r.steps / per).toFixed(2).replace(/\.00$/, "")} cycles)` +
            (drums && song.drumPattern !== "own" && song.drums !== "none" ? "; the automatic pattern plays too (drum pattern: my own turns it off)" : "");
        } catch (e) { err.className = "err"; err.textContent = e.message; }
      };
      const text = h("textarea", { rows: 3, value: p.text, spellcheck: false,
        onfocus: () => { if (partIndex !== i) { partIndex = i; drawParts(); drawRoll(); } },
        oninput: (e) => {
          const had = hasArps();
          p.text = e.target.value; changed(); check(); drawRoll();
          if (had !== hasArps()) drawHead();               // the arpeggio's speed shown only when there is one
        } });
      check();
      const inst = h("select", { onchange: (e) => { p.instrument = e.target.value; changed(); drawParts(); drawRoll(); } },
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
        text, err,
        p.instrument === "drums" ? h("div", { className: "muted", style: "font-size:12px" },
          `Strokes, one a step: thom (deep), tha (main), ki (light), dhi (ringing) — or kick, snare, hat, open. ` +
          `kick+hat plays two at once; - or , is a step with none; | a bar line; !1 to !9 the volume.`) : "");
    }));
  }
  // A drum part to start from: the automatic pattern for a cycle, written
  // out, and the automatic pattern turned off so the two do not double.
  function addDrumPart() {
    const { beats } = M.cycleOf(song);
    const per = beats * song.steps;
    if (song.drums === "none") song.drums = M.kitOf(song);
    song.parts.push({ name: "drums", instrument: "drums", octave: 0, gain: 0.9, pan: 0.15,
                      text: M.writeDrums(M.autoHits(song, per), per, song, per) });
    song.drumPattern = "own";
    partIndex = song.parts.length - 1;
    changed(); drawAll();
    status("Drum part added from the automatic pattern; drum pattern is now 'my own'. Change the strokes, or click on the roll.");
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
    rollName.textContent = p.name || "part " + (partIndex + 1);
    if (p.instrument === "drums") return drawDrumRoll(p);
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
      g.globalAlpha = n.vol ? 0.3 + 0.7 * n.vol / 9 : 1;    // quieter notes, fainter
      g.fillStyle = n.mark ? "#4fb3a9" : "#f0a330";
      g.fillRect(LABEL + n.at * CW + 1, r * RH + 2, n.len * CW - 2, RH - 4);
      g.globalAlpha = 1;
      for (const a of n.arp || []) {                       // an arpeggio's other notes, as ticks where they sound
        if (!a) continue;
        const rr = rows.indexOf(n.semi + a);
        if (rr < 0) continue;                              // a note off the roll's rows
        const yy = rr * RH + RH / 2;
        g.fillStyle = "#e0789a";
        for (let k = 0; k < n.len; k++) g.fillRect(LABEL + (n.at + k) * CW + 3, yy - 2, CW - 6, 4);
      }
      if (n.vol) { g.fillStyle = "#fff"; g.font = "9px monospace"; g.fillText(String(n.vol), LABEL + n.at * CW + 3, r * RH + RH / 2); }
    }
    if (song.loopCycle > 0) {                              // the loop point
      const x = LABEL + Math.min(song.loopCycle * per, steps) * CW;
      g.fillStyle = "#4fb3a9"; g.fillRect(x - 1, 0, 3, roll.height);
      g.font = "10px sans-serif"; g.fillText("loop ↺", x + 4, 10);
    }
    if (source) {
      const x = LABEL + ((audio.currentTime - playStart) % playLen) / playLen * M.songSteps(song) * CW;
      g.fillStyle = "#fff"; g.fillRect(x, 0, 2, roll.height);
    }
  }
  // A drum part's roll: a lane for each kind of stroke; click to add or remove
  function drawDrumRoll(p) {
    let parsed;
    try { parsed = M.parseDrums(p.text, song); } catch (e) { parsed = { hits: [], steps: 0 }; }
    const { beats, strong } = M.cycleOf(song);
    const per = beats * song.steps;
    const steps = Math.max(M.songSteps(song), parsed.steps + per);
    rows = M.KIND_ORDER;
    roll.width = LABEL + steps * CW; roll.height = rows.length * RH * 1.5;
    const g = roll.getContext("2d"), rh = RH * 1.5;
    g.fillStyle = "#1b1c24"; g.fillRect(0, 0, roll.width, roll.height);
    g.font = "11px ui-monospace, monospace"; g.textBaseline = "middle";
    rows.forEach((kind, r) => {
      g.fillStyle = r % 2 ? "#20222b" : "#1d1f27"; g.fillRect(LABEL, r * rh, roll.width, rh);
      g.fillStyle = "#c9c7c0"; g.fillText(M.drumWord(kind, song), 4, r * rh + rh / 2);
    });
    for (let st = 0; st <= steps; st++) {
      const beat = st % song.steps === 0, b = Math.floor((st % per) / song.steps);
      g.strokeStyle = st % per === 0 ? "#f0a33088" : beat && strong.includes(b) ? "#ffffff30" : beat ? "#ffffff18" : "#ffffff08";
      g.beginPath(); g.moveTo(LABEL + st * CW, 0); g.lineTo(LABEL + st * CW, roll.height); g.stroke();
    }
    for (const x of parsed.hits) {
      const r = rows.indexOf(x.kind);
      g.globalAlpha = x.vol ? 0.3 + 0.7 * x.vol / 9 : 1;
      g.fillStyle = ["#e5604f", "#f0a330", "#4fb3a9", "#e0789a", "#ffd166", "#9ccc65", "#8fa8ff"][r];
      g.beginPath(); g.arc(LABEL + x.at * CW + CW / 2, r * rh + rh / 2, CW * 0.36, 0, Math.PI * 2); g.fill();
      g.globalAlpha = 1;
    }
    if (source) {
      const xx = LABEL + ((audio.currentTime - playStart) % playLen) / playLen * M.songSteps(song) * CW;
      g.fillStyle = "#fff"; g.fillRect(xx, 0, 2, roll.height);
    }
  }
  function clickDrumRoll(p, e) {
    let parsed;
    try { parsed = M.parseDrums(p.text, song); } catch (err) { return status("Mend the drum part first: " + err.message, true); }
    const at = Math.floor((e.offsetX - LABEL) / CW), kind = M.KIND_ORDER[Math.floor(e.offsetY / (RH * 1.5))];
    if (!kind || at < 0) return;
    const there = parsed.hits.findIndex((x) => x.at === at && x.kind === kind);
    if (there >= 0) parsed.hits.splice(there, 1); else parsed.hits.push({ at, kind });
    const { beats } = M.cycleOf(song), per = beats * song.steps;
    const end = Math.max(parsed.steps, at + 1);
    p.text = M.writeDrums(parsed.hits, Math.ceil(end / per) * per, song, per);
    changed(); drawParts(); drawRoll();
  }

  roll.addEventListener("mousedown", (e) => {
    const p = song.parts[partIndex];
    if (p && p.instrument === "drums") { if (e.offsetX >= LABEL) clickDrumRoll(p, e); return; }
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
      status("Rendering the song to play it…");
      playBtn.textContent = "… rendering"; playBtn.disabled = true;
      const [L, R] = mix(await renderAsync(JSON.parse(JSON.stringify(s))));
      const a = ctx();
      await a.resume();
      const rate = song.rate || M.RATE;
      const b = a.createBuffer(2, L.length, rate);
      b.copyToChannel(L, 0); b.copyToChannel(R, 1);
      source = a.createBufferSource();
      source.buffer = b; source.loop = true; source.connect(a.destination);
      if (only === null) source.loopStart = M.loopFrame(song) / rate;     // as the game will loop it
      playBtn.disabled = false;
      playStart = a.currentTime; playLen = L.length / rate;
      source.start();
      playBtn.textContent = "■ Stop"; playBtn.classList.add("on");
      status(`Playing ${path || "the new song"}: ${playLen.toFixed(1)} s, looping.`);
      const tick = () => { drawRoll(); raf = requestAnimationFrame(tick); };
      tick();
    } catch (e) { playBtn.disabled = false; playBtn.textContent = "▶ Play"; status(e.message, true); }
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
  function togglePlay() { if (!playBtn.disabled) source ? stop() : play(); }

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
      const old = song.made && song.made.engine !== M.ENGINE;
      status(old ? `Opened ${path}. Its WAV was made by Isai engine ${song.made.engine}; this is engine ${M.ENGINE}, ` +
        "so making it again will change its sound a little." : `Opened ${path}.`, old);
    } catch (e) { status(`${files.value}: ${e.message}`, true); }
  }
  // An example song, opened as a new song: Save puts it in this game's music folder
  async function openExample() {
    if (!examples.value) return;
    if (dirty && !confirm("The song in hand has changes that are not saved. Open the example anyway?")) return;
    try {
      const s = await (await fetch(new URL("./songs/" + examples.value, import.meta.url))).json();
      song = { ...M.newSong(s.system), ...s };
      path = ""; dirty = true; partIndex = 0;
      stop(); drawAll();
      status(`${s.title}: ${s.about} Save keeps a copy in this game's music folder.`);
    } catch (e) { status("Could not open the example: " + e.message, true); }
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
      await refreshNote(song);                         // still what its WAV was made from?
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
      const ch = await renderAsync(JSON.parse(JSON.stringify(song)));
      const wav = wavBytes(song, ch);
      await api.write(wavOf(path), wav);
      song.made = await madeNote(song, wav);           // the note pack reads: which engine, which WAV, which song
      await save();
      status(`Made ${wavOf(path)} (${(ch[0].length / (song.rate || M.RATE)).toFixed(1)} s, ${Math.round(wav.length / 1024)} KB) and saved ${path}.`);
      drawHead();
    } catch (e) { status("No WAV made: " + e.message, true); }
  }

  // Every song in the game's music folder whose WAV is missing or out of date
  async function makeAll() {
    if (dirty && !confirm("The song in hand has changes that are not saved; Make all WAVs uses the saved songs. Go on?")) return;
    const songs = shared.files.filter((f) => /^music\/[^/]+\.json$/.test(f));
    let made = 0;
    try {
      for (const f of songs) {
        const s = JSON.parse(await api.readText(f));
        if (s.format !== "isai-song") continue;
        await refreshNote(s);
        const why = needsWav(s, shared.files.includes(wavOf(f)));
        if (!why) continue;
        status(`Making ${wavOf(f)} (${why})…`);
        const wav = wavBytes(s, await renderAsync(s));
        await api.write(wavOf(f), wav);
        s.made = await madeNote(s, wav);
        await api.write(f, JSON.stringify(s, null, 1) + "\n");
        made++;
        if (f === path) song.made = s.made;
      }
      await refreshFiles();
      status(made ? `Made ${made} WAV${made > 1 ? "s" : ""}; every song's WAV is up to date.` : "Every song's WAV was already up to date.");
    } catch (e) { status("Stopped: " + e.message, true); }
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
