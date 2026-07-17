#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define DEFAULT_PIP_BASE 0x43c00000u
#define DEFAULT_MAP_SIZE 0x10000u

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
    uint32_t base;
    uint32_t control;
    uint32_t x;
    uint32_t y;
    int status_only;
} app_config_t;

static void usage(const char *argv0)
{
    fprintf(stderr,
            "usage: %s [--base 0x43c00000] [--preset name] [--enable 0|1] [--x px] [--y px] [--scale 2|4] [--border 0|1] [--effect normal|invert|grayscale] [--status-only]\n"
            "presets: bypass, bottom-right, top-left, large, small, normal, invert, grayscale\n",
            argv0);
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

static int set_effect(app_config_t *config, const char *name)
{
    config->control &= ~(CTRL_EFFECT_INVERT | CTRL_EFFECT_GRAYSCALE);
    if (strcmp(name, "normal") == 0) {
        config->control |= CTRL_EFFECT_NORMAL;
    } else if (strcmp(name, "invert") == 0) {
        config->control |= CTRL_EFFECT_INVERT;
    } else if (strcmp(name, "grayscale") == 0 || strcmp(name, "gray") == 0) {
        config->control |= CTRL_EFFECT_GRAYSCALE;
    } else {
        return -1;
    }
    return 0;
}

static int set_scale(app_config_t *config, uint32_t scale)
{
    config->control &= ~(CTRL_SCALE_QUARTER);
    if (scale == 2u) {
        config->control |= CTRL_SCALE_HALF;
    } else if (scale == 4u) {
        config->control |= CTRL_SCALE_QUARTER;
    } else {
        return -1;
    }
    return 0;
}

static int set_preset(app_config_t *config, const char *preset)
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

static int parse_args(int argc, char **argv, app_config_t *config)
{
    int i;

    config->base = DEFAULT_PIP_BASE;
    config->control = CTRL_ENABLE | CTRL_BORDER | CTRL_SCALE_QUARTER | CTRL_EFFECT_NORMAL;
    config->x = 1088u;
    config->y = 598u;
    config->status_only = 0;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--base") == 0 && i + 1 < argc) {
            if (parse_u32(argv[++i], 0x40000000u, 0x7fffffffu, &config->base) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "--preset") == 0 && i + 1 < argc) {
            if (set_preset(config, argv[++i]) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "--enable") == 0 && i + 1 < argc) {
            uint32_t enable;
            if (parse_u32(argv[++i], 0u, 1u, &enable) != 0) {
                return -1;
            }
            if (enable) {
                config->control |= CTRL_ENABLE;
            } else {
                config->control &= ~CTRL_ENABLE;
            }
        } else if (strcmp(argv[i], "--x") == 0 && i + 1 < argc) {
            if (parse_u32(argv[++i], 0u, 1279u, &config->x) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "--y") == 0 && i + 1 < argc) {
            if (parse_u32(argv[++i], 0u, 719u, &config->y) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "--scale") == 0 && i + 1 < argc) {
            uint32_t scale;
            if (parse_u32(argv[++i], 2u, 4u, &scale) != 0 || set_scale(config, scale) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "--border") == 0 && i + 1 < argc) {
            uint32_t border;
            if (parse_u32(argv[++i], 0u, 1u, &border) != 0) {
                return -1;
            }
            if (border) {
                config->control |= CTRL_BORDER;
            } else {
                config->control &= ~CTRL_BORDER;
            }
        } else if (strcmp(argv[i], "--effect") == 0 && i + 1 < argc) {
            if (set_effect(config, argv[++i]) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "--status-only") == 0) {
            config->status_only = 1;
        } else if (strcmp(argv[i], "--help") == 0) {
            usage(argv[0]);
            exit(0);
        } else {
            return -1;
        }
    }
    return 0;
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

static void print_status(volatile uint8_t *regs, const char *tag)
{
    uint32_t control = reg_read(regs, REG_CONTROL);
    uint32_t x = reg_read(regs, REG_X);
    uint32_t y = reg_read(regs, REG_Y);
    uint32_t status = reg_read(regs, REG_STATUS);
    uint32_t active_w = status & 0xffffu;
    uint32_t active_h = (status >> 16) & 0xffffu;

    printf("PIP_EFFECT_STATUS tag=%s control=0x%08x enable=%u border=%u scale=%u effect=%u x=%u y=%u active_w=%u active_h=%u main_frames=%u pip_frames=%u overlay_pixels=%u\n",
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

int main(int argc, char **argv)
{
    app_config_t config;
    volatile uint8_t *regs = 0;

    if (parse_args(argc, argv, &config) != 0) {
        usage(argv[0]);
        return 2;
    }

    if (map_regs(config.base, &regs) != 0) {
        return 1;
    }

    if (config.status_only) {
        print_status(regs, "status-only");
        munmap((void *)regs, DEFAULT_MAP_SIZE);
        return 0;
    }

    reg_write(regs, REG_X, config.x);
    reg_write(regs, REG_Y, config.y);
    reg_write(regs, REG_CONTROL, config.control);
    printf("PIP_EFFECT_CONFIGURED base=0x%08x control=0x%08x x=%u y=%u\n",
           config.base,
           config.control,
           config.x,
           config.y);
    print_status(regs, "after-config");

    munmap((void *)regs, DEFAULT_MAP_SIZE);
    return 0;
}
