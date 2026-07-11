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
	python3 - "$system_user_dtsi" "$fragment" <<'PY'
import pathlib
import re
import sys

target = pathlib.Path(sys.argv[1])
fragment = pathlib.Path(sys.argv[2]).read_text()
text = target.read_text()
node = re.compile(r'\n\s*jpegpl_dma_probe_0: jpegpl-[^{]+\{.*?\n\s*\};', re.S)
replacement = node.search(fragment).group(0)
updated, count = node.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit("existing jpegpl DMA node was not found")
target.write_text(updated)
PY
	printf 'JPEGPL_DMA_PROBE_OVERLAY_UPDATED project=%s system_user_dtsi=%s\n' \
		"$project_path" "$system_user_dtsi"
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
