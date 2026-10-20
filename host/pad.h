/* pad.h — game controllers for the desktop host (SDL2's GameController).
 *
 * Any controller SDL knows (Xbox, PlayStation, Switch Pro, most USB pads)
 * works as the console's buttons, alongside the keyboard:
 *
 *   D-pad or left stick   D-pad          A B X Y      A B X Y (by name)
 *   LB / RB, or triggers  L / R          Start, Back  START, SELECT
 *
 * Controllers can be plugged in and out while a game runs; several at once
 * all count as the one player. */
#ifndef PULLI_HOST_PAD_H
#define PULLI_HOST_PAD_H

#include <SDL.h>
#include <stdint.h>

/* Open every controller already plugged in. Call after SDL_INIT_GAMECONTROLLER. */
void pad_open_all(void);
/* Pass every SDL event: controllers plugged in or out are opened or closed. */
void pad_event(const SDL_Event *ev);
/* The buttons held on all controllers, as bits 1 << PULLI_BTN_*. */
uint32_t pad_buttons(void);
/* How many controllers are open. */
int pad_count(void);
void pad_close_all(void);

#endif
