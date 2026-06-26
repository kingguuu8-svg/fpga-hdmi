#include "video_udp_receiver.h"

static void clear_chunks(video_udp_receiver_t *receiver)
{
    unsigned int i;
    for (i = 0; i < VIDEO_UDP_MAX_CHUNKS; i++) {
        receiver->chunk_seen[i] = 0u;
    }
    receiver->bytes_received = 0u;
    receiver->end_seen = 0u;
}

static void start_frame(video_udp_receiver_t *receiver, uint32_t frame_id)
{
    receiver->frame_id = frame_id;
    clear_chunks(receiver);
}

static void publish_frame(video_udp_receiver_t *receiver)
{
    uint8_t *old_front = receiver->front_buffer;
    receiver->front_buffer = receiver->back_buffer;
    receiver->back_buffer = old_front;
    receiver->complete_frames++;
    receiver->has_frame = 1u;
    clear_chunks(receiver);
}

void video_udp_receiver_init(
    video_udp_receiver_t *receiver,
    uint8_t *buffer_a,
    uint8_t *buffer_b
)
{
    receiver->front_buffer = buffer_a;
    receiver->back_buffer = buffer_b;
    receiver->frame_id = 0xffffffffu;
    receiver->complete_frames = 0u;
    receiver->dropped_packets = 0u;
    receiver->has_frame = 0u;
    clear_chunks(receiver);
}

int video_udp_receiver_on_packet(
    video_udp_receiver_t *receiver,
    const uint8_t *packet,
    size_t packet_len
)
{
    video_udp_header_t header;
    const uint8_t *payload;
    uint32_t chunk_index;
    uint32_t frame_end;
    int parsed;

    if (receiver == 0 || receiver->front_buffer == 0 || receiver->back_buffer == 0) {
        return -1;
    }

    parsed = video_udp_parse_header(packet, packet_len, &header);
    if (parsed != 0) {
        receiver->dropped_packets++;
        return parsed;
    }
    if (header.width != VIDEO_UDP_DEFAULT_WIDTH ||
        header.height != VIDEO_UDP_DEFAULT_HEIGHT) {
        receiver->dropped_packets++;
        return -10;
    }
    if (header.payload_len > VIDEO_UDP_CHUNK_BYTES) {
        receiver->dropped_packets++;
        return -11;
    }
    frame_end = header.offset + header.payload_len;
    if (frame_end > VIDEO_UDP_FRAME_BYTES || frame_end < header.offset) {
        receiver->dropped_packets++;
        return -12;
    }
    if ((header.offset % VIDEO_UDP_CHUNK_BYTES) != 0u) {
        receiver->dropped_packets++;
        return -13;
    }

    if (header.frame_id != receiver->frame_id) {
        start_frame(receiver, header.frame_id);
    }

    payload = packet + VIDEO_UDP_HEADER_LEN;
    chunk_index = header.offset / VIDEO_UDP_CHUNK_BYTES;
    if (chunk_index >= VIDEO_UDP_MAX_CHUNKS) {
        receiver->dropped_packets++;
        return -14;
    }

    if (!receiver->chunk_seen[chunk_index]) {
        uint32_t i;
        for (i = 0; i < header.payload_len; i++) {
            receiver->back_buffer[header.offset + i] = payload[i];
        }
        receiver->chunk_seen[chunk_index] = 1u;
        receiver->bytes_received += header.payload_len;
    }

    if ((header.flags & VIDEO_UDP_FLAG_END_OF_FRAME) != 0u) {
        receiver->end_seen = 1u;
    }
    if (receiver->end_seen && receiver->bytes_received == VIDEO_UDP_FRAME_BYTES) {
        publish_frame(receiver);
        return 1;
    }

    return 0;
}

const uint8_t *video_udp_receiver_active_frame(const video_udp_receiver_t *receiver)
{
    if (receiver == 0 || !receiver->has_frame) {
        return 0;
    }
    return receiver->front_buffer;
}

