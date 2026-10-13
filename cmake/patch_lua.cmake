# Applies Pulli's configuration to a freshly unpacked Lua source tree.
# Run by cmake/lua.cmake from the root of that tree. Safe to run twice.

set(conf "${CMAKE_CURRENT_SOURCE_DIR}/src/luaconf.h")
if(NOT EXISTS "${conf}")
    set(conf "src/luaconf.h")
endif()
file(READ "${conf}" text)

if(NOT text MATCHES "Pulli configuration")
    # 32-bit integers and floats. The RP2350 has a single-precision FPU, and
    # the desktop must compute exactly what the device computes.
    string(REGEX REPLACE "#define LUA_32BITS[ \t]+0" "#define LUA_32BITS\t1" patched "${text}")
    if(patched STREQUAL text)
        message(FATAL_ERROR "patch_lua: LUA_32BITS not found in ${conf}; has the Lua version changed?")
    endif()

    # A fixed hash seed, so pairs() walks string keys in the same order on
    # every run and every machine. Stock Lua seeds from the clock and from
    # memory addresses.
    set(marker "** Local configuration. You can use this space to add your redefinitions")
    string(FIND "${patched}" "${marker}" at)
    if(at EQUAL -1)
        message(FATAL_ERROR "patch_lua: local configuration section not found in ${conf}")
    endif()
    string(REPLACE "${marker}"
        "** Pulli configuration (see cmake/patch_lua.cmake in the Pulli tree).\n*/\n#define luai_makeseed(L)\t0x50554C49u\n\n/*\n${marker}"
        patched "${patched}")
    file(WRITE "${conf}" "${patched}")
    set(text "${patched}")
endif()

if(NOT text MATCHES "lua_math.h")
    # sin, cos, exp, log, ^ and the rest come from runtime/pmath.c, not from
    # the C library, whose answers differ between machines in the last bit.
    set(seed "#define luai_makeseed(L)\t0x50554C49u\n")
    string(FIND "${text}" "${seed}" at)
    if(at EQUAL -1)
        message(FATAL_ERROR "patch_lua: Pulli configuration not found in ${conf}")
    endif()
    string(REPLACE "${seed}" "${seed}#include \"lua_math.h\"\n" text "${text}")
    file(WRITE "${conf}" "${text}")
endif()
