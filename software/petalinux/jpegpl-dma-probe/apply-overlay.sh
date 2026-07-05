#!/usr/bin/env bash
set -euo pipefail

project_path="${1:-/home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

dt_files_dir="${project_path}/project-spec/meta-user/recipes-bsp/device-tree/files"
system_user_dtsi="${dt_files_dir}/system-user.dtsi"
fragment="${script_dir}/system-user.dtsi.fragment"
marker="fpga-hdml,jpegpl-dma-probe-1.0"

install -d "$dt_files_dir"

if [[ ! -f "$system_user_dtsi" ]]; then
	install -m 0644 \
		"${repo_root}/software/petalinux/hdmi-linux-display-stack/system-user.dtsi" \
		"$system_user_dtsi"
fi

if grep -q "$marker" "$system_user_dtsi"; then
	if grep -q 'max-transfer-size' "$system_user_dtsi"; then
		printf 'JPEGPL_DMA_PROBE_OVERLAY_ALREADY_PRESENT project=%s\n' "$project_path"
	else
		sed -i '/buffer-size = <0x00200000>;/a\		max-transfer-size = <16380>;' \
			"$system_user_dtsi"
		printf 'JPEGPL_DMA_PROBE_OVERLAY_UPGRADED project=%s system_user_dtsi=%s\n' \
			"$project_path" "$system_user_dtsi"
	fi
else
	{
		printf '\n'
		printf '/* jpegpl DMA probe client node: appended by software/petalinux/jpegpl-dma-probe/apply-overlay.sh */\n'
		cat "$fragment"
		printf '\n'
	} >>"$system_user_dtsi"
	printf 'JPEGPL_DMA_PROBE_OVERLAY_OK project=%s system_user_dtsi=%s\n' \
		"$project_path" "$system_user_dtsi"
fi
