/* lua_math.h — included by Lua's luaconf.h (see cmake/patch_lua.cmake).
 *
 * Sends every maths call Lua makes whose result depends on the C library
 * to pmath.c instead. This covers the math library and the ^ operator.
 */
#ifndef PULLI_LUA_MATH_H
#define PULLI_LUA_MATH_H

/* The C library's own declarations must be read before its names are
 * redirected, or they would be rewritten too. */
#include <math.h>
#include "pmath.h"

#define sinf   pulli_sinf
#define cosf   pulli_cosf
#define tanf   pulli_tanf
#define asinf  pulli_asinf
#define acosf  pulli_acosf
#define atan2f pulli_atan2f
#define expf   pulli_expf
#define logf   pulli_logf
#define log2f  pulli_log2f
#define log10f pulli_log10f
#define powf   pulli_powf

#endif /* PULLI_LUA_MATH_H */
