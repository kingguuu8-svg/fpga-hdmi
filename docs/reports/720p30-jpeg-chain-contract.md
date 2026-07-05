# 720p30 JPEG Chain Contract

Date: 2026-07-05

Result: PASSED for contract and gate creation. The connected-board 720p30
software-reference baseline is BLOCKED at about 5.5 fps, which justifies the
next PL decoder work.

## Objective

Fix 720p30 as the first real target for the `jpegpldec` PL decoder route, while
keeping higher targets such as 1080p30, 720p60, and 1080p60 open for later
scale-up.

This cycle does not implement PL JPEG decode. It removes ambiguity before that
work starts:

```text
720p30 is the first decoder target.
320x240 is only historical/probe evidence.
PL decode means compressed JPEG input to raw video output.
Raw-buffer PL probe/writeback is already proven and is not the final decoder.
```

## Changed Scope

- Added `docs/protocols/jpegpldec-720p30-contract.md`.
- Registered the new contract in `AGENTS.md`.
- Added `tools/run_720p30_jpeg_chain_gate.ps1` as the fixed-parameter 720p30
  gate wrapper around the existing GStreamer bottleneck probe.

## Contract

The first PL decoder target is:

```text
1280x720
30 fps
baseline MJPEG over RTP/JPEG
jpegpldec as the decoder entry point
software jpegdec child as the reference backend
PL backend later replaces the compressed-JPEG-to-raw-frame responsibility
```

The current display path is still the previously verified HDMI path unless a
separate 720p HDMI mode gate passes. A 720p decoder gate may therefore first
pass with `fakesink` or an 800x600 downscaled display output, but it must say so
explicitly.

## Verification Plan

Static checks:

```powershell
rtk powershell.exe -NoProfile -Command "`$null = [scriptblock]::Create((Get-Content -Raw .\tools\run_720p30_jpeg_chain_gate.ps1)); Write-Host POWERSHELL_PARSE_OK"
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_720p30_jpeg_chain_gate.ps1 -PlanOnly
```

Connected-board gate:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_720p30_jpeg_chain_gate.ps1 -DurationSec 6 -OutDir build\720p30-jpeg-chain-contract
```

Expected marker:

```text
720P30_JPEG_CHAIN_GATE_OK input=1280x720@30 output=800x600
```

## Verification Performed

Static checks:

```text
POWERSHELL_PARSE_OK
720P30_JPEG_CHAIN_GATE_PLAN_OK
```

Connected-board gate:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_720p30_jpeg_chain_gate.ps1 -DurationSec 6 -OutDir build\720p30-jpeg-chain-contract
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_720p30_jpeg_chain_gate.ps1 -AnalyzeOnly -OutDir build\720p30-jpeg-chain-contract
```

The wrapper initially treated a residual child exit code as a hard script
failure even though the underlying bottleneck probe completed and wrote its
summary. The wrapper was corrected to classify the gate from the generated
summary instead of failing before analysis.

Final marker:

```text
720P30_JPEG_CHAIN_GATE_BLOCKED status=blocked-software-baseline input=1280x720@30 output=800x600 fakesink_fps=5.47 fbdevsink_fps=5.37 cases=2 summary=E:\main\fpga-hdml\build\720p30-jpeg-chain-contract\video-bottleneck-summary.json
```

Measured cases:

| Route | Input | Output | Requested fps | Rendered | Dropped | Board average fps | Board gst-launch CPU |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| RTP/JPEG to fakesink | 1280x720@30 | 800x600 | 30 | 34 | 0 | 5.47 | 23.78% |
| RTP/JPEG to fbdevsink | 1280x720@30 | 800x600 | 30 | 34 | 0 | 5.37 | 25.20% |

The board GStreamer caps confirmed that the input was real 720p JPEG:

```text
rtpjpegdepay src caps: image/jpeg width=1280 height=720
jpegdec src caps: video/x-raw format=I420 width=1280 height=720
videoscale src caps: video/x-raw width=800 height=600 format=BGR
```

## Decision Rules

If the 720p30 software reference gate passes:

```text
Open jpegpldec-pl-decode-720p30-v0.
```

If `fakesink` passes but `fbdevsink` fails:

```text
Do not start by optimizing JPEG decode. The immediate blocker is display or
framebuffer output.
```

If both fail and the board log shows decode/fps collapse:

```text
Proceed with PL decoder work, using software jpegdec as the reference.
```

If HDMI native 720p is required for the demo:

```text
Open a separate 720p HDMI mode gate before claiming native 720p output.
```

## Residual Risks

- The current board reference owner still records 800x600 as the verified HDMI
  mode. Native 720p output is not claimed by this contract.
- The connected gate used the existing software `jpegdec` benchmark path, not
  `jpegpldec` profile counters at 720p. It is a software-reference route gate,
  not a PL decoder measurement.
- PL decoder implementation remains future work.

## Decision

Open the next implementation cycle as `jpegpldec-pl-decode-720p30-v0`.

The next cycle should not repeat generic profiling. It should begin replacing
the software `jpegdec` child responsibility inside `jpegpldec` with a
compressed-JPEG-to-raw-frame PL backend for the fixed 720p30 contract.
