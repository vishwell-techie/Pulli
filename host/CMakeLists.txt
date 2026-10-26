# Desktop frontends. pulli-headless needs nothing but a C compiler;
# pulli-host needs SDL2 2.24.0 or newer (the controller test attaches a
# virtual controller with SDL_JoystickAttachVirtualEx, new in 2.24.0) and is
# skipped when it is not installed.
add_library(pulli_host_common STATIC common.c link.c)
target_link_libraries(pulli_host_common PUBLIC pulli_runtime)
if(NOT WIN32)
    target_link_libraries(pulli_host_common PUBLIC m)
endif()

add_executable(pulli-headless headless_main.c)
target_link_libraries(pulli-headless PRIVATE pulli_host_common)

find_package(SDL2 2.24.0 CONFIG QUIET)
if(TARGET SDL2::SDL2)
    add_executable(pulli-host sdl_main.c pad.c)
    target_link_libraries(pulli-host PRIVATE pulli_host_common SDL2::SDL2)
    # the controller mapping, checked with a virtual controller
    add_executable(pad-test pad_test.c pad.c)
    target_link_libraries(pad-test PRIVATE pulli_runtime SDL2::SDL2)
    add_test(NAME pad COMMAND pad-test)
else()
    message(STATUS "SDL2 2.24.0 or newer not found: building pulli-headless only. "
                   "Install it for the windowed host and controllers (see README.md, Build and test).")
endif()

if(NOT MSVC)
    target_compile_options(pulli_host_common PRIVATE -Wall -Wextra)
    target_compile_options(pulli-headless PRIVATE -Wall -Wextra)
    if(TARGET pulli-host)
        target_compile_options(pulli-host PRIVATE -Wall -Wextra)
        target_compile_options(pad-test PRIVATE -Wall -Wextra)
    endif()
endif()
