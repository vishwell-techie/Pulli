/* gfx.c — Pulli rasterizer. No platform dependencies, by contract.
 * Compiles unchanged for the desktop host and the RP2350 firmware.
 * tools/refgfx.py mirrors every primitive here; tests/ compares the two. */
#include "pulli.h"
#include <string.h>

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

void pulli_rectfill(pulli_gfx *g, int x, int y, int w, int h, int c) {
    for (int j = 0; j < h; j++)
        for (int i = 0; i < w; i++)
            put(g, x+i, y+j, c);
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

void pulli_circfill(pulli_gfx *g, int cx, int cy, int r, int c) {
    for (int y = -r; y <= r; y++)
        for (int x = -r; x <= r; x++)
            if (x*x + y*y <= r*r) put(g, cx+x, cy+y, c);
}

/* Sprite n indexes 8x8 cells in the atlas, left-to-right, top-to-bottom.
 * cw/ch are cell counts, so spr(n,x,y,2,2) draws a 16x16 sprite. */
void pulli_spr(pulli_gfx *g, int n, int x, int y, int cw, int ch,
               bool flip_x, bool flip_y) {
    if (!g->atlas || g->atlas_w <= 0 || n < 0) return;
    if (cw <= 0) cw = 1;
    if (ch <= 0) ch = 1;
    const int cells_per_row = g->atlas_w / PULLI_SPRITE_CELL;
    if (cells_per_row <= 0) return;
    const int ax = (n % cells_per_row) * PULLI_SPRITE_CELL;
    const int ay = (n / cells_per_row) * PULLI_SPRITE_CELL;
    const int pw = cw * PULLI_SPRITE_CELL, ph = ch * PULLI_SPRITE_CELL;

    for (int j = 0; j < ph; j++) {
        int sy = ay + (flip_y ? ph - 1 - j : j);
        if (sy < 0 || sy >= g->atlas_h) continue;
        for (int i = 0; i < pw; i++) {
            int sx = ax + (flip_x ? pw - 1 - i : i);
            if (sx < 0 || sx >= g->atlas_w) continue;
            int c = g->atlas[sy * g->atlas_w + sx] & PULLI_COLOR_MASK;
            if (g->transparent[c]) continue;
            put(g, x + i, y + j, c);
        }
    }
}

/* Nearest-neighbour stretched blit. Integer-only: identical on host and MCU. */
void pulli_sspr(pulli_gfx *g, int sx, int sy, int sw, int sh,
                int dx, int dy, int dw, int dh) {
    if (!g->atlas || sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0) return;
    for (int j = 0; j < dh; j++) {
        int ty = sy + (j * sh) / dh;
        if (ty < 0 || ty >= g->atlas_h) continue;
        for (int i = 0; i < dw; i++) {
            int tx = sx + (i * sw) / dw;
            if (tx < 0 || tx >= g->atlas_w) continue;
            int c = g->atlas[ty * g->atlas_w + tx] & PULLI_COLOR_MASK;
            if (g->transparent[c]) continue;
            put(g, dx + i, dy + j, c);
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

void pulli_pal(pulli_gfx *g, int a, int b) {
    if (a < 0) {
        for (int i = 0; i < PULLI_PALETTE_LEN; i++) g->pal_map[i] = (uint8_t)i;
        return;
    }
    g->pal_map[a & PULLI_COLOR_MASK] = (uint8_t)(b & PULLI_COLOR_MASK);
}

void pulli_palt(pulli_gfx *g, int c, bool t) {
    if (c < 0) {
        for (int i = 0; i < PULLI_PALETTE_LEN; i++) g->transparent[i] = false;
        g->transparent[0] = true;          /* index 0 transparent by default */
        return;
    }
    g->transparent[c & PULLI_COLOR_MASK] = t;
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

void pulli_map_draw(pulli_gfx *g, const pulli_map *m, int layer, int sx, int sy) {
    if (layer < 0 || layer >= m->layers) return;
    const int cell = PULLI_SPRITE_CELL;
    const uint16_t *cells = m->cells + (size_t)layer * m->w * m->h;
    /* The first tile on screen. Division rounds toward zero, which is only
     * wrong left of and above the map, where there are no tiles to miss. */
    int first_x = (g->cam_x + sx) / cell, first_y = (g->cam_y + sy) / cell;
    for (int my = first_y; my <= first_y + PULLI_SCREEN_H / cell; my++) {
        if (my < 0 || my >= m->h) continue;
        for (int mx = first_x; mx <= first_x + PULLI_SCREEN_W / cell; mx++) {
            if (mx < 0 || mx >= m->w) continue;
            uint16_t c = cells[my * m->w + mx];
            if (!(c & PULLI_TILE_MASK)) continue;         /* tile 0 is empty */
            pulli_spr(g, c & PULLI_TILE_MASK, mx * cell - sx, my * cell - sy, 1, 1,
                      c & PULLI_TILE_FLIP_X, c & PULLI_TILE_FLIP_Y);
        }
    }
}

/* Strip-wise index -> RGB565. On the RP2350 this runs into a small buffer
 * that is DMA'd to the panel while the next strip converts. The cost of
 * this loop is the number that decides whether 320x240 survives (SPEC §9). */
void pulli_scanout(const pulli_gfx *g, int y0, int rows, uint16_t *out) {
    const uint8_t *src = g->fb + (size_t)y0 * PULLI_SCREEN_W;
    size_t n = (size_t)rows * PULLI_SCREEN_W;
    for (size_t i = 0; i < n; i++) out[i] = g->shown[src[i] & PULLI_COLOR_MASK];
}
