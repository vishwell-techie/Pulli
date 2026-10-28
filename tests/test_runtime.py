#!/usr/bin/env python3
"""Runtime behaviour, tested from Lua through the real C runtime.

Run: python3 tests/test_runtime.py

Each case is a tiny game. It reports through dbg(), which the headless host
prints to stdout, and the test compares that with what SPEC.md promises.
"""
import os, sys, tempfile

from harness import Suite, ROOT


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
    r = t.run_game("local a = require('count') dbg(unrequire('count'), unrequire('count'), unrequire('nowhere')) "
                   "local b = require('count') dbg(runs, a ~= b)", extra=mods)
    expect("unrequire forgets a module, and the next require runs it again", r, ["true\tfalse\tfalse", "2\ttrue"])
    expect_error("a module cannot be forgotten while it is still loading",
                 t.run_game("require('self')", extra={"self.lua": "unrequire('self')"}), "still loading")
    r = t.run_game("require('bytes')", extra={"bytes.lua": b"\x1bLua\x54\x00" + bytes(40)})
    expect_error("a module of precompiled bytecode is refused", r, "binary")

    # ---- drawing arguments --------------------------------------------
    r = t.run_game("""
        pset(10.9, 20.9, 7)  pset(1, 1, 64 + 9)  pset(-5, 500, 3)
        dbg(pget(10, 20), pget(11, 21), pget(1, 1), pget(-5, 500), pget(0, 0))
        dbg(pcall(circfill, 'not a number', nil, {}, false))
        cls(5) shade(0, "no lights") dbg(pget(160, 120))
        cls(5) shade(1, {160, 120, 4, 'x', {}, 3, 10}, 99) dbg(pget(160, 120), pget(0, 3), pget(0, 4))
    """)
    expect("coordinates round down, colours wrap, off-screen is ignored, junk does not crash", r,
           ["7\t0\t9\t0\t0", "true", "0", "5\t5\t1"])

    # ---- text: English and Tamil (SPEC §3, "Text") --------------------------
    import refgfx
    ta = refgfx.TamilFont()
    size = lambda text: refgfx.text_size(ta, text.encode())
    SIG = """local function sig(x0, y0, w, h)
               local t = {}
               for y = y0, y0 + h - 1 do for x = x0, x0 + w - 1 do t[#t + 1] = pget(x, y) > 0 and '#' or '.' end end
               return table.concat(t)
             end
             """
    r = t.run_game("""function draw()
        cls()
        dbg(print("AB", 10, 0, 7), text_size(""))
        dbg(text_size("AB\\nABCD"))
        dbg(print("A\\0B", 0, 0, 7), text_size("A\\0B"))
        dbg(print("கொ", 5, 50, 7), text_size("கொ\\nA"))
    end""", frames=1)
    expect("print returns where the next letter would go; text_size gives the widest line and the height", r,
           ["26\t0\t8", "32\t16", "16\t16\t8", f"{5 + size('கொ')[0]}\t{size('கொ')[0]}\t{ta.rows + 8}"])
    small = refgfx.TamilFont(os.path.join(ROOT, "runtime", "font_ta_small.txt"))
    widths = [w for w, _ in refgfx.icons()]
    r = t.run_game("""function draw()
        dbg(buttons.a == "\\u{E004}", buttons.left == "\\u{E000}", buttons.select == "\\u{E00B}", #buttons.start)
        dbg(text_size(buttons.a .. buttons.start .. "x"))
        dbg(text_size("கொ" .. buttons.b))
        font("small") dbg(text_size("கொ\\nA"))
        font() dbg(text_size("கொ"))
        font("small") font("normal") dbg(text_size("கொ"))
    end""", frames=1)
    expect("buttons holds each button's icon; icons are as wide as drawn, and font() picks the Tamil size", r,
           ["true\ttrue\ttrue\t3", f"{widths[4] + widths[10] + 8}\t8",
            f"{size('கொ')[0] + widths[5]}\t{ta.rows}",
            f"{small.glyphs['கொ'][2]}\t{small.rows + 8}", f"{size('கொ')[0]}\t{ta.rows}", f"{size('கொ')[0]}\t{ta.rows}"])
    expect_error("font() refuses a size it does not have", t.run_game("font('huge')"), "invalid option")
    r = t.run_game("""function draw()
        dbg(text_size("Floor 42"))
        dbg(text_size("தளம் 42"))
        font("small") dbg(text_size("தளம் 42")) font()
        dbg(text_size("42\\nதளம்"))
    end""", frames=1)
    digits = lambda f, s: sum(f.glyphs[d][2] for d in s)
    expect("a number on a Tamil line is drawn at the Tamil size, and at 8x8 on an English line", r,
           [f"64\t8", f"{size('தளம் ')[0] + digits(ta, '42')}\t{ta.rows}",
            f"{refgfx.text_size(small, 'தளம் '.encode())[0] + digits(small, '42')}\t{small.rows}",
            f"{size('தளம்')[0]}\t{8 + ta.rows}"])
    r = t.run_game("""function draw()
        cls() print("கொ", 0, 0, 7)
        local left, right = 99, -1
        for y = 0, 40 do for x = 0, 60 do if pget(x, y) > 0 then left = math.min(left, x) right = math.max(right, x) end end end
        dbg(left, right)
    end""", frames=1)
    width, kern, adv, rows = ta.glyphs["கொ"]
    expect("a syllable is drawn whole: கொ is one glyph, its sign before and after the letter", r,
           [f"{kern + min(row.index('#') for row in rows if '#' in row)}\t{kern + max(row.rindex('#') for row in rows if '#' in row)}"])
    r = t.run_game(SIG + """function draw()
        cls() print("\\255A", 0, 0, 7) local bad = sig(0, 0, 16, 8)
        cls() print("?A", 0, 0, 7) local shown = sig(0, 0, 16, 8)
        cls() print("€", 0, 0, 7) local missing = sig(0, 0, 8, 8)
        cls() print("?", 0, 0, 7)
        dbg(bad == shown, missing == sig(0, 0, 8, 8))
    end""", frames=1)
    expect("a byte that is not UTF-8, and a character the fonts lack, are drawn as ?", r, ["true\ttrue"])
    r = t.run_game(f"""function draw()
        cls() print("B\\nA", 0, 20, 7) local english = pget(2, 28)
        cls() print("க\\nA", 0, 20, 7)
        dbg(english, pget(2, {20 + ta.rows}), pget(2, 28))
        cls() print("கA", 0, 20, 7)
        dbg(pget({ta.glyphs["க"][2] + 2}, {20 + ta.above}), pget({ta.glyphs["க"][2] + 2}, 20))
    end""", frames=1)
    expect("a line holding Tamil is as tall as the Tamil font, and its English shares the Tamil baseline", r,
           ["7\t7\t0", "7\t0"])
    r = t.run_game(f"""function draw()
        cls() print("க்", 0, 20, 7)
        local top, bottom = 99, -1
        for y = 0, 60 do for x = 0, 30 do if pget(x, y) > 0 then top = math.min(top, y) bottom = math.max(bottom, y) end end end
        dbg(top >= 20, bottom < {20 + ta.rows})
    end""", frames=1)
    expect("Tamil is drawn inside its line, from the y given down", r, ["true\ttrue"])

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
        dbg(save('bad key', 1), save('', 1), save(string.rep('k', 33), 1), save('t', { dbg }), save('f', dbg))
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

    # ---- tables in save data ---------------------------------------------
    BIG = manifest(save_target='"sd"', save_size="512")
    r = t.run_game("""
        local t = { n = 7, f = 0.5, name = 'Vish', on = true, off = false, list = { 10, 20, 'thirty' },
                    [5] = 'five', [2.5] = 'half', [true] = 'yes', deep = { a = { b = { c = 1 } } } }
        dbg(save('t', t))
        local u = load('t')
        dbg(u.n, math.type(u.n), u.f, u.name, u.on, u.off, #u.list, u.list[3], u[5], u[2.5], u[true], u.deep.a.b.c)
        dbg(u ~= t, load('t') ~= u)
        u.n = 99 dbg(load('t').n)
    """, manifest=BIG)
    expect("a table of numbers, text, booleans and tables is kept and comes back, as a new table each time", r, [
        "true", "7\tinteger\t0.5\tVish\ttrue\tfalse\t3\tthirty\tfive\thalf\tyes\t1", "true\ttrue", "7"])
    r = t.run_game("""
        local four = { { { { 1 } } } }                  -- a table in a table in a table in a table
        local five = { { { { { 1 } } } } }
        local mine = {} mine.me = mine
        dbg(save('four', four), save('five', five), save('mine', mine))
        dbg(save('fn', { f = dbg }), save('keyfn', { [dbg] = 1 }), save('keytbl', { [{}] = 1 }))
        dbg(save('empty', {}), next(load('empty')), save('mixed', { 1, 2, x = 3 }), load('mixed').x)
    """, manifest=BIG)
    expect("tables nest four deep; deeper, self-containing, and with functions or table keys are refused", r, [
        "true\tfalse\tfalse", "false\tfalse\tfalse", "true\tnil\ttrue\t3"])
    r = t.run_game("""
        dbg(save('a', string.rep('x', 200)), save('t', { string.rep('y', 200), string.rep('z', 200) }), load('a') ~= nil)
        dbg(save('t', { string.rep('y', 100) }), #load('t')[1])
        dbg(save('t', { string.rep('y', 300) }), #load('t')[1])
    """, manifest=BIG)
    expect("a table is refused when it does not fit, and the old value stays", r, [
        "true\tfalse\ttrue", "true\t100", "false\t100"])
    r = t.run_game("""
        save('t', { 1, 2, 3 }) dbg(#load('t')) save('t', 5) dbg(load('t'))
        save('t', { 'a' }) dbg(load('t')[1]) save('t', nil) dbg(load('t', 'gone'))
    """, manifest=BIG)
    expect("a table can be replaced by another kind of value and back, or deleted", r, ["3", "5", "a", "gone"])
    with tempfile.TemporaryDirectory() as saves:
        t.run_game("dbg(save('cfg', { vol = 3, keys = { 'a', 'b' }, nested = { x = 1.5 } }))", manifest=BIG, saves=saves)
        r = t.run_game("local c = load('cfg') dbg(c.vol, c.keys[2], c.nested.x)", manifest=BIG, saves=saves)
        expect("a saved table comes back in a later run", r, ["3\tb\t1.5"])
        # Damage the table inside the file: cut its closing brace off and shorten the record to match.
        blob = bytearray(open(f"{saves}/test.game.sav", "rb").read())
        start = blob.index(b"cfg") - 4                # a record: key length, type, value length (2), key, value
        vlen = blob[start + 2] | (blob[start + 3] << 8)
        end = start + 4 + 3 + vlen
        t.check("the saved table ends with its closing brace", blob[end - 1] == ord("}"))
        blob[start + 2:start + 4] = (vlen - 1).to_bytes(2, "little")
        del blob[end - 1]
        open(f"{saves}/test.game.sav", "wb").write(blob)
        r = t.run_game("dbg(load('cfg', 'default'))", manifest=BIG, saves=saves)
        expect("a damaged table loads as if never saved, giving the default", r, ["default"])
        t.run_game("save('cfg', { 1 })", manifest=BIG, saves=saves)
        blob = bytearray(open(f"{saves}/test.game.sav", "rb").read())
        start = blob.index(b"cfg") - 4
        vlen = blob[start + 2] | (blob[start + 3] << 8)
        blob[start + 2:start + 4] = (vlen + 1).to_bytes(2, "little")
        blob.insert(start + 4 + 3 + vlen, ord("x"))                  # one stray byte after the table
        open(f"{saves}/test.game.sav", "wb").write(blob)
        r = t.run_game("dbg(load('cfg', 'default'))", manifest=BIG, saves=saves)
        expect("a table with something left over after it loads as if never saved", r, ["default"])
    r = t.run_game("""dbg(save('big', { string.rep('x', 40000), string.rep('y', 40000) }), load('big'))
                     dbg(save('ok', { string.rep('x', 40000) }), #load('ok')[1])""",
                   manifest=manifest(save_target='"sd"', save_size="65536"))
    expect("one saved value may not be more than 65535 bytes, even if the save data has room", r,
           ["false\tnil", "true\t40000"])

    # ---- when saves are written ---------------------------------------------
    def hang_after(lua, **fields):
        """Run a game that saves and then hangs, kill it as a crash or a flat
        battery would, and say what the save file holds."""
        import time
        with tempfile.TemporaryDirectory() as saves:
            m = manifest(save_target='"sd"', save_size="256", **fields)
            started = t._start(os.path.join(saves, "run"), t.package(lua, m), frames=100000, saves=saves)
            time.sleep(1.5)
            started[0].kill()
            started[0].communicate()
            path = os.path.join(saves, "test.game.sav")
            if not os.path.exists(path):
                return "no file"
            r = t.run_game("dbg(load('k'))", manifest=m, saves=saves)
            return r.lines[0] if r.lines else r.err
    def count(until, hang):
        """Save the frame number every frame up to `until`, then hang at `hang`."""
        return (f"function update() local f = stat('frame') if f <= {until} then save('k', f) end"
                f" if f == {hang} then while true do end end end")
    t.check("default: nothing is written until the game ends, so a crash loses it",
            hang_after(count(800, 801)) == "no file")
    t.check("save_mode 'exit' is the same as the default", hang_after(count(800, 801), save_mode='"exit"') == "no file")
    t.check("save_mode 'auto' with the shortest wait, 10 s, writes at 10 s, and again no sooner than 10 s later",
            hang_after(count(1300, 1301), save_mode='"auto"', save_interval="10") == "1200")
    t.check("a longer save_interval is kept to: 12 s writes at 12 s and 24 s",
            hang_after(count(1500, 1501), save_mode='"auto"', save_interval="12") == "1440")
    t.check("nothing is written before the wait is over", hang_after(count(590, 591), save_mode='"auto"', save_interval="10") == "no file")
    t.check("with no save_interval, 'auto' waits 60 s",
            hang_after(count(3599, 3600), save_mode='"auto"') == "no file"
            and hang_after(count(3650, 3651), save_mode='"auto"') == "3600")
    t.check("save_commit is a checkpoint: it writes at once in any mode, and starts the auto wait over",
            hang_after("function update() local f = stat('frame') if f <= 700 then save('k', f) end"
                       " if f == 300 then save_commit() end if f == 701 then while true do end end end",
                       save_mode='"auto"', save_interval="10") == "300")
    t.check("save_commit in the default mode writes what was saved up to then",
            hang_after("function update() local f = stat('frame') if f <= 500 then save('k', f) end"
                       " if f == 200 then save_commit() end if f == 501 then while true do end end end") == "200")
    t.check("save_mode 'auto' writes nothing when nothing was saved",
            hang_after("function update() if stat('frame') == 5 then while true do end end end", save_mode='"auto"') == "no file")
    expect_error("save_mode must be 'exit' or 'auto'", t.run_game("", manifest=manifest(save_mode='"often"')), "save_mode")
    for bad in ("9", "0", "3601", "'soon'", "2.5"):
        expect_error(f"save_interval {bad} is refused: it must be a whole number of seconds from 10 to 3600",
                     t.run_game("", manifest=manifest(save_mode='"auto"', save_interval=bad)), "save_interval", "10 to 3600")
    with tempfile.TemporaryDirectory() as saves:
        t.run_game("save('k', 9)", manifest=manifest(save_target='"sd"', save_mode='"auto"'), saves=saves)
        r = t.run_game("dbg(load('k'))", manifest=manifest(save_target='"sd"'), saves=saves)
        expect("the end of the game still writes, in either mode", r, ["9"])

    # ---- the palette --------------------------------------------------------
    def rgb(r, g, b):
        return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
    r = t.run_game("""
        palette(5, 255, 128, 0) palette(6, 300, -20, 17) palette(71, 1, 2, 3)
        function draw() cls(5) rectfill(0, 0, 10, 10, 6) rectfill(20, 0, 10, 10, 7) end
    """)
    px = lambda res, x, y: int.from_bytes(res.rgb[2 * (y * 320 + x):2 * (y * 320 + x) + 2], "little")
    t.check("palette(c, r, g, b) sets a colour from 0-255 values, holds them to that range, and wraps the number",
            r.code == 0 and px(r, 100, 100) == rgb(255, 128, 0) and px(r, 5, 5) == rgb(255, 0, 17)
            and px(r, 25, 5) == rgb(1, 2, 3), r.err)
    r = t.run_game("""
        palette(5, 255, 128, 0)
        function draw() cls(5) fade(0.5) palette(5, 255, 128, 0) end
    """)
    k = 16
    t.check("a colour set by palette() is dimmed by fade() like the rest",
            px(r, 5, 5) == rgb(255, 128, 0) * 0 + ((((255 >> 3) * k) >> 5) << 11 | (((128 >> 2) * k) >> 5) << 5 | 0), (px(r, 5, 5),))
    r = t.run_game("""
        local default = ...
        function draw() cls(1) palette(1, 9, 9, 9) palette() end
    """)
    plain = t.run_game("function draw() cls(1) end")
    t.check("palette() with nothing puts the colours back", r.code == 0 and r.rgb == plain.rgb, r.err)

    # ---- music pause -------------------------------------------------------
    r = t.run_game("music_pause() music_pause(false) music_pause(true) sfx(-1)", frames=3)
    expect("pausing music when there is none is harmless", r, [])

    # ---- frame rate and load, for the developer ----------------------------------
    def clocked(step, frames=200):
        r = t.run_game("function draw() if stat('frame') == %d then dbg(stat('fps'), stat('cpu')) end end" % frames,
                       frames=frames, clock=step)
        return r.lines[0] if r.lines else r.err
    expect("without a clock, stat('fps') and stat('cpu') are nil",
           t.run_game("function draw() if stat('frame') == 3 then dbg(stat('fps'), stat('cpu')) end end", frames=3),
           ["nil\tnil"])
    # Each frame reads the clock four times, so a step of 4000 us is 16 ms a frame, about 62.5 a second,
    # of which update and draw each used one step: 8000 us of a frame's 16667.
    t.check("stat('fps') and stat('cpu') measure from the port's clock: 16 ms frames, half of it used",
            clocked(4000) == "63\t48", clocked(4000))
    t.check("a slower clock gives a lower rate and a fuller frame", clocked(8000) == "31\t96", clocked(8000))
    t.check("before a second has passed there is no rate yet, only the load",
            clocked(4000, 20) == "0\t48", clocked(4000, 20))
    t.check("the rate is updated every second: the same clock gives the same figure later",
            clocked(4000, 600) == "63\t48", clocked(4000, 600))

    # ---- memory -------------------------------------------------------
    r = t.run_game("dbg(stat('mem') > 0, stat('mem') < 64, stat('nonsense'))", manifest=manifest(lua_heap="64"))
    expect("stat('mem') reports the Lua heap in KB", r, ["true\ttrue\tnil"])
    r = t.run_game("""
        local hog = {}
        function update() for i = 1, 2000 do hog[#hog + 1] = { i } end end
    """, manifest=manifest(lua_heap="64"), frames=600)
    expect_error("the Lua heap is capped at the manifest's lua_heap", r, "not enough memory")
    # The count and the cap are in the console's bytes (a 64-bit desktop
    # scales its own, SPEC §10): the heap fills to just under lua_heap.
    r = t.run_game("""
        local hog, most = {}, 0
        function update()
          for i = 1, 200 do hog[#hog + 1] = { i } most = math.max(most, stat('mem')) end
        end
        function draw() dbg(most) end
    """, manifest=manifest(lua_heap="64"), frames=600)
    most = float(r.lines[-1]) if r.lines else 0
    t.check("stat('mem') climbs to just under lua_heap before memory runs out", 60 < most <= 64, most)

    # ---- the parts of the package in memory (SPEC §2, §3 "Loading") ---------
    from harness import pulli
    MB = 1024 * 1024
    parts = {"a.bin": bytes([1]) * (5 * MB // 2), "b.bin": bytes([2]) * (5 * MB // 2),
             "c.bin": bytes([3]) * (5 * MB // 2), "huge.bin": bytes(7 * MB)}
    r = t.run_game("""
        local function kb() return math.floor(stat("active")) end
        local base = kb()
        dbg(preload("a.bin", "b.bin"), kb() - base)
        dbg(preload("c.bin"), kb() - base)
        dbg(preload("a.bin"), kb() - base)
        dbg(preload("nowhere.bin", "a.bin"), kb() <= 6144)
        dbg(pcall(preload, "huge.bin"))
    """, extra=parts)
    out = r.out.split("\n")
    t.check("preload reads parts into memory and stat('active') counts them; the oldest unused is let go",
            out[:4] == ["true\t5120", "true\t5120", "true\t5120", "false\ttrue"], r.out + r.err)
    t.check("a part too big for memory is an error naming it",
            len(out) > 4 and out[4].startswith("false") and "huge.bin" in out[4] and "6144 KB" in out[4], r.out)

    sheets = {"sprites.kolam": pulli.kolam(8, 8, bytes([8]) * 64), "blue.kolam": pulli.kolam(8, 8, bytes([12]) * 64)}
    r = t.run_game("""
        function draw()
            cls() spr(0, 0, 0) local before = pget(3, 3)
            sheet.load("blue.kolam") spr(0, 0, 0) local after = pget(3, 3)
            preload("a.bin", "b.bin", "c.bin")          -- fills memory: the sheet in use stays
            cls() spr(0, 0, 0)
            dbg(before, after, pget(3, 3), (pcall(sheet.load, "nowhere.kolam")), (pcall(sheet.load, "main.lua")))
            sheet.load("sprites.kolam") cls() spr(0, 0, 0) dbg(pget(3, 3))
        end""", extra=dict(parts, **sheets))
    t.check("sheet.load changes the sheet sprites are drawn from; the one in use is kept in memory",
            r.out.split("\n")[:2] == ["8\t12\t12\tfalse\tfalse", "8"], r.out + r.err)
    # a backdrop is kept too: read once, and not let go when memory fills
    bd = {"bd.kolam": pulli.kolam(320, 240, bytes([9]) * (320 * 240))}
    r = t.run_game("""
        function init() backdrop("bd.kolam") end
        function draw()
            local before = stat("active")
            preload("a.bin", "b.bin", "c.bin")          -- fills memory: the backdrop stays
            cls() dbg(pget(100, 100), stat("active") >= 75)
        end""", extra=dict(parts, **bd), frames=2)
    t.check("a backdrop is kept in memory while it is set, even when memory fills",
            r.code == 0 and r.out.split("\n")[:2] == ["9\ttrue", "9\ttrue"], r.out + r.err)
    r = t.run_game("sheet.load('nowhere.kolam')", extra=sheets)
    t.check("sheet.load of a sheet the package does not have names it", r.code == 1 and "nowhere.kolam" in r.err, r.err)

    sound = {"sfx.oli": pulli.bank("sfx", [(22050, 1, [100] * 2205, None, pulli.PCM),
                                           (22050, 1, [200] * 22050, None, pulli.PCM)])}
    r = t.run_game("""
        local a = stat("active")
        sfx(1) local b = stat("active")
        dbg(math.floor((b - a) * 1024 + 0.5), preload("sfx 0"), preload("sfx 2"), preload("music 0"))
    """, extra=sound)
    t.check("a sound is read when it is first played, and preload takes 'sfx N'",
            r.out.split("\n")[0] == "44100\ttrue\tfalse\tfalse", r.out + r.err)

    game = """
        function update() if stat("frame") % 3 == 0 then preload(({"a.bin", "b.bin", "c.bin"})[stat("frame") % 9 // 3 + 1]) end end
        function draw() cls(stat("frame") % 16) dbg(math.floor(stat("active"))) end"""
    read, mapped = t.run_game(game, extra=parts, frames=20), t.run_game(game, extra=parts, frames=20, mapped=True)
    t.check("a game behaves the same, memory counted alike, whether its package is read in parts or held",
            read.code == 0 and read.out == mapped.out and read.fb == mapped.fb, read.err + mapped.err)

    # ---- save data in a cartridge's flash (SPEC §2 "Cartridges") -----------
    import tempfile as _tmp
    counter = """
        local n = load("runs", 0)
        dbg("run", n)
        save("runs", n + 1) save("pad", string.rep("x", PAD))
        dbg("saved", save_commit())
    """
    def cart_game(pad, size):
        manifest = f'return {{ id = "test.cart", title = "Cart", spec = 1, save_target = "cart", save_size = {size} }}\n'
        return t.package(counter.replace("PAD", str(pad)), manifest)
    with _tmp.TemporaryDirectory() as tmp:
        img = os.path.join(tmp, "cart.img")
        with open(img, "wb") as f:
            f.write(pulli.cart_image(cart_game(60000, 65536)))
        seen = []
        for _ in range(10):                                  # seven slots of 68 KB: round them more than once
            r = t.run_package(b"", cart=img)
            seen.append([l for l in r.lines if l.startswith("run")])
        t.check("a cartridge keeps its saves in its own flash, run after run, through every slot",
                [x[0] if x else None for x in seen] == [f"run\t{i}" for i in range(10)],
                str(seen) + r.err)
        with open(img, "rb") as f:
            image = f.read()
        area = image[-512 * 1024:]
        t.check("the saves are in the last 512 KB, written in turn: seven slots for the largest save",
                pulli.cart_image(cart_game(60000, 65536))[:-512 * 1024] == image[:-512 * 1024]
                and sum(area[i * 69632:i * 69632 + 4] == b"SAV1" for i in range(7)) == 7, "")
        # Pulled out while saving: the save being written is lost, the one before is not.
        r = t.run_package(b"", cart=img, cart_cut=1000)
        cut = [l for l in r.lines if l.startswith(("run", "saved"))]
        r = t.run_package(b"", cart=img)
        after = [l for l in r.lines if l.startswith("run")]
        t.check("a cartridge pulled out while saving keeps the save before",
                cut == ["run\t10", "saved\tfalse"] and after == ["run\t10"], f"{cut} {after} {r.err}")
        with open(img, "wb") as f:
            f.write(pulli.cart_image(cart_game(10, 64)))
        for _ in range(3):
            r = t.run_package(b"", cart=img)
        t.check("a small save on a cartridge works the same", [l for l in r.lines if l.startswith("run")] == ["run\t2"], r.err)
        # a cartridge is 8, 16, 32 or 64 MB (one chip, or two read as one range)
        small = cart_game(10, 64)
        def refused(mb):
            try: pulli.cart_image(small, mb)
            except pulli.PackageError: return True
            return False
        t.check("a cartridge image is the smallest cartridge that holds it, 8, 16, 32 or 64 MB, and no other size",
                len(pulli.cart_image(small)) == 8 << 20 and len(pulli.cart_image(small, 16)) == 16 << 20
                and refused(1) and refused(12) and refused(128), "")

    # ---- errors -------------------------------------------------------
    boom = "function update()\n  local t = nil\n  return t.x\nend\n"
    r = t.run_game(boom, frames=10, debug=True)
    expect_error("a runtime error stops the game and says where", r, "main.lua:3:", "local 't'", "stack traceback",
                 "0 of 10 frames")
    # Debug information (SPEC §10): dropped unless asked for; asked for by the
    # developer (--debug) or the manifest (debug = true).
    r = t.run_game(boom, frames=10)
    t.check("without debug information an error names its file but not the line",
            r.code == 1 and "error: main.lua: attempt to index a nil value" in r.err and "main.lua:3" not in r.err, r.err)
    r = t.run_game(boom, manifest=manifest(debug="true"), frames=10)
    t.check("the manifest's debug = true keeps the line numbers", r.code == 1 and "main.lua:3:" in r.err, r.err)
    r = t.run_game("x = 1", manifest=manifest(debug="'yes'"))
    expect_error("debug must be true or false", r, "'debug' must be true or false")
    # A debug build counts the heap as a release build does (its line
    # numbers left out), and loading a module again and again leaks nothing.
    many = ("local n = 0 function update() n = n + 1 unrequire('m') require('m') "
            "if n == 50 or n == 250 then collectgarbage() collectgarbage() dbg(n, stat('mem')) end end")
    module = {"m.lua": "local t = {} " + " ".join("function t.f%d(a, b) local c = a + b return c * %d end" % (k, k)
                                                   for k in range(40)) + " return t"}
    mem = {}
    for debug in (False, True):
        r = t.run_game(many, extra=module, frames=260, debug=debug)
        mem[debug] = {l.split("\t")[0]: float(l.split("\t")[1]) for l in r.lines if "\t" in l}
    t.check("a debug build counts the heap within a few KB of a release build; loading a module again leaks nothing",
            all(abs(mem[True][n] - mem[False][n]) < 2.5 and mem[d]["250"] - mem[d]["50"] < 0.5
                for n in ("50", "250") for d in (False, True)), mem)
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
