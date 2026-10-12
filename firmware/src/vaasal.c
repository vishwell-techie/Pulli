/* Vaasal: the Pulli runtime. Loads a cart and drives its init/update/draw callbacks. */

#include <stdio.h>

#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"

#include "platform.h"
#include "vaasal.h"

static const luaL_Reg cart_libs[] = {
    {LUA_GNAME, luaopen_base},
    {LUA_COLIBNAME, luaopen_coroutine},
    {LUA_TABLIBNAME, luaopen_table},
    {LUA_STRLIBNAME, luaopen_string},
    {LUA_MATHLIBNAME, luaopen_math},
    {LUA_UTF8LIBNAME, luaopen_utf8},
    {NULL, NULL},
};

/* pulli.time(): seconds since power-on */
static int l_time(lua_State *L)
{
    lua_pushnumber(L, (lua_Number)plat_millis() / 1000);
    return 1;
}

/* pulli.btn(name): no input hardware yet, so nothing is ever pressed */
static int l_btn(lua_State *L)
{
    luaL_checkstring(L, 1);
    lua_pushboolean(L, 0);
    return 1;
}

static const luaL_Reg pulli_api[] = {
    {"time", l_time},
    {"btn", l_btn},
    {NULL, NULL},
};

static int traceback(lua_State *L)
{
    luaL_traceback(L, L, lua_tostring(L, 1), 1);
    return 1;
}

/* Calls global `name` with nargs arguments already on the stack; a missing callback is not an error. */
static bool call_cart(lua_State *L, const char *name, int nargs)
{
    int base = lua_gettop(L) - nargs;

    if (lua_getglobal(L, name) != LUA_TFUNCTION) {
        lua_settop(L, base);
        return true;
    }
    lua_insert(L, base + 1);
    lua_pushcfunction(L, traceback);
    lua_insert(L, base + 1);
    if (lua_pcall(L, nargs, 0, base + 1) != LUA_OK) {
        printf("[vaasal] error in %s: %s\n", name, lua_tostring(L, -1));
        lua_settop(L, base);
        return false;
    }
    lua_settop(L, base);
    return true;
}

bool vaasal_run(const char *name, const char *src, size_t len, long max_frames)
{
    const uint32_t frame_ms = 1000 / VAASAL_FPS;
    bool ok = false;
    char chunk[64];

    lua_State *L = luaL_newstate();
    if (!L) {
        printf("[vaasal] out of memory\n");
        return false;
    }
    for (const luaL_Reg *lib = cart_libs; lib->func; lib++) {
        luaL_requiref(L, lib->name, lib->func, 1);
        lua_pop(L, 1);
    }
    /* loading code from files comes back once there is a filesystem to load from */
    lua_pushnil(L);
    lua_setglobal(L, "dofile");
    lua_pushnil(L);
    lua_setglobal(L, "loadfile");

    luaL_newlib(L, pulli_api);
    lua_pushstring(L, VAASAL_VERSION);
    lua_setfield(L, -2, "version");
    lua_setglobal(L, "pulli");

    printf("[vaasal] %s, %s, cart '%s'\n", VAASAL_VERSION, LUA_RELEASE, name);

    /* "@" makes Lua report errors as name:line */
    snprintf(chunk, sizeof(chunk), "@%s", name);
    lua_pushcfunction(L, traceback);
    if (luaL_loadbuffer(L, src, len, chunk) != LUA_OK || lua_pcall(L, 0, 0, 1) != LUA_OK) {
        printf("[vaasal] error loading cart: %s\n", lua_tostring(L, -1));
        goto out;
    }
    lua_settop(L, 0);

    if (!call_cart(L, "init", 0))
        goto out;

    uint32_t next = plat_millis();
    for (long frame = 0; max_frames < 0 || frame < max_frames; frame++) {
        lua_pushnumber(L, (lua_Number)1 / VAASAL_FPS);
        if (!call_cart(L, "update", 1) || !call_cart(L, "draw", 0))
            goto out;

        next += frame_ms;
        uint32_t now = plat_millis();
        if ((int32_t)(next - now) > 0)
            plat_sleep_ms(next - now);
        else
            next = now; /* the cart overran its frame: drop the lost time */
    }
    ok = true;
out:
    lua_close(L);
    return ok;
}
