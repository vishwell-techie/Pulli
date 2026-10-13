/* api.c — the Lua-facing API from SPEC §3.
 * This file is the platform's public contract. Changing a signature here
 * breaks every game ever written for Pulli, so it changes slowly. */
#include "internal.h"
#include "pmath.h"
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
/* True on the frame a button goes down. Held, it then repeats, the way a
 * keyboard does, so a menu can be scrolled by holding a direction. START
 * and SELECT never repeat: they pause, confirm and quit, where a second
 * firing from a held button would undo the first. */
static int l_btnp(lua_State *L) {
    int b = btn_index(L, 1);
    bool hit = false;
    if (b >= 0) {
        uint32_t held = E->ctx.btn_held[b];
        bool repeats = b != PULLI_BTN_START && b != PULLI_BTN_SELECT;
        hit = held == 1 || (repeats && held > PULLI_REPEAT_DELAY &&
                            (held - 1 - PULLI_REPEAT_DELAY) % PULLI_REPEAT_RATE == 0);
    }
    lua_pushboolean(L, hit);
    return 1;
}

/* ---- audio ---------------------------------------------------------- */
static int l_sfx(lua_State *L) {
    pulli_audio_sfx(&E->audio, arg_i(L,1,0), arg_i(L,2,-1));
    return 0;
}
static int l_music(lua_State *L) {
    pulli_audio_music(&E->audio, arg_i(L,1,0), arg_i(L,2,0), arg_b(L,3,true));
    return 0;
}
static int l_music_stop(lua_State *L) {
    pulli_audio_music_stop(&E->audio, arg_i(L,1,0));
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

/* ---- link ---------------------------------------------------------- */
static bool link_up(void) {
    return E->link_state == PULLI_LINK_CONNECTED;
}
static int l_link_status(lua_State *L) {
    static const char *const NAMES[] = { "off", "waiting", "connected" };
    lua_pushstring(L, NAMES[E->link_state]);
    return 1;
}
static int l_link_side(lua_State *L) {
    if (link_up()) lua_pushinteger(L, E->link_side); else lua_pushnil(L);
    return 1;
}
static int l_link_send(lua_State *L) {
    size_t len;
    const char *msg = luaL_checklstring(L, 1, &len);
    const pulli_backend *B = E->backend;
    bool ok = link_up() && len <= PULLI_LINK_MSG_MAX && E->link_sent < PULLI_LINK_SENDS &&
              B->link_send && B->link_send(msg, len);
    if (ok) E->link_sent++;
    lua_pushboolean(L, ok);
    return 1;
}
static int l_link_recv(lua_State *L) {
    char msg[PULLI_LINK_MSG_MAX];
    const pulli_backend *B = E->backend;
    int n = link_up() && B->link_recv ? B->link_recv(msg, sizeof(msg)) : -1;
    if (n < 0) lua_pushnil(L); else lua_pushlstring(L, msg, (size_t)n);
    return 1;
}

/* ---- map ----------------------------------------------------------- */
/* The cell a game names, or NULL if it is outside the loaded map. */
static uint16_t *map_cell(lua_State *L) {
    pulli_map *m = &E->ctx.map;
    int layer = arg_i(L,1,0), cx = arg_i(L,2,0), cy = arg_i(L,3,0);
    if (layer < 0 || layer >= m->layers || cx < 0 || cy < 0 || cx >= m->w || cy >= m->h) return NULL;
    return &m->cells[((size_t)layer * m->h + cy) * m->w + cx];
}
static int l_map_load(lua_State *L) {
    const char *name = luaL_optstring(L, 1, "map.ooru");
    pulli_blob b;
    if (!pulli_pkg_find(&E->pkg, name, &b)) return luaL_error(L, "map.load: the package has no '%s'", name);
    const char *why = pulli_map_check(b);
    if (why) return luaL_error(L, "map.load: %s: %s", name, why);
    pulli_map_load(&E->ctx.map, b);
    return 0;
}
static int l_map_draw(lua_State *L) {
    pulli_map_draw(&E->ctx.g, &E->ctx.map, arg_i(L,1,0), arg_i(L,2,0), arg_i(L,3,0));
    return 0;
}
static int l_map_get(lua_State *L) {
    const uint16_t *c = map_cell(L);
    lua_pushinteger(L, c ? *c & PULLI_TILE_MASK : 0);
    lua_pushboolean(L, c && (*c & PULLI_TILE_FLIP_X));
    lua_pushboolean(L, c && (*c & PULLI_TILE_FLIP_Y));
    return 3;
}
static int l_map_set(lua_State *L) {
    uint16_t *c = map_cell(L);
    int tile = arg_i(L,4,0);
    if (!c || tile < 0 || tile > PULLI_TILE_MASK) return 0;
    *c = (uint16_t)(tile | (arg_b(L,5,false) ? PULLI_TILE_FLIP_X : 0) | (arg_b(L,6,false) ? PULLI_TILE_FLIP_Y : 0));
    return 0;
}
static int l_map_flags(lua_State *L) {
    const pulli_map *m = &E->ctx.map;
    int tile = arg_i(L,1,0);
    lua_pushinteger(L, tile >= 0 && tile < m->flag_count ? m->flags[tile] : 0);
    return 1;
}
static int l_map_size(lua_State *L) {
    lua_pushinteger(L, E->ctx.map.layers ? E->ctx.map.w : 0);
    lua_pushinteger(L, E->ctx.map.layers ? E->ctx.map.h : 0);
    return 2;
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
    {"load",l_map_load},{"draw",l_map_draw},{"get",l_map_get},{"set",l_map_set},
    {"flags",l_map_flags},{"size",l_map_size},{NULL,NULL}
};

static const luaL_Reg SYS[] = {
    {"has",l_sys_has},{NULL,NULL}
};

static const luaL_Reg LINK[] = {
    {"status",l_link_status},{"side",l_link_side},
    {"send",l_link_send},{"recv",l_link_recv},{NULL,NULL}
};

/* ---- 16.16 fixed point ---------------------------------------------- */
/* A fixed-point number is an ordinary Lua integer, so a float passed where
 * one belongs is refused unless it happens to be whole. */
static int32_t arg_fix(lua_State *L, int i) { return (int32_t)luaL_checkinteger(L, i); }

static int l_fix_from(lua_State *L) {
    if (lua_isinteger(L, 1)) lua_pushinteger(L, (lua_Integer)((lua_Unsigned)lua_tointeger(L, 1) << 16));
    else lua_pushinteger(L, pulli_fix_from((float)luaL_checknumber(L, 1)));
    return 1;
}
static int l_fix_to(lua_State *L)    { lua_pushnumber(L, pulli_fix_to(arg_fix(L, 1))); return 1; }
static int l_fix_floor(lua_State *L) {
    int32_t a = arg_fix(L, 1);
    lua_pushinteger(L, a < 0 ? -(lua_Integer)((0xFFFFu - (uint32_t)a) >> 16) : a >> 16);   /* rounds down */
    return 1;
}
static int l_fix_mul(lua_State *L)   { lua_pushinteger(L, pulli_fix_mul(arg_fix(L, 1), arg_fix(L, 2))); return 1; }
static int l_fix_div(lua_State *L) {
    int32_t a = arg_fix(L, 1), b = arg_fix(L, 2);
    if (!b) return luaL_error(L, "fix.div: attempt to divide by zero");
    lua_pushinteger(L, pulli_fix_div(a, b));
    return 1;
}
static int l_fix_sqrt(lua_State *L) {
    int32_t a = arg_fix(L, 1);
    if (a < 0) return luaL_error(L, "fix.sqrt: square root of a negative number");
    lua_pushinteger(L, pulli_fix_sqrt(a));
    return 1;
}
static int l_fix_sin(lua_State *L)   { lua_pushinteger(L, pulli_fix_sin(arg_fix(L, 1))); return 1; }
static int l_fix_cos(lua_State *L)   { lua_pushinteger(L, pulli_fix_cos(arg_fix(L, 1))); return 1; }
static int l_fix_atan(lua_State *L) {
    int32_t x = lua_isnoneornil(L, 2) ? PULLI_FIX_ONE : arg_fix(L, 2);
    lua_pushinteger(L, pulli_fix_atan2(arg_fix(L, 1), x));
    return 1;
}

static const luaL_Reg FIX[] = {
    {"from",l_fix_from},{"to",l_fix_to},{"floor",l_fix_floor},
    {"mul",l_fix_mul},{"div",l_fix_div},{"sqrt",l_fix_sqrt},
    {"sin",l_fix_sin},{"cos",l_fix_cos},{"atan",l_fix_atan},{NULL,NULL}
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
    luaL_newlib(L, LINK);
    lua_setglobal(L, "link");
    luaL_newlib(L, FIX);
    lua_pushinteger(L, PULLI_FIX_ONE);
    lua_setfield(L, -2, "one");
    lua_pushinteger(L, PULLI_FIX_PI);
    lua_setfield(L, -2, "pi");
    lua_setglobal(L, "fix");

    /* Deliberately NOT exposing button names as bare globals: "x", "y", "a"
     * and "b" are the most common variable names in game code. Buttons are
     * addressed by string, e.g. btn("left"). */
}
