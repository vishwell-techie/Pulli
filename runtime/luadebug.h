/* luadebug.h — a loaded chunk's debug information (luadebug.c). */
#ifndef PULLI_LUADEBUG_H
#define PULLI_LUADEBUG_H

#include <stddef.h>

struct lua_State;
typedef void (*pulli_debug_block)(void *ud, const void *block, size_t bytes);

/* Drop the debug information of the Lua function on top of the stack. */
void pulli_lua_strip(struct lua_State *L);
/* Report each block of it, by address and size, to fn. */
void pulli_lua_debug_blocks(struct lua_State *L, pulli_debug_block fn, void *ud);

#endif
