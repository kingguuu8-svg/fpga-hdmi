#!/usr/bin/env bash
set -euo pipefail

chroot_path="${1:-/opt/chroots/ubuntu18-petalinux2018}"
project_path="${2:-/home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic}"
log_dir="${3:-/mnt/e/main/fpga-hdml/build/hdmi-linux-display-stack}"

ensure_mount() {
	local src="$1"
	local dst="$2"
	local mode="${3:-bind}"

	install -d "$dst"
	if mountpoint -q "$dst"; then
		return
	fi

	case "$mode" in
		bind) mount --bind "$src" "$dst" ;;
		rbind) mount --rbind "$src" "$dst" ;;
		proc) mount -t proc proc "$dst" ;;
		tmpfs) mount -t tmpfs tmpfs "$dst" ;;
		*) printf 'Unknown mount mode: %s\n' "$mode" >&2; return 2 ;;
	esac
}

ensure_mount /opt/petalinux-v2018.3 "${chroot_path}/opt/petalinux-v2018.3" bind
ensure_mount /home "${chroot_path}/home" bind
ensure_mount /mnt/e "${chroot_path}/mnt/e" bind
ensure_mount proc "${chroot_path}/proc" proc
ensure_mount /sys "${chroot_path}/sys" rbind
ensure_mount /dev "${chroot_path}/dev" rbind
ensure_mount tmpfs "${chroot_path}/dev/shm" tmpfs
chmod 1777 "${chroot_path}/dev/shm"

chroot "$chroot_path" /bin/bash -lc \
	'python3 -c "import multiprocessing; multiprocessing.Lock(); print(\"CHROOT_SHM_LOCK_OK\")"'

install -d "$log_dir"

runner="${chroot_path}/tmp/run-hdmi-linux-display-stack-build.sh"
cat >"$runner" <<EOF_RUNNER
#!/usr/bin/env bash
set -euo pipefail
export LANG=en_US.utf8
export LC_ALL=en_US.utf8
source /opt/petalinux-v2018.3/settings.sh >/tmp/petalinux-settings.log
cd "$project_path"
petalinux-build
EOF_RUNNER
chmod 0755 "$runner"

set +e
chroot "$chroot_path" /bin/bash -lc \
	"su - petalinux -c /tmp/run-hdmi-linux-display-stack-build.sh" \
	2>&1 | tee "${log_dir}/petalinux-build.log"
status=${PIPESTATUS[0]}
set -e

if [[ "$status" -ne 0 ]]; then
	printf 'HDMI_LINUX_DISPLAY_STACK_BUILD_FAILED status=%s log=%s\n' \
		"$status" "${log_dir}/petalinux-build.log" >&2
	exit "$status"
fi

printf 'HDMI_LINUX_DISPLAY_STACK_BUILD_OK log=%s\n' \
	"${log_dir}/petalinux-build.log"
