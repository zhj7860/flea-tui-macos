// flea-framecap records one output as H, F and D lines for tools/flea-field-search.
static const char usage[] =
    "usage: flea-framecap [-h] [-O OUTPUT] [-r X,Y,W,H] [-m X,Y,W,H]... [-d PREFIX] [-w X,Y,W,H] [-o FILE]\n"
    "Records one output through ext-image-copy-capture-v1 and prints one line per presented frame.\n"
    "Options: -O records the output with this name, default the first; -r sets the compared region;\n"
    "-m excludes a rectangle from the comparison, repeatable; -d writes the newest frame to PREFIX-N.ppm\n"
    "on SIGUSR1, masks not applied; -w sets the rectangle -d writes, default the region;\n"
    "-o writes the lines to FILE instead of stdout; -h prints this text.\n"
    "Lines: H <width> <height> <wl_shm format> <monotonic ns at start>\n"
    "F <presentation ns> <received ns> <changed rows> <first row> <last row> <first column> <last column> <ink rows>\n"
    "A frame the compositor sends with no presentation_time event prints 0 for the presentation ns.\n"
    "D <path> <monotonic ns>\n"
    "Times are CLOCK_MONOTONIC ns. The first F line has no frame before it and reports -1 changed rows.\n"
    "Rows and columns are output coordinates. Ink rows count region rows holding more than one colour on a changed\n"
    "frame, masks not applied, and are -1 on an unchanged frame.\n"
    "Exit codes: 0 stopped by a signal; 1 setup failure; 2 bad argument or no output named by -O; 3 capture or display\n"
    "failure.\n";
#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include "ext-image-capture-source-v1-client-protocol.h"
#include "ext-image-copy-capture-v1-client-protocol.h"

#define MAX_MASKS 8
#define MAX_OUTPUTS 16
// Roundtrips waited for the compositor to deliver every output name.
#define NAME_ROUNDTRIPS 10
#define NS_PER_SEC 1000000000ull
#define EXIT_SETUP 1
#define EXIT_ARGUMENT 2
#define EXIT_CAPTURE 3

struct rect { int x, y, w, h; };
struct output_entry { struct wl_output *output; char *name; };

static struct wl_shm *shm;
static struct wl_output *output;
static const char *want_output;
static struct output_entry outputs[MAX_OUTPUTS];
static int output_count;
static struct ext_output_image_capture_source_manager_v1 *source_mgr;
static struct ext_image_copy_capture_manager_v1 *copy_mgr;
static struct ext_image_copy_capture_session_v1 *session;
static struct ext_image_copy_capture_frame_v1 *frame;
static struct wl_display *display;

static uint32_t buf_w, buf_h, buf_format;
static int have_format, session_done;
static uint8_t *pixels[2];
static struct wl_buffer *buffers[2];
static int cur, frames_seen, newest = -1;
static uint64_t present_ns;

static struct rect region, dump_rect, masks[MAX_MASKS];
static int mask_count, have_region, have_dump_rect;
static FILE *out;
static const char *dump_prefix;
static volatile sig_atomic_t quit, dump_req;
static int dump_n, capture_failed;

static uint64_t mono_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * NS_PER_SEC + (uint64_t)ts.tv_nsec;
}

static void die(int code, const char *what)
{
    fprintf(stderr, "flea-framecap: %s\n", what);
    exit(code);
}

// Parses "-r 10,20,800,600" into a rect, true when all four numbers are present.
static int parse_rect(const char *s, struct rect *r)
{
    return sscanf(s, "%d,%d,%d,%d", &r->x, &r->y, &r->w, &r->h) == 4 && r->w > 0 && r->h > 0;
}

static int col_lo, col_hi;

// True when row y differs outside every mask, widening col_lo and col_hi.
static int row_differs(int y, const uint8_t *a, const uint8_t *b)
{
    int x0 = region.x, x1 = region.x + region.w, i;
    // Collect the masked x-intervals this row crosses, then walk the gaps between them left to right.
    int lo[MAX_MASKS], hi[MAX_MASKS], m = 0;
    for (i = 0; i < mask_count; i++) {
        if (y < masks[i].y || y >= masks[i].y + masks[i].h) continue;
        lo[m] = masks[i].x < x0 ? x0 : masks[i].x;
        hi[m] = masks[i].x + masks[i].w > x1 ? x1 : masks[i].x + masks[i].w;
        if (lo[m] < hi[m]) m++;
    }
    // Insertion sort by start, at most MAX_MASKS entries.
    for (i = 1; i < m; i++) {
        int l = lo[i], h = hi[i], j = i - 1;
        while (j >= 0 && lo[j] > l) { lo[j + 1] = lo[j]; hi[j + 1] = hi[j]; j--; }
        lo[j + 1] = l; hi[j + 1] = h;
    }
    size_t row = (size_t)y * buf_w * 4;
    int at = x0, differs = 0;
    for (i = 0; i <= m; i++) {
        int end = i < m ? lo[i] : x1;
        if (end > at && memcmp(a + row + (size_t)at * 4, b + row + (size_t)at * 4, (size_t)(end - at) * 4) != 0) {
            // Only a changed row pays for the pixel walk that says where in the row.
            int x;
            differs = 1;
            for (x = at; x < end; x++) {
                if (memcmp(a + row + (size_t)x * 4, b + row + (size_t)x * 4, 4) == 0) continue;
                if (x < col_lo) col_lo = x;
                if (x > col_hi) col_hi = x;
            }
        }
        if (i < m && hi[i] > at) at = hi[i];
    }
    return differs;
}

// A row holds ink when its pixels are not all the colour of its first pixel.
static int row_has_ink(int y, const uint8_t *a)
{
    const uint32_t *p = (const uint32_t *)(const void *)(a + (size_t)y * buf_w * 4);
    int x;
    for (x = region.x + 1; x < region.x + region.w; x++)
        if (p[x] != p[region.x]) return 1;
    return 0;
}

static void write_dump(void)
{
    char path[512];
    FILE *f;
    int y, x, bgr;
    if (!dump_prefix || newest < 0) return;
    bgr = buf_format == WL_SHM_FORMAT_XBGR8888 || buf_format == WL_SHM_FORMAT_ABGR8888;
    snprintf(path, sizeof path, "%s-%d.ppm", dump_prefix, dump_n++);
    f = fopen(path, "wb");
    if (!f) { fprintf(stderr, "flea-framecap: cannot write %s: %s\n", path, strerror(errno)); return; }
    fprintf(f, "P6\n%d %d\n255\n", dump_rect.w, dump_rect.h);
    for (y = dump_rect.y; y < dump_rect.y + dump_rect.h; y++) {
        const uint8_t *p = pixels[newest] + ((size_t)y * buf_w + dump_rect.x) * 4;
        for (x = 0; x < dump_rect.w; x++, p += 4) { fputc(p[bgr ? 0 : 2], f); fputc(p[1], f); fputc(p[bgr ? 2 : 0], f); }
    }
    fclose(f);
    fprintf(out, "D %s %llu\n", path, (unsigned long long)mono_ns());
    fflush(out);
}

static void request_frame(void);

static void frame_transform(void *d, struct ext_image_copy_capture_frame_v1 *f, uint32_t t) { (void)d; (void)f; (void)t; }
static void frame_damage(void *d, struct ext_image_copy_capture_frame_v1 *f, int32_t x, int32_t y, int32_t w, int32_t h)
{ (void)d; (void)f; (void)x; (void)y; (void)w; (void)h; }

static void frame_time(void *d, struct ext_image_copy_capture_frame_v1 *f, uint32_t hi, uint32_t lo, uint32_t nsec)
{
    (void)d; (void)f;
    present_ns = (((uint64_t)hi << 32) + lo) * NS_PER_SEC + nsec;
}

static void frame_ready(void *d, struct ext_image_copy_capture_frame_v1 *f)
{
    uint64_t recv = mono_ns();
    int changed = -1, first = -1, last = -1, ink = -1, y;
    (void)d;
    col_lo = (int)buf_w;
    col_hi = -1;
    if (frames_seen > 0) {
        const uint8_t *a = pixels[cur], *b = pixels[cur ^ 1];
        changed = 0;
        for (y = region.y; y < region.y + region.h; y++) {
            if (!row_differs(y, a, b)) continue;
            if (first < 0) first = y;
            last = y;
            changed++;
        }
        if (changed > 0) {
            ink = 0;
            for (y = region.y; y < region.y + region.h; y++) ink += row_has_ink(y, a);
        }
    }
    fprintf(out, "F %llu %llu %d %d %d %d %d %d\n", (unsigned long long)present_ns, (unsigned long long)recv, changed,
            first, last, changed > 0 ? col_lo : -1, col_hi, ink);
    fflush(out);
    newest = cur;
    frames_seen++;
    cur ^= 1;
    ext_image_copy_capture_frame_v1_destroy(f);
    frame = NULL;
    request_frame();
}

static void frame_failed(void *d, struct ext_image_copy_capture_frame_v1 *f, uint32_t reason)
{
    (void)d;
    ext_image_copy_capture_frame_v1_destroy(f);
    frame = NULL;
    fprintf(stderr, "flea-framecap: a frame failed, reason %u\n", reason);
    capture_failed = 1;
    quit = 1;
}

static const struct ext_image_copy_capture_frame_v1_listener frame_listener = {
    frame_transform, frame_damage, frame_time, frame_ready, frame_failed,
};

static void request_frame(void)
{
    if (quit || !session_done) return;
    // A frame without a presentation_time event prints 0, never the previous frame's stamp.
    present_ns = 0;
    frame = ext_image_copy_capture_session_v1_create_frame(session);
    ext_image_copy_capture_frame_v1_add_listener(frame, &frame_listener, NULL);
    ext_image_copy_capture_frame_v1_attach_buffer(frame, buffers[cur]);
    ext_image_copy_capture_frame_v1_damage_buffer(frame, 0, 0, (int32_t)buf_w, (int32_t)buf_h);
    ext_image_copy_capture_frame_v1_capture(frame);
}

static void session_size(void *d, struct ext_image_copy_capture_session_v1 *s, uint32_t w, uint32_t h)
{ (void)d; (void)s; buf_w = w; buf_h = h; }

static void session_format(void *d, struct ext_image_copy_capture_session_v1 *s, uint32_t fmt)
{
    (void)d; (void)s;
    // 32 bit formats only: the comparison reads four bytes a pixel.
    if (!have_format && (fmt == WL_SHM_FORMAT_XRGB8888 || fmt == WL_SHM_FORMAT_ARGB8888 ||
                         fmt == WL_SHM_FORMAT_XBGR8888 || fmt == WL_SHM_FORMAT_ABGR8888)) {
        buf_format = fmt;
        have_format = 1;
    }
}

static void session_dmabuf_device(void *d, struct ext_image_copy_capture_session_v1 *s, struct wl_array *a)
{ (void)d; (void)s; (void)a; }
static void session_dmabuf_format(void *d, struct ext_image_copy_capture_session_v1 *s, uint32_t f, struct wl_array *a)
{ (void)d; (void)s; (void)f; (void)a; }

static void session_done_ev(void *d, struct ext_image_copy_capture_session_v1 *s)
{
    size_t size;
    int fd, i;
    struct wl_shm_pool *pool;
    (void)d; (void)s;
    if (session_done) return;
    if (!have_format || !buf_w || !buf_h) die(EXIT_SETUP, "the compositor offered no 32 bit shm format");
    size = (size_t)buf_w * buf_h * 4;
    fd = memfd_create("flea-framecap", 0);
    if (fd < 0 || ftruncate(fd, (off_t)(size * 2)) != 0) die(EXIT_SETUP, "memfd for the capture buffers");
    pixels[0] = mmap(NULL, size * 2, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (pixels[0] == MAP_FAILED) die(EXIT_SETUP, "mmap of the capture buffers");
    pixels[1] = pixels[0] + size;
    pool = wl_shm_create_pool(shm, fd, (int32_t)(size * 2));
    for (i = 0; i < 2; i++)
        buffers[i] = wl_shm_pool_create_buffer(pool, (int32_t)(size * (size_t)i), (int32_t)buf_w, (int32_t)buf_h,
                                               (int32_t)(buf_w * 4), buf_format);
    wl_shm_pool_destroy(pool);
    close(fd);
    if (!have_region) { region.x = 0; region.y = 0; region.w = (int)buf_w; region.h = (int)buf_h; }
    if (!have_dump_rect) dump_rect = region;
    if (region.x < 0 || region.y < 0 || region.x + region.w > (int)buf_w || region.y + region.h > (int)buf_h)
        die(EXIT_ARGUMENT, "the region lies outside the output");
    if (dump_rect.x < 0 || dump_rect.y < 0 || dump_rect.x + dump_rect.w > (int)buf_w ||
        dump_rect.y + dump_rect.h > (int)buf_h)
        die(EXIT_ARGUMENT, "the -w rectangle lies outside the output");
    session_done = 1;
    fprintf(out, "H %u %u %u %llu\n", buf_w, buf_h, buf_format, (unsigned long long)mono_ns());
    fflush(out);
    request_frame();
}

static void session_stopped(void *d, struct ext_image_copy_capture_session_v1 *s)
{ (void)d; (void)s; fprintf(stderr, "flea-framecap: the capture session stopped\n"); capture_failed = 1; quit = 1; }

static const struct ext_image_copy_capture_session_v1_listener session_listener = {
    session_size, session_format, session_dmabuf_device, session_dmabuf_format, session_done_ev, session_stopped,
};

static void out_geometry(void *d, struct wl_output *o, int32_t x, int32_t y, int32_t pw, int32_t ph, int32_t sp,
                         const char *make, const char *model, int32_t tr)
{ (void)d; (void)o; (void)x; (void)y; (void)pw; (void)ph; (void)sp; (void)make; (void)model; (void)tr; }
static void out_mode(void *d, struct wl_output *o, uint32_t fl, int32_t w, int32_t h, int32_t r)
{ (void)d; (void)o; (void)fl; (void)w; (void)h; (void)r; }
static void out_done(void *d, struct wl_output *o) { (void)d; (void)o; }
static void out_scale(void *d, struct wl_output *o, int32_t f) { (void)d; (void)o; (void)f; }
static void out_name(void *d, struct wl_output *o, const char *name)
{
    struct output_entry *e = d;
    (void)o;
    free(e->name);
    e->name = strdup(name);
}
static void out_desc(void *d, struct wl_output *o, const char *desc) { (void)d; (void)o; (void)desc; }

static const struct wl_output_listener output_listener = {
    out_geometry, out_mode, out_done, out_scale, out_name, out_desc,
};

static void global_add(void *d, struct wl_registry *reg, uint32_t name, const char *iface, uint32_t version)
{
    (void)d;
    if (strcmp(iface, "wl_shm") == 0) {
        shm = wl_registry_bind(reg, name, &wl_shm_interface, 1);
    } else if (strcmp(iface, "wl_output") == 0) {
        // Keeps every output; main picks by name once the roundtrips deliver the names.
        struct wl_output *o;
        if (output_count == MAX_OUTPUTS) return;
        o = wl_registry_bind(reg, name, &wl_output_interface, version < 4 ? version : 4);
        outputs[output_count].output = o;
        outputs[output_count].name = NULL;
        wl_output_add_listener(o, &output_listener, &outputs[output_count]);
        output_count++;
    } else if (strcmp(iface, "ext_output_image_capture_source_manager_v1") == 0) {
        source_mgr = wl_registry_bind(reg, name, &ext_output_image_capture_source_manager_v1_interface, 1);
    } else if (strcmp(iface, "ext_image_copy_capture_manager_v1") == 0) {
        copy_mgr = wl_registry_bind(reg, name, &ext_image_copy_capture_manager_v1_interface, 1);
    }
}
static void global_remove(void *d, struct wl_registry *reg, uint32_t name) { (void)d; (void)reg; (void)name; }
static const struct wl_registry_listener registry_listener = { global_add, global_remove };

static void on_signal(int sig)
{
    if (sig == SIGUSR1) dump_req = 1;
    else quit = 1;
}

int main(int argc, char **argv)
{
    struct wl_registry *registry;
    struct ext_image_capture_source_v1 *source;
    struct sigaction sa;
    int opt, i, j, named, chosen = -1;
    out = stdout;
    while ((opt = getopt(argc, argv, "O:r:m:d:w:o:h")) != -1) {
        switch (opt) {
        case 'O': want_output = optarg; break;
        case 'r':
            if (!parse_rect(optarg, &region)) die(EXIT_ARGUMENT, "-r wants X,Y,W,H");
            have_region = 1;
            break;
        case 'm':
            if (mask_count == MAX_MASKS) die(EXIT_ARGUMENT, "too many -m masks");
            if (!parse_rect(optarg, &masks[mask_count])) die(EXIT_ARGUMENT, "-m wants X,Y,W,H");
            mask_count++;
            break;
        case 'd': dump_prefix = optarg; break;
        case 'w':
            if (!parse_rect(optarg, &dump_rect)) die(EXIT_ARGUMENT, "-w wants X,Y,W,H");
            have_dump_rect = 1;
            break;
        case 'o':
            out = fopen(optarg, "w");
            if (!out) die(EXIT_SETUP, "cannot open the -o file");
            break;
        case 'h': printf("%s", usage); return 0;
        default: fprintf(stderr, "%s", usage); return EXIT_ARGUMENT;
        }
    }
    if (optind < argc) { fprintf(stderr, "%s", usage); return EXIT_ARGUMENT; }
    display = wl_display_connect(NULL);
    if (!display) die(EXIT_SETUP, "cannot connect to the compositor (is WAYLAND_DISPLAY set?)");
    registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    for (i = 0; i < NAME_ROUNDTRIPS; i++) {
        named = 1;
        wl_display_roundtrip(display);
        for (j = 0; j < output_count; j++) if (!outputs[j].name) named = 0;
        if (named) break;
    }
    if (!shm || !output_count || !source_mgr || !copy_mgr)
        die(EXIT_SETUP, "the compositor lacks wl_shm, wl_output, ext_output_image_capture_source_manager_v1 or ext_image_copy_capture_manager_v1");
    for (i = 0; i < output_count; i++) {
        int match = want_output ? (outputs[i].name && strcmp(outputs[i].name, want_output) == 0) : i == 0;
        if (match && chosen < 0) chosen = i;
    }
    if (chosen < 0) {
        // Only a -O name can miss here (no output at all dies above); it is a bad argument, so name what was sent.
        fprintf(stderr, "flea-framecap: no output named \"%s\"; outputs:", want_output);
        for (i = 0; i < output_count; i++)
            fprintf(stderr, "%s%s", i ? ", " : " ", outputs[i].name ? outputs[i].name : "(unnamed)");
        fprintf(stderr, "\n");
        return EXIT_ARGUMENT;
    }
    output = outputs[chosen].output;
    for (i = 0; i < output_count; i++) if (i != chosen) wl_output_destroy(outputs[i].output);
    source = ext_output_image_capture_source_manager_v1_create_source(source_mgr, output);
    session = ext_image_copy_capture_manager_v1_create_session(copy_mgr, source, 0);
    ext_image_copy_capture_session_v1_add_listener(session, &session_listener, NULL);
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_signal;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGUSR1, &sa, NULL);
    while (!quit) {
        struct pollfd pfd;
        int r;
        while (wl_display_prepare_read(display) != 0)
            if (wl_display_dispatch_pending(display) < 0) { fprintf(stderr, "flea-framecap: the display failed before polling\n"); capture_failed = 1; quit = 1; break; }
        if (quit) break;
        if (wl_display_flush(display) < 0 && errno != EAGAIN) { fprintf(stderr, "flea-framecap: the display failed on flush\n"); capture_failed = 1; quit = 1; break; }
        pfd.fd = wl_display_get_fd(display);
        pfd.events = POLLIN;
        r = poll(&pfd, 1, 50);
        if (r > 0) {
            if (pfd.revents & (POLLHUP | POLLERR)) { wl_display_cancel_read(display); fprintf(stderr, "flea-framecap: the display hung up\n"); capture_failed = 1; quit = 1; break; }
            if (wl_display_read_events(display) < 0) { fprintf(stderr, "flea-framecap: the display failed on read\n"); capture_failed = 1; quit = 1; break; }
        } else {
            wl_display_cancel_read(display);
            if (r < 0 && errno != EINTR) { fprintf(stderr, "flea-framecap: poll failed: %s\n", strerror(errno)); capture_failed = 1; quit = 1; break; }
        }
        if (wl_display_dispatch_pending(display) < 0) { fprintf(stderr, "flea-framecap: the display failed on dispatch\n"); capture_failed = 1; quit = 1; break; }
        if (dump_req) { dump_req = 0; write_dump(); }
    }
    fflush(out);
    return capture_failed ? EXIT_CAPTURE : 0;
}
