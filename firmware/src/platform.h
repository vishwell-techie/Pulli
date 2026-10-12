#ifndef PULLI_PLATFORM_H
#define PULLI_PLATFORM_H

#include <stdint.h>

/* What every port (port/pico.c, port/host.c) provides to the runtime. */

void plat_init(void);
uint32_t plat_millis(void);
void plat_sleep_ms(uint32_t ms);

#endif
