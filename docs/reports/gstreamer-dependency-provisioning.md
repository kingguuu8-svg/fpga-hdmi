# GStreamer Dependency Provisioning

Date: 2026-07-02

Result: FAILED before provisioning.

## Objective

Provide the missing GStreamer runtime dependencies required by the mature Linux
video route.

## Failure Reason

The cycle was opened with a pass condition that required:

```text
petalinux_image_built == 1 and board_booted_updated_image == 1 and
tf_card_update_verified == 1
```

That over-constrained the shortest path. A faster valid dependency route exists:
hot-installing GStreamer packages into the running board Linux rootfs with
`apt-get`, if the image has apt and network access. Hot install does not rebuild
PetaLinux and does not change PL/Vivado/bitstream. Because the frozen pass gate
cannot be edited in place, this cycle is closed before provisioning and a
corrected hot-install-first cycle must be opened.

## Verification

Partial dependency probes were run:

```text
HOST_CMD_MISSING gst-launch-1.0
HOST_CMD_MISSING gst-inspect-1.0
HOST_CMD_PRESENT winget
HOST_CMD_MISSING choco
PETALINUX_PROJECT_PRESENT=1
GStreamer recipes exist in the installed PetaLinux/Yocto layers.
```

No package install, PetaLinux build, TF-card update, reboot, video pipeline, or
HDMI capture was run in this cycle.

## Board Action

None.

## Result

pass_condition=(pc_gst_launch_present == 1 and pc_gst_inspect_present == 1
and pc_required_gst_elements_missing == 0 and board_gst_launch_present == 1
and board_gst_inspect_present == 1 and board_required_gst_elements_missing == 0
and board_drm_card0_present == 1 and petalinux_image_built == 1 and
board_booted_updated_image == 1 and tf_card_update_verified == 1).

measured=(pc_gst_launch_present=0, pc_gst_inspect_present=0,
pc_required_gst_elements_missing=not-run, board_gst_launch_present=0,
board_gst_inspect_present=0, board_required_gst_elements_missing=not-run,
board_drm_card0_present=1, petalinux_image_built=0,
board_booted_updated_image=0, tf_card_update_verified=0,
cycle_scope_error=hot_install_path_excluded).

The cycle fails because its own frozen pass condition cannot be satisfied by
the now-preferred shortest dependency route.

## Evidence

- `build/gstreamer-dependency-provisioning/host-gstreamer-availability.log`
- `build/gstreamer-dependency-provisioning/yocto-gstreamer-recipes.log`

## Next Step

Open a corrected dependency cycle that tries, in order:

1. PC GStreamer install via existing host package manager.
2. Board apt hot install, including old-releases source repair if needed.
3. Only if hot install fails, close FAILED and open a later PetaLinux image
   build cycle.
