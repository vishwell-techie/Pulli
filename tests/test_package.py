#!/usr/bin/env python3
"""Package format: the packer round-trips, and both readers reject damage.

Run: python3 tests/test_package.py
"""
import os, struct, sys, tempfile, zlib

from harness import Suite, MANIFEST, pulli

MAIN = "function draw() cls(3) end\n"


def refit(data, flags=None):
    """Recompute size and checksum after editing a package by hand."""
    data = bytearray(data)
    if flags is not None:
        data[5] = flags
    struct.pack_into("<I", data, 8, len(data))
    struct.pack_into("<I", data, 12, zlib.crc32(bytes(data[16:])) & 0xFFFFFFFF)
    return bytes(data)


def rejects(fn, *args):
    try:
        fn(*args)
    except pulli.PackageError as e:
        return str(e)
    return None


def main():
    t = Suite("Pulli package format")

    with tempfile.TemporaryDirectory() as tmp:
        files = {"manifest.lua": MANIFEST.encode(), "main.lua": MAIN.encode(),
                 "odd.bin": b"\x01\x02\x03", "empty.bin": b"", "a" * 32: b"thirty-two"}
        for name, blob in files.items():
            with open(os.path.join(tmp, name), "wb") as f:
                f.write(blob)
        open(os.path.join(tmp, ".hidden"), "wb").close()
        data = pulli.build(tmp)
        t.check("round trip returns every file unchanged", dict(pulli.parse(data)) == files)
        t.check("hidden files are left out", ".hidden" not in dict(pulli.parse(data)))

        os.remove(os.path.join(tmp, "main.lua"))
        t.check("packer refuses a game with no main.lua", rejects(pulli.build, tmp))

    version, flags, count, total, crc = struct.unpack("<BBHII", data[4:16])
    t.check("header: magic, version, count, size", data[:4] == b"PULI" and version == 1
            and count == 5 and total == len(data))
    t.check("header: checksum is CRC-32 of everything after the header",
            crc == zlib.crc32(data[16:]) & 0xFFFFFFFF)
    offsets = [struct.unpack_from("<I", data, 16 + i * 40 + 32)[0] for i in range(count)]
    t.check("every entry starts on a 4-byte boundary", all(o % 4 == 0 for o in offsets))

    t.check("packer refuses a 33-character name",
            rejects(pulli.build_entries, [("b" * 33, b"")]))
    t.check("packer refuses a name with a path in it",
            rejects(pulli.build_entries, [("../x", b"")]))
    t.check("packer refuses 65 entries",
            rejects(pulli.build_entries, [(f"f{i}", b"") for i in range(65)]))

    good = pulli.build_entries([("main.lua", MAIN.encode()), ("manifest.lua", MANIFEST.encode())])
    flipped = bytearray(good)
    flipped[-3] ^= 0x40
    oob = bytearray(good)
    struct.pack_into("<I", oob, 16 + 36, 1 << 20)          # first entry's length
    damaged = {
        "one flipped bit": (bytes(flipped), "checksum"),
        "truncated file": (good[:-10], "truncated"),
        "not a package at all": (b"hello world, this is not a package", "not a Pulli package"),
        "empty file": (b"", "not a Pulli package"),
        "future format version": (refit(good[:4] + b"\x02" + good[5:]), "version"),
        "entry past the end": (refit(oob), "outside"),
        "encrypted flag": (refit(good, flags=pulli.FLAG_ENCRYPTED), "encrypted"),
        "no manifest.lua": (pulli.build_entries([("main.lua", MAIN.encode())]), "manifest.lua"),
        "no main.lua": (pulli.build_entries([("manifest.lua", MANIFEST.encode())]), "main.lua"),
    }
    for name in ("one flipped bit", "truncated file", "not a package at all", "entry past the end"):
        t.check(f"python reader rejects: {name}", rejects(pulli.parse, damaged[name][0]))

    if t.need_runtime("C reader checks"):
        r = t.run_package(pulli.build_entries(
            [("a" * 32, b"x"), ("main.lua", MAIN.encode()), ("manifest.lua", MANIFEST.encode())]))
        t.check("C reader accepts a good package, including a 32-character name",
                r.code == 0, r.err)
        for name, (blob, expect) in damaged.items():
            r = t.run_package(blob)
            t.check(f"C reader rejects: {name}", r.code == 1 and expect in r.err, r.err)
        # A longer file than the header claims is fine: on a cartridge the
        # package sits at the start of a larger flash region.
        r = t.run_package(good + b"\xff" * 64)
        t.check("C reader ignores bytes after the package", r.code == 0, r.err)

    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
