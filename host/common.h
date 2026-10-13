/* common.h — pieces both desktop frontends share. */
#ifndef PULLI_HOST_COMMON_H
#define PULLI_HOST_COMMON_H

#include "pulli.h"

/* Whole file into malloc'd memory; NULL if it cannot be read. */
uint8_t *host_read_file(const char *path, size_t *len);

/* "wifi,cart" -> PULLI_CAP_* bits. Returns false on an unknown name. */
bool host_parse_caps(const char *list, uint32_t *caps);

/* "a,left" -> button bits. Returns false on an unknown name. */
bool host_parse_buttons(const char *list, uint32_t *buttons);

/* Save blobs live in one directory as <game id>.sav. With no directory set,
 * saves are accepted and forgotten when the process exits. */
void host_set_save_dir(const char *dir);
int  host_save_read(const char *game_id, void *blob, size_t max);
bool host_save_write(const char *game_id, const void *blob, size_t len);

void host_log(const char *msg);     /* game dbg() output, to stdout */

#endif
