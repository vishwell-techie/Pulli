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

void pulli_print(pulli_gfx *g, const char *s, int x, int y, int c) {
    if (!g->font || !s) return;
    int ox = x;
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        if (*p == '\n') { x = ox; y += PULLI_SPRITE_CELL; continue; }
        if (*p < 32 || *p > 127) continue;
        const uint8_t *glyph = g->font + (*p - 32) * PULLI_SPRITE_CELL;
        for (int j = 0; j < PULLI_SPRITE_CELL; j++) {
            uint8_t row = glyph[j];
            for (int i = 0; i < PULLI_SPRITE_CELL; i++)
                if (row & (0x80u >> i)) put(g, x + i, y + j, c);
        }
        x += PULLI_SPRITE_CELL;
    }
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
