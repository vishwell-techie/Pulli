/* pad.c — game controllers for the desktop host. See pad.h. */
#include "pad.h"
#include "pulli.h"
#include <stdio.h>

#define PADS 4
/* A stick or trigger pushed past half way counts as pressed. */
#define PUSHED 16384

static SDL_GameController *pads[PADS];

static const struct { SDL_GameControllerButton from; int to; } MAP[] = {
    { SDL_CONTROLLER_BUTTON_DPAD_LEFT, PULLI_BTN_LEFT },
    { SDL_CONTROLLER_BUTTON_DPAD_RIGHT, PULLI_BTN_RIGHT },
    { SDL_CONTROLLER_BUTTON_DPAD_UP, PULLI_BTN_UP },
    { SDL_CONTROLLER_BUTTON_DPAD_DOWN, PULLI_BTN_DOWN },
    { SDL_CONTROLLER_BUTTON_A, PULLI_BTN_A },
    { SDL_CONTROLLER_BUTTON_B, PULLI_BTN_B },
    { SDL_CONTROLLER_BUTTON_X, PULLI_BTN_X },
    { SDL_CONTROLLER_BUTTON_Y, PULLI_BTN_Y },
    { SDL_CONTROLLER_BUTTON_LEFTSHOULDER, PULLI_BTN_L },
    { SDL_CONTROLLER_BUTTON_RIGHTSHOULDER, PULLI_BTN_R },
    { SDL_CONTROLLER_BUTTON_START, PULLI_BTN_START },
    { SDL_CONTROLLER_BUTTON_BACK, PULLI_BTN_SELECT },
};

static void open_pad(int index) {
    if (!SDL_IsGameController(index)) return;
    SDL_JoystickID id = SDL_JoystickGetDeviceInstanceID(index);
    for (int i = 0; i < PADS; i++)
        if (pads[i] && SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(pads[i])) == id) return;
    for (int i = 0; i < PADS; i++) {
        if (!pads[i]) {
            pads[i] = SDL_GameControllerOpen(index);
            if (pads[i]) fprintf(stderr, "pulli-host: controller %s\n", SDL_GameControllerName(pads[i]));
            return;
        }
    }
}

void pad_open_all(void) {
    for (int i = 0; i < SDL_NumJoysticks(); i++) open_pad(i);
}

void pad_event(const SDL_Event *ev) {
    if (ev->type == SDL_CONTROLLERDEVICEADDED) {
        open_pad(ev->cdevice.which);
    } else if (ev->type == SDL_CONTROLLERDEVICEREMOVED) {
        for (int i = 0; i < PADS; i++) {
            if (pads[i] && SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(pads[i])) == ev->cdevice.which) {
                SDL_GameControllerClose(pads[i]);
                pads[i] = NULL;
            }
        }
    }
}

uint32_t pad_buttons(void) {
    uint32_t b = 0;
    for (int i = 0; i < PADS; i++) {
        SDL_GameController *p = pads[i];
        if (!p) continue;
        for (size_t m = 0; m < sizeof(MAP) / sizeof(MAP[0]); m++)
            if (SDL_GameControllerGetButton(p, MAP[m].from)) b |= 1u << MAP[m].to;
        int x = SDL_GameControllerGetAxis(p, SDL_CONTROLLER_AXIS_LEFTX);
        int y = SDL_GameControllerGetAxis(p, SDL_CONTROLLER_AXIS_LEFTY);
        if (x <= -PUSHED) b |= 1u << PULLI_BTN_LEFT;
        if (x >= PUSHED) b |= 1u << PULLI_BTN_RIGHT;
        if (y <= -PUSHED) b |= 1u << PULLI_BTN_UP;
        if (y >= PUSHED) b |= 1u << PULLI_BTN_DOWN;
        if (SDL_GameControllerGetAxis(p, SDL_CONTROLLER_AXIS_TRIGGERLEFT) >= PUSHED) b |= 1u << PULLI_BTN_L;
        if (SDL_GameControllerGetAxis(p, SDL_CONTROLLER_AXIS_TRIGGERRIGHT) >= PUSHED) b |= 1u << PULLI_BTN_R;
    }
    return b;
}

int pad_count(void) {
    int n = 0;
    for (int i = 0; i < PADS; i++) n += pads[i] != NULL;
    return n;
}

void pad_close_all(void) {
    for (int i = 0; i < PADS; i++) {
        if (pads[i]) SDL_GameControllerClose(pads[i]);
        pads[i] = NULL;
    }
}
