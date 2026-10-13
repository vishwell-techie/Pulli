#!/usr/bin/env python3
"""pulli.py — the Pulli command line (SPEC §6) and package format (SPEC §2).

    python3 tools/pulli.py new    <dir>                    start a new game
    python3 tools/pulli.py pack   <dir> [out.pulli]        build a package
    python3 tools/pulli.py list   <game.pulli>             show what is inside
    python3 tools/pulli.py unpack <game.pulli> <dir>       extract the files
    python3 tools/pulli.py run    <dir|game.pulli> [scale] [--link PORT]
                                                           play it in a window
    python3 tools/pulli.py check  <dir|game.pulli> [frames] run it with no window

Deliberately dependency-free: this has to run on a student's laptop with a
stock Python install and nothing else. `run` and `check` also need the host
built (see README.md).
"""
import hashlib, os, re, shlex, shutil, struct, subprocess, sys, tempfile, zlib

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


def build(srcdir: str, flags: int = 0) -> bytes:
    """Package every file in a game directory."""
    if not os.path.isdir(srcdir):
        raise PackageError(f"{srcdir} is not a directory")
    names = sorted(
        f for f in os.listdir(srcdir)
        if os.path.isfile(os.path.join(srcdir, f)) and not f.startswith(".")
    )
    for req in REQUIRED:
        if req not in names:
            raise PackageError(f"{srcdir} is missing {req}")
    entries = []
    for n in names:
        with open(os.path.join(srcdir, n), "rb") as f:
            entries.append((n, f.read()))
    return build_entries(entries, flags)


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


def cmd_pack(srcdir, out=None):
    data = build(srcdir)
    out = out or os.path.basename(os.path.normpath(srcdir)) + EXT
    with open(out, "wb") as f:
        f.write(data)
    print(f"packed {len(parse(data))} entries -> {out} ({len(data)} bytes)")


def cmd_list(path):
    for name, blob in read(path):
        print(f"{len(blob):>8}  {name}")
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
            with open(pkg, "wb") as f:
                f.write(build(target))
            return subprocess.call([host, pkg] + extra)
    return subprocess.call([host, target] + extra)


def cmd_run(target, *options):
    return _launch("pulli-host", target, list(options))


def cmd_check(target, frames="600"):
    return _launch("pulli-headless", target, ["--frames", frames])


COMMANDS = {
    "new": (cmd_new, 1, 1), "pack": (cmd_pack, 1, 2), "list": (cmd_list, 1, 1),
    "unpack": (cmd_unpack, 2, 2), "run": (cmd_run, 1, 4), "check": (cmd_check, 1, 2),
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
