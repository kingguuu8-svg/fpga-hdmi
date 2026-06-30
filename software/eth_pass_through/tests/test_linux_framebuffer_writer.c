#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "video_framebuffer.h"

static int expect_eq(uint8_t actual, uint8_t expected, const char *name)
{
    if (actual != expected) {
        printf("%s mismatch actual=%u expected=%u\n", name, actual, expected);
        return 1;
    }
    return 0;
}

int main(void)
{
    uint8_t src[12];
    uint8_t dst[20];
    int rc;
    int failed = 0;
    size_t i;

    for (i = 0; i < sizeof(src); i++) {
        src[i] = (uint8_t)(i + 1u);
    }
    memset(dst, 0xa5, sizeof(dst));

    rc = video_fb_copy_rgb888_to_stride(dst, sizeof(dst), 10u, src, 2u, 2u);
    if (rc != 0) {
        printf("copy failed rc=%d\n", rc);
        return 1;
    }

    for (i = 0; i < 6u; i++) {
        failed |= expect_eq(dst[i], src[i], "row0");
    }
    for (i = 6u; i < 10u; i++) {
        failed |= expect_eq(dst[i], 0xa5u, "row0 padding");
    }
    for (i = 0; i < 6u; i++) {
        failed |= expect_eq(dst[10u + i], src[6u + i], "row1");
    }
    for (i = 16u; i < 20u; i++) {
        failed |= expect_eq(dst[i], 0xa5u, "row1 padding");
    }

    if (video_fb_copy_rgb888_to_stride(dst, 11u, 6u, src, 2u, 2u) >= 0) {
        printf("short destination was not rejected\n");
        failed = 1;
    }
    if (video_fb_copy_rgb888_to_stride(dst, sizeof(dst), 5u, src, 2u, 2u) >= 0) {
        printf("short stride was not rejected\n");
        failed = 1;
    }

    memset(dst, 0xa5, sizeof(dst));
    rc = video_fb_copy_rgb888_to_24bpp(dst, sizeof(dst), 10u, src, 2u, 2u, 2u, 1u, 0u);
    if (rc != 0) {
        printf("24bpp copy failed rc=%d\n", rc);
        return 1;
    }
    failed |= expect_eq(dst[0], src[2], "bgr pixel0 blue byte");
    failed |= expect_eq(dst[1], src[1], "bgr pixel0 green byte");
    failed |= expect_eq(dst[2], src[0], "bgr pixel0 red byte");
    failed |= expect_eq(dst[3], src[5], "bgr pixel1 blue byte");
    failed |= expect_eq(dst[4], src[4], "bgr pixel1 green byte");
    failed |= expect_eq(dst[5], src[3], "bgr pixel1 red byte");
    failed |= expect_eq(dst[6], 0xa5u, "bgr row0 padding");

    if (video_fb_copy_rgb888_to_24bpp(dst, sizeof(dst), 10u, src, 2u, 2u, 0u, 0u, 2u) >= 0) {
        printf("duplicate channel byte mapping was not rejected\n");
        failed = 1;
    }

    if (failed) {
        return 1;
    }

    printf("VIDEO_FB_COPY_TEST_OK\n");
    return 0;
}
