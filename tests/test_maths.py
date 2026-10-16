#!/usr/bin/env python3
"""The maths functions, tested from Lua through the real C runtime.

Run: python3 tests/test_maths.py

SPEC §4 promises that sin, cos, ^, % and the rest give the same bits on
every machine. Three things are checked here:

  - the runtime's self-check returns the value recorded in runtime/pmath.h,
    which is what a new port compares itself with;
  - the host program takes none of these functions from the C library;
  - what Lua gets back is the true result to within one unit in the last
    place, using Python's double-precision maths as the reference;
  - the 16.16 fixed-point functions (SPEC §3) match the same sums done
    here with Python's unlimited integers.
"""
import math, shutil, struct, subprocess, sys
from fractions import Fraction

from harness import Suite

LIBRARY = {"sinf", "cosf", "tanf", "asinf", "acosf", "atanf", "atan2f", "expf", "logf",
           "log2f", "log10f", "powf", "sin", "cos", "tan", "asin", "acos", "atan", "atan2",
           "exp", "log", "log2", "log10", "pow", "fmodf", "fmod"}
PER_CASE = 2000
LIMIT = 0.55            # units in the last place; a perfect answer is at most 0.5


def f32(b):
    return struct.unpack("<f", struct.pack("<I", b))[0]


def nearest(v):
    try:
        return struct.unpack("<f", struct.pack("<f", v))[0]
    except OverflowError:
        return math.copysign(math.inf, v)


def ulp(v):
    return 2.0 ** (max(math.frexp(v)[1] - 1, -126) - 23) if v else 2.0 ** -149


# ---- inputs: the same sequence is produced here and in Lua ----------------
ANY, MID, UNIT, NEAR1 = (0, 256), (113, 22), (103, 24), (126, 2)


class Sequence:
    def __init__(self):
        self.seed = 0x50554C49

    def next(self):
        self.seed = (self.seed * 1664525 + 1013904223) & 0xFFFFFFFF
        return self.seed

    def pick(self, lo, span, positive=False):
        r = self.next()
        b = (r & 0x807FFFFF) | ((lo + ((r >> 23) & 0xFF) % span) << 23)
        return b & 0x7FFFFFFF if positive else b


LUA_HEAD = """
local seed, row, n = 0x50554C49, {}, 0
local function pick(lo, span, positive)
  seed = seed * 1664525 + 1013904223
  local b = (seed & 0x807FFFFF) | ((lo + ((seed >> 23) & 0xFF) % span) << 23)
  if positive then b = b & 0x7FFFFFFF end
  return (string.unpack("<f", string.pack("<i4", b)))
end
local function out(v)
  n = n + 1
  row[n] = string.format("%08x", (string.unpack("<i4", string.pack("<f", v))))
  if n == 32 then dbg(table.concat(row, " ", 1, n)); n = 0 end
end
"""


# ---- what the right answer is ---------------------------------------------
def trig(fn):
    return lambda x: math.nan if math.isinf(x) else fn(x)


def inverse(fn):
    return lambda x: math.nan if abs(x) > 1 else fn(x)


def log(fn):
    return lambda x: -math.inf if x == 0 else math.nan if x < 0 else fn(x)


def exp(x):
    try:
        return math.exp(x)
    except OverflowError:
        return math.inf


def power(x, y):
    if y == 0 or x == 1:
        return 1.0
    if math.isnan(x) or math.isnan(y):
        return math.nan
    odd = y == math.floor(y) and abs(y) < 2.0 ** 24 and int(y) % 2 == 1
    sign = -1.0 if math.copysign(1, x) < 0 and odd else 1.0
    try:
        return math.pow(x, y)
    except OverflowError:
        return sign * math.inf
    except ValueError:                      # 0 to a negative power, or a root of a negative
        return sign * math.inf if x == 0 else math.nan


# name, Lua expression, reference, then one list of argument kinds per case
def fmod(x, y):
    """The remainder of x / y with the sign of x: exact in doubles, so exact here."""
    if y == 0 or math.isinf(x) or math.isnan(x) or math.isnan(y):
        return math.nan
    return math.fmod(x, y)


CASES = [
    ("sin",   "math.sin(a)",     trig(math.sin),      [[ANY], [MID]]),
    ("cos",   "math.cos(a)",     trig(math.cos),      [[ANY], [MID]]),
    ("tan",   "math.tan(a)",     trig(math.tan),      [[ANY], [MID]]),
    ("asin",  "math.asin(a)",    inverse(math.asin),  [[UNIT], [ANY]]),
    ("acos",  "math.acos(a)",    inverse(math.acos),  [[UNIT], [ANY]]),
    ("atan",  "math.atan(a, b)", math.atan2,          [[ANY, ANY], [MID, MID]]),
    ("exp",   "math.exp(a)",     exp,                 [[ANY], [MID]]),
    ("log",   "math.log(a)",     log(math.log),       [[ANY], [MID + (True,)], [NEAR1 + (True,)]]),
    ("log2",  "math.log(a, 2)",  log(math.log2),      [[ANY], [MID + (True,)], [NEAR1 + (True,)]]),
    ("log10", "math.log(a, 10)", log(math.log10),     [[ANY], [MID + (True,)], [NEAR1 + (True,)]]),
    ("^",     "a ^ b",           power,               [[ANY, ANY], [MID + (True,), MID],
                                                       [NEAR1 + (True,), MID], [UNIT, MID]]),
    # fmod has one right answer, and a C library may miss it: Lua's % and
    # math.fmod use the runtime's own, which must find it every time.
    ("fmod",  "math.fmod(a, b)", fmod,                [[ANY, ANY], [MID, MID], [ANY, MID]]),
]


def error_in_ulps(got, want):
    """How far `got` is from the true result `want`; 99 means plainly wrong."""
    if math.isnan(want) or math.isnan(got):
        return 0.0 if math.isnan(want) and math.isnan(got) else 99.0
    if math.isinf(got) or math.isinf(want):
        return 0.0 if got == nearest(want) else 99.0
    if got == 0 and nearest(want) == 0 and math.copysign(1, got) != math.copysign(1, want):
        return 99.0
    return abs(got - want) / ulp(want)


# ---- fixed point: the right answers, from exact integer arithmetic -------
def wrap(v):
    v &= 0xFFFFFFFF
    return v - (1 << 32) if v & 0x80000000 else v


def nearest_fix(v):
    return wrap(math.floor(v * 65536 + 0.5))


def fix_from(x):
    return 0 if math.isnan(x) or math.isinf(x) else wrap(math.floor(Fraction(x) * 65536))


FIX_CASES = [   # name, Lua expression, reference; a and b are any 32-bit integers, s is small
    ("mul",   "fix.mul(a, b)",       lambda a, b, s: wrap(a * b >> 16)),
    ("mul",   "fix.mul(s, b)",       lambda a, b, s: wrap(s * b >> 16)),
    ("div",   "fix.div(a, b | 1)",   lambda a, b, s: wrap((a << 16) // (b | 1))),
    ("div",   "fix.div(s, b | 1)",   lambda a, b, s: wrap((s << 16) // (b | 1))),
    ("div",   "fix.div(a, s | 1)",   lambda a, b, s: wrap((a << 16) // (s | 1))),
    ("sqrt",  "fix.sqrt(a & 0x7FFFFFFF)", lambda a, b, s: math.isqrt((a & 0x7FFFFFFF) << 16)),
    ("floor", "fix.floor(a)",        lambda a, b, s: a >> 16),
    ("to",    "fix.from(fix.to(a))", lambda a, b, s: fix_from(nearest(a) / 65536)),
    ("from",  "fix.from(fix.to(s) * 1.37)", lambda a, b, s: fix_from(nearest(nearest(nearest(s) / 65536) * nearest(1.37)))),
    ("sin",   "fix.sin(a)",          lambda a, b, s: nearest_fix(math.sin(a / 65536))),
    ("sin",   "fix.sin(s)",          lambda a, b, s: nearest_fix(math.sin(s / 65536))),
    ("cos",   "fix.cos(a)",          lambda a, b, s: nearest_fix(math.cos(a / 65536))),
    ("cos",   "fix.cos(s)",          lambda a, b, s: nearest_fix(math.cos(s / 65536))),
    ("atan",  "fix.atan(a, b)",      lambda a, b, s: nearest_fix(math.atan2(a, b))),
    ("atan",  "fix.atan(s, b >> 14)", lambda a, b, s: nearest_fix(math.atan2(s, (b & 0xFFFFFFFF) >> 14))),
    ("atan",  "fix.atan(s)",         lambda a, b, s: nearest_fix(math.atan2(s, 65536))),
]

FIX_LUA = """
local seed, row, n = 0x50554C49, {}, 0
local function next() seed = seed * 1664525 + 1013904223; return seed end
local function out(v)
  n = n + 1
  row[n] = string.format("%08x", v)
  if n == 32 then dbg(table.concat(row, " ", 1, n)); n = 0 end
end
for i = 1, COUNT do
  local a, b, s = next(), next(), (next() >> 12) - 524288
  EXPRESSIONS
end
dbg(table.concat(row, " ", 1, n))
"""


def main():
    t = Suite("Pulli maths")
    if not t.need_runtime("everything in this file"):
        return t.finish()

    # ---- the self-check a port compares itself with --------------------
    r = subprocess.run([t.headless, "--maths-check"], capture_output=True, text=True)
    t.check("self-check returns the value recorded in pmath.h", r.returncode == 0, r.stdout + r.stderr)

    # ---- nothing comes from the C library --------------------------------
    nm = shutil.which("nm")
    listing = subprocess.run([nm, "-u", t.headless], capture_output=True, text=True) if nm else None
    if listing and listing.returncode == 0 and listing.stdout.strip():
        used = {line.split()[-1].split("@")[0].lstrip("_") for line in listing.stdout.splitlines()}
        t.check("the host takes no sin, cos, exp, log, pow or fmod from the C library",
                not used & LIBRARY, sorted(used & LIBRARY))
    else:
        print("  SKIP  C library check (needs nm and a dynamically linked host)")

    # ---- exact results ---------------------------------------------------
    def expect(name, lua, lines):
        r = t.run_game(lua)
        t.check(name, r.code == 0 and r.lines == lines, f"stdout: {r.lines}\nwanted: {lines}\nstderr: {r.err}")

    expect("zero, one and whole powers come out exact",
           "dbg(math.sin(0), math.cos(0), math.exp(0), math.log(1), 2^10, 3^4, 10^3, 2^-1, (-2)^3, 0^0)",
           ["0.0\t1.0\t1.0\t0.0\t1024.0\t81.0\t1000.0\t0.5\t-8.0\t1.0"])
    expect("logarithms of exact powers are whole numbers",
           "dbg(math.log(8, 2), math.log(1024, 2), math.log(0.25, 2), math.log(1000, 10), math.log(0.01, 10))",
           ["3.0\t10.0\t-2.0\t3.0\t-2.0"])
    expect("the inverse functions land on pi",
           "dbg(math.atan(1, 1) * 4 == math.pi, math.atan(0, -1) == math.pi, math.asin(1) * 2 == math.pi,"
           " math.acos(-1) == math.pi, math.atan(1) * 4 == math.pi, math.acos(1), math.atan(-0.0, 1))",
           ["true\ttrue\ttrue\ttrue\ttrue\t0.0\t-0.0"])
    expect("results outside the numbers are infinity, zero or not-a-number",
           "local n = (-8) ^ (1 / 3)"
           " dbg(2.0 ^ 128 == math.huge, math.exp(1000) == math.huge, math.exp(-1000), 2.0 ^ -200,"
           " math.log(0) == -math.huge, n ~= n, math.asin(2) ~= math.asin(2), math.sin(math.huge) ~= 0)",
           ["true\ttrue\t0.0\t0.0\ttrue\ttrue\ttrue\ttrue"])
    expect("a square root and a half power agree", "dbg(2 ^ 0.5 == math.sqrt(2), 9 ^ 0.5, 2 ^ 2, 1.5 ^ 2)",
           ["true\t3.0\t4.0\t2.25"])

    # ---- accuracy ----------------------------------------------------------
    lua, seq, inputs = [LUA_HEAD], Sequence(), []
    for name, expr, ref, cases in CASES:
        for kinds in cases:
            args = ", ".join(f"pick({', '.join(str(k).lower() for k in kind)})" for kind in kinds)
            names = "a, b" if len(kinds) == 2 else "a"
            lua.append(f"for i = 1, {PER_CASE} do local {names} = {args}; out({expr}) end")
            for _ in range(PER_CASE):
                inputs.append((name, ref, [f32(seq.pick(*kind)) for kind in kinds]))
    lua.append('dbg(table.concat(row, " ", 1, n))')
    r = t.run_game("\n".join(lua))
    results = [f32(int(word, 16)) for word in r.out.split()]
    if t.check("every case ran", r.code == 0 and len(results) == len(inputs),
               f"{len(results)} results for {len(inputs)} inputs\n{r.err}"):
        worst = {}
        for (name, ref, args), got in zip(inputs, results):
            want = math.nan if any(math.isnan(a) for a in args) and name != "^" else ref(*args)
            err = error_in_ulps(got, want)
            if err > worst.get(name, (-1,))[0]:
                worst[name] = (err, args, got, want)
        for name, (err, args, got, want) in worst.items():
            t.check(f"{name:5} is within {LIMIT} of a unit in the last place (worst {err:.4f})",
                    err <= LIMIT, f"{name} {args} gave {got!r}, true result {want!r}")

    # ---- 16.16 fixed point -------------------------------------------------
    expect("fixed point: one is 65536, and whole numbers and halves convert exactly",
           "dbg(fix.one, fix.pi, fix.from(3), fix.from(-3), fix.from(0.5), fix.from(-0.5), fix.to(98304),"
           " fix.floor(fix.from(-2.5)), fix.floor(fix.from(2.5)))",
           ["65536\t205887\t196608\t-196608\t32768\t-32768\t1.5\t-3\t2"])
    expect("fixed point: conversions and results round down",
           "dbg(fix.from(1e-9), fix.from(-1e-9), fix.mul(1, 1), fix.mul(-1, 1), fix.div(1, fix.from(3)),"
           " fix.div(-1, fix.from(3)), fix.sqrt(fix.from(2)), fix.sqrt(fix.from(9)))",
           ["0\t-1\t0\t-1\t0\t-1\t92681\t196608"])
    expect("fixed point: everything wraps at 32 bits, as Lua integers do",
           "dbg(fix.from(32768), fix.from(32768.0), fix.from(65536.5), fix.mul(fix.from(200), fix.from(200)),"
           " fix.from(1e30), fix.from(1 / 0), fix.from(0 / 0))",
           ["-2147483648\t-2147483648\t32768\t-1673527296\t0\t0\t0"])
    expect("fixed point: sines, cosines and angles land on the exact values",
           "dbg(fix.sin(0), fix.cos(0), fix.cos(fix.pi), fix.atan(0, -fix.one), fix.atan(fix.one, 0),"
           " fix.atan(fix.one, fix.one) * 4 - fix.pi, fix.atan(0, 0), fix.atan(-fix.one))",
           ["0\t65536\t-65536\t205887\t102944\t1\t0\t-51472"])
    r = t.run_game("dbg(fix.div(fix.one, 0))")
    t.check("fixed point: dividing by zero stops the game with a clear error",
            r.code == 1 and "divide by zero" in r.err, r.err)
    r = t.run_game("dbg(fix.sqrt(-1))")
    t.check("fixed point: the square root of a negative number is an error",
            r.code == 1 and "negative" in r.err, r.err)
    r = t.run_game("dbg(fix.mul(1.5, fix.one))")
    t.check("fixed point: a float where a fixed-point number belongs is refused",
            r.code == 1 and "integer" in r.err, r.err)

    lua = FIX_LUA.replace("COUNT", str(PER_CASE)).replace(
        "EXPRESSIONS", "\n  ".join(f"out({expr})" for _, expr, _ in FIX_CASES))
    r = t.run_game(lua)
    got = [wrap(int(word, 16)) for word in r.out.split()]
    if t.check("fixed point: every case ran", r.code == 0 and len(got) == PER_CASE * len(FIX_CASES),
               f"{len(got)} results\n{r.err}"):
        seq, wrong = Sequence(), {}
        for i in range(PER_CASE):
            a, b = wrap(seq.next()), wrap(seq.next())
            s = (seq.next() >> 12) - 524288
            for j, (name, expr, ref) in enumerate(FIX_CASES):
                have, want = got[i * len(FIX_CASES) + j], ref(a, b, s)
                if have != want:
                    wrong.setdefault(name, []).append(f"{expr} with a={a} b={b} s={s}: got {have}, want {want}")
        for name in dict.fromkeys(name for name, _, _ in FIX_CASES):
            t.check(f"fixed point: {name} matches exact integer arithmetic on {PER_CASE} inputs",
                    name not in wrong, "\n".join(wrong.get(name, [])[:4]))
    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
