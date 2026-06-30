#include "video_framebuffer.h"

#include <string.h>

int video_fb_copy_rgb888_to_stride(
    uint8_t *dst,
    size_t dst_size,
    size_t dst_stride,
    const uint8_t *src,
    uint16_t width,
    uint16_t height
)
{
    size_t row_bytes;
    size_t y;

    if (dst == 0 || src == 0 || width == 0u || height == 0u) {
        return -1;
    }

    row_bytes = (size_t)width * 3u;
    if (dst_stride < row_bytes) {
        return -2;
    }
    if (dst_size < dst_stride * (size_t)height) {
        return -3;
    }

    for (y = 0; y < (size_t)height; y++) {
        memcpy(dst + y * dst_stride, src + y * row_bytes, row_bytes);
    }

    return 0;
}

int video_fb_copy_rgb888_to_24bpp(
    uint8_t *dst,
    size_t dst_size,
    size_t dst_stride,
    const uint8_t *src,
    uint16_t width,
    uint16_t height,
    unsigned int red_byte,
    unsigned int green_byte,
    unsigned int blue_byte
)
{
    size_t row_bytes;
    size_t y;

    if (dst == 0 || src == 0 || width == 0u || height == 0u) {
        return -1;
    }
    if (red_byte > 2u || green_byte > 2u || blue_byte > 2u ||
        red_byte == green_byte || red_byte == blue_byte || green_byte == blue_byte) {
        return -2;
    }

    row_bytes = (size_t)width * 3u;
    if (dst_stride < row_bytes) {
        return -3;
    }
    if (dst_size < dst_stride * (size_t)height) {
        return -4;
    }

    for (y = 0; y < (size_t)height; y++) {
        size_t x;
        uint8_t *dst_row = dst + y * dst_stride;
        const uint8_t *src_row = src + y * row_bytes;
        for (x = 0; x < (size_t)width; x++) {
            const uint8_t *src_pixel = src_row + x * 3u;
            uint8_t *dst_pixel = dst_row + x * 3u;
            dst_pixel[red_byte] = src_pixel[0];
            dst_pixel[green_byte] = src_pixel[1];
            dst_pixel[blue_byte] = src_pixel[2];
        }
    }

    return 0;
}
