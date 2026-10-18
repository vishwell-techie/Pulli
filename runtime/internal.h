/* internal.h — shared between the runtime's own source files only. */
#ifndef PULLI_INTERNAL_H
#define PULLI_INTERNAL_H

#include "pulli.h"
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

/* The number model is part of the platform contract: 32-bit integers and
 * 32-bit floats, on the desktop and on the device alike. A game that fits
 * and behaves one way on a laptop must do the same in the hand. */
typedef char pulli_needs_32bit_lua_integer[sizeof(lua_Integer) == 4 ? 1 : -1];
typedef char pulli_needs_32bit_lua_number[sizeof(lua_Number) == 4 ? 1 : -1];

/* sha256.c */
void pulli_sha256(const uint8_t *data, size_t len, uint8_t out[32]);

/* parts.c — the active set. A use returns the bytes, or NULL and the
 * reason in e->part_error. */
const uint8_t *pulli_part_use(pulli_engine *e, uint32_t offset, uint32_t len, const char *label,
                              bool pin, bool sound);
const uint8_t *pulli_entry_use(pulli_engine *e, const char *name, bool pin, uint32_t *len);
void pulli_part_unpin(pulli_engine *e, const uint8_t *data);
void pulli_parts_sound_pins(pulli_engine *e);
void pulli_parts_free(pulli_engine *e);

/* engine.c: the sprite sheet and map in use. NULL, or why not. */
const char *pulli_sheet_load(pulli_engine *e, const char *name);
const char *pulli_map_use(pulli_engine *e, const char *name);

/* audio.c */
const char *pulli_audio_boot(pulli_engine *e, const char **which);   /* NULL, or why a bank is bad */
/* These two read the sound into the active set first: NULL, or why not. */
const char *pulli_audio_sfx(pulli_engine *e, int n, int channel);
const char *pulli_audio_music(pulli_engine *e, int n, int fade_ms, bool looping);
const char *pulli_audio_preload(pulli_engine *e, bool music, int n);   /* NULL, or why not */
void pulli_audio_music_stop(pulli_audio *a, int fade_ms);
void pulli_audio_music_pause(pulli_audio *a, bool paused);

/* map.c */
const char *pulli_map_check(pulli_blob b);              /* NULL, or why it is not a map */
void pulli_map_load(pulli_map *m, pulli_blob b);        /* b must have passed the check */

/* api.c */
void pulli_api_open(lua_State *L, pulli_engine *e);

/* save.c — Ninaivu, the key-value save store */
void pulli_save_boot(pulli_engine *e);
bool pulli_save_commit(pulli_engine *e);
bool pulli_save_set(pulli_engine *e, lua_State *L, const char *key, size_t klen, int value_idx);
bool pulli_save_get(pulli_engine *e, lua_State *L, const char *key, size_t klen);

#endif
