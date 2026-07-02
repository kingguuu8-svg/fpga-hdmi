# Current Cycle

Status: no active implementation cycle is open.

## Rule

Open a cycle here before starting implementation work that should end in a
commit. A cycle must have a concrete objective, verification plan, and closure
criteria.

## Cycle Template

```text
Cycle ID:
Objective:
Scope:
Verification plan:
Board action:
Evidence target:
pass_condition:
validator:
Highest-risk assumption this cycle falsifies:
Cheapest alternative way to falsify the same assumption:
```

The last two fields are the human review gate for opening a cycle. They force
the cycle author to state, before any work begins, which assumption is the
riskiest one being tested and whether a cheaper experiment could falsify the
same assumption. If the "cheapest alternative" line names a much shorter path
than the planned scope, the cycle direction should be reconsidered before
approval, not after debugging. These two lines exist to be read by a human at
cycle open time; they are not a self-audit checklist for cycle close.

The `pass_condition:` and `validator:` lines replace the former free-text
`Closure criteria:`. They are governed by the "Verification standard
governance" section of `AGENTS.md`:

- `pass_condition:` is a precise, numeric or boolean threshold (for example
  `mean_luma > 8`, `frame_id match rate >= 95%`, `grep finds the three named
  rules`). Free-text prose like "capture looks right" is not acceptable.
- `validator:` names the already-committed script, command, or check that
  produces the measured value. It must point to a script that existed in a
  prior commit (see the validator same-cycle prohibition rule in `AGENTS.md`),
  unless this cycle's explicit objective is to introduce a new validator, in
  which case the cycle must calibrate it against a known-good and a known-bad
  case before it may be used as the pass gate.
- These two lines are frozen once the cycle becomes active: they must not be
  edited during the work phase. To change the pass bar, close this cycle and
  open a new one with the new bar stated up front.
- The freeze must be auditable: commit the `## Active Cycle` block (with the
  frozen `pass_condition:`/`validator:` and risk-field lines) in a cycle-open
  commit BEFORE running verification, then record `measured=` in a separate
  cycle-close commit. See the Rule 1 open-commit sub-rule in `AGENTS.md`.
  Cycles whose `pass_condition` is purely structural presence may use a single
  commit.

### Optional third-party review (recorded after cycle close, non-blocking)

A closed cycle may carry a `## Third-party review` section appended after the
cycle's own report. It records an external reviewer's verification findings:
what was independently checked, whether claims hold up, and any residual
concerns the reviewer spotted that the cycle's own closure criteria did not
cover. This section is non-blocking — it does not reopen the cycle or gate the
next one. Its purpose is to leave a durable, checked record so that the next
agent or the human can read the reviewer's view alongside the cycle's own PASSED
claim, and decide whether the residual concerns deserve a follow-up cycle.
If no review was performed, omit the section entirely; do not write a
placeholder.

## Active Cycle

```text
Cycle ID: gstreamer-hot-install-first
Objective: provision the GStreamer runtime dependencies by hot install before
  considering a PetaLinux/rootfs rebuild.
Scope: install or expose PC-side GStreamer with the available host package
  manager, then try board-side apt hot install on the running TF-card Linux
  rootfs. If board apt is absent, has no network route, cannot update after
  old-releases source repair, or cannot install required packages, close this
  cycle FAILED and leave PetaLinux rebuild for a later cycle. Do not run the
  RTP video route gate in this cycle.
Verification plan: probe PC gst commands and required sender elements; probe
  board apt, rootfs free space, route/DNS, and /dev/dri/card0; if apt exists,
  try apt-get update, repair Ubuntu 18.04 sources to old-releases only if the
  update failure matches stale bionic repository symptoms, then install the
  required board GStreamer packages; re-probe gst commands/elements and record
  measured values.
Board action: UART shell commands only. Runtime rootfs package install may be
  attempted through apt. No Vivado/PetaLinux build, JTAG programming,
  BOOT.BIN/image.ub packaging, TF-card image write, board flash write, or HDMI
  capture.
Evidence target: docs/reports/gstreamer-hot-install-first.md and
  build/gstreamer-hot-install-first/
pass_condition: pc_gst_launch_present == 1 and pc_gst_inspect_present == 1
  and pc_required_gst_elements_missing == 0 and board_apt_probe_completed == 1
  and board_install_method == apt-hot-install and board_apt_update_status == pass
  and board_apt_install_status == pass and board_gst_launch_present == 1
  and board_gst_inspect_present == 1 and board_required_gst_elements_missing == 0
  and board_drm_card0_present == 1 and board_rootfs_free_mb_after >= 200
  and petalinux_image_built == 0 and tf_card_image_written == 0
validator: rtk powershell.exe -NoProfile -Command "Get-Command gst-launch-1.0,
  gst-inspect-1.0; gst-inspect-1.0 videotestsrc videoconvert rtpvrawpay udpsink"
  plus tools/uart_run_commands.ps1 running command -v apt-get, df -Pm /,
  ls -l /dev/dri/card0, apt-get update/install, command -v gst-launch-1.0,
  command -v gst-inspect-1.0, and gst-inspect-1.0 udpsrc rtpjitterbuffer
  rtpvrawdepay videoconvert kmssink.
Highest-risk assumption this cycle falsifies: the running board Linux rootfs
  can install the missing GStreamer stack in place through apt, so no slow
  PetaLinux rebuild is needed for the mature Linux route.
Cheapest alternative way to falsify the same assumption: probe command -v
  apt-get and apt-get update before any package install; if apt or networked
  package index update is impossible, the hot-install route is false.
```

## Recently Closed Cycle

```text
Cycle ID: gstreamer-rtp-kmssink-route-gate
Result: FAILED before verification. The GStreamer direction is correct, but
  the independent audit in docs/reports/eth-ps-pl-hdmi-pass-through.md found
  that the frozen pass_condition removed required rulers:
  frame_duration_stddev_ms<=4.0, frame-drop accountability, and frame-id
  correspondence. Per Rule 1, the frozen bar is not edited in place; the next
  cycle must reopen with corrected thresholds before running verification.
  pass_condition=(pc_gst_launch_present == 1 and board_gst_launch_present == 1
  and board_required_gst_elements_present == 5 and
  board_required_gst_elements_missing == 0 and board_sink == kmssink and
  board_display_device == /dev/dri/card0 and transport == rtp-raw-udp and
  self_written_udp_receiver_used == 0 and fbdev_live_write_used == 0 and
  pc_sender_frames >= 120 and hdmi_captured_frames >= 120 and
  captured_motion_frames >= 120 and tearing_frames == 0 and
  validator_status == pass),
  measured=(not_run, audit_status=fail,
  missing_required_gate_fields=frame_duration_stddev_ms<=4.0,
  drop_rate<=0.05_or_sent_equals_received, frame_id_correspondence).
Evidence: docs/reports/gstreamer-rtp-kmssink-route-gate.md and
  docs/reports/eth-ps-pl-hdmi-pass-through.md
Board action: none. No UART command, Ethernet test, HDMI capture,
  Vivado/PetaLinux build, TF-card write, JTAG programming, or board flash
  write was performed.

Cycle ID: gstreamer-rtp-kmssink-corrected-route-gate
Result: FAILED. The corrected pass gate restored smoothness, drop-rate, and
  frame-id correspondence rulers, then failed at the cheapest dependency
  check: PC `gst-launch-1.0` and `gst-inspect-1.0` are missing, and board
  `gst-launch-1.0` and `gst-inspect-1.0` are also missing. `/dev/dri/card0`
  exists, but the current image cannot run `kmssink` or required GStreamer
  elements. No RTP sender, receive pipeline, HDMI capture, trace validator, or
  tearing validator was run.
  pass_condition=(pc_gst_launch_present == 1 and board_gst_launch_present == 1
  and pc_required_gst_elements_missing == 0 and
  board_required_gst_elements_missing == 0 and board_sink == kmssink and
  board_display_device == /dev/dri/card0 and transport == rtp-raw-udp and
  jitter_buffer == rtpjitterbuffer and self_written_udp_receiver_used == 0
  and fbdev_live_write_used == 0 and trace_sent_frames >= 120 and
  trace_captured_frames >= 114 and trace_matched_frames >= 114 and
  trace_drop_rate <= 0.05 and trace_order_violations == 0 and
  trace_content_mismatches == 0 and trace_black_frames == 0 and
  trace_image_path_failures == 0 and hdmi_captured_frames >= 120 and
  frame_duration_stddev_ms <= 4.0 and tearing_frames == 0 and
  unified_validator_status == pass and tearing_validator_status == pass),
  measured=(pc_gst_launch_present=0, board_gst_launch_present=0,
  pc_required_gst_elements_missing=5, board_required_gst_elements_missing=5,
  board_sink=missing, board_display_device=/dev/dri/card0, transport=not-run,
  jitter_buffer=missing, self_written_udp_receiver_used=0,
  fbdev_live_write_used=0, trace_sent_frames=0, trace_captured_frames=0,
  trace_matched_frames=0, trace_drop_rate=1.0,
  trace_order_violations=not-run, trace_content_mismatches=not-run,
  trace_black_frames=not-run, trace_image_path_failures=not-run,
  hdmi_captured_frames=0, frame_duration_stddev_ms=not-run,
  tearing_frames=not-run, unified_validator_status=not-run,
  tearing_validator_status=not-run).
Evidence: docs/reports/gstreamer-rtp-kmssink-corrected-route-gate.md
Board action: UART shell inspection only. No Ethernet video send, HDMI
  capture, Vivado/PetaLinux build, TF-card write, JTAG programming, or board
  flash write was performed.

Cycle ID: gstreamer-dependency-provisioning
Result: FAILED before provisioning. The cycle was opened with a pass condition
  that required PetaLinux image rebuild and TF-card update. A shorter valid
  route exists: hot-installing GStreamer into the running Linux rootfs via apt
  if apt and network access work. Because the frozen bar cannot be edited in
  place, this cycle is closed and a hot-install-first cycle must be opened.
  pass_condition=(pc_gst_launch_present == 1 and pc_gst_inspect_present == 1
  and pc_required_gst_elements_missing == 0 and board_gst_launch_present == 1
  and board_gst_inspect_present == 1 and board_required_gst_elements_missing
  == 0 and board_drm_card0_present == 1 and petalinux_image_built == 1 and
  board_booted_updated_image == 1 and tf_card_update_verified == 1),
  measured=(pc_gst_launch_present=0, pc_gst_inspect_present=0,
  board_gst_launch_present=0, board_gst_inspect_present=0,
  board_drm_card0_present=1, petalinux_image_built=0,
  board_booted_updated_image=0, tf_card_update_verified=0,
  cycle_scope_error=hot_install_path_excluded).
Evidence: docs/reports/gstreamer-dependency-provisioning.md
Board action: none.

Cycle ID: drm-kms-local-motion-pacing
Result: PASSED. Isolated the board display side by generating textured motion
  locally on the Zynq Linux userspace process, writing only DRM dumb back
  buffers, and presenting with DRM/KMS page-flip vblank events. The connected
  board run proved the current display path can meet the frozen
  smoothness/tearing gate when full-frame UDP receive is removed:
  drm_dumb_buffers=2, drm_page_flip_calls=120,
  drm_vblank_flip_events=120, generated_frames=120,
  captured_motion_frames=255, tearing_frames=0,
  frame_duration_stddev_ms=1.514, and validator_status=pass.
  pass_condition=(display_backend == drm-kms and drm_device == /dev/dri/card0
  and video_source == board-generated-textured-motion and
  fbdev_live_write_used == 0 and drm_dumb_buffers == 2 and
  drm_page_flip_calls == 120 and drm_vblank_flip_events == 120 and
  generated_frames == 120 and motion_content_type == textured-motion and
  captured_motion_frames >= 120 and tearing_frames == 0 and
  frame_duration_stddev_ms <= 4.0 and validator_status == pass),
  measured=(display_backend=drm-kms, drm_device=/dev/dri/card0,
  video_source=board-generated-textured-motion, fbdev_live_write_used=0,
  drm_dumb_buffers=2, drm_page_flip_calls=120,
  drm_vblank_flip_events=120, generated_frames=120,
  motion_content_type=textured-motion, captured_motion_frames=255,
  tearing_frames=0, frame_duration_stddev_ms=1.514,
  validator_status=pass).
Evidence: docs/reports/drm-kms-local-motion-pacing.md
Board action: deployed and ran the Linux DRM/KMS local-motion binary from
  /tmp, generated textured motion on the board, page-flipped /dev/dri/card0
  dumb buffers, captured HDMI through UVC, and used UART shell control. No
  Vivado/PetaLinux/JTAG/TF-card/flash write.

Cycle ID: drm-kms-vblank-motion-tearing
Result: FAILED. Implemented a Linux userspace DRM/KMS receiver using
  /dev/dri/card0, two dumb buffers, and legacy page-flip events. The connected
  board run proved the functional Linux network-to-DRM-to-HDMI path:
  60 textured-motion frames sent, 60 receiver writes, dropped=0,
  drm_dumb_buffers=2, drm_page_flip_calls=60, drm_vblank_flip_events=60,
  captured_motion_frames=120, tearing_validator_calibrated=1, tearing_frames=0,
  and validator_status=pass. The cycle still failed its frozen smoothness gate:
  pass_condition=(display_backend == drm-kms and drm_device == /dev/dri/card0
  and fbdev_live_write_used == 0 and drm_dumb_buffers == 2 and
  drm_page_flip_calls == 60 and drm_vblank_flip_events == 60 and
  sent_frames == 60 and receiver_written_frames == 60 and
  receiver_dropped_packets == 0 and motion_content_type == textured-motion
  and captured_motion_frames >= 60 and tearing_validator_calibrated == 1 and
  tearing_frames == 0 and frame_duration_stddev_ms <= 4.0 and
  validator_status == pass),
  measured=(display_backend=drm-kms, drm_device=/dev/dri/card0,
  fbdev_live_write_used=0, drm_dumb_buffers=2, drm_page_flip_calls=60,
  drm_vblank_flip_events=60, sent_frames=60, receiver_written_frames=60,
  receiver_dropped_packets=0, motion_content_type=textured-motion,
  captured_motion_frames=120, tearing_validator_calibrated=1,
  tearing_frames=0, frame_duration_stddev_ms=19.614,
  validator_status=pass).
Evidence: docs/reports/drm-kms-vblank-motion-tearing.md
Board action: deployed and ran the Linux DRM/KMS receiver from /tmp, sent PC
  UDP textured-motion payloads over Ethernet, page-flipped /dev/dri/card0
  dumb buffers, captured HDMI through UVC, and used UART shell control. No
  Vivado/PetaLinux/JTAG/TF-card/flash write.

Cycle ID: linux-net-to-hdmi-direct-copy
Result: PASSED. Implemented and verified the review-recommended Tier 1 Linux
  path: PC sender emits framebuffer-native 24bpp payloads, the Linux receiver
  starts with `FB_COPY_MODE mode=direct-memcpy`, writes complete UDP frames to
  /dev/fb0 with direct row memcpy, and HDMI/UVC saved-image trace validation
  matches all 30 validation frames. No Vivado, PetaLinux, device-tree,
  bitstream, TF-card, or persistent board write was performed.
  pass_condition=(receiver_fb_copy_mode == direct-memcpy and
  sender_wire_format == fb24-native and sender_fps == 15 and sent_frames == 30
  and receiver_written_frames == 30 and receiver_dropped_packets == 0 and
  receiver_effect == none and trace_require_image_paths == 1 and
  trace_image_path_failures == 0 and validator_status == pass and
  trace_sent_frames == 30 and trace_matched_frames >= 29 and
  trace_drop_rate <= 0.05 and trace_order_violations == 0 and
  trace_content_mismatches == 0 and trace_black_frames == 0 and
  trace_max_latency_ms <= 1000),
  measured=(receiver_fb_copy_mode=direct-memcpy,
  sender_wire_format=fb24-native, sender_fps=15, sent_frames=30,
  receiver_written_frames=30, receiver_dropped_packets=0,
  receiver_effect=none, mjpeg_saved_frames=520, mjpeg_unique_hashes=42,
  mjpeg_unique_colors=8, trace_require_image_paths=1,
  trace_image_path_failures=0, validator_status=pass, trace_sent_frames=30,
  trace_matched_frames=30, trace_drop_rate=0.0, trace_order_violations=0,
  trace_content_mismatches=0, trace_black_frames=0,
  trace_mean_latency_ms=27.038, trace_max_latency_ms=62.382).
Evidence: docs/reports/linux-net-to-hdmi-direct-copy.md
Board action: deployed and ran the Linux receiver from /tmp, sent PC UDP
  fb24-native payloads over Ethernet, wrote /dev/fb0, captured HDMI through
  UVC, and used UART shell control. No Vivado/PetaLinux/JTAG/TF-card/flash
  write.

Cycle ID: dashboard-truthful-sent-received-timelines
Result: FAILED, frozen at user request. The Dashboard left preview now reports
  `latest-actual-sent-frame` instead of pairing to the HDMI frame ID, and the
  connected-board trace matched 90/90 returned HDMI frames with drop_rate=0.0.
  However the frozen pass condition required actual sender cadence between
  9.5 and 10.5 fps, and the run measured only 8.047 fps. The cycle therefore
  cannot be marked passed or rescued by changing the threshold after the run.
  pass_condition=(preview_source == latest-actual-sent-frame and
  configured_sender_fps == 10 and 9.5 <= sender_measured_fps <= 10.5 and
  receiver_present_fps == 10 and hdmi_delivery_fps == 10 and
  content_dwell_seconds == 5 and timeline_samples >= 20 and
  negative_lag_samples == 0 and positive_lag_samples >= 1 and
  distinct_sent_ids >= 3 and distinct_hdmi_ids >= 3 and max_lag_frames <= 30
  and sent_frames == 90 and receiver_written_frames == 90 and
  receiver_dropped_packets == 0 and validator_status == pass and
  trace_matched_frames >= 86 and trace_drop_rate <= 0.05 and
  trace_order_violations == 0 and trace_content_mismatches == 0 and
  trace_black_frames == 0 and trace_image_path_failures == 0 and
  trace_max_latency_ms <= 1000),
  measured=(preview_source=latest-actual-sent-frame,
  configured_sender_fps=10, sender_measured_fps=8.047,
  receiver_present_fps=10, hdmi_delivery_fps=10,
  content_dwell_seconds=5, timeline_samples=20, negative_lag_samples=0,
  positive_lag_samples=3, distinct_sent_ids=4, distinct_hdmi_ids=4,
  max_lag_frames=2, sent_frames=90, receiver_written_frames=90,
  receiver_dropped_packets=0, validator_status=pass,
  trace_matched_frames=90, trace_drop_rate=0.0, trace_order_violations=0,
  trace_content_mismatches=0, trace_black_frames=0,
  trace_image_path_failures=0, trace_max_latency_ms=135.028).
Evidence: docs/reports/dashboard-truthful-sent-received-timelines.md
Board action: deployed and ran the Linux receiver from /tmp, sent Dashboard-
  owned UDP RGB888, captured HDMI through UVC, and used UART shell control. No
  Vivado/PetaLinux/JTAG/TF-card/flash write.

Cycle ID: dashboard-unified-15fps-paired-preview
Result: FAILED. Dashboard start-stream launched the unified sender and the
  transport validator reached 90/90 matches with board dropped=0, but the
  implementation made the left panel follow the HDMI-decoded frame_id. The user
  rejected that semantic because it hides natural latency instead of showing
  the independently sent and received timelines. A supplemental measurement
  also found configured sender_fps=15 produced only 12.011 actual fps.
  pass_condition=(dashboard_sender_kind == unified and sender_fps == 15 and
  receiver_present_fps == 15 and hdmi_sample_fps == 15 and
  content_dwell_seconds == 5 and paired_preview_samples >= 20 and
  paired_preview_id_mismatches == 0 and sent_frames == 90 and
  receiver_written_frames == 90 and receiver_dropped_packets == 0 and
  validator_status == pass and trace_matched_frames >= 86 and
  trace_drop_rate <= 0.05 and trace_order_violations == 0 and
  trace_content_mismatches == 0 and trace_black_frames == 0 and
  trace_image_path_failures == 0 and trace_max_latency_ms <= 1000),
  measured=(dashboard_sender_kind=unified, configured_sender_fps=15,
  sender_measured_fps=12.011,
  receiver_present_fps=15, hdmi_sample_fps=15, content_dwell_seconds=5,
  paired_preview_samples=20, paired_preview_id_mismatches=0, sent_frames=90,
  receiver_written_frames=90, receiver_dropped_packets=0,
  validator_status=pass, trace_matched_frames=90, trace_drop_rate=0.0,
  trace_order_violations=0, trace_content_mismatches=0,
  trace_black_frames=0, trace_image_path_failures=0,
  trace_max_latency_ms=141.088, user_acceptance=failed-paired-preview-rejected).
Evidence: docs/reports/dashboard-unified-15fps-paired-preview.md
Board action: deployed and ran the Linux receiver from /tmp, sent Dashboard-
  owned UDP RGB888, captured HDMI through UVC, and used UART shell control. No
  Vivado/PetaLinux/JTAG/TF-card/flash write.

Cycle ID: verification-standard-governance-fix
Result: PASSED. Closed the Rule 1 auditability gap exposed by the
  post-governance audit: the frozen pass_condition must now be committed in a
  cycle-open commit before verification runs, with a structural-presence
  exception for docs/governance cycles. Git management was reconciled to
  require two commits (open + close) for implementation cycles with a tunable
  pass_condition. The boundary-fix report's inaccurate "opened before
  implementation" claim was corrected. Third-party review sections with
  independently re-run validator evidence were appended to the boundary-fix
  and 15fps reports.
  pass_condition=(check1_open_commit_subrule_in_agents == present and
  check2_two_commit_in_git_mgmt == present and check3_template_crossref ==
  present and check4_false_assertion_gone == 0 and
  check4_correction_present == 1 and check5_boundaryfix_review == present and
  check6_15fps_review == present),
  measured=(check1_open_commit_subrule_in_agents=present(grep=2),
  check2_two_commit_in_git_mgmt=present(grep=1),
  check3_template_crossref=present(grep=4), check4_false_assertion_gone=0,
  check4_correction_present=1, check5_boundaryfix_review=present(grep=1),
  check6_15fps_review=present(grep=1)).
Evidence: docs/reports/unified-validator-boundary-order-fix.md (corrected
  residual risk + Third-party review),
  docs/reports/unified-15fps-image-evidence-pass-through.md (Third-party
  review), AGENTS.md, docs/current-cycle.md.
Board action: none; docs/governance cycle only. Independent validator re-runs
  were PC-side and touched no board hardware.

Cycle ID: unified-15fps-image-evidence-pass-through
Result: PASSED. The board-live loop now passes the unified validator with
  saved HDMI image evidence. PC sent 30 unique 15 fps validation frames with
  image-decodable markers; the Linux receiver wrote all 30 validation frame
  IDs with dropped=0; the HDMI MJPEG probe saved 220 frames with 47 unique
  hashes and 8 decoded colors; the trace builder decoded all 30 validation
  frame IDs from saved JPEGs with require_image_paths=true; the committed
  validator reported matched_frames=30, drop_rate=0.0, order_violations=0,
  content_mismatches=0, black_frames=0, image_path_failures=0, and max
  return-path latency=257.561 ms under the recorded 1000 ms HDMI-UVC/MJPEG
  trace requirement.
  pass_condition=(sender_fps == 15 and sent_frames == 30 and
  receiver_written_frames == 30 and receiver_dropped_packets == 0 and
  mjpeg_saved_frames >= 60 and mjpeg_unique_hashes >= 8 and
  mjpeg_unique_colors >= 8 and trace_require_image_paths == 1 and
  trace_image_path_failures == 0 and validator_status == pass and
  trace_sent_frames == 30 and trace_matched_frames >= 29 and
  trace_drop_rate <= 0.05 and trace_order_violations == 0 and
  trace_content_mismatches == 0 and trace_black_frames == 0),
  measured=(sender_fps=15, sent_frames=30, receiver_written_frames=30,
  receiver_dropped_packets=0, mjpeg_saved_frames=220,
  mjpeg_unique_hashes=47, mjpeg_unique_colors=8,
  trace_require_image_paths=1, trace_image_path_failures=0,
  validator_status=pass, trace_sent_frames=30, trace_matched_frames=30,
  trace_drop_rate=0.0, trace_order_violations=0,
  trace_content_mismatches=0, trace_black_frames=0).
Evidence: docs/reports/unified-15fps-image-evidence-pass-through.md
Board action: ran a Linux userspace receiver from /tmp, sent generated UDP
  RGB888 frames from the PC over Ethernet, captured HDMI through the PC UVC
  adapter, and used UART only for Linux shell control. No Vivado build,
  PetaLinux build, JTAG programming, TF-card write, QSPI, NAND, eMMC, or other
  board flash write.

Cycle ID: unified-validator-boundary-order-fix
Result: PASSED. Fixed the two third-party-reviewed validator edge defects:
  exact 19/20 boundary handling now reports drop_rate=0.05 and passes the
  95% threshold, and an unmatched high frame_id capture no longer creates a
  spurious frame_order_violation before a later legitimate frame. Real
  wrong-order traces still fail with frame_order_violation.
  pass_condition=(calibration_status == pass and boundary_19_of_20_status ==
  pass and boundary_19_of_20_drop_rate == 0.05 and
  unmatched_high_then_lower_status == fail and
  unmatched_high_then_lower_has_unmatched_capture == 1 and
  unmatched_high_then_lower_has_frame_order_violation == 0 and
  wrong_order_status == fail and wrong_order_has_frame_order_violation == 1),
  measured=(calibration_status=pass, boundary_19_of_20_status=pass,
  boundary_19_of_20_drop_rate=0.05,
  unmatched_high_then_lower_status=fail,
  unmatched_high_then_lower_has_unmatched_capture=1,
  unmatched_high_then_lower_has_frame_order_violation=0,
  wrong_order_status=fail, wrong_order_has_frame_order_violation=1).
Evidence: docs/reports/unified-validator-boundary-order-fix.md
Board action: none. PC-side validator defect-fix cycle only; no Vivado,
  PetaLinux, JTAG, TF-card, UART, Ethernet, HDMI, or board flash action.

Cycle ID: unified-passthrough-validator-calibration
Result: PASSED. Added and calibrated the reusable temporal pass-through
  validator. pass_condition=(known_good_pass == 1 and known_bad_black_fail ==
  1 and known_bad_wrong_order_fail == 1 and known_bad_missing_frame_fail == 1
  and known_bad_wrong_content_fail == 1 and known_bad_latency_fail == 1),
  measured=(known_good_pass=1, known_bad_black_fail=1,
  known_bad_wrong_order_fail=1, known_bad_missing_frame_fail=1,
  known_bad_wrong_content_fail=1, known_bad_latency_fail=1).
Evidence: docs/reports/unified-passthrough-validator-calibration.md
Board action: none. PC-side validator/calibration cycle only; no Vivado,
  PetaLinux, JTAG, TF-card, UART, Ethernet, HDMI, or board flash action.

Cycle ID: verification-standard-governance
Result: PASSED. Added three structural rules to AGENTS.md (pass-condition
  preregistration/freeze, validator same-cycle prohibition, cycle-log
  threshold+measured) and updated the Cycle Template and cycle-log Entry
  Template to match. pass_condition=(three named rules present; template
  fields present), measured=(grep audit 0 missing).
Evidence: docs/cycle-log.md (2026-07-01 verification-standard-governance)
Board action: none; docs-only governance cycle.

Cycle ID: dashboard-color-block-loop-and-uart-audit
Result: PASSED. Replaced the ambiguous generated demo with full-screen
  sequential color blocks, classified the live HDMI MJPEG return stream as the
  source color set, fixed the Linux console cursor overlay, and made Dashboard
  UART pause/resume/status actions return real receiver markers. The finite
  board loop sent 12 color-block frames, the receiver wrote 12 frames with
  packets=14400 and dropped=0, and the MJPEG probe read 80 returned frames with
  8 unique colors.
Evidence: docs/reports/dashboard-color-block-loop-and-uart-audit.md
Board action: ran Linux userspace receivers from /tmp, sent generated UDP
  frames from the PC, streamed HDMI through the PC capture adapter, and sent
  UART shell commands to /tmp/video_ctl. No Vivado/PetaLinux/JTAG/TF-card/flash
  action.

Cycle ID: dashboard-live-pass-through-preview
Result: PASSED. Added a live HDMI MJPEG return endpoint for the dashboard right
  panel and changed the board-live helper to validate that same stream. The
  connected board wrote 12 no-effect generated frames, 14400 packets, dropped=0;
  the MJPEG probe read 80 returned HDMI frames from /api/output-stream.mjpeg
  with 26 unique hashes.
Evidence: docs/reports/dashboard-live-pass-through-preview.md
Board action: ran a Linux userspace receiver from /tmp, sent generated UDP
  frames from the PC through Dashboard, and streamed HDMI through the PC
  capture adapter. No Vivado/PetaLinux/JTAG/TF-card/flash action.

Cycle ID: dashboard-truthful-loop-validation
Result: PASSED. Corrected the dashboard closed-loop demo so the input preview
  is generated from the exact sender source, start-stream schedules HDMI
  capture asynchronously instead of blocking the button response, and the
  board-live helper requires dynamic HDMI sample hashes. The connected board
  wrote 12 generated frames, 14400 UDP packets, dropped=0; HDMI capture on
  DirectShow index 1 passed non-black validation and saved six samples with
  five unique hashes.
Evidence: docs/reports/dashboard-truthful-loop-validation.md
Board action: ran a Linux userspace receiver from /tmp, sent generated UDP
  frames from the PC through Dashboard, and captured HDMI. No Vivado/PetaLinux/
  JTAG/TF-card/flash action.

Cycle ID: dashboard-board-live-loop
Result: PASSED. Added a displayable board-live loop helper. It builds/deploys
  the Linux receiver to /tmp, starts it with /tmp/video_ctl, starts the
  dashboard, triggers Dashboard `start-stream`, sends five generated RGB888
  frames, verifies five VIDEO_UDP_FRAME_WRITTEN markers and
  VIDEO_UDP_RECEIVER_DONE frames=5 packets=6000 dropped=0, and validates HDMI
  capture with non-black mean_luma=136.39. The captured image shows the
  generated demo frame.
Evidence: docs/reports/dashboard-board-live-loop.md
Board action: ran a Linux userspace receiver from /tmp, sent UDP frames from
  the PC through Dashboard, and captured HDMI. No Vivado/PetaLinux/JTAG/flash
  action.

Cycle ID: dashboard-hdmi-capture-timeout-fix
Result: PASSED. Real dashboard `start-stream` initially hit
  HDMI_CAPTURE_TIMEOUT because the dashboard timeout was shorter than the
  DirectShow capture latency. The timeout is now at least 90 seconds and the
  default preview capture frame count is 8. Retest returned HDMI_CAPTURE_OK,
  capture_status=ok, and image_exists=true.
Evidence: docs/reports/dashboard-hdmi-capture-timeout-fix.md
Board action: PC-side dashboard process and HDMI capture only. No
  Vivado/PetaLinux/JTAG/flash action.

Cycle ID: dashboard-hdmi-capture-binding
Result: PASSED. Added HDMI preview capture binding to the dashboard. The
  capture tool now supports validation-profile none for preview captures.
  `start-stream` launches the sender and then attempts HDMI capture;
  `capture-output` refreshes HDMI manually. Live capture opened DirectShow
  device index 0 and wrote latest.png, but the frame was near black
  (mean_luma=0.05), so meaningful board output still depends on receiver
  readiness.
Evidence: docs/reports/dashboard-hdmi-capture-binding.md
Board action: PC-side HDMI capture only. No Vivado/PetaLinux/JTAG/flash action.

Cycle ID: dashboard-live-minimal-controls
Result: PASSED. The dashboard UI is now a plain functional view with no
  decorative background, gradients, shadows, or card styling. Start stream
  launches a real dashboard-owned demo sender subprocess; Stop stream
  terminates it. Self-test received a real localhost ZVID UDP packet from the
  sender and verified UART actions return UART_NOT_CONFIGURED when no UART port
  is provided.
Evidence: docs/reports/dashboard-live-minimal-controls.md
Board action: none. UART live binding was implemented but not exercised against
  the connected board in this automated cycle.

Cycle ID: dashboard-control-integration
Result: PASSED. The PC dashboard now exposes `/api/actions` and `/api/action`
  plus active control buttons. Self-test posted six dry-run actions covering
  sender start/stop, UART/FIFO pause/resume/status semantics, and effect launch
  semantics. Final state recorded stream_state=stopped, receiver_paused=false,
  selected_effect=invert, and no camera/custom-file input.
Evidence: docs/reports/dashboard-control-integration.md
Board action: none. PC-side dry-run dashboard action surface only.

Cycle ID: fixed-demo-video-sender
Result: PASSED. Added a fixed built-in deterministic RGB888 dynamic video
  source and UDP sender for the dashboard MVP. Self-test proved generated frame
  size, dynamic frame difference, localhost UDP packetization, 30/30 received
  packets, full payload byte count, and stable frame id. Parser inspection
  confirmed there is no camera/webcam/file input option. The result explicitly
  keeps camera/webcam input disabled and custom-file input deferred after MVP.
Evidence: docs/reports/fixed-demo-video-sender.md
Board action: none. PC-side fixed demo-video sender only.

Cycle ID: visual-dashboard-scaffold
Result: PASSED. Added a Python-stdlib PC dashboard scaffold with three visual
  regions: generated input preview, FPGA HDMI-output preview slot, and
  function-control/log panel skeleton. Self-test fetched the HTML, state JSON,
  generated input SVG, and output placeholder SVG. The state explicitly reports
  camera_enabled=false and custom_file_enabled=false.
Evidence: docs/reports/visual-dashboard-scaffold.md
Board action: none. PC dashboard scaffold only.

Cycle ID: first-board-side-effect
Result: PASSED. The Linux receiver now supports a board-side RGB invert effect.
  PC sent the deterministic non-camera rgb-stripes UDP frame; board logs showed
  VIDEO_UDP_FRAME_WRITTEN frame_id=200 effect=invert and
  VIDEO_UDP_RECEIVER_DONE frames=1 packets=1200 dropped=0. HDMI capture using
  the inverted-rgb-stripes profile returned HDMI_CAPTURE_OK.
Evidence: docs/reports/first-board-side-effect.md
Board action: ran a userspace binary from /tmp, sent one generated UDP frame
  from the PC, and captured HDMI for output verification. No camera/webcam
  video input, no Vivado rebuild, no PetaLinux rebuild, no JTAG programming,
  and no board flash writes.

Cycle ID: uart-control-endpoint
Result: PASSED. The Linux receiver now supports a FIFO control endpoint that
  can be driven from the UART shell. UART `pause` caused a complete UDP frame
  to log VIDEO_UDP_FRAME_SKIPPED_PAUSED instead of writing /dev/fb0; UART
  `resume` and `status` were accepted, the next UDP frame was written, and HDMI
  capture returned HDMI_CAPTURE_OK.
Evidence: docs/reports/uart-control-endpoint.md
Board action: ran a userspace binary from /tmp, wrote control commands through
  the UART shell to /tmp/video_ctl, sent UDP frames from the PC, and captured
  HDMI. No Vivado rebuild, no PetaLinux rebuild, no JTAG programming, and no
  board flash writes.

Cycle ID: sustained-low-fps-stream
Result: PASSED. The Linux UDP receiver handled a five-frame 800x600 RGB888
  low-FPS stream. PC sent 6000 UDP packets; board logs showed five
  VIDEO_UDP_FRAME_WRITTEN markers and VIDEO_UDP_RECEIVER_DONE frames=5
  packets=6000 dropped=0. HDMI capture after the stream returned
  HDMI_CAPTURE_OK.
Evidence: docs/reports/sustained-low-fps-stream.md
Board action: ran a userspace binary from /tmp after downloading it through a
  one-shot Ethernet file server, sent UDP frames from the PC, and captured
  HDMI. No Vivado rebuild, no PetaLinux rebuild, no JTAG programming, and no
  board flash writes.

Cycle ID: ethernet-video-userspace-receiver
Result: PASSED. A Linux userspace ARM receiver now accepts the project UDP
  RGB888 frame protocol on port 5005, assembles a complete 800x600 frame,
  maps protocol RGB into the actual /dev/fb0 channel byte order, and writes the
  frame to the proven VDMA/DRM HDMI framebuffer. PC sent one rgb-stripes frame
  as 1200 UDP packets; board log showed packets=1200 dropped=0 and HDMI
  capture validation returned HDMI_CAPTURE_OK.
Evidence: docs/reports/ethernet-video-userspace-receiver.md
Board action: ran a userspace binary from /tmp after downloading it over
  Ethernet, sent UDP from the PC, and captured HDMI. No Vivado rebuild, no
  PetaLinux rebuild, no JTAG programming, and no QSPI, NAND, eMMC, or other
  board flash writes.

Cycle ID: hdmi-linux-fixed-mode-connector
Result: PASSED. Linux now exposes a connected fixed-mode HDMI connector,
  /dev/dri/card0, and /dev/fb0. The VDMA DMA-decode failure was traced to a
  Linux CMA allocation outside the official VDMA DDR window documented in
  docs/boards/hellofpga-smart-zynq-sl.md; moving CMA inside that window removed
  VDMA errors and flip timeouts. A userspace /dev/fb0 write changed HDMI from
  the Linux login console to a deterministic three-stripe image, and automated
  HDMI capture validation passed.
Evidence: docs/reports/hdmi-linux-fixed-mode-connector.md
Board action: replaced image.ub on the TF-card FAT boot partition via board
  Linux wget over Ethernet, retained backups, rebooted from TF card, wrote a
  test frame through /dev/fb0, and captured HDMI. No JTAG programming, QSPI,
  NAND, eMMC, or other board nonvolatile storage writes.

Cycle ID: hdmi-linux-display-stack
Result: PARTIAL. The project image now enables Xilinx PL display DRM
  (CONFIG_DRM_XLNX=y, CONFIG_DRM_XLNX_PL_DISP=y), boots from the TF card, and
  exposes /dev/dri/card0. HDMI capture still sees stable 800x600 color bars.
  The image is not yet Linux-controllable because DRM has no connector/mode
  provider: /dev/fb* is absent, /sys/class/drm/card0 has no status/modes/enabled
  files, and dmesg says "[drm] Cannot find any crtc or sizes".
Evidence: docs/reports/hdmi-linux-display-stack.md
Board action: replaced image.ub on the TF-card FAT boot partition via board
  Linux wget over Ethernet, backed up the old image.ub on the same partition,
  rebooted from TF card, and captured UART/HDMI evidence. No JTAG programming,
  QSPI, NAND, eMMC, or other nonvolatile board storage writes.

Cycle ID: petalinux-vdma-hdmi-minimal-project
Result: PASSED. The VDMA HDMI hardware description was made Linux-consumable by
  connecting VDMA MM2S/S2MM interrupts to PS IRQ_F2P. PetaLinux 2018.3 built
  image.ub in the Ubuntu 18.04 chroot, packaged BOOT.BIN, and copied BOOT.BIN +
  image.ub to the ZYNQBOOT TF-card partition with matching SHA256 hashes.
Evidence: docs/reports/petalinux-vdma-hdmi-minimal-project.md
Board action: TF-card file write only; no board boot or nonvolatile flash write.

Cycle ID: vdma-boot-probe-verify
Result: PASSED. The project-built TF-card image boots to Linux userspace,
  accepts root/root over UART, eth0 links at 1000/Full and pings from the PC
  with 0% loss, and the VDMA node binds to the xilinx-vdma platform driver.
  No /dev/dri or /dev/fb* node appears, so HDMI/display output remains a
  separate device-tree/display-stack follow-up.
Evidence: docs/reports/vdma-boot-probe-verify.md
Board action: booted generated image from TF card only; no JTAG programming,
  QSPI, NAND, eMMC, or other nonvolatile board storage writes.
```

## Resolved Route Gate

The TF-card Linux ping route gate PASSED on 2026-06-29.

```text
Cycle ID: eth-ps-pl-hdmi-pass-through (route-gate phase)
Result: PASSED. Official Linux boots from TF card, eth0 link up at 1000/Full,
  PC ping 192.168.1.10 = 4/4 received, 0% loss.
Evidence: docs/reports/tf-card-linux-ping-2026-06-29.md
Decision: Outcome A - proceed on Linux/socket route, retire hand-written
  baremetal RGMII bridge.
```

## Current Decision

The active implementation route is now confirmed by hardware evidence:

```text
PC UDP RGB888 frame -> Linux userspace socket receiver -> DDR framebuffer
-> VDMA MM2S -> v_axi4s_vid_out -> rgb2dvi -> HDMI
```

The hand-written baremetal RGMII bridge + lwIP route is retired. It was
verified as a dead end: the same physical path that fails under the hand-written
bridge works perfectly under Linux + official macb driver (RX errors=0, ping
0% loss). The bridge code remains in the repo as negative evidence only.

## Current Evidence

Known-good subchains:

```text
Official VDMA HDMI image passed on connected board and PC HDMI capture.
Official pure-PL UDP loopback passed over the same PC/RJ45/RTL8211E path.
Official Linux boots from TF card, eth0 1000/Full, RX errors=0, ping 0% loss.
PetaLinux 2018.3 host tooling is installed and command-visible in WSL.
Project baremetal board-to-PC UDP heartbeat works (but PC-to-board RX does not).
Project Linux exposes a connected DRM HDMI output and /dev/fb0.
Linux userspace framebuffer writes pass automated HDMI capture validation.
Project Linux userspace UDP receiver receives a complete 800x600 RGB888 frame
and updates the physical HDMI output through /dev/fb0.
Project Linux userspace UDP receiver handles a five-frame low-FPS stream with
6000 UDP packets, dropped=0, and HDMI capture validation after the stream.
Project Linux receiver accepts UART-shell-driven pause/resume/status commands
through a FIFO control endpoint without breaking UDP receive or HDMI output.
Project Linux receiver applies a board-side RGB invert effect to generated PC
UDP input and HDMI capture validates the inverted output.
PC dashboard scaffold exposes generated input preview, FPGA HDMI return
preview, and function-control/log panel regions without camera or custom-file
input.
PC fixed demo sender generates deterministic dynamic RGB888 frames and
packetizes them through the existing UDP protocol without camera or custom-file
input.
PC dashboard control API exposes tested dry-run sender, UART/FIFO, and effect
actions without camera or custom-file input.
PC dashboard is now minimal and `start-stream`/`stop-stream` control a real
local demo sender subprocess. UART/FIFO controls are wired to the UART helper
but require a ready board receiver FIFO.
PC dashboard `start-stream` starts the real demo sender and exposes the live
HDMI return endpoint. `capture-output` remains a manual still-capture fallback.
Dashboard board-live loop now deploys/starts the receiver, drives Dashboard
`start-stream`, receives/writes twelve generated no-effect frames with
dropped=0, and validates the right-panel `/api/output-stream.mjpeg` HDMI return
stream with 80 returned frames and 26 unique hashes.
Dashboard color-block loop now uses full-screen sequential color blocks as the
PC source and validates the live HDMI return stream by classifying returned
MJPEG frames as the source colors.
Dashboard UART pause/resume/status actions now return real receiver markers
from the running board receiver through `/tmp/video_ctl`.
Unified pass-through trace validator is calibrated against synthetic good/bad
cases and is the required pass gate for future faithful live pass-through
claims.
Unified pass-through validator boundary/order edge cases are fixed: exact
19/20 matching passes at drop_rate=0.05, unmatched captures fail without
spurious frame_order_violation, and real wrong-order traces still fail.
Unified 15 fps image-evidence pass-through is closed: 30 generated validation
frames with image-decodable markers were received, presented to HDMI, captured
as saved JPEGs, decoded into a trace with `require_image_paths=true`, and
accepted by the committed validator with matched_frames=30 and drop_rate=0.0.
Linux direct-copy network-to-HDMI path is closed: PC sends framebuffer-native
24bpp payloads, the Linux receiver writes complete UDP frames to /dev/fb0 with
direct row memcpy, HDMI saved-image trace validation matches 30/30 frames, and
receiver dropped=0.
DRM/KMS local textured-motion display pacing is closed: the board generates
120 textured frames locally, writes only DRM dumb back buffers, receives 120
vblank page-flip events on /dev/dri/card0, HDMI capture validates 255
motion-like frames, tearing_frames=0, and frame_duration_stddev_ms=1.514.
Rule 1 open-commit sub-rule added: implementation cycles with a tunable
pass_condition must commit the Active Cycle block before verification, so the
frozen bar is auditable in git history; docs/governance cycles with a
structural-presence pass_condition are excepted.
Third-party review with independently re-run validator evidence appended to the
boundary-fix and 15fps reports; one saved HDMI JPEG was independently
marker-decoded and matched the trace's claimed frame_id.
```

Retired dead end:

```text
Project baremetal PC-to-board UDP RX through the hand-written RGMII bridge:
rx=0, rxfcs rising, no frames reach lwIP. Root cause confirmed by the Linux
ping result as the hand-written bridge BUFIO/BUFG crossing, not the physical
layer. Do not resume this work.
```

## Next Cycle Direction

No active cycle is open. The next implementation cycle can build on two
verified facts: the Linux direct-copy network-to-HDMI transfer chain passes,
and the board display side can page-flip textured motion through DRM/KMS with
stable vblank cadence when network receive is removed. If the goal is smooth
network-driven video through mature Linux components, the next dependency
cycle must try hot install first: install PC-side GStreamer with an available
host package manager and try board-side `apt-get` installation, repairing
Ubuntu 18.04 sources to old-releases if needed. Only if hot install fails
should a later cycle rebuild the PetaLinux/rootfs image. Because the next cycle
will carry a tunable numeric `pass_condition`, it must follow the Rule 1
open-commit sub-rule: commit the `## Active Cycle` block with the frozen
`pass_condition:`/`validator:` before running verification, then close in a
separate commit.
