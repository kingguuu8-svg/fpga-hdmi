#include <arpa/inet.h>
#include <drm/drm.h>
#include <drm/drm_fourcc.h>
#include <drm/drm_mode.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#include "video_udp_protocol.h"
#include "video_udp_receiver.h"

#ifndef DRM_MODE_CONNECTED
#define DRM_MODE_CONNECTED 1
#endif

typedef struct {
    const char *drm_path;
    uint16_t port;
    unsigned int frames;
    unsigned int timeout_seconds;
} app_config_t;

typedef struct {
    uint32_t handle;
    uint32_t fb_id;
    uint32_t pitch;
    uint64_t size;
    uint8_t *map;
} drm_buffer_t;

typedef struct {
    int fd;
    uint32_t connector_id;
    uint32_t crtc_id;
    struct drm_mode_modeinfo mode;
    drm_buffer_t buffers[2];
    unsigned int buffer_count;
    unsigned int page_flip_calls;
    unsigned int vblank_events;
} drm_target_t;

static void usage(const char *argv0)
{
    fprintf(stderr, "usage: %s [--drm /dev/dri/card0] [--port 5005] [--frames 60] [--timeout-sec 120]\n", argv0);
}

static int parse_u32(const char *text, unsigned int min, unsigned int max, unsigned int *out)
{
    char *end = 0;
    unsigned long value;

    errno = 0;
    value = strtoul(text, &end, 0);
    if (errno != 0 || end == text || *end != '\0' || value < min || value > max) {
        return -1;
    }
    *out = (unsigned int)value;
    return 0;
}

static int parse_args(int argc, char **argv, app_config_t *config)
{
    int i;

    config->drm_path = "/dev/dri/card0";
    config->port = VIDEO_UDP_DEFAULT_PORT;
    config->frames = 60u;
    config->timeout_seconds = 120u;

    for (i = 1; i < argc; i++) {
        unsigned int value;
        if (strcmp(argv[i], "--drm") == 0 && i + 1 < argc) {
            config->drm_path = argv[++i];
        } else if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) {
            if (parse_u32(argv[++i], 1u, 65535u, &value) != 0) {
                return -1;
            }
            config->port = (uint16_t)value;
        } else if (strcmp(argv[i], "--frames") == 0 && i + 1 < argc) {
            if (parse_u32(argv[++i], 1u, 1000000u, &config->frames) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "--timeout-sec") == 0 && i + 1 < argc) {
            if (parse_u32(argv[++i], 1u, 3600u, &config->timeout_seconds) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "--help") == 0) {
            usage(argv[0]);
            exit(0);
        } else {
            return -1;
        }
    }
    return 0;
}

static unsigned long long monotonic_ms(void)
{
    struct timeval tv;

    if (gettimeofday(&tv, 0) != 0) {
        return 0u;
    }
    return ((unsigned long long)tv.tv_sec * 1000ull) + ((unsigned long long)tv.tv_usec / 1000ull);
}

static int get_resources(
    int fd,
    struct drm_mode_card_res *res,
    uint32_t **fbs,
    uint32_t **connectors,
    uint32_t **crtcs,
    uint32_t **encoders)
{
    memset(res, 0, sizeof(*res));
    if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, res) != 0) {
        perror("DRM_IOCTL_MODE_GETRESOURCES count");
        return -1;
    }
    if (res->count_connectors == 0u || res->count_crtcs == 0u) {
        fprintf(stderr, "DRM_BLOCKER no connectors or crtcs connectors=%u crtcs=%u\n", res->count_connectors, res->count_crtcs);
        return -1;
    }

    *fbs = (uint32_t *)calloc(res->count_fbs ? res->count_fbs : 1u, sizeof(uint32_t));
    *connectors = (uint32_t *)calloc(res->count_connectors, sizeof(uint32_t));
    *crtcs = (uint32_t *)calloc(res->count_crtcs, sizeof(uint32_t));
    *encoders = (uint32_t *)calloc(res->count_encoders ? res->count_encoders : 1u, sizeof(uint32_t));
    if (*fbs == 0 || *connectors == 0 || *crtcs == 0 || *encoders == 0) {
        fprintf(stderr, "calloc resources failed\n");
        return -1;
    }

    res->fb_id_ptr = (uint64_t)(uintptr_t)(*fbs);
    res->connector_id_ptr = (uint64_t)(uintptr_t)(*connectors);
    res->crtc_id_ptr = (uint64_t)(uintptr_t)(*crtcs);
    res->encoder_id_ptr = (uint64_t)(uintptr_t)(*encoders);
    if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, res) != 0) {
        perror("DRM_IOCTL_MODE_GETRESOURCES ids");
        return -1;
    }
    return 0;
}

static int find_connected_output(drm_target_t *target)
{
    struct drm_mode_card_res res;
    uint32_t *fbs = 0;
    uint32_t *connectors = 0;
    uint32_t *crtcs = 0;
    uint32_t *encoders = 0;
    uint32_t i;
    int rc = -1;

    if (get_resources(target->fd, &res, &fbs, &connectors, &crtcs, &encoders) != 0) {
        goto cleanup;
    }

    for (i = 0; i < res.count_connectors; i++) {
        struct drm_mode_get_connector conn;
        struct drm_mode_modeinfo *modes = 0;
        uint32_t *connector_encoders = 0;
        uint32_t *props = 0;
        uint64_t *prop_values = 0;

        memset(&conn, 0, sizeof(conn));
        conn.connector_id = connectors[i];
        if (ioctl(target->fd, DRM_IOCTL_MODE_GETCONNECTOR, &conn) != 0) {
            continue;
        }
        printf("DRM_CONNECTOR_PROBE id=%u connection=%u modes=%u encoders=%u\n",
               conn.connector_id,
               conn.connection,
               conn.count_modes,
               conn.count_encoders);
        if (conn.count_modes == 0u) {
            continue;
        }
        modes = (struct drm_mode_modeinfo *)calloc(conn.count_modes, sizeof(*modes));
        if (modes == 0) {
            goto cleanup;
        }
        connector_encoders = (uint32_t *)calloc(conn.count_encoders ? conn.count_encoders : 1u, sizeof(uint32_t));
        props = (uint32_t *)calloc(conn.count_props ? conn.count_props : 1u, sizeof(uint32_t));
        prop_values = (uint64_t *)calloc(conn.count_props ? conn.count_props : 1u, sizeof(uint64_t));
        if (connector_encoders == 0 || props == 0 || prop_values == 0) {
            free(modes);
            free(connector_encoders);
            free(props);
            free(prop_values);
            goto cleanup;
        }
        conn.modes_ptr = (uint64_t)(uintptr_t)modes;
        conn.encoders_ptr = (uint64_t)(uintptr_t)connector_encoders;
        conn.props_ptr = (uint64_t)(uintptr_t)props;
        conn.prop_values_ptr = (uint64_t)(uintptr_t)prop_values;
        if (ioctl(target->fd, DRM_IOCTL_MODE_GETCONNECTOR, &conn) != 0) {
            perror("DRM_IOCTL_MODE_GETCONNECTOR fill");
            free(modes);
            free(connector_encoders);
            free(props);
            free(prop_values);
            continue;
        }
        printf("DRM_CONNECTOR_MODE id=%u connection=%u modes=%u first_mode=%ux%u name=%s\n",
               conn.connector_id,
               conn.connection,
               conn.count_modes,
               modes[0].hdisplay,
               modes[0].vdisplay,
               modes[0].name);
        target->connector_id = conn.connector_id;
        target->crtc_id = crtcs[0];
        target->mode = modes[0];
        printf("DRM_OUTPUT connector=%u crtc=%u mode=%ux%u refresh=%u name=%s\n",
               target->connector_id,
               target->crtc_id,
               target->mode.hdisplay,
               target->mode.vdisplay,
               target->mode.vrefresh,
               target->mode.name);
        free(modes);
        free(connector_encoders);
        free(props);
        free(prop_values);
        rc = 0;
        break;
    }

    if (rc != 0) {
        fprintf(stderr, "DRM_BLOCKER no connector with modes\n");
    }

cleanup:
    free(fbs);
    free(connectors);
    free(crtcs);
    free(encoders);
    return rc;
}

static int create_buffer(drm_target_t *target, drm_buffer_t *buffer, uint32_t width, uint32_t height)
{
    struct drm_mode_create_dumb create;
    struct drm_mode_fb_cmd2 fb;
    struct drm_mode_map_dumb map_req;
    uint32_t handles[4] = {0, 0, 0, 0};
    uint32_t pitches[4] = {0, 0, 0, 0};
    uint32_t offsets[4] = {0, 0, 0, 0};

    memset(&create, 0, sizeof(create));
    create.width = width;
    create.height = height;
    create.bpp = 24;
    if (ioctl(target->fd, DRM_IOCTL_MODE_CREATE_DUMB, &create) != 0) {
        perror("DRM_IOCTL_MODE_CREATE_DUMB");
        return -1;
    }

    buffer->handle = create.handle;
    buffer->pitch = create.pitch;
    buffer->size = create.size;

    handles[0] = buffer->handle;
    pitches[0] = buffer->pitch;
    memset(&fb, 0, sizeof(fb));
    fb.width = width;
    fb.height = height;
    fb.pixel_format = DRM_FORMAT_RGB888;
    memcpy(fb.handles, handles, sizeof(handles));
    memcpy(fb.pitches, pitches, sizeof(pitches));
    memcpy(fb.offsets, offsets, sizeof(offsets));
    if (ioctl(target->fd, DRM_IOCTL_MODE_ADDFB2, &fb) != 0) {
        perror("DRM_IOCTL_MODE_ADDFB2 RGB888");
        return -1;
    }
    buffer->fb_id = fb.fb_id;

    memset(&map_req, 0, sizeof(map_req));
    map_req.handle = buffer->handle;
    if (ioctl(target->fd, DRM_IOCTL_MODE_MAP_DUMB, &map_req) != 0) {
        perror("DRM_IOCTL_MODE_MAP_DUMB");
        return -1;
    }
    buffer->map = (uint8_t *)mmap(0, buffer->size, PROT_READ | PROT_WRITE, MAP_SHARED, target->fd, (off_t)map_req.offset);
    if (buffer->map == MAP_FAILED) {
        buffer->map = 0;
        perror("mmap dumb buffer");
        return -1;
    }
    memset(buffer->map, 0, buffer->size);
    return 0;
}

static int copy_frame_to_buffer(drm_buffer_t *buffer, const uint8_t *frame, uint32_t width, uint32_t height)
{
    uint32_t y;
    size_t row_bytes = (size_t)width * 3u;

    if (buffer->pitch < row_bytes || buffer->size < (uint64_t)buffer->pitch * height) {
        fprintf(stderr, "dumb buffer stride/size too small\n");
        return -1;
    }
    for (y = 0; y < height; y++) {
        memcpy(buffer->map + ((size_t)y * buffer->pitch), frame + ((size_t)y * row_bytes), row_bytes);
    }
    return 0;
}

static int init_drm(const char *path, drm_target_t *target)
{
    uint32_t connector;

    memset(target, 0, sizeof(*target));
    target->fd = open(path, O_RDWR | O_CLOEXEC);
    if (target->fd < 0) {
        perror("open drm");
        return -1;
    }
    if (find_connected_output(target) != 0) {
        return -1;
    }
    if (target->mode.hdisplay != VIDEO_UDP_DEFAULT_WIDTH || target->mode.vdisplay != VIDEO_UDP_DEFAULT_HEIGHT) {
        fprintf(stderr, "DRM_BLOCKER mode is not 800x600: %ux%u\n", target->mode.hdisplay, target->mode.vdisplay);
        return -1;
    }
    if (create_buffer(target, &target->buffers[0], target->mode.hdisplay, target->mode.vdisplay) != 0 ||
        create_buffer(target, &target->buffers[1], target->mode.hdisplay, target->mode.vdisplay) != 0) {
        return -1;
    }
    target->buffer_count = 2u;
    connector = target->connector_id;
    if (ioctl(target->fd, DRM_IOCTL_MODE_SETCRTC, &(struct drm_mode_crtc){
            .set_connectors_ptr = (uint64_t)(uintptr_t)&connector,
            .count_connectors = 1,
            .crtc_id = target->crtc_id,
            .fb_id = target->buffers[0].fb_id,
            .mode = target->mode,
            .mode_valid = 1}) != 0) {
        perror("DRM_IOCTL_MODE_SETCRTC");
        return -1;
    }
    printf("DRM_DUMB_BUFFERS count=2 width=%u height=%u pitch0=%u pitch1=%u format=RGB888\n",
           target->mode.hdisplay,
           target->mode.vdisplay,
           target->buffers[0].pitch,
           target->buffers[1].pitch);
    return 0;
}

static int wait_page_flip_event(drm_target_t *target, uint32_t frame_id)
{
    uint8_t buffer[256];
    ssize_t got;
    struct drm_event *event;
    struct drm_event_vblank *vblank;

    got = read(target->fd, buffer, sizeof(buffer));
    if (got < (ssize_t)sizeof(struct drm_event)) {
        perror("read drm event");
        return -1;
    }
    event = (struct drm_event *)buffer;
    if (event->type != DRM_EVENT_FLIP_COMPLETE || event->length < sizeof(struct drm_event_vblank)) {
        fprintf(stderr, "unexpected drm event type=%u length=%u\n", event->type, event->length);
        return -1;
    }
    vblank = (struct drm_event_vblank *)buffer;
    target->vblank_events++;
    printf("DRM_PAGE_FLIP_EVENT frame_id=%u event_count=%u sequence=%u tv_sec=%u tv_usec=%u user_data=%llu\n",
           frame_id,
           target->vblank_events,
           vblank->sequence,
           vblank->tv_sec,
           vblank->tv_usec,
           (unsigned long long)vblank->user_data);
    fflush(stdout);
    return 0;
}

static int submit_page_flip(drm_target_t *target, unsigned int buffer_index, uint32_t frame_id)
{
    struct drm_mode_crtc_page_flip flip;

    memset(&flip, 0, sizeof(flip));
    flip.crtc_id = target->crtc_id;
    flip.fb_id = target->buffers[buffer_index].fb_id;
    flip.flags = DRM_MODE_PAGE_FLIP_EVENT;
    flip.user_data = (uint64_t)frame_id;
    if (ioctl(target->fd, DRM_IOCTL_MODE_PAGE_FLIP, &flip) != 0) {
        perror("DRM_IOCTL_MODE_PAGE_FLIP");
        return -1;
    }
    target->page_flip_calls++;
    printf("DRM_PAGE_FLIP_SUBMITTED frame_id=%u submit_count=%u fb_id=%u buffer=%u\n",
           frame_id,
           target->page_flip_calls,
           flip.fb_id,
           buffer_index);
    fflush(stdout);
    return wait_page_flip_event(target, frame_id);
}

static int open_udp_socket(uint16_t port, unsigned int timeout_seconds)
{
    int fd;
    int yes = 1;
    int rcvbuf = 32 * 1024 * 1024;
    struct timeval timeout;
    struct sockaddr_in addr;

    fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) {
        perror("socket");
        return -1;
    }
    (void)setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    (void)setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof(rcvbuf));
    timeout.tv_sec = (time_t)timeout_seconds;
    timeout.tv_usec = 0;
    if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) != 0) {
        perror("SO_RCVTIMEO");
        close(fd);
        return -1;
    }
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(port);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        perror("bind");
        close(fd);
        return -1;
    }
    return fd;
}

int main(int argc, char **argv)
{
    app_config_t config;
    drm_target_t drm;
    video_udp_receiver_t receiver;
    uint8_t *buffer_a = 0;
    uint8_t *buffer_b = 0;
    uint8_t packet[VIDEO_UDP_HEADER_LEN + VIDEO_UDP_CHUNK_BYTES];
    unsigned int packets = 0u;
    unsigned int frames_written = 0u;
    unsigned int buffer_index = 1u;
    unsigned long long start_ms;
    int sock = -1;
    int exit_code = 1;

    if (parse_args(argc, argv, &config) != 0) {
        usage(argv[0]);
        return 1;
    }
    buffer_a = (uint8_t *)malloc(VIDEO_UDP_FRAME_BYTES);
    buffer_b = (uint8_t *)malloc(VIDEO_UDP_FRAME_BYTES);
    if (buffer_a == 0 || buffer_b == 0) {
        fprintf(stderr, "failed to allocate frame buffers\n");
        goto cleanup;
    }
    if (init_drm(config.drm_path, &drm) != 0) {
        goto cleanup;
    }
    sock = open_udp_socket(config.port, config.timeout_seconds);
    if (sock < 0) {
        goto cleanup;
    }
    video_udp_receiver_init(&receiver, buffer_a, buffer_b);
    printf("VIDEO_UDP_DRM_RECEIVER_READY display_backend=drm-kms drm_device=%s frames=%u port=%u fbdev_live_write_used=0 motion_content_type=textured-motion\n",
           config.drm_path,
           config.frames,
           config.port);
    fflush(stdout);
    start_ms = monotonic_ms();

    while (frames_written < config.frames) {
        ssize_t got;
        int rc;

        if (monotonic_ms() - start_ms > (unsigned long long)config.timeout_seconds * 1000ull) {
            fprintf(stderr, "receive timeout after %u seconds\n", config.timeout_seconds);
            goto cleanup;
        }
        got = recv(sock, packet, sizeof(packet), 0);
        if (got < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
                continue;
            }
            perror("recv");
            goto cleanup;
        }
        packets++;
        rc = video_udp_receiver_on_packet(&receiver, packet, (size_t)got);
        if (rc < 0) {
            continue;
        }
        if (rc == 1) {
            const uint8_t *frame = video_udp_receiver_active_frame(&receiver);
            if (copy_frame_to_buffer(&drm.buffers[buffer_index], frame, VIDEO_UDP_DEFAULT_WIDTH, VIDEO_UDP_DEFAULT_HEIGHT) != 0) {
                goto cleanup;
            }
            if (submit_page_flip(&drm, buffer_index, receiver.frame_id) != 0) {
                goto cleanup;
            }
            frames_written++;
            printf("VIDEO_UDP_DRM_FRAME_WRITTEN frame_id=%lu frames=%u packets=%u dropped=%lu elapsed_ms=%llu\n",
                   (unsigned long)receiver.frame_id,
                   frames_written,
                   packets,
                   (unsigned long)receiver.dropped_packets,
                   monotonic_ms() - start_ms);
            fflush(stdout);
            buffer_index = 1u - buffer_index;
        }
    }

    printf("VIDEO_UDP_DRM_RECEIVER_DONE display_backend=drm-kms fbdev_live_write_used=0 frames=%u packets=%u dropped=%lu drm_dumb_buffers=%u drm_page_flip_calls=%u drm_vblank_flip_events=%u elapsed_ms=%llu\n",
           frames_written,
           packets,
           (unsigned long)receiver.dropped_packets,
           drm.buffer_count,
           drm.page_flip_calls,
           drm.vblank_events,
           monotonic_ms() - start_ms);
    exit_code = 0;

cleanup:
    if (sock >= 0) {
        close(sock);
    }
    free(buffer_a);
    free(buffer_b);
    return exit_code;
}
