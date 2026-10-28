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
export const sheets = (files) => inFolder(files, "sprites", ".png");
export const backdrops = (files) => files.filter((f) => f.endsWith(".png") && f.startsWith("backdrops/"));
