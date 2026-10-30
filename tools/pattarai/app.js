// Pattarai's shell: the tabs, the game folder (through `pulli edit`), the
// palette and the sprite sheet the editors share.
import { named, editorOf, pictureNamedIn } from "./lib/layout.js";
import { readKolam, writeKolam } from "./lib/kolam.js";
import { BUILTIN, parsePalette, ownColours, quantiseTo } from "./lib/palette.js";
import { encodePNG } from "./lib/png.js";
import { kolam } from "./kolam.js";
import { ooru } from "./ooru.js";
import { isai } from "./isai.js";
import { vidhi } from "./vidhi.js";
import { oli } from "./oli.js";
import { backdrop } from "./backdrop.js";
import { project } from "./project.js";
import { useTamil, say } from "./lib/i18n.js";

const token = location.hash.slice(1);

async function call(method, url, body) {
  const r = await fetch(url, { method, body, headers: { "X-Pulli-Token": token } });
  if (!r.ok) throw new Error(await r.text());
  return r;
}

export const api = {
  files: async () => (await call("GET", "/api/files")).json(),
  read: async (path) => new Uint8Array(await (await call("GET", "/api/file?path=" + encodeURIComponent(path))).arrayBuffer()),
  readText: async (path) => (await call("GET", "/api/file?path=" + encodeURIComponent(path))).text(),
  write: async (path, data) => call("PUT", "/api/file?path=" + encodeURIComponent(path), data),
  budget: async () => (await call("GET", "/api/budget")).json(),
  run: async (mode) => (await call("POST", "/api/run" + (mode ? "?live=" + mode : ""))).text(),
  stop: async () => (await call("POST", "/api/stop")).text(),
  live: async () => (await call("GET", "/api/live")).json(),
  sounds: async () => (await call("GET", "/api/sounds")).json(),
};

// The status line: each tab keeps its own, so a message from one editor is
// not left showing in another.
const said = {};
const tabNow = () => document.querySelector(".tab.on")?.dataset.tab || "";
// While a game runs hot-reloaded, what the emulator says of each reload
// shows in the status line: "Hot-reloaded.", or why not (the game goes on
// with the code it had).
let liveTimer = 0, liveHeard = -1;
function watchLive() {
  clearInterval(liveTimer);
  liveHeard = -1;
  liveTimer = setInterval(async () => {
    try {
      const l = await api.live();
      if (l.memory) { shared.memory = l.memory; shared.changed("memory"); }
      if (!l.running) { clearInterval(liveTimer); return; }
      if (liveHeard < 0) liveHeard = l.heard;                 // (what was said before this run)
      if (l.heard > liveHeard) {
        liveHeard = l.heard;
        if (l.said === "reloaded") status("Hot-reloaded: the game goes on with what was saved.");
        else status("Not hot-reloaded: " + l.said.replace(/^reload: /, "") + " (the game goes on with the code it had)", true);
      }
    } catch (e) { clearInterval(liveTimer); }
  }, 1500);
}

export function status(text, bad = false) {
  const s = document.getElementById("status");
  text = say(text);
  s.textContent = text;
  s.className = bad ? "bad" : "";
  said[tabNow()] = [text, bad];
}

// Help that is there when wanted: a "?" that opens to the text.
export const help = (...text) => h("details", { className: "help" }, h("summary", { title: "Help" }, "?"),
  h("div", {}, ...text));

export const h = (tag, props = {}, ...kids) => {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
    else if (k === "style") e.style.cssText = v;
    else if (k in e && k !== "list") e[k] = v;
    else e.setAttribute(k, v);
  }
  for (const k of kids.flat()) if (k != null) e.append(k.nodeType ? k : String(k));
  return e;
};

// What the editors share: the files, the colours, and the sprite sheet as
// palette indices (colour 0 is see-through), which Kolam draws and Ooru
// builds its tiles from.
export const shared = {
  files: [], palette: BUILTIN, colours: 256, sheet: null, listeners: [], dirtyChecks: [],
  changed(what) {
    for (const f of this.listeners) f(what);
    if (what === "files") emptyLists();
  },
};

// A list of files with none in it says so, instead of showing a blank box.
function emptyLists() {
  for (const sel of document.querySelectorAll("select[data-empty]")) {
    const real = [...sel.options].filter((o) => !o.dataset.placeholder);
    sel.querySelectorAll("option[data-placeholder]").forEach((o) => o.remove());
    if (!real.length) {
      sel.append(h("option", { value: "", disabled: true, selected: true, "data-placeholder": "1" }, sel.dataset.empty));
      sel.classList.add("empty");
    } else sel.classList.remove("empty");
  }
}

// A picture in the game's colours: palette indices, 0 where it is less
// than half opaque, the rest the nearest colour (as pack does). `moved`
// counts the pixels whose colour was not one of the palette's.
export async function decodePicture(bytes) {
  const bitmap = await createImageBitmap(new Blob([bytes]), { premultiplyAlpha: "none", colorSpaceConversion: "none" });
  const c = new OffscreenCanvas(bitmap.width, bitmap.height);
  const g = c.getContext("2d");
  g.drawImage(bitmap, 0, 0);
  return quantise(g.getImageData(0, 0, c.width, c.height).data, c.width, c.height);
}

export const quantise = (rgba, width, height, dither = false) => quantiseTo(rgba, width, height, shared.palette.slice(0, shared.colours), dither);

export async function encodePicture(pic) {
  const rgba = new Uint8Array(pic.width * pic.height * 4);
  for (let i = 0; i < pic.pixels.length; i++) {
    const p = pic.pixels[i];
    if (!p) continue;
    const c = shared.palette[p];
    rgba.set([c >> 16, (c >> 8) & 255, c & 255, 255], i * 4);
  }
  return encodePNG(pic.width, pic.height, rgba);
}

// A picture kept as a .kolam is read and written as it is; any other as a PNG.
export const isKolam = (path) => path.endsWith(".kolam");
export async function readPicture(path) {
  const bytes = await api.read(path);
  return isKolam(path) ? readKolam(bytes) : decodePicture(bytes);
}
export async function writePicture(path, pic) {
  await api.write(path, isKolam(path) ? writeKolam(pic) : await encodePicture(pic));
}

// The editor a file opens in, from Vidhi's explorer: the tab is shown and
// the file chosen in its list (each editor opens what is chosen there).
export { editorOf };
export function openIn(f) {
  const tab = editorOf(f);
  if (!tab || tab === "vidhi") return false;
  document.querySelector(`[data-tab=${tab}]`).click();
  const sel = document.querySelector(`#${tab} select`);
  if (![...sel.options].some((o) => o.value === f)) return false;
  sel.value = f;
  sel.dispatchEvent(new Event("change"));
  return true;
}

// The sheet a map's tiles come from. A map may name it through its Tiled
// tileset; a game that loads its sheets itself names it in its code, as
// sheet = "forest.kolam" at or above the line naming "f1.ooru". The one
// chosen in Ooru is remembered for the map. The sheet open in Kolam is
// used as it is (so its unsaved changes show).
const pictures = new Map();
const remembered = () => { try { return JSON.parse(localStorage.getItem("pattarai.sheets." + gameName()) || "{}"); } catch { return {}; } };
const gameName = () => document.getElementById("game")?.textContent || "";
export function rememberSheet(map, sheet) {
  try { const r = remembered(); r[map] = sheet; localStorage.setItem("pattarai.sheets." + gameName(), JSON.stringify(r)); } catch { /* not kept */ }
}
export const guessSheet = (map, tsxText) => guessPicture(map, "sheet", tsxText);
export const guessBackdrop = (map) => guessPicture(map, "bg");
async function guessPicture(map, key, tsxText) {
  const r = remembered()[key === "sheet" ? map : key + ":" + map];
  if (r && shared.files.includes(r)) return r;
  const image = tsxText && tsxText.match(/<image\b[^>]*source="([^"]+)"/);
  if (image) { const f = named(shared.files, image[1].slice(image[1].lastIndexOf("/") + 1)); if (f) return f; }
  const stem = map.slice(map.lastIndexOf("/") + 1).replace(/\.tmx$/, "");
  for (const f of shared.files.filter((f) => f.endsWith(".lua"))) {
    let text;
    try { text = await api.readText(f); } catch { continue; }
    const stemNamed = pictureNamedIn(text, stem, key);
    if (stemNamed) {
      const f2 = named(shared.files, stemNamed + ".kolam") || named(shared.files, stemNamed + ".png");
      if (f2) return f2;
    }
  }
  if (key !== "sheet") return null;
  return shared.sheet?.path || named(shared.files, "sprites.png") || named(shared.files, "sprites.kolam") || null;
}
export async function sheetPicture(path) {
  if (!path) return null;
  if (shared.sheet && shared.sheet.path === path) return shared.sheet;
  if (!pictures.has(path)) pictures.set(path, { path, ...(await readPicture(path)) });
  return pictures.get(path);
}

export async function loadSheet(path) {
  const pic = await readPicture(path);
  pictures.delete(path);
  shared.sheet = { path, width: pic.width, height: pic.height, pixels: pic.pixels, dirty: false };
  shared.changed("sheet");
  return pic.moved;
}

export async function saveSheet() {
  const s = shared.sheet;
  await writePicture(s.path, s);
  s.dirty = false;
}

// The budget meter in the header: what the game takes against the target
// chosen in Project. It warns; it refuses only when the game is set strict
// (the server does that, on save).
export async function refreshBudget() {
  let b;
  try { b = await api.budget(); } catch (e) { return; }
  const was = shared.budget?.over?.length;
  shared.budget = b;
  const m = document.getElementById("meter");
  const share = b.room ? b.size / b.room : 0;
  m.querySelector(".fill").style.width = `${Math.min(100, share * 100)}%`;
  m.className = "meter" + (b.error ? " unknown" : b.over.length ? " over" : share > 0.8 ? " near" : "");
  const mb = (n) => (n / 1048576).toFixed(n < 10 * 1048576 ? 2 : 1);
  m.querySelector(".txt").textContent = b.error ? `${b.target}: not measured`
    : `${b.target}: ${mb(b.size)} of ${mb(b.room)} MB` + (b.settings.strict ? " · strict" : "");
  m.title = b.error ? `The game does not pack yet: ${b.error}` : b.over.length ? "Over budget: " + b.over.join("; ")
    : "What the game takes against its budget; open Project to choose the cartridge.";
  if (b.over.length && !was) status("Over budget: " + b.over.join("; ") + (b.settings.strict ? "" : ". Saves still work; set the budget strict in Project to stop them."), true);
  shared.changed("budget");
}

export async function refreshFiles() {
  const r = await api.files();
  shared.files = r.files;
  refreshBudget();
  document.getElementById("game").textContent = r.game;
  shared.changed("files");
  api.sounds().then((x) => { shared.sounds = x; shared.changed("files"); }, () => { shared.sounds = null; });   // not waited for
}

async function start() {
  if (!token) {
    status("Open Pattarai with the address `pulli edit` printed (it carries the key).", true);
    return;
  }
  for (const b of document.querySelectorAll(".tab")) {
    b.onclick = () => {
      for (const x of document.querySelectorAll(".tab, .panel")) x.classList.remove("on");
      b.classList.add("on");
      document.getElementById(b.dataset.tab).classList.add("on");
      const [text, bad] = said[b.dataset.tab] || ["", false];
      const s = document.getElementById("status");
      s.textContent = text; s.className = bad ? "bad" : "";
    };
  }
  // the language: kept in this browser, as a convenience
  let ta = false;
  try { ta = localStorage.getItem("pattarai-lang") === "ta"; } catch (e) { /* private window */ }
  const langBtn = document.getElementById("lang");
  langBtn.textContent = ta ? "English" : "தமிழ்";
  langBtn.onclick = () => {
    if (shared.dirtyChecks.some((f) => f()) && !confirm("Changes not saved will be lost. Change the language anyway?")) return;
    try { localStorage.setItem("pattarai-lang", ta ? "en" : "ta"); } catch (e) { /* not kept */ }
    shared.dirtyChecks.length = 0;            // asked already
    location.reload();
  };
  const liveBox = document.getElementById("live");
  document.getElementById("run").onclick = async () => {
    try { status(await api.run(liveBox.value)); watchLive(); } catch (e) { status("Could not run the game: " + e.message, true); }
  };
  document.getElementById("meter").onclick = () => document.querySelector('[data-tab=project]').click();
  document.getElementById("stop").onclick = async () => { try { status(await api.stop()); } catch (e) { status(e.message, true); } };
  try {
    await refreshFiles();
    const pal = shared.files.find((f) => f === "palette.hex" || f === "palette.gpl");
    if (pal) {
      const text = await api.readText(pal);
      shared.palette = parsePalette(text);
      shared.colours = ownColours(text);
    }
    vidhi(document.getElementById("vidhi"));
    kolam(document.getElementById("kolam"));
    ooru(document.getElementById("ooru"));
    backdrop(document.getElementById("backdrop"));
    oli(document.getElementById("oli"));
    isai(document.getElementById("isai"));
    project(document.getElementById("project"));
    shared.changed("files");                       // the editors were made after the files were listed
    const sheet = named(shared.files, "sprites.png") || named(shared.files, "sprites.kolam");
    if (sheet) await loadSheet(sheet);
    if (ta) useTamil(document.body);
    status(`Editing ${document.getElementById("game").textContent}: ${shared.files.length} files the editors can open.`);
  } catch (e) {
    status(e.message, true);
  }
  addEventListener("beforeunload", (e) => {
    if (shared.dirtyChecks.some((f) => f())) e.preventDefault();
  });
}

start();

// How a sound in the game folder will play, as SPEC §2 and §3 have it.
export function soundInfo(row) {
  if (!row) return "";
  if (row.error) return "⚠ " + row.error;
  return `${row.channels === 1 ? "mono" : "stereo"} · ${row.rate.toLocaleString("en")} Hz · ${row.seconds.toFixed(2)} s · ` +
    `${Math.ceil(row.packed / 1024)} KB packed`;
}
export const CHANNEL_NOTE = "The console has 8 sound channels, 0 to 7: sfx(n) takes a free one (or the oldest), " +
  "sfx(n, c) uses channel c. Music is one track at a time, mixed on top of the 8. Everything is played at 44,100 Hz; " +
  "sounds add up at full level and the total is clipped, so leave headroom.";
