#ifndef VIDEO_CONTROL_H
#define VIDEO_CONTROL_H

#include <stdint.h>

typedef enum {
    VIDEO_CONTROL_ACTION_NONE = 0,
    VIDEO_CONTROL_ACTION_PAUSE = 1,
    VIDEO_CONTROL_ACTION_RESUME = 2,
    VIDEO_CONTROL_ACTION_STATUS = 3,
    VIDEO_CONTROL_ACTION_QUIT = 4,
    VIDEO_CONTROL_ACTION_UNKNOWN = -1
} video_control_action_t;

typedef struct {
    uint8_t paused;
    uint8_t quit;
    uint32_t commands_seen;
    uint32_t unknown_commands;
} video_control_state_t;

void video_control_init(video_control_state_t *state);
video_control_action_t video_control_apply_line(video_control_state_t *state, const char *line);

#endif
