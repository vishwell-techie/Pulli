/* pad_test.c — the controller mapping in pad.c, checked through SDL's own
 * GameController layer with a virtual controller: no real one, and no
 * window, needed. Run by ctest as "pad". */
#define SDL_MAIN_HANDLED
#include "pad.h"
#include "pulli.h"
#include <stdio.h>

static int failed;

static void check(const char *what, uint32_t got, uint32_t want) {
    if (got != want) {
        printf("  FAIL  %s: buttons 0x%03x, wanted 0x%03x\n", what, (unsigned)got, (unsigned)want);
        failed++;
    } else {
        printf("  PASS  %s\n", what);
    }
}

#define BIT(b) (1u << (b))

int main(void) {
    SDL_SetMainReady();
    SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
    /* only the virtual controller below: a real one plugged in is left alone */
    SDL_SetHint(SDL_HINT_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT, "0x1209/0x0001");
    if (SDL_Init(SDL_INIT_GAMECONTROLLER) != 0) {
        printf("SKIP  no SDL game controller support: %s\n", SDL_GetError());
        return 0;
    }
    SDL_VirtualJoystickDesc desc = { 0 };
    desc.version = SDL_VIRTUAL_JOYSTICK_DESC_VERSION;
    desc.type = SDL_JOYSTICK_TYPE_GAMECONTROLLER;
    desc.naxes = SDL_CONTROLLER_AXIS_MAX;
    desc.nbuttons = SDL_CONTROLLER_BUTTON_MAX;
    desc.vendor_id = 0x1209;
    desc.product_id = 0x0001;
    int index = SDL_JoystickAttachVirtualEx(&desc);
    if (index < 0) {
        printf("SKIP  no virtual controller: %s\n", SDL_GetError());
        SDL_Quit();
        return 0;
    }
    pad_open_all();
    SDL_Joystick *j = SDL_JoystickOpen(index);
    check("one controller opened", (uint32_t)pad_count(), 1);

    static const struct { SDL_GameControllerButton b; int want; const char *name; } PRESS[] = {
        { SDL_CONTROLLER_BUTTON_DPAD_LEFT, PULLI_BTN_LEFT, "D-pad left is left" },
        { SDL_CONTROLLER_BUTTON_DPAD_RIGHT, PULLI_BTN_RIGHT, "D-pad right is right" },
        { SDL_CONTROLLER_BUTTON_DPAD_UP, PULLI_BTN_UP, "D-pad up is up" },
        { SDL_CONTROLLER_BUTTON_DPAD_DOWN, PULLI_BTN_DOWN, "D-pad down is down" },
        { SDL_CONTROLLER_BUTTON_A, PULLI_BTN_A, "A is A" },
        { SDL_CONTROLLER_BUTTON_B, PULLI_BTN_B, "B is B" },
        { SDL_CONTROLLER_BUTTON_X, PULLI_BTN_X, "X is X" },
        { SDL_CONTROLLER_BUTTON_Y, PULLI_BTN_Y, "Y is Y" },
        { SDL_CONTROLLER_BUTTON_LEFTSHOULDER, PULLI_BTN_L, "the left shoulder is L" },
        { SDL_CONTROLLER_BUTTON_RIGHTSHOULDER, PULLI_BTN_R, "the right shoulder is R" },
        { SDL_CONTROLLER_BUTTON_START, PULLI_BTN_START, "Start is START" },
        { SDL_CONTROLLER_BUTTON_BACK, PULLI_BTN_SELECT, "Back is SELECT" },
    };
    check("nothing pressed, nothing held", pad_buttons(), 0);
    for (size_t i = 0; i < sizeof(PRESS) / sizeof(PRESS[0]); i++) {
        SDL_JoystickSetVirtualButton(j, PRESS[i].b, 1);
        SDL_GameControllerUpdate();
        check(PRESS[i].name, pad_buttons(), BIT(PRESS[i].want));
        SDL_JoystickSetVirtualButton(j, PRESS[i].b, 0);
    }
    SDL_GameControllerUpdate();

    static const struct { SDL_GameControllerAxis a; int16_t v; uint32_t want; const char *name; } PUSH[] = {
        { SDL_CONTROLLER_AXIS_LEFTX, -32768, BIT(PULLI_BTN_LEFT), "the left stick pushed left is left" },
        { SDL_CONTROLLER_AXIS_LEFTX, 32767, BIT(PULLI_BTN_RIGHT), "the left stick pushed right is right" },
        { SDL_CONTROLLER_AXIS_LEFTY, -32768, BIT(PULLI_BTN_UP), "the left stick pushed up is up" },
        { SDL_CONTROLLER_AXIS_LEFTY, 32767, BIT(PULLI_BTN_DOWN), "the left stick pushed down is down" },
        { SDL_CONTROLLER_AXIS_LEFTX, 8000, 0, "the stick barely moved is nothing" },
        { SDL_CONTROLLER_AXIS_TRIGGERLEFT, 32767, BIT(PULLI_BTN_L), "the left trigger is L" },
        { SDL_CONTROLLER_AXIS_TRIGGERRIGHT, 32767, BIT(PULLI_BTN_R), "the right trigger is R" },
    };
    for (size_t i = 0; i < sizeof(PUSH) / sizeof(PUSH[0]); i++) {
        SDL_JoystickSetVirtualAxis(j, PUSH[i].a, PUSH[i].v);
        SDL_GameControllerUpdate();
        check(PUSH[i].name, pad_buttons(), PUSH[i].want);
        SDL_JoystickSetVirtualAxis(j, PUSH[i].a, 0);
        SDL_GameControllerUpdate();
    }

    /* unplugged: the controller is closed, and nothing stays held */
    SDL_JoystickSetVirtualButton(j, SDL_CONTROLLER_BUTTON_A, 1);
    SDL_GameControllerUpdate();
    SDL_JoystickClose(j);
    SDL_JoystickDetachVirtual(index);
    SDL_Event ev;
    while (SDL_PollEvent(&ev)) pad_event(&ev);
    check("unplugged, it is closed", (uint32_t)pad_count(), 0);
    check("unplugged, nothing stays held", pad_buttons(), 0);

    pad_close_all();
    SDL_Quit();
    printf(failed ? "FAILED %d\n" : "all pad checks passed\n", failed);
    return failed ? 1 : 0;
}
