/* audio.c — the mixer (SPEC §3 "Audio", §2 "sfx.oli and music.isai").
 *
 * Every game frame the engine mixes exactly PULLI_AUDIO_FRAMES stereo
 * frames and hands them to the port. All of it is integer arithmetic, so
 * a game sounds the same, sample for sample, on every machine.
 * tools/refaudio.py is the reference this file must match. A bank's table
 * is read when the game starts; each sound is read into the active set the
 * first time it is played, and kept there while it plays (parts.c).
 */
#include "internal.h"
#include <stdio.h>
#include <string.h>

#define BANK_HEADER 8
#define CLIP_ENTRY  28
#define GAIN_FULL   (1 << 24)

static const int16_t ADPCM_STEP[89] = {
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
    50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230,
    253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963,
    1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327,
    3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442,
    11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794,
    32767
};
static const int8_t ADPCM_INDEX[8] = { -1, -1, -1, -1, 2, 4, 6, 8 };

static uint32_t rd16(const uint8_t *p) { return p[0] | ((uint32_t)p[1] << 8); }
static uint32_t rd32(const uint8_t *p) { return rd16(p) | (rd16(p + 2) << 16); }
static int16_t  rds16(const uint8_t *p) { return (int16_t)(uint16_t)rd16(p); }

/* ---- banks ----------------------------------------------------------- */

/* One sound as its bank describes it. */
typedef struct {
    uint32_t bytes, frames, loop, rate;
    uint8_t  channels, adpcm;
    int16_t  loop_pred[2];
    uint8_t  loop_index[2];
} clip;

/* `table` is the bank's header and table; offsets are from the bank's start. */
static void read_clip(pulli_blob table, unsigned n, clip *c, uint32_t *offset) {
    const uint8_t *p = table.data + BANK_HEADER + CLIP_ENTRY * n;
    *offset = rd32(p);
    c->bytes = rd32(p + 4);
    c->frames = rd32(p + 8);
    c->loop = rd32(p + 12);
    c->rate = rd16(p + 16);
    c->channels = p[18];
    c->adpcm = p[19];
    for (int ch = 0; ch < 2; ch++) {
        c->loop_pred[ch] = rds16(p + 20 + 4 * ch);
        c->loop_index[ch] = p[22 + 4 * ch];
    }
}

/* Checks a bank's table once, at boot, so playing a sound never has to:
 * every sound must lie inside the bank, of `len` bytes. Returns NULL if it
 * is sound, else what is wrong with it. */
static const char *check_bank(pulli_blob table, uint32_t len, uint16_t *count) {
    uint32_t n = rd16(table.data + 4);
    for (uint32_t i = 0; i < n; i++) {
        clip c;
        uint32_t offset;
        read_clip(table, i, &c, &offset);
        if (c.channels < 1 || c.channels > 2) return "a sound must be mono or stereo";
        if (c.adpcm > 1) return "unknown sound encoding";
        if (c.rate < PULLI_CLIP_RATE_MIN || c.rate > PULLI_CLIP_RATE_MAX) return "sample rate out of range";
        if (c.frames < 1 || c.frames > PULLI_CLIP_FRAMES_MAX) return "a sound is empty or too long";
        if (c.loop >= c.frames) return "loop point is past the end of the sound";
        uint32_t samples = c.frames * c.channels;
        if (c.bytes != (c.adpcm ? (samples + 1) / 2 : samples * 2)) return "sound length does not match its data";
        if (offset < BANK_HEADER + CLIP_ENTRY * n || offset > len || c.bytes > len - offset)
            return "sound data lies outside the bank";
        if (c.loop_index[0] > 88 || c.loop_index[1] > 88) return "bad loop state";
    }
    *count = (uint16_t)n;
    return NULL;
}

/* Reads one bank's table into the active set, pinned, and checks it. */
static const char *open_bank(pulli_engine *e, const char *name, const char *magic,
                             pulli_blob *table, uint32_t *at, uint32_t *len, uint16_t *count) {
    pulli_entry en;
    uint8_t head[BANK_HEADER];
    const uint8_t *h;
    if (!pulli_pkg_find(&e->pkg, name, &en)) return NULL;
    if (en.len < BANK_HEADER) return "not a sound bank";
    const char *why = pulli_pkg_get(&e->pkg, en.offset, BANK_HEADER, head, &h);
    if (why) return why;
    if (memcmp(h, magic, 4) != 0) return "not a sound bank";
    uint32_t n = rd16(h + 4);
    if (n > PULLI_CLIP_MAX) return "too many sounds";
    if (BANK_HEADER + CLIP_ENTRY * n > en.len) return "sound table runs past the end";
    table->len = BANK_HEADER + CLIP_ENTRY * n;
    table->data = pulli_part_use(e, en.offset, table->len, name, true, false);
    if (!table->data) return e->part_error;
    *at = en.offset;
    *len = en.len;
    return check_bank(*table, en.len, count);
}

const char *pulli_audio_boot(pulli_engine *e, const char **which) {
    pulli_audio *a = &e->audio;
    const char *why;
    memset(a, 0, sizeof(*a));
    *which = "sfx.oli";
    if ((why = open_bank(e, *which, "OLI1", &a->sfx, &a->sfx_at, &a->sfx_len, &a->sfx_count))) return why;
    *which = "music.isai";
    if ((why = open_bank(e, *which, "ISA1", &a->music, &a->music_at, &a->music_len, &a->music_count))) return why;
    return NULL;
}

/* Sound n of a bank, in the active set: its clip and its bytes. */
static const uint8_t *sound(pulli_engine *e, bool music, unsigned n, clip *c) {
    pulli_audio *a = &e->audio;
    char label[16];
    uint32_t offset;
    read_clip(music ? a->music : a->sfx, n, c, &offset);
    snprintf(label, sizeof(label), "%s %u", music ? "music" : "sfx", n);
    return pulli_part_use(e, (music ? a->music_at : a->sfx_at) + offset, c->bytes, label, false, true);
}

const char *pulli_audio_preload(pulli_engine *e, bool music, int n) {
    clip c;
    if (n < 0 || n >= (music ? e->audio.music_count : e->audio.sfx_count)) return "no such sound";
    return sound(e, music, (unsigned)n, &c) ? NULL : e->part_error;
}

/* ---- voices ---------------------------------------------------------- */

/* Reads the next frame of the sound into v->nxt. Past the end, a looping
 * voice carries on from its loop point and any other is given silence and
 * marked as finishing. */
static void fetch(pulli_voice *v) {
    if (v->at == v->frames) {
        if (!v->looping) {
            v->nxt[0] = v->nxt[1] = 0;
            v->last = true;
            return;
        }
        v->at = v->loop;
        for (int ch = 0; ch < 2; ch++) {
            v->pred[ch] = v->loop_pred[ch];
            v->index[ch] = v->loop_index[ch];
        }
    }
    for (uint32_t ch = 0; ch < v->channels; ch++) {
        uint32_t k = v->at * v->channels + ch;
        if (!v->adpcm) {
            v->nxt[ch] = rds16(v->data + 2 * k);
            continue;
        }
        uint32_t nibble = (v->data[k / 2] >> (k & 1 ? 4 : 0)) & 15;
        int32_t step = ADPCM_STEP[v->index[ch]], diff = step >> 3;
        if (nibble & 4) diff += step;
        if (nibble & 2) diff += step >> 1;
        if (nibble & 1) diff += step >> 2;
        int32_t pred = v->pred[ch] + (nibble & 8 ? -diff : diff);
        if (pred > 32767) pred = 32767;
        if (pred < -32768) pred = -32768;
        int index = v->index[ch] + ADPCM_INDEX[nibble & 7];
        v->pred[ch] = (int16_t)pred;
        v->index[ch] = (uint8_t)(index < 0 ? 0 : index > 88 ? 88 : index);
        v->nxt[ch] = (int16_t)pred;
    }
    if (v->channels == 1) v->nxt[1] = v->nxt[0];
    v->at++;
}

static void start(pulli_audio *a, pulli_voice *v, const clip *cl, const uint8_t *data, bool looping) {
    clip c = *cl;
    memset(v, 0, sizeof(*v));
    v->data = data;
    v->frames = c.frames;
    v->loop = c.loop;
    v->channels = c.channels;
    v->adpcm = c.adpcm;
    v->looping = looping;
    v->step = c.rate * 65536u / PULLI_AUDIO_RATE;
    memcpy(v->loop_pred, c.loop_pred, sizeof(v->loop_pred));
    memcpy(v->loop_index, c.loop_index, sizeof(v->loop_index));
    v->gain = GAIN_FULL;
    v->started = ++a->serial;
    v->active = true;
    fetch(v);
    v->cur[0] = v->nxt[0];
    v->cur[1] = v->nxt[1];
    fetch(v);
}

/* Adds one output frame of this voice to the sums and moves it on. */
static void render(pulli_voice *v, int32_t *left, int32_t *right) {
    int32_t f = (int32_t)(v->frac >> 1);          /* 15 bits, so the product fits */
    int32_t l = v->cur[0] + (v->nxt[0] - v->cur[0]) * f / 32768;
    int32_t r = v->cur[1] + (v->nxt[1] - v->cur[1]) * f / 32768;
    if (v->gain != GAIN_FULL) {
        l = l * (v->gain >> 9) / 32768;
        r = r * (v->gain >> 9) / 32768;
    }
    *left += l;
    *right += r;

    for (v->frac += v->step; v->frac >= 65536; v->frac -= 65536) {
        if (v->last) { v->active = false; return; }
        v->cur[0] = v->nxt[0];
        v->cur[1] = v->nxt[1];
        fetch(v);
    }
    if (v->gain_step) {
        v->gain += v->gain_step;
        if (v->gain >= GAIN_FULL) { v->gain = GAIN_FULL; v->gain_step = 0; }
        if (v->gain <= 0) v->active = false;
    }
}

static int16_t clamp16(int32_t s) { return (int16_t)(s > 32767 ? 32767 : s < -32768 ? -32768 : s); }

void pulli_audio_mix(pulli_audio *a, int16_t *out, int frames) {
    for (int i = 0; i < frames; i++) {
        int32_t l = 0, r = 0;
        for (int c = 0; c < PULLI_SFX_CHANNELS; c++)
            if (a->ch[c].active) render(&a->ch[c], &l, &r);
        if (!a->music_paused)                         /* paused music stands still, fades included */
            for (int m = 0; m < 2; m++)
                if (a->tune[m].active) render(&a->tune[m], &l, &r);
        out[2 * i] = clamp16(l);
        out[2 * i + 1] = clamp16(r);
    }
}

/* ---- what the Lua API calls ------------------------------------------ */

const char *pulli_audio_sfx(pulli_engine *e, int n, int channel) {
    pulli_audio *a = &e->audio;
    if (channel >= PULLI_SFX_CHANNELS) return NULL;
    if (n < 0) {                                  /* stop one channel, or all of them */
        for (int c = 0; c < PULLI_SFX_CHANNELS; c++)
            if (channel < 0 || c == channel) a->ch[c].active = false;
        return NULL;
    }
    if (n >= a->sfx_count) return NULL;
    clip cl;
    const uint8_t *data = sound(e, false, (unsigned)n, &cl);
    if (!data) return e->part_error;
    if (channel < 0) {                            /* a free channel, else the oldest sound */
        channel = 0;
        for (int c = 0; c < PULLI_SFX_CHANNELS; c++) {
            if (!a->ch[c].active) { channel = c; break; }
            if (a->ch[c].started < a->ch[channel].started) channel = c;
        }
    }
    start(a, &a->ch[channel], &cl, data, false);
    return NULL;
}

/* How much the gain moves per output frame for a fade of this length. */
static int32_t fade_step(int fade_ms) {
    int32_t frames = (int32_t)fade_ms * (PULLI_AUDIO_RATE / 100) / 10, step = GAIN_FULL / frames;
    return step ? step : 1;
}

void pulli_audio_music_pause(pulli_audio *a, bool paused) {
    a->music_paused = paused;
}

void pulli_audio_music_stop(pulli_audio *a, int fade_ms) {
    a->music_paused = false;                      /* stopping lets the fade run */
    if (fade_ms <= 0) {
        a->tune[0].active = a->tune[1].active = false;
    } else if (a->tune[0].active) {               /* tune[1] is the one on its way out */
        a->tune[1] = a->tune[0];
        a->tune[1].gain_step = -fade_step(fade_ms);
        a->tune[0].active = false;
    }
}

const char *pulli_audio_music(pulli_engine *e, int n, int fade_ms, bool looping) {
    pulli_audio *a = &e->audio;
    if (n < 0 || n >= a->music_count) return NULL;
    clip cl;
    const uint8_t *data = sound(e, true, (unsigned)n, &cl);
    if (!data) return e->part_error;
    pulli_audio_music_stop(a, fade_ms);
    a->music_paused = false;                      /* new music plays */
    start(a, &a->tune[0], &cl, data, looping);
    if (fade_ms > 0) {
        a->tune[0].gain = 0;
        a->tune[0].gain_step = fade_step(fade_ms);
    }
    return NULL;
}
