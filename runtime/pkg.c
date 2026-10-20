/* pkg.c — game package reader (SPEC §2). No platform dependencies.
 *
 * A package is either mapped (all of it addressable, as flash read in
 * place is) or read in parts through a function the port gives (a file, an
 * SD card, a cartridge). Opening it checks only its front: the header, the
 * entry table and the hash of every 64 KB block of the payload. Each block
 * is checked when it is first used, so a 64 MB cartridge starts at once and
 * still never runs a byte that was changed. Packages come from strangers,
 * so every offset and length is checked before it is used. */
#include "internal.h"
#include <stdlib.h>
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
    return pk->front + PULLI_PKG_HEADER + (size_t)i * PULLI_PKG_ENTRY;
}

static const uint8_t *hash_of(const pulli_pkg *pk, uint32_t block) {
    return pk->front + PULLI_PKG_HEADER + (size_t)pk->count * PULLI_PKG_ENTRY + (size_t)block * PULLI_PKG_HASH;
}

/* Reads bytes of the file: in place when mapped, else through the port. */
static bool fetch(const pulli_pkg *pk, uint32_t offset, void *dst, uint32_t len) {
    if (pk->base) { memcpy(dst, pk->base + offset, len); return true; }
    return pk->read(offset, dst, len);
}

static const char *fail_open(pulli_pkg *pk, const char *why) {
    pulli_pkg_close(pk);
    return why;
}

const char *pulli_pkg_open(pulli_pkg *pk, const void *data, size_t len, pulli_read_fn read) {
    uint8_t head[PULLI_PKG_HEADER];
    memset(pk, 0, sizeof(*pk));
    pk->base = data;
    pk->read = read;
    if (!data && !read) return "no package";
    if (len < PULLI_PKG_HEADER || !fetch(pk, 0, head, PULLI_PKG_HEADER) || memcmp(head, PULLI_PKG_MAGIC, 4) != 0)
        return "not a Pulli package";
    if (head[4] != PULLI_PKG_VERSION)
        return "unsupported package version";

    uint32_t count = (uint32_t)head[6] | ((uint32_t)head[7] << 8);
    uint32_t total = rd32(head + 8), payload = rd32(head + 16);
    if (total > len)
        return "package is truncated";
    if (total > PULLI_PKG_MAX_SIZE)
        return "package is larger than 64 MB";
    if (count > PULLI_PKG_MAX_ENTRIES)
        return "too many entries";
    if (payload > total || (payload & 3))
        return "the payload starts outside the package";
    uint32_t blocks = (total - payload + PULLI_PKG_BLOCK - 1) / PULLI_PKG_BLOCK;
    if (PULLI_PKG_HEADER + count * PULLI_PKG_ENTRY + blocks * PULLI_PKG_HASH > payload)
        return "entry table runs past the end of the package";

    /* The seal follows the package: its length, so one read can take it
     * and the front together when the package is not mapped. */
    uint8_t sh[PULLI_SEAL_HEADER];
    if (len - total < PULLI_SEAL_HEADER || !fetch(pk, total, sh, PULLI_SEAL_HEADER) ||
        memcmp(sh, PULLI_SEAL_MAGIC, 4) != 0)
        return "package has no licence and signature";
    if (sh[4] != PULLI_SEAL_VERSION)
        return "unsupported licence and signature version";
    uint32_t lic_len = (uint32_t)sh[8] | ((uint32_t)sh[9] << 8);
    uint32_t sig_len = (uint32_t)sh[10] | ((uint32_t)sh[11] << 8);
    if (lic_len + sig_len > len - total - PULLI_SEAL_HEADER)
        return "licence and signature are truncated";

    const uint8_t *seal;
    if (data) {
        pk->front = data;
        seal = (const uint8_t *)data + total + PULLI_SEAL_HEADER;
    } else {
        pk->own = malloc((size_t)payload + lic_len + sig_len);
        pk->scratch = malloc(PULLI_PKG_BLOCK);
        if (!pk->own || !pk->scratch) return fail_open(pk, "out of memory");
        if (!read(0, pk->own, payload) || !read(total + PULLI_SEAL_HEADER, pk->own + payload, lic_len + sig_len))
            return fail_open(pk, "the package could not be read");
        pk->front = pk->own;
        seal = pk->own + payload;
    }
    pk->size = total;
    pk->payload = payload;
    pk->blocks = blocks;
    pk->count = (uint16_t)count;
    pk->flags = head[5];
    if (pulli_crc32(pk->front + 16, payload - 16) != rd32(head + 12))
        return fail_open(pk, "checksum mismatch: package is corrupt");
    for (int i = 0; i < pk->count; i++) {
        const uint8_t *e = entry_at(pk, i);
        uint32_t off = rd32(e + 32), n = rd32(e + 36);
        if (off < payload || off > total || n > total - off || (off & 3))
            return fail_open(pk, "entry lies outside the package");
        if (e[0] == 0)
            return fail_open(pk, "entry has no name");
    }
    if (pk->flags & PULLI_PKG_ENCRYPTED)
        /* Needs the licence block unwrapped with a device key. */
        return fail_open(pk, "package is encrypted; this runtime cannot unwrap it yet");

    pk->licence_kind = sh[5];
    pk->signature_kind = sh[6];
    pk->licence.data = seal;
    pk->licence.len = lic_len;
    pk->signature.data = seal + lic_len;
    pk->signature.len = sig_len;

    /* Only the developer kinds exist so far. The store's kinds will add a
     * real signature and a licence tied to the buyer's devices. The front
     * holds a hash of every block, so signing it signs the whole package. */
    if (pk->licence_kind != PULLI_LICENCE_DEVELOPER)
        return fail_open(pk, "package carries a kind of licence this runtime does not know");
    if (pk->signature_kind != PULLI_SIGNATURE_DEVELOPER)
        return fail_open(pk, "package carries a kind of signature this runtime does not know");
    uint8_t digest[32];
    pulli_sha256(pk->front, payload, digest);
    if (sig_len != sizeof(digest) || memcmp(pk->signature.data, digest, sizeof(digest)) != 0)
        return fail_open(pk, "signature does not match: the package was changed after it was signed");
    return NULL;
}

void pulli_pkg_close(pulli_pkg *pk) {
    free(pk->own);
    free(pk->scratch);
    pk->own = pk->scratch = NULL;
    pk->front = NULL;
}

bool pulli_pkg_find(const pulli_pkg *pk, const char *name, pulli_entry *out) {
    size_t n = strlen(name);
    if (n == 0 || n > PULLI_PKG_NAME_MAX) return false;
    for (int i = 0; i < pk->count; i++) {
        const uint8_t *e = entry_at(pk, i);
        /* Names are NUL-padded and a 32-byte name has no terminator. */
        if (memcmp(e, name, n) != 0) continue;
        if (n < PULLI_PKG_NAME_MAX && e[n] != 0) continue;
        if (out) { out->offset = rd32(e + 32); out->len = rd32(e + 36); }
        return true;
    }
    return false;
}

void pulli_pkg_name(const pulli_pkg *pk, int i, char out[PULLI_PKG_NAME_MAX + 1]) {
    memcpy(out, entry_at(pk, i), PULLI_PKG_NAME_MAX);
    out[PULLI_PKG_NAME_MAX] = 0;
}

static bool block_good(const uint8_t *bytes, uint32_t len, const uint8_t *hash) {
    uint8_t digest[32];
    pulli_sha256(bytes, len, digest);
    return memcmp(digest, hash, sizeof(digest)) == 0;
}

const char *pulli_pkg_get(pulli_pkg *pk, uint32_t offset, uint32_t len, uint8_t *dst, const uint8_t **out) {
    if (offset < pk->payload || offset > pk->size || len > pk->size - offset)
        return "lies outside the package";
    *out = pk->base ? pk->base + offset : dst;
    if (len == 0) return NULL;
    uint32_t first = (offset - pk->payload) / PULLI_PKG_BLOCK;
    uint32_t last = (offset + len - 1 - pk->payload) / PULLI_PKG_BLOCK;
    for (uint32_t b = first; b <= last; b++) {
        uint32_t start = pk->payload + b * PULLI_PKG_BLOCK;
        uint32_t n = pk->size - start < PULLI_PKG_BLOCK ? pk->size - start : PULLI_PKG_BLOCK;
        if (pk->base) {
            /* Mapped bytes cannot change under us: each block is checked once. */
            if (pk->checked[b / 8] & (1u << (b % 8))) continue;
            if (!block_good(pk->base + start, n, hash_of(pk, b))) return "is damaged: a block does not match its hash";
            pk->checked[b / 8] |= (uint8_t)(1u << (b % 8));
            continue;
        }
        /* Read: every time, since what is read is not kept. A block wholly
         * wanted is read straight into place; one wanted in part goes
         * through the scratch block. */
        if (start >= offset && start + n <= offset + len) {
            uint8_t *at = dst + (start - offset);
            if (!pk->read(start, at, n)) return "could not be read";
            if (!block_good(at, n, hash_of(pk, b))) return "is damaged: a block does not match its hash";
        } else {
            if (!pk->read(start, pk->scratch, n)) return "could not be read";
            if (!block_good(pk->scratch, n, hash_of(pk, b))) return "is damaged: a block does not match its hash";
            uint32_t from = offset > start ? offset : start;
            uint32_t to = offset + len < start + n ? offset + len : start + n;
            memcpy(dst + (from - offset), pk->scratch + (from - start), to - from);
        }
    }
    return NULL;
}
