#!/usr/bin/env python3
"""PC-side dashboard scaffold for the Zynq video pipeline.

The MVP dashboard deliberately avoids camera/webcam input and custom input
files. Input preview frames are generated deterministically on the PC.
"""

from __future__ import annotations

import argparse
import html
import json
import mimetypes
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse


DEFAULT_WIDTH = 800
DEFAULT_HEIGHT = 600
NO_CAMERA_POLICY = "MVP input source is generated on the PC; camera/webcam and custom file input are disabled."


def make_input_svg(frame: int, width: int = DEFAULT_WIDTH, height: int = DEFAULT_HEIGHT) -> bytes:
    phase = frame % 120
    pip_x = 80 + (phase * 5) % 520
    pip_y = 90 + (phase * 3) % 340
    hue = (frame * 17) % 360
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  <defs>
    <linearGradient id="bg" x1="0" x2="1" y1="0" y2="1">
      <stop offset="0" stop-color="#10231f"/>
      <stop offset="0.54" stop-color="#1f4c43"/>
      <stop offset="1" stop-color="#d9a441"/>
    </linearGradient>
    <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
      <path d="M40 0H0V40" fill="none" stroke="rgba(255,255,255,0.13)" stroke-width="1"/>
    </pattern>
  </defs>
  <rect width="100%" height="100%" fill="url(#bg)"/>
  <rect width="100%" height="100%" fill="url(#grid)"/>
  <circle cx="{(phase * 9) % width}" cy="96" r="72" fill="hsl({hue},80%,58%)" opacity="0.42"/>
  <rect x="{pip_x}" y="{pip_y}" width="170" height="120" rx="18" fill="#f3efe0" opacity="0.95"/>
  <rect x="{pip_x + 16}" y="{pip_y + 18}" width="138" height="84" rx="10" fill="#15332f"/>
  <path d="M{pip_x + 28} {pip_y + 86} L{pip_x + 76} {pip_y + 42} L{pip_x + 118} {pip_y + 82}" fill="none" stroke="#f0bd42" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>
  <text x="38" y="58" fill="#fff8dc" font-family="Bahnschrift, 'Trebuchet MS', sans-serif" font-size="28" font-weight="700">GENERATED INPUT</text>
  <text x="38" y="94" fill="#d8eadf" font-family="Bahnschrift, 'Trebuchet MS', sans-serif" font-size="18">non-camera deterministic source | frame {frame}</text>
  <text x="38" y="{height - 38}" fill="#fff8dc" font-family="Bahnschrift, 'Trebuchet MS', sans-serif" font-size="22">800x600 RGB888 UDP target</text>
</svg>
"""
    return svg.encode("utf-8")


def make_output_placeholder_svg(width: int = DEFAULT_WIDTH, height: int = DEFAULT_HEIGHT) -> bytes:
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  <defs>
    <linearGradient id="outbg" x1="0" x2="1" y1="0" y2="1">
      <stop offset="0" stop-color="#111827"/>
      <stop offset="1" stop-color="#334155"/>
    </linearGradient>
  </defs>
  <rect width="100%" height="100%" fill="url(#outbg)"/>
  <rect x="72" y="70" width="{width - 144}" height="{height - 140}" rx="28" fill="none" stroke="#91a7b8" stroke-width="5" stroke-dasharray="16 13"/>
  <text x="50%" y="45%" text-anchor="middle" fill="#e5edf2" font-family="Bahnschrift, 'Trebuchet MS', sans-serif" font-size="32" font-weight="700">FPGA OUTPUT PREVIEW</text>
  <text x="50%" y="52%" text-anchor="middle" fill="#b8c7d2" font-family="Bahnschrift, 'Trebuchet MS', sans-serif" font-size="20">waiting for HDMI capture image</text>
  <text x="50%" y="60%" text-anchor="middle" fill="#f0bd42" font-family="Bahnschrift, 'Trebuchet MS', sans-serif" font-size="18">output verification only, not an input source</text>
</svg>
"""
    return svg.encode("utf-8")


def dashboard_html() -> bytes:
    policy = html.escape(NO_CAMERA_POLICY)
    page = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Zynq Video Console</title>
  <style>
    :root {{
      --ink: #10201d;
      --paper: #f4ecd8;
      --amber: #d79a27;
      --teal: #2d6f64;
      --slate: #22313d;
      --line: rgba(16,32,29,0.16);
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      color: var(--ink);
      font-family: Bahnschrift, "Trebuchet MS", Verdana, sans-serif;
      background:
        radial-gradient(circle at 15% 12%, rgba(215,154,39,0.42), transparent 26rem),
        radial-gradient(circle at 88% 8%, rgba(45,111,100,0.38), transparent 28rem),
        linear-gradient(135deg, #efe3c4 0%, #c8d8cd 48%, #f6efd9 100%);
      min-height: 100vh;
    }}
    header {{
      padding: 28px clamp(18px, 4vw, 48px) 12px;
      display: flex;
      justify-content: space-between;
      gap: 20px;
      align-items: flex-end;
    }}
    h1 {{
      margin: 0;
      font-size: clamp(34px, 6vw, 76px);
      line-height: 0.9;
      letter-spacing: -0.06em;
    }}
    .policy {{
      max-width: 460px;
      padding: 14px 16px;
      border: 1px solid var(--line);
      border-radius: 18px;
      background: rgba(255,248,220,0.62);
      box-shadow: 0 16px 40px rgba(20, 40, 36, 0.11);
    }}
    main {{
      padding: 18px clamp(18px, 4vw, 48px) 44px;
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr) minmax(280px, 0.72fr);
      gap: 18px;
    }}
    .card {{
      background: rgba(255, 252, 238, 0.78);
      border: 1px solid var(--line);
      border-radius: 28px;
      box-shadow: 0 24px 70px rgba(20, 40, 36, 0.15);
      overflow: hidden;
      min-height: 320px;
    }}
    .card h2 {{
      margin: 0;
      padding: 18px 20px 12px;
      font-size: 22px;
      letter-spacing: -0.02em;
      border-bottom: 1px solid var(--line);
    }}
    .preview {{
      width: 100%;
      display: block;
      aspect-ratio: 4 / 3;
      background: #1e293b;
      object-fit: cover;
    }}
    .meta {{
      display: grid;
      gap: 8px;
      padding: 16px 18px 18px;
      font-size: 14px;
    }}
    .pill {{
      display: inline-flex;
      width: max-content;
      border-radius: 999px;
      padding: 6px 10px;
      background: rgba(45,111,100,0.12);
      color: #17463f;
      font-weight: 700;
    }}
    .controls {{
      padding: 16px;
      display: grid;
      gap: 12px;
    }}
    button {{
      border: 0;
      border-radius: 16px;
      padding: 14px 14px;
      color: #fff7e5;
      background: linear-gradient(135deg, var(--slate), var(--teal));
      font: inherit;
      font-weight: 700;
      cursor: not-allowed;
      opacity: 0.72;
    }}
    .log {{
      margin: 0 16px 18px;
      padding: 14px;
      min-height: 170px;
      border-radius: 18px;
      color: #d9f7eb;
      background: #13231f;
      font-family: "Cascadia Mono", Consolas, monospace;
      font-size: 13px;
      white-space: pre-wrap;
    }}
    @media (max-width: 1080px) {{
      main {{ grid-template-columns: 1fr; }}
      header {{ align-items: flex-start; flex-direction: column; }}
    }}
  </style>
</head>
<body>
  <header>
    <div>
      <h1>Zynq Video<br>Control Console</h1>
    </div>
    <div class="policy" data-testid="no-camera-policy">{policy}</div>
  </header>
  <main>
    <section class="card" data-panel="input">
      <h2>Input To FPGA</h2>
      <img class="preview" id="input-preview" src="/api/input-preview.svg?frame=0" alt="generated PC input preview">
      <div class="meta">
        <span class="pill">generated source</span>
        <span>Custom file input: deferred after MVP.</span>
        <span>Camera/webcam input: disabled.</span>
      </div>
    </section>
    <section class="card" data-panel="output">
      <h2>FPGA Output</h2>
      <img class="preview" id="output-preview" src="/api/output-preview" alt="FPGA HDMI output preview">
      <div class="meta">
        <span class="pill">HDMI capture slot</span>
        <span>Displays latest HDMI capture image when configured.</span>
      </div>
    </section>
    <section class="card" data-panel="control">
      <h2>Function Control Panel</h2>
      <div class="controls">
        <button disabled>Start stream</button>
        <button disabled>Stop stream</button>
        <button disabled>Pause FPGA receiver</button>
        <button disabled>Resume FPGA receiver</button>
        <button disabled>Effect: none / invert</button>
      </div>
      <pre class="log" id="log">dashboard scaffold ready
stream/control actions are wired in later cycles</pre>
    </section>
  </main>
  <script>
    let frame = 0;
    async function tick() {{
      frame = (frame + 1) % 100000;
      document.getElementById("input-preview").src = "/api/input-preview.svg?frame=" + frame;
      try {{
        const state = await fetch("/api/state").then(r => r.json());
        document.getElementById("log").textContent = state.logs.join("\\n");
      }} catch (err) {{
        document.getElementById("log").textContent = "dashboard state fetch failed: " + err;
      }}
    }}
    setInterval(tick, 1000);
  </script>
</body>
</html>
"""
    return page.encode("utf-8")


class DashboardState:
    def __init__(self, output_image: Path | None = None) -> None:
        self.started_at = time.time()
        self.output_image = output_image
        self.logs = [
            "dashboard scaffold ready",
            "input source: generated PC frames",
            "custom file input: deferred after MVP",
            "camera/webcam input: disabled",
        ]

    def as_json(self) -> dict[str, Any]:
        return {
            "status": "scaffold",
            "panels": ["input-preview", "fpga-output-preview", "function-control-panel"],
            "input_source": {
                "kind": "generated",
                "camera_enabled": False,
                "custom_file_enabled": False,
                "policy": NO_CAMERA_POLICY,
            },
            "output_preview": {
                "kind": "hdmi-capture-slot",
                "configured_image": str(self.output_image) if self.output_image else None,
            },
            "control_panel": {
                "actions_enabled": False,
                "planned_actions": ["start", "stop", "pause", "resume", "effect"],
            },
            "uptime_s": round(time.time() - self.started_at, 3),
            "logs": list(self.logs),
        }


def make_handler(state: DashboardState) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "ZynqDashboard/0.1"

        def log_message(self, format: str, *args: Any) -> None:  # noqa: A003
            return

        def send_payload(self, status: int, content_type: str, payload: bytes) -> None:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)

        def do_GET(self) -> None:  # noqa: N802
            parsed = urlparse(self.path)
            if parsed.path == "/":
                self.send_payload(200, "text/html; charset=utf-8", dashboard_html())
                return
            if parsed.path == "/api/state":
                payload = json.dumps(state.as_json(), indent=2).encode("utf-8")
                self.send_payload(200, "application/json; charset=utf-8", payload)
                return
            if parsed.path == "/api/input-preview.svg":
                frame_text = parse_qs(parsed.query).get("frame", ["0"])[0]
                try:
                    frame = int(frame_text)
                except ValueError:
                    frame = 0
                self.send_payload(200, "image/svg+xml", make_input_svg(frame))
                return
            if parsed.path == "/api/output-preview":
                if state.output_image and state.output_image.exists():
                    content_type = mimetypes.guess_type(str(state.output_image))[0] or "application/octet-stream"
                    self.send_payload(200, content_type, state.output_image.read_bytes())
                else:
                    self.send_payload(200, "image/svg+xml", make_output_placeholder_svg())
                return
            self.send_payload(404, "text/plain; charset=utf-8", b"not found")

    return Handler


def run_server(host: str, port: int, output_image: Path | None) -> None:
    state = DashboardState(output_image=output_image)
    server = ThreadingHTTPServer((host, port), make_handler(state))
    print(f"DASHBOARD_READY http://{host}:{server.server_port}", flush=True)
    server.serve_forever()


def run_self_test(out_dir: Path) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    state = DashboardState()
    server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(state))
    url = f"http://127.0.0.1:{server.server_port}"
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        html_bytes = urllib.request.urlopen(url + "/", timeout=5).read()
        state_bytes = urllib.request.urlopen(url + "/api/state", timeout=5).read()
        input_bytes = urllib.request.urlopen(url + "/api/input-preview.svg?frame=7", timeout=5).read()
        output_bytes = urllib.request.urlopen(url + "/api/output-preview", timeout=5).read()

        out_dir.joinpath("index.html").write_bytes(html_bytes)
        out_dir.joinpath("state.json").write_bytes(state_bytes)
        out_dir.joinpath("input-preview.svg").write_bytes(input_bytes)
        out_dir.joinpath("output-placeholder.svg").write_bytes(output_bytes)

        page = html_bytes.decode("utf-8")
        data = json.loads(state_bytes.decode("utf-8"))
        assert 'data-panel="input"' in page
        assert 'data-panel="output"' in page
        assert 'data-panel="control"' in page
        assert data["input_source"]["camera_enabled"] is False
        assert data["input_source"]["custom_file_enabled"] is False
        assert "camera/webcam input: disabled" in data["logs"]
        assert b"GENERATED INPUT" in input_bytes
        assert b"FPGA OUTPUT PREVIEW" in output_bytes
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    print(f"DASHBOARD_SCAFFOLD_SELF_TEST_OK out={out_dir}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--output-image", default="")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--out-dir", default="build/visual-dashboard-scaffold")
    args = parser.parse_args()

    output_image = Path(args.output_image) if args.output_image else None
    if args.self_test:
        return run_self_test(Path(args.out_dir))
    run_server(args.host, args.port, output_image)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
