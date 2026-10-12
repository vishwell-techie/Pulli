#ifndef PULLI_VAASAL_H
#define PULLI_VAASAL_H

#include <stdbool.h>
#include <stddef.h>

#define VAASAL_VERSION "0.1.0"
#define VAASAL_FPS 30

/* Runs a cart from Lua source until it fails or max_frames have been played
 * (max_frames < 0: forever). Returns false if the cart raised an error. */
bool vaasal_run(const char *name, const char *src, size_t len, long max_frames);

#endif
