/* parts.c — the active set: the parts of the package in memory (SPEC §2,
 * "Size, and the parts in memory"). No platform dependencies.
 *
 * A part is a range of the package: a whole entry (a Lua file, a map, a
 * sprite sheet), a sound bank's table, or one sound. It is read the first
 * time it is used and kept, up to PULLI_ACTIVE_MAX bytes in all. When a new
 * part needs room, the parts used longest ago are let go, except those
 * pinned: the sprite sheet and the map in use, the sound banks' tables, and
 * the sounds playing. The accounting is the same whether the package is
 * mapped or read, so a game that fits on a desktop fits on a console, and
 * what is let go depends only on what the game did. */
#include "internal.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* How many voices are playing the sound that starts at `data`. */
static uint16_t voices_on(const pulli_engine *e, const uint8_t *data) {
    uint16_t n = 0;
    for (int c = 0; c < PULLI_SFX_CHANNELS; c++)
        if (e->audio.ch[c].active && e->audio.ch[c].data == data) n++;
    for (int m = 0; m < 2; m++)
        if (e->audio.tune[m].active && e->audio.tune[m].data == data) n++;
    return n;
}

void pulli_parts_sound_pins(pulli_engine *e) {
    for (int i = 0; i < e->part_count; i++) {
        pulli_part *p = &e->parts[i];
        if (p->sound && p->data) p->pins = voices_on(e, p->data);
    }
}

static void let_go(pulli_engine *e, pulli_part *p) {
    free(p->buf);
    p->buf = NULL;
    p->data = NULL;
    e->active -= p->len;
}

static const uint8_t *refuse(pulli_engine *e, const char *fmt, const char *label, unsigned a, unsigned b) {
    snprintf(e->part_error, sizeof(e->part_error), fmt, label, a, b);
    return NULL;
}

static const uint8_t *no_memory(pulli_engine *e, const char *label) {
    snprintf(e->part_error, sizeof(e->part_error), "out of memory reading %s", label);
    return NULL;
}

const uint8_t *pulli_part_use(pulli_engine *e, uint32_t offset, uint32_t len, const char *label,
                              bool pin, bool sound) {
    pulli_parts_sound_pins(e);
    pulli_part *p = NULL;
    for (int i = 0; i < e->part_count; i++)
        if (e->parts[i].offset == offset && e->parts[i].len == len) { p = &e->parts[i]; break; }
    if (p && p->data) {
        p->used = ++e->part_clock;
        if (pin) p->pins++;
        return p->data;
    }
    if (len > PULLI_ACTIVE_MAX)
        return refuse(e, "%s is %u KB, more than the %u KB of the package a game may have in memory",
                      label, (len + 1023) / 1024, PULLI_ACTIVE_MAX / 1024);
    /* Room, from the parts used longest ago that are not in use. */
    while (e->active + len > PULLI_ACTIVE_MAX) {
        pulli_part *oldest = NULL;
        for (int i = 0; i < e->part_count; i++) {
            pulli_part *q = &e->parts[i];
            if (q->data && q->pins == 0 && (!oldest || q->used < oldest->used)) oldest = q;
        }
        if (!oldest)
            return refuse(e, "no room for %s (%u KB): %u KB of the package in memory is in use",
                          label, (len + 1023) / 1024, (e->active + 1023) / 1024);
        let_go(e, oldest);
    }
    if (!p) {
        if (e->part_count == e->part_cap) {
            int cap = e->part_cap ? e->part_cap * 2 : 32;
            pulli_part *grown = realloc(e->parts, (size_t)cap * sizeof(*grown));
            if (!grown) return no_memory(e, label);
            e->parts = grown;
            e->part_cap = cap;
        }
        p = &e->parts[e->part_count++];
        memset(p, 0, sizeof(*p));
        p->offset = offset;
        p->len = len;
        p->sound = sound;
    }
    uint8_t *buf = NULL;
    if (!e->pkg.base && !(buf = malloc(len ? len : 1)))
        return no_memory(e, label);
    const uint8_t *data;
    const char *why = pulli_pkg_get(&e->pkg, offset, len, buf, &data);
    if (why) {
        free(buf);
        snprintf(e->part_error, sizeof(e->part_error), "%s %s", label, why);
        return NULL;
    }
    p->buf = buf;
    p->data = data;
    p->used = ++e->part_clock;
    p->pins = pin ? 1 : 0;
    e->active += len;
    return data;
}

void pulli_part_unpin(pulli_engine *e, const uint8_t *data) {
    if (!data) return;
    for (int i = 0; i < e->part_count; i++)
        if (e->parts[i].data == data && e->parts[i].pins > 0) { e->parts[i].pins--; return; }
}

void pulli_parts_free(pulli_engine *e) {
    for (int i = 0; i < e->part_count; i++) free(e->parts[i].buf);
    free(e->parts);
    e->parts = NULL;
    e->part_count = e->part_cap = 0;
    e->active = 0;
}

/* A whole entry of the package, by name. */
const uint8_t *pulli_entry_use(pulli_engine *e, const char *name, bool pin, uint32_t *len) {
    pulli_entry en;
    if (!pulli_pkg_find(&e->pkg, name, &en)) {
        snprintf(e->part_error, sizeof(e->part_error), "the package has no '%s'", name);
        return NULL;
    }
    *len = en.len;
    return pulli_part_use(e, en.offset, en.len, name, pin, false);
}
