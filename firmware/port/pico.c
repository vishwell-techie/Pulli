/* Port for RP2040 / RP2350 boards. Console output goes to USB serial. */

#include <stdio.h>

#include "pico/stdlib.h"

#include "platform.h"
#include "vaasal.h"

extern const char cart_builtin[];
extern const size_t cart_builtin_len;

void plat_init(void)
{
    stdio_init_all();
}

uint32_t plat_millis(void)
{
    return to_ms_since_boot(get_absolute_time());
}

void plat_sleep_ms(uint32_t ms)
{
    sleep_ms(ms);
}

int main(void)
{
    plat_init();
    /* give a serial terminal a moment to attach before the first lines scroll past */
    sleep_ms(2000);

    for (;;) {
        vaasal_run("builtin", cart_builtin, cart_builtin_len, -1);
        printf("[vaasal] cart stopped, restarting in 5 s\n");
        sleep_ms(5000);
    }
}
