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
    [int]$CaptureFrames = 90,
    [int]$CaptureSaveSamples = 6,
    [int]$Frames = 12,
    [double]$Fps = 2.0,
    [int]$InterPacketUs = 200,
    [string]$ControlFifo = "/tmp/video_ctl",
    [string]$OutDir = "build\dashboard-board-live-loop"
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

function Stop-StaleDemoSenders {
    $senders = Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -match "python" -and
            $_.CommandLine -match "send_demo_video_udp\.py"
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

function Invoke-DashboardAction {
    param(
        [string]$Url,
        [string]$Action,
        [int]$TimeoutSec
    )

    $body = @{ action = $Action } | ConvertTo-Json
    Invoke-RestMethod -Uri "$Url/api/action" -Method Post -ContentType "application/json" -Body $body -TimeoutSec $TimeoutSec
}

function Wait-DashboardCapture {
    param(
        [string]$Url,
        [int]$TimeoutSec
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSec)
    $lastState = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $lastState = Invoke-RestMethod -Uri "$Url/api/state" -TimeoutSec 5
        if ($lastState.output_preview.capture_status -eq "ok" -and $lastState.output_preview.image_exists) {
            return $lastState
        }
        if ($lastState.output_preview.capture_status -in @("failed", "timeout")) {
            throw "dashboard HDMI capture failed: $($lastState.output_preview.capture_last_error)"
        }
        Start-Sleep -Milliseconds 500
    }

    if ($lastState) {
        $lastState | ConvertTo-Json -Depth 12 | Write-Host
    }
    throw "dashboard HDMI capture did not complete within $TimeoutSec seconds"
}

function Test-DynamicSamples {
    param(
        [string]$CaptureDir,
        [string]$OutPath
    )

    $samples = Get-ChildItem -LiteralPath $CaptureDir -Filter "latest-sample-*.png" -ErrorAction SilentlyContinue |
        Sort-Object Name
    if ($samples.Count -lt 2) {
        throw "dynamic HDMI proof needs at least two saved samples"
    }

    $hashes = @()
    foreach ($sample in $samples) {
        $bytes = [System.IO.File]::ReadAllBytes($sample.FullName)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha.ComputeHash($bytes)
        }
        finally {
            $sha.Dispose()
        }
        $hashText = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
        $hashes += [pscustomobject]@{
            file = $sample.FullName
            sha256 = $hashText
        }
    }

    $hashes | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutPath "hdmi_dynamic_sample_hashes.json") -Encoding UTF8
    $unique = @($hashes.sha256 | Sort-Object -Unique)
    if ($unique.Count -lt 2) {
        throw "HDMI samples are static: only one unique sample hash"
    }

    return $unique.Count
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outPath = Join-Path $repoRoot $OutDir
New-Item -ItemType Directory -Force -Path $outPath | Out-Null

Stop-DashboardListener -Port $DashboardPort
Stop-StaleDemoSenders
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

try {
    Start-Sleep -Seconds 1

    $deployCommands = Join-Path $outPath "uart_deploy_start_receiver.commands"
    @(
        "ifconfig eth0 $BoardIp netmask 255.255.255.0 up",
        "kill `$(pidof fb_video_udp_receiver 2>/dev/null) 2>/dev/null || true",
        "rm -f /tmp/fb_video_udp_receiver /tmp/fb_video_udp_receiver.log $ControlFifo",
        "wget -q -O /tmp/fb_video_udp_receiver http://$($PcIp):$($HttpPort)/fb_video_udp_receiver",
        "echo '$receiverSha  /tmp/fb_video_udp_receiver' | sha256sum -c -",
        "chmod +x /tmp/fb_video_udp_receiver",
        "/tmp/fb_video_udp_receiver --port $UdpPort --frames $Frames --timeout-sec 180 --control-fifo $ControlFifo > /tmp/fb_video_udp_receiver.log 2>&1 & echo RECEIVER_PID=`$!",
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
        "--sender-payload", "1200",
        "--sender-inter-packet-us", "$InterPacketUs",
        "--uart-port", $Port,
        "--control-fifo", $ControlFifo,
        "--capture-device", $CaptureDevice,
        "--capture-backend", $CaptureBackend,
        "--capture-width", "800",
        "--capture-height", "600",
        "--capture-frames", "$CaptureFrames",
        "--capture-profile", "non-black",
        "--capture-save-samples", "$CaptureSaveSamples",
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

    $startResult = Invoke-DashboardAction -Url $dashboardUrl -Action "start-stream" -TimeoutSec 20
    $startResult | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outPath "dashboard_start_stream.json") -Encoding UTF8
    if ($startResult.detail -notmatch "HDMI_CAPTURE_SCHEDULED" -or
        $startResult.state.output_preview.capture_status -ne "running") {
        throw "dashboard start-stream did not schedule HDMI capture"
    }

    $captureState = Wait-DashboardCapture -Url $dashboardUrl -TimeoutSec 180
    $captureState | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outPath "dashboard_capture_done_state.json") -Encoding UTF8

    $afterCommands = Join-Path $outPath "uart_after_dashboard_stream.commands"
    @(
        "cat /tmp/fb_video_udp_receiver.log",
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
        -OutputPath (Join-Path $OutDir "uart_after_dashboard_stream.log")

    $afterLog = Get-Content -Raw -LiteralPath (Join-Path $outPath "uart_after_dashboard_stream.log")
    $writtenCount = ([regex]::Matches($afterLog, "VIDEO_UDP_FRAME_WRITTEN")).Count
    if ($writtenCount -lt 1 -or $afterLog -notmatch "VIDEO_UDP_RECEIVER_DONE frames=$Frames .*dropped=0") {
        throw "dashboard-driven receiver write/done markers missing"
    }

    $stopResult = Invoke-DashboardAction -Url $dashboardUrl -Action "stop-stream" -TimeoutSec 30
    $stopResult | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outPath "dashboard_stop_stream.json") -Encoding UTF8

    $finalState = Invoke-RestMethod -Uri "$dashboardUrl/api/state" -TimeoutSec 5
    $finalState | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outPath "dashboard_final_state.json") -Encoding UTF8

    $captureReport = Join-Path $outPath "hdmi-capture\latest-validation.json"
    if (-not (Test-Path -LiteralPath $captureReport)) {
        throw "dashboard HDMI capture report missing"
    }
    $captureJson = Get-Content -Raw -LiteralPath $captureReport | ConvertFrom-Json
    if ($captureJson.status -ne "pass" -or $captureJson.validation_profile -ne "non-black") {
        throw "dashboard HDMI capture was not non-black"
    }
    $uniqueSampleCount = Test-DynamicSamples -CaptureDir (Join-Path $outPath "hdmi-capture") -OutPath $outPath

    $marker = "DASHBOARD_BOARD_LIVE_LOOP_OK frames=$Frames written=$writtenCount dynamic_samples_unique=$uniqueSampleCount out=$outPath"
    Set-Content -LiteralPath (Join-Path $outPath "dashboard_board_live_loop.marker.txt") -Value $marker -Encoding ASCII
    Write-Host $marker
}
finally {
    if ($serverJob) {
        Stop-Job $serverJob -ErrorAction SilentlyContinue
        Remove-Job $serverJob -Force -ErrorAction SilentlyContinue
    }
}
