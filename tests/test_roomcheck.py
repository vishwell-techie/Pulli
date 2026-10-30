#!/usr/bin/env python3
"""Room layouts: tools/roomcheck.py finds what a player cannot reach.

Run: python3 tests/test_roomcheck.py
"""
import os, subprocess, sys, tempfile

from harness import Suite, pulli

sys.path.insert(0, os.path.dirname(pulli.__file__))
import roomcheck   # noqa: E402

TOOL = os.path.join(os.path.dirname(pulli.__file__), "roomcheck.py")


def room(*rows):
    return [r.ljust(20, ".") for r in rows]


def main():
    t = Suite("Room layouts: tools/roomcheck.py")
    up = lambda n: room(*([""] * (9 - n)), "........====", *([""] * (n - 2)), "S.........D", "#" * 20)

    t.check("a ledge 4 tiles up is reached", roomcheck.check(up(4)) == [], roomcheck.check(up(4)))
    e = roomcheck.check(up(5))
    t.check("one 5 tiles up is not", e == ["no ledge on row 4 can be reached"], e)
    t.check("... unless the jump is higher", roomcheck.check(up(5), jump=5) == [])

    gap = room("", "", "", "", "S...............D", "#####......#########")
    t.check("a floor beyond a gap of 6 is reached", roomcheck.check(gap) == [], roomcheck.check(gap))
    far = room("", "", "", "", "S...............D", "#####........#######")
    e = roomcheck.check(far)
    t.check("one beyond a gap of 8 is not, and the pit is no floor", e == ["door at (16,4) cannot be reached"], e)

    roof = room("", "", "", "############", "", "", "....====....", "", "", "S...........D", "#" * 20)
    e = roomcheck.check(roof)
    t.check("a ledge under a low roof is reached; a thin ledge is jumped up through",
            e == [], e)

    e = roomcheck.check(room("", "", "", "", "", "....########", "", "S..........D", "#" * 20))
    t.check("a passage two tiles high is rolled through", e == [], e)
    e = roomcheck.check(room("", "", "", "", "", "", "....########", "S..........D", "#" * 20))
    t.check("one tile high is not", any("door" in m for m in e), e)

    e = roomcheck.check(room("", "", "S.........D", "", "#" * 20))
    t.check("a marker in mid-air is reported, and counted where it would land",
            e == ["S at (0,2) has nothing under it", "D at (10,2) has nothing under it"], e)
    e = roomcheck.check(room("", "..........D", "#" * 20))
    t.check("a room without a start says so", e == ["0 starts (S); a room needs one"], e)

    text = ("Intro\nR01 — Courtyard\nGrid (3 rows):\n" + "\n".join(up(4)) + "\n\nR02 — Up\n"
            + "\n".join(up(5)) + "\n")
    found = roomcheck.rooms(text)
    t.check("rooms are found by their R-number line, each with its grid",
            [(n.split()[0], len(g)) for n, g in found] == [("R01", 10), ("R02", 10)], found)
    with tempfile.TemporaryDirectory() as d:
        f = os.path.join(d, "rooms.txt")
        open(f, "w", encoding="utf-8").write(text)
        r = subprocess.run([sys.executable, TOOL, f], capture_output=True, text=True)
        t.check("from the command line: each room PASS or FAIL, and 1 when one fails",
                r.returncode == 1 and "PASS  R01" in r.stdout and "FAIL  R02" in r.stdout
                and "1 of 2 rooms pass" in r.stdout, r.stdout)
    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
