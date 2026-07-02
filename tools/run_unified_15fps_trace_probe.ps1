[CmdletBinding()]
param(
    [string]$BoardIp = "192.168.1.10",
    [string]$PcIp = "192.168.1.2",
    [string]$Port = "COM16",
    [int]$UdpPort = 5005,
    [int]$HttpPort = 8000,
    [string]$DashboardHost = "127.0.0.1",
    [int]$DashboardPort = 8765,
    [string]$CaptureDevice = "1",
    [string]$CaptureBackend = "dshow",
    [double]$StreamFps = 10.0,
    [int]$MjpegFrames = 150,
    [int]$MjpegMinUnique = 20,
    [int]$MjpegMinColors = 2,
    [int]$Frames = 90,
    [int]$WarmupFrames = 12,
    [int]$ValidationStartFrameId = 100,
    [double]$Fps = 10.0,
    [double]$TraceMaxLatencyMs = 1000.0,
    [int]$UdpPayload = 1200,
    [int]$HoldRepeats = 1,
    [int]$InterPacketUs = 0,
    [double]$PacketWindowFraction = 0.85,
    [ValidateSet("msync", "none")]
    [string]$ReceiverSyncMode = "none",
    [int]$ReceiverPresentFps = 10,
    [int]$ContentHoldFrames = 50,
    [int]$TimelineSamples = 20,
    [string]$ControlFifo = "/tmp/video_ctl",
    [string]$OutDir = "build\dashboard-truthful-sent-received-timelines"
)

$ErrorActionPreference = "Stop"

function Stop-DashboardListener {
    param([int]$Port)

    $listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    foreach ($listener in $listeners) {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)" -ErrorAction SilentlyContinue
        if ($null -eq $process -or $process.CommandLine -notmatch "pc_dashboard\.py") {
            throw "TCP port $Port is occupied by non-dashboard process pid=$($listener.OwningProcess)"
        }
        Stop-Process -Id $listener.OwningProcess -Force -ErrorAction Stop
    }
}

function Stop-StaleSenders {
    $senders = Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -match "python" -and
            ($_.CommandLine -match "send_demo_video_udp\.py" -or $_.CommandLine -match "send_unified_test_video_udp\.py")
        }
    foreach ($sender in $senders) {
        Stop-Process -Id $sender.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Send-UartInterrupt {
    param(
        [string]$Port,
        [int]$BaudRate = 115200
    )

    $serial = [System.IO.Ports.SerialPort]::new(
        $Port,
        $BaudRate,
        [System.IO.Ports.Parity]::None,
        8,
        [System.IO.Ports.StopBits]::One
    )
    try {
        $serial.Open()
        $serial.Write([char]3)
        Start-Sleep -Milliseconds 300
        $serial.Write("`r`n")
        Start-Sleep -Milliseconds 300
        [void]$serial.ReadExisting()
    }
    finally {
        if ($serial.IsOpen) {
            $serial.Close()
        }
        $serial.Dispose()
    }
}

function Read-JsonFile {
    param([string]$Path)
    Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Invoke-DashboardAction {
    param(
        [string]$Url,
        [string]$Action
    )
    $body = @{ action = $Action } | ConvertTo-Json
    Invoke-RestMethod -Uri "$Url/api/action" -Method Post -ContentType "application/json" -Body $body -TimeoutSec 20
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outPath = Join-Path $repoRoot $OutDir
New-Item -ItemType Directory -Force -Path $outPath | Out-Null

Stop-DashboardListener -Port $DashboardPort
Stop-StaleSenders
Send-UartInterrupt -Port $Port

& (Join-Path $repoRoot "software\eth_pass_through\scripts\build-linux-receiver-wsl.ps1") -OutDir $OutDir
if ($LASTEXITCODE -ne 0) {
    throw "receiver build failed"
}

$shaLine = Get-Content -LiteralPath (Join-Path $outPath "fb_video_udp_receiver.sha256.txt") | Select-Object -First 1
$receiverSha = ($shaLine -split "\s+")[0]

$listener = Get-NetTCPConnection -LocalPort $HttpPort -State Listen -ErrorAction SilentlyContinue
if ($listener) {
    throw "TCP port $HttpPort is already listening"
}

$receiverPath = Join-Path $outPath "fb_video_udp_receiver"
$serverJob = Start-Job -ArgumentList $HttpPort,$receiverPath -ScriptBlock {
    param($BindPort, $FilePath)

    $listener = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Any,
        [int]$BindPort
    )
    $listener.Start()
    try {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $buffer = New-Object byte[] 4096
            [void]$stream.Read($buffer, 0, $buffer.Length)
            $body = [System.IO.File]::ReadAllBytes($FilePath)
            $headerText = "HTTP/1.0 200 OK`r`nContent-Type: application/octet-stream`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
            $header = [System.Text.Encoding]::ASCII.GetBytes($headerText)
            $stream.Write($header, 0, $header.Length)
            $stream.Write($body, 0, $body.Length)
            $stream.Flush()
            Write-Output "ONE_SHOT_HTTP_SERVED bytes=$($body.Length)"
        }
        finally {
            $client.Close()
        }
    }
    finally {
        $listener.Stop()
    }
}

$dashboardProcess = $null
$mjpegProcess = $null

try {
    Start-Sleep -Seconds 1

    $deployCommands = Join-Path $outPath "uart_deploy_start_receiver.commands"
    @(
        "ifconfig eth0 $BoardIp netmask 255.255.255.0 up",
        "sysctl -w net.core.rmem_max=33554432 2>/dev/null || true",
        "sysctl -w net.core.rmem_default=33554432 2>/dev/null || true",
        "kill `$(pidof fb_video_udp_receiver 2>/dev/null) 2>/dev/null || true",
        "rm -f /tmp/fb_video_udp_receiver /tmp/fb_video_udp_receiver.log $ControlFifo",
        "wget -q -O /tmp/fb_video_udp_receiver http://$($PcIp):$($HttpPort)/fb_video_udp_receiver",
        "echo '$receiverSha  /tmp/fb_video_udp_receiver' | sha256sum -c -",
        "chmod +x /tmp/fb_video_udp_receiver",
        "echo 0 > /sys/class/graphics/fbcon/cursor_blink 2>/dev/null || true",
        "printf '\033[?25l' > /dev/tty0 2>/dev/null || true",
        "setterm -cursor off -blank 0 -powersave off < /dev/tty0 > /dev/tty0 2>/dev/null || true",
        "/tmp/fb_video_udp_receiver --port $UdpPort --frames 1000000 --timeout-sec 180 --control-fifo $ControlFifo --sync-mode $ReceiverSyncMode --present-fps $ReceiverPresentFps > /tmp/fb_video_udp_receiver.log 2>&1 & echo RECEIVER_PID=`$!",
        "sleep 1",
        "cat /tmp/fb_video_udp_receiver.log"
    ) | Set-Content -LiteralPath $deployCommands -Encoding ASCII

    & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port `
        -CommandFile $deployCommands `
        -LoginRoot `
        -Password root `
        -InitialReadSeconds 1 `
        -InterCommandDelayMilliseconds 500 `
        -FinalReadSeconds 2 `
        -OutputPath (Join-Path $OutDir "uart_deploy_start_receiver.log")

    if (-not (Wait-Job $serverJob -Timeout 60)) {
        throw "receiver download did not reach the one-shot HTTP server"
    }
    Receive-Job $serverJob -Wait -AutoRemoveJob | Tee-Object -FilePath (Join-Path $outPath "one-shot-http-server.log")
    $serverJob = $null

    $deployLog = Get-Content -Raw -LiteralPath (Join-Path $outPath "uart_deploy_start_receiver.log")
    if ($deployLog -notmatch "/tmp/fb_video_udp_receiver: OK" -or
        $deployLog -notmatch "CONTROL_FIFO_READY" -or
        $deployLog -notmatch "VIDEO_UDP_LINUX_RECEIVER_READY") {
        throw "receiver deploy/start markers missing"
    }

    $dashboardOut = Join-Path $outPath "dashboard.out.log"
    $dashboardErr = Join-Path $outPath "dashboard.err.log"
    $dashboardArgs = @(
        ".\tools\dashboard\pc_dashboard.py",
        "--host", $DashboardHost,
        "--port", "$DashboardPort",
        "--board-host", $BoardIp,
        "--udp-port", "$UdpPort",
        "--sender-frames", "$Frames",
        "--sender-fps", "$Fps",
        "--sender-start-frame-id", "$ValidationStartFrameId",
        "--sender-warmup-frames", "$WarmupFrames",
        "--sender-content-hold-frames", "$ContentHoldFrames",
        "--sender-payload", "$UdpPayload",
        "--sender-inter-packet-us", "$InterPacketUs",
        "--uart-disabled",
        "--capture-device", $CaptureDevice,
        "--capture-backend", $CaptureBackend,
        "--capture-width", "800",
        "--capture-height", "600",
        "--stream-fps", "$StreamFps",
        "--log-dir", $OutDir
    )
    $dashboardProcess = Start-Process -WindowStyle Hidden -FilePath python `
        -ArgumentList $dashboardArgs `
        -WorkingDirectory $repoRoot `
        -RedirectStandardOutput $dashboardOut `
        -RedirectStandardError $dashboardErr `
        -PassThru

    $dashboardUrl = "http://$($DashboardHost):$DashboardPort"
    $dashboardReady = $false
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        try {
            Invoke-RestMethod -Uri "$dashboardUrl/api/state" -TimeoutSec 2 | Out-Null
            $dashboardReady = $true
            break
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }
    if (-not $dashboardReady) {
        throw "dashboard did not become ready"
    }

    $mjpegOut = Join-Path $outPath "mjpeg-return"
    Remove-Item -LiteralPath $mjpegOut -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $mjpegOut | Out-Null
    $mjpegStdout = Join-Path $mjpegOut "probe.out.log"
    $mjpegStderr = Join-Path $mjpegOut "probe.err.log"
    $mjpegArgs = @(
        ".\tools\probe_mjpeg_stream.py",
        "$dashboardUrl/api/output-stream.mjpeg",
        "--out-dir", $mjpegOut,
        "--frames", "$MjpegFrames",
        "--min-unique", "$MjpegMinUnique",
        "--timeout-sec", "30"
    )
    $mjpegProcess = Start-Process -WindowStyle Hidden -FilePath python `
        -ArgumentList $mjpegArgs `
        -WorkingDirectory $repoRoot `
        -RedirectStandardOutput $mjpegStdout `
        -RedirectStandardError $mjpegStderr `
        -PassThru

    $probeStatusPath = Join-Path $mjpegOut "probe-live-status.json"
    $probeReady = $false
    $sentTimeOffsetMs = 0.0
    for ($attempt = 0; $attempt -lt 80; $attempt++) {
        if (Test-Path -LiteralPath $probeStatusPath) {
            $probeStatus = Read-JsonFile $probeStatusPath
            if ([int]$probeStatus.saved_frames -ge 1) {
                $sentTimeOffsetMs = [double]$probeStatus.latest_captured_ms
                $probeReady = $true
                break
            }
        }
        Start-Sleep -Milliseconds 250
    }
    if (-not $probeReady) {
        throw "MJPEG probe did not produce a pre-roll frame before sender start"
    }

    $startResult = Invoke-DashboardAction -Url $dashboardUrl -Action "start-stream"
    $startResult | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outPath "dashboard_start_stream.json") -Encoding UTF8
    if (-not $startResult.ok -or $startResult.state.input_source.sender_kind -ne "unified") {
        throw "Dashboard did not start the unified sender"
    }

    $timelineCount = 0
    $negativeLagSamples = 0
    $positiveLagSamples = 0
    $maxLagFrames = 0
    $timelinePreviewSource = ""
    $timelineRecords = @()
    $sentTimelineIds = New-Object 'System.Collections.Generic.HashSet[int]'
    $hdmiTimelineIds = New-Object 'System.Collections.Generic.HashSet[int]'
    for ($attempt = 0; $attempt -lt 200 -and $timelineCount -lt $TimelineSamples; $attempt++) {
        try {
            $preview = Invoke-WebRequest -UseBasicParsing -Uri "$dashboardUrl/api/input-preview.bmp?sample=$attempt" -TimeoutSec 5
            $frameIdText = [string]$preview.Headers["X-Frame-ID"]
            $hdmiFrameIdText = [string]$preview.Headers["X-HDMI-Frame-ID"]
            $previewSource = [string]$preview.Headers["X-Preview-Source"]
            if ($previewSource -eq "latest-actual-sent-frame" -and $frameIdText -ne "" -and $hdmiFrameIdText -ne "") {
                $timelinePreviewSource = $previewSource
                $sentFrameId = [int]$frameIdText
                $hdmiFrameId = [int]$hdmiFrameIdText
                $lagFrames = $sentFrameId - $hdmiFrameId
                $timelineCount++
                [void]$sentTimelineIds.Add($sentFrameId)
                [void]$hdmiTimelineIds.Add($hdmiFrameId)
                if ($lagFrames -lt 0) {
                    $negativeLagSamples++
                }
                if ($lagFrames -gt 0) {
                    $positiveLagSamples++
                }
                if ($lagFrames -gt $maxLagFrames) {
                    $maxLagFrames = $lagFrames
                }
                $timelineRecords += [ordered]@{
                    sample = $timelineCount
                    sent_frame_id = $sentFrameId
                    hdmi_frame_id = $hdmiFrameId
                    lag_frames = $lagFrames
                }
            }
        }
        catch {
        }
        Start-Sleep -Milliseconds 100
    }
    $timelineEvidence = [ordered]@{
        preview_source = "latest-actual-sent-frame"
        requested_samples = $TimelineSamples
        timeline_samples = $timelineCount
        negative_lag_samples = $negativeLagSamples
        positive_lag_samples = $positiveLagSamples
        distinct_sent_ids = $sentTimelineIds.Count
        distinct_hdmi_ids = $hdmiTimelineIds.Count
        max_lag_frames = $maxLagFrames
        records = $timelineRecords
    }
    $timelineEvidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outPath "timeline-evidence.json") -Encoding UTF8
    if ($timelineCount -lt $TimelineSamples -or $negativeLagSamples -ne 0 -or
        $positiveLagSamples -lt 1 -or $sentTimelineIds.Count -lt 3 -or
        $hdmiTimelineIds.Count -lt 3 -or $maxLagFrames -gt 30) {
        throw "timeline check failed samples=$timelineCount negative=$negativeLagSamples positive=$positiveLagSamples distinct_sent=$($sentTimelineIds.Count) distinct_hdmi=$($hdmiTimelineIds.Count) max_lag=$maxLagFrames"
    }

    $senderTracePath = Join-Path $outPath "sender\sender-trace.json"
    $senderFinished = $false
    for ($attempt = 0; $attempt -lt 240; $attempt++) {
        $dashboardState = Invoke-RestMethod -Uri "$dashboardUrl/api/state" -TimeoutSec 5
        if ($dashboardState.control_panel.stream_state -eq "stopped" -and (Test-Path -LiteralPath $senderTracePath)) {
            $senderFinished = $true
            break
        }
        Start-Sleep -Milliseconds 250
    }
    if (-not $senderFinished) {
        throw "Dashboard unified sender did not finish or emit sender trace"
    }

    if (-not $mjpegProcess.WaitForExit(45000)) {
        Stop-Process -Id $mjpegProcess.Id -Force -ErrorAction SilentlyContinue
        throw "MJPEG probe timed out"
    }
    $mjpegProcess.Refresh()
    $mjpegProbeReport = Read-JsonFile (Join-Path $mjpegOut "mjpeg-stream-probe.json")
    if ([string]$mjpegProbeReport.status -ne "pass") {
        throw "MJPEG probe failed; see $mjpegStdout and $mjpegStderr"
    }
    if (-not $mjpegProbeReport.saved -or [int]$mjpegProbeReport.saved.Count -lt 1) {
        throw "MJPEG probe report has no saved frames"
    }
    $sentTimeOffsetMs = [double]$mjpegProbeReport.saved[0].captured_ms
    $mjpegProcess = $null

    $afterCommands = Join-Path $outPath "uart_after_unified_15fps.commands"
    @(
        "cat /tmp/fb_video_udp_receiver.log",
        "kill `$(pidof fb_video_udp_receiver 2>/dev/null) 2>/dev/null || true",
        "ifconfig eth0 | grep -E 'RX packets|TX packets|errors|dropped'"
    ) | Set-Content -LiteralPath $afterCommands -Encoding ASCII

    & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port `
        -CommandFile $afterCommands `
        -LoginRoot `
        -Password root `
        -InitialReadSeconds 1 `
        -InterCommandDelayMilliseconds 500 `
        -FinalReadSeconds 2 `
        -OutputPath (Join-Path $OutDir "uart_after_unified_15fps.log")

    $afterLog = Get-Content -Raw -LiteralPath (Join-Path $outPath "uart_after_unified_15fps.log")
    $writeMatches = [regex]::Matches($afterLog, "VIDEO_UDP_FRAME_WRITTEN frame_id=(\d+) frames=(\d+) packets=(\d+) dropped=(\d+)")
    $validationEndFrameId = $ValidationStartFrameId + $Frames - 1
    $validationWrittenIds = New-Object 'System.Collections.Generic.HashSet[int]'
    $receiverDropped = 0
    foreach ($match in $writeMatches) {
        $frameId = [int]$match.Groups[1].Value
        $dropped = [int]$match.Groups[4].Value
        if ($dropped -gt $receiverDropped) {
            $receiverDropped = $dropped
        }
        if ($frameId -ge $ValidationStartFrameId -and $frameId -le $validationEndFrameId) {
            [void]$validationWrittenIds.Add($frameId)
        }
    }
    $receiverFrames = $validationWrittenIds.Count
    if ($receiverFrames -ne $Frames -or $receiverDropped -ne 0) {
        throw "receiver counters failed validation_written=$receiverFrames expected=$Frames dropped=$receiverDropped"
    }

    $traceDir = Join-Path $outPath "trace"
    $traceJson = Join-Path $traceDir "trace.json"
    $minMatchedFrames = [int][Math]::Ceiling($Frames * 0.95)
    & python (Join-Path $repoRoot "tools\build_unified_trace_from_mjpeg.py") `
        --sender-json $senderTracePath `
        --mjpeg-report (Join-Path $mjpegOut "mjpeg-stream-probe.json") `
        --out-dir $traceDir `
        --trace-json $traceJson `
        --capture-fps $StreamFps `
        --min-colors $MjpegMinColors `
        --min-matched-frames $minMatchedFrames `
        --max-latency-ms $TraceMaxLatencyMs `
        --sent-time-offset-ms $sentTimeOffsetMs
    if ($LASTEXITCODE -ne 0) {
        throw "trace builder failed"
    }

    $validatorResult = Join-Path $traceDir "validation-result.json"
    & python (Join-Path $repoRoot "tools\validate_passthrough_trace.py") `
        $traceJson `
        --result-json $validatorResult
    if ($LASTEXITCODE -ne 0) {
        throw "unified trace validator failed"
    }

    $senderJson = Read-JsonFile $senderTracePath
    $mjpegReport = Read-JsonFile (Join-Path $mjpegOut "mjpeg-stream-probe.json")
    $classification = Read-JsonFile (Join-Path $traceDir "mjpeg-classification.json")
    $validator = Read-JsonFile $validatorResult
    $trace = Read-JsonFile $traceJson

    $senderFps = [double]$senderJson.fps
    $sentFrames = [int]$senderJson.frames
    $sentTimes = @($senderJson.sent | ForEach-Object { [double]$_.sent_ms })
    $senderMeasuredFps = (($sentTimes.Count - 1) * 1000.0) / ($sentTimes[-1] - $sentTimes[0])
    $mjpegSavedFrames = [int]$classification.summary.mjpeg_saved_frames
    $mjpegUniqueHashes = [int]$mjpegReport.unique_hashes
    $mjpegUniqueColors = [int]$classification.summary.mjpeg_unique_colors
    $traceRequireImages = if ($trace.requirements.require_image_paths) { 1 } else { 0 }
    $traceMetrics = $validator.metrics
    $validatorStatus = [string]$validator.status
    $dashboardState = Invoke-RestMethod -Uri "$dashboardUrl/api/state" -TimeoutSec 5
    $contentDwellSeconds = [double]$dashboardState.input_source.content_dwell_seconds
    $dashboardSenderKind = [string]$dashboardState.input_source.sender_kind
    $dashboardSenderFps = [double]$dashboardState.input_source.sender_fps

    $passCondition = (
        $dashboardSenderKind -eq "unified" -and
        $timelinePreviewSource -eq "latest-actual-sent-frame" -and
        $dashboardSenderFps -eq 10.0 -and
        $senderFps -eq 10.0 -and
        $senderMeasuredFps -ge 9.5 -and
        $senderMeasuredFps -le 10.5 -and
        $ReceiverPresentFps -eq 10 -and
        $StreamFps -eq 10.0 -and
        $contentDwellSeconds -eq 5.0 -and
        $timelineCount -ge 20 -and
        $negativeLagSamples -eq 0 -and
        $positiveLagSamples -ge 1 -and
        $sentTimelineIds.Count -ge 3 -and
        $hdmiTimelineIds.Count -ge 3 -and
        $maxLagFrames -le 30 -and
        $sentFrames -eq 90 -and
        $receiverFrames -eq 90 -and
        $receiverDropped -eq 0 -and
        $traceRequireImages -eq 1 -and
        [int]$traceMetrics.image_path_failures -eq 0 -and
        $validatorStatus -eq "pass" -and
        [int]$traceMetrics.sent_frames -eq 90 -and
        [int]$traceMetrics.matched_frames -ge 86 -and
        [double]$traceMetrics.drop_rate -le 0.05 -and
        [int]$traceMetrics.order_violations -eq 0 -and
        [int]$traceMetrics.content_mismatches -eq 0 -and
        [int]$traceMetrics.black_frames -eq 0 -and
        [double]$traceMetrics.max_latency_ms -le 1000.0
    )

    $summary = [ordered]@{
        status = if ($passCondition) { "pass" } else { "fail" }
        dashboard_sender_kind = $dashboardSenderKind
        preview_source = $timelinePreviewSource
        dashboard_sender_fps = $dashboardSenderFps
        sender_fps = $senderFps
        sender_measured_fps = [Math]::Round($senderMeasuredFps, 3)
        receiver_present_fps = $ReceiverPresentFps
        hdmi_delivery_fps = $StreamFps
        content_dwell_seconds = $contentDwellSeconds
        timeline_samples = $timelineCount
        negative_lag_samples = $negativeLagSamples
        positive_lag_samples = $positiveLagSamples
        distinct_sent_ids = $sentTimelineIds.Count
        distinct_hdmi_ids = $hdmiTimelineIds.Count
        max_lag_frames = $maxLagFrames
        sent_frames = $sentFrames
        sender_hold_repeats = [int]$senderJson.hold_repeats
        receiver_written_frames = $receiverFrames
        receiver_dropped_packets = $receiverDropped
        mjpeg_saved_frames = $mjpegSavedFrames
        mjpeg_unique_hashes = $mjpegUniqueHashes
        mjpeg_unique_colors = $mjpegUniqueColors
        trace_require_image_paths = $traceRequireImages
        trace_image_path_failures = [int]$traceMetrics.image_path_failures
        validator_status = $validatorStatus
        trace_sent_frames = [int]$traceMetrics.sent_frames
        trace_matched_frames = [int]$traceMetrics.matched_frames
        trace_drop_rate = [double]$traceMetrics.drop_rate
        trace_order_violations = [int]$traceMetrics.order_violations
        trace_content_mismatches = [int]$traceMetrics.content_mismatches
        trace_black_frames = [int]$traceMetrics.black_frames
        trace_required_max_latency_ms = [double]$validator.requirements.max_latency_ms
        trace_mean_latency_ms = $traceMetrics.mean_latency_ms
        trace_max_latency_ms = $traceMetrics.max_latency_ms
        sent_time_offset_ms = $sentTimeOffsetMs
        out = $outPath
    }
    $summaryPath = Join-Path $outPath "dashboard-truthful-sent-received-timelines-summary.json"
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

    $markerBits = "dashboard_sender_kind=$dashboardSenderKind preview_source=$timelinePreviewSource configured_sender_fps=$dashboardSenderFps sender_measured_fps=$([Math]::Round($senderMeasuredFps, 3)) receiver_present_fps=$ReceiverPresentFps hdmi_delivery_fps=$StreamFps content_dwell_seconds=$contentDwellSeconds timeline_samples=$timelineCount negative_lag_samples=$negativeLagSamples positive_lag_samples=$positiveLagSamples distinct_sent_ids=$($sentTimelineIds.Count) distinct_hdmi_ids=$($hdmiTimelineIds.Count) max_lag_frames=$maxLagFrames sent_frames=$sentFrames receiver_written_frames=$receiverFrames receiver_dropped_packets=$receiverDropped mjpeg_saved_frames=$mjpegSavedFrames mjpeg_unique_hashes=$mjpegUniqueHashes mjpeg_unique_colors=$mjpegUniqueColors trace_require_image_paths=$traceRequireImages trace_image_path_failures=$($traceMetrics.image_path_failures) validator_status=$validatorStatus trace_sent_frames=$($traceMetrics.sent_frames) trace_matched_frames=$($traceMetrics.matched_frames) trace_drop_rate=$($traceMetrics.drop_rate) trace_order_violations=$($traceMetrics.order_violations) trace_content_mismatches=$($traceMetrics.content_mismatches) trace_black_frames=$($traceMetrics.black_frames) trace_required_max_latency_ms=$($validator.requirements.max_latency_ms) trace_max_latency_ms=$($traceMetrics.max_latency_ms) sent_time_offset_ms=$sentTimeOffsetMs out=$outPath"
    if ($passCondition) {
        $marker = "DASHBOARD_TRUTHFUL_SENT_RECEIVED_TIMELINES_OK $markerBits"
        Set-Content -LiteralPath (Join-Path $outPath "dashboard-truthful-sent-received-timelines.marker.txt") -Value $marker -Encoding ASCII
        Write-Host $marker
    } else {
        $marker = "DASHBOARD_TRUTHFUL_SENT_RECEIVED_TIMELINES_FAIL $markerBits"
        Set-Content -LiteralPath (Join-Path $outPath "dashboard-truthful-sent-received-timelines.marker.txt") -Value $marker -Encoding ASCII
        throw $marker
    }
}
finally {
    if ($mjpegProcess -and -not $mjpegProcess.HasExited) {
        Stop-Process -Id $mjpegProcess.Id -Force -ErrorAction SilentlyContinue
    }
    if ($serverJob) {
        Stop-Job $serverJob -ErrorAction SilentlyContinue
        Remove-Job $serverJob -Force -ErrorAction SilentlyContinue
    }
    if ($dashboardProcess -and -not $dashboardProcess.HasExited) {
        Stop-Process -Id $dashboardProcess.Id -Force -ErrorAction SilentlyContinue
    }
}
