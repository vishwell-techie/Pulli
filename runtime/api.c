/* api.c — the Lua-facing API from SPEC §3.
 * This file is the platform's public contract. Changing a signature here
 * breaks every game ever written for Pulli, so it changes slowly. */
#include "internal.h"
#include <math.h>
#include <string.h>

static pulli_engine *E;     /* the one running game */

static const char *BTN_NAMES[PULLI_BTN_COUNT] = {
    "left","right","up","down","a","b","x","y","l","r","start","select"
};

/* Every coordinate and size goes through here. Fractions round down, so a
 * game can keep positions as floats, and the result is held to the 16-bit
 * range that the CPU-to-GPU command format carries. */
static int arg_i(lua_State *L, int i, int def) {
    if (lua_isnoneornil(L, i)) return def;
    lua_Number n = l_mathop(floor)(lua_tonumber(L, i));
    if (!(n > -32768)) return -32768;      /* also catches NaN */
    if (n > 32767) return 32767;
    return (int)n;
}
static bool arg_b(lua_State *L, int i, bool def) {
    return lua_isnoneornil(L, i) ? def : lua_toboolean(L, i);
}

/* ---- graphics ------------------------------------------------------ */
static int l_cls(lua_State *L)  { pulli_cls(&E->ctx.g, arg_i(L,1,0)); return 0; }
static int l_pset(lua_State *L) { pulli_pset(&E->ctx.g, arg_i(L,1,0), arg_i(L,2,0), arg_i(L,3,7)); return 0; }
static int l_pget(lua_State *L) { lua_pushinteger(L, pulli_pget(&E->ctx.g, arg_i(L,1,0), arg_i(L,2,0))); return 1; }
static int l_line(lua_State *L) { pulli_line(&E->ctx.g, arg_i(L,1,0),arg_i(L,2,0),arg_i(L,3,0),arg_i(L,4,0),arg_i(L,5,7)); return 0; }
static int l_rect(lua_State *L) { pulli_rect(&E->ctx.g, arg_i(L,1,0),arg_i(L,2,0),arg_i(L,3,0),arg_i(L,4,0),arg_i(L,5,7)); return 0; }
static int l_rectfill(lua_State *L) { pulli_rectfill(&E->ctx.g, arg_i(L,1,0),arg_i(L,2,0),arg_i(L,3,0),arg_i(L,4,0),arg_i(L,5,7)); return 0; }
static int l_circ(lua_State *L) { pulli_circ(&E->ctx.g, arg_i(L,1,0),arg_i(L,2,0),arg_i(L,3,1),arg_i(L,4,7)); return 0; }
static int l_circfill(lua_State *L){ pulli_circfill(&E->ctx.g, arg_i(L,1,0),arg_i(L,2,0),arg_i(L,3,1),arg_i(L,4,7)); return 0; }

static int l_spr(lua_State *L) {
    pulli_spr(&E->ctx.g, arg_i(L,1,0), arg_i(L,2,0), arg_i(L,3,0),
              arg_i(L,4,1), arg_i(L,5,1), arg_b(L,6,false), arg_b(L,7,false));
    return 0;
}
static int l_sspr(lua_State *L) {
    pulli_sspr(&E->ctx.g, arg_i(L,1,0),arg_i(L,2,0),arg_i(L,3,0),arg_i(L,4,0),
               arg_i(L,5,0),arg_i(L,6,0),
               arg_i(L,7,arg_i(L,3,0)), arg_i(L,8,arg_i(L,4,0)));
    return 0;
}
static int l_print(lua_State *L) {
    lua_settop(L, 4);
    const char *s = luaL_tolstring(L, 1, NULL);
    pulli_print(&E->ctx.g, s, arg_i(L,2,0), arg_i(L,3,0), arg_i(L,4,7));
    return 0;
}
static int l_camera(lua_State *L) { pulli_camera(&E->ctx.g, arg_i(L,1,0), arg_i(L,2,0)); return 0; }
static int l_clip(lua_State *L)   { pulli_clip(&E->ctx.g, arg_i(L,1,0),arg_i(L,2,0),arg_i(L,3,0),arg_i(L,4,0)); return 0; }
static int l_pal(lua_State *L)    { pulli_pal(&E->ctx.g, arg_i(L,1,-1), arg_i(L,2,0)); return 0; }
static int l_palt(lua_State *L)   { pulli_palt(&E->ctx.g, arg_i(L,1,-1), arg_b(L,2,true)); return 0; }
static int l_fade(lua_State *L)   { pulli_fade(&E->ctx.g, (float)luaL_optnumber(L,1,0)); return 0; }

/* ---- input --------------------------------------------------------- */
static int btn_index(lua_State *L, int arg) {
    if (lua_type(L, arg) == LUA_TNUMBER) {
        int i = arg_i(L, arg, -1);
        return (i >= 0 && i < PULLI_BTN_COUNT) ? i : -1;
    }
    const char *s = lua_tostring(L, arg);
    if (!s) return -1;
    for (int i = 0; i < PULLI_BTN_COUNT; i++)
        if (strcmp(s, BTN_NAMES[i]) == 0) return i;
    return -1;
}
static int l_btn(lua_State *L) {
    int b = btn_index(L, 1);
    lua_pushboolean(L, b >= 0 && (E->ctx.btn_state & (1u << b)));
    return 1;
}
static int l_btnp(lua_State *L) {
    int b = btn_index(L, 1);
    lua_pushboolean(L, b >= 0 && (E->ctx.btn_state & (1u<<b)) && !(E->ctx.btn_prev & (1u<<b)));
    return 1;
}

/* ---- audio (backend-delegated) ------------------------------------- */
static int l_sfx(lua_State *L) {
    const pulli_backend *B = E->backend;
    if (B && B->audio_sfx) B->audio_sfx(arg_i(L,1,0), arg_i(L,2,-1));
    return 0;
}
static int l_music(lua_State *L) {
    const pulli_backend *B = E->backend;
    if (B && B->audio_music) B->audio_music(arg_i(L,1,0), arg_i(L,2,0));
    return 0;
}
static int l_music_stop(lua_State *L) {
    const pulli_backend *B = E->backend;
    if (B && B->audio_music) B->audio_music(-1, arg_i(L,1,0));
    return 0;
}

/* ---- save data -----------------------------------------------------
 * Games get a key-value store, never a filesystem. That single restriction
 * is what makes SD and cartridge saves indistinguishable to a game. */
static int l_save(lua_State *L) {
    size_t klen;
    const char *k = luaL_checklstring(L, 1, &klen);
    lua_settop(L, 2);
    lua_pushboolean(L, pulli_save_set(E, L, k, klen, 2));
    return 1;
}
static int l_load(lua_State *L) {
    size_t klen;
    const char *k = luaL_checklstring(L, 1, &klen);
    lua_settop(L, 2);
    if (!pulli_save_get(E, L, k, klen)) lua_pushvalue(L, 2);   /* the default */
    return 1;
}
static int l_save_commit(lua_State *L) {
    lua_pushboolean(L, pulli_save_commit(E));
    return 1;
}

/* ---- system -------------------------------------------------------- */
static int l_time(lua_State *L) {
    lua_pushnumber(L, (lua_Number)E->ctx.frame / PULLI_TICK_HZ);
    return 1;
}
static int l_dbg(lua_State *L) {
    const pulli_backend *B = E->backend;
    int n = lua_gettop(L);
    char out[512]; out[0] = 0;
    for (int i = 1; i <= n; i++) {
        const char *s = luaL_tolstring(L, i, NULL);
        strncat(out, s, sizeof(out) - strlen(out) - 2);
        if (i < n) strncat(out, "\t", sizeof(out) - strlen(out) - 2);
        lua_pop(L, 1);
    }
    if (B && B->log) B->log(out);
    return 0;
}
static int l_stat(lua_State *L) {
    const char *what = luaL_optstring(L, 1, "");
    if      (!strcmp(what, "mem"))   lua_pushnumber(L, (lua_Number)E->heap_used / 1024);
    else if (!strcmp(what, "frame")) lua_pushinteger(L, (lua_Integer)E->ctx.frame);
    else lua_pushnil(L);
    return 1;
}
static int l_sys_has(lua_State *L) {
    static const char *CAPS[] = { "video", "wifi", "cart", "rumble", "link", NULL };
    const char *cap = luaL_optstring(L, 1, "");
    uint32_t have = E->backend ? E->backend->caps : 0;
    bool has = false;
    for (int i = 0; CAPS[i]; i++)
        if (!strcmp(cap, CAPS[i])) has = (have >> i) & 1u;
    lua_pushboolean(L, has);
    return 1;
}

/* ---- map ----------------------------------------------------------- */
static int l_map_draw(lua_State *L) {
    pulli_map_draw(&E->ctx, arg_i(L,1,0), arg_i(L,2,0), arg_i(L,3,0));
    return 0;
}
static int l_map_get(lua_State *L) {
    int layer = arg_i(L,1,0), cx = arg_i(L,2,0), cy = arg_i(L,3,0);
    pulli_layer *lay = &E->ctx.layers[layer < 0 || layer > 1 ? 0 : layer];
    if (!lay->tiles || cx < 0 || cy < 0 || cx >= lay->w || cy >= lay->h)
        lua_pushinteger(L, 0);
    else
        lua_pushinteger(L, lay->tiles[cy * lay->w + cx]);
    return 1;
}

static const luaL_Reg CORE[] = {
    {"cls",l_cls},{"pset",l_pset},{"pget",l_pget},{"line",l_line},
    {"rect",l_rect},{"rectfill",l_rectfill},{"circ",l_circ},{"circfill",l_circfill},
    {"spr",l_spr},{"sspr",l_sspr},{"print",l_print},{"camera",l_camera},
    {"clip",l_clip},{"pal",l_pal},{"palt",l_palt},{"fade",l_fade},
    {"btn",l_btn},{"btnp",l_btnp},
    {"sfx",l_sfx},{"music",l_music},{"music_stop",l_music_stop},
    {"save",l_save},{"load",l_load},{"save_commit",l_save_commit},
    {"time",l_time},{"dbg",l_dbg},{"stat",l_stat},
    {NULL,NULL}
};

static const luaL_Reg MAP[] = {
    {"draw",l_map_draw},{"get",l_map_get},{NULL,NULL}
};

static const luaL_Reg SYS[] = {
    {"has",l_sys_has},{NULL,NULL}
};

/* Sandbox by construction: the io, os, package and debug libraries are
 * never opened, rather than opened and then hidden. */
static const luaL_Reg LIBS[] = {
    {LUA_GNAME, luaopen_base},
    {LUA_COLIBNAME, luaopen_coroutine},
    {LUA_TABLIBNAME, luaopen_table},
    {LUA_STRLIBNAME, luaopen_string},
    {LUA_MATHLIBNAME, luaopen_math},
    {LUA_UTF8LIBNAME, luaopen_utf8},
    {NULL, NULL}
};

void pulli_api_open(lua_State *L, pulli_engine *e) {
    E = e;
    for (const luaL_Reg *lib = LIBS; lib->func; lib++) {
        luaL_requiref(L, lib->name, lib->func, 1);
        lua_pop(L, 1);
    }
    /* The base library can still reach the host's files. Lua's load() goes
     * too: it is replaced by the save-data load() below, which also closes
     * the door on hand-crafted bytecode. */
    static const char *strip[] = { "dofile", "loadfile", NULL };
    for (int i = 0; strip[i]; i++) {
        lua_pushnil(L);
        lua_setglobal(L, strip[i]);
    }

    /* Same random sequence on every run and every machine (SPEC §4). A game
     * that wants variety reseeds from player input timing. */
    lua_getglobal(L, "math");
    lua_getfield(L, -1, "randomseed");
    lua_pushinteger(L, 0x50554C49);
    lua_call(L, 1, 0);
    lua_pop(L, 1);

    lua_pushglobaltable(L);
    luaL_setfuncs(L, CORE, 0);
    lua_pop(L, 1);

    luaL_newlib(L, MAP);
    lua_setglobal(L, "map");
    luaL_newlib(L, SYS);
    lua_setglobal(L, "sys");

    /* Deliberately NOT exposing button names as bare globals: "x", "y", "a"
     * and "b" are the most common variable names in game code. Buttons are
     * addressed by string, e.g. btn("left"). */
}
