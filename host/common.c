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
