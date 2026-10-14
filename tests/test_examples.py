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
        ("pong",  3600,   "a",            None),                  # a whole match; the console wins
        ("pong",  3600,   "up",           "a@5"),
        ("pong",  3600,   "x",            "down@1,a@5"),          # two players
        ("walk",  120,    None,           None),                  # waits on the title screen
        ("walk",  300,    None,           "a@5"),                 # sprites, a map from Tiled, music
        ("walk",  600,    "right,down",   "a@5"),                 # walks until a wall stops it
        ("walk",  3000,   None,           "a@5,a@2900"),          # runs out of time, then tries again
        ("talk",  120,    "right",        None),                  # the SDK helpers; the camera follows
        ("catch", 900,    "right",        "a@30")]                # the tutorial's game, played until it is lost

# Talk: walk to the villager and press A. They greet you (read it), ask
# (wait for the question to appear), you answer yes, read the reply, and
# the gem flies to the bag.
TALK_TAPS = "right@1-296,a@330,a@340,a@350,a@450,a@510"
TALK_ASKED, TALK_FLYING, TALK_FRAMES = 430, 516, 600

WALK_START = 5          # the frame on which A leaves Walk's title screen; it also seeds the scattering


def walk_gems(fb, package):
    """Where Walk has scattered the gems, read off a picture of level 1.
    That level is one screen, so a tile's place on the map is its place on
    the screen. The game scatters them at random; this is how the test
    learns where they went."""
    sheet = dict(pulli.parse(package))["sprites.kolam"]
    width = struct.unpack("<H", sheet[4:6])[0]
    gem = [sheet[8 + (6 // (width // 8) * 8 + y) * width + 6 % (width // 8) * 8 + x]
           for y in range(8) for x in range(8)]                    # the gem is sprite 6
    return {(tx, ty) for ty in range(2, 30) for tx in range(40)
            if all(not c or fb[(ty * 8 + i // 8) * 320 + tx * 8 + i % 8] == c for i, c in enumerate(gem))}


def walk_route(gems, first_frame):
    """Button presses that walk Walk's level 1 and pick up every gem: the
    nearest gem each time, by the shortest way round the walls. Returns the
    presses for --tap and the frame on which the last gem is taken."""
    from collections import deque
    path = os.path.join(ROOT, "examples", "walk", "level1.tmx")
    w, h, layers, flags = pulli.read_ooru(pulli.ooru_from_tmx(path, 8))
    ground, things = ([c & pulli.TILE_MAX for c in layer] for layer in layers)
    solid = lambda x, y: ground[y * w + x] < len(flags) and flags[ground[y * w + x]] & 1
    at = divmod(things.index(8), w)[::-1]                          # the player's tile on the sheet is 8
    gems = set(gems)
    moves = []
    while gems:
        came, todo, goal = {at: None}, deque([at]), None
        while todo and goal is None:
            x, y = todo.popleft()
            for step, nxt in (("right", (x + 1, y)), ("left", (x - 1, y)), ("down", (x, y + 1)), ("up", (x, y - 1))):
                if nxt not in came and not solid(*nxt):
                    came[nxt] = ((x, y), step)
                    todo.append(nxt)
                    if nxt in gems:
                        goal = nxt
                        break
        leg, node = [], goal
        while came[node]:
            node, step = came[node]
            leg.append(step)
        moves += leg[::-1]
        gems.discard(goal)
        at = goal
    taps, frame = [], first_frame                                  # a tile is 8 pixels, a pixel a frame
    for i, step in enumerate(moves):
        if i and moves[i - 1] == step:
            taps[-1][2] += 8
        else:
            taps.append([step, frame, frame + 7])
        frame += 8
    return ",".join(f"{b}@{a}-{z}" for b, a, z in taps), frame - 1

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

        # Walk scatters its gems at random, seeded by the frame on which A
        # is pressed on the title screen.
        walk = pulli.build(os.path.join(ROOT, "examples", "walk"))
        begin = f"a@{WALK_START}"
        look = lambda tap: walk_gems(t.run_package(walk, frames=40, tap=tap).fb, walk)
        gems = look(begin)
        t.check("walk: level 1 starts with its 8 gems, scattered the same way for the same start",
                len(gems) == 8 and look(begin) == gems, sorted(gems))
        t.check("walk: starting at another moment scatters them differently",
                len(look("a@6")) == 8 and len({frozenset(look(f"a@{n}")) for n in (5, 6, 17, 30)}) == 4)

        # Pause: START freezes the level and START again carries on, to the
        # same picture a run with no pause reaches.
        plain = t.run_package(walk, frames=300, hold="right,down", tap=begin)
        held = t.run_package(walk, frames=150, hold="right,down", tap=f"{begin},start@100")
        resumed = t.run_package(walk, frames=360, hold="right,down", tap=f"{begin},start@100,start@160")
        t.check("walk: START pauses and START again carries on where it left off",
                plain.code == 0 and held.fb != t.run_package(walk, frames=150, hold="right,down", tap=begin).fb
                and resumed.fb == plain.fb, plain.err)
        # The music is the same in both, so any difference in the frame
        # where START is pressed is the pause tone.
        pressed = t.run_package(walk, frames=105, tap=f"{begin},start@100", sound=True).sound[99 * 735:]
        unpressed = t.run_package(walk, frames=105, tap=begin, sound=True).sound[99 * 735:]
        t.check("walk: pausing plays a tone", pressed != unpressed and pressed[:735] != unpressed[:735])
        # While paused the tune is still: the only sound in the following second is silence.
        waiting = t.run_package(walk, frames=220, tap=f"{begin},start@100", sound=True).sound
        t.check("walk: the music stops while the game is paused", max(abs(s) for pair in waiting[130 * 735:] for s in pair) == 0)
        later = t.run_package(walk, frames=260, tap=f"{begin},start@100,start@200", sound=True).sound
        t.check("walk: the music carries on when the game is", max(abs(s) for pair in later[230 * 735:] for s in pair) > 0)

        # Level 1: follow a route to every gem, then press A for level 2.
        # The pictures are compared with a run that does not press A, and
        # the sound with silence, so this fails if the level did not end.
        taps, last = walk_route(gems, WALK_START + 1)
        taps = f"{begin},{taps}"
        cleared = t.run_package(walk, frames=last + 90, tap=taps, sound=True)
        onward = t.run_package(walk, frames=last + 90, tap=f"{taps},a@{last + 30}", sound=True)
        idle = t.run_package(walk, frames=last + 90, tap=begin, sound=True)
        ok = t.check("walk: a route to every gem runs without error",
                     cleared.code == 0 and onward.code == 0 and idle.code == 0, cleared.err + onward.err)
        if ok:
            quiet = lambda r, n: max(abs(s) for pair in r.sound[-n:] for s in pair) == 0
            t.check("walk: music plays during a level and stops when the level is cleared",
                    not quiet(idle, 735) and quiet(cleared, 735) and not quiet(cleared, 80 * 735))
            t.check("walk: pressing A after clearing a level starts the next one, with its music",
                    onward.fb != cleared.fb and not quiet(onward, 735))
            seen["walk level 1 cleared"] = hashlib.sha256(cleared.fb + cleared.rgb).hexdigest()
            seen["walk level 2 reached"] = hashlib.sha256(onward.fb + onward.rgb).hexdigest()
            if not t.update:
                for key in ("walk level 1 cleared", "walk level 2 reached"):
                    t.check(f"{key}: draws what it drew before", seen[key] == pinned.get(key),
                            "behaviour changed; if that was intended, rerun with --update")

        # Talk uses all six SDK helpers and keeps none of them in its own
        # folder: packing it supplies them.
        talk_dir = os.path.join(ROOT, "examples", "talk")
        t.check("talk: packing supplies the helpers it requires",
                {"tween.lua", "camera_follow.lua", "inventory.lua", "dialog.lua", "quest.lua", "particles.lua"}
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
