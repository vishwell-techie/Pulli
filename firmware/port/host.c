/* Port for Linux, to run carts without hardware:
 *   pulli [cart.lua] [frames]
 * With no cart it runs the built-in one; with no frame count it runs until killed. */

#define _POSIX_C_SOURCE 199309L

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "platform.h"
#include "vaasal.h"

extern const char cart_builtin[];
extern const size_t cart_builtin_len;

void plat_init(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
}

uint32_t plat_millis(void)
{
    struct timespec ts;

    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

void plat_sleep_ms(uint32_t ms)
{
    struct timespec ts = {ms / 1000, (long)(ms % 1000) * 1000000};

    nanosleep(&ts, NULL);
}

static char *read_file(const char *path, size_t *len)
{
    FILE *f = fopen(path, "rb");
    char *buf = NULL;
    long size;

    if (!f)
        return NULL;
    if (fseek(f, 0, SEEK_END) == 0 && (size = ftell(f)) >= 0 && (buf = malloc(size + 1))) {
        rewind(f);
        *len = fread(buf, 1, size, f);
    }
    fclose(f);
    return buf;
}

int main(int argc, char **argv)
{
    long frames = argc > 2 ? atol(argv[2]) : -1;
    bool ok;

    plat_init();
    if (argc > 1) {
        size_t len;
        char *src = read_file(argv[1], &len);

        if (!src) {
            fprintf(stderr, "cannot read %s\n", argv[1]);
            return 2;
        }
        ok = vaasal_run(argv[1], src, len, frames);
        free(src);
    } else {
        ok = vaasal_run("builtin", cart_builtin, cart_builtin_len, frames);
    }
    return ok ? 0 : 1;
}
