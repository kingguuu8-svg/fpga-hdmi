#!/usr/bin/env bash
set -euo pipefail

project_path="${1:-/home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

linux_recipe_dir="${project_path}/project-spec/meta-user/recipes-kernel/linux"
dt_files_dir="${project_path}/project-spec/meta-user/recipes-bsp/device-tree/files"

install_file_checked() {
	local src="$1"
	local dst="$2"
	install -d "$(dirname "$dst")"
	if [[ -e "$dst" ]] && ! cmp -s "$src" "$dst"; then
		printf 'Refusing to overwrite existing different file: %s\n' "$dst" >&2
		return 2
	fi
	install -m 0644 "$src" "$dst"
}

install_file_with_backup() {
	local src="$1"
	local dst="$2"
	install -d "$(dirname "$dst")"
	if [[ -e "$dst" ]] && ! cmp -s "$src" "$dst"; then
		local bak="${dst}.pre-hdmi-linux-display-stack"
		if [[ ! -e "$bak" ]]; then
			cp -p "$dst" "$bak"
		fi
	fi
	install -m 0644 "$src" "$dst"
}

install_file_checked "${script_dir}/linux-xlnx_%.bbappend" \
	"${linux_recipe_dir}/linux-xlnx_%.bbappend"
install_file_checked "${script_dir}/user.cfg" \
	"${linux_recipe_dir}/files/user.cfg"
install_file_with_backup "${script_dir}/system-user.dtsi" \
	"${dt_files_dir}/system-user.dtsi"

old_dir="${linux_recipe_dir}/linux-xlnx"
if [[ -d "$old_dir" ]]; then
	if [[ -f "${old_dir}/linux-xlnx_%.bbappend" ]] &&
		cmp -s "${script_dir}/linux-xlnx_%.bbappend" \
			"${old_dir}/linux-xlnx_%.bbappend"; then
		rm -f "${old_dir}/linux-xlnx_%.bbappend"
	fi
	if [[ -f "${old_dir}/files/user.cfg" ]] &&
		cmp -s "${script_dir}/user.cfg" "${old_dir}/files/user.cfg"; then
		rm -f "${old_dir}/files/user.cfg"
		rmdir "${old_dir}/files" 2>/dev/null || true
	fi
	rmdir "$old_dir" 2>/dev/null || true
fi

printf 'HDMI_LINUX_DISPLAY_STACK_OVERLAY_OK project=%s\n' "$project_path"
