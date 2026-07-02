# GStreamer platform integration for the network-video-to-HDMI route.
#
# Keep the intended route headless: do not add a desktop UI stack. Some
# optional sink packages may still appear through GStreamer dependencies.
# The goal is a practical media runtime for Linux userspace pipelines feeding
# DRM/KMS HDMI output.

IMAGE_INSTALL_append = " peekpoke"
IMAGE_INSTALL_append = " gpio-demo"

IMAGE_INSTALL_append = " gstreamer1.0"
IMAGE_INSTALL_append = " gstreamer1.0-meta-base"
IMAGE_INSTALL_append = " gstreamer1.0-plugins-base"
IMAGE_INSTALL_append = " gstreamer1.0-plugins-good"
IMAGE_INSTALL_append = " gstreamer1.0-plugins-bad"
IMAGE_INSTALL_append = " gstreamer1.0-rtsp-server"
IMAGE_INSTALL_append = " packagegroup-petalinux-v4lutils"
IMAGE_INSTALL_append = " libdrm"
IMAGE_INSTALL_append = " libdrm-kms"
IMAGE_INSTALL_append = " libdrm-tests"
