[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BoardProfile,
    [ValidateSet("auto", "xsct", "openfpgaloader")]
    [string]$Backend = "auto",
    [string]$Example = "led-chaser"
)

$ErrorActionPreference = "Stop"
$skillRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$reportsRoot = Join-Path $repoRoot "build\reports"
New-Item -ItemType Directory -Force -Path $reportsRoot | Out-Null

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [System.IO.File]::OpenRead((Resolve-Path $Path).Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            return (($sha.ComputeHash($stream) | ForEach-Object { $_.ToString("x2") }) -join "")
        }
        finally {
            $sha.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

& (Join-Path $skillRoot "zynq7020-environment\scripts\probe-environment.ps1")

$buildScript = Join-Path $skillRoot "zynq7020-vivado\scripts\build-wsl.ps1"
$bitstream = & $buildScript -BoardProfile $BoardProfile -Example $Example
$bitstream = $bitstream | Select-Object -Last 1

if ($Backend -eq "auto") {
    try {
        & (Join-Path $skillRoot "zynq7020-environment\scripts\probe-hardware.ps1")
        $Backend = "xsct"
    }
    catch {
        $Backend = "openfpgaloader"
    }
}

switch ($Backend) {
    "xsct" {
        & (Join-Path $skillRoot "zynq7020-hardware\scripts\program-xsct.ps1") `
            -Bitstream $bitstream
    }
    "openfpgaloader" {
        & (Join-Path $skillRoot "zynq7020-hardware\scripts\program-openfpgaloader.ps1") `
            -Bitstream $bitstream
    }
}

$bitItem = Get-Item -LiteralPath $bitstream
$exampleBuildRoot = Join-Path $repoRoot "build\$Example"
$runReport = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    repository = $repoRoot
    board_profile = (Resolve-Path $BoardProfile).Path
    example = $Example
    backend = $Backend
    bitstream = $bitItem.FullName
    bitstream_size = $bitItem.Length
    bitstream_sha256 = Get-FileSha256 -Path $bitItem.FullName
    drc_report = Join-Path $exampleBuildRoot "reports\drc.rpt"
    timing_report = Join-Path $exampleBuildRoot "reports\timing_summary.rpt"
    programming_scope = "PL SRAM only"
    result = "MVP_PIPELINE_OK"
}
$runReport | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 `
    -LiteralPath (Join-Path $reportsRoot "latest-mvp-run.json")

Write-Output "MVP_PIPELINE_OK bitstream=$bitstream backend=$Backend"
