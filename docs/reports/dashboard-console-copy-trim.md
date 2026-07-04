# Dashboard Console Copy Trim

Cycle ID: dashboard-console-copy-trim

Date: 2026-07-04

## Objective

Remove redundant explanatory copy from the visible dashboard panels while
keeping machine-readable status and debug fields in `/api/state` and logs.

## Changed Scope

- Removed the header input-policy line from the browser-visible dashboard.
- Removed the static input-panel source/camera/custom-file explanation.
- Removed the static output-panel source/role/Windows-HDMI explanation.
- Kept `input_source.policy`, `output_preview.semantic`, status fields, and
  action logs unchanged for debugging and automation.

## Verification

Commands:

```powershell
rtk powershell.exe -NoProfile -Command "python -m py_compile tools\dashboard\pc_dashboard.py"
rtk powershell.exe -NoProfile -Command "python .\tools\dashboard\pc_dashboard.py --self-test --out-dir build\dashboard-console-copy-trim"
rtk powershell.exe -NoProfile -Command "rg -n '仅使用 PC|来源：PC 端 GStreamer 演示源预览|摄像头：禁用|自定义文件：暂缓|来源：通过采集卡读取的 HDMI 实时回传|角色：GStreamer RTP/JPEG 到 fbdevsink 的输出回看|说明：Windows 可能把 HDMI/UVC 采集卡标记为摄像头设备' build\dashboard-console-copy-trim\index.html; if ($LASTEXITCODE -eq 1) { 'HTML_COPY_TRIM_OK' }"
```

Observed markers:

```text
DASHBOARD_SCAFFOLD_SELF_TEST_OK
DASHBOARD_CONTROL_INTEGRATION_SELF_TEST_OK
DASHBOARD_MINIMAL_UI_SELF_TEST_OK
DASHBOARD_LIVE_SENDER_CONTROL_SELF_TEST_OK
DASHBOARD_GSTREAMER_CONTROL_SELF_TEST_OK
DASHBOARD_CHINESE_UI_SELF_TEST_OK
HTML_COPY_TRIM_OK
```

## Board Action

None. This is a PC-side dashboard rendering change only.

## Evidence

- `build/dashboard-console-copy-trim/index.html`
- `build/dashboard-console-copy-trim/state.json`
- `build/dashboard-console-copy-trim/final-state.json`

## Result

PASSED. The dashboard still renders the required input, output, and control
panels; control/API self-tests pass; the specified explanatory copy no longer
appears in the generated HTML.

## Residual Risk

An already-running dashboard process must be restarted to serve the updated
HTML.
