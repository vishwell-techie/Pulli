#!/usr/bin/env python3
"""The SDK helpers in sdk/, run through the real runtime.

Run: python3 tests/test_sdk.py

The helpers are plain Lua that a game copies in and requires. Each case
here is a small game that uses one and reports through dbg().
"""
import os, subprocess, sys, tempfile

from harness import Suite, ROOT, pulli

SDK = os.path.join(ROOT, "sdk")
SAVES = 'return { id = "test.sdk", title = "SDK", spec = 1, save_target = "sd", save_size = 512 }\n'


def helper(*names):
    return {name + ".lua": open(os.path.join(SDK, name + ".lua")).read() for name in names}


def main():
    t = Suite("Pulli SDK helpers")
    if not t.need_runtime("everything in this file"):
        return t.finish()

    def expect(name, lua, lines, uses, **opts):
        r = t.run_game(lua, extra=helper(*uses), **opts)
        t.check(name, r.code == 0 and r.lines == lines, f"stdout: {r.lines}\nwanted: {lines}\nstderr: {r.err}")

    def fails(name, lua, uses, *needles):
        r = t.run_game(lua, extra=helper(*uses))
        t.check(name, r.code == 1 and all(n in r.err for n in needles), f"exit {r.code}\n{r.err}")

    R = "local function r(v) return math.floor(v * 100 + 0.5) / 100 end "       # two decimal places

    # ---- tween ---------------------------------------------------------------
    T = ("tween",)
    expect("tween: a value moves steadily from where it is to its goal, and lands exactly",
           R + """local tween = require('tween') local o = { x = 10 }
           tween.to(o, { x = 110 }, 1, 'linear')
           for i = 1, 59 do tween.update(1 / 60) if i == 15 or i == 30 or i == 59 then dbg(r(o.x), tween.count()) end end
           tween.update(1 / 60) tween.update(1 / 60) dbg(o.x, tween.count())""",
           ["35.0\t1", "60.0\t1", "108.33\t1", "110\t0"], T)
    expect("tween: several fields move together, and done is called once at the end",
           R + """local tween = require('tween') local o, calls = { x = 0, y = 100, z = 5 }, 0
           tween.to(o, { x = 8, y = 0 }, 0.5, 'linear', function() calls = calls + 1 end)
           for i = 1, 15 do tween.update(1 / 60) end dbg(r(o.x), r(o.y), o.z, calls)
           for i = 1, 30 do tween.update(1 / 60) end dbg(o.x, o.y, o.z, calls)""",
           ["4.0\t50.0\t5\t0", "8\t0\t5\t1"], T)
    expect("tween: every ease starts at 0 and ends at 1",
           """local tween = require('tween') local names = {}
           for name, f in pairs(tween.ease) do
             names[#names + 1] = name
             assert(math.abs(f(0)) < 1e-5 and math.abs(f(1) - 1) < 1e-5, name)
           end
           table.sort(names) dbg(table.concat(names, ' '))""",
           ["in_cubic in_out_cubic in_out_quad in_quad linear out_back out_bounce out_cubic out_quad"], T)
    expect("tween: eases shape the journey: out_quad is ahead of linear, in_quad behind, out_back overshoots",
           R + """local tween = require('tween') local a, b, c, d = { v = 0 }, { v = 0 }, { v = 0 }, { v = 0 }
           tween.to(a, { v = 100 }, 1, 'linear') tween.to(b, { v = 100 }, 1) tween.to(c, { v = 100 }, 1, 'in_quad')
           tween.to(d, { v = 100 }, 1, 'out_back')
           local most = 0
           for i = 1, 60 do tween.update(1 / 60) most = math.max(most, d.v) if i == 30 then dbg(r(a.v), r(b.v), r(c.v)) end end
           tween.update(1 / 60) dbg(most > 100, d.v)""",
           ["50.0\t75.0\t25.0", "true\t100"], T)
    expect("tween: a tween can be stopped where it is, alone or with all on its target",
           R + """local tween = require('tween') local o, p = { x = 0, y = 0 }, { x = 0 }
           local h = tween.to(o, { x = 100 }, 1, 'linear') tween.to(o, { y = 100 }, 1, 'linear') tween.to(p, { x = 100 }, 1, 'linear')
           for i = 1, 30 do tween.update(1 / 60) end
           dbg(tween.stop(h), tween.stop(h), tween.count())
           for i = 1, 15 do tween.update(1 / 60) end
           tween.stop_all(o) dbg(tween.count())
           for i = 1, 60 do tween.update(1 / 60) end dbg(r(o.x), r(o.y), p.x)
           tween.to(p, { x = 0 }, 1) tween.to(o, { x = 0 }, 1) tween.stop_all() dbg(tween.count())""",
           ["true\tfalse\t2", "1", "50.0\t75.0\t100", "0"], T)
    expect("tween: done may start another tween, and finished tweens are used again",
           """local tween = require('tween') local o, log = { x = 0 }, ''
           local function back() log = log .. 'B' tween.to(o, { x = 0 }, 0.1, 'linear', function() log = log .. 'E' end) end
           tween.to(o, { x = 9 }, 0.1, 'linear', back)
           for i = 1, 5 do tween.to({ v = 0 }, { v = 1 }, 0.05) end
           for i = 1, 30 do tween.update(1 / 60) end dbg(log, o.x, tween.count())""",
           ["BE\t0\t0"], T)
    expect("tween: a tween of no length arrives on the next update",
           "local tween = require('tween') local o = { x = 1 } tween.to(o, { x = 5 }, 0) tween.update(1 / 60) dbg(o.x, tween.count())",
           ["5\t0"], T)
    fails("tween: an unknown ease is an error that names it",
          "local tween = require('tween') tween.to({ x = 0 }, { x = 1 }, 1, 'wobble')", T, "wobble", "main.lua:1")
    fails("tween: leaving out the time is an error that says so",
          "local tween = require('tween') tween.to({ x = 0 }, { x = 1 })", T, "seconds", "main.lua:1")
    fails("tween: a field that is not a number is an error that names it",
          "local tween = require('tween') tween.to({ x = 'left' }, { x = 1 }, 1)", T, "'x'", "main.lua:1")

    # ---- camera_follow ---------------------------------------------------------
    C = ("camera_follow",)
    expect("camera: snap centres the view on a point, and bounds keep it inside the map",
           """local cam = require('camera_follow').new()
           cam:snap(500, 400) dbg(cam.x, cam.y)
           cam:bounds(0, 0, 640, 480) dbg(cam.x, cam.y)
           cam:snap(0, 0) dbg(cam.x, cam.y) cam:snap(9999, 9999) dbg(cam.x, cam.y)
           cam:bounds() cam:snap(0, 0) dbg(cam.x, cam.y)""",
           ["340.0\t280.0", "320\t240", "0\t0", "320\t240", "-160.0\t-120.0"], C)
    expect("camera: it closes on its target a little each frame and gets there",
           R + """local cam = require('camera_follow').new({ smooth = 6 })
           cam:snap(160, 120) local last, steady = 0, true
           for i = 1, 240 do
             cam:update(460, 120, 1 / 60)
             steady = steady and cam.x >= last  last = cam.x
             if i == 1 or i == 10 then dbg(r(cam.x)) end
           end
           dbg(steady, r(cam.x), cam.y)""",
           ["30.0", "195.4", "true\t300.0\t0.0"], C)
    expect("camera: with smooth = 0 it is on its target at once",
           "local cam = require('camera_follow').new({ smooth = 0 }) cam:update(460, 320, 1 / 60) dbg(cam.x, cam.y)",
           ["300.0\t200.0"], C)
    expect("camera: inside the dead zone the target moves without moving the view",
           """local cam = require('camera_follow').new({ smooth = 0, dead_w = 80, dead_h = 40 })
           cam:snap(160, 120)
           cam:update(199, 139, 1 / 60) dbg(cam.x, cam.y)        -- 39 right, 19 down: inside
           cam:update(210, 120, 1 / 60) dbg(cam.x, cam.y)        -- 50 right: 10 past the edge
           cam:update(160, 90, 1 / 60) dbg(cam.x, cam.y)""",     # back inside across, 10 past the top
           ["0.0\t0.0", "10.0\t0.0", "10.0\t-10.0"], C)
    expect("camera: a map smaller than the screen is centred",
           "local cam = require('camera_follow').new() cam:bounds(0, 0, 200, 100) cam:snap(50, 50) dbg(cam.x, cam.y)",
           ["-60.0\t-70.0"], C)
    expect("camera: a shake moves the view by no more than asked, fades, and stops",
           """local cam = require('camera_follow').new() cam:snap(160, 120)
           cam:shake(4, 0.5) local biggest, moved = 0, 0
           for i = 1, 40 do
             cam:update(160, 120, 1 / 60)
             local size = math.max(math.abs(cam.shake_x), math.abs(cam.shake_y))
             biggest = math.max(biggest, size) if size > 0 then moved = moved + 1 end
           end
           dbg(biggest > 1, biggest <= 4, moved, cam.shake_x, cam.shake_y, cam.x)""",
           ["true\ttrue\t29\t0\t0\t0.0"], C)
    r = t.run_game("""local cam = require('camera_follow').new({ smooth = 0 }) cam:snap(1160, 620)
                   function draw() cls() cam:apply() pset(1000, 500, 9) camera() pset(5, 5, 8) end""", extra=helper(*C))
    t.check("camera: apply moves the drawing, and camera() puts it back",
            r.code == 0 and r.fb[0] == 9 and r.fb[5 * 320 + 5] == 8 and sum(1 for v in r.fb if v) == 2, r.err)

    # ---- inventory -----------------------------------------------------------------
    I = ("inventory",)
    expect("inventory: things are added, counted and listed in the order they were picked up",
           """local bag = require('inventory').new()
           dbg(bag:add('potion', 2), bag:add('key'), bag:add('potion'), bag:count('potion'), bag:count('sword'))
           dbg(bag:has('key'), bag:has('potion', 3), bag:has('potion', 4), bag:has('sword'), bag:kinds())
           dbg(bag:item(1)) dbg(bag:item(2)) dbg(bag:item(3))""",
           ["true\ttrue\ttrue\t3\t0", "true\ttrue\tfalse\tfalse\t2", "potion\t3", "key\t1", ""], I)
    expect("inventory: removing takes all that was asked for or nothing, and the last one frees its place",
           """local bag = require('inventory').new() bag:add('potion', 3) bag:add('key') bag:add('map')
           dbg(bag:remove('potion', 5), bag:count('potion'), bag:remove('sword'), bag:remove('potion', 2), bag:count('potion'))
           dbg(bag:remove('key'), bag:kinds(), bag:has('key')) dbg(bag:item(1)) dbg(bag:item(2))
           dbg(bag:remove('potion', 0), bag:add('potion', 0), bag:add('potion', -1))""",
           ["false\t3\tfalse\ttrue\t1", "true\t2\tfalse", "potion\t1", "map\t1", "false\tfalse\tfalse"], I)
    expect("inventory: a full bag takes more of what it holds but nothing new",
           """local bag = require('inventory').new(2) bag:add('a') bag:add('b')
           dbg(bag:add('c'), bag:add('a', 4), bag:kinds(), bag:count('a'))
           bag:remove('b') dbg(bag:add('c'), bag:kinds())""",
           ["false\ttrue\t2\t5", "true\t2"], I)
    expect("inventory: a stack holds only so many, all or nothing",
           """local bag = require('inventory').new(4, 10) bag:add('arrow', 8)
           dbg(bag:add('arrow', 3), bag:count('arrow'), bag:add('arrow', 2), bag:count('arrow'), bag:add('bolt', 11), bag:kinds())""",
           ["false\t8\ttrue\t10\tfalse\t1"], I)
    expect("inventory: clear empties the bag",
           "local bag = require('inventory').new() bag:add('a', 2) bag:add('b') bag:clear() dbg(bag:kinds(), bag:count('a'), bag:add('c'))",
           ["0\t0\ttrue"], I)
    with tempfile.TemporaryDirectory() as saves:
        t.run_game("""local bag = require('inventory').new() bag:add('potion', 3) bag:add('old key') bag:add('gem', 12)
                   bag:remove('old key') bag:add('rope') dbg(bag:save('bag'))""", manifest=SAVES, saves=saves, extra=helper(*I))
        expect("inventory: a saved bag comes back the same in a later run",
               """local bag = require('inventory').new() bag:add('junk')
               dbg(bag:load('bag'), bag:kinds(), bag:count('junk')) dbg(bag:item(1)) dbg(bag:item(2)) dbg(bag:item(3))
               dbg(bag:load('other'), bag:kinds())""",
               ["true\t3\t0", "potion\t3", "gem\t12", "rope\t1", "false\t3"], I, manifest=SAVES, saves=saves)

    # ---- dialog ----------------------------------------------------------------------
    D = ("dialog",)
    LOG = """local dialog = require('dialog') local log = ''
             function update(dt) local on = dialog.update(dt) log = log .. (on and '#' or '.') end
             function draw() if stat('frame') == FRAMES then dbg(log) end end """

    def talk(name, setup, frames, tap, want, **opts):
        expect(name, LOG.replace("FRAMES", str(frames)) + setup, [want] if isinstance(want, str) else want, D,
               frames=frames, tap=tap, **opts)

    talk("dialog: nothing queued, nothing shown", "", 5, None, ".....")
    # "Hello there" is 11 letters: at 60 a second it is all showing on frame 11.
    talk("dialog: A shows the rest of the text, and A again moves on",
         "dialog.speed = 60 dialog.say('Elder', 'Hello there')", 12, "a@4,a@8", "#######.....")
    talk("dialog: text that has finished appearing needs one press",
         "dialog.speed = 60 dialog.say(nil, 'Hello there')", 16, "a@14", "#############...")
    talk("dialog: holding A down does not skip through",
         "dialog.speed = 0 dialog.say(nil, 'One') dialog.say(nil, 'Two') dialog.say(nil, 'Three')", 60, "a@3-58",
         "##" + "#" * 58)
    talk("dialog: each press reads one thing, in the order they were said",
         "dialog.speed = 0 dialog.say(nil, 'One', function() log = log .. '1' end)"
         " dialog.say(nil, 'Two', function() log = log .. '2' end)", 9, "a@3,a@6", "##1###2....")
    talk("dialog: a button already down when the talking starts does not count",
         "dialog.speed = 0 function init() end local said"
         " local u = update function update(dt) if stat('frame') == 3 then dialog.say(nil, 'Hi') end u(dt) end",
         10, "a@2-5,a@8", "..#####...")
    long = " ".join(["word"] * 40)                    # 199 letters: 36 a line, 3 lines a box, so 2 boxes
    talk("dialog: long text is wrapped and split over as many boxes as it needs",
         f"dialog.speed = 0 dialog.say(nil, '{long}')", 10, "a@3,a@6", "#####.....")
    fits = " ".join(["aaaa bbbb cccc dddd eeee ffff gggg h"] * 3)          # three lines of exactly 36 letters
    talk("dialog: a line may be filled to its last letter",
         f"dialog.speed = 0 dialog.say(nil, '{fits}')", 6, "a@3", "##....")
    over = " ".join(["aaaa bbbb cccc dddd eeee ffff gggg hh"] * 3)         # one letter too many for a line
    talk("dialog: a line one letter too long is wrapped, not squeezed in",
         f"dialog.speed = 0 dialog.say(nil, '{over}')", 8, "a@3,a@6", "#####...")
    talk("dialog: after clear, a button still held does not answer what is said next",
         "dialog.speed = 0 dialog.say(nil, 'One')"
         " local u = update function update(dt) local f = stat('frame')"
         " if f == 3 then dialog.clear() end if f == 5 then dialog.say(nil, 'Two') end u(dt) end",
         12, "a@4-7,a@10", "##..#####...")
    talk("dialog: a new line can be forced, and a word too long for a line is cut",
         "dialog.speed = 0 dialog.say(nil, 'a\\nb\\nc\\nd') dialog.say(nil, string.rep('x', 36 * 3 + 1))",
         14, "a@2,a@4,a@6,a@8", "#######.......")
    talk("dialog: done may say more, and it follows straight on",
         "dialog.speed = 0 dialog.say(nil, 'One', function() dialog.say(nil, 'Two') end)", 9, "a@3,a@6", "#####....")
    talk("dialog: a question waits for an answer; up and down choose and A picks",
         "dialog.speed = 0 dialog.ask('Elder', 'Help us?', { 'Yes', 'No', 'Later' },"
         " function(i, text) log = log .. i .. text end)", 9, "down@2,down@4,up@6,a@8", "#######2No..")
    talk("dialog: choosing wraps round from the last answer to the first, and back",
         "dialog.speed = 0 dialog.ask(nil, 'Well?', { 'A', 'B' }, function(i) log = log .. i end)"
         " dialog.ask(nil, 'And?', { 'A', 'B' }, function(i) log = log .. i end)",
         12, "up@2,a@4,down@6,down@8,a@10", "###2######1...")
    talk("dialog: an answer cannot be picked while the question is still appearing",
         "dialog.speed = 60 dialog.ask(nil, 'Are you sure?', { 'Yes', 'No' }, function(i) log = log .. i end)",
         10, "down@2,a@4,down@6,a@8", "#######2...")
    talk("dialog: clear drops everything, and active reports whether anything shows",
         "dialog.say(nil, 'One') dialog.say(nil, 'Two') dbg(dialog.active()) dialog.clear() dbg(dialog.active())",
         3, None, ["true", "false", "..."])
    fails("dialog: a question with no answers is an error",
          "require('dialog').ask(nil, 'Well?', {})", D, "answers", "main.lua:1")
    r = t.run_game("local dialog = require('dialog') dialog.blip = 0 dialog.speed = 30"
                   " dialog.say(nil, 'Tick tick tick tick tick') function update(dt) dialog.update(dt) end",
                   extra=dict(helper(*D), **{"sfx.oli": pulli.bank("sfx", [(8000, 1, [9000] * 40, None, pulli.PCM)])}),
                   frames=40, sound=True)
    heard = r.sound                               # worked out afresh each time it is asked for
    blips = sum(1 for i in range(1, len(heard)) if heard[i][0] and not heard[i - 1][0])
    t.check(f"dialog: a blip plays as the letters appear ({blips} in 40 frames)", r.code == 0 and 5 <= blips <= 14, r.err)

    # What the box looks like is pinned as a picture; look at tests/dialog.png after an intended change.
    scene = """local dialog = require('dialog') dialog.speed = 0
               dialog.ask('Elder', 'The road north is closed, traveller. Will you help us open it again?',
                          { 'Yes, gladly', 'Not now' })
               function update(dt) dialog.update(dt) end
               function draw() cls(1) dialog.draw() end"""
    r = t.run_game(scene, extra=helper(*D), frames=3, tap="down@2")
    words = sum(1 for v in r.fb if v == 7)
    t.check("dialog: it draws a box, the speaker's name, the text and the answers",
            r.code == 0 and r.fb[178 * 320 + 10] == 32 and r.fb[100 * 320 + 100] == 1 and words > 1500
            and any(v == 10 for v in r.fb[165 * 320:176 * 320]), r.err)
    quiet = t.run_game("local dialog = require('dialog') function update(dt) dialog.update(dt) end"
                       " function draw() cls(1) dialog.draw() end", extra=helper(*D), frames=3)
    t.check("dialog: with nothing to say it draws nothing", quiet.code == 0 and set(quiet.fb) == {1}, quiet.err)

    # ---- quest -------------------------------------------------------------------------
    Q = ("quest",)
    DEF = """local quest = require('quest')
             quest.define('gems', 'The Lost Gems', { 'Talk to the elder', { 'Find three gems', need = 3 }, 'Bring them back' })
             quest.define('well', 'The Dry Well', { 'Mend the rope' }) """
    expect("quest: a quest is new until started, then moves through its steps to done",
           DEF + """dbg(quest.state('gems'), quest.step('gems'), quest.title('gems'))
           dbg(quest.start('gems'), quest.start('gems'), quest.state('gems')) dbg(quest.step('gems'))
           dbg(quest.advance('gems')) dbg(quest.step('gems'))
           dbg(quest.advance('gems'), quest.advance('gems')) dbg(quest.step('gems'))
           dbg(quest.advance('gems')) dbg(quest.step('gems'))
           dbg(quest.advance('gems'), quest.state('gems'), quest.step('gems'), quest.advance('gems'))""",
           ["new\tnil\tThe Lost Gems", "true\tfalse\tactive", "1\tTalk to the elder\t0\t1", "false",
            "2\tFind three gems\t0\t3", "false\tfalse", "2\tFind three gems\t2\t3", "false",
            "3\tBring them back\t0\t1", "true\tdone\tnil\tfalse"], Q)
    expect("quest: several can be counted at once, and a quest not started does not move",
           DEF + """dbg(quest.advance('well'), quest.state('well')) quest.start('gems') quest.advance('gems')
           dbg(quest.advance('gems', 2)) dbg(quest.step('gems')) dbg(quest.advance('gems', 5)) dbg(quest.step('gems'))""",
           ["false\tnew", "false", "2\tFind three gems\t2\t3", "false", "3\tBring them back\t0\t1"], Q)
    expect("quest: the game is told when a quest starts, moves on and is done",
           DEF + """local log = '' quest.on_change = function(id, state) log = log .. id .. ':' .. state .. ' ' end
           quest.start('well') quest.start('gems') quest.advance('gems') quest.advance('gems') quest.advance('well')
           dbg(log)""", ["well:active gems:active gems:active well:done "], Q)
    expect("quest: quests are listed in the order they were defined, and reset puts them all back",
           DEF + """dbg(quest.count(), quest.id(1), quest.id(2), quest.id(3)) quest.start('gems') quest.start('well')
           quest.advance('well') quest.reset() dbg(quest.state('gems'), quest.state('well'), quest.start('well'))""",
           ["2\tgems\twell\tnil", "new\tnew\ttrue"], Q)
    with tempfile.TemporaryDirectory() as saves:
        t.run_game(DEF + "quest.start('gems') quest.advance('gems') quest.advance('gems', 2) quest.start('well')"
                   " quest.advance('well') dbg(quest.save('q'))", manifest=SAVES, saves=saves, extra=helper(*Q))
        expect("quest: saved progress comes back in a later run",
               DEF + """dbg(quest.load('q'), quest.state('gems'), quest.state('well')) dbg(quest.step('gems'))
               dbg(quest.load('nothing'))""",
               ["true\tactive\tdone", "2\tFind three gems\t2\t3", "false"], Q, manifest=SAVES, saves=saves)
        expect("quest: saved progress that no longer fits the quest is left alone",
               """local quest = require('quest') quest.define('gems', 'Shorter now', { 'Only step' })
               quest.define('well', 'The Dry Well', { 'Mend the rope' })
               dbg(quest.load('q'), quest.state('gems'), quest.state('well'))""",
               ["true\tnew\tdone"], Q, manifest=SAVES, saves=saves)
    with tempfile.TemporaryDirectory() as saves:
        t.run_game("save('q.gems', 'active 2 7') save('q.well', 'asleep 1 0')", manifest=SAVES, saves=saves)
        expect("quest: a saved count or state that makes no sense is left alone",
               DEF + "dbg(quest.load('q'), quest.state('gems'), quest.state('well'))",
               ["false\tnew\tnew"], Q, manifest=SAVES, saves=saves)
    fails("quest: a quest that was never defined is an error that names it",
          "require('quest').start('dragon')", Q, "dragon", "main.lua:1")
    fails("quest: a quest with no steps is an error", "require('quest').define('x', 'X', {})", Q, "at least one step")

    # ---- particles ---------------------------------------------------------------------
    P = ("particles",)
    expect("particles: they are sent out, live their time and are gone",
           """local set = require('particles').new(50) set:emit(100, 100, 12, { life = 0.5 }) dbg(set:count())
           for i = 1, 29 do set:update(1 / 60) end dbg(set:count())
           for i = 1, 2 do set:update(1 / 60) end dbg(set:count())""", ["12", "12", "0"], P)
    expect("particles: a full set drops what does not fit, and clear empties it",
           """local set = require('particles').new(10) set:emit(0, 0, 8) set:emit(0, 0, 8) dbg(set:count())
           set:clear() dbg(set:count()) set:emit(0, 0) dbg(set:count())""", ["10", "0", "1"], P)
    expect("particles: particles of different lives are each removed at their own time",
           """local set = require('particles').new(50)
           set:emit(0, 0, 5, { life = 0.1 }) set:emit(0, 0, 7, { life = 1 }) set:emit(0, 0, 3, { life = 0.1 })
           for i = 1, 10 do set:update(1 / 60) end dbg(set:count())
           set:emit(0, 0, 4, { life = 0.05 }) for i = 1, 5 do set:update(1 / 60) end dbg(set:count())""",
           ["7", "7"], P)
    expect("particles: they go the way they are sent: right at 0 degrees, up at 90",
           R + """local set = require('particles').new(4)
           set:emit(100, 100, 1, { angle = 0, spread = 0, speed = 60, jitter = 0, life = 9 })
           set:emit(100, 100, 1, { angle = 90, spread = 0, speed = 60, jitter = 0, life = 9 })
           for i = 1, 60 do set:update(1 / 60) end
           dbg(r(set[1].x), r(set[1].y), r(set[2].x), r(set[2].y))""", ["160.0\t100.0\t100.0\t40.0"], P)
    expect("particles: a spread keeps them inside its fan, and jitter varies their speed",
           """local set = require('particles').new(200)
           set:emit(0, 0, 200, { angle = 90, spread = 60, speed = 100, jitter = 0.5, life = 9 })
           local inside, slowest, fastest = true, 1e9, 0
           for i = 1, 200 do
             local p = set[i] local v = math.sqrt(p.vx * p.vx + p.vy * p.vy)
             local a = math.deg(math.atan(-p.vy, p.vx))
             inside = inside and a >= 59.9 and a <= 120.1
             slowest, fastest = math.min(slowest, v), math.max(fastest, v)
           end
           dbg(inside, slowest >= 49.9, slowest < 60, fastest > 90, fastest <= 100.1)""",
           ["true\ttrue\ttrue\ttrue\ttrue"], P)
    expect("particles: gravity pulls them down and drag slows them",
           R + """local set = require('particles').new(4)
           set:emit(0, 0, 1, { angle = 0, spread = 0, speed = 60, jitter = 0, life = 9, gravity = 120 })
           set:emit(0, 0, 1, { angle = 0, spread = 0, speed = 60, jitter = 0, life = 9, drag = 2 })
           for i = 1, 60 do set:update(1 / 60) end
           dbg(r(set[1].x), set[1].y > 55 and set[1].y < 65, set[2].x > 20 and set[2].x < 30, r(set[2].y))""",
           ["60.0\ttrue\ttrue\t0.0"], P)
    r = t.run_game("""local set = require('particles').new(8)
                   set:emit(50, 50, 1, { speed = 0, life = 1, colors = { 10, 9, 8 } })
                   set:emit(100, 50, 1, { speed = 0, life = 1, size = 4, colors = { 12 } })
                   local shot = {}
                   function update(dt) set:update(dt) end
                   function draw() cls() set:draw() local f = stat('frame')
                     if f == 10 or f == 30 or f == 50 then shot[#shot + 1] = pget(50, 50) end
                     if f == 50 then dbg(shot[1], shot[2], shot[3], pget(100, 50), pget(98, 48), pget(101, 51), pget(102, 50)) end
                     if f == 70 then dbg(pget(50, 50), pget(100, 50)) end end""", extra=helper(*P), frames=70)
    t.check("particles: a particle changes colour as it ages, a larger one is a square, and both vanish",
            r.code == 0 and r.lines == ["10\t9\t8\t12\t12\t12\t0", "0\t0"], f"{r.lines}\n{r.err}")
    expect("particles: emitting and updating make no garbage",
           """local set = require('particles').new(100) local style = { life = 0.2, gravity = 50 }
           for i = 1, 30 do set:emit(10, 10, 5, style) set:update(1 / 60) end
           collectgarbage() collectgarbage('stop') local before = collectgarbage('count')
           for i = 1, 300 do set:emit(10, 10, 5, style) set:update(1 / 60) end
           dbg(collectgarbage('count') - before == 0)""", ["true"], P)

    # ---- the add command ---------------------------------------------------------------
    tool = [sys.executable, os.path.join(ROOT, "tools", "pulli.py")]
    listing = subprocess.run(tool + ["add"], capture_output=True, text=True).stdout
    t.check("pulli.py add lists the helpers with a line about each",
            all(n in listing for n in ("camera_follow", "dialog", "inventory", "particles", "quest", "tween"))
            and "carrying" in listing, listing)
    with tempfile.TemporaryDirectory() as tmp:
        game = os.path.join(tmp, "g")
        subprocess.run(tool + ["new", game], capture_output=True)
        added = subprocess.run(tool + ["add", game, "tween", "dialog"], capture_output=True, text=True)
        same = open(os.path.join(game, "tween.lua")).read() == open(os.path.join(SDK, "tween.lua")).read()
        t.check("pulli.py add copies helpers into a game", added.returncode == 0 and same, added.stderr)
        t.check("a copy in the game's folder is used in place of the SDK's",
                dict(pulli.parse(pulli.build(game)))["tween.lua"] == open(os.path.join(game, "tween.lua"), "rb").read())
        open(os.path.join(game, "dialog.lua"), "w").write("return { mine = true }")
        open(os.path.join(game, "main.lua"), "w").write("dbg(require('dialog').mine)")
        r = t.run_package(pulli.build(game), frames=1)
        t.check("a game that changes its copy gets its own version", r.code == 0 and r.lines == ["true"], r.err)
        again = subprocess.run(tool + ["add", game, "tween"], capture_output=True, text=True)
        t.check("pulli.py add will not overwrite a helper the developer may have changed",
                again.returncode == 1 and "already exists" in again.stderr, again.stderr)
        t.check("pulli.py add refuses a helper that does not exist",
                subprocess.run(tool + ["add", game, "nope"], capture_output=True).returncode == 1)
        open(os.path.join(game, "main.lua"), "w").write(
            "local tween = require('tween') local o = { x = 0 } tween.to(o, { x = 1 }, 0)"
            " function update(dt) tween.update(dt) end function draw() if o.x == 1 then dbg('ok') o.x = 2 end end")
        r = t.run_package(pulli.build(game), frames=3)
        t.check("a game packed with a helper in its folder can require it", r.code == 0 and r.lines == ["ok"], r.err)

    # ---- helpers supplied when a game is packed -----------------------------------------
    def packed(files):
        with tempfile.TemporaryDirectory() as tmp:
            for name, text in dict({"manifest.lua": 'return { id = "t.p", title = "P", spec = 1 }'}, **files).items():
                open(os.path.join(tmp, name), "w").write(text)
            return pulli.build(tmp)

    def names(files):
        return sorted(n for n, _ in pulli.parse(packed(files)) if n not in ("main.lua", "manifest.lua"))

    t.check("pack supplies a helper the game requires and does not have",
            names({"main.lua": "local tween = require('tween')"}) == ["tween.lua"]
            and dict(pulli.parse(packed({"main.lua": "require('tween')"})))["tween.lua"]
            == open(os.path.join(SDK, "tween.lua"), "rb").read())
    t.check("every way of writing require is seen",
            names({"main.lua": 'require "tween"\nlocal d = require( "dialog" )\nq = require\'quest\''})
            == ["dialog.lua", "quest.lua", "tween.lua"])
    t.check("a game that requires no helper gets none", names({"main.lua": "local x = 1"}) == [])
    t.check("a helper only mentioned in a comment is not supplied",
            names({"main.lua": "-- local tween = require('tween')\n--[[ require('dialog')\n require('quest') ]]\nlocal x = 1"}) == [])
    t.check("a helper required from one of the game's own modules is supplied too",
            names({"main.lua": "require('world')", "world.lua": "return require('particles')"})
            == ["particles.lua", "world.lua"])
    r = t.run_package(packed({"main.lua": "local bag = require('inventory').new() bag:add('gem') dbg(bag:count('gem'))"}))
    t.check("a game runs with a helper it never copied in", r.code == 0 and r.lines == ["1"], r.err)
    try:
        packed({"main.lua": "require('dragons')"})
        t.check("requiring something that is neither in the game nor in the SDK is refused at packing", False)
    except pulli.PackageError as e:
        t.check("requiring something that is neither in the game nor in the SDK is refused at packing",
                "dragons" in str(e), str(e))
    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
