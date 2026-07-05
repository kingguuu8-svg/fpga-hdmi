#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
out_dir="${1:-$repo_root/build/jpegpl-dma-probe-kernel-client}"

kernel_dir="${KERNEL_DIR:-/home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic/build/tmp/work/plnx_zynq7-xilinx-linux-gnueabi/linux-xlnx/4.14-xilinx-v2018.3+gitAUTOINC+eeab73d120-r0/linux-plnx_zynq7-standard-build}"
cross_prefix="${CROSS_COMPILE:-/opt/petalinux-v2018.3/tools/linux-i386/gcc-arm-linux-gnueabi/bin/arm-linux-gnueabihf-}"
host_cc="${HOST_CC:-gcc}"
cross_cc="${CROSS_CC:-${cross_prefix}gcc}"

mkdir -p "$out_dir"

if [[ ! -d "$kernel_dir" ]]; then
  echo "ERROR: kernel build directory not found: $kernel_dir" >&2
  exit 1
fi
if [[ ! -x "$cross_cc" ]]; then
  echo "ERROR: cross compiler not found: $cross_cc" >&2
  exit 1
fi

make -C "$kernel_dir" \
  M="$script_dir/src" \
  ARCH=arm \
  CROSS_COMPILE="$cross_prefix" \
  clean >/dev/null

"$host_cc" -std=gnu99 -Wall -Wextra -Werror \
  -I"$script_dir/include" \
  "$script_dir/test/jpegpl_dma_probe_test.c" \
  -o "$out_dir/jpegpl_dma_probe_test_host"
"$out_dir/jpegpl_dma_probe_test_host" --self-test \
  | tee "$out_dir/jpegpl_dma_probe_test_host.log"

make -C "$kernel_dir" \
  M="$script_dir/src" \
  ARCH=arm \
  CROSS_COMPILE="$cross_prefix" \
  modules

cp "$script_dir/src/jpegpl_dma_probe.ko" "$out_dir/"

make -C "$kernel_dir" \
  M="$script_dir/src" \
  ARCH=arm \
  CROSS_COMPILE="$cross_prefix" \
  clean >/dev/null

"$cross_cc" -std=gnu99 -Wall -Wextra -Werror \
  -I"$script_dir/include" \
  "$script_dir/test/jpegpl_dma_probe_test.c" \
  -o "$out_dir/jpegpl_dma_probe_test"

file "$out_dir/jpegpl_dma_probe.ko" | tee "$out_dir/jpegpl_dma_probe.ko.file.txt"
sha256sum "$out_dir/jpegpl_dma_probe.ko" | tee "$out_dir/jpegpl_dma_probe.ko.sha256.txt"
file "$out_dir/jpegpl_dma_probe_test" | tee "$out_dir/jpegpl_dma_probe_test.file.txt"
sha256sum "$out_dir/jpegpl_dma_probe_test" | tee "$out_dir/jpegpl_dma_probe_test.sha256.txt"

echo "JPEGPL_DMA_PROBE_CLIENT_BUILD_OK out=$out_dir"
