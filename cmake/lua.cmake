# Lua, pinned and built from source as the `pulli_lua` library.
#
# The host and the firmware both include this file, so they run the same
# interpreter with the same number model. The system's Lua is never used: a
# game has to behave identically wherever it runs (SPEC §0.2).

include(FetchContent)
if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()

FetchContent_Declare(lua
    URL https://www.lua.org/ftp/lua-5.4.8.tar.gz
    URL_HASH SHA256=4f18ddae154e793e46eeab727c59ef1c0c0c2b744e7b94219710d76f530629ae
    # PATCH_LEVEL only makes CMake run the patch again on a tree it has
    # already patched; raise it whenever patch_lua.cmake gains a step.
    PATCH_COMMAND ${CMAKE_COMMAND} -DPATCH_LEVEL=2 -P ${CMAKE_CURRENT_LIST_DIR}/patch_lua.cmake
)
FetchContent_MakeAvailable(lua)

set(LUA_SRC ${lua_SOURCE_DIR}/src)
# No io, os, package or debug library, and no linit.c: runtime/api.c opens
# exactly the libraries a game may use.
add_library(pulli_lua STATIC
    ${LUA_SRC}/lapi.c ${LUA_SRC}/lauxlib.c ${LUA_SRC}/lbaselib.c ${LUA_SRC}/lcode.c
    ${LUA_SRC}/lcorolib.c ${LUA_SRC}/lctype.c ${LUA_SRC}/ldebug.c ${LUA_SRC}/ldo.c
    ${LUA_SRC}/ldump.c ${LUA_SRC}/lfunc.c ${LUA_SRC}/lgc.c ${LUA_SRC}/llex.c
    ${LUA_SRC}/lmathlib.c ${LUA_SRC}/lmem.c ${LUA_SRC}/lobject.c ${LUA_SRC}/lopcodes.c
    ${LUA_SRC}/lparser.c ${LUA_SRC}/lstate.c ${LUA_SRC}/lstring.c ${LUA_SRC}/lstrlib.c
    ${LUA_SRC}/ltable.c ${LUA_SRC}/ltablib.c ${LUA_SRC}/ltm.c ${LUA_SRC}/lundump.c
    ${LUA_SRC}/lutf8lib.c ${LUA_SRC}/lvm.c ${LUA_SRC}/lzio.c
)
target_include_directories(pulli_lua PUBLIC ${LUA_SRC})
# luaconf.h includes runtime/lua_math.h, which sends Lua's maths to pulli_math.
target_link_libraries(pulli_lua PUBLIC pulli_math)
if(NOT MSVC)
    # a*b+c must round twice on every CPU, never fuse into one operation
    target_compile_options(pulli_lua PUBLIC -ffp-contract=off)
endif()
