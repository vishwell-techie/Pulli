/* headless_main.c — runs a game with no window, for tests and automation.
 *
 *   pulli-headless <game.pulli> [options]
 *     --frames N        frames to run (default 60)
 *     --hold a,left     buttons held down for the whole run
 *     --tap a@1,start@90  buttons pressed for one frame each (frames count from 1)
 *     --caps wifi,cart  optional hardware reported through sys.has()
 *     --link PORT       link to another host started with the same port
 *     --saves DIR       keep save data in DIR (default: discarded on exit)
 *     --dump-fb FILE    write the final indexed framebuffer, 76800 bytes
 *     --dump-rgb FILE   write the final screen as RGB565, little-endian
 *   pulli-headless --maths-check
 *     run the maths self-check (runtime/pmath.h) and print the result
 *
 * Game dbg() output goes to stdout; everything else goes to stderr. Exits 0
 * if the game ran every frame, 1 if it failed, 2 on a usage error. */
#include "common.h"
#include "pmath.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static pulli_engine engine;
static uint16_t screen[PULLI_FB_BYTES];

static void present(const uint16_t *rgb565, int y0, int rows) {
    memcpy(screen + (size_t)y0 * PULLI_SCREEN_W, rgb565,
           (size_t)rows * PULLI_SCREEN_W * sizeof(uint16_t));
}

static bool write_file(const char *path, const uint8_t *data, size_t len) {
    FILE *f = fopen(path, "wb");
    if (!f) return false;
    bool ok = fwrite(data, 1, len, f) == len;
    return fclose(f) == 0 && ok;
}

#define MAX_TAPS 64
static struct { long frame; uint32_t buttons; } taps[MAX_TAPS];
static int tap_count;

/* "a@1,start@90" */
static bool parse_taps(const char *list) {
    while (*list) {
        char name[16];
        size_t n = strcspn(list, "@,");
        if (n == 0 || list[n] != '@' || n >= sizeof(name) || tap_count == MAX_TAPS) return false;
        memcpy(name, list, n);
        name[n] = 0;
        char *end;
        long frame = strtol(list + n + 1, &end, 10);
        if (end == list + n + 1 || frame < 1 || !host_parse_buttons(name, &taps[tap_count].buttons))
            return false;
        taps[tap_count++].frame = frame;
        list = *end == ',' ? end + 1 : end;
        if (*end && *end != ',') return false;
    }
    return true;
}

static int usage(void) {
    fprintf(stderr,
        "usage: pulli-headless <game.pulli> [--frames N] [--hold BUTTONS] [--tap BUTTON@FRAME,...]\n"
        "                      [--caps CAPS] [--link PORT]\n"
        "                      [--saves DIR] [--dump-fb FILE] [--dump-rgb FILE]\n");
    return 2;
}

int main(int argc, char **argv) {
    const char *game = NULL, *dump_fb = NULL, *dump_rgb = NULL;
    long frames = 60;
    uint32_t held = 0, caps = 0;
    pulli_backend backend = { 0 };
    backend.present = present;
    backend.save_read = host_save_read;
    backend.save_write = host_save_write;
    backend.log = host_log;

    if (argc == 2 && !strcmp(argv[1], "--maths-check")) {
        uint32_t sum = pulli_math_check();
        printf("%08x %08x\n", (unsigned)sum, (unsigned)PULLI_MATH_CHECK);
        return sum == PULLI_MATH_CHECK ? 0 : 1;
    }
    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        const char *v = i + 1 < argc ? argv[i + 1] : NULL;
        if (a[0] != '-') { if (game) return usage(); game = a; continue; }
        if (!v) return usage();
        i++;
        if      (!strcmp(a, "--frames"))   frames = atol(v);
        else if (!strcmp(a, "--saves"))    host_set_save_dir(v);
        else if (!strcmp(a, "--dump-fb"))  dump_fb = v;
        else if (!strcmp(a, "--dump-rgb")) dump_rgb = v;
        else if (!strcmp(a, "--hold"))     { if (!host_parse_buttons(v, &held)) return usage(); }
        else if (!strcmp(a, "--tap"))      { if (!parse_taps(v)) return usage(); }
        else if (!strcmp(a, "--caps"))     { if (!host_parse_caps(v, &caps)) return usage(); }
        else if (!strcmp(a, "--link"))     { if (!host_use_link(&backend, v, true)) return usage(); }
        else return usage();
    }
    if (!game || frames < 0) return usage();
    backend.caps |= caps;

    size_t len;
    uint8_t *data = host_read_file(game, &len);
    if (!data) { fprintf(stderr, "pulli-headless: cannot read %s\n", game); return 2; }

    bool ok = pulli_boot(&engine, data, len, &backend);
    long done = 0;
    while (ok && done < frames) {
        uint32_t buttons = held;
        for (int i = 0; i < tap_count; i++)
            if (taps[i].frame == done + 1) buttons |= taps[i].buttons;
        ok = pulli_update(&engine, buttons) && pulli_draw(&engine);
        if (ok) done++;
    }

    pulli_present(&engine);
    if (dump_fb && !write_file(dump_fb, engine.ctx.g.fb, PULLI_FB_BYTES))
        { fprintf(stderr, "pulli-headless: cannot write %s\n", dump_fb); ok = false; }
    if (dump_rgb) {
        static uint8_t le[PULLI_FB_BYTES * 2];
        for (size_t i = 0; i < PULLI_FB_BYTES; i++) {
            le[2 * i] = (uint8_t)screen[i];
            le[2 * i + 1] = (uint8_t)(screen[i] >> 8);
        }
        if (!write_file(dump_rgb, le, sizeof(le)))
            { fprintf(stderr, "pulli-headless: cannot write %s\n", dump_rgb); ok = false; }
    }

    if (engine.error[0]) fprintf(stderr, "error: %s\n", engine.error);
    fprintf(stderr, "%s: %ld of %ld frames, Lua heap %.1f KB, peak %.1f of %d KB\n",
            engine.manifest.title[0] ? engine.manifest.title : game, done, frames,
            engine.heap_used / 1024.0, engine.heap_peak / 1024.0, engine.manifest.lua_heap_kb);
    pulli_shutdown(&engine);
    host_link_close();
    free(data);
    return ok ? 0 : 1;
}
