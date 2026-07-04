[CmdletBinding()]
param(
    [string]$BoardIp = "192.168.1.10",
    [string]$PcIp = "192.168.1.2",
    [string]$Port = "COM16",
    [int]$GstPort = 5011,
    [int[]]$FpsList = @(5, 10, 15, 30),
    [int]$DurationSec = 8,
    [int]$InputWidth = 320,
    [int]$InputHeight = 240,
    [int]$OutputWidth = 800,
    [int]$OutputHeight = 600,
    [int]$JpegQuality = 90,
    [string]$CondaEnv = "build\conda-gstreamer-pc",
    [string]$OutDir = "build\video-bottleneck-probe",
    [switch]$RunRawDirectCopy
)

$ErrorActionPreference = "Stop"

function Invoke-UartCommands {
    param(
        [string[]]$Commands,
        [string]$Label,
        [int]$FinalReadSeconds = 2
    )

    $commandFile = Join-Path $outPath "uart-$Label.commands"
    $logFile = Join-Path $outPath "uart-$Label.log"
    $Commands | Set-Content -LiteralPath $commandFile -Encoding ASCII
    $runnerOutput = & (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
        -Port $Port `
        -CommandFile $commandFile `
        -LoginRoot `
        -Password root `
        -InitialReadSeconds 0 `
        -InterCommandDelayMilliseconds 250 `
        -FinalReadSeconds $FinalReadSeconds `
        -OutputPath (Join-Path $OutDir "uart-$Label.log")
    if ($runnerOutput) {
        $runnerOutput | Set-Content -LiteralPath (Join-Path $outPath "uart-$Label.runner-output.log") -Encoding UTF8
    }
    if ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $logFile)) {
        throw "UART command failed for $Label and no log was written"
    }
    return $logFile
}

function Stop-StalePcGst {
    $processes = Get-CimInstance Win32_Process |
        Where-Object {
            ($_.Name -match "gst-launch|conda|python") -and
            ($_.CommandLine -match "gst-launch-1\.0" -or
             $_.CommandLine -match "send_unified_test_video_udp\.py")
        }
    foreach ($process in $processes) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Get-GstCaps {
    return "application/x-rtp, media=(string)video, clock-rate=(int)90000, encoding-name=(string)JPEG, payload=(int)26"
}

function Get-BoardPipeline {
    param([string]$Sink)

    $caps = Get-GstCaps
    if ($Sink -eq "fakesink") {
        $sinkSpec = "fakesink sync=false"
    } elseif ($Sink -eq "fbdevsink") {
        $sinkSpec = "fbdevsink device=/dev/fb0 sync=false"
    } else {
        throw "unknown sink $Sink"
    }

    return "gst-launch-1.0 -v udpsrc port=$GstPort caps=`"$caps`" ! rtpjitterbuffer latency=100 drop-on-latency=true ! rtpjpegdepay ! jpegdec ! videoconvert ! videoscale ! video/x-raw,format=BGR,width=$OutputWidth,height=$OutputHeight ! fpsdisplaysink text-overlay=false video-sink=`"$sinkSpec`" sync=false"
}

function Start-BoardReceiver {
    param(
        [string]$CaseName,
        [string]$Sink
    )

    $pipeline = Get-BoardPipeline -Sink $Sink
    $commands = @(
        "ifconfig eth0 $BoardIp netmask 255.255.255.0 up",
        "killall gst-launch-1.0 2>/dev/null || true",
        "rm -f /tmp/$CaseName.*",
        "setterm -cursor off > /dev/`$(cat /sys/class/tty/tty0/active) 2>/dev/null || true",
        "nohup sh -c '$pipeline' > /tmp/$CaseName.gst.log 2>&1 & echo `$! > /tmp/$CaseName.pid",
        "sleep 1",
        "pid=`$(cat /tmp/$CaseName.pid 2>/dev/null); echo GST_BENCH_RECEIVER_STARTED case=$CaseName sink=$Sink pid=`$pid",
        "cat /proc/stat | head -n 1 > /tmp/$CaseName.cpu_start",
        "cat /proc/`$pid/stat > /tmp/$CaseName.proc_start 2>/dev/null || true",
        "getconf CLK_TCK > /tmp/$CaseName.clk_tck 2>/dev/null || echo 100 > /tmp/$CaseName.clk_tck",
        "grep -c '^processor' /proc/cpuinfo > /tmp/$CaseName.cpu_count 2>/dev/null || echo 2 > /tmp/$CaseName.cpu_count",
        "true"
    )
    Invoke-UartCommands -Commands $commands -Label "start-$CaseName" | Out-Null
}

function Stop-BoardReceiver {
    param([string]$CaseName)

    $commands = @(
        "pid=`$(cat /tmp/$CaseName.pid 2>/dev/null); echo GST_BENCH_STOPPING case=$CaseName pid=`$pid",
        "cat /proc/stat | head -n 1 > /tmp/$CaseName.cpu_end",
        "cat /proc/`$pid/stat > /tmp/$CaseName.proc_end 2>/dev/null || true",
        "kill `$pid 2>/dev/null || true",
        "sleep 1",
        "cat /tmp/$CaseName.cpu_start 2>/dev/null || true",
        "cat /tmp/$CaseName.cpu_end 2>/dev/null || true",
        "echo PROC_START; cat /tmp/$CaseName.proc_start 2>/dev/null || true",
        "echo PROC_END; cat /tmp/$CaseName.proc_end 2>/dev/null || true",
        "echo CLK_TCK; cat /tmp/$CaseName.clk_tck 2>/dev/null || true",
        "echo CPU_COUNT; cat /tmp/$CaseName.cpu_count 2>/dev/null || true",
        "echo GST_LOG_TAIL; tail -n 160 /tmp/$CaseName.gst.log 2>/dev/null || true",
        "killall gst-launch-1.0 2>/dev/null || true"
    )
    return Invoke-UartCommands -Commands $commands -Label "stop-$CaseName" -FinalReadSeconds 3
}

function Invoke-PcJpegSender {
    param(
        [int]$Fps,
        [int]$Frames,
        [string]$CaseName
    )

    $condaPath = Join-Path $repoRoot $CondaEnv
    $outLog = Join-Path $outPath "$CaseName.pc-gst.out.log"
    $errLog = Join-Path $outPath "$CaseName.pc-gst.err.log"
    $args = @(
        "run", "-p", $condaPath,
        "gst-launch-1.0", "-v",
        "videotestsrc", "num-buffers=$Frames", "is-live=true", "pattern=ball", "motion=sweep", "animation-mode=wall-time", "background-color=0xff14354a", "foreground-color=0xffffd166",
        "!", "video/x-raw,format=RGB,width=$InputWidth,height=$InputHeight,framerate=$Fps/1",
        "!", "videoconvert",
        "!", "video/x-raw,format=I420",
        "!", "jpegenc", "quality=$JpegQuality",
        "!", "rtpjpegpay", "pt=26", "mtu=1200",
        "!", "udpsink", "host=$BoardIp", "port=$GstPort", "sync=false", "async=false"
    )

    $started = Get-Date
    $process = Start-Process -FilePath "conda" `
        -ArgumentList $args `
        -WorkingDirectory $repoRoot `
        -NoNewWindow `
        -RedirectStandardOutput $outLog `
        -RedirectStandardError $errLog `
        -PassThru
    $timeoutSec = [Math]::Max(20, [int]([Math]::Ceiling(($Frames / [Math]::Max(1, $Fps)) + 15)))
    if (-not $process.WaitForExit($timeoutSec * 1000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "PC GStreamer sender timed out for $CaseName"
    }
    $process.Refresh()
    $ended = Get-Date
    return [PSCustomObject]@{
        exit_code = $process.ExitCode
        elapsed_s = [Math]::Round(($ended - $started).TotalSeconds, 3)
        stdout = $outLog
        stderr = $errLog
    }
}

function Get-LastFpsDisplay {
    param([string]$Text)

    $matches = [regex]::Matches($Text, "rendered:\s*(\d+),\s*dropped:\s*(\d+),\s*current:\s*([0-9.]+),\s*average:\s*([0-9.]+)")
    if ($matches.Count -eq 0) {
        return $null
    }
    $match = $matches[$matches.Count - 1]
    return [PSCustomObject]@{
        rendered = [int]$match.Groups[1].Value
        dropped = [int]$match.Groups[2].Value
        current_fps = [double]$match.Groups[3].Value
        average_fps = [double]$match.Groups[4].Value
    }
}

function Get-ProcCpuPercent {
    param([string]$Text)

    $cpuLines = [regex]::Matches($Text, "(?m)^cpu\s+(.+)$")
    $procStart = [regex]::Match($Text, "(?s)PROC_START\s*\r?\n(.+?)\r?\nPROC_END")
    $procEnd = [regex]::Match($Text, "(?s)PROC_END\s*\r?\n(.+?)\r?\nCLK_TCK")
    $clk = [regex]::Match($Text, "(?s)CLK_TCK\s*\r?\n(\d+)")
    $cpus = [regex]::Match($Text, "(?s)CPU_COUNT\s*\r?\n(\d+)")
    if ($cpuLines.Count -lt 2 -or -not $procStart.Success -or -not $procEnd.Success -or -not $clk.Success -or -not $cpus.Success) {
        return $null
    }

    $startCpu = @($cpuLines[0].Groups[1].Value.Trim() -split "\s+" | ForEach-Object { [double]$_ })
    $endCpu = @($cpuLines[$cpuLines.Count - 1].Groups[1].Value.Trim() -split "\s+" | ForEach-Object { [double]$_ })
    $totalStart = ($startCpu | Measure-Object -Sum).Sum
    $totalEnd = ($endCpu | Measure-Object -Sum).Sum
    $totalDelta = $totalEnd - $totalStart
    if ($totalDelta -le 0) {
        return $null
    }

    $startFields = @($procStart.Groups[1].Value.Trim() -split "\s+")
    $endFields = @($procEnd.Groups[1].Value.Trim() -split "\s+")
    if ($startFields.Count -lt 15 -or $endFields.Count -lt 15) {
        return $null
    }
    $procStartTicks = [double]$startFields[13] + [double]$startFields[14]
    $procEndTicks = [double]$endFields[13] + [double]$endFields[14]
    $procDelta = $procEndTicks - $procStartTicks
    $cpuCount = [double]$cpus.Groups[1].Value
    return [Math]::Round(($procDelta / $totalDelta) * $cpuCount * 100.0, 2)
}

function Invoke-JpegCase {
    param(
        [string]$Sink,
        [int]$Fps
    )

    $frames = [Math]::Max(1, $Fps * $DurationSec)
    $caseName = "jpeg-$Sink-${Fps}fps"
    Start-BoardReceiver -CaseName $caseName -Sink $Sink
    Start-Sleep -Seconds 1
    $sender = Invoke-PcJpegSender -Fps $Fps -Frames $frames -CaseName $caseName
    Start-Sleep -Seconds 1
    $stopLog = Stop-BoardReceiver -CaseName $caseName
    $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $stopLog).Path)
    $fpsInfo = Get-LastFpsDisplay -Text $text
    $cpu = Get-ProcCpuPercent -Text $text
    $received = $null
    $dropped = $null
    $avgFps = $null
    if ($null -ne $fpsInfo) {
        $received = $fpsInfo.rendered
        $dropped = $fpsInfo.dropped
        $avgFps = $fpsInfo.average_fps
    }

    return [PSCustomObject]@{
        case = $caseName
        route = "rtp-jpeg-to-$Sink"
        input = "${InputWidth}x${InputHeight}@${Fps}"
        output = "${OutputWidth}x${OutputHeight}"
        requested_fps = $Fps
        requested_frames = $frames
        pc_sender_exit_code = $sender.exit_code
        pc_sender_elapsed_s = $sender.elapsed_s
        board_rendered = $received
        board_dropped = $dropped
        board_average_fps = $avgFps
        board_gst_cpu_percent = $cpu
        board_log = $stopLog
        pc_stdout = $sender.stdout
        pc_stderr = $sender.stderr
        status = if ($null -ne $fpsInfo) { "measured" } else { "incomplete" }
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outPath = Join-Path $repoRoot $OutDir
New-Item -ItemType Directory -Force -Path $outPath | Out-Null
Stop-StalePcGst
Invoke-UartCommands -Commands @("killall gst-launch-1.0 2>/dev/null || true", "echo GST_BENCH_CLEAN_START") -Label "clean-start" | Out-Null

$results = @()
$rawReference = [PSCustomObject]@{
    route = "raw-direct-copy-reference"
    input = "800x600 framebuffer-native 24bpp"
    requested_fps = 15
    source = "docs/reports/linux-net-to-hdmi-direct-copy.md"
    result = "previously verified: sent_frames=30 receiver_written_frames=30 receiver_dropped_packets=0 trace_matched_frames=30 trace_max_latency_ms=62.382"
}

if ($RunRawDirectCopy) {
    $rawOut = Join-Path $OutDir "raw-direct-copy"
    & (Join-Path $repoRoot "tools\run_linux_net_to_hdmi_direct_copy_probe.ps1") -OutDir $rawOut
    if ($LASTEXITCODE -ne 0) {
        throw "raw direct-copy probe failed"
    }
    $rawReference = [PSCustomObject]@{
        route = "raw-direct-copy-live"
        input = "800x600 framebuffer-native 24bpp"
        requested_fps = 15
        out_dir = $rawOut
        result = "live probe completed"
    }
}

foreach ($sink in @("fakesink", "fbdevsink")) {
    foreach ($fps in $FpsList) {
        $results += Invoke-JpegCase -Sink $sink -Fps $fps
    }
}

$summary = [PSCustomObject]@{
    date = (Get-Date).ToString("s")
    board_ip = $BoardIp
    gst_port = $GstPort
    jpeg_input = "${InputWidth}x${InputHeight}"
    jpeg_output = "${OutputWidth}x${OutputHeight}"
    jpeg_quality = $JpegQuality
    duration_sec = $DurationSec
    raw_direct_copy = $rawReference
    jpeg_cases = $results
}

$summaryPath = Join-Path $outPath "video-bottleneck-summary.json"
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$fakesinkMax = ($results | Where-Object { $_.route -eq "rtp-jpeg-to-fakesink" -and $_.status -eq "measured" } | Sort-Object board_average_fps -Descending | Select-Object -First 1)
$fbdevMax = ($results | Where-Object { $_.route -eq "rtp-jpeg-to-fbdevsink" -and $_.status -eq "measured" } | Sort-Object board_average_fps -Descending | Select-Object -First 1)

$marker = "VIDEO_BOTTLENECK_PROBE_OK fakesink_best_fps=$($fakesinkMax.board_average_fps) fbdevsink_best_fps=$($fbdevMax.board_average_fps) report=$summaryPath"
$marker | Tee-Object -FilePath (Join-Path $outPath "video-bottleneck.marker.txt")
