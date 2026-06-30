#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "video_effect.h"

static int expect_int(const char *name, int actual, int expected)
{
    if (actual != expected) {
        printf("%s mismatch actual=%d expected=%d\n", name, actual, expected);
        return 1;
    }
    return 0;
}

static int expect_u8(const char *name, uint8_t actual, uint8_t expected)
{
    if (actual != expected) {
        printf("%s mismatch actual=%u expected=%u\n", name, actual, expected);
        return 1;
    }
    return 0;
}

int main(void)
{
    const uint8_t src[] = {0u, 1u, 127u, 128u, 254u, 255u};
    uint8_t dst[sizeof(src)];
    video_effect_t effect = VIDEO_EFFECT_NONE;
    int failed = 0;

    failed |= expect_int("parse invert", video_effect_parse(" invert\n", &effect), 0);
    failed |= expect_int("effect enum", effect, VIDEO_EFFECT_INVERT);
    failed |= expect_int("apply invert", video_effect_apply(effect, dst, sizeof(dst), src, sizeof(src)), 0);
    failed |= expect_u8("invert 0", dst[0], 255u);
    failed |= expect_u8("invert 1", dst[1], 254u);
    failed |= expect_u8("invert 127", dst[2], 128u);
    failed |= expect_u8("invert 128", dst[3], 127u);
    failed |= expect_u8("invert 254", dst[4], 1u);
    failed |= expect_u8("invert 255", dst[5], 0u);

    memset(dst, 0, sizeof(dst));
    failed |= expect_int("parse none", video_effect_parse("NONE", &effect), 0);
    failed |= expect_int("apply none", video_effect_apply(effect, dst, sizeof(dst), src, sizeof(src)), 0);
    failed |= expect_int("none copy", memcmp(dst, src, sizeof(src)), 0);
    failed |= expect_int("parse invalid", video_effect_parse("rotate", &effect), -2);

    if (failed) {
        return 1;
    }

    printf("VIDEO_EFFECT_TEST_OK\n");
    return 0;
}
