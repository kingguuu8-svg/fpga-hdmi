#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "jpegpl_dma_probe.h"

#define DEFAULT_DEVICE "/dev/jpegpl_dma_probe"
#define DEFAULT_LENGTH 115200u

static uint32_t fnv1a32(const uint8_t *data, size_t size)
{
	uint32_t hash = 2166136261u;
	size_t i;

	for (i = 0; i < size; i++) {
		hash ^= data[i];
		hash *= 16777619u;
	}
	return hash;
}

static void fill_pattern(uint8_t *data, size_t size)
{
	size_t i;

	for (i = 0; i < size; i++)
		data[i] = (uint8_t)((i * 37u + (i >> 3) + 0x5au) & 0xffu);
}

static int run_self_test(void)
{
	uint8_t sample[32];
	uint32_t checksum;

	fill_pattern(sample, sizeof(sample));
	checksum = fnv1a32(sample, sizeof(sample));
	if (checksum != 0x6fd741bdu) {
		fprintf(stderr, "unexpected checksum 0x%08x\n", checksum);
		return 1;
	}
	printf("JPEGPL_DMA_PROBE_TEST_SELF_TEST_OK checksum=0x%08x\n", checksum);
	return 0;
}

int main(int argc, char **argv)
{
	const char *device = DEFAULT_DEVICE;
	uint32_t length = DEFAULT_LENGTH;
	uint32_t timeout_ms = 1000u;
	uint8_t *input;
	uint8_t *output;
	struct jpegpl_dma_probe_run req;
	int fd;
	int ret = 1;
	int i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--self-test") == 0)
			return run_self_test();
		if (strcmp(argv[i], "--device") == 0 && i + 1 < argc) {
			device = argv[++i];
		} else if (strcmp(argv[i], "--length") == 0 && i + 1 < argc) {
			length = (uint32_t)strtoul(argv[++i], NULL, 0);
		} else if (strcmp(argv[i], "--timeout-ms") == 0 && i + 1 < argc) {
			timeout_ms = (uint32_t)strtoul(argv[++i], NULL, 0);
		} else {
			fprintf(stderr,
				"usage: %s [--self-test] [--device path] [--length bytes] [--timeout-ms ms]\n",
				argv[0]);
			return 2;
		}
	}

	input = malloc(length);
	output = malloc(length);
	if (!input || !output) {
		fprintf(stderr, "malloc failed\n");
		goto out_free;
	}
	fill_pattern(input, length);
	memset(output, 0, length);

	fd = open(device, O_RDWR);
	if (fd < 0) {
		fprintf(stderr, "open %s failed: %s\n", device, strerror(errno));
		goto out_free;
	}

	memset(&req, 0, sizeof(req));
	req.length = length;
	req.timeout_ms = timeout_ms;
	req.user_in = (uintptr_t)input;
	req.user_out = (uintptr_t)output;

	if (ioctl(fd, JPEGPL_DMA_PROBE_IOC_RUN, &req) != 0) {
		fprintf(stderr, "ioctl failed: %s status=0x%08x\n",
			strerror(errno), req.status);
		goto out_close;
	}

	printf("JPEGPL_DMA_PROBE_TEST_RESULT length=%u status=0x%08x checksum_in=0x%08x checksum_out=0x%08x elapsed_ns=%" PRIu64 "\n",
	       req.length, req.status, req.checksum_in, req.checksum_out,
	       (uint64_t)req.elapsed_ns);

	if (memcmp(input, output, length) != 0) {
		fprintf(stderr, "loopback data mismatch\n");
		goto out_close;
	}
	printf("JPEGPL_DMA_PROBE_TEST_OK length=%u checksum=0x%08x\n",
	       length, fnv1a32(output, length));
	ret = 0;

out_close:
	close(fd);
out_free:
	free(input);
	free(output);
	return ret;
}
