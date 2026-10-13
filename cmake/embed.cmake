# Turns a file into a C byte array, so a game package can be linked into the
# firmware and read in place from flash:
#   cmake -DIN=<file> -DOUT=<file.c> -DNAME=<symbol> -P embed.cmake
file(READ "${IN}" hex HEX)
string(REGEX REPLACE "([0-9a-f][0-9a-f])" "0x\\1," bytes "${hex}")
file(WRITE "${OUT}"
"/* Generated from ${IN}. Do not edit. */
__attribute__((aligned(4))) const unsigned char ${NAME}[] = {${bytes}};
const unsigned int ${NAME}_len = sizeof(${NAME});
")
