#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 3 ]]; then
	printf 'usage: %s <chroot-path> <project-path> <command> [args...]\n' "$0" >&2
	exit 2
fi

chroot_path="$1"
project_path="$2"
shift 2

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

command_line="$(printf '%q ' "$@")"
runner="${chroot_path}/tmp/run-hdmi-linux-display-stack-command.sh"
cat >"$runner" <<EOF_RUNNER
#!/usr/bin/env bash
set -euo pipefail
export LANG=en_US.utf8
export LC_ALL=en_US.utf8
source /opt/petalinux-v2018.3/settings.sh >/tmp/petalinux-settings.log
cd "$project_path"
$command_line
EOF_RUNNER
chmod 0755 "$runner"

chroot "$chroot_path" /bin/bash -lc \
	"su - petalinux -c /tmp/run-hdmi-linux-display-stack-command.sh"
