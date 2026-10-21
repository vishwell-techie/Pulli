/* luadebug.c — a loaded chunk's debug information: its line numbers and
 * the names of its locals and upvalues. Error messages use it to say where
 * they happened; it costs about a quarter of the memory a chunk's code
 * takes (SPEC §10).
 *
 * pulli_lua_strip drops it from the function on top of the stack and every
 * function inside it, in place, as luac -s would, but keeps the file's name.
 * pulli_lua_debug_blocks instead reports the blocks it lies in, so the
 * engine can leave them out of the heap it counts: a game kept with its
 * debug information is counted as if it were not.
 *
 * This reaches into Lua's own structures (the pinned 5.4.8 in cmake/), the
 * one place outside Lua that does. */
#include "lua.h"
#include "lobject.h"
#include "lstate.h"
#include "lmem.h"
#include "luadebug.h"

static void strip(lua_State *L, Proto *f) {
    luaM_freearray(L, f->lineinfo, (size_t)f->sizelineinfo);
    f->lineinfo = NULL;
    f->sizelineinfo = 0;
    luaM_freearray(L, f->abslineinfo, (size_t)f->sizeabslineinfo);
    f->abslineinfo = NULL;
    f->sizeabslineinfo = 0;
    luaM_freearray(L, f->locvars, (size_t)f->sizelocvars);
    f->locvars = NULL;
    f->sizelocvars = 0;
    for (int i = 0; i < f->sizeupvalues; i++) f->upvalues[i].name = NULL;
    /* the source's name stays: one string for the whole file, and errors
     * still say which file */
    for (int i = 0; i < f->sizep; i++) strip(L, f->p[i]);
}

static void report(Proto *f, pulli_debug_block fn, void *ud) {
    if (f->lineinfo) fn(ud, f->lineinfo, sizeof(ls_byte) * (size_t)f->sizelineinfo);
    if (f->abslineinfo) fn(ud, f->abslineinfo, sizeof(AbsLineInfo) * (size_t)f->sizeabslineinfo);
    if (f->locvars) fn(ud, f->locvars, sizeof(LocVar) * (size_t)f->sizelocvars);
    for (int i = 0; i < f->sizep; i++) report(f->p[i], fn, ud);
}

static Proto *top_proto(lua_State *L) {
    const TValue *o = s2v(L->top.p - 1);
    return ttisLclosure(o) ? clLvalue(o)->p : NULL;
}

void pulli_lua_strip(lua_State *L) {
    Proto *f = top_proto(L);
    if (f) strip(L, f);
}

void pulli_lua_debug_blocks(lua_State *L, pulli_debug_block fn, void *ud) {
    Proto *f = top_proto(L);
    if (f) report(f, fn, ud);
}
