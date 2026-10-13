/* link.c — the console-to-console link, emulated between two host
 * processes on one computer with a local TCP connection.
 *
 * Both are started with the same port. The first to arrive listens and is
 * side 1; the second connects and is side 2.
 *
 * On the wire a message is one length byte (0..64) and its bytes. A 0xFF
 * byte marks the end of a frame. In step mode (the headless host) each
 * side waits at the start of a frame for the other's end-of-frame mark, so
 * a message sent during frame N is always received during frame N + 1 and
 * a linked run gives the same result every time. The windowed host does
 * not wait: it plays in real time and takes messages as they come. */
#include "common.h"

#ifdef _WIN32

bool host_link_open(int port, bool step) { (void)port; (void)step; return false; }
pulli_link_state host_link_poll(int *side) { (void)side; return PULLI_LINK_OFF; }
bool host_link_send(const void *msg, size_t len) { (void)msg; (void)len; return false; }
int  host_link_recv(void *msg, size_t max) { (void)msg; (void)max; return -1; }
void host_link_close(void) {}

#else

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define FRAME_MARK    0xFF
#define CONNECT_WAIT  5000      /* ms the step mode waits for the other side */

static int  listener = -1, peer = -1;
static int  my_side, link_port;
static bool opened, step_mode, was_connected, frame_open;
static uint8_t rx[8192];
static size_t rx_len;           /* bytes received and not yet consumed */
static size_t rx_ready;         /* how many of them the game may see */

static struct sockaddr_in address(void) {
    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_port = htons((uint16_t)link_port);
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    return a;
}

static void drop_peer(void) {
    if (peer >= 0) close(peer);
    peer = -1;
    rx_len = rx_ready = 0;
    frame_open = false;
}

static void adopt(int fd) {
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    peer = fd;
    was_connected = true;
}

bool host_link_open(int port, bool step) {
    struct sockaddr_in a;
    int one = 1;
    link_port = port;
    step_mode = step;
    a = address();
    listener = socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0) return false;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    if (bind(listener, (struct sockaddr *)&a, sizeof(a)) == 0 && listen(listener, 1) == 0) {
        my_side = 1;
    } else {                    /* someone is already there: join them */
        close(listener);
        listener = -1;
        my_side = 2;
    }
    opened = true;
    return true;
}

/* One attempt to find the other side, waiting at most wait_ms. */
static void try_connect(int wait_ms) {
    if (my_side == 1) {
        struct pollfd p = { listener, POLLIN, 0 };
        if (poll(&p, 1, wait_ms) > 0) {
            int fd = accept(listener, NULL, NULL);
            if (fd >= 0) adopt(fd);
        }
    } else {
        struct sockaddr_in a = address();
        int fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd >= 0 && connect(fd, (struct sockaddr *)&a, sizeof(a)) == 0) {
            adopt(fd);
        } else {
            if (fd >= 0) close(fd);
            if (wait_ms > 0) poll(NULL, 0, wait_ms);
        }
    }
}

/* Read what has arrived, waiting at most wait_ms. False if the peer left. */
static bool pump(int wait_ms) {
    struct pollfd p = { peer, POLLIN, 0 };
    if (poll(&p, 1, wait_ms) <= 0) return true;
    if (rx_len == sizeof(rx)) return true;          /* full: the game is not reading */
    ssize_t n = recv(peer, rx + rx_len, sizeof(rx) - rx_len, 0);
    if (n <= 0) return false;
    rx_len += (size_t)n;
    return true;
}

/* Offset just past the first end-of-frame mark at or after `from`, or 0. */
static size_t after_mark(size_t from) {
    size_t i = from;
    while (i < rx_len) {
        if (rx[i] == FRAME_MARK) return i + 1;
        if (i + 1 + rx[i] > rx_len) break;          /* message still arriving */
        i += 1 + (size_t)rx[i];
    }
    return 0;
}

pulli_link_state host_link_poll(int *side) {
    static const uint8_t mark = FRAME_MARK;
    if (!opened) return PULLI_LINK_OFF;

    if (peer < 0) {
        /* Step mode waits for its partner once, at the very start, so both
         * sides count frames from the same moment. */
        int waited = 0, slice = step_mode && !was_connected ? 50 : 0;
        do {
            try_connect(slice);
            waited += slice;
        } while (peer < 0 && slice > 0 && waited < CONNECT_WAIT);
        if (peer < 0) return PULLI_LINK_WAITING;
    } else {
        /* Close the frame just played, then collect the other side's. */
        bool alive = !frame_open || send(peer, &mark, 1, MSG_NOSIGNAL) == 1;
        if (alive && step_mode) {
            size_t end;
            while (alive && (end = after_mark(rx_ready)) == 0) alive = pump(-1);
            if (alive) rx_ready = end;
        } else if (alive) {
            alive = pump(0);
            rx_ready = rx_len;
        }
        if (!alive) {
            drop_peer();
            return PULLI_LINK_WAITING;
        }
    }
    frame_open = true;
    *side = my_side;
    return PULLI_LINK_CONNECTED;
}

bool host_link_send(const void *msg, size_t len) {
    uint8_t out[1 + PULLI_LINK_MSG_MAX];
    if (peer < 0 || len > PULLI_LINK_MSG_MAX) return false;
    out[0] = (uint8_t)len;
    memcpy(out + 1, msg, len);
    /* If the peer has just gone, the next poll reports it. Answering from
     * the socket here would make the result depend on timing. */
    (void)!send(peer, out, 1 + len, MSG_NOSIGNAL);
    return true;
}

int host_link_recv(void *msg, size_t max) {
    while (rx_ready > 0) {
        size_t used;
        int len = -1;
        if (rx[0] == FRAME_MARK) {
            used = 1;
        } else {
            used = 1 + (size_t)rx[0];
            if (used > rx_ready) return -1;         /* rest of it not here yet */
            len = rx[0];
            if ((size_t)len > max || len > PULLI_LINK_MSG_MAX) len = -2;   /* not ours: skip */
            else memcpy(msg, rx + 1, (size_t)len);
        }
        memmove(rx, rx + used, rx_len - used);
        rx_len -= used;
        rx_ready -= used;
        if (len >= 0) return len;
    }
    return -1;
}

void host_link_close(void) {
    /* Stop answering first, or the other side could reconnect to us while
     * we are on our way out. */
    if (listener >= 0) close(listener);
    listener = -1;
    /* Finish the last frame, so what was sent in it is still delivered. */
    if (peer >= 0 && frame_open) {
        const uint8_t mark = FRAME_MARK;
        uint8_t ignored[256];
        struct pollfd p = { peer, POLLIN, 0 };
        (void)!send(peer, &mark, 1, MSG_NOSIGNAL);
        /* Say goodbye and wait for the other side to hang up too. Closing
         * with its messages still unread would make the system discard
         * what we just sent before it had been read. */
        shutdown(peer, SHUT_WR);
        for (int waited = 0; waited < 1000 && poll(&p, 1, 50) >= 0; waited += 50)
            if ((p.revents & (POLLIN | POLLHUP | POLLERR)) && recv(peer, ignored, sizeof(ignored), 0) <= 0)
                break;
    }
    drop_peer();
    opened = false;
}

#endif
