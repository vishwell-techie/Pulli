"""Shared helpers for the test scripts. Standard library only.

Every script takes:
    --headless PATH   the pulli-headless binary (default: build/host/, if built)
    --update          rewrite the golden files this script owns

Checks that need the C runtime are skipped, loudly, when it is not built, so
the Python-only checks still run on a machine with no compiler.
"""
import argparse, os, subprocess, sys, tempfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TESTS = os.path.join(ROOT, "tests")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import pulli   # noqa: E402

MANIFEST = 'return { id = "test.game", title = "Test", spec = 1 }\n'


class Result:
    def __init__(self, code, out, err, fb, rgb):
        self.code, self.out, self.err, self.fb, self.rgb = code, out, err, fb, rgb
        self.lines = out.splitlines()


class Suite:
    def __init__(self, title):
        ap = argparse.ArgumentParser()
        ap.add_argument("--headless")
        ap.add_argument("--update", action="store_true")
        args = ap.parse_args()
        self.update = args.update
        self.headless = args.headless
        if not self.headless:
            exe = "pulli-headless" + (".exe" if os.name == "nt" else "")
            default = os.path.join(ROOT, "build", "host", exe)
            self.headless = default if os.path.isfile(default) else None
        self.failed, self.skipped, self.count = [], 0, 0
        print(title + "\n")

    def check(self, name, cond, detail=""):
        self.count += 1
        print(f"  {'PASS' if cond else 'FAIL'}  {name}")
        if not cond:
            self.failed.append(name)
            if detail:
                print("        " + str(detail).rstrip().replace("\n", "\n        "))
        return cond

    def need_runtime(self, what):
        """True if the C runtime is available; otherwise records a skip."""
        if self.headless:
            return True
        self.skipped += 1
        print(f"  SKIP  {what} (pulli-headless is not built)")
        return False

    def run_package(self, data, frames=1, hold=None, tap=None, caps=None, saves=None):
        """Run package bytes in the headless host and collect everything."""
        with tempfile.TemporaryDirectory() as tmp:
            pkg, fb, rgb = (os.path.join(tmp, n) for n in ("game.pulli", "fb", "rgb"))
            with open(pkg, "wb") as f:
                f.write(data)
            cmd = [self.headless, pkg, "--frames", str(frames), "--dump-fb", fb, "--dump-rgb", rgb]
            for flag, value in (("--hold", hold), ("--tap", tap), ("--caps", caps), ("--saves", saves)):
                if value:
                    cmd += [flag, value]
            p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)

            def slurp(path):
                return open(path, "rb").read() if os.path.exists(path) else b""
            return Result(p.returncode, p.stdout.decode("utf-8", "replace"),
                          p.stderr.decode("utf-8", "replace"), slurp(fb), slurp(rgb))

    def run_game(self, main, manifest=MANIFEST, extra=None, **opts):  # opts: see run_package
        """Run a game given as Lua source text."""
        entries = {"manifest.lua": manifest, "main.lua": main}
        entries.update(extra or {})
        blobs = [(n, v if isinstance(v, bytes) else v.encode()) for n, v in sorted(entries.items())]
        return self.run_package(pulli.build_entries(blobs), **opts)

    def finish(self):
        print()
        if self.skipped:
            print(f"{self.skipped} group(s) skipped: build the host to run them")
        if self.failed:
            print(f"FAILED {len(self.failed)} of {self.count}: " + ", ".join(self.failed))
            return 1
        print(f"all {self.count} checks passed")
        return 0
