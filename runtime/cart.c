/* cart.c — save data in a cartridge's own flash (SPEC §2, "Cartridges").
 * No platform dependencies: a port gives the flash's read, erase and
 * program, and this decides what goes where.
 *
 * The last 512 KB of the flash is the save area, cut into slots, each big
 * enough for one whole save. Saves are written in turn, a slot after the
 * newest, so wear is spread over the area. A slot is a header, then the
 * save; the header is written last, so a slot whose writing was cut short
 * (the cartridge pulled, the battery flat) has no valid header and the save
 * before it is still the newest. */
#include "internal.h"
#include <string.h>

#define SLOT_MAGIC  "SAV1"
#define SLOT_HEADER 16                  /* magic, number, length, CRC-32 of the save */

static uint32_t rd32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static void wr32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24);
}

uint32_t pulli_cart_slot_bytes(uint32_t save_size) {
    uint32_t n = SLOT_HEADER + save_size;
    return (n + PULLI_CART_SECTOR - 1) / PULLI_CART_SECTOR * PULLI_CART_SECTOR;
}

uint32_t pulli_cart_slots(uint32_t save_size) {
    return PULLI_CART_SAVE_AREA / pulli_cart_slot_bytes(save_size);
}

static uint32_t slot_at(const pulli_cart_flash *f, uint32_t save_size, uint32_t i) {
    return f->base + i * pulli_cart_slot_bytes(save_size);
}

/* The slot headers that look whole: their numbers, newest first. */
static int candidates(const pulli_cart_flash *f, uint32_t save_size, uint32_t *slot, uint32_t *number) {
    uint32_t slots = pulli_cart_slots(save_size);
    int n = 0;
    for (uint32_t i = 0; i < slots; i++) {
        uint8_t h[SLOT_HEADER];
        if (!f->read(slot_at(f, save_size, i), h, SLOT_HEADER)) continue;
        if (memcmp(h, SLOT_MAGIC, 4) != 0 || rd32(h + 8) > save_size) continue;
        int k = n++;
        for (; k > 0 && number[k - 1] < rd32(h + 4); k--) { slot[k] = slot[k - 1]; number[k] = number[k - 1]; }
        slot[k] = i;
        number[k] = rd32(h + 4);
    }
    return n;
}

int pulli_cart_save_read(const pulli_cart_flash *f, uint32_t save_size, void *blob, size_t max) {
    uint32_t slot[PULLI_CART_SAVE_AREA / PULLI_CART_SECTOR], number[PULLI_CART_SAVE_AREA / PULLI_CART_SECTOR];
    int n = candidates(f, save_size, slot, number);
    for (int k = 0; k < n; k++) {                    /* the newest save whose bytes are whole */
        uint8_t h[SLOT_HEADER];
        uint32_t at = slot_at(f, save_size, slot[k]);
        if (!f->read(at, h, SLOT_HEADER)) continue;
        uint32_t len = rd32(h + 8);
        if (len > max || !f->read(at + SLOT_HEADER, blob, len)) continue;
        if (pulli_crc32(blob, len) == rd32(h + 12)) return (int)len;
    }
    return -1;
}

bool pulli_cart_save_write(const pulli_cart_flash *f, uint32_t save_size, const void *blob, size_t len) {
    uint32_t slot[PULLI_CART_SAVE_AREA / PULLI_CART_SECTOR], number[PULLI_CART_SAVE_AREA / PULLI_CART_SECTOR];
    if (len > save_size) return false;
    int n = candidates(f, save_size, slot, number);
    uint32_t next = n ? (slot[0] + 1) % pulli_cart_slots(save_size) : 0;
    uint32_t at = slot_at(f, save_size, next);
    for (uint32_t s = 0; s < pulli_cart_slot_bytes(save_size); s += PULLI_CART_SECTOR)
        if (!f->erase(at + s)) return false;
    uint8_t h[SLOT_HEADER];
    memcpy(h, SLOT_MAGIC, 4);
    wr32(h + 4, n ? number[0] + 1 : 1);
    wr32(h + 8, (uint32_t)len);
    wr32(h + 12, pulli_crc32(blob, len));
    return f->program(at + SLOT_HEADER, blob, (uint32_t)len) && f->program(at, h, SLOT_HEADER);
}
