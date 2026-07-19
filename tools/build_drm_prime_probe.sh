#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
out_dir="${1:-$repo_root/build/native-720p30-dmabuf-display-v1/drm-prime-probe}"

cross_cc="${CROSS_CC:-/opt/petalinux-v2018.3/tools/linux-i386/gcc-arm-linux-gnueabi/bin/arm-linux-gnueabihf-gcc}"
petalinux_project="${PETALINUX_PROJECT:-/home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic}"
libdrm_component="${LIBDRM_COMPONENT:-$petalinux_project/build/tmp/sysroots-components/cortexa9hf-neon/libdrm}"

mkdir -p "$out_dir"
if [[ ! -x "$cross_cc" ]]; then
  echo "ERROR: cross compiler not found: $cross_cc" >&2
  exit 1
fi
if [[ ! -f "$libdrm_component/usr/include/xf86drm.h" ||
      ! -f "$libdrm_component/usr/lib/libdrm.so" ]]; then
  echo "ERROR: libdrm target component not found: $libdrm_component" >&2
  exit 1
fi

"$cross_cc" -std=gnu99 -Wall -Wextra -Werror -O2 \
  -I"$libdrm_component/usr/include" \
  -I"$libdrm_component/usr/include/libdrm" \
  "$script_dir/drm_prime_probe.c" \
  -L"$libdrm_component/usr/lib" \
  -Wl,-rpath-link,"$libdrm_component/usr/lib" \
  -ldrm -o "$out_dir/drm_prime_probe"

file "$out_dir/drm_prime_probe" | tee "$out_dir/drm_prime_probe.file.txt"
sha256sum "$out_dir/drm_prime_probe" | tee "$out_dir/drm_prime_probe.sha256.txt"
echo "DRM_PRIME_PROBE_BUILD_OK out=$out_dir/drm_prime_probe"
