#ifndef JPEGPL_DMA_PROBE_UAPI_H
#define JPEGPL_DMA_PROBE_UAPI_H

#include <linux/ioctl.h>
#include <linux/types.h>

#define JPEGPL_DMA_PROBE_IOC_MAGIC 'J'

#define JPEGPL_DMA_PROBE_STATUS_TX_DONE 0x00000001u
#define JPEGPL_DMA_PROBE_STATUS_RX_DONE 0x00000002u
#define JPEGPL_DMA_PROBE_STATUS_TIMEOUT 0x00000004u
#define JPEGPL_DMA_PROBE_STATUS_COPY_ERR 0x00000008u

struct jpegpl_dma_probe_run {
	__u32 length;
	__u32 timeout_ms;
	__u32 flags;
	__u32 status;
	__u32 checksum_in;
	__u32 checksum_out;
	__u32 reserved0;
	__u32 reserved1;
	__u64 user_in;
	__u64 user_out;
	__u64 elapsed_ns;
};

#define JPEGPL_DMA_PROBE_IOC_RUN \
	_IOWR(JPEGPL_DMA_PROBE_IOC_MAGIC, 0x01, struct jpegpl_dma_probe_run)

#endif
