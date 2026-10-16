/* pmath.h — Pulli's own maths functions (SPEC §4).
 *
 * The C standard does not say what sinf(1) returns in its last bit, and the
 * desktop's library and the device's disagree. These do the whole
 * calculation in 64-bit integers, so the answer is the same bits on every
 * machine and with every compiler. Each is within one unit in the last
 * place of the true result.
 *
 * Lua reaches them through lua_math.h. sqrt, fmod, floor and ceil are not
 * here: IEEE 754 fixes their results exactly, so every C library agrees.
 */
#ifndef PULLI_PMATH_H
#define PULLI_PMATH_H

#include <stdint.h>

float pulli_sinf  (float x);
float pulli_cosf  (float x);
float pulli_tanf  (float x);
float pulli_asinf (float x);
float pulli_acosf (float x);
float pulli_atan2f(float y, float x);
float pulli_expf  (float x);
float pulli_logf  (float x);
float pulli_log2f (float x);
float pulli_log10f(float x);
float pulli_powf  (float x, float y);
float pulli_fmodf (float x, float y);   /* exact; Lua's % and math.fmod use it */

/* 16.16 fixed point: a 32-bit integer counting 65536ths (SPEC §3). All of
 * it wraps around at 32 bits. div needs b != 0 and sqrt needs a >= 0. */
#define PULLI_FIX_ONE 65536
#define PULLI_FIX_PI  205887
int32_t pulli_fix_from (float x);
float   pulli_fix_to   (int32_t a);
int32_t pulli_fix_mul  (int32_t a, int32_t b);
int32_t pulli_fix_div  (int32_t a, int32_t b);
int32_t pulli_fix_sqrt (int32_t a);
int32_t pulli_fix_sin  (int32_t a);
int32_t pulli_fix_cos  (int32_t a);
int32_t pulli_fix_atan2(int32_t y, int32_t x);

/* Runs every function above, the library ones Lua also uses and plain
 * float arithmetic over a fixed set of inputs, and returns a checksum of
 * the results. A port is correct when this returns PULLI_MATH_CHECK,
 * whether its floats are done by a float unit or by software. */
#define PULLI_MATH_CHECK 0x3CCD6CA1u
uint32_t pulli_math_check(void);

#endif /* PULLI_PMATH_H */
