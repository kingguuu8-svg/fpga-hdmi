#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <netinet/in.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

#include "video_control.h"
#include "video_effect.h"
#include "video_framebuffer.h"
#include "video_udp_protocol.h"
#include "video_udp_receiver.h"

typedef struct {
    const char *fb_path;
    uint16_t port;
    unsigned int frames;
    unsigned int timeout_seconds;
    const char *control_fifo_path;
    video_effect_t effect;
    int framebuffer_msync;
    unsigned int present_interval_ms;
} app_config_t;

typedef struct {
    int fd;
    uint8_t *map;
    size_t map_len;
    unsigned int red_byte;
    unsigned int green_byte;
    unsigned int blue_byte;
    struct fb_fix_screeninfo fix;
    struct fb_var_screeninfo var;
} fb_target_t;

static void usage(const char *argv0)
{
    fprintf(stderr,
            "usage: %s [--fb /dev/fb0] [--port 5005] [--frames 1] [--timeout-sec 20] [--control-fifo /tmp/video_ctl] [--effect none|invert] [--sync-mode msync|none] [--present-fps 15]\n",
            argv0);
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

    config->fb_path = "/dev/fb0";
    config->port = VIDEO_UDP_DEFAULT_PORT;
    config->frames = 1u;
    config->timeout_seconds = 20u;
    config->control_fifo_path = 0;
    config->effect = VIDEO_EFFECT_NONE;
    config->framebuffer_msync = 1;
    config->present_interval_ms = 0u;

    for (i = 1; i < argc; i++) {
        unsigned int value;
        if (strcmp(argv[i], "--fb") == 0 && i + 1 < argc) {
            config->fb_path = argv[++i];
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
        } else if (strcmp(argv[i], "--control-fifo") == 0 && i + 1 < argc) {
            config->control_fifo_path = argv[++i];
        } else if (strcmp(argv[i], "--effect") == 0 && i + 1 < argc) {
            if (video_effect_parse(argv[++i], &config->effect) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "--sync-mode") == 0 && i + 1 < argc) {
            const char *mode = argv[++i];
            if (strcmp(mode, "msync") == 0) {
                config->framebuffer_msync = 1;
            } else if (strcmp(mode, "none") == 0) {
                config->framebuffer_msync = 0;
            } else {
                return -1;
            }
        } else if (strcmp(argv[i], "--present-fps") == 0 && i + 1 < argc) {
            if (parse_u32(argv[++i], 1u, 120u, &value) != 0) {
                return -1;
            }
            config->present_interval_ms = (1000u + value - 1u) / value;
        } else if (strcmp(argv[i], "--help") == 0) {
            usage(argv[0]);
            exit(0);
        } else {
            return -1;
        }
    }

    return 0;
}

static int open_framebuffer(const char *path, fb_target_t *target)
{
    size_t min_map_len;

    memset(target, 0, sizeof(*target));
    target->fd = -1;
    target->fd = open(path, O_RDWR);
    if (target->fd < 0) {
        perror("open framebuffer");
        return -1;
    }
    if (ioctl(target->fd, FBIOGET_FSCREENINFO, &target->fix) != 0) {
        perror("FBIOGET_FSCREENINFO");
        return -1;
    }
    if (ioctl(target->fd, FBIOGET_VSCREENINFO, &target->var) != 0) {
        perror("FBIOGET_VSCREENINFO");
        return -1;
    }

    printf("FB_INFO path=%s xres=%u yres=%u xres_virtual=%u yres_virtual=%u bpp=%u line_length=%u smem_len=%u red_offset=%u green_offset=%u blue_offset=%u\n",
           path,
           target->var.xres,
           target->var.yres,
           target->var.xres_virtual,
           target->var.yres_virtual,
           target->var.bits_per_pixel,
           target->fix.line_length,
           target->fix.smem_len,
           target->var.red.offset,
           target->var.green.offset,
           target->var.blue.offset);

    if (target->var.xres < VIDEO_UDP_DEFAULT_WIDTH ||
        target->var.yres < VIDEO_UDP_DEFAULT_HEIGHT ||
        target->var.bits_per_pixel != 24u ||
        target->fix.line_length < VIDEO_UDP_DEFAULT_WIDTH * VIDEO_UDP_BYTES_PER_PIXEL) {
        fprintf(stderr, "framebuffer does not match required 800x600 RGB888 path\n");
        return -1;
    }
    if ((target->var.red.offset % 8u) != 0u ||
        (target->var.green.offset % 8u) != 0u ||
        (target->var.blue.offset % 8u) != 0u ||
        target->var.red.length != 8u ||
        target->var.green.length != 8u ||
        target->var.blue.length != 8u) {
        fprintf(stderr, "unsupported framebuffer channel bitfields\n");
        return -1;
    }
    target->red_byte = target->var.red.offset / 8u;
    target->green_byte = target->var.green.offset / 8u;
    target->blue_byte = target->var.blue.offset / 8u;
    if (target->red_byte > 2u || target->green_byte > 2u || target->blue_byte > 2u ||
        target->red_byte == target->green_byte ||
        target->red_byte == target->blue_byte ||
        target->green_byte == target->blue_byte) {
        fprintf(stderr, "unsupported framebuffer channel byte mapping\n");
        return -1;
    }
    printf("FB_CHANNEL_BYTES red=%u green=%u blue=%u\n",
           target->red_byte,
           target->green_byte,
           target->blue_byte);

    min_map_len = (size_t)target->fix.line_length * (size_t)target->var.yres;
    target->map_len = target->fix.smem_len;
    if (target->map_len < min_map_len) {
        target->map_len = min_map_len;
    }

    target->map = mmap(0, target->map_len, PROT_READ | PROT_WRITE, MAP_SHARED, target->fd, 0);
    if (target->map == MAP_FAILED) {
        target->map = 0;
        perror("mmap framebuffer");
        return -1;
    }

    return 0;
}

static void close_framebuffer(fb_target_t *target)
{
    if (target->map != 0) {
        (void)munmap(target->map, target->map_len);
        target->map = 0;
    }
    if (target->fd >= 0) {
        (void)close(target->fd);
        target->fd = -1;
    }
}

static int open_control_fifo(const char *path)
{
    struct stat st;
    int fd;

    if (path == 0) {
        return -1;
    }
    if (stat(path, &st) == 0) {
        if (!S_ISFIFO(st.st_mode)) {
            fprintf(stderr, "control path exists but is not a FIFO: %s\n", path);
            return -1;
        }
    } else if (errno == ENOENT) {
        if (mkfifo(path, 0600) != 0) {
            perror("mkfifo control fifo");
            return -1;
        }
    } else {
        perror("stat control fifo");
        return -1;
    }

    fd = open(path, O_RDWR | O_NONBLOCK);
    if (fd < 0) {
        perror("open control fifo");
        return -1;
    }
    printf("CONTROL_FIFO_READY path=%s\n", path);
    return fd;
}

static void log_control_action(video_control_action_t action, const video_control_state_t *control)
{
    switch (action) {
    case VIDEO_CONTROL_ACTION_PAUSE:
        printf("CONTROL_PAUSED commands=%lu\n", (unsigned long)control->commands_seen);
        break;
    case VIDEO_CONTROL_ACTION_RESUME:
        printf("CONTROL_RESUMED commands=%lu\n", (unsigned long)control->commands_seen);
        break;
    case VIDEO_CONTROL_ACTION_STATUS:
        printf("CONTROL_STATUS paused=%u quit=%u commands=%lu unknown=%lu\n",
               control->paused,
               control->quit,
               (unsigned long)control->commands_seen,
               (unsigned long)control->unknown_commands);
        break;
    case VIDEO_CONTROL_ACTION_QUIT:
        printf("CONTROL_QUIT commands=%lu\n", (unsigned long)control->commands_seen);
        break;
    case VIDEO_CONTROL_ACTION_UNKNOWN:
        printf("CONTROL_UNKNOWN commands=%lu unknown=%lu\n",
               (unsigned long)control->commands_seen,
               (unsigned long)control->unknown_commands);
        break;
    case VIDEO_CONTROL_ACTION_NONE:
    default:
        break;
    }
}

static void process_control_bytes(video_control_state_t *control, const char *bytes, ssize_t byte_count)
{
    char line[128];
    size_t line_len = 0u;
    ssize_t i;

    for (i = 0; i < byte_count; i++) {
        char ch = bytes[i];
        if (ch == '\n' || ch == '\r') {
            if (line_len > 0u) {
                video_control_action_t action;
                line[line_len] = '\0';
                action = video_control_apply_line(control, line);
                log_control_action(action, control);
                line_len = 0u;
            }
        } else if (line_len + 1u < sizeof(line)) {
            line[line_len++] = ch;
        }
    }
    if (line_len > 0u) {
        video_control_action_t action;
        line[line_len] = '\0';
        action = video_control_apply_line(control, line);
        log_control_action(action, control);
    }
}

static int write_framebuffer(fb_target_t *target, const uint8_t *frame, int framebuffer_msync)
{
    int rc;

    rc = video_fb_copy_rgb888_to_24bpp(
        target->map,
        target->map_len,
        target->fix.line_length,
        frame,
        VIDEO_UDP_DEFAULT_WIDTH,
        VIDEO_UDP_DEFAULT_HEIGHT,
        target->red_byte,
        target->green_byte,
        target->blue_byte
    );
    if (rc != 0) {
        fprintf(stderr, "framebuffer copy failed rc=%d\n", rc);
        return -1;
    }
    if (framebuffer_msync) {
        if (msync(target->map, target->map_len, MS_SYNC) != 0) {
            perror("msync framebuffer");
            return -1;
        }
    }
    return 0;
}

static const uint8_t *prepare_output_frame(
    video_effect_t effect,
    uint8_t *effect_buffer,
    const uint8_t *frame
)
{
    if (effect == VIDEO_EFFECT_NONE) {
        return frame;
    }
    if (video_effect_apply(effect, effect_buffer, VIDEO_UDP_FRAME_BYTES, frame, VIDEO_UDP_FRAME_BYTES) != 0) {
        return 0;
    }
    return effect_buffer;
}

static int open_udp_socket(uint16_t port, unsigned int timeout_seconds)
{
    int fd;
    int yes = 1;
    int rcvbuf = 32 * 1024 * 1024;
    socklen_t rcvbuf_len = sizeof(rcvbuf);
    struct timeval timeout;
    struct sockaddr_in addr;

    fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) {
        perror("socket");
        return -1;
    }

    (void)setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    (void)setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof(rcvbuf));
    if (getsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, &rcvbuf_len) == 0) {
        printf("UDP_RCVBUF bytes=%d\n", rcvbuf);
    }

    timeout.tv_sec = (time_t)timeout_seconds;
    timeout.tv_usec = 0;
    if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) != 0) {
        perror("SO_RCVTIMEO");
        (void)close(fd);
        return -1;
    }

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(port);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        perror("bind");
        (void)close(fd);
        return -1;
    }

    return fd;
}

static unsigned long long monotonic_ms(void)
{
    struct timeval tv;

    if (gettimeofday(&tv, 0) != 0) {
        return 0u;
    }
    return ((unsigned long long)tv.tv_sec * 1000ull) + ((unsigned long long)tv.tv_usec / 1000ull);
}

int main(int argc, char **argv)
{
    app_config_t config;
    fb_target_t fb;
    video_udp_receiver_t receiver;
    video_control_state_t control;
    uint8_t *buffer_a = 0;
    uint8_t *buffer_b = 0;
    uint8_t *effect_buffer = 0;
    uint8_t packet[VIDEO_UDP_HEADER_LEN + VIDEO_UDP_CHUNK_BYTES];
    unsigned int packets = 0u;
    unsigned int frames_written = 0u;
    unsigned int frames_skipped = 0u;
    unsigned long long start_ms;
    unsigned long long last_present_ms = 0u;
    int sock = -1;
    int control_fd = -1;
    int exit_code = 1;

    if (parse_args(argc, argv, &config) != 0) {
        usage(argv[0]);
        return 1;
    }

    buffer_a = (uint8_t *)malloc(VIDEO_UDP_FRAME_BYTES);
    buffer_b = (uint8_t *)malloc(VIDEO_UDP_FRAME_BYTES);
    effect_buffer = (uint8_t *)malloc(VIDEO_UDP_FRAME_BYTES);
    if (buffer_a == 0 || buffer_b == 0 || effect_buffer == 0) {
        fprintf(stderr, "failed to allocate frame buffers\n");
        goto cleanup;
    }

    if (open_framebuffer(config.fb_path, &fb) != 0) {
        goto cleanup;
    }
    sock = open_udp_socket(config.port, config.timeout_seconds);
    if (sock < 0) {
        goto cleanup;
    }
    video_control_init(&control);
    if (config.control_fifo_path != 0) {
        control_fd = open_control_fifo(config.control_fifo_path);
        if (control_fd < 0) {
            goto cleanup;
        }
    }

    video_udp_receiver_init(&receiver, buffer_a, buffer_b);
    printf("VIDEO_UDP_LINUX_RECEIVER_READY port=%u frames=%u timeout_sec=%u control=%s effect=%s sync_mode=%s present_interval_ms=%u\n",
           config.port,
           config.frames,
           config.timeout_seconds,
           config.control_fifo_path == 0 ? "none" : config.control_fifo_path,
           video_effect_name(config.effect),
           config.framebuffer_msync ? "msync" : "none",
           config.present_interval_ms);
    fflush(stdout);
    start_ms = monotonic_ms();

    while (frames_written < config.frames && !control.quit) {
        fd_set read_fds;
        struct timeval timeout;
        int max_fd = sock;
        int selected;

        if (monotonic_ms() - start_ms > (unsigned long long)config.timeout_seconds * 1000ull) {
            fprintf(stderr, "receive timeout after %u seconds\n", config.timeout_seconds);
            goto cleanup;
        }

        FD_ZERO(&read_fds);
        FD_SET(sock, &read_fds);
        if (control_fd >= 0) {
            FD_SET(control_fd, &read_fds);
            if (control_fd > max_fd) {
                max_fd = control_fd;
            }
        }

        timeout.tv_sec = 1;
        timeout.tv_usec = 0;
        selected = select(max_fd + 1, &read_fds, 0, 0, &timeout);
        if (selected < 0) {
            if (errno == EINTR) {
                continue;
            }
            perror("select");
            goto cleanup;
        }
        if (selected == 0) {
            continue;
        }

        if (control_fd >= 0 && FD_ISSET(control_fd, &read_fds)) {
            char control_buf[256];
            ssize_t got = read(control_fd, control_buf, sizeof(control_buf));
            if (got > 0) {
                process_control_bytes(&control, control_buf, got);
                fflush(stdout);
            }
        }

        if (FD_ISSET(sock, &read_fds)) {
            ssize_t got;
            int rc;
            const uint8_t *frame;

            got = recv(sock, packet, sizeof(packet), 0);
            if (got < 0) {
                if (errno == EAGAIN || errno == EWOULDBLOCK) {
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
                frame = video_udp_receiver_active_frame(&receiver);
                if (control.paused) {
                    frames_skipped++;
                    printf("VIDEO_UDP_FRAME_SKIPPED_PAUSED frame_id=%lu skipped=%u packets=%u dropped=%lu elapsed_ms=%llu\n",
                           (unsigned long)receiver.frame_id,
                           frames_skipped,
                           packets,
                           (unsigned long)receiver.dropped_packets,
                           monotonic_ms() - start_ms);
                    fflush(stdout);
                    continue;
                }
                frame = prepare_output_frame(config.effect, effect_buffer, frame);
                if (config.present_interval_ms > 0u && last_present_ms > 0u) {
                    unsigned long long now_ms = monotonic_ms();
                    unsigned long long elapsed_since_present = now_ms - last_present_ms;
                    if (elapsed_since_present < (unsigned long long)config.present_interval_ms) {
                        usleep((useconds_t)(((unsigned long long)config.present_interval_ms - elapsed_since_present) * 1000ull));
                    }
                }
                if (frame == 0 || write_framebuffer(&fb, frame, config.framebuffer_msync) != 0) {
                    goto cleanup;
                }
                last_present_ms = monotonic_ms();
                frames_written++;
                printf("VIDEO_UDP_FRAME_WRITTEN frame_id=%lu frames=%u packets=%u dropped=%lu skipped=%u effect=%s elapsed_ms=%llu\n",
                       (unsigned long)receiver.frame_id,
                       frames_written,
                       packets,
                       (unsigned long)receiver.dropped_packets,
                       frames_skipped,
                       video_effect_name(config.effect),
                       monotonic_ms() - start_ms);
                fflush(stdout);
            }
        }
    }

    printf("VIDEO_UDP_RECEIVER_DONE frames=%u skipped=%u packets=%u dropped=%lu elapsed_ms=%llu\n",
           frames_written,
           frames_skipped,
           packets,
           (unsigned long)receiver.dropped_packets,
           monotonic_ms() - start_ms);
    exit_code = 0;

cleanup:
    if (sock >= 0) {
        (void)close(sock);
    }
    if (control_fd >= 0) {
        (void)close(control_fd);
    }
    close_framebuffer(&fb);
    free(buffer_a);
    free(buffer_b);
    free(effect_buffer);
    return exit_code;
}
