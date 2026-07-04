[CmdletBinding()]
param(
    [string]$BoardIp = "192.168.1.10",
    [string]$PcIp = "192.168.1.2",
    [string]$Port = "COM16",
    [int]$HttpPort = 8091,
    [int]$GstPort = 5011,
    [int]$OutputWidth = 800,
    [int]$OutputHeight = 600,
    [int]$SummaryInterval = 30,
    [string]$ProbeMode = "pl-probe",
    [string]$OutDir = "build\jpegpldec-pl-probe-and-profile",
    [string]$DashboardUrl = "http://127.0.0.1:8765"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outPath = Join-Path $repoRoot $OutDir
$pluginOut = Join-Path $outPath "plugin"
New-Item -ItemType Directory -Force -Path $outPath | Out-Null

function Invoke-UartCommands {
    param(
        [string[]]$Commands,
        [string]$Label,
        [int]$FinalReadSeconds = 3
    )

    $commandFile = Join-Path $outPath "uart-$Label.commands"
    $logFile = Join-Path $outPath "uart-$Label.log"
    $Commands | Set-Content -LiteralPath $commandFile -Encoding ASCII
    & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port `
        -CommandFile $commandFile `
        -LoginRoot `
        -Password root `
        -InitialReadSeconds 0 `
        -InterCommandDelayMilliseconds 400 `
        -FinalReadSeconds $FinalReadSeconds `
        -OutputPath (Join-Path $OutDir "uart-$Label.log") | Out-File -LiteralPath (Join-Path $outPath "uart-$Label.runner-output.log") -Encoding UTF8
    if (-not (Test-Path -LiteralPath $logFile)) {
        throw "UART log was not written: $logFile"
    }
    return $logFile
}

function Require-Text {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Label
    )
    $text = Get-Content -Raw -LiteralPath $Path
    if ($text -notmatch $Pattern) {
        throw "$Label missing in $Path"
    }
}

Write-Output "JPEGPLDEC_PL_PROBE_BUILD_START"
& (Join-Path $repoRoot "software\gstreamer\jpegpldec\build-wsl.ps1") -OutDir $pluginOut
if ($LASTEXITCODE -ne 0) {
    throw "jpegpldec build failed"
}

$plugin = Join-Path $pluginOut "libgstjpegpldec.so"
$shaFile = Join-Path $pluginOut "libgstjpegpldec.sha256.txt"
if (-not (Test-Path -LiteralPath $plugin) -or -not (Test-Path -LiteralPath $shaFile)) {
    throw "plugin artifact or sha256 file missing under $pluginOut"
}
$hash = ((Get-Content -LiteralPath $shaFile -TotalCount 1) -split "\s+")[0].ToLowerInvariant()

$http = Start-Process `
    -FilePath python `
    -ArgumentList @("-m", "http.server", "$HttpPort", "--bind", $PcIp) `
    -WorkingDirectory $pluginOut `
    -WindowStyle Hidden `
    -PassThru
try {
    Set-Content -LiteralPath (Join-Path $outPath "http-server.pid") -Value $http.Id -Encoding ASCII
    Write-Output "JPEGPLDEC_PL_PROBE_HTTP_SERVER pid=$($http.Id) port=$HttpPort"

    $deployLog = Invoke-UartCommands -Label "deploy-inspect" -Commands @(
        "ifconfig eth0 $BoardIp netmask 255.255.255.0 up",
        "mkdir -p /tmp/gst-plugins",
        "rm -f /tmp/gst-plugins/libgstjpegpldec.so /tmp/gst-registry-jpegpldec-profile.bin",
        "wget -O /tmp/gst-plugins/libgstjpegpldec.so http://$($PcIp):$($HttpPort)/libgstjpegpldec.so",
        "sha256sum /tmp/gst-plugins/libgstjpegpldec.so",
        "GST_PLUGIN_PATH=/tmp/gst-plugins GST_REGISTRY=/tmp/gst-registry-jpegpldec-profile.bin gst-inspect-1.0 jpegpldec | sed -n '1,140p'",
        "echo JPEGPLDEC_DEPLOY_INSPECT_DONE"
    )
    Require-Text -Path $deployLog -Pattern $hash -Label "deployed plugin sha256"
    Require-Text -Path $deployLog -Pattern "probe-mode" -Label "probe-mode property"
    Require-Text -Path $deployLog -Pattern "pl-base" -Label "pl-base property"
    Require-Text -Path $deployLog -Pattern "JPEGPLDEC_DEPLOY_INSPECT_DONE" -Label "deploy marker"

    $caps = "application/x-rtp, media=(string)video, clock-rate=(int)90000, encoding-name=(string)JPEG, payload=(int)26"
    $pipeline = "GST_PLUGIN_PATH=/tmp/gst-plugins GST_REGISTRY=/tmp/gst-registry-jpegpldec-profile.bin nohup gst-launch-1.0 -v udpsrc port=$GstPort caps=`"$caps`" ! rtpjitterbuffer latency=100 drop-on-latency=true ! rtpjpegdepay ! jpegpldec probe-mode=$ProbeMode summary-interval=$SummaryInterval ! videoconvert ! videoscale ! video/x-raw,format=BGR,width=$OutputWidth,height=$OutputHeight ! fbdevsink device=/dev/fb0 sync=false > /tmp/gst_jpegpldec_profile.log 2>&1 & echo `$! > /tmp/gst_jpegpldec_profile.pid"

    $startLog = Invoke-UartCommands -Label "start-profile" -FinalReadSeconds 3 -Commands @(
        "killall gst-launch-1.0 2>/dev/null || true",
        "rm -f /tmp/gst_jpegpldec_profile.log /tmp/gst_jpegpldec_profile.pid",
        "/tmp/pip_effect_ctl --preset bottom-right >/tmp/jpegpldec_pip_position.log 2>&1 || true",
        "cat /tmp/jpegpldec_pip_position.log 2>/dev/null || true",
        "setterm -cursor off > /dev/`$(cat /sys/class/tty/tty0/active) 2>/dev/null || true",
        $pipeline,
        "sleep 8",
        "echo JPEGPLDEC_PROFILE_RECEIVER_STARTED pid=`$(cat /tmp/gst_jpegpldec_profile.pid 2>/dev/null) log=/tmp/gst_jpegpldec_profile.log",
        "ps | grep gst-launch | grep -v grep || true",
        "tail -n 160 /tmp/gst_jpegpldec_profile.log",
        "echo JPEGPLDEC_PROFILE_RECEIVER_LOG_TAIL_DONE"
    )
    Require-Text -Path $startLog -Pattern "JPEGPLDEC_PROFILE_RECEIVER_STARTED" -Label "receiver start marker"
    Require-Text -Path $startLog -Pattern "JPEGPLDEC_PROFILE frames=" -Label "profile marker"
    if ($ProbeMode -match "pl") {
        Require-Text -Path $startLog -Pattern "JPEGPLDEC_PL_PROBE" -Label "PL probe marker"
    }
    if ($ProbeMode -match "buffer") {
        Require-Text -Path $startLog -Pattern "JPEGPLDEC_BUFFER_PROBE.*result=pass" -Label "buffer probe marker"
    }

    $probeOut = Join-Path $outPath "dashboard-output-mjpeg-probe"
    try {
        & python (Join-Path $repoRoot "tools\probe_mjpeg_stream.py") `
            "$DashboardUrl/api/output-stream.mjpeg" `
            --out-dir $probeOut `
            --frames 60 `
            --min-unique 5 `
            --timeout-sec 20
        if ($LASTEXITCODE -ne 0) {
            throw "output mjpeg probe exited $LASTEXITCODE"
        }
        $mjpegStatus = "pass"
    } catch {
        $mjpegStatus = "skipped_or_failed: $($_.Exception.Message)"
    }

    if ($ProbeMode -match "buffer" -and $mjpegStatus -eq "pass") {
        & python (Join-Path $repoRoot "tools\validate_jpegpldec_buffer_marker.py") `
            $probeOut `
            --out (Join-Path $outPath "buffer-marker-validation.json") `
            --min-frames 60 `
            --min-pass-frames 50
        if ($LASTEXITCODE -ne 0) {
            throw "buffer marker validation failed"
        }
        $bufferMarkerStatus = "pass"
    } else {
        $bufferMarkerStatus = "not-run"
    }

    $summary = [PSCustomObject]@{
        cycle = if ($ProbeMode -match "buffer") { "jpegpldec-pl-buffer-datapath-probe" } else { "jpegpldec-pl-probe-and-profile" }
        plugin_sha256 = $hash
        probe_mode = $ProbeMode
        deployed_plugin = "/tmp/gst-plugins/libgstjpegpldec.so"
        receiver_log = "/tmp/gst_jpegpldec_profile.log"
        deploy_log = $deployLog
        start_log = $startLog
        dashboard_output_probe = $mjpegStatus
        buffer_marker_validation = $bufferMarkerStatus
        result = "pass"
    }
    $summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outPath "summary.json") -Encoding UTF8
    Write-Output "JPEGPLDEC_PL_PROBE_OK summary=$(Join-Path $outPath "summary.json")"
} finally {
    if ($http -and -not $http.HasExited) {
        Stop-Process -Id $http.Id -Force -ErrorAction SilentlyContinue
    }
}
