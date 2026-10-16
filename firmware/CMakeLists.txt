cmake_minimum_required(VERSION 3.16)

# Pulli firmware for RP2350 boards. Default board: Raspberry Pi Pico 2.
# Needs arm-none-eabi-gcc and Python 3. The Pico SDK is downloaded if
# PICO_SDK_PATH does not point at one.
#
# Bring-up stage: one chip and no display. It runs the real runtime from
# ../runtime on a game linked into the image and reports timings over USB
# serial. The desktop host is built by the top-level CMakeLists.txt instead.

if(NOT PICO_BOARD)
    set(PICO_BOARD pico2 CACHE STRING "Board to build for")
endif()
# The board has no buttons yet. The default game, Pong, waits on a title
# screen, so for it alone the firmware taps A every two seconds; any other
# game gets no input unless this is set.
if(DEFINED PULLI_GAME)
    set(auto_a_default 0)
else()
    set(auto_a_default 2)
endif()
set(PULLI_AUTO_A_SECONDS ${auto_a_default} CACHE STRING
    "Tap the A button every this many seconds; 0 for never")
set(PULLI_GAME "${CMAKE_CURRENT_LIST_DIR}/../examples/pong" CACHE PATH
    "Game directory linked into the firmware")

# The Pico SDK, pinned like Lua is (cmake/lua.cmake): one exact release, so
# everyone builds the same firmware. A copy of your own is used when
# PICO_SDK_PATH names one; otherwise this release is downloaded into the
# build folder, with the one bundled library the firmware needs (USB).
set(PULLI_PICO_SDK_VERSION 2.3.1)
set(PULLI_PICO_SDK_COMMIT 079c6f39023649b154152db30f1d781e884879bc)
if(NOT PICO_SDK_PATH AND NOT DEFINED ENV{PICO_SDK_PATH})
    include(FetchContent)
    set(sdk_dir ${CMAKE_BINARY_DIR}/_deps/pico_sdk-src)
    message(STATUS "PICO_SDK_PATH is not set: downloading Pico SDK ${PULLI_PICO_SDK_VERSION}")
    FetchContent_Populate(pico_sdk QUIET
        GIT_REPOSITORY https://github.com/raspberrypi/pico-sdk.git
        GIT_TAG ${PULLI_PICO_SDK_VERSION}
        GIT_SHALLOW TRUE
        GIT_SUBMODULES lib/tinyusb
        GIT_SUBMODULES_RECURSE FALSE
        SOURCE_DIR ${sdk_dir}
        BINARY_DIR ${CMAKE_BINARY_DIR}/_deps/pico_sdk-build
        SUBBUILD_DIR ${CMAKE_BINARY_DIR}/_deps/pico_sdk-subbuild
    )
    # A tag can be moved; the commit it named when this was written cannot.
    find_package(Git REQUIRED)
    execute_process(COMMAND ${GIT_EXECUTABLE} -C ${sdk_dir} rev-parse HEAD
                    OUTPUT_VARIABLE sdk_commit OUTPUT_STRIP_TRAILING_WHITESPACE)
    if(NOT sdk_commit STREQUAL PULLI_PICO_SDK_COMMIT)
        message(FATAL_ERROR "Pico SDK ${PULLI_PICO_SDK_VERSION} downloaded as commit ${sdk_commit}, "
                            "expected ${PULLI_PICO_SDK_COMMIT}. Delete ${CMAKE_BINARY_DIR}/_deps and try again.")
    endif()
    set(PICO_SDK_PATH ${sdk_dir})
endif()

include(pico_sdk_import.cmake)
project(pulli_firmware C CXX ASM)
pico_sdk_init()

if(PICO_SDK_VERSION_STRING VERSION_LESS 2.3.0)
    message(FATAL_ERROR "Pulli needs Pico SDK 2.3.0 or newer (it is built with ${PULLI_PICO_SDK_VERSION}); "
                        "${PICO_SDK_PATH} is ${PICO_SDK_VERSION_STRING}. Update it, or unset PICO_SDK_PATH "
                        "to have the right one downloaded.")
endif()
if(NOT PICO_SDK_VERSION_STRING VERSION_EQUAL PULLI_PICO_SDK_VERSION)
    message(WARNING "Building with Pico SDK ${PICO_SDK_VERSION_STRING}; Pulli is built and checked with "
                    "${PULLI_PICO_SDK_VERSION}.")
endif()

if(NOT PICO_RP2350)
    message(FATAL_ERROR "Pulli targets the RP2350 (SPEC §0.1). ${PICO_BOARD} is not an RP2350 board; "
                        "an RP2040 has too little RAM for the framebuffer and the Lua heap.")
endif()

include(../cmake/lua.cmake)
add_subdirectory(../runtime runtime)
# The functions that draw most of a frame run from RAM: code in flash is
# read through a small cache shared with the game's sprites, and drawing
# from there was measured at half the speed.
target_compile_definitions(pulli_runtime PRIVATE "PULLI_HOT=__attribute__((section(\".time_critical.pulli\")))")

# --- the built-in game: packed, then linked in as a byte array -----------
find_package(Python3 REQUIRED COMPONENTS Interpreter)
get_filename_component(PULLI_GAME "${PULLI_GAME}" ABSOLUTE)
file(GLOB_RECURSE game_files CONFIGURE_DEPENDS "${PULLI_GAME}/*" "${CMAKE_CURRENT_LIST_DIR}/../sdk/*.lua")
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
    # The second core only draws halves of the screen; its stack is the
    # 4 KB SCRATCH_X region.
    PICO_CORE1_STACK_SIZE=0x1000
    PULLI_AUTO_A_SECONDS=${PULLI_AUTO_A_SECONDS}
)
# The SDK keeps the stack in a 4 KB region at the very top of RAM, which a
# 16 KB stack does not fit. Move the boundaries down so that region is 16 KB:
#   0x20000000  RAM         500 KB   (was 512 KB)
#   0x2007D000  SCRATCH_X     4 KB   the second core's stack
#   0x2007E000  SCRATCH_Y    16 KB   the stack; ends at 0x20082000 as before
pico_set_linker_script_var(pulli RAM_LENGTH 500k)
pico_set_linker_script_var(pulli SCRATCH_X_ORIGIN 0x2007D000)
pico_set_linker_script_var(pulli SCRATCH_Y_ORIGIN 0x2007E000)
pico_set_linker_script_var(pulli SCRATCH_Y_LENGTH 16k)
target_link_libraries(pulli PRIVATE pulli_runtime pico_stdlib pico_multicore)
pico_enable_stdio_usb(pulli 1)
pico_enable_stdio_uart(pulli 0)
pico_add_extra_outputs(pulli)
