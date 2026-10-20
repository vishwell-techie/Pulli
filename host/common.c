#include "common.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

uint8_t *host_read_file(const char *path, size_t *len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    uint8_t *buf = NULL;
    long n;
    if (fseek(f, 0, SEEK_END) == 0 && (n = ftell(f)) >= 0 && fseek(f, 0, SEEK_SET) == 0 &&
        (buf = malloc((size_t)n + 1)) != NULL) {
        if (fread(buf, 1, (size_t)n, f) == (size_t)n) {
            *len = (size_t)n;
        } else {
            free(buf);
            buf = NULL;
        }
    }
    fclose(f);
    return buf;
}

static bool parse_list(const char *list, const char *const *names, uint32_t *bits) {
    *bits = 0;
    while (*list) {
        size_t n = strcspn(list, ",");
        int found = -1;
        for (int i = 0; names[i]; i++)
            if (strlen(names[i]) == n && strncmp(names[i], list, n) == 0) found = i;
        if (found < 0) return false;
        *bits |= 1u << found;
        list += n;
        if (*list == ',') list++;
    }
    return true;
}

bool host_parse_caps(const char *list, uint32_t *caps) {
    static const char *const names[] = { "video", "wifi", "cart", "rumble", "link", NULL };
    return parse_list(list, names, caps);
}

bool host_parse_buttons(const char *list, uint32_t *buttons) {
    static const char *const names[] = {
        "left", "right", "up", "down", "a", "b", "x", "y", "l", "r", "start", "select", NULL
    };
    return parse_list(list, names, buttons);
}

static char save_dir[768];

void host_set_save_dir(const char *dir) {
    snprintf(save_dir, sizeof(save_dir), "%s", dir ? dir : "");
}

/* The runtime has already restricted game ids to letters, digits, '.', '_'
 * and '-', not starting with '.', so an id cannot name another directory. */
static bool save_path(const char *game_id, char *out, size_t cap) {
    if (!save_dir[0]) return false;
    size_t n = strlen(save_dir);
    const char *sep = (save_dir[n - 1] == '/' || save_dir[n - 1] == '\\') ? "" : "/";
    return snprintf(out, cap, "%s%s%s.sav", save_dir, sep, game_id) < (int)cap;
}

int host_save_read(const char *game_id, void *blob, size_t max) {
    char path[1024];
    if (!save_path(game_id, path, sizeof(path))) return -1;
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    size_t n = fread(blob, 1, max, f);
    fclose(f);
    return (int)n;
}

bool host_save_write(const char *game_id, const void *blob, size_t len) {
    char path[1024];
    if (!save_dir[0]) return true;
    if (!save_path(game_id, path, sizeof(path))) return false;
    FILE *f = fopen(path, "wb");
    if (!f) return false;
    bool ok = fwrite(blob, 1, len, f) == len;
    return fclose(f) == 0 && ok;
}

bool host_use_link(pulli_backend *backend, const char *port, bool step) {
    int n = atoi(port);
    if (n < 1024 || n > 65535 || !host_link_open(n, step)) return false;
    backend->caps |= PULLI_CAP_LINK;
    backend->link_poll = host_link_poll;
    backend->link_send = host_link_send;
    backend->link_recv = host_link_recv;
    return true;
}

void host_log(const char *msg) {
    printf("%s\n", msg);
    fflush(stdout);
}

void host_halves(void (*fn)(void *arg, int half), void *arg) {
    fn(arg, 1);
    fn(arg, 0);
}

/* ---- a package read in parts, and a cartridge -------------------------- */
static FILE *pkg_file;

bool host_open_package(const char *path, size_t *len) {
    long n;
    if (pkg_file) fclose(pkg_file);
    pkg_file = fopen(path, "rb");
    if (!pkg_file || fseek(pkg_file, 0, SEEK_END) != 0 || (n = ftell(pkg_file)) < 0) return false;
    *len = (size_t)n;
    return true;
}

bool host_pkg_read(uint32_t offset, void *dst, uint32_t len) {
    return pkg_file && fseek(pkg_file, (long)offset, SEEK_SET) == 0 && fread(dst, 1, len, pkg_file) == len;
}

static long cart_cut = -1;              /* bytes the first save may still write, or -1 */
static pulli_cart_flash cart_flash;

static bool cart_erase(uint32_t offset) {
    uint8_t ff[PULLI_CART_SECTOR];
    memset(ff, 0xFF, sizeof(ff));
    return fseek(pkg_file, (long)offset, SEEK_SET) == 0 && fwrite(ff, 1, sizeof(ff), pkg_file) == sizeof(ff);
}

/* NOR flash: programming only clears bits. A cut cartridge stops writing
 * part way, and every write after the cut fails. */
static bool cart_program(uint32_t offset, const void *src, uint32_t len) {
    uint8_t buf[4096];
    const uint8_t *s = src;
    while (len > 0) {
        uint32_t n = len < sizeof(buf) ? len : (uint32_t)sizeof(buf);
        bool cut = false;
        if (cart_cut >= 0 && (long)n > cart_cut) { n = (uint32_t)cart_cut; cut = true; }
        if (!host_pkg_read(offset, buf, n)) return false;
        for (uint32_t i = 0; i < n; i++) buf[i] &= s[i];
        if (fseek(pkg_file, (long)offset, SEEK_SET) != 0 || fwrite(buf, 1, n, pkg_file) != n) return false;
        if (cart_cut >= 0) cart_cut -= (long)n;
        if (cut) return false;
        offset += n; s += n; len -= n;
    }
    return true;
}

bool host_open_cart(const char *path, long cut, size_t *len) {
    long n;
    if (pkg_file) fclose(pkg_file);
    pkg_file = fopen(path, "r+b");
    if (!pkg_file || fseek(pkg_file, 0, SEEK_END) != 0 || (n = ftell(pkg_file)) < 0 ||
        (unsigned long)n < PULLI_CART_SAVE_AREA)
        return false;
    cart_cut = cut;
    cart_flash.base = (uint32_t)n - PULLI_CART_SAVE_AREA;
    cart_flash.read = host_pkg_read;
    cart_flash.erase = cart_erase;
    cart_flash.program = cart_program;
    *len = (size_t)cart_flash.base;      /* the package may not reach into the save area */
    return true;
}

/* The slots are sized by the game's save_size, which the engine gives as
 * `max` when it reads the save at boot, before any write. */
static uint32_t cart_save_size;

int host_cart_save_read(const char *game_id, void *blob, size_t max) {
    (void)game_id;
    cart_save_size = (uint32_t)max;
    return pulli_cart_save_read(&cart_flash, cart_save_size, blob, max);
}

bool host_cart_save_write(const char *game_id, const void *blob, size_t len) {
    (void)game_id;
    bool ok = cart_save_size && pulli_cart_save_write(&cart_flash, cart_save_size, blob, len);
    fflush(pkg_file);
    return ok;
}
