# The portable engine. Built unchanged by the desktop host (top-level
# CMakeLists.txt) and by the firmware (firmware/CMakeLists.txt).
add_library(pulli_runtime STATIC
    api.c
    engine.c
    font.c
    gfx.c
    pkg.c
    save.c
)
target_include_directories(pulli_runtime PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(pulli_runtime PUBLIC pulli_lua)
set_target_properties(pulli_runtime PROPERTIES
    C_STANDARD 99
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF
)
if(NOT MSVC)
    target_compile_options(pulli_runtime PRIVATE -Wall -Wextra -Wpedantic -Wshadow)
endif()
