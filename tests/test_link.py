#!/usr/bin/env python3
"""The console-to-console link, tested between two headless hosts.

Run: python3 tests/test_link.py

The headless host links in step: a message sent during frame N arrives
during frame N + 1, every time, so these runs are exactly repeatable.
"""
import os, sys

from harness import Suite, ROOT, pulli

# Says what it sees every frame, and sends its side and frame number.
TALKER = """
    function update()
      local f = stat('frame')
      local got = ''
      while true do
        local m = link.recv()
        if not m then break end
        got = got .. '[' .. m .. ']'
      end
      dbg(f, link.status(), link.side(), got)
      if f <= 3 then link.send('s' .. link.side() .. 'f' .. f) end
      if f == 2 then link.send('second') end
    end
"""


def main():
    t = Suite("Pulli link")
    if not t.need_runtime("everything in this file"):
        return t.finish()

    def expect(name, r, lines):
        t.check(name, r.code == 0 and r.lines == lines,
                f"exit {r.code}\nstdout: {r.lines}\nwanted: {lines}\nstderr: {r.err}")

    r = t.run_game("""
        dbg(sys.has('link'), link.status(), link.side(), link.send('hello'), link.recv())
    """)
    expect("with no link hardware everything answers quietly", r, ["false\toff\tnil\tfalse\tnil"])

    a, b = t.run_linked(t.package(TALKER), t.package(TALKER), {"frames": 5}, {"frames": 5})
    expect("side 1: messages arrive one frame after they were sent, whole and in order", a, [
        "1\tconnected\t1\t",
        "2\tconnected\t1\t[s2f1]",
        "3\tconnected\t1\t[s2f2][second]",
        "4\tconnected\t1\t[s2f3]",
        "5\tconnected\t1\t",
    ])
    expect("side 2 sees the same from the other end", b, [
        "1\tconnected\t2\t",
        "2\tconnected\t2\t[s1f1]",
        "3\tconnected\t2\t[s1f2][second]",
        "4\tconnected\t2\t[s1f3]",
        "5\tconnected\t2\t",
    ])

    probe = """
        function update()
          if stat('frame') == 1 then
            local sent = 0
            for i = 1, 12 do if link.send('m' .. i) then sent = sent + 1 end end
            dbg(sys.has('link'), sent, link.send(string.rep('x', 64)), link.send(string.rep('x', 65)))
          elseif stat('frame') == 2 then
            dbg(link.send(''), link.send(string.rep('y', 64)), link.send(string.rep('y', 65)))
          end
        end
    """
    counter = """
        local n, bytes = 0, 0
        function update()
          while true do
            local m = link.recv()
            if not m then break end
            n = n + 1
            bytes = bytes + #m
          end
          if stat('frame') == 4 then dbg(n, bytes) end
        end
    """
    a, b = t.run_linked(t.package(probe), t.package(counter), {"frames": 4}, {"frames": 4})
    expect("a frame carries at most 8 messages of at most 64 bytes", a,
           ["true\t8\tfalse\tfalse", "true\ttrue\tfalse"])
    expect("exactly what was accepted is delivered", b, ["10\t" + str(2 + 2 + 2 + 2 + 2 + 2 + 2 + 2 + 0 + 64)])

    leaver = "function update() link.send('bye') end"
    stayer = """
        function update()
          local m = link.recv()
          dbg(stat('frame'), link.status(), link.side(), m, link.send('anyone?'))
        end
    """
    a, b = t.run_linked(t.package(leaver), t.package(stayer), {"frames": 2}, {"frames": 5})
    expect("when the other console leaves, the link goes back to waiting", b, [
        "1\tconnected\t2\tnil\ttrue",
        "2\tconnected\t2\tbye\ttrue",
        "3\tconnected\t2\tbye\ttrue",
        "4\twaiting\tnil\tnil\tfalse",
        "5\twaiting\tnil\tnil\tfalse",
    ])

    r = t.run_game("function update() dbg(link.status(), link.side(), link.send('x')) end", link=45999)
    t.check("a console with nobody to talk to waits, and does not hang for ever",
            r.code == 0 and r.lines == ["waiting\tnil\tfalse"], f"{r.lines} {r.err}")

    # ---- Pong over the link -------------------------------------------
    # Both consoles pick LINK PLAY ("up" from the first menu entry wraps to
    # it), then side 1 presses A on frame 40.
    pong = pulli.build(os.path.join(ROOT, "examples", "pong"))
    PICK, START = "up@1", "up@1,a@40"

    def match(frames, host_tap=START, guest_tap=PICK, guest_frames=None, guest_hold=None):
        a, b = t.run_linked(pong, pong, {"frames": frames, "tap": host_tap},
                            {"frames": guest_frames or frames, "tap": guest_tap, "hold": guest_hold})
        if a.code or b.code:
            t.check(f"linked pong runs ({frames} frames, {host_tap} / {guest_tap})", False, a.err + b.err)
        return a.fb, b.fb

    lobby = match(200, host_tap=PICK)
    host, guest = match(120)
    t.check("pong: a link match starts, and both screens leave the menu",
            host != lobby[0] and guest != lobby[1])
    t.check("pong: side 2 draws exactly what side 1 drew one frame earlier", match(121)[1] == host)
    t.check("pong: a linked match is the same every time it is run", match(120) == (host, guest))

    whole = match(3000)
    t.check("pong: a whole link match finishes, one side winning and the other losing",
            whole[0] != whole[1] and whole == match(3200))
    t.check("pong: side 2's paddle moves on side 1's screen",
            match(400, guest_hold="down")[0] != match(400)[0])

    frozen = match(200, guest_tap=PICK + ",start@100")
    t.check("pong: side 2 can pause the match for both",
            frozen == match(260, guest_tap=PICK + ",start@100") and frozen[0] != match(200)[0])
    t.check("pong: and resume it", match(300, guest_tap=PICK + ",start@100,start@150")[0] == match(250)[0])
    t.check("pong: side 2 giving up returns both to the menu",
            match(200, guest_tap=PICK + ",start@100,select@130") == lobby)

    alone = match(300, guest_frames=150)[0]
    t.check("pong: if the other console goes away mid-match, side 1 falls back to the menu",
            alone == match(400, guest_frames=150)[0] and alone != lobby[0] and alone != match(300)[0])
    host, guest = match(200, guest_tap="a@100")
    t.check("pong: side 1 cannot start until side 2 has chosen link play",
            host != lobby[0] and host == match(260, guest_tap="a@100")[0])

    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
