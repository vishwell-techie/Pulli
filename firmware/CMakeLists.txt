cmake_minimum_required(VERSION 3.16)

# Pulli firmware for RP2350 boards. Default board: Raspberry Pi Pico 2.
# Needs the Pico SDK 2.x (PICO_SDK_PATH), arm-none-eabi-gcc and Python 3.
#
# Bring-up stage: one chip and no display. It runs the real runtime from
# ../runtime on a game linked into the image and reports timings over USB
# serial. The desktop host is built by the top-level CMakeLists.txt instead.

if(NOT PICO_BOARD)
    set(PICO_BOARD pico2 CACHE STRING "Board to build for")
endif()
set(PULLI_GAME "${CMAKE_CURRENT_LIST_DIR}/../examples/pong" CACHE PATH
    "Game directory linked into the firmware")

include(pico_sdk_import.cmake)
project(pulli_firmware C CXX ASM)
pico_sdk_init()

if(NOT PICO_RP2350)
    message(FATAL_ERROR "Pulli targets the RP2350 (SPEC §0.1). ${PICO_BOARD} is not an RP2350 board; "
                        "an RP2040 has too little RAM for the framebuffer and the Lua heap.")
endif()

include(../cmake/lua.cmake)
add_subdirectory(../runtime runtime)

# --- the built-in game: packed, then linked in as a byte array -----------
find_package(Python3 REQUIRED COMPONENTS Interpreter)
get_filename_component(PULLI_GAME "${PULLI_GAME}" ABSOLUTE)
file(GLOB game_files CONFIGURE_DEPENDS "${PULLI_GAME}/*")
set(game_pkg ${CMAKE_CURRENT_BINARY_DIR}/builtin.pulli)
set(game_c ${CMAKE_CURRENT_BINARY_DIR}/builtin_game.c)
add_custom_command(
    OUTPUT ${game_c}
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_LIST_DIR}/../tools/pulli.py pack ${PULLI_GAME} ${game_pkg}
    COMMAND ${CMAKE_COMMAND} -DIN=${game_pkg} -DOUT=${game_c} -DNAME=pulli_builtin_game
            -P ${CMAKE_CURRENT_LIST_DIR}/../cmake/embed.cmake
    DEPENDS ${game_files} ${CMAKE_CURRENT_LIST_DIR}/../tools/pulli.py
            ${CMAKE_CURRENT_LIST_DIR}/../cmake/embed.cmake
    VERBATIM
)

add_executable(pulli main.c ${game_c})
target_compile_options(pulli PRIVATE -Wall -Wextra)
target_compile_definitions(pulli PRIVATE
    # Lua recurses on the C stack while it compiles and runs a game. The
    # SDK's 2 KB default is far too small. 16 KB is an estimate that has not
    # yet been measured on a board; the guard turns an overflow into a fault
    # instead of silent corruption.
    PICO_STACK_SIZE=0x4000
    PICO_USE_STACK_GUARDS=1
)
target_link_libraries(pulli PRIVATE pulli_runtime pico_stdlib)
pico_enable_stdio_usb(pulli 1)
pico_enable_stdio_uart(pulli 0)
pico_add_extra_outputs(pulli)
