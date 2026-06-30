#include "video_effect.h"

#include <ctype.h>
#include <string.h>

static int text_equals(const char *a, const char *b)
{
    while (*a != '\0' && isspace((unsigned char)*a)) {
        a++;
    }
    while (*b != '\0') {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) {
            return 0;
        }
        a++;
        b++;
    }
    while (*a != '\0') {
        if (!isspace((unsigned char)*a)) {
            return 0;
        }
        a++;
    }
    return 1;
}

const char *video_effect_name(video_effect_t effect)
{
    switch (effect) {
    case VIDEO_EFFECT_INVERT:
        return "invert";
    case VIDEO_EFFECT_NONE:
    default:
        return "none";
    }
}

int video_effect_parse(const char *name, video_effect_t *out_effect)
{
    if (name == 0 || out_effect == 0) {
        return -1;
    }
    if (text_equals(name, "none")) {
        *out_effect = VIDEO_EFFECT_NONE;
        return 0;
    }
    if (text_equals(name, "invert")) {
        *out_effect = VIDEO_EFFECT_INVERT;
        return 0;
    }
    return -2;
}

int video_effect_apply(
    video_effect_t effect,
    uint8_t *dst,
    size_t dst_size,
    const uint8_t *src,
    size_t src_size
)
{
    size_t i;

    if (dst == 0 || src == 0 || dst_size < src_size) {
        return -1;
    }

    switch (effect) {
    case VIDEO_EFFECT_NONE:
        if (dst != src) {
            memcpy(dst, src, src_size);
        }
        return 0;
    case VIDEO_EFFECT_INVERT:
        for (i = 0; i < src_size; i++) {
            dst[i] = (uint8_t)(255u - src[i]);
        }
        return 0;
    default:
        return -2;
    }
}
