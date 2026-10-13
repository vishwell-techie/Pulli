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

const char *pulli_map_check(pulli_blob b) {
    if (b.len < OORU_HEADER || memcmp(b.data, "ORU1", 4) != 0) return "not a map";
    uint32_t w = rd16(b.data + 4), h = rd16(b.data + 6), layers = b.data[8], flags = rd16(b.data + 10);
    if (layers < 1 || layers > PULLI_MAP_LAYERS) return "a map has one or two layers";
    if (w == 0 || h == 0 || w * h * layers > PULLI_MAP_CELLS_MAX) return "map is empty or too large";
    if (flags > PULLI_TILE_MASK + 1u) return "too many tile flags";
    if (b.len != OORU_HEADER + 2 * w * h * layers + flags) return "map size does not match its data";
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
}
