[CmdletBinding()]
param(
    [string]$Distro = "Ubuntu-22.04",
    [string]$Vivado = "/opt/Xilinx/Vivado/2018.3/bin/vivado",
    [string]$OutDir = "build\jpeg-pl-decoder-board-datapath-v1\sim"
)

$ErrorActionPreference = "Stop"

function Convert-ToWslPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full -notmatch "^([A-Za-z]):\\(.*)$") {
        throw "Cannot convert non-drive path to WSL path: $full"
    }
    return "/mnt/$($matches[1].ToLowerInvariant())/$($matches[2] -replace '\\','/')"
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$outPath = Join-Path $repoRoot $OutDir
$vector = Join-Path $repoRoot "examples\jpeg-pl-decoder-qualification\vectors\gstreamer-ball-1280x720-q90.jpg"
$prepare = Join-Path $repoRoot "examples\jpeg-pl-decoder-qualification\prepare_vector.py"
$compare = Join-Path $repoRoot "examples\jpeg-pl-decoder-qualification\compare_pixels.py"
$tcl = Join-Path $PSScriptRoot "sim_jpeg_board_datapath.tcl"
New-Item -ItemType Directory -Force $outPath | Out-Null

python $prepare $vector $outPath
if ($LASTEXITCODE -ne 0) { throw "vector preparation failed" }
$vectorInfo = Get-Content -Raw (Join-Path $outPath "vector.json") | ConvertFrom-Json

& wsl.exe -d $Distro -- $Vivado -mode batch -nojournal -nolog `
    -source (Convert-ToWslPath $tcl) -tclargs `
    (Convert-ToWslPath $repoRoot) (Convert-ToWslPath $outPath) $vectorInfo.word_count
if ($LASTEXITCODE -ne 0) { throw "JPEG board datapath xsim failed" }

python $compare (Join-Path $outPath "rtl_pixels.hex") `
    (Join-Path $outPath "software-reference.bgr") `
    (Join-Path $outPath "pixel-comparison.json") `
    --min-psnr-db 35 --expected-fnv 0xa567410c
if ($LASTEXITCODE -ne 0) { throw "JPEG board datapath pixel comparison failed" }
Write-Output "JPEG_BOARD_DATAPATH_SIM_GATE_OK out=$outPath"
