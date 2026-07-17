#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#define DEFAULT_PIP_BASE 0x43c00000u
#define DEFAULT_MAP_SIZE 0x10000u
#define DEFAULT_LISTEN_PORT 5012
#define LINE_MAX_BYTES 256
#define RESPONSE_MAX_BYTES 1024

#define REG_CONTROL 0x00u
#define REG_X 0x04u
#define REG_Y 0x08u
#define REG_STATUS 0x0cu
#define REG_MAIN_FRAMES 0x10u
#define REG_PIP_FRAMES 0x14u
#define REG_OVERLAY_PIXELS 0x18u

#define CTRL_ENABLE 0x00000001u
#define CTRL_BORDER 0x00000002u
#define CTRL_SCALE_HALF 0x00000000u
#define CTRL_SCALE_QUARTER 0x00000004u
#define CTRL_EFFECT_NORMAL 0x00000000u
#define CTRL_EFFECT_INVERT 0x00000010u
#define CTRL_EFFECT_GRAYSCALE 0x00000020u

typedef struct {
    uint32_t control;
    uint32_t x;
    uint32_t y;
} pip_config_t;

typedef struct {
    uint32_t base;
    uint16_t port;
} app_config_t;

static uint64_t now_us(void)
{
    struct timeval tv;
    gettimeofday(&tv, 0);
    return ((uint64_t)tv.tv_sec * 1000000ull) + (uint64_t)tv.tv_usec;
}

static uint32_t reg_read(volatile uint8_t *base, uint32_t offset)
{
    volatile uint32_t *reg = (volatile uint32_t *)(base + offset);
    return *reg;
}

static void reg_write(volatile uint8_t *base, uint32_t offset, uint32_t value)
{
    volatile uint32_t *reg = (volatile uint32_t *)(base + offset);
    *reg = value;
}

static int parse_u32(const char *text, uint32_t min, uint32_t max, uint32_t *out)
{
    char *end = 0;
    unsigned long value;

    errno = 0;
    value = strtoul(text, &end, 0);
    if (errno != 0 || end == text || *end != '\0' || value < min || value > max) {
        return -1;
    }
    *out = (uint32_t)value;
    return 0;
}

static void usage(const char *argv0)
{
    fprintf(stderr, "usage: %s [--base 0x43c00000] [--port 5012]\n", argv0);
}

static int parse_args(int argc, char **argv, app_config_t *config)
{
    int i;
    uint32_t port;

    config->base = DEFAULT_PIP_BASE;
    config->port = DEFAULT_LISTEN_PORT;
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--base") == 0 && i + 1 < argc) {
            if (parse_u32(argv[++i], 0x40000000u, 0x7fffffffu, &config->base) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) {
            if (parse_u32(argv[++i], 1u, 65535u, &port) != 0) {
                return -1;
            }
            config->port = (uint16_t)port;
        } else if (strcmp(argv[i], "--help") == 0) {
            usage(argv[0]);
            exit(0);
        } else {
            return -1;
        }
    }
    return 0;
}

static int set_preset(pip_config_t *config, const char *preset)
{
    config->control = CTRL_ENABLE | CTRL_BORDER | CTRL_SCALE_QUARTER | CTRL_EFFECT_NORMAL;
    config->x = 1088u;
    config->y = 598u;

    if (strcmp(preset, "bypass") == 0) {
        config->control &= ~CTRL_ENABLE;
    } else if (strcmp(preset, "bottom-right") == 0 || strcmp(preset, "small") == 0 || strcmp(preset, "normal") == 0) {
        /* defaults */
    } else if (strcmp(preset, "top-left") == 0) {
        config->x = 32u;
        config->y = 32u;
    } else if (strcmp(preset, "large") == 0) {
        config->x = 928u;
        config->y = 508u;
        config->control &= ~CTRL_SCALE_QUARTER;
        config->control |= CTRL_SCALE_HALF;
    } else if (strcmp(preset, "invert") == 0) {
        config->control |= CTRL_EFFECT_INVERT;
    } else if (strcmp(preset, "grayscale") == 0 || strcmp(preset, "gray") == 0) {
        config->control |= CTRL_EFFECT_GRAYSCALE;
    } else {
        return -1;
    }
    return 0;
}

static int map_regs(uint32_t base_addr, volatile uint8_t **mapped)
{
    int fd;
    void *map;

    fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("open /dev/mem");
        return -1;
    }
    map = mmap(0, DEFAULT_MAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)base_addr);
    close(fd);
    if (map == MAP_FAILED) {
        perror("mmap pip regs");
        return -1;
    }
    *mapped = (volatile uint8_t *)map;
    return 0;
}

static int append_status(char *response, size_t response_size, volatile uint8_t *regs, const char *tag)
{
    uint32_t control = reg_read(regs, REG_CONTROL);
    uint32_t x = reg_read(regs, REG_X);
    uint32_t y = reg_read(regs, REG_Y);
    uint32_t status = reg_read(regs, REG_STATUS);
    uint32_t active_w = status & 0xffffu;
    uint32_t active_h = (status >> 16) & 0xffffu;
    int used = (int)strlen(response);

    return snprintf(
        response + used,
        response_size - (size_t)used,
        "PIP_EFFECT_STATUS tag=%s control=0x%08x enable=%u border=%u scale=%u effect=%u x=%u y=%u active_w=%u active_h=%u main_frames=%u pip_frames=%u overlay_pixels=%u\n",
        tag,
        control,
        control & CTRL_ENABLE ? 1u : 0u,
        control & CTRL_BORDER ? 1u : 0u,
        (control & CTRL_SCALE_QUARTER) ? 4u : 2u,
        (control >> 4) & 0x3u,
        x,
        y,
        active_w,
        active_h,
        reg_read(regs, REG_MAIN_FRAMES),
        reg_read(regs, REG_PIP_FRAMES),
        reg_read(regs, REG_OVERLAY_PIXELS));
}

static void trim_line(char *line)
{
    size_t len = strlen(line);
    while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r' || line[len - 1] == ' ' || line[len - 1] == '\t')) {
        line[--len] = '\0';
    }
}

static int handle_command(volatile uint8_t *regs, uint32_t base_addr, const char *line, char *response, size_t response_size)
{
    char command[LINE_MAX_BYTES];
    char *verb;
    char *arg;
    uint64_t started = now_us();
    uint64_t elapsed;
    pip_config_t config;

    snprintf(command, sizeof(command), "%s", line);
    trim_line(command);
    verb = strtok(command, " \t");
    arg = strtok(0, " \t");

    response[0] = '\0';
    if (verb == 0 || strcmp(verb, "status") == 0) {
        append_status(response, response_size, regs, "tcp-status");
        elapsed = now_us() - started;
        snprintf(response + strlen(response), response_size - strlen(response), "PIP_CONTROL_OK command=status latency_us=%llu\n", (unsigned long long)elapsed);
        return 0;
    }
    if (strcmp(verb, "preset") == 0 && arg != 0) {
        if (set_preset(&config, arg) != 0) {
            snprintf(response, response_size, "PIP_CONTROL_ERROR command=preset detail=unknown_preset preset=%s\n", arg);
            return -1;
        }
        reg_write(regs, REG_X, config.x);
        reg_write(regs, REG_Y, config.y);
        reg_write(regs, REG_CONTROL, config.control);
        snprintf(response, response_size, "PIP_EFFECT_CONFIGURED base=0x%08x control=0x%08x x=%u y=%u\n", base_addr, config.control, config.x, config.y);
        append_status(response, response_size, regs, "tcp-after-config");
        elapsed = now_us() - started;
        snprintf(response + strlen(response), response_size - strlen(response), "PIP_CONTROL_OK command=preset preset=%s latency_us=%llu\n", arg, (unsigned long long)elapsed);
        return 0;
    }
    if (strcmp(verb, "ping") == 0) {
        elapsed = now_us() - started;
        snprintf(response, response_size, "PIP_CONTROL_OK command=ping latency_us=%llu\n", (unsigned long long)elapsed);
        return 0;
    }
    snprintf(response, response_size, "PIP_CONTROL_ERROR command=%s detail=expected_status_or_preset\n", verb);
    return -1;
}

static int create_server(uint16_t port)
{
    int fd;
    int yes = 1;
    struct sockaddr_in addr;

    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        perror("socket");
        return -1;
    }
    if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes)) != 0) {
        perror("setsockopt");
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
    if (listen(fd, 8) != 0) {
        perror("listen");
        close(fd);
        return -1;
    }
    return fd;
}

int main(int argc, char **argv)
{
    app_config_t config;
    volatile uint8_t *regs = 0;
    int server_fd;
    struct pollfd poll_fd;

    if (parse_args(argc, argv, &config) != 0) {
        usage(argv[0]);
        return 2;
    }
    if (map_regs(config.base, &regs) != 0) {
        return 1;
    }
    server_fd = create_server(config.port);
    if (server_fd < 0) {
        munmap((void *)regs, DEFAULT_MAP_SIZE);
        return 1;
    }

    printf("PIP_CONTROL_SERVER_READY host=0.0.0.0 port=%u base=0x%08x\n", (unsigned)config.port, config.base);
    fflush(stdout);
    poll_fd.fd = server_fd;
    poll_fd.events = POLLIN;

    for (;;) {
        int poll_result = poll(&poll_fd, 1, -1);
        int client_fd;
        char line[LINE_MAX_BYTES];
        char response[RESPONSE_MAX_BYTES];
        ssize_t got;

        if (poll_result < 0) {
            if (errno == EINTR) {
                continue;
            }
            perror("poll");
            break;
        }
        if ((poll_fd.revents & POLLIN) == 0) {
            continue;
        }
        client_fd = accept(server_fd, 0, 0);
        if (client_fd < 0) {
            perror("accept");
            continue;
        }
        got = read(client_fd, line, sizeof(line) - 1u);
        if (got > 0) {
            line[got] = '\0';
            handle_command(regs, config.base, line, response, sizeof(response));
            (void)write(client_fd, response, strlen(response));
        }
        close(client_fd);
    }

    close(server_fd);
    munmap((void *)regs, DEFAULT_MAP_SIZE);
    return 1;
}
