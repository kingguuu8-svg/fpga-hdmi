#include <gst/gst.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include "jpegpl_dma_probe.h"

#define DEFAULT_PL_BASE 0x43c00000u
#define DEFAULT_PL_MAP_SIZE 0x10000u
#define REG_CONTROL 0x00u
#define REG_X 0x04u
#define REG_Y 0x08u
#define REG_STATUS 0x0cu
#define REG_MAIN_FRAMES 0x10u
#define REG_PIP_FRAMES 0x14u
#define REG_OVERLAY_PIXELS 0x18u
#define RECENT_WINDOW 256u
#define BUFFER_PROBE_MARKER_SIZE 24
#define DEFAULT_DMA_DEVICE "/dev/jpegpl_dma_probe"

typedef struct _GstJpegPlDecJpegInfo {
  gboolean valid;
  gboolean baseline;
  gboolean progressive;
  gboolean has_sos;
  gboolean sampling_420;
  guint width;
  guint height;
  guint components;
  guint restart_interval;
  guint dqt_segments;
  guint dht_segments;
  gchar sampling[16];
} GstJpegPlDecJpegInfo;

typedef struct _GstJpegPlDecSample {
  GstClockTime entered_at;
  gsize in_bytes;
} GstJpegPlDecSample;

typedef struct _GstJpegPlDec {
  GstBin parent;
  GstElement *decoder;
  GQueue *pending;
  GMutex lock;
  gchar *probe_mode;
  gchar *backend;
  gchar *dma_device;
  guint summary_interval;
  guint32 pl_base;
  guint32 pl_map_size;
  volatile guint8 *pl_regs;
  gboolean pl_probe_failed;
  gboolean dma_probe_failed;
  gint dma_fd;
  guint8 *dma_in;
  gsize dma_in_capacity;
  guint8 *dma_out;
  gsize dma_out_capacity;
  guint64 frames;
  guint64 in_frames;
  guint64 total_decode_ns;
  guint64 total_buffer_probe_ns;
  guint64 max_decode_ns;
  guint64 max_buffer_probe_ns;
  guint64 total_in_bytes;
  guint64 total_out_bytes;
  guint64 buffer_probe_frames;
  guint64 dma_probe_frames;
  guint64 dma_probe_pass_frames;
  guint64 dma_probe_fail_frames;
  guint64 dma_writeback_frames;
  guint64 dma_writeback_pass_frames;
  guint64 dma_writeback_fail_frames;
  guint64 compressed_dma_frames;
  guint64 compressed_dma_pass_frames;
  guint64 compressed_dma_fail_frames;
  guint64 total_dma_probe_ns;
  guint64 max_dma_probe_ns;
  guint64 total_compressed_dma_ns;
  guint64 max_compressed_dma_ns;
  guint64 recent_decode_ns[RECENT_WINDOW];
  guint recent_count;
  guint recent_index;
} GstJpegPlDec;

typedef struct _GstJpegPlDecClass {
  GstBinClass parent_class;
} GstJpegPlDecClass;

#define GST_TYPE_JPEG_PL_DEC (gst_jpeg_pl_dec_get_type())
#define GST_JPEG_PL_DEC(obj) ((GstJpegPlDec *)(obj))
GType gst_jpeg_pl_dec_get_type(void);

G_DEFINE_TYPE(GstJpegPlDec, gst_jpeg_pl_dec, GST_TYPE_BIN)

enum {
  PROP_0,
  PROP_BACKEND,
  PROP_PROBE_MODE,
  PROP_SUMMARY_INTERVAL,
  PROP_PL_BASE,
  PROP_PL_MAP_SIZE,
  PROP_DMA_DEVICE
};

static GstStaticPadTemplate sink_template = GST_STATIC_PAD_TEMPLATE(
    "sink",
    GST_PAD_SINK,
    GST_PAD_ALWAYS,
    GST_STATIC_CAPS("image/jpeg"));

static GstStaticPadTemplate src_template = GST_STATIC_PAD_TEMPLATE(
    "src",
    GST_PAD_SRC,
    GST_PAD_ALWAYS,
    GST_STATIC_CAPS("video/x-raw"));

static gint
compare_u64(const void *left, const void *right)
{
  const guint64 a = *(const guint64 *)left;
  const guint64 b = *(const guint64 *)right;

  return (a > b) - (a < b);
}

static gdouble
ns_to_ms(guint64 ns)
{
  return (gdouble)ns / 1000000.0;
}

static guint64
percentile_recent(GstJpegPlDec *self, gdouble percentile)
{
  guint64 values[RECENT_WINDOW];
  guint index;

  if (self->recent_count == 0u) {
    return 0u;
  }

  memcpy(values, self->recent_decode_ns, self->recent_count * sizeof(values[0]));
  qsort(values, self->recent_count, sizeof(values[0]), compare_u64);
  index = (guint)((percentile * (gdouble)(self->recent_count - 1u)) + 0.5);
  if (index >= self->recent_count) {
    index = self->recent_count - 1u;
  }
  return values[index];
}

static guint32
pl_reg_read(volatile guint8 *base, guint32 offset)
{
  volatile guint32 *reg = (volatile guint32 *)(base + offset);
  return *reg;
}

static gboolean
gst_jpeg_pl_dec_compressed_dma_enabled(GstJpegPlDec *self)
{
  return g_strcmp0(self->probe_mode, "compressed-dma-probe") == 0 ||
         g_strcmp0(self->probe_mode, "pl-compressed-dma-probe") == 0 ||
         g_strcmp0(self->backend, "pl-compressed-probe") == 0;
}

static gboolean
gst_jpeg_pl_dec_pl_probe_enabled(GstJpegPlDec *self)
{
  return g_strcmp0(self->probe_mode, "pl-probe") == 0 ||
         g_strcmp0(self->probe_mode, "pl-buffer-probe") == 0 ||
         g_strcmp0(self->probe_mode, "pl-dma-probe") == 0 ||
         g_strcmp0(self->probe_mode, "pl-dma-writeback") == 0 ||
         g_strcmp0(self->probe_mode, "pl-compressed-dma-probe") == 0;
}

static gboolean
gst_jpeg_pl_dec_buffer_probe_enabled(GstJpegPlDec *self)
{
  return g_strcmp0(self->probe_mode, "buffer-probe") == 0 ||
         g_strcmp0(self->probe_mode, "pl-buffer-probe") == 0;
}

static gboolean
gst_jpeg_pl_dec_dma_probe_enabled(GstJpegPlDec *self)
{
  return g_strcmp0(self->probe_mode, "dma-probe") == 0 ||
         g_strcmp0(self->probe_mode, "pl-dma-probe") == 0 ||
         g_strcmp0(self->probe_mode, "dma-writeback") == 0 ||
         g_strcmp0(self->probe_mode, "pl-dma-writeback") == 0;
}

static gboolean
gst_jpeg_pl_dec_dma_writeback_enabled(GstJpegPlDec *self)
{
  return g_strcmp0(self->probe_mode, "dma-writeback") == 0 ||
         g_strcmp0(self->probe_mode, "pl-dma-writeback") == 0;
}

static guint32
fnv1a32(const guint8 *data, gsize size)
{
  guint32 hash = 2166136261u;
  gsize i;

  for (i = 0; i < size; i++) {
    hash ^= data[i];
    hash *= 16777619u;
  }
  return hash;
}

static guint
read_be16(const guint8 *data)
{
  return ((guint)data[0] << 8) | (guint)data[1];
}

static void
gst_jpeg_pl_dec_parse_jpeg_info(const guint8 *data, gsize size,
                                GstJpegPlDecJpegInfo *info)
{
  gsize pos = 2u;

  memset(info, 0, sizeof(*info));
  g_strlcpy(info->sampling, "unknown", sizeof(info->sampling));

  if (data == NULL || size < 4u || data[0] != 0xffu || data[1] != 0xd8u) {
    return;
  }

  info->valid = TRUE;
  while (pos + 4u <= size) {
    guint marker;
    guint segment_len;
    gsize segment_start;

    while (pos < size && data[pos] != 0xffu) {
      pos++;
    }
    while (pos < size && data[pos] == 0xffu) {
      pos++;
    }
    if (pos >= size) {
      break;
    }

    marker = data[pos++];
    if (marker == 0xd9u) {
      break;
    }
    if (marker == 0x01u || (marker >= 0xd0u && marker <= 0xd7u)) {
      continue;
    }
    if (pos + 2u > size) {
      break;
    }

    segment_len = read_be16(data + pos);
    if (segment_len < 2u || pos + segment_len > size) {
      break;
    }
    segment_start = pos + 2u;

    if (marker == 0xc0u || marker == 0xc2u) {
      info->baseline = marker == 0xc0u;
      info->progressive = marker == 0xc2u;
      if (segment_len >= 8u) {
        guint i;
        guint sampling0 = 0u;

        info->height = read_be16(data + segment_start + 1u);
        info->width = read_be16(data + segment_start + 3u);
        info->components = data[segment_start + 5u];
        if (info->components > 0u && segment_len >= 8u + (info->components * 3u)) {
          sampling0 = data[segment_start + 7u];
          for (i = 0u; i < info->components; i++) {
            guint sampling = data[segment_start + 7u + (i * 3u)];
            if (i == 0u && sampling == 0x22u) {
              continue;
            }
            if (i > 0u && sampling == 0x11u) {
              continue;
            }
            sampling0 = 0u;
            break;
          }
          info->sampling_420 = sampling0 == 0x22u && info->components == 3u;
          if (info->sampling_420) {
            g_strlcpy(info->sampling, "4:2:0", sizeof(info->sampling));
          } else {
            g_snprintf(info->sampling, sizeof(info->sampling), "0x%02x", sampling0);
          }
        }
      }
    } else if (marker == 0xdbu) {
      info->dqt_segments++;
    } else if (marker == 0xc4u) {
      info->dht_segments++;
    } else if (marker == 0xddu && segment_len >= 4u) {
      info->restart_interval = read_be16(data + segment_start);
    } else if (marker == 0xdau) {
      info->has_sos = TRUE;
      break;
    }

    pos += segment_len;
  }
}

static gboolean
gst_jpeg_pl_dec_get_jpeg_caps(GstPad *pad, gint *width, gint *height)
{
  GstCaps *caps = gst_pad_get_current_caps(pad);
  GstStructure *structure;
  gboolean ok = FALSE;

  if (caps == NULL || gst_caps_is_empty(caps)) {
    if (caps != NULL) {
      gst_caps_unref(caps);
    }
    return FALSE;
  }

  structure = gst_caps_get_structure(caps, 0);
  ok = gst_structure_get_int(structure, "width", width) &&
       gst_structure_get_int(structure, "height", height);
  gst_caps_unref(caps);
  return ok;
}

static gboolean
gst_jpeg_pl_dec_get_raw_caps(GstPad *pad, gchar *format, gsize format_size,
                             gint *width, gint *height)
{
  GstCaps *caps = gst_pad_get_current_caps(pad);
  GstStructure *structure;
  const gchar *fmt;
  gboolean ok = FALSE;

  if (caps == NULL || gst_caps_is_empty(caps)) {
    if (caps != NULL) {
      gst_caps_unref(caps);
    }
    return FALSE;
  }

  structure = gst_caps_get_structure(caps, 0);
  fmt = gst_structure_get_string(structure, "format");
  if (fmt != NULL &&
      gst_structure_get_int(structure, "width", width) &&
      gst_structure_get_int(structure, "height", height)) {
    g_strlcpy(format, fmt, format_size);
    ok = TRUE;
  }
  gst_caps_unref(caps);
  return ok;
}

static gboolean
gst_jpeg_pl_dec_stamp_i420_marker_data(guint8 *data, gsize size,
                                       gint width, gint height,
                                       guint32 *checksum_before,
                                       guint32 *checksum_after)
{
  gint marker_w = MIN(BUFFER_PROBE_MARKER_SIZE, width);
  gint marker_h = MIN(BUFFER_PROBE_MARKER_SIZE, height);
  gint x;
  gint y;
  gsize expected_size;

  if (width <= 0 || height <= 0) {
    return FALSE;
  }

  expected_size = (gsize)width * (gsize)height * 3u / 2u;
  if (data == NULL || size < expected_size) {
    return FALSE;
  }

  *checksum_before = fnv1a32(data, size);

  for (y = 0; y < marker_h; y++) {
    for (x = 0; x < marker_w; x++) {
      guint8 value = (((x / 4) + (y / 4)) & 1) ? 0xffu : 0x10u;
      data[(gsize)y * (gsize)width + (gsize)x] = value;
    }
  }

  /* Keep the marker neutral in chroma so only luma carries the probe pattern. */
  if (width >= 2 && height >= 2) {
    gsize u_base = (gsize)width * (gsize)height;
    gsize v_base = u_base + ((gsize)width * (gsize)height / 4u);
    gint chroma_w = width / 2;
    gint chroma_marker_w = marker_w / 2;
    gint chroma_marker_h = marker_h / 2;

    for (y = 0; y < chroma_marker_h; y++) {
      for (x = 0; x < chroma_marker_w; x++) {
        data[u_base + (gsize)y * (gsize)chroma_w + (gsize)x] = 0x80u;
        data[v_base + (gsize)y * (gsize)chroma_w + (gsize)x] = 0x80u;
      }
    }
  }

  *checksum_after = fnv1a32(data, size);
  return TRUE;
}

static gboolean
gst_jpeg_pl_dec_stamp_i420_marker(GstBuffer *buffer, gint width, gint height,
                                  guint32 *checksum_before,
                                  guint32 *checksum_after)
{
  GstMapInfo map;
  gboolean ok;

  if (!gst_buffer_map(buffer, &map, GST_MAP_READWRITE)) {
    return FALSE;
  }
  ok = gst_jpeg_pl_dec_stamp_i420_marker_data(map.data, map.size, width, height,
                                              checksum_before, checksum_after);
  gst_buffer_unmap(buffer, &map);
  return ok;
}

static void
gst_jpeg_pl_dec_log_buffer_probe(GstJpegPlDec *self, GstPadProbeInfo *info,
                                 GstPad *pad, guint64 frame_id)
{
  GstBuffer *buffer = GST_PAD_PROBE_INFO_BUFFER(info);
  GstBuffer *writable;
  GstClockTime started;
  guint64 elapsed_ns;
  guint32 checksum_before = 0u;
  guint32 checksum_after = 0u;
  gchar format[16] = "";
  gint width = 0;
  gint height = 0;
  gboolean caps_ok;
  gboolean stamp_ok = FALSE;

  if (!gst_jpeg_pl_dec_buffer_probe_enabled(self) || buffer == NULL) {
    return;
  }

  started = gst_util_get_timestamp();
  caps_ok = gst_jpeg_pl_dec_get_raw_caps(pad, format, sizeof(format), &width, &height);
  if (caps_ok && g_strcmp0(format, "I420") == 0) {
    writable = gst_buffer_make_writable(buffer);
    if (writable != buffer) {
      GST_PAD_PROBE_INFO_DATA(info) = writable;
      buffer = writable;
    }
    stamp_ok = gst_jpeg_pl_dec_stamp_i420_marker(buffer, width, height,
                                                 &checksum_before,
                                                 &checksum_after);
  }

  elapsed_ns = gst_util_get_timestamp() - started;
  self->buffer_probe_frames++;
  self->total_buffer_probe_ns += elapsed_ns;
  self->max_buffer_probe_ns = MAX(self->max_buffer_probe_ns, elapsed_ns);

  g_print("JPEGPLDEC_BUFFER_PROBE frame=%" G_GUINT64_FORMAT
          " mode=%s format=%s width=%d height=%d bytes=%" G_GSIZE_FORMAT
          " checksum_before=0x%08x checksum_after=0x%08x"
          " stamp=%s result=%s elapsed_ms=%.3f avg_ms=%.3f max_ms=%.3f\n",
          frame_id,
          self->probe_mode,
          caps_ok ? format : "unknown",
          width,
          height,
          gst_buffer_get_size(buffer),
          checksum_before,
          checksum_after,
          stamp_ok ? "top-left-i420-luma-checker" : "none",
          stamp_ok ? "pass" : "unsupported-caps-or-map-failed",
          ns_to_ms(elapsed_ns),
          ns_to_ms(self->total_buffer_probe_ns / MAX(self->buffer_probe_frames, 1u)),
          ns_to_ms(self->max_buffer_probe_ns));
}

static gboolean
gst_jpeg_pl_dec_open_dma_probe(GstJpegPlDec *self)
{
  if (self->dma_fd >= 0) {
    return TRUE;
  }
  if (self->dma_probe_failed) {
    return FALSE;
  }

  self->dma_fd = open(self->dma_device, O_RDWR | O_CLOEXEC);
  if (self->dma_fd < 0) {
    g_print("JPEGPLDEC_DMA_PROBE_ERROR detail=open device=%s errno=%d\n",
            self->dma_device, errno);
    self->dma_probe_failed = TRUE;
    return FALSE;
  }

  g_print("JPEGPLDEC_DMA_PROBE_READY device=%s\n", self->dma_device);
  return TRUE;
}

static void
gst_jpeg_pl_dec_log_dma_probe(GstJpegPlDec *self, GstBuffer *buffer,
                              GstPad *pad, guint64 frame_id)
{
  struct jpegpl_dma_probe_run req;
  GstMapInfo map;
  GstClockTime started;
  guint64 elapsed_ns;
  guint8 *input_data = NULL;
  guint32 host_checksum = 0u;
  guint32 checksum_before = 0u;
  guint32 checksum_after = 0u;
  guint32 write_checksum = 0u;
  gboolean pass = FALSE;
  gboolean caps_ok = FALSE;
  gboolean stamp_ok = FALSE;
  gboolean mapped = FALSE;
  gboolean writeback = gst_jpeg_pl_dec_dma_writeback_enabled(self);
  gint ioctl_result = -1;
  gint ioctl_errno = 0;
  gchar format[16] = "";
  gint width = 0;
  gint height = 0;

  if (!gst_jpeg_pl_dec_dma_probe_enabled(self) || buffer == NULL) {
    return;
  }

  started = gst_util_get_timestamp();
  memset(&req, 0, sizeof(req));
  if (!gst_jpeg_pl_dec_open_dma_probe(self)) {
    ioctl_errno = errno;
    goto done;
  }
  if (!gst_buffer_map(buffer, &map, writeback ? GST_MAP_READWRITE : GST_MAP_READ)) {
    ioctl_errno = EFAULT;
    goto done;
  }
  mapped = TRUE;
  if (map.size == 0u || map.size > G_MAXUINT32) {
    ioctl_errno = E2BIG;
    goto done;
  }

  if (self->dma_out_capacity < map.size) {
    self->dma_out = g_realloc(self->dma_out, map.size);
    self->dma_out_capacity = map.size;
  }
  memset(self->dma_out, 0, map.size);
  input_data = map.data;
  host_checksum = fnv1a32(map.data, map.size);
  checksum_before = host_checksum;
  checksum_after = host_checksum;
  if (writeback) {
    caps_ok = gst_jpeg_pl_dec_get_raw_caps(pad, format, sizeof(format),
                                           &width, &height);
    if (!caps_ok || g_strcmp0(format, "I420") != 0) {
      ioctl_errno = EOPNOTSUPP;
      goto done;
    }
    if (self->dma_in_capacity < map.size) {
      self->dma_in = g_realloc(self->dma_in, map.size);
      self->dma_in_capacity = map.size;
    }
    memcpy(self->dma_in, map.data, map.size);
    stamp_ok = gst_jpeg_pl_dec_stamp_i420_marker_data(
        self->dma_in, map.size, width, height, &checksum_before,
        &checksum_after);
    if (!stamp_ok) {
      ioctl_errno = EFAULT;
      goto done;
    }
    input_data = self->dma_in;
    host_checksum = checksum_after;
  }

  req.length = (guint32)map.size;
  req.timeout_ms = 1000u;
  req.user_in = (guint64)(uintptr_t)input_data;
  req.user_out = (guint64)(uintptr_t)self->dma_out;
  ioctl_result = ioctl(self->dma_fd, JPEGPL_DMA_PROBE_IOC_RUN, &req);
  if (ioctl_result != 0) {
    ioctl_errno = errno;
  } else {
    pass = req.status == (JPEGPL_DMA_PROBE_STATUS_TX_DONE |
                          JPEGPL_DMA_PROBE_STATUS_RX_DONE) &&
           req.checksum_in == host_checksum &&
           req.checksum_out == host_checksum &&
           memcmp(input_data, self->dma_out, map.size) == 0;
    if (pass && writeback) {
      memcpy(map.data, self->dma_out, map.size);
      write_checksum = fnv1a32(map.data, map.size);
      pass = write_checksum == req.checksum_out;
    }
  }

done:
  elapsed_ns = gst_util_get_timestamp() - started;
  self->dma_probe_frames++;
  self->total_dma_probe_ns += elapsed_ns;
  self->max_dma_probe_ns = MAX(self->max_dma_probe_ns, elapsed_ns);
  if (pass) {
    self->dma_probe_pass_frames++;
  } else {
    self->dma_probe_fail_frames++;
  }

  if (writeback) {
    self->dma_writeback_frames++;
    if (pass) {
      self->dma_writeback_pass_frames++;
    } else {
      self->dma_writeback_fail_frames++;
    }
    g_print("JPEGPLDEC_DMA_WRITEBACK frame=%" G_GUINT64_FORMAT
            " format=%s width=%d height=%d bytes=%u chunks=%u max_chunk=%u"
            " status=0x%08x checksum_original=0x%08x checksum_staged=0x%08x"
            " checksum_dma_in=0x%08x checksum_dma_out=0x%08x"
            " checksum_written=0x%08x stamp=%s"
            " dma_elapsed_ms=%.3f total_elapsed_ms=%.3f"
            " ioctl_result=%d errno=%d result=%s\n",
            frame_id,
            caps_ok ? format : "unknown",
            width,
            height,
            req.length,
            req.chunks,
            req.max_chunk_size,
            req.status,
            checksum_before,
            checksum_after,
            req.checksum_in,
            req.checksum_out,
            write_checksum,
            stamp_ok ? "top-left-i420-luma-checker-via-dma" : "none",
            ns_to_ms(req.elapsed_ns),
            ns_to_ms(elapsed_ns),
            ioctl_result,
            ioctl_errno,
            pass ? "pass" : "fail");
  } else {
    g_print("JPEGPLDEC_DMA_PROBE frame=%" G_GUINT64_FORMAT
            " bytes=%u chunks=%u max_chunk=%u status=0x%08x checksum_host=0x%08x"
            " checksum_dma_in=0x%08x checksum_dma_out=0x%08x"
            " dma_elapsed_ms=%.3f total_elapsed_ms=%.3f"
            " ioctl_result=%d errno=%d result=%s\n",
            frame_id,
            req.length,
            req.chunks,
            req.max_chunk_size,
            req.status,
            host_checksum,
            req.checksum_in,
            req.checksum_out,
            ns_to_ms(req.elapsed_ns),
            ns_to_ms(elapsed_ns),
            ioctl_result,
            ioctl_errno,
            pass ? "pass" : "fail");
  }

  if (mapped) {
    gst_buffer_unmap(buffer, &map);
  }
}

static void
gst_jpeg_pl_dec_log_compressed_dma_probe(GstJpegPlDec *self, GstBuffer *buffer,
                                         GstPad *pad, guint64 frame_id)
{
  struct jpegpl_dma_probe_run req;
  GstMapInfo map;
  GstClockTime started;
  guint64 elapsed_ns;
  guint32 host_checksum = 0u;
  gboolean pass = FALSE;
  gboolean mapped = FALSE;
  gint ioctl_result = -1;
  gint ioctl_errno = 0;
  gint caps_width = 0;
  gint caps_height = 0;
  gboolean caps_ok = FALSE;
  GstJpegPlDecJpegInfo jpeg_info;

  if (!gst_jpeg_pl_dec_compressed_dma_enabled(self) || buffer == NULL) {
    return;
  }

  started = gst_util_get_timestamp();
  memset(&req, 0, sizeof(req));
  memset(&jpeg_info, 0, sizeof(jpeg_info));

  if (!gst_jpeg_pl_dec_open_dma_probe(self)) {
    ioctl_errno = errno;
    goto done;
  }
  if (!gst_buffer_map(buffer, &map, GST_MAP_READ)) {
    ioctl_errno = EFAULT;
    goto done;
  }
  mapped = TRUE;
  if (map.size == 0u || map.size > G_MAXUINT32) {
    ioctl_errno = E2BIG;
    goto done;
  }

  gst_jpeg_pl_dec_parse_jpeg_info(map.data, map.size, &jpeg_info);
  caps_ok = gst_jpeg_pl_dec_get_jpeg_caps(pad, &caps_width, &caps_height);
  if (self->dma_out_capacity < map.size) {
    self->dma_out = g_realloc(self->dma_out, map.size);
    self->dma_out_capacity = map.size;
  }
  memset(self->dma_out, 0, map.size);
  host_checksum = fnv1a32(map.data, map.size);

  req.length = (guint32)map.size;
  req.timeout_ms = 1000u;
  req.user_in = (guint64)(uintptr_t)map.data;
  req.user_out = (guint64)(uintptr_t)self->dma_out;
  ioctl_result = ioctl(self->dma_fd, JPEGPL_DMA_PROBE_IOC_RUN, &req);
  if (ioctl_result != 0) {
    ioctl_errno = errno;
  } else {
    pass = req.status == (JPEGPL_DMA_PROBE_STATUS_TX_DONE |
                          JPEGPL_DMA_PROBE_STATUS_RX_DONE) &&
           req.checksum_in == host_checksum &&
           req.checksum_out == host_checksum &&
           memcmp(map.data, self->dma_out, map.size) == 0;
  }

done:
  elapsed_ns = gst_util_get_timestamp() - started;
  self->compressed_dma_frames++;
  self->total_compressed_dma_ns += elapsed_ns;
  self->max_compressed_dma_ns = MAX(self->max_compressed_dma_ns, elapsed_ns);
  if (pass) {
    self->compressed_dma_pass_frames++;
  } else {
    self->compressed_dma_fail_frames++;
  }

  g_print("JPEGPLDEC_COMPRESSED_DMA_PROBE frame=%" G_GUINT64_FORMAT
          " backend=%s mode=%s caps_width=%d caps_height=%d"
          " jpeg_valid=%u jpeg_width=%u jpeg_height=%u baseline=%u progressive=%u"
          " sampling=%s components=%u dqt=%u dht=%u sos=%u restart_interval=%u"
          " bytes=%u chunks=%u max_chunk=%u status=0x%08x"
          " checksum_host=0x%08x checksum_dma_in=0x%08x checksum_dma_out=0x%08x"
          " dma_elapsed_ms=%.3f total_elapsed_ms=%.3f"
          " ioctl_result=%d errno=%d result=%s\n",
          frame_id,
          self->backend,
          self->probe_mode,
          caps_ok ? caps_width : 0,
          caps_ok ? caps_height : 0,
          jpeg_info.valid ? 1u : 0u,
          jpeg_info.width,
          jpeg_info.height,
          jpeg_info.baseline ? 1u : 0u,
          jpeg_info.progressive ? 1u : 0u,
          jpeg_info.sampling,
          jpeg_info.components,
          jpeg_info.dqt_segments,
          jpeg_info.dht_segments,
          jpeg_info.has_sos ? 1u : 0u,
          jpeg_info.restart_interval,
          req.length,
          req.chunks,
          req.max_chunk_size,
          req.status,
          host_checksum,
          req.checksum_in,
          req.checksum_out,
          ns_to_ms(req.elapsed_ns),
          ns_to_ms(elapsed_ns),
          ioctl_result,
          ioctl_errno,
          pass ? "pass" : "fail");

  if (mapped) {
    gst_buffer_unmap(buffer, &map);
  }
}

static gboolean
gst_jpeg_pl_dec_map_pl_regs(GstJpegPlDec *self)
{
  int fd;
  void *mapped;

  if (self->pl_regs != NULL) {
    return TRUE;
  }
  if (self->pl_probe_failed) {
    return FALSE;
  }

  fd = open("/dev/mem", O_RDONLY | O_SYNC);
  if (fd < 0) {
    g_print("JPEGPLDEC_PL_PROBE_ERROR detail=open_dev_mem errno=%d\n", errno);
    self->pl_probe_failed = TRUE;
    return FALSE;
  }

  mapped = mmap(NULL, self->pl_map_size, PROT_READ, MAP_SHARED, fd,
                (off_t)self->pl_base);
  close(fd);
  if (mapped == MAP_FAILED) {
    g_print("JPEGPLDEC_PL_PROBE_ERROR detail=mmap base=0x%08x errno=%d\n",
            self->pl_base, errno);
    self->pl_probe_failed = TRUE;
    return FALSE;
  }

  self->pl_regs = (volatile guint8 *)mapped;
  g_print("JPEGPLDEC_PL_PROBE_READY base=0x%08x map_size=0x%08x\n",
          self->pl_base, self->pl_map_size);
  return TRUE;
}

static void
gst_jpeg_pl_dec_log_pl_probe(GstJpegPlDec *self)
{
  guint32 control;
  guint32 status;

  if (!gst_jpeg_pl_dec_pl_probe_enabled(self)) {
    return;
  }
  if (!gst_jpeg_pl_dec_map_pl_regs(self)) {
    return;
  }

  control = pl_reg_read(self->pl_regs, REG_CONTROL);
  status = pl_reg_read(self->pl_regs, REG_STATUS);
  g_print("JPEGPLDEC_PL_PROBE frame=%" G_GUINT64_FORMAT
          " control=0x%08x enable=%u scale=%u effect=%u x=%u y=%u"
          " active_w=%u active_h=%u main_frames=%u pip_frames=%u"
          " overlay_pixels=%u\n",
          self->frames,
          control,
          (control & 0x1u) ? 1u : 0u,
          (control & 0x4u) ? 4u : 2u,
          (control >> 4) & 0x3u,
          pl_reg_read(self->pl_regs, REG_X),
          pl_reg_read(self->pl_regs, REG_Y),
          status & 0xffffu,
          (status >> 16) & 0xffffu,
          pl_reg_read(self->pl_regs, REG_MAIN_FRAMES),
          pl_reg_read(self->pl_regs, REG_PIP_FRAMES),
          pl_reg_read(self->pl_regs, REG_OVERLAY_PIXELS));
}

static void
gst_jpeg_pl_dec_log_profile(GstJpegPlDec *self, guint64 decode_ns,
                            gsize in_bytes, gsize out_bytes)
{
  guint64 p50;
  guint64 p95;
  gdouble avg_ms;
  gdouble avg_in_bytes;
  gdouble avg_out_bytes;

  self->frames++;
  self->total_decode_ns += decode_ns;
  self->max_decode_ns = MAX(self->max_decode_ns, decode_ns);
  self->total_in_bytes += in_bytes;
  self->total_out_bytes += out_bytes;
  self->recent_decode_ns[self->recent_index] = decode_ns;
  self->recent_index = (self->recent_index + 1u) % RECENT_WINDOW;
  if (self->recent_count < RECENT_WINDOW) {
    self->recent_count++;
  }

  if (self->summary_interval == 0u ||
      (self->frames % self->summary_interval) != 0u) {
    return;
  }

  p50 = percentile_recent(self, 0.50);
  p95 = percentile_recent(self, 0.95);
  avg_ms = ns_to_ms(self->total_decode_ns / MAX(self->frames, 1u));
  avg_in_bytes = (gdouble)self->total_in_bytes / (gdouble)self->frames;
  avg_out_bytes = (gdouble)self->total_out_bytes / (gdouble)self->frames;

  g_print("JPEGPLDEC_PROFILE frames=%" G_GUINT64_FORMAT
          " mode=%s last_ms=%.3f avg_ms=%.3f p50_ms=%.3f p95_ms=%.3f"
          " max_ms=%.3f avg_in_bytes=%.1f avg_out_bytes=%.1f"
          " pending=%u\n",
          self->frames,
          self->probe_mode,
          ns_to_ms(decode_ns),
          avg_ms,
          ns_to_ms(p50),
          ns_to_ms(p95),
          ns_to_ms(self->max_decode_ns),
          avg_in_bytes,
          avg_out_bytes,
          g_queue_get_length(self->pending));
  gst_jpeg_pl_dec_log_pl_probe(self);
}

static GstPadProbeReturn
gst_jpeg_pl_dec_sink_probe(GstPad *pad, GstPadProbeInfo *info,
                           gpointer user_data)
{
  GstJpegPlDec *self = GST_JPEG_PL_DEC(user_data);
  GstBuffer *buffer = GST_PAD_PROBE_INFO_BUFFER(info);
  GstJpegPlDecSample *sample;
  guint64 frame_id;

  if (buffer == NULL) {
    return GST_PAD_PROBE_OK;
  }

  g_mutex_lock(&self->lock);
  frame_id = self->in_frames + 1u;
  g_mutex_unlock(&self->lock);
  gst_jpeg_pl_dec_log_compressed_dma_probe(self, buffer, pad, frame_id);

  sample = g_new0(GstJpegPlDecSample, 1);
  sample->entered_at = gst_util_get_timestamp();
  sample->in_bytes = gst_buffer_get_size(buffer);

  g_mutex_lock(&self->lock);
  self->in_frames++;
  g_queue_push_tail(self->pending, sample);
  g_mutex_unlock(&self->lock);
  return GST_PAD_PROBE_OK;
}

static GstPadProbeReturn
gst_jpeg_pl_dec_src_probe(GstPad *pad, GstPadProbeInfo *info,
                          gpointer user_data)
{
  GstJpegPlDec *self = GST_JPEG_PL_DEC(user_data);
  GstBuffer *buffer = GST_PAD_PROBE_INFO_BUFFER(info);
  GstBuffer *writable;
  GstJpegPlDecSample *sample = NULL;
  GstClockTime now;
  guint64 decode_ns = 0u;
  gsize in_bytes = 0u;
  gsize out_bytes = 0u;

  (void)pad;
  if (buffer == NULL) {
    return GST_PAD_PROBE_OK;
  }

  now = gst_util_get_timestamp();
  gst_jpeg_pl_dec_log_buffer_probe(self, info, pad, self->frames + 1u);
  buffer = GST_PAD_PROBE_INFO_BUFFER(info);
  if (gst_jpeg_pl_dec_dma_writeback_enabled(self)) {
    writable = gst_buffer_make_writable(buffer);
    if (writable != buffer) {
      GST_PAD_PROBE_INFO_DATA(info) = writable;
      buffer = writable;
    }
  }
  gst_jpeg_pl_dec_log_dma_probe(self, buffer, pad, self->frames + 1u);
  out_bytes = gst_buffer_get_size(buffer);

  g_mutex_lock(&self->lock);
  if (!g_queue_is_empty(self->pending)) {
    sample = g_queue_pop_head(self->pending);
  }
  if (sample != NULL) {
    decode_ns = now > sample->entered_at ? now - sample->entered_at : 0u;
    in_bytes = sample->in_bytes;
    g_free(sample);
  }
  gst_jpeg_pl_dec_log_profile(self, decode_ns, in_bytes, out_bytes);
  g_mutex_unlock(&self->lock);
  return GST_PAD_PROBE_OK;
}

static gboolean
gst_jpeg_pl_dec_create_ghost_pad(GstJpegPlDec *self, const gchar *target_name,
                                 const gchar *ghost_name)
{
  GstPad *target = gst_element_get_static_pad(self->decoder, target_name);
  GstPad *ghost = NULL;
  gboolean ok;

  if (target == NULL) {
    GST_ERROR_OBJECT(self, "missing %s pad", target_name);
    return FALSE;
  }

  ghost = gst_ghost_pad_new(ghost_name, target);
  gst_object_unref(target);
  if (ghost == NULL) {
    GST_ERROR_OBJECT(self, "failed to create %s ghost pad", ghost_name);
    return FALSE;
  }

  ok = gst_element_add_pad(GST_ELEMENT(self), ghost);
  if (!ok) {
    gst_object_unref(ghost);
  }
  return ok;
}

static void
gst_jpeg_pl_dec_install_probes(GstJpegPlDec *self)
{
  GstPad *sink = gst_element_get_static_pad(self->decoder, "sink");
  GstPad *src = gst_element_get_static_pad(self->decoder, "src");

  if (sink != NULL) {
    gst_pad_add_probe(sink, GST_PAD_PROBE_TYPE_BUFFER,
                      gst_jpeg_pl_dec_sink_probe, self, NULL);
    gst_object_unref(sink);
  }
  if (src != NULL) {
    gst_pad_add_probe(src, GST_PAD_PROBE_TYPE_BUFFER,
                      gst_jpeg_pl_dec_src_probe, self, NULL);
    gst_object_unref(src);
  }
}

static void
gst_jpeg_pl_dec_set_property(GObject *object, guint prop_id,
                             const GValue *value, GParamSpec *pspec)
{
  GstJpegPlDec *self = GST_JPEG_PL_DEC(object);

  switch (prop_id) {
    case PROP_BACKEND: {
      const gchar *backend = g_value_get_string(value);
      if (g_strcmp0(backend, "software-reference") != 0 &&
          g_strcmp0(backend, "pl-compressed-probe") != 0) {
        GST_WARNING_OBJECT(self, "unknown backend '%s', using software-reference",
                           backend == NULL ? "" : backend);
        backend = "software-reference";
      }
      g_free(self->backend);
      self->backend = g_strdup(backend);
      break;
    }
    case PROP_PROBE_MODE: {
      const gchar *mode = g_value_get_string(value);
      if (g_strcmp0(mode, "software") != 0 &&
          g_strcmp0(mode, "pl-probe") != 0 &&
          g_strcmp0(mode, "buffer-probe") != 0 &&
          g_strcmp0(mode, "pl-buffer-probe") != 0 &&
          g_strcmp0(mode, "dma-probe") != 0 &&
          g_strcmp0(mode, "pl-dma-probe") != 0 &&
          g_strcmp0(mode, "dma-writeback") != 0 &&
          g_strcmp0(mode, "pl-dma-writeback") != 0 &&
          g_strcmp0(mode, "compressed-dma-probe") != 0 &&
          g_strcmp0(mode, "pl-compressed-dma-probe") != 0) {
        GST_WARNING_OBJECT(self, "unknown probe-mode '%s', using software",
                           mode == NULL ? "" : mode);
        mode = "software";
      }
      g_free(self->probe_mode);
      self->probe_mode = g_strdup(mode);
      break;
    }
    case PROP_SUMMARY_INTERVAL:
      self->summary_interval = g_value_get_uint(value);
      break;
    case PROP_PL_BASE:
      self->pl_base = g_value_get_uint(value);
      break;
    case PROP_PL_MAP_SIZE:
      self->pl_map_size = g_value_get_uint(value);
      break;
    case PROP_DMA_DEVICE:
      g_free(self->dma_device);
      self->dma_device = g_value_dup_string(value);
      break;
    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID(object, prop_id, pspec);
      break;
  }
}

static void
gst_jpeg_pl_dec_get_property(GObject *object, guint prop_id, GValue *value,
                             GParamSpec *pspec)
{
  GstJpegPlDec *self = GST_JPEG_PL_DEC(object);

  switch (prop_id) {
    case PROP_BACKEND:
      g_value_set_string(value, self->backend);
      break;
    case PROP_PROBE_MODE:
      g_value_set_string(value, self->probe_mode);
      break;
    case PROP_SUMMARY_INTERVAL:
      g_value_set_uint(value, self->summary_interval);
      break;
    case PROP_PL_BASE:
      g_value_set_uint(value, self->pl_base);
      break;
    case PROP_PL_MAP_SIZE:
      g_value_set_uint(value, self->pl_map_size);
      break;
    case PROP_DMA_DEVICE:
      g_value_set_string(value, self->dma_device);
      break;
    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID(object, prop_id, pspec);
      break;
  }
}

static void
gst_jpeg_pl_dec_finalize(GObject *object)
{
  GstJpegPlDec *self = GST_JPEG_PL_DEC(object);

  if (self->pl_regs != NULL) {
    munmap((void *)self->pl_regs, self->pl_map_size);
    self->pl_regs = NULL;
  }
  if (self->dma_fd >= 0) {
    close(self->dma_fd);
    self->dma_fd = -1;
  }
  if (self->dma_probe_frames > 0u) {
    g_print("JPEGPLDEC_DMA_PROBE_SUMMARY frames=%" G_GUINT64_FORMAT
            " pass=%" G_GUINT64_FORMAT " fail=%" G_GUINT64_FORMAT
            " avg_ms=%.3f max_ms=%.3f\n",
            self->dma_probe_frames,
            self->dma_probe_pass_frames,
            self->dma_probe_fail_frames,
            ns_to_ms(self->total_dma_probe_ns / self->dma_probe_frames),
            ns_to_ms(self->max_dma_probe_ns));
  }
  if (self->dma_writeback_frames > 0u) {
    g_print("JPEGPLDEC_DMA_WRITEBACK_SUMMARY frames=%" G_GUINT64_FORMAT
            " pass=%" G_GUINT64_FORMAT " fail=%" G_GUINT64_FORMAT "\n",
            self->dma_writeback_frames,
            self->dma_writeback_pass_frames,
            self->dma_writeback_fail_frames);
  }
  if (self->compressed_dma_frames > 0u) {
    g_print("JPEGPLDEC_COMPRESSED_DMA_SUMMARY frames=%" G_GUINT64_FORMAT
            " pass=%" G_GUINT64_FORMAT " fail=%" G_GUINT64_FORMAT
            " avg_ms=%.3f max_ms=%.3f\n",
            self->compressed_dma_frames,
            self->compressed_dma_pass_frames,
            self->compressed_dma_fail_frames,
            ns_to_ms(self->total_compressed_dma_ns / self->compressed_dma_frames),
            ns_to_ms(self->max_compressed_dma_ns));
  }
  if (self->pending != NULL) {
    g_queue_free_full(self->pending, g_free);
    self->pending = NULL;
  }
  g_clear_pointer(&self->probe_mode, g_free);
  g_clear_pointer(&self->backend, g_free);
  g_clear_pointer(&self->dma_device, g_free);
  g_clear_pointer(&self->dma_in, g_free);
  g_clear_pointer(&self->dma_out, g_free);
  g_mutex_clear(&self->lock);
  G_OBJECT_CLASS(gst_jpeg_pl_dec_parent_class)->finalize(object);
}

static void
gst_jpeg_pl_dec_init(GstJpegPlDec *self)
{
  self->pending = g_queue_new();
  self->backend = g_strdup("software-reference");
  self->probe_mode = g_strdup("software");
  self->dma_device = g_strdup(DEFAULT_DMA_DEVICE);
  self->dma_fd = -1;
  self->summary_interval = 30u;
  self->pl_base = DEFAULT_PL_BASE;
  self->pl_map_size = DEFAULT_PL_MAP_SIZE;
  g_mutex_init(&self->lock);

  self->decoder = gst_element_factory_make("jpegdec", "software-reference-decoder");
  if (self->decoder == NULL) {
    GST_ELEMENT_ERROR(self, CORE, MISSING_PLUGIN,
                      ("jpegpldec requires the system jpegdec element"),
                      ("could not create jpegdec"));
    return;
  }

  gst_bin_add(GST_BIN(self), self->decoder);
  if (!gst_jpeg_pl_dec_create_ghost_pad(self, "sink", "sink") ||
      !gst_jpeg_pl_dec_create_ghost_pad(self, "src", "src")) {
    GST_ELEMENT_ERROR(self, CORE, FAILED,
                      ("failed to expose jpegpldec pads"),
                      ("could not create ghost pads"));
  }
  gst_jpeg_pl_dec_install_probes(self);
}

static void
gst_jpeg_pl_dec_class_init(GstJpegPlDecClass *klass)
{
  GObjectClass *object_class = G_OBJECT_CLASS(klass);
  GstElementClass *element_class = GST_ELEMENT_CLASS(klass);

  object_class->set_property = gst_jpeg_pl_dec_set_property;
  object_class->get_property = gst_jpeg_pl_dec_get_property;
  object_class->finalize = gst_jpeg_pl_dec_finalize;

  g_object_class_install_property(
      object_class,
      PROP_BACKEND,
      g_param_spec_string(
          "backend",
          "Decoder backend",
          "software-reference keeps the internal jpegdec child; pl-compressed-probe sends compressed JPEG input through the PL DMA data plane before falling back to software reference decode",
          "software-reference",
          G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
  g_object_class_install_property(
      object_class,
      PROP_PROBE_MODE,
      g_param_spec_string(
          "probe-mode",
          "Probe mode",
          "software keeps the reference jpegdec path; pl-probe samples PL status; buffer-probe stamps I420; dma-probe loops each decoded buffer through PL; compressed-dma-probe loops compressed JPEG input through PL before software decode; dma-writeback writes PL-returned bytes downstream",
          "software",
          G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
  g_object_class_install_property(
      object_class,
      PROP_SUMMARY_INTERVAL,
      g_param_spec_uint(
          "summary-interval",
          "Summary interval",
          "Number of decoded frames between JPEGPLDEC_PROFILE markers; 0 disables markers",
          0u, 100000u, 30u,
          G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
  g_object_class_install_property(
      object_class,
      PROP_PL_BASE,
      g_param_spec_uint(
          "pl-base",
          "PL AXI-Lite base",
          "Physical base address for the PL PIP status probe",
          0x40000000u, 0x7fffffffu, DEFAULT_PL_BASE,
          G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
  g_object_class_install_property(
      object_class,
      PROP_PL_MAP_SIZE,
      g_param_spec_uint(
          "pl-map-size",
          "PL AXI-Lite map size",
          "Mapping size for the PL PIP status probe",
          0x1000u, 0x100000u, DEFAULT_PL_MAP_SIZE,
          G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
  g_object_class_install_property(
      object_class,
      PROP_DMA_DEVICE,
      g_param_spec_string(
          "dma-device",
          "PL DMA probe device",
          "Linux misc device used for decoded-buffer PS-to-PL loopback",
          DEFAULT_DMA_DEVICE,
          G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));

  gst_element_class_set_static_metadata(
      element_class,
      "JPEG PL decoder entry point",
      "Codec/Decoder/Image",
      "Project-owned JPEG decoder entry point with software reference and PL data-plane probes",
      "fpga-hdml");

  gst_element_class_add_static_pad_template(element_class, &sink_template);
  gst_element_class_add_static_pad_template(element_class, &src_template);
}

static gboolean
jpegpldec_plugin_init(GstPlugin *plugin)
{
  return gst_element_register(plugin, "jpegpldec", GST_RANK_NONE,
                              GST_TYPE_JPEG_PL_DEC);
}

GST_PLUGIN_DEFINE(
    GST_VERSION_MAJOR,
    GST_VERSION_MINOR,
    jpegpldec,
    "Project-owned JPEG decoder skeleton for later Zynq PL acceleration",
    jpegpldec_plugin_init,
    "0.1.0",
    "LGPL",
    "fpga-hdml",
    "https://github.com/kingguuu8-svg/fpga-hdmi")
