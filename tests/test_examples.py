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
import hashlib, os, shutil, struct, sys, tempfile

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

        if t.update:
            with open(path, "w") as f:
                f.writelines(f"{k} {v}\n" for k, v in seen.items())
            print("  ....  wrote tests/examples.sha256")

    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
