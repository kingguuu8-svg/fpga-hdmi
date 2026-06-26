#ifndef VIDEO_UDP_RECEIVER_H
#define VIDEO_UDP_RECEIVER_H

#include <stdint.h>
#include <stddef.h>

#include "video_udp_protocol.h"

typedef struct {
    uint8_t *front_buffer;
    uint8_t *back_buffer;
    uint8_t chunk_seen[VIDEO_UDP_MAX_CHUNKS];
    uint32_t frame_id;
    uint32_t bytes_received;
    uint32_t complete_frames;
    uint32_t dropped_packets;
    uint8_t end_seen;
    uint8_t has_frame;
} video_udp_receiver_t;

void video_udp_receiver_init(
    video_udp_receiver_t *receiver,
    uint8_t *buffer_a,
    uint8_t *buffer_b
);

int video_udp_receiver_on_packet(
    video_udp_receiver_t *receiver,
    const uint8_t *packet,
    size_t packet_len
);

const uint8_t *video_udp_receiver_active_frame(const video_udp_receiver_t *receiver);

#endif

