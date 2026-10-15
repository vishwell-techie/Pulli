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
        ("manickam", 300,  None,          "a@5"),                 # sprites, a map from Tiled, music
        ("manickam", 600,  None, "a@5,right@6-600,down@6-600"),   # walks until a wall stops it
        ("manickam", 3000, None,          "a@5,a@2900"),          # runs out of time, then tries again
        ("talk",  120,    "right",        None),                  # the SDK helpers; the camera follows
        ("catch", 900,    "right",        "a@30")]                # the tutorial's game, played until it is lost

# Talk: walk to the villager and press A. They greet you (read it), ask
# (wait for the question to appear), you answer yes, read the reply, and
# the gem flies to the bag.
TALK_TAPS = "right@1-296,a@330,a@340,a@350,a@450,a@510"
TALK_ASKED, TALK_FLYING, TALK_FRAMES = 430, 516, 600
# The same, but answering no: the villager replies, and A closes the box.
TALK_NO_TAPS = "right@1-296,a@330,a@340,a@350,down@440,a@450,a@460,a@470"

GEM_START = 5           # the frame on which A chooses New game on Manickam's title; it also seeds the scattering
OLD = lambda k: (30 + k // 8) * 64 + k % 8      # the gem hunt's 8x8 sprites, in the strip under the title art
SOLID, WATER = 1, 2     # Manickam's tile flags


def sprite_pixels(package, n):
    """Sprite n of a package's sheet, as 64 colours, row by row."""
    sheet = dict(pulli.parse(package))["sprites.kolam"]
    width = struct.unpack("<H", sheet[4:6])[0]
    return [sheet[8 + (n // (width // 8) * 8 + y) * width + n % (width // 8) * 8 + x]
            for y in range(8) for x in range(8)]


def manickam_level(n):
    """Level n of Manickam as (width, ground, things, flags of each ground tile)."""
    path = os.path.join(ROOT, "examples", "manickam", f"level{n}.tmx")
    w, h, layers, flags = pulli.read_ooru(pulli.ooru_from_tmx(path, 64))
    ground, things = ([c & pulli.TILE_MAX for c in layer] for layer in layers)
    return w, ground, things, [flags[t] if t < len(flags) else 0 for t in ground]


def manickam_gems(fb, package):
    """Where Manickam has scattered the gems, read off a picture of level 1.
    That level is one screen, so a tile's place on the map is its place on
    the screen. The game scatters them at random; this is how the test
    learns where they went."""
    gem = sprite_pixels(package, OLD(6))
    return {(tx, ty) for ty in range(2, 30) for tx in range(40)
            if all(not c or fb[(ty * 8 + i // 8) * 320 + tx * 8 + i % 8] == c for i, c in enumerate(gem))}


def player_at(fb, package):
    """The top-left corner of the player's sprite on the screen, found by
    the one colour of the sprite that nothing else on level 1 uses."""
    me = sprite_pixels(package, OLD(8))
    others = {c for n in (1, 2, 3, 4, 5, 6, 7) for c in sprite_pixels(package, OLD(n))}
    mark = next(c for c in me if c and c not in others)
    dx, dy = min(i % 8 for i, c in enumerate(me) if c == mark), min(i // 8 for i, c in enumerate(me) if c == mark)
    seen = [(i % 320, i // 320) for i in range(12 * 320, len(fb)) if fb[i] == mark]
    return min(x for x, _ in seen) - dx, min(y for _, y in seen) - dy


def manickam_route(at, goals, first_frame):
    """Button presses that walk Manickam's level 1, on dry ground, from tile
    `at` to every tile in `goals`: the nearest each time, by the shortest way
    round walls and water. Returns the presses for --tap and the frame on
    which the last goal is reached."""
    from collections import deque
    w, _, _, flags = manickam_level(1)
    blocked = lambda x, y: flags[y * w + x] & (SOLID | WATER)
    goals = set(goals)
    moves = []
    while goals:
        came, todo, goal = {at: None}, deque([at]), None
        while todo and goal is None:
            x, y = todo.popleft()
            for step, nxt in (("right", (x + 1, y)), ("left", (x - 1, y)), ("down", (x, y + 1)), ("up", (x, y - 1))):
                if nxt not in came and not blocked(*nxt):
                    came[nxt] = ((x, y), step)
                    todo.append(nxt)
                    if nxt in goals:
                        goal = nxt
                        break
        leg, node = [], goal
        while came[node]:
            node, step = came[node]
            leg.append(step)
        moves += leg[::-1]
        goals.discard(goal)
        at = goal
    taps, frame = [], first_frame                                  # a tile is 8 pixels, a pixel a frame
    for i, step in enumerate(moves):
        if i and moves[i - 1] == step:
            taps[-1][2] += 8
        else:
            taps.append([step, frame, frame + 7])
        frame += 8
    return ",".join(f"{b}@{a}-{z}" for b, a, z in taps), frame - 1


def manickam_start():
    """The player's tile on level 1."""
    w, _, things, _ = manickam_level(1)
    return divmod(things.index(OLD(8)), w)[::-1]                   # the player's tile

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

        # Manickam scatters its gems at random, seeded by the frame on which
        # A is pressed on the title screen.
        game = pulli.build(os.path.join(ROOT, "examples", "manickam"))
        begin = f"a@{GEM_START}"
        look = lambda tap: manickam_gems(t.run_package(game, frames=40, tap=tap).fb, game)
        gems = look(begin)
        t.check("manickam: level 1 starts with its 8 gems, scattered the same way for the same start",
                len(gems) == 8 and look(begin) == gems, sorted(gems))
        scatterings = [look(f"a@{n}") for n in (5, 6, 17, 30)]
        t.check("manickam: starting at another moment scatters them differently",
                all(len(g) == 8 for g in scatterings) and len({frozenset(g) for g in scatterings}) == 4)
        w1, _, _, flags1 = manickam_level(1)
        t.check("manickam: gems are never scattered into water",
                not any(flags1[y * w1 + x] & WATER for g in scatterings for x, y in g))

        # The title: a menu in Tamil to start with; the language set in the
        # options is kept for next time, as is a game once begun (Continue).
        with tempfile.TemporaryDirectory() as saves:
            fresh = t.run_package(game, frames=20).fb
            t.run_package(game, frames=40, tap="down@5,a@10,a@20,b@30", saves=saves)     # Options, language, back
            english = t.run_package(game, frames=20, saves=saves).fb
            t.check("manickam: the language chosen in the options is kept for next time", english != fresh)
        with tempfile.TemporaryDirectory() as saves:
            t.run_package(game, frames=30, tap=begin, saves=saves)                        # New game
            again = t.run_package(game, frames=20, saves=saves).fb
            t.check("manickam: once a game is begun, the title offers to continue it", again != fresh)
        marked = t.run_package(game, frames=20, tap="select@5").fb
        unmarked = t.run_package(game, frames=20, tap="select@5,select@10").fb
        t.check("manickam: SELECT on the title switches the benchmark on, and again off",
                marked != fresh and unmarked == fresh)
        # The benchmark: a fixed run through three heavy scenes, the same on every
        # machine, reporting each scene through dbg().
        runs = [t.run_package(game, frames=1830, tap="select@5,a@10") for _ in range(2)]
        lines = [[l for l in r.lines if l.startswith("bench ") and "frames=" in l] for r in runs]
        t.check("manickam: the benchmark runs its three scenes and reports each, the same every run",
                all(r.code == 0 for r in runs) and len(lines[0]) == 3 and lines[0] == lines[1]
                and all("frames=600" in l for l in lines[0]), lines[0] + [runs[0].err[-300:]])

        # Pause: START freezes the level and START again carries on, to the
        # same picture a run with no pause reaches.
        walk = lambda n: f"right@6-{n},down@6-{n}"      # after New game, so the title menu does not move
        plain = t.run_package(game, frames=300, tap=f"{begin},{walk(300)}")
        held = t.run_package(game, frames=150, tap=f"{begin},{walk(150)},start@100")
        resumed = t.run_package(game, frames=360, tap=f"{begin},{walk(360)},start@100,start@160")
        t.check("manickam: START pauses and START again carries on where it left off",
                plain.code == 0 and held.fb != t.run_package(game, frames=150, tap=f"{begin},{walk(150)}").fb
                and resumed.fb == plain.fb, plain.err)
        # The music is the same in both, so any difference in the frame
        # where START is pressed is the pause tone.
        pressed = t.run_package(game, frames=105, tap=f"{begin},start@100", sound=True).sound[99 * 735:]
        unpressed = t.run_package(game, frames=105, tap=begin, sound=True).sound[99 * 735:]
        t.check("manickam: pausing plays a tone", pressed != unpressed and pressed[:735] != unpressed[:735])
        # While paused the tune is still: the only sound in the following second is silence.
        waiting = t.run_package(game, frames=220, tap=f"{begin},start@100", sound=True).sound
        t.check("manickam: the music stops while the game is paused", max(abs(s) for pair in waiting[130 * 735:] for s in pair) == 0)
        later = t.run_package(game, frames=260, tap=f"{begin},start@100,start@200", sound=True).sound
        t.check("manickam: the music carries on when the game is", max(abs(s) for pair in later[230 * 735:] for s in pair) > 0)

        # Water: no level makes it solid, so slimes, which stop only at
        # solid tiles, go in after the player.
        t.check("manickam: every level has water, and it is water, not a wall",
                all(any(f & WATER for f in manickam_level(n)[3])
                    and not any(f & WATER and f & SOLID for f in manickam_level(n)[3]) for n in (1, 2, 3)))
        # The player walks to just above the pool on level 1 and holds down
        # into it, then out of the far side and right along the ground.
        # In water they wade at half speed, and stay that slow for three
        # seconds after climbing out.
        pool = next(i for i, f in enumerate(flags1) if f & WATER)
        above = (pool % w1 + 2, pool // w1 - 2)
        t.check("manickam: level 1 has two dry tiles above its pool", not flags1[(above[1] + 1) * w1 + above[0]])
        taps, there = manickam_route(manickam_start(), [above], GEM_START + 1)
        taps = f"{begin},{taps},down@{there + 1}-{there + 90},right@{there + 91}-{there + 400}"
        at = lambda frame: player_at(t.run_package(game, frames=frame, tap=taps).fb, game)
        x0, y0 = at(there)
        _, y1 = at(there + 21)
        _, y2 = at(there + 41)
        t.check("manickam: the player walks into the water", x0 == above[0] * 8 and y0 == above[1] * 8
                and all(flags1[(y + 5) // 8 * w1 + above[0]] & WATER for y in (y1, y2)), (x0, y0, y1, y2))
        t.check("manickam: in water the player wades at half speed", 9 <= y2 - y1 <= 11, y2 - y1)
        slow = at(there + 131)[0] - at(there + 111)[0]
        fast = at(there + 341)[0] - at(there + 321)[0]
        t.check("manickam: just out of the water the player is still slow, and three seconds later is not",
                9 <= slow <= 11 and 19 <= fast <= 21, (slow, fast))

        # Level 1: follow a route to every gem, then press A for level 2.
        # The pictures are compared with a run that does not press A, and
        # the sound with silence, so this fails if the level did not end.
        taps, last = manickam_route(manickam_start(), gems, GEM_START + 1)
        taps = f"{begin},{taps}"
        cleared = t.run_package(game, frames=last + 90, tap=taps, sound=True)
        onward = t.run_package(game, frames=last + 90, tap=f"{taps},a@{last + 30}", sound=True)
        idle = t.run_package(game, frames=last + 90, tap=begin, sound=True)
        ok = t.check("manickam: a route to every gem runs without error",
                     cleared.code == 0 and onward.code == 0 and idle.code == 0, cleared.err + onward.err)
        if ok:
            quiet = lambda r, n: max(abs(s) for pair in r.sound[-n:] for s in pair) == 0
            t.check("manickam: music plays during a level and stops when the level is cleared",
                    not quiet(idle, 735) and quiet(cleared, 735) and not quiet(cleared, 80 * 735))
            t.check("manickam: pressing A after clearing a level starts the next one, with its music",
                    onward.fb != cleared.fb and not quiet(onward, 735))
            seen["manickam level 1 cleared"] = hashlib.sha256(cleared.fb + cleared.rgb).hexdigest()
            seen["manickam level 2 reached"] = hashlib.sha256(onward.fb + onward.rgb).hexdigest()
            if not t.update:
                for key in ("manickam level 1 cleared", "manickam level 2 reached"):
                    t.check(f"{key}: draws what it drew before", seen[key] == pinned.get(key),
                            "behaviour changed; if that was intended, rerun with --update")

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
