// Kolam: the sprite editor. Draws on the game's sprite sheet (a .png) in
// its 64, 128 or 256 colours; colour 0 is see-through. spr(n) counts 8x8 cells left to
// right, top to bottom, and the number of the cell in hand is shown.
// A sprite (a frame) is any multiple of 8 across and down: 48×56, 96×128.
// Besides the pen there are shapes (a limb, a polygon, an oval) that fill
// themselves with a material, shaded for light from the upper left
// (lib/shapes.js); a game's own materials are kept in art/materials.json,
// which pack leaves out.
import { FOLDERS, place, sheets } from "./lib/layout.js";
import { api, h, shared, status, loadSheet, saveSheet, refreshFiles } from "./app.js";
import { css } from "./lib/palette.js";
import { MATERIALS, FRAME_SIZES, limb, polygon, ellipse, mask, shade, frameAt, checkMaterial } from "./lib/shapes.js";

const MATERIALS_FILE = "art/materials.json";

export function kolam(root) {
  let colour = 8, tool = "pen", cell = 0, fw = 16, fh = 16, zoom = 20, sheetZoom = 3;
  let mirror = "", onion = false, frames = 4, fps = 8, animTimer = 0;   // symmetry, and the animation
  let materials = MATERIALS.map((m) => ({ ...m })), material = 1, r0 = 3, r1 = 2;
  let poly = [];                                    // the polygon being placed, frame pixels
  const undo = [], redo = [];
  let clip = null;

  const files = h("select", { title: "Pictures in the game folder", "data-empty": "no pictures yet: New…", onchange: () => open() });
  const big = h("canvas");
  const whole = h("canvas");
  const info = h("span", { className: "muted" });
  const swatches = h("div", { className: "swatches" });
  const tools = {};
  for (const [k, label, key] of [["pen", "✎ Pen", "p"], ["fill", "◧ Fill", "f"], ["line", "╱ Line", "l"],
                                 ["rect", "▭ Box", "r"], ["pick", "⊙ Pick", "k"], ["erase", "⌫ Erase", "e"],
                                 ["move", "✥ Move", "m"], ["limb", "⟋ Limb", "b"], ["poly", "⬠ Shape", "s"],
                                 ["oval", "◯ Oval", "o"]])
    tools[k] = h("button", { title: `${label.slice(2)} (${key.toUpperCase()})`, onclick: () => setTool(k) }, label);
  const mirrorSel = h("select", { title: "Draw mirrored: what is drawn on one side is drawn on the other",
    onchange: () => { mirror = mirrorSel.value; draw(); } },
    ...[["", "no mirror"], ["x", "mirror ⇋"], ["y", "mirror ⇵"], ["xy", "mirror both"]].map(([v, t]) => h("option", { value: v }, t)));
  const anim = h("canvas", { width: 128, height: 128 });
  const animInfo = h("span", { className: "muted" });
  const sizes = h("select", { id: "kolam-size", title: "The sprite's size: any multiple of 8 across and down",
    onchange: () => {
      if (sizes.value === "other") {
        const got = prompt("Sprite size, width × height (multiples of 8)", `${fw}x${fh}`);
        const m = got && got.match(/^\s*(\d+)\s*[x×*,]\s*(\d+)\s*$/);
        if (m && +m[1] % 8 === 0 && +m[2] % 8 === 0 && +m[1] > 0 && +m[2] > 0 && +m[1] <= 256 && +m[2] <= 256) setSize(+m[1], +m[2]);
        else status("A sprite's width and height are multiples of 8, up to 256.", true);
        sizeOptions();
      } else setSize(...sizes.value.split("x").map(Number));
    } });
  const matSel = h("select", { id: "kolam-material", title: "What the shapes are made of", onchange: () => { material = +matSel.value; paintMaterial(); } });
  const matSwatch = h("span", { className: "swatches", style: "display:inline-flex;gap:2px" });
  const width0 = h("input", { id: "kolam-r0", type: "number", min: 0.5, max: 40, step: 0.5, value: r0, style: "width:56px",
    title: "A limb's half-width where it starts", onchange: (e) => { r0 = Math.max(0.5, +e.target.value); } });
  const width1 = h("input", { id: "kolam-r1", type: "number", min: 0.5, max: 40, step: 0.5, value: r1, style: "width:56px",
    title: "A limb's half-width where it ends", onchange: (e) => { r1 = Math.max(0.5, +e.target.value); } });

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
      h("button", { title: "Flip left-right", onclick: () => region((get) => (x, y) => get(fw - 1 - x, y)) }, "⇋"),
      h("button", { title: "Flip up-down", onclick: () => region((get) => (x, y) => get(x, fh - 1 - y)) }, "⇵"),
      h("button", { title: "Turn a quarter clockwise (a square sprite)", onclick: () => fw === fh
        ? region((get) => (x, y) => get(y, fw - 1 - x)) : status("Only a square sprite can be turned.", true) }, "↻"),
      h("button", { title: "Copy (Ctrl+C)", onclick: copy }, "Copy"),
      h("button", { title: "Paste (Ctrl+V)", onclick: paste }, "Paste"),
      h("button", { title: "Clear to see-through", onclick: () => region(() => () => 0) }, "Clear"),
      h("span", { className: "sep" }), mirrorSel,
      h("label", { title: "Show the sprite before this one faintly behind it" },
        h("input", { type: "checkbox", onchange: (e) => { onion = e.target.checked; draw(); } }), "onion skin")),
    h("div", { className: "bar" },
      h("label", { title: "The limb, shape and oval tools fill with this, shaded: lit on the upper left, edged in its darkest shade below and right" },
        "material", matSel), matSwatch,
      h("button", { title: "Make a material from the four colours picked last: edge, shadow, base, lit", onclick: newMaterial }, "New material…"),
      h("label", {}, "limb width", width0, "to", width1),
      h("span", { className: "muted" }, "Limb: drag from end to end. Shape: click its corners, Enter or a double-click to fill, Esc to drop. Oval: drag its box.")),
    h("div", { className: "cols" },
      h("div", { className: "box" }, h("h3", {}, "Colours"), swatches,
        h("p", { className: "muted", style: "max-width:190px" }, "Right-click picks a colour. 0 is see-through.")),
      h("div", { className: "box" }, h("h3", {}, "Sprite ", info, " ", sizes), big,
        h("h3", { style: "margin-top:12px" }, "Animation"),
        h("div", { className: "bar" },
          h("label", { title: "This sprite and the ones after it, each the size above, along the row and on to the next" }, "frames",
            h("input", { type: "number", min: 1, max: 64, value: frames, onchange: (e) => { frames = Math.max(1, +e.target.value); animate(); } })),
          h("label", {}, "a second", h("input", { type: "number", min: 1, max: 60, value: fps, onchange: (e) => { fps = Math.max(1, +e.target.value); animate(); } }))),
        h("div", { className: "bar" }, anim, animInfo)),
      h("div", { className: "box wide" }, h("h3", {}, "Sheet"), h("div", { className: "scroll" }, whole))));

  let animKey = "";
  function setTool(k) {
    tool = k;
    poly = [];
    for (const [n, b] of Object.entries(tools)) b.classList.toggle("on", n === k);
    if (S()) draw();
  }
  function setSize(w, hh) {
    fw = w; fh = hh;
    zoom = Math.max(3, Math.floor(Math.min(384 / fw, 448 / fh)));
    poly = [];
    draw();
  }
  function sizeOptions() {
    const all = FRAME_SIZES.some(([w, hh]) => w === fw && hh === fh) ? FRAME_SIZES : [...FRAME_SIZES, [fw, fh]];
    sizes.replaceChildren(...all.map(([w, hh]) => h("option", { value: `${w}x${hh}`, selected: w === fw && hh === fh }, `${w}×${hh}`)),
      h("option", { value: "other" }, "other…"));
  }
  sizeOptions();

  function paintSwatches() {
    swatches.replaceChildren(...shared.palette.slice(0, shared.colours).map((c, i) => h("div", {
      className: (i === 0 ? "clear" : "") + (i === colour ? " on" : ""), title: `colour ${i}`,
      style: i ? `background:${css(c)}` : "", onclick: () => pickColour(i) })));
  }
  const picked = [];                                // the last colours picked, for a new material
  function pickColour(i) {
    colour = i;
    if (i) { picked.push(i); if (picked.length > 4) picked.shift(); }
    paintSwatches();
  }
  function paintMaterial() {
    matSel.replaceChildren(...materials.map((m, i) => h("option", { value: i, selected: i === material }, m.name)));
    const m = materials[material];
    matSwatch.replaceChildren(...[m.edge, m.shade, m.base, m.lit, ...(m.dots ? [m.dots[0]] : [])].map((c, i) =>
      h("div", { title: ["edge", "shadow", "base", "lit", "dots"][i] + ` (${c})`, style: `background:${css(shared.palette[c])}` })));
  }
  async function loadMaterials() {
    materials = MATERIALS.map((m) => ({ ...m }));
    try {
      const own = JSON.parse(await api.readText(MATERIALS_FILE));
      for (const m of own) {
        const bad = checkMaterial(m);
        if (bad) { status(`${MATERIALS_FILE}: ${bad}`, true); continue; }
        const i = materials.findIndex((x) => x.name === m.name);
        if (i >= 0) materials[i] = m; else materials.push(m);
      }
    } catch { /* none kept yet: the built-in ones */ }
    material = Math.min(material, materials.length - 1);
    paintMaterial();
  }
  async function newMaterial() {
    if (picked.length < 4) return status("Pick four colours first (click them in order): its edge, shadow, base and lit shade.", true);
    const name = prompt(`A name for the material ${picked.join(", ")} (edge, shadow, base, lit)`, "");
    if (!name) return;
    const m = { name, edge: picked[0], shade: picked[1], base: picked[2], lit: picked[3] };
    const own = materials.filter((x) => !MATERIALS.some((b) => JSON.stringify(b) === JSON.stringify(x)) && x.name !== name);
    own.push(m);
    try {
      await api.write(MATERIALS_FILE, JSON.stringify(own, null, 1) + "\n");
      await loadMaterials();
      material = materials.findIndex((x) => x.name === name);
      paintMaterial();
      status(`Material "${name}" kept in ${MATERIALS_FILE}.`);
    } catch (e) { status("Not kept: " + e.message, true); }
  }

  // ---- the sheet and the sprite in hand --------------------------------------
  const S = () => shared.sheet;
  const cols = () => S().width / 8;
  const origin = () => [(cell % cols()) * 8, Math.floor(cell / cols()) * 8];
  const at = (x, y) => S().pixels[y * S().width + x];
  const pixelAt = (x, y) => (x >= 0 && y >= 0 && x < S().width && y < S().height ? at(x, y) : 0);
  const cellOf = ([x, y]) => (y / 8) * cols() + x / 8;
  // the top left of frame `k` of the animation: the sprite in hand and the
  // ones after it, each fw × fh, along the row and on to the next row
  function frameOrigin(k) {
    const [ox, oy] = origin();
    return frameAt(S().width, S().height, ox, oy, fw, fh, k);
  }
  function animate() {
    clearInterval(animTimer);
    if (!S()) return;
    let k = 0;
    const z = Math.max(1, Math.floor(160 / Math.max(fw, fh)));
    anim.width = fw * z; anim.height = fh * z;
    const tick = () => {
      const o = frameOrigin(k % frames);
      const g = anim.getContext("2d");
      g.fillStyle = "#23252e"; g.fillRect(0, 0, anim.width, anim.height);
      if (o) for (let y = 0; y < fh; y++) for (let x = 0; x < fw; x++) {
        const p = pixelAt(o[0] + x, o[1] + y);
        if (p) { g.fillStyle = css(shared.palette[p]); g.fillRect(x * z, y * z, z, z); }
      }
      animInfo.textContent = o ? `frame ${k % frames + 1} of ${frames}: spr(${cellOf(o)})` : `frame ${k % frames + 1}: past the sheet`;
      k++;
    };
    tick();
    animTimer = setInterval(tick, 1000 / fps);
  }

  function draw() {
    const s = S();
    if (!s) { info.textContent = "(no sheet: open or make one)"; return; }
    const [ox, oy] = origin();
    const w = Math.min(fw, s.width - ox), hh = Math.min(fh, s.height - oy);
    big.width = fw * zoom; big.height = fh * zoom;
    const g = big.getContext("2d");
    g.clearRect(0, 0, big.width, big.height);
    const prev = onion ? frameOrigin(-1) : null;
    for (let y = 0; y < fh; y++) for (let x = 0; x < fw; x++) {
      const p = x < w && y < hh ? at(ox + x, oy + y) : 0;
      g.fillStyle = p ? css(shared.palette[p]) : (x + y) % 2 ? "#3a3c48" : "#2c2e38";
      g.fillRect(x * zoom, y * zoom, zoom, zoom);
      if (!p && prev) {                          // the frame before, faint, where this one is empty
        const q = pixelAt(prev[0] + x, prev[1] + y);
        if (q) { g.globalAlpha = 0.3; g.fillStyle = css(shared.palette[q]); g.fillRect(x * zoom, y * zoom, zoom, zoom); g.globalAlpha = 1; }
      }
    }
    if (mirror) {                                 // the mirror's axes
      g.strokeStyle = "#4fb3a9"; g.lineWidth = 2; g.beginPath();
      if (mirror.includes("x")) { g.moveTo(fw * zoom / 2, 0); g.lineTo(fw * zoom / 2, fh * zoom); }
      if (mirror.includes("y")) { g.moveTo(0, fh * zoom / 2); g.lineTo(fw * zoom, fh * zoom / 2); }
      g.stroke(); g.lineWidth = 1;
    }
    g.strokeStyle = "#0005";
    for (let i = 0; i <= fw; i++) {
      g.lineWidth = i % 8 ? 1 : 2;
      g.beginPath(); g.moveTo(i * zoom, 0); g.lineTo(i * zoom, fh * zoom); g.stroke();
    }
    for (let i = 0; i <= fh; i++) {
      g.lineWidth = i % 8 ? 1 : 2;
      g.beginPath(); g.moveTo(0, i * zoom); g.lineTo(fw * zoom, i * zoom); g.stroke();
    }
    if (poly.length) {                            // the shape's corners so far
      g.strokeStyle = "#f0a330"; g.lineWidth = 2; g.beginPath();
      poly.forEach(([x, y], i) => (i ? g.lineTo : g.moveTo).call(g, x * zoom, y * zoom));
      g.stroke(); g.lineWidth = 1;
    }
    info.textContent = `spr(${cell})  at ${ox},${oy}, ${fw}×${fh}`;
    drawWhole();
    const key = `${cell}/${fw}x${fh}/${frames}/${fps}`;
    if (key !== animKey) { animKey = key; animate(); }
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
    g.strokeRect(ox * sheetZoom, oy * sheetZoom, fw * sheetZoom, fh * sheetZoom);
  }

  whole.addEventListener("mousedown", (e) => {
    if (!S()) return;
    const x = Math.floor(e.offsetX / sheetZoom / 8), y = Math.floor(e.offsetY / sheetZoom / 8);
    cell = Math.max(0, Math.min(y * cols() + x, cols() * (S().height / 8) - 1));
    poly = [];
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

  function inFrame(x, y) {
    const [ox, oy] = origin();
    return x >= 0 && y >= 0 && x < fw && y < fh && ox + x < S().width && oy + y < S().height;
  }
  function put(x, y, p) {
    const [ox, oy] = origin();
    if (inFrame(x, y)) S().pixels[(oy + y) * S().width + ox + x] = p;
  }
  function putM(x, y, p) {                     // put, and its mirror images
    put(x, y, p);
    if (mirror.includes("x")) put(fw - 1 - x, y, p);
    if (mirror.includes("y")) put(x, fh - 1 - y, p);
    if (mirror === "xy") put(fw - 1 - x, fh - 1 - y, p);
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
      if (!inFrame(cx, cy)) continue;
      if (at(ox + cx, oy + cy) !== was) continue;
      put(cx, cy, p);
      stack.push([cx + 1, cy], [cx - 1, cy], [cx, cy + 1], [cx, cy - 1]);
    }
  }
  // a shape laid on: shaded in its material, and mirrored if asked
  function layShape(inside) {
    const m = materials[material];
    const flips = [[false, false], ...(mirror.includes("x") ? [[true, false]] : []), ...(mirror.includes("y") ? [[false, true]] : []),
                   ...(mirror === "xy" ? [[true, true]] : [])];
    for (const [mx, my] of flips) {
      const f = (x, y) => inside(mx ? fw - x : x, my ? fh - y : y);
      for (const [i, c] of shade(mask(f, fw, fh), fw, fh, m)) put(i % fw, Math.floor(i / fw), c);
    }
  }

  let down = null, before = null;
  const where = (e) => [Math.floor(e.offsetX / zoom), Math.floor(e.offsetY / zoom)];
  const exact = (e) => [e.offsetX / zoom, e.offsetY / zoom];        // for shapes: points between pixels too
  big.addEventListener("contextmenu", (e) => e.preventDefault());
  big.addEventListener("mousedown", (e) => {
    if (!S()) return;
    const [x, y] = where(e);
    const [ox, oy] = origin();
    if (e.button === 2 || tool === "pick") {
      if (ox + x < S().width && oy + y < S().height) pickColour(at(ox + x, oy + y));
      return;
    }
    if (tool === "poly") {
      const [px, py] = exact(e);
      if (e.detail > 1 && poly.length > 2) return finishPoly();
      poly.push([Math.round(px * 2) / 2, Math.round(py * 2) / 2]);
      draw();
      return;
    }
    snapshot();
    const p = tool === "erase" ? 0 : colour;
    down = [x, y, p, ...exact(e)];
    before = S().pixels.slice();
    if (tool === "fill") { fill(x, y, p); down = null; touched(); return; }
    if (tool === "move" || tool === "limb" || tool === "oval") return;
    putM(x, y, p);
    touched();
  });
  big.addEventListener("mousemove", (e) => {
    if (!down) return;
    const [x, y] = where(e);
    const [x0, y0, p, ex0, ey0] = down;
    if (tool === "pen" || tool === "erase") {
      lineCells(x0, y0, x, y, (a, b) => putM(a, b, p));
      down = [x, y, p, ex0, ey0];
    } else {
      S().pixels.set(before);
      const [ex, ey] = exact(e);
      if (tool === "line") lineCells(x0, y0, x, y, (a, b) => putM(a, b, p));
      else if (tool === "rect") {
        for (let a = Math.min(x0, x); a <= Math.max(x0, x); a++) { putM(a, y0, p); putM(a, y, p); }
        for (let b = Math.min(y0, y); b <= Math.max(y0, y); b++) { putM(x0, b, p); putM(x, b, p); }
      } else if (tool === "move") shift(x - x0, y - y0);
      else if (tool === "limb") layShape(limb(ex0, ey0, ex, ey, r0, r1));
      else if (tool === "oval") layShape(ellipse((ex0 + ex) / 2, (ey0 + ey) / 2, Math.max(0.5, Math.abs(ex - ex0) / 2), Math.max(0.5, Math.abs(ey - ey0) / 2)));
    }
    touched();
  });
  addEventListener("mouseup", () => { down = null; });
  function finishPoly() {
    if (poly.length < 3) { poly = []; return draw(); }
    snapshot();
    layShape(polygon(poly));
    poly = [];
    touched();
  }

  function region(make) {
    if (!S()) return;
    snapshot();
    const [ox, oy] = origin();
    const w = Math.min(fw, S().width - ox), hh = Math.min(fh, S().height - oy);
    const copyOf = [];
    for (let y = 0; y < hh; y++) for (let x = 0; x < w; x++) copyOf.push(at(ox + x, oy + y));
    const f = make((x, y) => (x >= 0 && y >= 0 && x < w && y < hh ? copyOf[y * w + x] : 0));
    for (let y = 0; y < hh; y++) for (let x = 0; x < w; x++) put(x, y, f(x, y));
    touched();
  }
  // the sprite's pixels moved by dx, dy; what moves out is lost, what is
  // left behind is see-through (from `before`, the sprite as the drag began)
  function shift(dx, dy) {
    const [ox, oy] = origin();
    const w = Math.min(fw, S().width - ox), hh = Math.min(fh, S().height - oy);
    const was = (x, y) => before[(oy + y) * S().width + ox + x];
    for (let y = 0; y < hh; y++) for (let x = 0; x < w; x++) {
      const sx = x - dx, sy = y - dy;
      put(x, y, sx >= 0 && sy >= 0 && sx < w && sy < hh ? was(sx, sy) : 0);
    }
  }
  function copy() {
    if (!S()) return;
    const [ox, oy] = origin();
    clip = { w: fw, h: fh, px: [] };
    for (let y = 0; y < fh; y++) for (let x = 0; x < fw; x++)
      clip.px.push(ox + x < S().width && oy + y < S().height ? at(ox + x, oy + y) : 0);
    status(`Copied spr(${cell}), ${fw}×${fh}.`);
  }
  function paste() {
    if (!clip || !S()) return;
    snapshot();
    for (let y = 0; y < clip.h; y++) for (let x = 0; x < clip.w; x++) put(x, y, clip.px[y * clip.w + x]);
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
    else if (tool === "poly" && k === "enter") finishPoly();
    else if (tool === "poly" && k === "escape") { poly = []; draw(); }
    else if (!e.ctrlKey && { p: 1, f: 1, l: 1, r: 1, k: 1, e: 1, m: 1, b: 1, s: 1, o: 1 }[k])
      setTool({ p: "pen", f: "fill", l: "line", r: "rect", k: "pick", e: "erase", m: "move", b: "limb", s: "poly", o: "oval" }[k]);
    else if (S() && ["arrowleft", "arrowright", "arrowup", "arrowdown"].includes(k)) {
      e.preventDefault();
      const n = cols() * (S().height / 8);
      cell = { arrowleft: cell - fw / 8, arrowright: cell + fw / 8, arrowup: cell - cols() * fh / 8,
               arrowdown: cell + cols() * fh / 8 }[k];
      cell = Math.max(0, Math.min(n - 1, cell));
      poly = [];
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
      await loadMaterials();
    } catch (e) { status(e.message, true); }
  }
  async function newSheet() {
    let name = prompt("File name for the new sheet (kept in sprites/)", "sprites.png");
    if (!name) return;
    if (!/^[\w-]+(\/[\w-]+)*\.png$/.test(name)) return status("A sheet's name ends in .png", true);
    name = place(FOLDERS.sprites, name);
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
      files.replaceChildren(...sheets(shared.files).map((f) => h("option", { value: f }, f)));
      if (was) files.value = was;
    }
    if (what === "sheet") { if (S()) files.value = S().path; draw(); }
    if (what === "palette") { paintSwatches(); paintMaterial(); draw(); }
  });
  shared.dirtyChecks.push(() => S()?.dirty);
  paintSwatches();
  paintMaterial();
  loadMaterials();
  draw();
}
