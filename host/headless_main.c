/* headless_main.c — runs a game with no window, for tests and automation.
 *
 *   pulli-headless <game.pulli> [options]
 *     --frames N        frames to run (default 60)
 *     --hold a,left     buttons held down for the whole run
 *     --caps wifi,cart  optional hardware reported through sys.has()
 *     --saves DIR       keep save data in DIR (default: discarded on exit)
 *     --dump-fb FILE    write the final indexed framebuffer, 76800 bytes
 *     --dump-rgb FILE   write the final screen as RGB565, little-endian
 *
 * Game dbg() output goes to stdout; everything else goes to stderr. Exits 0
 * if the game ran every frame, 1 if it failed, 2 on a usage error. */
#include "common.h"
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

static int usage(void) {
    fprintf(stderr,
        "usage: pulli-headless <game.pulli> [--frames N] [--hold BUTTONS] [--caps CAPS]\n"
        "                      [--saves DIR] [--dump-fb FILE] [--dump-rgb FILE]\n");
    return 2;
}

int main(int argc, char **argv) {
    const char *game = NULL, *dump_fb = NULL, *dump_rgb = NULL;
    long frames = 60;
    uint32_t held = 0;
    pulli_backend backend = { 0 };
    backend.present = present;
    backend.save_read = host_save_read;
    backend.save_write = host_save_write;
    backend.log = host_log;

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
        else if (!strcmp(a, "--caps"))     { if (!host_parse_caps(v, &backend.caps)) return usage(); }
        else return usage();
    }
    if (!game || frames < 0) return usage();

    size_t len;
    uint8_t *data = host_read_file(game, &len);
    if (!data) { fprintf(stderr, "pulli-headless: cannot read %s\n", game); return 2; }

    bool ok = pulli_boot(&engine, data, len, &backend);
    long done = 0;
    while (ok && done < frames) {
        ok = pulli_update(&engine, held) && pulli_draw(&engine);
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
    free(data);
    return ok ? 0 : 1;
}
