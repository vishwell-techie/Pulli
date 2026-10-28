#!/usr/bin/env python3
"""The example games run, and still draw exactly what they drew before.

Run: python3 tests/test_examples.py [--update]

Each example is run for a fixed number of frames with fixed input, and the
final framebuffer and screen, and all the sound the run made, are hashed
against tests/examples.sha256. The
runtime is deterministic (SPEC §4), so a changed hash means the engine, the
Lua build or the example itself changed behaviour. If that was intended,
rerun with --update. The same hashes must come out on every machine.
"""
import hashlib, os, re, shutil, struct, sys, tempfile

from harness import Suite, ROOT, TESTS, pulli

#        example  frames  held buttons    taps (button@frame)
RUNS = [("hello", 120,    None,           None),
        ("hello", 120,    "right,down,a", None),
        ("pong",  600,    None,           None),                  # sits on the menu
        ("pong",  3600,   None,           "a@5"),                 # a whole match; the console wins
        ("pong",  3600,   "up",           "a@5"),
        ("pong",  3600,   "x",            "down@1,a@5"),          # two players
        ("hello", 120,    None,           "r@10,r@20,l@30,r@40"), # L and R change the box's colour
        ("manickam", 120,  None,          None),                  # waits on the title screen
        ("manickam", 900,  None,          "a@5"),                 # the opening cut-scene, waiting on its first line
        ("manickam", 600,  None, "a@5,start@100,a@300,a@330,a@360,a@390,a@420,right@440-600"),  # skipped; chapter 0, walking
        ("talk",  120,    "right",        None),                  # the SDK helpers; the camera follows
        ("catch", 900,    "right",        "a@30")]                # the tutorial's game, played until it is lost

# Talk: walk to the villager and press A. They greet you (read it), ask
# (wait for the question to appear), you answer yes, read the reply, and
# the gem flies to the bag.
TALK_TAPS = "right@1-296,a@330,a@340,a@350,a@450,a@510"
TALK_ASKED, TALK_FLYING, TALK_FRAMES = 430, 516, 600
# The same, but answering no: the villager replies, and A closes the box.
TALK_NO_TAPS = "right@1-296,a@330,a@340,a@350,down@440,a@450,a@460,a@470"

MANICKAM = os.path.join(ROOT, "examples", "manickam")


def manickam_variant(tmp, chapter, extra=""):
    """Manickam, changed to start straight in a chapter."""
    import shutil
    folder = os.path.join(tmp, "manickam")
    shutil.copytree(MANICKAM, folder, ignore=shutil.ignore_patterns("music", "sfx"))
    main = open(os.path.join(folder, "main.lua")).read()
    main = main.replace('core.go("title")', f'core.go("play", {chapter})')
    open(os.path.join(folder, "main.lua"), "w").write(main + extra)
    return pulli.build(folder)


def walkable_without_keys(name):
    """From a Manickam map's start, which markers can be reached without
    opening a shrine gate. Reads the .tmx and the tileset's flags."""
    import xml.etree.ElementTree as ET
    flags = {}
    for tile in ET.parse(os.path.join(MANICKAM, "sprites.tsx")).getroot().iter("tile"):
        for prop in tile.iter("property"):
            if prop.get("name") == "flags":
                flags[int(tile.get("id"))] = int(prop.get("value"))
    root = ET.parse(os.path.join(MANICKAM, name + ".tmx")).getroot()
    w, h = int(root.get("width")), int(root.get("height"))
    ground, front = [[(int(v) & 0x0FFFFFFF) - 1 for v in layer.find("data").text.replace("\n", "").split(",")
                      if v.strip()] for layer in root.iter("layer")]
    names = "start slime swimmer paati potter villager villager2 piece key pot lotus heart".split() + \
        "switch_a switch_b switch_c stone_a stone_b stone_c exit".split()
    marks = {}
    for i, t in enumerate(front):
        if 1000 <= t < 1000 + len(names):
            marks.setdefault(names[t - 1000], []).append(i)
    start = marks["start"][0]
    seen, todo = {start}, [start]
    while todo:
        i = todo.pop()
        for j in (i - 1, i + 1, i - w, i + w):
            if 0 <= j < w * h and abs(j % w - i % w) <= 1 and j not in seen and not flags.get(ground[j], 0) & (1 | 8):
                seen.add(j)
                todo.append(j)
    return {k: (sum(i in seen for i in v), len(v)) for k, v in marks.items()}


# Nizhalattam's music is some 70 MB of WAV, and packing it takes a minute:
# the copies the tests play leave it out (music() then does nothing), and
# one test packs the game whole.
NO_MUSIC = shutil.ignore_patterns("music")


def challenge_passable(rows, start, goal, up, across, wall=False, dodge=False):
    """Whether, in a challenge room drawn as rows of "#" (solid), "=" (thin)
    and "." (open), Komali can get from `start` to `goal` (cells his feet
    stand in): climbing `up` tiles and jumping `across` (the double jump:
    more of each); with the wall jump, up a narrow shaft between two walls;
    with the second dodge, straight across a pit at most 14 wide, or one
    tile down."""
    h, w = len(rows), len(rows[0])
    solid = lambda x, y: not (0 <= x < w and 0 <= y < h) or rows[y][x] == "#"
    floor_ = lambda x, y: 0 <= y + 1 < h and rows[y + 1][x] in "#="
    stand = lambda x, y: 0 <= x < w and 0 <= y < h and not any(solid(x, y - n) for n in range(3)) and floor_(x, y)

    def nexts(x, y):
        for dx in range(-across, across + 1):
            lo, hi = sorted((x, x + dx))
            for dy in range(-up, h - y):
                q = (x + dx, y + dy)
                top = min(y, q[1])
                if stand(*q) and not any(solid(x, yy) for yy in range(top - 2, y + 1)) \
                   and not any(solid(c, yy) for c in range(lo + 1, hi) for yy in range(y - up, top + 1)):
                    yield q
        if wall:                       # a shaft: walls either side within five tiles, all the way up
            for dx in range(-6, 7):
                for dy in range(-12, -up - 1 + 1):
                    q = (x + dx, y + dy)
                    if stand(*q):
                        lo, hi = sorted((x, q[0]))
                        ok = True
                        for yy in range(q[1] + 1, y - 2):     # (the bottom of a shaft is walked into)
                            left = any(solid(c, yy) for c in range(lo - 4, lo + 1))
                            right = any(solid(c, yy) for c in range(hi, hi + 5))
                            if not (left and right):
                                ok = False
                                break
                        if ok:
                            yield q
        if dodge:                      # two rolls, straight on, through nothing solid
            for d in (-1, 1):
                for n in range(1, 15):
                    if any(solid(x + d * n, y - r) for r in range(3)):
                        break
                    for dy in (0, 1):
                        q = (x + d * n, y + dy)
                        if stand(*q):
                            yield q
    seen, todo = {start}, [start]
    while todo:
        for q in nexts(*todo.pop()):
            if q not in seen:
                seen.add(q)
                todo.append(q)
    return goal in seen


def nizhalattam_climbs(up=3, across=7):
    """Whether, in every Nizhalattam room, each door can be reached from the
    start and from each other door, climbing at most `up` tiles at a time (a
    held jump rises 4.5) and jumping at most `across` tiles. A coarse walk
    over the places Komali can stand (three clear tiles over a floor); a
    boat's deck stands level with the quays, and a ferry's spans its water.
    The grey test rooms too: they are behind a door in the Courtyard."""
    import glob, xml.etree.ElementTree as ET
    game = os.path.join(ROOT, "examples", "nizhalattam")
    flags = {}
    for tile in ET.parse(os.path.join(game, "sprites.tsx")).getroot().iter("tile"):
        for prop in tile.iter("property"):
            if prop.get("name") == "flags":
                flags[int(tile.get("id"))] = int(prop.get("value"))
    START, DOOR, BOAT, FERRY = 1000, 1002, 1016, 1017
    stuck = []
    for path in sorted(glob.glob(os.path.join(game, "*.tmx"))):
        name = os.path.basename(path)[:-4]
        root = ET.parse(path).getroot()
        w, h = int(root.get("width")), int(root.get("height"))
        ground, front = [[(int(v) & 0x0FFFFFFF) - 1 for v in layer.find("data").text.replace("\n", "").split(",")
                          if v.strip()] for layer in root.iter("layer")]
        for o in root.iter("object"):          # the room's things, its map's objects, put in their cells
            kind = {"start": START, "door": DOOR, "boat": BOAT, "ferry": FERRY}.get(o.get("class"))
            if kind:
                front[(int(o.get("y")) - 8) // 8 * w + (int(o.get("x")) - 4) // 8] = kind
        flag = lambda x, y: 1 if not 0 <= x < w else 0 if not 0 <= y < h else flags.get(ground[y * w + x], 0)
        decks = set()                          # cells a boat's deck holds Komali up in
        for i, m in enumerate(front):
            x, y = i % w, i // w
            if m == BOAT:
                decks |= {(c, y) for c in range(x - 2, x + 4)}
            elif m == FERRY:
                a = b = x
                while not flag(a - 1, y + 1) & 1 and not flag(a - 1, y) & 1: a -= 1
                while not flag(b + 1, y + 1) & 1 and not flag(b + 1, y) & 1: b += 1
                decks |= {(c, y) for c in range(a, b + 1)}
        solid = lambda x, y: flag(x, y) & 1
        stand = lambda x, y: (0 <= x < w and 0 <= y < h and not any(solid(x, y - n) for n in range(3))
                              and (flag(x, y + 1) & 3 or (x, y) in decks))

        def nexts(x, y):
            for dx in range(-across, across + 1):
                lo, hi = sorted((x, x + dx))
                for dy in range(-up, h - y):
                    q = (x + dx, y + dy)
                    top = min(y, q[1])             # the arc's lowest top: nothing solid in the way
                    if stand(*q) and not any(solid(x, yy) for yy in range(top - 2, y + 1)) \
                       and not any(solid(c, yy) for c in range(lo + 1, hi) for yy in range(y - up, top + 1)):
                        yield q
            if flag(x, y + 1) & 2 and not flag(x, y + 1) & 1:      # down + A through a thin floor
                yy = y + 2
                while yy < h and not stand(x, yy) and not solid(x, yy):
                    yy += 1
                if stand(x, yy):
                    yield (x, yy)

        def snap(x, y):
            while y < h and not stand(x, y):
                y += 1
            return x, y
        doors = [snap(i % w, i // w) for i, m in enumerate(front) if m == DOOR]
        for s in [snap(i % w, i // w) for i, m in enumerate(front) if m == START] + doors:
            seen, todo = {s}, [s]
            while todo:
                for q in nexts(*todo.pop()):
                    if q not in seen:
                        seen.add(q)
                        todo.append(q)
            stuck += [f"{name}: {s} to {d}" for d in doors if d not in seen]
    return not stuck, stuck


# Pong seeds its random numbers from the frame on which A is pressed. Pressed
# on frame 6, the first serve goes to the console, which returns it: that
# puts the console's paddle to work and gives a paddle hit to test against.
START = "a@6"

# The four levels, chosen from the menu and compared while the console is
# chasing that serve, where its paddle is somewhere different on each.
LEVEL_FRAME = 160
LEVEL_TAPS = {"easy": "left@1,a@6", "normal": "a@6", "hard": "right@1,a@6",
              "insane": "right@1,right@3,a@6"}


def main():
    t = Suite("Pulli examples")
    path = os.path.join(TESTS, "examples.sha256")
    pinned = {}
    if os.path.exists(path):
        for line in open(path):
            key, digest = line.rsplit(None, 1)
            pinned[key] = digest

    for name in sorted({r[0] for r in RUNS}):
        try:
            pulli.build(os.path.join(ROOT, "examples", name))
            ok, why = True, ""
        except pulli.PackageError as e:
            ok, why = False, str(e)
        t.check(f"{name} packs", ok, why)

    # Every example is written with the SDK: it requires helpers, which
    # packing supplies, and keeps no copy of any in its own folder.
    helpers = {f for f in os.listdir(os.path.join(ROOT, "sdk")) if f.endswith(".lua")}
    for name in sorted(os.listdir(os.path.join(ROOT, "examples"))):
        folder = os.path.join(ROOT, "examples", name)
        packed = {n for n, _ in pulli.parse(pulli.build(folder))}
        t.check(f"{name} uses SDK helpers and keeps no copies of them",
                packed & helpers and not helpers & set(os.listdir(folder)), sorted(packed & helpers))

    # The forest: shrine gates close the piece, the heart lotus and the way
    # out, and all three keys can be found without opening one.
    forest = walkable_without_keys("forest")
    t.check("manickam: in the forest the piece, the heart and the exit are behind gates, and every key is not",
            forest["key"] == (3, 3) and forest["piece"][0] == forest["heart"][0] == forest["exit"][0] == 0, forest)

    if t.need_runtime("running the examples"):
        seen = {}
        for name, frames, hold, tap in RUNS:
            key = f"{name} frames={frames} hold={hold or '-'} tap={tap or '-'}"
            r = t.run_package(pulli.build(os.path.join(ROOT, "examples", name)),
                              frames=frames, hold=hold, tap=tap, sound=True)
            if not t.check(f"{key}: runs without error", r.code == 0, r.err):
                continue
            seen[key] = hashlib.sha256(r.fb + r.rgb).hexdigest()
            seen[key + " sound"] = hashlib.sha256(r.wav).hexdigest()
            if not t.update:
                t.check(f"{key}: draws what it drew before", seen[key] == pinned.get(key),
                        "behaviour changed; if that was intended, rerun with --update")
                t.check(f"{key}: sounds as it sounded before", seen[key + " sound"] == pinned.get(key + " sound"),
                        "the sound changed; if that was intended, rerun with --update")

        # Hello: R moves the box to the next colour and L back again.
        hello = pulli.build(os.path.join(ROOT, "examples", "hello"))
        shot = lambda tap: t.run_package(hello, frames=30, tap=tap).fb
        t.check("hello: R gives the box another colour, and L puts it back",
                shot("r@10") != shot(None) == shot("r@10,l@20") and shot("r@10,r@20") != shot("r@10"))

        game = pulli.build(MANICKAM)
        begin = "a@5"
        fresh = t.run_package(game, frames=20).fb
        # The title: a menu in Tamil to start with; the language set in the
        # options is kept for next time, as is a game once begun (Continue).
        with tempfile.TemporaryDirectory() as saves:
            t.run_package(game, frames=40, tap="down@5,a@10,a@20,b@30", saves=saves)     # Options, language, back
            english = t.run_package(game, frames=20, saves=saves).fb
            t.check("manickam: the language chosen in the options is kept for next time", english != fresh)
        with tempfile.TemporaryDirectory() as saves:
            t.run_package(game, frames=200, tap=f"{begin},start@100", saves=saves)       # New game
            again = t.run_package(game, frames=20, saves=saves).fb
            t.check("manickam: once a game is begun, the title offers to continue it", again != fresh)
        marked = t.run_package(game, frames=20, tap="select@5").fb
        unmarked = t.run_package(game, frames=20, tap="select@5,select@10").fb
        t.check("manickam: SELECT on the title switches the benchmark on, and again off",
                marked != fresh and unmarked == fresh)
        # The benchmark: a fixed run through heavy scenes, the same on every
        # machine, reporting each scene through dbg().
        runs = [t.run_package(game, frames=4230, tap="select@5,a@10") for _ in range(2)]
        lines = [[l for l in r.lines if l.startswith("bench ") and "frames=" in l] for r in runs]
        t.check("manickam: the benchmark runs its scenes and reports each, the same every run",
                all(r.code == 0 for r in runs) and len(lines[0]) == 7 and lines[0] == lines[1]
                and all("frames=600" in l for l in lines[0]), lines[0] + [runs[0].err[-300:]])

        # A new game opens with the cut-scene; START skips it to chapter 0,
        # and leaves the world as watching it to the end would.
        opened = t.run_package(game, frames=150, tap=begin)
        skipped = t.run_package(game, frames=300, tap=f"{begin},start@100")
        t.check("manickam: a new game begins with the opening, and START skips it to chapter 0",
                "chapter opening" in opened.lines and "chapter 0" not in opened.lines
                and "chapter 0" in skipped.lines, skipped.err)

        # Pause: START freezes chapter 0 and START again carries on, to the
        # same picture a run with no pause reaches.
        go = begin + ",start@100," + ",".join(f"a@{f}" for f in range(300, 571, 30))   # skip the opening, read Minmini's tips
        walk = lambda n: f"up@600-{n}"
        plain = t.run_package(game, frames=700, tap=f"{go},{walk(700)}")
        held = t.run_package(game, frames=660, tap=f"{go},{walk(660)},start@640")
        resumed = t.run_package(game, frames=760, tap=f"{go},{walk(760)},start@640,start@700")
        t.check("manickam: START pauses and START again carries on where it left off",
                plain.code == 0 and held.fb != t.run_package(game, frames=660, tap=f"{go},{walk(660)}").fb
                and resumed.fb == plain.fb, plain.err)
        pressed = t.run_package(game, frames=645, tap=f"{go},start@640", sound=True).sound[639 * 735:]
        unpressed = t.run_package(game, frames=645, tap=go, sound=True).sound[639 * 735:]
        t.check("manickam: pausing plays a tone", pressed != unpressed)
        shown = t.run_package(game, frames=700, tap=f"{go},select@640")
        t.check("manickam: SELECT while playing shows how hard the machine is working",
                shown.code == 0 and shown.fb != plain.fb, shown.err[-300:])

        # Every chapter loads its map and region and plays a while, in both
        # languages; and the worst case for memory, every module loaded with
        # the festival's fireworks going, fits in the Lua heap.
        with tempfile.TemporaryDirectory() as tmp:
            for ch in range(7):
                r = t.run_package(manickam_variant(os.path.join(tmp, str(ch)), ch), frames=400,
                                  tap="a@100,a@160,a@220,a@280,right@300-400")
                t.check(f"manickam: chapter {ch} starts and plays", r.code == 0 and f"chapter {ch}" in r.lines, r.err[-300:])
            # Night with Minmini flaring again and again: lights of every
            # size must not use up memory.
            flares = ",".join(f"b@{f}" for f in range(300, 3000, 200))
            r = t.run_package(manickam_variant(os.path.join(tmp, "flare"), 2), frames=3000,
                              tap="a@100,a@160,a@220,a@280," + flares)
            t.check("manickam: flaring in the dark forest for a minute keeps within memory", r.code == 0, r.err[-300:])
            # Caught: Kayal spins and fades, the game is over, and A goes back
            # to the title.
            dies = 'local up = update\nfunction update(dt) up(dt) if stat("frame") == 120 then require("world").die() end end\n'
            death = manickam_variant(os.path.join(tmp, "die"), 0, extra=dies)
            dying = t.run_package(death, frames=170)
            over = t.run_package(death, frames=330)
            back = t.run_package(death, frames=600, tap="a@420")
            title = t.run_package(game, frames=20).fb
            t.check("manickam: when the dark catches Kayal she fades away and the game is over; A goes to the title",
                    dying.code == 0 and over.code == 0 and back.code == 0 and dying.fb != over.fb
                    and back.fb[:320 * 120] == title[:320 * 120], back.err[-300:])   # the title art, above the menu
            # Caught in the hills when the escape runs out, with both pieces
            # found: she dies once, and Continue on the title begins the
            # chapter afresh, the pieces back in their caves to find again.
            late = ('local up = update\nlocal w, core = require("world"), require("core")\nlocal die, last = w.die\n'
                    'function w.die() dbg("die") die() end\n'
                    'function update(dt) up(dt)\n'
                    '  if stat("frame") == 400 then\n'
                    '    local d = require("progress").data\n'
                    '    for _, t in ipairs(w.things) do if t.kind == "piece" then\n'
                    '      d.got[t.id] = true d.pieces = d.pieces | (1 << (w.region.pieces[t.n] - 1)) end end\n'
                    '    w.region.escape = 0.5\n'
                    '  end\n'
                    '  if core.current() ~= last then last = core.current() dbg("scene", last) end\n'
                    '  if stat("frame") == 1400 then local n = 0\n'
                    '    for _, t in ipairs(w.things) do if t.kind == "piece" then n = n + 1 end end\n'
                    '    dbg("left", w.pieces_left(), n) end\n'
                    'end\n')
            r = t.run_package(manickam_variant(os.path.join(tmp, "late"), 4, extra=late), frames=1400,
                              tap="a@100,a@130,a@160,a@190,a@220,a@250,a@420,a@440,a@460,a@700,a@900,"
                                  "a@1000,a@1030,a@1060,a@1090,a@1120")
            t.check("manickam: caught once, she dies once; Continue starts the chapter afresh, its pieces to find again",
                    r.code == 0 and r.out.count("die") == 1 and r.out.count("scene\tover") == 1
                    and "scene\ttitle\nscene\tplay" in r.out and "left\t2\t2" in r.out, r.out[-400:] + r.err[-300:])
            # Every chapter: everything found in it, picked up, then the
            # chapter begun again. Not yet finished, it is all back to find,
            # with the hearts as they were; finished, it stays found.
            again = ('local up = update\nlocal w, core, progress = require("world"), require("core"), require("progress")\n'
                     'local function state(tag) local d, n = progress.data, 0\n'
                     '  for _, t in ipairs(w.things) do if t.kind ~= "key" then n = n + 1 end end\n'
                     '  dbg(tag, n, d.pieces, d.hearts, d.lotuses, d.pots) end\n'
                     'function update(dt) up(dt) local f = stat("frame")\n'
                     '  if f == 300 then state("start")\n'
                     '    for i = #w.things, 1, -1 do local t = w.things[i]\n'
                     '      if t.kind ~= "key" then table.remove(w.things, i) w.pick(t) end end\n'
                     '    state("found") FINISH end\n'
                     '  if f == 330 then core.go("play", w.chapter) end\n'
                     '  if f == 700 then state("again") end\n'
                     'end\n')
            for ch in range(1, 6):
                for finished in (False, True):
                    extra = again.replace("FINISH", "progress.data.unlocked = w.chapter + 1" if finished else "")
                    r = t.run_package(manickam_variant(os.path.join(tmp, f"again{ch}{finished}"), ch, extra=extra),
                                      frames=700, tap="a@100,a@160,a@220,a@280")
                    got = {k: v for k, *v in (l.split("\t", 1) for l in r.out.splitlines() if "\t" in l)}
                    want = got.get("found") if finished else got.get("start")
                    t.check(f"manickam: chapter {ch} begun again " + ("once finished keeps what was found" if finished
                            else "before it is finished has its gems and hearts to find again"),
                            r.code == 0 and got.get("start") != got.get("found") and got.get("again") == want,
                            r.out[-300:] + r.err[-300:])
            # What earlier chapters gave is hers: the lake begun again, with
            # the fields' and forest's pieces and two heart lotuses already
            # found, puts back only the lake's own.
            before = again.replace('if f == 300 then state("start")',
                                   'if f == 290 then local d = progress.data d.pieces, d.hearts = 3, 5 '
                                   'd.got[1 * 65536 + 5] = true d.got[2 * 65536 + 5] = true end\n'
                                   '  if f == 300 then state("start")').replace("FINISH", "")
            r = t.run_package(manickam_variant(os.path.join(tmp, "before"), 3, extra=before),
                              frames=700, tap="a@100,a@160,a@220,a@280")
            t.check("manickam: a chapter begun again keeps the gems and hearts found in earlier chapters",
                    r.code == 0 and "start\t10\t3\t5\t0\t0" in r.out and "found\t0\t15\t6\t7\t0" in r.out
                    and "again\t10\t3\t5\t0\t0" in r.out, r.out[-300:] + r.err[-300:])
            # Hearts carry on into the next chapter, and Paati's story
            # between chapters gives one back; starting afresh gives them all.
            carry = ('local up = update\nfunction update(dt) up(dt)\n'
                     '  local w = require("world")\n'
                     '  if stat("frame") == 150 then w.p.hearts = 1 w.finish() end\n'
                     '  if w.chapter == NEXT and w.control and not shown then shown = true dbg("hearts", w.p.hearts) end\n'
                     'end\n')
            story = ",".join(f"a@{f}" for f in range(200, 1400, 30))
            told = t.run_package(manickam_variant(os.path.join(tmp, "carry"), 1, extra=carry.replace("NEXT", "2")),
                                 frames=1500, tap=story)
            r = t.run_package(manickam_variant(os.path.join(tmp, "carry0"), 0, extra=carry.replace("NEXT", "1")),
                              frames=1500, tap=story)
            fresh = t.run_package(manickam_variant(os.path.join(tmp, "fresh"), 2,
                                                   extra=carry.replace("== 150", "== -1").replace("NEXT", "2")),
                                  frames=400, tap="a@100,a@130,a@160")
            t.check("manickam: Kayal starts the next chapter with the hearts she had left",
                    "hearts\t1" in r.out, r.out[-300:] + r.err[-300:])
            t.check("manickam: Paati's story between chapters gives her one heart back",
                    "hearts\t2" in told.out, told.out[-300:] + told.err[-300:])
            t.check("manickam: a chapter started afresh gives her all her hearts",
                    "hearts\t3" in fresh.out, fresh.out[-300:] + fresh.err[-300:])
            # Picking up a ruby piece with a slime on top of her: while she
            # holds it up nothing hostile moves, and the slime is scared off
            # before the world moves again, so she loses no heart.
            pick = ('local up = update\nlocal s0\nfunction update(dt) up(dt)\n'
                    '  local w = require("world")\n'
                    '  local f = stat("frame")\n'
                    '  if f == 150 then require("talk").clear() w.add_slime(w.p.x, w.p.y) s0 = w.slimes[#w.slimes]\n'
                    '    w.pick({ kind = "piece", n = 1, x = w.p.x, y = w.p.y }) s0.x0, s0.y0 = s0.x, s0.y end\n'
                    '  if f == 220 then dbg("held", w.p.hearts, s0.x == s0.x0 and s0.y == s0.y0) end\n'
                    '  if f == 460 then dbg("after", w.p.hearts) end\n'
                    'end\n')
            r = t.run_package(manickam_variant(os.path.join(tmp, "pick"), 0, extra=pick), frames=470,
                              tap="a@100,a@130,a@260,a@290,a@320,a@350")
            t.check("manickam: while Kayal holds up a piece, a slime on top of her stays still and does no harm",
                    "held\t3\ttrue" in r.out, r.out[-300:] + r.err[-300:])
            t.check("manickam: after the piece, the slime is scared off and she still has every heart",
                    "after\t3" in r.out, r.out[-300:] + r.err[-300:])
            # The whole game in one sitting, chapter 0 to the festival, each
            # chapter ended as soon as Kayal can move (chapter 5 by its boss,
            # its lamps lit for her, and A by the great lamp sets the ruby). The chapters left behind are forgotten,
            # so the festival has the room it had when started on its own.
            through = ('local up = update\nlocal done, since = {}, 0\nfunction update(dt) up(dt)\n'
                       '  local w = require("world")\n'
                       '  if w.control then since = since + 1 else since = 0 end\n'
                       '  local c = w.chapter\n'
                       '  if c and since == 120 and not done[c] then\n'
                       '    if c == 5 and not done.top then done.top = true w.start(5, require("ch5").top)\n'
                       '    elseif c ~= 5 then done[c] = true w.finish() end\n'
                       '  end\n'
                       '  if c == 5 and done.top and stat("frame") % 60 == 0 then\n'
                       '    for _, l in ipairs(w.lamps) do l.lit = true end w.p.hearts = 3\n'
                       '    w.p.x, w.p.y = 152, 126\n'                    # by the great lamp, for the ruby
                       '  end\n'
                       '  if c == 6 then in6 = (in6 or 0) + 1 end\n'
                       '  if in6 == 900 then collectgarbage() dbg("festival", stat("mem")) end\n'
                       'end\n')
            # Every sound, map and piece of music is read ahead, at the start
            # or behind a chapter's loading screen, never first in mid-play.
            ahead = ('local ready, pre, s, m, ml = {}, preload, sfx, music, map.load\n'
                     'function preload(...) for _, n in ipairs({ ... }) do ready[n] = true\n'
                     # the copy played here has no sounds; maps must be there
                     '  if not pre(n) and n:find("%.") then dbg("late", "missing " .. n) end end return true end\n'
                     'function sfx(n, ...) if not ready["sfx " .. n] then dbg("late", "sfx " .. n) end return s(n, ...) end\n'
                     'function music(n, ...) if not ready["music " .. n] then dbg("late", "music " .. n) end return m(n, ...) end\n'
                     'function map.load(n) if not ready[n] then dbg("late", n) end return ml(n) end\n')
            reads = ",".join(f"a@{f}" for f in range(100, 9000, 30))
            r = t.run_package(manickam_variant(os.path.join(tmp, "all"), 0, extra=ahead + through), frames=9000, tap=reads)
            kb = [float(l.split("\t")[1]) for l in r.lines if l.startswith("festival")]
            t.check("manickam: played through in one sitting, the festival and its fireworks fit in memory",
                    r.code == 0 and kb and kb[0] < 215, f"{kb} {r.err[-300:]}")
            late = sorted({l for l in r.lines if l.startswith("late")})
            t.check("manickam: every sound, map and tune is read ahead, behind a loading screen, never in mid-play",
                    r.code == 0 and kb and not late, late)
            sounds = len([f for f in os.listdir(os.path.join(MANICKAM, "sfx")) if f.endswith(".wav")])
            t.check("manickam: it reads ahead every sound it has, and no more",
                    f"for i = 0, {sounds - 1} do" in open(os.path.join(MANICKAM, "main.lua")).read(), sounds)
            # Switching language lets the other language's lines go, and
            # a benchmark run from the title is let go when a game starts:
            # either way chapter 0 has the room it has in a plain game.
            settle = ('local up = update\nlocal n = 0\nfunction update(dt) up(dt)\n'
                      '  local w = require("world")\n'
                      '  if w.chapter == 0 and w.control then n = n + 1 end\n'
                      '  if n == 60 then collectgarbage() dbg("settled", stat("mem")) end\n'
                      'end\n')
            def settled(game, frames, tap):
                r = t.run_package(game, frames=frames, tap=tap)
                kb = [float(l.split("\t")[1]) for l in r.lines if l.startswith("settled")]
                return (kb[0] if kb else None), r
            new = "a@5,start@100," + ",".join(f"a@{f}" for f in range(300, 600, 30))
            plain_kb, _ = settled(manickam_variant(os.path.join(tmp, "plainlang"), 0, extra=settle), 600,
                                  "a@100,a@160,a@220,a@280")
            swap = settle.replace("function update(dt) up(dt)\n",
                                  'function update(dt) up(dt)\n  if stat("frame") == 2 then local s = require("story") '
                                  's.lang = "en" s.t("story") s.lang = "ta" s.t("story") end\n')
            swap_kb, r = settled(manickam_variant(os.path.join(tmp, "swap"), 0, extra=swap), 600,
                                 "a@100,a@160,a@220,a@280")
            t.check("manickam: switching language lets the other language's lines go",
                    plain_kb and swap_kb and abs(swap_kb - plain_kb) < 1, f"{plain_kb} {swap_kb} {r.err[-200:]}")
            folder = os.path.join(tmp, "benchfirst")
            shutil.copytree(MANICKAM, folder, ignore=shutil.ignore_patterns("music", "sfx"))
            with open(os.path.join(folder, "main.lua"), "a") as f:
                f.write(settle)
            # Up to 4 KB may stay: the tables of lights and orbs the benchmark
            # filled, which the later chapters fill to the same size anyway.
            B = 4800                              # the benchmark's seven stages are over by then
            game_taps = f"a@{B + 180},start@{B + 280}," + ",".join(f"a@{f}" for f in range(B + 480, B + 900, 30))
            built = pulli.build(folder)
            title_kb, _ = settled(built, B + 900, game_taps)
            bench_kb, r = settled(built, B + 900, f"select@60,a@90,start@{B},select@{B + 120}," + game_taps)
            t.check("manickam: a benchmark run before a game is let go when the game starts",
                    title_kb and bench_kb and abs(bench_kb - title_kb) < 4, f"{title_kb} {bench_kb} {r.err[-200:]}")

            # The ring of pieces fills from the left, whichever was found:
            # the lake's second piece alone shows as the first of seven.
            ring = ('local dr = draw\nfunction draw() dr()\n'
                    '  if stat("frame") == 150 then local t = {}\n'
                    '    for i = 0, 6 do for x = 0, 7 do t[#t + 1] = pget(116 + i * 10 + x, 6) end end\n'
                    '    dbg("ring", table.concat(t, ",")) end\nend\n'
                    'local up = update\nfunction update(dt) up(dt) require("progress").data.pieces = BITS end\n')
            def ring_of(bits):
                r = t.run_package(manickam_variant(os.path.join(tmp, f"ring{bits}"), 3,
                                                   extra=ring.replace("BITS", str(bits))), frames=150)
                return [l for l in r.lines if l.startswith("ring")]
            fourth, first, none = ring_of(1 << 3), ring_of(1), ring_of(0)
            t.check("manickam: the ring fills from the left, whichever piece was found",
                    fourth and fourth == first != none)

            # The hills: standing still in the canyon is no shelter, as most
            # rocks are aimed at Kayal.
            still = ('local up = update\nfunction update(dt) up(dt)\n'
                     '  local w = require("world")\n'
                     '  local f = stat("frame")\n'
                     '  if f == 150 then local m = w.marks.rocks[1] w.p.x, w.p.y = m.x - 4, m.y - 3 w.p.hearts = 9 end\n'
                     '  if f > 150 and f < 750 then w.p.x, w.p.y = require("world").marks.rocks[1].x - 4, w.marks.rocks[1].y - 3 end\n'
                     '  if f == 750 then dbg("hits", 9 - w.p.hearts) end\n'
                     'end\n')
            r = t.run_package(manickam_variant(os.path.join(tmp, "rocks"), 4, extra=still), frames=760,
                              tap=",".join(f"a@{f}" for f in range(100, 760, 40)))
            hits = [int(l.split("\t")[1]) for l in r.lines if l.startswith("hits")]
            t.check("manickam: standing still under the falling rocks, Kayal is hit again and again",
                    hits and hits[0] >= 3, f"{hits} {r.err[-200:]}")

            # A cave cannot be seen into from outside: a slime inside it is
            # not drawn while Kayal stands in the light.
            cave = ('local up, dr = update, draw\nlocal spot\nfunction update(dt) up(dt)\n'
                    '  local w = require("world")\n'
                    '  if stat("frame") == 150 then\n'
                    '    local cv = w.caves\n'
                    '    for i = 1, #cv, 3 do\n'
                    '      local cx, cy = cv:byte(i, i + 1)\n'
                    '      for d = 1, 6 do for _, o in ipairs({ { 0, -d }, { 0, d }, { -d, 0 } }) do\n'
                    '        local x, y = cx * 8 + 4 + o[1] * 8, cy * 8 + 4 + o[2] * 8\n'
                    '        if not spot and w.flags_at(x, y) & (w.SOLID | w.DARK | w.DEEP | w.HURT) == 0 then\n'
                    '          spot = { cx * 8 + 4, cy * 8 + 4 } w.p.x, w.p.y = x - 4, y - 3\n'
                    '          w.add_slime(spot[1], spot[2]) end end end\n'
                    '    end\n'
                    '  end\n'
                    '  if spot then local w = require("world") w.slimes[#w.slimes].x, w.slimes[#w.slimes].y = spot[1] - 4, spot[2] - 3 end\n'
                    'end\nfunction draw() dr()\n'
                    '  local w = require("world")\n'
                    '  if spot and stat("frame") == 200 then\n'
                    '    local t = {}\n'
                    '    for y = -2, 1 do for x = -2, 1 do t[#t + 1] = pget(spot[1] - w.cam.x + x, spot[2] - w.cam.y + y) end end\n'
                    '    dbg("cave", table.concat(t, ","))\n'
                    '  end\nend\n')
            r = t.run_package(manickam_variant(os.path.join(tmp, "cave"), 4, extra=cave), frames=200,
                              tap="a@100,a@130,a@160,a@190")
            seen_cave = [l.split("\t")[1] for l in r.lines if l.startswith("cave")]
            t.check("manickam: from outside a cave, nothing inside it shows, slimes included",
                    seen_cave and set(seen_cave[0].split(",")) == {"32"}, f"{seen_cave} {r.err[-200:]}")

            # The temple: a beam lamp has to be lit before it shines, and a
            # lamp lit by a beam goes out when the mirror is turned away.
            beam = ('local up = update\nfunction update(dt) up(dt)\n'
                    '  local w = require("world")\n'
                    '  if stat("frame") ~= 150 then return end\n'
                    '  local src, recv\n'
                    '  for _, l in ipairs(w.lamps) do\n'
                    '    if l.cy >= 120 and l.cy < 150 then if l.src then src = l elseif l.beam then recv = l end end\n'
                    '  end\n'
                    '  local function turn() local t, f = map.get(0, 6, 140) map.set(0, 6, 140, t, not f) w.trace() end\n'
                    '  turn() local a = recv.lit\n'
                    '  w.light_lamp(src) local b = recv.lit\n'
                    '  turn() local c = recv.lit\n'
                    '  dbg("beam", a, b, c)\n'
                    'end\n')
            r = t.run_package(manickam_variant(os.path.join(tmp, "beam"), 5, extra=beam), frames=152,
                              tap="a@100,a@130")
            t.check("manickam: a beam shines once its lamp is lit, and a lamp it lit goes out when the beam leaves",
                    "beam\tfalse\ttrue\tfalse" in r.out, r.out[-300:] + r.err[-300:])

            # The Irul fight: each lotus found stops one dark orb.
            fight = ('local up = update\nfunction update(dt) up(dt)\n'
                     '  local w = require("world")\n'
                     '  local f = stat("frame")\n'
                     '  if f == 150 then require("progress").data.lotuses = LOTUSES w.start(5, require("ch5").top) end\n'
                     '  if f == 1950 then dbg("fight", require("ch5").top.shields, w.p.hearts) end\n'
                     'end\n')
            def fight_with(lotuses):
                r = t.run_package(manickam_variant(os.path.join(tmp, f"fight{lotuses}"), 5,
                                                   extra=fight.replace("LOTUSES", str(lotuses))),
                                  frames=1950, tap=",".join(f"a@{f}" for f in range(100, 700, 30)))
                got = [l.split("\t")[1:] for l in r.lines if l.startswith("fight")]
                return (tuple(int(v) for v in got[0]) if got else None), r
            (shield7, hearts7), r7 = fight_with(7)
            (shield0, hearts0), r0 = fight_with(0)
            t.check("manickam: in the Irul fight each lotus stops an orb, and without lotuses the orbs hurt",
                    shield7 < 7 and (hearts7 == 3 or shield7 == 0) and shield0 == 0 and hearts0 < 3,
                    f"{shield7} {hearts7} {shield0} {hearts0} {r7.err[-200:]}")

        # Talk uses nine SDK helpers and keeps none of them in its own
        # folder: packing it supplies them.
        talk_dir = os.path.join(ROOT, "examples", "talk")
        t.check("talk: packing supplies the helpers it requires",
                {"tween.lua", "camera_follow.lua", "inventory.lua", "dialog.lua", "quest.lua", "particles.lua",
                 "input.lua", "anim.lua", "text.lua"}
                <= {name for name, _ in pulli.parse(pulli.build(talk_dir))}
                and not any(f.endswith(".lua") and f not in ("main.lua", "manifest.lua") for f in os.listdir(talk_dir)))
        talk = pulli.build(talk_dir)
        gem_in_bag = lambda fb: any(fb[y * 320 + x] not in (0, 32) for y in range(2, 10) for x in range(110, 118))
        with tempfile.TemporaryDirectory() as saves:
            first = t.run_package(talk, frames=TALK_FRAMES, tap=TALK_TAPS, saves=saves)
            asked = t.run_package(talk, frames=TALK_ASKED, tap=TALK_TAPS)
            flying = t.run_package(talk, frames=TALK_FLYING, tap=TALK_TAPS)
            later = t.run_package(talk, frames=2, saves=saves)
            fresh = t.run_package(talk, frames=2)
            t.check("talk: the villager is asked, answers, and the gem ends up in the bag",
                    first.code == 0 and gem_in_bag(first.fb) and not gem_in_bag(asked.fb) and not gem_in_bag(fresh.fb),
                    first.err)
            t.check("talk: the gem is in the air on its way to the bag, between the villager and the top",
                    sum(1 for v in flying.fb[12 * 320:100 * 320] if v == 10) > 5 and not gem_in_bag(flying.fb))
            t.check("talk: the bag is still full the next time the game is played",
                    later.code == 0 and gem_in_bag(later.fb), later.err)
            box = lambda fb: fb[200 * 320 + 20] == 32                  # the dialog box's black
            replying = t.run_package(talk, frames=465, tap=TALK_NO_TAPS)
            after = t.run_package(talk, frames=520, tap=TALK_NO_TAPS)
            t.check("talk: answering no, the villager replies, and the A that closes the box does not open it again",
                    box(replying.fb) and not box(after.fb) and not gem_in_bag(after.fb), after.err)
            seen["talk given a gem"] = hashlib.sha256(first.fb + first.rgb).hexdigest()
            if not t.update:
                t.check("talk given a gem: draws what it drew before", seen["talk given a gem"] == pinned.get("talk given a gem"),
                        "behaviour changed; if that was intended, rerun with --update")

        pong = pulli.build(os.path.join(ROOT, "examples", "pong"))

        def play(frames, tap=None, **opts):
            r = t.run_package(pong, frames=frames, tap=tap, **opts)
            if r.code != 0:
                t.check(f"pong runs (frames={frames} tap={tap})", False, r.err)
            return r.fb

        levels = {name: play(LEVEL_FRAME, tap) for name, tap in LEVEL_TAPS.items()}
        t.check("pong: each of the four levels plays differently",
                len(set(levels.values())) == len(levels))

        # Pause: START freezes a match, START again lets it run on, and the
        # result is the same match whenever the pause came, including during
        # the screen shake that follows a paddle hit (every frame from 100 to
        # 140 is tried, which covers the console's first return).
        playing = play(400, START)
        t.check("pong: a paused match does not move",
                play(200, f"{START},start@100") == play(300, f"{START},start@100") != play(300, START))
        moments = list(range(60, 100, 8)) + list(range(100, 140)) + list(range(140, 340, 8))
        same = [play(450, f"{START},start@{f},start@{f + 50}") == playing for f in moments]
        t.check(f"pong: resuming carries on from where it stopped, at {len(moments)} different moments",
                all(same), f"{same.count(False)} of {len(same)} pauses changed the match")
        quit_ = play(300, f"{START},start@100,select@150")
        t.check("pong: SELECT while paused leaves the match, and A starts a new one",
                quit_ == play(400, f"{START},start@100,select@150") != play(300, f"{START},start@100")
                and play(300, f"{START},start@100,select@150,a@160") != quit_)
        starts = {play(n + 200, f"a@{n}") for n in range(5, 10)}
        t.check("pong: when A is pressed changes the match that follows", len(starts) > 1)

        # Each level has its own backdrop: above the menu, away from the net,
        # the screen is the level's picture.
        def backdrop_shown(fb, name):
            w, h, pixels = pulli.read_png(open(os.path.join(ROOT, "examples", "pong", name + ".png"), "rb").read())
            index = {c: i for i, c in reversed(list(enumerate(pulli.palette()))) if i}   # (black packs as 32)
            return all(fb[y * 320 + x] == index[pixels[y * w + x][:3]]
                       for y in range(36) for x in range(320) if x not in (159, 160))
        shown = [backdrop_shown(play(5, ",".join(f"right@{1 + 2 * k}" for k in range(n)) or None), name)
                 for n, name in ((3, "bg_easy"), (0, "bg_normal"), (1, "bg_hard"), (2, "bg_insane"))]
        t.check("pong: each level shows its own backdrop", all(shown), shown)

        # Saved between runs: the chosen level, and wins on each level.
        with tempfile.TemporaryDirectory() as saves:
            play(10, "right@1,a@5", saves=saves)
            t.check("pong: the chosen level is remembered", play(3, saves=saves) == play(3, "right@1"))
            r = t.run_game("save('wins3', 12)", manifest=open(os.path.join(ROOT, "examples", "pong",
                           "manifest.lua")).read(), saves=saves)
            t.check("pong: wins are read back for the level shown", r.code == 0
                    and play(3, saves=saves) != play(3, "right@1"))

        # Nizhalattam, step 1: how Komali moves, in the grey test room. Each
        # case places him, then drives him through body.read on exact frames.
        def komali(name, place, read, report, frames=240, pre=""):
            extra = pre + ('require("title").skip = 1\n'          # (straight to slot 1, no title)
                     'local body, shadows, fight, rooms = require("body"), require("shadows"), require("fight"), require("rooms")\n'
                     'local up, i0 = update, {}\n'
                     f'local function at(cx, feet) body.place(cx * 8 + 5, feet) end\n'
                     f'local st = {{}}\n'
                     f'function body.read() local k, f, s = body.k, stat("frame"), shadows.list[1] local i = {{ swap = 0 }}\n{read}\n return i end\n'
                     f'function update(dt) if stat("frame") == 1 then rooms.enter("test.ooru", nil, body) fight.wear({{ "komali", "veeran" }}) {place} end up(dt) local k, f = body.k, stat("frame")\n{report}\nend\n')
            with tempfile.TemporaryDirectory() as tmp:
                folder = os.path.join(tmp, "n")
                shutil.copytree(os.path.join(ROOT, "examples", "nizhalattam"), folder, ignore=NO_MUSIC)
                with open(os.path.join(folder, "main.lua"), "a") as f:
                    f.write("\n" + extra)
                r = t.run_package(pulli.build(folder), frames=frames)
            return r, {l.split("\t")[0]: l.split("\t")[1:] for l in r.lines if "\t" in l}

        r, got = komali("jumps", "at(5, 208)",
                        "if f >= 30 and f <= 70 then i.a = true end if f == 30 or f == 120 then i.a, i.jump = true, true end",
                        'if f == 110 then dbg("held", k.peak) end if f == 200 then dbg("tap", k.peak) end')
        held, tap = float(got.get("held", ["0"])[0]), float(got.get("tap", ["0"])[0])
        t.check("nizhalattam: a held jump rises 4.5 tiles, a tapped one about 1.5",
                r.code == 0 and 34 <= held <= 38 and 10 <= tap <= 14, f"{held} {tap} {r.err[-200:]}")

        tops = {}
        for step, cx, feet in (("4", 20, 176), ("5", 25, 168)):
            r, got = komali("step", f"at({cx}, 208)",
                            "i.right = true if f >= 30 and f <= 80 then i.a = true end if f == 30 then i.jump = true end",
                            f'if k.ground and k.y + k.h == {feet} then st.on = true end if f == 200 then dbg("on", tostring(st.on)) end')
            tops[step] = got.get("on", ["?"])[0]
        t.check("nizhalattam: a held jump clears a step four tiles high, not five",
                tops == {"4": "true", "5": "nil"}, tops)
        t.check("nizhalattam: every room's doors are reached with climbs of three tiles at most, leaving a held jump room to spare",
                *nizhalattam_climbs())

        late = {}
        for n in (4, 8):
            r, got = komali("coyote", "at(12, 192)",
                            f"i.right = true if k.air == {n} and not st.p then st.p = true i.a, i.jump = true, true end",
                            'if st.p and not st.r then st.r = true dbg("jumped", tostring(k.vy < 0)) end')
            late[n] = got.get("jumped", ["?"])[0]
        t.check("nizhalattam: A pressed just after running off a ledge still jumps (6 frames), not later",
                late == {4: "true", 8: "false"}, late)

        early = {}
        for n in (15, 8):
            r, got = komali("buffer", "at(32, 160)",
                            f"if not st.down then i.right = true end if k.air == {n} and not st.p then st.p = true i.a, i.jump = true, true end",
                            'if k.air > 0 then st.down = true end '
                            'if st.down and k.ground and not st.l then st.l = f end '
                            'if st.l and f == st.l + 2 then dbg("bounced", tostring(k.vy < 0 or not k.ground)) end')
            early[n] = got.get("bounced", ["?"])[0]
        t.check("nizhalattam: A pressed just before landing jumps on landing; pressed too early, it does not",
                early == {15: "true", 8: "false"}, early)

        r, got = komali("dodge", "at(3, 208)",
                        "if f == 30 then i.right = true end if f == 31 or f == 52 or f == 82 then i.dodge = true end",
                        'if f == 30 then st.x = k.x end if body.safe() then st.safe = (st.safe or 0) + 1 end '
                        'if f == 49 then dbg("far", k.x - st.x) end if f == 53 then dbg("again", k.dodge) end '
                        'if f == 83 then dbg("later", k.dodge) end if f == 100 then dbg("safe", st.safe) end')
        far = float(got.get("far", ["0"])[0])
        t.check("nizhalattam: a dodge rolls about 57 px ahead, untouchable for 10 frames, and waits half a second",
                r.code == 0 and 50 <= far <= 62 and got.get("safe") == ["20"] and got.get("again") == ["0"]
                and got.get("later", ["0"])[0] != "0", got)

        r, got = komali("pit", "at(49, 208)", "if k.health == 100 then i.right = true end",
                        'if f == 230 then dbg("back", k.health, tostring(k.x < 52 * 8)) end')
        t.check("nizhalattam: falling in a pit costs 10 health and puts him back on the last ledge",
                got.get("back") == ["90", "true"], got)

        r, got = komali("thin", "at(44, 208)",
                        "if f >= 30 and f <= 70 then i.a = true end if f == 30 then i.jump = true end "
                        "if f == 120 then i.down, i.a, i.jump = true, true, true end",
                        'if f == 110 then dbg("up", k.y + k.h, tostring(k.ground)) end '
                        'if f == 200 then dbg("down", k.y + k.h, tostring(k.ground)) end')
        t.check("nizhalattam: he lands on a thin floor from below, and down + A drops him through",
                got.get("up") == ["184", "true"] and got.get("down") == ["208", "true"], got)       # (the stack's first, row 23)

        r, got = komali("wall", "at(70, 150)", "i.left = true",        # (below the pillar's top: down its side)
                        'if k.wall ~= 0 then st.n = (st.n or 0) + 1 st.v = math.max(st.v or 0, k.vy) end '
                        'if f == 200 then dbg("slid", st.n or 0, st.v or 0) end')
        slid = got.get("slid", ["0", "9"])
        t.check("nizhalattam: falling against a wall he holds into, he slides down slowly",
                int(slid[0]) > 20 and float(slid[1]) <= 1.0, slid)

        # Step 2: fighting. The arena's first soldier stands at cell 128.
        # `s` is that soldier; frame 2 sets the scene.
        def scene(setup, read, report, frames=300):
            return komali("fight", "at(124, 208)", read,
                          f"local s = shadows.list[1] if f == 2 then {setup} end\n{report}", frames)

        r, got = scene("",
                       "",
                       'if f == 2 then s.x, s.state, s.face = k.x + 30, "walk", -1 '
                       'dbg("front", shadows.strike(s, 6, 1, false), s.hp) '
                       'dbg("behind", shadows.strike(s, 6, -1, false), s.hp) '
                       's.state = "walk" dbg("heavy", shadows.strike(s, 10, 1, true), s.hp) end', frames=5)
        t.check("nizhalattam: a soldier on guard turns a light blow from the front aside; from behind, or heavy, it lands",
                got.get("front") == ["blocked", "40"] and got.get("behind") == ["hit", "34"]
                and got.get("heavy") == ["hit", "24"], got)

        r, got = scene("", "",
                       'if s.state == "wind" and not st.w then st.w = f end '
                       'if k.health < 100 and not st.h then st.h = f dbg("struck", k.health, f - st.w) end')
        warn = int(got.get("struck", ["0", "0", "0"])[1]) if "struck" in got else 0
        t.check("nizhalattam: the soldier walks up, winds up for 24 frames, then strikes for 12",
                got.get("struck", [""])[0] == "88" and warn == 25, got)

        r, got = scene("", 'if s.state == "wind" and s.t == 2 then i.dodge, i.right = true, true end',
                       'if f == 140 then dbg("health", k.health, tostring(k.x > s.x)) end', frames=150)
        t.check("nizhalattam: a dodge just before the blow lands passes through it",
                got.get("health") == ["100", "true"], got)

        r, got = scene("", 'if f == 2 then i.swap = 1 end',
                       'if k.health < 100 and not st.h then st.h = true dbg("struck", k.health, fight.role().name) end')
        t.check("nizhalattam: wearing the warrior, a blow costs 15% less",
                got.get("struck") == ["90", "Veeran"], got)

        r, got = scene('s.x, s.state, s.face = k.x + 16, "walk", -1', 'if f == 3 then i.swap = 1 end',
                       'if f == 20 then dbg("swap", s.hp, s.state) end', frames=25)
        t.check("nizhalattam: the role coming in strikes, and breaks a guard",
                got.get("swap") == ["22", "reel"], got)

        r, got = scene('s.x, s.state, s.face = k.x + 20, "walk", -1', 'if f == 3 then i.skill = true end',
                       'if f == 6 then dbg("trip", s.state, k.struck > 0) end', frames=8)
        t.check("nizhalattam: Komali's pratfall trips the soldiers close by, and nothing touches him",
                got.get("trip") == ["reel", "true"], got)

        # just out of reach of his first swing, within reach of the heavy slash
        r, got = scene('fight.wear({ "veeran", "komali" }) s.x, s.state, s.t, s.face = k.x + 30, "rest", 400, -1',
                       'if f >= 30 and f <= 85 then i.b = true end if f == 30 then i.attack = true end',
                       'if not s.on and not st.t then st.t = f dbg("torn", f) end '
                       'if f == 299 then dbg("mai", fight.mai) end')
        t.check("nizhalattam: the warrior's slash, B held until it shines, tears a soldier; its ink flies to Komali",
                "torn" in got and int(got.get("mai", ["0"])[0]) >= 1, got)

        r, got = scene('s.x, s.state, s.t, s.face = k.x + 16, "rest", 400, -1', 'i.right = f > 10 if f == 10 then i.attack = true end',
                       'if s.hp < 40 and not st.h then st.h = f st.x = k.x end '
                       'if st.h and f == st.h + 2 then dbg("still", k.x == st.x, fight.freeze > 0) end', frames=40)
        t.check("nizhalattam: when a blow lands the world stands still for a moment",
                got.get("still") == ["true", "true"], got)

        r, got = scene("", 'i.right = f % 200 < 100 i.left = not i.right if f % 23 == 0 then i.attack = true end '
                       'if f % 61 == 0 then i.dodge = true end if f % 300 == 0 then i.swap = 1 end',
                       'if f == 600 then collectgarbage() st.m = stat("mem") end '
                       'if f == 1800 then collectgarbage() dbg("grew", stat("mem") - st.m) end', frames=1800)
        grew = float(got.get("grew", ["99"])[0])
        t.check("nizhalattam: half a minute of fighting makes nothing that stays in memory",
                r.code == 0 and grew < 2, f"{grew} KB {r.err[-200:]}")

        # Step 3: rooms and doors. The test room's door is at cell (163, 22),
        # on the step at its far end; the climb's door back is at (6, 55).
        r, got = komali("door", "at(162, 184)",
                        "if f == 10 or f == 80 then i.door = true end",
                        'if f == 9 then k.health = 70 fight.mai = 4 end '
                        'if f == 60 then dbg("there", rooms.name, math.floor(k.x + k.w / 2), k.y + k.h, k.health, fight.mai) end '
                        'if f == 130 then dbg("back", rooms.name, math.floor((k.x + k.w / 2) / 8)) end', frames=140)
        t.check("nizhalattam: up at a door fades to the room beyond, in at the door back; he keeps his health and mai",
                got.get("there") == ["climb.ooru", "52", "448", "70", "4"] and got.get("back") == ["test.ooru", "163"], got)

        r, got = komali("shut", "at(5, 208)",
                        "if f == 20 or f == 60 or f == 120 then i.door = true end",
                        'if f == 3 then rooms.enter("arena.ooru", "climb.ooru", body) end '
                        'if f == 50 then dbg("shut", rooms.name, tostring(rooms.locked())) '
                        '  for _, s in ipairs(shadows.list) do s.on = false end end '
                        'if f == 100 then dbg("open", rooms.name) end', frames=110)
        t.check("nizhalattam: a fight room's door stays shut until its shadows are torn",
                got.get("shut") == ["arena.ooru", "true"] and got.get("open") == ["climb.ooru"], got)

        # Through every room, by their doors: each map and sheet is read
        # ahead before it is first used, and a frame changes sheets twice.
        ahead = ('local ready, pre, ml, sl = {}, preload, map.load, sheet.load\n'
                 'ready["map.ooru"], ready["sprites.kolam"], ready["test.ooru"] = true, true, true\n'   # (the test enters it itself)
                 'function preload(...) for _, n in ipairs({ ... }) do ready[n] = true end return pre(...) end\n'
                 'function map.load(n) if not ready[n] then dbg("late", n) end return ml(n) end\n'
                 'local loads = 0\n'
                 'function sheet.load(n) loads = loads + 1 if not ready[n] then dbg("late", n) end return sl(n) end\n'
                 'local bd = backdrop function backdrop(n) if n and not ready[n] then dbg("late", n) end return bd(n) end\n'
                 'local d = draw function draw() loads = 0 d() st_loads = loads end\n')
        r, got = komali("ahead", "at(162, 184)",
                        "if f == 10 or f == 60 or f == 110 then i.door = true end",
                        'if f == 45 then body.place(34 * 8 + 4, 64) end '            # the climb's top door
                        'if f == 95 then for _, s in ipairs(shadows.list) do s.on = false end body.place(55 * 8 + 4, 208) end '
                        'if f == 140 then dbg("route", rooms.name, st_loads) end', frames=150, pre=ahead)
        t.check("nizhalattam: every room and sheet is read ahead, behind a door, before it is used",
                r.code == 0 and "late" not in got and got.get("route") == ["test.ooru", "2"], got)

        # Step 4: the first playable. A game starts in the Courtyard; `story`
        # runs it from there, `setup` on frame 1 (entering a room with
        # rooms.enter, say).
        def story(setup, read, report, frames=300, pre="", saves=None, title=False):
            extra = pre + ('' if title else 'require("title").skip = 1\n') + (      # (straight to slot 1, no title)
                           'local body, shadows, fight, rooms = require("body"), require("shadows"), require("fight"), require("rooms")\n'
                           'local run, lines = require("run"), require("lines")\n'
                           'local up, st = update, {}\n'
                           'local function at(cx, feet) body.place(cx * 8 + 5, feet) end\n'
                           f'function body.read() local k, f = body.k, stat("frame") local i = {{ swap = 0 }}\n{read}\n return i end\n'
                           f'function update(dt) local k, f = body.k, stat("frame") if f == 1 then {setup} end up(dt)\n{report}\nend\n')
            with tempfile.TemporaryDirectory() as tmp:
                folder = os.path.join(tmp, "n")
                shutil.copytree(os.path.join(ROOT, "examples", "nizhalattam"), folder, ignore=NO_MUSIC)
                with open(os.path.join(folder, "main.lua"), "a") as f:
                    f.write("\n" + extra)
                r = t.run_package(pulli.build(folder), frames=frames, saves=saves)
            return r, {l.split("\t")[0]: l.split("\t")[1:] for l in r.lines if "\t" in l}

        r, got = story("at(34, 208)", "if f == 10 then i.door = true end",
                       'if f == 2 then dbg("start", rooms.name, #fight.carried) end if f == 60 then dbg("in", rooms.name) end', frames=70)
        t.check("nizhalattam: a game starts in the Courtyard with Komali's own role; its door leads into the Screen",
                got.get("start") == ["map.ooru", "1"] and got.get("in") == ["s1.ooru"], got)

        # striking the dummies: walk up to the nearest, strike it, on to the next
        r, got = story('rooms.enter("s2.ooru", "s1.ooru", body)',
                       'local near for _, s in ipairs(shadows.list) do if s.on and s.x > k.x and (not near or s.x < near.x) then near = s end end '
                       'if near and near.x - k.x > 12 then i.right = true elseif near and f % 14 == 0 then i.attack = true end',
                       'if f == 3 then dbg("shut", tostring(rooms.locked())) end '
                       'if f == 900 then dbg("open", tostring(rooms.locked()), fight.mai > 0) end', frames=910)
        t.check("nizhalattam: the striking lesson's door stays shut until its three dummies are torn, and they leave mai",
                got.get("shut") == ["true"] and got.get("open") == ["false", "true"], got)

        r, got = story('rooms.enter("s3.ooru", "s2.ooru", body)', "if shadows.list[1].x - k.x > 24 then i.right = true end",
                       'if k.health < 100 and not st.h then st.h = true dbg("soft", k.health) end', frames=400)
        t.check("nizhalattam: in the dodging lesson the soldier's blow is soft: 4, not 12",
                got.get("soft") == ["96"], f"{got} {r.err[-300:]}")

        r, got = story('rooms.enter("s4.ooru", "s3.ooru", body)', "",
                       'if f == 3 then for _, s in ipairs(shadows.list) do if s.kind == "ink" then st.ink = s end end '
                       '  dbg("struck", shadows.strike(st.ink, 10, 1, false)) local n = 0 '
                       '  for _, s in ipairs(shadows.list) do if s.on and s.kind == "small" then n = n + 1 end end dbg("small", n) '
                       '  for _, s in ipairs(shadows.list) do if s.kind == "small" and s.on then dbg("again", shadows.strike(s, 10, 1, false)) break end end '
                       '  n = 0 for _, s in ipairs(shadows.list) do if s.on and s.kind == "small" then n = n + 1 end end dbg("left", n) end', frames=5)
        t.check("nizhalattam: an inkblot struck down splits into two small ones, which do not split again",
                got.get("struck") == ["torn"] and got.get("small") == ["2"] and got.get("again") == ["torn"] and got.get("left") == ["1"], got)

        r, got = story('rooms.enter("s5.ooru", "s4.ooru", body)',
                       'if f == 2 then for _, s in ipairs(shadows.list) do if s.kind == "scrap" then k.x = s.x break end end end',
                       'if f == 2 then for _, s in ipairs(shadows.list) do if s.kind == "scrap" then st.s = s break end end end '
                       'if st.s and st.s.state == "dive" then st.d = true end '
                       'if f == 200 then dbg("swoop", tostring(st.d), tostring(k.health < 100)) end', frames=210)
        t.check("nizhalattam: a scrap hanging over Komali swoops at him, and it hurts",
                got.get("swoop") == ["true", "true"], f"{got} {r.err[-300:]}")

        r, got = story('rooms.enter("s6.ooru", "s5.ooru", body) at(20, 208) fight.mai, k.health = 400, 60',
                       'if f == 10 then i.door = true end if f == 15 or f == 25 or f == 35 or f == 45 then i.jump = true end '
                       'if f == 20 or f == 30 or f == 40 then i.down_p = true end if f == 50 then i.attack = true end',
                       'if f == 60 then dbg("bought", k.health, fight.mai, table.concat(run.charms, ","), tostring(run.sharp.Komali), tostring(rooms.shop.is_open())) '
                       '  local it = rooms.shop.ITEMS dbg("stock", #it, it[3].key .. "," .. it[4].key, it[3].price + it[4].price) end', frames=70)
        stock = got.get("stock", ["0", "", "0"])
        t.check("nizhalattam: at the stall mai buys mending, a sharper role, and charms; B leaves",
                stock[0] == "4" and got.get("bought") == ["85", str(400 - 30 - 80 - int(stock[2])), stock[1], "true", "false"], got)

        # the later repairs: the wall jump, a second dodge, more mending, a
        # third charm, a stall stocking one more; and the charms they open
        def wall(on):
            r, got = komali("wall", f'body.k.walljump = {on} body.place(68 * 8 + 5, 120)',
                            "i.left = f < 21 if f == 20 then i.jump, i.a = true, true end if f > 20 and f < 40 then i.a = true end",
                            'if f == 19 then dbg("sliding", k.wall) end if f == 22 then dbg("off", k.vy < 0 and "up" or "down", k.vx > 0 and "away" or "-") end', frames=24)
            return got.get("sliding"), got.get("off")
        def dodges(on):
            r, got = komali("dodge", f'body.k.second, body.k.spare = {on}, {on} at(20, 208)',
                            "if f == 10 or f == 33 then i.dodge = true end",
                            'if f == 34 then dbg("again", tostring(k.dodge > 0)) end', frames=36)
            return got.get("again")
        t.check("nizhalattam: the wall jump (a repair) springs up and away from a wall he slides down; a second dodge follows the first",
                wall("true") == (["-1"], ["up", "away"]) and wall("false") == (["-1"], ["down", "-"])
                and dodges("true") == ["true"] and dodges("false") == ["false"], (wall("true"), wall("false")))
        r, got = story('run.data.repairs.r_stock, run.data.repairs.r_charm3, run.data.repairs.r_mend = 1, 1, 1 '
                       'rooms.enter("s6.ooru", "s5.ooru", body) at(20, 208) fight.mai, k.health = 900, 40 run.charms[1], run.charms[2] = "x", "y"',
                       'if f == 10 then i.door = true end if f == 15 then i.jump = true end '
                       'if f == 20 or f == 22 then i.down_p = true end if f == 25 then i.jump = true end',
                       'if f == 30 then dbg("stall", #rooms.shop.ITEMS, k.health, #run.charms) end', frames=32)
        t.check("nizhalattam: with the repairs, stalls stock three charms, mend 35, and a third charm can be carried",
                got.get("stall") == ["5", "75", "3"], f"{got} {r.err[-300:]}")
        dummies = ('local d = {} for _, s in ipairs(shadows.list) do if s.kind == "dummy" then d[#d + 1] = s end end ')
        r, got = story('rooms.enter("s2.ooru", "s1.ooru", body) run.charms[1] = "torn" ' + dummies + 'st.d = d at(16, 208) k.face = 1',
                       "if f == 10 or f == 40 then i.attack = true end",
                       'if f == 30 then dbg("first", st.d[1].hp) end if f == 60 then dbg("then", st.d[1].hp) end', frames=62)
        r2, got2 = story('rooms.enter("s2.ooru", "s1.ooru", body) run.charms[1] = "soot" ' + dummies +
                         'd[1].hp = 1 d[2].x = d[1].x + 14 st.d = d at(16, 208) k.face = 1',
                         "if f == 10 then i.attack = true end",
                         'if f == 30 then dbg("burnt", tostring(st.d[1].on), st.d[2].hp) end', frames=32)
        r3, got3 = story('run.charms[1] = "drum" fight.hit(false) dbg("drum", fight.freeze, fight.cost(10, fight.role()))', "", "", frames=3)
        t.check("nizhalattam: the torn page doubles a room's first blow; lamp soot burns a torn shadow's neighbours; the drum skin hits longer and harder",
                got.get("first") == ["6"] and int(got.get("then", ["9"])[0]) <= 0
                and got2.get("burnt") == ["false", "12"] and got3.get("drum") == ["5", "12"],
                f"{got} {got2} {got3} {r.err[-200:]} {r2.err[-200:]} {r3.err[-200:]}")

        r, got = story('rooms.enter("s6.ooru", "s5.ooru", body) at(20, 208) fight.mai, k.health = 10, 60',
                       'if f == 10 then i.door = true end if f == 15 then i.jump = true end',
                       'if f == 30 then dbg("poor", k.health, fight.mai) end', frames=40)
        t.check("nizhalattam: without the mai, nothing is bought",
                got.get("poor") == ["60", "10"], got)

        # the Screen's shadows before its stall leave, at the least, enough
        # for the stall's cheapest good: the first stall is never out of reach
        import xml.etree.ElementTree as ET
        nz = os.path.join(ROOT, "examples", "nizhalattam")
        src = open(os.path.join(nz, "shadows.lua")).read()
        least = {"soldier": int(re.search(r"mai = \{ (\d+), \d+ \},\s+-- drops of ink he leaves", src).group(1))}
        for kind in ("dummy", "ink", "scrap"):
            least[kind] = int(re.search(kind + r" = \{[^}]*mai = \{ (\d+),", src).group(1))
        earned = 0
        for n in range(1, 6):
            root = ET.parse(os.path.join(nz, f"s{n}.tmx")).getroot()
            earned += sum(least.get(o.get("class"), 0) for o in root.iter("object"))
        prices = [int(p) for p in re.findall(r"price = (\d+)", open(os.path.join(nz, "stall.lua")).read())]
        t.check("nizhalattam: the Screen's shadows leave enough mai for something at its stall",
                earned >= min(prices), f"{earned} {min(prices)}")

        r, got = story('rooms.enter("s7.ooru", "s6.ooru", body) run.charms[1] = "spool" at(18, 208) '
                       'for _, s in ipairs(shadows.list) do s.on = false end',
                       "if f < 60 then i.right = true end",
                       'if k.y > 230 then st.fell = true end if f == 200 then dbg("spool", tostring(st.fell), k.health) end', frames=210)
        t.check("nizhalattam: with the thread spool, a fall into a pit costs nothing",
                got.get("spool") == ["true", "100"], f"{got} {r.err[-300:]}")

        # the boss: each move's first wind-up is twice as long as later ones
        r, got = story('rooms.enter("boss.ooru", "s7.ooru", body)', "",
                       'k.health = 100 local b = shadows.boss '
                       'if b.state == "wind" and not st.w then st.w = true st.seen = st.seen or {} '
                       '  local m = b.move st.seen[m] = (st.seen[m] or 0) + 1 dbg(m .. st.seen[m], b.t) '
                       'elseif b.state ~= "wind" then st.w = false end', frames=1500)
        firsts = {k[:-1]: int(v[0]) for k, v in got.items() if k.endswith("1")}
        seconds = {k[:-1]: int(v[0]) for k, v in got.items() if k.endswith("2")}
        shown = [m for m in seconds if m in firsts and firsts[m] == 2 * seconds[m]]
        wind = {"combo": 20, "heavy": 45, "bash": 16}       # veeran.lua's B.wind
        t.check("nizhalattam: Veeran shows each move first, with a wind-up twice as long",
                r.code == 0 and len(firsts) >= 2 and all(v == 2 * wind[m] for m, v in firsts.items())
                and len(shown) >= 1 and all(seconds[m] == wind[m] for m in seconds), got)

        # his walk is drawn a whole frame at a time (48 px: 6 cells apart),
        # never half of one and half of the next
        r, got = story('rooms.enter("boss.ooru", "s7.ooru", body) local o = spr nz_bad, nz_walk = 0, 0 '
                       'spr = function(n, ...) if n >= 1024 and n < 1084 then '
                       '  if (n - 1024) % 6 ~= 0 then nz_bad = nz_bad + 1 elseif n > 1024 and n < 1054 then nz_walk = nz_walk + 1 end end '
                       '  return o(n, ...) end', "",
                       'k.health = 100 if f == 600 then dbg("walk", nz_walk > 0, nz_bad) end', frames=610)
        t.check("nizhalattam: Veeran's walk is drawn in whole frames",
                got.get("walk") == ["true", "0"], f"{got} {r.err[-300:]}")

        # (a run of two stories: the halfway tear comes after the first)
        r, got = story('run.start(body, { "forest" }) rooms.enter("boss.ooru", "s7.ooru", body)',
                       "if f == 140 or f == 240 then i.door = true end",
                       'if f == 3 then st.oil = run.data.oil local b = shadows.boss b.hp = 1 shadows.strike(b, 5, -1, true) end '
                       'if f == 10 then dbg("lent", #fight.carried, fight.carried[2] and fight.carried[2].name, run.data.oil - st.oil) '
                       '  at(54, 208) end '
                       'if f == 200 then dbg("tear", rooms.name) at(34, 208) end '
                       'if f == 300 then dbg("on", rooms.name, #fight.carried, palette(25)) end', frames=310)
        t.check("nizhalattam: Veeran torn lends his role and 8 oil; on through the halfway tear into the Painted Forest, in its colours",
                got.get("lent") == ["2", "Veeran", "8"] and got.get("tear") == ["tear.ooru"]
                and got.get("on", [""])[:2] == ["f1.ooru", "2"] and got.get("on", ["", "", "x"])[2] != "255", got)

        # Step 5: the Painted Forest. Its own shadows, in its rooms only.
        r, got = story('rooms.enter("f2.ooru", "f1.ooru", body)', "",
                       'if f == 3 then dbg("forest", tostring(shadows.kinds.vine ~= nil), tostring(shadows.kinds.wisp ~= nil)) '
                       '  rooms.enter("f4.ooru", "f3.ooru", body) dbg("stall", tostring(shadows.kinds.vine ~= nil), tostring(rooms.shop ~= nil)) '
                       '  rooms.enter("map.ooru", nil, body) dbg("hub", tostring(shadows.kinds.vine ~= nil)) end', frames=5)
        t.check("nizhalattam: the forest's shadows' code is there in its rooms only",
                got.get("forest") == ["true", "true"] and got.get("stall") == ["false", "true"] and got.get("hub") == ["false"], got)

        # the vine-hand: under the leaves no blow reaches it; walked up to,
        # it rises, grabs (6) and holds him; A shakes him free sooner
        vines = ('if f == 2 then for _, s in ipairs(shadows.list) do if s.kind ~= "vine" then s.on = false elseif not st.v then st.v = s end end '
                 '  dbg("hidden", tostring(shadows.strike(st.v, 10, 1, false)), st.v.hp) end ')
        held = {}
        for shake in (False, True):
            r, got = story('rooms.enter("f2.ooru", "f1.ooru", body) at(12, 208)',
                           'i.right = not st.c and f > 5 ' + ('if st.c and f % 2 == 0 then i.jump = true end' if shake else ''),
                           vines + 'if k.held > 0 and not st.c then st.c = f dbg("caught", k.health, st.v.state) end '
                           'if st.c and k.held == 0 and not st.free then st.free = f - st.c end '
                           'if f == 200 then dbg("held", st.free or -1) end', frames=210)
            held[shake] = int(got.get("held", ["-1"])[0])
        t.check("nizhalattam: a vine-hand hidden takes no blow; walked up to it grabs (6) and holds; A shakes free sooner",
                got.get("hidden") == ["nil", "16"] and got.get("caught") == ["94", "hold"]
                and 38 <= held[False] <= 44 and 0 < held[True] < 14, (got, held))

        r, got = story('rooms.enter("f3.ooru", "f2.ooru", body) at(30, 448)', "",
                       'if f == 2 then for _, s in ipairs(shadows.list) do s.on = s.kind == "wisp" and not st.w if s.on then st.w = s end end '
                       '  st.w.x, st.w.y = 4, 420 st.x = st.w.x end k.health = 100 '
                       'if f == 40 then dbg("through", st.w.x - st.x > 8) st.w.t = 1 end '
                       'if f == 42 then dbg("gone", st.w.state, tostring(shadows.strike(st.w, 5, 1, false))) end', frames=45)
        t.check("nizhalattam: a banyan wisp drifts at Komali through walls; faded, no blow reaches it",
                got.get("through") == ["true"] and got.get("gone") == ["gone", "nil"], got)

        r, got = story('rooms.enter("f1.ooru", nil, body) at(26, 208)', "",
                       'if f == 2 then for _, s in ipairs(shadows.list) do if s.kind == "moth" and (not st.m or math.abs(s.x - k.x) < math.abs(st.m.x - k.x)) then st.m = s end end '
                       '  for _, s in ipairs(shadows.list) do s.on = s == st.m end end '
                       'local d = st.m and math.abs(st.m.x - k.x) + math.abs(st.m.y - k.y) if f == 2 then st.d = d end '
                       'if d and k.health < 100 and not st.h then st.h = true dbg("touched", k.health, tostring(d < st.d)) end', frames=400)
        t.check("nizhalattam: a leaf-moth flutters at Komali, and touching it hurts (4)",
                got.get("touched") == ["96", "true"], got)

        # Vil: each move shown first; his arrows hurt; close in and he leaps away
        r, got = story('rooms.enter("fboss.ooru", "f6.ooru", body) at(8, 208)', "",
                       'local b = shadows.boss if k.health < 100 and not st.h then st.h = true dbg("arrow", k.health) end k.health = 100 '
                       'if b.state == "wind" and not st.w then st.w = true st.seen = st.seen or {} '
                       '  local m = b.move st.seen[m] = (st.seen[m] or 0) + 1 dbg(m .. st.seen[m], b.t) '
                       'elseif b.state ~= "wind" then st.w = false end', frames=1500)
        firsts = {k[:-1]: int(v[0]) for k, v in got.items() if k.endswith("1")}
        seconds = {k[:-1]: int(v[0]) for k, v in got.items() if k.endswith("2")}
        wind = {"shot": 24, "volley": 30, "leap": 10}      # vil.lua's B.wind
        t.check("nizhalattam: Vil shows each move first, with a warning twice as long; his arrow costs 10",
                r.code == 0 and {"shot", "volley"} <= set(firsts) and all(v == 2 * wind[m] for m, v in firsts.items())
                and len(seconds) >= 1 and all(seconds[m] == wind[m] for m in seconds) and got.get("arrow") == ["90"],
                f"{got} {r.err[-300:]}")

        r, got = story('rooms.enter("fboss.ooru", "f6.ooru", body)', "",
                       'local b = shadows.boss if f == 2 then at(math.floor(b.x / 8) - 3, 208) st.x = b.x end k.health = 100 '
                       'if b.state == "leap" then st.l = true end '
                       'if f == 120 then dbg("leapt", tostring(st.l), math.abs(b.x - st.x) > 40) end', frames=125)
        t.check("nizhalattam: come close and Vil leaps away",
                got.get("leapt") == ["true", "true"], got)

        r, got = story('run.start(body, { "forest" }) rooms.enter("fboss.ooru", "f6.ooru", body)', "if f == 140 then i.door = true end",
                       'if f == 3 then st.oil, st.p = run.data.oil, run.data.played local b = shadows.boss b.hp = 1 '
                       '  shadows.strike(b, 5, -1, true) end '
                       'if f == 10 then dbg("lent", #fight.carried, fight.carried[2] and fight.carried[2].name, run.data.oil - st.oil) '
                       '  at(58, 208) end '
                       'if f == 380 then dbg("home", rooms.name, run.data.played - st.p, #fight.carried, fight.mai, '
                       '  tostring(rawget(fight.ROLES, "vil") ~= nil)) end', frames=390)
        t.check("nizhalattam: Vil torn lends his role and 9 oil; the door on ends the run, back in the Courtyard; his role let go",
                got.get("lent") == ["2", "Vil", "9"] and got.get("home") == ["map.ooru", "1", "1", "0", "false"], got)

        # Step 5c: the Leather Sea. Its own shadows and boats, in its rooms only.
        r, got = story('rooms.enter("k2.ooru", "k1.ooru", body)', "",
                       'if f == 3 then dbg("sea", tostring(shadows.kinds.crab ~= nil), tostring(shadows.kinds.boat ~= nil)) '
                       '  for _, s in ipairs(shadows.list) do s.on = false end shadows.add(30 * 8 + 4, 208, "boat") '
                       '  dbg("open", tostring(rooms.locked()), #body.floors) '
                       '  rooms.enter("k4.ooru", "k3.ooru", body) dbg("stall", tostring(shadows.kinds.crab ~= nil), tostring(rooms.shop ~= nil), #body.floors) '
                       '  rooms.enter("kboss.ooru", "k6.ooru", body) dbg("deck", tostring(shadows.kinds.crab ~= nil), tostring(shadows.kinds.aattakkaari ~= nil)) '
                       '  rooms.enter("map.ooru", nil, body) dbg("hub", tostring(shadows.kinds.crab ~= nil), tostring(shadows.kinds.aattakkaari ~= nil)) end', frames=5)
        t.check("nizhalattam: the sea's shadows' code is there in its rooms only; a fight room's door does not wait for a boat",
                got.get("sea") == ["true", "true"] and got.get("open") == ["false", "1"] and got.get("stall") == ["false", "true", "0"]
                and got.get("deck") == ["false", "true"] and got.get("hub") == ["false", "false"], f"{got} {r.err[-300:]}")

        # the crab-shield: its claw turns a light blow from the front; from behind
        # it lands. Close, it draws back (22 frames), then lunges (10).
        r, got = story('rooms.enter("k2.ooru", "k1.ooru", body) at(52, 208)', "",
                       'if f == 2 then for _, s in ipairs(shadows.list) do if s.kind == "crab" and s.x > 300 and not st.c then st.c = s end end '
                       '  for _, s in ipairs(shadows.list) do s.on = s == st.c end st.c.face = 1 '
                       '  dbg("front", shadows.strike(st.c, 8, -1, false), st.c.hp) dbg("back", shadows.strike(st.c, 8, 1, false), st.c.hp) '
                       '  st.c.state, st.c.t = "walk", 0 end '
                       'if f > 2 and st.c.state == "wind" and not st.w then st.w = st.c.t end '
                       'if k.health < 100 and not st.h then st.h = true dbg("lunge", k.health, st.c.state, st.w) end', frames=200)
        t.check("nizhalattam: a crab-shield turns a light blow from the front, not from behind; close, it draws back (22), then lunges (10)",
                got.get("front") == ["blocked", "24"] and got.get("back") == ["hit", "16"] and got.get("lunge") == ["90", "lunge", "22"],
                f"{got} {r.err[-300:]}")

        # the wave-cutter rides across, through Komali; riding, a light blow is
        # turned aside; its wave sunk at the far end, it lands
        r, got = story('rooms.enter("k5.ooru", "k4.ooru", body) at(30, 208)', "",
                       'if f == 2 then for _, s in ipairs(shadows.list) do if s.kind == "wave" and not st.w then st.w = s end end '
                       '  for _, s in ipairs(shadows.list) do s.on = s == st.w end end '
                       'local w = st.w if w and w.state == "ride" and not st.r then st.r = true dbg("ride", shadows.strike(w, 8, 1, false), w.hp) end '
                       'if k.health < 100 and not st.h then st.h = true dbg("rode", k.health) end '
                       'if w and st.r and w.state == "rest" and not st.e then st.e = true dbg("sank", tostring(w.x > k.x), shadows.strike(w, 8, 1, false), w.hp) end',
                       frames=300)
        t.check("nizhalattam: a wave-cutter rides through Komali (10); riding, a light blow is turned aside; its wave sunk, it lands",
                got.get("ride") == ["blocked", "20"] and got.get("rode") == ["90"] and got.get("sank") == ["true", "hit", "12"],
                f"{got} {r.err[-300:]}")

        # the gull cries out, hovering (20 frames), then dives (8)
        r, got = story('rooms.enter("k5.ooru", "k4.ooru", body) at(74, 208)', "",
                       'if f == 2 then for _, s in ipairs(shadows.list) do if s.kind == "gull" and (not st.g or s.x < st.g.x) then st.g = s end end '
                       '  for _, s in ipairs(shadows.list) do s.on = s == st.g end end '
                       'if f == 5 then at(math.floor(st.g.x / 8), 208) end '
                       'if st.g and st.g.state == "wind" and not st.w then st.w = true dbg("cry", st.g.t) end '
                       'if k.health < 100 and not st.h then st.h = true dbg("dove", k.health, st.g.state) end', frames=200)
        t.check("nizhalattam: a gull cries out, hovering, before it dives at Komali (8)",
                got.get("cry") == ["20"] and got.get("dove") == ["92", "dive"], f"{got} {r.err[-300:]}")

        # boats: a ferry carries Komali across; a boat bobs him up and down; down +
        # A drops him through, into the sea
        r, got = story('rooms.enter("k3.ooru", "k2.ooru", body)', "",
                       'if f == 2 then for _, s in ipairs(shadows.list) do if s.kind == "ferry" and not st.b then st.b = s end end '
                       '  body.place(st.b.x + st.b.w / 2, st.b.y) st.x, st.bx = k.x, st.b.x end '
                       'if f == 90 then dbg("carried", tostring(k.on == st.b), math.floor(k.x - st.x + 0.5), math.floor(st.b.x - st.bx + 0.5), k.health) end',
                       frames=95)
        r2, got2 = story('rooms.enter("k1.ooru", nil, body)', "if f == 160 then i.down, i.jump = true, true end",
                         'if f == 2 then for _, s in ipairs(shadows.list) do if s.kind == "boat" then st.b = s else s.on = false end end '
                         '  body.place(st.b.x + 20, st.b.y) st.lo, st.hi = 999, -999 end '
                         'if f > 5 and f < 150 then st.lo, st.hi = math.min(st.lo, k.y), math.max(st.hi, k.y) end '
                         'if f == 150 then dbg("bob", tostring(k.on == st.b), tostring(st.hi - st.lo > 3)) end '
                         'if k.y > 230 then st.fell = true end if f == 220 then dbg("dropped", tostring(st.fell), k.health) end', frames=225)
        c = got.get("carried", ["", "0", "1", ""])
        t.check("nizhalattam: a ferry carries Komali along; a boat bobs him up and down; down + A drops him into the sea",
                c[0] == "true" and int(c[1]) == int(c[2]) and abs(int(c[1])) > 20 and c[3] == "100"
                and got2.get("bob") == ["true", "true"] and got2.get("dropped") == ["true", "90"], f"{got} {got2} {r.err[-300:]} {r2.err[-300:]}")

        # Aattakkaari: each move shown first; her kicks hurt (12)
        r, got = story('rooms.enter("kboss.ooru", "k6.ooru", body) at(8, 208)', "",
                       'local b = shadows.boss if k.health < 100 and not st.h then st.h = true dbg("kick", k.health, b.state) end k.health = 100 '
                       'if b.state == "wind" and not st.w then st.w = true st.seen = st.seen or {} '
                       '  local m = b.move st.seen[m] = (st.seen[m] or 0) + 1 dbg(m .. st.seen[m], b.t) '
                       'elseif b.state ~= "wind" then st.w = false end', frames=1500)
        firsts = {k[:-1]: int(v[0]) for k, v in got.items() if k.endswith("1")}
        seconds = {k[:-1]: int(v[0]) for k, v in got.items() if k.endswith("2")}
        wind = {"kicks": 26, "dash": 30, "whirl": 14}      # aattakkaari.lua's B.wind
        t.check("nizhalattam: Aattakkaari shows each move first, with a warning twice as long; her kicks cost 12",
                r.code == 0 and set(wind) <= set(firsts) and all(v == 2 * wind[m] for m, v in firsts.items())
                and len(seconds) >= 2 and all(seconds[m] == wind[m] for m in seconds) and got.get("kick") == ["88", "kicks"],
                f"{got} {r.err[-300:]}")

        r, got = story('rooms.enter("kboss.ooru", "k6.ooru", body) at(20, 208)', "",
                       'local b = shadows.boss if f == 2 then b.shown.dash, b.move, b.state, b.t, b.face = true, "dash", "wind", 1, -1 end '
                       'if k.health < 100 and not st.h then st.h = true dbg("stunned", k.health, k.held) end '
                       'if f == 60 then at(math.floor((b.x + b.w / 2) / 8) - 2, 208) b.state, b.t, b.move = "walk", 0, nil b.think = 99 end '
                       'if f > 60 and b.state == "wind" and not st.w then st.w = true dbg("close", b.move) end', frames=90)
        t.check("nizhalattam: Aattakkaari's dash stuns Komali (14, held 40); come close and she whirls",
                got.get("stunned") == ["86", "40"] and got.get("close") == ["whirl"], f"{got} {r.err[-300:]}")

        r, got = story('run.start(body, { "sea" }) rooms.enter("kboss.ooru", "k6.ooru", body)', "",
                       'if f == 3 then st.oil = run.data.oil local b = shadows.boss b.hp = 1 shadows.strike(b, 5, -1, true) end '
                       'if f == 10 then dbg("lent", #fight.carried, fight.carried[2] and fight.carried[2].name, run.data.oil - st.oil) end', frames=12)
        t.check("nizhalattam: Aattakkaari torn lends her role and 10 oil",
                got.get("lent") == ["2", "Aattakkaari", "10"], f"{got} {r.err[-300:]}")

        # The dancer's role, among the striking lesson's dummies (cells 18, 26, 34)
        def dancer(read, report, frames=120, wear='"aattakkaari"', room="s2.ooru", cell=14):
            return story(f'rooms.enter("{room}", "s1.ooru", body) fight.wear({{ {wear} }}) at({cell}, 208)', read,
                         'local d1, d2 = shadows.list[1], shadows.list[2] ' + report, frames)

        r, got = dancer("if f == 10 or f == 20 or f == 30 then i.attack = true end",
                        'if f == 9 then st.x = k.x end if f == 70 then dbg("kicks", tostring(d1.on), math.floor(k.x - st.x)) end')
        t.check("nizhalattam: as Aattakkaari, B kicks three times, each carrying Komali on; the three tear a dummy",
                got.get("kicks", ["", "0"])[0] == "false" and int(got.get("kicks", ["", "0"])[1]) >= 24, f"{got} {r.err[-300:]}")

        r, got = dancer("if f == 10 then i.skill = true end",
                        'if f == 9 then st.x = k.x end if f == 12 then dbg("safe", tostring(body.safe())) end '
                        'if f == 40 then dbg("dash", d1.hp, tostring(k.x > d1.x + d1.w), math.floor(k.x - st.x)) end')
        r2, got2 = dancer("if f == 10 then i.skill = true end",
                          'if f == 2 then for _, s in ipairs(shadows.list) do if s.kind == "soldier" then st.s = s else s.on = false end end '
                          '  st.s.x = k.x + 40 end '
                          'if f == 30 then dbg("stun", st.s.state, tostring(st.s.t > 60)) end', room="s3.ooru", cell=8)
        t.check("nizhalattam: as Aattakkaari, X dashes through a shadow, striking (6) and stunning it; nothing touches Komali",
                got.get("safe") == ["true"] and got.get("dash", [""])[0] == "12" and got.get("dash", ["", ""])[1] == "true"
                and got2.get("stun") == ["reel", "true"], f"{got} {got2} {r.err[-300:]} {r2.err[-300:]}")

        r, got = dancer("if f == 10 then i.dodge = true end", 'if f == 2 then d1.x = k.x + 16 end if f == 40 then dbg("ring", d1.hp) end')
        r2, got2 = dancer("if f == 10 then i.swap = 1 end",
                          'if f == 2 then d1.x, d2.x = k.x - 18, k.x + 18 end if f == 40 then dbg("whirl", d1.hp, d2.hp, fight.role().name) end',
                          wear='"komali", "aattakkaari"')
        t.check("nizhalattam: as Aattakkaari, a dodge leaves a ring that strikes; coming in, she whirls, striking both sides",
                got.get("ring") == ["12"] and got2.get("whirl") == ["8", "8", "Aattakkaari"], f"{got} {got2} {r.err[-300:]} {r2.err[-300:]}")

        # Step 5d: the Battlefield of Flags. Its own shadows, in its rooms only.
        r, got = story('rooms.enter("b2.ooru", "b1.ooru", body)', "",
                       'if f == 3 then dbg("field", tostring(shadows.kinds.archer ~= nil), tostring(shadows.kinds.drum ~= nil)) '
                       '  rooms.enter("b4.ooru", "b3.ooru", body) dbg("stall", tostring(shadows.kinds.flag ~= nil), tostring(rooms.shop ~= nil)) '
                       '  rooms.enter("bboss.ooru", "b6.ooru", body) dbg("boss", tostring(shadows.kinds.flag ~= nil), tostring(shadows.kinds.yaanai ~= nil)) '
                       '  rooms.enter("map.ooru", nil, body) dbg("hub", tostring(shadows.kinds.flag ~= nil), tostring(shadows.kinds.yaanai ~= nil)) end', frames=5)
        t.check("nizhalattam: the battlefield's shadows' code is there in its rooms only",
                got.get("field") == ["true", "true"] and got.get("stall") == ["false", "true"]
                and got.get("boss") == ["false", "true"] and got.get("hub") == ["false", "false"], f"{got} {r.err[-300:]}")

        # the flag-bearer rallies the shadows near it: they take half a blow
        r, got = story('rooms.enter("b2.ooru", "b1.ooru", body) at(4, 208)', "",
                       'if f == 3 then for _, s in ipairs(shadows.list) do if s.kind == "flag" then st.fl = s elseif s.kind == "soldier" and not st.so then st.so = s end end '
                       '  for _, s in ipairs(shadows.list) do s.on = s == st.fl or s == st.so end '
                       '  st.so.x, st.so.y = st.fl.x - 24, st.fl.y '
                       '  dbg("rallied", shadows.strike(st.so, 10, 1, true), st.so.hp) '
                       '  st.fl.hp = 1 dbg("flag", shadows.strike(st.fl, 5, 1, true)) '
                       '  dbg("alone", shadows.strike(st.so, 10, 1, true), st.so.hp) end', frames=5)
        t.check("nizhalattam: a shadow near a flag-bearer takes half a blow (5 of 10); the flag torn, the whole",
                got.get("rallied") == ["hit", "35"] and got.get("flag") == ["torn"] and got.get("alone") == ["hit", "25"],
                f"{got} {r.err[-300:]}")

        # the archer line draws together and looses together; one struck while
        # drawing misses the volley
        volleys = {}
        for strike in (False, True):
            r, got = story('rooms.enter("b5.ooru", "b4.ooru", body) at(40, 208)', "",
                           'if f == 2 then for _, s in ipairs(shadows.list) do s.on = s.kind == "archer" end end '
                           'if f == 135 then local n = 0 for _, s in ipairs(shadows.list) do if s.on and s.state == "wind" then n = n + 1 st.a = s end end dbg("drawing", n) '
                           + ('  shadows.strike(st.a, 2, 1, false) ' if strike else '') + 'end '
                           'if f == 150 then dbg("loosed", fight.shots.count()) end '
                           'if f == 260 then dbg("hurt", k.health) end', frames=265)
            volleys[strike] = (got.get("drawing"), got.get("loosed"), got.get("hurt"))
        t.check("nizhalattam: an archer line draws together, then looses together (8); one struck while drawing misses",
                volleys[False] == (["3"], ["3"], ["92"]) and volleys[True] == (["3"], ["2"], ["92"]), f"{volleys} {r.err[-300:]}")

        # the war drum's shockwave reaches feet on the ground, not on a plank
        drums = {}
        for where, feet in (("ground", "at(40, 208)"), ("plank", "at(42, 176)")):
            r, got = story(f'rooms.enter("b3.ooru", "b2.ooru", body) {feet}', "",
                           'if f == 2 then for _, s in ipairs(shadows.list) do s.on = s.kind == "drum" and s.x < 400 end end '
                           'if f == 200 then dbg("drum", k.health) end', frames=205)
            drums[where] = got.get("drum")
        t.check("nizhalattam: the war drum's beat sends a shockwave along the ground (10); on a plank it passes under",
                drums == {"ground": ["90"], "plank": ["100"]}, f"{drums} {r.err[-300:]}")

        # the Elephant: each move shown first; his charge hurts (16) and ends at a
        # wall, where he stands dizzy; his pound's shockwave hurts (12) on the ground
        r, got = story('rooms.enter("bboss.ooru", "b6.ooru", body) at(8, 208)', "",
                       'local b = shadows.boss if k.health < 100 and not st.h then st.h = true dbg("charged", k.health, b.state) end k.health = 100 '
                       'if b.state == "rest" and b.move == "charge" and not st.d then st.d = true dbg("dizzy", tostring(b.x < 40 or b.x + b.w > rooms.w - 40)) end '
                       'if b.state == "wind" and not st.w then st.w = true st.seen = st.seen or {} '
                       '  local m = b.move st.seen[m] = (st.seen[m] or 0) + 1 dbg(m .. st.seen[m], b.t) '
                       'elseif b.state ~= "wind" then st.w = false end', frames=1500)
        firsts = {k[:-1]: int(v[0]) for k, v in got.items() if k.endswith("1")}
        seconds = {k[:-1]: int(v[0]) for k, v in got.items() if k.endswith("2")}
        wind = {"charge": 34, "pound": 30}                 # yaanai.lua's B.wind
        t.check("nizhalattam: the Elephant shows each move first, with a warning twice as long; his charge (16) ends dizzy at a wall",
                r.code == 0 and set(wind) <= set(firsts) and all(v == 2 * wind[m] for m, v in firsts.items())
                and len(seconds) >= 1 and all(seconds[m] == wind[m] for m in seconds)
                and got.get("charged") == ["84", "charge"] and got.get("dizzy") == ["true"], f"{got} {r.err[-300:]}")

        pounds = {}
        for where, feet in (("ground", "at(20, 208)"), ("plank", "at(18, 144)")):
            r, got = story(f'rooms.enter("bboss.ooru", "b6.ooru", body) {feet}', "",
                           'local b = shadows.boss if f == 2 then b.shown.pound, b.move, b.state, b.t = true, "pound", "wind", 1 end '
                           'if f == 120 then dbg("pound", k.health) end', frames=125)
            pounds[where] = got.get("pound")
        t.check("nizhalattam: the Elephant's pound sends a shockwave along the ground (12); on a plank it passes under",
                pounds == {"ground": ["88"], "plank": ["100"]}, f"{pounds} {r.err[-300:]}")

        r, got = story('run.start(body, { "flags" }) rooms.enter("bboss.ooru", "b6.ooru", body)', "",
                       'if f == 3 then st.oil = run.data.oil local b = shadows.boss b.hp = 1 shadows.strike(b, 5, -1, true) end '
                       'if f == 10 then dbg("lent", #fight.carried, fight.carried[2] and fight.carried[2].name, run.data.oil - st.oil) end', frames=12)
        t.check("nizhalattam: the Elephant torn lends his role and 12 oil",
                got.get("lent") == ["2", "Yaanai", "12"], f"{got} {r.err[-300:]}")

        # The elephant's role
        def trunk(read, report, frames=120, wear='"yaanai"', room="s2.ooru", cell=14):
            return story(f'rooms.enter("{room}", "s1.ooru", body) fight.wear({{ {wear} }}) at({cell}, 208)', read,
                         'local d1, d2 = shadows.list[1], shadows.list[2] ' + report, frames)

        r, got = trunk("if f == 10 then i.attack = true end",
                       'if f == 2 then d1.x = k.x + k.w + 20 end if f == 40 then dbg("sweep", d1.hp) end')
        r2, got2 = trunk("", 'if f == 10 then k.vx = 0 body.hurt(10, k.x + 20) dbg("steady", k.vx, k.health) end')
        t.check("nizhalattam: as the Elephant, B sweeps wide (12 at 20 px); no blow throws him back",
                got.get("sweep") == ["6"] and got2.get("steady") == ["0", "90"], f"{got} {got2} {r.err[-300:]} {r2.err[-300:]}")

        r, got = trunk("if f == 10 then i.skill = true end",
                       'if f == 2 then st.w = rooms.w at(math.floor(rooms.w / 8) - 12, 208) d1.x = k.x + 16 d2.on = false end '
                       'if f == 60 then dbg("wall", tostring(d1.on), tostring(d1.x > st.w - 60)) end')
        r2, got2 = trunk("if f == 10 then i.skill = true end",
                         'if f == 2 then d1.x = k.x + 16 d2.on = false end if f == 60 then dbg("open", d1.hp, tostring(d1.x > k.x)) end')
        t.check("nizhalattam: as the Elephant, X charges a shadow before him to the wall (20, tearing a dummy); short of one, 10",
                got.get("wall") == ["false", "true"] and got2.get("open") == ["8", "true"], f"{got} {got2} {r.err[-300:]} {r2.err[-300:]}")

        # Step 5e: the Market of Masks. Its own shadows, in its rooms only.
        r, got = story('rooms.enter("m2.ooru", "m1.ooru", body)', "",
                       'if f == 3 then dbg("market", tostring(shadows.kinds.thief ~= nil), tostring(shadows.kinds.twin ~= nil)) '
                       '  rooms.enter("m4.ooru", "m3.ooru", body) dbg("stall", tostring(shadows.kinds.thief ~= nil), tostring(rooms.shop ~= nil)) '
                       '  rooms.enter("mboss.ooru", "m6.ooru", body) dbg("court", tostring(shadows.kinds.thief ~= nil), tostring(shadows.kinds.mandhiri ~= nil)) '
                       '  rooms.enter("map.ooru", nil, body) dbg("hub", tostring(shadows.kinds.thief ~= nil), tostring(shadows.kinds.mandhiri ~= nil)) end', frames=5)
        t.check("nizhalattam: the market's shadows' code is there in its rooms only",
                got.get("market") == ["true", "true"] and got.get("stall") == ["false", "true"]
                and got.get("court") == ["false", "true"] and got.get("hub") == ["false", "false"], f"{got} {r.err[-300:]}")

        # the mask thief snatches 20 mai and runs; caught, it gives back double
        r, got = story('rooms.enter("m1.ooru", nil, body) at(26, 208) fight.mai = 30', "",
                       'if f == 2 then for _, s in ipairs(shadows.list) do if s.kind == "thief" and not st.t then st.t = s end end '
                       '  for _, s in ipairs(shadows.list) do s.on = s == st.t end end '
                       'if f > 2 and st.t.state == "flee" and not st.s then st.s = true dbg("stole", fight.mai, k.health) end '
                       'if f == 150 then st.t.hp = 1 dbg("caught", shadows.strike(st.t, 5, 1, false), fight.mai) end', frames=155)
        t.check("nizhalattam: a mask thief snatches 20 mai and runs, hurting no one; caught, it gives back double",
                got.get("stole") == ["10", "100"] and got.get("caught") == ["torn", "50"], f"{got} {r.err[-300:]}")

        # the juggler lobs three knives to fall about Komali (8); struck while
        # juggling, it drops them
        juggled = {}
        for strike in (False, True):
            r, got = story('rooms.enter("m3.ooru", "m2.ooru", body) at(36, 208)', "",
                           'if f == 2 then for _, s in ipairs(shadows.list) do if s.kind == "juggler" and not st.j then st.j = s end end '
                           '  for _, s in ipairs(shadows.list) do s.on = s == st.j end end '
                           + ('if f > 2 and st.j.state == "wind" and not st.w then st.w = true shadows.strike(st.j, 2, 1, false) end ' if strike else '')
                           + 'if f == 180 then dbg("knives", k.health) end', frames=185)
            juggled[strike] = got.get("knives")
        t.check("nizhalattam: a juggler lobs knives to fall about Komali (8); struck while juggling, it drops them",
                juggled == {False: ["92"], True: ["100"]}, f"{juggled} {r.err[-300:]}")

        # twin masks flash, then swap places; one torn, the other flies faster and swaps no more
        r, got = story('rooms.enter("m2.ooru", "m1.ooru", body) at(50, 208)', "",
                       'if f == 2 then for _, s in ipairs(shadows.list) do if s.kind == "twin" then if s.sun then st.sun = s else st.moon = s end end end '
                       '  for _, s in ipairs(shadows.list) do s.on = s.kind == "twin" end end '
                       'k.health = 100 if f > 2 then '
                       'if st.was == "wind" and st.sun.state == "walk" and not st.sw then st.sw = true dbg("swapped", tostring(math.abs(st.sun.x - st.mx) < 4)) end '
                       'st.was, st.mx = st.sun.state, st.moon.x end '
                       'if f == 200 then st.moon.hp = 1 shadows.strike(st.moon, 5, 1, false) end '
                       'if f == 220 then dbg("alone", string.format("%.1f", math.sqrt(st.sun.vx ^ 2 + st.sun.vy ^ 2))) end', frames=225)
        t.check("nizhalattam: twin masks flash, then swap places; one torn, the other flies at Komali faster",
                got.get("swapped") == ["true"] and got.get("alone") == ["1.0"], f"{got} {r.err[-300:]}")

        # The Minister's role, against the dodging lesson's soldier
        def ink(read, report, frames=120, wear='"mandhiri"', room="s3.ooru", cell=8):
            return story(f'rooms.enter("{room}", "s2.ooru", body) fight.wear({{ {wear} }}) at({cell}, 208)', read,
                         'local so = shadows.list[1] ' + report, frames)

        r, got = ink("if f == 10 then i.attack = true end",
                     'if f == 2 then so.x = k.x + 60 end if f == 40 then dbg("dart", so.hp, tostring((so.slow or 0) > 0)) end',
                     room="s2.ooru")
        t.check("nizhalattam: as the Minister, B throws an ink dart (7) that slows what it strikes",
                got.get("dart") == ["11", "true"], f"{got} {r.err[-300:]}")

        r, got = ink("if f == 10 then i.skill = true end",
                     'if f == 2 then so.x = k.x + 70 end if f == 30 then at(40, 208) st.x = so.x end '
                     'if f == 31 then dbg("lured", tostring(shadows.lure ~= nil)) end '
                     'if f == 200 then dbg("decoy", tostring(so.x < st.x), k.health) end', frames=205)
        t.check("nizhalattam: as the Minister, X leaves a paper decoy the shadows go for instead of Komali",
                got.get("lured") == ["true"] and got.get("decoy") == ["true", "100"], f"{got} {r.err[-300:]}")

        r, got = ink("if f == 10 then i.swap = 1 end",
                     'if f == 2 then so.x = k.x + 60 end if f == 16 then at(3, 208) end '
                     'if so.state == "reel" and so.t > 100 and not st.h then st.h = true dbg("snared", tostring(f > 20)) end',
                     frames=200, wear='"komali", "mandhiri"')
        t.check("nizhalattam: as the Minister, coming in he drops an ink snare that holds the first shadow into it",
                got.get("snared") == ["true"], f"{got} {r.err[-300:]}")

        # the Minister: each move shown first; his dart (10); his snares hold
        r, got = story('rooms.enter("mboss.ooru", "m6.ooru", body) at(8, 208)', "",
                       'local b = shadows.boss if k.health < 100 and not st.h then st.h = true dbg("dart", k.health) end k.health = 100 k.held = 0 '
                       'if b.state == "wind" and not st.w then st.w = true st.seen = st.seen or {} '
                       '  local m = b.move st.seen[m] = (st.seen[m] or 0) + 1 dbg(m .. st.seen[m], b.t) '
                       'elseif b.state ~= "wind" then st.w = false end', frames=1500)
        firsts = {k[:-1]: int(v[0]) for k, v in got.items() if k.endswith("1")}
        seconds = {k[:-1]: int(v[0]) for k, v in got.items() if k.endswith("2")}
        wind = {"dart": 22, "snare": 28, "decoys": 34}        # mandhiri.lua's B.wind
        t.check("nizhalattam: the Minister shows each move first, with a warning twice as long; his ink dart costs 10",
                r.code == 0 and set(wind) <= set(firsts) and all(v == 2 * wind[m] for m, v in firsts.items())
                and len(seconds) >= 1 and all(seconds[m] == wind[m] for m in seconds) and got.get("dart") == ["90"],
                f"{got} {r.err[-300:]}")

        r, got = story('rooms.enter("mboss.ooru", "m6.ooru", body) at(20, 208)', "",
                       'local b = shadows.boss if f == 2 then b.shown.snare, b.move, b.state, b.t = true, "snare", "wind", 1 end '
                       'if k.held > 0 and not st.h then st.h = true dbg("held", k.health, k.held) end', frames=80)
        t.check("nizhalattam: the Minister's ink snares land about Komali; stepping in one holds him (4, 50 frames)",
                got.get("held") == ["96", "50"], f"{got} {r.err[-300:]}")

        r, got = story('rooms.enter("mboss.ooru", "m6.ooru", body) at(8, 208)', "",
                       'local b = shadows.boss if f == 2 then b.shown.decoys, b.move, b.state, b.t = true, "decoys", "wind", 1 st.x = b.x end '
                       'k.health = 100 '
                       'if f == 18 then local n = 0 for _, d in ipairs(b.decoys) do if d.on then n = n + 1 end end dbg("decoys", n) '
                       '  dbg("paper", shadows.strike(b.decoys[1], 10, 1, false), tostring(b.decoys[1].on), b.hp) end '
                       'if f == 30 then b.hp = 1 shadows.strike(b, 5, 1, true) dbg("gone", tostring(b.decoys[2].on)) end', frames=200)
        t.check("nizhalattam: the Minister conjures two decoys; a blow tears one (he takes nothing); they go when he is torn",
                got.get("decoys") == ["2"] and got.get("paper") == ["torn", "false", "170"] and got.get("gone") == ["false"],
                f"{got} {r.err[-300:]}")

        r, got = story('rooms.enter("mboss.ooru", "m6.ooru", body) at(8, 208)', "",
                       'local b = shadows.boss if f == 2 then b.shown.decoys, b.move, b.state, b.t = true, "decoys", "wind", 1 st.x = b.x end '
                       'k.health = 100 if f > 2 and math.abs(b.x - st.x) > 30 and not st.m then st.m = true dbg("shuffled", f) end', frames=200)
        t.check("nizhalattam: the Minister and his decoys change places",
                "shuffled" in got, f"{got} {r.err[-300:]}")

        r, got = story('run.start(body, { "masks" }) rooms.enter("mboss.ooru", "m6.ooru", body)', "",
                       'if f == 3 then st.oil = run.data.oil local b = shadows.boss b.hp = 1 shadows.strike(b, 5, -1, true) end '
                       'if f == 10 then dbg("lent", #fight.carried, fight.carried[2] and fight.carried[2].name, run.data.oil - st.oil) end', frames=12)
        t.check("nizhalattam: the Minister torn lends his role and 11 oil",
                got.get("lent") == ["2", "Mandhiri", "11"], f"{got} {r.err[-300:]}")

        # Step 5f: the Lamp Palace, the Queen, the Puppet King, and the ending.
        r, got = story('rooms.enter("p2.ooru", "p1.ooru", body)', "",
                       'if f == 3 then dbg("palace", tostring(shadows.kinds.mirror ~= nil), tostring(shadows.kinds.cinder ~= nil)) '
                       '  rooms.enter("p4.ooru", "p3.ooru", body) dbg("stall", tostring(shadows.kinds.mirror ~= nil), tostring(rooms.shop ~= nil)) '
                       '  rooms.enter("pboss.ooru", "p6.ooru", body) dbg("hall", tostring(shadows.kinds.mirror ~= nil), tostring(shadows.kinds.rani ~= nil)) '
                       '  rooms.enter("p7.ooru", "pboss.ooru", body) dbg("stage", tostring(shadows.kinds.rani ~= nil), tostring(shadows.kinds.king ~= nil)) '
                       '  rooms.enter("map.ooru", nil, body) dbg("hub", tostring(shadows.kinds.mirror ~= nil), tostring(shadows.kinds.king ~= nil)) end', frames=5)
        t.check("nizhalattam: the palace's shadows' code is there in its rooms only",
                got.get("palace") == ["true", "true"] and got.get("stall") == ["false", "true"] and got.get("hall") == ["false", "true"]
                and got.get("stage") == ["false", "true"] and got.get("hub") == ["false", "false"], f"{got} {r.err[-300:]}")

        # the lamp guard: its shield turns a light blow from the front; its spear
        # reaches 30 px (12) after a wind-up of 26
        r, got = story('rooms.enter("p1.ooru", nil, body) at(36, 208)', "",
                       'if f == 2 then for _, s in ipairs(shadows.list) do if s.kind == "lampguard" and not st.g then st.g = s end end '
                       '  for _, s in ipairs(shadows.list) do s.on = s == st.g end st.g.face = -1 '
                       '  dbg("front", shadows.strike(st.g, 8, 1, false), st.g.hp) st.g.state = "walk" end '
                       'if f > 2 and st.g.state == "wind" and not st.w then st.w = st.g.t dbg("gap", math.floor(st.g.x - (k.x + k.w))) end '
                       'if k.health < 100 and not st.h then st.h = true dbg("thrust", k.health, st.w) end', frames=200)
        gap = int(got.get("gap", ["0"])[0])
        t.check("nizhalattam: a lamp guard's shield turns a light blow from the front; its spear reaches far (12) after 26 frames",
                got.get("front") == ["blocked", "44"] and got.get("thrust") == ["88", "26"] and gap > 20, f"{got} {r.err[-300:]}")

        # the mirror shade copies Komali's jump, then his blow, a moment later
        r, got = story('rooms.enter("p2.ooru", "p1.ooru", body) at(10, 208)',
                       "if f == 20 then i.jump, i.a = true, true end if f > 20 and f < 30 then i.a = true end if f == 100 then i.attack = true end",
                       'if f == 2 then for _, s in ipairs(shadows.list) do if s.kind == "mirror" and not st.m then st.m = s end end '
                       '  for _, s in ipairs(shadows.list) do s.on = s == st.m end end '
                       'k.health = 100 if f > 2 and st.m.state ~= st.last then st.last = st.m.state '
                       '  if st.m.state == "jump" or st.m.state == "strike" then dbg(st.m.state, f) end end', frames=200)
        jf, sf = int(got.get("jump", ["0"])[0]), int(got.get("strike", ["0"])[0])
        t.check("nizhalattam: a mirror shade does what Komali did, a moment later: his jump, then his blow",
                40 <= jf <= 50 and 120 <= sf <= 130, f"{got} {r.err[-300:]}")

        # the cinder swells, then bursts (14), burning a shadow beside it too;
        # struck, it bursts soon
        r, got = story('rooms.enter("p3.ooru", "p2.ooru", body) at(10, 208)', "",
                       'if f == 2 then for _, s in ipairs(shadows.list) do if s.kind == "cinder" and not st.c then st.c = s end end '
                       '  for _, s in ipairs(shadows.list) do s.on = s == st.c end '
                       '  st.c.x, st.c.y = k.x + 30, k.y st.d = shadows.add(math.floor(k.x + 40), 208, "dummy") end '
                       'if f > 2 and st.c.state == "wind" and not st.w then st.w = f end '
                       'if k.health < 100 and not st.h then st.h = true dbg("burst", k.health, f - st.w, st.d.hp) end', frames=100)
        r2, got2 = story('rooms.enter("p3.ooru", "p2.ooru", body) at(40, 208)', "",
                         'if f == 2 then for _, s in ipairs(shadows.list) do if s.kind == "cinder" and not st.c then st.c = s end end '
                         '  for _, s in ipairs(shadows.list) do s.on = s == st.c end '
                         '  st.c.x, st.c.y = k.x + 100, k.y dbg("struck", tostring(shadows.strike(st.c, 2, 1, false))) end '
                         'if f > 2 and not st.c.on and not st.g then st.g = true dbg("gone", f) end', frames=40)
        t.check("nizhalattam: a cinder swells, then bursts (14), burning the shadows beside it; struck, it bursts soon",
                got.get("burst", ["", ""])[0:2] == ["86", "36"] and got.get("burst", ["", "", "", "18"])[2] != "18"
                and got2.get("struck") == ["nil"] and int(got2.get("gone", ["99"])[0]) <= 12, f"{got} {got2} {r.err[-300:]}")

        # the Queen: each move first; lamp-fire (10); her shield turns three blows
        # and she mends behind it
        r, got = story('rooms.enter("pboss.ooru", "p6.ooru", body) at(8, 208)', "",
                       'local b = shadows.boss if k.health < 100 and not st.h then st.h = true dbg("fire", k.health) end k.health = 100 '
                       'if b.state == "wind" and not st.w then st.w = true st.seen = st.seen or {} '
                       '  local m = b.move st.seen[m] = (st.seen[m] or 0) + 1 dbg(m .. st.seen[m], b.t) '
                       'elseif b.state ~= "wind" then st.w = false end', frames=1500)
        firsts = {k[:-1]: int(v[0]) for k, v in got.items() if k.endswith("1")}
        seconds = {k[:-1]: int(v[0]) for k, v in got.items() if k.endswith("2")}
        wind = {"fire": 24, "shield": 16, "ring": 20}         # rani.lua's B.wind
        t.check("nizhalattam: the Queen shows each move first, with a warning twice as long; her lamp-fire costs 10",
                r.code == 0 and {"fire", "shield"} <= set(firsts) and all(v == 2 * wind[m] for m, v in firsts.items())
                and len(seconds) >= 1 and all(seconds[m] == wind[m] for m in seconds) and got.get("fire") == ["90"], f"{got} {r.err[-300:]}")

        r, got = story('rooms.enter("pboss.ooru", "p6.ooru", body) at(8, 208)', "",
                       'local b = shadows.boss if f == 2 then b.hp = 100 b.shown.shield, b.move, b.state, b.t = true, "shield", "wind", 1 end '
                       'if f == 60 then dbg("mended", b.hp) local r = {} for n = 1, 4 do r[n] = shadows.strike(b, 5, 1, false) end '
                       '  dbg("blows", table.concat(r, ","), b.state) end', frames=65)
        t.check("nizhalattam: the Queen's lamp shield turns three blows, then breaks; she mends behind it",
                got.get("mended") == ["102"] and got.get("blows") == ["blocked,blocked,blocked,hit", "rest"], f"{got} {r.err[-300:]}")

        r, got = story('run.start(body, { "forest" }, "palace") rooms.enter("pboss.ooru", "p6.ooru", body)', "",
                       'if f == 3 then st.oil = run.data.oil local b = shadows.boss b.hp = 1 shadows.strike(b, 5, -1, true) end '
                       'if f == 10 then dbg("lent", #fight.carried, fight.carried[2] and fight.carried[2].name, run.data.oil - st.oil) end', frames=12)
        t.check("nizhalattam: the Queen torn lends her role and 14 oil",
                got.get("lent") == ["2", "Rani", "14"], f"{got} {r.err[-300:]}")

        r, got = story('rooms.enter("s3.ooru", "s2.ooru", body) fight.wear({ "rani" }) at(8, 208)', "if f == 10 then i.skill = true end",
                       'if f == 30 then k.health = 80 local r = {} for n = 1, 4 do r[n] = tostring(body.hurt(10, k.x + 20)) k.struck = 0 end '
                       '  dbg("shield", table.concat(r, ","), k.health) end if f == 150 then dbg("mends", k.health) end', frames=155)
        t.check("nizhalattam: as the Queen, X raises a lamp shield that turns three blows aside; behind it he mends",
                got.get("shield") == ["false,false,false,10", "70"] and got.get("mends") == ["70"], f"{got} {r.err[-300:]}")
        r, got = story('rooms.enter("s3.ooru", "s2.ooru", body) fight.wear({ "rani" }) at(8, 208)', "if f == 10 then i.skill = true end",
                       'if f == 30 then k.health = 80 end if f == 130 then dbg("mends", k.health) end', frames=135)
        t.check("nizhalattam: as the Queen, he mends while the lamp shield holds",
                int(got.get("mends", ["0"])[0]) > 80, f"{got} {r.err[-300:]}")

        # The Puppet King's role, once he is home: X summons two shadow
        # soldiers that go for the shadows about him; each shadow torn makes
        # the next summons sooner; coming in, the cape turns blows from the front
        r, got = story('rooms.enter("s2.ooru", "s1.ooru", body) fight.wear({ "king" }) at(12, 208)', "if f == 10 then i.skill = true end",
                       'local function dummies() local n = 0 for _, s in ipairs(shadows.list) do if s.on and s.kind == "dummy" then n = n + 1 end end return n end '
                       'if f == 12 then dbg("summoned", fight.ROLES.king.summoned(), dummies()) end '
                       'if f == 500 then dbg("later", fight.ROLES.king.summoned(), dummies(), fight.cooldown()) end '
                       'if f == 600 then dbg("gone", fight.ROLES.king.summoned()) end', frames=605)
        later = got.get("later", ["0", "3", "999"])
        t.check("nizhalattam: as the King, X summons two shadow soldiers that tear the shadows near; each torn shortens the wait",
                got.get("summoned") == ["2", "3"] and later[0] == "2" and int(later[1]) < 3
                # (the wait stands still while the world does, a few frames a blow)
                and int(later[2]) < 900 - 490 - 90 * (3 - int(later[1])) + 40 and got.get("gone") == ["0"], f"{got} {r.err[-300:]}")
        r, got = story('rooms.enter("s3.ooru", "s2.ooru", body) fight.wear({ "komali", "king" }) at(8, 208)', "if f == 10 then i.swap = 1 end",
                       'if f == 14 then k.struck = 0 local front = body.hurt(10, k.x + k.w / 2 + k.face * 20) k.struck = 0 '
                       '  dbg("cape", fight.role().name, tostring(front), tostring(body.hurt(10, k.x + k.w / 2 - k.face * 20))) end', frames=16)
        t.check("nizhalattam: as the King, coming in his cape turns blows from the front aside, not from behind",
                got.get("cape") == ["King", "false", "10"], f"{got} {r.err[-300:]}")
        r, got = story('run.data.king, run.data.repairs.r_slot, run.data.chosen = true, 1, { "king" } run.start(body, { "forest" }, "palace") '
                       'local pk = rooms.want("pick") pk.open("box") pk.update({}, body)', "",
                       'if f == 3 then dbg("carried", #fight.carried, fight.carried[2] and fight.carried[2].name) end', frames=4)
        t.check("nizhalattam: once the King is home his role can be chosen at the box, and is carried from the start",
                got.get("carried") == ["2", "King"], f"{got} {r.err[-300:]}")

        # The Puppet King: act one calls in soldiers, and his cape turns blows back
        r, got = story('rooms.enter("p7.ooru", "pboss.ooru", body) at(20, 208)', "",
                       'local b = shadows.boss if f == 2 then b.shown.summon, b.move, b.state, b.t = true, "summon", "wind", 1 end '
                       'if f == 5 then local n = 0 for _, s in ipairs(shadows.list) do if s.on and s.kind == "soldier" then n = n + 1 end end dbg("soldiers", n) '
                       '  b.state, b.t, b.face, k.health, k.struck = "cape", 0, -1, 100, 0 dbg("cape", shadows.strike(b, 10, 1, false), k.health) '
                       '  b.hp = 1 shadows.strike(b, 5, -1, true) n = 0 for _, s in ipairs(shadows.list) do if s.on then n = n + 1 end end dbg("after", n, tostring(rooms.locked())) end',
                       frames=8)
        t.check("nizhalattam: in act one the King calls soldiers in from the wings; his cape turns a blow back (6); beaten, the stage clears",
                got.get("soldiers") == ["2"] and got.get("cape") == ["blocked", "94"] and got.get("after") == ["0", "false"], f"{got} {r.err[-300:]}")

        # act three: a move from each puppet saved, and more health for each
        r, got = story('run.data.saved = { "veeran", "yaanai" } rooms.enter("p9.ooru", "p8.ooru", body)', "",
                       'if f == 2 then local b = shadows.boss dbg("saved2", table.concat(b.moves, ","), b.max) '
                       '  run.data.saved = {} rooms.enter("p9.ooru", "p8.ooru", body) b = shadows.boss dbg("none", table.concat(b.moves, ","), b.max) end', frames=4)
        t.check("nizhalattam: in act three the King fights with a move from each puppet saved, and has more health for each",
                got.get("saved2") == ["swing,leap,pound", "120"] and got.get("none") == ["swing", "70"], f"{got} {r.err[-300:]}")

        # The ending: the King beaten in act three lets one puppet go, chosen by
        # the player; it is saved, and the run ends at the box. With all six saved,
        # he comes home himself.
        steps = "if f == 10 or f == 12 then i.right_p = true end if f == 14 then i.jump = true end"
        r, got = story('run.start(body, { "forest" }, "palace") run.data.saved = { "veeran" } rooms.enter("p9.ooru", "p8.ooru", body)', steps,
                       'if f == 3 then st.p = run.data.played local b = shadows.boss b.hp = 1 shadows.strike(b, 5, -1, true) end '
                       'if f == 6 then dbg("choose", tostring(rooms.pick.is_open())) end '
                       'if f == 300 then dbg("freed", table.concat(run.data.saved, ","), run.data.played - st.p, rooms.name) end', frames=305)
        r2, got2 = story('run.start(body, { "forest" }, "palace") run.data.saved = { "veeran", "vil", "aattakkaari", "yaanai", "mandhiri", "rani" } '
                         'rooms.enter("p9.ooru", "p8.ooru", body)', "",
                         'if f == 3 then local b = shadows.boss b.hp = 1 shadows.strike(b, 5, -1, true) end '
                         'if f == 300 then dbg("king", tostring(run.data.king), rooms.name) end', frames=305)
        t.check("nizhalattam: the King beaten lets the puppet chosen go home (saved); the run ends at the box; with all six home, he comes",
                got.get("choose") == ["true"] and got.get("freed") == ["veeran,yaanai", "1", "map.ooru"]
                and got2.get("king") == ["true", "map.ooru"], f"{got} {got2} {r.err[-300:]} {r2.err[-300:]}")

        # Hard mode, once the King is home: shadows have half as much health
        # again, hit half as hard again, and come more of them
        count = ('local n, hp = 0, nil for _, s in ipairs(shadows.list) do if s.on and not s.prop then n = n + 1 end '
                 '  if s.kind == "soldier" and not hp then hp = s.hp end end ')
        r, got = story('rooms.enter("b1.ooru", nil, body) ' + count + 'dbg("gentle", n, hp, tostring(run.hard())) '
                       'run.data.king = true rooms.enter("b1.ooru", nil, body) ' + count + 'dbg("hard", n, hp, tostring(run.hard())) '
                       'dbg("blow", body.hurt(12, 0), k.health)', "", "", frames=4)
        gentle, hard = got.get("gentle", ["0"]), got.get("hard", ["0"])
        t.check("nizhalattam: in hard mode shadows have 1.5x health, hit 1.5x harder, and there are more of them",
                gentle[1:] == ["40", "false"] and hard[1:] == ["60", "true"] and int(hard[0]) > int(gentle[0])
                and got.get("blow") == ["18", "82"], f"{got} {r.err[-300:]}")

        # a boss is a shadow once his puppet is saved, and every one is in
        # hard mode (the King too: his shadow is hard's last boss, below); a
        # shadow torn lends no role, but leaves its oil
        r, got = story('rooms.enter("boss.ooru", "s7.ooru", body) dbg("puppet", tostring(shadows.boss.shade)) '
                       'run.data.saved = { "veeran" } rooms.enter("boss.ooru", "s7.ooru", body) dbg("saved", tostring(shadows.boss.shade)) '
                       'run.data.saved = {} run.data.king = true rooms.enter("fboss.ooru", "f6.ooru", body) '
                       '  dbg("hard", tostring(shadows.boss.shade), shadows.boss.hp, shadows.boss.max) '
                       'rooms.enter("p7.ooru", "pboss.ooru", body) dbg("king", tostring(shadows.boss.shade)) '
                       'run.data.king = false run.data.saved = { "veeran" } run.start(body, { "forest" }, "palace") '
                       '  rooms.enter("boss.ooru", "s7.ooru", body) st.oil = run.data.oil local b = shadows.boss b.hp = 1 shadows.strike(b, 5, -1, true)', "",
                       'if f == 10 then dbg("torn", #fight.carried, tostring(run.lent.veeran), run.data.oil - st.oil) end', frames=12)
        t.check("nizhalattam: a saved puppet's boss is its shadow, and in hard mode every boss; a shadow lends no role",
                got.get("puppet") == ["false"] and got.get("saved") == ["true"] and got.get("hard") == ["true", "225", "225"]
                and got.get("king") == ["true"] and got.get("torn") == ["1", "nil", "8"], f"{got} {r.err[-300:]}")

        # each boss's shadow has its stronger moves: watched for 2400 frames
        # with Komali walking to and fro, never falling (the blows' costs say
        # which moves landed; the most arrows loosed in one frame)
        watch = ('local h0 = body.hurt body.hurt = function(n, x) st.h = st.h or {} st.h[n] = true return h0(n, x) end '
                 'local sh = require("shots") local f0 = sh.fire sh.fire = function(...) st.fired = (st.fired or 0) + 1 return f0(...) end ')
        report = ('local b = shadows.boss k.health, k.struck, k.steady = 100, 0, true '
                  'if (st.fired or 0) > (st.most or 0) then st.most = st.fired end st.fired = 0 '
                  'if b and b.on then st.s = st.s or {} st.s[b.state] = true if (b.count or 0) > (st.c or 0) then st.c = b.count end '
                  '  if b.again then st.again = true end end '
                  'if f == 2400 then local s = {} for x in pairs(st.s or {}) do s[#s + 1] = x end table.sort(s) '
                  '  local h = {} for x in pairs(st.h or {}) do h[#h + 1] = x end table.sort(h) '
                  '  dbg("seen", table.concat(s, ","), table.concat(h, ","), st.most or 0, st.c or 0, tostring(st.again)) end')
        shades = {}
        for boss, room, came in (("veeran", "boss.ooru", "s7.ooru"), ("vil", "fboss.ooru", "f6.ooru"),
                                 ("aattakkaari", "kboss.ooru", "k6.ooru"), ("yaanai", "bboss.ooru", "b6.ooru"),
                                 ("mandhiri", "mboss.ooru", "m6.ooru"), ("rani", "pboss.ooru", "p6.ooru")):
            r, got = story(f'run.data.saved = {{ "{boss}" }} rooms.enter("{room}", "{came}", body) at(8, 208) ' + watch,
                           "i.right = f % 300 < 90 i.left = f % 300 >= 150 and f % 300 < 240", report, frames=2402)
            seen = got.get("seen", ["", "", "0", "0", "nil"])
            shades[boss] = (seen[0].split(","), seen[1].split(","), int(seen[2]), int(seen[3]), seen[4], r.err[-200:] if r.code else "")
        v, a, d, e, m, q = (shades[b] for b in ("veeran", "vil", "aattakkaari", "yaanai", "mandhiri", "rani"))
        t.check("nizhalattam: the bosses' shadows: the Warrior leaps (16) and slashes five times; the Archer looses three at once "
                "and rains arrows; the Dancer's afterimages strike (10); the Elephant charges twice and stones fall (10); "
                "the Minister's decoys throw too; the Queen's ring closes in",
                "leap" in v[0] and "16" in v[1] and v[3] == 5 and "rain" in a[0] and a[2] == 3 and "10" in d[1]
                and e[4] == "true" and "10" in e[1] and m[2] >= 2 and "close" in q[0]
                and not any(s[5] for s in shades.values()), shades)

        # hard mode's last boss: the King's shadow, in three acts, with the
        # puppets' moves; when he summons, a puppet's shadow comes out of the
        # wings with his soldiers, each puppet in turn; torn in the third
        # act, it is Ending B
        hard_king = 'run.data.king = true run.data.saved = { "veeran", "vil", "aattakkaari", "yaanai", "mandhiri", "rani" } '
        r, got = story(hard_king + 'local function moves(n) rooms.enter("p" .. n .. ".ooru", nil, body) local b = shadows.boss '
                       '  local m = {} for _, x in ipairs(b.moves) do m[#m + 1] = x end table.sort(m) '
                       '  dbg("act" .. b.act, tostring(b.shade), table.concat(m, ","), tostring(fight.shots ~= nil)) end '
                       'moves(7) moves(8) moves(9) at(8, 208) local b = shadows.boss b.move, b.state, b.t = "summon", "wind", 1', "",
                       'local b = shadows.boss if f == 4 then dbg("called", b.pk or "-", tostring(b.pt > 0), tostring(b.soldiers[1].on)) end '
                       'if f == 200 then b.move, b.state, b.t = "summon", "wind", 1 end '
                       'if f == 204 then dbg("next", b.pk or "-") end', frames=206)
        t.check("nizhalattam: in hard mode the King is his shadow: each act has puppets' moves, and a summons brings a puppet's shadow",
                got.get("act1") == ["true", "cape,dash,leap,summon,swing", "true"]
                and got.get("act2") == ["true", "crown,pound,summon,swing,volley", "true"]
                and got.get("act3") == ["true", "dash,leap,pound,ring,snare,summon,swing,volley", "true"]
                and got.get("called") == ["veeran", "true", "true"] and got.get("next") == ["vil"], f"{got} {r.err[-300:]}")

        r, got = story('run.start(body, { "forest" }, "palace") ' + hard_king + 'rooms.enter("p9.ooru", "p8.ooru", body)', "",
                       'if f == 3 then local b = shadows.boss b.hp = 1 shadows.strike(b, 5, -1, true) end '
                       'if f == 6 then dbg("choose", tostring(rooms.pick ~= nil and rooms.pick.is_open())) end '
                       'if f == 300 then dbg("ending", tostring(run.data.ending_b), #run.data.saved, rooms.name) end', frames=305)
        t.check("nizhalattam: the King's shadow torn in the third act is Ending B; no puppet is chosen, the run ends at the box",
                got.get("choose") == ["false"] and got.get("ending") == ["true", "6", "map.ooru"], f"{got} {r.err[-300:]}")

        # each ending is a scene of three panels before its card: A moves a
        # panel on after a moment; left alone it plays them all
        played = {}
        for name, king, taps in (("a", "false", "if f % 50 == 0 then i.jump = true end"), ("a_alone", "false", ""),
                                 ("b", "true", "if f % 50 == 0 then i.jump = true end")):
            r, got = story(f'run.start(body, {{ "forest" }}, "palace") run.data.king = {king} '
                           'run.data.saved = { "veeran", "vil", "aattakkaari", "yaanai", "mandhiri", "rani" } rooms.enter("p9.ooru", "p8.ooru", body)', taps,
                           'if f == 3 then st.p = run.data.played local b = shadows.boss b.hp = 1 shadows.strike(b, 5, -1, true) end '
                           'if f == 450 then dbg("played", run.data.played - st.p) end '
                           'if f == 1300 then dbg("later", run.data.played - st.p, rooms.name) end', frames=1302)
            played[name] = (got.get("played"), got.get("later"), r.err[-200:] if r.code else "")
        t.check("nizhalattam: each ending plays as a scene, A moving it on; then its card, and the box",
                played["a"][0] == ["1"] and played["b"][0] == ["1"] and played["a_alone"][0] == ["0"]
                and played["a_alone"][1] == ["1", "map.ooru"], played)

        # the pages of the King's story: one in a room of each story; found,
        # it is read at once and kept (in the order found), and is not there
        # again; at the box the pages found are read again (B puts them away)
        r, got = story('rooms.enter("s5.ooru", "s4.ooru", body) dbg("lying", tostring(rooms.page_x ~= nil)) '
                       'body.place(rooms.page_x, rooms.page_y)', "",
                       'if f == 3 then dbg("found", table.concat(run.data.pages, ","), tostring(rooms.page_x)) '
                       '  rooms.enter("s5.ooru", "s4.ooru", body) dbg("again", tostring(rooms.page_x)) end', frames=5)
        r2, got2 = story('local n = 0 for _, room in ipairs({ "f1", "k5", "b3", "m5", "p3" }) do '
                         '  rooms.enter(room .. ".ooru", nil, body) if rooms.page_x then n = n + 1 end end dbg("each", n)', "", "", frames=3)
        r3, got3 = story('run.data.pages = { "screen" } at(7, 208)',
                         " ".join(f"if f == {fr} then i.{b} = true end" for fr, b in
                                  [(10, "door")] + [(12 + 2 * n, "right_p") for n in range(5)] + [(24, "jump"), (30, "attack"), (40, "attack")]),
                         'if f == 34 then dbg("reading", tostring(rooms.shop.is_open())) end '
                         'if f == 44 then dbg("left", tostring(rooms.shop.is_open())) end', frames=46)
        t.check("nizhalattam: a page of the King's story lies in a room of each story; found, it is kept, not there again, and read at the box",
                got.get("lying") == ["true"] and got.get("found") == ["screen", "nil"] and got.get("again") == ["nil"]
                and got2.get("each") == ["5"] and got3.get("reading") == ["true"] and got3.get("left") == ["false"],
                f"{got} {got2} {got3} {r.err[-300:]} {r2.err[-300:]} {r3.err[-300:]}")

        # A run is kept at every door: switched off and on again, the game
        # asks, and A takes it up where it was; falling lets it go.
        with tempfile.TemporaryDirectory() as saves:
            r, got = story("at(34, 208)", "if f == 10 or f == 70 then i.door = true end",
                           'if f == 60 then fight.mai, k.health = 77, 63 fight.lend("veeran") run.charms[1] = "bell" '
                           '  at(math.floor(rooms.w / 8) - 6, 208) end '
                           'if f == 120 then local kp = run.kept() dbg("kept", kp.room, kp.from, kp.health, kp.mai, '
                           '  table.concat(kp.roles, ","), kp.charms[1], tostring(kp.seed == run.seed)) end', frames=125, saves=saves)
            r2, got2 = story("", "if f == 10 then i.jump = true end",
                             'if f == 2 then dbg("asks", rooms.name, tostring(run.kept() ~= nil)) end '
                             'if f == 20 then local n = {} for _, r in ipairs(fight.carried) do n[#n + 1] = r.name end '
                             '  dbg("back", rooms.name, k.health, fight.mai, table.concat(n, ","), run.charms[1], run.seed) k.health = 0 end '
                             'if f == 300 then dbg("fell", rooms.name, tostring(run.kept())) end', frames=305, saves=saves)
            r3, got3 = story("", "", 'if f == 5 then dbg("after", tostring(run.kept())) end', frames=8, saves=saves)
        kept = got.get("kept", [""] * 7)
        t.check("nizhalattam: a run is kept at every door; switched on again, A takes it up where it was; falling lets it go",
                kept[:6] == ["s2.ooru", "s1.ooru", "63", "77", "komali,veeran", "bell"] and kept[6] == "true"
                and got2.get("asks") == ["map.ooru", "true"] and (got2.get("back") or [""])[:5] == ["s2.ooru", "63", "77", "Komali,Veeran", "bell"]
                and got2.get("fell") == ["map.ooru", "nil"] and got3.get("after") == ["nil"],
                f"{got} {got2} {got3} {r.err[-300:]} {r2.err[-300:]}")

        # The title: three save slots, each showing its runs played through
        # and its oil. A plays the slot chosen; X twice empties it. The save
        # from before there were slots becomes slot 1; the language is shared.
        with tempfile.TemporaryDirectory() as saves:
            r, got = story("", "if f == 10 then i.right_p = true end if f == 14 then i.jump = true end",
                           'if f == 5 then dbg("title", tostring(rooms.name)) end '
                           'if f == 20 then dbg("slot", rooms.name, run.slot) run.data.oil, run.data.played = 33, 2 run.keep() end',
                           frames=25, saves=saves, title=True)
            r2, got2 = story("", "if f == 10 then i.jump = true end",
                             'if f == 5 then local a, b = require("title").peek(1), require("title").peek(2) dbg("peek", tostring(a), b.played, b.oil) end '
                             'if f == 20 then dbg("one", run.slot, run.data.oil) end', frames=25, saves=saves, title=True)
            r3, got3 = story("", "if f == 10 then i.right_p = true end if f == 12 or f == 14 then i.skill = true end",
                             'if f == 20 then dbg("erased", tostring(require("title").peek(2))) end', frames=25, saves=saves, title=True)
        with tempfile.TemporaryDirectory() as saves:
            t.run_game("save('progress', { version = 1, lang = 'en', oil = 21, played = 3, falls = 0, runs = 4, "
                       "repairs = {}, saved = { 'vil' }, chosen = {}, king = false, kept = false })",
                       manifest=open(os.path.join(ROOT, "examples", "nizhalattam", "manifest.lua")).read(), saves=saves)
            r4, got4 = story("", "if f == 10 then i.jump = true end",
                             'if f == 5 then local p = require("title").peek(1) dbg("old", p.played, p.oil, p.saved[1], lines.lang) end '
                             'if f == 20 then dbg("moved", run.data.oil, tostring(load("progress"))) end', frames=25, saves=saves, title=True)
        t.check("nizhalattam: the game opens on the title; a slot chosen, Komali is in the Courtyard, its save his",
                got.get("title") == ["nil"] and got.get("slot") == ["map.ooru", "2"]
                and got2.get("peek") == ["nil", "2", "33"] and got2.get("one") == ["1", "0"], f"{got} {got2} {r.err[-300:]}")
        t.check("nizhalattam: at the title X, and X again, empties a slot",
                got3.get("erased") == ["nil"], f"{got3} {r3.err[-300:]}")
        t.check("nizhalattam: the save from before the slots is slot 1, in its language",
                got4.get("old") == ["3", "21", "vil", "en"] and got4.get("moved") == ["21", "nil"], f"{got4} {r4.err[-300:]}")

        # The run: a seed when Komali steps into the Screen; the stories
        # between the first and the last in an order from it; the halfway
        # tear after the middle one.
        r, got = story("at(34, 208)", "if f == 10 then i.door = true end",
                       'if f == 2 then st.runs = run.data.runs dbg("before", tostring(run.seed)) end '
                       'if f == 60 then dbg("begun", rooms.name, tostring(run.seed ~= nil), table.concat(run.order, ","), '
                       '  run.data.runs - st.runs, tostring(run.typed)) end', frames=70)
        begun = got.get("begun", [""] * 5)
        t.check("nizhalattam: a run begins as Komali steps into the Screen: a seed, the stories in order, counted",
                got.get("before") == ["nil"] and begun[:2] == ["s1.ooru", "true"] and begun[3:] == ["1", "false"]
                and begun[2].startswith("screen,") and begun[2].endswith(",palace")
                and sorted(begun[2].split(",")[1:-1]) == ["flags", "forest", "masks", "sea"], got)

        r, got = story("", "",
                       'if f == 3 then local m = { "forest", "sea", "flags", "masks" } local seen = {} '
                       '  for _, seed in ipairs({ 12345, 12345, 777, 4242 }) do run.next_seed = seed run.start(body, m, "palace") '
                       '    seen[#seen + 1] = table.concat(run.order, ",") end '
                       '  dbg("orders", table.unpack(seen)) dbg("half", run.half, tostring(run.typed)) '
                       '  run.order, run.half = { "screen", "forest" }, 1 '
                       '  dbg("after", rooms.after("screen"), rooms.after("tear"), rooms.after("forest")) end', frames=5)
        orders = got.get("orders", [])
        t.check("nizhalattam: the same seed, the same order of stories; the Screen first, the Palace last; the tear halfway",
                len(orders) == 4 and orders[0] == orders[1] and len(set(orders)) >= 3
                and all(o.startswith("screen,") and o.endswith(",palace") and len(o.split(",")) == 6 for o in orders)
                and got.get("half") == ["3", "true"] and got.get("after") == ["tear.ooru", "f1.ooru", "end"], got)

        r, got = story('run.next_seed = 4242 run.start(body, rooms.MIDDLE) rooms.enter("fboss.ooru", "f6.ooru", body)',
                       "if f == 140 then i.door = true end",
                       'if f == 3 then st.oil, st.p, st.runs = run.data.oil, run.data.played, run.data.runs local b = shadows.boss b.hp = 1 '
                       '  shadows.strike(b, 5, -1, true) end '
                       'if f == 10 then at(58, 208) end '
                       'if f == 145 then dbg("end", string.format("%05d", run.seed), run.clock(), run.cleared) end '
                       'if f == 380 then dbg("kept", run.data.oil - st.oil, run.data.played - st.p, run.data.runs - st.runs) end', frames=390)
        t.check("nizhalattam: a run from a typed seed keeps nothing: no oil, not counted; its seed and time are shown",
                got.get("end") == ["04242", "0:02", "1"] and got.get("kept") == ["0", "0", "0"], got)

        def presses(*steps):
            """Lua for body.read: each (frame, field) sets that input on that frame."""
            return " ".join(f"if f == {f} then i.{k} = true end" for f, k in steps)

        # The Aasaan's box: places bought with oil; the saved puppets' roles
        # to carry in them; a seed. Its cards: health, double jump, mai,
        # place, roles, seed. The picker's: the six puppets, then Done.
        r, got = story('run.data.oil = 25 at(7, 208)',
                       presses((10, "door"), (12, "down_p"), (14, "down_p"), (16, "down_p"), (18, "jump"), (22, "attack")),
                       'if f == 30 then dbg("place", run.data.oil, run.data.repairs.r_slot) end', frames=35)
        t.check("nizhalattam: at the box oil buys a place for a role carried from the start (20)",
                got.get("place") == ["5", "1"], got)

        steps = [(10, "door")] + [(12 + 2 * n, "down_p") for n in range(4)] + [(20, "jump"),     # Roles
                 (24, "jump"), (26, "right_p"), (28, "jump")] + [(30 + 2 * n, "right_p") for n in range(5)] + [(42, "jump")]
        r, got = story('run.data.saved = { "veeran", "vil" } run.data.repairs.r_slot = 2 at(7, 208)', presses(*steps),
                       'if f == 50 then dbg("chosen", table.concat(run.data.chosen, ","), tostring(rooms.pick.is_open())) '
                       '  run.start(body, rooms.MIDDLE) local n = {} for _, r in ipairs(fight.carried) do n[#n + 1] = r.name end '
                       '  dbg("wears", table.concat(n, ",")) '
                       '  run.data.repairs.r_slot = 1 run.start(body, rooms.MIDDLE) dbg("one", #fight.carried) '
                       '  run.data.saved = { "vil" } run.data.repairs.r_slot = 2 run.start(body, rooms.MIDDLE) dbg("unsaved", #fight.carried) end', frames=55)
        t.check("nizhalattam: at the box saved puppets' roles go in the places bought, to carry from the start of each run",
                got.get("chosen") == ["veeran,vil", "false"] and got.get("wears") == ["Komali,Veeran,Vil"]
                and got.get("one") == ["2"] and got.get("unsaved") == ["2"], got)

        steps = [(10, "door")] + [(12 + 2 * n, "down_p") for n in range(4)] + [(20, "jump"),
                 (24, "jump"), (26, "right_p"), (28, "right_p"), (30, "jump")]       # Veeran; then Aattakkaari, not saved
        r, got = story('run.data.saved = { "veeran", "vil" } run.data.repairs.r_slot = 0 at(7, 208)', presses(*steps),
                       'if f == 25 then dbg("locked", #require("pick").PUPPETS) end '
                       'if f == 32 then dbg("none", tostring(rooms.pick.is_open())) end', frames=35)
        r2, got2 = story('run.data.saved = { "veeran" } run.data.repairs.r_slot = 2 at(7, 208)',
                         presses(*(steps[:7] + [(26, "right_p"), (28, "jump")] + [(30 + 2 * n, "right_p") for n in range(5)] + [(42, "jump")])),
                         'if f == 50 then dbg("chosen", table.concat(run.data.chosen, ",")) end', frames=55)
        t.check("nizhalattam: no place bought, or a puppet not saved, and nothing is chosen",
                got2.get("chosen") == ["veeran"] and got.get("none") == ["true"], (got, got2))

        steps = [(10, "door")] + [(12 + 2 * n, "down_p") for n in range(6)] + [(24, "jump"),     # Seed
                 (26, "door"), (28, "door"), (30, "door"), (32, "right_p"), (34, "door"), (36, "jump")]
        r, got = story("at(7, 208)", presses(*steps),
                       'if f == 40 then dbg("seed", tostring(run.next_seed)) run.start(body, rooms.MIDDLE) '
                       '  dbg("typed", run.seed, tostring(run.typed), tostring(run.next_seed)) end', frames=45)
        t.check("nizhalattam: at the box a seed is typed digit by digit, for the next run only, which keeps nothing",
                got.get("seed") == ["31000"] and got.get("typed") == ["31000", "true", "nil"], got)

        # The halfway tear: the roles carried change, once a run. Veeran was
        # lent in this run (he needs no place bought); Vil is saved, in the
        # one place bought.
        steps = [(10, "door"), (14, "jump"), (16, "right_p"), (18, "jump")] + [(20 + 2 * n, "right_p") for n in range(5)] + [(32, "jump"),
                 (40, "door"), (44, "jump")]
        r, got = story('run.data.saved = { "vil" } run.data.repairs.r_slot = 1 run.lent.veeran = true '
                       'fight.wear({ "komali", "veeran" }) rooms.enter("tear.ooru", "boss.ooru", body) at(20, 208)', presses(*steps),
                       'local function names() local n = {} for _, r in ipairs(fight.carried) do n[#n + 1] = r.name end return table.concat(n, ",") end '
                       'if f == 36 then dbg("changed", names(), tostring(run.torn)) end '
                       'if f == 42 then dbg("again", tostring(rooms.pick.is_open())) end '
                       'if f == 50 then dbg("once", names(), tostring(rooms.pick.is_open())) end', frames=55)
        t.check("nizhalattam: at the halfway tear the roles carried change, once a run",
                got.get("changed") == ["Komali,Vil", "true"] and got.get("again") == ["true"]
                and got.get("once") == ["Komali,Vil", "false"], got)

        # Lent a role with both places full: give one up for it, or keep them.
        full = ('rawset(fight.ROLES, "aattakkaari", { name = "Aattakkaari", combo = fight.ROLES.komali.combo, '
                'air = fight.ROLES.komali.air, swap = fight.ROLES.komali.swap, skill = "pratfall", wait = 240, '
                'slow = 0.5, dodge_wait = 1, guard = 0 }) fight.wear({ "komali", "vil", "aattakkaari" }) '
                'rooms.enter("boss.ooru", "s7.ooru", body) ')
        given = {}
        for name, read in (("give", "if f == 12 then i.down_p = true end if f == 14 then i.jump = true end"),
                           ("keep", "if f == 12 or f == 14 then i.down_p = true end if f == 16 then i.jump = true end")):
            r, got = story(full, read,
                           'if f == 3 then local b = shadows.boss b.hp = 1 shadows.strike(b, 5, -1, true) end '
                           'if f == 10 then dbg("asks", tostring(rooms.pick.is_open())) end '
                           'if f == 30 then local n = {} for _, r in ipairs(fight.carried) do n[#n + 1] = r.name end '
                           '  dbg("carried", table.concat(n, ","), tostring(rooms.pick.is_open())) end', frames=35)
            given[name] = (got.get("asks"), got.get("carried"))
        t.check("nizhalattam: lent a role with both places full, Komali gives one up for it, or keeps those he carries",
                given["give"] == (["true"], ["Komali,Vil,Veeran", "false"])
                and given["keep"] == (["true"], ["Komali,Vil,Aattakkaari", "false"]), given)

        # Vil's role, among the striking lesson's dummies (cells 18, 26, 34)
        def archer(read, report, frames=120, wear='"vil"'):
            return story(f'rooms.enter("s2.ooru", "s1.ooru", body) fight.wear({{ {wear} }}) at(8, 208)', read,
                         'local d1, d2 = shadows.list[1], shadows.list[2] local shots = require("shots") ' + report, frames)

        r, got = archer("if f == 10 then i.attack = true end", 'if f == 60 then dbg("hp", d1.hp, d2.hp) end')
        r2, got2 = archer("if f == 10 then i.attack, i.up = true, true end if f < 16 then i.up = true end",
                          'if f == 60 then dbg("hp", d1.hp, d2.hp) end')
        t.check("nizhalattam: as Vil, B looses an arrow that strikes from afar (7); aimed up, it flies over",
                got.get("hp") == ["11", "18"] and got2.get("hp") == ["18", "18"], (got, got2))

        r, got = archer("if f == 10 then i.attack = true end if f >= 30 and f <= 64 then i.b = true end",
                        'if f == 110 then dbg("hp", tostring(d1.on), d2.hp) end')
        t.check("nizhalattam: as Vil, B held looses a piercing arrow (16) through one dummy into the next",
                got.get("hp") == ["false", "2"], got)

        r, got = archer("if f == 10 or f == 30 or f == 70 then i.attack = true end if f >= 66 and f < 76 then i.up = true end",
                        'if f == 60 then dbg("two", shots.streak) end if f == 140 then dbg("missed", shots.streak) end', frames=145)
        t.check("nizhalattam: as Vil, each arrow that strikes counts toward the next flying further; a miss starts again",
                got.get("two") == ["2"] and got.get("missed") == ["0"], got)

        r, got = archer("if f == 10 then i.skill = true end", 'if f == 100 then dbg("rain", tostring(d1.on), d2.hp) end')
        t.check("nizhalattam: as Vil, X brings a rain of arrows down on a spot ahead",
                got.get("rain") == ["false", "18"], got)

        r, got = archer("if f == 10 then i.swap = 1 end",
                        'if f == 9 then st.x = k.x end if f == 13 then dbg("leap", tostring(k.vy < 0), fight.role().name) end '
                        'if f == 40 then dbg("back", k.x < st.x) end', frames=45, wear='"komali", "vil"')
        t.check("nizhalattam: Vil coming in leaps back",
                got.get("leap") == ["true", "Vil"] and got.get("back") == ["true"], got)

        r, got = story('rooms.enter("s5.ooru", "s4.ooru", body) fight.mai = 30', "",
                       'if f == 5 then st.oil = run.data.oil k.health = 0 end '
                       'if f == 240 then dbg("woke", rooms.name, k.health, fight.mai, run.data.falls, run.data.oil - st.oil) end', frames=250)
        t.check("nizhalattam: fallen, Komali wakes on the Aasaan's box: the run's mai is lost, oil is kept",
                got.get("woke") == ["map.ooru", "100", "0", "1", "0"], got)

        r, got = story('rooms.enter("s5.ooru", "s4.ooru", body)', "if f == 20 or f == 90 then i.pause = true end",
                       'local sum = 0 for _, s in ipairs(shadows.list) do if s.on then sum = sum + s.x + s.y + s.step end end '
                       'if f == 30 then st.x = sum end if f == 80 then dbg("still", tostring(sum == st.x)) end '
                       'if f == 120 then dbg("moving", tostring(sum ~= st.x)) end', frames=130)
        t.check("nizhalattam: START pauses the world, and START again carries on",
                got.get("still") == ["true"] and got.get("moving") == ["true"], f"{got} {r.err[-300:]}")

        # Places have colours of their own: entering the Screen sets them.
        r, got = story("", "",
                       'if f == 3 then dbg("court", palette(20)) dbg("court_shade", palette(52)) '
                       '  rooms.enter("s1.ooru", "map.ooru", body) dbg("screen", palette(20)) dbg("screen_shade", palette(52)) '
                       '  dbg("actor", palette(10)) rooms.enter("map.ooru", "s1.ooru", body) dbg("again", palette(20)) end', frames=5)
        t.check("nizhalattam: each place sets its own colours (20-31 and their shades); the characters' stay",
                got.get("court") and got.get("court") != got.get("screen") and got.get("court_shade") != got.get("screen_shade")
                and got.get("again") == got.get("court") and got.get("screen", ["0"])[0] == "255", got)

        # Veeran is twice Komali's size, and in the way: no walking, rolling
        # or single jump gets past him; a double jump does.
        held = 'local b = shadows.boss b.state, b.t, b.vx = "rest", 9999, 0 '
        r, got = story('rooms.enter("boss.ooru", "s7.ooru", body) at(24, 208)',
                       'i.right = true if f % 40 == 0 then i.dodge = true end if f % 25 == 5 then i.a, i.jump = true, true end '
                       'if f % 25 > 5 and f % 25 < 20 then i.a = true end',
                       held + 'k.health = 100 if f == 400 then dbg("past", tostring(k.x > b.x + b.w), b.h) end', frames=410)
        t.check("nizhalattam: Veeran, 40 tall, blocks Komali: walking, rolling and single jumps do not get past",
                got.get("past") == ["false", "40"], got)
        r, got = story('rooms.enter("boss.ooru", "s7.ooru", body) at(24, 208) k.double = true',
                       'i.right = true if f == 40 or f == 62 then i.a, i.jump = true, true end if f > 40 and f < 90 then i.a = true end',
                       held + 'k.health = 100 if f == 200 then dbg("past", tostring(k.x > b.x + b.w)) end', frames=210)
        t.check("nizhalattam: with the double jump, Komali clears Veeran",
                got.get("past") == ["true"], got)

        # The boss room's rails climb to a bridge above Veeran: from the
        # floor, rails each a jump above the last lead over him.
        import xml.etree.ElementTree as ET
        root = ET.parse(os.path.join(ROOT, "examples", "nizhalattam", "boss.tmx")).getroot()
        bw, bh = int(root.get("width")), int(root.get("height"))
        layer = [(int(v) & 0x0FFFFFFF) - 1 for v in root.find("layer").find("data").text.replace("\n", "").split(",") if v.strip()]
        stand = {(x, y) for y in range(bh) for x in range(bw) if layer[y * bw + x] in (1, 3, 5, 6, 7, 11, 12)}
        reach, todo = {c for c in stand if c[1] == 26}, [c for c in stand if c[1] == 26]
        while todo:
            x, y = todo.pop()
            for c in stand:
                if c not in reach and 0 <= y - c[1] <= 4 and abs(c[0] - x) <= 6 or (c not in reach and c[1] > y and abs(c[0] - x) <= 6):
                    reach.add(c)
                    todo.append(c)
        bridge = sorted(x for x, y in reach if y <= 21 and 26 <= x <= 34)
        t.check("nizhalattam: in the boss room, rails a jump apart reach a bridge above Veeran's head",
                len(bridge) >= 6, bridge)

        # The Aasaan's box sells repairs for oil: the double jump, from the next run.
        r, got = story('run.data.oil = 30 at(7, 208)',
                       'if f == 10 then i.door = true end if f == 20 then i.down_p = true end if f == 30 then i.jump = true end '
                       'if f == 40 then i.attack = true end',
                       'if f == 50 then dbg("bought", run.data.oil, run.data.repairs.r_double, tostring(k.double)) '
                       '  run.begin(body) dbg("next", tostring(k.double)) end', frames=60)
        t.check("nizhalattam: at the Aasaan's box oil buys the double jump, which takes hold from the next run",
                got.get("bought") == ["5", "1", "false"] and got.get("next") == ["true"], got)

        en = set(re.findall(r"^  (\w+) =", open(os.path.join(ROOT, "examples", "nizhalattam", "lines_en.lua")).read(), re.M))
        ta = set(re.findall(r"^  (\w+) =", open(os.path.join(ROOT, "examples", "nizhalattam", "lines_ta.lua")).read(), re.M))
        t.check("nizhalattam: every line is there in Tamil and in English", en == ta and len(en) > 30, en ^ ta)
        # each story's own words, in its rooms' file: the same keys in both languages
        uneven = {}
        for name in sorted(os.listdir(os.path.join(ROOT, "examples", "nizhalattam"))):
            if name.startswith("rooms_") and name.endswith(".lua"):
                text = open(os.path.join(ROOT, "examples", "nizhalattam", name)).read()
                langs = {lang: set(re.findall(r"^    (\w+) =", body, re.M))
                         for lang, body in re.findall(r"^  (en|ta) = \{\n(.*?)^  \},", text, re.M | re.S)}
                if not langs.get("en") or langs.get("en") != langs.get("ta"):
                    uneven[name] = langs
        t.check("nizhalattam: every story's own words are there in Tamil and in English", not uneven, uneven)

        # The music: a track for the title, the Courtyard, each story, the
        # bosses, the King and the endings; a room plays its own (a boss's
        # room the bosses'), each coming in over the last
        r, got = story('local function play(room, from) rooms.enter(room, from, body) return rooms.playing end '
                       'dbg("tracks", rooms.playing, play("s1.ooru", "map.ooru"), play("boss.ooru", "s7.ooru"), play("f1.ooru"), '
                       '  play("k1.ooru"), play("b1.ooru"), play("m1.ooru"), play("p1.ooru"), play("pboss.ooru"), play("p7.ooru"), '
                       '  play("tear.ooru"))', "", "", frames=3)
        r2, got2 = story("", "", 'if f == 2 then dbg("title", rooms.playing) end', frames=3, title=True)
        t.check("nizhalattam: each place plays its track, a boss's room the bosses', the King's his own, the title its own",
                got.get("tracks") == ["1", "2", "8", "3", "4", "5", "6", "7", "8", "9", "1"] and got2.get("title") == ["0"],
                f"{got} {got2} {r.err[-300:]} {r2.err[-300:]}")

        # Challenge rooms, behind the secret door in each story's stall room:
        # built from the run's seed and the Jester's skills. Every room can
        # be crossed with the skills he has; and each skill he has is needed
        # in it (without it, no way through)
        dump = ('local function dump(tag) local w, h = map.size() for y = 0, h - 1 do local r = {} for x = 0, w - 1 do '
                'local f = map.flags(map.get(0, x, y)) r[#r + 1] = f & 1 ~= 0 and "#" or f & 2 ~= 0 and "=" or "." end '
                'dbg(tag .. string.format("%02d", y), table.concat(r)) end '
                'dbg(tag .. "at", rooms.chest_x // 8, rooms.floor_y // 8 - 1, (k.x + 5) // 8, (k.y + k.h) // 8 - 1) end ')
        setup = dump + 'run.start(body, { "forest" }, "palace") '
        cases = []
        for place, stall in (("screen", "s6"), ("forest", "f4"), ("sea", "k4"), ("flags", "b4"), ("masks", "m4"), ("palace", "p4")):
            for seed in (11, 4242):
                for skills in range(8):
                    dj, wj, d2 = bool(skills & 1), bool(skills & 2), bool(skills & 4)
                    tag = f"{place}{seed}_{skills}_"
                    cases.append((tag, dj, wj, d2))
                    setup += (f'run.seed = {seed} k.double, k.walljump, k.second = {str(dj).lower()}, {str(wj).lower()}, {str(d2).lower()} '
                              f'rooms.enter("{stall}.ooru", nil, body) rooms.enter("challenge.ooru", "{stall}.ooru", body) dump("{tag}") ')
        r, got = story(setup, "", "", frames=2)
        bad = []
        for tag, dj, wj, d2 in cases:
            rows = [got.get(f"{tag}{y:02d}", [""])[0] for y in range(30)]
            at = [int(v) for v in got.get(tag + "at", ["0", "0", "0", "0"])]
            if not all(rows):
                bad.append((tag, "no room"))
                continue
            goal, start = (at[0], at[1]), (at[2], at[3])
            up, across = (6, 10) if dj else (3, 7)
            if not challenge_passable(rows, start, goal, up, across, wj, d2):
                bad.append((tag, "cannot be crossed with its skills"))
            for has, without in ((dj, dict(up=3, across=7, wall=wj, dodge=d2)), (wj, dict(up=up, across=across, wall=False, dodge=d2)),
                                 (d2, dict(up=up, across=across, wall=wj, dodge=False))):
                if has and challenge_passable(rows, start, goal, **without):
                    bad.append((tag, "crossed without a skill it should ask for"))
        t.check("nizhalattam: each challenge room can be crossed with the Jester's skills, and asks for every one he has",
                r.code == 0 and not bad, f"{bad[:8]} {r.err[-300:]}")

        # and played, with the real body: up the shaft with wall jumps, and
        # across the roofed pit with two rolls; not without them
        # (the room is built for the skill; played with it, or with it taken away)
        enter = ('run.start(body, {{ "forest" }}, "palace") run.seed = {seed} '
                 'k.double, k.walljump, k.second, k.spare = false, {wj} ~= nil, {d2} ~= nil, {d2} ~= nil '
                 'rooms.enter("f4.ooru", nil, body) rooms.enter("challenge.ooru", "f4.ooru", body) '
                 'k.walljump, k.second, k.spare = {wj} == true, {d2} == true, {d2} == true ')
        played = {}
        for seed in (11, 4242, 7):
            for wj in ("true", "false"):
                r, got = story(enter.format(seed=seed, wj=wj, d2="nil") +
                               'local a = rooms.shop.shaft_at st.top = a[3] at(a[1], (a[2] + 1) * 8) st.dir = 1',
                               'k.health = 100 if k.wall ~= 0 then i.jump = true st.dir = -k.wall end '
                               'if k.ground and f > 5 and (k.y + k.h) // 8 > st.top + 1 then i.jump = true st.dir = 1 end '
                               'i.right, i.left, i.a = st.dir > 0, st.dir < 0, true',
                               'if not st.up and k.ground and (k.y + k.h) // 8 - 1 <= st.top then st.up = f end '
                               'if f == 600 then dbg("up", tostring(st.up ~= nil)) end', frames=602)
                played[f"shaft {seed} {wj}"] = got.get("up", ["?"])[0]
            for d2 in ("true", "false"):
                r, got = story(enter.format(seed=seed, wj="nil", d2=d2) +
                               'local a = rooms.shop.tunnel_at st.a = a at(a[1], (a[2] + 1) * 8)',
                               'k.health = 100 i.right = true '
                               'if not st.go and (k.x + k.w) // 8 >= st.a[1] + 3 then st.go = f end '
                               'if st.go and f < st.go + 60 and k.dodge == 0 and (st.n or 0) < 2 then i.dodge = true end '
                               'if k.dodge == 17 then st.n = (st.n or 0) + 1 end',
                               'if not st.across and (k.x + 5) // 8 >= st.a[3] and k.ground then st.across = f end '
                               'if f == 150 then dbg("across", tostring(st.across ~= nil)) end', frames=152)
                played[f"tunnel {seed} {d2}"] = got.get("across", ["?"])[0]
        t.check("nizhalattam: a challenge room's shaft is climbed with wall jumps and its roofed pit crossed with two rolls, not without",
                all(v == ("true" if k.endswith("true") else "false") for k, v in played.items()), played)

        # the chest: oil, mai or a charm, once a run; in hard mode, while the
        # story's page is not found, the page alone (and not where it lay);
        # the shadows of a challenge room leave nothing when torn
        go = ('run.start(body, {{ "forest" }}, "palace") run.data.king = {hard} k.double = true '
              'rooms.enter("k4.ooru", nil, body) rooms.enter("challenge.ooru", "k4.ooru", body) ')
        r, got = story(go.format(hard="false") +
                       'st.oil, st.mai, st.c = run.data.oil, fight.mai, #run.charms '
                       'local a, b = rooms.shop.open() local again = rooms.shop.open() '
                       'dbg("chest", a, tostring(again), run.data.oil - st.oil + fight.mai - st.mai + #run.charms - st.c > 0, '
                       '  tostring(shadows.nodrop), #run.data.pages) '
                       'rooms.enter("k5.ooru", nil, body) dbg("lying", tostring(rooms.page_x ~= nil))', "", "", frames=3)
        r2, got2 = story(go.format(hard="true") +
                         'st.oil, st.mai, st.c = run.data.oil, fight.mai, #run.charms '
                         'local a, b = rooms.shop.open() '
                         'dbg("chest", a, table.concat(run.data.pages, ","), run.data.oil - st.oil + fight.mai - st.mai + #run.charms - st.c) '
                         'rooms.enter("k5.ooru", nil, body) dbg("lying", tostring(rooms.page_x ~= nil))', "", "", frames=3)
        t.check("nizhalattam: a challenge chest gives oil, mai or a charm once; in hard mode the story's page alone; its shadows drop nothing",
                got.get("chest") == ["say", "nil", "true", "true", "0"] and got.get("lying") == ["true"]
                and got2.get("chest") == ["card", "sea", "0"] and got2.get("lying") == ["false"],
                f"{got} {got2} {r.err[-300:]} {r2.err[-300:]}")

        # fallen in a challenge room, the run goes on: he is back at the
        # secret door with the health he went in with
        r, got = story('run.start(body, { "forest" }, "palace") k.double = true rooms.enter("b4.ooru", nil, body) k.health = 64 '
                       'rooms.enter("challenge.ooru", "b4.ooru", body) st.falls = run.data.falls fight.mai = 33', "",
                       'if f == 3 then k.health = 0 end '
                       'if f == 6 then dbg("back", rooms.name, k.health, (k.x + 5) // 8, (k.y + k.h) // 8, run.data.falls - st.falls, '
                       '  tostring(run.seed ~= nil), fight.mai) end', frames=8)
        t.check("nizhalattam: fallen in a challenge room, the Jester is back at its secret door with the health he took in; the run goes on",
                got.get("back") == ["b4.ooru", "64", "34", "20", "0", "true", "33"], f"{got} {r.err[-300:]}")

        # the Courtyard has one way into the stories, the theatre's screen (no
        # side door to the test rooms); standing at a way in, it glows and
        # the button shows (rooms.at_entry): at a door, at the box, not between
        r, got = story('dbg("doors", #rooms.def().doors, rooms.def().doors[1]) '
                       'local function at(cx) body.place(cx * 8 + 4, 208) k.ground = true return tostring(rooms.at_entry(k) ~= nil) end '
                       'dbg("entry", at(34), at(7), at(20))', "", "", frames=3)
        t.check("nizhalattam: the Courtyard's one door is the theatre's screen; a way in glows, with its button, only while he stands at it",
                got.get("doors") == ["1", "s1.ooru"] and got.get("entry") == ["true", "true", "false"], f"{got} {r.err[-300:]}")

        # sound effects: each thing done has its own (sound.lua names them)
        heard = ('local N = require("sound").N local named = {} for k, v in pairs(N) do named[v] = k end '
                 'sfx = function(n) st.heard = st.heard or {} st.heard[named[n]] = true end ')
        r, got = story(heard + 'rooms.enter("s2.ooru", "s1.ooru", body) at(16, 208) k.face = 1 '
                       'for _, s in ipairs(shadows.list) do if s.kind == "dummy" then s.hp = 1 end end',
                       'if f == 5 then i.jump = true end if f >= 5 and f < 30 then i.a = true end '
                       'if f >= 60 and f % 14 == 0 then i.attack = true end '
                       'if f == 200 then i.dodge = true end',
                       'if f == 260 then rooms.enter("boss.ooru", "s7.ooru", body) at(8, 208) end '
                       'if f == 480 then local h = {} for k in pairs(st.heard or {}) do h[#h + 1] = k end table.sort(h) '
                       '  dbg("heard", table.concat(h, ",")) end', frames=482)
        heard_ = set(got.get("heard", [""])[0].split(","))
        t.check("nizhalattam: jumping, landing, blows landing, tearing, dodging and a boss getting ready each have their sound",
                {"jump", "land", "slap", "hit", "torn", "dodge", "warn"} <= heard_, f"{got} {r.err[-300:]}")

        # the whole game, its music packed (once: a minute's work): eleven
        # tracks of 44.1 kHz stereo, squeezed; a story's track and a boss's
        # coming in over it stay inside the 6 MB a game may hold
        # (the songs are in git, their WAVs are not: until they are made,
        # with Isai or tools/pattarai/make-wavs.mjs, skipped)
        music = os.path.join(ROOT, "examples", "nizhalattam", "music")
        songs = sorted(f for f in os.listdir(music) if f.endswith(".json")) if os.path.isdir(music) else []
        if not songs or not all(os.path.exists(os.path.join(music, f[:-5] + ".wav")) for f in songs):
            t.skipped += 1
            print("  SKIP  nizhalattam: its music (the songs' WAVs are not made: "
                  "node tools/pattarai/make-wavs.mjs examples/nizhalattam)")
        else:
            with tempfile.TemporaryDirectory() as tmp:
                folder = os.path.join(tmp, "n")
                shutil.copytree(os.path.join(ROOT, "examples", "nizhalattam"), folder)
                with open(os.path.join(folder, "main.lua"), "a") as f:
                    f.write('\nrequire("title").skip = 1\nlocal body, rooms = require("body"), require("rooms")\nlocal up = update\n'
                            'function update(dt) local f = stat("frame") if f == 2 then rooms.enter("s5.ooru", "s4.ooru", body) end '
                            'if f == 100 then rooms.enter("boss.ooru", "s7.ooru", body) end up(dt) '
                            'local a = stat("active") if a > (_G.most or 0) then _G.most = a end '
                            'if f == 200 then dbg("active", _G.most) end end\n')
                data = pulli.build(folder)
                clips = pulli.read_bank(dict(pulli.parse(data))["music.isai"])
                r = t.run_package(data, frames=205)
            active = {l.split("\t")[0]: l.split("\t")[1:] for l in r.lines if "\t" in l}.get("active", ["99999"])
            t.check("nizhalattam: its music is eleven squeezed 44.1 kHz stereo loops of 30 to 41 s, and playing it the game stays in its 6 MB",
                    len(clips) == 11 and all(c[0] == 44100 and c[1] == 2 and c[4] == 1 and 30 * 44100 <= c[2] <= 41 * 44100 for c in clips)
                    and r.code == 0 and float(active[0]) < 6144, f"{[(c[0], c[1], c[2] // 44100, c[4]) for c in clips]} {active} {r.err[-300:]}")

        # In the console's bytes (SPEC §10 item 31); the heap is 256 KB.
        r, got = story("", "",
                       'if f == 30 then collectgarbage() dbg("hub", stat("mem")) rooms.enter("boss.ooru", "s7.ooru", body) end '
                       'if f == 60 then collectgarbage() dbg("boss", stat("mem")) fight.lend("veeran") rooms.enter("f5.ooru", "f4.ooru", body) end '
                       'if f == 90 then collectgarbage() dbg("forest", stat("mem")) rooms.enter("fboss.ooru", "f6.ooru", body) end '
                       'if f == 120 then collectgarbage() dbg("vil", stat("mem")) fight.lend("vil") rooms.enter("k6.ooru", "k5.ooru", body) end '
                       'if f == 150 then collectgarbage() dbg("sea", stat("mem")) rooms.enter("kboss.ooru", "k6.ooru", body) end '
                       'if f == 180 then collectgarbage() dbg("aatta", stat("mem")) fight.give_up("veeran", "aattakkaari") '
                       '  rooms.enter("b6.ooru", "b5.ooru", body) end '
                       'if f == 210 then collectgarbage() dbg("field", stat("mem")) rooms.enter("bboss.ooru", "b6.ooru", body) end '
                       'if f == 240 then collectgarbage() dbg("elephant", stat("mem")) fight.give_up("vil", "yaanai") '
                       '  rooms.enter("m6.ooru", "m5.ooru", body) end '
                       'if f == 270 then collectgarbage() dbg("market", stat("mem")) rooms.enter("mboss.ooru", "m6.ooru", body) end '
                       'if f == 300 then collectgarbage() dbg("minister", stat("mem")) fight.give_up("aattakkaari", "mandhiri") '
                       '  rooms.enter("p6.ooru", "p5.ooru", body) end '
                       'if f == 330 then collectgarbage() dbg("palace", stat("mem")) rooms.enter("pboss.ooru", "p6.ooru", body) end '
                       'if f == 360 then collectgarbage() dbg("queen", stat("mem")) fight.give_up("yaanai", "rani") '
                       '  run.data.saved = { "veeran", "vil", "aattakkaari", "yaanai", "mandhiri", "rani" } rooms.enter("p9.ooru", "p8.ooru", body) end '
                       'if f == 390 then collectgarbage() dbg("king", stat("mem")) run.data.saved = {} '
                       '  run.begin(body) rooms.enter("map.ooru", nil, body) end '
                       'if f == 420 then collectgarbage() dbg("after", stat("mem")) end', frames=430)
        hub, bossroom, forestroom, vilroom, searoom, aattaroom, fieldroom, elephantroom, marketroom, ministerroom, \
            palaceroom, queenroom, kingroom, after = (
                float(got.get(k, ["999"])[0]) for k in ("hub", "boss", "forest", "vil", "sea", "aatta", "field", "elephant",
                                                        "market", "minister", "palace", "queen", "king", "after"))
        t.check("nizhalattam: the Lua heap stays within its budget in every story, and a story's code is let go after it",
                hub < 143 and bossroom < 144 and forestroom < 149 and vilroom < 153 and searoom < 164 and aattaroom < 158
                and fieldroom < 161 and elephantroom < 158 and marketroom < 158 and ministerroom < 163
                and palaceroom < 167 and queenroom < 164 and kingroom < 171
                # back in the Courtyard, no story's code stays (Lua's string table may have grown once: a few KB)
                and after < hub + 7, got)

        if t.update:
            with open(path, "w") as f:
                f.writelines(f"{k} {v}\n" for k, v in seen.items())
            print("  ....  wrote tests/examples.sha256")

    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
