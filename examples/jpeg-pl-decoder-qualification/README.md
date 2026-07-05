# JPEG PL Decoder Qualification

This example qualifies the pinned `ultraembedded/core_jpeg` RTL against the
project's 720p30 JPEG contract. It is intentionally standalone: it proves that
the decoder itself accepts the current baseline 4:2:0 profile before the core
is connected to Linux, DMA, or `jpegpldec`.

Run the complete gate from PowerShell:

```powershell
rtk powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\examples\jpeg-pl-decoder-qualification\run-qualification.ps1
```

The gate performs:

1. JPEG-vector preparation and software-reference decode.
2. RTL decode in xsim with writable Huffman tables enabled.
3. Pixel-coordinate reconstruction and software/RTL comparison.
4. XC7Z020 synthesis and implementation at the qualification clock.
5. Timing, DRC, resource, and throughput checks.

The RTL is pinned under `third_party/ultraembedded-core-jpeg`; see its
`UPSTREAM.md` and `LICENSE` files.
