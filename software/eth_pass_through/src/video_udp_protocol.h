#ifndef VIDEO_UDP_PROTOCOL_H
#define VIDEO_UDP_PROTOCOL_H

#include <stdint.h>
#include <stddef.h>

#define VIDEO_UDP_MAGIC0 'Z'
#define VIDEO_UDP_MAGIC1 'V'
#define VIDEO_UDP_MAGIC2 'I'
#define VIDEO_UDP_MAGIC3 'D'
#define VIDEO_UDP_VERSION 1u
#define VIDEO_UDP_HEADER_LEN 24u
#define VIDEO_UDP_FLAG_END_OF_FRAME 0x01u
#define VIDEO_UDP_FLAG_KEY_FRAME 0x02u
#define VIDEO_UDP_DEFAULT_PORT 5005u
#define VIDEO_UDP_DEFAULT_WIDTH 800u
#define VIDEO_UDP_DEFAULT_HEIGHT 600u
#define VIDEO_UDP_BYTES_PER_PIXEL 3u
#define VIDEO_UDP_FRAME_BYTES \
    (VIDEO_UDP_DEFAULT_WIDTH * VIDEO_UDP_DEFAULT_HEIGHT * VIDEO_UDP_BYTES_PER_PIXEL)
#define VIDEO_UDP_CHUNK_BYTES 1200u
#define VIDEO_UDP_MAX_CHUNKS \
    ((VIDEO_UDP_FRAME_BYTES + VIDEO_UDP_CHUNK_BYTES - 1u) / VIDEO_UDP_CHUNK_BYTES)

typedef struct {
    uint8_t version;
    uint8_t flags;
    uint16_t width;
    uint16_t height;
    uint32_t frame_id;
    uint32_t offset;
    uint16_t payload_len;
} video_udp_header_t;

int video_udp_parse_header(
    const uint8_t *packet,
    size_t packet_len,
    video_udp_header_t *out_header
);

#endif
