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
import hashlib, os, sys, tempfile

from harness import Suite, ROOT, TESTS, pulli

#        example  frames  held buttons    taps (button@frame)
RUNS = [("hello", 120,    None,           None),
        ("hello", 120,    "right,down,a", None),
        ("pong",  600,    None,           None),                  # sits on the menu
        ("pong",  3600,   "a",            None),                  # a whole match; the console wins
        ("pong",  3600,   "up",           "a@5"),
        ("pong",  3600,   "x",            "down@1,a@5"),          # two players
        ("walk",  300,    None,           None),                  # sprites and a map from Tiled
        ("walk",  600,    "right,down",   None),                  # walks until a wall stops it
        ("walk",  900,    "down",         None),                  # walks over a gem and takes it
        ("walk",  1500,   "right",        None),                  # a slime sees the player and closes in
        ("walk",  7300,   None,           "a@7000")]              # stands still, loses to the slimes, plays again

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
