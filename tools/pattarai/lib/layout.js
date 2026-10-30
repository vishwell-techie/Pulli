// Where a game's files live: code/, sprites/, maps/, backdrops/, sfx/ and
// music/, with manifest.lua in the game folder itself. pack takes each file
// by its name alone (code/main.lua is the entry main.lua), and still reads
// files kept in the game folder itself, as older games have them.

export const FOLDERS = { code: "code", sprites: "sprites", maps: "maps", backdrops: "backdrops" };

export const base = (f) => f.slice(f.lastIndexOf("/") + 1);

// files of `ext` in `folder`, or in the game folder itself
export const inFolder = (files, folder, ext) =>
  files.filter((f) => f.endsWith(ext) && (f.startsWith(folder + "/") || !f.includes("/")));

// the file whose name (in any folder) is `name`
export const named = (files, name) => files.find((f) => base(f) === name);

// a name typed for a new file, placed in its folder
export const place = (folder, name) => (name.includes("/") ? name : `${folder}/${name}`);

// the sprite sheets: pictures in sprites/ (or the game folder), not backdrops
// (a .png, or a .kolam kept as the console reads it)
export const sheets = (files) => [...inFolder(files, "sprites", ".png"), ...inFolder(files, "sprites", ".kolam")].sort();
export const backdrops = (files) => files.filter((f) => /\.(png|kolam)$/.test(f) && f.startsWith("backdrops/")).sort();
// The editor a file opens in: Vidhi (code), Kolam (sprite sheets), Ooru
// (maps), Thirai (backdrops), Oli (sound effects), Isai (songs), or none.
export function editorOf(f) {
  if (f.endsWith(".lua")) return "vidhi";
  if (f.endsWith(".tmx")) return "ooru";
  if (/\.(png|kolam)$/.test(f)) return f.startsWith("backdrops/") ? "backdrop" : "kolam";
  if (f.endsWith(".json") && f.startsWith("sfx/")) return "oli";
  if (f.endsWith(".json") && f.startsWith("music/")) return "isai";
  return null;
}

// The picture a game's code gives a map, for `key` (sheet, or bg): the last
// key = "name.kolam" at or above the line that names "<stem>.ooru", as a
// table of rooms has it, its own or the defaults set above it. The name
// without its ending, or null.
export function pictureNamedIn(text, stem, key) {
  const at = text.indexOf(`"${stem}.ooru"`);
  if (at < 0) return null;
  const end = text.indexOf("\n", at);
  const found = [...text.slice(0, end < 0 ? text.length : end).matchAll(new RegExp(`\\b${key}\\s*=\\s*"([\\w-]+)\\.(?:kolam|png)"`, "g"))].pop();
  return found ? found[1] : null;
}

// the name the game uses for a picture: a .png is packed as a .kolam
export const entry = (f) => base(f).replace(/\.png$/, ".kolam");
