#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/device.h>
#include <linux/dmaengine.h>
#include <linux/dma-mapping.h>
#include <linux/fs.h>
#include <linux/io.h>
#include <linux/ioctl.h>
#include <linux/jiffies.h>
#include <linux/ktime.h>
#include <linux/math64.h>
#include <linux/mm.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/slab.h>
#include <linux/uaccess.h>

#include "jpegpl_dma_probe.h"

#define JPEGPL_DMA_PROBE_DEFAULT_BUFFER_SIZE (4u * 1024u * 1024u)
#define JPEGPL_DMA_PROBE_DEFAULT_TIMEOUT_MS 1000u
#define JPEGPL_DMA_PROBE_DEFAULT_MAX_TRANSFER_SIZE 16380u

#define JPEGPL_REG_CONTROL 0x00u
#define JPEGPL_REG_DST_BASE 0x04u
#define JPEGPL_REG_STRIDE 0x08u
#define JPEGPL_REG_DIMENSIONS 0x0cu
#define JPEGPL_REG_EXPECTED_PIXELS 0x10u
#define JPEGPL_REG_STATUS 0x14u
#define JPEGPL_REG_PIXELS 0x18u
#define JPEGPL_REG_CYCLES 0x1cu
#define JPEGPL_REG_COMMANDS 0x20u
#define JPEGPL_REG_RESPONSES 0x24u
#define JPEGPL_REG_OUTPUT_BYTES 0x28u
#define JPEGPL_REG_STALL_CYCLES 0x2cu
#define JPEGPL_REG_ERROR_FLAGS 0x30u
#define JPEGPL_REG_INPUT_BYTES 0x34u
#define JPEGPL_REG_LAST_ADDRESS 0x38u
#define JPEGPL_REG_VERSION 0x3cu

#define JPEGPL_HW_STATUS_BUSY BIT(0)
#define JPEGPL_HW_STATUS_DONE BIT(1)
#define JPEGPL_HW_STATUS_ERROR BIT(2)

#define JPEGPL_CONTROL_START BIT(0)
#define JPEGPL_CONTROL_BUSY BIT(0)
#define JPEGPL_CONTROL_COUNT_ONLY BIT(1)
#define JPEGPL_CONTROL_INPUT_SINK BIT(2)
#define JPEGPL_CONTROL_MODE_MASK (JPEGPL_CONTROL_COUNT_ONLY | \
					  JPEGPL_CONTROL_INPUT_SINK)

static bool jpegpl_trace_timing;
module_param_named(trace_timing, jpegpl_trace_timing, bool, 0644);
MODULE_PARM_DESC(trace_timing,
		 "log per-frame driver phase timings when enabled");

struct jpegpl_dma_chan_wait {
	struct completion done;
};

struct jpegpl_dma_probe_dev {
	struct device *dev;
	struct dma_chan *tx_chan;
	struct miscdevice miscdev;
	struct mutex lock;
	void __iomem *regs;
	void *tx_buf;
	void *rx_buf;
	dma_addr_t tx_dma;
	dma_addr_t rx_dma;
	u32 buffer_size;
	u32 max_transfer_size;
	bool output_mmap_logged;
	bool config_valid;
	bool control_verified;
	u32 control_verified_mode;
	u32 configured_width;
	u32 configured_height;
	u32 configured_stride;
};

static void jpegpl_dma_probe_complete(void *arg)
{
	struct jpegpl_dma_chan_wait *wait = arg;

	complete(&wait->done);
}

static void jpegpl_dma_probe_snapshot(struct jpegpl_dma_probe_dev *probe,
				      struct jpegpl_dma_probe_decode *req)
{
	u32 hw_status = readl(probe->regs + JPEGPL_REG_STATUS);

	req->input_bytes = readl(probe->regs + JPEGPL_REG_INPUT_BYTES);
	req->output_bytes = readl(probe->regs + JPEGPL_REG_OUTPUT_BYTES);
	req->pixels = readl(probe->regs + JPEGPL_REG_PIXELS);
	req->cycles = readl(probe->regs + JPEGPL_REG_CYCLES);
	req->commands = readl(probe->regs + JPEGPL_REG_COMMANDS);
	req->responses = readl(probe->regs + JPEGPL_REG_RESPONSES);
	req->stall_cycles = readl(probe->regs + JPEGPL_REG_STALL_CYCLES);
	req->error_flags = readl(probe->regs + JPEGPL_REG_ERROR_FLAGS);
	req->last_address = readl(probe->regs + JPEGPL_REG_LAST_ADDRESS);
	if (hw_status & JPEGPL_HW_STATUS_DONE)
		req->status |= JPEGPL_DMA_PROBE_STATUS_PL_DONE;
	if (hw_status & JPEGPL_HW_STATUS_ERROR)
		req->status |= JPEGPL_DMA_PROBE_STATUS_PL_ERROR;
	if (req->error_flags)
		req->status |= JPEGPL_DMA_PROBE_STATUS_PL_ERROR;
}

static int jpegpl_dma_probe_open(struct inode *inode, struct file *file)
{
	struct miscdevice *misc = file->private_data;
	struct jpegpl_dma_probe_dev *probe =
		container_of(misc, struct jpegpl_dma_probe_dev, miscdev);

	file->private_data = probe;
	return 0;
}

static int jpegpl_dma_probe_mmap(struct file *file, struct vm_area_struct *vma)
{
	struct jpegpl_dma_probe_dev *probe = file->private_data;
	unsigned long size = vma->vm_end - vma->vm_start;

	if (vma->vm_pgoff != 0 || size == 0 || size > probe->buffer_size)
		return -EINVAL;

	return dma_mmap_coherent(probe->dev, vma, probe->rx_buf,
				probe->rx_dma, probe->buffer_size);
}

static int jpegpl_dma_probe_info(
	struct jpegpl_dma_probe_dev *probe,
	struct jpegpl_dma_probe_info __user *argp)
{
	struct jpegpl_dma_probe_info info = {
		.buffer_size = probe->buffer_size,
		.max_transfer_size = probe->max_transfer_size,
		.version = JPEGPL_DMA_PROBE_VERSION,
	};

	if (copy_to_user(argp, &info, sizeof(info)))
		return -EFAULT;
	return 0;
}

static int jpegpl_dma_probe_verify_config(
	struct jpegpl_dma_probe_dev *probe, u32 width, u32 height, u32 stride,
	struct jpegpl_dma_probe_register_smoke *smoke)
{
	u32 dst_base = lower_32_bits(probe->rx_dma);
	u32 dimensions = (height << 16) | width;
	u32 expected_pixels = width * height;

	writel(dst_base, probe->regs + JPEGPL_REG_DST_BASE);
	writel(stride, probe->regs + JPEGPL_REG_STRIDE);
	writel(dimensions, probe->regs + JPEGPL_REG_DIMENSIONS);
	writel(expected_pixels, probe->regs + JPEGPL_REG_EXPECTED_PIXELS);

	smoke->dst_base = readl(probe->regs + JPEGPL_REG_DST_BASE);
	smoke->stride = readl(probe->regs + JPEGPL_REG_STRIDE);
	smoke->dimensions = readl(probe->regs + JPEGPL_REG_DIMENSIONS);
	smoke->expected_pixels = readl(probe->regs + JPEGPL_REG_EXPECTED_PIXELS);
	smoke->version = readl(probe->regs + JPEGPL_REG_VERSION);
	if (smoke->version != JPEGPL_DMA_PROBE_VERSION ||
	    smoke->dst_base != dst_base || smoke->stride != stride ||
	    smoke->dimensions != dimensions ||
	    smoke->expected_pixels != expected_pixels) {
		dev_warn(probe->dev,
			 "JPEGPL_CONFIG_VERIFY_FAILED dst_base=0x%08x stride=%u dimensions=0x%08x expected_pixels=%u version=0x%08x\n",
			 smoke->dst_base, smoke->stride, smoke->dimensions,
			 smoke->expected_pixels, smoke->version);
		return -EIO;
	}
	probe->config_valid = true;
	probe->configured_width = width;
	probe->configured_height = height;
	probe->configured_stride = stride;
	dev_info(probe->dev,
		 "JPEGPL_CONFIG_VERIFIED dst_base=0x%08x stride=%u dimensions=0x%08x expected_pixels=%u version=0x%08x\n",
		 smoke->dst_base, smoke->stride, smoke->dimensions,
		 smoke->expected_pixels, smoke->version);
	return 0;
}

static int jpegpl_dma_probe_start_and_verify_control(
	struct jpegpl_dma_probe_dev *probe, u32 flags)
{
	u32 expected_mode = 0u;
	u32 control;

	if (flags & JPEGPL_DMA_PROBE_DECODE_FLAG_COUNT_ONLY)
		expected_mode |= JPEGPL_CONTROL_COUNT_ONLY;
	if (flags & JPEGPL_DMA_PROBE_DECODE_FLAG_INPUT_SINK)
		expected_mode |= JPEGPL_CONTROL_INPUT_SINK;
	writel(JPEGPL_CONTROL_START | expected_mode,
	       probe->regs + JPEGPL_REG_CONTROL);
	if (probe->control_verified &&
	    probe->control_verified_mode == expected_mode)
		return 0;
	control = readl(probe->regs + JPEGPL_REG_CONTROL);
	if (!(control & JPEGPL_CONTROL_BUSY) ||
	    (control & JPEGPL_CONTROL_MODE_MASK) != expected_mode) {
		dev_warn(probe->dev,
			 "JPEGPL_CONTROL_VERIFY_FAILED control=0x%08x expected_mode=0x%08x\n",
			 control, expected_mode);
		return -EIO;
	}
	probe->control_verified = true;
	probe->control_verified_mode = expected_mode;
	dev_info(probe->dev,
		 "JPEGPL_CONTROL_VERIFIED control=0x%08x mode=0x%08x\n",
		 control, expected_mode);
	return 0;
}

static int jpegpl_dma_probe_send(struct jpegpl_dma_probe_dev *probe,
				 struct jpegpl_dma_probe_decode *req,
				 unsigned long deadline)
{
	struct dma_async_tx_descriptor *tx_desc;
	struct jpegpl_dma_chan_wait tx_wait;
	dma_cookie_t tx_cookie;
	u32 offset = 0u;
	while (offset < req->input_length) {
		unsigned long remaining;
		u32 chunk = min(req->input_length - offset,
				probe->max_transfer_size);

		if (time_after_eq(jiffies, deadline))
			return -ETIMEDOUT;
		remaining = deadline - jiffies;
		init_completion(&tx_wait.done);
		tx_desc = dmaengine_prep_slave_single(
			probe->tx_chan, probe->tx_dma + offset, chunk,
			DMA_MEM_TO_DEV, DMA_PREP_INTERRUPT | DMA_CTRL_ACK);
		if (!tx_desc)
			return -EIO;
		tx_desc->callback = jpegpl_dma_probe_complete;
		tx_desc->callback_param = &tx_wait;
		tx_cookie = dmaengine_submit(tx_desc);
		if (dma_submit_error(tx_cookie))
			return -EIO;

		dma_async_issue_pending(probe->tx_chan);
		if (offset == 0u)
			dev_dbg(probe->dev,
				"JPEGPL_DMA_SUBMITTED input_length=%u\n",
				req->input_length);
		if (!wait_for_completion_timeout(&tx_wait.done, remaining)) {
			dmaengine_terminate_sync(probe->tx_chan);
			return -ETIMEDOUT;
		}
		offset += chunk;
		req->chunks++;
	}
	req->status |= JPEGPL_DMA_PROBE_STATUS_TX_DONE;
	dev_dbg(probe->dev, "JPEGPL_DMA_COMPLETED chunks=%u\n", req->chunks);
	return 0;
}

static int jpegpl_dma_probe_register_smoke(
	struct jpegpl_dma_probe_dev *probe,
	struct jpegpl_dma_probe_register_smoke __user *argp)
{
	struct jpegpl_dma_probe_register_smoke req;
	int ret;

	if (copy_from_user(&req, argp, sizeof(req)))
		return -EFAULT;
	if (!req.width || !req.height || req.stride < req.width * 3u)
		return -EINVAL;

	mutex_lock(&probe->lock);
	ret = jpegpl_dma_probe_verify_config(probe, req.width, req.height,
					     req.stride, &req);
	mutex_unlock(&probe->lock);
	if (copy_to_user(argp, &req, sizeof(req)) && !ret)
		ret = -EFAULT;
	return ret;
}

static int jpegpl_dma_probe_decode(
	struct jpegpl_dma_probe_dev *probe,
	struct jpegpl_dma_probe_decode __user *argp)
{
	struct jpegpl_dma_probe_decode req;
	u64 output_size;
	u64 ioctl_start_ns = ktime_get_ns();
	u64 copy_start_ns;
	u64 copy_ns = 0u;
	u64 config_start_ns;
	u64 config_ns = 0u;
	u64 control_start_ns;
	u64 control_ns = 0u;
	u64 tx_start_ns;
	u64 tx_wait_ns = 0u;
	u64 poll_start_ns;
	u64 poll_ns = 0u;
	u64 post_start_ns;
	u64 post_ns = 0u;
	unsigned long deadline;
	u32 hw_status;
	bool config_matches;
	int ret = 0;

	if (copy_from_user(&req, argp, sizeof(req)))
		return -EFAULT;
	if ((req.flags & JPEGPL_DMA_PROBE_DECODE_FLAG_OUTPUT_MMAP) &&
	    !probe->output_mmap_logged) {
		probe->output_mmap_logged = true;
		dev_info(probe->dev,
			 "JPEGPL_OUTPUT_MMAP_ACTIVE flags=0x%08x output_copy=disabled\n",
			 req.flags);
	}
	req.status = 0;
	req.chunks = 0;
	req.elapsed_ns = 0;
	if (!req.timeout_ms)
		req.timeout_ms = JPEGPL_DMA_PROBE_DEFAULT_TIMEOUT_MS;
	output_size = (u64)req.stride * req.height;
	if (!req.input_length || req.input_length > probe->buffer_size ||
	    !req.width || !req.height || (req.width & 7u) ||
	    req.stride < req.width * 3u || output_size > probe->buffer_size ||
	    !req.user_input ||
	    (!(req.flags & JPEGPL_DMA_PROBE_DECODE_FLAG_OUTPUT_MMAP) &&
	     !req.user_output) ||
	    (req.flags & JPEGPL_DMA_PROBE_DECODE_FLAG_OUTPUT_MMAP &&
	     (req.flags & JPEGPL_DMA_PROBE_DECODE_FLAG_COUNT_ONLY)))
		return -EINVAL;

	mutex_lock(&probe->lock);
	copy_start_ns = ktime_get_ns();
	if (copy_from_user(probe->tx_buf,
			   (const void __user *)(uintptr_t)req.user_input,
			   req.input_length)) {
		req.status |= JPEGPL_DMA_PROBE_STATUS_COPY_ERR;
		ret = -EFAULT;
		goto out;
	}
	copy_ns = ktime_get_ns() - copy_start_ns;
	/* Full-writeback mode overwrites every byte before PL_DONE. */
	dma_wmb();

	config_matches = probe->config_valid &&
		probe->configured_width == req.width &&
		probe->configured_height == req.height &&
		probe->configured_stride == req.stride;
	if (!config_matches) {
		struct jpegpl_dma_probe_register_smoke config;

		config_start_ns = ktime_get_ns();
		ret = jpegpl_dma_probe_verify_config(probe, req.width, req.height,
						     req.stride, &config);
		config_ns = ktime_get_ns() - config_start_ns;
		if (ret)
			goto out;
	}
	control_start_ns = ktime_get_ns();
	ret = jpegpl_dma_probe_start_and_verify_control(probe, req.flags);
	control_ns = ktime_get_ns() - control_start_ns;
	if (ret)
		goto out;
	req.elapsed_ns = ktime_get_ns();
	deadline = jiffies + msecs_to_jiffies(req.timeout_ms);

	tx_start_ns = ktime_get_ns();
	ret = jpegpl_dma_probe_send(probe, &req, deadline);
	tx_wait_ns = ktime_get_ns() - tx_start_ns;
	if (ret) {
		if (ret == -ETIMEDOUT)
			req.status |= JPEGPL_DMA_PROBE_STATUS_TIMEOUT;
		jpegpl_dma_probe_snapshot(probe, &req);
		goto out_terminate;
	}
	if (req.flags & JPEGPL_DMA_PROBE_DECODE_FLAG_INPUT_SINK) {
		jpegpl_dma_probe_snapshot(probe, &req);
		req.elapsed_ns = ktime_get_ns() - req.elapsed_ns;
		goto out;
	}

	poll_start_ns = ktime_get_ns();
	do {
		hw_status = readl(probe->regs + JPEGPL_REG_STATUS);
		if (hw_status & JPEGPL_HW_STATUS_DONE)
			break;
		usleep_range(500, 1000);
	} while (time_before(jiffies, deadline));
	poll_ns = ktime_get_ns() - poll_start_ns;
	if (!(hw_status & JPEGPL_HW_STATUS_DONE)) {
		req.status |= JPEGPL_DMA_PROBE_STATUS_TIMEOUT;
		jpegpl_dma_probe_snapshot(probe, &req);
		ret = -ETIMEDOUT;
		goto out_terminate;
	}
	req.status |= JPEGPL_DMA_PROBE_STATUS_PL_DONE;
	if (hw_status & JPEGPL_HW_STATUS_ERROR)
		req.status |= JPEGPL_DMA_PROBE_STATUS_PL_ERROR;

	post_start_ns = ktime_get_ns();
	jpegpl_dma_probe_snapshot(probe, &req);
	req.elapsed_ns = ktime_get_ns() - req.elapsed_ns;
	if (req.error_flags) {
		req.status |= JPEGPL_DMA_PROBE_STATUS_PL_ERROR;
		ret = -EIO;
		goto out_terminate;
	}

	if (!(req.flags & JPEGPL_DMA_PROBE_DECODE_FLAG_COUNT_ONLY)) {
		dma_rmb();
	}
	if (!(req.flags & JPEGPL_DMA_PROBE_DECODE_FLAG_COUNT_ONLY) &&
	    !(req.flags & JPEGPL_DMA_PROBE_DECODE_FLAG_OUTPUT_MMAP)) {
		if (copy_to_user((void __user *)(uintptr_t)req.user_output,
				 probe->rx_buf, output_size)) {
			req.status |= JPEGPL_DMA_PROBE_STATUS_COPY_ERR;
			ret = -EFAULT;
		}
	}
	post_ns = ktime_get_ns() - post_start_ns;
	goto out;

out_terminate:
	req.elapsed_ns = ktime_get_ns() - req.elapsed_ns;
	dev_warn(probe->dev,
		 "JPEGPL_DECODE_ABORT status=0x%08x input_bytes=%u output_bytes=%u pixels=%u cycles=%u commands=%u responses=%u stalls=%u errors=0x%08x chunks=%u last_address=0x%08x\n",
		 req.status, req.input_bytes, req.output_bytes, req.pixels,
		 req.cycles, req.commands, req.responses, req.stall_cycles,
		 req.error_flags, req.chunks, req.last_address);
	dmaengine_terminate_sync(probe->tx_chan);
out:
	if (jpegpl_trace_timing)
		dev_info(probe->dev,
			 "JPEGPL_TIMING flags=0x%08x copy_us=%llu config_us=%llu control_us=%llu tx_wait_us=%llu pl_poll_us=%llu post_us=%llu driver_window_us=%llu ioctl_us=%llu status=0x%08x\n",
			 req.flags,
			 div_u64(copy_ns, 1000u),
			 div_u64(config_ns, 1000u),
			 div_u64(control_ns, 1000u),
			 div_u64(tx_wait_ns, 1000u),
			 div_u64(poll_ns, 1000u),
			 div_u64(post_ns, 1000u),
			 div_u64(req.elapsed_ns, 1000u),
			 div_u64(ktime_get_ns() - ioctl_start_ns, 1000u),
			 req.status);
	if (copy_to_user(argp, &req, sizeof(req)) && !ret)
		ret = -EFAULT;
	mutex_unlock(&probe->lock);
	return ret;
}

static long jpegpl_dma_probe_ioctl(struct file *file, unsigned int cmd,
				   unsigned long arg)
{
	struct jpegpl_dma_probe_dev *probe = file->private_data;

	switch (cmd) {
	case JPEGPL_DMA_PROBE_IOC_RUN:
		return -EOPNOTSUPP;
	case JPEGPL_DMA_PROBE_IOC_DECODE:
		return jpegpl_dma_probe_decode(
			probe, (struct jpegpl_dma_probe_decode __user *)arg);
	case JPEGPL_DMA_PROBE_IOC_REGISTER_SMOKE:
		return jpegpl_dma_probe_register_smoke(
			probe, (struct jpegpl_dma_probe_register_smoke __user *)arg);
	case JPEGPL_DMA_PROBE_IOC_INFO:
		return jpegpl_dma_probe_info(
			probe, (struct jpegpl_dma_probe_info __user *)arg);
	default:
		return -ENOTTY;
	}
}

static const struct file_operations jpegpl_dma_probe_fops = {
	.owner = THIS_MODULE,
	.open = jpegpl_dma_probe_open,
	.mmap = jpegpl_dma_probe_mmap,
	.unlocked_ioctl = jpegpl_dma_probe_ioctl,
};

static int jpegpl_dma_probe_probe(struct platform_device *pdev)
{
	struct jpegpl_dma_probe_dev *probe;
	struct resource *resource;
	u32 buffer_size = JPEGPL_DMA_PROBE_DEFAULT_BUFFER_SIZE;
	u32 max_transfer_size = JPEGPL_DMA_PROBE_DEFAULT_MAX_TRANSFER_SIZE;
	int ret;

	probe = devm_kzalloc(&pdev->dev, sizeof(*probe), GFP_KERNEL);
	if (!probe)
		return -ENOMEM;
	probe->dev = &pdev->dev;
	mutex_init(&probe->lock);
	of_property_read_u32(pdev->dev.of_node, "buffer-size", &buffer_size);
	of_property_read_u32(pdev->dev.of_node, "max-transfer-size",
			     &max_transfer_size);
	probe->buffer_size = buffer_size;
	probe->max_transfer_size = min(max_transfer_size, buffer_size);
	if (!probe->max_transfer_size)
		return -EINVAL;

	resource = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	probe->regs = devm_ioremap_resource(&pdev->dev, resource);
	if (IS_ERR(probe->regs))
		return PTR_ERR(probe->regs);
	probe->tx_chan = dma_request_chan(&pdev->dev, "tx");
	if (IS_ERR(probe->tx_chan))
		return PTR_ERR(probe->tx_chan);
	probe->tx_buf = dmam_alloc_coherent(&pdev->dev, probe->buffer_size,
					    &probe->tx_dma, GFP_KERNEL);
	probe->rx_buf = dmam_alloc_coherent(&pdev->dev, probe->buffer_size,
					    &probe->rx_dma, GFP_KERNEL);
	if (!probe->tx_buf || !probe->rx_buf) {
		ret = -ENOMEM;
		goto err_release_tx;
	}

	probe->miscdev.minor = MISC_DYNAMIC_MINOR;
	probe->miscdev.name = "jpegpl_dma_probe";
	probe->miscdev.fops = &jpegpl_dma_probe_fops;
	probe->miscdev.parent = &pdev->dev;
	ret = misc_register(&probe->miscdev);
	if (ret)
		goto err_release_tx;
	platform_set_drvdata(pdev, probe);
	dev_info(&pdev->dev,
		 "JPEGPL_DECODER_READY dev=/dev/%s buffer_size=%u tx_dma=%pad output_dma=%pad\n",
		 probe->miscdev.name, probe->buffer_size,
		 &probe->tx_dma, &probe->rx_dma);
	return 0;

err_release_tx:
	dma_release_channel(probe->tx_chan);
	return ret;
}

static int jpegpl_dma_probe_remove(struct platform_device *pdev)
{
	struct jpegpl_dma_probe_dev *probe = platform_get_drvdata(pdev);

	misc_deregister(&probe->miscdev);
	dmaengine_terminate_sync(probe->tx_chan);
	dma_release_channel(probe->tx_chan);
	return 0;
}

static const struct of_device_id jpegpl_dma_probe_of_match[] = {
	{ .compatible = "fpga-hdml,jpegpl-dma-probe-1.0" },
	{ }
};
MODULE_DEVICE_TABLE(of, jpegpl_dma_probe_of_match);

static struct platform_driver jpegpl_dma_probe_driver = {
	.probe = jpegpl_dma_probe_probe,
	.remove = jpegpl_dma_probe_remove,
	.driver = {
		.name = "jpegpl_dma_probe",
		.of_match_table = jpegpl_dma_probe_of_match,
		.suppress_bind_attrs = true,
	},
};

module_platform_driver(jpegpl_dma_probe_driver);

MODULE_AUTHOR("fpga-hdml");
MODULE_DESCRIPTION("AXI DMA and PL JPEG frame decoder client");
MODULE_LICENSE("GPL");
