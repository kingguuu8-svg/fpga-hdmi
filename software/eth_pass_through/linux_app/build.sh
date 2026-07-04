#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
out_dir="${1:-$repo_root/build/ethernet-video-userspace-receiver}"
cross_cc="${CROSS_CC:-/opt/petalinux-v2018.3/tools/linux-i386/gcc-arm-linux-gnueabi/bin/arm-linux-gnueabihf-gcc}"
host_cc="${HOST_CC:-gcc}"

mkdir -p "$out_dir"

common_cflags=(
    -std=gnu99
    -Wall
    -Wextra
    -Werror
    -O2
    -I"$repo_root/software/eth_pass_through/src"
)

"$host_cc" "${common_cflags[@]}" \
    "$repo_root/software/eth_pass_through/tests/test_video_udp_receiver.c" \
    "$repo_root/software/eth_pass_through/src/video_udp_receiver.c" \
    "$repo_root/software/eth_pass_through/src/video_udp_protocol.c" \
    -o "$out_dir/test_video_udp_receiver"

"$host_cc" "${common_cflags[@]}" \
    "$repo_root/software/eth_pass_through/tests/test_linux_framebuffer_writer.c" \
    "$repo_root/software/eth_pass_through/src/video_framebuffer.c" \
    -o "$out_dir/test_linux_framebuffer_writer"

"$host_cc" "${common_cflags[@]}" \
    "$repo_root/software/eth_pass_through/tests/test_video_control.c" \
    "$repo_root/software/eth_pass_through/src/video_control.c" \
    -o "$out_dir/test_video_control"

"$host_cc" "${common_cflags[@]}" \
    "$repo_root/software/eth_pass_through/tests/test_video_effect.c" \
    "$repo_root/software/eth_pass_through/src/video_effect.c" \
    -o "$out_dir/test_video_effect"

"$out_dir/test_video_udp_receiver" | tee "$out_dir/test_video_udp_receiver.log"
"$out_dir/test_linux_framebuffer_writer" | tee "$out_dir/test_linux_framebuffer_writer.log"
"$out_dir/test_video_control" | tee "$out_dir/test_video_control.log"
"$out_dir/test_video_effect" | tee "$out_dir/test_video_effect.log"

"$cross_cc" "${common_cflags[@]}" \
    "$repo_root/software/eth_pass_through/linux_app/src/fb_video_udp_receiver.c" \
    "$repo_root/software/eth_pass_through/src/video_udp_receiver.c" \
    "$repo_root/software/eth_pass_through/src/video_udp_protocol.c" \
    "$repo_root/software/eth_pass_through/src/video_framebuffer.c" \
    "$repo_root/software/eth_pass_through/src/video_control.c" \
    "$repo_root/software/eth_pass_through/src/video_effect.c" \
    -o "$out_dir/fb_video_udp_receiver"

file "$out_dir/fb_video_udp_receiver" | tee "$out_dir/fb_video_udp_receiver.file.txt"
sha256sum "$out_dir/fb_video_udp_receiver" | tee "$out_dir/fb_video_udp_receiver.sha256.txt"

"$cross_cc" "${common_cflags[@]}" \
    "$repo_root/software/eth_pass_through/linux_app/src/drm_kms_udp_receiver.c" \
    "$repo_root/software/eth_pass_through/src/video_udp_receiver.c" \
    "$repo_root/software/eth_pass_through/src/video_udp_protocol.c" \
    -o "$out_dir/drm_kms_udp_receiver"

file "$out_dir/drm_kms_udp_receiver" | tee "$out_dir/drm_kms_udp_receiver.file.txt"
sha256sum "$out_dir/drm_kms_udp_receiver" | tee "$out_dir/drm_kms_udp_receiver.sha256.txt"

"$cross_cc" "${common_cflags[@]}" \
    "$repo_root/software/eth_pass_through/linux_app/src/vdma_mm2s_config.c" \
    -o "$out_dir/vdma_mm2s_config"

file "$out_dir/vdma_mm2s_config" | tee "$out_dir/vdma_mm2s_config.file.txt"
sha256sum "$out_dir/vdma_mm2s_config" | tee "$out_dir/vdma_mm2s_config.sha256.txt"

"$cross_cc" "${common_cflags[@]}" \
    "$repo_root/software/eth_pass_through/linux_app/src/pip_effect_ctl.c" \
    -o "$out_dir/pip_effect_ctl"

file "$out_dir/pip_effect_ctl" | tee "$out_dir/pip_effect_ctl.file.txt"
sha256sum "$out_dir/pip_effect_ctl" | tee "$out_dir/pip_effect_ctl.sha256.txt"

"$cross_cc" "${common_cflags[@]}" \
    "$repo_root/software/eth_pass_through/linux_app/src/pip_effect_server.c" \
    -o "$out_dir/pip_effect_server"

file "$out_dir/pip_effect_server" | tee "$out_dir/pip_effect_server.file.txt"
sha256sum "$out_dir/pip_effect_server" | tee "$out_dir/pip_effect_server.sha256.txt"
echo "LINUX_RECEIVER_BUILD_OK out=$out_dir/fb_video_udp_receiver"
echo "DRM_KMS_RECEIVER_BUILD_OK out=$out_dir/drm_kms_udp_receiver"
echo "VDMA_MM2S_CONFIG_BUILD_OK out=$out_dir/vdma_mm2s_config"
echo "PIP_EFFECT_CTL_BUILD_OK out=$out_dir/pip_effect_ctl"
echo "PIP_EFFECT_SERVER_BUILD_OK out=$out_dir/pip_effect_server"
