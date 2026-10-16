/* pmath.c — maths functions that give the same bits on every machine.
 *
 * A float goes in, is taken apart into an integer and a power of two, and
 * everything from there to the final rounding is 64-bit integer (fixed
 * point) arithmetic. No floating-point instruction takes part, so neither
 * the CPU, the compiler nor the C library can change an answer.
 *
 * "Qn" below means a fixed-point number with n bits after the point: the
 * integer v stands for v / 2^n.
 */
#include "pmath.h"

#include <math.h>      /* only for the library functions pulli_math_check() covers */
#include <stdbool.h>
#include <string.h>

typedef uint64_t u64;

#define SIGN  0x80000000u
#define INF   0x7F800000u
#define QNAN  0x7FC00000u
#define ONE   0x3F800000u       /* 1.0f */
#define TINY  0x38800000u       /* 2^-14: below this sin x = x and cos x = 1 to the last bit */

#define ONE55 ((u64)1 << 55)
#define ONE62 ((u64)1 << 62)
#define ONE63 ((u64)1 << 63)

#define PIO2_Q63     0xC90FDAA22168C234ULL   /* pi / 2 */
#define PIO2_Q61     0x3243F6A8885A308DULL
#define PI_Q61       0x6487ED5110B4611AULL
#define LN2_Q64      0xB17217F7D1CF79ABULL   /* ln 2 */
#define LN2_Q55      0x0058B90BFBE8E7BCULL
#define INV_LN2_Q63  0xB8AA3B295C17F0BBULL   /* 1 / ln 2 */
#define INV_LN10_Q64 0x6F2DEC549B9438CAULL   /* 1 / ln 10 */

/* 2 / pi, the first 224 bits after the point. */
static const uint32_t TWO_OVER_PI[7] = {
    0xA2F9836E, 0x4E441529, 0xFC2757D1, 0xF534DDC0, 0xDB629599, 0x3C439041, 0xFE5163AB
};

#define R(n) (0xFFFFFFFFFFFFFFFFULL / (n))   /* 1 / n in Q64 */

/* [n] = 1 / n!: the sine, cosine and exponential series. */
static const u64 INV_FACT[16] = {
    0, 0, R(2), R(6), R(24), R(120), R(720), R(5040), R(40320), R(362880), R(3628800),
    R(39916800), R(479001600), R(6227020800), R(87178291200), R(1307674368000)
};
/* [k] = 1 / (2k + 1): the logarithm and arctangent series. */
static const u64 INV_ODD[10] = {
    0, R(3), R(5), R(7), R(9), R(11), R(13), R(15), R(17), R(19)
};
/* [i] = atan(i / 8) in Q63. */
static const u64 ATAN8[9] = {
    0x0000000000000000ULL, 0x0FEADD4D5617B6E3ULL, 0x1F5B75F92C80DD62ULL,
    0x2DEC3283C9BDE11CULL, 0x3B58CE0AC3769ED1ULL, 0x47802EAF7BFACFCDULL,
    0x525E3E8C9A7B8492ULL, 0x5C029F15E118CF39ULL, 0x6487ED5110B4611AULL
};

/* ---- floats in and out ---------------------------------------------- */

static uint32_t bits(float x)         { uint32_t u; memcpy(&u, &x, sizeof u); return u; }
static float    from_bits(uint32_t u) { float x; memcpy(&x, &u, sizeof x); return x; }
static float    nan_(void)            { return from_bits(QNAN); }

static int clz64(u64 v) {             /* leading zero bits; v must not be 0 */
    int n = 0;
    if (!(v >> 32)) { n += 32; v <<= 32; }
    if (!(v >> 48)) { n += 16; v <<= 16; }
    if (!(v >> 56)) { n += 8;  v <<= 8; }
    if (!(v >> 60)) { n += 4;  v <<= 4; }
    if (!(v >> 62)) { n += 2;  v <<= 2; }
    if (!(v >> 63)) n += 1;
    return n;
}

/* The magnitude bits of a finite, non-zero float as m * 2^e, with m a
 * 24-bit integer whose top bit is set. */
static uint32_t split(uint32_t a, int *e) {
    uint32_t m = a & 0x7FFFFF;
    int field = (int)(a >> 23);
    if (field) m |= 0x800000;
    else { int s = clz64(m) - 40; m <<= s; field = 1 - s; }      /* subnormal */
    *e = field - 150;
    return m;
}

/* The float nearest to m * 2^e, ties to even, with the given sign bit. */
static float pack(uint32_t sign, u64 m, int e) {
    if (!m) return from_bits(sign);
    int s = clz64(m);
    m <<= s;
    int field = e - s + 63 + 127;           /* exponent field if no rounding carries */
    if (field >= 255) return from_bits(sign | INF);
    int drop = 40;                          /* a float keeps 24 of the 64 bits */
    if (field <= 0) { drop += 1 - field; field = 1; }             /* subnormal */
    if (drop > 64) return from_bits(sign);
    u64 keep = drop < 64 ? m >> drop : 0;
    u64 rest = drop < 64 ? m << (64 - drop) : m;
    if (rest > ONE63 || (rest == ONE63 && (keep & 1))) keep++;
    return from_bits(sign | (((uint32_t)(field - 1) << 23) + (uint32_t)keep));
}

/* ---- integer helpers ------------------------------------------------- */

static u64 mulhi(u64 a, u64 b) {      /* the top 64 bits of the 128-bit product */
    u64 al = (uint32_t)a, ah = a >> 32, bl = (uint32_t)b, bh = b >> 32;
    u64 mid = ah * bl + ((al * bl) >> 32);
    u64 mid2 = al * bh + (uint32_t)mid;
    return ah * bh + (mid >> 32) + (mid2 >> 32);
}

/* floor(a * 2^n / b), for a < b. One bit per step: simple, and the slowest
 * thing here. Being exact, it can be replaced by any faster exact division
 * without changing a single result. */
static u64 divq(u64 a, u64 b, int n) {
    u64 q = 0;
    while (n--) {
        bool carry = a >> 63;
        a <<= 1;
        q <<= 1;
        if (carry || a >= b) { a -= b; q |= 1; }
    }
    return q;
}

static uint32_t isqrt(u64 v, u64 *rem) {   /* floor(sqrt(v)), and what is left over */
    u64 r = 0;
    for (u64 bit = ONE62; bit; bit >>= 2) {
        if (v >= r + bit) { v -= r + bit; r = (r >> 1) + bit; }
        else r >>= 1;
    }
    *rem = v;
    return (uint32_t)r;
}

/* num / den as a float; both are positive fixed-point numbers of one format. */
static float ratio(uint32_t sign, u64 num, u64 den) {
    if (!den) return from_bits(sign | INF);
    if (!num) return from_bits(sign);
    int sn = clz64(num), sd = clz64(den);
    return pack(sign, divq((num << sn) >> 1, den << sd, 40), sd - sn - 39);
}

/* ---- sine, cosine, tangent ------------------------------------------- */

/* |x| = m * 2^e, at least 2^-37 and with m below 2^32. Finds the nearest multiple of pi/2: *quad
 * is that multiple mod 4, the result is how far |x| is from it in Q63
 * radians (at most pi/4) and *before says whether |x| is below it.
 * Multiplies by enough bits of 2/pi to be exact for any float. */
static u64 reduce(uint32_t m, int e, unsigned *quad, bool *before) {
    int first = e >= 2 ? e - 2 : 0;         /* bits of 2/pi above this only add whole turns */
    const uint32_t *t = TWO_OVER_PI + first / 32;
    int o = first % 32;
    u64 w0 = t[0], w1 = t[1], w2 = t[2];
    if (o) {
        w0 = (uint32_t)(t[0] << o | t[1] >> (32 - o));
        w1 = (uint32_t)(t[1] << o | t[2] >> (32 - o));
        w2 = (uint32_t)(t[2] << o | t[3] >> (32 - o));
    }
    u64 p0 = m * w0, p1 = m * w1, p2 = m * w2;
    u64 lo = p2 + (p1 << 32);
    u64 hi = p0 + (p1 >> 32) + (lo < p2);
    int n = 34 - (e - first);               /* 32..71 */
    u64 turns = n < 64 ? (lo >> n) | (hi << (64 - n)) : hi >> (n - 64);   /* quarter turns, Q62 */
    u64 f = turns << 2;
    *quad = (unsigned)(turns >> 62);
    *before = f >> 63;
    if (*before) { f = 0 - f; (*quad)++; }
    return mulhi(f, PIO2_Q63);
}

/* sin and cos of a Q63 angle up to pi/4, in Q63. Both are the usual power
 * series, cut off where the next term is below 2^-50. */
static u64 ksin(u64 th) {
    u64 z = mulhi(th << 1, th << 1), p = INV_FACT[15];        /* z = th^2 in Q64 */
    for (int n = 13; n >= 3; n -= 2) p = INV_FACT[n] - mulhi(z, p);
    return th - mulhi(th, mulhi(z, p));
}

static u64 kcos(u64 th) {
    u64 z = mulhi(th << 1, th << 1), p = INV_FACT[14];
    for (int n = 12; n >= 2; n -= 2) p = INV_FACT[n] - mulhi(z, p);
    return ONE63 - (mulhi(z, p) >> 1);
}

/* Sine (turn 0) or cosine (turn 1) of m * 2^e, in Q63; *neg is its sign. */
static u64 sin_or_cos(uint32_t m, int e, unsigned turn, bool *neg) {
    unsigned quad;
    bool before;
    u64 th = reduce(m, e, &quad, &before);
    quad += turn;                               /* cos x = sin(x + pi/2) */
    *neg = quad & 2;
    if (quad & 1) return kcos(th);
    if (before) *neg = !*neg;
    return ksin(th);
}

static float sin_or_cosf(float x, unsigned turn) {
    uint32_t u = bits(x), a = u & ~SIGN;
    if (a >= INF) return nan_();
    if (a < TINY) return turn ? 1.0f : x;
    int e;
    bool neg;
    uint32_t m = split(a, &e);
    u64 mag = sin_or_cos(m, e, turn, &neg);
    if (!turn && (u & SIGN)) neg = !neg;        /* sine is odd, cosine even */
    return pack(neg ? SIGN : 0, mag, -63);
}

float pulli_sinf(float x) { return sin_or_cosf(x, 0); }
float pulli_cosf(float x) { return sin_or_cosf(x, 1); }

float pulli_tanf(float x) {
    uint32_t u = bits(x), a = u & ~SIGN;
    if (a >= INF) return nan_();
    if (a < TINY) return x;
    int e;
    uint32_t m = split(a, &e);
    unsigned quad;
    bool before;
    u64 th = reduce(m, e, &quad, &before);
    u64 s = ksin(th), c = kcos(th);
    uint32_t sign = (u & SIGN) ^ (before ? SIGN : 0);
    if (quad & 1) return ratio(sign ^ SIGN, c, s);   /* tan(pi/2 + r) = -1 / tan r */
    return ratio(sign, s, c);
}

/* ---- exponential ------------------------------------------------------ */

static u64 kexp2(u64 g) {              /* 2^g for a Q64 g in [0, 1), in Q62 */
    u64 u = mulhi(g, LN2_Q64), p = INV_FACT[15];            /* e^u, u below 0.694 */
    for (int n = 14; n >= 2; n--) p = INV_FACT[n] + mulhi(u, p);
    return ONE62 + (u >> 2) + (mulhi(mulhi(u, u), p) >> 2);
}

/* 2^p or 2^-p for a Q55 p below 256. */
static float kpow2(uint32_t sign, bool neg, u64 p) {
    int k = (int)(p >> 55);
    u64 g = p & (ONE55 - 1);
    if (neg) {
        k = -k;
        if (g) { k--; g = ONE55 - g; }
    }
    return pack(sign, kexp2(g << 9), k - 62);
}

float pulli_expf(float x) {
    uint32_t u = bits(x), a = u & ~SIGN;
    if (a > INF) return nan_();
    if (a < 0x32800000u) return 1.0f;                               /* |x| < 2^-26 */
    if (a >= 0x42D20000u) return from_bits((u & SIGN) ? 0 : INF);   /* |x| >= 105 */
    int e;
    u64 fix = (u64)split(a, &e) << (e + 56);                        /* |x| in Q56 */
    return kpow2(0, u & SIGN, mulhi(fix, INV_LN2_Q63));
}

/* ---- logarithms ------------------------------------------------------- */

/* Writes the magnitude bits of a positive float as 2^E * M with M in
 * [sqrt(1/2), sqrt(2)), so that ln M stays small. Returns E; *l is |ln M|
 * in Q63 and *neg says whether ln M is negative. */
static int klog(uint32_t a, u64 *l, bool *neg) {
    int e;
    uint32_t m = split(a, &e), top = 1u << 23;
    *neg = m >= 0xB504F4u;                    /* sqrt(2) * 2^23 */
    if (*neg) top <<= 1;
    /* ln M = 2 atanh(s), s = (M - 1) / (M + 1), which is at most 0.172 */
    u64 num = *neg ? top - m : m - top, den = (u64)m + top;
    u64 s = (((num << 32) / den) << 32) | ((((num << 32) % den) << 32) / den);   /* Q64 */
    u64 z = mulhi(s, s), p = INV_ODD[9];
    for (int k = 8; k >= 1; k--) p = INV_ODD[k] + mulhi(z, p);
    *l = s + mulhi(s, mulhi(z, p));
    return e + (*neg ? 24 : 23);
}

static float logs(float x, int base) {        /* base 0 means e */
    uint32_t u = bits(x), a = u & ~SIGN;
    if (a > INF) return nan_();
    if (!a) return from_bits(SIGN | INF);
    if (u & SIGN) return nan_();
    if (a == INF) return x;
    u64 l;
    bool neg;
    int E = klog(a, &l, &neg);
    if (base == 2) l = mulhi(l, INV_LN2_Q63) << 1;
    if (!E) {                                 /* near 1: keep every bit of a small answer */
        if (base == 10) l = mulhi(l, INV_LN10_Q64);
        return pack(neg ? SIGN : 0, l, -63);
    }
    int64_t t = E * (int64_t)(base == 2 ? ONE55 : LN2_Q55);          /* Q55 */
    t += neg ? -(int64_t)(l >> 8) : (int64_t)(l >> 8);
    u64 mag = t < 0 ? 0 - (u64)t : (u64)t;
    if (base == 10) mag = mulhi(mag, INV_LN10_Q64);
    return pack(t < 0 ? SIGN : 0, mag, -55);
}

float pulli_logf(float x)   { return logs(x, 0); }
float pulli_log2f(float x)  { return logs(x, 2); }
float pulli_log10f(float x) { return logs(x, 10); }

/* ---- power ------------------------------------------------------------ */

static int int_kind(uint32_t a) {     /* of a finite magnitude: 0 not an integer, 1 odd, 2 even */
    int ex = (int)(a >> 23) - 127;
    if (ex >= 24) return 2;
    if (ex < 0) return 0;
    uint32_t m = (a & 0x7FFFFF) | 0x800000;
    if (m & ((1u << (23 - ex)) - 1)) return 0;
    return (m >> (23 - ex)) & 1 ? 1 : 2;
}

float pulli_powf(float x, float y) {
    uint32_t ux = bits(x), uy = bits(y), ax = ux & ~SIGN, ay = uy & ~SIGN;
    bool yneg = uy & SIGN;
    if (!ay || ux == ONE) return 1.0f;
    if (ax > INF || ay > INF) return nan_();
    if (ay == INF) return ax == ONE ? 1.0f : from_bits((ax > ONE) != yneg ? INF : 0);
    int kind = int_kind(ay);
    uint32_t sign = (ux & SIGN) && kind == 1 ? SIGN : 0;
    if (!ax)       return from_bits(sign | (yneg ? INF : 0));
    if (ax == INF) return from_bits(sign | (yneg ? 0 : INF));
    if ((ux & SIGN) && !kind) return nan_();

    /* |x|^y = 2^(y * log2 |x|) */
    u64 l;
    bool lneg;
    int E = klog(ax, &l, &lneg), q = 62;
    l = mulhi(l, INV_LN2_Q63);                /* |log2 M| in Q62 */
    if (E) {
        int64_t t = E * (int64_t)ONE55 + (lneg ? -(int64_t)(l >> 7) : (int64_t)(l >> 7));
        lneg = t < 0;
        l = lneg ? 0 - (u64)t : (u64)t;
        q = 55;
    }
    int ey;
    u64 my = split(ay, &ey);
    u64 p = mulhi(l, my << 40);               /* l * my / 2^24, still Qq */
    int sh = ey + 24 + 55 - q;                /* shift that makes it |y * log2 x| in Q55 */
    if (sh >= 64 || (sh > 0 && p >> (64 - sh))) p = p ? ~(u64)0 : 0;
    else if (sh > 0) p <<= sh;
    else p = sh > -64 ? p >> -sh : 0;
    bool neg = lneg != yneg;
    if (p >= (u64)200 << 55) return from_bits(sign | (neg ? 0 : INF));
    return kpow2(sign, neg, p);
}

/* ---- inverse trigonometry --------------------------------------------- */

/* atan(y / x) for y, x >= 0, each given as m * 2^e with the top bit of m
 * set, or m == 0 for zero. Returns Q61 radians in [0, pi/2]. */
static u64 katan(u64 my, int ey, u64 mx, int ex) {
    if (!my) return 0;
    if (!mx) return PIO2_Q61;
    bool swap = ey > ex || (ey == ex && my > mx);   /* above 45 degrees: use x / y */
    if (swap) {
        u64 m = my; my = mx; mx = m;
        int e = ey; ey = ex; ex = e;
    }
    int d = ex - ey;
    u64 t = 0;                                      /* y / x in Q63, at most 1 */
    if (d < 64) {
        t = divq(my >> 1, mx, 63);
        t = d ? t >> (d - 1) : t << 1;
    }
    /* atan t = atan c + atan((t - c) / (1 + t c)), c the nearest eighth */
    unsigned i = (unsigned)((t + (ONE63 >> 4)) >> 60);
    u64 c = (u64)i << 60;
    bool below = t < c;
    u64 u = divq((below ? c - t : t - c) >> 1, ONE62 + mulhi(t, c), 64);   /* Q64, at most 1/16 */
    u64 z = mulhi(u, u), p = INV_ODD[5];
    for (int k = 4; k >= 1; k--) p = INV_ODD[k] - mulhi(z, p);
    u -= mulhi(u, mulhi(z, p));
    u64 a = (below ? ATAN8[i] - (u >> 1) : ATAN8[i] + (u >> 1)) >> 2;
    return swap ? PIO2_Q61 - a : a;
}

float pulli_atan2f(float y, float x) {
    uint32_t uy = bits(y), ux = bits(x), ay = uy & ~SIGN, ax = ux & ~SIGN;
    if (ay > INF || ax > INF) return nan_();
    u64 r;                                          /* the angle for |y|, |x| */
    if (ay == INF || ax == INF) r = ax != INF ? PIO2_Q61 : ay != INF ? 0 : PIO2_Q61 >> 1;
    else if (!ay) r = 0;
    else if (!ax) r = PIO2_Q61;
    else {
        int ey, ex;
        u64 my = split(ay, &ey), mx = split(ax, &ex);
        /* A very small angle is y / x itself, and a float division is
         * exact on every machine. */
        if (!(ux & SIGN) && ey - ex < -14) return y / x;
        r = katan(my << 40, ey - 40, mx << 40, ex - 40);
    }
    if (ux & SIGN) r = PI_Q61 - r;
    return pack(uy & SIGN, r, -61);
}

static float asin_or_cos(float x, bool cosine) {
    uint32_t u = bits(x), a = u & ~SIGN;
    if (a > ONE) return nan_();
    u64 r = 0;                                      /* asin |x| in Q61 */
    if (a == ONE) r = PIO2_Q61;
    else if (a && a < TINY) {                       /* asin x = x */
        if (!cosine) return x;
        int e, sh;
        u64 m = split(a, &e);
        sh = e + 61;
        r = sh >= 0 ? m << sh : sh > -64 ? m >> -sh : 0;
    } else if (a) {
        /* asin x = atan(x / sqrt(1 - x^2)) */
        int e;
        u64 fix = (u64)split(a, &e) << (e + 62);    /* |x| in Q62 */
        u64 low = ONE62 - fix;
        int sh = clz64(low), q = 61 + sh;
        u64 w = mulhi(low << sh, (ONE62 + fix) << 1);   /* 1 - x^2 in Qq */
        if (q & 1) { w >>= 1; q--; }
        u64 rem;
        uint32_t s0 = isqrt(w, &rem);
        u64 root = ((u64)s0 << 32) + (rem << 31) / s0;  /* sqrt(1 - x^2) in Q(q/2 + 32) */
        int sx = clz64(fix), sr = clz64(root);
        r = katan(fix << sx, -62 - sx, root << sr, -(q / 2 + 32) - sr);
    }
    if (!cosine) return pack(u & SIGN, r, -61);
    return pack(0, (u & SIGN) ? PIO2_Q61 + r : PIO2_Q61 - r, -61);   /* acos x = pi/2 - asin x */
}

float pulli_asinf(float x) { return asin_or_cos(x, false); }
float pulli_acosf(float x) { return asin_or_cos(x, true); }

/* ---- 16.16 fixed point -------------------------------------------------
 *
 * A fixed-point number is a 32-bit integer counting 65536ths. Everything
 * wraps around at 32 bits, as Lua integers do. from, mul, div and sqrt
 * round down; sin, cos and atan2 round to the nearest 65536th.
 */

static int32_t wrap(u64 v)                { return (int32_t)(uint32_t)v; }
static u64     magnitude(int32_t a)       { return a < 0 ? 0 - (u64)(int64_t)a : (u64)a; }
static int32_t with_sign(u64 v, bool neg) { return wrap(neg ? 0 - v : v); }

int32_t pulli_fix_from(float x) {
    uint32_t u = bits(x), a = u & ~SIGN;
    if (!a || a >= INF) return 0;
    int e;
    u64 m = split(a, &e), mag;
    int sh = e + 16;
    bool part = false;                          /* something below a 65536th was cut off */
    if (sh >= 0) mag = sh < 32 ? m << sh : 0;
    else if (sh > -24) { mag = m >> -sh; part = m & (((u64)1 << -sh) - 1); }
    else { mag = 0; part = true; }
    if (!(u & SIGN)) return wrap(mag);
    return wrap(0 - mag - (part ? 1 : 0));
}

float pulli_fix_to(int32_t a) { return (float)a / 65536.0f; }

int32_t pulli_fix_mul(int32_t a, int32_t b) {
    return wrap((u64)((int64_t)a * b) >> 16);   /* the low bits of a wrapped floor */
}

int32_t pulli_fix_div(int32_t a, int32_t b) {
    int64_t num = (int64_t)a * 65536, q = num / b;
    if (num % b && (num < 0) != (b < 0)) q--;   /* C rounds toward zero; round down instead */
    return wrap((u64)q);
}

int32_t pulli_fix_sqrt(int32_t a) {
    u64 rem;
    return (int32_t)isqrt((u64)a << 16, &rem);
}

static int32_t fix_sin_or_cos(int32_t a, unsigned turn) {
    if (!a) return turn ? 65536 : 0;
    bool neg;
    u64 mag = sin_or_cos((uint32_t)magnitude(a), -16, turn, &neg);
    if (!turn && a < 0) neg = !neg;
    return with_sign((mag + ((u64)1 << 46)) >> 47, neg);
}

int32_t pulli_fix_sin(int32_t a) { return fix_sin_or_cos(a, 0); }
int32_t pulli_fix_cos(int32_t a) { return fix_sin_or_cos(a, 1); }

int32_t pulli_fix_atan2(int32_t y, int32_t x) {
    u64 ay = magnitude(y), ax = magnitude(x), r = 0;
    if (ay && !ax) r = PIO2_Q61;
    else if (ay) {
        int sy = clz64(ay), sx = clz64(ax);
        r = katan(ay << sy, -sy, ax << sx, -sx);
    }
    if (x < 0) r = PI_Q61 - r;
    return with_sign((r + ((u64)1 << 44)) >> 45, y < 0);
}

/* ---- self-check -------------------------------------------------------- */

/* ---- fmod -------------------------------------------------------------
 * The remainder of x / y, with the sign of x. It is always exact, so there
 * is one right answer, but C libraries do not all find it: the one the
 * Pico SDK links gave other bits than the desktop's. This works on the
 * bits alone, by long division of the two significands, and so cannot
 * differ. NaN, an infinite x or a zero y give NaN. */
float pulli_fmodf(float x, float y) {
    uint32_t ux = bits(x), uy = bits(y), sx = ux & SIGN, i;
    int ex = (int)(ux >> 23 & 0xFF), ey = (int)(uy >> 23 & 0xFF);
    if ((uy & ~SIGN) == 0 || ex == 0xFF || (uy & ~SIGN) > INF) return nan_();
    if ((ux << 1) <= (uy << 1))                     /* |x| <= |y| */
        return (ux << 1) == (uy << 1) ? from_bits(sx) : x;
    /* both significands as integers with the leading 1 at bit 23 */
    if (!ex) { for (i = ux << 9; !(i >> 31); ex--, i <<= 1) {} ux <<= -ex + 1; }
    else     { ux &= 0x007FFFFFu; ux |= 0x00800000u; }
    if (!ey) { for (i = uy << 9; !(i >> 31); ey--, i <<= 1) {} uy <<= -ey + 1; }
    else     { uy &= 0x007FFFFFu; uy |= 0x00800000u; }
    for (; ex > ey; ex--) {                         /* long division, a bit at a time */
        i = ux - uy;
        if (!(i >> 31)) { if (!i) return from_bits(sx); ux = i; }
        ux <<= 1;
    }
    i = ux - uy;
    if (!(i >> 31)) { if (!i) return from_bits(sx); ux = i; }
    for (; !(ux >> 23); ux <<= 1, ex--) {}
    if (ex > 0) ux = (ux - 0x00800000u) | (uint32_t)ex << 23;
    else ux >>= -ex + 1;                            /* a subnormal result */
    return from_bits(ux | sx);
}

static uint32_t check_seed, check_sum;

static uint32_t next(void) { return check_seed = check_seed * 1664525u + 1013904223u; }

/* A float with any sign and fraction, and an exponent field in [lo, lo + span). */
static float pick(uint32_t lo, uint32_t span) {
    uint32_t r = next();
    return from_bits((r & 0x807FFFFFu) | ((lo + ((r >> 23) & 0xFF) % span) << 23));
}

static void add_int(int32_t v) { check_sum = (check_sum ^ (uint32_t)v) * 16777619u; }

static void add(float v) {
    uint32_t b = bits(v);
    if ((b & ~SIGN) > INF) b = QNAN;          /* libraries differ in the bits of a NaN */
    check_sum = (check_sum ^ b) * 16777619u;
}

uint32_t pulli_math_check(void) {
    check_seed = 0x50554C49u;
    check_sum = 2166136261u;
    for (int i = 0; i < 500; i++) {
        float any = pick(0, 256), any2 = pick(0, 256);     /* anything, NaN and infinity too */
        float mid = pick(113, 22), mid2 = pick(113, 22);   /* 2^-14 to 2^8 */
        float unit = pick(103, 24);                        /* up to 1 */
        float whole = (float)(int)(next() % 41u) - 20.0f;
        add(pulli_sinf(any));   add(pulli_sinf(mid));
        add(pulli_cosf(any));   add(pulli_cosf(mid));
        add(pulli_tanf(any));   add(pulli_tanf(mid));
        add(pulli_asinf(unit)); add(pulli_acosf(unit));
        add(pulli_atan2f(any, any2));   add(pulli_atan2f(mid, mid2));
        add(pulli_expf(any));   add(pulli_expf(mid));
        add(pulli_logf(any));   add(pulli_logf(fabsf(mid)));
        add(pulli_log2f(fabsf(any)));   add(pulli_log10f(fabsf(any)));
        add(pulli_powf(any, any2));     add(pulli_powf(fabsf(mid), mid2));
        add(pulli_powf(mid, whole));    add(pulli_powf(fabsf(unit) + 0.5f, any2));
        add(sqrtf(any));        add(sqrtf(fabsf(mid)));
        add(pulli_fmodf(any, mid));   add(pulli_fmodf(mid, mid2));
        add(floorf(mid));       add(ceilf(mid));
        /* Plain arithmetic, which a float unit and software floats must
         * round the same way, down to the smallest numbers. */
        float small = pick(1, 30);
        add(any + any2);        add(mid + mid2);
        add(any - mid);         add(mid - unit);
        add(any * any2);        add(mid * mid2);
        add(any / any2);        add(mid / mid2);
        add(small * unit);      add(small / mid);
        add((float)(int32_t)next());
        /* Fixed point. */
        int32_t f = (int32_t)next(), g = (int32_t)next(), h = (int32_t)(next() >> 12) - 524288;
        add_int(pulli_fix_from(any));   add_int(pulli_fix_from(mid));
        add(pulli_fix_to(f));           add_int(pulli_fix_mul(f, g));
        add_int(pulli_fix_mul(h, g));   add_int(pulli_fix_div(f, g | 1));
        add_int(pulli_fix_div(h, g | 1));   add_int(pulli_fix_sqrt(f & 0x7FFFFFFF));
        add_int(pulli_fix_sin(f));      add_int(pulli_fix_sin(h));
        add_int(pulli_fix_cos(f));      add_int(pulli_fix_cos(h));
        add_int(pulli_fix_atan2(f, g)); add_int(pulli_fix_atan2(h, g >> 14));
    }
    return check_sum;
}
