#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>

#include "jpegpl_dma_probe.h"

#define DEFAULT_DEVICE "/dev/jpegpl_dma_probe"
#define JPEGPL_MIN_COUNTER_PERIOD_NS 5ull

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

static int run_self_test(void)
{
	static const uint8_t sample[8] = { 0, 1, 2, 3, 4, 5, 6, 7 };
	uint32_t checksum = fnv1a32(sample, sizeof(sample));

	if (checksum != 0x6bf6a41du) {
		fprintf(stderr, "unexpected checksum 0x%08x\n", checksum);
		return 1;
	}
	printf("JPEGPL_DMA_PROBE_TEST_SELF_TEST_OK checksum=0x%08x\n", checksum);
	return 0;
}

static uint8_t *read_file(const char *path, size_t *size)
{
	struct stat statbuf;
	uint8_t *data;
	FILE *file;

	if (stat(path, &statbuf) != 0 || statbuf.st_size <= 0)
		return NULL;
	data = malloc((size_t)statbuf.st_size);
	if (!data)
		return NULL;
	file = fopen(path, "rb");
	if (!file || fread(data, 1, (size_t)statbuf.st_size, file) !=
			(size_t)statbuf.st_size) {
		if (file)
			fclose(file);
		free(data);
		return NULL;
	}
	fclose(file);
	*size = (size_t)statbuf.st_size;
	return data;
}

int main(int argc, char **argv)
{
	const char *device = DEFAULT_DEVICE;
	const char *input_path = NULL;
	const char *output_path = NULL;
	uint32_t width = 1280;
	uint32_t height = 720;
	uint32_t timeout_ms = 2000;
	uint32_t expected_fnv = 0;
	uint32_t output_fnv;
	uint64_t min_cycles;
	uint64_t max_cycles;
	int count_only = 0;
	int input_sink = 0;
	int register_smoke = 0;
	int expect_fnv = 0;
	struct jpegpl_dma_probe_decode req;
	struct jpegpl_dma_probe_register_smoke smoke;
	uint8_t *input = NULL;
	uint8_t *output = NULL;
	size_t input_size = 0;
	size_t output_size;
	FILE *output_file;
	int fd = -1;
	int ret = 1;
	int i;

	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--self-test"))
			return run_self_test();
		else if (!strcmp(argv[i], "--register-smoke"))
			register_smoke = 1;
		else if (!strcmp(argv[i], "--device") && i + 1 < argc)
			device = argv[++i];
		else if (!strcmp(argv[i], "--decode") && i + 2 < argc) {
			input_path = argv[++i];
			output_path = argv[++i];
		} else if (!strcmp(argv[i], "--width") && i + 1 < argc)
			width = (uint32_t)strtoul(argv[++i], NULL, 0);
		else if (!strcmp(argv[i], "--height") && i + 1 < argc)
			height = (uint32_t)strtoul(argv[++i], NULL, 0);
		else if (!strcmp(argv[i], "--timeout-ms") && i + 1 < argc)
			timeout_ms = (uint32_t)strtoul(argv[++i], NULL, 0);
		else if (!strcmp(argv[i], "--expect-fnv") && i + 1 < argc) {
			expected_fnv = (uint32_t)strtoul(argv[++i], NULL, 0);
			expect_fnv = 1;
		}
		else if (!strcmp(argv[i], "--count-only"))
			count_only = 1;
		else if (!strcmp(argv[i], "--input-sink"))
			input_sink = 1;
		else {
			fprintf(stderr,
				"usage: %s --self-test | --register-smoke [--width n] [--height n] [--device path] | --decode input.jpg output.bgr [--width n] [--height n] [--timeout-ms n] [--count-only] [--input-sink] [--expect-fnv value] [--device path]\n",
				argv[0]);
			return 2;
		}
	}
	if (register_smoke && (input_path || output_path))
		return 2;
	if (!register_smoke && (!input_path || !output_path))
		return 2;
	if (expect_fnv && (register_smoke || count_only || input_sink))
		return 2;
	if (register_smoke) {
		fd = open(device, O_RDWR);
		if (fd < 0) {
			fprintf(stderr, "open %s failed: %s\n", device, strerror(errno));
			goto out;
		}
		memset(&smoke, 0, sizeof(smoke));
		smoke.width = width;
		smoke.height = height;
		smoke.stride = width * 3u;
		if (ioctl(fd, JPEGPL_DMA_PROBE_IOC_REGISTER_SMOKE, &smoke) != 0) {
			fprintf(stderr, "register smoke ioctl failed: %s\n",
				strerror(errno));
			goto out;
		}
		if (smoke.version != JPEGPL_DMA_PROBE_VERSION ||
		    smoke.dimensions != ((height << 16) | width) ||
		    smoke.expected_pixels != width * height ||
		    smoke.stride != width * 3u) {
			fprintf(stderr, "register smoke readback gate failed\n");
			goto out;
		}
		printf("JPEGPL_REGISTER_SMOKE_OK dst_base=0x%08x stride=%u dimensions=0x%08x expected_pixels=%u version=0x%08x\n",
		       smoke.dst_base, smoke.stride, smoke.dimensions,
		       smoke.expected_pixels, smoke.version);
		ret = 0;
		goto out;
	}
	input = read_file(input_path, &input_size);
	if (!input || input_size > UINT32_MAX) {
		fprintf(stderr, "read %s failed\n", input_path);
		goto out;
	}
	output_size = (size_t)width * height * 3u;
	output = calloc(1, output_size);
	if (!output) {
		fprintf(stderr, "output allocation failed\n");
		goto out;
	}
	fd = open(device, O_RDWR);
	if (fd < 0) {
		fprintf(stderr, "open %s failed: %s\n", device, strerror(errno));
		goto out;
	}

	memset(&req, 0, sizeof(req));
	req.input_length = (uint32_t)input_size;
	req.width = width;
	req.height = height;
	req.stride = width * 3u;
	req.timeout_ms = timeout_ms;
	if (count_only)
		req.flags |= JPEGPL_DMA_PROBE_DECODE_FLAG_COUNT_ONLY;
	if (input_sink)
		req.flags |= JPEGPL_DMA_PROBE_DECODE_FLAG_INPUT_SINK;
	req.user_input = (uintptr_t)input;
	req.user_output = (uintptr_t)output;
	if (ioctl(fd, JPEGPL_DMA_PROBE_IOC_DECODE, &req) != 0) {
		fprintf(stderr,
			"decode ioctl failed: %s status=0x%08x errors=0x%08x\n",
			strerror(errno), req.status, req.error_flags);
		goto out;
	}
	if (!count_only && !input_sink) {
		output_file = fopen(output_path, "wb");
		if (!output_file || fwrite(output, 1, output_size, output_file) != output_size) {
			fprintf(stderr, "write %s failed\n", output_path);
			if (output_file)
				fclose(output_file);
			goto out;
		}
		fclose(output_file);
	}
	output_fnv = fnv1a32(output, output_size);
	printf("JPEGPL_DECODE_RESULT status=0x%08x flags=0x%08x input_bytes=%u output_bytes=%u pixels=%u cycles=%u commands=%u responses=%u stalls=%u errors=0x%08x chunks=%u elapsed_ns=%" PRIu64 " output_fnv=0x%08x\n",
	       req.status, req.flags, req.input_bytes, req.output_bytes, req.pixels,
	       req.cycles, req.commands, req.responses, req.stall_cycles,
	       req.error_flags, req.chunks, (uint64_t)req.elapsed_ns,
	       output_fnv);
	min_cycles = input_sink ? (req.input_bytes + 3u) / 4u :
		(uint64_t)width * height;
	max_cycles = req.elapsed_ns / JPEGPL_MIN_COUNTER_PERIOD_NS + 1u;
	if (req.cycles < min_cycles || req.cycles > max_cycles) {
		fprintf(stderr,
			"hardware cycle counter gate failed: cycles=%u min_cycles=%" PRIu64 " max_cycles=%" PRIu64 " elapsed_ns=%" PRIu64 "\n",
			req.cycles, min_cycles, max_cycles,
			(uint64_t)req.elapsed_ns);
		goto out;
	}
	if (expect_fnv && output_fnv != expected_fnv) {
		fprintf(stderr,
			"output FNV gate failed: actual=0x%08x expected=0x%08x\n",
			output_fnv, expected_fnv);
		goto out;
	}
	if (input_sink) {
		if (req.status != JPEGPL_DMA_PROBE_STATUS_TX_DONE ||
		    req.input_bytes != input_size || req.output_bytes != 0 ||
		    req.pixels != 0 || req.commands != 0 || req.responses != 0 ||
		    req.error_flags) {
			fprintf(stderr, "input sink counter gate failed\n");
			goto out;
		}
	} else if (req.status != (JPEGPL_DMA_PROBE_STATUS_TX_DONE |
				  JPEGPL_DMA_PROBE_STATUS_PL_DONE) ||
		   req.input_bytes != input_size ||
		   req.output_bytes != (count_only ? 0u : output_size) ||
		   req.pixels != width * height || req.commands != req.responses ||
		   (count_only && req.commands != 0) ||
		   req.error_flags) {
		fprintf(stderr, "hardware counter gate failed\n");
		goto out;
	}
	printf("JPEGPL_DECODE_OK mode=%s output=%s\n",
	       input_sink ? "input-sink" :
	       (count_only ? "count-only" : "rgb-writeback"), output_path);
	ret = 0;

out:
	if (fd >= 0)
		close(fd);
	free(input);
	free(output);
	return ret;
}
