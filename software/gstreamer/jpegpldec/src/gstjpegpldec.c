#include <gst/gst.h>

typedef struct _GstJpegPlDec {
  GstBin parent;
  GstElement *decoder;
} GstJpegPlDec;

typedef struct _GstJpegPlDecClass {
  GstBinClass parent_class;
} GstJpegPlDecClass;

#define GST_TYPE_JPEG_PL_DEC (gst_jpeg_pl_dec_get_type())
GType gst_jpeg_pl_dec_get_type(void);

G_DEFINE_TYPE(GstJpegPlDec, gst_jpeg_pl_dec, GST_TYPE_BIN)

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
gst_jpeg_pl_dec_init(GstJpegPlDec *self)
{
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
}

static void
gst_jpeg_pl_dec_class_init(GstJpegPlDecClass *klass)
{
  GstElementClass *element_class = GST_ELEMENT_CLASS(klass);

  gst_element_class_set_static_metadata(
      element_class,
      "JPEG PL decoder skeleton",
      "Codec/Decoder/Image",
      "Project-owned JPEG decoder entry point; current implementation wraps jpegdec as the software reference path",
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
