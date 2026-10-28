/* map.c — reading map.ooru (SPEC §2) into the working map.
 *
 * A game may change tiles with map.set(), so a loaded map is copied into
 * the engine's fixed working set; the tile flags never change and are read
 * in place from the package.
 */
#include "internal.h"
#include <string.h>

#define OORU_HEADER 12

static uint32_t rd16(const uint8_t *p) { return p[0] | ((uint32_t)p[1] << 8); }

/* The objects section (SPEC §2): walked to its end, every length inside
 * the blob. Returns where it ends, or 0 if it does not fit. */
static uint32_t objects_end(const uint8_t *p, uint32_t at, uint32_t len) {
#define NEED(n) do { if ((uint64_t)at + (n) > len) return 0; } while (0)
#define SHORT() do { NEED(1); at += 1u + p[at]; NEED(0); } while (0)
    uint32_t total = 0;
    NEED(2);
    uint32_t groups = rd16(p + at);
    at += 2;
    for (uint32_t g = 0; g < groups; g++) {
        SHORT();
        NEED(2);
        uint32_t n = rd16(p + at);
        at += 2;
        if ((total += n) > PULLI_MAP_OBJECTS_MAX) return 0;
        for (uint32_t i = 0; i < n; i++) {
            NEED(10);
            at += 10;
            SHORT();                                    /* name */
            SHORT();                                    /* type */
            NEED(1);
            uint32_t props = p[at++];
            for (uint32_t k = 0; k < props; k++) {
                SHORT();
                NEED(1);
                uint8_t kind = p[at++];
                if (kind == 0 || kind == 1) { NEED(4); at += 4; }
                else if (kind == 2) { NEED(1); at += 1; }
                else if (kind == 3) SHORT();
                else return 0;
            }
        }
    }
    return at;
#undef SHORT
#undef NEED
}

const char *pulli_map_check(pulli_blob b) {
    if (b.len < OORU_HEADER || memcmp(b.data, "ORU1", 4) != 0) return "not a map";
    uint32_t w = rd16(b.data + 4), h = rd16(b.data + 6), layers = b.data[8], flags = rd16(b.data + 10);
    if (layers < 1 || layers > PULLI_MAP_LAYERS) return "a map has one or two layers";
    if (w == 0 || h == 0 || w * h * layers > PULLI_MAP_CELLS_MAX) return "map is empty or too large";
    if (flags > PULLI_TILE_MASK + 1u) return "too many tile flags";
    if (b.data[9] > 1) return "map size does not match its data";
    uint32_t end = OORU_HEADER + 2 * w * h * layers + flags;
    if (b.data[9] == 1) {                               /* its objects follow */
        if (b.len < end || (end = objects_end(b.data, end, b.len)) == 0) return "map's objects are damaged";
    }
    if (b.len != end) return "map size does not match its data";
    return NULL;
}

void pulli_map_load(pulli_map *m, pulli_blob b) {
    uint32_t cells;
    m->w = (int)rd16(b.data + 4);
    m->h = (int)rd16(b.data + 6);
    m->layers = b.data[8];
    m->flag_count = (int)rd16(b.data + 10);
    cells = (uint32_t)(m->w * m->h * m->layers);
    for (uint32_t i = 0; i < cells; i++) m->cells[i] = (uint16_t)rd16(b.data + OORU_HEADER + 2 * i);
    m->flags = b.data + OORU_HEADER + 2 * cells;
    m->objects = b.data[9] == 1 ? m->flags + m->flag_count : NULL;
    m->objects_len = m->objects ? (uint32_t)(b.len - (m->objects - b.data)) : 0;
}
