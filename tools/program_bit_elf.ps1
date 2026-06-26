[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Bitstream,
    [Parameter(Mandatory = $true)]
    [string]$Elf,
    [Parameter(Mandatory = $true)]
    [string]$Ps7Init,
    [string]$Marker = "PROGRAM_BIT_ELF_OK",
    [string]$ReportDir = "build\reports\program-bit-elf",
    [string]$VivadoRoot = "E:\Xilinx\Vivado\2018.3",
    [string]$SdkRoot = "E:\Xilinx\SDK\2018.3"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$bit = (Resolve-Path (Join-Path $repoRoot $Bitstream)).Path
$elfPath = (Resolve-Path (Join-Path $repoRoot $Elf)).Path
$ps7InitPath = (Resolve-Path (Join-Path $repoRoot $Ps7Init)).Path
$reportRoot = Join-Path $repoRoot $ReportDir
$hwServer = Join-Path $VivadoRoot "bin\hw_server.bat"
$xsct = Join-Path $SdkRoot "bin\xsct.bat"
$tcl = Join-Path $PSScriptRoot "program_bit_elf.tcl"

New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null

$server = Start-Process -FilePath $hwServer -ArgumentList @("-s", "tcp::3121") `
    -WindowStyle Hidden -PassThru
try {
    $safeMarker = $Marker -replace '[^A-Za-z0-9_.-]', '_'
    $log = Join-Path $reportRoot "$safeMarker.log"
    & $xsct $tcl $bit $elfPath $ps7InitPath $Marker 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) {
        throw "XSCT bit+ELF program/run failed with exit code $LASTEXITCODE."
    }
}
finally {
    if (-not $server.HasExited) {
        Stop-Process -Id $server.Id
    }
}
