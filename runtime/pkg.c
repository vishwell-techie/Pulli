/* pkg.c — game package reader (SPEC §2). No platform dependencies.
 *
 * A package is parsed in place: nothing is copied, entries are returned as
 * pointers into the caller's memory. That is what lets cartridge flash be
 * read through XIP instead of being loaded into RAM. Packages come from
 * strangers, so every offset and length is checked before it is used. */
#include "pulli.h"
#include <string.h>

static uint32_t rd32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

/* CRC-32 (IEEE 802.3, the zlib one), four bits at a time. */
uint32_t pulli_crc32(const uint8_t *data, size_t len) {
    static const uint32_t T[16] = {
        0x00000000, 0x1DB71064, 0x3B6E20C8, 0x26D930AC, 0x76DC4190, 0x6B6B51F4,
        0x4DB26158, 0x5005713C, 0xEDB88320, 0xF00F9344, 0xD6D6A3E8, 0xCB61B38C,
        0x9B64C2B0, 0x86D3D2D4, 0xA00AE278, 0xBDBDF21C
    };
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < len; i++) {
        c ^= data[i];
        c = T[c & 15] ^ (c >> 4);
        c = T[c & 15] ^ (c >> 4);
    }
    return c ^ 0xFFFFFFFFu;
}

static const uint8_t *entry_at(const pulli_pkg *pk, int i) {
    return pk->base + PULLI_PKG_HEADER + (size_t)i * PULLI_PKG_ENTRY;
}

const char *pulli_pkg_open(pulli_pkg *pk, const void *data, size_t len) {
    const uint8_t *b = data;
    memset(pk, 0, sizeof(*pk));

    if (!b || len < PULLI_PKG_HEADER || memcmp(b, PULLI_PKG_MAGIC, 4) != 0)
        return "not a Pulli package";
    if (b[4] != PULLI_PKG_VERSION)
        return "unsupported package version";

    uint32_t count = (uint32_t)b[6] | ((uint32_t)b[7] << 8);
    uint32_t total = rd32(b + 8);
    if (total > len)
        return "package is truncated";
    if (count > PULLI_PKG_MAX_ENTRIES)
        return "too many entries";
    uint32_t table_end = PULLI_PKG_HEADER + count * PULLI_PKG_ENTRY;
    if (table_end > total)
        return "entry table runs past the end of the package";
    if (pulli_crc32(b + PULLI_PKG_HEADER, total - PULLI_PKG_HEADER) != rd32(b + 12))
        return "checksum mismatch: package is corrupt";

    pk->base = b;
    pk->size = total;
    pk->count = (uint16_t)count;
    pk->flags = b[5];
    for (int i = 0; i < pk->count; i++) {
        const uint8_t *e = entry_at(pk, i);
        uint32_t off = rd32(e + 32), n = rd32(e + 36);
        if (off < table_end || off > total || n > total - off || (off & 3))
            return "entry lies outside the package";
        if (e[0] == 0)
            return "entry has no name";
    }
    if (pk->flags & PULLI_PKG_ENCRYPTED)
        /* Needs the licence block unwrapped with a device key. */
        return "package is encrypted; this runtime cannot unwrap it yet";
    return NULL;
}

bool pulli_pkg_find(const pulli_pkg *pk, const char *name, pulli_blob *out) {
    size_t n = strlen(name);
    if (n == 0 || n > PULLI_PKG_NAME_MAX) return false;
    for (int i = 0; i < pk->count; i++) {
        const uint8_t *e = entry_at(pk, i);
        /* Names are NUL-padded and a 32-byte name has no terminator. */
        if (memcmp(e, name, n) != 0) continue;
        if (n < PULLI_PKG_NAME_MAX && e[n] != 0) continue;
        if (out) { out->data = pk->base + rd32(e + 32); out->len = rd32(e + 36); }
        return true;
    }
    return false;
}
