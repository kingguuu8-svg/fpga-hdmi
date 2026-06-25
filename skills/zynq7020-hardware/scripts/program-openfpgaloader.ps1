[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Bitstream,
    [string]$OpenFPGALoader = "C:\msys64\ucrt64\bin\openFPGALoader.exe",
    [string]$Cable = "ft4232"
)

$ErrorActionPreference = "Stop"
$bit = (Resolve-Path $Bitstream).Path
if (-not (Test-Path -LiteralPath $OpenFPGALoader -PathType Leaf)) {
    throw "openFPGALoader not found at '$OpenFPGALoader'."
}

& $OpenFPGALoader --cable $Cable --detect
if ($LASTEXITCODE -ne 0) {
    throw "JTAG detection failed. Verify that FT4232 interface A uses WinUSB."
}

& $OpenFPGALoader --cable $Cable $bit
if ($LASTEXITCODE -ne 0) {
    throw "openFPGALoader programming failed with exit code $LASTEXITCODE."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$reportDir = Join-Path $repoRoot "build\reports"
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$hashOutput = & certutil.exe -hashfile $bit SHA256
$record = @(
    "generated_at: $((Get-Date).ToString('o'))"
    "backend: openFPGALoader"
    "cable: $Cable"
    "bitstream: $bit"
    "sha256_output: |"
) + ($hashOutput | ForEach-Object { "  $_" })
$record | Set-Content -LiteralPath (Join-Path $reportDir "programming.yml") -Encoding UTF8
