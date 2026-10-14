/* engine.c — one game's lifetime: package, manifest, Lua VM, frames.
 * No platform dependencies. A port owns the main loop and calls in here. */
#include "internal.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MANIFEST_HEAP   (64 * 1024)
#define MANIFEST_STEPS  100000
#define KOLAM_HEADER    8

typedef char pulli_strips_tile_the_screen[PULLI_SCREEN_H % PULLI_SCANOUT_ROWS == 0 ? 1 : -1];

static bool fail(pulli_engine *e, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(e->error, sizeof(e->error), fmt, ap);
    va_end(ap);
    e->running = false;
    return false;
}

/* The Lua heap is capped (SPEC §0.3): a game that would run out of memory
 * on the device has to run out of memory on the desktop too. */
static void *heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    pulli_engine *e = ud;
    size_t old = ptr ? osize : 0;
    if (nsize == 0) {
        free(ptr);
        e->heap_used -= old;
        return NULL;
    }
    if (nsize > old && nsize - old > e->heap_limit - e->heap_used) return NULL;
    void *p = realloc(ptr, nsize);
    if (!p) return NULL;
    e->heap_used = e->heap_used - old + nsize;
    if (e->heap_used > e->heap_peak) e->heap_peak = e->heap_used;
    return p;
}

static int traceback(lua_State *L) {
    const char *msg = lua_tostring(L, 1);
    luaL_traceback(L, L, msg ? msg : "error", 1);
    return 1;
}

static const char *top_message(lua_State *L) {
    const char *msg = lua_tostring(L, -1);
    return msg ? msg : "unknown error";
}

/* ---- manifest ------------------------------------------------------- */
struct boot_args { pulli_engine *e; pulli_blob src; };

static void manifest_hook(lua_State *L, lua_Debug *ar) {
    (void)ar;
    luaL_error(L, "ran for too long");
}

static void str_field(lua_State *L, const char *key, char *out, size_t cap, bool required) {
    out[0] = 0;
    int t = lua_getfield(L, -1, key);
    if (t == LUA_TNIL) {
        if (required) luaL_error(L, "'%s' is required", key);
    } else if (t != LUA_TSTRING) {
        luaL_error(L, "'%s' must be a string", key);
    } else {
        size_t n;
        const char *s = lua_tolstring(L, -1, &n);
        if (n >= cap || strlen(s) != n)
            luaL_error(L, "'%s' must be at most %d characters", key, (int)cap - 1);
        memcpy(out, s, n + 1);
    }
    lua_pop(L, 1);
}

static int int_field(lua_State *L, const char *key, int def, int min, int max) {
    int v = def;
    if (lua_getfield(L, -1, key) != LUA_TNIL) {
        int ok;
        lua_Integer n = lua_tointegerx(L, -1, &ok);
        if (!ok || n < min || n > max)
            luaL_error(L, "'%s' must be a whole number from %d to %d", key, min, max);
        v = (int)n;
    }
    lua_pop(L, 1);
    return v;
}

/* Runs protected, in a state with no libraries at all: a manifest is data,
 * and the launcher reads it for every game on the card (SPEC §2). */
static int read_manifest(lua_State *L) {
    struct boot_args *a = lua_touserdata(L, 1);
    pulli_manifest *m = &a->e->manifest;
    char target[8];

    if (luaL_loadbufferx(L, (const char *)a->src.data, a->src.len, "=manifest.lua", "t") != LUA_OK)
        return lua_error(L);
    lua_sethook(L, manifest_hook, LUA_MASKCOUNT, MANIFEST_STEPS);
    lua_call(L, 0, 1);
    lua_sethook(L, NULL, 0, 0);
    if (!lua_istable(L, -1)) luaL_error(L, "must return a table");

    str_field(L, "id", m->id, sizeof(m->id), true);
    for (const char *c = m->id; *c; c++) {
        bool ok = (*c >= 'a' && *c <= 'z') || (*c >= 'A' && *c <= 'Z') ||
                  (*c >= '0' && *c <= '9') || *c == '_' || *c == '-' || (*c == '.' && c != m->id);
        if (!ok) luaL_error(L, "'id' may only use letters, digits, '.', '_' and '-'");
    }
    if (!m->id[0]) luaL_error(L, "'id' is required");
    str_field(L, "title", m->title, sizeof(m->title), true);
    str_field(L, "author", m->author, sizeof(m->author), false);
    str_field(L, "version", m->version, sizeof(m->version), false);

    m->spec = int_field(L, "spec", 0, 1, 9999);
    if (m->spec == 0) luaL_error(L, "'spec' is required");
    if (m->spec > PULLI_SPEC_VERSION)
        luaL_error(L, "game needs Pulli spec %d; this runtime implements spec %d",
                   m->spec, PULLI_SPEC_VERSION);

    str_field(L, "save_target", target, sizeof(target), false);
    if      (!target[0] || !strcmp(target, "none")) m->save_target = PULLI_SAVE_NONE;
    else if (!strcmp(target, "sd"))                 m->save_target = PULLI_SAVE_SD;
    else if (!strcmp(target, "cart"))               m->save_target = PULLI_SAVE_CART;
    else luaL_error(L, "'save_target' must be \"sd\", \"cart\" or \"none\"");
    char mode[16];
    str_field(L, "save_mode", mode, sizeof(mode), false);
    if      (!mode[0] || !strcmp(mode, "exit")) m->save_mode = PULLI_SAVE_ON_EXIT;
    else if (!strcmp(mode, "auto"))             m->save_mode = PULLI_SAVE_AUTO;
    else luaL_error(L, "'save_mode' must be \"exit\" or \"auto\"");
    m->save_interval = int_field(L, "save_interval", PULLI_SAVE_INTERVAL_DEF,
                                 PULLI_SAVE_INTERVAL_MIN, PULLI_SAVE_INTERVAL_MAX);
    m->save_size   = int_field(L, "save_size", 4096, 16, PULLI_SAVE_MAX);
    m->lua_heap_kb = int_field(L, "lua_heap", PULLI_LUA_HEAP_MAX_KB, 16, PULLI_LUA_HEAP_MAX_KB);
    return 0;
}

static bool load_manifest(pulli_engine *e, pulli_blob src) {
    struct boot_args args = { e, src };
    e->heap_limit = MANIFEST_HEAP;
    lua_State *M = lua_newstate(heap_alloc, e);
    if (!M) return fail(e, "out of memory");
    lua_pushcfunction(M, read_manifest);
    lua_pushlightuserdata(M, &args);
    bool ok = lua_pcall(M, 1, 0, 0) == LUA_OK;
    if (!ok) {
        const char *msg = top_message(M);
        bool located = strncmp(msg, "manifest.lua:", 13) == 0;     /* e.g. a syntax error */
        fail(e, "%s%s", located ? "" : "manifest.lua: ", msg);
    }
    lua_close(M);
    return ok;
}

/* ---- assets --------------------------------------------------------- */
/* sprites.kolam: "KLM1", u16 width, u16 height, then width*height indexed
 * pixels. The pixels are used where they lie, never copied. */
static bool load_sprites(pulli_engine *e, pulli_blob b) {
    if (b.len < KOLAM_HEADER || memcmp(b.data, "KLM1", 4) != 0)
        return fail(e, "sprites.kolam: not a sprite sheet");
    uint32_t w = b.data[4] | ((uint32_t)b.data[5] << 8);
    uint32_t h = b.data[6] | ((uint32_t)b.data[7] << 8);
    if (w == 0 || h == 0 || w % PULLI_SPRITE_CELL || h % PULLI_SPRITE_CELL)
        return fail(e, "sprites.kolam: width and height must be multiples of %d", PULLI_SPRITE_CELL);
    if (w * h > PULLI_ATLAS_MAX || w * h != b.len - KOLAM_HEADER)
        return fail(e, "sprites.kolam: %ux%u does not match its %u bytes of pixels (max %d)",
                    (unsigned)w, (unsigned)h, (unsigned)(b.len - KOLAM_HEADER), PULLI_ATLAS_MAX);
    e->ctx.g.atlas = b.data + KOLAM_HEADER;
    e->ctx.g.atlas_w = (int)w;
    e->ctx.g.atlas_h = (int)h;
    return true;
}

/* ---- VM ------------------------------------------------------------- */
static int start_game(lua_State *L) {
    struct boot_args *a = lua_touserdata(L, 1);
    pulli_api_open(L, a->e);
    /* Source only for now. Lua does not verify bytecode, so accepting it
     * from a package means trusting whoever built the package. */
    if (luaL_loadbufferx(L, (const char *)a->src.data, a->src.len, "@main.lua", "t") != LUA_OK)
        return lua_error(L);
    lua_call(L, 0, 0);
    return 0;
}

/* Stack: the callback's name, then its arguments. A game need not define
 * every callback. */
static int call_global(lua_State *L) {
    const char *name = lua_touserdata(L, 1);
    if (lua_getglobal(L, name) != LUA_TFUNCTION) return 0;
    lua_insert(L, 2);
    lua_call(L, lua_gettop(L) - 2, 0);
    return 0;
}

static bool run_callback(pulli_engine *e, const char *name, bool pass_dt) {
    lua_State *L = e->L;
    lua_settop(L, 0);
    lua_pushcfunction(L, traceback);
    lua_pushcfunction(L, call_global);
    lua_pushlightuserdata(L, (void *)name);
    if (pass_dt) lua_pushnumber(L, (lua_Number)1 / PULLI_TICK_HZ);
    if (lua_pcall(L, pass_dt ? 2 : 1, 0, 1) != LUA_OK)
        return fail(e, "%s", top_message(L));
    return true;
}

static void teardown(pulli_engine *e) {
    if (e->L) lua_close(e->L);
    free(e->save);
    e->L = NULL;
    e->save = NULL;
    e->running = false;
}

bool pulli_boot(pulli_engine *e, const void *data, size_t len, const pulli_backend *backend) {
    pulli_blob manifest, main_lua, sprites;

    memset(e, 0, sizeof(*e));
    e->backend = backend;
    pulli_gfx_init(&e->ctx.g);

    const char *why = pulli_pkg_open(&e->pkg, data, len);
    if (why) return fail(e, "%s", why);
    if (!pulli_pkg_find(&e->pkg, "manifest.lua", &manifest)) return fail(e, "package has no manifest.lua");
    if (!pulli_pkg_find(&e->pkg, "main.lua", &main_lua))     return fail(e, "package has no main.lua");
    if (!load_manifest(e, manifest)) return false;
    if (pulli_pkg_find(&e->pkg, "sprites.kolam", &sprites) && !load_sprites(e, sprites)) return false;
    const char *bank, *why_not = pulli_audio_boot(e, &bank);
    if (why_not) return fail(e, "%s: %s", bank, why_not);
    /* Every map is checked now, so map.load() cannot meet a bad one later.
     * A game with a map.ooru starts with it loaded. */
    pulli_blob pal;
    pulli_default_palette(e->base_palette);
    if (pulli_pkg_find(&e->pkg, "palette.pal", &pal)) {
        if (pal.len != 4 + 3 * PULLI_PALETTE_LEN || memcmp(pal.data, "PAL1", 4) != 0)
            return fail(e, "palette.pal: not a palette of %d colours", PULLI_PALETTE_LEN);
        for (int i = 0; i < PULLI_PALETTE_LEN; i++) {
            const uint8_t *c = pal.data + 4 + 3 * i;
            e->base_palette[i] = (uint16_t)(((c[0] >> 3) << 11) | ((c[1] >> 2) << 5) | (c[2] >> 3));
        }
        pulli_load_palette(&e->ctx.g, e->base_palette);
    }
    for (unsigned i = 0; i < e->pkg.count; i++) {
        char name[PULLI_PKG_NAME_MAX + 1] = { 0 };          /* a full-length name has no terminator */
        memcpy(name, e->pkg.base + PULLI_PKG_HEADER + PULLI_PKG_ENTRY * i, PULLI_PKG_NAME_MAX);
        size_t n = strlen(name);
        pulli_blob map;
        if (n < 5 || strcmp(name + n - 5, ".ooru") != 0) continue;
        pulli_pkg_find(&e->pkg, name, &map);
        if ((why_not = pulli_map_check(map)) != NULL) return fail(e, "%s: %s", name, why_not);
        if (strcmp(name, "map.ooru") == 0) pulli_map_load(&e->ctx.map, map);
    }

    if (e->manifest.save_target != PULLI_SAVE_NONE) {
        e->save = malloc((size_t)e->manifest.save_size);
        if (!e->save) return fail(e, "out of memory");
        pulli_save_boot(e);
    }

    struct boot_args args = { e, main_lua };
    e->heap_limit = (size_t)e->manifest.lua_heap_kb * 1024;
    e->heap_peak = 0;
    e->L = lua_newstate(heap_alloc, e);
    if (!e->L) { teardown(e); return fail(e, "out of memory"); }
    lua_pushcfunction(e->L, traceback);
    lua_pushcfunction(e->L, start_game);
    lua_pushlightuserdata(e->L, &args);
    if (lua_pcall(e->L, 1, 0, 1) != LUA_OK || !run_callback(e, "init", false)) {
        if (!e->error[0]) fail(e, "%s", top_message(e->L));
        teardown(e);
        return false;
    }
    e->running = true;
    return true;
}

/* The developer's clock, if the port has one. */
static uint32_t now_us(const pulli_engine *e) {
    return e->backend && e->backend->micros ? e->backend->micros() : 0;
}

bool pulli_update(pulli_engine *e, uint32_t buttons) {
    if (!e->running) return false;
    uint32_t began = now_us(e);
    if (e->backend && e->backend->micros) {
        /* Updates a second: the updates begun in each second of the port's
         * clock, over the time they took to begin. */
        uint32_t elapsed = began - e->clock_since;
        if (e->clock_frames == 0) {
            e->clock_since = began;
        } else if (elapsed >= 1000000u) {
            e->fps = (uint32_t)(((uint64_t)e->clock_frames * 1000000u + elapsed / 2) / elapsed);
            e->clock_since = began;
            e->clock_frames = 0;
        }
        e->clock_frames++;
    }
    e->ctx.btn_state = buttons & ((1u << PULLI_BTN_COUNT) - 1);
    for (int i = 0; i < PULLI_BTN_COUNT; i++)
        e->ctx.btn_held[i] = (e->ctx.btn_state >> i) & 1u ? e->ctx.btn_held[i] + 1 : 0;
    e->ctx.frame++;
    e->link_sent = 0;
    e->link_side = 0;
    e->link_state = e->backend && e->backend->link_poll
        ? e->backend->link_poll(&e->link_side) : PULLI_LINK_OFF;
    if (e->link_state != PULLI_LINK_CONNECTED) e->link_side = 0;

    /* Step the GC every frame rather than letting it decide when to stop
     * the world. On the MCU this is not optional. */
    lua_gc(e->L, LUA_GCSTEP, 2);
    if (!run_callback(e, "update", true)) return false;
    if (e->backend && e->backend->micros) e->work_us = e->backend->micros() - began;

    /* "auto" saves: once a change has waited as long as the game asked for
     * (at least 10 s), write it. Whether the write worked is not the game's
     * concern here; it may ask with save_commit(). A failed write is not
     * retried every frame. */
    if (e->save && e->manifest.save_mode == PULLI_SAVE_AUTO && e->save_dirty &&
        e->ctx.frame - e->save_written >= (uint32_t)e->manifest.save_interval * PULLI_TICK_HZ) {
        pulli_save_commit(e);
        e->save_written = e->ctx.frame;
    }

    /* This frame's sound, including whatever update() just started. */
    if (e->backend && e->backend->audio) {
        pulli_audio_mix(&e->audio, e->audio.out, PULLI_AUDIO_FRAMES);
        e->backend->audio(e->audio.out, PULLI_AUDIO_FRAMES);
    }
    return true;
}

bool pulli_draw(pulli_engine *e) {
    if (!e->running) return false;
    uint32_t began = now_us(e);
    bool ok = run_callback(e, "draw", false);
    if (e->backend && e->backend->micros) {
        uint32_t used = e->work_us + (e->backend->micros() - began);   /* update and draw of this frame */
        e->cpu = (uint32_t)(((uint64_t)used * 100u + 8333u) / 16667u);
        e->work_us = 0;
    }
    return ok;
}

void pulli_present(pulli_engine *e) {
    static uint16_t strip[PULLI_SCANOUT_ROWS * PULLI_SCREEN_W];
    if (!e->backend || !e->backend->present) return;
    for (int y = 0; y < PULLI_SCREEN_H; y += PULLI_SCANOUT_ROWS) {
        pulli_scanout(&e->ctx.g, y, PULLI_SCANOUT_ROWS, strip);
        e->backend->present(strip, y, PULLI_SCANOUT_ROWS);
    }
}

void pulli_shutdown(pulli_engine *e) {
    if (e->save && !pulli_save_commit(e) && e->backend && e->backend->log)
        e->backend->log("save data could not be written");
    teardown(e);
}
