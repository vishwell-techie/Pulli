#!/usr/bin/env python3
"""pulli.py — the Pulli command line (SPEC §6) and package format (SPEC §2).

    python3 tools/pulli.py new    <dir>                    start a new game
    python3 tools/pulli.py pack   <dir> [out.pulli]        build a package
    python3 tools/pulli.py list   <game.pulli>             show what is inside
    python3 tools/pulli.py unpack <game.pulli> <dir>       extract the files
    python3 tools/pulli.py run    <dir|game.pulli> [scale] [--link PORT]
                                                           play it in a window
    python3 tools/pulli.py check  <dir|game.pulli> [frames] run it with no window
    python3 tools/pulli.py palette [<dir|game.pulli>] <out.gpl|out.hex|out.png>
                                                           the 64 colours, standard or a
                                                           game's own, for a paint program
    python3 tools/pulli.py add    [<dir> helper...]        copy SDK helpers into a game to
                                                           change them; alone, list them

Deliberately dependency-free: this has to run on a student's laptop with a
stock Python install and nothing else. `run` and `check` also need the host
built (see README.md).
"""
import base64, gzip, hashlib, os, re, shlex, shutil, struct, subprocess, sys, tempfile, zlib
import xml.etree.ElementTree as ET

MAGIC = b"PULI"
VERSION = 1
HEADER = 16
ENTRY = 40
NAME_MAX = 32
MAX_ENTRIES = 64
REQUIRED = ("manifest.lua", "main.lua")
EXT = ".pulli"

# Header flags. Reserved now, before the format ships, because adding them
# later would break every package and every device in the field.
FLAG_ENCRYPTED = 0x01   # payload entries are wrapped; the licence unwraps them
FLAG_SIGNED    = 0x02   # package carries a publisher signature
FLAG_DEVBUILD  = 0x04   # unsigned developer build, never store-distributed

# The seal: a licence and a signature that follow the package, outside its
# size and checksum, so a store can replace them without rebuilding it.
SEAL_MAGIC = b"SEAL"
SEAL_VERSION = 1
SEAL_HEADER = 12
LICENCE_DEVELOPER = 0     # runs on any device; not for sale
SIGNATURE_DEVELOPER = 0   # SHA-256 of the package: catches damage, proves nothing
KIND_NAMES = {0: "developer"}

# Sound banks (SPEC §2). `pack` builds them from the .wav files in a game's
# sfx/ and music/ folders, in order of file name.
BANKS = {"sfx": ("sfx.oli", b"OLI1"), "music": ("music.isai", b"ISA1")}
BANK_HEADER = 8
CLIP_ENTRY = 28
CLIP_MAX = 256
CLIP_RATES = (4000, 48000)
PCM, ADPCM = 0, 1
ADPCM_STEP = (
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
    50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230,
    253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963,
    1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327,
    3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442,
    11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794,
    32767)
ADPCM_INDEX = (-1, -1, -1, -1, 2, 4, 6, 8)

# Pictures and maps (SPEC §2). `pack` turns every .png in a game folder into
# a .kolam sprite sheet and every Tiled .tmx map into a .ooru.
CELL = 8
ATLAS_MAX = 128 * 1024
MAP_CELLS_MAX = 32768
TILE_MAX = 0x3FFF
FLIP_X, FLIP_Y = 0x8000, 0x4000
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


class PackageError(Exception):
    pass


def _align4(n: int) -> int:
    return (n + 3) & ~3


def seal(body: bytes, licence_kind: int = LICENCE_DEVELOPER, licence: bytes = b"",
         signature_kind: int = SIGNATURE_DEVELOPER, signature: bytes = None) -> bytes:
    """Return `body` with a licence and signature attached. By default these
    are the developer ones, which is what every locally built package gets."""
    if signature is None:
        signature = hashlib.sha256(body).digest()
    return (body + SEAL_MAGIC +
            struct.pack("<BBBBHH", SEAL_VERSION, licence_kind, signature_kind, 0,
                        len(licence), len(signature)) + licence + signature)


def split(data: bytes):
    """Separate a package file into the package itself and whatever follows it."""
    if len(data) < HEADER or data[:4] != MAGIC:
        raise PackageError("not a Pulli package")
    total = struct.unpack("<I", data[8:12])[0]
    if total > len(data):
        raise PackageError(f"package is truncated (header says {total}, file is {len(data)})")
    return data[:total], data[total:]


def read_seal(data: bytes):
    """Check the seal and return (licence kind, licence, signature kind, signature)."""
    body, tail = split(data)
    if len(tail) < SEAL_HEADER or tail[:4] != SEAL_MAGIC:
        raise PackageError("package has no licence and signature")
    version, lic_kind, sig_kind, _, lic_len, sig_len = struct.unpack("<BBBBHH", tail[4:SEAL_HEADER])
    if version != SEAL_VERSION:
        raise PackageError(f"unsupported licence and signature version {version}")
    if SEAL_HEADER + lic_len + sig_len != len(tail):
        raise PackageError("licence and signature are the wrong length")
    licence = tail[SEAL_HEADER:SEAL_HEADER + lic_len]
    signature = tail[SEAL_HEADER + lic_len:]
    if sig_kind == SIGNATURE_DEVELOPER and signature != hashlib.sha256(body).digest():
        raise PackageError("signature does not match: the package was changed after it was signed")
    return lic_kind, licence, sig_kind, signature


def build_entries(entries, flags: int = 0) -> bytes:
    """Lay out (name, bytes) pairs as a sealed package. No policy, just the format."""
    if len(entries) > MAX_ENTRIES:
        raise PackageError(f"{len(entries)} entries, max {MAX_ENTRIES}")
    for name, _ in entries:
        if not name or len(name) > NAME_MAX or not name.isascii() or not name.isprintable() \
                or "/" in name or "\\" in name:
            raise PackageError(f"bad entry name (1 to {NAME_MAX} plain ASCII characters): {name!r}")
    if len({name for name, _ in entries}) != len(entries):
        raise PackageError("two entries share a name")

    # Payload starts after header + entry table, and every entry is 4-byte
    # aligned so the MCU can read structures in place from XIP flash.
    offset = _align4(HEADER + ENTRY * len(entries))
    table, payload = b"", b""
    cursor = offset
    for name, blob in entries:
        pad = _align4(cursor) - cursor
        payload += b"\0" * pad
        cursor += pad
        table += name.encode("ascii").ljust(NAME_MAX, b"\0") + struct.pack("<II", cursor, len(blob))
        payload += blob
        cursor += len(blob)

    table_pad = b"\0" * (offset - (HEADER + ENTRY * len(entries)))
    body = table + table_pad + payload
    total = HEADER + len(body)
    crc = zlib.crc32(body) & 0xFFFFFFFF
    return seal(MAGIC + struct.pack("<BBHII", VERSION, flags, len(entries), total, crc) + body)


def build(srcdir: str, flags: int = 0, notes=None) -> bytes:
    """Package every file in a game directory, turning .png, .tmx and .wav
    files into the formats the console reads. Anything worth telling the
    developer is added to `notes`."""
    if not os.path.isdir(srcdir):
        raise PackageError(f"{srcdir} is not a directory")
    names = sorted(
        f for f in os.listdir(srcdir)
        if os.path.isfile(os.path.join(srcdir, f)) and not f.startswith(".")
    )
    for req in REQUIRED:
        if req not in names:
            raise PackageError(f"{srcdir} is missing {req}")
    entries, made = [], {}
    sources = [n for n in names if n in ("palette.hex", "palette.gpl")]
    if len(sources) > 1:
        raise PackageError(f"{srcdir} has both palette.hex and palette.gpl; keep one")
    if "palette.pal" in names and sources:
        raise PackageError(f"{srcdir} has both palette.pal and {sources[0]}; keep one")
    colours = game_palette(srcdir)
    if sources:
        entries.append(("palette.pal", palette_entry(colours)))
    for n in names:
        stem, ext = os.path.splitext(n)
        ext = ext.lower()
        if n in sources:
            continue
        if ext in (".png", ".tmx"):
            made[stem + (".kolam" if ext == ".png" else ".ooru")] = n
        elif ext != ".tsx":                             # a Tiled tileset is read through its map
            with open(os.path.join(srcdir, n), "rb") as f:
                entries.append((n, f.read()))
    for entry, source in made.items():
        if entry in names:
            raise PackageError(f"{srcdir} has both {entry} and {source}; keep one")
    sheet_columns = None                                # tiles across the sheet, for checking maps
    for entry, source in sorted(made.items()):
        if entry.endswith(".kolam"):
            with open(os.path.join(srcdir, source), "rb") as f:
                entries.append((entry, kolam_from_png(f.read(), source, notes, colours)))
    for name, blob in entries:
        if name == "sprites.kolam":
            sheet_columns = struct.unpack("<H", blob[4:6])[0] // CELL
    for entry, source in sorted(made.items()):
        if entry.endswith(".ooru"):
            entries.append((entry, ooru_from_tmx(os.path.join(srcdir, source), sheet_columns, notes)))
    for kind, (entry, _) in BANKS.items():
        folder = os.path.join(srcdir, kind)
        if not os.path.isdir(folder) or not any(f.lower().endswith(".wav") for f in os.listdir(folder)):
            continue
        if entry in names:
            raise PackageError(f"{srcdir} has both {entry} and a {kind}/ folder; keep one")
        entries.append((entry, bank_from_folder(kind, folder)))
    add_helpers(entries)
    return build_entries(sorted(entries), flags)


def required(source: bytes):
    """The modules a Lua file asks for with require("name"). Comments are
    left out, so a helper mentioned in one is not taken for a real request."""
    text = source.decode("utf-8", "replace")
    text = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.S)
    text = re.sub(r"--[^\n]*", "", text)
    return set(re.findall(r"""\brequire\s*\(?\s*["']([A-Za-z0-9_]+)["']""", text))


def add_helpers(entries):
    """Supply the SDK helpers a game requires but does not have. A file of
    the game's own always comes first, so a game changes a helper by keeping
    its own copy of it (`pulli.py add`). A helper may require another."""
    have = {name for name, _ in entries}
    waiting = [blob for name, blob in entries if name.endswith(".lua") and name != "manifest.lua"]
    while waiting:
        for module in sorted(required(waiting.pop())):
            entry = module + ".lua"
            if entry in have:
                continue
            path = os.path.join(sdk_dir(), entry)
            if not os.path.isfile(path):
                raise PackageError(f"the game requires '{module}', but there is no {entry} in its folder "
                                   f"and no helper of that name in the SDK")
            with open(path, "rb") as f:
                blob = f.read()
            entries.append((entry, blob))
            have.add(entry)
            waiting.append(blob)


def parse(data: bytes):
    """Validate a package and its seal, and return its (name, bytes) entries."""
    whole = data
    data, _ = split(data)
    version, flags, count, total, crc = struct.unpack("<BBHII", data[4:16])
    if version != VERSION:
        raise PackageError(f"unsupported package version {version}")
    if count > MAX_ENTRIES or HEADER + count * ENTRY > total:
        raise PackageError("entry table runs past the end of the package")
    if (zlib.crc32(data[HEADER:]) & 0xFFFFFFFF) != crc:
        raise PackageError("checksum mismatch: package is corrupt")
    entries = []
    for i in range(count):
        e = data[HEADER + i * ENTRY: HEADER + (i + 1) * ENTRY]
        name = e[:NAME_MAX].rstrip(b"\0").decode("ascii", "replace")
        off, length = struct.unpack("<II", e[NAME_MAX:])
        if off < HEADER + count * ENTRY or off + length > len(data):
            raise PackageError(f"entry {name} lies outside the package")
        entries.append((name, data[off:off + length]))
    read_seal(whole)
    return entries


def read(path: str):
    with open(path, "rb") as f:
        return parse(f.read())


def kolam(width: int, height: int, pixels: bytes) -> bytes:
    """A sprites.kolam sheet: 8-bit indexed pixels, row by row (SPEC §2)."""
    if width % 8 or height % 8 or width <= 0 or height <= 0:
        raise PackageError("sprite sheet width and height must be multiples of 8")
    if len(pixels) != width * height:
        raise PackageError(f"expected {width * height} pixels, got {len(pixels)}")
    return b"KLM1" + struct.pack("<HH", width, height) + bytes(pixels)


# ---- pictures -----------------------------------------------------------

def palette():
    """The 64 colours as (red, green, blue), in palette order."""
    import refgfx
    return [((c >> 16) & 255, (c >> 8) & 255, c & 255) for c in refgfx.DEFAULT_PALETTE]


def read_png(data: bytes, name: str = "picture"):
    """Read a .png file. Returns (width, height, pixels), with `pixels` a
    list of (red, green, blue, alpha), each 0 to 255, row by row."""
    if data[:8] != PNG_MAGIC:
        raise PackageError(f"{name}: not a PNG file")
    header = colours = clear = None
    packed, at = b"", 8
    while at + 8 <= len(data):
        size, tag = struct.unpack(">I4s", data[at:at + 8])
        chunk = data[at + 8:at + 8 + size]
        if tag == b"IHDR":
            header = chunk
        elif tag == b"PLTE":
            colours = chunk
        elif tag == b"tRNS":
            clear = chunk
        elif tag == b"IDAT":
            packed += chunk
        at += 12 + size
    if header is None or len(header) != 13 or not packed:
        raise PackageError(f"{name}: PNG file has no picture in it")
    w, h, depth, kind, _, _, interlaced = struct.unpack(">IIBBBBB", header)
    if interlaced:
        raise PackageError(f"{name}: interlaced PNG files are not supported; save it without interlacing")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(kind)
    if channels is None or depth not in (1, 2, 4, 8, 16) or (depth < 8 and kind not in (0, 3)) \
            or (kind == 3 and (depth == 16 or colours is None)):
        raise PackageError(f"{name}: unsupported kind of PNG file")
    step = max(1, channels * depth // 8)            # bytes between a value and the one to its left
    stride = (w * channels * depth + 7) // 8
    try:
        raw = zlib.decompress(packed)
    except zlib.error:
        raise PackageError(f"{name}: PNG file is damaged")
    if w == 0 or h == 0 or len(raw) != h * (stride + 1):
        raise PackageError(f"{name}: PNG file is damaged")

    # Each row is stored as differences from its neighbours; undo that.
    rows, above = [], bytearray(stride)
    for y in range(h):
        kind_of_row = raw[y * (stride + 1)]
        row = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            left = row[i - step] if i >= step else 0
            up = above[i]
            corner = above[i - step] if i >= step else 0
            if kind_of_row == 1:
                row[i] = (row[i] + left) & 255
            elif kind_of_row == 2:
                row[i] = (row[i] + up) & 255
            elif kind_of_row == 3:
                row[i] = (row[i] + (left + up) // 2) & 255
            elif kind_of_row == 4:
                p = left + up - corner
                near = min((abs(p - left), 0, left), (abs(p - up), 1, up), (abs(p - corner), 2, corner))
                row[i] = (row[i] + near[2]) & 255
            elif kind_of_row != 0:
                raise PackageError(f"{name}: PNG file is damaged")
        rows.append(row)
        above = row

    pixels = []
    for row in rows:
        if depth == 16:
            values = row[0::2]                      # keep the top 8 bits
        elif depth == 8:
            values = row
        else:
            values = [(row[i * depth // 8] >> (8 - depth - i * depth % 8)) & ((1 << depth) - 1)
                      for i in range(w * channels)]
            if kind == 0:
                values = [v * 255 // ((1 << depth) - 1) for v in values]
        for x in range(w):
            v = values[x * channels:(x + 1) * channels]
            if kind == 0:
                pixels.append((v[0], v[0], v[0], 255))
            elif kind == 2:
                pixels.append((v[0], v[1], v[2], 255))
            elif kind == 3:
                if 3 * v[0] + 2 >= len(colours):
                    raise PackageError(f"{name}: PNG file is damaged")
                alpha = clear[v[0]] if clear is not None and v[0] < len(clear) else 255
                pixels.append((colours[3 * v[0]], colours[3 * v[0] + 1], colours[3 * v[0] + 2], alpha))
            elif kind == 4:
                pixels.append((v[0], v[0], v[0], v[1]))
            else:
                pixels.append(tuple(v))
    return w, h, pixels


def write_png(width: int, height: int, rgb: bytes) -> bytes:
    """A PNG file from 8-bit red, green, blue values, row by row."""
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))
    rows = b"".join(b"\0" + rgb[y * width * 3:(y + 1) * width * 3] for y in range(height))
    return (PNG_MAGIC + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def read_palette(data: bytes, name: str = "palette"):
    """The 64 colours of a palette.hex (one rrggbb per line) or palette.gpl
    (GIMP, Aseprite and Krita's format), as (red, green, blue)."""
    text = data.decode("utf-8", "replace")
    colours = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith(("GIMP", "Name:", "Columns:", "//", ";")):
            continue
        parts = line.lstrip("#").split()
        if line.startswith("#") and not re.fullmatch(r"#[0-9a-fA-F]{6}", line):
            continue                                    # a comment in a .gpl
        if len(parts) == 1 and re.fullmatch(r"[0-9a-fA-F]{6}", parts[0]):
            v = int(parts[0], 16)
            colours.append(((v >> 16) & 255, (v >> 8) & 255, v & 255))
        elif len(parts) >= 3 and all(p.isdigit() and int(p) < 256 for p in parts[:3]):
            colours.append(tuple(int(p) for p in parts[:3]))
        else:
            raise PackageError(f"{name}: cannot read the line {line!r}")
    if len(colours) != 64:
        raise PackageError(f"{name}: has {len(colours)} colours; a palette has exactly 64")
    return colours


def read_palette_entry(data: bytes, name: str = "palette.pal"):
    """The colours in a palette.pal."""
    if len(data) != 196 or data[:4] != b"PAL1":
        raise PackageError(f"{name}: not a palette of 64 colours")
    return [tuple(data[4 + 3 * i:7 + 3 * i]) for i in range(64)]


def game_palette(srcdir: str):
    """A game folder's own colours, from palette.hex, palette.gpl or a
    ready-made palette.pal, or None if it uses the standard ones."""
    for name in ("palette.hex", "palette.gpl", "palette.pal"):
        path = os.path.join(srcdir, name)
        if os.path.isfile(path):
            with open(path, "rb") as f:
                data = f.read()
            return read_palette_entry(data, name) if name.endswith(".pal") else read_palette(data, name)
    return None


def palette_entry(colours) -> bytes:
    """A palette.pal entry: "PAL1", then red, green, blue for each colour."""
    return b"PAL1" + bytes(v for c in colours for v in c)


def kolam_from_png(data: bytes, name: str = "picture", notes=None, colours=None) -> bytes:
    """Turn a PNG into a sprite sheet. A see-through pixel becomes colour 0;
    any other becomes the nearest of colours 1 to 63, so solid black is
    colour 32 and stays visible. Says so in `notes` if colours had to move."""
    w, h, pixels = read_png(data, name)
    if w % CELL or h % CELL:
        raise PackageError(f"{name}: {w}x{h}; a sprite sheet's width and height must be multiples of {CELL}")
    if w * h > ATLAS_MAX:
        raise PackageError(f"{name}: {w}x{h} is {w * h} pixels; a sprite sheet holds at most {ATLAS_MAX}")
    which = "the game's palette" if colours else "the Pulli palette"
    colours, found, moved = colours or palette(), {}, set()
    out = bytearray()
    for r, g, b, a in pixels:
        if a < 128:
            out.append(0)
            continue
        if (r, g, b) not in found:
            far, index = min(((r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2, i)
                             for i, (pr, pg, pb) in enumerate(colours) if i)
            found[(r, g, b)] = index
            if far:
                moved.add((r, g, b))
        out.append(found[(r, g, b)])
    if moved and notes is not None:
        notes.append(f"{name}: {len(moved)} colour(s) are not in {which} and were changed to the "
                     f"nearest one (`pulli.py palette` writes the palette for a paint program)")
    return kolam(w, h, bytes(out))


# ---- maps ---------------------------------------------------------------

def ooru(width: int, height: int, layers, flags: bytes = b"") -> bytes:
    """A map.ooru: one or two layers of cells, row by row, then one byte of
    flags per tile number (SPEC §2). A cell is a tile number, plus FLIP_X
    and FLIP_Y."""
    if not 1 <= len(layers) <= 2:
        raise PackageError(f"{len(layers)} layers; a map has one or two")
    if width < 1 or height < 1 or width * height * len(layers) > MAP_CELLS_MAX:
        raise PackageError(f"{width}x{height} tiles in {len(layers)} layer(s); "
                           f"a map holds at most {MAP_CELLS_MAX} tiles in all")
    if any(len(layer) != width * height for layer in layers):
        raise PackageError("a layer does not match the map's size")
    if len(flags) > TILE_MAX + 1:
        raise PackageError("flags for more tiles than there can be")
    cells = [c for layer in layers for c in layer]
    return (b"ORU1" + struct.pack("<HHBBH", width, height, len(layers), 0, len(flags))
            + struct.pack(f"<{len(cells)}H", *cells) + bytes(flags))


def read_ooru(data: bytes):
    """A map as (width, height, layers, flags)."""
    w, h, count, _, nflags = struct.unpack("<HHBBH", data[4:12])
    cells = struct.unpack(f"<{w * h * count}H", data[12:12 + 2 * w * h * count])
    return w, h, [list(cells[i * w * h:(i + 1) * w * h]) for i in range(count)], data[12 + 2 * w * h * count:]


def ooru_from_tmx(path: str, sheet_columns: int = None, notes=None) -> bytes:
    """Turn a map made in Tiled into a map.ooru. The map must use 8x8 tiles
    from one tileset, which should be the game's sprite sheet: tile number n
    is drawn as sprite n. The first two tile layers become layers 0 and 1."""
    name = os.path.basename(path)

    def fail(why):
        raise PackageError(f"{name}: {why}")

    def number(element, key, default=None):
        try:
            return int(element.get(key, default))
        except (TypeError, ValueError):
            fail(f"'{key}' is missing or not a number")

    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        fail("not a Tiled map")
    if root.tag != "map":
        fail("not a Tiled map")
    if root.get("orientation", "orthogonal") != "orthogonal":
        fail("only square-grid (orthogonal) maps are supported")
    if root.get("infinite", "0") == "1":
        fail("infinite maps are not supported; turn off 'Infinite' in Map Properties")
    if number(root, "tilewidth") != CELL or number(root, "tileheight") != CELL:
        fail(f"tiles must be {CELL}x{CELL} pixels")
    w, h = number(root, "width"), number(root, "height")

    tilesets = root.findall("tileset")
    if len(tilesets) != 1:
        fail(f"{len(tilesets)} tilesets; a map must use exactly one, the game's sprite sheet")
    first = number(tilesets[0], "firstgid", 1)
    tileset = tilesets[0]
    if tileset.get("source"):
        try:
            tileset = ET.parse(os.path.join(os.path.dirname(path), tileset.get("source"))).getroot()
        except (OSError, ET.ParseError):
            fail(f"cannot read its tileset, {tilesets[0].get('source')}")
    columns = number(tileset, "columns", 0)
    if sheet_columns and columns and columns != sheet_columns:
        fail(f"its tileset is {columns} tiles wide but the sprite sheet is {sheet_columns}: "
             f"tile numbers would not match sprite numbers")

    flags = bytearray()
    for tile in tileset.findall("tile"):
        value = 0
        for prop in tile.iter("property"):
            if prop.get("name") == "flags":
                value |= number(prop, "value", 0) & 255
            elif prop.get("name") == "solid" and prop.get("value") == "true":
                value |= 1
        if value:
            n = number(tile, "id")
            if n > TILE_MAX:
                fail(f"tile {n} is past the highest tile number, {TILE_MAX}")
            flags.extend(bytes(n + 1 - len(flags)))
            flags[n] = value

    layers, used_first = [], False
    for layer in root.iter("layer"):
        data = layer.find("data")
        if data is None:
            fail(f"layer '{layer.get('name')}' has no tiles")
        text, encoding, squeeze = (data.text or "").strip(), data.get("encoding"), data.get("compression")
        try:
            if encoding == "csv":
                gids = [int(v) for v in text.split(",") if v.strip()]
            elif encoding == "base64" and squeeze in (None, "zlib", "gzip"):
                raw = base64.b64decode(text)
                raw = zlib.decompress(raw) if squeeze == "zlib" else gzip.decompress(raw) if squeeze else raw
                gids = list(struct.unpack(f"<{len(raw) // 4}I", raw[:len(raw) // 4 * 4]))
            else:
                fail("unsupported layer format; in Map Properties set Tile Layer Format to CSV")
        except (ValueError, OSError, zlib.error):
            fail(f"layer '{layer.get('name')}' is damaged")
        if len(gids) != w * h:
            fail(f"layer '{layer.get('name')}' has {len(gids)} tiles, not {w}x{h}")
        cells = []
        for gid in gids:
            if gid & 0x20000000:
                fail("a tile is rotated; only flipping left-right and up-down is supported")
            n = (gid & 0x0FFFFFFF) - first if gid & 0x0FFFFFFF else 0
            if n < 0 or n > TILE_MAX:
                fail(f"a tile number is outside 0 to {TILE_MAX}")
            used_first = used_first or (gid & 0x0FFFFFFF) == first
            cells.append(n | (FLIP_X if gid & 0x80000000 else 0) | (FLIP_Y if gid & 0x40000000 else 0) if n else 0)
        layers.append(cells)
    if used_first and notes is not None:
        notes.append(f"{name}: uses the first tile of the sheet, which maps never draw; keep that tile blank")
    others = [e.tag for e in root.iter() if e.tag in ("objectgroup", "imagelayer")]
    if others and notes is not None:
        notes.append(f"{name}: object and image layers are not imported")
    try:
        return ooru(w, h, layers, bytes(flags))
    except PackageError as e:
        fail(str(e))


# ---- sound --------------------------------------------------------------

def read_wav(data: bytes, name: str = "sound"):
    """Read a .wav file. Returns (rate, channels, samples, loop start), with
    `samples` a flat list of 16-bit values, left then right when stereo, and
    the loop start a frame number or None if the file marks no loop."""
    if len(data) < 12 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise PackageError(f"{name}: not a WAV file")
    fmt = body = loop = None
    at = 12
    while at + 8 <= len(data):
        tag, size = data[at:at + 4], struct.unpack("<I", data[at + 4:at + 8])[0]
        chunk = data[at + 8:at + 8 + size]
        if tag == b"fmt ":
            fmt = chunk
        elif tag == b"data":
            body = chunk
        elif tag == b"smpl" and len(chunk) >= 60 and struct.unpack("<I", chunk[28:32])[0] >= 1:
            loop = struct.unpack("<I", chunk[44:48])[0]
        at += 8 + size + (size & 1)
    if fmt is None or body is None or len(fmt) < 16:
        raise PackageError(f"{name}: WAV file has no sound in it")
    kind, channels, rate, _, _, bits = struct.unpack("<HHIIHH", fmt[:16])
    if kind == 0xFFFE and len(fmt) >= 26:               # "extensible": the real kind is further in
        kind = struct.unpack("<H", fmt[24:26])[0]
    if kind != 1 or bits not in (8, 16, 24, 32):
        raise PackageError(f"{name}: only plain PCM WAV files are supported (8, 16, 24 or 32 bit)")
    if channels not in (1, 2):
        raise PackageError(f"{name}: {channels} channels; a sound must be mono or stereo")
    if not CLIP_RATES[0] <= rate <= CLIP_RATES[1]:
        raise PackageError(f"{name}: {rate} Hz; the sample rate must be {CLIP_RATES[0]} to {CLIP_RATES[1]}")
    width = bits // 8
    count = len(body) // width // channels * channels
    if width == 1:                                      # 8-bit WAV is unsigned
        samples = [(b - 128) << 8 for b in body[:count]]
    elif width == 2:
        samples = list(struct.unpack(f"<{count}h", body[:count * 2]))
    else:                                               # keep the top 16 bits
        samples = [int.from_bytes(body[i * width + width - 2:i * width + width], "little", signed=True)
                   for i in range(count)]
    if not samples:
        raise PackageError(f"{name}: WAV file has no sound in it")
    if loop is not None and loop >= count // channels:
        loop = None
    return rate, channels, samples, loop


def adpcm_step(nibble: int, pred: int, index: int):
    """Advance an IMA ADPCM decoder by one 4-bit code."""
    step = ADPCM_STEP[index]
    diff = step >> 3
    if nibble & 4:
        diff += step
    if nibble & 2:
        diff += step >> 1
    if nibble & 1:
        diff += step >> 2
    pred = max(-32768, min(32767, pred - diff if nibble & 8 else pred + diff))
    return pred, max(0, min(88, index + ADPCM_INDEX[nibble & 7]))


def adpcm_encode(samples, channels: int, loop: int):
    """Squeeze 16-bit samples to 4 bits each. Returns the bytes and, for
    each channel, the decoder's (value, step index) just before the loop
    frame, which a player needs in order to jump back there."""
    state = [(0, 0)] * channels
    at_loop = list(state)
    nibbles = []
    for k, sample in enumerate(samples):
        ch = k % channels
        if k // channels == loop:
            at_loop[ch] = state[ch]
        pred, index = state[ch]
        step = ADPCM_STEP[index]
        diff = sample - pred
        nibble = 8 if diff < 0 else 0
        diff = abs(diff)
        if diff >= step:
            nibble |= 4
            diff -= step
        if diff >= step >> 1:
            nibble |= 2
            diff -= step >> 1
        if diff >= step >> 2:
            nibble |= 1
        nibbles.append(nibble)
        state[ch] = adpcm_step(nibble, pred, index)
    nibbles.append(0)
    packed = bytes(nibbles[i] | nibbles[i + 1] << 4 for i in range(0, len(nibbles) - 1, 2))
    return packed, at_loop


def bank(kind: str, clips) -> bytes:
    """Build sfx.oli or music.isai. Each clip is (rate, channels, samples,
    loop start or None, encoding)."""
    if len(clips) > CLIP_MAX:
        raise PackageError(f"{len(clips)} sounds in one bank, max {CLIP_MAX}")
    table, payload = b"", b""
    offset = BANK_HEADER + CLIP_ENTRY * len(clips)
    for rate, channels, samples, loop, encoding in clips:
        frames, loop = len(samples) // channels, loop or 0
        state = [(0, 0), (0, 0)]
        if encoding == ADPCM:
            blob, at_loop = adpcm_encode(samples, channels, loop)
            state[:channels] = at_loop
        else:
            blob = struct.pack(f"<{len(samples)}h", *samples)
        payload += b"\0" * (_align4(offset) - offset)
        offset = _align4(offset)
        table += struct.pack("<IIIIHBBhBxhBx", offset, len(blob), frames, loop, rate, channels, encoding,
                             state[0][0], state[0][1], state[1][0], state[1][1])
        payload += blob
        offset += len(blob)
    return BANKS[kind][1] + struct.pack("<HH", len(clips), 0) + table + payload


def bank_from_folder(kind: str, folder: str) -> bytes:
    """Sound effects are kept exact; music is squeezed to a quarter the size."""
    clips = []
    for n in sorted(f for f in os.listdir(folder) if f.lower().endswith(".wav")):
        with open(os.path.join(folder, n), "rb") as f:
            rate, channels, samples, loop = read_wav(f.read(), f"{kind}/{n}")
        clips.append((rate, channels, samples, loop, ADPCM if kind == "music" else PCM))
    return bank(kind, clips)


def read_bank(data: bytes):
    """The clips in a sound bank, as (rate, channels, frames, loop, encoding, bytes)."""
    count = struct.unpack("<H", data[4:6])[0]
    out = []
    for i in range(count):
        e = data[BANK_HEADER + CLIP_ENTRY * i:BANK_HEADER + CLIP_ENTRY * (i + 1)]
        _, size, frames, loop, rate, channels, encoding = struct.unpack("<IIIIHBB", e[:20])
        out.append((rate, channels, frames, loop, encoding, size))
    return out


# ---- commands -----------------------------------------------------------

MANIFEST_TEMPLATE = """return {{
  id      = "com.example.{slug}",   -- reverse-DNS, unique to this game
  title   = "{title}",
  author  = "",
  version = "0.1.0",
  spec    = 1,                      -- Pulli spec version this game needs
}}
"""

MAIN_TEMPLATE = """-- {title}
-- Create everything in init() and change it in place afterwards, so the
-- garbage collector has nothing to do while the game runs.

local x, y = 152, 112

function init()
end

function update(dt)
  if btn("left")  then x = x - 60 * dt end
  if btn("right") then x = x + 60 * dt end
  if btn("up")    then y = y - 60 * dt end
  if btn("down")  then y = y + 60 * dt end
end

function draw()
  cls(1)
  print("{title}", 8, 8, 7)
  rectfill(x, y, 16, 16, 9)
end
"""


def cmd_new(path):
    if os.path.exists(path):
        raise PackageError(f"{path} already exists")
    name = os.path.basename(os.path.normpath(path))
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "game"
    title = name.replace('"', "").replace("\\", "") or "Game"
    os.makedirs(path)
    with open(os.path.join(path, "manifest.lua"), "w") as f:
        f.write(MANIFEST_TEMPLATE.format(slug=slug, title=title))
    with open(os.path.join(path, "main.lua"), "w") as f:
        f.write(MAIN_TEMPLATE.format(title=title))
    print(f"created {path}/  (try: python3 {shlex.quote(sys.argv[0])} run {shlex.quote(path)})")


def _tell(notes):
    for note in notes:
        print(f"note: {note}", file=sys.stderr)


def cmd_pack(srcdir, out=None):
    notes = []
    data = build(srcdir, notes=notes)
    _tell(notes)
    out = out or os.path.basename(os.path.normpath(srcdir)) + EXT
    with open(out, "wb") as f:
        f.write(data)
    print(f"packed {len(parse(data))} entries -> {out} ({len(data)} bytes)")


def cmd_list(path):
    for name, blob in read(path):
        print(f"{len(blob):>8}  {name}")
        if blob[:4] == b"PAL1":
            print(f"            this game's own 64 colours")
        if blob[:4] == b"KLM1":
            w, h = struct.unpack("<HH", blob[4:8])
            print(f"            {w}x{h} pixels, sprites 0 to {(w // CELL) * (h // CELL) - 1}")
        if blob[:4] == b"ORU1":
            w, h, layers, flags = read_ooru(blob)
            print(f"            {w}x{h} tiles, {len(layers)} layer(s), flags for {len(flags)} tile(s)")
        if blob[:4] in (magic for _, magic in BANKS.values()):
            for i, (rate, channels, frames, loop, encoding, size) in enumerate(read_bank(blob)):
                print(f"{size:>8}    {i}: {frames / rate:.2f} s, {rate} Hz, "
                      f"{'stereo' if channels == 2 else 'mono'}, {'squeezed 4:1' if encoding else 'exact'}"
                      + (f", loops from {loop / rate:.2f} s" if loop else ""))
    with open(path, "rb") as f:
        lic_kind, licence, sig_kind, signature = read_seal(f.read())
    print(f"licence: {KIND_NAMES.get(lic_kind, lic_kind)} ({len(licence)} bytes)   "
          f"signature: {KIND_NAMES.get(sig_kind, sig_kind)} ({len(signature)} bytes)")


def cmd_unpack(path, dest):
    os.makedirs(dest, exist_ok=True)
    for name, blob in read(path):
        with open(os.path.join(dest, name), "wb") as f:
            f.write(blob)
    print(f"unpacked to {dest}")


def cmd_palette(*args):
    """Write the standard palette, or a game's own (from its folder or its
    .pulli), for a paint program."""
    out, colours, whose, why = args[-1], palette(), "the standard", ""
    if len(args) == 2:
        game = args[0]
        if os.path.isdir(game):
            own = game_palette(game)
        else:
            entries = dict(read(game))
            own = read_palette_entry(entries["palette.pal"]) if "palette.pal" in entries else None
        if own:
            colours, whose = own, "the game's own"
        else:
            why = " (the game has no palette of its own)"
    ext = os.path.splitext(out)[1].lower()
    if ext == ".gpl":                                   # GIMP, Aseprite, Krita, Inkscape
        text = "GIMP Palette\nName: Pulli\nColumns: 8\n#\n" + "".join(
            f"{r:3} {g:3} {b:3}\t{i}\n" for i, (r, g, b) in enumerate(colours))
        data = text.encode()
    elif ext == ".hex":                                 # one colour per line
        data = "".join(f"{r:02x}{g:02x}{b:02x}\n" for r, g, b in colours).encode()
    elif ext == ".png":                                 # one pixel per colour, 8 across
        data = write_png(8, 8, bytes(v for c in colours for v in c))
    else:
        raise PackageError("the palette can be written as .gpl, .hex or .png")
    with open(out, "wb") as f:
        f.write(data)
    print(f"wrote {whose} 64 colours to {out}{why}. Colour 0 is see-through in sprites.")


def sdk_dir():
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sdk")


def cmd_add(game=None, *helpers):
    """Copy helpers from sdk/ into a game's folder. A game gets the helpers
    it requires without this; a copy is for changing one, since a file in
    the game's folder is used in place of the SDK's."""
    have = sorted(f[:-4] for f in os.listdir(sdk_dir()) if f.endswith(".lua"))
    if not helpers:
        for name in have:
            with open(os.path.join(sdk_dir(), name + ".lua")) as f:
                about = f.readline().split("\u2014", 1)[-1].strip()
            print(f"{name:16}{about}")
        return 0
    if not os.path.isdir(game):
        raise PackageError(f"{game} is not a directory")
    for name in helpers:
        if name not in have:
            raise PackageError(f"no helper called '{name}'; there are: {', '.join(have)}")
    for name in helpers:
        dest = os.path.join(game, name + ".lua")
        if os.path.exists(dest):
            raise PackageError(f"{dest} already exists; delete it first if you want a fresh copy")
    for name in helpers:
        shutil.copyfile(os.path.join(sdk_dir(), name + ".lua"), os.path.join(game, name + ".lua"))
        print(f"added {os.path.join(game, name + '.lua')}: the game now uses this copy, which is yours to change")


def find_host(name):
    """Locate pulli-host or pulli-headless: $PULLI_HOST_DIR, ./build, then PATH."""
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    exe = name + (".exe" if os.name == "nt" else "")
    for d in (os.environ.get("PULLI_HOST_DIR"), os.path.join(root, "build", "host")):
        if d and os.path.isfile(os.path.join(d, exe)):
            return os.path.join(d, exe)
    found = shutil.which(name)
    if not found:
        raise PackageError(f"{name} not found: build the host first (see README.md)")
    return found


def _launch(name, target, extra):
    host = find_host(name)
    if os.path.isdir(target):
        with tempfile.TemporaryDirectory() as tmp:
            pkg = os.path.join(tmp, os.path.basename(os.path.normpath(target)) + EXT)
            notes = []
            with open(pkg, "wb") as f:
                f.write(build(target, notes=notes))
            _tell(notes)
            return subprocess.call([host, pkg] + extra)
    return subprocess.call([host, target] + extra)


def cmd_run(target, *options):
    return _launch("pulli-host", target, list(options))


def cmd_check(target, frames="600"):
    return _launch("pulli-headless", target, ["--frames", frames])


COMMANDS = {
    "new": (cmd_new, 1, 1), "pack": (cmd_pack, 1, 2), "list": (cmd_list, 1, 1),
    "unpack": (cmd_unpack, 2, 2), "run": (cmd_run, 1, 4), "check": (cmd_check, 1, 2),
    "palette": (cmd_palette, 1, 2), "add": (cmd_add, 0, 9),
}


def main(argv):
    if len(argv) < 2 or argv[1] not in COMMANDS:
        print(__doc__.strip())
        return 2
    fn, least, most = COMMANDS[argv[1]]
    args = argv[2:]
    if not least <= len(args) <= most:
        print(__doc__.strip())
        return 2
    try:
        return fn(*args) or 0
    except (PackageError, OSError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
