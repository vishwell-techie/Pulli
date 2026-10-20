#!/usr/bin/env python3
"""The game developer's guide in docs/guide, checked against the real thing.

Run: python3 tests/test_docs.py

  - every step of the tutorial runs, and the last one is examples/catch;
  - the reference documents every function the runtime gives a game, and
    nothing it does not;
  - the helpers page names every helper in sdk/;
  - every link between the pages leads somewhere;
  - the Tamil guide (docs/guide/ta) and README.ta.md have a page for every
    English one, with exactly the same code, and the pages link both ways.
"""
import os, re, sys

from harness import Suite, ROOT, pulli

GUIDE = os.path.join(ROOT, "docs", "guide")
TAMIL = os.path.join(GUIDE, "ta")
FENCE = re.compile(r"^( *)```[^\n]*\n.*?^\1```[ \t]*$", re.M | re.S)
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
              elseif type(v) == 'table' and (k == 'map' or k == 'link' or k == 'sys' or k == 'fix' or k == 'sheet') then
                for kk, vv in pairs(v) do if type(vv) == 'function' then names[#names + 1] = k .. '.' .. kk end end
              end
            end
            table.sort(names) for i = 1, #names do dbg(names[i]) end""")   # one a line: dbg cuts long lines
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

    # ---- the Tamil translation ---------------------------------------------------------
    english = sorted(f for f in os.listdir(GUIDE) if f.endswith(".md"))
    tamil = sorted(f for f in os.listdir(TAMIL) if f.endswith(".md"))
    t.check("the Tamil guide has a page for every English page, and no others", tamil == english,
            f"English: {english}, Tamil: {tamil}")
    pairs = [(os.path.join(GUIDE, f), os.path.join(TAMIL, f)) for f in english if f in tamil]
    pairs.append((os.path.join(ROOT, "README.md"), os.path.join(ROOT, "README.ta.md")))
    for en, ta in pairs:
        label = os.path.relpath(ta, ROOT)
        if not os.path.exists(ta):
            t.check(f"{label} exists", False)
            continue
        en_text, ta_text = open(en).read(), open(ta).read()
        same = [m.group(0) for m in FENCE.finditer(en_text)] == [m.group(0) for m in FENCE.finditer(ta_text)]
        t.check(f"{label}: has exactly the English page's code, in the same order", same)
        back = os.path.relpath(en, os.path.dirname(ta))
        there = os.path.relpath(ta, os.path.dirname(en))
        t.check(f"{label}: links to the English page, and the English page links to it",
                f"]({back})" in ta_text and f"]({there})" in en_text)
        broken = [target for target in re.findall(r"\]\(([^)#\s]+)(?:#[^)]*)?\)", ta_text)
                  if not re.match(r"[a-z]+://", target)
                  and not os.path.exists(os.path.join(os.path.dirname(ta), target))]
        t.check(f"{label}: every link leads to a file that exists", not broken, broken)
    if os.path.exists(os.path.join(TAMIL, "reference.md")):
        ta_documented = set(re.findall(r"^### `([A-Za-z_][\w.]*)\(", page("ta/reference.md"), re.M))
        t.check("the Tamil reference documents the same functions as the English one", ta_documented == documented,
                f"missing: {sorted(documented - ta_documented)}, extra: {sorted(ta_documented - documented)}")
    if os.path.exists(os.path.join(TAMIL, "helpers.md")):
        ta_listed = set(re.findall(r"^\| `(\w+)` \|", page("ta/helpers.md"), re.M))
        t.check("the Tamil helpers page lists every helper in sdk/, and its count is right",
                ta_listed == have and f"{len(have)} உதவி நிரல்" in page("ta/helpers.md")
                and f"{len(have)} Lua உதவி நிரல்" in page("ta/README.md"), sorted(have ^ ta_listed))
    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
