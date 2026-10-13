/* sdl_main.c — Pulli desktop host: a window, a keyboard and a clock.
 *
 *   pulli-host <game.pulli> [scale]
 *
 * Everything platform-specific lives in host/. The engine in runtime/ is
 * shared verbatim with the RP2350 firmware; porting means writing a file
 * like this one, not touching the engine. */
#define SDL_MAIN_HANDLED
#include <SDL.h>
#include "common.h"
#include <stdio.h>
#include <stdlib.h>

#define SCALE_DEFAULT 3

static pulli_engine engine;
static SDL_Texture *texture;

static void present(const uint16_t *rgb565, int y0, int rows) {
    SDL_Rect r = { 0, y0, PULLI_SCREEN_W, rows };
    SDL_UpdateTexture(texture, &r, rgb565, PULLI_SCREEN_W * (int)sizeof(uint16_t));
}

static const SDL_Scancode KEYMAP[PULLI_BTN_COUNT] = {
    SDL_SCANCODE_LEFT, SDL_SCANCODE_RIGHT, SDL_SCANCODE_UP, SDL_SCANCODE_DOWN,
    SDL_SCANCODE_Z, SDL_SCANCODE_X, SDL_SCANCODE_A, SDL_SCANCODE_S,
    SDL_SCANCODE_Q, SDL_SCANCODE_W, SDL_SCANCODE_RETURN, SDL_SCANCODE_RSHIFT
};

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: pulli-host <game.pulli> [scale]\n");
        return 2;
    }
    int scale = argc > 2 ? atoi(argv[2]) : SCALE_DEFAULT;
    if (scale < 1) scale = SCALE_DEFAULT;

    size_t len;
    uint8_t *data = host_read_file(argv[1], &len);
    if (!data) { fprintf(stderr, "pulli-host: cannot read %s\n", argv[1]); return 2; }

    SDL_SetMainReady();
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return 1;
    }
    char *prefs = SDL_GetPrefPath("VishWell", "Pulli");
    host_set_save_dir(prefs);
    SDL_free(prefs);

    pulli_backend backend = { 0 };
    backend.present = present;
    backend.save_read = host_save_read;
    backend.save_write = host_save_write;
    backend.log = host_log;                 /* audio hooks stay NULL: silent for now */

    if (!pulli_boot(&engine, data, len, &backend)) {
        fprintf(stderr, "error: %s\n", engine.error);
        SDL_Quit();
        return 1;
    }

    char title[96];
    snprintf(title, sizeof(title), "%s - Pulli", engine.manifest.title);
    SDL_Window *win = SDL_CreateWindow(title, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                                       PULLI_SCREEN_W * scale, PULLI_SCREEN_H * scale, 0);
    SDL_Renderer *ren = win ? SDL_CreateRenderer(win, -1, SDL_RENDERER_PRESENTVSYNC) : NULL;
    texture = ren ? SDL_CreateTexture(ren, SDL_PIXELFORMAT_RGB565, SDL_TEXTUREACCESS_STREAMING,
                                      PULLI_SCREEN_W, PULLI_SCREEN_H) : NULL;
    if (!texture) {
        fprintf(stderr, "SDL: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    /* Fixed 1/60 timestep. Determinism is a spec requirement (SPEC §4):
     * it is what makes replay-based regression tests possible. */
    const double STEP = 1.0 / PULLI_TICK_HZ;
    uint64_t prev = SDL_GetPerformanceCounter();
    double accum = 0.0;
    bool running = true;

    while (running) {
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_QUIT) running = false;
            if (ev.type == SDL_KEYDOWN && ev.key.keysym.sym == SDLK_ESCAPE) running = false;
        }
        uint64_t now = SDL_GetPerformanceCounter();
        double elapsed = (double)(now - prev) / (double)SDL_GetPerformanceFrequency();
        prev = now;
        if (elapsed > 0.25) elapsed = 0.25;        /* don't spiral after a stall */
        accum += elapsed;

        /* Behind schedule: run the missed updates and draw once (SPEC §3). */
        const Uint8 *keys = SDL_GetKeyboardState(NULL);
        while (running && accum >= STEP) {
            uint32_t buttons = 0;
            for (int i = 0; i < PULLI_BTN_COUNT; i++)
                if (keys[KEYMAP[i]]) buttons |= 1u << i;
            running = pulli_update(&engine, buttons);
            accum -= STEP;
        }
        if (!running || !pulli_draw(&engine)) break;

        pulli_present(&engine);
        SDL_RenderClear(ren);
        SDL_RenderCopy(ren, texture, NULL, NULL);
        SDL_RenderPresent(ren);
        if (accum < STEP) SDL_Delay(1);            /* in case vsync is unavailable */
    }

    int status = engine.error[0] ? 1 : 0;
    if (status) fprintf(stderr, "error: %s\n", engine.error);
    pulli_shutdown(&engine);
    SDL_DestroyTexture(texture);
    SDL_DestroyRenderer(ren);
    SDL_DestroyWindow(win);
    SDL_Quit();
    free(data);
    return status;
}
