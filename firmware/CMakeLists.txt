cmake_minimum_required(VERSION 3.13)

# pico: RP2040 / RP2350 boards via the Pico SDK (pick the board with -DPICO_BOARD=pico|pico2)
# host: runs the same runtime on Linux, for testing carts without hardware
set(PULLI_PLATFORM "pico" CACHE STRING "Target platform: pico or host")
set(PULLI_CART "${CMAKE_CURRENT_LIST_DIR}/../carts/hello/main.lua" CACHE FILEPATH "Cart built into the firmware")

if(PULLI_PLATFORM STREQUAL "pico")
    include(pico_sdk_import.cmake)
endif()

project(pulli C CXX ASM)
set(CMAKE_C_STANDARD 11)

if(PULLI_PLATFORM STREQUAL "pico")
    pico_sdk_init()
endif()

# --- Lua -------------------------------------------------------------------
include(FetchContent)
if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()
FetchContent_Declare(lua
    URL https://www.lua.org/ftp/lua-5.4.8.tar.gz
    URL_HASH SHA256=4f18ddae154e793e46eeab727c59ef1c0c0c2b744e7b94219710d76f530629ae
    # 32-bit integers and floats: the RP2040 has no FPU and the RP2350 only a
    # single-precision one. The host build uses the same so carts behave alike.
    PATCH_COMMAND sed -i "s/^#define LUA_32BITS[ \t]*0/#define LUA_32BITS 1/" src/luaconf.h
)
FetchContent_MakeAvailable(lua)

set(LUA_SRC ${lua_SOURCE_DIR}/src)
# No io/os/package/debug libraries and no linit.c: vaasal.c opens the libraries carts may use.
add_library(lua STATIC
    ${LUA_SRC}/lapi.c ${LUA_SRC}/lauxlib.c ${LUA_SRC}/lbaselib.c ${LUA_SRC}/lcode.c
    ${LUA_SRC}/lcorolib.c ${LUA_SRC}/lctype.c ${LUA_SRC}/ldebug.c ${LUA_SRC}/ldo.c
    ${LUA_SRC}/ldump.c ${LUA_SRC}/lfunc.c ${LUA_SRC}/lgc.c ${LUA_SRC}/llex.c
    ${LUA_SRC}/lmathlib.c ${LUA_SRC}/lmem.c ${LUA_SRC}/lobject.c ${LUA_SRC}/lopcodes.c
    ${LUA_SRC}/lparser.c ${LUA_SRC}/lstate.c ${LUA_SRC}/lstring.c ${LUA_SRC}/lstrlib.c
    ${LUA_SRC}/ltable.c ${LUA_SRC}/ltablib.c ${LUA_SRC}/ltm.c ${LUA_SRC}/lundump.c
    ${LUA_SRC}/lutf8lib.c ${LUA_SRC}/lvm.c ${LUA_SRC}/lzio.c
)
target_include_directories(lua PUBLIC ${LUA_SRC})

# --- Built-in cart ---------------------------------------------------------
set(CART_C ${CMAKE_CURRENT_BINARY_DIR}/cart_builtin.c)
add_custom_command(
    OUTPUT ${CART_C}
    COMMAND ${CMAKE_COMMAND} -DIN=${PULLI_CART} -DOUT=${CART_C} -P ${CMAKE_CURRENT_LIST_DIR}/cmake/embed_cart.cmake
    DEPENDS ${PULLI_CART} ${CMAKE_CURRENT_LIST_DIR}/cmake/embed_cart.cmake
    VERBATIM
)

# --- Vaasal ----------------------------------------------------------------
add_executable(pulli src/vaasal.c ${CART_C})
target_include_directories(pulli PRIVATE src)
target_compile_options(pulli PRIVATE -Wall -Wextra)

if(PULLI_PLATFORM STREQUAL "pico")
    target_sources(pulli PRIVATE port/pico.c)
    target_link_libraries(lua PUBLIC pico_stdlib)
    target_link_libraries(pulli PRIVATE lua pico_stdlib)
    pico_enable_stdio_usb(pulli 1)
    pico_enable_stdio_uart(pulli 0)
    pico_add_extra_outputs(pulli)
elseif(PULLI_PLATFORM STREQUAL "host")
    target_sources(pulli PRIVATE port/host.c)
    target_link_libraries(pulli PRIVATE lua m)
else()
    message(FATAL_ERROR "PULLI_PLATFORM must be pico or host, got '${PULLI_PLATFORM}'")
endif()
