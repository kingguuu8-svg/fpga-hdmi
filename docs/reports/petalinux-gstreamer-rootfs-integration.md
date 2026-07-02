# PetaLinux GStreamer Rootfs Integration

Date: 2026-07-02

## Result

PASSED for dependency/image integration.

The generated PetaLinux image now boots on the connected board with GStreamer
1.12.2, the required core tools, practical base/good/bad plugin coverage,
`kmssink`, DRM/KMS userspace tools, and V4L utilities available in the rootfs.

This does not claim the final RTP/raw-video-to-`kmssink` route is complete.
That remains a separate video-route gate.

## Changed Scope

- Added `petalinux-user-image.bbappend` to the repository overlay.
- Updated `apply-overlay.sh` so the overlay installs the image bbappend into
  the active PetaLinux project's `recipes-core/images` directory.
- Built a new `image.ub` in the verified Ubuntu 18.04 PetaLinux 2018.3
  chroot.
- Updated the TF-card `image.ub` from the running board over Ethernet after
  SHA-256 verification.
- Rebooted the board and verified GStreamer runtime commands and elements over
  UART.

## Package Policy

Included package families:

- `gstreamer1.0`
- `gstreamer1.0-meta-base`
- `gstreamer1.0-plugins-base`
- `gstreamer1.0-plugins-good`
- `gstreamer1.0-plugins-bad`
- `gstreamer1.0-rtsp-server`
- `packagegroup-petalinux-v4lutils`
- `libdrm`, `libdrm-kms`, `libdrm-tests`

Explicit exclusions:

- `gstreamer1.0-plugins-ugly`: skipped by Yocto because the restricted license
  flag is not whitelisted.
- `gstreamer1.0-libav`: skipped by Yocto because the restricted license flag is
  not whitelisted.
- `ffmpeg`: carries a commercial license flag in this PetaLinux/Yocto stack.
- `packagegroup-petalinux-gstreamer`: pulls `gstreamer1.0-omx`; OMX failed to
  compile in this Zynq-7020 image and is not required for the current
  DRM/KMS-oriented route.

## Build Evidence

- Build command:
  `rtk wsl -d Ubuntu-22.04 -u root -- bash /mnt/e/main/fpga-hdml/software/petalinux/hdmi-linux-display-stack/build-in-chroot.sh /opt/chroots/ubuntu18-petalinux2018 /home/petalinux/fpga-hdml-build/petalinux/vdma-hdmi-minimal-bionic /mnt/e/main/fpga-hdml/build/petalinux-gstreamer-rootfs-integration`
- Build result: `Attempted 4725 tasks ... all succeeded`.
- `image.ub` SHA-256:
  `3c8f131a1e8424e08a73c356bdc3e808ec6d42c79dfe5cc063642d046830d6b4`.
- `rootfs.manifest` SHA-256:
  `3f6752190bdfe926ff01f70b0d243fe807801b30064adff82ebafaa60ce6dc16`.
- Built image size copied to the board: `31795488` bytes.

## Board Update Evidence

- Board Ethernet was configured as `192.168.1.10`.
- Board pinged the PC HTTP host `192.168.1.2` successfully.
- Board downloaded `image.ub` over HTTP, verified the expected SHA-256, backed
  up the previous TF-card image, copied the new image into place, synced, and
  rebooted.
- Board update marker: `GSTREAMER_IMAGE_UPDATE_OK`.
- U-Boot loaded `31795488 bytes` from TF-card `image.ub`.
- Rebooted kernel build string changed to the new PetaLinux image build.
- Linux still exposes `/dev/dri/card0` and `/dev/fb0`.

## Runtime Evidence

Verified over UART after boot:

- `/usr/bin/gst-launch-1.0`
- `/usr/bin/gst-inspect-1.0`
- `gst-launch-1.0 version 1.12.2`
- `gst-inspect-1.0 version 1.12.2`
- Required elements present:
  `videotestsrc`, `filesrc`, `udpsrc`, `tcpclientsrc`, `tcpserversrc`,
  `rtpjitterbuffer`, `rtpvrawdepay`, `rtph264depay`, `videoconvert`,
  `videoscale`, `queue`, `capsfilter`, `identity`, `fpsdisplaysink`,
  `kmssink`, `v4l2src`, and `v4l2sink`.
- Tools present: `modetest`, `v4l2-ctl`, and `yavta`.
- A simple GStreamer pipeline passed:
  `videotestsrc num-buffers=5 ! video/x-raw,width=320,height=240,framerate=5/1 ! videoconvert ! fakesink`.
- `kmssink` is present and reports KMS sink properties including
  `driver-name`, `bus-id`, `connector-id`, `plane-id`,
  `force-modesetting`, and `can-scale`.
- A background `videotestsrc -> videoconvert -> kmssink` smoke run negotiated
  800x600 KMS caps and reached the sink, but did not complete as a clean finite
  playback route during this cycle.

## Evidence Files

- `build/petalinux-gstreamer-rootfs-integration/petalinux-build.log`
- `build/petalinux-gstreamer-rootfs-integration/rootfs.manifest`
- `build/petalinux-gstreamer-rootfs-integration/sha256sum.txt`
- `build/petalinux-gstreamer-rootfs-integration/uart-board-image-update.log`
- `build/petalinux-gstreamer-rootfs-integration/uart-gstreamer-runtime-probe.log`
- `build/petalinux-gstreamer-rootfs-integration/uart-gstreamer-element-probe.log`
- `build/petalinux-gstreamer-rootfs-integration/uart-gstreamer-pipeline-smoke.log`
- `build/petalinux-gstreamer-rootfs-integration/uart-kmssink-diag.log`
- `build/petalinux-gstreamer-rootfs-integration/uart-kmssink-bg-smoke.log`

## Rollback Point

- Git rollback point before this cycle: `d7f0a84`.
- Board rollback copy:
  `/run/media/mmcblk0p1/image.ub.prev-gstreamer-rootfs-20260702`.

## Residual Risks

- The final RTP/raw-video GStreamer route has not been run.
- PC-side GStreamer remains unresolved; the earlier winget path failed on an
  installer hash mismatch.
- `kmssink` is installed and negotiates with KMS, but a clean finite
  `kmssink` playback/EOS route still needs its own gate.
- HDMI capture validation was not run in this dependency integration cycle.
- Some X-oriented GStreamer sink packages appear in the manifest through
  GStreamer package dependencies; no desktop UI route was intentionally added.
