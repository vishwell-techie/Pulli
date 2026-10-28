/* headless_main.c — runs a game with no window, for tests and automation.
 *
 *   pulli-headless <game.pulli> [options]
 *     --frames N        frames to run (default 60)
 *     --hold a,left     buttons held down for the whole run
 *     --tap a@1,right@90-150  buttons pressed on one frame, or held from one
 *                       frame to another (frames count from 1)
 *     --caps wifi,cart  optional hardware reported through sys.has()
 *     --link PORT       link to another host started with the same port
 *     --saves DIR       keep save data in DIR (default: discarded on exit)
 *     --debug           keep the game's debug information: errors say where
 *     --dump-fb FILE    write the final indexed framebuffer, 76800 bytes
 *     --dump-rgb FILE   write the final screen as RGB565, little-endian
 *     --dump-wav FILE   write everything the game played, as a WAV file
 *     --clock-step US   give the game a clock that moves US microseconds each
 *                       time it is read, so stat("fps") and stat("cpu") have
 *                       an answer that is the same every run
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

/* Sound is collected only when --dump-wav asks for it. */
static uint32_t clock_step, clock_now;
static uint32_t fake_micros(void) { return clock_now += clock_step; }

static FILE *wav;
static uint32_t wav_frames;

static void put32(uint8_t *p, uint32_t v) { for (int i = 0; i < 4; i++) p[i] = (uint8_t)(v >> (8 * i)); }

static bool wav_header(void) {
    uint8_t h[44] = "RIFF....WAVEfmt ";
    uint32_t bytes = wav_frames * 4;
    put32(h + 4, 36 + bytes);
    put32(h + 16, 16);
    h[20] = 1; h[22] = 2;                           /* PCM, stereo */
    put32(h + 24, PULLI_AUDIO_RATE);
    put32(h + 28, PULLI_AUDIO_RATE * 4);
    h[32] = 4; h[34] = 16;
    memcpy(h + 36, "data", 4);
    put32(h + 40, bytes);
    return fseek(wav, 0, SEEK_SET) == 0 && fwrite(h, 1, sizeof(h), wav) == sizeof(h);
}

static void audio(const int16_t *stereo, int frames) {
    for (int i = 0; i < frames * 2; i++) {
        fputc(stereo[i] & 0xFF, wav);
        fputc((stereo[i] >> 8) & 0xFF, wav);
    }
    wav_frames += (uint32_t)frames;
}

static bool write_file(const char *path, const uint8_t *data, size_t len) {
    FILE *f = fopen(path, "wb");
    if (!f) return false;
    bool ok = fwrite(data, 1, len, f) == len;
    return fclose(f) == 0 && ok;
}

#define MAX_TAPS 512
static struct { long frame, last; uint32_t buttons; } taps[MAX_TAPS];
static int tap_count;

/* "a@1,right@90-150" */
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
        long last = frame;
        if (*end == '-') {
            const char *from = end + 1;
            last = strtol(from, &end, 10);
            if (end == from || last < frame) return false;
        }
        taps[tap_count].last = last;
        taps[tap_count++].frame = frame;
        list = *end == ',' ? end + 1 : end;
        if (*end && *end != ',') return false;
    }
    return true;
}

/* --reload FRAME:PACKAGE[:ENTRIES]: before frame FRAME, the game's package
 * becomes PACKAGE and is hot-reloaded, as Pattarai does when a file is
 * saved (ENTRIES: the entries that changed, by comma; all if left out). */
#define RELOADS_MAX 4
static struct { long frame; char *pkg; const char *names[64]; int count; } reloads[RELOADS_MAX];
static int reload_count;

static bool parse_reload(char *v) {
    if (reload_count == RELOADS_MAX) return false;
    char *pkg = strchr(v, ':');
    if (!pkg) return false;
    *pkg++ = 0;
    reloads[reload_count].frame = atol(v);
    char *names = strchr(pkg, ':');
    reloads[reload_count].pkg = pkg;
    reloads[reload_count].count = -1;              /* all */
    if (names) {
        *names++ = 0;
        int n = 0;
        for (char *t = strtok(names, ","); t && n < 64; t = strtok(NULL, ",")) reloads[reload_count].names[n++] = t;
        reloads[reload_count].count = n;
    }
    reload_count++;
    return true;
}

static int usage(void) {
    fprintf(stderr,
        "usage: pulli-headless <game.pulli> [--frames N] [--hold BUTTONS] [--tap BUTTON@FRAME[-FRAME],...]\n"
        "                      [--caps CAPS] [--link PORT]\n"
        "                      [--saves DIR] [--dump-fb FILE] [--dump-rgb FILE] [--dump-wav FILE]\n"
        "                      [--clock-step US] [--mapped] [--cart IMAGE] [--cart-cut BYTES] [--debug]\n"
        "                      [--reload FRAME:PACKAGE[:ENTRY,ENTRY...]]\n");
    return 2;
}

int main(int argc, char **argv) {
    const char *game = NULL, *dump_fb = NULL, *dump_rgb = NULL, *dump_wav = NULL, *cart = NULL;
    bool mapped = false;
    long cart_cut = -1;
    long frames = 60;
    uint32_t held = 0, caps = 0;
    pulli_backend backend = { 0 };
    backend.present = present;
    backend.save_read = host_save_read;
    backend.save_write = host_save_write;
    backend.log = host_log;
    backend.halves = host_halves;

    if (argc == 2 && !strcmp(argv[1], "--maths-check")) {
        uint32_t sum = pulli_math_check();
        printf("%08x %08x\n", (unsigned)sum, (unsigned)PULLI_MATH_CHECK);
        return sum == PULLI_MATH_CHECK ? 0 : 1;
    }
    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        const char *v = i + 1 < argc ? argv[i + 1] : NULL;
        if (a[0] != '-') { if (game) return usage(); game = a; continue; }
        if (!strcmp(a, "--mapped")) { mapped = true; continue; }   /* the whole package in memory */
        if (!strcmp(a, "--debug")) { backend.debug = true; continue; }
        if (!v) return usage();
        i++;
        if      (!strcmp(a, "--frames"))   frames = atol(v);
        else if (!strcmp(a, "--saves"))    host_set_save_dir(v);
        else if (!strcmp(a, "--dump-fb"))  dump_fb = v;
        else if (!strcmp(a, "--dump-rgb")) dump_rgb = v;
        else if (!strcmp(a, "--dump-wav")) dump_wav = v;
        else if (!strcmp(a, "--clock-step")) { clock_step = (uint32_t)atol(v); backend.micros = fake_micros; }
        else if (!strcmp(a, "--hold"))     { if (!host_parse_buttons(v, &held)) return usage(); }
        else if (!strcmp(a, "--tap"))      { if (!parse_taps(v)) return usage(); }
        else if (!strcmp(a, "--caps"))     { if (!host_parse_caps(v, &caps)) return usage(); }
        else if (!strcmp(a, "--link"))     { if (!host_use_link(&backend, v, true)) return usage(); }
        else if (!strcmp(a, "--cart"))     cart = v;
        else if (!strcmp(a, "--cart-cut")) cart_cut = atol(v);
        else if (!strcmp(a, "--reload"))   { if (!parse_reload(argv[i])) return usage(); }
        else return usage();
    }
    if ((!game) == (!cart) || frames < 0 || (cart && mapped)) return usage();
    backend.caps |= caps;

    /* As a console does: the package read in parts as the game uses them,
     * from its file or from a cartridge. --mapped holds all of it in memory
     * instead, as flash read in place is; a game must behave the same. */
    size_t len = 0;
    uint8_t *data = NULL;
    if (cart) {
        if (!host_open_cart(cart, cart_cut, &len)) { fprintf(stderr, "pulli-headless: cannot use %s\n", cart); return 2; }
        backend.pkg_read = host_pkg_read;
        backend.save_read = host_cart_save_read;
        backend.save_write = host_cart_save_write;
        backend.caps |= PULLI_CAP_CART;
        game = cart;
    } else if (mapped) {
        if (!(data = host_read_file(game, &len))) { fprintf(stderr, "pulli-headless: cannot read %s\n", game); return 2; }
    } else {
        if (!host_open_package(game, &len)) { fprintf(stderr, "pulli-headless: cannot read %s\n", game); return 2; }
        backend.pkg_read = host_pkg_read;
    }

    if (dump_wav) {
        wav = fopen(dump_wav, "wb");
        if (!wav || !wav_header()) { fprintf(stderr, "pulli-headless: cannot write %s\n", dump_wav); return 2; }
        backend.audio = audio;
    }

    bool ok = pulli_boot(&engine, data, len, &backend);
    long done = 0;
    while (ok && done < frames) {
        for (int r = 0; r < reload_count; r++) {
            if (reloads[r].frame != done + 1) continue;
            size_t n;
            if (!host_open_package(reloads[r].pkg, &n)) { fprintf(stderr, "pulli-headless: cannot read %s\n", reloads[r].pkg); return 2; }
            const char *why = pulli_reload(&engine, n, reloads[r].count < 0 ? NULL : reloads[r].names,
                                           reloads[r].count < 0 ? 0 : reloads[r].count);
            if (why) fprintf(stderr, "reload: %s\n", why);
        }
        uint32_t buttons = held;
        for (int i = 0; i < tap_count; i++)
            if (taps[i].frame <= done + 1 && done + 1 <= taps[i].last) buttons |= taps[i].buttons;
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

    if (wav && (!wav_header() || fclose(wav) != 0))
        { fprintf(stderr, "pulli-headless: cannot write %s\n", dump_wav); ok = false; }

    if (engine.error[0]) fprintf(stderr, "error: %s\n", engine.error);
    fprintf(stderr, "%s: %ld of %ld frames, Lua heap %.1f KB, peak %.1f of %d KB; "
            "active %.1f KB, peak %.1f of %u KB, read again %u\n",
            engine.manifest.title[0] ? engine.manifest.title : game, done, frames,
            pulli_heap_used(&engine) / 1024.0, pulli_heap_peak(&engine) / 1024.0, engine.manifest.lua_heap_kb,
            engine.active / 1024.0, pulli_active_peak(&engine) / 1024.0, PULLI_ACTIVE_MAX / 1024,
            (unsigned)pulli_active_rereads(&engine));
    pulli_shutdown(&engine);
    host_link_close();
    free(data);
    return ok ? 0 : 1;
}
