#!/usr/bin/env python3
"""Send baseline 4:2:0 JPEG files as paced RFC 2435 RTP/JPEG frames."""

from __future__ import annotations

import argparse
import json
import socket
import struct
import time
from pathlib import Path


SOF_MARKERS = {0xC0, 0xC1, 0xC2}


def _segment_end(data: bytes, position: int) -> tuple[int, int]:
    if position + 2 > len(data):
        raise ValueError("truncated JPEG segment length")
    length = int.from_bytes(data[position : position + 2], "big")
    if length < 2 or position + length > len(data):
        raise ValueError("invalid JPEG segment length")
    return position + 2, position + length


def parse_jpeg(data: bytes) -> tuple[int, int, int, bytes, bytes]:
    if not data.startswith(b"\xff\xd8"):
        raise ValueError("JPEG SOI missing")
    width = height = 0
    jpeg_type = -1
    quant_tables: dict[int, bytes] = {}
    scan_start = None
    position = 2
    while position < len(data):
        if data[position] != 0xFF:
            position += 1
            continue
        while position < len(data) and data[position] == 0xFF:
            position += 1
        if position >= len(data):
            break
        marker = data[position]
        position += 1
        if marker == 0xDA:
            segment_start, segment_end = _segment_end(data, position)
            scan_start = segment_end
            break
        if marker in {0xD8, 0xD9} or 0xD0 <= marker <= 0xD7:
            continue
        segment_start, segment_end = _segment_end(data, position)
        payload = data[segment_start:segment_end]
        if marker == 0xDB:
            table_position = 0
            while table_position < len(payload):
                precision_and_id = payload[table_position]
                table_position += 1
                precision = precision_and_id >> 4
                table_id = precision_and_id & 0x0F
                table_bytes = 64 * (2 if precision == 1 else 1)
                if precision not in {0, 1} or table_position + table_bytes > len(payload):
                    raise ValueError("unsupported JPEG quantization table")
                if precision == 0:
                    quant_tables[table_id] = payload[table_position : table_position + table_bytes]
                table_position += table_bytes
        elif marker in SOF_MARKERS:
            if len(payload) < 6:
                raise ValueError("truncated JPEG frame header")
            height = int.from_bytes(payload[1:3], "big")
            width = int.from_bytes(payload[3:5], "big")
            components = payload[5]
            if components != 3 or len(payload) < 6 + components * 3:
                raise ValueError("JPEG is not three-component baseline 4:2:0")
            sampling = [payload[7 + component * 3] for component in range(components)]
            if sampling != [0x22, 0x11, 0x11]:
                raise ValueError(f"unsupported JPEG sampling factors: {sampling!r}")
            jpeg_type = 1
        position = segment_end

    if scan_start is None or width <= 0 or height <= 0 or jpeg_type != 1:
        raise ValueError("incomplete baseline 4:2:0 JPEG")
    scan_end = data.rfind(b"\xff\xd9")
    if scan_end < scan_start:
        raise ValueError("JPEG EOI missing")
    if 0 not in quant_tables or 1 not in quant_tables:
        raise ValueError("JPEG luminance/chrominance quantization tables missing")
    quantization = quant_tables[0] + quant_tables[1]
    return width, height, jpeg_type, quantization, data[scan_start:scan_end]


def wait_until(target: float) -> None:
    while True:
        remaining = target - time.perf_counter()
        if remaining <= 0:
            return
        time.sleep(min(remaining / 2.0, 0.002))


def rtp_header(sequence: int, timestamp: int, marker: bool, payload_type: int, ssrc: int) -> bytes:
    second = payload_type | (0x80 if marker else 0)
    return struct.pack(">BBHII", 0x80, second, sequence & 0xFFFF, timestamp & 0xFFFFFFFF, ssrc)


def send_frame(
    sock: socket.socket,
    target: tuple[str, int],
    jpeg: bytes,
    sequence: int,
    timestamp: int,
    payload_type: int,
    ssrc: int,
    mtu: int,
) -> tuple[int, int, int, int]:
    width, height, jpeg_type, quantization, scan = parse_jpeg(jpeg)
    if width % 8 or height % 8 or width // 8 > 255 or height // 8 > 255:
        raise ValueError(f"RTP/JPEG dimensions are not representable: {width}x{height}")
    base_header_size = 12 + 8
    quant_header = b"\x00\x00" + struct.pack(">H", len(quantization)) + quantization
    offset = 0
    packets = 0
    while offset < len(scan):
        extra = len(quant_header) if offset == 0 else 0
        chunk_size = mtu - base_header_size - extra
        if chunk_size <= 0:
            raise ValueError("MTU is too small for RFC 2435 quantization tables")
        chunk = scan[offset : offset + chunk_size]
        last = offset + len(chunk) >= len(scan)
        jpeg_header = bytes(
            [
                0,
                (offset >> 16) & 0xFF,
                (offset >> 8) & 0xFF,
                offset & 0xFF,
                jpeg_type,
                255,
                width // 8,
                height // 8,
            ]
        )
        packet = rtp_header(sequence, timestamp, last, payload_type, ssrc) + jpeg_header
        if offset == 0:
            packet += quant_header
        sock.sendto(packet + chunk, target)
        sequence = (sequence + 1) & 0xFFFF
        packets += 1
        offset += len(chunk)
    return sequence, packets, width, height


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host")
    parser.add_argument("--port", type=int, default=5011)
    parser.add_argument("--sequence-dir", default="build/rtp-jpeg-tearing-sequence")
    parser.add_argument("--frames", type=int, default=180)
    parser.add_argument("--fps", type=float, default=30.0)
    parser.add_argument("--payload-mtu", type=int, default=1200)
    parser.add_argument("--payload-type", type=int, default=26)
    parser.add_argument("--ssrc", type=lambda value: int(value, 0), default=0x46504741)
    parser.add_argument("--out-dir", default="build/rtp-jpeg-tearing-sequence")
    args = parser.parse_args()
    if args.frames <= 0 or args.fps <= 0:
        raise SystemExit("frames and fps must be positive")

    sequence_dir = Path(args.sequence_dir)
    files = sorted(sequence_dir.glob("frame-*.jpg"))[: args.frames]
    if len(files) < args.frames:
        raise SystemExit(f"expected {args.frames} JPEG frames, found {len(files)}")
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    target = (args.host, args.port)
    trace = []
    sequence = 0
    started = time.perf_counter()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        for index, path in enumerate(files):
            wait_until(started + index / args.fps)
            sequence, packets, width, height = send_frame(
                sock,
                target,
                path.read_bytes(),
                sequence,
                int(index * 90000 / args.fps),
                args.payload_type,
                args.ssrc,
                args.payload_mtu,
            )
            trace.append({
                "index": index,
                "file": path.name,
                "packets": packets,
                "width": width,
                "height": height,
                "rtp_timestamp": int(index * 90000 / args.fps),
            })

    report = {
        "schema": "rfc2435-rtp-jpeg-sequence-send-v1",
        "host": args.host,
        "port": args.port,
        "fps": args.fps,
        "frames": len(trace),
        "payload_mtu": args.payload_mtu,
        "trace": trace,
    }
    report_path = out_dir / "rtp-send-trace.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(
        "RTP_JPEG_SEQUENCE_SEND_OK "
        f"frames={len(trace)} packets={sum(item['packets'] for item in trace)} "
        f"size={trace[0]['width']}x{trace[0]['height']} target={args.host}:{args.port} "
        f"report={report_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
