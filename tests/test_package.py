#!/usr/bin/env python3
"""Package format: the packer round-trips, and both readers reject damage.

Run: python3 tests/test_package.py
"""
import hashlib, os, struct, sys, tempfile, zlib

from harness import Suite, MANIFEST, pulli

MAIN = "function draw() cls(3) end\n"


def refit(data, flags=None, edit=None, reseal=True):
    """Change a package by hand, then recompute its checksum and, unless told
    otherwise, its seal: the result is damaged only in the way intended."""
    body = bytearray(pulli.split(data)[0])
    if flags is not None:
        body[5] = flags
    if edit:
        edit(body)
    start = struct.unpack_from("<I", body, 16)[0]
    struct.pack_into("<I", body, 12, zlib.crc32(bytes(body[16:start])) & 0xFFFFFFFF)
    return pulli.seal(bytes(body)) if reseal else bytes(body) + pulli.split(data)[1]


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
        for notes in ("README.md", "notes.MD"):
            open(os.path.join(tmp, notes), "w").write("# For people, not the console\n")
        data = pulli.build(tmp)
        t.check("round trip returns every file unchanged", dict(pulli.parse(data)) == files)
        t.check("hidden files are left out", ".hidden" not in dict(pulli.parse(data)))
        t.check("Markdown files, such as a README, are left out",
                not {"README.md", "notes.MD"} & set(dict(pulli.parse(data))))

        # Copied into WSL from a Windows download, every file gains a
        # "<name>:Zone.Identifier" twin; Windows also leaves Thumbs.db and
        # desktop.ini. None of them is part of the game.
        made = [n + ":Zone.Identifier" for n in files] + ["Thumbs.db", "desktop.ini"]
        for name in made:
            open(os.path.join(tmp, name), "wb").close()
        notes = []
        data = pulli.build(tmp, notes=notes)
        t.check("files the operating system made are left out, and the developer is told",
                dict(pulli.parse(data)) == files and len(notes) == 1 and "operating system" in notes[0], notes)
        for name in made:
            os.remove(os.path.join(tmp, name))
        for i in range(1030):
            open(os.path.join(tmp, f"extra{i}.bin"), "wb").close()
        try:
            pulli.build(tmp)
            listed = ""
        except pulli.PackageError as e:
            listed = str(e)
        t.check("too many files: the error says which are being packed", "extra999.bin" in listed, listed[:120])
        for i in range(1030):
            os.remove(os.path.join(tmp, f"extra{i}.bin"))

        os.remove(os.path.join(tmp, "main.lua"))
        t.check("packer refuses a game with no main.lua", rejects(pulli.build, tmp))

    # A game's folders (SPEC §6): code/, sprites/, maps/ and backdrops/ hold
    # its files, and each is an entry by its name alone.
    with tempfile.TemporaryDirectory() as tmp:
        for rel, blob in (("manifest.lua", MANIFEST.encode()), ("code/main.lua", MAIN.encode()),
                          ("code/enemy.lua", b"return {}"), ("backdrops/note.bin", b"x"), ("maps/README.md", b"#")):
            os.makedirs(os.path.dirname(os.path.join(tmp, rel)), exist_ok=True)
            open(os.path.join(tmp, rel), "wb").write(blob)
        names = sorted(dict(pulli.parse(pulli.build(tmp))))
        t.check("files in the game's folders are packed by their names alone",
                names == ["enemy.lua", "main.lua", "manifest.lua", "note.bin"], names)
        open(os.path.join(tmp, "enemy.lua"), "wb").write(b"return 1")
        why = rejects(pulli.build, tmp)
        t.check("two files of one name in different folders are refused, naming both",
                why and "code/enemy.lua" in why and "keep one" in why, why)
        os.remove(os.path.join(tmp, "enemy.lua"))
        os.makedirs(os.path.join(tmp, "other"))
        open(os.path.join(tmp, "other", "x.lua"), "wb").write(b"")
        t.check("a folder that is not one of a game's is left out", "x.lua" not in dict(pulli.parse(pulli.build(tmp))))
    with tempfile.TemporaryDirectory() as tmp:
        game = os.path.join(tmp, "g")
        pulli.cmd_new(game)
        t.check("pulli new makes manifest.lua and code/main.lua",
                os.path.isfile(os.path.join(game, "manifest.lua")) and os.path.isfile(os.path.join(game, "code", "main.lua"))
                and not os.path.exists(os.path.join(game, "main.lua")))

    version, flags, count, total, crc, start = struct.unpack("<BBHIII", data[4:20])
    body, tail = pulli.split(data)
    t.check("header: magic, version, count, size, where the payload starts",
            data[:4] == b"PULI" and version == 2 and count == 5 and total == len(body)
            and start % 4 == 0 and 20 + 40 * count + 32 <= start)
    t.check("header: checksum is CRC-32 of the front after it: table and block hashes",
            crc == zlib.crc32(body[16:start]) & 0xFFFFFFFF)
    hashes = body[20 + 40 * count:]
    t.check("the front holds the SHA-256 of every 64 KB block of the payload",
            hashes[:32] == hashlib.sha256(body[start:start + 65536]).digest())
    t.check("a built package ends with a developer licence and signature, over its front",
            tail[:4] == b"SEAL" and pulli.read_seal(data) ==
            (pulli.LICENCE_DEVELOPER, b"", pulli.SIGNATURE_DEVELOPER, hashlib.sha256(body[:start]).digest()))
    offsets = [struct.unpack_from("<I", data, 20 + i * 40 + 32)[0] for i in range(count)]
    t.check("every entry starts on a 4-byte boundary, in the payload", all(o % 4 == 0 and o >= start for o in offsets))

    t.check("packer refuses a 33-character name",
            rejects(pulli.build_entries, [("b" * 33, b"")]))
    t.check("packer refuses a name with a path in it",
            rejects(pulli.build_entries, [("../x", b"")]))
    t.check("packer takes 1024 entries", not rejects(pulli.build_entries, [(f"f{i}", b"") for i in range(1024)]))
    t.check("packer refuses 1025 entries",
            rejects(pulli.build_entries, [(f"f{i}", b"") for i in range(1025)]))
    t.check("packer refuses a package over 64 MB",
            "64" in (rejects(pulli.build_entries, [("big", bytes(64 * 1024 * 1024))]) or ""))

    good = pulli.build_entries([("main.lua", MAIN.encode()), ("manifest.lua", MANIFEST.encode())])
    body, tail = pulli.split(good)
    flipped = bytearray(good)
    flipped[len(body) - 3] ^= 0x40

    def past_the_end(b):
        struct.pack_into("<I", b, 20 + 36, 1 << 20)        # first entry's length

    def future_version(b):
        b[4] = 3

    def other_hash(b):                                     # the front, and so the signature
        b[20 + 40 * 2] ^= 1

    def other_colour(b):
        b[b.index(b"cls(3)") + 4] = ord("4")               # the game now clears to another colour

    damaged = {
        "one flipped bit": (bytes(flipped), "damaged"),
        "truncated file": (good[:len(body) - 10], "truncated"),
        "not a package at all": (b"hello world, this is not a package", "not a Pulli package"),
        "empty file": (b"", "not a Pulli package"),
        "future format version": (refit(good, edit=future_version), "version"),
        "entry past the end": (refit(good, edit=past_the_end), "outside"),
        "encrypted flag": (refit(good, flags=pulli.FLAG_ENCRYPTED), "encrypted"),
        "no manifest.lua": (pulli.build_entries([("main.lua", MAIN.encode())]), "manifest.lua"),
        "no main.lua": (pulli.build_entries([("manifest.lua", MANIFEST.encode())]), "main.lua"),
        # the seal
        "no licence and signature": (body, "no licence and signature"),
        "licence and signature cut short": (good[:-5], "truncated"),
        "a byte of the game changed after signing": (refit(good, edit=other_colour, reseal=False), "damaged"),
        "the front changed after signing, checksum repaired": (refit(good, edit=other_hash, reseal=False),
                                                               "signature does not match"),
        "a wrong signature": (pulli.seal(body, signature=bytes(32)), "signature does not match"),
        "a kind of licence from the future": (pulli.seal(body, licence_kind=7), "kind of licence"),
        "a kind of signature from the future": (pulli.seal(body, signature_kind=7, signature=b"x" * 64),
                                                "kind of signature"),
    }
    for name in ("one flipped bit", "truncated file", "not a package at all", "entry past the end",
                 "no licence and signature", "a byte of the game changed after signing",
                 "the front changed after signing, checksum repaired", "a wrong signature"):
        t.check(f"python reader rejects: {name}", rejects(pulli.parse, damaged[name][0]))

    # What the store will do: put a different licence on the very same package.
    licensed = pulli.seal(body, licence=b"L" * 300)
    t.check("a licence can be attached without changing one byte of the package",
            pulli.split(licensed)[0] == body and dict(pulli.parse(licensed)) == dict(pulli.parse(good))
            and pulli.read_seal(licensed)[1] == b"L" * 300)

    if t.need_runtime("C reader checks"):
        r = t.run_package(pulli.build_entries(
            [("a" * 32, b"x"), ("main.lua", MAIN.encode()), ("manifest.lua", MANIFEST.encode())]))
        t.check("C reader accepts a good package, including a 32-character name",
                r.code == 0, r.err)
        for name, (blob, expect) in damaged.items():
            for mapped in (False, True):
                r = t.run_package(blob, mapped=mapped)
                t.check(f"C reader rejects: {name}{' (mapped)' if mapped else ''}",
                        r.code == 1 and expect in r.err, r.err)

        # Damage is found where it is read, not before: a package whose only
        # damage is in a part the game never uses starts and runs; reading
        # that part stops the game, naming it. A block in the middle of a
        # large part is checked too.
        big = bytes(range(256)) * 1024                     # 256 KB: four blocks
        pkg = pulli.build_entries([("main.lua", b"function update() if stat('frame') == 3 then preload('big.bin') end end"),
                                   ("manifest.lua", MANIFEST.encode()), ("big.bin", big)])
        hit = bytearray(pkg)
        hit[pkg.index(big) + 2 * 65536 + 7] ^= 1           # inside the third block of big.bin
        for mapped in (False, True):
            way = " (mapped)" if mapped else ""
            r = t.run_package(bytes(hit), frames=2, mapped=mapped)
            t.check(f"C reader: damage in a part not yet used does not stop the game{way}", r.code == 0, r.err)
            r = t.run_package(bytes(hit), frames=5, mapped=mapped)
            t.check(f"C reader: reading the damaged part stops the game and names it{way}",
                    r.code == 1 and "big.bin" in r.err and "damaged" in r.err, r.err)
            r = t.run_package(pkg, frames=5, mapped=mapped)
            t.check(f"C reader: the same package undamaged reads it{way}", r.code == 0, r.err)
        t.check("C reader accepts the same package under a different licence",
                t.run_package(licensed).code == 0)
        # The signature is a SHA-256 computed in C; its padding rules change
        # with the length, so try every length across two blocks.
        sizes = [t.run_package(pulli.build_entries(
            [("main.lua", MAIN.encode()), ("manifest.lua", MANIFEST.encode()), ("zz", b"z" * n)])).code
            for n in range(130)]
        t.check("C and Python agree on the signature for packages of 130 different lengths",
                sizes == [0] * 130, f"failed for sizes {[n for n, c in enumerate(sizes) if c]}")
        # A longer file than the package and its seal is fine: on a cartridge
        # they sit at the start of a larger flash region.
        r = t.run_package(good + b"\xff" * 64)
        t.check("C reader ignores bytes after the seal", r.code == 0, r.err)

    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
