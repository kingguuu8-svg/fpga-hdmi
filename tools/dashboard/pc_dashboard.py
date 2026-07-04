#!/usr/bin/env python3
"""Minimal PC-side control dashboard for the Zynq video pipeline.

The MVP dashboard deliberately avoids camera/webcam input and custom input
files. Input preview frames are generated deterministically on the PC.
"""

from __future__ import annotations

import argparse
import html
import json
import mimetypes
import queue
import socket
import struct
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

TOOLS_DIR = Path(__file__).resolve().parents[1]
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from send_unified_test_video_udp import (  # noqa: E402
    color_for_frame,
    decode_marker_from_frame,
    frame_sha256,
    make_color_frame,
)


DEFAULT_WIDTH = 800
DEFAULT_HEIGHT = 600
DEFAULT_BOARD_HOST = "192.168.1.10"
DEFAULT_UDP_PORT = 5005
DEFAULT_SENDER_FRAMES = 0
DEFAULT_SENDER_FPS = 10.0
DEFAULT_SENDER_START_FRAME_ID = 100
DEFAULT_CONTENT_HOLD_FRAMES = 50
DEFAULT_SENDER_PAYLOAD = 1200
DEFAULT_SENDER_INTER_PACKET_US = 0.0
DEFAULT_UART_PORT = "COM16"
DEFAULT_UART_BAUD = 115200
DEFAULT_CONTROL_FIFO = "/tmp/video_ctl"
DEFAULT_CAPTURE_DEVICE = "1"
DEFAULT_CAPTURE_BACKEND = "dshow"
DEFAULT_CAPTURE_WIDTH = 800
DEFAULT_CAPTURE_HEIGHT = 600
DEFAULT_CAPTURE_FRAMES = 8
DEFAULT_CAPTURE_PROFILE = "none"
DEFAULT_CAPTURE_SAVE_SAMPLES = 0
DEFAULT_STREAM_FPS = 10.0
NO_CAMERA_POLICY = "仅使用 PC 生成输入。MVP 阶段禁用摄像头/网络摄像头和自定义文件输入。"
DEFAULT_PIPELINE = "gstreamer"
DEFAULT_GST_CONDA_ENV = "build/conda-gstreamer-pc"
DEFAULT_GST_PORT = 5011
DEFAULT_GST_INPUT_WIDTH = 320
DEFAULT_GST_INPUT_HEIGHT = 240
DEFAULT_GST_OUTPUT_WIDTH = 800
DEFAULT_GST_OUTPUT_HEIGHT = 600
DEFAULT_GST_FPS = 5
DEFAULT_GST_NUM_BUFFERS = -1
DEFAULT_GST_PAYLOAD_TYPE = 26
DEFAULT_GST_MTU = 1200
DEFAULT_GST_BOARD_LOG = "/tmp/gst_dashboard_receiver.log"
DEFAULT_GST_BOARD_PID = "/tmp/gst_dashboard_receiver.pid"
DEFAULT_PIP_CONTROL_PORT = 5012
DEFAULT_PIP_CONTROL_TIMEOUT_S = 1.5


ACTION_DEFINITIONS = [
    {
        "id": "start-stream",
        "label": "启动视频流",
        "kind": "sender-process",
        "semantics": "启动板端 GStreamer receiver 和 PC 端 GStreamer RTP/JPEG sender；右侧面板读取 HDMI 回传 MJPEG",
    },
    {
        "id": "stop-stream",
        "label": "停止视频流",
        "kind": "sender-process",
        "semantics": "停止 PC 端 GStreamer sender，并尝试停止板端 GStreamer receiver",
    },
    {
        "id": "capture-output",
        "label": "捕获输出",
        "kind": "hdmi-capture",
        "semantics": "手动捕获 FPGA HDMI 输出的静态图，作为回退验证",
    },
    {
        "id": "pause-receiver",
        "label": "暂停接收端",
        "kind": "uart-fifo-control",
        "semantics": "旧 UDP receiver 的 FIFO 暂停命令；GStreamer 模式暂未实现",
    },
    {
        "id": "resume-receiver",
        "label": "恢复接收端",
        "kind": "uart-fifo-control",
        "semantics": "旧 UDP receiver 的 FIFO 恢复命令；GStreamer 模式暂未实现",
    },
    {
        "id": "receiver-status",
        "label": "接收端状态",
        "kind": "uart-fifo-control",
        "semantics": "GStreamer 模式读取板端 gst receiver 日志；旧 UDP 模式读取 FIFO receiver 日志",
    },
    {
        "id": "effect-none",
        "label": "关闭特效",
        "kind": "receiver-effect",
        "semantics": "旧 UDP receiver 的 effect 参数；GStreamer 模式暂未实现",
    },
    {
        "id": "effect-invert",
        "label": "反色特效",
        "kind": "receiver-effect",
        "semantics": "旧 UDP receiver 的 effect 参数；GStreamer 模式暂未实现",
    },
    {
        "id": "pip-top-left",
        "label": "PIP 左上",
        "kind": "pl-effect-preset",
        "semantics": "通过板端 /tmp/pip_effect_ctl 将 PL PIP 小窗移动到左上",
    },
    {
        "id": "pip-bottom-right",
        "label": "PIP 右下",
        "kind": "pl-effect-preset",
        "semantics": "通过板端 /tmp/pip_effect_ctl 将 PL PIP 小窗移动到右下",
    },
    {
        "id": "pip-large",
        "label": "PIP 放大",
        "kind": "pl-effect-preset",
        "semantics": "通过板端 /tmp/pip_effect_ctl 切换 PL PIP 到 1/2 尺寸",
    },
    {
        "id": "pip-small",
        "label": "PIP 缩小",
        "kind": "pl-effect-preset",
        "semantics": "通过板端 /tmp/pip_effect_ctl 切换 PL PIP 到 1/4 尺寸",
    },
    {
        "id": "pip-invert",
        "label": "PIP 反色",
        "kind": "pl-effect-preset",
        "semantics": "通过板端 /tmp/pip_effect_ctl 将小窗切换为反色",
    },
    {
        "id": "pip-grayscale",
        "label": "PIP 灰度",
        "kind": "pl-effect-preset",
        "semantics": "通过板端 /tmp/pip_effect_ctl 将小窗切换为灰度",
    },
    {
        "id": "pip-bypass",
        "label": "PIP 旁路",
        "kind": "pl-effect-preset",
        "semantics": "通过板端 /tmp/pip_effect_ctl 关闭 PL PIP 叠加",
    },
]

PIP_PRESET_ACTIONS = {
    "pip-top-left": "top-left",
    "pip-bottom-right": "bottom-right",
    "pip-large": "large",
    "pip-small": "small",
    "pip-invert": "invert",
    "pip-grayscale": "grayscale",
    "pip-bypass": "bypass",
}


def parse_key_value_marker(text: str, marker: str) -> dict[str, Any] | None:
    for line in reversed(text.splitlines()):
        stripped = line.strip()
        if not stripped.startswith(marker):
            continue
        parsed: dict[str, Any] = {"raw": stripped}
        for part in stripped.split()[1:]:
            if "=" not in part:
                continue
            key, value = part.split("=", 1)
            if value.startswith("0x"):
                parsed[key] = value
                continue
            try:
                parsed[key] = int(value)
            except ValueError:
                parsed[key] = value
        return parsed
    return None


def rgb888_to_bmp(frame: bytes, width: int, height: int) -> bytes:
    """Encode RGB888 frame bytes as a browser-readable 24-bit BMP."""
    expected = width * height * 3
    if len(frame) != expected:
        raise ValueError(f"RGB888 frame has {len(frame)} bytes, expected {expected}")

    try:
        from PIL import Image

        image = Image.frombytes("RGB", (width, height), frame)
        packed = image.transpose(Image.Transpose.FLIP_TOP_BOTTOM).tobytes("raw", "BGR")
        row_bytes = width * 3
        row_size = ((row_bytes + 3) // 4) * 4
        if row_size == row_bytes:
            pixel_bytes = packed
        else:
            padding = b"\x00" * (row_size - row_bytes)
            pixel_bytes = b"".join(
                packed[offset : offset + row_bytes] + padding
                for offset in range(0, len(packed), row_bytes)
            )
        file_size = 14 + 40 + len(pixel_bytes)
        return (
            b"BM"
            + struct.pack("<IHHI", file_size, 0, 0, 54)
            + struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0, len(pixel_bytes), 2835, 2835, 0, 0)
            + pixel_bytes
        )
    except ImportError:
        pass

    try:
        import numpy as np

        rgb = np.frombuffer(frame, dtype=np.uint8).reshape((height, width, 3))
        row_size = ((width * 3 + 3) // 4) * 4
        bgr_bottom_up = rgb[::-1, :, ::-1]
        if row_size == width * 3:
            pixel_bytes = bgr_bottom_up.tobytes()
        else:
            padded = np.zeros((height, row_size), dtype=np.uint8)
            padded[:, : width * 3] = bgr_bottom_up.reshape((height, width * 3))
            pixel_bytes = padded.tobytes()
        file_size = 14 + 40 + len(pixel_bytes)
        return (
            b"BM"
            + struct.pack("<IHHI", file_size, 0, 0, 54)
            + struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0, len(pixel_bytes), 2835, 2835, 0, 0)
            + pixel_bytes
        )
    except ImportError:
        pass

    row_size = ((width * 3 + 3) // 4) * 4
    pixel_bytes = bytearray(row_size * height)
    for out_y in range(height):
        src_y = height - 1 - out_y
        for x in range(width):
            src = (src_y * width + x) * 3
            dst = out_y * row_size + x * 3
            r, g, b = frame[src], frame[src + 1], frame[src + 2]
            pixel_bytes[dst : dst + 3] = bytes((b, g, r))

    file_size = 14 + 40 + len(pixel_bytes)
    return (
        b"BM"
        + struct.pack("<IHHI", file_size, 0, 0, 54)
        + struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0, len(pixel_bytes), 2835, 2835, 0, 0)
        + bytes(pixel_bytes)
    )


def make_input_bmp(
    frame_id: int,
    width: int = DEFAULT_WIDTH,
    height: int = DEFAULT_HEIGHT,
    content_hold_frames: int = DEFAULT_CONTENT_HOLD_FRAMES,
    content_start_frame_id: int = DEFAULT_SENDER_START_FRAME_ID,
) -> tuple[bytes, str]:
    """Rebuild an actually sent unified frame from its committed frame ID."""
    _, color = color_for_frame(frame_id, content_hold_frames, content_start_frame_id)
    rgb = make_color_frame(width, height, color, frame_id)
    return rgb888_to_bmp(rgb, width, height), frame_sha256(rgb)


def make_gstreamer_source_rgb(frame_index: int, width: int = DEFAULT_GST_INPUT_WIDTH, height: int = DEFAULT_GST_INPUT_HEIGHT) -> tuple[bytes, str]:
    """Render a fallback RGB preview while the real GStreamer source frame is unavailable."""
    frame = bytearray(width * height * 3)
    ball_radius = max(10, min(width, height) // 12)
    span_x = max(1, width - ball_radius * 2 - 1)
    span_y = max(1, height - ball_radius * 2 - 1)
    phase = frame_index % 120
    sweep = phase if phase < 60 else 119 - phase
    cx = ball_radius + int(span_x * sweep / 59)
    cy = ball_radius + int(span_y * ((phase * 2) % 60) / 59)

    for y in range(height):
        for x in range(width):
            offset = (y * width + x) * 3
            frame[offset : offset + 3] = b"\x14\x35\x4a"
            dx = x - cx
            dy = y - cy
            if dx * dx + dy * dy <= ball_radius * ball_radius:
                frame[offset : offset + 3] = b"\xff\xff\xff"

    data = bytes(frame)
    return data, frame_sha256(data)


def make_gstreamer_source_bmp(frame_index: int, width: int = DEFAULT_GST_INPUT_WIDTH, height: int = DEFAULT_GST_INPUT_HEIGHT) -> tuple[bytes, str]:
    """Render a fallback BMP preview while the real GStreamer source frame is unavailable."""
    data, sha = make_gstreamer_source_rgb(frame_index, width, height)
    return rgb888_to_bmp(data, width, height), sha


def make_output_placeholder_svg(width: int = DEFAULT_WIDTH, height: int = DEFAULT_HEIGHT) -> bytes:
    """Return a plain output placeholder."""
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  <rect width="100%" height="100%" fill="#fff"/>
  <rect x="1" y="1" width="{width - 2}" height="{height - 2}" fill="none" stroke="#000" stroke-width="2"/>
  <text x="16" y="32" fill="#000" font-family="Consolas, monospace" font-size="20">FPGA 输出</text>
  <text x="16" y="64" fill="#000" font-family="Consolas, monospace" font-size="16">尚未配置 HDMI 捕获图像。</text>
  <text x="16" y="92" fill="#000" font-family="Consolas, monospace" font-size="16">此面板仅用于输出验证。</text>
</svg>
"""
    return svg.encode("utf-8")


def dashboard_html(actions_enabled: bool = True) -> bytes:
    policy = html.escape(NO_CAMERA_POLICY)
    disabled_attr = "" if actions_enabled else " disabled"
    page = f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Zynq 视频控制台</title>
  <style>
    * {{ box-sizing: border-box; }}
    body {{
      margin: 16px;
      color: #000;
      background: #fff;
      font-family: Consolas, "Courier New", monospace;
      font-size: 14px;
    }}
    header {{ margin-bottom: 12px; }}
    h1 {{ margin: 0 0 8px 0; font-size: 20px; font-weight: 700; }}
    main {{
      display: grid;
      grid-template-columns: 1fr 1fr 320px;
      gap: 12px;
    }}
    section {{ border: 1px solid #000; padding: 8px; min-width: 0; }}
    h2 {{ margin: 0 0 8px 0; font-size: 16px; }}
    img.preview {{
      display: block;
      width: 100%;
      aspect-ratio: 4 / 3;
      border: 1px solid #000;
      object-fit: contain;
      background: #fff;
    }}
    .meta, .statusline {{ margin-top: 8px; white-space: pre-wrap; }}
    .controls {{ display: grid; gap: 6px; margin-bottom: 8px; }}
    button {{
      padding: 6px 8px;
      border: 1px solid #000;
      color: #000;
      background: #eee;
      font: inherit;
      text-align: left;
      cursor: pointer;
    }}
    button:disabled {{ color: #777; cursor: not-allowed; }}
    pre.log {{
      height: 260px;
      overflow: auto;
      margin: 0;
      padding: 8px;
      border: 1px solid #000;
      background: #fff;
      color: #000;
      white-space: pre-wrap;
    }}
    @media (max-width: 1100px) {{
      main {{ grid-template-columns: 1fr; }}
    }}
  </style>
</head>
<body>
  <header>
    <h1>Zynq 视频控制台</h1>
    <div data-testid="no-camera-policy">{policy}</div>
  </header>
  <main>
    <section data-panel="input">
      <h2>输入到 FPGA</h2>
      <img class="preview" id="input-preview" src="/api/input-stream.mjpeg" alt="PC 端实际发送的 GStreamer 源视频流">
      <div class="meta">来源：PC 端 GStreamer 演示源预览
摄像头：禁用
自定义文件：暂缓</div>
    </section>
    <section data-panel="output">
      <h2>FPGA 输出</h2>
      <img class="preview" id="output-preview" src="/api/output-stream.mjpeg" alt="FPGA HDMI 实时回传预览">
      <div class="meta">来源：通过采集卡读取的 HDMI 实时回传
角色：GStreamer RTP/JPEG 到 fbdevsink 的输出回看
说明：Windows 可能把 HDMI/UVC 采集卡标记为摄像头设备</div>
    </section>
    <section data-panel="control">
      <h2>控制</h2>
      <div class="controls">
        <button{disabled_attr} data-action="start-stream" onclick="postAction('start-stream')">启动视频流</button>
        <button{disabled_attr} data-action="stop-stream" onclick="postAction('stop-stream')">停止视频流</button>
        <button{disabled_attr} data-action="capture-output" onclick="postAction('capture-output')">捕获输出</button>
        <button{disabled_attr} data-action="pause-receiver" onclick="postAction('pause-receiver')">暂停接收端</button>
        <button{disabled_attr} data-action="resume-receiver" onclick="postAction('resume-receiver')">恢复接收端</button>
        <button{disabled_attr} data-action="receiver-status" onclick="postAction('receiver-status')">接收端状态</button>
        <button{disabled_attr} data-action="effect-none" onclick="postAction('effect-none')">关闭特效</button>
        <button{disabled_attr} data-action="effect-invert" onclick="postAction('effect-invert')">反色特效</button>
        <button{disabled_attr} data-action="pip-top-left" onclick="postAction('pip-top-left')">PIP 左上</button>
        <button{disabled_attr} data-action="pip-bottom-right" onclick="postAction('pip-bottom-right')">PIP 右下</button>
        <button{disabled_attr} data-action="pip-large" onclick="postAction('pip-large')">PIP 放大</button>
        <button{disabled_attr} data-action="pip-small" onclick="postAction('pip-small')">PIP 缩小</button>
        <button{disabled_attr} data-action="pip-invert" onclick="postAction('pip-invert')">PIP 反色</button>
        <button{disabled_attr} data-action="pip-grayscale" onclick="postAction('pip-grayscale')">PIP 灰度</button>
        <button{disabled_attr} data-action="pip-bypass" onclick="postAction('pip-bypass')">PIP 旁路</button>
      </div>
      <div class="statusline" id="action-status">加载中...</div>
      <pre class="log" id="log">加载中...</pre>
    </section>
  </main>
  <script>
    function zh(value) {{
      const map = {{
        "gstreamer": "GStreamer",
        "legacy-udp": "旧UDP",
        "rtp/raw": "RTP/raw",
        "rtp/jpeg": "RTP/JPEG",
        "zvid-udp": "ZVID/UDP",
        "live": "实时",
        "dry-run": "演练",
        "running": "运行",
        "stopped": "停止",
        "idle": "空闲",
        "enabled": "启用",
        "disabled": "禁用",
        "streaming": "传输中",
        "failed": "失败",
        "ok": "正常",
        "none": "无",
        "invert": "反色",
        "not-configured": "未配置"
      }};
      return map[value] || value;
    }}
    function applyState(state) {{
      const pipStatus = state.control_panel.last_pip_register_status;
      const pipLatency = state.control_panel.last_pip_control_latency_ms;
      const pipSummary = pipStatus
        ? " PIP_REG=enable:" + pipStatus.enable + ",x:" + pipStatus.x + ",y:" + pipStatus.y + ",scale:" + pipStatus.scale + ",effect:" + pipStatus.effect
        : " PIP_REG=waiting";
      document.getElementById("log").textContent = state.logs.join("\\n");
      document.getElementById("action-status").textContent =
        "链路=" + zh(state.pipeline.mode) +
        " 传输=" + zh(state.pipeline.transport) +
        " 模式=" + zh(state.control_panel.action_mode) +
        " 视频流=" + zh(state.control_panel.stream_state) +
        " 发送进程=" + (state.control_panel.sender_pid || "无") +
        " HDMI=" + zh(state.output_preview.capture_status) +
        " UART=" + zh(state.control_panel.uart_status) +
        " 特效=" + zh(state.control_panel.selected_effect) +
        " 已发送帧=" + (state.input_source.latest_sent_frame_id ?? "等待") +
        " HDMI帧=" + (state.input_source.latest_hdmi_frame_id ?? "等待");
      document.getElementById("action-status").textContent +=
        " PIP_CTRL=" + (state.control_panel.last_pip_control_transport || "waiting") +
        " PIP_LATENCY_MS=" + (pipLatency ?? "waiting") +
        pipSummary;
    }}
    async function refreshState() {{
      const state = await fetch("/api/state").then(r => r.json());
      applyState(state);
    }}
    async function postAction(action) {{
      const response = await fetch("/api/action", {{
        method: "POST",
        headers: {{ "Content-Type": "application/json" }},
        body: JSON.stringify({{ action }})
      }});
      const result = await response.json();
      if (result.state) {{
        applyState(result.state);
      }}
      if (!response.ok) {{
        document.getElementById("log").textContent += "\\n动作失败 action=" + action + " error=" + result.error;
      }}
    }}
    refreshState();
    setInterval(refreshState, 1000);
  </script>
</body>
</html>
"""
    return page.encode("utf-8")


class DashboardState:
    def __init__(
        self,
        output_image: Path | None = None,
        *,
        repo_root: Path | None = None,
        board_host: str = DEFAULT_BOARD_HOST,
        udp_port: int = DEFAULT_UDP_PORT,
        sender_frames: int = DEFAULT_SENDER_FRAMES,
        sender_fps: float = DEFAULT_SENDER_FPS,
        sender_start_frame_id: int = DEFAULT_SENDER_START_FRAME_ID,
        sender_warmup_frames: int = 0,
        sender_content_hold_frames: int = DEFAULT_CONTENT_HOLD_FRAMES,
        sender_width: int = DEFAULT_WIDTH,
        sender_height: int = DEFAULT_HEIGHT,
        sender_payload: int = DEFAULT_SENDER_PAYLOAD,
        sender_inter_packet_us: float = DEFAULT_SENDER_INTER_PACKET_US,
        pipeline: str = DEFAULT_PIPELINE,
        gst_conda_env: Path | str = DEFAULT_GST_CONDA_ENV,
        gst_port: int = DEFAULT_GST_PORT,
        gst_input_width: int = DEFAULT_GST_INPUT_WIDTH,
        gst_input_height: int = DEFAULT_GST_INPUT_HEIGHT,
        gst_output_width: int = DEFAULT_GST_OUTPUT_WIDTH,
        gst_output_height: int = DEFAULT_GST_OUTPUT_HEIGHT,
        gst_fps: int = DEFAULT_GST_FPS,
        gst_num_buffers: int = DEFAULT_GST_NUM_BUFFERS,
        gst_payload_type: int = DEFAULT_GST_PAYLOAD_TYPE,
        gst_mtu: int = DEFAULT_GST_MTU,
        gst_board_log: str = DEFAULT_GST_BOARD_LOG,
        gst_board_pid: str = DEFAULT_GST_BOARD_PID,
        uart_port: str = DEFAULT_UART_PORT,
        uart_baud: int = DEFAULT_UART_BAUD,
        uart_login_root: bool = False,
        uart_password: str = "",
        control_fifo: str = DEFAULT_CONTROL_FIFO,
        pip_control_host: str | None = None,
        pip_control_port: int = DEFAULT_PIP_CONTROL_PORT,
        pip_control_timeout_s: float = DEFAULT_PIP_CONTROL_TIMEOUT_S,
        pip_control_fallback_uart: bool = True,
        capture_enabled: bool = True,
        capture_device: str = DEFAULT_CAPTURE_DEVICE,
        capture_backend: str = DEFAULT_CAPTURE_BACKEND,
        capture_width: int = DEFAULT_CAPTURE_WIDTH,
        capture_height: int = DEFAULT_CAPTURE_HEIGHT,
        capture_frames: int = DEFAULT_CAPTURE_FRAMES,
        capture_profile: str = DEFAULT_CAPTURE_PROFILE,
        capture_save_samples: int = DEFAULT_CAPTURE_SAVE_SAMPLES,
        stream_fps: float = DEFAULT_STREAM_FPS,
        auto_capture_on_start: bool = False,
        actions_enabled: bool = True,
        action_mode: str = "live",
        log_dir: Path | None = None,
    ) -> None:
        self.started_at = time.time()
        self.repo_root = repo_root or Path(__file__).resolve().parents[2]
        self.board_host = board_host
        self.udp_port = udp_port
        self.sender_frames = sender_frames
        self.sender_fps = sender_fps
        self.sender_start_frame_id = sender_start_frame_id
        self.sender_warmup_frames = sender_warmup_frames
        self.sender_content_hold_frames = sender_content_hold_frames
        self.sender_width = sender_width
        self.sender_height = sender_height
        self.sender_payload = sender_payload
        self.sender_inter_packet_us = sender_inter_packet_us
        self.pipeline = pipeline
        self.gst_conda_env = Path(gst_conda_env)
        self.gst_port = gst_port
        self.gst_input_width = gst_input_width
        self.gst_input_height = gst_input_height
        self.gst_output_width = gst_output_width
        self.gst_output_height = gst_output_height
        self.gst_fps = gst_fps
        self.gst_num_buffers = gst_num_buffers
        self.gst_payload_type = gst_payload_type
        self.gst_mtu = gst_mtu
        self.gst_board_log = gst_board_log
        self.gst_board_pid = gst_board_pid
        self.uart_port = uart_port
        self.uart_baud = uart_baud
        self.uart_login_root = uart_login_root
        self.uart_password = uart_password
        self.control_fifo = control_fifo
        self.pip_control_host = pip_control_host or board_host
        self.pip_control_port = pip_control_port
        self.pip_control_timeout_s = pip_control_timeout_s
        self.pip_control_fallback_uart = pip_control_fallback_uart
        self.capture_enabled = capture_enabled
        self.capture_device = capture_device
        self.capture_backend = capture_backend
        self.capture_width = capture_width
        self.capture_height = capture_height
        self.capture_frames = capture_frames
        self.capture_profile = capture_profile
        self.capture_save_samples = capture_save_samples
        self.stream_fps = stream_fps
        self.auto_capture_on_start = auto_capture_on_start
        self.actions_enabled = actions_enabled
        self.action_mode = action_mode
        self.log_dir = log_dir or self.repo_root / "build" / "dashboard-live"
        self.sender_out_dir = self.log_dir / "sender"
        self.sender_live_state_path = self.sender_out_dir / "live-state.json"
        self.gst_preview_dir = self.sender_out_dir / "gstreamer-preview"
        self.sender_live_state_path.unlink(missing_ok=True)
        self.output_image = output_image or (self.log_dir / "hdmi-capture" / "latest.png")
        self.lock = threading.Lock()
        self.sender_process: subprocess.Popen[bytes] | None = None
        self.sender_last_exit_code: int | None = None
        self.capture_status = "idle" if capture_enabled else "disabled"
        self.capture_last_report: Path | None = None
        self.capture_last_log: Path | None = None
        self.capture_thread: threading.Thread | None = None
        self.capture_count = 0
        self.capture_started_at_s: float | None = None
        self.capture_finished_at_s: float | None = None
        self.capture_last_error: str | None = None
        self.live_stream_status = "enabled" if capture_enabled else "disabled"
        self.live_stream_detail = ""
        self.live_stream_clients = 0
        self.last_returned_frame_id: int | None = None
        self.last_returned_frame_at_s: float | None = None
        self.receiver_paused = False
        self.selected_effect = "none"
        self.last_action: dict[str, Any] | None = None
        self.last_pip_control_latency_ms: float | None = None
        self.last_pip_control_transport: str | None = None
        self.last_pip_register_status: dict[str, Any] | None = None
        self.logs = [
            "控制台就绪",
            f"视频链路：{pipeline}",
            f"GStreamer RTP/JPEG 目标：{board_host}:{gst_port}",
            f"GStreamer 输入：{gst_input_width}x{gst_input_height}@{gst_fps}fps -> 板端缩放到 {gst_output_width}x{gst_output_height}",
            f"旧 UDP 回退目标：{board_host}:{udp_port}",
            f"HDMI 采集：{'启用' if capture_enabled else '禁用'}",
            "HDMI 回传：右侧面板读取实时 MJPEG；Windows 可能把 HDMI/UVC 采集卡标记为摄像头",
            f"UART：{uart_port or '未配置'}",
            "摄像头/网络摄像头输入：禁用",
            "自定义文件输入：暂缓",
        ]

    def action_catalog(self) -> list[dict[str, str]]:
        return [dict(item) for item in ACTION_DEFINITIONS]

    def _append_log_locked(self, line: str) -> None:
        self.logs.append(line)
        del self.logs[:-120]

    def _read_sender_live_state_locked(self) -> dict[str, Any] | None:
        try:
            return json.loads(self.sender_live_state_path.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            return None

    def input_preview_descriptor(self) -> dict[str, Any]:
        with self.lock:
            return self._input_preview_descriptor_locked()

    def _input_preview_descriptor_locked(self) -> dict[str, Any]:
        if self.pipeline == "gstreamer":
            preview = self._latest_gstreamer_preview_frame_locked()
            if preview is not None:
                return {
                    "frame_id": int(preview.stem.rsplit("-", 1)[-1]),
                    "hdmi_frame_id": self.last_returned_frame_id,
                    "latest_sent_frame_id": int(preview.stem.rsplit("-", 1)[-1]),
                    "source": "latest-actual-gstreamer-source-frame",
                }
            elapsed = max(0.0, time.time() - self.started_at)
            frame_id = int(elapsed * max(1, self.gst_fps))
            return {
                "frame_id": frame_id,
                "hdmi_frame_id": self.last_returned_frame_id,
                "latest_sent_frame_id": frame_id if self._sender_alive_locked() else None,
                "source": "waiting-for-actual-gstreamer-source-frame",
            }

        live = self._read_sender_live_state_locked()
        hdmi_frame_id = self.last_returned_frame_id
        if live is None:
            return {
                "frame_id": self.sender_start_frame_id,
                "hdmi_frame_id": None,
                "latest_sent_frame_id": None,
                "source": "waiting-for-actual-sent-frame",
            }

        latest_sent = int(live["frame_id"])
        return {
            "frame_id": latest_sent,
            "hdmi_frame_id": hdmi_frame_id,
            "latest_sent_frame_id": latest_sent,
            "source": "latest-actual-sent-frame",
        }

    def _latest_gstreamer_preview_frame_locked(self) -> Path | None:
        expected_size = self.gst_input_width * self.gst_input_height * 3
        candidates = sorted(self.gst_preview_dir.glob("frame-*.rgb"), reverse=True)
        for path in candidates:
            try:
                if path.stat().st_size == expected_size:
                    return path
            except OSError:
                continue
        return None

    def gstreamer_input_preview_bmp(self, frame_id: int) -> tuple[bytes, str]:
        data, sha = self.gstreamer_input_preview_rgb(frame_id)
        return rgb888_to_bmp(data, self.gst_input_width, self.gst_input_height), sha

    def gstreamer_input_preview_rgb(self, frame_id: int) -> tuple[bytes, str]:
        with self.lock:
            preview = self._latest_gstreamer_preview_frame_locked()
        if preview is not None:
            try:
                data = preview.read_bytes()
                if len(data) == self.gst_input_width * self.gst_input_height * 3:
                    return data, frame_sha256(data)
            except OSError:
                pass
        return make_gstreamer_source_rgb(frame_id, self.gst_input_width, self.gst_input_height)

    def _record_returned_frame_id(self, frame_id: int) -> None:
        with self.lock:
            self.last_returned_frame_id = frame_id
            self.last_returned_frame_at_s = round(time.time() - self.started_at, 3)

    def _sender_alive_locked(self) -> bool:
        if self.sender_process is None:
            return False
        code = self.sender_process.poll()
        if code is None:
            return True
        self.sender_last_exit_code = code
        return False

    def _sender_pid_locked(self) -> int | None:
        if self._sender_alive_locked() and self.sender_process is not None:
            return self.sender_process.pid
        return None

    def _sender_log_paths(self) -> tuple[Path, Path]:
        self.log_dir.mkdir(parents=True, exist_ok=True)
        return self.log_dir / "sender.out.log", self.log_dir / "sender.err.log"

    def _sender_command_locked(self) -> list[str]:
        if self.pipeline == "gstreamer":
            return self._gstreamer_sender_command_locked()
        return [
            sys.executable,
            str(self.repo_root / "tools" / "send_unified_test_video_udp.py"),
            self.board_host,
            "--port",
            str(self.udp_port),
            "--width",
            str(self.sender_width),
            "--height",
            str(self.sender_height),
            "--fps",
            f"{self.sender_fps:g}",
            "--frames",
            str(self.sender_frames),
            "--start-frame-id",
            str(self.sender_start_frame_id),
            "--warmup-frames",
            str(self.sender_warmup_frames),
            "--warmup-start-frame-id",
            "0",
            "--payload",
            str(self.sender_payload),
            "--inter-packet-us",
            f"{self.sender_inter_packet_us:g}",
            "--packet-window-fraction",
            "0.85",
            "--burst",
            "--content-hold-frames",
            str(self.sender_content_hold_frames),
            "--live-state-json",
            str(self.sender_live_state_path),
            "--out-dir",
            str(self.sender_out_dir),
        ]

    def _gstreamer_sender_command_locked(self) -> list[str]:
        preview_pattern = (self.gst_preview_dir / "frame-%08d.rgb").resolve().as_posix()
        return [
            "conda",
            "run",
            "-p",
            str(self.repo_root / self.gst_conda_env),
            "gst-launch-1.0",
            "-v",
            "videotestsrc",
            f"num-buffers={self.gst_num_buffers}",
            "is-live=true",
            "pattern=ball",
            "motion=sweep",
            "animation-mode=wall-time",
            "flip=false",
            "background-color=0xff14354a",
            "foreground-color=0xffffd166",
            "!",
            f"video/x-raw,format=RGB,width={self.gst_input_width},height={self.gst_input_height},framerate={self.gst_fps}/1",
            "!",
            "tee",
            "name=source",
            "source.",
            "!",
            "queue",
            "!",
            "videoconvert",
            "!",
            "video/x-raw,format=I420",
            "!",
            "jpegenc",
            "quality=90",
            "!",
            "rtpjpegpay",
            f"pt={self.gst_payload_type}",
            f"mtu={self.gst_mtu}",
            "!",
            "udpsink",
            f"host={self.board_host}",
            f"port={self.gst_port}",
            "sync=false",
            "async=false",
            "source.",
            "!",
            "queue",
            "leaky=downstream",
            "max-size-buffers=1",
            "!",
            "multifilesink",
            f"location={preview_pattern}",
            "max-files=3",
        ]

    def _gstreamer_caps(self) -> str:
        return (
            'application/x-rtp, media=(string)video, clock-rate=(int)90000, '
            f'encoding-name=(string)JPEG, payload=(int){self.gst_payload_type}'
        )

    def _gstreamer_board_receiver_command(self) -> str:
        caps = self._gstreamer_caps().replace('"', '\\"')
        pipeline = (
            f'gst-launch-1.0 -v udpsrc port={self.gst_port} caps="{caps}" '
            f'! rtpjitterbuffer latency=100 drop-on-latency=true '
            f'! rtpjpegdepay ! jpegdec ! videoconvert ! videoscale '
            f'! video/x-raw,format=BGR,width={self.gst_output_width},height={self.gst_output_height} '
            f'! fbdevsink device=/dev/fb0 sync=true'
        )
        return (
            "killall gst-launch-1.0 2>/dev/null || true; "
            "setterm -cursor off > /dev/$(cat /sys/class/tty/tty0/active) 2>/dev/null || true; "
            f"nohup {pipeline} > {self.gst_board_log} 2>&1 & echo $! > {self.gst_board_pid}; "
            "sleep 1; "
            f"echo GSTREAMER_RECEIVER_STARTED pid=$(cat {self.gst_board_pid} 2>/dev/null) log={self.gst_board_log}; "
            f"tail -n 20 {self.gst_board_log} 2>/dev/null || true"
        )

    def _gstreamer_board_stop_command(self) -> str:
        return (
            "killall gst-launch-1.0 2>/dev/null || true; "
            f"rm -f {self.gst_board_pid}; echo GSTREAMER_RECEIVER_STOPPED"
        )

    def _capture_command_locked(self) -> tuple[list[str], Path, Path, Path]:
        capture_dir = self.log_dir / "hdmi-capture"
        capture_dir.mkdir(parents=True, exist_ok=True)
        report_path = capture_dir / "latest-validation.json"
        stdout_path = capture_dir / "capture.out.log"
        stderr_path = capture_dir / "capture.err.log"
        cmd = [
            sys.executable,
            str(self.repo_root / "tools" / "capture_hdmi.py"),
            "--device",
            self.capture_device,
            "--backend",
            self.capture_backend,
            "--width",
            str(self.capture_width),
            "--height",
            str(self.capture_height),
            "--frames",
            str(self.capture_frames),
            "--validation-profile",
            self.capture_profile,
            "--out-dir",
            str(capture_dir),
        ]
        if self.capture_save_samples > 0:
            cmd.extend(["--save-samples", str(self.capture_save_samples)])
        return cmd, report_path, stdout_path, stderr_path

    def _capture_output_locked(self) -> tuple[bool, str]:
        if not self.capture_enabled:
            self.capture_status = "disabled"
            return False, "HDMI_CAPTURE_DISABLED"

        cmd, report_path, stdout_path, stderr_path = self._capture_command_locked()
        timeout_s = max(90.0, 10.0 + self.capture_frames * 3.0)
        self.capture_status = "running"
        try:
            result = subprocess.run(
                cmd,
                cwd=str(self.repo_root),
                capture_output=True,
                text=True,
                timeout=timeout_s,
                check=False,
            )
        except subprocess.TimeoutExpired:
            self.capture_status = "timeout"
            self.capture_last_report = report_path
            return False, f"HDMI_CAPTURE_TIMEOUT report={report_path}"

        stdout_path.write_text(result.stdout, encoding="utf-8")
        stderr_path.write_text(result.stderr, encoding="utf-8")
        self.capture_last_report = report_path
        self.capture_last_log = stdout_path
        if result.returncode == 0 and self.output_image.exists():
            self.capture_status = "ok"
            return True, f"HDMI_CAPTURE_OK image={self.output_image} report={report_path}"

        self.capture_status = "failed"
        detail = (result.stderr or result.stdout).strip().replace("\r", " ").replace("\n", " ")
        return False, f"HDMI_CAPTURE_FAILED report={report_path} detail={detail[:300]}"

    def _capture_worker(self, cmd: list[str], report_path: Path, stdout_path: Path, stderr_path: Path) -> None:
        timeout_s = max(90.0, 10.0 + self.capture_frames * 3.0)
        ok = False
        detail = ""
        try:
            result = subprocess.run(
                cmd,
                cwd=str(self.repo_root),
                capture_output=True,
                text=True,
                timeout=timeout_s,
                check=False,
            )
            stdout_path.write_text(result.stdout, encoding="utf-8")
            stderr_path.write_text(result.stderr, encoding="utf-8")
            if result.returncode == 0 and self.output_image.exists():
                ok = True
                detail = f"HDMI_CAPTURE_OK image={self.output_image} report={report_path}"
            else:
                raw = (result.stderr or result.stdout).strip().replace("\r", " ").replace("\n", " ")
                detail = f"HDMI_CAPTURE_FAILED report={report_path} detail={raw[:300]}"
        except subprocess.TimeoutExpired:
            detail = f"HDMI_CAPTURE_TIMEOUT report={report_path}"
        except OSError as exc:
            detail = f"HDMI_CAPTURE_OS_ERROR report={report_path} detail={exc}"

        with self.lock:
            self.capture_last_report = report_path
            self.capture_last_log = stdout_path
            self.capture_finished_at_s = round(time.time() - self.started_at, 3)
            self.capture_status = "ok" if ok else "failed"
            self.capture_last_error = None if ok else detail
            self._append_log_locked(detail)

    def _start_capture_thread_locked(self) -> tuple[bool, str]:
        if not self.capture_enabled:
            self.capture_status = "disabled"
            return False, "HDMI_CAPTURE_DISABLED"
        if self.capture_thread is not None and self.capture_thread.is_alive():
            return True, "HDMI_CAPTURE_ALREADY_RUNNING"

        cmd, report_path, stdout_path, stderr_path = self._capture_command_locked()
        self.capture_count += 1
        self.capture_started_at_s = round(time.time() - self.started_at, 3)
        self.capture_finished_at_s = None
        self.capture_last_error = None
        self.capture_status = "running"
        self.capture_thread = threading.Thread(
            target=self._capture_worker,
            args=(cmd, report_path, stdout_path, stderr_path),
            daemon=True,
        )
        self.capture_thread.start()
        return True, f"HDMI_CAPTURE_SCHEDULED count={self.capture_count} report={report_path}"

    def _set_live_stream_status(self, status: str, detail: str, delta_clients: int = 0) -> None:
        with self.lock:
            self.live_stream_status = status
            self.live_stream_detail = detail
            self.live_stream_clients = max(0, self.live_stream_clients + delta_clients)

    def _open_live_capture(self) -> tuple[Any, int, str]:
        if not self.capture_enabled:
            raise RuntimeError("HDMI_STREAM_DISABLED")

        try:
            import cv2
        except ImportError as exc:
            raise RuntimeError("OPENCV_NOT_AVAILABLE") from exc

        backend_by_name = {
            "dshow": cv2.CAP_DSHOW,
            "msmf": cv2.CAP_MSMF,
            "any": cv2.CAP_ANY,
        }
        backend = backend_by_name.get(self.capture_backend, cv2.CAP_DSHOW)
        indices = range(9) if self.capture_device == "auto" else [int(self.capture_device)]
        fallback: tuple[Any, int, str] | None = None
        for index in indices:
            cap = cv2.VideoCapture(index, backend)
            if not cap.isOpened():
                cap.release()
                continue
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.capture_width)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.capture_height)
            cap.set(cv2.CAP_PROP_FPS, max(1.0, self.stream_fps))
            ok, frame = cap.read()
            actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            detail = f"device={index} backend={self.capture_backend} size={actual_w}x{actual_h}"
            if ok and frame is not None and frame.size:
                if actual_w == self.capture_width and actual_h == self.capture_height:
                    if fallback is not None:
                        fallback[0].release()
                    return cap, index, detail
                if fallback is None:
                    fallback = (cap, index, detail)
                    continue
            cap.release()

        if fallback is not None:
            return fallback
        raise RuntimeError("HDMI_STREAM_OPEN_FAILED")

    def _start_sender_locked(self) -> tuple[bool, str]:
        if self._sender_alive_locked():
            pid = self.sender_process.pid if self.sender_process else "unknown"
            if self.auto_capture_on_start:
                capture_ok, capture_detail = self._start_capture_thread_locked()
                suffix = capture_detail if capture_ok else f"采集警告：{capture_detail}"
            else:
                suffix = "HDMI_RETURN_STREAM_READY endpoint=/api/output-stream.mjpeg"
            return True, f"发送端已在运行 pid={pid}; {suffix}"

        receiver_detail = ""
        if self.pipeline == "gstreamer":
            ok, receiver_detail = self._run_uart_commands_locked(
                "gstreamer-start",
                [self._gstreamer_board_receiver_command()],
                timeout_s=14,
            )
            if not ok:
                return False, f"GSTREAMER_RECEIVER_START_FAILED {receiver_detail}"

        stdout_path, stderr_path = self._sender_log_paths()
        cmd = self._sender_command_locked()
        self.sender_live_state_path.unlink(missing_ok=True)
        self.sender_out_dir.mkdir(parents=True, exist_ok=True)
        self.gst_preview_dir.mkdir(parents=True, exist_ok=True)
        for path in self.gst_preview_dir.glob("frame-*.rgb"):
            path.unlink(missing_ok=True)
        self.last_returned_frame_id = None
        self.last_returned_frame_at_s = None
        with stdout_path.open("wb") as stdout_file, stderr_path.open("wb") as stderr_file:
            self.sender_process = subprocess.Popen(
                cmd,
                cwd=str(self.repo_root),
                stdout=stdout_file,
                stderr=stderr_file,
            )
        self.sender_last_exit_code = None
        time.sleep(0.5)
        if self.auto_capture_on_start:
            capture_ok, capture_detail = self._start_capture_thread_locked()
            suffix = capture_detail if capture_ok else f"采集警告：{capture_detail}"
        else:
            suffix = "HDMI_RETURN_STREAM_READY endpoint=/api/output-stream.mjpeg"
        receiver_prefix = f"{receiver_detail}; " if receiver_detail else ""
        return True, f"{receiver_prefix}发送端已启动 pid={self.sender_process.pid} log={stdout_path}; {suffix}"

    def _stop_sender_locked(self) -> tuple[bool, str]:
        board_stop_detail = ""
        if self.pipeline == "gstreamer" and self.uart_port:
            ok, board_stop_detail = self._run_uart_commands_locked(
                "gstreamer-stop",
                [self._gstreamer_board_stop_command()],
                timeout_s=8,
            )
            if not ok:
                board_stop_detail = f"板端停止警告：{board_stop_detail}"

        if not self._sender_alive_locked():
            suffix = f"; {board_stop_detail}" if board_stop_detail else ""
            return True, f"发送端未运行{suffix}"
        assert self.sender_process is not None
        pid = self.sender_process.pid
        self.sender_process.terminate()
        try:
            code = self.sender_process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.sender_process.kill()
            code = self.sender_process.wait(timeout=3)
        self.sender_last_exit_code = code
        suffix = f"; {board_stop_detail}" if board_stop_detail else ""
        return True, f"发送端已停止 pid={pid} exit_code={code}{suffix}"

    def _uart_commands_for_action(self, action: str) -> list[str]:
        if action == "pause-receiver":
            return [
                f"echo pause > {self.control_fifo}",
                "sleep 1",
                "tail -n 30 /tmp/fb_video_udp_receiver.log 2>/dev/null || true",
            ]
        if action == "resume-receiver":
            return [
                f"echo resume > {self.control_fifo}",
                "sleep 1",
                "tail -n 30 /tmp/fb_video_udp_receiver.log 2>/dev/null || true",
            ]
        if action == "receiver-status":
            return [
                f"echo status > {self.control_fifo}",
                "sleep 1",
                "tail -n 30 /tmp/fb_video_udp_receiver.log 2>/dev/null || true",
            ]
        raise ValueError(action)

    def _run_uart_action_locked(self, action: str) -> tuple[bool, str]:
        return self._run_uart_commands_locked(action, self._uart_commands_for_action(action), timeout_s=8)

    def _run_pip_preset_tcp_locked(self, preset: str) -> tuple[bool, str, str, float]:
        started = time.perf_counter()
        try:
            with socket.create_connection(
                (self.pip_control_host, self.pip_control_port),
                timeout=self.pip_control_timeout_s,
            ) as sock:
                sock.settimeout(self.pip_control_timeout_s)
                sock.sendall(f"preset {preset}\n".encode("ascii"))
                chunks: list[bytes] = []
                while True:
                    chunk = sock.recv(4096)
                    if not chunk:
                        break
                    chunks.append(chunk)
        except OSError as exc:
            elapsed_ms = (time.perf_counter() - started) * 1000.0
            return False, f"TCP_PIP_CONTROL_FAILED host={self.pip_control_host} port={self.pip_control_port} latency_ms={elapsed_ms:.3f} detail={exc}", "", elapsed_ms

        elapsed_ms = (time.perf_counter() - started) * 1000.0
        text = b"".join(chunks).decode("utf-8", errors="replace")
        compact = " | ".join(line.strip() for line in text.splitlines() if line.strip())
        if "PIP_CONTROL_OK" not in text:
            return False, f"TCP_PIP_CONTROL_ERROR host={self.pip_control_host} port={self.pip_control_port} latency_ms={elapsed_ms:.3f} response={compact[:600]}", text, elapsed_ms
        return True, f"tcp pip control host={self.pip_control_host} port={self.pip_control_port} latency_ms={elapsed_ms:.3f} response={compact[:600]}", text, elapsed_ms

    def _record_pip_control_result_locked(self, transport: str, elapsed_ms: float, text: str) -> None:
        status = parse_key_value_marker(text, "PIP_EFFECT_STATUS")
        control = parse_key_value_marker(text, "PIP_CONTROL_OK")
        if status is not None and control is not None and "latency_us" in control:
            status["server_latency_us"] = control["latency_us"]
        self.last_pip_control_transport = transport
        self.last_pip_control_latency_ms = round(elapsed_ms, 3)
        self.last_pip_register_status = status

    def _run_pip_preset_locked(self, action: str) -> tuple[bool, str]:
        preset = PIP_PRESET_ACTIONS[action]
        ok, detail, text, elapsed_ms = self._run_pip_preset_tcp_locked(preset)
        if ok:
            self._record_pip_control_result_locked("tcp", elapsed_ms, text)
            return ok, detail

        tcp_detail = detail
        if not self.pip_control_fallback_uart:
            self._record_pip_control_result_locked("tcp-failed", elapsed_ms, text)
            return False, tcp_detail

        uart_started = time.perf_counter()
        ok, uart_detail = self._run_uart_commands_locked(
            action,
            [
                f"/tmp/pip_effect_ctl --preset {preset}",
                "/tmp/pip_effect_ctl --status-only",
            ],
            timeout_s=20,
        )
        uart_elapsed_ms = (time.perf_counter() - uart_started) * 1000.0
        self._record_pip_control_result_locked("uart-fallback" if ok else "uart-fallback-failed", uart_elapsed_ms, uart_detail)
        fallback_detail = f"{tcp_detail}; fallback=uart; {uart_detail}; latency_ms={uart_elapsed_ms:.3f}"
        return ok, fallback_detail

    def _run_uart_commands_locked(self, label: str, commands: list[str], timeout_s: float = 12.0) -> tuple[bool, str]:
        if not self.uart_port:
            return False, "UART_NOT_CONFIGURED"

        self.log_dir.mkdir(parents=True, exist_ok=True)
        stamp = int(time.time() * 1000)
        safe_label = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in label)
        rel_output = self.log_dir / f"uart-{safe_label}-{stamp}.log"
        rel_commands = self.log_dir / f"uart-{safe_label}-{stamp}.commands"
        command_path = self.repo_root / rel_commands
        command_path.parent.mkdir(parents=True, exist_ok=True)
        command_path.write_text("\n".join(commands) + "\n", encoding="ascii")
        script = self.repo_root / "tools" / "uart_run_commands.ps1"
        cmd = [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(script),
            "-Port",
            self.uart_port,
            "-BaudRate",
            str(self.uart_baud),
            "-CommandFile",
            str(rel_commands),
            "-InitialReadSeconds",
            "0",
            "-InterCommandDelayMilliseconds",
            "250",
            "-FinalReadSeconds",
            "1",
            "-OutputPath",
            str(rel_output),
        ]
        if self.uart_login_root:
            cmd.append("-LoginRoot")
        if self.uart_password:
            cmd.extend(["-Password", self.uart_password])
        try:
            result = subprocess.run(
                cmd,
                cwd=str(self.repo_root),
                capture_output=True,
                text=True,
                timeout=timeout_s,
                check=False,
            )
        except subprocess.TimeoutExpired:
            return False, f"UART_TIMEOUT port={self.uart_port}"

        if result.returncode != 0:
            detail = (result.stderr or result.stdout).strip().replace("\r", " ").replace("\n", " ")
            return False, f"UART_COMMAND_FAILED port={self.uart_port} detail={detail[:300]}"

        log_path = self.repo_root / rel_output
        markers: list[str] = []
        if log_path.exists():
            log_text = log_path.read_text(encoding="utf-8", errors="replace")
            for line in log_text.splitlines():
                stripped = line.strip()
                if any(token in stripped for token in ("CONTROL_", "VIDEO_UDP_", "FB_INFO", "PIP_EFFECT_", "GSTREAMER_", "UART_RUN_COMMANDS_OK", "rtpjpegdepay", "jpegdec", "fbdevsink")):
                    markers.append(stripped)
        marker_tail = " | ".join(markers[-6:]) if markers else "no receiver response marker"
        return True, f"uart command sent port={self.uart_port} log={rel_output} response={marker_tail[:600]}"

    def run_action(self, action: str) -> dict[str, Any]:
        action_ids = {item["id"] for item in ACTION_DEFINITIONS}
        if action not in action_ids:
            return {"ok": False, "error": f"unknown action: {action}", "state": self.as_json()}

        with self.lock:
            if not self.actions_enabled:
                return {"ok": False, "error": "dashboard actions are disabled", "state": self._as_json_locked()}

            ok = True
            detail = ""
            if self.action_mode == "dry-run":
                detail = self._run_dry_action_locked(action)
            elif action == "start-stream":
                ok, detail = self._start_sender_locked()
            elif action == "stop-stream":
                ok, detail = self._stop_sender_locked()
            elif action == "capture-output":
                ok, detail = self._start_capture_thread_locked()
            elif action in {"pause-receiver", "resume-receiver", "receiver-status"}:
                if self.pipeline == "gstreamer":
                    if action == "receiver-status":
                        ok, detail = self._run_uart_commands_locked(
                            "gstreamer-status",
                            [
                                f"cat {self.gst_board_pid} 2>/dev/null || true",
                                f"tail -n 40 {self.gst_board_log} 2>/dev/null || true",
                            ],
                            timeout_s=8,
                        )
                    else:
                        ok = False
                        detail = "GSTREAMER_CONTROL_NOT_IMPLEMENTED pause/resume is not wired for gst-launch pipeline"
                else:
                    ok, detail = self._run_uart_action_locked(action)
                    if ok and action == "pause-receiver":
                        self.receiver_paused = True
                    elif ok and action == "resume-receiver":
                        self.receiver_paused = False
            elif action in PIP_PRESET_ACTIONS:
                ok, detail = self._run_pip_preset_locked(action)
                if ok:
                    self.selected_effect = PIP_PRESET_ACTIONS[action]
            elif action == "effect-none":
                if self.pipeline == "gstreamer":
                    ok = False
                    detail = "GSTREAMER_EFFECT_NOT_IMPLEMENTED"
                else:
                    self.selected_effect = "none"
                    detail = "已选择特效=none；下次启动接收端时生效"
            elif action == "effect-invert":
                if self.pipeline == "gstreamer":
                    ok = False
                    detail = "GSTREAMER_EFFECT_NOT_IMPLEMENTED"
                else:
                    self.selected_effect = "invert"
                    detail = "已选择特效=invert；下次启动接收端时生效"

            status = "OK" if ok else "ERROR"
            self.last_action = {
                "action": action,
                "mode": self.action_mode,
                "ok": ok,
                "detail": detail,
                "timestamp_s": round(time.time() - self.started_at, 3),
            }
            self._append_log_locked(f"ACTION_{status} action={action} {detail}")
            response = {
                "ok": ok,
                "action": action,
                "mode": self.action_mode,
                "detail": detail,
                "state": self._as_json_locked(),
            }
            if action in PIP_PRESET_ACTIONS:
                response["pip_control_transport"] = self.last_pip_control_transport
                response["pip_control_latency_ms"] = self.last_pip_control_latency_ms
                response["pip_register_status"] = self.last_pip_register_status
            if not ok:
                response["error"] = detail
            return response

    def _run_dry_action_locked(self, action: str) -> str:
        if action == "start-stream":
            return "dry-run sender start"
        if action == "stop-stream":
            return "dry-run sender stop"
        if action == "pause-receiver":
            self.receiver_paused = True
            return "dry-run fifo_command=pause"
        if action == "resume-receiver":
            self.receiver_paused = False
            return "dry-run fifo_command=resume"
        if action == "receiver-status":
            return f"dry-run fifo_command=status paused={int(self.receiver_paused)}"
        if action == "effect-none":
            self.selected_effect = "none"
            return "dry-run effect=none"
        if action == "effect-invert":
            self.selected_effect = "invert"
            return "dry-run effect=invert"
        if action in PIP_PRESET_ACTIONS:
            self.selected_effect = PIP_PRESET_ACTIONS[action]
            return f"dry-run pip_preset={PIP_PRESET_ACTIONS[action]}"
        return "dry-run"

    def as_json(self) -> dict[str, Any]:
        with self.lock:
            return self._as_json_locked()

    def _as_json_locked(self) -> dict[str, Any]:
        sender_pid = self._sender_pid_locked()
        stream_state = "running" if sender_pid is not None else "stopped"
        live = self._read_sender_live_state_locked()
        descriptor = self._input_preview_descriptor_locked()
        return {
            "status": "action-ready" if self.actions_enabled else "disabled",
            "panels": ["input-preview", "fpga-output-preview", "function-control-panel"],
            "pipeline": {
                "mode": self.pipeline,
                "transport": "rtp/jpeg" if self.pipeline == "gstreamer" else "zvid-udp",
                "source": "videotestsrc ball" if self.pipeline == "gstreamer" else "send_unified_test_video_udp.py",
                "sink": "fbdevsink" if self.pipeline == "gstreamer" else "fbdev receiver",
                "board_port": self.gst_port if self.pipeline == "gstreamer" else self.udp_port,
                "pc_gstreamer_env": str(self.gst_conda_env) if self.pipeline == "gstreamer" else None,
                "gst_num_buffers": self.gst_num_buffers if self.pipeline == "gstreamer" else None,
            },
            "input_source": {
                "kind": "gstreamer-videotestsrc-ball" if self.pipeline == "gstreamer" else "unified-actual-sent",
                "camera_enabled": False,
                "custom_file_enabled": False,
                "policy": NO_CAMERA_POLICY,
                "preview_endpoint": "/api/input-preview.bmp",
                "live_stream_endpoint": "/api/input-stream.mjpeg",
                "preview_matches_sender_source": True,
                "preview_mode": descriptor["source"],
                "sender_kind": "gstreamer" if self.pipeline == "gstreamer" else "unified",
                "sender_fps": self.gst_fps if self.pipeline == "gstreamer" else self.sender_fps,
                "content_hold_frames": None if self.pipeline == "gstreamer" else self.sender_content_hold_frames,
                "content_dwell_seconds": None if self.pipeline == "gstreamer" else self.sender_content_hold_frames / self.sender_fps,
                "latest_sent_frame_id": descriptor["latest_sent_frame_id"] if self.pipeline == "gstreamer" else None if live is None else int(live["frame_id"]),
                "latest_hdmi_frame_id": self.last_returned_frame_id,
                "latest_hdmi_frame_at_s": self.last_returned_frame_at_s,
            },
            "output_preview": {
                "kind": "hdmi-capture-slot",
                "configured_image": str(self.output_image) if self.output_image else None,
                "image_exists": bool(self.output_image and self.output_image.exists()),
                "capture_enabled": self.capture_enabled,
                "capture_status": self.capture_status,
                "capture_profile": self.capture_profile,
                "capture_save_samples": self.capture_save_samples,
                "capture_report": str(self.capture_last_report) if self.capture_last_report else None,
                "capture_log": str(self.capture_last_log) if self.capture_last_log else None,
                "capture_count": self.capture_count,
                "capture_started_at_s": self.capture_started_at_s,
                "capture_finished_at_s": self.capture_finished_at_s,
                "capture_last_error": self.capture_last_error,
                "semantic": "manual snapshot fallback; the right panel uses live_stream_endpoint",
                "live_stream_enabled": self.capture_enabled,
                "live_stream_endpoint": "/api/output-stream.mjpeg",
                "live_stream_status": self.live_stream_status,
                "live_stream_detail": self.live_stream_detail,
                "live_stream_clients": self.live_stream_clients,
                "stream_fps": self.stream_fps,
            },
            "control_panel": {
                "actions_enabled": self.actions_enabled,
                "action_mode": self.action_mode,
                "available_actions": [item["id"] for item in ACTION_DEFINITIONS],
                "pipeline": self.pipeline,
                "stream_state": stream_state,
                "sender_pid": sender_pid,
                "sender_last_exit_code": self.sender_last_exit_code,
                "receiver_paused": self.receiver_paused,
                "selected_effect": self.selected_effect,
                "uart_status": self.uart_port or "not-configured",
                "control_fifo": self.control_fifo,
                "gstreamer_port": self.gst_port,
                "gstreamer_sink": "fbdevsink" if self.pipeline == "gstreamer" else None,
                "gstreamer_board_log": self.gst_board_log if self.pipeline == "gstreamer" else None,
                "pip_control_host": self.pip_control_host,
                "pip_control_port": self.pip_control_port,
                "pip_control_timeout_s": self.pip_control_timeout_s,
                "pip_control_fallback_uart": self.pip_control_fallback_uart,
                "last_pip_control_transport": self.last_pip_control_transport,
                "last_pip_control_latency_ms": self.last_pip_control_latency_ms,
                "last_pip_register_status": self.last_pip_register_status,
                "last_action": self.last_action,
                "live_transport": self.action_mode == "live",
                "dry_run_only": self.action_mode == "dry-run",
            },
            "uptime_s": round(time.time() - self.started_at, 3),
            "logs": list(self.logs),
        }


def make_handler(state: DashboardState) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "ZynqDashboard/0.2"

        def log_message(self, format: str, *args: Any) -> None:  # noqa: A003
            return

        def send_payload(self, status: int, content_type: str, payload: bytes) -> None:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            try:
                self.wfile.write(payload)
            except (BrokenPipeError, ConnectionAbortedError, ConnectionResetError):
                pass

        def stream_input_mjpeg(self) -> None:
            try:
                import cv2
                import numpy as np
            except Exception as exc:
                self.send_payload(503, "text/plain; charset=utf-8", f"input stream unavailable: {exc}".encode("utf-8"))
                return

            self.send_response(200)
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()

            source_fps = state.gst_fps if state.pipeline == "gstreamer" else state.sender_fps
            delay_s = 1.0 / max(1.0, float(source_fps))
            next_emit = time.perf_counter()
            last_sha: str | None = None

            try:
                while True:
                    descriptor = state.input_preview_descriptor()
                    frame_id = int(descriptor["frame_id"])
                    if state.pipeline == "gstreamer":
                        rgb, sha = state.gstreamer_input_preview_rgb(frame_id)
                        width = state.gst_input_width
                        height = state.gst_input_height
                    else:
                        _, color = color_for_frame(
                            frame_id,
                            state.sender_content_hold_frames,
                            state.sender_start_frame_id,
                        )
                        rgb = make_color_frame(state.sender_width, state.sender_height, color, frame_id)
                        sha = frame_sha256(rgb)
                        width = state.sender_width
                        height = state.sender_height

                    remaining = next_emit - time.perf_counter()
                    if remaining > 0:
                        time.sleep(remaining)
                    next_emit = max(next_emit + delay_s, time.perf_counter())

                    if sha == last_sha:
                        continue
                    last_sha = sha

                    rgb_frame = np.frombuffer(rgb, dtype=np.uint8).reshape((height, width, 3))
                    bgr_frame = rgb_frame[:, :, ::-1]
                    ok, encoded = cv2.imencode(".jpg", bgr_frame, [int(cv2.IMWRITE_JPEG_QUALITY), 90])
                    if not ok:
                        continue
                    payload = encoded.tobytes()
                    self.wfile.write(b"--frame\r\n")
                    self.wfile.write(b"Content-Type: image/jpeg\r\n")
                    self.wfile.write(f"Content-Length: {len(payload)}\r\n".encode("ascii"))
                    self.wfile.write(f"X-Frame-ID: {frame_id}\r\n".encode("ascii"))
                    self.wfile.write(f"X-Preview-Source: {descriptor['source']}\r\n\r\n".encode("ascii"))
                    self.wfile.write(payload)
                    self.wfile.write(b"\r\n")
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionAbortedError, ConnectionResetError):
                pass

        def stream_mjpeg(self) -> None:
            try:
                import cv2
                cap, index, detail = state._open_live_capture()
            except Exception as exc:
                state._set_live_stream_status("failed", str(exc))
                self.send_payload(503, "text/plain; charset=utf-8", f"HDMI stream unavailable: {exc}".encode("utf-8"))
                return

            state._set_live_stream_status("streaming", detail, delta_clients=1)
            self.send_response(200)
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-HDMI-Capture-Device", str(index))
            self.end_headers()
            delay_s = 1.0 / max(1.0, state.stream_fps)
            frame_queue: queue.Queue[tuple[int, Any]] = queue.Queue(maxsize=256)
            stop_capture = threading.Event()

            def capture_frames() -> None:
                last_frame_id: int | None = None
                synthetic_frame_id = 0
                while not stop_capture.is_set():
                    ok, frame = cap.read()
                    if not ok or frame is None or not frame.size:
                        continue
                    try:
                        height, width = frame.shape[:2]
                        rgb_bytes = frame[:, :, ::-1].tobytes()
                        frame_id = decode_marker_from_frame(rgb_bytes, width, height)
                    except ValueError:
                        if state.pipeline != "gstreamer":
                            continue
                        synthetic_frame_id += 1
                        frame_id = synthetic_frame_id
                    if frame_id == last_frame_id:
                        continue
                    last_frame_id = frame_id
                    try:
                        frame_queue.put((frame_id, frame.copy()), timeout=0.1)
                    except queue.Full:
                        continue

            capture_thread = threading.Thread(target=capture_frames, daemon=True)
            capture_thread.start()
            latest: tuple[int, Any] | None = None
            next_emit = time.perf_counter()
            try:
                while True:
                    try:
                        latest = frame_queue.get(timeout=delay_s)
                    except queue.Empty:
                        if latest is None:
                            continue
                    assert latest is not None
                    frame_id, frame = latest
                    remaining = next_emit - time.perf_counter()
                    if remaining > 0:
                        time.sleep(remaining)
                    next_emit = max(next_emit + delay_s, time.perf_counter())
                    state._record_returned_frame_id(frame_id)
                    ok, encoded = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 85])
                    if not ok:
                        continue
                    payload = encoded.tobytes()
                    self.wfile.write(b"--frame\r\n")
                    self.wfile.write(b"Content-Type: image/jpeg\r\n")
                    self.wfile.write(f"Content-Length: {len(payload)}\r\n\r\n".encode("ascii"))
                    self.wfile.write(payload)
                    self.wfile.write(b"\r\n")
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionAbortedError, ConnectionResetError):
                pass
            finally:
                stop_capture.set()
                capture_thread.join(timeout=2)
                cap.release()
                state._set_live_stream_status("enabled", "last client disconnected", delta_clients=-1)

        def do_GET(self) -> None:  # noqa: N802
            parsed = urlparse(self.path)
            if parsed.path == "/":
                self.send_payload(200, "text/html; charset=utf-8", dashboard_html(state.actions_enabled))
                return
            if parsed.path == "/api/state":
                payload = json.dumps(state.as_json(), indent=2).encode("utf-8")
                self.send_payload(200, "application/json; charset=utf-8", payload)
                return
            if parsed.path == "/api/actions":
                payload = json.dumps({"actions": state.action_catalog()}, indent=2).encode("utf-8")
                self.send_payload(200, "application/json; charset=utf-8", payload)
                return
            if parsed.path == "/api/output-stream.mjpeg":
                self.stream_mjpeg()
                return
            if parsed.path == "/api/input-stream.mjpeg":
                self.stream_input_mjpeg()
                return
            if parsed.path == "/api/input-preview.bmp":
                descriptor = state.input_preview_descriptor()
                frame_id = int(descriptor["frame_id"])
                if state.pipeline == "gstreamer":
                    payload, sha = state.gstreamer_input_preview_bmp(frame_id)
                else:
                    payload, sha = make_input_bmp(
                        frame_id,
                        state.sender_width,
                        state.sender_height,
                        state.sender_content_hold_frames,
                        state.sender_start_frame_id,
                    )
                self.send_response(200)
                self.send_header("Content-Type", "image/bmp")
                self.send_header("Content-Length", str(len(payload)))
                self.send_header("Cache-Control", "no-store")
                self.send_header("X-Frame-SHA256", sha)
                self.send_header("X-Frame-ID", str(frame_id))
                self.send_header(
                    "X-HDMI-Frame-ID",
                    "" if descriptor["hdmi_frame_id"] is None else str(descriptor["hdmi_frame_id"]),
                )
                self.send_header("X-Preview-Source", str(descriptor["source"]))
                self.end_headers()
                try:
                    self.wfile.write(payload)
                except (BrokenPipeError, ConnectionAbortedError, ConnectionResetError):
                    pass
                return
            if parsed.path == "/api/output-preview":
                if state.output_image and state.output_image.exists():
                    content_type = mimetypes.guess_type(str(state.output_image))[0] or "application/octet-stream"
                    self.send_payload(200, content_type, state.output_image.read_bytes())
                else:
                    self.send_payload(200, "image/svg+xml", make_output_placeholder_svg())
                return
            self.send_payload(404, "text/plain; charset=utf-8", b"not found")

        def do_POST(self) -> None:  # noqa: N802
            parsed = urlparse(self.path)
            if parsed.path != "/api/action":
                self.send_payload(404, "text/plain; charset=utf-8", b"not found")
                return

            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length)
            content_type = self.headers.get("Content-Type", "")
            try:
                if "application/json" in content_type:
                    request = json.loads(body.decode("utf-8") or "{}")
                    action = str(request.get("action", ""))
                else:
                    request = parse_qs(body.decode("utf-8"))
                    action = request.get("action", [""])[0]
            except (UnicodeDecodeError, json.JSONDecodeError):
                payload = json.dumps({"ok": False, "error": "invalid action request"}).encode("utf-8")
                self.send_payload(400, "application/json; charset=utf-8", payload)
                return

            result = state.run_action(action)
            status = 200 if result["ok"] else 400
            payload = json.dumps(result, indent=2).encode("utf-8")
            self.send_payload(status, "application/json; charset=utf-8", payload)

    return Handler


def run_server(
    host: str,
    port: int,
    output_image: Path | None,
    *,
    board_host: str,
    udp_port: int,
    sender_frames: int,
    sender_fps: float,
    sender_start_frame_id: int,
    sender_warmup_frames: int,
    sender_content_hold_frames: int,
    sender_width: int,
    sender_height: int,
    sender_payload: int,
    sender_inter_packet_us: float,
    pipeline: str,
    gst_conda_env: Path,
    gst_port: int,
    gst_input_width: int,
    gst_input_height: int,
    gst_output_width: int,
    gst_output_height: int,
    gst_fps: int,
    gst_num_buffers: int,
    gst_payload_type: int,
    gst_mtu: int,
    gst_board_log: str,
    gst_board_pid: str,
    uart_port: str,
    uart_baud: int,
    uart_login_root: bool,
    uart_password: str,
    control_fifo: str,
    pip_control_host: str | None,
    pip_control_port: int,
    pip_control_timeout_s: float,
    pip_control_fallback_uart: bool,
    capture_enabled: bool,
    capture_device: str,
    capture_backend: str,
    capture_width: int,
    capture_height: int,
    capture_frames: int,
    capture_profile: str,
    capture_save_samples: int,
    stream_fps: float,
    auto_capture_on_start: bool,
    actions_enabled: bool,
    action_mode: str,
    log_dir: Path,
) -> None:
    state = DashboardState(
        output_image=output_image,
        board_host=board_host,
        udp_port=udp_port,
        sender_frames=sender_frames,
        sender_fps=sender_fps,
        sender_start_frame_id=sender_start_frame_id,
        sender_warmup_frames=sender_warmup_frames,
        sender_content_hold_frames=sender_content_hold_frames,
        sender_width=sender_width,
        sender_height=sender_height,
        sender_payload=sender_payload,
        sender_inter_packet_us=sender_inter_packet_us,
        pipeline=pipeline,
        gst_conda_env=gst_conda_env,
        gst_port=gst_port,
        gst_input_width=gst_input_width,
        gst_input_height=gst_input_height,
        gst_output_width=gst_output_width,
        gst_output_height=gst_output_height,
        gst_fps=gst_fps,
        gst_num_buffers=gst_num_buffers,
        gst_payload_type=gst_payload_type,
        gst_mtu=gst_mtu,
        gst_board_log=gst_board_log,
        gst_board_pid=gst_board_pid,
        uart_port=uart_port,
        uart_baud=uart_baud,
        uart_login_root=uart_login_root,
        uart_password=uart_password,
        control_fifo=control_fifo,
        pip_control_host=pip_control_host,
        pip_control_port=pip_control_port,
        pip_control_timeout_s=pip_control_timeout_s,
        pip_control_fallback_uart=pip_control_fallback_uart,
        capture_enabled=capture_enabled,
        capture_device=capture_device,
        capture_backend=capture_backend,
        capture_width=capture_width,
        capture_height=capture_height,
        capture_frames=capture_frames,
        capture_profile=capture_profile,
        capture_save_samples=capture_save_samples,
        stream_fps=stream_fps,
        auto_capture_on_start=auto_capture_on_start,
        actions_enabled=actions_enabled,
        action_mode=action_mode,
        log_dir=log_dir,
    )
    server = ThreadingHTTPServer((host, port), make_handler(state))
    print(f"DASHBOARD_READY http://{host}:{server.server_port}", flush=True)
    server.serve_forever()


def post_json(url: str, payload: dict[str, str]) -> tuple[int, dict[str, Any]]:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode("utf-8"))


def wait_for_udp_packet(sock: socket.socket, timeout_s: float) -> bytes:
    sock.settimeout(timeout_s)
    packet, _ = sock.recvfrom(2048)
    return packet


def run_self_test(out_dir: Path) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    receiver = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    receiver.bind(("127.0.0.1", 0))
    udp_port = int(receiver.getsockname()[1])

    state = DashboardState(
        board_host="127.0.0.1",
        udp_port=udp_port,
        sender_frames=0,
        sender_fps=10.0,
        sender_start_frame_id=100,
        sender_warmup_frames=0,
        sender_content_hold_frames=50,
        sender_width=800,
        sender_height=600,
        sender_payload=480,
        sender_inter_packet_us=0.0,
        pipeline="legacy-udp",
        uart_port="",
        capture_enabled=False,
        action_mode="live",
        log_dir=out_dir / "runtime",
    )
    server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(state))
    url = f"http://127.0.0.1:{server.server_port}"
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    action_results: list[dict[str, Any]] = []
    try:
        html_bytes = urllib.request.urlopen(url + "/", timeout=5).read()
        state_bytes = urllib.request.urlopen(url + "/api/state", timeout=5).read()
        actions_bytes = urllib.request.urlopen(url + "/api/actions", timeout=5).read()
        input_response = urllib.request.urlopen(url + "/api/input-preview.bmp", timeout=5)
        input_bytes = input_response.read()
        input_sha = input_response.headers.get("X-Frame-SHA256")
        input_stream_response = urllib.request.urlopen(url + "/api/input-stream.mjpeg", timeout=5)
        input_stream_head = input_stream_response.read(2048)
        input_stream_response.close()
        output_bytes = urllib.request.urlopen(url + "/api/output-preview", timeout=5).read()

        start_status, start_result = post_json(url + "/api/action", {"action": "start-stream"})
        action_results.append(start_result)
        first_packet = wait_for_udp_packet(receiver, 5)
        if first_packet[:4] != b"ZVID":
            raise AssertionError("sender packet magic mismatch")
        width = struct.unpack_from("<H", first_packet, 8)[0]
        height = struct.unpack_from("<H", first_packet, 10)[0]
        if (width, height) != (800, 600):
            raise AssertionError("sender packet dimensions mismatch")

        stop_status, stop_result = post_json(url + "/api/action", {"action": "stop-stream"})
        action_results.append(stop_result)
        capture_status, capture_result = post_json(url + "/api/action", {"action": "capture-output"})
        action_results.append(capture_result)
        uart_status, uart_result = post_json(url + "/api/action", {"action": "pause-receiver"})
        action_results.append(uart_result)
        effect_status, effect_result = post_json(url + "/api/action", {"action": "effect-invert"})
        action_results.append(effect_result)
        final_state_bytes = urllib.request.urlopen(url + "/api/state", timeout=5).read()

        out_dir.joinpath("index.html").write_bytes(html_bytes)
        out_dir.joinpath("state.json").write_bytes(state_bytes)
        out_dir.joinpath("actions.json").write_bytes(actions_bytes)
        out_dir.joinpath("action-results.json").write_text(json.dumps(action_results, indent=2), encoding="utf-8")
        out_dir.joinpath("final-state.json").write_bytes(final_state_bytes)
        out_dir.joinpath("input-preview.bmp").write_bytes(input_bytes)
        out_dir.joinpath("input-stream-head.bin").write_bytes(input_stream_head)
        out_dir.joinpath("output-placeholder.svg").write_bytes(output_bytes)

        page = html_bytes.decode("utf-8")
        data = json.loads(state_bytes.decode("utf-8"))
        actions = json.loads(actions_bytes.decode("utf-8"))
        final_state = json.loads(final_state_bytes.decode("utf-8"))
        action_ids = {item["id"] for item in actions["actions"]}

        assert start_status == 200
        assert stop_status == 200
        assert capture_status == 400
        assert uart_status == 400
        assert effect_status == 200
        assert "gradient" not in page
        assert "box-shadow" not in page
        assert "Zynq 视频控制台" in page
        assert "输入到 FPGA" in page
        assert "FPGA 输出" in page
        assert "启动视频流" in page
        assert NO_CAMERA_POLICY in page
        assert 'data-panel="input"' in page
        assert 'data-panel="output"' in page
        assert 'data-panel="control"' in page
        assert 'data-action="start-stream"' in page
        assert 'data-action="pause-receiver"' in page
        assert 'data-action="pip-top-left"' in page
        assert 'data-action="pip-grayscale"' in page
        assert 'src="/api/input-stream.mjpeg"' in page
        assert "disabled>启动视频流" not in page
        assert data["input_source"]["camera_enabled"] is False
        assert data["input_source"]["custom_file_enabled"] is False
        assert data["input_source"]["live_stream_endpoint"] == "/api/input-stream.mjpeg"
        assert data["output_preview"]["live_stream_endpoint"] == "/api/output-stream.mjpeg"
        assert data["output_preview"]["semantic"].startswith("manual snapshot fallback")
        assert data["control_panel"]["actions_enabled"] is True
        assert data["control_panel"]["action_mode"] == "live"
        assert "start-stream" in action_ids
        assert "capture-output" in action_ids
        assert "pause-receiver" in action_ids
        assert "resume-receiver" in action_ids
        assert "effect-invert" in action_ids
        assert "pip-top-left" in action_ids
        assert "pip-bottom-right" in action_ids
        assert "pip-large" in action_ids
        assert "pip-small" in action_ids
        assert "pip-invert" in action_ids
        assert "pip-grayscale" in action_ids
        assert "pip-bypass" in action_ids
        assert start_result["ok"] is True
        assert stop_result["ok"] is True
        assert capture_result["ok"] is False
        assert capture_result["error"] == "HDMI_CAPTURE_DISABLED"
        assert uart_result["ok"] is False
        assert uart_result["error"] == "UART_NOT_CONFIGURED"
        assert effect_result["ok"] is True
        assert final_state["control_panel"]["stream_state"] == "stopped"
        assert final_state["control_panel"]["selected_effect"] == "invert"
        assert any("ACTION_OK action=start-stream" in line for line in final_state["logs"])
        assert any("ACTION_OK action=stop-stream" in line for line in final_state["logs"])
        assert any("ACTION_ERROR action=pause-receiver UART_NOT_CONFIGURED" in line for line in final_state["logs"])
        expected_input = make_color_frame(800, 600, color_for_frame(100, 50, 100)[1], 100)
        assert input_bytes[:2] == b"BM"
        assert input_sha == frame_sha256(expected_input)
        assert b"--frame" in input_stream_head
        assert b"Content-Type: image/jpeg" in input_stream_head
        assert data["input_source"]["sender_kind"] == "unified"
        assert data["input_source"]["sender_fps"] == 10.0
        assert data["input_source"]["content_dwell_seconds"] == 5.0
        assert "FPGA 输出".encode("utf-8") in output_bytes

        gst_state = DashboardState(
            board_host="192.168.1.10",
            udp_port=udp_port,
            pipeline="gstreamer",
            uart_port="",
            capture_enabled=False,
            action_mode="dry-run",
            log_dir=out_dir / "gstreamer-runtime",
        )
        gst_data = gst_state.as_json()
        gst_cmd = " ".join(gst_state._gstreamer_sender_command_locked())
        board_cmd = gst_state._gstreamer_board_receiver_command()
        gst_preview, gst_sha = make_gstreamer_source_bmp(3)
        assert gst_data["pipeline"]["mode"] == "gstreamer"
        assert gst_data["pipeline"]["transport"] == "rtp/jpeg"
        assert gst_data["pipeline"]["sink"] == "fbdevsink"
        assert gst_data["input_source"]["sender_kind"] == "gstreamer"
        assert "gst-launch-1.0" in gst_cmd
        assert "num-buffers=-1" in gst_cmd
        assert "jpegenc" in gst_cmd
        assert "rtpjpegpay" in gst_cmd
        assert "udpsink" in gst_cmd
        assert "multifilesink" in gst_cmd
        assert "rtpjpegdepay" in board_cmd
        assert "jpegdec" in board_cmd
        assert "fbdevsink device=/dev/fb0" in board_cmd
        assert gst_preview[:2] == b"BM"
        assert gst_sha
        out_dir.joinpath("gstreamer-state.json").write_text(json.dumps(gst_data, indent=2), encoding="utf-8")
        out_dir.joinpath("gstreamer-pc-sender-command.txt").write_text(gst_cmd + "\n", encoding="utf-8")
        out_dir.joinpath("gstreamer-board-receiver-command.txt").write_text(board_cmd + "\n", encoding="utf-8")
        out_dir.joinpath("gstreamer-input-preview.bmp").write_bytes(gst_preview)
    finally:
        try:
            state.run_action("stop-stream")
        except Exception:
            pass
        receiver.close()
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    print(f"DASHBOARD_SCAFFOLD_SELF_TEST_OK out={out_dir}")
    print(f"DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK out={out_dir} actions={len(action_results)}")
    print(f"DASHBOARD_MINIMAL_UI_SELF_TEST_OK out={out_dir}")
    print(f"DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK out={out_dir} actions={len(action_results)}")
    print(f"DASHBOARD_GSTREAMER_CONTROL_SELF_TEST_OK out={out_dir}")
    print(f"DASHBOARD_CHINESE_UI_SELF_TEST_OK out={out_dir}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--board-host", default=DEFAULT_BOARD_HOST)
    parser.add_argument("--udp-port", type=int, default=DEFAULT_UDP_PORT)
    parser.add_argument("--sender-frames", type=int, default=DEFAULT_SENDER_FRAMES)
    parser.add_argument("--sender-fps", type=float, default=DEFAULT_SENDER_FPS)
    parser.add_argument("--sender-start-frame-id", type=int, default=DEFAULT_SENDER_START_FRAME_ID)
    parser.add_argument("--sender-warmup-frames", type=int, default=0)
    parser.add_argument("--sender-content-hold-frames", type=int, default=DEFAULT_CONTENT_HOLD_FRAMES)
    parser.add_argument("--sender-width", type=int, default=DEFAULT_WIDTH)
    parser.add_argument("--sender-height", type=int, default=DEFAULT_HEIGHT)
    parser.add_argument("--sender-payload", type=int, default=DEFAULT_SENDER_PAYLOAD)
    parser.add_argument("--sender-inter-packet-us", type=float, default=DEFAULT_SENDER_INTER_PACKET_US)
    parser.add_argument("--pipeline", choices=["gstreamer", "legacy-udp"], default=DEFAULT_PIPELINE)
    parser.add_argument("--gst-conda-env", default=DEFAULT_GST_CONDA_ENV)
    parser.add_argument("--gst-port", type=int, default=DEFAULT_GST_PORT)
    parser.add_argument("--gst-input-width", type=int, default=DEFAULT_GST_INPUT_WIDTH)
    parser.add_argument("--gst-input-height", type=int, default=DEFAULT_GST_INPUT_HEIGHT)
    parser.add_argument("--gst-output-width", type=int, default=DEFAULT_GST_OUTPUT_WIDTH)
    parser.add_argument("--gst-output-height", type=int, default=DEFAULT_GST_OUTPUT_HEIGHT)
    parser.add_argument("--gst-fps", type=int, default=DEFAULT_GST_FPS)
    parser.add_argument("--gst-num-buffers", type=int, default=DEFAULT_GST_NUM_BUFFERS)
    parser.add_argument("--gst-payload-type", type=int, default=DEFAULT_GST_PAYLOAD_TYPE)
    parser.add_argument("--gst-mtu", type=int, default=DEFAULT_GST_MTU)
    parser.add_argument("--gst-board-log", default=DEFAULT_GST_BOARD_LOG)
    parser.add_argument("--gst-board-pid", default=DEFAULT_GST_BOARD_PID)
    parser.add_argument("--uart-port", default=DEFAULT_UART_PORT)
    parser.add_argument("--uart-disabled", action="store_true")
    parser.add_argument("--uart-baud", type=int, default=DEFAULT_UART_BAUD)
    parser.add_argument("--uart-login-root", action="store_true")
    parser.add_argument("--uart-password", default="")
    parser.add_argument("--control-fifo", default=DEFAULT_CONTROL_FIFO)
    parser.add_argument("--pip-control-host", default="")
    parser.add_argument("--pip-control-port", type=int, default=DEFAULT_PIP_CONTROL_PORT)
    parser.add_argument("--pip-control-timeout-s", type=float, default=DEFAULT_PIP_CONTROL_TIMEOUT_S)
    parser.add_argument("--pip-control-no-fallback", action="store_true")
    parser.add_argument("--capture-disabled", action="store_true")
    parser.add_argument("--capture-device", default=DEFAULT_CAPTURE_DEVICE)
    parser.add_argument("--capture-backend", default=DEFAULT_CAPTURE_BACKEND)
    parser.add_argument("--capture-width", type=int, default=DEFAULT_CAPTURE_WIDTH)
    parser.add_argument("--capture-height", type=int, default=DEFAULT_CAPTURE_HEIGHT)
    parser.add_argument("--capture-frames", type=int, default=DEFAULT_CAPTURE_FRAMES)
    parser.add_argument("--capture-profile", default=DEFAULT_CAPTURE_PROFILE, choices=["none", "non-black", "pip", "rgb-stripes", "inverted-rgb-stripes"])
    parser.add_argument("--capture-save-samples", type=int, default=DEFAULT_CAPTURE_SAVE_SAMPLES)
    parser.add_argument("--stream-fps", type=float, default=DEFAULT_STREAM_FPS)
    parser.add_argument("--auto-capture-on-start", action="store_true")
    parser.add_argument("--action-mode", choices=["live", "dry-run"], default="live")
    parser.add_argument("--actions-disabled", action="store_true")
    parser.add_argument("--output-image", default="")
    parser.add_argument("--log-dir", default="build/dashboard-live")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--out-dir", default="build/dashboard-live-minimal-controls")
    args = parser.parse_args()

    output_image = Path(args.output_image) if args.output_image else None
    if args.self_test:
        return run_self_test(Path(args.out_dir))
    run_server(
        args.host,
        args.port,
        output_image,
        board_host=args.board_host,
        udp_port=args.udp_port,
        sender_frames=args.sender_frames,
        sender_fps=args.sender_fps,
        sender_start_frame_id=args.sender_start_frame_id,
        sender_warmup_frames=args.sender_warmup_frames,
        sender_content_hold_frames=args.sender_content_hold_frames,
        sender_width=args.sender_width,
        sender_height=args.sender_height,
        sender_payload=args.sender_payload,
        sender_inter_packet_us=args.sender_inter_packet_us,
        pipeline=args.pipeline,
        gst_conda_env=Path(args.gst_conda_env),
        gst_port=args.gst_port,
        gst_input_width=args.gst_input_width,
        gst_input_height=args.gst_input_height,
        gst_output_width=args.gst_output_width,
        gst_output_height=args.gst_output_height,
        gst_fps=args.gst_fps,
        gst_num_buffers=args.gst_num_buffers,
        gst_payload_type=args.gst_payload_type,
        gst_mtu=args.gst_mtu,
        gst_board_log=args.gst_board_log,
        gst_board_pid=args.gst_board_pid,
        uart_port="" if args.uart_disabled else args.uart_port,
        uart_baud=args.uart_baud,
        uart_login_root=args.uart_login_root,
        uart_password=args.uart_password,
        control_fifo=args.control_fifo,
        pip_control_host=args.pip_control_host or None,
        pip_control_port=args.pip_control_port,
        pip_control_timeout_s=args.pip_control_timeout_s,
        pip_control_fallback_uart=not args.pip_control_no_fallback,
        capture_enabled=not args.capture_disabled,
        capture_device=args.capture_device,
        capture_backend=args.capture_backend,
        capture_width=args.capture_width,
        capture_height=args.capture_height,
        capture_frames=args.capture_frames,
        capture_profile=args.capture_profile,
        capture_save_samples=args.capture_save_samples,
        stream_fps=args.stream_fps,
        auto_capture_on_start=args.auto_capture_on_start,
        actions_enabled=not args.actions_disabled,
        action_mode=args.action_mode,
        log_dir=Path(args.log_dir),
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
