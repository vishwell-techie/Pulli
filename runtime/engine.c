/* engine.c — one game's lifetime: package, manifest, Lua VM, frames.
 * No platform dependencies. A port owns the main loop and calls in here. */
#include "internal.h"
#include "luadebug.h"
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
 * on the device has to run out of memory on the desktop too. The console
 * has 4-byte pointers; a desktop with 8-byte ones counts the same objects
 * about 1.47 times bigger (measured against a Pico 2: 1.47 to 1.49 for
 * whole games, more for a bare Lua state). The desktop counts in its own bytes and scales the
 * limit and what it reports, so stat("mem") and running out of memory come
 * within about 1% of the console, on the high side (SPEC §10). */
#define HEAP_WIDE    (sizeof(void *) > 4)
#define HEAP_TO(b)   (HEAP_WIDE ? (b) * 100 / 147 : (b))     /* to the console's bytes */
#define HEAP_FROM(b) (HEAP_WIDE ? (b) * 147 / 100 : (b))     /* and back */

size_t pulli_heap_used(const pulli_engine *e) { return HEAP_TO(e->heap_used); }
size_t pulli_heap_peak(const pulli_engine *e) { return HEAP_TO(e->heap_peak); }

/* The debug information kept in a debug build: its blocks, by address, so
 * the heap counts it as if it had been dropped (a debug build runs out of
 * memory where a release build does). An open-addressed table of pointers,
 * outside the Lua heap. */
struct pulli_debug_set { const void **p; size_t *n; size_t cap, used; };
#define GONE ((const void *)1)

static size_t slot_of(const struct pulli_debug_set *s, const void *p) {
    return (size_t)(((uintptr_t)p >> 3) * 2654435761u) & (s->cap - 1);
}

static bool debug_set_add(struct pulli_debug_set *s, const void *p, size_t n) {
    if ((s->used + 1) * 4 > s->cap * 3) {                   /* grow, dropping the gone */
        struct pulli_debug_set g = { NULL, NULL, s->cap ? s->cap * 2 : 256, 0 };
        g.p = calloc(g.cap, sizeof(*g.p));
        g.n = calloc(g.cap, sizeof(*g.n));
        if (!g.p || !g.n) { free(g.p); free(g.n); return false; }
        for (size_t i = 0; i < s->cap; i++)
            if (s->p[i] && s->p[i] != GONE) {
                size_t j = slot_of(&g, s->p[i]);
                while (g.p[j]) j = (j + 1) & (g.cap - 1);
                g.p[j] = s->p[i];
                g.n[j] = s->n[i];
                g.used++;
            }
        free(s->p);
        free(s->n);
        *s = g;
    }
    size_t j = slot_of(s, p);
    while (s->p[j] && s->p[j] != GONE) j = (j + 1) & (s->cap - 1);
    if (!s->p[j]) s->used++;                                 /* (a gone slot is counted already) */
    s->p[j] = p;
    s->n[j] = n;
    return true;
}

/* Whether p is a debug block; if so it is forgotten. */
static bool debug_set_take(struct pulli_debug_set *s, const void *p) {
    if (!s->cap) return false;
    for (size_t j = slot_of(s, p); s->p[j]; j = (j + 1) & (s->cap - 1))
        if (s->p[j] == p) { s->p[j] = GONE; return true; }
    return false;
}

static void keep_block(void *ud, const void *block, size_t bytes) {
    pulli_engine *e = ud;
    if (debug_set_add(e->debug_blocks, block, bytes)) e->heap_used -= bytes;
}

/* A chunk compiled (main.lua, a module): its debug information is dropped,
 * or in a debug build kept and left out of the count. */
void pulli_lua_loaded(pulli_engine *e, lua_State *L) {
    if (!e->debug) pulli_lua_strip(L);
    else if (e->debug_blocks) pulli_lua_debug_blocks(L, keep_block, e);
}

static void *heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    pulli_engine *e = ud;
    size_t old = ptr ? osize : 0;
    if (ptr && e->debug_blocks && debug_set_take(e->debug_blocks, ptr))
        e->heap_used += old;                    /* not counted: counted again, to be let go */
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
    lua_getfield(L, -1, "debug");
    if (!lua_isnil(L, -1) && !lua_isboolean(L, -1)) luaL_error(L, "'debug' must be true or false");
    m->debug = lua_toboolean(L, -1);
    lua_pop(L, 1);
    return 0;
}

static bool load_manifest(pulli_engine *e, pulli_blob src) {
    struct boot_args args = { e, src };
    e->heap_limit = HEAP_FROM(MANIFEST_HEAP);
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
/* A .kolam: "KLM1", u16 width, u16 height, then width*height indexed
 * pixels. The sheet in use is pinned in the active set, and its pixels are
 * drawn from where they lie there. */
const char *pulli_sheet_load(pulli_engine *e, const char *name) {
    static char why[160];
    uint32_t len;
    const uint8_t *b = pulli_entry_use(e, name, true, &len);
    if (!b) return e->part_error;
    uint32_t w = len < KOLAM_HEADER ? 0 : b[4] | ((uint32_t)b[5] << 8);
    uint32_t h = len < KOLAM_HEADER ? 0 : b[6] | ((uint32_t)b[7] << 8);
    why[0] = 0;
    if (len < KOLAM_HEADER || memcmp(b, "KLM1", 4) != 0)
        snprintf(why, sizeof(why), "%s: not a sprite sheet", name);
    else if (w == 0 || h == 0 || w % PULLI_SPRITE_CELL || h % PULLI_SPRITE_CELL)
        snprintf(why, sizeof(why), "%s: width and height must be multiples of %d", name, PULLI_SPRITE_CELL);
    else if (w * h > PULLI_ATLAS_MAX || w * h != len - KOLAM_HEADER)
        snprintf(why, sizeof(why), "%s: %ux%u does not match its %u bytes of pixels (max %d)",
                 name, (unsigned)w, (unsigned)h, (unsigned)(len - KOLAM_HEADER), PULLI_ATLAS_MAX);
    if (why[0]) { pulli_part_unpin(e, b); return why; }
    pulli_part_unpin(e, e->sheet);                 /* the sheet before may now be let go */
    e->sheet = b;
    e->ctx.g.atlas = b + KOLAM_HEADER;
    e->ctx.g.atlas_w = (int)w;
    e->ctx.g.atlas_h = (int)h;
    return NULL;
}

/* The backdrop: a .kolam exactly the screen's size, kept in the active set
 * while it is set, so it is read (and on a two-chip console sent to the
 * GPU) once, not every frame. NULL lets it go. */
const char *pulli_backdrop_load(pulli_engine *e, const char *name) {
    static char why[160];
    if (!name) {
        pulli_part_unpin(e, e->backdrop_part);
        e->backdrop_part = NULL;
        e->ctx.g.backdrop = NULL;
        return NULL;
    }
    uint32_t len;
    const uint8_t *b = pulli_entry_use(e, name, true, &len);
    if (!b) return e->part_error;
    uint32_t w = len < KOLAM_HEADER ? 0 : b[4] | ((uint32_t)b[5] << 8);
    uint32_t h = len < KOLAM_HEADER ? 0 : b[6] | ((uint32_t)b[7] << 8);
    why[0] = 0;
    if (len < KOLAM_HEADER || memcmp(b, "KLM1", 4) != 0)
        snprintf(why, sizeof(why), "%s: not a picture (.kolam)", name);
    else if (w != PULLI_SCREEN_W || h != PULLI_SCREEN_H || len - KOLAM_HEADER != PULLI_FB_BYTES)
        snprintf(why, sizeof(why), "%s: %ux%u; a backdrop is the screen's size, %dx%d",
                 name, (unsigned)w, (unsigned)h, PULLI_SCREEN_W, PULLI_SCREEN_H);
    if (why[0]) { pulli_part_unpin(e, b); return why; }
    if (b != e->backdrop_part) pulli_part_unpin(e, e->backdrop_part);
    else pulli_part_unpin(e, b);                   /* the same one again: pinned once */
    e->backdrop_part = b;
    e->ctx.g.backdrop = b + KOLAM_HEADER;
    return NULL;
}

/* A map: its cells are copied into the engine (a game may change them);
 * the part stays pinned while it is the map in use, as its tile flags are
 * read where they lie. */
const char *pulli_map_use(pulli_engine *e, const char *name) {
    static char why[160];
    uint32_t len;
    const uint8_t *b = pulli_entry_use(e, name, true, &len);
    if (!b) return e->part_error;
    pulli_blob blob = { b, len };
    const char *bad = pulli_map_check(blob);
    if (bad) {
        pulli_part_unpin(e, b);
        snprintf(why, sizeof(why), "%s: %s", name, bad);
        return why;
    }
    pulli_part_unpin(e, e->map_part);
    e->map_part = b;
    pulli_map_load(&e->ctx.map, blob);
    return NULL;
}

/* ---- VM ------------------------------------------------------------- */
static int start_game(lua_State *L) {
    struct boot_args *a = lua_touserdata(L, 1);
    pulli_api_open(L, a->e);
    /* Source only for now. Lua does not verify bytecode, so accepting it
     * from a package means trusting whoever built the package. */
    if (luaL_loadbufferx(L, (const char *)a->src.data, a->src.len, "@main.lua", "t") != LUA_OK)
        return lua_error(L);
    pulli_lua_loaded(a->e, L);
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
    if (e->debug_blocks) {
        free(e->debug_blocks->p);
        free(e->debug_blocks->n);
        free(e->debug_blocks);
        e->debug_blocks = NULL;
    }
    free(e->save);
    pulli_parts_free(e);
    pulli_pkg_close(&e->pkg);
    e->L = NULL;
    e->save = NULL;
    e->sheet = e->map_part = e->backdrop_part = NULL;
    e->ctx.g.backdrop = NULL;
    e->running = false;
}

/* A failed boot frees what it took, so the engine can be booted again. */
static bool boot_fail(pulli_engine *e, const char *fmt, const char *a, const char *b) {
    fail(e, fmt, a, b);
    teardown(e);
    return false;
}

bool pulli_boot(pulli_engine *e, const void *data, size_t len, const pulli_backend *backend) {
    pulli_blob manifest, main_lua;
    pulli_entry en;
    const char *why;

    memset(e, 0, sizeof(*e));
    e->backend = backend;
    pulli_gfx_init(&e->ctx.g);
    e->ctx.g.halves = backend ? backend->halves : NULL;

    /* Only the front of the package is read and checked now; its parts
     * come into the active set as the game uses them (SPEC §2). */
    why = pulli_pkg_open(&e->pkg, data, len, data ? NULL : backend ? backend->pkg_read : NULL);
    if (why) return fail(e, "%s", why);
    if (!pulli_pkg_find(&e->pkg, "manifest.lua", NULL)) return boot_fail(e, "%s%s", "package has no manifest.lua", "");
    if (!pulli_pkg_find(&e->pkg, "main.lua", NULL))     return boot_fail(e, "%s%s", "package has no main.lua", "");
    manifest.data = pulli_entry_use(e, "manifest.lua", false, &manifest.len);
    if (!manifest.data) return boot_fail(e, "%s%s", e->part_error, "");
    if (!load_manifest(e, manifest)) { teardown(e); return false; }
    if (pulli_pkg_find(&e->pkg, "sprites.kolam", NULL) && (why = pulli_sheet_load(e, "sprites.kolam")))
        return boot_fail(e, "%s%s", why, "");
    const char *bank;
    if ((why = pulli_audio_boot(e, &bank))) return boot_fail(e, "%s: %s", bank, why);
    pulli_default_palette(e->base_palette);
    if (pulli_pkg_find(&e->pkg, "palette.pal", &en)) {
        uint32_t n;
        const uint8_t *pal = pulli_entry_use(e, "palette.pal", false, &n);
        if (!pal) return boot_fail(e, "%s%s", e->part_error, "");
        if (n != 4 + 3 * PULLI_PALETTE_LEN || memcmp(pal, "PAL1", 4) != 0)
            return boot_fail(e, "palette.pal: not a palette of %s colours%s", "64", "");
        for (int i = 0; i < PULLI_PALETTE_LEN; i++) {
            const uint8_t *c = pal + 4 + 3 * i;
            e->base_palette[i] = (uint16_t)(((c[0] >> 3) << 11) | ((c[1] >> 2) << 5) | (c[2] >> 3));
        }
        pulli_load_palette(&e->ctx.g, e->base_palette);
    }
    /* A game with a map.ooru starts with it loaded. Other maps are checked
     * when map.load() reads them. */
    if (pulli_pkg_find(&e->pkg, "map.ooru", NULL) && (why = pulli_map_use(e, "map.ooru")))
        return boot_fail(e, "%s%s", why, "");
    main_lua.data = pulli_entry_use(e, "main.lua", false, &main_lua.len);
    if (!main_lua.data) return boot_fail(e, "%s%s", e->part_error, "");

    if (e->manifest.save_target != PULLI_SAVE_NONE) {
        e->save = malloc((size_t)e->manifest.save_size);
        if (!e->save) return boot_fail(e, "%s%s", "out of memory", "");
        pulli_save_boot(e);
    }

    struct boot_args args = { e, main_lua };
    e->heap_limit = HEAP_FROM((size_t)e->manifest.lua_heap_kb * 1024);
    e->heap_peak = 0;
    /* A debug build keeps the game's debug information: asked for by the
     * manifest, or by the developer (--debug, PULLI_DEBUG). */
    e->debug = e->manifest.debug || (backend && backend->debug);
    if (e->debug) {
        e->debug_blocks = calloc(1, sizeof(*e->debug_blocks));
        if (!e->debug_blocks) return boot_fail(e, "%s%s", "out of memory", "");
    }
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
