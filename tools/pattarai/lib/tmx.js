// Tiled maps (.tmx), the source `pulli pack` turns into a .ooru (SPEC §2).
// Read and written as text so that whatever Tiled keeps in the file and
// this editor does not know about (objects, properties) survives a save.

const FLIP_X = 0x80000000, FLIP_Y = 0x40000000;

function attr(tag, name) {
  const m = tag.match(new RegExp("\\s" + name + "=\"([^\"]*)\""));
  return m ? m[1] : null;
}

// Returns {width, height, firstgid, tileset, layers: [{name, cells}], text}.
// A cell is a tile number (sprite number) with bit 15 for a left-right flip
// and bit 14 for an up-down one, as in a .ooru.
export function parseTMX(text) {
  const head = text.match(/<map\b[^>]*>/);
  if (!head) throw new Error("not a Tiled map");
  const width = +attr(head[0], "width"), height = +attr(head[0], "height");
  if (attr(head[0], "tilewidth") !== "8" || attr(head[0], "tileheight") !== "8")
    throw new Error("tiles must be 8x8 pixels");
  if (attr(head[0], "infinite") === "1") throw new Error("infinite maps are not supported");
  const ts = text.match(/<tileset\b[^>]*>/);
  const firstgid = ts ? +(attr(ts[0], "firstgid") || 1) : 1;
  const layers = [];
  const re = /<layer\b([^>]*)>\s*<data\b([^>]*)>([\s\S]*?)<\/data>/g;
  let m;
  while ((m = re.exec(text))) {
    if (attr(m[2], "encoding") !== "csv")
      throw new Error("layer data must be CSV (Map Properties, Tile Layer Format)");
    const gids = m[3].split(",").map((s) => s.trim()).filter((s) => s).map(Number);
    if (gids.length !== width * height) throw new Error("a layer has the wrong number of tiles");
    const cells = new Uint16Array(gids.map((g) => {
      const id = g & 0x0fffffff;
      if (!id) return 0;
      return (id - firstgid) | (g & FLIP_X ? 0x8000 : 0) | (g & FLIP_Y ? 0x4000 : 0);
    }));
    layers.push({ name: attr(" " + m[1], "name") || "layer", cells });
  }
  return { width, height, firstgid, tileset: ts ? attr(ts[0], "source") : null, layers, text };
}

function csv(cells, width, firstgid) {
  const rows = [];
  for (let y = 0; y < cells.length / width; y++) {
    const row = [];
    for (let x = 0; x < width; x++) {
      const c = cells[y * width + x], n = c & 0x3fff;
      row.push(n ? ((n + firstgid) | (c & 0x8000 ? FLIP_X : 0) | (c & 0x4000 ? FLIP_Y : 0)) >>> 0 : 0);
    }
    rows.push(row.join(","));
  }
  return "\n" + rows.join(",\n") + "\n";
}

// A map's text with its layers' cells put back. Layers past the ones in
// the text are added after the last.
export function writeTMX(map) {
  let i = 0;
  let text = map.text.replace(/(<layer\b[^>]*>\s*<data\b[^>]*>)([\s\S]*?)(<\/data>)/g, (all, a, _, b) => {
    const layer = map.layers[i++];
    return layer ? a + csv(layer.cells, map.width, map.firstgid) + b : all;
  });
  let id = Math.max(0, ...[...text.matchAll(/<layer\b[^>]*\sid="(\d+)"/g)].map((m) => +m[1]));
  for (; i < map.layers.length; i++) {
    const l = map.layers[i];
    const xml = ` <layer id="${++id}" name="${l.name}" width="${map.width}" height="${map.height}">\n` +
      `  <data encoding="csv">${csv(l.cells, map.width, map.firstgid)}</data>\n </layer>\n`;
    text = text.replace(/<\/map>/, xml + "</map>");
  }
  return text.replace(/(<map\b[^>]*\snextlayerid=")\d+/, (_, a) => a + (id + 1));
}

// A new map for the game's sprite sheet (its tileset, sprites.tsx, written
// beside it when the game has none).
export function newTMX(width, height, layers = 2) {
  const text = `<?xml version="1.0" encoding="UTF-8"?>
<map version="1.10" tiledversion="1.10.2" orientation="orthogonal" renderorder="right-down" width="${width}" height="${height}" tilewidth="8" tileheight="8" infinite="0" nextlayerid="1" nextobjectid="1">
 <tileset firstgid="1" source="sprites.tsx"/>
</map>
`;
  const names = ["ground", "top"];
  const map = { width, height, firstgid: 1, tileset: "sprites.tsx", text,
    layers: names.slice(0, layers).map((name) => ({ name, cells: new Uint16Array(width * height) })) };
  map.text = writeTMX(map);
  return map;
}

export function newTSX(sheetWidth, sheetHeight) {
  const cols = sheetWidth / 8, count = cols * (sheetHeight / 8);
  return `<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.10" tiledversion="1.10.2" name="sprites" tilewidth="8" tileheight="8" tilecount="${count}" columns="${cols}">
 <image source="sprites.png" width="${sheetWidth}" height="${sheetHeight}"/>
</tileset>
`;
}
