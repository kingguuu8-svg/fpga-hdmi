[CmdletBinding()]
param(
    [string]$Bitstream = "build\eth-ps-pl-hdmi-pass-through\board\eth_ps_pl_hdmi_stage1_board.bit",
    [string]$Elf = "build\eth-ps-pl-hdmi-pass-through\software\eth_pass_through.elf",
    [string]$Ps7Init = "build\eth-ps-pl-hdmi-pass-through\software\sdk_workspace\stage1_hw\ps7_init.tcl",
    [string]$VivadoRoot = "E:\Xilinx\Vivado\2018.3",
    [string]$SdkRoot = "E:\Xilinx\SDK\2018.3"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$bit = (Resolve-Path (Join-Path $repoRoot $Bitstream)).Path
$elfPath = (Resolve-Path (Join-Path $repoRoot $Elf)).Path
$ps7InitPath = (Resolve-Path (Join-Path $repoRoot $Ps7Init)).Path
$reportRoot = Join-Path $repoRoot "build\eth-ps-pl-hdmi-pass-through\hardware\reports"
$hwServer = Join-Path $VivadoRoot "bin\hw_server.bat"
$xsct = Join-Path $SdkRoot "bin\xsct.bat"
$tcl = Join-Path $PSScriptRoot "program_stage1_run.tcl"

New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null

$server = Start-Process -FilePath $hwServer -ArgumentList @("-s", "tcp::3121") `
    -WindowStyle Hidden -PassThru
try {
    $log = Join-Path $reportRoot "program_stage1_run.log"
    & $xsct $tcl $bit $elfPath $ps7InitPath 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) {
        throw "XSCT stage1 program/run failed with exit code $LASTEXITCODE."
    }
}
finally {
    if (-not $server.HasExited) {
        Stop-Process -Id $server.Id
    }
}
