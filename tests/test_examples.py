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
import hashlib, os, struct, sys, tempfile

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


def manickam_variant(tmp, chapter, every=False):
    """Manickam, changed to start straight in a chapter, and, with `every`,
    to load all of its modules first: the most Lua memory the game can need,
    as a player who goes through it all in one sitting ends up with every
    chapter loaded."""
    import shutil
    folder = os.path.join(tmp, "manickam")
    shutil.copytree(MANICKAM, folder, ignore=shutil.ignore_patterns("music", "sfx"))
    main = open(os.path.join(folder, "main.lua")).read()
    main = main.replace('core.go("title")', f'core.go("play", {chapter})')
    if every:
        main = main.replace('require("title")', 'require("title")\nfor _, m in ipairs({ "opening", "ch0", "ch1", "ch2", '
                            '"ch3", "ch4", "ch5", "ch6" }) do require(m) end')
    open(os.path.join(folder, "main.lua"), "w").write(main)
    return pulli.build(folder)


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
        runs = [t.run_package(game, frames=1830, tap="select@5,a@10") for _ in range(2)]
        lines = [[l for l in r.lines if l.startswith("bench ") and "frames=" in l] for r in runs]
        t.check("manickam: the benchmark runs its scenes and reports each, the same every run",
                all(r.code == 0 for r in runs) and len(lines[0]) >= 3 and lines[0] == lines[1]
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

        # Every chapter loads its map and region and plays a while, in both
        # languages; and the worst case for memory, every module loaded with
        # the festival's fireworks going, fits in the Lua heap.
        with tempfile.TemporaryDirectory() as tmp:
            for ch in range(7):
                r = t.run_package(manickam_variant(os.path.join(tmp, str(ch)), ch), frames=400,
                                  tap="a@100,a@160,a@220,a@280,right@300-400")
                t.check(f"manickam: chapter {ch} starts and plays", r.code == 0 and f"chapter {ch}" in r.lines, r.err[-300:])
            reads = ",".join(f"a@{f}" for f in range(200, 1000, 60))
            r = t.run_package(manickam_variant(os.path.join(tmp, "all"), 6, every=True), frames=2400, tap=reads)
            t.check("manickam: with every chapter loaded, the festival and its fireworks fit in memory",
                    r.code == 0, r.err[-300:])

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
