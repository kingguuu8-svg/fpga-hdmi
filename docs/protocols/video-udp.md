# Raw Video UDP Protocol

This protocol is for the first-stage Ethernet-to-HDMI pass-through only. It is
intentionally smaller than HTTP, RTP, or a reliable transport.

## Scope

```text
PC sender -> UDP -> PS baremetal lwIP receiver -> DDR frame buffer
```

The first implementation sends raw RGB888 frames. It does not provide
compression, retransmission, ordering repair, negotiation, or streaming session
management.

## Packet Format

All multi-byte integer fields are little-endian.

```text
byte 0..3    magic       ASCII "ZVID"
byte 4       version     1
byte 5       flags       bit0=end_of_frame, bit1=key_frame
byte 6..7    header_len  24
byte 8..9    width       pixels
byte 10..11  height      pixels
byte 12..15  frame_id    monotonically increasing
byte 16..19  offset      byte offset in the RGB888 frame
byte 20..21  payload_len bytes after this header
byte 22..23  reserved    0
byte 24..N   payload     RGB888 bytes, R then G then B
```

Constants:

```text
magic = "ZVID"
version = 1
header_len = 24
pixel_format = RGB888
default port = 5005
default test size = 800x600
default max payload = 1200 bytes
```

## Receiver Rules

The PS receiver should:

```text
1. Drop packets with wrong magic, version, header length, dimensions, or payload
   length.
2. Copy payload bytes to inactive_frame_buffer + offset.
3. Track the received byte coverage for the current frame.
4. Publish the inactive buffer only when all bytes for a frame are received.
5. Keep HDMI reading the previous complete frame if a frame is incomplete.
```

For the first pass, the receiver may accept only one fixed resolution and one
fixed pixel format.

## Why UDP

UDP is used because first-stage video pass-through only needs fresh complete
frames. TCP/HTTP would add connection state, buffering, parsing, and head-of-line
blocking before the hardware path is proven.
