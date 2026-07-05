# Upstream Provenance

- Project: `ultraembedded/core_jpeg`
- Repository: https://github.com/ultraembedded/core_jpeg
- Commit: `f9e269a6687ed341b122cdd1412d101ee163e199`
- License: Apache-2.0, retained in `LICENSE`
- Imported scope: synthesizable Verilog sources from `src_v/`, with trailing
  whitespace normalized and no logic changes

The qualification instantiates `jpeg_core` with its fixed standard Huffman
tables. The current GStreamer `jpegenc` stream carries DHT markers containing
the standard tables; software/RTL pixel comparison is the compatibility gate.
