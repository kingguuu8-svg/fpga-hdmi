#include "video_control.h"

#include <ctype.h>
#include <string.h>

static int command_equals(const char *line, const char *command)
{
    size_t i = 0u;

    while (line[i] != '\0' && isspace((unsigned char)line[i])) {
        i++;
    }
    while (*command != '\0') {
        if (tolower((unsigned char)line[i]) != tolower((unsigned char)*command)) {
            return 0;
        }
        i++;
        command++;
    }
    while (line[i] != '\0') {
        if (!isspace((unsigned char)line[i])) {
            return 0;
        }
        i++;
    }
    return 1;
}

void video_control_init(video_control_state_t *state)
{
    if (state == 0) {
        return;
    }
    state->paused = 0u;
    state->quit = 0u;
    state->commands_seen = 0u;
    state->unknown_commands = 0u;
}

video_control_action_t video_control_apply_line(video_control_state_t *state, const char *line)
{
    if (state == 0 || line == 0) {
        return VIDEO_CONTROL_ACTION_UNKNOWN;
    }

    if (command_equals(line, "")) {
        return VIDEO_CONTROL_ACTION_NONE;
    }

    state->commands_seen++;
    if (command_equals(line, "pause")) {
        state->paused = 1u;
        return VIDEO_CONTROL_ACTION_PAUSE;
    }
    if (command_equals(line, "resume")) {
        state->paused = 0u;
        return VIDEO_CONTROL_ACTION_RESUME;
    }
    if (command_equals(line, "status")) {
        return VIDEO_CONTROL_ACTION_STATUS;
    }
    if (command_equals(line, "quit")) {
        state->quit = 1u;
        return VIDEO_CONTROL_ACTION_QUIT;
    }

    state->unknown_commands++;
    return VIDEO_CONTROL_ACTION_UNKNOWN;
}
