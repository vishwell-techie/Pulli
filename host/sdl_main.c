/* sdl_main.c — Pulli desktop host: a window, a keyboard, game controllers
 * (pad.c) and a clock.
 *
 *   pulli-host <game.pulli> [scale] [--link PORT]      (scale 3 when left out)
 *
 * Start two with the same --link port to play a linked game between them.
 *
 * Everything platform-specific lives in host/. The engine in runtime/ is
 * shared verbatim with the RP2350 firmware; porting means writing a file
 * like this one, not touching the engine. */
#define SDL_MAIN_HANDLED
#include <SDL.h>
#include "common.h"
#include "pad.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SCALE_DEFAULT 3

static pulli_engine engine;
static SDL_Texture *texture;

static void present(const uint16_t *rgb565, int y0, int rows) {
    SDL_Rect r = { 0, y0, PULLI_SCREEN_W, rows };
    SDL_UpdateTexture(texture, &r, rgb565, PULLI_SCREEN_W * (int)sizeof(uint16_t));
}

/* The game keeps time by the screen and the sound card by its own clock,
 * so the two drift. When more than a tenth of a second of sound is waiting,
 * a frame's worth is dropped rather than letting the sound fall behind. */
static SDL_AudioDeviceID speaker;
#define SOUND_WAITING_MAX (6 * PULLI_AUDIO_FRAMES * 2 * (int)sizeof(int16_t))

static void audio(const int16_t *stereo, int frames) {
    if (SDL_GetQueuedAudioSize(speaker) > SOUND_WAITING_MAX) return;
    SDL_QueueAudio(speaker, stereo, (Uint32)frames * 2 * sizeof(int16_t));
}

static uint32_t micros(void) {
    return (uint32_t)((SDL_GetPerformanceCounter() * 1000000ull) / SDL_GetPerformanceFrequency());
}

static const SDL_Scancode KEYMAP[PULLI_BTN_COUNT] = {
    SDL_SCANCODE_LEFT, SDL_SCANCODE_RIGHT, SDL_SCANCODE_UP, SDL_SCANCODE_DOWN,
    SDL_SCANCODE_Z, SDL_SCANCODE_X, SDL_SCANCODE_A, SDL_SCANCODE_S,
    SDL_SCANCODE_Q, SDL_SCANCODE_W, SDL_SCANCODE_RETURN, SDL_SCANCODE_RSHIFT
};

int main(int argc, char **argv) {
    const char *game = NULL, *link_port = NULL;
    int scale = SCALE_DEFAULT;
    bool bad = false, debug = false;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--link")) {
            if (++i < argc) link_port = argv[i]; else bad = true;
        } else if (!strcmp(argv[i], "--debug")) {
            debug = true;                       /* keep line numbers for errors */
        } else if (!game) {
            game = argv[i];
        } else if (atoi(argv[i]) >= 1) {
            scale = atoi(argv[i]);
        } else {
            bad = true;
        }
    }
    if (!game || bad) {
        fprintf(stderr, "usage: pulli-host <game.pulli> [scale, 3 if left out] [--link PORT] [--debug]\n");
        return 2;
    }

    /* The package is read in parts as the game uses them, as a console
     * reads its SD card (SPEC §2). */
    size_t len;
    if (!host_open_package(game, &len)) { fprintf(stderr, "pulli-host: cannot read %s\n", game); return 2; }

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
    backend.log = host_log;
    backend.halves = host_halves;
    backend.micros = micros;
    backend.pkg_read = host_pkg_read;
    backend.debug = debug;
    /* No sound card is not an error: the game runs silently. */
    SDL_AudioSpec want = { 0 };
    want.freq = PULLI_AUDIO_RATE;
    want.format = AUDIO_S16SYS;
    want.channels = 2;
    want.samples = 512;
    if (SDL_InitSubSystem(SDL_INIT_AUDIO) == 0)
        speaker = SDL_OpenAudioDevice(NULL, 0, &want, NULL, 0);
    if (speaker) {
        backend.audio = audio;
        SDL_PauseAudioDevice(speaker, 0);
    } else {
        fprintf(stderr, "pulli-host: no sound (%s)\n", SDL_GetError());
    }
    /* No controller support is not an error either: the keyboard still works. */
    if (SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER) == 0)
        pad_open_all();
    else
        fprintf(stderr, "pulli-host: no game controllers (%s)\n", SDL_GetError());
    if (link_port && !host_use_link(&backend, link_port, false)) {
        fprintf(stderr, "pulli-host: cannot open a link on port %s (use 1024 to 65535)\n", link_port);
        SDL_Quit();
        return 2;
    }

    if (!pulli_boot(&engine, NULL, len, &backend)) {
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
            pad_event(&ev);
        }
        uint64_t now = SDL_GetPerformanceCounter();
        double elapsed = (double)(now - prev) / (double)SDL_GetPerformanceFrequency();
        prev = now;
        if (elapsed > 0.25) elapsed = 0.25;        /* don't spiral after a stall */
        accum += elapsed;

        /* Behind schedule: run the missed updates and draw once (SPEC §3). */
        const Uint8 *keys = SDL_GetKeyboardState(NULL);
        while (running && accum >= STEP) {
            uint32_t buttons = pad_buttons();
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
    host_link_close();
    pad_close_all();
    SDL_DestroyTexture(texture);
    SDL_DestroyRenderer(ren);
    SDL_DestroyWindow(win);
    SDL_Quit();
    return status;
}
