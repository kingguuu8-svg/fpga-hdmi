#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
out_dir="${1:-$repo_root/build/jpegpldec-plugin-skeleton}"

cross_cc="${CROSS_CC:-/opt/petalinux-v2018.3/tools/linux-i386/gcc-arm-linux-gnueabi/bin/arm-linux-gnueabihf-gcc}"
petalinux_project="${PETALINUX_PROJECT:-/home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic}"
components_dir="${SYSROOT_COMPONENTS:-$petalinux_project/build/tmp/sysroots-components/cortexa9hf-neon}"
gst_component="${GST_COMPONENT:-$components_dir/gstreamer1.0}"
gst_base_component="${GST_BASE_COMPONENT:-$components_dir/gstreamer1.0-plugins-base}"
glib_component="${GLIB_COMPONENT:-$components_dir/glib-2.0}"

mkdir -p "$out_dir"

if [[ ! -x "$cross_cc" ]]; then
  echo "ERROR: cross compiler not found: $cross_cc" >&2
  exit 1
fi

if [[ ! -d "$gst_component/usr/include/gstreamer-1.0" ]]; then
  echo "ERROR: GStreamer target headers not found: $gst_component" >&2
  exit 1
fi

if [[ ! -f "$gst_base_component/usr/include/gstreamer-1.0/gst/video/gstvideodecoder.h" ]]; then
  echo "ERROR: GStreamer video decoder headers not found: $gst_base_component" >&2
  exit 1
fi

if [[ ! -d "$glib_component/usr/include/glib-2.0" ]]; then
  echo "ERROR: GLib target headers not found: $glib_component" >&2
  exit 1
fi

cflags=(
  -std=gnu99
  -Wall
  -Wextra
  -Werror
  -O2
  -fPIC
  -DPACKAGE=\"fpga-hdml-jpegpldec\"
  -I"$gst_component/usr/include/gstreamer-1.0"
  -I"$gst_base_component/usr/include/gstreamer-1.0"
  -I"$glib_component/usr/include/glib-2.0"
  -I"$glib_component/usr/lib/glib-2.0/include"
  -I"$repo_root/software/kernel/jpegpl_dma_probe/include"
)

ldflags=(
  -shared
  -Wl,--no-undefined
  -L"$gst_component/usr/lib"
  -L"$gst_base_component/usr/lib"
  -L"$glib_component/usr/lib"
  -lgstreamer-1.0
  -lgstvideo-1.0
  -lgobject-2.0
  -lglib-2.0
)

"$cross_cc" "${cflags[@]}" \
  "$repo_root/software/gstreamer/jpegpldec/src/gstjpegpldec.c" \
  "${ldflags[@]}" \
  -o "$out_dir/libgstjpegpldec.so"

file "$out_dir/libgstjpegpldec.so" | tee "$out_dir/libgstjpegpldec.file.txt"
sha256sum "$out_dir/libgstjpegpldec.so" | tee "$out_dir/libgstjpegpldec.sha256.txt"
echo "JPEGPLDEC_PLUGIN_BUILD_OK out=$out_dir/libgstjpegpldec.so"
