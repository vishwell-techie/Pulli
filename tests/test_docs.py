#!/usr/bin/env python3
"""The game developer's guide in docs/guide, checked against the real thing.

Run: python3 tests/test_docs.py

  - every step of the tutorial runs, and the last one is examples/catch;
  - the reference documents every function the runtime gives a game, and
    nothing it does not;
  - the helpers page names every helper in sdk/;
  - every link between the pages leads somewhere.
"""
import os, re, sys

from harness import Suite, ROOT, pulli

GUIDE = os.path.join(ROOT, "docs", "guide")
CATCH = os.path.join(ROOT, "examples", "catch")

# The parts of standard Lua a game gets; everything else global is Pulli's.
LUA = {"assert", "collectgarbage", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "rawequal",
       "rawget", "rawlen", "rawset", "select", "setmetatable", "tonumber", "tostring", "type", "xpcall", "warn",
       "_G", "_VERSION", "string", "table", "math", "utf8", "coroutine"}
CALLBACKS = {"init", "update", "draw"}


def page(name):
    return open(os.path.join(GUIDE, name)).read()


def main():
    t = Suite("Pulli developer's guide")

    # ---- the tutorial runs ---------------------------------------------------------
    tutorial = page("tutorial.md")
    steps = re.findall(r"```lua\n(-- step (\d+):.*?)```", tutorial, re.S)
    t.check("the tutorial has its eight steps, in order", [int(n) for _, n in steps] == list(range(1, 9)))
    final = open(os.path.join(CATCH, "main.lua")).read()
    t.check("the tutorial's last step is examples/catch/main.lua, word for word",
            steps and steps[-1][0] == final)
    if t.need_runtime("running the tutorial's steps"):
        assets = dict(pulli.parse(pulli.build(CATCH)))
        manifest = assets.pop("manifest.lua").decode()
        assets.pop("main.lua")
        for code, n in steps:
            extra = dict(assets)
            for helper in sorted(pulli.required(code.encode())):
                extra[helper + ".lua"] = open(os.path.join(ROOT, "sdk", helper + ".lua"), "rb").read()
            # Start the game, play a while, let it end, and start again.
            r = t.run_game(code, manifest=manifest, extra=extra, frames=2400, hold="right",
                           tap="a@30,a@1800,a@1900,a@2000")
            t.check(f"tutorial step {n} runs for 40 seconds of play without an error", r.code == 0, r.err)

    # ---- the reference matches the runtime -----------------------------------------
    reference = page("reference.md")
    documented = set(re.findall(r"^### `([A-Za-z_][\w.]*)\(", reference, re.M))
    if t.need_runtime("comparing the reference with the runtime"):
        r = t.run_game("""local names = {}
            for k, v in pairs(_G) do
              if type(v) == 'function' then names[#names + 1] = k
              elseif type(v) == 'table' and (k == 'map' or k == 'link' or k == 'sys' or k == 'fix') then
                for kk, vv in pairs(v) do if type(vv) == 'function' then names[#names + 1] = k .. '.' .. kk end end
              end
            end
            table.sort(names) dbg(table.concat(names, ' '))""")
        given = set(r.out.split()) - LUA
        t.check("the reference documents every function the runtime gives a game",
                r.code == 0 and given <= documented, sorted(given - documented))
        t.check("the reference documents no function the runtime does not have",
                documented - CALLBACKS <= given, sorted(documented - CALLBACKS - given))

    # ---- the helpers page names every helper ---------------------------------------
    helpers = page("helpers.md")
    have = {f[:-4] for f in os.listdir(os.path.join(ROOT, "sdk")) if f.endswith(".lua")}
    listed = set(re.findall(r"^\| `(\w+)` \|", helpers, re.M))
    t.check(f"the helpers page lists every helper in sdk/, and only those ({len(have)})", listed == have,
            f"missing: {sorted(have - listed)}, not in sdk/: {sorted(listed - have)}")
    t.check("the guide's count of helpers is right",
            f"{len(have)} ready-made" in page("README.md") and f"comes with {len(have)} helpers" in helpers)

    # ---- links lead somewhere --------------------------------------------------------
    for name in sorted(f for f in os.listdir(GUIDE) if f.endswith(".md")):
        text = page(name)
        broken = []
        for target in re.findall(r"\]\(([^)#\s]+)(?:#[^)]*)?\)", text):
            if not re.match(r"[a-z]+://", target) and not os.path.exists(os.path.join(GUIDE, target)):
                broken.append(target)
        t.check(f"{name}: every link leads to a file that exists", not broken, broken)
    t.check("the README points to the guide", "docs/guide" in open(os.path.join(ROOT, "README.md")).read())
    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
