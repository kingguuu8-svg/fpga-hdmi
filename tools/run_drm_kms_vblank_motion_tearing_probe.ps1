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
    [double]$StreamFps = 30.0,
    [int]$MjpegFrames = 120,
    [int]$MjpegMinUnique = 8,
    [int]$Frames = 60,
    [int]$ValidationStartFrameId = 100,
    [double]$Fps = 15.0,
    [int]$UdpPayload = 1200,
    [int]$InterPacketUs = 0,
    [double]$PacketWindowFraction = 0.85,
    [string]$OutDir = "build\drm-kms-vblank-motion-tearing"
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

function Stop-StaleProcesses {
    $stale = Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -match "python" -and
            ($_.CommandLine -match "send_motion_video_udp\.py" -or
             $_.CommandLine -match "probe_mjpeg_stream\.py")
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
    $summaryPath = Join-Path $script:outPath "drm-kms-vblank-motion-tearing-summary.json"
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    return $summaryPath
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outPath = Join-Path $repoRoot $OutDir
$script:outPath = $outPath
New-Item -ItemType Directory -Force -Path $outPath | Out-Null

$dashboardProcess = $null
$mjpegProcess = $null
$serverJob = $null
$fields = @{
    display_backend = "unknown"
    drm_device = "/dev/dri/card0"
    fbdev_live_write_used = 1
    drm_dumb_buffers = 0
    drm_page_flip_calls = 0
    drm_vblank_flip_events = 0
    sent_frames = 0
    receiver_written_frames = 0
    receiver_dropped_packets = -1
    motion_content_type = "unknown"
    captured_motion_frames = 0
    tearing_validator_calibrated = 0
    tearing_frames = -1
    frame_duration_stddev_ms = [double]::PositiveInfinity
    validator_status = "not-run"
    out = $outPath
}

try {
    Stop-DashboardListener -Port $DashboardPort
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
    $deployCommands = Join-Path $outPath "uart_deploy_start_drm_receiver.commands"
    @(
        "ifconfig eth0 $BoardIp netmask 255.255.255.0 up",
        "sysctl -w net.core.rmem_max=33554432 2>/dev/null || true",
        "sysctl -w net.core.rmem_default=33554432 2>/dev/null || true",
        "kill `$(pidof drm_kms_udp_receiver 2>/dev/null) 2>/dev/null || true",
        "kill `$(pidof fb_video_udp_receiver 2>/dev/null) 2>/dev/null || true",
        "rm -f /tmp/drm_kms_udp_receiver /tmp/drm_kms_udp_receiver.log",
        "wget -q -O /tmp/drm_kms_udp_receiver http://$($PcIp):$($HttpPort)/drm_kms_udp_receiver",
        "echo '$receiverSha  /tmp/drm_kms_udp_receiver' | sha256sum -c -",
        "chmod +x /tmp/drm_kms_udp_receiver",
        "/tmp/drm_kms_udp_receiver --drm /dev/dri/card0 --port $UdpPort --frames $Frames --timeout-sec 180 > /tmp/drm_kms_udp_receiver.log 2>&1 & echo RECEIVER_PID=`$!",
        "sleep 2",
        "cat /tmp/drm_kms_udp_receiver.log"
    ) | Set-Content -LiteralPath $deployCommands -Encoding ASCII

    & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port `
        -CommandFile $deployCommands `
        -LoginRoot `
        -Password root `
        -InitialReadSeconds 1 `
        -InterCommandDelayMilliseconds 500 `
        -FinalReadSeconds 2 `
        -OutputPath (Join-Path $OutDir "uart_deploy_start_drm_receiver.log")

    if (-not (Wait-Job $serverJob -Timeout 60)) {
        throw "receiver download did not reach the one-shot HTTP server"
    }
    Receive-Job $serverJob -Wait -AutoRemoveJob | Tee-Object -FilePath (Join-Path $outPath "one-shot-http-server.log")
    $serverJob = $null

    $deployLog = Get-Content -Raw -LiteralPath (Join-Path $outPath "uart_deploy_start_drm_receiver.log")
    if ($deployLog -notmatch "/tmp/drm_kms_udp_receiver: OK") {
        throw "receiver deploy sha marker missing"
    }
    if ($deployLog -match "DRM_BLOCKER|DRM_IOCTL|open drm|no connected connector") {
        throw "DRM/KMS receiver failed during startup; see uart_deploy_start_drm_receiver.log"
    }
    if ($deployLog -notmatch "VIDEO_UDP_DRM_RECEIVER_READY .*display_backend=drm-kms") {
        throw "DRM receiver ready marker missing"
    }

    $calibrationDir = Join-Path $outPath "validator-calibration"
    & python (Join-Path $repoRoot "tools\validate_motion_tearing.py") `
        --calibration `
        --out-dir $calibrationDir `
        2>&1 | Tee-Object -FilePath (Join-Path $outPath "validator-calibration.out.log")
    if ($LASTEXITCODE -ne 0) {
        throw "motion tearing validator calibration failed"
    }
    $calibration = Read-JsonFile (Join-Path $calibrationDir "motion-tearing-calibration.json")
    $fields.tearing_validator_calibrated = [int]$calibration.tearing_validator_calibrated

    $mjpegOut = Join-Path $outPath "mjpeg-return"
    Remove-Item -LiteralPath $mjpegOut -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $mjpegOut | Out-Null
    $mjpegStdout = Join-Path $mjpegOut "probe.out.log"
    $mjpegStderr = Join-Path $mjpegOut "probe.err.log"
    $mjpegArgs = @(
        ".\tools\probe_hdmi_motion_capture.py",
        "--out-dir", $mjpegOut,
        "--device", $CaptureDevice,
        "--backend", $CaptureBackend,
        "--width", "800",
        "--height", "600",
        "--frames", "$MjpegFrames",
        "--fps", "$StreamFps",
        "--timeout-sec", "180"
    )
    $mjpegProcess = Start-Process -WindowStyle Hidden -FilePath python `
        -ArgumentList $mjpegArgs `
        -WorkingDirectory $repoRoot `
        -RedirectStandardOutput $mjpegStdout `
        -RedirectStandardError $mjpegStderr `
        -PassThru

    Start-Sleep -Milliseconds 500

    $senderOut = Join-Path $outPath "sender"
    New-Item -ItemType Directory -Force -Path $senderOut | Out-Null
    & python (Join-Path $repoRoot "tools\send_motion_video_udp.py") `
        $BoardIp `
        --port $UdpPort `
        --width 800 `
        --height 600 `
        --fps $Fps `
        --frames $Frames `
        --start-frame-id $ValidationStartFrameId `
        --payload $UdpPayload `
        --inter-packet-us $InterPacketUs `
        --packet-window-fraction $PacketWindowFraction `
        --out-dir $senderOut `
        2>&1 | Tee-Object -FilePath (Join-Path $outPath "sender.out.log")
    if ($LASTEXITCODE -ne 0) {
        throw "motion sender failed"
    }

    if (-not $mjpegProcess.WaitForExit(180000)) {
        Stop-Process -Id $mjpegProcess.Id -Force -ErrorAction SilentlyContinue
        throw "MJPEG probe timed out"
    }
    $mjpegProcess.Refresh()
    $mjpegReport = Read-JsonFile (Join-Path $mjpegOut "mjpeg-stream-probe.json")
    if ([string]$mjpegReport.status -ne "pass") {
        throw "MJPEG probe failed; see $mjpegStdout and $mjpegStderr"
    }
    $mjpegProcess = $null

    $afterCommands = Join-Path $outPath "uart_after_drm_receiver.commands"
    @(
        "cat /tmp/drm_kms_udp_receiver.log",
        "kill `$(pidof drm_kms_udp_receiver 2>/dev/null) 2>/dev/null || true",
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
        -OutputPath (Join-Path $OutDir "uart_after_drm_receiver.log")

    $afterLog = Get-Content -Raw -LiteralPath (Join-Path $outPath "uart_after_drm_receiver.log")
    $senderJson = Read-JsonFile (Join-Path $senderOut "sender-trace.json")
    $fields.sent_frames = [int]$senderJson.frames
    $fields.motion_content_type = [string]$senderJson.motion_content_type

    $readyMatch = [regex]::Match($afterLog, "VIDEO_UDP_DRM_RECEIVER_READY .*display_backend=(\S+) .*drm_device=(\S+) .*fbdev_live_write_used=(\d+) .*motion_content_type=(\S+)")
    if ($readyMatch.Success) {
        $fields.display_backend = $readyMatch.Groups[1].Value
        $fields.drm_device = $readyMatch.Groups[2].Value
        $fields.fbdev_live_write_used = [int]$readyMatch.Groups[3].Value
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

    $doneMatch = [regex]::Match($afterLog, "VIDEO_UDP_DRM_RECEIVER_DONE .*frames=(\d+) .*dropped=(\d+) .*drm_dumb_buffers=(\d+) .*drm_page_flip_calls=(\d+) .*drm_vblank_flip_events=(\d+)")
    if ($doneMatch.Success) {
        $fields.receiver_written_frames = [int]$doneMatch.Groups[1].Value
        $fields.receiver_dropped_packets = [int]$doneMatch.Groups[2].Value
        $fields.drm_dumb_buffers = [int]$doneMatch.Groups[3].Value
        $fields.drm_page_flip_calls = [int]$doneMatch.Groups[4].Value
        $fields.drm_vblank_flip_events = [int]$doneMatch.Groups[5].Value
    }

    $validationDir = Join-Path $outPath "motion-tearing-validation"
    $validationJson = Join-Path $validationDir "motion-tearing-validation.json"
    & python (Join-Path $repoRoot "tools\validate_motion_tearing.py") `
        --mjpeg-report (Join-Path $mjpegOut "mjpeg-stream-probe.json") `
        --out-dir $validationDir `
        --result-json $validationJson `
        2>&1 | Tee-Object -FilePath (Join-Path $outPath "motion-tearing-validation.out.log")
    if ($LASTEXITCODE -ne 0) {
        $fields.validator_status = "fail"
    } else {
        $fields.validator_status = "pass"
    }
    $tearing = Read-JsonFile $validationJson
    $fields.captured_motion_frames = [int]$tearing.captured_motion_frames
    $fields.tearing_frames = [int]$tearing.tearing_frames
    $fields.validator_status = [string]$tearing.validator_status

    $passCondition = (
        $fields.display_backend -eq "drm-kms" -and
        $fields.drm_device -eq "/dev/dri/card0" -and
        $fields.fbdev_live_write_used -eq 0 -and
        $fields.drm_dumb_buffers -eq 2 -and
        $fields.drm_page_flip_calls -eq 60 -and
        $fields.drm_vblank_flip_events -eq 60 -and
        $fields.sent_frames -eq 60 -and
        $fields.receiver_written_frames -eq 60 -and
        $fields.receiver_dropped_packets -eq 0 -and
        $fields.motion_content_type -eq "textured-motion" -and
        $fields.captured_motion_frames -ge 60 -and
        $fields.tearing_validator_calibrated -eq 1 -and
        $fields.tearing_frames -eq 0 -and
        [double]$fields.frame_duration_stddev_ms -le 4.0 -and
        $fields.validator_status -eq "pass"
    )

    $summaryPath = Write-Summary -Status $(if ($passCondition) { "pass" } else { "fail" }) -FailureReason "" -Fields $fields
    $markerBits = "display_backend=$($fields.display_backend) drm_device=$($fields.drm_device) fbdev_live_write_used=$($fields.fbdev_live_write_used) drm_dumb_buffers=$($fields.drm_dumb_buffers) drm_page_flip_calls=$($fields.drm_page_flip_calls) drm_vblank_flip_events=$($fields.drm_vblank_flip_events) sent_frames=$($fields.sent_frames) receiver_written_frames=$($fields.receiver_written_frames) receiver_dropped_packets=$($fields.receiver_dropped_packets) motion_content_type=$($fields.motion_content_type) captured_motion_frames=$($fields.captured_motion_frames) tearing_validator_calibrated=$($fields.tearing_validator_calibrated) tearing_frames=$($fields.tearing_frames) frame_duration_stddev_ms=$($fields.frame_duration_stddev_ms) validator_status=$($fields.validator_status) summary=$summaryPath"
    if ($passCondition) {
        $marker = "DRM_KMS_VBLANK_MOTION_TEARING_OK $markerBits"
        Set-Content -LiteralPath (Join-Path $outPath "drm-kms-vblank-motion-tearing.marker.txt") -Value $marker -Encoding ASCII
        Write-Host $marker
    } else {
        $marker = "DRM_KMS_VBLANK_MOTION_TEARING_FAIL $markerBits"
        Set-Content -LiteralPath (Join-Path $outPath "drm-kms-vblank-motion-tearing.marker.txt") -Value $marker -Encoding ASCII
        throw $marker
    }
}
catch {
    $summaryPath = Write-Summary -Status "fail" -FailureReason $_.Exception.Message -Fields $fields
    $marker = "DRM_KMS_VBLANK_MOTION_TEARING_FAIL reason=$($_.Exception.Message) summary=$summaryPath"
    Set-Content -LiteralPath (Join-Path $outPath "drm-kms-vblank-motion-tearing.marker.txt") -Value $marker -Encoding ASCII
    Write-Error $marker
    exit 1
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
