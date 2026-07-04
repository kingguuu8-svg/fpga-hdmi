[CmdletBinding()]
param(
    [string]$Port = "COM16",
    [string]$OutDir = "build\jpegpldec-dma-capability-route-gate"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outPath = Join-Path $repoRoot $OutDir
New-Item -ItemType Directory -Force -Path $outPath | Out-Null

$commands = @(
    "echo DMA_CAPABILITY_PROBE_BEGIN",
    "cat /proc/cmdline",
    "uname -a",
    "echo DEV_DMA_NODES_BEGIN",
    "ls -l /dev | grep -E 'dma|udmabuf|u-dma|heap|ion|vfio|uio|fb|dri' || true",
    "ls -l /dev/dma_heap 2>/dev/null || true",
    "test -d /dev/dma_heap && echo DEV_DMA_HEAP_PRESENT || echo DEV_DMA_HEAP_ABSENT",
    "ls /dev/uio* >/dev/null 2>&1 && echo DEV_UIO_PRESENT || echo DEV_UIO_ABSENT",
    "find /dev -maxdepth 1 -iname '*udmabuf*' 2>/dev/null | grep . >/dev/null && echo DEV_UDMABUF_PRESENT || echo DEV_UDMABUF_ABSENT",
    "find /dev -maxdepth 1 -iname '*ion*' 2>/dev/null | grep . >/dev/null && echo DEV_ION_PRESENT || echo DEV_ION_ABSENT",
    "echo DEV_DMA_NODES_END",
    "echo SYS_DMA_NODES_BEGIN",
    "find /sys -maxdepth 4 -iname '*dma*' 2>/dev/null | head -n 120",
    "find /sys -maxdepth 4 -iname '*udmabuf*' 2>/dev/null | head -n 40",
    "find /sys -maxdepth 4 -iname '*uio*' 2>/dev/null | head -n 40",
    "ls /sys/class/uio/uio* >/dev/null 2>&1 && echo SYS_UIO_PRESENT || echo SYS_UIO_ABSENT",
    "find /sys -maxdepth 4 -iname '*udmabuf*' 2>/dev/null | grep . >/dev/null && echo SYS_UDMABUF_PRESENT || echo SYS_UDMABUF_ABSENT",
    "echo SYS_DMA_NODES_END",
    "echo KCONFIG_DMA_BEGIN",
    "zcat /proc/config.gz 2>/dev/null | grep -E 'CONFIG_DMA_SHARED_BUFFER|CONFIG_DMABUF|CONFIG_CMA|CONFIG_UDMABUF|CONFIG_UIO|CONFIG_XILINX_DMA|CONFIG_XILINX_VDMA|CONFIG_DMA_ENGINE' || true",
    "echo KCONFIG_DMA_END",
    "echo IOMEM_DMA_BEGIN",
    "cat /proc/iomem | grep -Ei 'cma|reserved|dma|frame|vdma' || true",
    "echo IOMEM_DMA_END",
    "echo FB_INFO_BEGIN",
    "cat /sys/class/graphics/fb0/name 2>/dev/null || true",
    "cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || true",
    "cat /sys/class/graphics/fb0/stride 2>/dev/null || true",
    "echo FB_INFO_END",
    "echo DMA_CAPABILITY_PROBE_END"
)

$commandFile = Join-Path $outPath "uart-dma-capability.commands"
$logFile = Join-Path $outPath "uart-dma-capability.log"
$summaryFile = Join-Path $outPath "summary.json"
$commands | Set-Content -LiteralPath $commandFile -Encoding ASCII

& (Join-Path $repoRoot "tools\uart_run_commands.ps1") `
    -Port $Port `
    -CommandFile $commandFile `
    -LoginRoot `
    -Password root `
    -InitialReadSeconds 0 `
    -InterCommandDelayMilliseconds 400 `
    -FinalReadSeconds 4 `
    -OutputPath (Join-Path $OutDir "uart-dma-capability.log") |
    Set-Content -LiteralPath (Join-Path $outPath "uart-dma-capability.runner-output.log") -Encoding UTF8

if (-not (Test-Path -LiteralPath $logFile)) {
    throw "UART capability log missing: $logFile"
}

$text = Get-Content -Raw -LiteralPath $logFile
$hasCma = $text -match "CONFIG_CMA=y"
$hasDmaSharedBuffer = $text -match "CONFIG_DMA_SHARED_BUFFER=y"
$hasXilinxDma = $text -match "CONFIG_XILINX_DMA=y"
$hasDmaEngine = $text -match "CONFIG_DMA_ENGINE=y"
$hasDmaHeapDev = $text -match "(?m)^\s*DEV_DMA_HEAP_PRESENT\s*$"
$hasUdmaBuf = $text -match "(?m)^\s*(DEV_UDMABUF_PRESENT|SYS_UDMABUF_PRESENT)\s*$"
$hasIon = $text -match "(?m)^\s*DEV_ION_PRESENT\s*$"
$hasUioDev = $text -match "(?m)^\s*(DEV_UIO_PRESENT|SYS_UIO_PRESENT)\s*$"
$hasFb0 = $text -match "\bfb0\b"
$hasVdmaDevice = $text -match "43000000\.dma|43000000-4300ffff|/amba_pl/dma@43000000"

$directUserDmaInterface = $hasDmaHeapDev -or $hasUdmaBuf -or $hasIon -or $hasUioDev
$result = if ($directUserDmaInterface) { "usable-userspace-dma-interface-present" } else { "missing-userspace-dma-buffer-interface" }

$summary = [PSCustomObject]@{
    cycle = "jpegpldec-dma-capability-route-gate"
    result = $result
    config_cma = $hasCma
    config_dma_shared_buffer = $hasDmaSharedBuffer
    config_dma_engine = $hasDmaEngine
    config_xilinx_dma = $hasXilinxDma
    dev_dma_heap = $hasDmaHeapDev
    udmabuf = $hasUdmaBuf
    ion = $hasIon
    dev_uio = $hasUioDev
    fb0 = $hasFb0
    vdma_device_43000000 = $hasVdmaDevice
    direct_user_dma_interface = $directUserDmaInterface
    uart_log = $logFile
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $summaryFile -Encoding UTF8

Write-Output (
    "JPEGPLDEC_DMA_CAPABILITY_PROBE_OK " +
    "result=$result " +
    "cma=$([int]$hasCma) " +
    "dma_shared_buffer=$([int]$hasDmaSharedBuffer) " +
    "xilinx_dma=$([int]$hasXilinxDma) " +
    "dma_heap=$([int]$hasDmaHeapDev) " +
    "udmabuf=$([int]$hasUdmaBuf) " +
    "uio_dev=$([int]$hasUioDev) " +
    "fb0=$([int]$hasFb0) " +
    "vdma=$([int]$hasVdmaDevice) " +
    "summary=$summaryFile"
)
