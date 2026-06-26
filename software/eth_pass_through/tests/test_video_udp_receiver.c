#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "video_udp_receiver.h"

static uint8_t buffer_a[VIDEO_UDP_FRAME_BYTES];
static uint8_t buffer_b[VIDEO_UDP_FRAME_BYTES];
static uint8_t packet[VIDEO_UDP_HEADER_LEN + VIDEO_UDP_CHUNK_BYTES];

static void write_le16(uint8_t *p, uint16_t value)
{
    p[0] = (uint8_t)(value & 0xffu);
    p[1] = (uint8_t)(value >> 8);
}

static void write_le32(uint8_t *p, uint32_t value)
{
    p[0] = (uint8_t)(value & 0xffu);
    p[1] = (uint8_t)((value >> 8) & 0xffu);
    p[2] = (uint8_t)((value >> 16) & 0xffu);
    p[3] = (uint8_t)((value >> 24) & 0xffu);
}

static size_t make_packet(uint32_t frame_id, uint32_t offset, uint16_t payload_len, uint8_t flags)
{
    uint16_t i;
    memset(packet, 0, sizeof(packet));
    packet[0] = 'Z';
    packet[1] = 'V';
    packet[2] = 'I';
    packet[3] = 'D';
    packet[4] = VIDEO_UDP_VERSION;
    packet[5] = flags;
    write_le16(packet + 6, VIDEO_UDP_HEADER_LEN);
    write_le16(packet + 8, VIDEO_UDP_DEFAULT_WIDTH);
    write_le16(packet + 10, VIDEO_UDP_DEFAULT_HEIGHT);
    write_le32(packet + 12, frame_id);
    write_le32(packet + 16, offset);
    write_le16(packet + 20, payload_len);
    for (i = 0; i < payload_len; i++) {
        packet[VIDEO_UDP_HEADER_LEN + i] = (uint8_t)((offset + i) & 0xffu);
    }
    return VIDEO_UDP_HEADER_LEN + payload_len;
}

int main(void)
{
    video_udp_receiver_t receiver;
    uint32_t offset;
    int complete = 0;
    const uint8_t *active;

    video_udp_receiver_init(&receiver, buffer_a, buffer_b);

    for (offset = 0; offset < VIDEO_UDP_FRAME_BYTES; offset += VIDEO_UDP_CHUNK_BYTES) {
        uint8_t flags = VIDEO_UDP_FLAG_KEY_FRAME;
        size_t packet_len;
        int rc;
        if (offset + VIDEO_UDP_CHUNK_BYTES >= VIDEO_UDP_FRAME_BYTES) {
            flags |= VIDEO_UDP_FLAG_END_OF_FRAME;
        }
        packet_len = make_packet(7u, offset, VIDEO_UDP_CHUNK_BYTES, flags);
        rc = video_udp_receiver_on_packet(&receiver, packet, packet_len);
        if (rc < 0) {
            printf("packet failed offset=%lu rc=%d\n", (unsigned long)offset, rc);
            return 1;
        }
        if (rc == 1) {
            complete++;
        }
    }

    active = video_udp_receiver_active_frame(&receiver);
    if (complete != 1 || receiver.complete_frames != 1u || active == 0) {
        printf("completion failed complete=%d frames=%lu active=%p\n",
               complete, (unsigned long)receiver.complete_frames, (const void *)active);
        return 1;
    }
    if (active[0] != 0u || active[1] != 1u ||
        active[VIDEO_UDP_FRAME_BYTES - 2u] != 0xfeu ||
        active[VIDEO_UDP_FRAME_BYTES - 1u] != 0xffu) {
        printf("frame data mismatch\n");
        return 1;
    }

    printf("VIDEO_UDP_RECEIVER_TEST_OK\n");
    return 0;
}

