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

try:
    from dashboard.demo_source import frame_sha256, make_demo_frame
except ModuleNotFoundError:
    from demo_source import frame_sha256, make_demo_frame


DEFAULT_WIDTH = 800
DEFAULT_HEIGHT = 600
DEFAULT_BOARD_HOST = "192.168.1.10"
DEFAULT_UDP_PORT = 5005
DEFAULT_SENDER_FRAMES = 0
DEFAULT_SENDER_FPS = 1.0
DEFAULT_SENDER_PAYLOAD = 1200
DEFAULT_SENDER_INTER_PACKET_US = 200.0
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
NO_CAMERA_POLICY = "Generated PC input only. Camera/webcam and custom file input are disabled for MVP."


ACTION_DEFINITIONS = [
    {
        "id": "start-stream",
        "label": "Start stream",
        "kind": "sender-process",
        "semantics": "start dashboard-owned fixed demo UDP sender; right panel reads HDMI return MJPEG",
    },
    {
        "id": "stop-stream",
        "label": "Stop stream",
        "kind": "sender-process",
        "semantics": "stop dashboard-owned fixed demo UDP sender",
    },
    {
        "id": "capture-output",
        "label": "Capture output",
        "kind": "hdmi-capture",
        "semantics": "manual still capture fallback for FPGA HDMI output",
    },
    {
        "id": "pause-receiver",
        "label": "Pause receiver",
        "kind": "uart-fifo-control",
        "semantics": "send: echo pause > /tmp/video_ctl",
    },
    {
        "id": "resume-receiver",
        "label": "Resume receiver",
        "kind": "uart-fifo-control",
        "semantics": "send: echo resume > /tmp/video_ctl",
    },
    {
        "id": "receiver-status",
        "label": "Receiver status",
        "kind": "uart-fifo-control",
        "semantics": "send: echo status > /tmp/video_ctl; tail receiver log",
    },
    {
        "id": "effect-none",
        "label": "Effect none",
        "kind": "receiver-effect",
        "semantics": "select receiver launch effect argument --effect none",
    },
    {
        "id": "effect-invert",
        "label": "Effect invert",
        "kind": "receiver-effect",
        "semantics": "select receiver launch effect argument --effect invert",
    },
]


def rgb888_to_bmp(frame: bytes, width: int, height: int) -> bytes:
    """Encode RGB888 frame bytes as a browser-readable 24-bit BMP."""
    expected = width * height * 3
    if len(frame) != expected:
        raise ValueError(f"RGB888 frame has {len(frame)} bytes, expected {expected}")

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


def make_input_bmp(frame: int, width: int = DEFAULT_WIDTH, height: int = DEFAULT_HEIGHT) -> tuple[bytes, str]:
    """Return the exact deterministic source frame used by the UDP sender."""
    rgb = make_demo_frame(width, height, frame)
    return rgb888_to_bmp(rgb, width, height), frame_sha256(rgb)


def make_output_placeholder_svg(width: int = DEFAULT_WIDTH, height: int = DEFAULT_HEIGHT) -> bytes:
    """Return a plain output placeholder."""
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  <rect width="100%" height="100%" fill="#fff"/>
  <rect x="1" y="1" width="{width - 2}" height="{height - 2}" fill="none" stroke="#000" stroke-width="2"/>
  <text x="16" y="32" fill="#000" font-family="Consolas, monospace" font-size="20">FPGA OUTPUT</text>
  <text x="16" y="64" fill="#000" font-family="Consolas, monospace" font-size="16">No HDMI capture image configured.</text>
  <text x="16" y="92" fill="#000" font-family="Consolas, monospace" font-size="16">This panel is output verification only.</text>
</svg>
"""
    return svg.encode("utf-8")


def dashboard_html(actions_enabled: bool = True) -> bytes:
    policy = html.escape(NO_CAMERA_POLICY)
    disabled_attr = "" if actions_enabled else " disabled"
    page = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Zynq video control</title>
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
    <h1>Zynq video control</h1>
    <div data-testid="no-camera-policy">{policy}</div>
  </header>
  <main>
    <section data-panel="input">
      <h2>Input to FPGA</h2>
      <img class="preview" id="input-preview" src="/api/input-preview.bmp?frame=0" alt="actual generated PC UDP frame preview">
      <div class="meta">source: exact generated PC RGB888 UDP frame
camera: disabled
custom file: deferred</div>
    </section>
    <section data-panel="output">
      <h2>FPGA output</h2>
      <img class="preview" id="output-preview" src="/api/output-stream.mjpeg" alt="live FPGA HDMI return preview">
      <div class="meta">source: live HDMI return stream via capture adapter
role: no-effect pass-through preview
note: Windows may label the HDMI/UVC adapter as a camera device</div>
    </section>
    <section data-panel="control">
      <h2>Control</h2>
      <div class="controls">
        <button{disabled_attr} data-action="start-stream" onclick="postAction('start-stream')">start stream</button>
        <button{disabled_attr} data-action="stop-stream" onclick="postAction('stop-stream')">stop stream</button>
        <button{disabled_attr} data-action="capture-output" onclick="postAction('capture-output')">capture output</button>
        <button{disabled_attr} data-action="pause-receiver" onclick="postAction('pause-receiver')">pause receiver</button>
        <button{disabled_attr} data-action="resume-receiver" onclick="postAction('resume-receiver')">resume receiver</button>
        <button{disabled_attr} data-action="receiver-status" onclick="postAction('receiver-status')">receiver status</button>
        <button{disabled_attr} data-action="effect-none" onclick="postAction('effect-none')">effect none</button>
        <button{disabled_attr} data-action="effect-invert" onclick="postAction('effect-invert')">effect invert</button>
      </div>
      <div class="statusline" id="action-status">loading...</div>
      <pre class="log" id="log">loading...</pre>
    </section>
  </main>
  <script>
    let frame = 0;
    function applyState(state) {{
      document.getElementById("log").textContent = state.logs.join("\\n");
      document.getElementById("action-status").textContent =
        "mode=" + state.control_panel.action_mode +
        " stream=" + state.control_panel.stream_state +
        " sender_pid=" + (state.control_panel.sender_pid || "none") +
        " hdmi=" + state.output_preview.capture_status +
        " uart=" + state.control_panel.uart_status +
        " effect=" + state.control_panel.selected_effect;
    }}
    async function refreshState() {{
      frame = (frame + 1) % 100000;
      document.getElementById("input-preview").src = "/api/input-preview.bmp?frame=" + frame;
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
        document.getElementById("log").textContent += "\\nACTION_ERROR action=" + action + " error=" + result.error;
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
        sender_width: int = DEFAULT_WIDTH,
        sender_height: int = DEFAULT_HEIGHT,
        sender_payload: int = DEFAULT_SENDER_PAYLOAD,
        sender_inter_packet_us: float = DEFAULT_SENDER_INTER_PACKET_US,
        uart_port: str = DEFAULT_UART_PORT,
        uart_baud: int = DEFAULT_UART_BAUD,
        control_fifo: str = DEFAULT_CONTROL_FIFO,
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
        self.sender_width = sender_width
        self.sender_height = sender_height
        self.sender_payload = sender_payload
        self.sender_inter_packet_us = sender_inter_packet_us
        self.uart_port = uart_port
        self.uart_baud = uart_baud
        self.control_fifo = control_fifo
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
        self.receiver_paused = False
        self.selected_effect = "none"
        self.last_action: dict[str, Any] | None = None
        self.logs = [
            "dashboard ready",
            "ui: minimal",
            f"sender target: {board_host}:{udp_port}",
            f"sender frames: {'continuous' if sender_frames == 0 else sender_frames}",
            f"hdmi capture: {'enabled' if capture_enabled else 'disabled'}",
            "hdmi return: live MJPEG preview; Windows may report the HDMI capture adapter as camera access",
            f"uart: {uart_port or 'not configured'}",
            "camera/webcam input: disabled",
            "custom file input: deferred",
        ]

    def action_catalog(self) -> list[dict[str, str]]:
        return [dict(item) for item in ACTION_DEFINITIONS]

    def _append_log_locked(self, line: str) -> None:
        self.logs.append(line)
        del self.logs[:-120]

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
        return [
            sys.executable,
            str(self.repo_root / "tools" / "send_demo_video_udp.py"),
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
            "--payload",
            str(self.sender_payload),
            "--inter-packet-us",
            f"{self.sender_inter_packet_us:g}",
        ]

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
                suffix = capture_detail if capture_ok else f"capture warning: {capture_detail}"
            else:
                suffix = "HDMI_RETURN_STREAM_READY endpoint=/api/output-stream.mjpeg"
            return True, f"sender already running pid={pid}; {suffix}"

        stdout_path, stderr_path = self._sender_log_paths()
        cmd = self._sender_command_locked()
        with stdout_path.open("ab") as stdout_file, stderr_path.open("ab") as stderr_file:
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
            suffix = capture_detail if capture_ok else f"capture warning: {capture_detail}"
        else:
            suffix = "HDMI_RETURN_STREAM_READY endpoint=/api/output-stream.mjpeg"
        return True, f"sender started pid={self.sender_process.pid} log={stdout_path}; {suffix}"

    def _stop_sender_locked(self) -> tuple[bool, str]:
        if not self._sender_alive_locked():
            return True, "sender not running"
        assert self.sender_process is not None
        pid = self.sender_process.pid
        self.sender_process.terminate()
        try:
            code = self.sender_process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.sender_process.kill()
            code = self.sender_process.wait(timeout=3)
        self.sender_last_exit_code = code
        return True, f"sender stopped pid={pid} exit_code={code}"

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
        if not self.uart_port:
            return False, "UART_NOT_CONFIGURED"

        self.log_dir.mkdir(parents=True, exist_ok=True)
        stamp = int(time.time() * 1000)
        rel_output = self.log_dir / f"uart-{action}-{stamp}.log"
        rel_commands = self.log_dir / f"uart-{action}-{stamp}.commands"
        command_path = self.repo_root / rel_commands
        command_path.parent.mkdir(parents=True, exist_ok=True)
        command_path.write_text("\n".join(self._uart_commands_for_action(action)) + "\n", encoding="ascii")
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
        try:
            result = subprocess.run(
                cmd,
                cwd=str(self.repo_root),
                capture_output=True,
                text=True,
                timeout=8,
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
                if any(token in stripped for token in ("CONTROL_", "VIDEO_UDP_", "FB_INFO", "UART_RUN_COMMANDS_OK")):
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
                ok, detail = self._run_uart_action_locked(action)
                if ok and action == "pause-receiver":
                    self.receiver_paused = True
                elif ok and action == "resume-receiver":
                    self.receiver_paused = False
            elif action == "effect-none":
                self.selected_effect = "none"
                detail = "selected effect=none; applies on next receiver launch"
            elif action == "effect-invert":
                self.selected_effect = "invert"
                detail = "selected effect=invert; applies on next receiver launch"

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
        return "dry-run"

    def as_json(self) -> dict[str, Any]:
        with self.lock:
            return self._as_json_locked()

    def _as_json_locked(self) -> dict[str, Any]:
        sender_pid = self._sender_pid_locked()
        stream_state = "running" if sender_pid is not None else "stopped"
        return {
            "status": "action-ready" if self.actions_enabled else "disabled",
            "panels": ["input-preview", "fpga-output-preview", "function-control-panel"],
            "input_source": {
                "kind": "generated",
                "camera_enabled": False,
                "custom_file_enabled": False,
                "policy": NO_CAMERA_POLICY,
                "preview_endpoint": "/api/input-preview.bmp",
                "preview_matches_sender_source": True,
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
                "stream_state": stream_state,
                "sender_pid": sender_pid,
                "sender_last_exit_code": self.sender_last_exit_code,
                "receiver_paused": self.receiver_paused,
                "selected_effect": self.selected_effect,
                "uart_status": self.uart_port or "not-configured",
                "control_fifo": self.control_fifo,
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
            self.wfile.write(payload)

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
            try:
                while True:
                    ok, frame = cap.read()
                    if not ok or frame is None or not frame.size:
                        time.sleep(delay_s)
                        continue
                    ok, encoded = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 85])
                    if not ok:
                        time.sleep(delay_s)
                        continue
                    payload = encoded.tobytes()
                    self.wfile.write(b"--frame\r\n")
                    self.wfile.write(b"Content-Type: image/jpeg\r\n")
                    self.wfile.write(f"Content-Length: {len(payload)}\r\n\r\n".encode("ascii"))
                    self.wfile.write(payload)
                    self.wfile.write(b"\r\n")
                    self.wfile.flush()
                    time.sleep(delay_s)
            except (BrokenPipeError, ConnectionAbortedError, ConnectionResetError):
                pass
            finally:
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
            if parsed.path == "/api/input-preview.bmp":
                frame_text = parse_qs(parsed.query).get("frame", ["0"])[0]
                try:
                    frame = int(frame_text)
                except ValueError:
                    frame = 0
                payload, sha = make_input_bmp(frame, state.sender_width, state.sender_height)
                self.send_response(200)
                self.send_header("Content-Type", "image/bmp")
                self.send_header("Content-Length", str(len(payload)))
                self.send_header("Cache-Control", "no-store")
                self.send_header("X-Frame-SHA256", sha)
                self.end_headers()
                self.wfile.write(payload)
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
    sender_width: int,
    sender_height: int,
    sender_payload: int,
    sender_inter_packet_us: float,
    uart_port: str,
    uart_baud: int,
    control_fifo: str,
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
        sender_width=sender_width,
        sender_height=sender_height,
        sender_payload=sender_payload,
        sender_inter_packet_us=sender_inter_packet_us,
        uart_port=uart_port,
        uart_baud=uart_baud,
        control_fifo=control_fifo,
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
        sender_fps=30.0,
        sender_width=80,
        sender_height=60,
        sender_payload=480,
        sender_inter_packet_us=0.0,
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
        input_response = urllib.request.urlopen(url + "/api/input-preview.bmp?frame=7", timeout=5)
        input_bytes = input_response.read()
        input_sha = input_response.headers.get("X-Frame-SHA256")
        output_bytes = urllib.request.urlopen(url + "/api/output-preview", timeout=5).read()

        start_status, start_result = post_json(url + "/api/action", {"action": "start-stream"})
        action_results.append(start_result)
        first_packet = wait_for_udp_packet(receiver, 5)
        if first_packet[:4] != b"ZVID":
            raise AssertionError("sender packet magic mismatch")
        width = struct.unpack_from("<H", first_packet, 8)[0]
        height = struct.unpack_from("<H", first_packet, 10)[0]
        if (width, height) != (80, 60):
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
        assert 'data-panel="input"' in page
        assert 'data-panel="output"' in page
        assert 'data-panel="control"' in page
        assert 'data-action="start-stream"' in page
        assert 'data-action="pause-receiver"' in page
        assert "disabled>start stream" not in page
        assert data["input_source"]["camera_enabled"] is False
        assert data["input_source"]["custom_file_enabled"] is False
        assert data["output_preview"]["live_stream_endpoint"] == "/api/output-stream.mjpeg"
        assert data["output_preview"]["semantic"].startswith("manual snapshot fallback")
        assert data["control_panel"]["actions_enabled"] is True
        assert data["control_panel"]["action_mode"] == "live"
        assert "start-stream" in action_ids
        assert "capture-output" in action_ids
        assert "pause-receiver" in action_ids
        assert "resume-receiver" in action_ids
        assert "effect-invert" in action_ids
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
        expected_input = make_demo_frame(80, 60, 7)
        assert input_bytes[:2] == b"BM"
        assert input_sha == frame_sha256(expected_input)
        assert b"FPGA OUTPUT" in output_bytes
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
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--board-host", default=DEFAULT_BOARD_HOST)
    parser.add_argument("--udp-port", type=int, default=DEFAULT_UDP_PORT)
    parser.add_argument("--sender-frames", type=int, default=DEFAULT_SENDER_FRAMES)
    parser.add_argument("--sender-fps", type=float, default=DEFAULT_SENDER_FPS)
    parser.add_argument("--sender-width", type=int, default=DEFAULT_WIDTH)
    parser.add_argument("--sender-height", type=int, default=DEFAULT_HEIGHT)
    parser.add_argument("--sender-payload", type=int, default=DEFAULT_SENDER_PAYLOAD)
    parser.add_argument("--sender-inter-packet-us", type=float, default=DEFAULT_SENDER_INTER_PACKET_US)
    parser.add_argument("--uart-port", default=DEFAULT_UART_PORT)
    parser.add_argument("--uart-disabled", action="store_true")
    parser.add_argument("--uart-baud", type=int, default=DEFAULT_UART_BAUD)
    parser.add_argument("--control-fifo", default=DEFAULT_CONTROL_FIFO)
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
        sender_width=args.sender_width,
        sender_height=args.sender_height,
        sender_payload=args.sender_payload,
        sender_inter_packet_us=args.sender_inter_packet_us,
        uart_port="" if args.uart_disabled else args.uart_port,
        uart_baud=args.uart_baud,
        control_fifo=args.control_fifo,
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
