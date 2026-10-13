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

/* audio.c */
const char *pulli_audio_boot(pulli_engine *e, const char **which);   /* NULL, or why a bank is bad */
void pulli_audio_sfx(pulli_audio *a, int n, int channel);
void pulli_audio_music(pulli_audio *a, int n, int fade_ms, bool looping);
void pulli_audio_music_stop(pulli_audio *a, int fade_ms);

/* api.c */
void pulli_api_open(lua_State *L, pulli_engine *e);

/* save.c — Ninaivu, the key-value save store */
void pulli_save_boot(pulli_engine *e);
bool pulli_save_commit(pulli_engine *e);
bool pulli_save_set(pulli_engine *e, lua_State *L, const char *key, size_t klen, int value_idx);
bool pulli_save_get(pulli_engine *e, lua_State *L, const char *key, size_t klen);

#endif
