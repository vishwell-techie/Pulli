/* Pulli firmware, bring-up stage: one RP2350, no display, no buttons.
 *
 * Runs the same runtime as the desktop host on a game linked into the
 * image, and measures the numbers the hardware plan rests on (SPEC §9):
 * time spent in update() and draw(), the cost of converting a frame to
 * RGB565, and the Lua heap a real game needs. Results go to USB serial
 * once a second. */
#include <stdio.h>

#include "pico/stdlib.h"

#include "pulli.h"

extern const unsigned char pulli_builtin_game[];
extern const unsigned int pulli_builtin_game_len;

#define FRAME_US (1000000 / PULLI_TICK_HZ)

static pulli_engine engine;     /* static: it holds the 76.8 KB framebuffer */

/* No panel yet. The strip has already been converted by the time this is
 * called, which is the part being timed. */
static void present(const uint16_t *rgb565, int y0, int rows) {
    (void)rgb565; (void)y0; (void)rows;
}

static void log_line(const char *msg) {
    printf("[game] %s\n", msg);
}

static const pulli_backend backend = {
    .present = present,
    .log = log_line,
    /* no audio, no save storage, no optional hardware yet */
};

static void run_game(void) {
    if (!pulli_boot(&engine, pulli_builtin_game, pulli_builtin_game_len, &backend)) {
        printf("[pulli] error: %s\n", engine.error);
        return;
    }
    printf("[pulli] %s (%s), %u byte package read in place, Lua heap limit %d KB\n",
           engine.manifest.title, engine.manifest.id, pulli_builtin_game_len,
           engine.manifest.lua_heap_kb);

    uint64_t update_us = 0, draw_us = 0, scanout_us = 0, worst_us = 0;
    unsigned frames = 0, late = 0;
    absolute_time_t next = get_absolute_time();

    for (uint32_t tick = 0;; tick++) {
        /* No buttons yet. PULLI_AUTO_A_SECONDS (a build option, 0 = off)
         * taps A at that interval, so a game that waits on a title screen
         * starts, and starts again when it ends. */
        uint32_t buttons = 0;
        if (PULLI_AUTO_A_SECONDS > 0 && tick % (PULLI_AUTO_A_SECONDS * PULLI_TICK_HZ) == 0)
            buttons = 1u << PULLI_BTN_A;
        uint64_t t0 = time_us_64();
        bool ok = pulli_update(&engine, buttons);
        uint64_t t1 = time_us_64();
        ok = ok && pulli_draw(&engine);
        uint64_t t2 = time_us_64();
        pulli_present(&engine);
        uint64_t t3 = time_us_64();
        if (!ok) break;

        update_us += t1 - t0;
        draw_us += t2 - t1;
        scanout_us += t3 - t2;
        if (t3 - t0 > worst_us) worst_us = t3 - t0;
        if (++frames == PULLI_TICK_HZ) {
            printf("[pulli] per frame: update %u us, draw %u us, scanout %u us; worst frame %u us of %u; "
                   "late %u/%u; heap %u KB, peak %u KB\n",
                   (unsigned)(update_us / frames), (unsigned)(draw_us / frames),
                   (unsigned)(scanout_us / frames), (unsigned)worst_us, (unsigned)FRAME_US,
                   late, frames, (unsigned)(engine.heap_used / 1024), (unsigned)(engine.heap_peak / 1024));
            update_us = draw_us = scanout_us = worst_us = 0;
            frames = late = 0;
        }

        next = delayed_by_us(next, FRAME_US);
        if (time_reached(next)) {           /* overran the frame: drop the lost time */
            late++;
            next = get_absolute_time();
        } else {
            sleep_until(next);
        }
    }
    printf("[pulli] error: %s\n", engine.error);
    pulli_shutdown(&engine);
}

int main(void) {
    stdio_init_all();
    sleep_ms(2000);     /* give a serial terminal a moment to attach */
    for (;;) {
        run_game();
        printf("[pulli] game stopped, restarting in 5 s\n");
        sleep_ms(5000);
    }
}
