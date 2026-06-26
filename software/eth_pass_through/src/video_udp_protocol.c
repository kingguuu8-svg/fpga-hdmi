#include "video_udp_protocol.h"

static uint16_t read_le16(const uint8_t *p)
{
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t read_le32(const uint8_t *p)
{
    return (uint32_t)p[0]
        | ((uint32_t)p[1] << 8)
        | ((uint32_t)p[2] << 16)
        | ((uint32_t)p[3] << 24);
}

int video_udp_parse_header(
    const uint8_t *packet,
    size_t packet_len,
    video_udp_header_t *out_header
)
{
    uint16_t header_len;
    uint16_t payload_len;

    if (packet == 0 || out_header == 0) {
        return -1;
    }
    if (packet_len < VIDEO_UDP_HEADER_LEN) {
        return -2;
    }
    if (packet[0] != VIDEO_UDP_MAGIC0 || packet[1] != VIDEO_UDP_MAGIC1 ||
        packet[2] != VIDEO_UDP_MAGIC2 || packet[3] != VIDEO_UDP_MAGIC3) {
        return -3;
    }
    if (packet[4] != VIDEO_UDP_VERSION) {
        return -4;
    }

    header_len = read_le16(packet + 6);
    if (header_len != VIDEO_UDP_HEADER_LEN) {
        return -5;
    }

    payload_len = read_le16(packet + 20);
    if ((size_t)payload_len + VIDEO_UDP_HEADER_LEN != packet_len) {
        return -6;
    }

    out_header->version = packet[4];
    out_header->flags = packet[5];
    out_header->width = read_le16(packet + 8);
    out_header->height = read_le16(packet + 10);
    out_header->frame_id = read_le32(packet + 12);
    out_header->offset = read_le32(packet + 16);
    out_header->payload_len = payload_len;
    return 0;
}

