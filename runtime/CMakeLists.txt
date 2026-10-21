# The portable engine. Built unchanged by the desktop host (top-level
# CMakeLists.txt) and by the firmware (firmware/CMakeLists.txt).
add_library(pulli_runtime STATIC
    api.c
    audio.c
    engine.c
    font.c
    font_ta.c
    font_ta_small.c
    parts.c
    cart.c
    gfx.c
    luadebug.c
    map.c
    pkg.c
    save.c
    sha256.c
)
# The maths functions are a library of their own because Lua itself calls
# them (see lua_math.h), and the engine is built on top of Lua.
add_library(pulli_math STATIC pmath.c)
target_include_directories(pulli_math PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_include_directories(pulli_runtime PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(pulli_runtime PUBLIC pulli_lua)
foreach(lib pulli_math pulli_runtime)
    set_target_properties(${lib} PROPERTIES
        C_STANDARD 99
        C_STANDARD_REQUIRED ON
        C_EXTENSIONS OFF
    )
    if(NOT MSVC)
        target_compile_options(${lib} PRIVATE -Wall -Wextra -Wpedantic -Wshadow)
    endif()
endforeach()
