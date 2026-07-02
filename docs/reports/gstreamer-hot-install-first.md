# GStreamer Hot Install First

Date: 2026-07-02

Result: FAILED.

## Objective

Try the shortest dependency route before rebuilding PetaLinux: install or
expose GStreamer on the PC, then hot-install the missing board-side GStreamer
stack into the running Linux image if apt is available.

## Frozen Pass Condition

```text
pc_gst_launch_present == 1 and pc_gst_inspect_present == 1
and pc_required_gst_elements_missing == 0 and board_apt_probe_completed == 1
and board_install_method == apt-hot-install and board_apt_update_status == pass
and board_apt_install_status == pass and board_gst_launch_present == 1
and board_gst_inspect_present == 1 and board_required_gst_elements_missing == 0
and board_drm_card0_present == 1 and board_rootfs_free_mb_after >= 200
and petalinux_image_built == 0 and tf_card_image_written == 0
```

## What Ran

PC side:

```text
HOST_CMD_MISSING gst-launch-1.0
HOST_CMD_MISSING gst-inspect-1.0
HOST_CMD_PRESENT winget
winget search found gstreamerproject.gstreamer 1.28.4
winget install failed with installer hash mismatch
HOST_CMD_MISSING gst-launch-1.0
HOST_CMD_MISSING gst-inspect-1.0
```

Board side over UART:

```text
BOARD_APT_GET_MISSING
BOARD_PKG_CMD_MISSING apt
BOARD_PKG_CMD_MISSING apt-get
BOARD_PKG_CMD_MISSING dpkg
BOARD_PKG_CMD_MISSING opkg
BOARD_PKG_CMD_MISSING rpm
BOARD_PKG_CMD_MISSING dnf
BOARD_PKG_CMD_MISSING yum
BOARD_PKG_CMD_MISSING pacman
/dev/dri/card0 exists
BOARD_GST_LAUNCH_MISSING
BOARD_GST_INSPECT_MISSING
BOARD_GST_ELEMENT_CHECK_SKIPPED no-gst-inspect
```

Network/mount evidence:

```text
eth0 = 192.168.1.10/24
PC 192.168.1.2 ping = 1/1 received
default route = absent
DNS = absent
8.8.8.8 ping = Network is unreachable
old-releases.ubuntu.com = bad address
rootfs / rootfs rw,size=243584k
/dev/mmcblk0p1 mounted as vfat at /run/media/mmcblk0p1
```

## Measured Result

```text
pc_gst_launch_present=0
pc_gst_inspect_present=0
pc_required_gst_elements_missing=4
pc_winget_package_found=1
pc_winget_install_status=failed_hash_mismatch
board_apt_probe_completed=1
board_install_method=none
board_apt_update_status=not_run_no_apt
board_apt_install_status=not_run_no_apt
board_gst_launch_present=0
board_gst_inspect_present=0
board_required_gst_elements_missing=5
board_drm_card0_present=1
board_package_managers_present=0
board_default_route_present=0
board_dns_present=0
board_rootfs_type=rootfs_ram
board_rootfs_size_mb=237
tf_boot_partition_mounted_mb=1020
petalinux_image_built=0
tf_card_image_written=0
```

The cycle fails its own frozen pass condition.

## Conclusion

The third-party hot-install suggestion was valid as a question, but the current
board image does not satisfy its prerequisites. This is not an Ubuntu bionic
old-releases problem yet: apt is absent, and the running rootfs is not a
package-managed ext4 root filesystem. The next practical route is a PetaLinux
rootfs/image build that includes GStreamer, or a different rootfs strategy that
intentionally provides package management and persistent storage.

PC-side GStreamer is also still unresolved. `winget --ignore-security-hash`
could bypass the failed hash check, but that should not be done silently.

## Evidence

- `build/gstreamer-hot-install-first/host-probe-before-install.log`
- `build/gstreamer-hot-install-first/host-probe-after-winget.log`
- `build/gstreamer-hot-install-first/board-hot-install-probe.log`
- `build/gstreamer-hot-install-first/board-package-manager-probe2.log`
