/* save.c — Ninaivu, the save store (SPEC §3 "Save data").
 *
 * A game's saves are one blob of at most manifest.save_size bytes, held in
 * RAM while the game runs and handed to the backend whole. The backend only
 * ever reads or writes that blob, which is what keeps SD and cartridge
 * saves indistinguishable to a game, and to a port.
 *
 *   blob    "NNV1", then records back to back
 *   record  u8 key length, u8 type, u16 value length (LE), key, value
 *
 * Integers and floats are stored as 4 little-endian bytes. */
#include "internal.h"
#include <string.h>

#define NV_MAGIC   "NNV1"
#define NV_HEAD    4
#define NV_KEY_MAX 32

enum { NV_FALSE = 1, NV_TRUE, NV_INT, NV_FLOAT, NV_STRING };

static bool key_ok(const char *k, size_t n) {
    if (n == 0 || n > NV_KEY_MAX) return false;
    for (size_t i = 0; i < n; i++) {
        char c = k[i];
        bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                  (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.';
        if (!ok) return false;
    }
    return true;
}

/* Size of the record at p, or 0 if it does not fit inside the blob. */
static uint32_t record_size(const pulli_engine *e, uint32_t p) {
    if (e->save_len - p < 4) return 0;
    uint32_t n = 4u + e->save[p] + (e->save[p + 2] | ((uint32_t)e->save[p + 3] << 8));
    return n <= e->save_len - p ? n : 0;
}

static bool find(const pulli_engine *e, const char *key, size_t klen, uint32_t *at) {
    uint32_t size;
    for (uint32_t p = NV_HEAD; p < e->save_len && (size = record_size(e, p)) != 0; p += size) {
        if (e->save[p] == klen && memcmp(e->save + p + 4, key, klen) == 0) {
            *at = p;
            return true;
        }
    }
    return false;
}

static void start_empty(pulli_engine *e) {
    memcpy(e->save, NV_MAGIC, NV_HEAD);
    e->save_len = NV_HEAD;
}

void pulli_save_boot(pulli_engine *e) {
    const pulli_backend *be = e->backend;
    if (!e->save) return;
    start_empty(e);
    if (!be || !be->save_read) return;

    int n = be->save_read(e->manifest.id, e->save, (size_t)e->manifest.save_size);
    if (n < 0) return;                                  /* no save yet */
    if (n < NV_HEAD || memcmp(e->save, NV_MAGIC, NV_HEAD) != 0) {
        if (be->log) be->log("save data is not in a known format; starting empty");
        start_empty(e);
        return;
    }
    e->save_len = n > e->manifest.save_size ? (uint32_t)e->manifest.save_size : (uint32_t)n;
    /* Keep the records that parse and drop a damaged tail. */
    uint32_t p = NV_HEAD;
    while (p < e->save_len) {
        uint32_t size = record_size(e, p);
        if (size == 0 || !key_ok((const char *)e->save + p + 4, e->save[p])) {
            if (be->log) be->log("save data is damaged; later entries were dropped");
            break;
        }
        p += size;
    }
    e->save_len = p;
}

bool pulli_save_commit(pulli_engine *e) {
    const pulli_backend *be = e->backend;
    if (!e->save || !e->save_dirty) return true;
    if (!be || !be->save_write || !be->save_write(e->manifest.id, e->save, e->save_len))
        return false;
    e->save_dirty = false;
    return true;
}

bool pulli_save_set(pulli_engine *e, lua_State *L, const char *key, size_t klen, int idx) {
    uint8_t num[4];
    const uint8_t *val = num;
    size_t vlen = 0;
    uint8_t type;

    if (!e->save || !key_ok(key, klen)) return false;
    switch (lua_type(L, idx)) {
    case LUA_TNIL:
        type = 0;                                       /* delete */
        break;
    case LUA_TBOOLEAN:
        type = lua_toboolean(L, idx) ? NV_TRUE : NV_FALSE;
        break;
    case LUA_TNUMBER: {
        uint32_t bits;
        if (lua_isinteger(L, idx)) {
            type = NV_INT;
            bits = (uint32_t)lua_tointeger(L, idx);
        } else {
            lua_Number f = lua_tonumber(L, idx);
            type = NV_FLOAT;
            memcpy(&bits, &f, 4);
        }
        num[0] = (uint8_t)bits; num[1] = (uint8_t)(bits >> 8);
        num[2] = (uint8_t)(bits >> 16); num[3] = (uint8_t)(bits >> 24);
        vlen = 4;
        break;
    }
    case LUA_TSTRING:
        type = NV_STRING;
        val = (const uint8_t *)lua_tolstring(L, idx, &vlen);
        if (vlen > 0xFFFF) return false;
        break;
    default:
        return false;                                   /* tables: not yet */
    }

    uint32_t at = 0, old = 0;
    if (find(e, key, klen, &at)) old = record_size(e, at);
    uint32_t add = type ? (uint32_t)(4 + klen + vlen) : 0;
    if (e->save_len - old + add > (uint32_t)e->manifest.save_size) return false;

    if (old) {
        memmove(e->save + at, e->save + at + old, e->save_len - at - old);
        e->save_len -= old;
    }
    if (type) {
        uint8_t *r = e->save + e->save_len;
        r[0] = (uint8_t)klen; r[1] = type;
        r[2] = (uint8_t)vlen; r[3] = (uint8_t)(vlen >> 8);
        memcpy(r + 4, key, klen);
        memcpy(r + 4 + klen, val, vlen);
        e->save_len += add;
    }
    if (old || add) e->save_dirty = true;
    return true;
}

/* Pushes the stored value and returns true, or pushes nothing. */
bool pulli_save_get(pulli_engine *e, lua_State *L, const char *key, size_t klen) {
    uint32_t at;
    if (!e->save || !key_ok(key, klen) || !find(e, key, klen, &at)) return false;

    const uint8_t *r = e->save + at;
    const uint8_t *val = r + 4 + r[0];
    uint32_t vlen = r[2] | ((uint32_t)r[3] << 8);
    uint32_t bits = vlen == 4
        ? (uint32_t)val[0] | ((uint32_t)val[1] << 8) | ((uint32_t)val[2] << 16) | ((uint32_t)val[3] << 24)
        : 0;

    switch (r[1]) {
    case NV_FALSE:  lua_pushboolean(L, 0); return true;
    case NV_TRUE:   lua_pushboolean(L, 1); return true;
    case NV_INT:    lua_pushinteger(L, (lua_Integer)(int32_t)bits); return true;
    case NV_FLOAT: { lua_Number f; memcpy(&f, &bits, 4); lua_pushnumber(L, f); return true; }
    case NV_STRING: lua_pushlstring(L, (const char *)val, vlen); return true;
    default:        return false;                       /* written by a newer runtime */
    }
}
