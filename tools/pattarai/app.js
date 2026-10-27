// Pattarai's shell: the tabs, the game folder (through `pulli edit`), the
// palette and the sprite sheet the editors share.
import { BUILTIN, parsePalette } from "./lib/palette.js";
import { encodePNG } from "./lib/png.js";
import { kolam } from "./kolam.js";
import { ooru } from "./ooru.js";
import { isai } from "./isai.js";
import { vidhi } from "./vidhi.js";
import { oli } from "./oli.js";
import { project } from "./project.js";
import { useTamil } from "./lib/i18n.js";

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
  run: async (liveRun) => (await call("POST", "/api/run" + (liveRun ? "?live=1" : ""))).text(),
  stop: async () => (await call("POST", "/api/stop")).text(),
  sounds: async () => (await call("GET", "/api/sounds")).json(),
};

export function status(text, bad = false) {
  const s = document.getElementById("status");
  s.textContent = text;
  s.className = bad ? "bad" : "";
}

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
  files: [], palette: BUILTIN, sheet: null, listeners: [], dirtyChecks: [],
  changed(what) { for (const f of this.listeners) f(what); },
};

export function nearest(rgb, palette) {
  let best = 1, bd = Infinity;
  for (let i = 1; i < 64; i++) {
    const c = palette[i];
    const d = ((c >> 16) - (rgb >> 16)) ** 2 + (((c >> 8) & 255) - ((rgb >> 8) & 255)) ** 2 + ((c & 255) - (rgb & 255)) ** 2;
    if (d < bd) { bd = d; best = i; }
  }
  return best;
}

export async function loadSheet(path) {
  const bitmap = await createImageBitmap(new Blob([await api.read(path)], { type: "image/png" }),
                                         { premultiplyAlpha: "none", colorSpaceConversion: "none" });
  const c = new OffscreenCanvas(bitmap.width, bitmap.height);
  const g = c.getContext("2d");
  g.drawImage(bitmap, 0, 0);
  const rgba = g.getImageData(0, 0, c.width, c.height).data;
  const pixels = new Uint8Array(c.width * c.height);
  const cache = new Map();
  let moved = 0;
  for (let i = 0; i < pixels.length; i++) {
    if (rgba[i * 4 + 3] < 128) continue;
    const rgb = (rgba[i * 4] << 16) | (rgba[i * 4 + 1] << 8) | rgba[i * 4 + 2];
    if (!cache.has(rgb)) cache.set(rgb, nearest(rgb, shared.palette));
    pixels[i] = cache.get(rgb);
    if (shared.palette[pixels[i]] !== rgb) moved++;
  }
  shared.sheet = { path, width: c.width, height: c.height, pixels, dirty: false };
  shared.changed("sheet");
  return moved;
}

export async function saveSheet() {
  const s = shared.sheet;
  const rgba = new Uint8Array(s.width * s.height * 4);
  for (let i = 0; i < s.pixels.length; i++) {
    const p = s.pixels[i];
    if (!p) continue;
    const c = shared.palette[p];
    rgba.set([c >> 16, (c >> 8) & 255, c & 255, 255], i * 4);
  }
  await api.write(s.path, await encodePNG(s.width, s.height, rgba));
  s.dirty = false;
}

export async function refreshFiles() {
  const r = await api.files();
  shared.files = r.files;
  try { shared.sounds = await api.sounds(); } catch (e) { shared.sounds = null; }
  document.getElementById("game").textContent = r.game;
  shared.changed("files");
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
    try { status(await api.run(liveBox.checked)); } catch (e) { status("Could not run the game: " + e.message, true); }
  };
  document.getElementById("stop").onclick = async () => { try { status(await api.stop()); } catch (e) { status(e.message, true); } };
  try {
    await refreshFiles();
    const pal = shared.files.find((f) => f === "palette.hex" || f === "palette.gpl");
    if (pal) shared.palette = parsePalette(await api.readText(pal));
    vidhi(document.getElementById("vidhi"));
    kolam(document.getElementById("kolam"));
    ooru(document.getElementById("ooru"));
    oli(document.getElementById("oli"));
    isai(document.getElementById("isai"));
    project(document.getElementById("project"));
    shared.changed("files");                       // the editors were made after the files were listed
    if (shared.files.includes("sprites.png")) await loadSheet("sprites.png");
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
