// Vidhi, the code editor: the game's Lua files, coloured, beside its assets. A
// sprite, sound, track, map or sheet is put into the code with a click as
// the call that uses it (spr(12, x, y), sfx(3), map.load("hall.ooru")...),
// and the call under the cursor shows what it names: the sprite drawn, the
// sound's file with a button to hear it. Check runs the game for two
// seconds with no window and lists its errors by line.
import { api, h, shared, status, refreshFiles, soundInfo, CHANNEL_NOTE } from "./app.js";
import { css } from "./lib/palette.js";
import { highlight, callAt, numbered, wordBefore, complete, callHint, SIGS } from "./lib/lua.js";
const SIGS_OF = (n) => SIGS[n];

export function vidhi(root) {
  let path = "", saved = "", sheetZoom = 2, tab = "sprites";
  const sounds = new Map();
  let audio = null;

  const files = h("select", { title: "Lua files in the game folder" });
  const area = h("textarea", { spellcheck: false, wrap: "off", className: "code-in",
    oninput: () => { paint(); link(); suggest(); }, onscroll: () => { sync(); hidePop(); },
    onkeyup: (e) => { link(); if (!["ArrowUp", "ArrowDown", "Enter", "Tab", "Escape"].includes(e.key)) showHint(); },
    onclick: () => { link(); showHint(); hidePop(); } });
  const pre = h("pre", { className: "code-out", "aria-hidden": "true" });
  const gutter = h("pre", { className: "code-gutter", "aria-hidden": "true" });
  const pop = h("div", { className: "complete", style: "display:none" });
  const hint = h("div", { className: "hint muted" }, "");
  const findIn = h("input", { placeholder: "find", style: "width:180px", oninput: () => findNext(0), onkeydown: (e) => {
    if (e.key === "Enter") { e.preventDefault(); findNext(e.shiftKey ? -1 : 1); } if (e.key === "Escape") closeFind(); } });
  const replIn = h("input", { placeholder: "replace with", style: "width:180px", onkeydown: (e) => { if (e.key === "Escape") closeFind(); } });
  const findCount = h("span", { className: "muted" });
  const findBar = h("div", { className: "bar", style: "display:none;margin:0 0 6px" }, findIn,
    h("button", { title: "Previous (Shift+Enter)", onclick: () => findNext(-1) }, "↑"),
    h("button", { title: "Next (Enter)", onclick: () => findNext(1) }, "↓"), replIn,
    h("button", { onclick: replaceOne }, "Replace"), h("button", { onclick: replaceAll }, "Replace all"),
    h("label", {}, h("input", { type: "checkbox", onchange: () => findNext(0), id: "vidhi-case" }), "Aa"),
    findCount, h("button", { onclick: () => closeFind() }, "✕"));
  const card = h("div", { className: "linkcard muted" }, "Put the cursor on spr(…), sfx(…), music(…) or map.load(…) to see what it names.");
  const problems = h("div", { className: "problems" });
  const assets = h("div");
  const tabs = {};
  for (const [k, label] of [["sprites", "Sprites"], ["sfx", "Sounds"], ["music", "Music"], ["maps", "Maps"], ["backdrops", "Backdrops"]])
    tabs[k] = h("button", { onclick: () => { tab = k; drawAssets(); } }, label);

  root.append(
    h("div", { className: "bar" }, files,
      h("button", { onclick: open }, "Open"),
      h("button", { onclick: create }, "New…"),
      h("button", { onclick: save, title: "Ctrl+S" }, "Save"),
      h("span", { className: "sep" }),
      h("button", { onclick: check, title: "Save, then run the game for two seconds with no window and list its errors" }, "✓ Check")),
    h("div", { className: "cols", style: "flex-wrap:nowrap" },
      h("div", { className: "wide", style: "min-width:0" }, findBar,
        h("div", { className: "code" }, gutter, h("div", { className: "code-box" }, pre, area, pop)), hint, problems),
      h("div", { className: "box", style: "width:360px;flex:none" },
        h("h3", {}, "Under the cursor"), card,
        h("h3", { style: "margin-top:14px" }, "Put in the code"),
        h("div", { className: "bar" }, ...Object.values(tabs)), assets)));

  // ---- the text ------------------------------------------------------------------
  function paint() {
    pre.innerHTML = highlight(area.value);
    const n = area.value.split("\n").length;
    gutter.textContent = Array.from({ length: n }, (_, i) => i + 1).join("\n") + "\n";
    sync();
  }
  function sync() { pre.scrollTop = gutter.scrollTop = area.scrollTop; pre.scrollLeft = area.scrollLeft; }
  const dirty = () => path && area.value !== saved;

  area.addEventListener("keydown", (e) => {
    if (pop.style.display !== "none") {           // the list of names is open
      if (e.key === "ArrowDown" || e.key === "ArrowUp") { e.preventDefault(); pick += e.key === "ArrowDown" ? 1 : -1; drawPop(); return; }
      if (e.key === "Enter" || e.key === "Tab") { e.preventDefault(); accept(); return; }
      if (e.key === "Escape") { hidePop(); return; }
    }
    if (e.ctrlKey && e.key.toLowerCase() === "f") { e.preventDefault(); openFind(); return; }
    if (e.ctrlKey && e.key === " ") { e.preventDefault(); suggest(true); return; }
    if (e.key === "Tab") {
      e.preventDefault();
      document.execCommand("insertText", false, "  ");
    } else if (e.key === "Enter") {             // keep the line's indent
      e.preventDefault();
      const before = area.value.slice(0, area.selectionStart);
      const line = before.slice(before.lastIndexOf("\n") + 1);
      let indent = line.match(/^\s*/)[0];
      if (/\b(then|do|else|function\b.*\))\s*$|\brepeat\s*$|\{\s*$/.test(line)) indent += "  ";
      document.execCommand("insertText", false, "\n" + indent);
    } else if (e.ctrlKey && e.key.toLowerCase() === "s") { e.preventDefault(); save(); }
  });

  // ---- names offered while typing, and the arguments of the call -------------
  let choices = [], pick = 0, at0 = 0;
  const charW = (() => { const c = document.createElement("canvas").getContext("2d");
    c.font = '13px ui-monospace, "Noto Sans Mono", monospace'; return c.measureText("M").width; })();
  function suggest(force = false) {
    const w = wordBefore(area.value, area.selectionStart);
    choices = w ? complete(w.word, area.value) : [];
    if (!choices.length || (!force && w.word.length < 2)) return hidePop();
    at0 = w.start; pick = 0;
    const before = area.value.slice(0, w.start), line = before.split("\n").length - 1;
    const col = w.start - before.lastIndexOf("\n") - 1;
    pop.style.left = `${10 + col * charW - area.scrollLeft}px`;
    pop.style.top = `${8 + (line + 1) * 19.5 - area.scrollTop}px`;
    pop.style.display = "block";
    drawPop();
  }
  function drawPop() {
    pick = (pick + choices.length) % choices.length;
    pop.replaceChildren(...choices.map((n, i) => h("div", { className: i === pick ? "on" : "",
      onmousedown: (e) => { e.preventDefault(); pick = i; accept(); } },
      n, SIGS_OF(n) ? h("span", { className: "muted" }, `(${SIGS_OF(n)[0]})`) : "")));
  }
  function hidePop() { pop.style.display = "none"; }
  function accept() {
    const n = choices[pick];
    area.setSelectionRange(at0, area.selectionStart);
    insert(n + (SIGS_OF(n) && area.value[area.selectionEnd] !== "(" ? "(" : ""));
    hidePop(); showHint();
  }
  function showHint() {
    const c = callHint(area.value, area.selectionStart);
    if (!c) { hint.textContent = ""; return; }
    const args = c.sig[0].split(",").map((a) => a.trim());
    hint.replaceChildren(h("span", { className: "f" }, c.name), "(",
      ...args.flatMap((a, i) => [i ? ", " : "", i === c.arg ? h("b", {}, a) : a]), ")", c.sig[1] ? `  — ${c.sig[1]}` : "");
  }

  // ---- find and replace ------------------------------------------------------------
  function openFind() {
    findBar.style.display = "flex";
    const s = area.value.slice(area.selectionStart, area.selectionEnd);
    if (s && !s.includes("\n")) findIn.value = s;
    findIn.focus(); findIn.select();
    findNext(0);
  }
  function closeFind() { findBar.style.display = "none"; area.focus(); }
  function matches() {
    const q = findIn.value;
    if (!q) return [];
    const cs = document.getElementById("vidhi-case")?.checked;
    const text = cs ? area.value : area.value.toLowerCase(), w = cs ? q : q.toLowerCase();
    const out = [];
    for (let i = text.indexOf(w); i >= 0; i = text.indexOf(w, i + Math.max(1, w.length))) out.push(i);
    return out;
  }
  function findNext(dir) {
    const all = matches();
    findCount.textContent = findIn.value ? `${all.length} found` : "";
    if (!all.length) return;
    const from = dir < 0 ? area.selectionStart : dir > 0 ? area.selectionEnd : area.selectionStart;
    let i = dir < 0 ? [...all].reverse().find((x) => x < from) : all.find((x) => x >= from);
    if (i === undefined) i = dir < 0 ? all[all.length - 1] : all[0];
    select(i, i + findIn.value.length);
    findCount.textContent = `${all.indexOf(i) + 1} of ${all.length}`;
  }
  function select(a, b) {
    area.setSelectionRange(a, b);
    const line = area.value.slice(0, a).split("\n").length;
    area.scrollTop = Math.max(0, (line - 6) * 19.5);
    sync();
  }
  function replaceOne() {
    const q = findIn.value, sel = area.value.slice(area.selectionStart, area.selectionEnd);
    const cs = document.getElementById("vidhi-case")?.checked;
    if (q && (cs ? sel === q : sel.toLowerCase() === q.toLowerCase())) {
      area.focus(); document.execCommand("insertText", false, replIn.value); paint();
    }
    findNext(1);
  }
  function replaceAll() {
    const all = matches();
    if (!all.length) return;
    let text = area.value;
    for (const i of [...all].reverse())       // from the end, so earlier places do not move
      text = text.slice(0, i) + replIn.value + text.slice(i + findIn.value.length);
    const top = area.scrollTop;
    area.focus();
    area.setSelectionRange(0, area.value.length);
    document.execCommand("insertText", false, text);   // one step for Ctrl+Z
    area.setSelectionRange(all[0], all[0]);
    area.scrollTop = top;
    paint();
    status(`Replaced ${all.length}.`);
    findNext(0);
  }

  // put text in at the cursor, through the browser so Ctrl+Z takes it back
  function insert(text) {
    area.focus();
    document.execCommand("insertText", false, text);
    paint(); link();
  }

  // ---- what the call under the cursor names ------------------------------------
  function link() {
    const at = area.selectionStart, text = area.value;
    const start = text.lastIndexOf("\n", at - 1) + 1, end = text.indexOf("\n", at);
    const call = callAt(text.slice(start, end < 0 ? text.length : end), at - start);
    if (!call) return;
    if (call.fn === "spr" && shared.sheet) {
      const c = h("canvas");
      drawSprite(c, call.arg, 1, 1, 8);
      card.replaceChildren(h("div", { className: "bar" }, c, h("span", {}, `spr(${call.arg}) on ${shared.sheet.path}`)));
    } else if (call.fn === "sfx" || call.fn === "music") {
      const list = numbered(shared.files, call.fn === "sfx" ? "sfx" : "music");
      const f = list[call.arg];
      const row = shared.sounds?.[call.fn === "sfx" ? "sfx" : "music"]?.[call.arg];
      card.replaceChildren(f ? h("div", {}, h("div", { className: "bar" }, h("button", { onclick: () => hear(f) }, "▶"), `${call.fn}(${call.arg}) is ${f}`),
                                 h("div", { className: "muted", style: "font-size:12px" }, soundInfo(row)))
                             : h("span", { className: "err" }, `${call.fn}(${call.arg}): there are only ${list.length} WAV files in ${call.fn === "sfx" ? "sfx" : "music"}/`));
    } else if (typeof call.arg === "string") {
      const stem = call.arg.replace(/\.(ooru|kolam)$/, "");
      const src = shared.files.find((f) => f === stem + ".tmx" || f === stem + ".png");
      card.replaceChildren(src ? h("span", {}, `${call.fn}("${call.arg}") is made from ${src}`)
                               : h("span", { className: "err" }, `${call.fn}("${call.arg}"): no ${stem}.tmx or ${stem}.png in the game`));
    }
  }

  async function hear(file) {
    try {
      audio = audio || new AudioContext();
      if (!sounds.has(file)) sounds.set(file, await audio.decodeAudioData((await api.read(file)).buffer));
      const s = audio.createBufferSource();
      s.buffer = sounds.get(file); s.connect(audio.destination); s.start();
      if (file.startsWith("music/")) setTimeout(() => s.stop(), 8000);   // a taste of a track
    } catch (e) { status(`${file}: ${e.message}`, true); }
  }

  // ---- the assets ----------------------------------------------------------------
  function drawSprite(c, n, w, hh, z) {
    const s = shared.sheet, cols = s.width / 8;
    c.width = w * 8 * z; c.height = hh * 8 * z;
    const g = c.getContext("2d");
    for (let y = 0; y < hh * 8; y++) for (let x = 0; x < w * 8; x++) {
      const sx = (n % cols) * 8 + x, sy = Math.floor(n / cols) * 8 + y;
      const p = sx < s.width && sy < s.height ? s.pixels[sy * s.width + sx] : 0;
      g.fillStyle = p ? css(shared.palette[p]) : (x + y) % 2 ? "#3a3c48" : "#2c2e38";
      g.fillRect(x * z, y * z, z, z);
    }
  }

  let from = null;
  function drawAssets() {
    for (const [k, b] of Object.entries(tabs)) b.classList.toggle("on", k === tab);
    if (tab === "sprites") {
      const s = shared.sheet;
      if (!s) return assets.replaceChildren(h("p", { className: "muted" }, "No sprite sheet open: open one in Kolam."));
      const c = h("canvas", { style: "cursor:pointer" });
      const cols = s.width / 8;
      const z = Math.max(1, Math.min(4, Math.floor(330 / s.width)));
      c.width = s.width * z; c.height = s.height * z;
      const g = c.getContext("2d");
      const img = new ImageData(s.width, s.height);
      for (let i = 0; i < s.pixels.length; i++) if (s.pixels[i]) {
        const v = shared.palette[s.pixels[i]];
        img.data.set([v >> 16, (v >> 8) & 255, v & 255, 255], i * 4);
      }
      const tmp = new OffscreenCanvas(s.width, s.height);
      tmp.getContext("2d").putImageData(img, 0, 0);
      g.imageSmoothingEnabled = false;
      g.drawImage(tmp, 0, 0, c.width, c.height);
      const cellOf = (e) => [Math.floor(e.offsetX / z / 8), Math.floor(e.offsetY / z / 8)];
      const hint = h("p", { className: "muted", style: "margin:4px 0 0" },
        `${s.path}: click a sprite to put spr(n, x, y) in the code; drag across cells for a bigger one.`);
      c.onmousedown = (e) => { from = cellOf(e); };
      c.onmouseup = (e) => {
        if (!from) return;
        const [x1, y1] = cellOf(e), [x0, y0] = from;
        from = null;
        const ax = Math.min(x0, x1), ay = Math.min(y0, y1), w = Math.abs(x1 - x0) + 1, hh = Math.abs(y1 - y0) + 1;
        const n = ay * cols + ax;
        insert(w > 1 || hh > 1 ? `spr(${n}, x, y, ${w}, ${hh})` : `spr(${n}, x, y)`);
      };
      c.onmousemove = (e) => { const [x, y] = cellOf(e); c.title = `spr(${y * cols + x})`; };
      const others = shared.files.filter((f) => f.endsWith(".png") && f !== s.path && !f.includes("/"));
      assets.replaceChildren(h("div", { className: "scroll", style: "max-height:46vh" }, c), hint,
        ...(others.length ? [h("p", { className: "muted", style: "margin:10px 0 4px" }, "Other sheets:"),
          h("div", { className: "keys" }, ...others.map((f) => h("button", { title: `sheet.load("${f.replace(/\.png$/, ".kolam")}")`,
            onclick: () => insert(`sheet.load("${f.replace(/\.png$/, ".kolam")}")`) }, f)))] : []));
    } else if (tab === "sfx" || tab === "music") {
      const list = numbered(shared.files, tab);
      const rows = shared.sounds?.[tab] || [];
      const max = shared.sounds?.max || 256;
      assets.replaceChildren(h("p", { className: "muted", style: "margin:0 0 8px;font-size:12px" }, CHANNEL_NOTE),
        list.length > max ? h("p", { className: "err" }, `${list.length} sounds: pack takes at most ${max} in ${tab}/.`) : "",
        list.length
        ? h("div", {}, ...list.map((f, i) => h("div", { style: "margin:0 0 6px" },
            h("div", { className: "bar", style: "margin:0" },
              h("button", { title: "Hear it", onclick: () => hear(f) }, "▶"),
              h("button", { onclick: () => insert(tab === "sfx" ? `sfx(${i})` : `music(${i})`) }, `${tab}(${i})`),
              tab === "sfx" ? h("button", { title: "On a channel of its own choosing, 0 to 7", onclick: () => insert(`sfx(${i}, 0)`) }, "on a channel") : "",
              h("span", {}, f.split("/")[1])),
            h("div", { className: rows[i]?.error ? "err" : "muted", style: "font-size:12px;margin-left:4px" }, soundInfo(rows[i])))))
        : h("p", { className: "muted" }, `No WAV files in ${tab}/ yet.` + (tab === "music" ? " Isai makes them." : " Oli makes them.")));
    } else if (tab === "backdrops") {
      const pics = shared.files.filter((f) => f.endsWith(".png") && !f.includes("/") && f !== "sprites.png");
      assets.replaceChildren(h("p", { className: "muted", style: "margin:0 0 8px;font-size:12px" },
          "backdrop(name) once, then cls() each frame starts from it. A backdrop is 320 × 240; make one in the Backdrop tab."),
        pics.length ? h("div", {}, ...pics.map((f) => h("div", { className: "bar", style: "margin:0 0 4px" },
          h("button", { onclick: () => insert(`backdrop("${f.replace(/\.png$/, ".kolam")}")`) }, `backdrop("${f.replace(/\.png$/, ".kolam")}")`))),
          h("button", { onclick: () => insert("backdrop()") }, "backdrop()  -- let it go"))
        : h("p", { className: "muted" }, "No pictures yet."));
    } else {
      const maps = shared.files.filter((f) => f.endsWith(".tmx") && !f.includes("/"));
      assets.replaceChildren(maps.length
        ? h("div", {}, ...maps.map((f) => h("div", { className: "bar", style: "margin:0 0 4px" },
            h("button", { onclick: () => insert(`map.load("${f.replace(/\.tmx$/, ".ooru")}")`) }, `map.load("${f.replace(/\.tmx$/, ".ooru")}")`),
            h("button", { onclick: () => insert(`map.draw(0)\n`) }, "map.draw"))))
        : h("p", { className: "muted" }, "No maps yet: make one in Ooru."));
    }
  }

  // ---- files and checking ---------------------------------------------------------
  async function open() {
    if (!files.value) return;
    if (dirty() && !confirm(`${path} has changes that are not saved. Open another anyway?`)) return;
    try {
      area.value = saved = await api.readText(files.value);
      path = files.value;
      area.scrollTop = 0;
      paint();
      status(`Opened ${path}.`);
    } catch (e) { status(e.message, true); }
  }
  async function create() {
    const name = prompt("Name of the new Lua file", "enemy.lua");
    if (!name) return;
    if (!/^[\w-]+\.lua$/.test(name)) return status("A Lua file's name ends in .lua and sits in the game folder.", true);
    if (shared.files.includes(name)) return status(`${name} exists; open it instead.`, true);
    path = name;
    area.value = `-- ${name}: used with require("${name.replace(/\.lua$/, "")}")\nlocal M = {}\n\nreturn M\n`;
    saved = "";
    paint();
    await save();
  }
  async function save() {
    if (!path) return false;
    try {
      await api.write(path, area.value);
      saved = area.value;
      await refreshFiles();
      files.value = path;
      status(`Saved ${path}.`);
      return true;
    } catch (e) { status("Not saved: " + e.message, true); return false; }
  }
  async function check() {
    if (dirty() && !(await save())) return;
    status("Checking: running the game for two seconds…");
    problems.replaceChildren();
    try {
      const r = await (await fetch("/api/check", { method: "POST", headers: { "X-Pulli-Token": location.hash.slice(1) } })).json();
      const lines = r.out.split("\n").filter((l) => l.trim());
      problems.replaceChildren(...lines.map((l) => {
        const m = l.match(/([\w./-]+\.lua):(\d+):/);
        return h("div", { className: m ? "err link" : r.ok ? "muted" : "err",
          onclick: m ? () => go(m[1], +m[2]) : null }, l);
      }));
      status(r.ok ? "No errors in two seconds of play." : "The game stopped with an error.", !r.ok);
    } catch (e) { status(e.message, true); }
  }
  async function go(file, line) {
    if (file !== path) { files.value = file; await open(); }
    const at = area.value.split("\n").slice(0, line - 1).join("\n").length + (line > 1 ? 1 : 0);
    area.focus();
    area.setSelectionRange(at, at);
    area.scrollTop = Math.max(0, (line - 5) * parseFloat(getComputedStyle(area).lineHeight));
    sync();
  }

  shared.listeners.push((what) => {
    if (what === "files") {
      const was = files.value;
      files.replaceChildren(...shared.files.filter((f) => f.endsWith(".lua")).map((f) => h("option", { value: f }, f)));
      files.value = was || (shared.files.includes("main.lua") ? "main.lua" : files.value);
      if (!path && files.value) open();
    }
    if (what === "files" || what === "sheet" || (what === "pixels" && tab === "sprites")) drawAssets();
  });
  shared.dirtyChecks.push(dirty);
  paint();
  drawAssets();
}
