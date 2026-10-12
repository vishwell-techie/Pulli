# Turns a Lua file into a C byte array: cmake -DIN=<cart.lua> -DOUT=<file.c> -P embed_cart.cmake
file(READ "${IN}" hex HEX)
string(REGEX REPLACE "([0-9a-f][0-9a-f])" "0x\\1," bytes "${hex}")
file(WRITE "${OUT}"
"#include <stddef.h>
const char cart_builtin[] = {${bytes}0};
const size_t cart_builtin_len = sizeof(cart_builtin) - 1;
")
