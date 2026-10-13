/* pulli.h — Pulli runtime core, spec v0.1
 *
 * This header and everything else in runtime/ is shared verbatim between the
 * desktop host and the RP2350 firmware. Nothing here may include a platform
 * header: the pixels produced on a laptop are the pixels produced on the
 * device. A port supplies a pulli_backend and a main loop, nothing more.
 */
#ifndef PULLI_RUNTIME_H
#define PULLI_RUNTIME_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#define PULLI_SPEC_VERSION    1
#define PULLI_SCREEN_W        320
#define PULLI_SCREEN_H        240
#define PULLI_FB_BYTES        (PULLI_SCREEN_W * PULLI_SCREEN_H)  /* 8-bit indexed: 76800 */
#define PULLI_PALETTE_LEN     64   /* locked. A power of two: colour indices wrap with a mask */
#define PULLI_COLOR_MASK      (PULLI_PALETTE_LEN - 1)
#define PULLI_SPRITE_CELL     8    /* base cell, see SPEC §8.1 */
#define PULLI_TICK_HZ         60
#define PULLI_LUA_HEAP_MAX_KB 256  /* SPEC §1 memory budget */
#define PULLI_SAVE_MAX        65536
#define PULLI_ATLAS_MAX       (128 * 1024)  /* resident sprite atlas, SPEC §1 */
#define PULLI_SCANOUT_ROWS    12   /* one strip: 12 rows x 320 px x 2 B = 7680 B */

/* ---- buttons ------------------------------------------------------- */
typedef enum {
    PULLI_BTN_LEFT = 0, PULLI_BTN_RIGHT, PULLI_BTN_UP, PULLI_BTN_DOWN,
    PULLI_BTN_A, PULLI_BTN_B, PULLI_BTN_X, PULLI_BTN_Y,
    PULLI_BTN_L, PULLI_BTN_R, PULLI_BTN_START, PULLI_BTN_SELECT,
    PULLI_BTN_COUNT
} pulli_btn;

/* ---- optional hardware, queried by games with sys.has() (SPEC §3a) -- */
#define PULLI_CAP_VIDEO   (1u << 0)
#define PULLI_CAP_WIFI    (1u << 1)
#define PULLI_CAP_CART    (1u << 2)
#define PULLI_CAP_RUMBLE  (1u << 3)
#define PULLI_CAP_LINK    (1u << 4)

/* ---- graphics state ------------------------------------------------ */
typedef struct {
    uint8_t  fb[PULLI_FB_BYTES];           /* indexed framebuffer            */
    uint16_t palette[PULLI_PALETTE_LEN];   /* RGB565, as the game set it      */
    uint16_t shown[PULLI_PALETTE_LEN];     /* palette with fade applied       */
    uint8_t  pal_map[PULLI_PALETTE_LEN];   /* draw-time index remap (pal())   */
    bool     transparent[PULLI_PALETTE_LEN];
    int      fade_k;                       /* 32 = full brightness, 0 = black */
    int      cam_x, cam_y;
    int      clip_x, clip_y, clip_w, clip_h;
    /* sprite atlas: linear, 8x8 cells, atlas_w is a multiple of 8 */
    const uint8_t *atlas;
    int      atlas_w, atlas_h;
    const uint8_t *font;                   /* 8x8 1bpp, 96 glyphs from ' '   */
} pulli_gfx;

/* ---- sprite/tile data ---------------------------------------------- */
typedef struct {
    const uint8_t *tiles;   /* layer data, tile indices, row-major */
    int w, h;               /* in tiles */
} pulli_layer;

/* ---- what the Lua API reads and writes ----------------------------- */
typedef struct {
    pulli_gfx   g;
    uint32_t    btn_state, btn_prev;
    uint32_t    frame;
    pulli_layer layers[2];
} pulli_ctx;

/* ---- gfx primitives (pure, no platform deps) ----------------------- */
extern const uint8_t pulli_font8x8[96 * 8];
void pulli_default_palette(uint16_t out[PULLI_PALETTE_LEN]);

void    pulli_gfx_init (pulli_gfx *g);    /* default palette and font, cleared screen */
void    pulli_cls      (pulli_gfx *g, int c);
void    pulli_pset     (pulli_gfx *g, int x, int y, int c);
uint8_t pulli_pget     (const pulli_gfx *g, int x, int y);
void    pulli_line     (pulli_gfx *g, int x0, int y0, int x1, int y1, int c);
void    pulli_rect     (pulli_gfx *g, int x, int y, int w, int h, int c);
void    pulli_rectfill (pulli_gfx *g, int x, int y, int w, int h, int c);
void    pulli_circ     (pulli_gfx *g, int cx, int cy, int r, int c);
void    pulli_circfill (pulli_gfx *g, int cx, int cy, int r, int c);
void    pulli_spr      (pulli_gfx *g, int n, int x, int y, int cw, int ch,
                        bool flip_x, bool flip_y);
void    pulli_sspr     (pulli_gfx *g, int sx, int sy, int sw, int sh,
                        int dx, int dy, int dw, int dh);
void    pulli_print    (pulli_gfx *g, const char *s, int x, int y, int c);
void    pulli_camera   (pulli_gfx *g, int x, int y);
void    pulli_clip     (pulli_gfx *g, int x, int y, int w, int h);
void    pulli_pal      (pulli_gfx *g, int a, int b);      /* a < 0 resets */
void    pulli_palt     (pulli_gfx *g, int c, bool t);     /* c < 0 resets */
void    pulli_fade     (pulli_gfx *g, float amount);      /* 0 = normal, 1 = black */
void    pulli_map_draw (pulli_ctx *ctx, int layer, int sx, int sy);

/* Scanout: convert one strip of indexed pixels to RGB565.
 * The device DMAs the result straight to the panel; the host uploads it as
 * a texture. Strip-wise so the MCU never needs a second full buffer. */
void    pulli_scanout  (const pulli_gfx *g, int y0, int rows, uint16_t *out);

/* ---- game package (.pulli), SPEC §2 -------------------------------- */
#define PULLI_PKG_MAGIC        "PULI"
#define PULLI_PKG_VERSION      1
#define PULLI_PKG_HEADER       16
#define PULLI_PKG_ENTRY        40
#define PULLI_PKG_NAME_MAX     32
#define PULLI_PKG_MAX_ENTRIES  64
#define PULLI_PKG_ENCRYPTED    0x01
#define PULLI_PKG_SIGNED       0x02
#define PULLI_PKG_DEVBUILD     0x04

typedef struct { const uint8_t *data; uint32_t len; } pulli_blob;

/* A package is read in place and never copied, so `data` must outlive it.
 * On the device that memory is cartridge or XIP flash. */
typedef struct {
    const uint8_t *base;
    uint32_t size;
    uint16_t count;
    uint8_t  flags;
} pulli_pkg;

/* Validates the whole container. Returns NULL on success, else the reason. */
const char *pulli_pkg_open(pulli_pkg *pk, const void *data, size_t len);
bool        pulli_pkg_find(const pulli_pkg *pk, const char *name, pulli_blob *out);
uint32_t    pulli_crc32(const uint8_t *data, size_t len);

/* ---- backend hooks a port provides --------------------------------- */
/* Any hook may be NULL: missing hardware degrades silently (SPEC §3a). */
typedef struct {
    uint32_t caps;                                    /* PULLI_CAP_* present  */
    void (*present)(const uint16_t *rgb565, int y0, int rows);
    void (*audio_sfx)(int n, int channel);
    void (*audio_music)(int n, int fade_ms);          /* n < 0 stops          */
    /* Save data is one blob per game, keyed by manifest id. */
    int  (*save_read)(const char *game_id, void *blob, size_t max); /* <0: none */
    bool (*save_write)(const char *game_id, const void *blob, size_t len);
    void (*log)(const char *msg);
} pulli_backend;

/* ---- engine --------------------------------------------------------- */
typedef enum { PULLI_SAVE_NONE = 0, PULLI_SAVE_SD, PULLI_SAVE_CART } pulli_save_target;

typedef struct {
    char id[64];            /* reverse-DNS, unique */
    char title[48];
    char author[48];
    char version[16];
    int  spec;
    int  save_size;         /* bytes */
    int  lua_heap_kb;
    pulli_save_target save_target;
} pulli_manifest;

struct lua_State;

/* One running game. Only one engine may be live at a time. */
typedef struct {
    pulli_ctx            ctx;
    pulli_pkg            pkg;
    pulli_manifest       manifest;
    const pulli_backend *backend;
    struct lua_State    *L;
    size_t   heap_used, heap_peak, heap_limit;   /* Lua heap, bytes */
    uint8_t *save;                               /* save blob, save_size bytes */
    uint32_t save_len;
    bool     save_dirty;
    bool     running;
    char     error[512];                         /* why boot/update/draw failed */
} pulli_engine;

/* Loads the manifest and main.lua from the package and calls init().
 * Each call returns false once the game has failed; see engine->error. */
bool pulli_boot    (pulli_engine *e, const void *pkg, size_t len, const pulli_backend *backend);
bool pulli_update  (pulli_engine *e, uint32_t buttons);   /* one fixed 1/60 s step */
bool pulli_draw    (pulli_engine *e);
void pulli_present (pulli_engine *e);                     /* scanout to backend->present */
void pulli_shutdown(pulli_engine *e);                     /* commits save data */

#endif /* PULLI_RUNTIME_H */
