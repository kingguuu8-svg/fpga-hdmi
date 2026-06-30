#include <stdio.h>

#include "video_control.h"

static int expect_int(const char *name, int actual, int expected)
{
    if (actual != expected) {
        printf("%s mismatch actual=%d expected=%d\n", name, actual, expected);
        return 1;
    }
    return 0;
}

int main(void)
{
    video_control_state_t state;
    int failed = 0;

    video_control_init(&state);
    failed |= expect_int("initial paused", state.paused, 0);
    failed |= expect_int("blank", video_control_apply_line(&state, "  \r\n"), VIDEO_CONTROL_ACTION_NONE);
    failed |= expect_int("pause action", video_control_apply_line(&state, " pause\n"), VIDEO_CONTROL_ACTION_PAUSE);
    failed |= expect_int("paused", state.paused, 1);
    failed |= expect_int("status action", video_control_apply_line(&state, "STATUS"), VIDEO_CONTROL_ACTION_STATUS);
    failed |= expect_int("resume action", video_control_apply_line(&state, "resume"), VIDEO_CONTROL_ACTION_RESUME);
    failed |= expect_int("paused after resume", state.paused, 0);
    failed |= expect_int("unknown action", video_control_apply_line(&state, "bogus"), VIDEO_CONTROL_ACTION_UNKNOWN);
    failed |= expect_int("unknown count", state.unknown_commands, 1);
    failed |= expect_int("quit action", video_control_apply_line(&state, "quit"), VIDEO_CONTROL_ACTION_QUIT);
    failed |= expect_int("quit flag", state.quit, 1);
    failed |= expect_int("commands seen", state.commands_seen, 5);

    if (failed) {
        return 1;
    }

    printf("VIDEO_CONTROL_TEST_OK\n");
    return 0;
}
