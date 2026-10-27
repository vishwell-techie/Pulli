// Oli: the sound-effect editor. Start from a kind of sound (jump, coin,
// hit...), try variations, move the settings, hear it; Save keeps it as
// sfx/<name>.json and makes sfx/<name>.wav, which `pulli pack` puts in
// sfx.oli. sfx(n) plays the WAV files of sfx/ in order of name.
import { api, h, shared, status, refreshFiles, CHANNEL_NOTE } from "./app.js";
import * as S from "./lib/sfx.js";
import { encodeWAV } from "./lib/wav.js";
import { numbered } from "./lib/lua.js";

export function oli(root) {
  let sfx = S.preset("jump", 1), path = "", dirty = false, auto = true, seed = 1;
  let audio = null;

  const files = h("select", { title: "Sound effects made in Oli (sfx/*.json)" });
  const wave = h("canvas", { width: 640, height: 140 });
  const knobs = h("div", { className: "knobs" });
  const waveSel = h("select", { onchange: (e) => { sfx.wave = e.target.value; touched(); } },
    ...S.WAVES.map((w) => h("option", { value: w }, w)));
  const title = h("strong");
  const number = h("span", { className: "muted" });

  root.append(
    h("div", { className: "bar" }, files,
      h("button", { onclick: open }, "Open"),
      h("button", { onclick: save, title: "Keep sfx/<name>.json and make sfx/<name>.wav (Ctrl+S)" }, "Save"),
      h("button", { onclick: saveAs }, "Save as…"),
      h("span", { className: "sep" }),
      h("button", { className: "on", onclick: play, title: "Space" }, "▶ Play"),
      h("label", {}, h("input", { type: "checkbox", checked: auto, onchange: (e) => { auto = e.target.checked; } }), "play on change")),
    h("div", { className: "bar" }, h("span", { className: "muted" }, "Start from:"),
      ...Object.keys(S.PRESETS).map((name) => h("button", { onclick: () => {
        seed++; sfx = S.preset(name, seed); touched(true); } }, name)),
      h("span", { className: "sep" }),
      h("button", { title: "A small change to every setting", onclick: () => { seed++; sfx = S.mutate(sfx, seed); touched(true); } }, "More like this")),
    h("div", { className: "cols" },
      h("div", { className: "box" }, h("h3", {}, title, " ", number), wave,
        h("p", { className: "muted", style: "margin:6px 0 0" }, "Saved mono (1 channel) at 22,050 samples a second; the console brings it to 44,100."),
        h("p", { className: "muted", style: "margin:6px 0 0;max-width:640px;font-size:12px" }, CHANNEL_NOTE)),
      h("div", { className: "box wide" }, h("h3", {}, "Settings"), h("div", { className: "bar" }, h("label", {}, "wave", waveSel)), knobs)));

  function drawKnobs() {
    waveSel.value = sfx.wave;
    knobs.replaceChildren(...S.KNOBS.map(([k, min, max, step, label]) => {
      const val = h("span", { className: "muted", style: "width:56px;text-align:right" }, fmt(sfx[k]));
      return h("label", { className: "knob" }, h("span", { style: "width:130px" }, label),
        h("input", { type: "range", min, max, step, value: sfx[k],
          oninput: (e) => { sfx[k] = +e.target.value; val.textContent = fmt(sfx[k]); touched(false, true); } }), val);
    }));
  }
  const fmt = (v) => (Math.abs(v) >= 100 ? v.toFixed(0) : v.toFixed(2));

  let pending = 0;
  function touched(redraw = false, slider = false) {
    dirty = true;
    if (redraw) drawKnobs();
    drawWave();
    if (auto) {                                    // a slider plays when it rests, not on every step
      clearTimeout(pending);
      pending = setTimeout(play, slider ? 180 : 0);
    }
  }

  function drawWave() {
    const v = S.render(sfx);
    const g = wave.getContext("2d");
    g.fillStyle = "#14151b"; g.fillRect(0, 0, wave.width, wave.height);
    g.strokeStyle = "#ffffff18"; g.beginPath(); g.moveTo(0, wave.height / 2); g.lineTo(wave.width, wave.height / 2); g.stroke();
    g.fillStyle = "#f0a330";
    const per = v.length / wave.width;
    for (let x = 0; x < wave.width; x++) {
      let lo = 0, hi = 0;
      for (let i = Math.floor(x * per); i < Math.floor((x + 1) * per); i++) { lo = Math.min(lo, v[i]); hi = Math.max(hi, v[i]); }
      g.fillRect(x, (1 - hi) * wave.height / 2, 1, Math.max(1, (hi - lo) * wave.height / 2));
    }
    title.textContent = (path || "(not saved)") + (dirty ? " •" : "");
    const n = numbered(shared.files, "sfx").indexOf(path.replace(/\.json$/, ".wav"));
    number.textContent = `${(v.length / S.RATE).toFixed(2)} s` + (n >= 0 ? ` · sfx(${n})` : "");
  }

  function play() {
    const v = S.render(sfx);
    audio = audio || new AudioContext();
    const b = audio.createBuffer(1, v.length, S.RATE);
    b.copyToChannel(v, 0);
    const src = audio.createBufferSource();
    src.buffer = b; src.connect(audio.destination); src.start();
  }

  // ---- files ----------------------------------------------------------------------
  async function open() {
    if (!files.value) return;
    if (dirty && !confirm("This sound has changes that are not saved. Open another anyway?")) return;
    try {
      const s = JSON.parse(await api.readText(files.value));
      if (s.format !== "oli-sfx") throw new Error("not an Oli sound");
      sfx = { ...S.newSfx(), ...s };
      path = files.value; dirty = false;
      drawKnobs(); drawWave(); play();
      status(`Opened ${path}.`);
    } catch (e) { status(`${files.value}: ${e.message}`, true); }
  }
  async function saveAs() {
    const have = numbered(shared.files, "sfx");
    const name = prompt(`Name for the sound: sfx/<name>.wav. sfx(n) counts the WAV files by name, so a number in front keeps them in order (there are ${have.length}).`,
                        String(have.length).padStart(2, "0") + "-sound");
    if (!name) return;
    if (!/^[\w-]+$/.test(name)) return status("Use letters, digits, - and _ in the name.", true);
    const p = `sfx/${name}.json`;
    if ((shared.files.includes(p) || shared.files.includes(`sfx/${name}.wav`)) && !confirm(`sfx/${name} exists. Replace it?`)) return;
    path = p;
    await save();
  }
  async function save() {
    if (!path) return saveAs();
    try {
      await api.write(path, JSON.stringify(sfx, null, 1) + "\n");
      await api.write(path.replace(/\.json$/, ".wav"), encodeWAV([S.render(sfx)], S.RATE));
      dirty = false;
      await refreshFiles();
      files.value = path;
      drawWave();
      const n = numbered(shared.files, "sfx").indexOf(path.replace(/\.json$/, ".wav"));
      status(`Saved ${path} and made ${path.replace(/\.json$/, ".wav")}: the game plays it with sfx(${n}).`);
    } catch (e) { status("Not saved: " + e.message, true); }
  }

  addEventListener("keydown", (e) => {
    if (!root.classList.contains("on") || /INPUT|TEXTAREA|SELECT/.test(document.activeElement?.tagName) &&
        document.activeElement.type !== "range") return;
    if (e.key === " ") { e.preventDefault(); play(); }
    else if (e.ctrlKey && e.key.toLowerCase() === "s") { e.preventDefault(); save(); }
  });

  shared.listeners.push((what) => {
    if (what !== "files") return;
    const was = files.value;
    files.replaceChildren(...shared.files.filter((f) => /^sfx\/[^/]+\.json$/.test(f)).map((f) => h("option", { value: f }, f)));
    if (was) files.value = was;
    drawWave();
  });
  shared.dirtyChecks.push(() => dirty);
  drawKnobs();
  drawWave();
}
