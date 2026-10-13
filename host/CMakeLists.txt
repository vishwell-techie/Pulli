# Desktop frontends. pulli-headless needs nothing but a C compiler;
# pulli-host needs SDL2 and is skipped when SDL2 is not installed.
add_library(pulli_host_common STATIC common.c)
target_link_libraries(pulli_host_common PUBLIC pulli_runtime)
if(NOT WIN32)
    target_link_libraries(pulli_host_common PUBLIC m)
endif()

add_executable(pulli-headless headless_main.c)
target_link_libraries(pulli-headless PRIVATE pulli_host_common)

find_package(SDL2 CONFIG QUIET)
if(TARGET SDL2::SDL2)
    add_executable(pulli-host sdl_main.c)
    target_link_libraries(pulli-host PRIVATE pulli_host_common SDL2::SDL2)
else()
    message(STATUS "SDL2 not found: building pulli-headless only. "
                   "Install it for the windowed host (Debian/Ubuntu: libsdl2-dev, macOS: brew install sdl2).")
endif()

if(NOT MSVC)
    target_compile_options(pulli_host_common PRIVATE -Wall -Wextra)
    target_compile_options(pulli-headless PRIVATE -Wall -Wextra)
    if(TARGET pulli-host)
        target_compile_options(pulli-host PRIVATE -Wall -Wextra)
    endif()
endif()
