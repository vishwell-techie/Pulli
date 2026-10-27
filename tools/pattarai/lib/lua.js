// Lua for Vidhi: colouring it, and finding the asset a call names.

// The functions a game gets, with their arguments and what they do, as
// SPEC §3 has them; tests/test_pattarai.py checks this against the spec.
export const SIGS = {
  "backdrop": ["name", "a picture each frame starts from; backdrop() lets it go"],
  "btn": ["b", "held.  b = \"left\",\"right\",\"up\",\"down\",\"a\",\"b\",\"x\",\"y\",\"l\",\"r\",\"start\",\"select\""],
  "btnp": ["b", "pressed this frame (with repeat, except \"start\" and \"select\")"],
  "camera": ["x, y", "world -> screen offset"],
  "circ": ["x,y,r,c", ""],
  "circfill": ["x,y,r,c", ""],
  "clip": ["x, y, w, h", "nil = reset"],
  "cls": ["c", "clear to palette index c (default 0); cls() starts from the backdrop, if set"],
  "dbg": ["...", "printf to host console / device serial; stripped in release"],
  "fade": ["amount", "0..1, palette-level, free"],
  "fix.atan": ["y [, x]", "angles in radians"],
  "fix.cos": ["a", "angles in radians"],
  "fix.div": ["a, b", ""],
  "fix.floor": ["a", "the whole part, as an integer, rounded down"],
  "fix.from": ["n", "a number as fixed point; an integer n means n whole units"],
  "fix.mul": ["a, b", ""],
  "fix.sin": ["a", "angles in radians"],
  "fix.sqrt": ["a", ""],
  "fix.to": ["a", "fixed point as a float"],
  "font": ["size", "\"normal\" or \"small\": the size Tamil is drawn at"],
  "line": ["x0,y0,x1,y1,c", ""],
  "link.recv": ["", "the next message that arrived, or nil"],
  "link.send": ["msg", "queue a string for the other console; true if accepted"],
  "link.side": ["", "1 or 2 while connected, otherwise nil"],
  "link.status": ["", "\"off\" (no link hardware), \"waiting\" or \"connected\""],
  "load": ["key, default", ""],
  "map.draw": ["layer, sx, sy", "layer 0 = behind, 1 = in front; sx, sy optional"],
  "map.flags": ["tile", "8 collision/meta bits per tile"],
  "map.get": ["layer, cx, cy", "tile, flip_x, flip_y"],
  "map.load": ["name", "load another map from the package (default \"map.ooru\")"],
  "map.set": ["layer, cx, cy, tile, flip_x, flip_y", ""],
  "map.size": ["", "width, height in tiles; 0, 0 with no map"],
  "music": ["n, fade_ms, loop", "play track n; fade_ms optional (0), loop optional (true)"],
  "music_pause": ["paused", "true (the default) holds the music still; false carries on"],
  "music_stop": ["fade_ms", ""],
  "pal": ["a, b", "remap palette index a -> b"],
  "palette": ["c, r, g, b", "give colour c new RGB; palette(c) reads it (§5)"],
  "palt": ["c, is_transparent", ""],
  "pget": ["x, y", ""],
  "preload": ["name, ...", "read parts of the package into memory now"],
  "print": ["text, x, y, c", "UTF-8, English and Tamil; returns the x after it"],
  "pset": ["x, y, c", ""],
  "rect": ["x,y,w,h,c", ""],
  "rectfill": ["x,y,w,h,c", ""],
  "save": ["key, value", "value: number, string, boolean, or a table"],
  "save_commit": ["", "flush to storage now"],
  "sfx": ["n, channel", "play sound n; channel optional, -1 = auto"],
  "shade": ["c, lights, edge", "darkness with lights cut out of it"],
  "sheet.load": ["name", "use another sprite sheet from the package"],
  "spr": ["n, x, y, w, h, flip_x, flip_y", "n = sprite index; w,h in 8px cells"],
  "sspr": ["sx,sy,sw,sh, dx,dy, dw,dh", "stretched blit"],
  "stat": ["\"what\"", "\"fps\", \"mem\", \"cpu\", \"frame\" or \"active\" (KB of the package in memory)"],
  "sys.has": ["cap", "\"video\",\"wifi\",\"cart\",\"rumble\",\"link\" -- hardware varies by variant"],
  "text_size": ["text", "width of the widest line and height of all, in pixels"],
  "time": ["", "seconds since the game started: stat(\"frame\") / 60"],
};
export const API = Object.keys(SIGS);
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
  const re = /\b(spr|sfx|music|map\.load|sheet\.load|backdrop|preload)\(\s*(\d+|"[^"]*")/g;
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


// The name being typed just before `at`, and where it starts.
export function wordBefore(text, at) {
  const m = text.slice(0, at).match(/[A-Za-z_][\w]*(?:\.[A-Za-z_]?\w*)?$/);
  return m ? { word: m[0], start: at - m[0].length } : null;
}

// Names to offer for what is typed: the API, then the file's own names.
export function complete(word, text) {
  if (!word || word.length < 2) return [];
  const own = new Set(text.match(/\b(?:local\s+function|function|local)\s+([A-Za-z_][\w.:]*)/g)?.map((s) => s.split(/\s+/).pop()) || []);
  const all = [...API, ...CALLBACKS, ...[...own].filter((n) => !API.includes(n))];
  return all.filter((n) => n.startsWith(word) && n !== word).slice(0, 12);
}

// The API call the cursor is inside, and which argument: for the hint.
export function callHint(text, at) {
  let depth = 0, args = 0;
  for (let i = at - 1; i >= 0 && text[i] !== "\n"; i--) {
    const ch = text[i];
    if (ch === ")") depth++;
    else if (ch === "(") {
      if (depth) { depth--; continue; }
      const m = text.slice(0, i).match(/([A-Za-z_][\w]*(?:\.[A-Za-z_]\w*)?)\s*$/);
      if (m && SIGS[m[1]]) return { name: m[1], arg: args, sig: SIGS[m[1]] };
      return null;
    } else if (ch === "," && !depth) args++;
  }
  return null;
}
