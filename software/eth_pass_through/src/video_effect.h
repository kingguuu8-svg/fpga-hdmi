#ifndef VIDEO_EFFECT_H
#define VIDEO_EFFECT_H

#include <stddef.h>
#include <stdint.h>

typedef enum {
    VIDEO_EFFECT_NONE = 0,
    VIDEO_EFFECT_INVERT = 1
} video_effect_t;

const char *video_effect_name(video_effect_t effect);
int video_effect_parse(const char *name, video_effect_t *out_effect);
int video_effect_apply(
    video_effect_t effect,
    uint8_t *dst,
    size_t dst_size,
    const uint8_t *src,
    size_t src_size
);

#endif
