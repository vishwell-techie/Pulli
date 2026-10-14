"""Shared helpers for the test scripts. Standard library only.

Every script takes:
    --headless PATH   the pulli-headless binary (default: build/host/, if built)
    --update          rewrite the golden files this script owns

Checks that need the C runtime are skipped, loudly, when it is not built, so
the Python-only checks still run on a machine with no compiler.
"""
import argparse, os, socket, struct, subprocess, sys, tempfile, time

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TESTS = os.path.join(ROOT, "tests")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import pulli   # noqa: E402

MANIFEST = 'return { id = "test.game", title = "Test", spec = 1 }\n'


class Result:
    def __init__(self, code, out, err, fb, rgb, wav=b""):
        self.code, self.out, self.err, self.fb, self.rgb = code, out, err, fb, rgb
        self.lines = out.splitlines()
        self.wav = wav                      # the whole WAV file, when sound was asked for

    @property
    def sound(self):
        """What the game played, as a list of (left, right) samples."""
        flat = struct.unpack(f"<{(len(self.wav) - 44) // 2}h", self.wav[44:])
        return list(zip(flat[0::2], flat[1::2]))


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

    def _start(self, tmp, data, frames=1, hold=None, tap=None, caps=None, saves=None, link=None,
               sound=False, clock=None):
        os.makedirs(tmp)
        pkg, fb, rgb, wav = (os.path.join(tmp, n) for n in ("game.pulli", "fb", "rgb", "wav"))
        with open(pkg, "wb") as f:
            f.write(data)
        cmd = [self.headless, pkg, "--frames", str(frames), "--dump-fb", fb, "--dump-rgb", rgb]
        for flag, value in (("--hold", hold), ("--tap", tap), ("--caps", caps), ("--saves", saves),
                            ("--link", link), ("--clock-step", clock)):
            if value:
                cmd += [flag, str(value)]
        if sound:
            cmd += ["--dump-wav", wav]
        return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE), fb, rgb, wav

    @staticmethod
    def _finish(started):
        proc, fb, rgb, wav = started
        try:
            out, err = proc.communicate(timeout=120)
        except subprocess.TimeoutExpired:
            proc.kill()
            out, err = proc.communicate()
            err += b"\n(killed: still running after 120 s)"

        def slurp(path):
            return open(path, "rb").read() if os.path.exists(path) else b""
        return Result(proc.returncode, out.decode("utf-8", "replace"),
                      err.decode("utf-8", "replace"), slurp(fb), slurp(rgb), slurp(wav))

    def run_package(self, data, **opts):
        """Run package bytes in the headless host and collect everything.
        Options: frames, hold, tap, caps, saves, link, sound, clock."""
        with tempfile.TemporaryDirectory() as tmp:
            return self._finish(self._start(os.path.join(tmp, "a"), data, **opts))

    def run_linked(self, first, second, first_opts=None, second_opts=None):
        """Run two packages linked to each other. `first` becomes side 1."""
        with socket.socket() as s:                 # ask the system for a free port
            s.bind(("127.0.0.1", 0))
            port = s.getsockname()[1]
        with tempfile.TemporaryDirectory() as tmp:
            a = self._start(os.path.join(tmp, "a"), first, link=port, **(first_opts or {}))
            time.sleep(0.3)                        # let it claim the port, and so side 1
            b = self._start(os.path.join(tmp, "b"), second, link=port, **(second_opts or {}))
            return self._finish(a), self._finish(b)

    @staticmethod
    def package(main, manifest=MANIFEST, extra=None):
        """Package a game given as Lua source text."""
        entries = {"manifest.lua": manifest, "main.lua": main}
        entries.update(extra or {})
        return pulli.build_entries(
            [(n, v if isinstance(v, bytes) else v.encode()) for n, v in sorted(entries.items())])

    def run_game(self, main, manifest=MANIFEST, extra=None, **opts):
        """Run a game given as Lua source text."""
        return self.run_package(self.package(main, manifest, extra), **opts)

    def finish(self):
        print()
        if self.skipped:
            print(f"{self.skipped} group(s) skipped: build the host to run them")
        if self.failed:
            print(f"FAILED {len(self.failed)} of {self.count}: " + ", ".join(self.failed))
            return 1
        print(f"all {self.count} checks passed")
        return 0
