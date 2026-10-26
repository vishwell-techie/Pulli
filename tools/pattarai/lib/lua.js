// Lua for Vidhi: colouring it, and finding the asset a call names.

// The functions a game gets (SPEC §3); tests/test_pattarai.py checks each
// is in the spec.
export const API = ["backdrop", "btn", "btnp", "camera", "circ", "clip", "cls", "dbg", "fade", "fix.floor", "fix.from",
  "fix.mul", "fix.sin", "fix.to", "font", "line", "link.recv", "link.send", "link.side", "link.status", "load",
  "map.draw", "map.flags", "map.get", "map.load", "map.set", "map.size", "music", "music_pause", "music_stop", "pal",
  "palette", "palt", "preload", "print", "pset", "rect", "save", "save_commit", "sfx", "shade", "sheet.load", "spr",
  "sspr", "stat", "sys.has", "text_size", "time"];
const KEYWORDS = ["and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in",
  "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"];
const CALLBACKS = ["init", "update", "draw"];

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");

// Lua, coloured: one pass of a regular expression, longest kinds first.
const TOKEN = /(--\[(=*)\[[\s\S]*?\]\2\]|--[^\n]*)|(\[(=*)\[[\s\S]*?\]\4\]|"(?:\\.|[^"\\\n])*"?|'(?:\\.|[^'\\\n])*'?)|(\b0x[0-9a-fA-F]+\b|\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b)|([A-Za-z_][\w]*(?:\.[A-Za-z_]\w*)?)/g;
export function highlight(text) {
  let out = "", last = 0, m;
  TOKEN.lastIndex = 0;
  while ((m = TOKEN.exec(text))) {
    out += esc(text.slice(last, m.index));
    const [all] = m;
    let cls = null;
    if (m[1]) cls = "c";
    else if (m[3]) cls = "s";
    else if (m[5]) cls = "n";
    else if (KEYWORDS.includes(all)) cls = "k";
    else if (API.includes(all) || CALLBACKS.includes(all)) cls = "f";
    out += cls ? `<span class="${cls}">${esc(all)}</span>` : esc(all);
    last = m.index + all.length;
  }
  return out + esc(text.slice(last)) + "\n";
}

// The asset a call on a line names, at or around column `col`.
export function callAt(line, col) {
  const re = /\b(spr|sfx|music|map\.load|sheet\.load|preload)\(\s*(\d+|"[^"]*")/g;
  let m, best = null;
  while ((m = re.exec(line))) {
    const end = line.indexOf(")", m.index);
    if (m.index <= col && col <= (end < 0 ? line.length : end + 1)) best = m;
  }
  if (!best) return null;
  const arg = best[2].startsWith('"') ? best[2].slice(1, -1) : +best[2];
  const sound = best[1] === "preload" && /^(sfx|music) (\d+)$/.exec(arg);     // preload("sfx 12")
  return sound ? { fn: sound[1], arg: +sound[2] } : { fn: best[1], arg };
}

// What pack numbers sfx(n) and music(n) by: the WAV files of the folder in
// order of name.
export const numbered = (files, folder) =>
  files.filter((f) => f.startsWith(folder + "/") && f.toLowerCase().endsWith(".wav") && f.split("/").length === 2).sort();
