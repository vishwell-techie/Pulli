cmake_minimum_required(VERSION 3.16)
project(pulli C)

# Desktop build: the runtime, the host frontends and the test suite.
# The RP2350 firmware is a separate project in firmware/.

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release)
endif()

include(cmake/lua.cmake)
add_subdirectory(runtime)
add_subdirectory(host)

enable_testing()
find_package(Python3 COMPONENTS Interpreter)
if(Python3_FOUND)
    add_test(NAME font
        COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tools/mkfont.py --check)
    foreach(suite package conformance runtime maths audio assets sdk examples link)
        add_test(NAME ${suite}
            COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/test_${suite}.py
                    --headless $<TARGET_FILE:pulli-headless>)
    endforeach()
else()
    message(STATUS "Python 3 not found: tests are disabled")
endif()
