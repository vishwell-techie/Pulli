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
#define PULLI_REPEAT_DELAY    24   /* frames a button is held before btnp() repeats */
#define PULLI_REPEAT_RATE     6    /* frames between repeats after that */
#define PULLI_LUA_HEAP_MAX_KB 256  /* SPEC §1 memory budget */
#define PULLI_SAVE_MAX        65536
#define PULLI_SAVE_INTERVAL_MIN  10   /* seconds: the shortest wait the game may ask for between automatic writes */
#define PULLI_SAVE_INTERVAL_MAX  3600
#define PULLI_SAVE_INTERVAL_DEF  60   /* when a game says "auto" and nothing else */
#define PULLI_SAVE_TABLE_DEPTH 4   /* tables inside tables, at most */
#define PULLI_ATLAS_MAX       (128 * 1024)  /* resident sprite atlas, SPEC §1 */
#define PULLI_MAP_LAYERS      2
#define PULLI_MAP_CELLS_MAX   32768         /* tiles in the loaded map, all layers: 64 KB (SPEC §1) */
#define PULLI_TILE_MASK       0x3FFF        /* a map cell: the tile number... */
#define PULLI_TILE_FLIP_Y     0x4000        /* ...and how it is turned over */
#define PULLI_TILE_FLIP_X     0x8000
#define PULLI_SCANOUT_ROWS    12   /* one strip: 12 rows x 320 px x 2 B = 7680 B */
#define PULLI_AUDIO_RATE      44100
#define PULLI_AUDIO_FRAMES    (PULLI_AUDIO_RATE / PULLI_TICK_HZ)  /* stereo frames mixed per game frame: 735 */
#define PULLI_SFX_CHANNELS    8    /* sound effects at once; music is mixed on top */
#define PULLI_CLIP_MAX        256  /* sounds in one bank */
#define PULLI_CLIP_RATE_MIN   4000
#define PULLI_CLIP_RATE_MAX   48000
#define PULLI_CLIP_FRAMES_MAX 0x0FFFFFFF
#define PULLI_LINK_MSG_MAX    64   /* bytes in one link message */
#define PULLI_LINK_SENDS      8    /* messages a game may send per frame */

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
    uint8_t  sprite_lut[PULLI_PALETTE_LEN]; /* a sprite pixel's colour on screen, or 0xFF if not drawn: pal_map and transparent together, kept by pal() and palt() */
    int      fade_k;                       /* 32 = full brightness, 0 = black */
    int      cam_x, cam_y;
    int      clip_x, clip_y, clip_w, clip_h;
    /* sprite atlas: linear, 8x8 cells, atlas_w is a multiple of 8 */
    const uint8_t *atlas;
    int      atlas_w, atlas_h;
    const uint8_t *font;                   /* 8x8 1bpp, 96 glyphs from ' '   */
} pulli_gfx;

/* ---- the loaded map (SPEC §3 "Map") --------------------------------- */
typedef struct {
    uint16_t cells[PULLI_MAP_CELLS_MAX];    /* layer 0 row by row, then layer 1 */
    int      w, h, layers;                  /* in tiles; layers is 0 when nothing is loaded */
    const uint8_t *flags;                   /* one byte per tile number, read in place */
    int      flag_count;
} pulli_map;

/* ---- what the Lua API reads and writes ----------------------------- */
typedef struct {
    pulli_gfx   g;
    uint32_t    btn_state;
    uint32_t    btn_held[PULLI_BTN_COUNT];   /* frames each button has been down */
    uint32_t    frame;
    pulli_map   map;
} pulli_ctx;

/* ---- gfx primitives (pure, no platform deps) ----------------------- */
extern const uint8_t pulli_font8x8[96 * 8];

/* Tamil: whole syllables as pixels (font_ta.c, generated from font_ta.txt;
 * SPEC §3 "Text"), sorted by their letters. Every glyph is
 * pulli_font_ta_rows rows tall; its row pulli_font_ta_above lines up with
 * row 0 of an English letter. */
typedef struct {
    uint32_t letters[4];        /* what it draws: 1 to 4 characters, the rest 0 */
    uint8_t  width;             /* columns of pixels */
    int8_t   kern;              /* where its first column is, from the pen */
    uint8_t  adv;               /* how far the pen moves after it */
    uint32_t offset;            /* its rows in pulli_font_ta_bits, (width + 7) / 8 bytes each, bit 7 leftmost */
} pulli_ta_glyph;
extern const pulli_ta_glyph pulli_font_ta[];
extern const uint8_t pulli_font_ta_bits[];
extern const int pulli_font_ta_count, pulli_font_ta_rows, pulli_font_ta_above;
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
/* Text is UTF-8: English from the 8x8 font, Tamil laid out as SPEC §3
 * "Text" says. Returns where the next letter would go on the last line. */
int     pulli_print    (pulli_gfx *g, const char *s, size_t len, int x, int y, int c);
void    pulli_text_size(const char *s, size_t len, int *w, int *h);  /* widest line; all lines */
void    pulli_camera   (pulli_gfx *g, int x, int y);
void    pulli_clip     (pulli_gfx *g, int x, int y, int w, int h);
void    pulli_pal      (pulli_gfx *g, int a, int b);      /* a < 0 resets */
void    pulli_palt     (pulli_gfx *g, int c, bool t);     /* c < 0 resets */
void    pulli_fade     (pulli_gfx *g, float amount);      /* 0 = normal, 1 = black */
void    pulli_set_colour(pulli_gfx *g, int c, int r, int gr, int b); /* c's colour, 0..255 each */
void    pulli_load_palette(pulli_gfx *g, const uint16_t rgb565[PULLI_PALETTE_LEN]);
void    pulli_map_draw (pulli_gfx *g, const pulli_map *m, int layer, int sx, int sy);

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

/* The seal: a licence and a signature that follow the package, outside its
 * size and checksum, so they can be replaced without touching the package. */
#define PULLI_SEAL_MAGIC       "SEAL"
#define PULLI_SEAL_VERSION     1
#define PULLI_SEAL_HEADER      12
#define PULLI_LICENCE_DEVELOPER   0   /* runs on any device; not for sale */
#define PULLI_SIGNATURE_DEVELOPER 0   /* SHA-256 of the package: catches damage, proves nothing */

typedef struct { const uint8_t *data; uint32_t len; } pulli_blob;

/* A package is read in place and never copied, so `data` must outlive it.
 * On the device that memory is cartridge or XIP flash. */
typedef struct {
    const uint8_t *base;
    uint32_t size;
    uint16_t count;
    uint8_t  flags;
    uint8_t  licence_kind, signature_kind;      /* PULLI_LICENCE_*, PULLI_SIGNATURE_* */
    pulli_blob licence, signature;
} pulli_pkg;

/* Validates the whole container. Returns NULL on success, else the reason. */
const char *pulli_pkg_open(pulli_pkg *pk, const void *data, size_t len);
bool        pulli_pkg_find(const pulli_pkg *pk, const char *name, pulli_blob *out);
uint32_t    pulli_crc32(const uint8_t *data, size_t len);

/* ---- audio (SPEC §3 "Audio") --------------------------------------- */
/* One sound being played. */
typedef struct {
    bool     active, looping, last;         /* last: nxt is the silence after the end */
    const uint8_t *data;
    uint32_t frames, loop, at;              /* at: the next frame to read */
    uint32_t frac, step;                    /* position between cur and nxt, 16.16 */
    uint8_t  channels, adpcm;
    int16_t  cur[2], nxt[2];
    int16_t  pred[2], loop_pred[2];         /* ADPCM decoder state, now and at the loop point */
    uint8_t  index[2], loop_index[2];
    int32_t  gain, gain_step;               /* music fades; full volume is 1 << 24 */
    uint32_t started;                       /* order of starting, to find the oldest */
} pulli_voice;

typedef struct {
    pulli_blob  sfx, music;                 /* sfx.oli and music.isai, read in place */
    uint16_t    sfx_count, music_count;
    pulli_voice ch[PULLI_SFX_CHANNELS];
    pulli_voice tune[2];                    /* [0] the music playing, [1] music fading out */
    uint32_t    serial;
    bool        music_paused;
    int16_t     out[PULLI_AUDIO_FRAMES * 2];
} pulli_audio;

/* Mixes the next `frames` stereo frames (left, right, left, ...). The
 * engine calls this once per game frame; a port only receives the result. */
void pulli_audio_mix(pulli_audio *a, int16_t *out, int frames);

/* ---- console-to-console link (SPEC §3, "Link") --------------------- */
typedef enum {
    PULLI_LINK_OFF = 0,     /* no link hardware */
    PULLI_LINK_WAITING,     /* hardware present, no other console answering */
    PULLI_LINK_CONNECTED
} pulli_link_state;

/* ---- backend hooks a port provides --------------------------------- */
/* Any hook may be NULL: missing hardware degrades silently (SPEC §3a). */
typedef struct {
    uint32_t caps;                                    /* PULLI_CAP_* present  */
    void (*present)(const uint16_t *rgb565, int y0, int rows);
    /* Called once per game frame with PULLI_AUDIO_FRAMES stereo frames of
     * 16-bit sound at PULLI_AUDIO_RATE, already mixed. */
    void (*audio)(const int16_t *stereo, int frames);
    /* Save data is one blob per game, keyed by manifest id. */
    int  (*save_read)(const char *game_id, void *blob, size_t max); /* <0: none */
    bool (*save_write)(const char *game_id, const void *blob, size_t len);
    void (*log)(const char *msg);
    /* A clock in microseconds, wrapping at 2^32. Only for stat("fps") and
     * stat("cpu"), which are for the developer; nothing else uses it, so
     * the game itself stays deterministic. */
    uint32_t (*micros)(void);
    /* Link. The port carries whole messages, in order and without loss
     * while connected. link_poll is called once at the start of every
     * frame; it returns the state and, when connected, which side this
     * console is (1 or 2, never the same on both). */
    pulli_link_state (*link_poll)(int *side);
    bool (*link_send)(const void *msg, size_t len);
    int  (*link_recv)(void *msg, size_t max);         /* length, or <0: none */
} pulli_backend;

/* ---- engine --------------------------------------------------------- */
typedef enum { PULLI_SAVE_NONE = 0, PULLI_SAVE_SD, PULLI_SAVE_CART } pulli_save_target;
/* When save data reaches storage. Either way it is written when the game
 * ends and whenever the game calls save_commit(). */
typedef enum { PULLI_SAVE_ON_EXIT = 0, PULLI_SAVE_AUTO } pulli_save_mode;

typedef struct {
    char id[64];            /* reverse-DNS, unique */
    char title[48];
    char author[48];
    char version[16];
    int  spec;
    int  save_size;         /* bytes */
    int  lua_heap_kb;
    pulli_save_target save_target;
    pulli_save_mode   save_mode;
    int               save_interval;     /* seconds between automatic writes */
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
    uint32_t save_written;                       /* frame of the last automatic write */
    pulli_audio audio;
    uint16_t    base_palette[PULLI_PALETTE_LEN]; /* the game's own colours: palette() puts them back */
    uint32_t    clock_frames, clock_since;       /* updates counted, and when counting began */
    uint32_t    fps;                             /* updates a second, measured once a second */
    uint32_t    work_us;                         /* this frame's update time so far, in microseconds */
    uint32_t    cpu;                             /* percent of the frame's time used, last frame */
    pulli_link_state link_state;                 /* as of this frame */
    int      link_side;                          /* 1 or 2 while connected */
    int      link_sent;                          /* messages sent this frame */
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
