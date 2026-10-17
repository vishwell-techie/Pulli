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
    /* Most arguments are whole numbers already: take them as they are,
     * without the float floor below, which on a chip with no double unit is
     * a library call for every argument of every drawing call. */
    int whole;
    lua_Integer v = lua_tointegerx(L, i, &whole);
    if (whole) return v < -32768 ? -32768 : v > 32767 ? 32767 : (int)v;
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

/* shade(c, lights, edge): lights is a list of x, y, r, x, y, r...; each
 * number is taken like any coordinate. Past PULLI_SHADE_LIGHTS lights the
 * rest are left out; anything but a table is no lights at all. */
static int l_shade(lua_State *L) {
    int lights[PULLI_SHADE_LIGHTS * 3], n = 0;
    if (lua_istable(L, 2)) {
        lua_Unsigned len = lua_rawlen(L, 2) / 3;
        n = len > PULLI_SHADE_LIGHTS ? PULLI_SHADE_LIGHTS : (int)len;
        for (int i = 0; i < n * 3; i++) {
            lua_rawgeti(L, 2, i + 1);
            lights[i] = arg_i(L, -1, 0);
            lua_pop(L, 1);
        }
    }
    pulli_shade(&E->ctx.g, arg_i(L,1,0), lights, n, arg_i(L,3,0));
    return 0;
}

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
/* print(text, x, y, c) draws UTF-8 text with its top at y and returns where
 * the next letter would go; text_size(text) is the width of its widest line
 * and the height of all its lines. */
static int l_print(lua_State *L) {
    lua_settop(L, 4);
    size_t len;
    const char *s = luaL_tolstring(L, 1, &len);
    lua_pushinteger(L, pulli_print(&E->ctx.g, s, len, arg_i(L,2,0), arg_i(L,3,0), arg_i(L,4,7)));
    return 1;
}
static int l_text_size(lua_State *L) {
    size_t len;
    int w, h;
    const char *s = luaL_tolstring(L, 1, &len);
    pulli_text_size(s, len, &w, &h);
    lua_pushinteger(L, w);
    lua_pushinteger(L, h);
    return 2;
}
static int l_camera(lua_State *L) { pulli_camera(&E->ctx.g, arg_i(L,1,0), arg_i(L,2,0)); return 0; }
static int l_clip(lua_State *L)   { pulli_clip(&E->ctx.g, arg_i(L,1,0),arg_i(L,2,0),arg_i(L,3,0),arg_i(L,4,0)); return 0; }
static int l_pal(lua_State *L)    { pulli_pal(&E->ctx.g, arg_i(L,1,-1), arg_i(L,2,0)); return 0; }
static int l_palt(lua_State *L)   { pulli_palt(&E->ctx.g, arg_i(L,1,-1), arg_b(L,2,true)); return 0; }
static int l_fade(lua_State *L)   { pulli_fade(&E->ctx.g, (float)luaL_optnumber(L,1,0)); return 0; }

/* palette(c, r, g, b) gives colour c a new look, red, green and blue each 0
 * to 255. palette(c) tells what colour c looks like now, and palette()
 * puts the game's own colours back. */
static int l_palette(lua_State *L) {
    if (lua_isnoneornil(L, 1)) {
        pulli_load_palette(&E->ctx.g, E->base_palette);
        return 0;
    }
    if (lua_gettop(L) == 1) {
        /* Widen the stored 5-6-5 bits back to 0..255, repeating the top bits
         * into the bottom so that full brightness reads back as 255. */
        uint16_t p = E->ctx.g.palette[arg_i(L,1,0) & PULLI_COLOR_MASK];
        int r = (p >> 11) & 0x1F, gr = (p >> 5) & 0x3F, b = p & 0x1F;
        lua_pushinteger(L, (r << 3) | (r >> 2));
        lua_pushinteger(L, (gr << 2) | (gr >> 4));
        lua_pushinteger(L, (b << 3) | (b >> 2));
        return 3;
    }
    pulli_set_colour(&E->ctx.g, arg_i(L,1,0), arg_i(L,2,0), arg_i(L,3,0), arg_i(L,4,0));
    return 0;
}

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
static int l_music_pause(lua_State *L) {
    pulli_audio_music_pause(&E->audio, arg_b(L,1,true));
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
    bool ok = pulli_save_commit(E);
    if (ok) E->save_written = E->ctx.frame;            /* a checkpoint: the timer starts over */
    lua_pushboolean(L, ok);
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
    /* These two need a clock, which a port may not have. They are for
     * finding out why a game is slow, not for the game to act on: they
     * differ from run to run. */
    else if (!strcmp(what, "fps") && E->backend && E->backend->micros)
        lua_pushinteger(L, (lua_Integer)E->fps);
    else if (!strcmp(what, "cpu") && E->backend && E->backend->micros)
        lua_pushinteger(L, (lua_Integer)E->cpu);
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
    {"rect",l_rect},{"rectfill",l_rectfill},{"circ",l_circ},{"circfill",l_circfill},{"shade",l_shade},
    {"spr",l_spr},{"sspr",l_sspr},{"print",l_print},{"text_size",l_text_size},{"camera",l_camera},
    {"clip",l_clip},{"pal",l_pal},{"palt",l_palt},{"fade",l_fade},
    {"btn",l_btn},{"btnp",l_btnp},
    {"sfx",l_sfx},{"music",l_music},{"music_stop",l_music_stop},{"music_pause",l_music_pause},{"palette",l_palette},
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

/* ---- require -------------------------------------------------------- */
/* A game may be split over several Lua files. require("name") runs name.lua
 * from the package the first time it is asked for and gives back whatever
 * the file returned, every time. Modules come from the package and nowhere
 * else, and as source: the same rules as main.lua. */
#define MODULES "pulli.modules"

static int l_require(lua_State *L) {
    size_t n;
    const char *name = luaL_checklstring(L, 1, &n);
    char entry[PULLI_PKG_NAME_MAX + 1];
    pulli_blob src;
    for (size_t i = 0; i < n; i++) {
        char c = name[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'))
            return luaL_error(L, "require: '%s' is not a module name (letters, digits and _ only)", name);
    }
    if (n == 0 || n + 4 > PULLI_PKG_NAME_MAX) return luaL_error(L, "require: bad module name");
    memcpy(entry, name, n);
    memcpy(entry + n, ".lua", 5);

    luaL_getsubtable(L, LUA_REGISTRYINDEX, MODULES);
    if (lua_getfield(L, -1, name) == LUA_TLIGHTUSERDATA)       /* the mark left while a module loads */
        return luaL_error(L, "require: '%s' requires itself, directly or through another module", name);
    if (!lua_isnil(L, -1)) return 1;                           /* loaded before */
    lua_pop(L, 1);

    if (!strcmp(name, "main") || !strcmp(name, "manifest") || !pulli_pkg_find(&E->pkg, entry, &src))
        return luaL_error(L, "require: the package has no module '%s' (%s)", name, entry);
    lua_pushlightuserdata(L, (void *)MODULES);
    lua_setfield(L, -2, name);
    lua_pushfstring(L, "@%s", entry);
    if (luaL_loadbufferx(L, (const char *)src.data, src.len, lua_tostring(L, -1), "t") != LUA_OK) {
        lua_pushnil(L);                                        /* let a later require try again */
        lua_setfield(L, -4, name);
        return lua_error(L);
    }
    lua_pushvalue(L, 1);
    lua_call(L, 1, 1);
    if (lua_isnil(L, -1)) {                                    /* a module that returns nothing gives true */
        lua_pop(L, 1);
        lua_pushboolean(L, 1);
    }
    lua_pushvalue(L, -1);
    lua_setfield(L, -4, name);
    return 1;
}

/* unrequire(name) forgets a module, so the memory it holds can be collected
 * once nothing else uses it; the next require runs the file again. Gives
 * true if the module was loaded. */
static int l_unrequire(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    luaL_getsubtable(L, LUA_REGISTRYINDEX, MODULES);
    int t = lua_getfield(L, -1, name);
    if (t == LUA_TLIGHTUSERDATA)
        return luaL_error(L, "unrequire: '%s' is still loading", name);
    lua_pop(L, 1);
    lua_pushnil(L);
    lua_setfield(L, -2, name);
    lua_pushboolean(L, t != LUA_TNIL);
    return 1;
}

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
    lua_register(L, "require", l_require);
    lua_register(L, "unrequire", l_unrequire);

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
