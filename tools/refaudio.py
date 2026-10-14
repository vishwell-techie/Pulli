#!/usr/bin/env python3
"""refaudio.py — reference mixer for Pulli (SPEC §3 "Audio").

Written for clarity, not speed. runtime/audio.c must produce the same
samples as this, bit for bit; tests/test_audio.py compares them.

    mixer = Mixer(sfx_bank_bytes, music_bank_bytes)
    mixer.sfx(0, -1)
    samples = mixer.frame()        # one game frame: 735 (left, right) pairs
"""
import struct

import pulli

RATE = 44100
FRAMES = RATE // 60
CHANNELS = 8
FULL = 1 << 24


def trunc_div(a: int, b: int) -> int:
    """Division that rounds toward zero, as C does."""
    return -(-a // b) if a < 0 else a // b


def decode(bank: bytes):
    """Every clip in a bank as (rate, loop start, [(left, right), ...])."""
    clips = []
    for i in range(struct.unpack("<H", bank[4:6])[0]):
        e = bank[pulli.BANK_HEADER + pulli.CLIP_ENTRY * i:pulli.BANK_HEADER + pulli.CLIP_ENTRY * (i + 1)]
        offset, size, frames, loop, rate, channels, encoding = struct.unpack("<IIIIHBB", e[:20])
        data = bank[offset:offset + size]
        if encoding == pulli.PCM:
            flat = struct.unpack(f"<{frames * channels}h", data)
        else:
            state, flat = [(0, 0)] * channels, []
            for k in range(frames * channels):
                nibble = (data[k // 2] >> (4 if k & 1 else 0)) & 15
                state[k % channels] = pulli.adpcm_step(nibble, *state[k % channels])
                flat.append(state[k % channels][0])
        pairs = [(flat[f * channels], flat[f * channels + channels - 1]) for f in range(frames)]
        clips.append((rate, loop, pairs))
    return clips


class Voice:
    def __init__(self, clip, looping, serial):
        self.rate, self.loop, self.pairs = clip
        self.looping = looping
        self.step = self.rate * 65536 // RATE
        self.frac = 0
        self.at = 0                     # the frame being played
        self.gain, self.gain_step = FULL, 0
        self.started = serial
        self.active = True

    def following(self):
        """The frame after the one being played, or None past the end."""
        nxt = self.at + 1
        if nxt < len(self.pairs):
            return nxt
        return self.loop if self.looping else None

    def render(self):
        cur, nxt = self.pairs[self.at], self.following()
        aim = self.pairs[nxt] if nxt is not None else (0, 0)
        f = self.frac >> 1
        out = [c + trunc_div((a - c) * f, 32768) for c, a in zip(cur, aim)]
        if self.gain != FULL:
            out = [trunc_div(s * (self.gain >> 9), 32768) for s in out]
        self.frac += self.step
        while self.frac >= 65536:
            self.frac -= 65536
            nxt = self.following()
            if nxt is None:
                self.active = False
                return out
            self.at = nxt
        if self.gain_step:
            self.gain += self.gain_step
            if self.gain >= FULL:
                self.gain, self.gain_step = FULL, 0
            if self.gain <= 0:
                self.active = False
        return out


def fade_step(fade_ms: int) -> int:
    return max(1, FULL // (fade_ms * (RATE // 100) // 10))


class Mixer:
    def __init__(self, sfx_bank: bytes = None, music_bank: bytes = None):
        self.sounds = decode(sfx_bank) if sfx_bank else []
        self.tracks = decode(music_bank) if music_bank else []
        self.ch = [None] * CHANNELS
        self.tune = [None, None]        # [0] playing, [1] fading out
        self.serial = 0
        self.paused = False

    @staticmethod
    def _on(v):
        return v is not None and v.active

    def sfx(self, n: int, channel: int = -1):
        if channel >= CHANNELS:
            return
        if n < 0:
            for c in range(CHANNELS):
                if channel < 0 or c == channel:
                    self.ch[c] = None
            return
        if n >= len(self.sounds):
            return
        if channel < 0:
            free = [c for c in range(CHANNELS) if not self._on(self.ch[c])]
            channel = free[0] if free else min(range(CHANNELS), key=lambda c: self.ch[c].started)
        self.serial += 1
        self.ch[channel] = Voice(self.sounds[n], False, self.serial)

    def music_pause(self, paused: bool = True):
        self.paused = paused

    def music_stop(self, fade_ms: int = 0):
        self.paused = False             # stopping lets the fade run
        if fade_ms <= 0:
            self.tune = [None, None]
        elif self._on(self.tune[0]):
            self.tune[1] = self.tune[0]
            self.tune[1].gain_step = -fade_step(fade_ms)
            self.tune[0] = None

    def music(self, n: int, fade_ms: int = 0, looping: bool = True):
        if n < 0 or n >= len(self.tracks):
            return
        self.music_stop(fade_ms)
        self.paused = False             # new music plays
        self.serial += 1
        self.tune[0] = Voice(self.tracks[n], looping, self.serial)
        if fade_ms > 0:
            self.tune[0].gain, self.tune[0].gain_step = 0, fade_step(fade_ms)

    def frame(self):
        out = []
        for _ in range(FRAMES):
            total = [0, 0]
            for v in self.ch + ([] if self.paused else self.tune):
                if self._on(v):
                    l, r = v.render()
                    total[0] += l
                    total[1] += r
            out.append(tuple(max(-32768, min(32767, s)) for s in total))
        return out
