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
            extra = pre + ('local body, shadows, fight, rooms = require("body"), require("shadows"), require("fight"), require("rooms")\n'
                     'local up, i0 = update, {}\n'
                     f'local function at(cx, feet) body.place(cx * 8 + 5, feet) end\n'
                     f'local st = {{}}\n'
                     f'function body.read() local k, f, s = body.k, stat("frame"), shadows.list[1] local i = {{ swap = 0 }}\n{read}\n return i end\n'
                     f'function update(dt) if stat("frame") == 1 then rooms.enter("test.ooru", nil, body) fight.wear({{ "komali", "veeran" }}) {place} end up(dt) local k, f = body.k, stat("frame")\n{report}\nend\n')
            with tempfile.TemporaryDirectory() as tmp:
                folder = os.path.join(tmp, "n")
                shutil.copytree(os.path.join(ROOT, "examples", "nizhalattam"), folder)
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
                got.get("up") == ["176", "true"] and got.get("down") == ["208", "true"], got)

        r, got = komali("wall", "at(70, 80)", "i.left = true",
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
                 'ready["map.ooru"], ready["sprites.kolam"] = true, true\n'
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
        def story(setup, read, report, frames=300, pre=""):
            extra = pre + ('local body, shadows, fight, rooms = require("body"), require("shadows"), require("fight"), require("rooms")\n'
                           'local run, stall, lines = require("run"), require("stall"), require("lines")\n'
                           'local up, st = update, {}\n'
                           'local function at(cx, feet) body.place(cx * 8 + 5, feet) end\n'
                           f'function body.read() local k, f = body.k, stat("frame") local i = {{ swap = 0 }}\n{read}\n return i end\n'
                           f'function update(dt) local k, f = body.k, stat("frame") if f == 1 then {setup} end up(dt)\n{report}\nend\n')
            with tempfile.TemporaryDirectory() as tmp:
                folder = os.path.join(tmp, "n")
                shutil.copytree(os.path.join(ROOT, "examples", "nizhalattam"), folder)
                with open(os.path.join(folder, "main.lua"), "a") as f:
                    f.write("\n" + extra)
                r = t.run_package(pulli.build(folder), frames=frames)
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
                       'if f == 60 then dbg("bought", k.health, fight.mai, table.concat(run.charms, ","), tostring(run.sharp.Komali), tostring(stall.is_open())) end', frames=70)
        t.check("nizhalattam: at the stall mai buys mending, a sharper role, and charms; B leaves",
                got.get("bought") == ["85", "130", "bell,spool", "true", "false"], got)

        r, got = story('rooms.enter("s6.ooru", "s5.ooru", body) at(20, 208) fight.mai, k.health = 10, 60',
                       'if f == 10 then i.door = true end if f == 15 then i.jump = true end',
                       'if f == 30 then dbg("poor", k.health, fight.mai) end', frames=40)
        t.check("nizhalattam: without the mai, nothing is bought",
                got.get("poor") == ["60", "10"], got)

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

        r, got = story('rooms.enter("boss.ooru", "s7.ooru", body)', "if f == 140 then i.door = true end",
                       'if f == 3 then st.oil = run.data.oil local b = shadows.boss b.hp = 1 shadows.strike(b, 5, -1, true) end '
                       'if f == 10 then dbg("lent", #fight.carried, fight.carried[2] and fight.carried[2].name, run.data.oil - st.oil) '
                       '  at(54, 208) end '
                       'if f == 380 then dbg("home", rooms.name, run.data.screen_played, #fight.carried, fight.mai) end', frames=390)
        t.check("nizhalattam: Veeran torn lends his role and 8 oil; the door on ends the Screen, back in the Courtyard",
                got.get("lent") == ["2", "Veeran", "8"] and got.get("home") == ["map.ooru", "1", "1", "0"], got)

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

        r, got = story("", "",
                       'if f == 30 then collectgarbage() dbg("hub", stat("mem")) rooms.enter("boss.ooru", "s7.ooru", body) end '
                       'if f == 60 then collectgarbage() dbg("boss", stat("mem")) rooms.enter("map.ooru", nil, body) end '
                       'if f == 90 then collectgarbage() dbg("after", stat("mem")) end', frames=100)
        hub, bossroom, after = (float(got.get(k, ["999"])[0]) for k in ("hub", "boss", "after"))
        t.check("nizhalattam: the Lua heap stays within its budget, and the boss's code is let go after his room",
                hub < 175 and bossroom < 190 and after < bossroom - 3, got)

        if t.update:
            with open(path, "w") as f:
                f.writelines(f"{k} {v}\n" for k, v in seen.items())
            print("  ....  wrote tests/examples.sha256")

    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
