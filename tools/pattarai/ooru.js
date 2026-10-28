// Ooru: the map editor. Opens and saves Tiled maps (.tmx), which `pulli
// pack` turns into .ooru; their tiles are the game's sprite sheet, so tile
// n is spr(n), and tile 0 is empty. Two layers, as the console draws.
import { FOLDERS, place, inFolder } from "./lib/layout.js";
import { api, h, shared, status, refreshFiles } from "./app.js";
import { parseTMX, writeTMX, newTMX, newTSX, parseTSX, setTileFlags, parseObjects, writeObjects, objectTop } from "./lib/tmx.js";

export function ooru(root) {
  let map = null, path = "", layer = 0, tool = "paint", zoom = 3, flipX = false, flipY = false, dirty = false;
  let brush = { w: 1, h: 1, cells: [1] };
  const shown = [true, true];
  const undo = [], redo = [];
  let tiles = null;                                        // the sheet drawn once, see-through kept
  let tsx = null, tsxPath = "", tsxDirty = false, showFlags = false;   // the tileset: each tile's flags
  // objects, on object layers: what map.objects() gives the game
  let groups = [], group = 0, chosen = null, showObjects = true, snap = true;

  const files = h("select", { title: "Maps in the game folder", "data-empty": "no maps yet: New…" });
  const canvas = h("canvas");
  const picker = h("canvas");
  const info = h("span", { className: "muted" });
  const layerButtons = ["Layer 0", "Layer 1"].map((label, n) => h("button", { onclick: () => { layer = n; bar(); } }, label));
  const eyes = ["show 0", "show 1"].map((label, n) => h("label", {}, h("input", { type: "checkbox", checked: true,
    onchange: (e) => { shown[n] = e.target.checked; draw(); } }), label));
  const tools = {};
  // rect: drag a box and fill it with the brush (repeated); copy: drag a box
  // of the map and it becomes the brush
  for (const [k, label] of [["paint", "✎ Paint"], ["rect", "▭ Box"], ["fill", "◧ Fill"], ["erase", "⌫ Erase"],
                            ["pick", "⊙ Pick"], ["copy", "⧉ Copy"], ["object", "◆ Objects"]])
    tools[k] = h("button", { onclick: () => { tool = k; bar(); } }, label);
  const fx = h("button", { title: "Place tiles turned over left to right (X)", onclick: () => { flipX = !flipX; bar(); } }, "⇋ Flip");
  const fy = h("button", { title: "Place tiles turned over top to bottom (Y)", onclick: () => { flipY = !flipY; bar(); } }, "⇵ Flip");
  const flagBox = h("div");
  const objectBox = h("div");
  const objectsEye = h("label", {}, h("input", { type: "checkbox", checked: true,
    onchange: (e) => { showObjects = e.target.checked; draw(); } }), "show objects");
  const flagsEye = h("label", {}, h("input", { type: "checkbox", onchange: (e) => { showFlags = e.target.checked; draw(); } }), "show flags");
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
      h("label", {}, "zoom", zoomSel), flagsEye, objectsEye, info),
    h("div", { className: "cols", style: "flex-wrap:nowrap" },
      h("div", { className: "box wide", style: "min-width:0" }, h("h3", {}, "Map"), h("div", { className: "scroll" }, canvas)),
      h("div", { className: "box", style: "width:420px;flex:none" }, h("h3", {}, "Tiles"),
        h("p", { className: "muted", style: "margin:0 0 6px;max-width:400px" },
          "The tiles are the picture open in Kolam: tile n is spr(n). Drag across tiles to paint with a block of them."),
        h("div", { className: "scroll", style: "max-height:calc(100vh - 360px)" }, picker), flagBox, objectBox)));

  function bar() {
    layerButtons.forEach((b, i) => b.classList.toggle("on", i === layer));
    for (const [k, b] of Object.entries(tools)) b.classList.toggle("on", k === tool);
    fx.classList.toggle("on", flipX);
    fy.classList.toggle("on", flipY);
    drawObjectBox();
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
    if (showFlags && tsx) {                              // tiles with flags: solid red, the rest numbered
      g.font = `${Math.max(7, 3 * zoom)}px monospace`; g.textBaseline = "top";
      for (let y = 0; y < map.height; y++) for (let x = 0; x < map.width; x++) {
        let f = 0;
        for (const l of map.layers.slice(0, 2)) f |= tsx.flags.get(l.cells[y * map.width + x] & 0x3fff) || 0;
        if (!f) continue;
        g.fillStyle = f & 1 ? "#e5604f88" : "#4fb3a966";
        g.fillRect(x * 8 * zoom, y * 8 * zoom, 8 * zoom, 8 * zoom);
        if (f > 1 && zoom >= 3) { g.fillStyle = "#fff"; g.fillText(String(f), x * 8 * zoom + 1, y * 8 * zoom + 1); }
      }
    }
    if (zoom >= 2) {
      g.strokeStyle = "#ffffff10";
      for (let x = 0; x <= map.width; x++) { g.beginPath(); g.moveTo(x * 8 * zoom, 0); g.lineTo(x * 8 * zoom, canvas.height); g.stroke(); }
      for (let y = 0; y <= map.height; y++) { g.beginPath(); g.moveTo(0, y * 8 * zoom); g.lineTo(canvas.width, y * 8 * zoom); g.stroke(); }
    }
    if (showObjects) drawObjects(g);
    g.strokeStyle = "#f0a33066";                         // the screen, 40x30 tiles, from the top left
    g.strokeRect(0, 0, 40 * 8 * zoom, 30 * 8 * zoom);
    if (tool === "object") {
      if (making && pxHover) {
        const [ax, ay, w, hh] = pxBox(making, pxHover);
        g.strokeStyle = "#5fb3f3"; g.setLineDash([4, 3]);
        g.strokeRect(ax * zoom, ay * zoom, Math.max(1, w * zoom), Math.max(1, hh * zoom));
        g.setLineDash([]);
      }
    } else if (boxFrom && hover) {
      const [ax, ay, w, hh] = boxOf(boxFrom, hover);
      g.fillStyle = "#f0a33030"; g.fillRect(ax * 8 * zoom, ay * 8 * zoom, w * 8 * zoom, hh * 8 * zoom);
      g.strokeStyle = "#f0a330"; g.strokeRect(ax * 8 * zoom, ay * 8 * zoom, w * 8 * zoom, hh * 8 * zoom);
    } else if (hover) {
      g.strokeStyle = "#f0a330";
      g.strokeRect(hover[0] * 8 * zoom, hover[1] * 8 * zoom, brush.w * 8 * zoom, brush.h * 8 * zoom);
    }
    info.textContent = `${path}${dirty ? " •" : ""}  ${map.width}×${map.height}` +
      (tool === "object" && pxHover ? `  x ${pxHover[0]}, y ${pxHover[1]}` :
       hover ? `  tile ${hover[0]},${hover[1]}: ${map.layers[layer]?.cells[hover[1] * map.width + hover[0]] & 0x3fff}` : "");
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

  // The flags of the tile in hand (the brush's first), as pack reads them
  function drawFlags() {
    if (!tsx) {
      flagBox.replaceChildren(h("p", { className: "muted" }, map ? `No tileset to keep flags in (${tsxPath || "none"}).` : ""));
      return;
    }
    const n = brush.cells[0] & 0x3fff, v = tsx.flags.get(n) || 0;
    flagBox.replaceChildren(
      h("h3", { style: "margin:10px 0 4px" }, `Flags of tile ${n} = ${v}`, tsxDirty ? " •" : ""),
      h("div", { className: "bar", style: "gap:4px 12px" }, ...[0, 1, 2, 3, 4, 5, 6, 7].map((b) =>
        h("label", { title: b ? `bit ${b}: map.flags(tile) & ${1 << b}` : "bit 0: solid (map.flags(tile) & 1)" },
          h("input", { type: "checkbox", checked: !!(v & (1 << b)), onchange: (e) => {
            const now = e.target.checked ? v | (1 << b) : v & ~(1 << b);
            tsx.text = setTileFlags(tsx.text, n, now);
            Object.assign(tsx, parseTSX(tsx.text));
            tsxDirty = true;
            drawFlags(); draw();
          } }), b ? String(b) : "0 solid"))),
      h("p", { className: "muted", style: "margin:4px 0 0;font-size:12px" },
        `Kept in ${tsxPath}, saved with the map. The game reads them with map.flags(tile).`));
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
    if (tool === "copy") tool = "paint";
    if (!["paint", "fill", "rect"].includes(tool)) tool = "paint";
    bar();
    drawPicker();
    drawFlags();
  }

  // ---- editing -----------------------------------------------------------------
  const state = () => ({ cells: map.layers.map((l) => l.cells.slice()), groups: structuredClone(groups) });
  function snapshot() {
    undo.push(state());
    if (undo.length > 100) undo.shift();
    redo.length = 0;
  }
  function step(from, to) {
    if (!from.length || !map) return;
    to.push(state());
    const was = from.pop();
    was.cells.forEach((c, i) => { map.layers[i].cells = c; });
    groups = was.groups;
    group = Math.min(group, Math.max(0, groups.length - 1));
    chosen = chosen && groups[group]?.objects.find((o) => o.id === chosen.id) || null;
    dirty = true;
    draw(); drawObjectBox();
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
      const c = brush.cells[sy * brush.w + sx];
      if (tx < map.width && ty < map.height) cells[ty * map.width + tx] = brush.raw ? c ^ (flipX ? 0x8000 : 0) ^ (flipY ? 0x4000 : 0) : placed(c);
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

  let painting = false, hover = null, boxFrom = null;
  const boxOf = ([x0, y0], [x1, y1]) => [Math.min(x0, x1), Math.min(y0, y1), Math.abs(x1 - x0) + 1, Math.abs(y1 - y0) + 1];
  function boxDone(to) {
    const [ax, ay, w, hh] = boxOf(boxFrom, to);
    boxFrom = null;
    const cells = map.layers[layer].cells;
    if (tool === "copy") {                      // the region, flips and all, becomes the brush
      brush = { w, h: hh, cells: [], raw: true };
      for (let y = 0; y < hh; y++) for (let x = 0; x < w; x++)
        brush.cells.push(ax + x < map.width && ay + y < map.height ? cells[(ay + y) * map.width + ax + x] : 0);
      tool = "paint"; flipX = flipY = false;
      bar(); drawPicker(); drawFlags();
      status(`Copied ${w}×${hh} tiles of layer ${layer}: paint with them.`);
    } else {                                    // the box filled with the brush, repeated
      snapshot();
      for (let y = 0; y < hh; y++) for (let x = 0; x < w; x++) {
        const bx = flipX ? brush.w - 1 - (x % brush.w) : x % brush.w, by = flipY ? brush.h - 1 - (y % brush.h) : y % brush.h;
        const c = brush.cells[by * brush.w + bx];
        if (ax + x < map.width && ay + y < map.height) cells[(ay + y) * map.width + ax + x] = brush.raw ? c : placed(c);
      }
      dirty = true;
    }
    draw();
  }
  const cellOf = (e) => [Math.floor(e.offsetX / 8 / zoom), Math.floor(e.offsetY / 8 / zoom)];
  canvas.addEventListener("contextmenu", (e) => e.preventDefault());
  canvas.addEventListener("mousedown", (e) => {
    if (map && tool === "object") return objectDown(e);
    if (!map || !map.layers[layer]) return;
    const [x, y] = cellOf(e);
    if (e.button === 2 || tool === "pick") {
      const c = map.layers[layer].cells[y * map.width + x];
      brush = { w: 1, h: 1, cells: [c & 0x3fff] };
      flipX = !!(c & 0x8000); flipY = !!(c & 0x4000);
      if (tool === "pick") tool = "paint";
      bar(); drawPicker(); drawFlags();
      return;
    }
    if (tool === "rect" || tool === "copy") { boxFrom = [x, y]; draw(); return; }
    snapshot();
    if (tool === "fill") { fillAt(x, y, placed(brush.cells[0] & 0x3fff)); dirty = true; draw(); return; }
    painting = true;
    act(x, y);
    draw();
  });
  canvas.addEventListener("mousemove", (e) => {
    if (!map) return;
    if (tool === "object") return objectMove(e);
    const c = cellOf(e);
    if (hover && c[0] === hover[0] && c[1] === hover[1]) return;
    hover = c;
    if (painting) act(...c);
    draw();
  });
  canvas.addEventListener("mouseleave", () => { hover = null; draw(); });
  addEventListener("mouseup", () => {
    painting = false; if (boxFrom && hover) boxDone(hover); boxFrom = null;
    if (making || moving) objectUp();
  });

  addEventListener("keydown", (e) => {
    if (!root.classList.contains("on") || /INPUT|TEXTAREA|SELECT/.test(document.activeElement?.tagName)) return;
    const k = e.key.toLowerCase();
    if (e.ctrlKey && k === "z") { e.preventDefault(); step(undo, redo); }
    else if (e.ctrlKey && k === "y") { e.preventDefault(); step(redo, undo); }
    else if (e.ctrlKey && k === "s") { e.preventDefault(); save(); }
    else if ((k === "delete" || k === "backspace") && tool === "object" && chosen) { e.preventDefault(); removeChosen(); }
    else if (k === "x") { flipX = !flipX; bar(); }
    else if (k === "y") { flipY = !flipY; bar(); }
    else if (k === "1" || k === "2") { layer = +k - 1; bar(); draw(); }
    else if ({ p: 1, f: 1, e: 1, k: 1, r: 1, c: 1, o: 1 }[k] && !e.ctrlKey) {
      tool = { p: "paint", f: "fill", e: "erase", k: "pick", r: "rect", c: "copy", o: "object" }[k]; bar(); draw();
    }
  });

  // ---- objects ------------------------------------------------------------------
  // On the Objects tool: click to place a point, drag to place a box, drag an
  // object to move it, Delete to remove it. Positions are in pixels, snapped
  // to whole tiles unless "snap" is off; the panel sets names and properties.
  let making = null, moving = null, pxHover = null;
  const pxOf = (e, exact) => {
    const x = Math.floor(e.offsetX / zoom), y = Math.floor(e.offsetY / zoom);
    return snap && !exact ? [Math.round(x / 8) * 8, Math.round(y / 8) * 8] : [x, y];
  };
  const pxBox = ([x0, y0], [x1, y1]) => [Math.min(x0, x1), Math.min(y0, y1), Math.abs(x1 - x0), Math.abs(y1 - y0)];
  const nextId = () => Math.max(0, ...groups.flatMap((g) => g.objects.map((o) => o.id)),
    (+(map.text.match(/<map\b[^>]*\snextobjectid="(\d+)"/) || [0, 1])[1]) - 1) + 1;

  function hit(o, x, y) {
    const top = objectTop(o);
    if (!o.w && !o.h) return Math.abs(x - o.x) <= 4 / zoom + 3 && Math.abs(y - o.y) <= 4 / zoom + 3;
    return x >= o.x - 2 && x <= o.x + o.w + 2 && y >= top - 2 && y <= top + o.h + 2;
  }
  function objectDown(e) {
    if (e.button === 2) return;
    const [x, y] = pxOf(e, true);
    const g = groups[group];
    const found = g && [...g.objects].reverse().find((o) => hit(o, x, y));
    if (found) {
      chosen = found;
      snapshot();
      moving = { o: found, dx: x - found.x, dy: y - found.y, moved: false };
    } else {
      chosen = null;
      making = pxHover = pxOf(e);                  // a click with no move places a point here
    }
    drawObjectBox(); draw();
  }
  function objectMove(e) {
    pxHover = pxOf(e);
    if (moving) {
      const [x, y] = pxOf(e, true);
      let nx = x - moving.dx, ny = y - moving.dy;
      if (snap) { nx = Math.round(nx / 8) * 8; ny = Math.round(ny / 8) * 8 + (moving.o.gid ? moving.o.h % 8 : 0); }
      if (nx !== moving.o.x || ny !== moving.o.y) {
        moving.o.x = nx; moving.o.y = ny; moving.o.changed = true; moving.moved = true; dirty = true;
        drawObjectBox();
      }
    }
    draw();
  }
  function objectUp() {
    if (moving) {
      if (!moving.moved) undo.pop();
      moving = null;
    } else if (making && pxHover) {
      const [x, y, w, hh] = pxBox(making, pxHover);
      making = null;
      if (!groups.length) { snapshot(); groups.push({ name: "objects", open: "", objects: [] }); group = 0; }
      else snapshot();
      const o = { id: nextId(), name: "", type: "", x, y, w, h: hh, gid: null, point: !w && !hh, props: [], changed: true };
      groups[group].objects.push(o);
      chosen = o;
      dirty = true;
      status(o.point ? `A point at ${x}, ${y}: name it, give it a class and properties.` :
        `A box ${w}×${hh} at ${x}, ${y}: name it, give it a class and properties.`);
    }
    making = null;
    drawObjectBox(); draw();
  }
  function removeChosen() {
    if (!chosen) return;
    snapshot();
    const g = groups[group];
    g.objects = g.objects.filter((o) => o !== chosen);
    chosen = null; dirty = true;
    drawObjectBox(); draw();
  }

  function drawObjects(g) {
    g.font = `${Math.max(9, 3 * zoom)}px sans-serif`; g.textBaseline = "bottom";
    groups.forEach((gr, gi) => {
      const mine = gi === group;
      for (const o of gr.objects) {
        const top = objectTop(o), x = o.x * zoom, y = top * zoom;
        const colour = o === chosen ? "#ffd166" : mine ? "#5fb3f3" : "#5fb3f366";
        if (o.gid) {
          const cell = ((o.gid & 0x0fffffff) - map.firstgid) | (o.gid & 0x80000000 ? 0x8000 : 0) | (o.gid & 0x40000000 ? 0x4000 : 0);
          g.save(); g.translate(x, y); g.scale(o.w / 8 || 1, o.h / 8 || 1);
          drawTile(g, cell, 0, 0, zoom); g.restore();
        }
        g.strokeStyle = colour; g.lineWidth = o === chosen ? 2 : 1;
        if (!o.w && !o.h) {
          const r = Math.max(4, 2 * zoom);
          g.beginPath(); g.moveTo(x, y - r); g.lineTo(x + r, y); g.lineTo(x, y + r); g.lineTo(x - r, y); g.closePath();
          g.fillStyle = colour + (colour.length > 7 ? "" : "55"); g.fill(); g.stroke();
        } else g.strokeRect(x + 0.5, y + 0.5, o.w * zoom, o.h * zoom);
        g.lineWidth = 1;
        const label = o.name || o.type;
        if (label && zoom >= 2) {
          g.fillStyle = "#000a"; g.fillText(label, x + 2, y - 1);
          g.fillStyle = colour; g.fillText(label, x + 1, y - 2);
        }
      }
    });
  }

  // The panel: the object layers, and the chosen object's name, class,
  // position and properties
  function drawObjectBox() {
    if (!map || tool !== "object") { objectBox.replaceChildren(); return; }
    const changed = () => { if (chosen) chosen.changed = true; dirty = true; draw(); };
    const layerSel = h("select", { onchange: (e) => { group = +e.target.value; chosen = null; drawObjectBox(); draw(); } },
      ...groups.map((g, i) => h("option", { value: i, selected: i === group }, `${g.name || "(no name)"} · ${g.objects.length}`)));
    const parts = [
      h("h3", { style: "margin:10px 0 4px" }, "Objects"),
      h("div", { className: "bar", style: "gap:6px" }, groups.length ? layerSel : h("span", { className: "muted" }, "No object layer yet."),
        h("button", { onclick: () => {
          const name = prompt("Name of the new object layer (the game reads it as map.objects(name))", groups.length ? "" : "spawns");
          if (name == null) return;
          snapshot(); groups.push({ name, open: "", objects: [] }); group = groups.length - 1; chosen = null; dirty = true;
          drawObjectBox(); draw();
        } }, "+ Layer"),
        groups.length ? h("button", { onclick: () => {
          const name = prompt("Rename this object layer", groups[group].name);
          if (name == null) return;
          snapshot(); groups[group].name = name; dirty = true; drawObjectBox();
        } }, "Rename") : "",
        h("label", { title: "Place and move objects on whole tiles (8 pixels)" },
          h("input", { type: "checkbox", checked: snap, onchange: (e) => { snap = e.target.checked; } }), "snap")),
      h("p", { className: "muted", style: "margin:4px 0;font-size:12px" },
        "Click to place a point, drag for a box, drag an object to move it, Delete to remove it. " +
        "The game reads them with map.objects()."),
    ];
    if (chosen) {
      const field = (label, key, number) => h("label", { style: "display:flex;gap:6px;align-items:center" }, label,
        h("input", { value: chosen[key], style: number ? "width:64px" : "width:150px", type: number ? "number" : "text",
          onfocus: () => snapshot(),
          oninput: (e) => {
            chosen[key] = number ? Math.round(+e.target.value || 0) : e.target.value;
            if (number && (key === "w" || key === "h")) chosen.point = !chosen.w && !chosen.h && !chosen.gid;
            changed();
          } }));
      const props = chosen.props.map((p, i) => h("div", { className: "bar", style: "gap:4px" },
        h("input", { value: p.name, placeholder: "name", style: "width:90px", onfocus: () => snapshot(),
          oninput: (e) => { p.name = e.target.value; changed(); } }),
        h("select", { onchange: (e) => { snapshot(); p.type = e.target.value;
          if (p.type === "bool") p.value = p.value === "true" ? "true" : "false";
          changed(); drawObjectBox(); } },
          ...[["string", "text"], ["int", "whole number"], ["float", "number"], ["bool", "true/false"]].map(([v, l]) =>
            h("option", { value: v, selected: (p.type || "string") === v }, l))),
        p.type === "bool"
          ? h("input", { type: "checkbox", checked: p.value === "true", onchange: (e) => { snapshot(); p.value = String(e.target.checked); changed(); } })
          : h("input", { value: p.value, style: "width:100px", type: p.type === "int" || p.type === "float" ? "number" : "text",
              step: p.type === "float" ? "any" : "1", onfocus: () => snapshot(),
              oninput: (e) => { p.value = e.target.value; changed(); } }),
        h("button", { title: "Remove this property", onclick: () => { snapshot(); chosen.props.splice(i, 1); changed(); drawObjectBox(); } }, "✕")));
      parts.push(
        h("div", { style: "display:grid;gap:4px;margin-top:6px" },
          h("div", { className: "bar", style: "gap:8px" }, field("name", "name"), field("class", "type")),
          h("div", { className: "bar", style: "gap:8px" }, field("x", "x", 1), field("y", "y", 1), field("w", "w", 1), field("h", "h", 1)),
          h("b", { style: "font-size:12px;margin-top:4px" }, "Properties"),
          ...props,
          h("div", { className: "bar", style: "gap:6px" },
            h("button", { onclick: () => { snapshot(); chosen.props.push({ name: "", type: "string", value: "" }); changed(); drawObjectBox(); } }, "+ Property"),
            h("button", { onclick: removeChosen }, "Remove object"))));
    } else if (groups[group]) {
      parts.push(h("div", { style: "display:grid;gap:2px;max-height:180px;overflow:auto" },
        ...groups[group].objects.map((o) => h("button", { style: "text-align:left",
          onclick: () => { chosen = o; drawObjectBox(); draw(); } },
          `${o.name || "(no name)"}${o.type ? " · " + o.type : ""}  ${o.x}, ${objectTop(o)}${o.w || o.h ? `  ${o.w}×${o.h}` : ""}`))));
    }
    objectBox.replaceChildren(...parts);
  }

  // ---- files -------------------------------------------------------------------
  async function open() {
    if (!files.value) return;
    if (dirty && !confirm(`${path} has changes that are not saved. Open another anyway?`)) return;
    try {
      if (tsxDirty && !confirm(`${tsxPath} has flags that are not saved. Open another map anyway?`)) return;
      map = parseTMX(await api.readText(files.value));
      groups = parseObjects(map.text); group = 0; chosen = null;
      path = files.value;
      await loadTileset();
      dirty = false;
      undo.length = redo.length = 0;
      layer = 0;
      const cells = map.width * map.height * Math.min(2, map.layers.length);
      if (cells > 32768) status(`${path} has ${cells} cells in its layers; a map holds at most 32,768 (SPEC §2).`, true);
      else if (map.layers.length > 2) status(`${path} has ${map.layers.length} layers; the console takes the first two.`);
      else status(`Opened ${path}: ${map.width}×${map.height} tiles, ${map.layers.length} layer${map.layers.length > 1 ? "s" : ""}.`);
      bar(); draw();
    } catch (e) { status(`${files.value}: ${e.message}`, true); }
  }
  async function loadTileset() {
    const dir = path.includes("/") ? path.slice(0, path.lastIndexOf("/") + 1) : "";
    tsxPath = map.tileset ? dir + map.tileset : "";
    tsx = null; tsxDirty = false;
    if (tsxPath && shared.files.includes(tsxPath)) {
      try {
        const text = await api.readText(tsxPath);
        tsx = { text, ...parseTSX(text) };
      } catch (e) { status(`${tsxPath}: ${e.message}`, true); }
    }
    drawFlags();
  }

  async function create() {
    let name = prompt("File name for the new map (kept in maps/)", "map.tmx");
    if (!name) return;
    if (!/^[\w-]+\.tmx$/.test(name)) return status("A map's name ends in .tmx; it is kept in maps/.", true);
    name = place(FOLDERS.maps, name);
    if (shared.files.includes(name) && !confirm(`${name} exists. Replace it?`)) return;
    const w = +prompt("Width in tiles (40 is one screen)", "40"), hh = +prompt("Height in tiles (30 is one screen)", "30");
    if (!(w > 0 && hh > 0 && w * hh * 2 <= 32768)) return status("A map holds at most 32,768 cells over both its layers.", true);
    map = newTMX(w, hh, 2);
    groups = []; group = 0; chosen = null;
    path = name;
    dirty = true;
    undo.length = redo.length = 0;
    const tileset = place(FOLDERS.maps, "sprites.tsx");
    if (!shared.files.includes(tileset) && shared.sheet) {
      await api.write(tileset, newTSX(shared.sheet.width, shared.sheet.height, "../" + shared.sheet.path));
      await refreshFiles();
    }
    await loadTileset();
    await save();
  }
  async function save() {
    if (!map) return;
    try {
      const text = writeObjects(writeTMX(map), groups);
      await api.write(path, text);
      if (tsx && tsxDirty) { await api.write(tsxPath, tsx.text); tsxDirty = false; drawFlags(); }
      map.text = text;
      const keep = chosen && chosen.id;              // what was written is now as Tiled would read it
      groups = parseObjects(text);
      chosen = keep ? groups[group]?.objects.find((o) => o.id === keep) || null : null;
      drawObjectBox();
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
      files.replaceChildren(...inFolder(shared.files, FOLDERS.maps, ".tmx").map((f) => h("option", { value: f }, f)));
      if (was) files.value = was;
    }
    if (what === "sheet" || what === "pixels") { buildTiles(); drawPicker(); draw(); }
  });
  shared.dirtyChecks.push(() => dirty || tsxDirty);
  draw();
}
