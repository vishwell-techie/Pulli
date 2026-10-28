// Thirai (திரை, "curtain" or "screen"): backdrops, whole-screen pictures, 320 x 240, that backdrop("name.kolam")
// sets and cls() starts each frame from (SPEC §3). Paint one in the game's
// colours, fill a sky with a dithered gradient, or bring in a picture made
// elsewhere, fitted to the screen and put in the 64 colours. A map can be
// shown over it, as the game would draw it, to see the two together.
import { api, h, shared, status, refreshFiles, decodePicture, encodePicture, quantise } from "./app.js";
import { css } from "./lib/palette.js";
import { parseTMX } from "./lib/tmx.js";

const W = 320, H = 240;

export function backdrop(root) {
  let pic = null, path = "", dirty = false, colour = 12, colour2 = 1, tool = "pen", zoom = 3;
  let overlay = null, overlayLayer = -1;
  const undo = [], redo = [];

  const files = h("select", { title: "Pictures in the game folder", "data-empty": "no pictures yet: New…" });
  const canvas = h("canvas", { style: "cursor:crosshair" });
  const info = h("span", { className: "muted" });
  const swatches = h("div", { className: "swatches" });
  const second = h("div", { className: "muted", style: "margin-top:6px" });
  const picker = h("input", { type: "file", accept: "image/*", style: "display:none", onchange: (e) => importFile(e.target.files[0]) });
  const tools = {};
  for (const [k, label] of [["pen", "✎ Pen"], ["fill", "◧ Fill"], ["line", "╱ Line"], ["rect", "▭ Box"], ["solid", "■ Filled box"],
                            ["gradient", "▤ Gradient"], ["pick", "⊙ Pick"]])
    tools[k] = h("button", { onclick: () => { tool = k; bar(); } }, label);
  const brushSel = h("select", { title: "Pen size" }, ...[1, 2, 4, 8].map((n) => h("option", { value: n }, `${n} px`)));
  const ditherBox = h("input", { type: "checkbox", checked: true });
  const mapSel = h("select", { title: "A map drawn over the backdrop, from its top left, as map.draw would",
    onchange: () => loadOverlay() });
  const layerSel = h("select", { onchange: () => { overlayLayer = +layerSel.value; draw(); } },
    h("option", { value: -1 }, "both layers"), h("option", { value: 0 }, "layer 0"), h("option", { value: 1 }, "layer 1"));

  root.append(
    h("div", { className: "bar" }, files,
      h("button", { onclick: open }, "Open"),
      h("button", { onclick: create }, "New…"),
      h("button", { onclick: () => picker.click(), title: "A picture from this computer, fitted to 320 x 240 and put in the game's colours" }, "Import picture…"),
      h("button", { onclick: save }, "Save"), picker,
      h("span", { className: "sep" }), ...Object.values(tools), brushSel,
      h("label", { title: "Gradients and imported pictures mix two colours in a fine pattern for the shades between" }, ditherBox, "dither"),
      h("span", { className: "sep" }),
      h("button", { title: "Undo (Ctrl+Z)", onclick: () => step(undo, redo) }, "↶"),
      h("button", { title: "Redo (Ctrl+Y)", onclick: () => step(redo, undo) }, "↷"),
      h("label", {}, "zoom", h("select", { onchange: (e) => { zoom = +e.target.value; draw(); } },
        ...[1, 2, 3, 4].map((n) => h("option", { value: n, selected: n === zoom }, `${n}×`))))),
    h("div", { className: "cols", style: "flex-wrap:nowrap" },
      h("div", { className: "box" }, h("h3", {}, "Colours"), swatches, second,
        h("p", { className: "muted", style: "max-width:190px;font-size:12px" },
          "Left click: the colour. Right click: the second colour, where a gradient goes to."),
        h("h3", { style: "margin-top:14px" }, "Map over it"), mapSel, h("div", { style: "margin-top:4px" }, layerSel)),
      h("div", { className: "box wide", style: "min-width:0" }, h("h3", {}, "Backdrop ", info),
        h("div", { className: "scroll" }, canvas),
        h("p", { className: "muted", style: "margin:6px 0 0;font-size:12px" },
          "In the game: backdrop(\"name.kolam\") once, then cls() each frame starts from it. It must be 320 × 240. " +
          "An imported picture is scaled to cover the screen and cropped; see-through parts become colour 0, as a backdrop has none."))));

  function bar() { for (const [k, b] of Object.entries(tools)) b.classList.toggle("on", k === tool); }
  bar();

  function paintSwatches() {
    swatches.replaceChildren(...shared.palette.map((c, i) => h("div", {
      className: (i === colour ? " on" : ""), title: `colour ${i}`, style: `background:${css(c)}` + (i === colour2 ? ";box-shadow:inset 0 0 0 3px #4fb3a9" : ""),
      onclick: () => { colour = i; paintSwatches(); },
      oncontextmenu: (e) => { e.preventDefault(); colour2 = i; paintSwatches(); } })));
    second.textContent = `colour ${colour}, second colour ${colour2}`;
  }

  // ---- drawing on the screen-sized picture ------------------------------------
  let image = null;
  function draw() {
    canvas.width = W * zoom; canvas.height = H * zoom;
    const g = canvas.getContext("2d");
    g.imageSmoothingEnabled = false;
    if (!pic) { g.fillStyle = "#1b1c24"; g.fillRect(0, 0, canvas.width, canvas.height); info.textContent = "(open, make or import one)"; return; }
    image = image || new ImageData(W, H);
    for (let i = 0; i < W * H; i++) {
      const c = shared.palette[pic.pixels[i]];
      image.data.set([c >> 16, (c >> 8) & 255, c & 255, 255], i * 4);
    }
    const tmp = new OffscreenCanvas(W, H);
    tmp.getContext("2d").putImageData(image, 0, 0);
    g.drawImage(tmp, 0, 0, canvas.width, canvas.height);
    if (overlay && shared.sheet) drawOverlay(g);
    info.textContent = `${path || "(not saved)"}${dirty ? " •" : ""}`;
  }

  function drawOverlay(g) {
    const s = shared.sheet, cols = s.width / 8;
    const tiles = new OffscreenCanvas(s.width, s.height), img = new ImageData(s.width, s.height);
    for (let i = 0; i < s.pixels.length; i++) if (s.pixels[i]) {
      const c = shared.palette[s.pixels[i]];
      img.data.set([c >> 16, (c >> 8) & 255, c & 255, 255], i * 4);
    }
    tiles.getContext("2d").putImageData(img, 0, 0);
    overlay.layers.slice(0, 2).forEach((l, li) => {
      if (overlayLayer >= 0 && li !== overlayLayer) return;
      for (let y = 0; y < Math.min(30, overlay.height); y++) for (let x = 0; x < Math.min(40, overlay.width); x++) {
        const cell = l.cells[y * overlay.width + x], n = cell & 0x3fff;
        if (!n) continue;
        g.save();
        g.translate(x * 8 * zoom + (cell & 0x8000 ? 8 * zoom : 0), y * 8 * zoom + (cell & 0x4000 ? 8 * zoom : 0));
        g.scale(cell & 0x8000 ? -1 : 1, cell & 0x4000 ? -1 : 1);
        g.drawImage(tiles, (n % cols) * 8, Math.floor(n / cols) * 8, 8, 8, 0, 0, 8 * zoom, 8 * zoom);
        g.restore();
      }
    });
  }

  async function loadOverlay() {
    overlay = null;
    if (mapSel.value) {
      try { overlay = parseTMX(await api.readText(mapSel.value)); }
      catch (e) { status(`${mapSel.value}: ${e.message}`, true); }
      if (!shared.sheet) status("Open the map's sprite sheet in Kolam to see its tiles.", true);
    }
    draw();
  }

  function snapshot() { undo.push(pic.pixels.slice()); if (undo.length > 50) undo.shift(); redo.length = 0; }
  function step(from, to) {
    if (!pic || !from.length) return;
    to.push(pic.pixels.slice());
    pic.pixels = from.pop();
    dirty = true; draw();
  }
  function put(x, y, p) {
    const r = +brushSel.value;
    for (let dy = 0; dy < r; dy++) for (let dx = 0; dx < r; dx++) {
      const px = x + dx - (r >> 1), py = y + dy - (r >> 1);
      if (px >= 0 && py >= 0 && px < W && py < H) pic.pixels[py * W + px] = p;
    }
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
    const was = pic.pixels[y * W + x];
    if (was === p) return;
    const stack = [x + y * W];
    while (stack.length) {
      const i = stack.pop();
      if (pic.pixels[i] !== was) continue;
      pic.pixels[i] = p;
      const cx = i % W;
      if (cx > 0) stack.push(i - 1);
      if (cx < W - 1) stack.push(i + 1);
      if (i >= W) stack.push(i - W);
      if (i < W * (H - 1)) stack.push(i + W);
    }
  }
  // A gradient from colour (at the drag's start) to the second colour (at
  // its end), across the whole picture, along the drag; dithered between.
  function gradient(x0, y0, x1, y1) {
    const a = shared.palette[colour], b = shared.palette[colour2];
    const len2 = (x1 - x0) ** 2 + (y1 - y0) ** 2 || 1;
    const rgba = new Uint8ClampedArray(W * H * 4);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      const t = Math.max(0, Math.min(1, ((x - x0) * (x1 - x0) + (y - y0) * (y1 - y0)) / len2));
      const i = (y * W + x) * 4;
      rgba[i] = (a >> 16) + ((b >> 16) - (a >> 16)) * t;
      rgba[i + 1] = ((a >> 8) & 255) + (((b >> 8) & 255) - ((a >> 8) & 255)) * t;
      rgba[i + 2] = (a & 255) + ((b & 255) - (a & 255)) * t;
      rgba[i + 3] = 255;
    }
    pic.pixels = quantise(rgba, W, H, ditherBox.checked).pixels;
  }

  let down = null, before = null;
  const where = (e) => [Math.floor(e.offsetX / zoom), Math.floor(e.offsetY / zoom)];
  canvas.addEventListener("contextmenu", (e) => e.preventDefault());
  canvas.addEventListener("mousedown", (e) => {
    if (!pic) return;
    const [x, y] = where(e);
    if (tool === "pick" || e.button === 2) {
      if (e.button === 2) colour2 = pic.pixels[y * W + x]; else colour = pic.pixels[y * W + x];
      paintSwatches(); return;
    }
    snapshot();
    before = pic.pixels.slice();
    if (tool === "fill") { fill(x, y, colour); dirty = true; draw(); return; }
    down = [x, y];
    if (tool === "pen") put(x, y, colour);
    dirty = true; draw();
  });
  canvas.addEventListener("mousemove", (e) => {
    if (!down) return;
    const [x, y] = where(e), [x0, y0] = down;
    if (tool === "pen") { lineCells(x0, y0, x, y, (a, b) => put(a, b, colour)); down = [x, y]; }
    else {
      pic.pixels.set(before);
      if (tool === "line") lineCells(x0, y0, x, y, (a, b) => put(a, b, colour));
      else if (tool === "rect" || tool === "solid") {
        for (let b = Math.min(y0, y); b <= Math.max(y0, y); b++) for (let a = Math.min(x0, x); a <= Math.max(x0, x); a++)
          if (tool === "solid" || a === x0 || a === x || b === y0 || b === y) pic.pixels[b * W + a] = colour;
      } else if (tool === "gradient") gradient(x0, y0, x, y);
    }
    draw();
  });
  addEventListener("mouseup", () => { down = null; });

  addEventListener("keydown", (e) => {
    if (!root.classList.contains("on") || /INPUT|TEXTAREA|SELECT/.test(document.activeElement?.tagName)) return;
    const k = e.key.toLowerCase();
    if (e.ctrlKey && k === "z") { e.preventDefault(); step(undo, redo); }
    else if (e.ctrlKey && k === "y") { e.preventDefault(); step(redo, undo); }
    else if (e.ctrlKey && k === "s") { e.preventDefault(); save(); }
  });

  // ---- files -------------------------------------------------------------------
  async function open() {
    if (!files.value) return;
    if (dirty && !confirm(`${path} has changes that are not saved. Open another anyway?`)) return;
    try {
      const p = await decodePicture(await api.read(files.value));
      if (p.width !== W || p.height !== H)
        return status(`${files.value} is ${p.width}×${p.height}: a backdrop is exactly ${W}×${H}. Import it to fit it.`, true);
      pic = p; path = files.value; dirty = false; undo.length = redo.length = 0;
      draw();
      status(p.moved ? `${path}: ${p.moved} pixels took the nearest of the 64 colours.` : `Opened ${path}.`);
    } catch (e) { status(`${files.value}: ${e.message}`, true); }
  }
  async function create() {
    if (dirty && !confirm("The backdrop in hand has changes that are not saved. Start a new one anyway?")) return;
    const name = askName("bg.png");
    if (!name) return;
    pic = { width: W, height: H, pixels: new Uint8Array(W * H).fill(colour) };
    path = name; dirty = true; undo.length = redo.length = 0;
    draw();
    await save();
  }
  function askName(suggest) {
    const name = prompt("File name for the backdrop (the game loads it as backdrop(\"<name>.kolam\"))", suggest);
    if (!name) return null;
    if (!/^[\w-]+\.png$/.test(name)) { status("A backdrop's name ends in .png and sits in the game folder.", true); return null; }
    if (name === "sprites.png") { status("sprites.png is the sprite sheet; give the backdrop another name.", true); return null; }
    if (shared.files.includes(name) && !confirm(`${name} exists. Replace it?`)) return null;
    return name;
  }
  // a picture from this computer: scaled to cover the screen, centred, cropped
  async function importFile(file) {
    picker.value = "";
    if (!file) return;
    try {
      const bitmap = await createImageBitmap(file);
      const c = new OffscreenCanvas(W, H), g = c.getContext("2d");
      const k = Math.max(W / bitmap.width, H / bitmap.height);
      g.imageSmoothingQuality = "high";
      g.drawImage(bitmap, (W - bitmap.width * k) / 2, (H - bitmap.height * k) / 2, bitmap.width * k, bitmap.height * k);
      const data = g.getImageData(0, 0, W, H).data;
      for (let i = 3; i < data.length; i += 4) data[i] = 255;      // a backdrop has no see-through
      const name = askName(file.name.replace(/\.[^.]*$/, "").replace(/[^\w-]/g, "_").toLowerCase() + ".png");
      if (!name) return;
      if (pic) snapshot();
      pic = quantise(data, W, H, ditherBox.checked);
      path = name; dirty = true;
      draw();
      await save();
    } catch (e) { status(`${file.name}: ${e.message}`, true); }
  }
  async function save() {
    if (!pic) return;
    if (!path) { path = askName("bg.png"); if (!path) return; }
    try {
      await api.write(path, await encodePicture(pic));
      dirty = false;
      await refreshFiles();
      files.value = path;
      draw();
      status(`Saved ${path}: the game sets it with backdrop("${path.replace(/\.png$/, ".kolam")}").`);
    } catch (e) { status("Not saved: " + e.message, true); }
  }

  shared.listeners.push((what) => {
    if (what === "files") {
      const was = files.value, m = mapSel.value;
      files.replaceChildren(...shared.files.filter((f) => f.endsWith(".png") && !f.includes("/") && f !== "sprites.png")
        .map((f) => h("option", { value: f }, f)));
      if (was) files.value = was;
      mapSel.replaceChildren(h("option", { value: "" }, "no map"),
        ...shared.files.filter((f) => f.endsWith(".tmx")).map((f) => h("option", { value: f }, f)));
      mapSel.value = m;
    }
    if ((what === "sheet" || what === "pixels") && overlay) draw();
  });
  shared.dirtyChecks.push(() => dirty);
  paintSwatches();
  draw();
}
