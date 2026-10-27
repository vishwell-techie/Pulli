// Kolam: the sprite editor. Draws on the game's sprite sheet (a .png) in
// its 64 colours; colour 0 is see-through. spr(n) counts 8x8 cells left to
// right, top to bottom, and the number of the cell in hand is shown.
import { api, h, shared, status, loadSheet, saveSheet, refreshFiles } from "./app.js";
import { css } from "./lib/palette.js";

export function kolam(root) {
  let colour = 8, tool = "pen", cell = 0, size = 16, zoom = 20, sheetZoom = 3;
  const undo = [], redo = [];
  let clip = null;

  const files = h("select", { title: "Pictures in the game folder" });
  const big = h("canvas");
  const whole = h("canvas");
  const info = h("span", { className: "muted" });
  const swatches = h("div", { className: "swatches" });
  const tools = {};
  for (const [k, label, key] of [["pen", "✎ Pen", "p"], ["fill", "◧ Fill", "f"], ["line", "╱ Line", "l"],
                                 ["rect", "▭ Box", "r"], ["pick", "⊙ Pick", "k"], ["erase", "⌫ Erase", "e"]])
    tools[k] = h("button", { title: `${label.slice(2)} (${key.toUpperCase()})`, onclick: () => setTool(k) }, label);
  const sizes = h("select", { onchange: () => { size = +sizes.value; zoom = Math.max(6, Math.floor(384 / size)); draw(); } },
    ...[8, 16, 32, 64].map((n) => h("option", { value: n, selected: n === size }, `${n}×${n}`)));

  root.append(
    h("div", { className: "bar" }, files,
      h("button", { onclick: open }, "Open"),
      h("button", { onclick: newSheet }, "New…"),
      h("button", { onclick: save }, "Save"),
      h("span", { className: "sep" }),
      ...Object.values(tools),
      h("span", { className: "sep" }),
      h("button", { title: "Undo (Ctrl+Z)", onclick: () => step(undo, redo) }, "↶"),
      h("button", { title: "Redo (Ctrl+Y)", onclick: () => step(redo, undo) }, "↷"),
      h("span", { className: "sep" }),
      h("button", { title: "Flip left-right", onclick: () => region((get) => (x, y) => get(size - 1 - x, y)) }, "⇋"),
      h("button", { title: "Flip up-down", onclick: () => region((get) => (x, y) => get(x, size - 1 - y)) }, "⇵"),
      h("button", { title: "Turn a quarter clockwise", onclick: () => region((get) => (x, y) => get(y, size - 1 - x)) }, "↻"),
      h("button", { title: "Copy (Ctrl+C)", onclick: copy }, "Copy"),
      h("button", { title: "Paste (Ctrl+V)", onclick: paste }, "Paste"),
      h("button", { title: "Clear to see-through", onclick: () => region(() => () => 0) }, "Clear")),
    h("div", { className: "cols" },
      h("div", { className: "box" }, h("h3", {}, "Colours"), swatches,
        h("p", { className: "muted", style: "max-width:190px" }, "Right-click picks a colour. 0 is see-through.")),
      h("div", { className: "box" }, h("h3", {}, "Sprite ", info, " ", sizes), big),
      h("div", { className: "box wide" }, h("h3", {}, "Sheet"), h("div", { className: "scroll" }, whole))));

  function setTool(k) {
    tool = k;
    for (const [n, b] of Object.entries(tools)) b.classList.toggle("on", n === k);
  }
  setTool("pen");

  function paintSwatches() {
    swatches.replaceChildren(...shared.palette.map((c, i) => h("div", {
      className: (i === 0 ? "clear" : "") + (i === colour ? " on" : ""), title: `colour ${i}`,
      style: i ? `background:${css(c)}` : "", onclick: () => { colour = i; paintSwatches(); } })));
  }

  // ---- the sheet and the sprite in hand --------------------------------------
  const S = () => shared.sheet;
  const cols = () => S().width / 8;
  const origin = () => [(cell % cols()) * 8, Math.floor(cell / cols()) * 8];
  const at = (x, y) => S().pixels[y * S().width + x];

  function draw() {
    const s = S();
    if (!s) { info.textContent = "(no sheet: open or make one)"; return; }
    const [ox, oy] = origin();
    const w = Math.min(size, s.width - ox), hh = Math.min(size, s.height - oy);
    big.width = size * zoom; big.height = size * zoom;
    const g = big.getContext("2d");
    g.clearRect(0, 0, big.width, big.height);
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
      const p = x < w && y < hh ? at(ox + x, oy + y) : 0;
      g.fillStyle = p ? css(shared.palette[p]) : (x + y) % 2 ? "#3a3c48" : "#2c2e38";
      g.fillRect(x * zoom, y * zoom, zoom, zoom);
    }
    g.strokeStyle = "#0005";
    for (let i = 0; i <= size; i++) {
      g.lineWidth = i % 8 ? 1 : 2;
      g.beginPath(); g.moveTo(i * zoom, 0); g.lineTo(i * zoom, size * zoom); g.stroke();
      g.beginPath(); g.moveTo(0, i * zoom); g.lineTo(size * zoom, i * zoom); g.stroke();
    }
    info.textContent = `spr(${cell})  at ${ox},${oy}`;
    drawWhole();
  }

  function drawWhole() {
    const s = S();
    whole.width = s.width * sheetZoom; whole.height = s.height * sheetZoom;
    const g = whole.getContext("2d");
    const img = new ImageData(s.width, s.height);
    for (let i = 0; i < s.pixels.length; i++) {
      const p = s.pixels[i];
      if (!p) continue;
      const c = shared.palette[p];
      img.data.set([c >> 16, (c >> 8) & 255, c & 255, 255], i * 4);
    }
    const tmp = new OffscreenCanvas(s.width, s.height);
    tmp.getContext("2d").putImageData(img, 0, 0);
    g.imageSmoothingEnabled = false;
    g.drawImage(tmp, 0, 0, whole.width, whole.height);
    g.strokeStyle = "#ffffff18";
    for (let x = 0; x <= s.width; x += 8) { g.beginPath(); g.moveTo(x * sheetZoom, 0); g.lineTo(x * sheetZoom, whole.height); g.stroke(); }
    for (let y = 0; y <= s.height; y += 8) { g.beginPath(); g.moveTo(0, y * sheetZoom); g.lineTo(whole.width, y * sheetZoom); g.stroke(); }
    const [ox, oy] = origin();
    g.strokeStyle = "#f0a330"; g.lineWidth = 2;
    g.strokeRect(ox * sheetZoom, oy * sheetZoom, size * sheetZoom, size * sheetZoom);
  }

  whole.addEventListener("mousedown", (e) => {
    if (!S()) return;
    const x = Math.floor(e.offsetX / sheetZoom / 8), y = Math.floor(e.offsetY / sheetZoom / 8);
    cell = Math.max(0, Math.min(y * cols() + x, cols() * (S().height / 8) - 1));
    draw();
  });
  whole.addEventListener("wheel", (e) => {
    if (!e.ctrlKey) return;
    e.preventDefault();
    sheetZoom = Math.max(1, Math.min(8, sheetZoom + (e.deltaY < 0 ? 1 : -1)));
    drawWhole();
  });

  // ---- drawing -----------------------------------------------------------------
  function snapshot() {
    undo.push(S().pixels.slice());
    if (undo.length > 100) undo.shift();
    redo.length = 0;
  }
  function step(from, to) {
    if (!from.length || !S()) return;
    to.push(S().pixels.slice());
    S().pixels = from.pop();
    touched();
  }
  function touched() { S().dirty = true; shared.changed("pixels"); draw(); }

  function put(x, y, p) {
    const [ox, oy] = origin();
    if (x < 0 || y < 0 || x >= size || y >= size || ox + x >= S().width || oy + y >= S().height) return;
    S().pixels[(oy + y) * S().width + ox + x] = p;
  }
  function lineCells(x0, y0, x1, y1, f) {
    const dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    let err = dx + dy;
    for (;;) {
      f(x0, y0);
      if (x0 === x1 && y0 === y1) break;
      const e2 = 2 * err;
      if (e2 >= dy) { err += dy; x0 += sx; }
      if (e2 <= dx) { err += dx; y0 += sy; }
    }
  }
  function fill(x, y, p) {
    const [ox, oy] = origin();
    const was = at(ox + x, oy + y);
    if (was === p) return;
    const stack = [[x, y]];
    while (stack.length) {
      const [cx, cy] = stack.pop();
      if (cx < 0 || cy < 0 || cx >= size || cy >= size || ox + cx >= S().width || oy + cy >= S().height) continue;
      if (at(ox + cx, oy + cy) !== was) continue;
      put(cx, cy, p);
      stack.push([cx + 1, cy], [cx - 1, cy], [cx, cy + 1], [cx, cy - 1]);
    }
  }

  let down = null, before = null;
  const where = (e) => [Math.floor(e.offsetX / zoom), Math.floor(e.offsetY / zoom)];
  big.addEventListener("contextmenu", (e) => e.preventDefault());
  big.addEventListener("mousedown", (e) => {
    if (!S()) return;
    const [x, y] = where(e);
    const [ox, oy] = origin();
    if (e.button === 2 || tool === "pick") {
      if (ox + x < S().width && oy + y < S().height) { colour = at(ox + x, oy + y); paintSwatches(); }
      return;
    }
    snapshot();
    const p = tool === "erase" ? 0 : colour;
    down = [x, y, p];
    before = S().pixels.slice();
    if (tool === "fill") { fill(x, y, p); down = null; touched(); return; }
    put(x, y, p);
    touched();
  });
  big.addEventListener("mousemove", (e) => {
    if (!down) return;
    const [x, y] = where(e);
    const [x0, y0, p] = down;
    if (tool === "pen" || tool === "erase") {
      lineCells(x0, y0, x, y, (a, b) => put(a, b, p));
      down = [x, y, p];
    } else {
      S().pixels.set(before);
      if (tool === "line") lineCells(x0, y0, x, y, (a, b) => put(a, b, p));
      else if (tool === "rect") {
        for (let a = Math.min(x0, x); a <= Math.max(x0, x); a++) { put(a, y0, p); put(a, y, p); }
        for (let b = Math.min(y0, y); b <= Math.max(y0, y); b++) { put(x0, b, p); put(x, b, p); }
      }
    }
    touched();
  });
  addEventListener("mouseup", () => { down = null; });

  function region(make) {
    if (!S()) return;
    snapshot();
    const [ox, oy] = origin();
    const n = Math.min(size, S().width - ox, S().height - oy);
    const copyOf = [];
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) copyOf.push(at(ox + x, oy + y));
    const f = make((x, y) => (x < n && y < n ? copyOf[y * n + x] : 0));
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) put(x, y, f(x, y));
    touched();
  }
  function copy() {
    if (!S()) return;
    const [ox, oy] = origin();
    clip = { size, px: [] };
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++)
      clip.px.push(ox + x < S().width && oy + y < S().height ? at(ox + x, oy + y) : 0);
    status(`Copied spr(${cell}), ${size}×${size}.`);
  }
  function paste() {
    if (!clip || !S()) return;
    snapshot();
    for (let y = 0; y < clip.size; y++) for (let x = 0; x < clip.size; x++) put(x, y, clip.px[y * clip.size + x]);
    touched();
  }

  addEventListener("keydown", (e) => {
    if (!root.classList.contains("on") || /INPUT|TEXTAREA|SELECT/.test(document.activeElement?.tagName)) return;
    const k = e.key.toLowerCase();
    if (e.ctrlKey && k === "z") { e.preventDefault(); step(undo, redo); }
    else if (e.ctrlKey && k === "y") { e.preventDefault(); step(redo, undo); }
    else if (e.ctrlKey && k === "c") copy();
    else if (e.ctrlKey && k === "v") paste();
    else if (e.ctrlKey && k === "s") { e.preventDefault(); save(); }
    else if (!e.ctrlKey && { p: "pen", f: "fill", l: "line", r: "rect", k: "pick", e: "erase" }[k])
      setTool({ p: "pen", f: "fill", l: "line", r: "rect", k: "pick", e: "erase" }[k]);
    else if (S() && ["arrowleft", "arrowright", "arrowup", "arrowdown"].includes(k)) {
      e.preventDefault();
      const n = cols() * (S().height / 8), stepBy = size / 8;
      cell = { arrowleft: cell - stepBy, arrowright: cell + stepBy, arrowup: cell - cols() * stepBy,
               arrowdown: cell + cols() * stepBy }[k];
      cell = Math.max(0, Math.min(n - 1, cell));
      draw();
    }
  });

  // ---- files -------------------------------------------------------------------
  async function open() {
    if (!files.value) return;
    if (S()?.dirty && !confirm(`${S().path} has changes that are not saved. Open another anyway?`)) return;
    try {
      const moved = await loadSheet(files.value);
      undo.length = redo.length = 0;
      cell = 0;
      const s = S(), cells = (s.width >> 3) * (s.height >> 3);
      // SPEC §2: width and height multiples of 8, at most 128 KB of pixels
      if (s.width % 8 || s.height % 8) status(`${s.path} is ${s.width}×${s.height}: pack needs both multiples of 8.`, true);
      else if (s.width * s.height > 131072) status(`${s.path} is ${s.width}×${s.height}, ${Math.round(s.width * s.height / 1024)} KB of pixels: a sheet holds at most 128 KB.`, true);
      else status((moved ? `${files.value}: ${moved} pixels were not in the palette and took the nearest colour. `
                         : `Opened ${files.value}. `) + `${s.width}×${s.height}: spr(0) to spr(${cells - 1}).`);
    } catch (e) { status(e.message, true); }
  }
  async function newSheet() {
    const name = prompt("File name for the new sheet", "sprites.png");
    if (!name) return;
    if (!/^[\w-]+(\/[\w-]+)*\.png$/.test(name)) return status("A sheet's name ends in .png", true);
    if (shared.files.includes(name) && !confirm(`${name} exists. Replace it with a blank sheet?`)) return;
    const w = +prompt("Width in pixels (a multiple of 8)", "128"), hh = +prompt("Height in pixels (a multiple of 8)", "128");
    if (!(w > 0 && hh > 0 && w % 8 === 0 && hh % 8 === 0 && w * hh <= 131072))
      return status("Width and height are multiples of 8, and a sheet holds at most 128 KB of pixels.", true);
    shared.sheet = { path: name, width: w, height: hh, pixels: new Uint8Array(w * hh), dirty: true };
    cell = 0;
    shared.changed("sheet");
    await save();
  }
  async function save() {
    if (!S()) return;
    try {
      await saveSheet();
      await refreshFiles();
      status(`Saved ${S().path}.`);
    } catch (e) { status("Not saved: " + e.message, true); }
  }

  shared.listeners.push((what) => {
    if (what === "files") {
      const was = files.value;
      files.replaceChildren(...shared.files.filter((f) => f.endsWith(".png")).map((f) => h("option", { value: f }, f)));
      if (was) files.value = was;
    }
    if (what === "sheet") { if (S()) files.value = S().path; draw(); }
  });
  shared.dirtyChecks.push(() => S()?.dirty);
  paintSwatches();
  draw();
}
