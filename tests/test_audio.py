#!/usr/bin/env python3
"""Sound: the WAV importer, the bank format and the mixer.

Run: python3 tests/test_audio.py

The mixer is tested the way the rasterizer is: tools/refaudio.py is the
reference, and runtime/audio.c has to produce the same samples bit for bit
through a script of sfx() and music() calls. Sound that is exactly right
cannot be told from sound that is slightly wrong by listening, so nothing
here relies on ears.
"""
import math, os, struct, sys, tempfile

from harness import Suite, pulli

sys.path.insert(0, os.path.dirname(pulli.__file__))
import refaudio   # noqa: E402


def tone(rate, seconds, hz, level=0.5, channels=1, hz_right=None):
    """A sine wave as a flat list of 16-bit samples."""
    out = []
    for i in range(int(rate * seconds)):
        out.append(int(32767 * level * math.sin(2 * math.pi * hz * i / rate)))
        if channels == 2:
            out.append(int(32767 * level * math.sin(2 * math.pi * (hz_right or hz) * i / rate)))
    return out


def wav(rate, channels, samples, bits=16, loop=None, extensible=False):
    if bits == 8:
        body = bytes((s >> 8) + 128 for s in samples)
    elif bits == 16:
        body = struct.pack(f"<{len(samples)}h", *samples)
    else:
        body = b"".join((s << (bits - 16)).to_bytes(bits // 8, "little", signed=True) for s in samples)
    block = channels * bits // 8
    fmt = struct.pack("<HHIIHH", 0xFFFE if extensible else 1, channels, rate, rate * block, block, bits)
    if extensible:
        fmt += struct.pack("<HHIH", 22, bits, 3, 1) + bytes(14)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    chunks += b"LIST" + struct.pack("<I", 5) + b"INFO!" + b"\0"        # an odd-sized chunk to skip
    if loop is not None:
        smpl = struct.pack("<9I", 0, 0, 0, 60, 0, 0, 0, 1, 0) + struct.pack("<6I", 0, 0, loop, len(samples), 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    chunks += b"data" + struct.pack("<I", len(body)) + body
    return b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks


# The sounds the mixer test plays. Rates, channel counts, both encodings.
SFX = [
    (22050, 1, tone(22050, 0.20, 440), None, pulli.PCM),
    (44100, 2, tone(44100, 0.10, 660, 0.4, 2, 990), None, pulli.PCM),
    (11025, 1, tone(11025, 0.50, 220, 0.9), None, pulli.PCM),            # loud: nine at once clip
    (48000, 1, tone(48000, 0.05, 1000), None, pulli.ADPCM),              # faster than the output
    (8000,  1, [12000, -12000, 3000], None, pulli.PCM),                  # three samples long
    (4000,  1, [9000], None, pulli.PCM),                                 # one sample long
]
MUSIC = [
    (22050, 2, tone(22050, 0.60, 330, 0.3, 2, 331), 4410, pulli.ADPCM),  # loops from 0.2 s
    (32000, 1, tone(32000, 0.25, 550, 0.3), None, pulli.ADPCM),
    (44100, 1, tone(44100, 0.30, 110, 0.3), None, pulli.PCM),
    (22050, 1, [5000], None, pulli.ADPCM),                               # one sample, looping
]

#  frame, call
SCRIPT = [
    (1,  ("sfx", 0, -1)),          (1,  ("sfx", 1, -1)),
    (3,  ("sfx", 4, 5)),           (3,  ("sfx", 5, 6)),
    (4,  ("sfx", 99, -1)),         (4,  ("sfx", 0, 8)),          (4, ("music", 9, 0, True)),   # all ignored
    (5,  ("music", 0, 0, True)),
    (8,  ("sfx", 3, 2)),           (9,  ("sfx", 3, 2)),          # the second replaces the first
    (12, ("sfx", -1, 0)),                                        # stop channel 0
    (20, [("sfx", 2, -1), ("sfx", 0, -1)] * 4),                  # every channel busy
    (22, ("sfx", 1, -1)),                                        # takes over the oldest, channel 0
    (24, ("sfx", -1, -1)),                                       # stop them all
    (30, ("music", 1, 300, True)),                               # cross-fade
    (40, ("music", 2, 500, False)),                              # change again part-way through
    (75, ("music", 3, 100, True)),
    (85, ("music_stop", 200)),
    (92, ("music_pause",)),                                      # a pause: music still, effects not
    (94, ("sfx", 0, -1)),
    (97, ("music_pause", False)),
    (98, ("music_pause", True)),                                 # paused again, then new music starts
    (100, ("music", 2, 0, False)),                               # plays once and ends by itself
    (125, ("music", 0, 250, True)),                              # fades in, then loops twice
    (130, ("music_pause",)),                                     # paused during that fade-in...
    (136, ("music_stop", 100)),                                  # ...stopping lets it carry on out
    (140, ("music", 0, 250, True)),
    (150, ("music_pause",)),                                     # paused for a long while,
    (180, ("music_pause", False)),                               # then it carries on where it was
    (210, ("music_stop", 0)),
    (212, ("sfx", 1, -1)),
]
FRAMES = 220


def lua_script():
    lines = ["local f = 0", "function update()", "  f = f + 1"]
    for frame, calls in SCRIPT:
        for call in calls if isinstance(calls, list) else [calls]:
            args = ", ".join(str(a).lower() for a in call[1:])
            lines.append(f"  if f == {frame} then {call[0]}({args}) end")
    return "\n".join(lines + ["end"])


def reference(sfx_bank, music_bank):
    mixer, out = refaudio.Mixer(sfx_bank, music_bank), []
    for frame in range(1, FRAMES + 1):
        for at, calls in SCRIPT:
            if at == frame:
                for call in calls if isinstance(calls, list) else [calls]:
                    getattr(mixer, call[0])(*call[1:])
        out += mixer.frame()
    return out


def loudest(samples):
    return max((abs(s) for pair in samples for s in pair), default=0)


def main():
    t = Suite("Pulli audio")

    def refuses(name, fn, *needles):
        try:
            fn()
            t.check(name, False, "accepted")
        except pulli.PackageError as e:
            t.check(name, all(n in str(e) for n in needles), str(e))

    # ---- reading WAV files -------------------------------------------------
    one = tone(22050, 0.01, 440)
    two = tone(22050, 0.01, 440, channels=2, hz_right=880)
    t.check("16-bit mono WAV is read exactly", pulli.read_wav(wav(22050, 1, one)) == (22050, 1, one, None))
    t.check("stereo keeps left and right apart", pulli.read_wav(wav(22050, 2, two)) == (22050, 2, two, None))
    t.check("8-bit WAV becomes 16-bit",
            pulli.read_wav(wav(8000, 1, one, bits=8))[2] == [s >> 8 << 8 for s in one])
    t.check("24-bit and 32-bit WAV keep their top 16 bits",
            pulli.read_wav(wav(44100, 1, one, bits=24))[2] == one
            and pulli.read_wav(wav(44100, 1, one, bits=32))[2] == one)
    t.check("the 'extensible' WAV header is understood",
            pulli.read_wav(wav(48000, 2, two, extensible=True)) == (48000, 2, two, None))
    t.check("a loop point marked in the file is found", pulli.read_wav(wav(22050, 1, one, loop=100))[3] == 100)
    t.check("a loop point past the end is dropped", pulli.read_wav(wav(22050, 1, one, loop=10 ** 6))[3] is None)
    refuses("a file that is not WAV is refused", lambda: pulli.read_wav(b"OggS" + bytes(64), "a.wav"), "a.wav")
    refuses("an empty WAV is refused", lambda: pulli.read_wav(wav(22050, 1, [])), "no sound")
    refuses("a sample rate outside 4000 to 48000 is refused", lambda: pulli.read_wav(wav(96000, 1, one)), "96000")
    refuses("more than two channels are refused", lambda: pulli.read_wav(wav(22050, 6, one * 6)), "6 channels")
    floaty = bytearray(wav(22050, 1, one))
    floaty[20:22] = struct.pack("<H", 3)
    refuses("a floating-point WAV is refused with a reason", lambda: pulli.read_wav(bytes(floaty)), "PCM")

    # ---- squeezing music ---------------------------------------------------
    song = tone(22050, 0.5, 440, 0.6)
    packed, _ = pulli.adpcm_encode(song, 1, 0)
    state, back = (0, 0), []
    for k in range(len(song)):
        state = pulli.adpcm_step((packed[k // 2] >> (4 if k & 1 else 0)) & 15, *state)
        back.append(state[0])
    noise = sum((a - b) ** 2 for a, b in zip(song, back)) / len(song)
    power = sum(a * a for a in song) / len(song)
    snr = 10 * math.log10(power / noise)
    t.check(f"squeezed sound is a quarter the size and still clean ({snr:.0f} dB)",
            len(packed) == (len(song) + 1) // 2 and snr > 30)

    # ---- packing a game's folders -------------------------------------------
    with tempfile.TemporaryDirectory() as tmp:
        for name, text in (("manifest.lua", 'return { id = "test.sound", title = "S", spec = 1 }'),
                           ("main.lua", "")):
            open(os.path.join(tmp, name), "w").write(text)
        os.makedirs(os.path.join(tmp, "sfx"))
        os.makedirs(os.path.join(tmp, "music"))
        for name, data in (("sfx/10-hit.wav", wav(22050, 1, one)), ("sfx/02-jump.WAV", wav(11025, 2, two)),
                           ("sfx/notes.txt", b"not a sound"), ("music/theme.wav", wav(22050, 1, song, loop=2205))):
            open(os.path.join(tmp, name), "wb").write(data)
        entries = dict(pulli.parse(pulli.build(tmp)))
        t.check("pack turns sfx/ and music/ into sfx.oli and music.isai",
                sorted(entries) == ["main.lua", "manifest.lua", "music.isai", "sfx.oli"])
        t.check("sounds are numbered in order of file name",
                [c[:5] for c in pulli.read_bank(entries["sfx.oli"])]
                == [(11025, 2, len(two) // 2, 0, pulli.PCM), (22050, 1, len(one), 0, pulli.PCM)])
        t.check("music is squeezed and keeps its loop point",
                pulli.read_bank(entries["music.isai"]) == [(22050, 1, len(song), 2205, pulli.ADPCM, (len(song) + 1) // 2)])
        open(os.path.join(tmp, "sfx.oli"), "wb").write(b"OLI1")
        refuses("a ready-made bank and a folder for the same thing are refused",
                lambda: pulli.build(tmp), "sfx.oli", "sfx/")

    sfx_bank, music_bank = pulli.bank("sfx", SFX), pulli.bank("music", MUSIC)
    t.check("the reference decodes exact sounds exactly",
            [p[0] for p in refaudio.decode(sfx_bank)[0][2]] == SFX[0][2])

    if not t.need_runtime("the mixer"):
        return t.finish()
    extra = {"sfx.oli": sfx_bank, "music.isai": music_bank}

    # ---- the mixer against the reference -----------------------------------
    want = reference(sfx_bank, music_bank)
    r = t.run_game(lua_script(), extra=extra, frames=FRAMES, sound=True)
    if t.check("the script runs and 735 samples come out per frame",
               r.code == 0 and len(r.wav) == 44 + FRAMES * 735 * 4, f"{len(r.wav)} bytes\n{r.err}"):
        got = r.sound
        first = next((i for i, (a, b) in enumerate(zip(got, want)) if a != b), None)
        t.check("the mixer matches the reference, sample for sample", first is None,
                f"first difference at sample {first} (frame {first // 735 + 1 if first is not None else 0}): "
                f"got {got[first] if first is not None else ''}, want {want[first] if first is not None else ''}")
        frame = lambda n: want[(n - 1) * 735:n * 735]
        t.check("the script exercises what it means to: silence, sound, clipping and stereo",
                loudest(frame(4)) > 0 and loudest(frame(21)) >= 32767 and loudest(frame(27)) > 0
                and any(a != b for a, b in frame(2)) and loudest(frame(220)) == 0)
        t.check("the script's pauses silence the music but not the effects, and the music carries on after",
                loudest(frame(91)) > 0 and loudest(frame(93)) == 0 and loudest(frame(95)) > 0
                and loudest(frame(96)) > 0 and loudest(frame(155)) == 0 and loudest(frame(185)) > 0)
        again = t.run_game(lua_script(), extra=extra, frames=FRAMES, sound=True)
        t.check("the same game makes the same sound every time", again.wav == r.wav)
        mapped = t.run_game(lua_script(), extra=extra, frames=FRAMES, sound=True, mapped=True)
        t.check("the same sound comes out whether the package is read in parts or held in memory",
                mapped.wav == r.wav, mapped.err)

    # ---- behaviour ---------------------------------------------------------
    r = t.run_game("function update() sfx(0) music(0, 100) music_stop(50) sfx(-1) end", frames=30, sound=True)
    t.check("a game with no sounds can call every sound function and gets silence",
            r.code == 0 and loudest(r.sound) == 0 and len(r.sound) == 30 * 735, r.err)
    r = t.run_game("function init() sfx(0) end", extra=extra, frames=3)
    t.check("sound costs nothing when no one is listening", r.code == 0, r.err)
    r = t.run_game("local f = 0 function update() f = f + 1 if f == 2 then sfx(5, 0) end end",
                   extra=extra, frames=3, sound=True)
    s = r.sound
    t.check("a sound starts in the frame that asked for it and not before",
            loudest(s[:735]) == 0 and s[735] == (9000, 9000), s[730:740])
    note = refaudio.decode(music_bank)[3][2][0]          # the one sample of track 3, as squeezed
    r = t.run_game("function init() music(3) end", extra=extra, frames=120, sound=True)
    t.check("music loops until it is stopped", note != (0, 0) and r.sound[-1] == note and r.sound[0] == note)
    r = t.run_game("function init() music(3, 0, false) end", extra=extra, frames=3, sound=True)
    t.check("music asked to play once ends", r.sound[0] == note and loudest(r.sound[735:]) == 0)

    # ---- bad banks ---------------------------------------------------------
    def bad(name, bank, entry, *needles):
        r = t.run_game("", extra={entry: bank})
        t.check(name, r.code == 1 and all(n in r.err for n in needles), f"exit {r.code}\n{r.err}")

    def patched(offset, fmt, value, source=sfx_bank):
        b = bytearray(source)
        struct.pack_into(fmt, b, offset, value)
        return bytes(b)

    first = pulli.BANK_HEADER
    bad("a bank with the wrong magic is refused", music_bank, "sfx.oli", "sfx.oli", "not a sound bank")
    bad("a truncated bank is refused", sfx_bank[:20], "sfx.oli", "sfx.oli", "past the end")
    bad("a sound that points outside its bank is refused", patched(first, "<I", len(sfx_bank)), "sfx.oli", "outside")
    bad("a sound whose length disagrees with its data is refused", patched(first + 8, "<I", 7), "sfx.oli", "length")
    bad("a loop point past the end is refused", patched(first + 12, "<I", 10 ** 6), "sfx.oli", "loop")
    bad("a loop point exactly at the end is refused", patched(first + 12, "<I", len(SFX[0][2])), "sfx.oli", "loop")
    bad("a sample rate out of range is refused", patched(first + 16, "<H", 100), "sfx.oli", "rate")
    bad("three channels are refused", patched(first + 18, "<B", 3), "sfx.oli", "mono or stereo")
    bad("an unknown encoding is refused", patched(first + 19, "<B", 7), "sfx.oli", "encoding")
    bad("a bad loop state is refused", patched(first + 22, "<B", 200, music_bank), "music.isai",
        "music.isai", "loop state")
    bad("more sounds than a bank may hold are refused", patched(4, "<H", 300), "sfx.oli", "too many")
    return t.finish()


if __name__ == "__main__":
    sys.exit(main())
