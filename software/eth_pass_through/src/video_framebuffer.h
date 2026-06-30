#ifndef VIDEO_FRAMEBUFFER_H
#define VIDEO_FRAMEBUFFER_H

#include <stddef.h>
#include <stdint.h>

int video_fb_copy_rgb888_to_stride(
    uint8_t *dst,
    size_t dst_size,
    size_t dst_stride,
    const uint8_t *src,
    uint16_t width,
    uint16_t height
);

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
);

#endif
