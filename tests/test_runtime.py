#!/usr/bin/env python3
"""Runtime behaviour, tested from Lua through the real C runtime.

Run: python3 tests/test_runtime.py

Each case is a tiny game. It reports through dbg(), which the headless host
prints to stdout, and the test compares that with what SPEC.md promises.
"""
import sys, tempfile

from harness import Suite


def manifest(**fields):
    base = {"id": '"test.game"', "title": '"Test"', "spec": "1"}
    base.update(fields)
    return "return { " + ", ".join(f"{k} = {v}" for k, v in base.items() if v is not None) + " }\n"


SAVES = manifest(save_target='"sd"', save_size="64")


def main():
    t = Suite("Pulli runtime behaviour")
    if not t.need_runtime("everything in this file"):
        return t.finish()

    def expect(name, r, lines, code=0):
        t.check(name, r.code == code and r.lines == lines,
                f"exit {r.code}\nstdout: {r.lines}\nwanted: {lines}\nstderr: {r.err}")

    def expect_error(name, r, *needles):
        t.check(name, r.code == 1 and all(n in r.err for n in needles), f"exit {r.code}\nstderr: {r.err}")

    # ---- lifecycle ----------------------------------------------------
    r = t.run_game("""
        local i, u, d = 0, 0, 0
        function init() i = i + 1 end
        function update(dt) u = u + 1; step = dt end
        function draw() d = d + 1; if d == 3 then dbg(i, u, d, step == 1/60, time() == 3/60) end end
    """, frames=3)
    expect("init once, then update and draw every frame at a fixed 1/60 s", r, ["1\t3\t3\ttrue\ttrue"])

    r = t.run_game("dbg('loaded')", frames=5)
    expect("a game need not define every callback", r, ["loaded"])

    # ---- number model -------------------------------------------------
    r = t.run_game("dbg(math.maxinteger, math.maxinteger + 1 == math.mininteger, 7 // 2, 7 / 2, 2^24 + 1 == 2^24)")
    expect("32-bit integers that wrap, and 32-bit floats", r, ["2147483647\ttrue\t3\t3.5\ttrue"])

    # ---- sandbox ------------------------------------------------------
    r = t.run_game("dbg(io, os, package, debug, dofile, loadfile)")
    expect("no io, os, package, debug or file loading", r, ["nil\tnil\tnil\tnil\tnil\tnil"])
    r = t.run_game("dbg(load('return 1 + 1'), string.format('%d', 5), #table.pack(1, 2), math.floor(2.5))")
    expect("load() is the save store, not a compiler; safe libraries remain", r, ["nil\t5\t2\t2"])
    r = t.run_game(b"\x1bLua\x54\x00\x19\x93\r\n\x1a\n" + b"\0" * 32)
    expect_error("precompiled bytecode is refused", r, "binary")
    r = t.run_game("print('to the screen, not the terminal')")
    expect("print() draws; only dbg() reaches the console", r, [])

    # ---- determinism --------------------------------------------------
    src = """
        local t = { apple = 1, mango = 2, guava = 3, banana = 4, jackfruit = 5 }
        local order = ''
        for k in pairs(t) do order = order .. k:sub(1, 1) end
        dbg(order, math.random(1000), math.random(1000), math.random())
    """
    a, b = t.run_game(src), t.run_game(src)
    t.check("random numbers and pairs() order repeat from run to run",
            a.code == 0 and a.lines == b.lines and len(a.lines) == 1, f"{a.lines} vs {b.lines} {a.err}")

    # ---- input --------------------------------------------------------
    src = """
        local seen = ''
        function update()
          seen = seen .. (btnp('a') and 'P' or '-') .. (btn('a') and 'H' or '-')
          if stat('frame') == 3 then dbg(seen, btn('left'), btn('b'), btn(4), btn(5), btn('nope'), btn(99)) end
        end
    """
    r = t.run_game(src, frames=3, hold="a,left")
    expect("btn() while held, btnp() on the first frame only, by name or number", r,
           ["PH-H-H\ttrue\tfalse\ttrue\tfalse\tfalse\tfalse"])
    r = t.run_game(src, frames=3)
    expect("nothing held reads as nothing pressed", r, ["------\tfalse\tfalse\tfalse\tfalse\tfalse\tfalse"])
    src = """
        local hits = { a = '', left = '', r = '', start = '', select = '' }
        function update()
          for name, log in pairs(hits) do
            if btnp(name) then hits[name] = log .. stat('frame') .. ' ' end
          end
        end
        function draw()
          if stat('frame') == 45 then dbg(hits.a, hits.left, hits.r, hits.start, hits.select) end
        end
    """
    r = t.run_game(src, frames=45, hold="a,left,r,start,select")
    expect("a held button repeats after 24 frames, then every 6; start and select never do", r,
           ["1 25 31 37 43 \t1 25 31 37 43 \t1 25 31 37 43 \t1 \t1 "])
    r = t.run_game(src, frames=45, tap="a@3,a@4,a@5,a@20,start@7,start@30")
    expect("letting go and pressing again counts as a new press", r, ["3 20 \t\t\t7 30 \t"])

    src = """
        local log = ''
        function update() if btnp('a') then log = log .. stat('frame') .. ' ' end end
        function draw() if stat('frame') == 9 then dbg(log, btn('b')) end end
    """
    expect("--tap presses a button for exactly one frame", t.run_game(src, frames=9, tap="a@2,a@5,b@9"),
           ["2 5 \ttrue"])
    src = """
        local log = ''
        function update() log = log .. (btn('a') and 'A' or '.') .. (btn('b') and 'B' or '.') .. ' ' end
        function draw() if stat('frame') == 6 then dbg(log) end end
    """
    expect("--tap with a range holds a button from one frame to another",
           t.run_game(src, frames=6, tap="a@2-4,b@4-5,b@1"), [".B A. A. AB .B .. "])
    for bad in ("@5", "a@0", "a@x", "nope@3", "a@1,@2", "a", "a@5-2", "a@3-", "a@3-x"):
        r = t.run_game(src, frames=9, tap=bad)
        t.check(f"--tap refuses {bad!r}", r.code == 2 and "usage" in r.err, f"exit {r.code} {r.err}")

    # ---- more than one Lua file ------------------------------------------
    mods = {"greet.lua": "local M = {} function M.hello(n) return 'hello ' .. n end return M",
            "count.lua": "runs = (runs or 0) + 1 return { name = ... }",
            "quiet.lua": "side_effect = 'ran'",
            "first.lua": "return require('second')", "second.lua": "return require('first')",
            "broken.lua": "this is not lua", "notes.txt": "return 1"}
    r = t.run_game("local g = require('greet') dbg(g.hello('you'), require('greet') == g)", extra=mods)
    expect("require runs a file from the package and gives back what it returned", r, ["hello you\ttrue"])
    r = t.run_game("local a, b = require('count'), require('count') dbg(runs, a == b, a.name)", extra=mods)
    expect("a module runs once however often it is required, and is told its name", r, ["1\ttrue\tcount"])
    r = t.run_game("dbg(require('quiet'), side_effect)", extra=mods)
    expect("a module that returns nothing gives true", r, ["true\tran"])
    expect_error("requiring a module the package does not have names it", t.run_game("require('nowhere')", extra=mods),
                 "nowhere.lua")
    expect_error("a mistake in a module is reported with its file name", t.run_game("require('broken')", extra=mods),
                 "broken.lua:1")
    expect_error("two modules that require each other are refused", t.run_game("require('first')", extra=mods),
                 "requires itself")
    for bad in ("../main", "notes.txt", "greet.lua", "", "main", "manifest"):
        r = t.run_game(f"require({bad!r})", extra=mods)
        t.check(f"require refuses {bad!r}", r.code == 1 and "require" in r.err, r.err)
    r = t.run_game("require('bytes')", extra={"bytes.lua": b"\x1bLua\x54\x00" + bytes(40)})
    expect_error("a module of precompiled bytecode is refused", r, "binary")

    # ---- drawing arguments --------------------------------------------
    r = t.run_game("""
        pset(10.9, 20.9, 7)  pset(1, 1, 64 + 9)  pset(-5, 500, 3)
        dbg(pget(10, 20), pget(11, 21), pget(1, 1), pget(-5, 500), pget(0, 0))
        dbg(pcall(circfill, 'not a number', nil, {}, false))
    """)
    expect("coordinates round down, colours wrap, off-screen is ignored, junk does not crash", r,
           ["7\t0\t9\t0\t0", "true"])

    # ---- capabilities -------------------------------------------------
    src = "dbg(sys.has('video'), sys.has('wifi'), sys.has('cart'), sys.has('rumble'), sys.has('link'), sys.has('teleport'))"
    expect("sys.has() is false for everything on the minimum hardware", t.run_game(src),
           ["false\tfalse\tfalse\tfalse\tfalse\tfalse"])
    expect("sys.has() reports the hardware a variant has", t.run_game(src, caps="wifi,rumble"),
           ["false\ttrue\tfalse\ttrue\tfalse\tfalse"])

    # ---- save data (Ninaivu) ------------------------------------------
    r = t.run_game("""
        dbg(save('n', 42), save('f', 1.5), save('s', 'vanakkam'), save('yes', true), save('no', false))
        dbg(load('n'), math.type(load('n')), load('f'), math.type(load('f')), load('s'), load('yes'), load('no'))
        dbg(load('missing'), load('missing', 7), load('no', 'default'))
        save('n', 43)  dbg(load('n'))
        save('n', nil) dbg(load('n', 'gone'))
    """, manifest=SAVES)
    expect("save and load keep the type of numbers, strings and booleans", r, [
        "true\ttrue\ttrue\ttrue\ttrue",
        "42\tinteger\t1.5\tfloat\tvanakkam\ttrue\tfalse",
        "nil\t7\tfalse",
        "43",
        "gone",
    ])
    r = t.run_game("""
        dbg(save('bad key', 1), save('', 1), save(string.rep('k', 33), 1), save('t', {}), save('f', dbg))
        dbg(save('big', string.rep('x', 64)), load('big'), save('fits', string.rep('x', 40)), #load('fits'))
    """, manifest=SAVES)
    expect("save refuses bad keys, unsupported values and anything past save_size", r,
           ["false\tfalse\tfalse\tfalse\tfalse", "false\tnil\ttrue\t40"])
    r = t.run_game("dbg(save('k', 1), load('k', 'none'), save_commit())")
    expect("a game with no save_target cannot save", r, ["false\tnone\ttrue"])

    with tempfile.TemporaryDirectory() as saves:
        t.run_game("save('best', 1280)  save('name', 'kutti')", manifest=SAVES, saves=saves)
        r = t.run_game("dbg(load('best'), load('name'))", manifest=SAVES, saves=saves)
        expect("saves are written on exit and read back by the next run", r, ["1280\tkutti"])
        r = t.run_game("dbg(load('best'))", manifest=manifest(id='"other.game"', save_target='"sd"'), saves=saves)
        expect("one game cannot read another game's saves", r, ["nil"])
        open(f"{saves}/test.game.sav", "wb").write(b"NNV1\x04\x03\x04\x00best\x00\x05\x00\x00" + b"\xff" * 9)
        r = t.run_game("dbg(load('best'), load('name'))", manifest=SAVES, saves=saves)
        expect("a damaged save file keeps its good entries and does not crash", r,
               ["save data is damaged; later entries were dropped", "1280\tnil"])

    # ---- memory -------------------------------------------------------
    r = t.run_game("dbg(stat('mem') > 0, stat('mem') < 64, stat('nonsense'))", manifest=manifest(lua_heap="64"))
    expect("stat('mem') reports the Lua heap in KB", r, ["true\ttrue\tnil"])
    r = t.run_game("""
        local hog = {}
        function update() for i = 1, 2000 do hog[#hog + 1] = { i } end end
    """, manifest=manifest(lua_heap="64"), frames=600)
    expect_error("the Lua heap is capped at the manifest's lua_heap", r, "not enough memory")

    # ---- errors -------------------------------------------------------
    r = t.run_game("function update()\n  local t = nil\n  return t.x\nend\n", frames=10)
    expect_error("a runtime error stops the game and says where", r, "main.lua:3:", "stack traceback", "0 of 10 frames")
    expect_error("a syntax error is reported with its line", t.run_game("function draw(\n  cls(\nend\n"), "main.lua:")
    expect_error("an error in init() stops the boot", t.run_game("function init() error('no cartridge') end"),
                 "no cartridge")

    # ---- manifest -----------------------------------------------------
    for name, text, needle in [
        ("without an id", manifest(id=None), "'id' is required"),
        ("without a title", manifest(title=None), "'title' is required"),
        ("without a spec version", manifest(spec=None), "'spec' is required"),
        ("needing a newer spec", manifest(spec="99"), "needs Pulli spec 99"),
        ("whose id could name a path", manifest(id='"../../etc/passwd"'), "'id' may only use"),
        ("with an unknown save_target", manifest(save_target='"cloud"'), "save_target"),
        ("with too large a save_size", manifest(save_size="65537"), "save_size"),
        ("asking for too much heap", manifest(lua_heap="257"), "lua_heap"),
        ("that is not a table", "return 42\n", "must return a table"),
        ("with a syntax error", "return {\n  id = \n}\n", "manifest.lua:3:"),
        ("that never finishes", "while true do end\n", "ran for too long"),
        ("that tries to use a library", "return { id = os.getenv('HOME') }\n", "manifest.lua:1:"),
        ("that tries to eat memory", "local s = 'x' while true do s = s .. s end\n", "not enough memory"),
    ]:
        expect_error(f"refuses a manifest {name}", t.run_game("", manifest=text), needle)

    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
