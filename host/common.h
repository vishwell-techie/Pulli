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

/* The link, emulated between two host processes given the same port on this
 * computer. `step` makes linked runs repeatable; see link.c. */
bool host_link_open(int port, bool step);
pulli_link_state host_link_poll(int *side);
bool host_link_send(const void *msg, size_t len);
int  host_link_recv(void *msg, size_t max);
void host_link_close(void);

/* Adds the link to a backend. False if the port is bad or links are not
 * available on this system. */
bool host_use_link(pulli_backend *backend, const char *port, bool step);

#endif
