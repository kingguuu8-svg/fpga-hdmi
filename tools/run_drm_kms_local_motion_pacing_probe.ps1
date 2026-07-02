[CmdletBinding()]
param(
    [string]$BoardIp = "192.168.1.10",
    [string]$PcIp = "192.168.1.2",
    [string]$Port = "COM16",
    [int]$HttpPort = 8000,
    [string]$CaptureDevice = "1",
    [string]$CaptureBackend = "dshow",
    [double]$CaptureFps = 30.0,
    [int]$CaptureFrames = 360,
    [int]$Frames = 120,
    [double]$PresentFps = 30.0,
    [int]$StartDelaySec = 8,
    [int]$HoldSec = 10,
    [string]$OutDir = "build\drm-kms-local-motion-pacing"
)

$ErrorActionPreference = "Stop"

function Stop-StaleProcesses {
    $stale = Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -match "python" -and
            ($_.CommandLine -match "probe_hdmi_motion_capture\.py")
        }
    foreach ($process in $stale) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
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

function Get-StdDev {
    param([double[]]$Values)

    if ($Values.Count -lt 2) {
        return [double]::PositiveInfinity
    }
    $mean = ($Values | Measure-Object -Average).Average
    $sum = 0.0
    foreach ($value in $Values) {
        $sum += [Math]::Pow($value - $mean, 2.0)
    }
    return [Math]::Sqrt($sum / $Values.Count)
}

function Write-Summary {
    param(
        [string]$Status,
        [string]$FailureReason,
        [hashtable]$Fields
    )

    $summary = [ordered]@{
        status = $Status
        failure_reason = $FailureReason
    }
    foreach ($key in $Fields.Keys) {
        $summary[$key] = $Fields[$key]
    }
    $summaryPath = Join-Path $script:outPath "drm-kms-local-motion-pacing-summary.json"
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    return $summaryPath
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outPath = Join-Path $repoRoot $OutDir
$script:outPath = $outPath
New-Item -ItemType Directory -Force -Path $outPath | Out-Null

$captureProcess = $null
$serverJob = $null
$fields = @{
    display_backend = "unknown"
    drm_device = "/dev/dri/card0"
    video_source = "unknown"
    fbdev_live_write_used = 1
    drm_dumb_buffers = 0
    drm_page_flip_calls = 0
    drm_vblank_flip_events = 0
    generated_frames = 0
    motion_content_type = "unknown"
    captured_motion_frames = 0
    tearing_frames = -1
    frame_duration_stddev_ms = [double]::PositiveInfinity
    validator_status = "not-run"
    out = $outPath
}

try {
    Stop-StaleProcesses
    Send-UartInterrupt -Port $Port

    & (Join-Path $repoRoot "software\eth_pass_through\scripts\build-linux-receiver-wsl.ps1") -OutDir $OutDir
    if ($LASTEXITCODE -ne 0) {
        throw "receiver build failed"
    }

    $shaLine = Get-Content -LiteralPath (Join-Path $outPath "drm_kms_udp_receiver.sha256.txt") | Select-Object -First 1
    $receiverSha = ($shaLine -split "\s+")[0]
    $receiverPath = Join-Path $outPath "drm_kms_udp_receiver"

    $listener = Get-NetTCPConnection -LocalPort $HttpPort -State Listen -ErrorAction SilentlyContinue
    if ($listener) {
        throw "TCP port $HttpPort is already listening"
    }

    $serverJob = Start-Job -ArgumentList $HttpPort,$receiverPath -ScriptBlock {
        param($BindPort, $FilePath)

        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, [int]$BindPort)
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

    Start-Sleep -Seconds 1
    $deployCommands = Join-Path $outPath "uart_deploy_start_local_motion.commands"
    @(
        "kill `$(pidof drm_kms_udp_receiver 2>/dev/null) 2>/dev/null || true",
        "kill `$(pidof fb_video_udp_receiver 2>/dev/null) 2>/dev/null || true",
        "rm -f /tmp/drm_kms_udp_receiver /tmp/drm_kms_local_motion.log",
        "wget -q -O /tmp/drm_kms_udp_receiver http://$($PcIp):$($HttpPort)/drm_kms_udp_receiver",
        "echo '$receiverSha  /tmp/drm_kms_udp_receiver' | sha256sum -c -",
        "chmod +x /tmp/drm_kms_udp_receiver",
        "/tmp/drm_kms_udp_receiver --drm /dev/dri/card0 --local-motion --frames $Frames --present-fps $PresentFps --start-delay-sec $StartDelaySec --hold-sec $HoldSec > /tmp/drm_kms_local_motion.log 2>&1 & echo LOCAL_MOTION_PID=`$!",
        "sleep 1",
        "sed -n '1,8p' /tmp/drm_kms_local_motion.log"
    ) | Set-Content -LiteralPath $deployCommands -Encoding ASCII

    & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port `
        -CommandFile $deployCommands `
        -LoginRoot `
        -Password root `
        -InitialReadSeconds 1 `
        -InterCommandDelayMilliseconds 500 `
        -FinalReadSeconds 2 `
        -OutputPath (Join-Path $OutDir "uart_deploy_start_local_motion.log")

    if (-not (Wait-Job $serverJob -Timeout 60)) {
        throw "receiver download did not reach the one-shot HTTP server"
    }
    Receive-Job $serverJob -Wait -AutoRemoveJob | Tee-Object -FilePath (Join-Path $outPath "one-shot-http-server.log")
    $serverJob = $null

    $deployLog = Get-Content -Raw -LiteralPath (Join-Path $outPath "uart_deploy_start_local_motion.log")
    if ($deployLog -notmatch "/tmp/drm_kms_udp_receiver: OK") {
        throw "receiver deploy sha marker missing"
    }
    if ($deployLog -match "DRM_BLOCKER|DRM_IOCTL|open drm") {
        throw "DRM/KMS local motion failed during startup; see uart_deploy_start_local_motion.log"
    }
    if ($deployLog -notmatch "VIDEO_DRM_LOCAL_MOTION_READY .*video_source=board-generated-textured-motion") {
        throw "local motion ready marker missing"
    }

    $captureOut = Join-Path $outPath "hdmi-motion-capture"
    Remove-Item -LiteralPath $captureOut -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $captureOut | Out-Null
    $captureStdout = Join-Path $captureOut "probe.out.log"
    $captureStderr = Join-Path $captureOut "probe.err.log"
    $captureArgs = @(
        ".\tools\probe_hdmi_motion_capture.py",
        "--out-dir", $captureOut,
        "--device", $CaptureDevice,
        "--backend", $CaptureBackend,
        "--width", "800",
        "--height", "600",
        "--frames", "$CaptureFrames",
        "--fps", "$CaptureFps",
        "--timeout-sec", "180"
    )
    $captureProcess = Start-Process -WindowStyle Hidden -FilePath python `
        -ArgumentList $captureArgs `
        -WorkingDirectory $repoRoot `
        -RedirectStandardOutput $captureStdout `
        -RedirectStandardError $captureStderr `
        -PassThru

    if (-not $captureProcess.WaitForExit(180000)) {
        Stop-Process -Id $captureProcess.Id -Force -ErrorAction SilentlyContinue
        throw "HDMI motion capture timed out"
    }
    $captureProcess.Refresh()
    $captureReport = Read-JsonFile (Join-Path $captureOut "mjpeg-stream-probe.json")
    if ([string]$captureReport.status -ne "pass") {
        throw "HDMI motion capture failed; see $captureStdout and $captureStderr"
    }
    $captureProcess = $null

    $afterCommands = Join-Path $outPath "uart_after_local_motion.commands"
    @(
        "cat /tmp/drm_kms_local_motion.log",
        "kill `$(pidof drm_kms_udp_receiver 2>/dev/null) 2>/dev/null || true"
    ) | Set-Content -LiteralPath $afterCommands -Encoding ASCII

    & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port `
        -CommandFile $afterCommands `
        -LoginRoot `
        -Password root `
        -InitialReadSeconds 1 `
        -InterCommandDelayMilliseconds 500 `
        -FinalReadSeconds 2 `
        -OutputPath (Join-Path $OutDir "uart_after_local_motion.log")

    $afterLog = Get-Content -Raw -LiteralPath (Join-Path $outPath "uart_after_local_motion.log")
    $readyMatch = [regex]::Match($afterLog, "VIDEO_DRM_LOCAL_MOTION_READY .*display_backend=(\S+) .*drm_device=(\S+) .*video_source=(\S+) .*fbdev_live_write_used=(\d+) .*motion_content_type=(\S+)")
    if ($readyMatch.Success) {
        $fields.display_backend = $readyMatch.Groups[1].Value
        $fields.drm_device = $readyMatch.Groups[2].Value
        $fields.video_source = $readyMatch.Groups[3].Value
        $fields.fbdev_live_write_used = [int]$readyMatch.Groups[4].Value
        $fields.motion_content_type = $readyMatch.Groups[5].Value
    }
    $dumbMatch = [regex]::Match($afterLog, "DRM_DUMB_BUFFERS count=(\d+)")
    if ($dumbMatch.Success) {
        $fields.drm_dumb_buffers = [int]$dumbMatch.Groups[1].Value
    }
    $fields.drm_page_flip_calls = [regex]::Matches($afterLog, "DRM_PAGE_FLIP_SUBMITTED frame_id=").Count
    $eventMatches = [regex]::Matches($afterLog, "DRM_PAGE_FLIP_EVENT frame_id=(\d+) event_count=(\d+) sequence=(\d+) tv_sec=(\d+) tv_usec=(\d+)")
    $fields.drm_vblank_flip_events = $eventMatches.Count
    $eventTimes = New-Object 'System.Collections.Generic.List[double]'
    foreach ($match in $eventMatches) {
        $eventTimes.Add(([double]$match.Groups[4].Value * 1000.0) + ([double]$match.Groups[5].Value / 1000.0))
    }
    if ($eventTimes.Count -ge 3) {
        $deltas = New-Object 'System.Collections.Generic.List[double]'
        for ($i = 1; $i -lt $eventTimes.Count; $i++) {
            $deltas.Add($eventTimes[$i] - $eventTimes[$i - 1])
        }
        $fields.frame_duration_stddev_ms = [Math]::Round((Get-StdDev -Values $deltas.ToArray()), 3)
    }
    $doneMatch = [regex]::Match($afterLog, "VIDEO_DRM_LOCAL_MOTION_DONE .*video_source=(\S+) .*fbdev_live_write_used=(\d+) .*generated_frames=(\d+) .*motion_content_type=(\S+) .*drm_dumb_buffers=(\d+) .*drm_page_flip_calls=(\d+) .*drm_vblank_flip_events=(\d+)")
    if ($doneMatch.Success) {
        $fields.video_source = $doneMatch.Groups[1].Value
        $fields.fbdev_live_write_used = [int]$doneMatch.Groups[2].Value
        $fields.generated_frames = [int]$doneMatch.Groups[3].Value
        $fields.motion_content_type = $doneMatch.Groups[4].Value
        $fields.drm_dumb_buffers = [int]$doneMatch.Groups[5].Value
        $fields.drm_page_flip_calls = [int]$doneMatch.Groups[6].Value
        $fields.drm_vblank_flip_events = [int]$doneMatch.Groups[7].Value
    }

    $validationDir = Join-Path $outPath "motion-tearing-validation"
    $validationJson = Join-Path $validationDir "motion-tearing-validation.json"
    & python (Join-Path $repoRoot "tools\validate_motion_tearing.py") `
        --mjpeg-report (Join-Path $captureOut "mjpeg-stream-probe.json") `
        --out-dir $validationDir `
        --result-json $validationJson `
        2>&1 | Tee-Object -FilePath (Join-Path $outPath "motion-tearing-validation.out.log")
    $tearing = Read-JsonFile $validationJson
    $fields.captured_motion_frames = [int]$tearing.captured_motion_frames
    $fields.tearing_frames = [int]$tearing.tearing_frames
    $fields.validator_status = [string]$tearing.validator_status

    $passCondition = (
        $fields.display_backend -eq "drm-kms" -and
        $fields.drm_device -eq "/dev/dri/card0" -and
        $fields.video_source -eq "board-generated-textured-motion" -and
        $fields.fbdev_live_write_used -eq 0 -and
        $fields.drm_dumb_buffers -eq 2 -and
        $fields.drm_page_flip_calls -eq 120 -and
        $fields.drm_vblank_flip_events -eq 120 -and
        $fields.generated_frames -eq 120 -and
        $fields.motion_content_type -eq "textured-motion" -and
        $fields.captured_motion_frames -ge 120 -and
        $fields.tearing_frames -eq 0 -and
        [double]$fields.frame_duration_stddev_ms -le 4.0 -and
        $fields.validator_status -eq "pass"
    )

    $summaryPath = Write-Summary -Status $(if ($passCondition) { "pass" } else { "fail" }) -FailureReason "" -Fields $fields
    $markerBits = "display_backend=$($fields.display_backend) drm_device=$($fields.drm_device) video_source=$($fields.video_source) fbdev_live_write_used=$($fields.fbdev_live_write_used) drm_dumb_buffers=$($fields.drm_dumb_buffers) drm_page_flip_calls=$($fields.drm_page_flip_calls) drm_vblank_flip_events=$($fields.drm_vblank_flip_events) generated_frames=$($fields.generated_frames) motion_content_type=$($fields.motion_content_type) captured_motion_frames=$($fields.captured_motion_frames) tearing_frames=$($fields.tearing_frames) frame_duration_stddev_ms=$($fields.frame_duration_stddev_ms) validator_status=$($fields.validator_status) summary=$summaryPath"
    if ($passCondition) {
        $marker = "DRM_KMS_LOCAL_MOTION_PACING_OK $markerBits"
        Set-Content -LiteralPath (Join-Path $outPath "drm-kms-local-motion-pacing.marker.txt") -Value $marker -Encoding ASCII
        Write-Host $marker
    } else {
        $marker = "DRM_KMS_LOCAL_MOTION_PACING_FAIL $markerBits"
        Set-Content -LiteralPath (Join-Path $outPath "drm-kms-local-motion-pacing.marker.txt") -Value $marker -Encoding ASCII
        throw $marker
    }
}
catch {
    $summaryPath = Write-Summary -Status "fail" -FailureReason $_.Exception.Message -Fields $fields
    $marker = "DRM_KMS_LOCAL_MOTION_PACING_FAIL reason=$($_.Exception.Message) summary=$summaryPath"
    Set-Content -LiteralPath (Join-Path $outPath "drm-kms-local-motion-pacing.marker.txt") -Value $marker -Encoding ASCII
    Write-Error $marker
    exit 1
}
finally {
    if ($captureProcess -and -not $captureProcess.HasExited) {
        Stop-Process -Id $captureProcess.Id -Force -ErrorAction SilentlyContinue
    }
    if ($serverJob) {
        Stop-Job $serverJob -ErrorAction SilentlyContinue
        Remove-Job $serverJob -Force -ErrorAction SilentlyContinue
    }
}
