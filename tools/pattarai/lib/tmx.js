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

export function newTSX(sheetWidth, sheetHeight, image = "../sprites/sprites.png") {
  const cols = sheetWidth / 8, count = cols * (sheetHeight / 8);
  return `<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.10" tiledversion="1.10.2" name="sprites" tilewidth="8" tileheight="8" tilecount="${count}" columns="${cols}">
 <image source="${image}" width="${sheetWidth}" height="${sheetHeight}"/>
</tileset>
`;
}

// ---- tile flags, kept in the tileset (.tsx) --------------------------------
// pack reads two properties of a tileset's tiles: `flags` (0-255) and
// `solid` (a tick box that sets bit 0); a tile's flags are the two put
// together.

const TILE = /<tile\b[^>]*\bid="(\d+)"[^>]*?(?:\/>|>([\s\S]*?)<\/tile>)/g;

export function parseTSX(text) {
  const head = text.match(/<tileset\b[^>]*>/);
  if (!head) throw new Error("not a Tiled tileset");
  const flags = new Map();
  let m;
  TILE.lastIndex = 0;
  while ((m = TILE.exec(text))) {
    const body = m[2] || "";
    let v = 0;
    const f = body.match(/<property\b[^>]*name="flags"[^>]*>/);
    if (f) v |= (+attr(f[0], "value") || 0) & 255;
    const s = body.match(/<property\b[^>]*name="solid"[^>]*>/);
    if (s && attr(s[0], "value") === "true") v |= 1;
    if (v) flags.set(+m[1], v);
  }
  return { columns: +attr(head[0], "columns") || 0, flags };
}

// The tileset's text with tile `id`'s flags set to `value`; everything else
// in it is kept.
export function setTileFlags(text, id, value) {
  value &= 255;
  const prop = `<property name="flags" type="int" value="${value}"/>`;
  TILE.lastIndex = 0;
  let m, found = null, after = null;
  while ((m = TILE.exec(text))) {
    if (+m[1] === id) { found = m; break; }
    if (+m[1] > id && after === null) after = m.index;
  }
  if (found) {
    let body = found[2] || "";
    if (/<property\b[^>]*name="flags"/.test(body)) body = body.replace(/<property\b[^>]*name="flags"[^>]*\/>/, prop);
    else if (/<properties>/.test(body)) body = body.replace(/<properties>/, `<properties>\n   ${prop}`);
    else body = `\n  <properties>\n   ${prop}\n  </properties>\n ` + body;
    body = body.replace(/(<property\b[^>]*name="solid"[^>]*value=")(true|false)/, (_, a) => a + (value & 1 ? "true" : "false"));
    const open = found[0].match(/^<tile\b[^>]*?(?=\/?>)/)[0];
    return text.slice(0, found.index) + `${open}>${body}</tile>` + text.slice(found.index + found[0].length);
  }
  if (!value) return text;
  const xml = `<tile id="${id}">\n  <properties>\n   ${prop}\n  </properties>\n </tile>\n `;
  if (after !== null) return text.slice(0, after) + xml + text.slice(after);
  return text.replace(/<\/tileset>/, ` ${xml.trimEnd()}\n</tileset>`);
}

// ---- objects, on object layers (SPEC §2: pack keeps them, map.objects reads them)
// Each object layer is {name, open, objects}; each object {id, name, type,
// x, y, w, h, gid, point, props: [{name, type, value}], raw}. An object Ooru
// has not changed is written back as Tiled wrote it (its polygon, text,
// template and all); a changed or new one is written afresh, keeping any
// shape inside it.

const GROUP = /<objectgroup\b[^>]*?(?:\/>|>[\s\S]*?<\/objectgroup>)/g;
const OBJECT = /<object\b[^>]*?(?:\/>|>[\s\S]*?<\/object>)/g;
const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const unesc = (s) => (s == null ? s : s.replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&"));

export function parseObjects(text) {
  const groups = [];
  for (const g of text.matchAll(GROUP)) {
    const open = g[0].match(/^<objectgroup\b[^>]*?(?=\/?>)/)[0];
    const objects = [];
    for (const o of g[0].matchAll(OBJECT)) {
      const tag = o[0].match(/^<object\b[^>]*>/)[0];
      const props = [...o[0].matchAll(/<property\b[^>]*?(?:\/>|>([\s\S]*?)<\/property>)/g)].map((p) => {
        const t = p[0].match(/^<property\b[^>]*>/)[0];
        return { name: unesc(attr(t, "name")) || "", type: attr(t, "type") || "string",
                 value: unesc(attr(t, "value") ?? p[1] ?? "") };
      });
      objects.push({ id: +attr(tag, "id") || 0, name: unesc(attr(tag, "name")) || "",
        type: unesc(attr(tag, "class") ?? attr(tag, "type")) || "",
        x: +attr(tag, "x") || 0, y: +attr(tag, "y") || 0, w: +attr(tag, "width") || 0, h: +attr(tag, "height") || 0,
        gid: attr(tag, "gid") ? +attr(tag, "gid") : null, point: /<point\s*\/>/.test(o[0]),
        props, raw: o[0] });
    }
    groups.push({ name: unesc(attr(open, "name")) || "", open, objects, raw: g[0] });
  }
  return groups;
}

function objectXML(o) {
  if (o.raw && !o.changed) return o.raw;
  const shape = o.raw ? (o.raw.match(/<(polygon|polyline)\b[^>]*\/>|<ellipse\s*\/>|<text\b[\s\S]*?<\/text>/) || [""])[0] : "";
  let a = `<object id="${o.id}"` + (o.name ? ` name="${esc(o.name)}"` : "") + (o.type ? ` class="${esc(o.type)}"` : "") +
    (o.gid ? ` gid="${o.gid >>> 0}"` : "") + ` x="${o.x}" y="${o.y}"` +
    (o.w || o.h ? ` width="${o.w}" height="${o.h}"` : "");
  const props = o.props.filter((p) => p.name);
  const inner = (props.length ? "\n   <properties>\n" + props.map((p) =>
    `    <property name="${esc(p.name)}"` + (p.type && p.type !== "string" ? ` type="${p.type}"` : "") +
    ` value="${esc(p.value)}"/>`).join("\n") + "\n   </properties>" : "") +
    (o.point ? "\n   <point/>" : shape ? "\n   " + shape : "");
  return inner ? `${a}>${inner}\n  </object>` : `${a}/>`;
}

function groupXML(g) {
  const was = g.raw && parseObjects(g.raw)[0];
  if (was && was.name === g.name && was.objects.length === g.objects.length &&
      g.objects.every((o, i) => !o.changed && o.raw === was.objects[i].raw)) return g.raw;
  const open = / name="/.test(g.open) ? g.open.replace(/ name="[^"]*"/, ` name="${esc(g.name)}"`)
    : g.open.replace(/^<objectgroup/, `<objectgroup name="${esc(g.name)}"`);
  if (!g.objects.length) return `${open}/>`;
  return `${open}>\n  ` + g.objects.map(objectXML).join("\n  ") + "\n </objectgroup>";
}

// The map's text with its object layers as `groups` says: each existing
// one rewritten in place, removed ones taken out, new ones added at the end,
// and the map's next object id past every id in it.
export function writeObjects(text, groups) {
  let i = 0;
  text = text.replace(GROUP, () => (i < groups.length ? groupXML(groups[i++]) : ""));
  let layerId = Math.max(0, ...[...text.matchAll(/<(?:layer|objectgroup|imagelayer|group)\b[^>]*\sid="(\d+)"/g)].map((m) => +m[1]));
  for (; i < groups.length; i++) {
    const g = groups[i];
    g.open = `<objectgroup id="${++layerId}" name="${esc(g.name)}"`;
    text = text.replace(/<\/map>/, " " + groupXML(g) + "\n</map>");
  }
  const ids = groups.flatMap((g) => g.objects.map((o) => o.id));
  const next = Math.max(0, ...ids, ...[...text.matchAll(/<object\b[^>]*\sid="(\d+)"/g)].map((m) => +m[1])) + 1;
  text = /<map\b[^>]*\snextobjectid="/.test(text) ? text.replace(/(<map\b[^>]*\snextobjectid=")(\d+)/, (_, a, n) => a + Math.max(+n, next))
    : text.replace(/<map\b/, `<map nextobjectid="${next}"`);
  return text.replace(/(<map\b[^>]*\snextlayerid=")(\d+)/, (_, a, n) => a + Math.max(+n, layerId + 1));
}

// An object's box in pixels as pack reads it: a tile object's y is its
// bottom in Tiled, so its top is y - h.
export const objectTop = (o) => (o.gid ? o.y - o.h : o.y);
