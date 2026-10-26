// Ooru: the map editor. Opens and saves Tiled maps (.tmx), which `pulli
// pack` turns into .ooru; their tiles are the game's sprite sheet, so tile
// n is spr(n), and tile 0 is empty. Two layers, as the console draws.
import { api, h, shared, status, refreshFiles } from "./app.js";
import { parseTMX, writeTMX, newTMX, newTSX } from "./lib/tmx.js";

export function ooru(root) {
  let map = null, path = "", layer = 0, tool = "paint", zoom = 3, flipX = false, flipY = false, dirty = false;
  let brush = { w: 1, h: 1, cells: [1] };
  const shown = [true, true];
  const undo = [], redo = [];
  let tiles = null;                                        // the sheet drawn once, see-through kept

  const files = h("select", { title: "Maps in the game folder" });
  const canvas = h("canvas");
  const picker = h("canvas");
  const info = h("span", { className: "muted" });
  const layerButtons = [0, 1].map((n) => h("button", { onclick: () => { layer = n; bar(); } }, `Layer ${n}`));
  const eyes = [0, 1].map((n) => h("label", {}, h("input", { type: "checkbox", checked: true,
    onchange: (e) => { shown[n] = e.target.checked; draw(); } }), `show ${n}`));
  const tools = {};
  for (const [k, label] of [["paint", "✎ Paint"], ["fill", "◧ Fill"], ["erase", "⌫ Erase"], ["pick", "⊙ Pick"]])
    tools[k] = h("button", { onclick: () => { tool = k; bar(); } }, label);
  const fx = h("button", { title: "Place tiles turned over left to right (X)", onclick: () => { flipX = !flipX; bar(); } }, "⇋ Flip");
  const fy = h("button", { title: "Place tiles turned over top to bottom (Y)", onclick: () => { flipY = !flipY; bar(); } }, "⇵ Flip");
  const zoomSel = h("select", { onchange: () => { zoom = +zoomSel.value; draw(); } },
    ...[1, 2, 3, 4, 6].map((n) => h("option", { value: n, selected: n === zoom }, `${n}×`)));

  root.append(
    h("div", { className: "bar" }, files,
      h("button", { onclick: open }, "Open"),
      h("button", { onclick: create }, "New…"),
      h("button", { onclick: save }, "Save"),
      h("span", { className: "sep" }), ...layerButtons, ...eyes,
      h("span", { className: "sep" }), ...Object.values(tools), fx, fy,
      h("span", { className: "sep" }),
      h("button", { title: "Undo (Ctrl+Z)", onclick: () => step(undo, redo) }, "↶"),
      h("button", { title: "Redo (Ctrl+Y)", onclick: () => step(redo, undo) }, "↷"),
      h("label", {}, "zoom", zoomSel), info),
    h("div", { className: "cols" },
      h("div", { className: "box wide" }, h("h3", {}, "Map"), h("div", { className: "scroll" }, canvas)),
      h("div", { className: "box" }, h("h3", {}, "Tiles"),
        h("p", { className: "muted", style: "margin:0 0 6px;max-width:400px" },
          "The tiles are the picture open in Kolam: tile n is spr(n). Drag across tiles to paint with a block of them."),
        h("div", { className: "scroll", style: "max-height:calc(100vh - 230px)" }, picker))));

  function bar() {
    layerButtons.forEach((b, i) => b.classList.toggle("on", i === layer));
    for (const [k, b] of Object.entries(tools)) b.classList.toggle("on", k === tool);
    fx.classList.toggle("on", flipX);
    fy.classList.toggle("on", flipY);
  }
  bar();

  // ---- the tiles: the sheet as an image --------------------------------------
  function buildTiles() {
    const s = shared.sheet;
    if (!s) { tiles = null; return; }
    const img = new ImageData(s.width, s.height);
    for (let i = 0; i < s.pixels.length; i++) {
      const p = s.pixels[i];
      if (!p) continue;
      const c = shared.palette[p];
      img.data.set([c >> 16, (c >> 8) & 255, c & 255, 255], i * 4);
    }
    tiles = new OffscreenCanvas(s.width, s.height);
    tiles.getContext("2d").putImageData(img, 0, 0);
  }
  const cols = () => shared.sheet.width / 8;

  function drawTile(g, cell, x, y, z) {
    const n = cell & 0x3fff;
    if (!n || !tiles) return;
    const sx = (n % cols()) * 8, sy = Math.floor(n / cols()) * 8;
    if (sy >= shared.sheet.height) return;
    g.save();
    g.translate(x + (cell & 0x8000 ? 8 * z : 0), y + (cell & 0x4000 ? 8 * z : 0));
    g.scale(cell & 0x8000 ? -1 : 1, cell & 0x4000 ? -1 : 1);
    g.drawImage(tiles, sx, sy, 8, 8, 0, 0, 8 * z, 8 * z);
    g.restore();
  }

  function draw() {
    if (!map) { info.textContent = "(open or make a map)"; return; }
    canvas.width = map.width * 8 * zoom; canvas.height = map.height * 8 * zoom;
    const g = canvas.getContext("2d");
    g.imageSmoothingEnabled = false;
    g.fillStyle = "#1b1c24";
    g.fillRect(0, 0, canvas.width, canvas.height);
    map.layers.forEach((l, i) => {
      if (!shown[i]) return;
      g.globalAlpha = i === layer || map.layers.length === 1 ? 1 : 0.55;
      for (let y = 0; y < map.height; y++) for (let x = 0; x < map.width; x++)
        drawTile(g, l.cells[y * map.width + x], x * 8 * zoom, y * 8 * zoom, zoom);
    });
    g.globalAlpha = 1;
    if (zoom >= 2) {
      g.strokeStyle = "#ffffff10";
      for (let x = 0; x <= map.width; x++) { g.beginPath(); g.moveTo(x * 8 * zoom, 0); g.lineTo(x * 8 * zoom, canvas.height); g.stroke(); }
      for (let y = 0; y <= map.height; y++) { g.beginPath(); g.moveTo(0, y * 8 * zoom); g.lineTo(canvas.width, y * 8 * zoom); g.stroke(); }
    }
    g.strokeStyle = "#f0a33066";                         // the screen, 40x30 tiles, from the top left
    g.strokeRect(0, 0, 40 * 8 * zoom, 30 * 8 * zoom);
    if (hover) {
      g.strokeStyle = "#f0a330";
      g.strokeRect(hover[0] * 8 * zoom, hover[1] * 8 * zoom, brush.w * 8 * zoom, brush.h * 8 * zoom);
    }
    info.textContent = `${path}${dirty ? " •" : ""}  ${map.width}×${map.height}` +
      (hover ? `  tile ${hover[0]},${hover[1]}: ${map.layers[layer]?.cells[hover[1] * map.width + hover[0]] & 0x3fff}` : "");
  }

  function drawPicker() {
    const s = shared.sheet;
    if (!s) return;
    const z = 3;
    picker.width = s.width * z; picker.height = s.height * z;
    const g = picker.getContext("2d");
    g.imageSmoothingEnabled = false;
    if (tiles) g.drawImage(tiles, 0, 0, picker.width, picker.height);
    g.strokeStyle = "#ffffff14";
    for (let x = 0; x <= s.width; x += 8) { g.beginPath(); g.moveTo(x * z, 0); g.lineTo(x * z, picker.height); g.stroke(); }
    for (let y = 0; y <= s.height; y += 8) { g.beginPath(); g.moveTo(0, y * z); g.lineTo(picker.width, y * z); g.stroke(); }
    const n = brush.cells[0] & 0x3fff;
    g.strokeStyle = "#f0a330"; g.lineWidth = 2;
    g.strokeRect((n % cols()) * 8 * z, Math.floor(n / cols()) * 8 * z, brush.w * 8 * z, brush.h * 8 * z);
    g.lineWidth = 1;
  }

  let pickFrom = null;
  const pickCell = (e) => [Math.floor(e.offsetX / 24), Math.floor(e.offsetY / 24)];
  picker.addEventListener("mousedown", (e) => { if (!shared.sheet) return; pickFrom = pickCell(e); pickTo(e); });
  picker.addEventListener("mousemove", (e) => { if (pickFrom) pickTo(e); });
  addEventListener("mouseup", () => { pickFrom = null; });
  function pickTo(e) {
    const [x1, y1] = pickCell(e), [x0, y0] = pickFrom;
    const ax = Math.min(x0, x1), ay = Math.min(y0, y1), w = Math.abs(x1 - x0) + 1, hh = Math.abs(y1 - y0) + 1;
    brush = { w, h: hh, cells: [] };
    for (let y = 0; y < hh; y++) for (let x = 0; x < w; x++) brush.cells.push((ay + y) * cols() + ax + x);
    if (tool !== "paint" && tool !== "fill") tool = "paint";
    bar();
    drawPicker();
  }

  // ---- editing -----------------------------------------------------------------
  function snapshot() {
    undo.push(map.layers.map((l) => l.cells.slice()));
    if (undo.length > 100) undo.shift();
    redo.length = 0;
  }
  function step(from, to) {
    if (!from.length || !map) return;
    to.push(map.layers.map((l) => l.cells.slice()));
    from.pop().forEach((c, i) => { map.layers[i].cells = c; });
    dirty = true;
    draw();
  }
  function placed(n) {
    if (!n) return 0;
    return n | (flipX ? 0x8000 : 0) | (flipY ? 0x4000 : 0);
  }
  function paintAt(x, y) {
    const cells = map.layers[layer].cells;
    for (let by = 0; by < brush.h; by++) for (let bx = 0; bx < brush.w; bx++) {
      // a flipped block is placed mirrored, so a 16x16 sprite stays whole
      const sx = flipX ? brush.w - 1 - bx : bx, sy = flipY ? brush.h - 1 - by : by;
      const tx = x + bx, ty = y + by;
      if (tx < map.width && ty < map.height) cells[ty * map.width + tx] = placed(brush.cells[sy * brush.w + sx]);
    }
  }
  function fillAt(x, y, value) {
    const cells = map.layers[layer].cells, was = cells[y * map.width + x];
    if (was === value) return;
    const stack = [[x, y]];
    while (stack.length) {
      const [cx, cy] = stack.pop();
      if (cx < 0 || cy < 0 || cx >= map.width || cy >= map.height || cells[cy * map.width + cx] !== was) continue;
      cells[cy * map.width + cx] = value;
      stack.push([cx + 1, cy], [cx - 1, cy], [cx, cy + 1], [cx, cy - 1]);
    }
  }
  function act(x, y) {
    if (tool === "paint") paintAt(x, y);
    else if (tool === "erase") map.layers[layer].cells[y * map.width + x] = 0;
    dirty = true;
  }

  let painting = false, hover = null;
  const cellOf = (e) => [Math.floor(e.offsetX / 8 / zoom), Math.floor(e.offsetY / 8 / zoom)];
  canvas.addEventListener("contextmenu", (e) => e.preventDefault());
  canvas.addEventListener("mousedown", (e) => {
    if (!map || !map.layers[layer]) return;
    const [x, y] = cellOf(e);
    if (e.button === 2 || tool === "pick") {
      const c = map.layers[layer].cells[y * map.width + x];
      brush = { w: 1, h: 1, cells: [c & 0x3fff] };
      flipX = !!(c & 0x8000); flipY = !!(c & 0x4000);
      if (tool === "pick") tool = "paint";
      bar(); drawPicker();
      return;
    }
    snapshot();
    if (tool === "fill") { fillAt(x, y, placed(brush.cells[0])); dirty = true; draw(); return; }
    painting = true;
    act(x, y);
    draw();
  });
  canvas.addEventListener("mousemove", (e) => {
    if (!map) return;
    const c = cellOf(e);
    if (hover && c[0] === hover[0] && c[1] === hover[1]) return;
    hover = c;
    if (painting) act(...c);
    draw();
  });
  canvas.addEventListener("mouseleave", () => { hover = null; draw(); });
  addEventListener("mouseup", () => { painting = false; });

  addEventListener("keydown", (e) => {
    if (!root.classList.contains("on") || /INPUT|TEXTAREA|SELECT/.test(document.activeElement?.tagName)) return;
    const k = e.key.toLowerCase();
    if (e.ctrlKey && k === "z") { e.preventDefault(); step(undo, redo); }
    else if (e.ctrlKey && k === "y") { e.preventDefault(); step(redo, undo); }
    else if (e.ctrlKey && k === "s") { e.preventDefault(); save(); }
    else if (k === "x") { flipX = !flipX; bar(); }
    else if (k === "y") { flipY = !flipY; bar(); }
    else if (k === "1" || k === "2") { layer = +k - 1; bar(); draw(); }
    else if ({ p: 1, f: 1, e: 1, k: 1 }[k]) { tool = { p: "paint", f: "fill", e: "erase", k: "pick" }[k]; bar(); }
  });

  // ---- files -------------------------------------------------------------------
  async function open() {
    if (!files.value) return;
    if (dirty && !confirm(`${path} has changes that are not saved. Open another anyway?`)) return;
    try {
      map = parseTMX(await api.readText(files.value));
      path = files.value;
      dirty = false;
      undo.length = redo.length = 0;
      layer = 0;
      if (map.layers.length > 2) status(`${path} has ${map.layers.length} layers; the console draws the first two.`);
      else status(`Opened ${path}.`);
      bar(); draw();
    } catch (e) { status(`${files.value}: ${e.message}`, true); }
  }
  async function create() {
    const name = prompt("File name for the new map", "map.tmx");
    if (!name) return;
    if (!/^[\w-]+\.tmx$/.test(name)) return status("A map's name ends in .tmx and sits in the game folder.", true);
    if (shared.files.includes(name) && !confirm(`${name} exists. Replace it?`)) return;
    const w = +prompt("Width in tiles (40 is one screen)", "40"), hh = +prompt("Height in tiles (30 is one screen)", "30");
    if (!(w > 0 && hh > 0 && w * hh * 2 <= 32768)) return status("A map holds at most 32,768 cells over both its layers.", true);
    map = newTMX(w, hh, 2);
    path = name;
    dirty = true;
    undo.length = redo.length = 0;
    if (!shared.files.includes("sprites.tsx") && shared.sheet)
      await api.write("sprites.tsx", newTSX(shared.sheet.width, shared.sheet.height));
    await save();
  }
  async function save() {
    if (!map) return;
    try {
      const text = writeTMX(map);
      await api.write(path, text);
      map.text = text;
      dirty = false;
      await refreshFiles();
      files.value = path;
      status(`Saved ${path}.`);
      draw();
    } catch (e) { status("Not saved: " + e.message, true); }
  }

  shared.listeners.push((what) => {
    if (what === "files") {
      const was = files.value;
      files.replaceChildren(...shared.files.filter((f) => f.endsWith(".tmx")).map((f) => h("option", { value: f }, f)));
      if (was) files.value = was;
    }
    if (what === "sheet" || what === "pixels") { buildTiles(); drawPicker(); draw(); }
  });
  shared.dirtyChecks.push(() => dirty);
  draw();
}
