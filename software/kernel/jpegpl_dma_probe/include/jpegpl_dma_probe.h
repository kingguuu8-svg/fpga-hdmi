#ifndef JPEGPL_DMA_PROBE_UAPI_H
#define JPEGPL_DMA_PROBE_UAPI_H

#include <linux/ioctl.h>
#include <linux/types.h>

#define JPEGPL_DMA_PROBE_IOC_MAGIC 'J'

#define JPEGPL_DMA_PROBE_STATUS_TX_DONE 0x00000001u
#define JPEGPL_DMA_PROBE_STATUS_RX_DONE 0x00000002u
#define JPEGPL_DMA_PROBE_STATUS_TIMEOUT 0x00000004u
#define JPEGPL_DMA_PROBE_STATUS_COPY_ERR 0x00000008u
#define JPEGPL_DMA_PROBE_STATUS_PL_DONE  0x00000010u
#define JPEGPL_DMA_PROBE_STATUS_PL_ERROR 0x00000020u

#define JPEGPL_DMA_PROBE_VERSION 0x4a504c31u

#define JPEGPL_DMA_PROBE_DECODE_FLAG_COUNT_ONLY 0x00000001u
#define JPEGPL_DMA_PROBE_DECODE_FLAG_INPUT_SINK 0x00000002u
#define JPEGPL_DMA_PROBE_DECODE_FLAG_OUTPUT_MMAP 0x00000004u
#define JPEGPL_DMA_PROBE_DECODE_FLAG_OUTPUT_DMABUF 0x00000008u
#define JPEGPL_DMA_PROBE_DECODE_FLAG_DMABUF_CPU_SYNC 0x00000010u
#define JPEGPL_DMA_PROBE_DECODE_FLAG_DMABUF_SKIP_DEVICE_SYNC 0x00000020u

#define JPEGPL_DMA_PROBE_MAX_DMABUF_SLOTS 4u

struct jpegpl_dma_probe_run {
	__u32 length;
	__u32 timeout_ms;
	__u32 flags;
	__u32 status;
	__u32 checksum_in;
	__u32 checksum_out;
	__u32 chunks;
	__u32 max_chunk_size;
	__u64 user_in;
	__u64 user_out;
	__u64 elapsed_ns;
};

#define JPEGPL_DMA_PROBE_IOC_RUN \
	_IOWR(JPEGPL_DMA_PROBE_IOC_MAGIC, 0x01, struct jpegpl_dma_probe_run)

struct jpegpl_dma_probe_decode {
	__u32 input_length;
	__u32 width;
	__u32 height;
	__u32 stride;
	__u32 timeout_ms;
	__u32 flags;
	__u32 status;
	__u32 input_bytes;
	__u32 output_bytes;
	__u32 pixels;
	__u32 cycles;
	__u32 commands;
	__u32 responses;
	__u32 stall_cycles;
	__u32 error_flags;
	__u32 last_address;
	__u32 chunks;
	__u64 user_input;
	__u64 user_output;
	__u64 elapsed_ns;
};

#define JPEGPL_DMA_PROBE_IOC_DECODE \
	_IOWR(JPEGPL_DMA_PROBE_IOC_MAGIC, 0x02, struct jpegpl_dma_probe_decode)

struct jpegpl_dma_probe_info {
	__u32 buffer_size;
	__u32 max_transfer_size;
	__u32 version;
	__u32 reserved;
};

#define JPEGPL_DMA_PROBE_IOC_INFO \
	_IOR(JPEGPL_DMA_PROBE_IOC_MAGIC, 0x04, struct jpegpl_dma_probe_info)

struct jpegpl_dma_probe_dmabuf_register {
	__s32 fd;
	__u32 slot;
	__u32 size;
	__u32 width;
	__u32 height;
	__u32 stride;
	__u32 reserved;
};

#define JPEGPL_DMA_PROBE_IOC_REGISTER_DMABUF \
	_IOWR(JPEGPL_DMA_PROBE_IOC_MAGIC, 0x05, \
	      struct jpegpl_dma_probe_dmabuf_register)

struct jpegpl_dma_probe_dmabuf_unregister {
	__u32 slot;
	__u32 reserved;
};

#define JPEGPL_DMA_PROBE_IOC_UNREGISTER_DMABUF \
	_IOW(JPEGPL_DMA_PROBE_IOC_MAGIC, 0x06, \
	     struct jpegpl_dma_probe_dmabuf_unregister)

struct jpegpl_dma_probe_decode_dmabuf {
	struct jpegpl_dma_probe_decode decode;
	__u32 output_slot;
	__u32 reserved;
};

#define JPEGPL_DMA_PROBE_IOC_DECODE_DMABUF \
	_IOWR(JPEGPL_DMA_PROBE_IOC_MAGIC, 0x07, \
	      struct jpegpl_dma_probe_decode_dmabuf)

struct jpegpl_dma_probe_register_smoke {
	__u32 width;
	__u32 height;
	__u32 stride;
	__u32 dst_base;
	__u32 dimensions;
	__u32 expected_pixels;
	__u32 version;
};

#define JPEGPL_DMA_PROBE_IOC_REGISTER_SMOKE \
	_IOWR(JPEGPL_DMA_PROBE_IOC_MAGIC, 0x03, \
	      struct jpegpl_dma_probe_register_smoke)

#endif
