#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#define DEFAULT_FB_PATH "/dev/fb0"
#define DEFAULT_VDMA_BASE 0x43010000u
#define DEFAULT_VDMA_MAP_SIZE 0x10000u
#define DEFAULT_WIDTH 800u
#define DEFAULT_HEIGHT 600u
#define DEFAULT_BYTES_PER_PIXEL 3u
#define DEFAULT_FRAME_COUNT 3u

#define XAXIVDMA_CR_OFFSET 0x00000000u
#define XAXIVDMA_SR_OFFSET 0x00000004u
#define XAXIVDMA_PARKPTR_OFFSET 0x00000028u
#define XAXIVDMA_MM2S_ADDR_OFFSET 0x00000050u
#define XAXIVDMA_VSIZE_OFFSET 0x00000000u
#define XAXIVDMA_HSIZE_OFFSET 0x00000004u
#define XAXIVDMA_STRD_FRMDLY_OFFSET 0x00000008u
#define XAXIVDMA_START_ADDR_OFFSET 0x0000000cu
#define XAXIVDMA_START_ADDR_LEN 0x00000004u

#define XAXIVDMA_CR_RUNSTOP_MASK 0x00000001u
#define XAXIVDMA_CR_TAIL_EN_MASK 0x00000002u
#define XAXIVDMA_CR_RESET_MASK 0x00000004u

#define XAXIVDMA_SR_HALTED_MASK 0x00000001u
#define XAXIVDMA_SR_IDLE_MASK 0x00000002u
#define XAXIVDMA_SR_ERR_ALL_MASK 0x00000ff0u

typedef struct {
    const char *fb_path;
    uint32_t vdma_base;
    uint32_t width;
    uint32_t height;
    uint32_t bytes_per_pixel;
    uint32_t frame_count;
    int status_only;
} app_config_t;

static void usage(const char *argv0)
{
    fprintf(stderr,
            "usage: %s [--fb /dev/fb0] [--vdma-base 0x43010000] [--width 800] [--height 600] [--bytes-per-pixel 3] [--frame-count 3] [--status-only]\n",
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

static int parse_args(int argc, char **argv, app_config_t *config)
{
    int i;

    config->fb_path = DEFAULT_FB_PATH;
    config->vdma_base = DEFAULT_VDMA_BASE;
    config->width = DEFAULT_WIDTH;
    config->height = DEFAULT_HEIGHT;
    config->bytes_per_pixel = DEFAULT_BYTES_PER_PIXEL;
    config->frame_count = DEFAULT_FRAME_COUNT;
    config->status_only = 0;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--fb") == 0 && i + 1 < argc) {
            config->fb_path = argv[++i];
        } else if (strcmp(argv[i], "--vdma-base") == 0 && i + 1 < argc) {
            if (parse_u32(argv[++i], 0x40000000u, 0x7fffffffu, &config->vdma_base) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "--width") == 0 && i + 1 < argc) {
            if (parse_u32(argv[++i], 1u, 8192u, &config->width) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "--height") == 0 && i + 1 < argc) {
            if (parse_u32(argv[++i], 1u, 8192u, &config->height) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "--bytes-per-pixel") == 0 && i + 1 < argc) {
            if (parse_u32(argv[++i], 1u, 8u, &config->bytes_per_pixel) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "--frame-count") == 0 && i + 1 < argc) {
            if (parse_u32(argv[++i], 1u, 16u, &config->frame_count) != 0) {
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

static int open_framebuffer_info(const app_config_t *config, uint32_t *frame_addr, uint32_t *stride, uint32_t *hsize)
{
    int fd;
    struct fb_fix_screeninfo fix;
    struct fb_var_screeninfo var;
    unsigned long min_frame_bytes;

    fd = open(config->fb_path, O_RDONLY);
    if (fd < 0) {
        perror("open framebuffer");
        return -1;
    }
    if (ioctl(fd, FBIOGET_FSCREENINFO, &fix) != 0) {
        perror("FBIOGET_FSCREENINFO");
        close(fd);
        return -1;
    }
    if (ioctl(fd, FBIOGET_VSCREENINFO, &var) != 0) {
        perror("FBIOGET_VSCREENINFO");
        close(fd);
        return -1;
    }
    close(fd);

    *hsize = config->width * config->bytes_per_pixel;
    *stride = fix.line_length;
    min_frame_bytes = (unsigned long)(*stride) * (unsigned long)config->height;

    printf("FB_INFO path=%s xres=%u yres=%u bpp=%u line_length=%u smem_start=0x%08lx smem_len=%u hsize=%u vsize=%u\n",
           config->fb_path,
           var.xres,
           var.yres,
           var.bits_per_pixel,
           fix.line_length,
           fix.smem_start,
           fix.smem_len,
           *hsize,
           config->height);

    if (var.xres < config->width || var.yres < config->height) {
        fprintf(stderr, "framebuffer resolution is smaller than requested VDMA frame\n");
        return -1;
    }
    if (var.bits_per_pixel != config->bytes_per_pixel * 8u) {
        fprintf(stderr, "framebuffer bpp does not match requested bytes-per-pixel\n");
        return -1;
    }
    if (fix.line_length < *hsize || fix.smem_len < min_frame_bytes) {
        fprintf(stderr, "framebuffer storage is smaller than requested VDMA frame\n");
        return -1;
    }
    if (fix.smem_start == 0ul || fix.smem_start > 0xfffffffful) {
        fprintf(stderr, "framebuffer physical address is invalid for 32-bit AXI VDMA\n");
        return -1;
    }
    if ((fix.smem_start & 0x3ul) != 0ul) {
        fprintf(stderr, "framebuffer physical address is not word-aligned\n");
        return -1;
    }

    *frame_addr = (uint32_t)fix.smem_start;
    return 0;
}

static int map_vdma(uint32_t vdma_base, volatile uint8_t **mapped)
{
    int fd;
    void *map;

    fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("open /dev/mem");
        return -1;
    }

    map = mmap(0, DEFAULT_VDMA_MAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)vdma_base);
    close(fd);
    if (map == MAP_FAILED) {
        perror("mmap vdma");
        return -1;
    }

    *mapped = (volatile uint8_t *)map;
    return 0;
}

static int wait_reset_done(volatile uint8_t *vdma)
{
    int i;

    for (i = 0; i < 1000; i++) {
        if ((reg_read(vdma, XAXIVDMA_CR_OFFSET) & XAXIVDMA_CR_RESET_MASK) == 0u) {
            return 0;
        }
        usleep(1000);
    }
    fprintf(stderr, "VDMA reset did not complete\n");
    return -1;
}

static int report_status(volatile uint8_t *vdma, const char *tag)
{
    uint32_t cr = reg_read(vdma, XAXIVDMA_CR_OFFSET);
    uint32_t sr = reg_read(vdma, XAXIVDMA_SR_OFFSET);

    printf("VDMA_MM2S_STATUS tag=%s cr=0x%08x sr=0x%08x halted=%u idle=%u errors=0x%03x\n",
           tag,
           cr,
           sr,
           (sr & XAXIVDMA_SR_HALTED_MASK) ? 1u : 0u,
           (sr & XAXIVDMA_SR_IDLE_MASK) ? 1u : 0u,
           (sr & XAXIVDMA_SR_ERR_ALL_MASK) >> 4);

    return (sr & XAXIVDMA_SR_ERR_ALL_MASK) == 0u ? 0 : -1;
}

static int configure_mm2s(const app_config_t *config, volatile uint8_t *vdma, uint32_t frame_addr, uint32_t stride, uint32_t hsize)
{
    uint32_t i;

    reg_write(vdma, XAXIVDMA_CR_OFFSET, XAXIVDMA_CR_RESET_MASK);
    if (wait_reset_done(vdma) != 0) {
        return -1;
    }

    reg_write(vdma, XAXIVDMA_CR_OFFSET, XAXIVDMA_CR_TAIL_EN_MASK);
    reg_write(vdma, XAXIVDMA_PARKPTR_OFFSET, 0u);
    reg_write(vdma, XAXIVDMA_MM2S_ADDR_OFFSET + XAXIVDMA_HSIZE_OFFSET, hsize);
    reg_write(vdma, XAXIVDMA_MM2S_ADDR_OFFSET + XAXIVDMA_STRD_FRMDLY_OFFSET, stride);
    for (i = 0; i < config->frame_count; i++) {
        reg_write(
            vdma,
            XAXIVDMA_MM2S_ADDR_OFFSET + XAXIVDMA_START_ADDR_OFFSET + (i * XAXIVDMA_START_ADDR_LEN),
            frame_addr
        );
    }

    reg_write(vdma, XAXIVDMA_CR_OFFSET, XAXIVDMA_CR_TAIL_EN_MASK | XAXIVDMA_CR_RUNSTOP_MASK);
    reg_write(vdma, XAXIVDMA_MM2S_ADDR_OFFSET + XAXIVDMA_VSIZE_OFFSET, config->height);
    usleep(10000);

    printf("VDMA_MM2S_CONFIGURED base=0x%08x frame_addr=0x%08x hsize=%u stride=%u vsize=%u frame_count=%u\n",
           config->vdma_base,
           frame_addr,
           hsize,
           stride,
           config->height,
           config->frame_count);

    return report_status(vdma, "after-config");
}

int main(int argc, char **argv)
{
    app_config_t config;
    volatile uint8_t *vdma = 0;
    uint32_t frame_addr = 0u;
    uint32_t stride = 0u;
    uint32_t hsize = 0u;
    int rc = 1;

    if (parse_args(argc, argv, &config) != 0) {
        usage(argv[0]);
        return 1;
    }

    if (!config.status_only &&
        open_framebuffer_info(&config, &frame_addr, &stride, &hsize) != 0) {
        return 1;
    }
    if (map_vdma(config.vdma_base, &vdma) != 0) {
        return 1;
    }

    if (config.status_only) {
        rc = report_status(vdma, "status-only");
    } else {
        rc = configure_mm2s(&config, vdma, frame_addr, stride, hsize);
    }

    (void)munmap((void *)vdma, DEFAULT_VDMA_MAP_SIZE);
    return rc == 0 ? 0 : 1;
}
