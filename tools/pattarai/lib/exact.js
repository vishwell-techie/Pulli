// Isai's own maths. A browser's Math.sin, Math.exp and ** may differ in the
// last bit from one browser (or one computer) to the next; +, -, *, / and
// Math.round never do. These are made from those alone, so a song makes the
// same samples, to the bit, everywhere it is rendered, and the same WAV.
// Each is within about 1e-12 of the true value: far below anything heard.

const PI = 3.141592653589793, TWO_PI = 6.283185307179586, HALF_PI = 1.5707963267948966;
const LN2 = 0.6931471805599453, SQRT2 = 1.4142135623730951;

// 2^k for every k a double can hold, made by halving and doubling (exact)
const P2 = new Float64Array(2098);                 // P2[k + 1074] = 2^k
{
  P2[1074] = 1;
  for (let k = 1; k <= 1023; k++) P2[1074 + k] = P2[1073 + k] * 2;
  for (let k = 1; k <= 1074; k++) P2[1074 - k] = P2[1075 - k] / 2;
}
const pow2 = (k) => (k > 1023 ? Infinity : k < -1074 ? 0 : P2[k + 1074]);

// sin: folded into [-π/2, π/2], then the Taylor series to x^15
export function sin(x) {
  x -= Math.round(x / TWO_PI) * TWO_PI;
  if (x > HALF_PI) x = PI - x;
  else if (x < -HALF_PI) x = -PI - x;
  const y = x * x;
  return x * (1 + y * (-1 / 6 + y * (1 / 120 + y * (-1 / 5040 + y * (1 / 362880 + y * (-1 / 39916800 +
    y * (1 / 6227020800 + y * (-1 / 1307674368000))))))));
}

export const cos = (x) => sin(x + HALF_PI);

// exp: x = k ln 2 + r with |r| <= ln 2 / 2, the series for e^r, times 2^k
export function exp(x) {
  if (x !== x) return x;
  if (x > 709.78) return Infinity;
  if (x < -745.2) return 0;
  const k = Math.round(x / LN2), r = x - k * LN2;
  let term = 1, sum = 1;
  for (let n = 1; n <= 14; n++) { term = term * r / n; sum += term; }
  return k < -1021 ? sum * pow2(k + 54) * pow2(-54) : sum * pow2(k);
}

// log, for x > 0: x = m 2^e with m in [1/√2, √2), log m = 2 atanh((m-1)/(m+1))
export function log(x) {
  if (!(x > 0)) return x === 0 ? -Infinity : NaN;
  if (x === Infinity) return x;
  let e = 0, lo = -1074, hi = 1023;
  while (lo < hi) {                                // the largest e with 2^e <= x
    const mid = Math.floor((lo + hi + 1) / 2);
    if (pow2(mid) <= x) lo = mid; else hi = mid - 1;
  }
  e = lo;
  let m = e >= -1022 ? x * pow2(-e) : x * pow2(54) * pow2(-e - 54);
  if (m > SQRT2) { m /= 2; e += 1; }
  const s = (m - 1) / (m + 1), s2 = s * s;
  let term = s, sum = s;
  for (let n = 3; n <= 31; n += 2) { term *= s2; sum += term / n; }
  return 2 * sum + e * LN2;
}

// a^b for a > 0 (all Isai needs), and whole powers of anything by multiplying
export function pow(a, b) {
  if (b === 0) return 1;
  if (Number.isInteger(b) && Math.abs(b) <= 64) {
    let r = 1, n = Math.abs(b), f = a;
    while (n) { if (n & 1) r *= f; f *= f; n >>= 1; }
    return b < 0 ? 1 / r : r;
  }
  if (a === 0) return b > 0 ? 0 : Infinity;
  return exp(b * log(a));
}
