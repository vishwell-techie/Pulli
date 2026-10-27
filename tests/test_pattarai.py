#!/usr/bin/env python3
"""Pattarai, the editors (tools/pattarai, served by `pulli edit`).

Run: python3 tests/test_pattarai.py

  - the editors' colours are the runtime's;
  - what the editors write (PNG, Tiled maps, WAV) reads back through
    pulli.py exactly, a map that is opened and saved is unchanged, and
    only the cells painted change;
  - Isai's scales: the 72 melakartas, the swaras of each raga, the
    notation read and written both ways (arpeggios too), a song plays the
    same every time, and a chiptune renders small at its own rate;
  - Oli's sound effects are the same every time, every kind and wave
    makes a sound within full scale, and pack takes them into sfx.oli
    with the Oli files beside them left out;
  - Vidhi, the code editor, colours Lua, finds the asset a call names and
    numbers sounds as pack does, and its functions are the spec's;
  - the server lets the page reach the game's files and nothing else, and
    its check runs the game and reports errors by line.

The library checks need node (any recent version); they are skipped,
loudly, without it.
"""
import base64, http.client, json, os, re, shutil, struct, subprocess, sys, tempfile, threading

from harness import Suite, ROOT, pulli

import refgfx   # noqa: E402

HERE = os.path.join(ROOT, "tools", "pattarai")
VILLAGE = os.path.join(ROOT, "examples", "manickam", "village.tmx")


def library(t):
    node = shutil.which("node")
    if not node:
        t.skipped += 1
        print("  SKIP  Pattarai's libraries (node is not installed)")
        return
    run = subprocess.run([node, os.path.join(ROOT, "tests", "pattarai_lib.mjs"), VILLAGE],
                         capture_output=True, text=True, timeout=600)
    if not t.check("the libraries run in node", run.returncode == 0, run.stderr[-2000:]):
        return
    r = json.loads(run.stdout)

    # ---- scales ----
    t.check("melakartas are made from their numbers", r["mela"] == {
        "1": [0, 1, 2, 5, 7, 8, 9], "8": [0, 1, 3, 5, 7, 8, 10], "15": [0, 1, 4, 5, 7, 8, 11],
        "20": [0, 2, 3, 5, 7, 8, 10], "22": [0, 2, 3, 5, 7, 9, 10], "28": [0, 2, 4, 5, 7, 9, 10],
        "29": [0, 2, 4, 5, 7, 9, 11], "36": [0, 3, 4, 5, 7, 10, 11], "37": [0, 1, 2, 6, 7, 8, 9],
        "56": [0, 2, 3, 6, 7, 8, 10], "65": [0, 2, 4, 6, 7, 9, 11], "72": [0, 3, 4, 6, 7, 10, 11]}, r["mela"])
    t.check("there are 72 melakartas, all different", r["melaCount"] == 72 and r["melaDistinct"] == 72)
    t.check("the well-known melakartas have their numbers", r["melaOf"] == {
        "Hanumatodi": 8, "Mayamalavagowla": 15, "Natabhairavi": 20, "Kharaharapriya": 22,
        "Dheerasankarabharanam": 29, "Shanmukhapriya": 56, "Mechakalyani": 65}, r["melaOf"])
    t.check("each janya raga's notes are in its parent melakarta", all(ok for _, ok in r["janyaInParent"]),
            [n for n, ok in r["janyaInParent"] if not ok])
    t.check("each note of a raga is named the swara it is", r["names"] == {
        "Mayamalavagowla": {"0": "S", "1": "R1", "4": "G3", "5": "M1", "7": "P", "8": "D1", "11": "N3"},
        "Hindolam": {"0": "S", "3": "G2", "5": "M1", "8": "D1", "10": "N2"},
        "Mohanam": {"0": "S", "2": "R2", "4": "G3", "7": "P", "9": "D2"},
        "Shivaranjani": {"0": "S", "2": "R2", "3": "G2", "7": "P", "9": "D2"},
        "Revati": {"0": "S", "1": "R1", "5": "M1", "7": "P", "10": "N2"},
        "Kalyani": {"0": "S", "2": "R2", "4": "G3", "6": "M2", "7": "P", "9": "D2", "11": "N3"}}, r["names"])

    # ---- notation ----
    notes = [(n["at"], n["len"], n["semi"], n["mark"]) for n in r["carnatic"]["notes"]]
    t.check("sargam reads: the raga's swaras, octaves, holds, rests, others named, gamakas", notes == [
        (0, 2, 0, ""), (2, 1, 1, ""), (3, 1, 4, ""), (4, 3, 5, ""), (7, 1, 7, ""), (8, 1, -4, ""), (9, 1, -1, ""),
        (10, 1, 12, ""), (11, 1, 24, ""), (13, 1, 4, ""), (14, 1, 6, "/"), (15, 2, 7, "\\")], notes)
    t.check("a stray mark is refused", r["badTilde"])
    t.check("a swara the raga lacks is refused, saying which to write", r["missing"] and "R2" in r["missing"],
            r["missing"])
    t.check("sargam written back reads the same", r["carnaticAgain"] == r["carnatic"])
    t.check("western notes read in the song's key and octave", r["westernNames"] ==
            ["D4", "F#4", "A4", "A4", "D5", "A#3"], r["westernNames"])
    t.check("a held note and a rest in western notation", [(n["at"], n["len"]) for n in r["western"]["notes"]] ==
            [(0, 2), (2, 1), (3, 1), (4, 1), (6, 1), (7, 3)] and r["western"]["notes"][3]["mark"] == "~")
    t.check("western written back reads the same", r["westernAgain"] == r["western"])
    t.check("tuning: A4 is 440 Hz; Sa an octave up is twice Sa",
            abs(r["freqs"]["a4"] - 440) < 1e-6 and abs(r["freqs"]["sa"] - 277.2) < 1e-6, r["freqs"])

    # ---- the band ----
    rd = r["render"]
    want = round(rd["steps"] * 60 / rd["tempo"] / rd["perStep"] * 44100)
    t.check("a song is as long as its cycles", rd["len"] == want, (rd["len"], want))
    t.check("a song plays the same every time", rd["same"])
    t.check("a song is mixed below full scale", 0.5 < rd["peak"] <= 0.8 + 1e-6, rd["peak"])
    t.check("every instrument with every drum kit makes a sound with no gaps in it", "badRender" not in r,
            r.get("badRender"))
    c = r["chip"]
    t.check("a chiptune renders at its own rate, as long as its cycles", c["len"] == c["want"] and c["finite"], c)
    t.check("the chiptune to start from fills its cycles", all(n % 16 == 0 and n for n in c["parts"]), c["parts"])
    t.check("an arpeggio is read after a note and its mark", r["arp"] == [
        [0, 2, "", [0, 4, 7]], [4, 1, "~", [0, 12]], [7, 1, "", [0, -12]]], r["arp"])
    t.check("an arpeggio written back reads the same", r["arpAgain"] == r["arp"])
    t.check("a broken arpeggio is refused", r["arpBad"])
    lo, hi, back = r["arpHeard"]
    t.check("an arpeggio is heard: the note, the octave above, the note again", hi > 1.8 * lo and abs(back - lo) <= 2,
            r["arpHeard"])
    d = r["decoded"]
    t.check("a WAV is read back sample for sample, with its loop point", d == {
        "rate": 12345, "loop": 2, "ch": [[0, 16384, -16383, 8192], [32767, -32767, 0, 0]]}, d)
    rate, channels, samples, _ = pulli.read_wav(open(os.path.join(ROOT, "examples", "catch", "sfx", "0-catch.wav"), "rb").read())
    t.check("a game's WAV reads as pack reads it", r["real"] == {"rate": rate, "channels": channels,
            "frames": len(samples) // channels, "first": list(samples[:50 * channels:channels])}, r["real"]["frames"])
    t.check("a file that is not a WAV is refused", r["notWav"])
    t.check("a note's volume is read and written back: !1 to !9, 9 being full", r["vol"] == [3, 9, 1, None] and
            r["volAgain"] == [3, None, 1, None], (r["vol"], r["volAgain"]))
    t.check("a volume outside !1 to !9 is refused", r["volBad"])
    t.check("a note at !3 sounds a third as loud", abs(r["volRatio"] - 3 / 9) < 0.03, r["volRatio"])
    lp = r["loop"]
    t.check("the loop point is the start of its cycle; none is the start; past the end is the last cycle",
            lp["frame"] == lp["want"] and lp["none"] == 0 and 0 < lp["past"], lp)
    rate, channels, samples, loop = pulli.read_wav(base64.b64decode(r["loopWav"]))
    t.check("the loop point is kept in the WAV where pack reads it", loop == lp["frame"], (loop, lp["frame"]))
    rate, channels, samples, _ = pulli.read_wav(base64.b64decode(r["chipWav"]))
    t.check("a chiptune's WAV is mono at 8,000 and pack reads it", (rate, channels) == (8000, 1) and
            len(samples) == c["len"])

    # ---- what the editors write, read by pulli.py ----
    w, h, px = pulli.read_png(base64.b64decode(r["png"]))
    raw = base64.b64decode(r["pngPixels"])
    t.check("a PNG Kolam writes reads back pixel for pixel, see-through kept", (w, h) == (24, 16) and
            px == [tuple(raw[i:i + 4]) for i in range(0, len(raw), 4)])
    rate, channels, samples, loop = pulli.read_wav(base64.b64decode(r["wav"]))
    t.check("a WAV Isai writes reads back, clipped at full scale", (rate, channels) == (22050, 2) and
            list(samples) == [0, 8192, 16384, 0, -16383, 0, 32767, 0, -32767, 0, 32767, -32767], list(samples))
    with tempfile.TemporaryDirectory() as tmp:
        shutil.copy(os.path.join(os.path.dirname(VILLAGE), "sprites.tsx"), tmp)
        def ooru(text, name="map.tmx"):
            with open(os.path.join(tmp, name), "w") as f:
                f.write(text)
            return pulli.read_ooru(pulli.ooru_from_tmx(os.path.join(tmp, name)))
        before = pulli.read_ooru(pulli.ooru_from_tmx(VILLAGE))
        t.check("a map opened and saved is unchanged, byte for byte", r["mapSame"] == open(VILLAGE).read())
        after = ooru(r["mapChanged"])
        w, h, layers = r["mapSize"]
        changed = [(l, i) for l in range(len(before[2])) for i in range(w * h) if before[2][l][i] != after[2][l][i]]
        t.check("only the cells painted change, flips kept", changed == [(0, 0), (layers - 1, w + 1)] and
                after[2][0][0] == 5 | pulli.FLIP_X and after[2][layers - 1][w + 1] == 7 | pulli.FLIP_Y,
                changed)
        with open(os.path.join(tmp, "sprites.tsx"), "w") as f:
            f.write(r["freshTSX"])
        fresh = ooru(r["fresh"], "new.tmx")
        t.check("a new map and its tileset are what pack reads", fresh[:2] == (10, 6) and len(fresh[2]) == 2 and
                fresh[2][1][3] == 2 and sum(map(sum, fresh[2])) == 2, fresh[:2])
        flags_of = lambda: dict(enumerate(pulli.read_ooru(pulli.ooru_from_tmx(os.path.join(tmp, "map.tmx")))[3]))
        shutil.copy(os.path.join(os.path.dirname(VILLAGE), "sprites.tsx"), tmp)
        ooru(r["mapSame"])
        before = {k: v for k, v in flags_of().items() if v}
        t.check("Ooru reads each tile's flags as pack does", {int(k): v for k, v in r["tsxFlags"].items()} == before,
                (r["tsxFlags"], before))
        with open(os.path.join(tmp, "sprites.tsx"), "w") as f:
            f.write(r["tsxChanged"])
        after = {k: v for k, v in flags_of().items() if v}
        want = {**before, 43: 5, 10: 3, 2000: 128}
        want.pop(44, None)
        t.check("flags Ooru sets are what pack reads: changed, added, added past the end, cleared", after == want,
                sorted(set(after.items()) ^ set(want.items())))
        t.check("setting a tile's flags to what they are leaves the tileset as it was", r["tsxSame"])
        t.check("a solid tick box counts as bit 0, and is kept in step with the flags set",
                r["solid"] == [{"2": 1}, {"2": 6}], r["solid"])
    oli(t, r)
    backdrops(t, r)
    vidhi(t, r)


def oli(t, r):
    o = r["oli"]
    t.check("a sound effect is the same every time, as long as its envelope, and a new seed varies it",
            o["same"] and o["len"] == o["want"] and o["varies"], o)
    t.check("every kind of sound with every wave sounds, within full scale", r["oliBad"] == [], r["oliBad"][:5])
    t.check("a variation keeps every setting within its range", r["oliInRange"])
    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, "sfx"))
        for name in ("00-jump.wav", "01-jump.wav"):
            with open(os.path.join(tmp, "sfx", name), "wb") as f:
                f.write(base64.b64decode(r["oliWav"]))
        with open(os.path.join(tmp, "sfx", "00-jump.json"), "w") as f:
            f.write("{}")
        sounds = pulli.read_bank(pulli.bank_from_folder("sfx", os.path.join(tmp, "sfx")))
        rate, channels, samples, _ = pulli.read_wav(base64.b64decode(r["oliWav"]))
        t.check("pack takes Oli's WAV files into sfx.oli, mono at 22,050, the .json beside them left out",
                (rate, channels) == (22050, 1) and len(sounds) == 2 and
                all(c[:3] == (22050, 1, len(samples)) for c in sounds), sounds)


def backdrops(t, r):
    t.check("a picture already in the 64 colours keeps them, dithered or not; see-through is colour 0",
            r["exact"] == list(range(64)) and r["exactDithered"] == list(range(64)), (r["exact"], r["exactDithered"]))
    colours = [pulli.palette()[i] for i in range(64)]
    t.check("a shade between two colours is one colour plain, and a mix of colours dithered",
            len(r["plain"]) == 1 and len(r["dithered"]) >= 2, (r["plain"], r["dithered"]))
    t.check("backdrop(name) under the cursor names its picture",
            r["backdropCall"] == {"fn": "backdrop", "arg": "bg_easy.kolam"}, r["backdropCall"])


def vidhi(t, r):
    spec = open(os.path.join(ROOT, "docs", "SPEC.md")).read()
    api = spec[spec.index("## 3. Lua API"):spec.index("## 3a")]
    found = {}
    for block in re.findall(r"```lua\n(.*?)```", api, re.S):
        for line in block.splitlines():
            for m in re.finditer(r"\b([a-z_]+(?:\.[a-z_]+)?)\(([^()]*(?:\([^()]*\))?[^()]*)\)", line.partition("--")[0]):
                if m.group(1) not in ("init", "update", "draw", "function", "require"):
                    found.setdefault(m.group(1), m.group(2).strip())
    sigs = {k: v[0] for k, v in r["sigs"].items()}
    t.check("Vidhi knows every function in the spec, with the spec's arguments, and no others",
            {k: v for k, v in sigs.items() if k != "stat"} == {k: v for k, v in found.items() if k != "stat"}
            and "stat" in found and "stat" in sigs, sorted(set(sigs.items()) ^ set(found.items())))
    t.check("names are offered as they are typed: the API, the callbacks, the file's own", r["complete"] == [
        ["map.draw", "map.flags", "map.get", "map.load", "map.set", "map.size", "make_enemy"],
        ["spr", "speed"], [], ["map.draw"]], r["complete"])
    t.check("the name being typed is found, dots and all", r["word"] == [{"word": "map.lo", "start": 4}, None], r["word"])
    t.check("the hint names the call the cursor is in and which argument",
            r["hints"] == [["spr", 2], ["print", 1], None, None, ["map.set", 3]], r["hints"])
    t.check("the call under the cursor names its asset", r["calls"] == [
        {"fn": "spr", "arg": 12}, {"fn": "sfx", "arg": 3}, {"fn": "map.load", "arg": "hall.ooru"},
        {"fn": "sfx", "arg": 7}, None, {"fn": "sheet.load", "arg": "actors.kolam"}], r["calls"])
    t.check("the nearest call is the one under the cursor", r["callFar"] == {"fn": "music", "arg": 1}, r["callFar"])
    t.check("Lua is coloured: keywords, strings, comments, the API, numbers", r["lit"] ==
            '<span class="k">local</span> s = <span class="s">"a"</span> <span class="c">-- c</span>\n'
            '<span class="f">spr</span>(<span class="n">1</span>) x = <span class="n">0x1f</span>\n\n', r["lit"])
    t.check("sounds are numbered as pack numbers them: the folder's WAV files by name",
            r["numbered"] == ["sfx/10.wav", "sfx/a.WAV", "sfx/b.wav"], r["numbered"])


def project(t):
    r = pulli.project_report(os.path.join(ROOT, "examples", "manickam"))
    entries = dict(pulli.parse(pulli.build(os.path.join(ROOT, "examples", "manickam"))))
    t.check("the project report measures the package pack builds", r["ok"] and r["error"] is None and
            r["size"] == len(pulli.build(os.path.join(ROOT, "examples", "manickam"))) and
            dict(r["entries"]) == {n: len(b) for n, b in entries.items()}, r["checks"])
    clips = pulli.read_bank(entries["sfx.oli"])
    t.check("each sound is measured as it is read, one at a time", [b for n, b in r["sounds"] if n.startswith("sfx(")] ==
            [c[5] for c in clips])
    with tempfile.TemporaryDirectory() as tmp:
        with open(os.path.join(tmp, "manifest.lua"), "w") as f:
            f.write("return {}\n")
        bad = pulli.project_report(tmp)
        t.check("a game that does not pack says why", not bad["ok"] and "main.lua" in bad["error"], bad)


def tamil(t):
    text = open(os.path.join(HERE, "lib", "i18n.js")).read()
    pairs = re.findall(r'"((?:[^"\\]|\\.)+)":\s*"((?:[^"\\]|\\.)+)"', text.split("export const TA")[1].split("};")[0])
    ui = "".join(open(os.path.join(HERE, f)).read() for f in os.listdir(HERE) if f.endswith((".js", ".html")))
    missing = [en for en, _ in pairs if en.strip() not in ui]
    t.check("every English word Pattarai puts in Tamil is one the editors show", pairs and not missing, missing)
    t.check("each is given in Tamil", all(re.search("[\u0b80-\u0bff]", ta) for _, ta in pairs),
            [en for en, ta in pairs if not re.search("[\u0b80-\u0bff]", ta)])


def budget(t):
    """The quick measure is the package's real size; the budget counts it
    against the game's target; the server refuses what the console could
    not use, and, when the game is strict, saves that go past its budget."""
    for name in ("catch", "manickam"):
        folder = os.path.join(ROOT, "examples", name)
        fast = len(pulli.build_entries(sorted(pulli.gather(folder, fast=True))))
        t.check(f"{name}: the quick measure is the real package's size, to the byte", fast == len(pulli.build(folder)),
                (fast, len(pulli.build(folder))))
    import wave

    def wav(path, seconds, channels=1, rate=22050):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with wave.open(path, "wb") as w:
            w.setnchannels(channels); w.setsampwidth(2); w.setframerate(rate)
            w.writeframes(b"\1\0" * channels * int(rate * seconds))
        return open(path, "rb").read()

    with tempfile.TemporaryDirectory() as tmp:
        game = os.path.join(tmp, "game")
        shutil.copytree(os.path.join(ROOT, "examples", "catch"), game)
        b = pulli.budget(game)
        t.check("a game with no setting is measured against an SD card, its kinds adding up",
                b["error"] is None and b["target"] == "SD card" and b["room"] == 64 * pulli.MB and not b["over"]
                and sum(b["kinds"].values()) < b["size"] and b["kinds"]["code"] > 0 and b["kinds"]["sound effects"] > 0, b)
        with open(os.path.join(game, ".pattarai.json"), "w") as f:
            json.dump({"target": "cart8", "strict": False, "limits": {"sound effects": 0.01}}, f)
        b = pulli.budget(game)
        t.check("a cartridge's room is its flash less the save area; a limit for a kind is counted",
                b["room"] == 8 * pulli.MB - 512 * 1024 and len(b["over"]) == 1 and "sound effects" in b["over"][0], b["over"])
        t.check("the setting is left out of the package", ".pattarai.json" not in dict(pulli.parse(pulli.build(game))))
        with open(os.path.join(game, ".pattarai.json"), "w") as f:
            f.write("not json")
        t.check("a damaged setting reads as no setting", pulli.game_settings(game) == {"target": "sd", "strict": False, "limits": {}})

        srv, token = pulli.edit_server(game, 0)
        threading.Thread(target=srv.serve_forever, daemon=True).start()

        def ask(method, path, body=None):
            c = http.client.HTTPConnection("127.0.0.1", srv.server_port, timeout=60)
            c.request(method, path, body=body, headers={"Host": f"127.0.0.1:{srv.server_port}", "X-Pulli-Token": token})
            r = c.getresponse()
            return r.status, r.read()

        try:
            status, body = ask("GET", "/api/budget")
            t.check("the page asks the server for the budget", status == 200 and json.loads(body)["target"] == "SD card")
            status, _ = ask("PUT", "/api/file?path=.pattarai.json", json.dumps({"target": "board", "strict": True}).encode())
            t.check("the page sets the game's budget; another hidden file is still refused",
                    status == 200 and pulli.game_settings(game)["target"] == "board" and
                    ask("PUT", "/api/file?path=.secret.json", b"{}")[0] == 403)
            big = wav(os.path.join(tmp, "big.wav"), 90)                  # 90 s of 22,050 mono: 3.9 MB in the game
            status, body = ask("PUT", "/api/file?path=sfx/9-big.wav", big)
            t.check("strict: a save that takes the game past its board is refused, saying why",
                    status == 409 and b"Pico 2 board" in body and b"strict" in body and not os.path.exists(os.path.join(game, "sfx", "9-big.wav"))
                    and not [f for f in os.listdir(os.path.join(game, "sfx")) if f.endswith(".part")], body)
            t.check("strict: code is saved even so", ask("PUT", "/api/file?path=main.lua",
                    open(os.path.join(game, "main.lua"), "rb").read())[0] == 200)
            ask("PUT", "/api/file?path=.pattarai.json", json.dumps({"target": "board", "strict": False}).encode())
            status, _ = ask("PUT", "/api/file?path=sfx/9-big.wav", big)
            over = json.loads(ask("GET", "/api/budget")[1])
            t.check("not strict: the save goes through, and the budget says the game is over", status == 200 and over["over"])
            ask("PUT", "/api/file?path=.pattarai.json", json.dumps({"target": "board", "strict": True}).encode())
            small = wav(os.path.join(tmp, "small.wav"), 10)
            t.check("strict, already over: a save that makes the game smaller is let through",
                    ask("PUT", "/api/file?path=sfx/9-big.wav", small)[0] == 200)
            ask("PUT", "/api/file?path=.pattarai.json", json.dumps({"target": "sd"}).encode())
            bad_png = open(os.path.join(game, "sprites.png"), "rb").read()
            bad_png = bad_png[:16] + struct.pack(">II", 1024, 1024) + bad_png[24:]
            three = bytearray(wav(os.path.join(tmp, "three.wav"), 0.1))
            three[22:24] = struct.pack("<H", 3)
            huge_map = ('<?xml version="1.0"?><map orientation="orthogonal" width="200" height="200" tilewidth="8" '
                        'tileheight="8" infinite="0"><tileset firstgid="1" source="sprites.tsx"/><layer id="1" name="a" '
                        'width="200" height="200"><data encoding="csv">' + ",".join(["0"] * 40000) + '</data></layer></map>')
            refusals = [ask("PUT", "/api/file?path=" + p, d) for p, d in (("big.png", bad_png), ("sfx/3.wav", bytes(three)),
                                                                          ("huge.tmx", huge_map.encode()))]
            t.check("never strict, still refused: a picture past 128 KB, a sound of three channels, a map past 32,768 tiles",
                    [r[0] for r in refusals] == [409, 409, 409] and b"SPEC" in refusals[0][1] and b"channels" in refusals[1][1]
                    and not any(os.path.exists(os.path.join(game, p)) for p in ("big.png", "sfx/3.wav", "huge.tmx")),
                    [r[1][:90] for r in refusals])
        finally:
            srv.stop_game()
            srv.shutdown()
            srv.server_close()


def palette(t):
    text = open(os.path.join(HERE, "lib", "palette.js")).read()
    colours = [int(v, 16) for v in re.findall(r"0x([0-9a-f]{6})", text.split("export function")[0])]
    t.check("the editors' 64 colours are the runtime's", colours == list(refgfx.DEFAULT_PALETTE))


def server(t):
    with tempfile.TemporaryDirectory() as tmp:
        game = os.path.join(tmp, "game")
        os.makedirs(os.path.join(game, "music"))
        for name, data in (("main.lua", "function draw() end\n"), ("sprites.png", "png"), ("map.tmx", "<map/>"),
                           ("music/a.json", "{}"), (".hidden.png", "x")):
            with open(os.path.join(game, name), "w") as f:
                f.write(data)
        with open(os.path.join(tmp, "secret.png"), "w") as f:
            f.write("outside")
        srv, token = pulli.edit_server(game, 0)
        port = srv.server_port
        threading.Thread(target=srv.serve_forever, daemon=True).start()

        def ask(method, path, body=None, key=token, host=None):
            c = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
            headers = {"Host": host or f"127.0.0.1:{port}"}
            if key:
                headers["X-Pulli-Token"] = key
            c.request(method, path, body=body, headers=headers)
            r = c.getresponse()
            return r.status, r.read()

        try:
            status, body = ask("GET", "/")
            t.check("the page is served", status == 200 and b"Pattarai" in body)
            t.check("the page's own files are served", ask("GET", "/lib/music.js")[0] == 200)
            t.check("nothing outside the page's folder is served",
                    ask("GET", "/../pulli.py")[0] == 404 and ask("GET", "/%2e%2e/pulli.py")[0] == 404)
            t.check("the files cannot be listed without the key", ask("GET", "/api/files", key=None)[0] == 403
                    and ask("GET", "/api/files", key="guess")[0] == 403)
            t.check("a request addressed to another name is refused (DNS rebinding)",
                    ask("GET", "/api/files", host="evil.example:80")[0] == 403)
            status, body = ask("GET", "/api/files")
            t.check("the files list holds what the editors open, and no hidden files",
                    status == 200 and json.loads(body)["files"] == ["main.lua", "map.tmx", "music/a.json", "sprites.png"], body)
            t.check("a file is read", ask("GET", "/api/file?path=map.tmx") == (200, b"<map/>"))
            os.makedirs(os.path.join(game, "sfx"))
            import wave
            for name, ch, rate in (("b.wav", 1, 22050), ("a.wav", 2, 8000)):
                with wave.open(os.path.join(game, "sfx", name), "wb") as w:
                    w.setnchannels(ch); w.setsampwidth(2); w.setframerate(rate); w.writeframes(b"\0\0" * ch * rate)
            with open(os.path.join(game, "sfx", "c.wav"), "wb") as f:
                f.write(b"not a wav")
            status, body = ask("GET", "/api/sounds")
            got = json.loads(body)
            t.check("the sounds are numbered as pack numbers them, each with its channels, rate and length",
                    status == 200 and got["max"] == 256 and got["music"] == [] and
                    [(x["n"], x["path"], x.get("channels"), x.get("rate"), x.get("seconds")) for x in got["sfx"]] ==
                    [(0, "sfx/a.wav", 2, 8000, 1.0), (1, "sfx/b.wav", 1, 22050, 1.0), (2, "sfx/c.wav", None, None, None)]
                    and "error" in got["sfx"][2] and got["sfx"][1]["packed"] == 44100, got)
            t.check("the sounds cannot be listed without the key", ask("GET", "/api/sounds", key=None)[0] == 403)
            shutil.rmtree(os.path.join(game, "sfx"))
            t.check("a file outside the game is not read",
                    ask("GET", "/api/file?path=../secret.png")[0] == 404 and
                    ask("GET", "/api/file?path=" + os.path.join(tmp, "secret.png"))[0] == 404)
            t.check("a song is written, its folder made", ask("PUT", "/api/file?path=music/new/b.json", b"{1}")[0] == 200
                    and open(os.path.join(game, "music", "new", "b.json")).read() == "{1}")
            t.check("Lua is written", ask("PUT", "/api/file?path=main.lua", b"function draw() end\n")[0] == 200)
            t.check("other kinds, hidden files and places outside the game are never written",
                    ask("PUT", "/api/file?path=run.py", b"evil")[0] == 403 and
                    ask("PUT", "/api/file?path=x.lua.sh", b"evil")[0] == 403 and
                    ask("PUT", "/api/file?path=.x.png", b"x")[0] == 403 and
                    ask("PUT", "/api/file?path=../out.png", b"x")[0] == 403 and
                    ask("PUT", "/api/file?path=map.tmx", b"x", key="guess")[0] == 403 and
                    not os.path.exists(os.path.join(game, "run.py")) and
                    not os.path.exists(os.path.join(tmp, "out.png")))
            t.check("the game cannot be checked without the key", ask("POST", "/api/check", key="guess")[0] == 403)

            # Run, and restart on save: with a stand-in for the emulator that notes each start
            fake = os.path.join(tmp, "fakehost")
            os.makedirs(fake)
            starts = os.path.join(tmp, "starts.txt")
            with open(os.path.join(fake, "pulli-host"), "w") as f:
                f.write(f"#!/bin/sh\necho \"$1\" >> {starts}\nexec sleep 30\n")
            os.chmod(os.path.join(fake, "pulli-host"), 0o755)
            with open(os.path.join(game, "manifest.lua"), "w") as f:
                f.write('return { id = "test.edit", title = "Edit", spec = 1 }\n')
            was = os.environ.get("PULLI_HOST_DIR")
            os.environ["PULLI_HOST_DIR"] = fake
            import time
            def count():
                time.sleep(1.0)
                return len(open(starts).read().split()) if os.path.exists(starts) else 0
            try:
                for junk in ("sprites.png", "map.tmx"):             # not a real picture and map
                    if os.path.exists(os.path.join(game, junk)):
                        os.remove(os.path.join(game, junk))
                first = ask("POST", "/api/run?live=1")
                ok = first[0] == 200 and count() == 1
                ask("PUT", "/api/file?path=music/a.json", b"{2}")
                ok = ok and count() == 2
                ask("POST", "/api/run")                            # not live: a save leaves it be
                ask("PUT", "/api/file?path=music/a.json", b"{3}")
                ok = ok and count() == 3
                ask("POST", "/api/stop")
                ask("PUT", "/api/file?path=music/a.json", b"{4}")
                t.check("Run starts the game; live, each save starts it again; stopped, it stays stopped",
                        ok and count() == 3, open(starts).read() if os.path.exists(starts) else first)
                t.check("the game cannot be run without the key", ask("POST", "/api/run", key="guess")[0] == 403)
            finally:
                srv.stop_game()
                if was is None:
                    os.environ.pop("PULLI_HOST_DIR", None)
                else:
                    os.environ["PULLI_HOST_DIR"] = was
                pass
            if t.need_runtime("checking a game from the page"):
                with open(os.path.join(game, "manifest.lua"), "w") as f:
                    f.write('return { id = "test.edit", title = "Edit", spec = 1 }\n')
                for junk in ("sprites.png", "map.tmx"):
                    if os.path.exists(os.path.join(game, junk)):
                        os.remove(os.path.join(game, junk))
                os.environ["PULLI_HOST_DIR"] = os.path.dirname(t.headless)
                status, body = ask("POST", "/api/check")
                good = json.loads(body)
                ask("PUT", "/api/file?path=main.lua", b"function init()\nend\nfunction draw()\n  local x = nil + 1\nend\n")
                bad = json.loads(ask("POST", "/api/check")[1])
                t.check("a check of a sound game passes; of a broken one names the file and line",
                        good["ok"] and not bad["ok"] and "main.lua:4:" in bad["out"], (good, bad))
        finally:
            srv.shutdown()
            srv.server_close()


def main():
    t = Suite("Pattarai, the editors")
    palette(t)
    budget(t)
    tamil(t)
    project(t)
    server(t)
    library(t)
    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
