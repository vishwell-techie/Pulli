// The project: the game as `pulli pack` builds it, measured against the
// spec's limits (SPEC §2): the package's size and entries, each part
// against the memory a game holds at once, what is read as it starts, and
// the Pico 2 board's flash. The biggest parts are listed, to see what to
// make smaller.
import { h, status, api, shared, refreshBudget, refreshFiles, help } from "./app.js";
import { BUILTIN, SIZES, sizeFor, css, readPaletteFile, paletteOfPixels, fitPalette, writePalette } from "./lib/palette.js";

export function project(root) {
  const out = h("div");
  const plan = h("div", { className: "box", style: "margin-bottom:14px" });
  const ran = h("div", { className: "box", style: "margin-bottom:14px" });
  const colours = h("div", { className: "box", style: "margin-bottom:14px" });
  const button = h("button", { className: "on", onclick: measure }, "Measure");
  root.append(plan, colours, ran,
    h("div", { className: "bar" }, button,
      help("Packs the game as pulli pack does, and checks it against the spec's limits: the package, what is held at once, " +
        "what is read as it starts, and the Pico 2 board's flash. A game with a lot of music takes a while.")),
    out);

  // ---- the budget: where the game goes, and what it may take ------------------
  const KINDS = ["code", "sprites", "maps", "sound effects", "music", "other"];
  function drawPlan() {
    const b = shared.budget;
    if (!b) return;
    const st = b.settings;
    const target = h("select", { id: "budget-target" }, ...Object.entries(b.targets).map(([k, name]) =>
      h("option", { value: k, selected: k === st.target }, name)));
    const strict = h("input", { type: "checkbox", id: "budget-strict", checked: st.strict });
    const limits = Object.fromEntries(KINDS.map((k) => [k, h("input", { type: "number", min: 0, step: 0.1, id: `budget-${k.replace(" ", "-")}`,
      value: st.limits[k] ?? "", placeholder: "none", style: "width:80px" })]));
    const mb = (n) => (n / 1048576).toFixed(2);
    plan.replaceChildren(
      h("div", { className: "bar", style: "margin-bottom:6px" }, h("h3", { style: "margin:0" }, "Budget"),
        help("Choose where the game is meant to go. The meter at the top shows what it takes against that, and Pattarai warns " +
          "when a save takes it past. Strict refuses those saves instead. Whatever the setting, Pattarai always refuses a " +
          "picture, map or sound the console could not use. The setting is kept in the game's folder (.pattarai.json), " +
          "which pack leaves out.")),
      h("div", { className: "bar" }, h("label", {}, "made for", target),
        h("label", { title: "Refuse saves that take the game past its budget or a limit" }, strict, "strict"),
        h("button", { onclick: () => save(target.value, strict.checked, limits) }, "Save setting")),
      h("table", { className: "limits" },
        h("tr", {}, h("th", {}, "kind"), h("th", { style: "text-align:right" }, "now"), h("th", {}, "limit (MB, empty for none)")),
        ...KINDS.map((k) => h("tr", {}, h("td", {}, k), h("td", { className: "num" }, `${mb(b.kinds[k])} MB`), h("td", {}, limits[k])))),
      b.error ? h("p", { className: "err", style: "margin:8px 0 0" }, "Not measured: " + b.error)
        : h("div", { style: "margin-top:10px" }, row(`the whole game, of ${b.target}`, b.size, b.room),
            ...KINDS.filter((k) => st.limits[k]).map((k) => row(`${k}, of its limit`, b.kinds[k], st.limits[k] * 1048576))),
      ...(b.over || []).map((o) => h("p", { className: "err", style: "margin:6px 0 0" }, "Over: " + o)));
  }
  async function save(target, strict, limits) {
    const set = { target, strict, limits: {} };
    for (const [k, input] of Object.entries(limits)) if (+input.value > 0) set.limits[k] = +input.value;
    try {
      await api.write(".pattarai.json", JSON.stringify(set, null, 1) + "\n");
      await refreshBudget();
      status(`Budget set: ${shared.budget.target}${strict ? ", strict" : ""}.`);
    } catch (e) { status("Not saved: " + e.message, true); }
  }
  shared.listeners.push((what) => { if (what === "budget") drawPlan(); });

  // ---- the palette: the game's 64, 128 or 256 colours, and one brought in to take their place ----
  let offered = null, offeredFrom = "", offeredSize = 256;
  const picker = h("input", { type: "file", accept: ".hex,.gpl,.pal,.txt,.png", style: "display:none",
    onchange: () => { bring(picker.files[0]); picker.value = ""; } });
  const strip = (pal) => h("div", { className: "palette-strip" }, ...pal.map((c, i) =>
    h("span", { title: `${i}: ${css(c)}`, style: `background:${css(c)}` })));
  function drawColours() {
    const own = shared.files.find((f) => f === "palette.hex" || f === "palette.gpl" || f === "palette.pal");
    colours.replaceChildren(
      h("div", { className: "bar", style: "margin-bottom:6px" }, h("h3", { style: "margin:0" }, "Palette"),
        help("The game's colours: it chooses 64, 128 or 256, and pictures are put in those. Every picture keeps its " +
          "colour numbers, so a new palette shows the same pictures in the new colours: colour 0 stays see-through " +
          "in sprites. Load palette brings in a palette from your computer (.hex or .png from Lospec, .gpl from " +
          "GIMP, Aseprite or Krita, .pal, or paint.net's .txt); its colours take the first places and the rest " +
          "stay. It is kept as palette.hex in the game's folder.")),
      h("div", { className: "muted", style: "margin-bottom:4px" }, own ? `In use: ${own}` : "In use: Pulli's own colours"),
      strip(shared.palette.slice(0, shared.colours)),
      h("div", { className: "bar", style: "margin-top:6px" }, h("span", { className: "muted" }, "Colours:"),
        ...SIZES.map((n) => h("button", { className: n === shared.colours ? "on" : "",
          onclick: () => n !== shared.colours && use(shared.palette, `${n} colours`, n) }, String(n)))),
      offered ? h("div", { style: "margin-top:10px" },
        h("div", { className: "muted", style: "margin-bottom:4px" }, `From ${offeredFrom}:`), strip(offered.slice(0, offeredSize)),
        h("div", { className: "bar", style: "margin-top:6px" },
          h("button", { className: "on", onclick: () => use(offered, offeredFrom, offeredSize) }, "Use this palette"),
          h("button", { onclick: () => { offered = null; drawColours(); } }, "Cancel"))) : "",
      h("div", { className: "bar", style: "margin-top:8px" },
        h("button", { onclick: () => picker.click() }, "Load palette…"),
        h("button", { onclick: () => { offered = BUILTIN; offeredFrom = "Pulli's own colours"; offeredSize = shared.colours; drawColours(); } }, "Pulli's own colours"),
        picker));
  }
  async function bring(file) {
    if (!file) return;
    try {
      let list;
      if (/\.png$/i.test(file.name)) {
        const bitmap = await createImageBitmap(file);
        const c = new OffscreenCanvas(bitmap.width, bitmap.height), g = c.getContext("2d");
        g.drawImage(bitmap, 0, 0);
        list = paletteOfPixels(g.getImageData(0, 0, c.width, c.height).data);
      } else list = readPaletteFile(file.name, await file.arrayBuffer());
      offered = fitPalette(list, shared.palette);
      offeredSize = sizeFor(list.length);
      offeredFrom = `${file.name} (${list.length} colour${list.length === 1 ? "" : "s"})`;
      drawColours();
      status(`${file.name}: ${list.length} colours. Use this palette to make it the game's.`);
    } catch (e) { status(`${file.name}: ${e.message}`, true); }
  }
  async function use(pal, from, size) {
    const gpl = shared.files.includes("palette.gpl");
    if (shared.files.includes("palette.pal")) return status("The game keeps a ready-made palette.pal: replace it by hand.", true);
    try {
      await api.write(gpl ? "palette.gpl" : "palette.hex", writePalette(pal.slice(0, size), gpl));
      shared.palette = pal;
      shared.colours = size;
      offered = null;
      await refreshFiles();
      shared.changed("palette");
      drawColours();
      status(`The game's palette is now ${from}; saved as ${gpl ? "palette.gpl" : "palette.hex"}.`);
    } catch (e) { status("Not saved: " + e.message, true); }
  }
  shared.listeners.push((what) => { if (what === "files" || what === "palette") drawColours(); });

  // ---- memory, as the game last ran: the Lua heap and the active set ----------
  const ACTIVE_MAX = 6 * 1048576;                   // SPEC §2
  function drawRan() {
    const m = shared.memory;
    ran.replaceChildren(
      h("div", { className: "bar", style: "margin-bottom:6px" }, h("h3", { style: "margin:0" }, "Memory, as the game ran"),
        help("Measured while the game runs from Run, once a second. The Lua heap is the game's working memory: its " +
          "tables, strings and code. The active set is the parts of the package in memory at once (pictures, maps, " +
          "sounds), at most 6 MB. When it is full, parts not in use are let go and read again when wanted: on a " +
          "console each of those is a read from the SD card, a pause in the game. Preload behind a loading screen " +
          "to avoid them.")),
      !m ? h("p", { className: "muted", style: "margin:0" }, "Run the game to measure it.")
        : h("div", {}, row("Lua heap, its peak", m.heap_peak, 256 * 1024),
            row("active set, its peak", m.active_peak, ACTIVE_MAX),
            row("active set, now", m.active, ACTIVE_MAX),
            h("div", { className: m.reread ? "warn" : "muted", style: "margin:3px 0" },
              ...(m.reread ? ["⚠ ", String(m.reread), " parts let go for room and read again"] : ["✓ No part was read again"]))));
  }
  shared.listeners.push((what) => { if (what === "memory") drawRan(); });
  drawRan();

  const kb = (n) => (n < 1048576 ? `${Math.ceil(n / 1024).toLocaleString("en")} KB` : `${(n / 1048576).toFixed(2)} MB`);

  async function measure() {
    button.disabled = true;
    status("Packing the game to measure it…");
    try {
      const r = await (await fetch("/api/project", { method: "POST", headers: { "X-Pulli-Token": location.hash.slice(1) } })).json();
      if (r.error) {
        out.replaceChildren(h("p", { className: "err" }, "The game does not pack: " + r.error));
        status("The game does not pack.", true);
        return;
      }
      const max = r.entries[0]?.[1] || 1;
      const kinds = {};
      for (const [n, b] of r.entries) {
        const k = n.endsWith(".lua") ? "code" : n.endsWith(".kolam") ? "sprites" : n.endsWith(".ooru") ? "maps"
          : n === "sfx.oli" ? "sound effects" : n === "music.isai" ? "music" : "other";
        kinds[k] = (kinds[k] || 0) + b;
      }
      out.replaceChildren(
        h("div", { className: "box", style: "margin-bottom:12px" }, h("h3", {}, `The package: ${kb(r.size)}`),
          ...r.checks.map(([ok, text], i) => h("div", { className: ok ? "" : i === 4 ? "warn" : "err", style: "margin:3px 0" },
            ok ? "✓ " : i === 4 ? "⚠ " : "✗ ", text)),
          ...r.notes.map((n) => h("div", { className: "muted", style: "margin:3px 0" }, "• " + n))),
        h("div", { className: "cols" },
          h("div", { className: "box" }, h("h3", {}, "By kind"),
            ...Object.entries(kinds).sort((a, b) => b[1] - a[1]).map(([k, b]) => row(k, b, r.size))),
          h("div", { className: "box wide" }, h("h3", {}, "Biggest entries"),
            ...r.entries.slice(0, 16).map(([n, b]) => row(n, b, max))),
          r.sounds.length ? h("div", { className: "box" }, h("h3", {}, "Each sound, as it is read"),
            ...[...r.sounds].sort((a, b) => b[1] - a[1]).slice(0, 12).map(([n, b]) => row(n, b, Math.max(...r.sounds.map((s) => s[1]))))) : ""));
      status(r.ok ? `The game packs to ${kb(r.size)}, within the spec's limits.` : "The game is past a limit of the spec.", !r.ok);
    } catch (e) { status(e.message, true); } finally { button.disabled = false; }
  }

  function row(name, bytes, of) {
    const over = bytes > of;
    return h("div", { className: "sizerow" }, h("span", { className: "name", title: name }, name),
      h("span", { className: "track" }, h("span", { style: `width:${Math.min(100, Math.max(1, bytes / of * 100))}%` +
        (over ? ";background:var(--bad)" : "") })),
      h("span", { className: over ? "err num" : "muted num" }, kb(bytes)));
  }
}
