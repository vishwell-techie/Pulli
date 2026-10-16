/* gfx.c — Pulli rasterizer. No platform dependencies, by contract.
 * Compiles unchanged for the desktop host and the RP2350 firmware.
 * tools/refgfx.py mirrors every primitive here; tests/ compares the two. */
#include "pulli.h"
#include <math.h>
#include <string.h>

/* PULLI_HOT marks the functions that draw most of every frame. A port may
 * define it to place them where its CPU runs code fastest: the Pico 2
 * firmware puts them in RAM rather than flash. Here it means nothing. */
#ifndef PULLI_HOT
#define PULLI_HOT
#endif

static inline bool in_clip(const pulli_gfx *g, int x, int y) {
    return x >= g->clip_x && y >= g->clip_y &&
           x <  g->clip_x + g->clip_w && y < g->clip_y + g->clip_h;
}

/* All drawing goes through here. Applies camera, clip and palette remap.
 * Single choke point = single place to get the semantics right. */
static inline void put(pulli_gfx *g, int x, int y, int c) {
    x -= g->cam_x; y -= g->cam_y;
    if (!in_clip(g, x, y)) return;
    g->fb[y * PULLI_SCREEN_W + x] = g->pal_map[c & PULLI_COLOR_MASK];
}

/* Clip a box of pixels, given in screen space (after the camera), to the
 * clip rectangle: [*x0, *x1) by [*y0, *y1). False if nothing is left.
 * The fast paths below use it to work out once per call which rows and
 * columns can be drawn, instead of asking put() about every pixel; what
 * they draw is exactly what put() would. */
static inline bool clip_box(const pulli_gfx *g, int *x0, int *y0, int *x1, int *y1) {
    if (*x0 < g->clip_x) *x0 = g->clip_x;
    if (*y0 < g->clip_y) *y0 = g->clip_y;
    if (*x1 > g->clip_x + g->clip_w) *x1 = g->clip_x + g->clip_w;
    if (*y1 > g->clip_y + g->clip_h) *y1 = g->clip_y + g->clip_h;
    return *x0 < *x1 && *y0 < *y1;
}

/* A run of one colour from x0 to x1 inclusive on row y, in world space. */
PULLI_HOT static void hline(pulli_gfx *g, int x0, int x1, int y, int c) {
    int sx0 = x0 - g->cam_x, sx1 = x1 - g->cam_x + 1, sy0 = y - g->cam_y, sy1 = sy0 + 1;
    if (!clip_box(g, &sx0, &sy0, &sx1, &sy1)) return;
    memset(g->fb + sy0 * PULLI_SCREEN_W + sx0, g->pal_map[c & PULLI_COLOR_MASK], (size_t)(sx1 - sx0));
}

/* 32 base hues, then the same hues at 9/16 brightness 32 indices later, so
 * pal(c, c+32) darkens anything. */
static const uint32_t BASE_RGB[32] = {
    0x000000,0x1D2B53,0x7E2553,0x008751,0xAB5236,0x5F574F,0xC2C3C7,0xFFF1E8,
    0xFF004D,0xFFA300,0xFFEC27,0x00E436,0x29ADFF,0x83769C,0xFF77A8,0xFFCCAA,
    0x291814,0x111D35,0x422136,0x125359,0x742F29,0x49333B,0xA28879,0xF3EF7D,
    0xBE1250,0xFF6C24,0xA8E72E,0x00B543,0x065AB5,0x754665,0xFF6E59,0xFF9D81
};

void pulli_default_palette(uint16_t out[PULLI_PALETTE_LEN]) {
    for (int i = 0; i < PULLI_PALETTE_LEN; i++) {
        uint32_t c = BASE_RGB[i % 32];
        uint32_t r = (c >> 16) & 0xFF, gr = (c >> 8) & 0xFF, b = c & 0xFF;
        if (i >= 32) { r = r * 9 / 16; gr = gr * 9 / 16; b = b * 9 / 16; }
        out[i] = (uint16_t)(((r >> 3) << 11) | ((gr >> 2) << 5) | (b >> 3));
    }
}

/* Rebuild what reaches the screen from the game's palette and the fade
 * level. Call after changing either. */
static void refresh_shown(pulli_gfx *g) {
    const int k = g->fade_k;
    for (int i = 0; i < PULLI_PALETTE_LEN; i++) {
        uint16_t p = g->palette[i];
        int r = (p >> 11) & 0x1F, gr = (p >> 5) & 0x3F, b = p & 0x1F;
        r = (r * k) >> 5; gr = (gr * k) >> 5; b = (b * k) >> 5;
        g->shown[i] = (uint16_t)((r << 11) | (gr << 5) | b);
    }
}

void pulli_gfx_init(pulli_gfx *g) {
    memset(g, 0, sizeof(*g));
    pulli_pal(g, -1, 0);
    pulli_palt(g, -1, true);
    g->clip_w = PULLI_SCREEN_W; g->clip_h = PULLI_SCREEN_H;
    g->font = pulli_font8x8;
    g->fade_k = 32;
    pulli_default_palette(g->palette);
    refresh_shown(g);
}

void pulli_cls(pulli_gfx *g, int c) {
    memset(g->fb, g->pal_map[c & PULLI_COLOR_MASK], PULLI_FB_BYTES);
}

void pulli_pset(pulli_gfx *g, int x, int y, int c) { put(g, x, y, c); }

uint8_t pulli_pget(const pulli_gfx *g, int x, int y) {
    x -= g->cam_x; y -= g->cam_y;
    if (x < 0 || y < 0 || x >= PULLI_SCREEN_W || y >= PULLI_SCREEN_H) return 0;
    return g->fb[y * PULLI_SCREEN_W + x];
}

void pulli_line(pulli_gfx *g, int x0, int y0, int x1, int y1, int c) {
    int dx = x1 - x0, dy = y1 - y0;
    int sx = dx >= 0 ? 1 : -1, sy = dy >= 0 ? 1 : -1;
    dx = dx >= 0 ? dx : -dx;
    dy = dy >= 0 ? dy : -dy;
    int err = dx - dy;
    for (;;) {
        put(g, x0, y0, c);
        if (x0 == x1 && y0 == y1) break;
        int e2 = err * 2;
        if (e2 > -dy) { err -= dy; x0 += sx; }
        if (e2 <  dx) { err += dx; y0 += sy; }
    }
}

void pulli_rect(pulli_gfx *g, int x, int y, int w, int h, int c) {
    if (w <= 0 || h <= 0) return;
    for (int i = 0; i < w; i++) { put(g, x+i, y, c); put(g, x+i, y+h-1, c); }
    for (int j = 1; j < h-1; j++) { put(g, x, y+j, c); put(g, x+w-1, y+j, c); }
}

PULLI_HOT void pulli_rectfill(pulli_gfx *g, int x, int y, int w, int h, int c) {
    if (w <= 0 || h <= 0) return;
    int x0 = x - g->cam_x, y0 = y - g->cam_y, x1 = x0 + w, y1 = y0 + h;
    if (!clip_box(g, &x0, &y0, &x1, &y1)) return;
    uint8_t v = g->pal_map[c & PULLI_COLOR_MASK];
    for (int j = y0; j < y1; j++) memset(g->fb + j * PULLI_SCREEN_W + x0, v, (size_t)(x1 - x0));
}

void pulli_circ(pulli_gfx *g, int cx, int cy, int r, int c) {
    int x = r, y = 0, err = 1 - r;
    while (x >= y) {
        put(g, cx+x, cy+y, c); put(g, cx+y, cy+x, c);
        put(g, cx-y, cy+x, c); put(g, cx-x, cy+y, c);
        put(g, cx-x, cy-y, c); put(g, cx-y, cy-x, c);
        put(g, cx+y, cy-x, c); put(g, cx+x, cy-y, c);
        y++;
        if (err < 0) err += 2*y + 1;
        else { x--; err += 2*(y - x) + 1; }
    }
}

/* Every point with x*x + y*y <= r*r, drawn a row at a time: on row y the
 * widest such x shrinks as y grows, so it is found by stepping down. */
PULLI_HOT void pulli_circfill(pulli_gfx *g, int cx, int cy, int r, int c) {
    if (r < 0) return;
    int x = r;
    for (int y = 0; y <= r; y++) {
        while (x * x + y * y > r * r) x--;
        hline(g, cx - x, cx + x, cy + y, c);
        if (y) hline(g, cx - x, cx + x, cy - y, c);
    }
}

/* The largest whole s with s * s <= v, for 0 <= v <= 32767 * 32767. The
 * float square root only gives a first guess; the steps make it exact on
 * every machine. */
static inline int isqrt_floor(int v) {
    int s = (int)sqrtf((float)v);
    while (s * s > v) s--;
    while ((s + 1) * (s + 1) <= v) s++;
    return s;
}

/* Darkness with lights cut out of it: every pixel of the clip rectangle
 * that no light reaches becomes colour c. lights holds n triples x, y, r in
 * world space; a light covers exactly the pixels circfill(x, y, r) would.
 * Row by row, the lights crossing the row give spans, sorted by where they
 * start and joined where they overlap or touch. Between the joined spans
 * goes c; on the first and last `edge` pixels of each (no more than half
 * its width, rounded down), c goes on every pixel whose x + y is even,
 * softening the edge. x and y there are world coordinates. */
PULLI_HOT void pulli_shade(pulli_gfx *g, int c, const int *lights, int n, int edge) {
    if (n > PULLI_SHADE_LIGHTS) n = PULLI_SHADE_LIGHTS;
    if (n < 0) n = 0;
    if (edge < 0) edge = 0;
    if (edge > PULLI_SHADE_EDGE) edge = PULLI_SHADE_EDGE;
    const int sx0 = g->clip_x, sx1 = g->clip_x + g->clip_w;
    const int sy0 = g->clip_y, sy1 = g->clip_y + g->clip_h;
    if (sx0 >= sx1 || sy0 >= sy1) return;
    const uint8_t v = g->pal_map[c & PULLI_COLOR_MASK];
    const int wx0 = sx0 + g->cam_x, wx1 = sx1 + g->cam_x;     /* the clip in world x */
    int from[PULLI_SHADE_LIGHTS], to[PULLI_SHADE_LIGHTS];
    for (int sy = sy0; sy < sy1; sy++) {
        const int y = sy + g->cam_y;
        int k = 0;
        for (int i = 0; i < n; i++) {
            const int lx = lights[3*i], ly = lights[3*i + 1], r = lights[3*i + 2];
            int dy = y - ly;
            if (dy < 0) dy = -dy;
            if (r < 0 || dy > r) continue;
            const int hw = isqrt_floor(r * r - dy * dy);
            const int a = lx - hw, b = lx + hw;
            int j = k;
            while (j > 0 && from[j-1] > a) { from[j] = from[j-1]; to[j] = to[j-1]; j--; }
            from[j] = a; to[j] = b;
            k++;
        }
        /* row points at world x 0 of this row, so row[x] is world pixel x */
        uint8_t *row = g->fb + sy * PULLI_SCREEN_W - g->cam_x;
        int x = wx0;                        /* the next world x not yet decided */
        for (int i = 0; i < k; ) {
            int a = from[i], b = to[i];
            for (i++; i < k && from[i] <= b + 1; i++) if (to[i] > b) b = to[i];
            if (a > x) {
                int e = a < wx1 ? a : wx1;
                if (e > x) memset(row + x, v, (size_t)(e - x));
            }
            const int half = (b - a + 1) / 2, w = edge < half ? edge : half;
            for (int p = 0; p < 2; p++) {
                int lo = p ? b - w + 1 : a, hi = p ? b : a + w - 1;      /* inclusive */
                if (lo < wx0) lo = wx0;
                if (hi >= wx1) hi = wx1 - 1;
                if ((lo + y) & 1) lo++;
                for (int px = lo; px <= hi; px += 2) row[px] = v;
            }
            if (b + 1 > x) x = b + 1;
        }
        if (x < wx1) memset(row + x, v, (size_t)(wx1 - x));
    }
}

/* Sprite n indexes 8x8 cells in the atlas, left-to-right, top-to-bottom.
 * cw/ch are cell counts, so spr(n,x,y,2,2) draws a 16x16 sprite. Only the
 * rows and columns inside the clip rectangle are visited; each pixel is
 * read from the atlas, skipped if transparent, and written through the
 * palette remap, as put() would. */
PULLI_HOT void pulli_spr(pulli_gfx *g, int n, int x, int y, int cw, int ch,
               bool flip_x, bool flip_y) {
    if (!g->atlas || g->atlas_w <= 0 || n < 0) return;
    if (cw <= 0) cw = 1;
    if (ch <= 0) ch = 1;
    const int cells_per_row = g->atlas_w / PULLI_SPRITE_CELL;
    if (cells_per_row <= 0) return;
    const int ax = (n % cells_per_row) * PULLI_SPRITE_CELL;
    const int ay = (n / cells_per_row) * PULLI_SPRITE_CELL;
    const int pw = cw * PULLI_SPRITE_CELL, ph = ch * PULLI_SPRITE_CELL;
    const int dx = x - g->cam_x, dy = y - g->cam_y;
    int x0 = dx, y0 = dy, x1 = dx + pw, y1 = dy + ph;
    if (!clip_box(g, &x0, &y0, &x1, &y1)) return;

    /* Columns whose atlas pixel lies past the sheet's right edge are not
     * drawn; cut them off once rather than test every pixel. */
    if (flip_x) { int lo = dx + pw - (g->atlas_w - ax); if (x0 < lo) x0 = lo; }
    else        { int hi = dx + g->atlas_w - ax;       if (x1 > hi) x1 = hi; }
    if (x0 >= x1) return;
    const uint8_t *lut = g->sprite_lut;
    const int run = x1 - x0;
    for (int sy0 = y0; sy0 < y1; sy0++) {
        int j = sy0 - dy;
        int sy = ay + (flip_y ? ph - 1 - j : j);
        if (sy < 0 || sy >= g->atlas_h) continue;
        uint8_t *dst = g->fb + sy0 * PULLI_SCREEN_W + x0;
        if (flip_x) {
            const uint8_t *src = g->atlas + sy * g->atlas_w + ax + pw - 1 - (x0 - dx);
            for (int k = 0; k < run; k++) {
                uint8_t v = lut[src[-k] & PULLI_COLOR_MASK];
                if (v != 0xFF) dst[k] = v;
            }
        } else {
            const uint8_t *src = g->atlas + sy * g->atlas_w + ax + (x0 - dx);
            for (int k = 0; k < run; k++) {
                uint8_t v = lut[src[k] & PULLI_COLOR_MASK];
                if (v != 0xFF) dst[k] = v;
            }
        }
    }
}

/* Nearest-neighbour stretched blit. Integer-only: identical on host and MCU.
 * Destination column i reads source column sx + floor(i * sw / dw); the
 * quotient is carried from one column to the next instead of divided out
 * for each pixel. */
PULLI_HOT void pulli_sspr(pulli_gfx *g, int sx, int sy, int sw, int sh,
                int dx, int dy, int dw, int dh) {
    if (!g->atlas || sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0) return;
    const int ox = dx - g->cam_x, oy = dy - g->cam_y;
    int x0 = ox, y0 = oy, x1 = ox + dw, y1 = oy + dh;
    if (!clip_box(g, &x0, &y0, &x1, &y1)) return;
    const int step_q = sw / dw, step_r = sw % dw;
    for (int sy0 = y0; sy0 < y1; sy0++) {
        int j = sy0 - oy;
        int ty = sy + (int)(((long long)j * sh) / dh);
        if (ty < 0 || ty >= g->atlas_h) continue;
        const uint8_t *src = g->atlas + ty * g->atlas_w;
        uint8_t *dst = g->fb + sy0 * PULLI_SCREEN_W;
        long long first = (long long)(x0 - ox) * sw;
        int q = (int)(first / dw), r = (int)(first % dw);
        for (int sx0 = x0; sx0 < x1; sx0++) {
            int tx = sx + q;
            if (tx >= 0 && tx < g->atlas_w) {
                uint8_t v = g->sprite_lut[src[tx] & PULLI_COLOR_MASK];
                if (v != 0xFF) dst[sx0] = v;
            }
            q += step_q; r += step_r;
            if (r >= dw) { q++; r -= dw; }
        }
    }
}

/* ---- text ------------------------------------------------------------ */

/* The character starting at byte i, and its length in bytes in *n. A byte
 * that does not start a well-formed character gives -1, length 1. */
static int32_t utf8_next(const unsigned char *s, size_t len, size_t i, int *n) {
    unsigned b = s[i];
    int32_t cp;
    *n = 1;
    if (b < 0x80) return (int32_t)b;
    if (b >= 0xC2 && b <= 0xDF)      { *n = 2; cp = b & 0x1F; }
    else if (b >= 0xE0 && b <= 0xEF) { *n = 3; cp = b & 0x0F; }
    else if (b >= 0xF0 && b <= 0xF4) { *n = 4; cp = b & 0x07; }
    else return -1;
    if (i + (size_t)*n > len) { *n = 1; return -1; }
    for (int k = 1; k < *n; k++) {
        unsigned c = s[i + k];
        if (c < 0x80 || c > 0xBF) { *n = 1; return -1; }
        cp = (cp << 6) | (int32_t)(c & 0x3F);
    }
    return cp;
}

/* The glyph that draws exactly these `count` characters, or NULL. The table
 * is sorted by letters, zero-padded to four, so a binary search finds it. */
static const pulli_ta_glyph *ta_find(const int32_t *cp, int count) {
    uint32_t key[4] = { 0, 0, 0, 0 };
    for (int k = 0; k < count; k++) key[k] = (uint32_t)cp[k];
    int lo = 0, hi = pulli_font_ta_count - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2, d = 0;
        const uint32_t *l = pulli_font_ta[mid].letters;
        for (int k = 0; k < 4 && d == 0; k++) d = l[k] < key[k] ? -1 : l[k] > key[k] ? 1 : 0;
        if (d == 0) return &pulli_font_ta[mid];
        if (d < 0) lo = mid + 1; else hi = mid - 1;
    }
    return NULL;
}

/* The next piece of a line that ends at byte `len`: Tamil matched longest
 * first, so a syllable comes out whole (*gl), else an English code (*code,
 * -1 for a control character to skip, '?' for a character the fonts lack).
 * Returns the bytes it takes. */
static size_t next_piece(const unsigned char *s, size_t len, size_t i, int *code, const pulli_ta_glyph **gl) {
    int32_t cp[4];
    int bytes[4], count = 0;
    size_t j = i;
    *gl = NULL;
    while (count < 4 && j < len) {
        cp[count] = utf8_next(s, len, j, &bytes[count]);
        if (cp[count] < 0 || (count > 0 && cp[count] < 128)) break;
        j += (size_t)bytes[count++];
    }
    if (count == 0) {                           /* not UTF-8 */
        *code = '?';
        return 1;
    }
    if (cp[0] < 128) {
        *code = cp[0] >= 32 ? (int)cp[0] : -1;
        return 1;
    }
    for (int n = count; n > 0; n--) {
        if ((*gl = ta_find(cp, n)) != NULL) {
            size_t used = 0;
            for (int k = 0; k < n; k++) used += (size_t)bytes[k];
            return used;
        }
    }
    *code = '?';
    return (size_t)bytes[0];
}

static void draw_english(pulli_gfx *g, int code, int x, int y, int c) {
    const uint8_t *glyph = g->font + (code - 32) * PULLI_SPRITE_CELL;
    for (int j = 0; j < PULLI_SPRITE_CELL; j++)
        for (int i = 0; i < PULLI_SPRITE_CELL; i++)
            if (glyph[j] & (0x80u >> i)) put(g, x + i, y + j, c);
}

static void draw_tamil(pulli_gfx *g, const pulli_ta_glyph *gl, int x, int y, int c) {
    const uint8_t *row = pulli_font_ta_bits + gl->offset;
    int stride = (gl->width + 7) / 8;
    for (int j = 0; j < pulli_font_ta_rows; j++, row += stride)
        for (int i = 0; i < gl->width; i++)
            if (row[i >> 3] & (0x80u >> (i & 7))) put(g, x + i, y + j, c);
}

/* Lays out the text line by line, drawing it when g is not NULL. A line
 * holding Tamil is pulli_font_ta_rows tall, with its English lowered to
 * share the Tamil baseline; any other line is 8. Fills where the last line
 * ended, the widest line and the height of them all. */
static void lay_out(pulli_gfx *g, const char *str, size_t len, int ox, int oy, int c,
                    int *end_x, int *widest, int *height) {
    const unsigned char *s = (const unsigned char *)str;
    const pulli_ta_glyph *gl;
    int code, x = 0, y = 0;
    size_t i = 0;
    *widest = 0;
    for (;;) {
        size_t end = i;
        while (end < len && s[end] != '\n') end++;
        bool tamil = false;
        for (size_t j = i; j < end; ) {
            j += next_piece(s, end, j, &code, &gl);
            if (gl) tamil = true;
        }
        int lower = tamil ? pulli_font_ta_above : 0;
        x = 0;
        for (size_t j = i; j < end; ) {
            j += next_piece(s, end, j, &code, &gl);
            if (gl) {
                if (g) draw_tamil(g, gl, ox + x + gl->kern, oy + y, c);
                x += gl->adv;
            } else if (code >= 0) {
                if (g) draw_english(g, code, ox + x, oy + y + lower, c);
                x += PULLI_SPRITE_CELL;
            }
        }
        if (x > *widest) *widest = x;
        y += tamil ? pulli_font_ta_rows : PULLI_SPRITE_CELL;
        if (end >= len) break;
        i = end + 1;
    }
    *end_x = x;
    *height = y;
}

int pulli_print(pulli_gfx *g, const char *s, size_t len, int x, int y, int c) {
    int end_x, w, h;
    if (!g->font || !s) return x;
    lay_out(g, s, len, x, y, c, &end_x, &w, &h);
    return x + end_x;
}

void pulli_text_size(const char *s, size_t len, int *w, int *h) {
    int end_x;
    lay_out(NULL, s ? s : "", s ? len : 0, 0, 0, 0, &end_x, w, h);
}

void pulli_camera(pulli_gfx *g, int x, int y) { g->cam_x = x; g->cam_y = y; }

void pulli_clip(pulli_gfx *g, int x, int y, int w, int h) {
    if (w <= 0 || h <= 0) {
        g->clip_x = 0; g->clip_y = 0;
        g->clip_w = PULLI_SCREEN_W; g->clip_h = PULLI_SCREEN_H;
        return;
    }
    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (w > PULLI_SCREEN_W - x) w = PULLI_SCREEN_W - x;
    if (h > PULLI_SCREEN_H - y) h = PULLI_SCREEN_H - y;
    g->clip_x = x; g->clip_y = y;
    g->clip_w = w > 0 ? w : 0;
    g->clip_h = h > 0 ? h : 0;
}

/* Sprites look up each pixel's colour on screen, or 0xFF for one not
 * drawn, in one table; pal() and palt() keep it up to date, changing only
 * the entry they touch unless they reset everything. */
static void refresh_lut_entry(pulli_gfx *g, int i) {
    g->sprite_lut[i] = g->transparent[i] ? 0xFF : g->pal_map[i];
}

static void refresh_lut(pulli_gfx *g) {
    for (int i = 0; i < PULLI_PALETTE_LEN; i++) refresh_lut_entry(g, i);
}

void pulli_pal(pulli_gfx *g, int a, int b) {
    if (a < 0) {
        for (int i = 0; i < PULLI_PALETTE_LEN; i++) g->pal_map[i] = (uint8_t)i;
        refresh_lut(g);
        return;
    }
    g->pal_map[a & PULLI_COLOR_MASK] = (uint8_t)(b & PULLI_COLOR_MASK);
    refresh_lut_entry(g, a & PULLI_COLOR_MASK);
}

void pulli_palt(pulli_gfx *g, int c, bool t) {
    if (c < 0) {
        for (int i = 0; i < PULLI_PALETTE_LEN; i++) g->transparent[i] = false;
        g->transparent[0] = true;          /* index 0 transparent by default */
        refresh_lut(g);
        return;
    }
    g->transparent[c & PULLI_COLOR_MASK] = t;
    refresh_lut_entry(g, c & PULLI_COLOR_MASK);
}

/* Palette-level fade: costs nothing per pixel, which is the whole point of
 * running an indexed framebuffer. It sets a level rather than darkening
 * what is there, so calling fade(0.5) every frame holds half brightness and
 * fade(0) restores the picture. */
void pulli_fade(pulli_gfx *g, float amount) {
    if (!(amount > 0)) amount = 0;         /* also catches NaN */
    if (amount > 1) amount = 1;
    g->fade_k = 32 - (int)(amount * 32.0f + 0.5f);
    refresh_shown(g);
}

/* Draws one layer with its top-left corner at (-sx, -sy), under the camera
 * like everything else. Only the tiles that can reach the screen are
 * visited, so a large map costs no more than a small one. */
/* A colour as red, green and blue from 0 to 255, kept as RGB565 like every
 * other. The fade level applies to it as to the rest. */
static int byte_of(int v) { return v < 0 ? 0 : v > 255 ? 255 : v; }

void pulli_set_colour(pulli_gfx *g, int c, int r, int gr, int b) {
    r = byte_of(r); gr = byte_of(gr); b = byte_of(b);
    g->palette[c & PULLI_COLOR_MASK] = (uint16_t)(((r >> 3) << 11) | ((gr >> 2) << 5) | (b >> 3));
    refresh_shown(g);
}

void pulli_load_palette(pulli_gfx *g, const uint16_t rgb565[PULLI_PALETTE_LEN]) {
    memcpy(g->palette, rgb565, sizeof(g->palette));
    refresh_shown(g);
}

/* One whole 8x8 tile, every pixel of it inside the clip rectangle and the
 * atlas: what most of map.draw is made of. It draws what pulli_spr would,
 * without the checks for rows and columns that might be cut off, and with
 * loops of a known length the compiler can unroll. */
PULLI_HOT static void tile8(const uint8_t *lut, const uint8_t *src, int stride,
                            uint8_t *dst, bool flip_x, bool flip_y) {
    if (flip_y) { src += 7 * stride; stride = -stride; }
    for (int j = 0; j < 8; j++, src += stride, dst += PULLI_SCREEN_W) {
        uint8_t p[8];
        if (flip_x) for (int k = 0; k < 8; k++) p[k] = lut[src[7 - k] & PULLI_COLOR_MASK];
        else        for (int k = 0; k < 8; k++) p[k] = lut[src[k] & PULLI_COLOR_MASK];
        for (int k = 0; k < 8; k++) if (p[k] != 0xFF) dst[k] = p[k];
    }
}

PULLI_HOT void pulli_map_draw(pulli_gfx *g, const pulli_map *m, int layer, int sx, int sy) {
    if (layer < 0 || layer >= m->layers) return;
    const int cell = PULLI_SPRITE_CELL;
    const uint16_t *cells = m->cells + (size_t)layer * m->w * m->h;
    const int per_row = g->atlas ? g->atlas_w / cell : 0;
    if (per_row <= 0) return;                      /* no sheet: pulli_spr draws nothing either */
    const int cx0 = g->clip_x, cy0 = g->clip_y;
    const int cx1 = cx0 + g->clip_w - cell, cy1 = cy0 + g->clip_h - cell;  /* last whole-tile spots */
    /* The first tile on screen. Division rounds toward zero, which is only
     * wrong left of and above the map, where there are no tiles to miss. */
    int first_x = (g->cam_x + sx) / cell, first_y = (g->cam_y + sy) / cell;
    for (int my = first_y; my <= first_y + PULLI_SCREEN_H / cell; my++) {
        if (my < 0 || my >= m->h) continue;
        const int wy = my * cell - sy, ty = wy - g->cam_y;
        const bool row_whole = ty >= cy0 && ty <= cy1;
        for (int mx = first_x; mx <= first_x + PULLI_SCREEN_W / cell; mx++) {
            if (mx < 0 || mx >= m->w) continue;
            uint16_t c = cells[my * m->w + mx];
            int n = c & PULLI_TILE_MASK;
            if (!n) continue;                              /* tile 0 is empty */
            const int wx = mx * cell - sx, tx = wx - g->cam_x;
            const int ax = (n % per_row) * cell, ay = (n / per_row) * cell;
            if (row_whole && tx >= cx0 && tx <= cx1 && ax + cell <= g->atlas_w && ay + cell <= g->atlas_h)
                tile8(g->sprite_lut, g->atlas + ay * g->atlas_w + ax, g->atlas_w,
                      g->fb + ty * PULLI_SCREEN_W + tx, c & PULLI_TILE_FLIP_X, c & PULLI_TILE_FLIP_Y);
            else
                pulli_spr(g, n, wx, wy, 1, 1, c & PULLI_TILE_FLIP_X, c & PULLI_TILE_FLIP_Y);
        }
    }
}

/* Strip-wise index -> RGB565. On the RP2350 this runs into a small buffer
 * that is DMA'd to the panel while the next strip converts. The cost of
 * this loop is the number that decides whether 320x240 survives (SPEC §9). */
PULLI_HOT void pulli_scanout(const pulli_gfx *g, int y0, int rows, uint16_t *out) {
    const uint8_t *src = g->fb + (size_t)y0 * PULLI_SCREEN_W;
    size_t n = (size_t)rows * PULLI_SCREEN_W;
    for (size_t i = 0; i < n; i++) out[i] = g->shown[src[i] & PULLI_COLOR_MASK];
}
