#!/usr/bin/env python3
"""roomcheck.py — check room layouts written as text grids.

    python3 tools/roomcheck.py <layouts.txt> [--jump 4] [--gap 6] [--tall 3] [--low 2]

A room starts at a line beginning "R" and a number (R01, R12 ...); its grid
is the run of lines after that, all one length, made only of these tiles:

    . empty   # solid   = thin ledge (stand on, jump up through)
    / \\ | b L F decoration (not solid)
    S start   D door   E enemy   ? secret      (each stands in an empty cell)

The player is --tall tiles high standing and --low tiles rolling, jumps at
most --jump tiles up and crosses at most --gap tiles in a jump, defaults
for Nizhalattam's Jester (10 x 20 px, a 36 px jump). From S it walks, rolls
through low gaps, drops off edges and jumps, and reports every D, E, ? and
thin ledge (=) it cannot reach, and every marker with nothing under it. Jumps are
checked against solid tiles straight up from the take-off and straight
down onto the landing, not along a true arc, so a pass is a good sign, not
a proof: try the room in the game.

Exit status 0 means every room passes, 1 that one does not.
"""
import argparse, re, sys

SOLID, THIN = "#", "="
DECOR = set("/\\|bLF")
MARK = set("SDE?")
TILES = set(".") | set(SOLID + THIN) | DECOR | MARK


def rooms(text):
    """(name, grid) for each room in a layouts file."""
    out, name, grid = [], None, []
    for line in text.splitlines() + [""]:
        s = line.rstrip()
        if re.match(r"^R\d+\b", s) and not grid:
            name = s
            continue
        if name and s and set(s) <= TILES and (not grid or len(s) == len(grid[0])):
            grid.append(s)
            continue
        if name and grid:
            out.append((name, grid))
            name, grid = None, []
    return out


def check(grid, jump=4, gap=6, tall=3, low=2):
    """Problems with one room, as a list of text; empty means it passes."""
    h, w = len(grid), len(grid[0])
    errs = []
    solid = lambda x, y: not (0 <= x < w) or y >= h or (y >= 0 and grid[y][x] == SOLID)
    under = lambda x, y: y + 1 < h and grid[y + 1][x] in (SOLID, THIN)   # below the room is a fall
    clear = lambda x, y, n: all(not solid(x, y - i) for i in range(n))
    stand = lambda x, y: 0 <= x < w and 0 <= y < h and under(x, y) and clear(x, y, tall)
    crawl = lambda x, y: 0 <= x < w and 0 <= y < h and under(x, y) and clear(x, y, low)

    for y, row in enumerate(grid):
        for x, c in enumerate(row):
            if c in MARK and not under(x, y):
                errs.append(f"{c} at ({x},{y}) has nothing under it")
    starts = [(x, y) for y, r in enumerate(grid) for x, c in enumerate(r) if c == "S"]
    if len(starts) != 1:
        errs.append(f"{len(starts)} starts (S); a room needs one")
        return errs

    def land(x, y):
        """Where a fall from (x, y) ends: the first cell with something under it."""
        while y < h - 1 and not under(x, y):
            if solid(x, y + 1):
                return None
            y += 1
        return (x, y) if under(x, y) and crawl(x, y) else None

    on = lambda x, y: (x, y) if under(x, y) else land(x, y)    # a floating marker counts where it lands
    starts = [on(*starts[0]) or starts[0]]
    seen, todo = set(starts), list(starts)
    while todo:
        x, y = todo.pop()
        nxt = []
        for dx in (-1, 1):                                  # walk, roll, or step off an edge
            if 0 <= x + dx < w and clear(x + dx, y, low):
                nxt.append((x + dx, y) if under(x + dx, y) else land(x + dx, y))
        if stand(x, y):                                     # jumps need room to stand
            for dy in range(1, jump + 1):                   # straight up, through thin ledges
                if solid(x, y - dy - tall + 1):
                    break
                top = y - dy
                for tx in range(x - gap - 1, x + gap + 2):     # over `gap` empty tiles
                    if not (0 <= tx < w):
                        continue
                    for ty in range(top, min(h, y + gap * 2)):
                        if solid(tx, ty):
                            break
                        if under(tx, ty) and crawl(tx, ty) and (ty < y or tx != x):
                            nxt.append((tx, ty))
                            break
        for p in nxt:
            if p and p not in seen:
                seen.add(p)
                todo.append(p)

    for y, row in enumerate(grid):
        for x, c in enumerate(row):
            if c in "DE?" and on(x, y) not in seen:
                errs.append(f"{ {'D': 'door', 'E': 'enemy', '?': 'secret'}[c]} at ({x},{y}) cannot be reached")
    ledges, unreached = set(), set()
    for y in range(h - 1):
        for x in range(w):
            if grid[y + 1][x] == THIN and grid[y][x] != THIN:     # the ledges a room offers
                ledges.add(y + 1)
                if (x, y) not in seen and crawl(x, y):
                    unreached.add(y + 1)
    for r in sorted(ledges & unreached):
        if all((x, r - 1) not in seen for x in range(w)):
            errs.append(f"no ledge on row {r} can be reached")
    return errs


def main():
    ap = argparse.ArgumentParser(description="Check room layouts written as text grids.")
    ap.add_argument("file")
    ap.add_argument("--jump", type=int, default=4, help="tiles a jump rises (default 4)")
    ap.add_argument("--gap", type=int, default=6, help="tiles a jump crosses (default 6)")
    ap.add_argument("--tall", type=int, default=3, help="tiles the player stands (default 3)")
    ap.add_argument("--low", type=int, default=2, help="tiles the player rolls (default 2)")
    a = ap.parse_args()
    bad = 0
    found = rooms(open(a.file, encoding="utf-8").read())
    if not found:
        print("no rooms found")
        return 1
    for name, grid in found:
        errs = check(grid, a.jump, a.gap, a.tall, a.low)
        print(f"{'PASS' if not errs else 'FAIL'}  {name}  ({len(grid[0])} x {len(grid)})")
        for e in errs:
            print("      " + e)
        bad += bool(errs)
    print(f"{len(found) - bad} of {len(found)} rooms pass")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
