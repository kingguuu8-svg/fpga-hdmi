[CmdletBinding()]
param(
    [string]$Distro = "Ubuntu-22.04",
    [string]$Vivado = "/opt/Xilinx/Vivado/2018.3/bin/vivado",
    [string]$OutDir = "build\jpeg-pl-decoder-qualification"
)

$ErrorActionPreference = "Stop"

function Convert-ToWslPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full -notmatch "^([A-Za-z]):\\(.*)$") {
        throw "Cannot convert non-drive path to WSL path: $full"
    }
    $drive = $matches[1].ToLowerInvariant()
    $rest = $matches[2] -replace "\\", "/"
    return "/mnt/$drive/$rest"
}

function Invoke-VivadoBatch {
    param(
        [Parameter(Mandatory = $true)][string]$Tcl,
        [Parameter(Mandatory = $true)][string[]]$TclArgs,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $stdout = Join-Path $outPath "$Label.stdout.log"
    $stderr = Join-Path $outPath "$Label.stderr.log"
    $vivadoArgs = @(
        "-d", $Distro, "--", $Vivado, "-mode", "batch", "-nojournal",
        "-log", (Convert-ToWslPath (Join-Path $outPath "$Label.vivado.log")),
        "-source", (Convert-ToWslPath $Tcl), "-tclargs"
    ) + $TclArgs
    $process = Start-Process -FilePath "wsl.exe" -ArgumentList $vivadoArgs `
        -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr
    Get-Content -Path $stdout,$stderr -ErrorAction SilentlyContinue
    if ($process.ExitCode -ne 0) {
        throw "$Label failed with exit code $($process.ExitCode)"
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$outPath = Join-Path $repoRoot $OutDir
$simPath = Join-Path $outPath "sim"
$implPath = Join-Path $outPath "impl"
$vector = Join-Path $PSScriptRoot "vectors\gstreamer-ball-1280x720-q90.jpg"
New-Item -ItemType Directory -Force -Path $simPath,$implPath | Out-Null

python (Join-Path $PSScriptRoot "prepare_vector.py") $vector $simPath
if ($LASTEXITCODE -ne 0) {
    throw "JPEG vector preparation failed"
}
$vectorInfo = Get-Content -Raw (Join-Path $simPath "vector.json") | ConvertFrom-Json

Invoke-VivadoBatch -Label "simulate" -Tcl (Join-Path $PSScriptRoot "simulate.tcl") `
    -TclArgs @((Convert-ToWslPath $repoRoot), (Convert-ToWslPath $simPath), [string]$vectorInfo.word_count)

python (Join-Path $PSScriptRoot "compare_pixels.py") `
    (Join-Path $simPath "rtl_pixels.hex") `
    (Join-Path $simPath "software-reference.rgb") `
    (Join-Path $simPath "pixel-comparison.json")
if ($LASTEXITCODE -ne 0) {
    throw "JPEG RTL/software pixel comparison failed"
}

Invoke-VivadoBatch -Label "implement" -Tcl (Join-Path $PSScriptRoot "implement.tcl") `
    -TclArgs @((Convert-ToWslPath $repoRoot), (Convert-ToWslPath $implPath))

$simLog = Get-Content -Raw (Join-Path $simPath "xsim.log")
$match = [regex]::Match($simLog, "JPEG_PL_RTL_SIM_OK width=(\d+) height=(\d+) pixels=(\d+) cycles=(\d+) duplicates=(\d+)")
if (-not $match.Success) {
    throw "Could not parse RTL simulation marker"
}
$cycles = [int64]$match.Groups[4].Value
$clockHz = 66666667.0
$decodeMs = $cycles / $clockHz * 1000.0
$maxFps = $clockHz / $cycles
$throughputPass = $decodeMs -le (1000.0 / 30.0)
$comparison = Get-Content -Raw (Join-Path $simPath "pixel-comparison.json") | ConvertFrom-Json
$impl = @{}
Get-Content (Join-Path $implPath "reports\qualification_summary.txt") | ForEach-Object {
    $parts = $_ -split "=",2
    if ($parts.Count -eq 2) { $impl[$parts[0]] = $parts[1] }
}
$summary = [ordered]@{
    result = if ($throughputPass) { "pass" } else { "fail" }
    upstream_commit = "f9e269a6687ed341b122cdd1412d101ee163e199"
    jpeg_sha256 = $vectorInfo.sha256
    width = 1280
    height = 720
    requested_fps = 30
    clock_hz = [int64]$clockHz
    rtl_cycles = $cycles
    decode_ms_at_clock = [math]::Round($decodeMs, 3)
    theoretical_fps = [math]::Round($maxFps, 3)
    psnr_db = [math]::Round([double]$comparison.psnr_db, 3)
    mean_absolute_error = [math]::Round([double]$comparison.mean_absolute_error, 3)
    max_absolute_error = $comparison.max_absolute_error
    wns_ns = [double]$impl.wns_ns
    drc_error_count = [int]$impl.drc_error_count
    support_writable_dht = 0
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -Encoding ASCII (Join-Path $outPath "summary.json")
if (-not $throughputPass) {
    throw "RTL decode misses 720p30 cycle budget: decode_ms=$decodeMs max_fps=$maxFps"
}
Write-Output ("JPEG_PL_DECODER_QUALIFICATION_OK cycles={0} decode_ms={1:F3} fps={2:F3} psnr_db={3:F3} wns_ns={4}" -f `
    $cycles,$decodeMs,$maxFps,[double]$comparison.psnr_db,$impl.wns_ns)
