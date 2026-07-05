#include <linux/completion.h>
#include <linux/device.h>
#include <linux/dmaengine.h>
#include <linux/dma-mapping.h>
#include <linux/fs.h>
#include <linux/ioctl.h>
#include <linux/ktime.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/slab.h>
#include <linux/uaccess.h>

#include "jpegpl_dma_probe.h"

#define JPEGPL_DMA_PROBE_DEFAULT_BUFFER_SIZE (2u * 1024u * 1024u)
#define JPEGPL_DMA_PROBE_DEFAULT_TIMEOUT_MS 1000u

struct jpegpl_dma_chan_wait {
	struct completion done;
	enum dma_status status;
};

struct jpegpl_dma_probe_dev {
	struct device *dev;
	struct dma_chan *tx_chan;
	struct dma_chan *rx_chan;
	struct miscdevice miscdev;
	struct mutex lock;
	void *tx_buf;
	void *rx_buf;
	dma_addr_t tx_dma;
	dma_addr_t rx_dma;
	u32 buffer_size;
};

static u32 jpegpl_dma_probe_fnv1a32(const u8 *data, size_t size)
{
	u32 hash = 2166136261u;
	size_t i;

	for (i = 0; i < size; i++) {
		hash ^= data[i];
		hash *= 16777619u;
	}
	return hash;
}

static void jpegpl_dma_probe_complete(void *arg)
{
	struct jpegpl_dma_chan_wait *wait = arg;

	wait->status = DMA_COMPLETE;
	complete(&wait->done);
}

static int jpegpl_dma_probe_open(struct inode *inode, struct file *file)
{
	struct miscdevice *misc = file->private_data;
	struct jpegpl_dma_probe_dev *probe =
		container_of(misc, struct jpegpl_dma_probe_dev, miscdev);

	file->private_data = probe;
	return 0;
}

static int jpegpl_dma_probe_run(struct jpegpl_dma_probe_dev *probe,
				struct jpegpl_dma_probe_run __user *argp)
{
	struct jpegpl_dma_probe_run req;
	struct dma_async_tx_descriptor *rx_desc;
	struct dma_async_tx_descriptor *tx_desc;
	struct jpegpl_dma_chan_wait rx_wait;
	struct jpegpl_dma_chan_wait tx_wait;
	dma_cookie_t rx_cookie;
	dma_cookie_t tx_cookie;
	unsigned long timeout;
	u64 started_ns;
	int ret = 0;

	if (copy_from_user(&req, argp, sizeof(req)))
		return -EFAULT;

	req.status = 0u;
	req.elapsed_ns = 0u;
	if (req.timeout_ms == 0u)
		req.timeout_ms = JPEGPL_DMA_PROBE_DEFAULT_TIMEOUT_MS;

	if (req.length == 0u || req.length > probe->buffer_size)
		return -EINVAL;
	if (req.user_in == 0u || req.user_out == 0u)
		return -EINVAL;

	mutex_lock(&probe->lock);

	if (copy_from_user(probe->tx_buf,
			   (const void __user *)(uintptr_t)req.user_in,
			   req.length)) {
		req.status |= JPEGPL_DMA_PROBE_STATUS_COPY_ERR;
		ret = -EFAULT;
		goto out_copy_req;
	}

	memset(probe->rx_buf, 0, req.length);
	req.checksum_in = jpegpl_dma_probe_fnv1a32(probe->tx_buf, req.length);

	init_completion(&rx_wait.done);
	init_completion(&tx_wait.done);
	rx_wait.status = DMA_IN_PROGRESS;
	tx_wait.status = DMA_IN_PROGRESS;

	rx_desc = dmaengine_prep_slave_single(probe->rx_chan, probe->rx_dma,
					      req.length, DMA_DEV_TO_MEM,
					      DMA_PREP_INTERRUPT | DMA_CTRL_ACK);
	if (!rx_desc) {
		ret = -EIO;
		goto out_copy_req;
	}
	tx_desc = dmaengine_prep_slave_single(probe->tx_chan, probe->tx_dma,
					      req.length, DMA_MEM_TO_DEV,
					      DMA_PREP_INTERRUPT | DMA_CTRL_ACK);
	if (!tx_desc) {
		ret = -EIO;
		goto out_copy_req;
	}

	rx_desc->callback = jpegpl_dma_probe_complete;
	rx_desc->callback_param = &rx_wait;
	tx_desc->callback = jpegpl_dma_probe_complete;
	tx_desc->callback_param = &tx_wait;

	rx_cookie = dmaengine_submit(rx_desc);
	tx_cookie = dmaengine_submit(tx_desc);
	if (dma_submit_error(rx_cookie) || dma_submit_error(tx_cookie)) {
		ret = -EIO;
		goto out_terminate;
	}

	started_ns = ktime_get_ns();
	dma_async_issue_pending(probe->rx_chan);
	dma_async_issue_pending(probe->tx_chan);

	timeout = msecs_to_jiffies(req.timeout_ms);
	if (!wait_for_completion_timeout(&tx_wait.done, timeout)) {
		req.status |= JPEGPL_DMA_PROBE_STATUS_TIMEOUT;
		ret = -ETIMEDOUT;
		goto out_terminate;
	}
	req.status |= JPEGPL_DMA_PROBE_STATUS_TX_DONE;

	if (!wait_for_completion_timeout(&rx_wait.done, timeout)) {
		req.status |= JPEGPL_DMA_PROBE_STATUS_TIMEOUT;
		ret = -ETIMEDOUT;
		goto out_terminate;
	}
	req.status |= JPEGPL_DMA_PROBE_STATUS_RX_DONE;
	req.elapsed_ns = ktime_get_ns() - started_ns;
	req.checksum_out = jpegpl_dma_probe_fnv1a32(probe->rx_buf, req.length);

	if (copy_to_user((void __user *)(uintptr_t)req.user_out,
			 probe->rx_buf, req.length)) {
		req.status |= JPEGPL_DMA_PROBE_STATUS_COPY_ERR;
		ret = -EFAULT;
	}

out_terminate:
	if (ret)
		dmaengine_terminate_sync(probe->tx_chan);
	if (ret)
		dmaengine_terminate_sync(probe->rx_chan);
out_copy_req:
	if (copy_to_user(argp, &req, sizeof(req)) && ret == 0)
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
		return jpegpl_dma_probe_run(
			probe, (struct jpegpl_dma_probe_run __user *)arg);
	default:
		return -ENOTTY;
	}
}

static const struct file_operations jpegpl_dma_probe_fops = {
	.owner = THIS_MODULE,
	.open = jpegpl_dma_probe_open,
	.unlocked_ioctl = jpegpl_dma_probe_ioctl,
};

static int jpegpl_dma_probe_probe(struct platform_device *pdev)
{
	struct jpegpl_dma_probe_dev *probe;
	u32 buffer_size = JPEGPL_DMA_PROBE_DEFAULT_BUFFER_SIZE;
	int ret;

	probe = devm_kzalloc(&pdev->dev, sizeof(*probe), GFP_KERNEL);
	if (!probe)
		return -ENOMEM;

	probe->dev = &pdev->dev;
	mutex_init(&probe->lock);
	of_property_read_u32(pdev->dev.of_node, "buffer-size", &buffer_size);
	probe->buffer_size = buffer_size;

	probe->tx_chan = dma_request_chan(&pdev->dev, "tx");
	if (IS_ERR(probe->tx_chan)) {
		ret = PTR_ERR(probe->tx_chan);
		dev_err(&pdev->dev, "failed to request tx DMA channel: %d\n", ret);
		return ret;
	}

	probe->rx_chan = dma_request_chan(&pdev->dev, "rx");
	if (IS_ERR(probe->rx_chan)) {
		ret = PTR_ERR(probe->rx_chan);
		dev_err(&pdev->dev, "failed to request rx DMA channel: %d\n", ret);
		goto err_release_tx;
	}

	probe->tx_buf = dmam_alloc_coherent(&pdev->dev, probe->buffer_size,
					    &probe->tx_dma, GFP_KERNEL);
	if (!probe->tx_buf) {
		ret = -ENOMEM;
		goto err_release_rx;
	}
	probe->rx_buf = dmam_alloc_coherent(&pdev->dev, probe->buffer_size,
					    &probe->rx_dma, GFP_KERNEL);
	if (!probe->rx_buf) {
		ret = -ENOMEM;
		goto err_release_rx;
	}

	probe->miscdev.minor = MISC_DYNAMIC_MINOR;
	probe->miscdev.name = "jpegpl_dma_probe";
	probe->miscdev.fops = &jpegpl_dma_probe_fops;
	probe->miscdev.parent = &pdev->dev;

	ret = misc_register(&probe->miscdev);
	if (ret)
		goto err_release_rx;

	platform_set_drvdata(pdev, probe);
	dev_info(&pdev->dev,
		 "JPEGPL_DMA_PROBE_READY dev=/dev/%s buffer_size=%u tx_dma=%pad rx_dma=%pad\n",
		 probe->miscdev.name, probe->buffer_size, &probe->tx_dma,
		 &probe->rx_dma);
	return 0;

err_release_rx:
	dma_release_channel(probe->rx_chan);
err_release_tx:
	dma_release_channel(probe->tx_chan);
	return ret;
}

static int jpegpl_dma_probe_remove(struct platform_device *pdev)
{
	struct jpegpl_dma_probe_dev *probe = platform_get_drvdata(pdev);

	misc_deregister(&probe->miscdev);
	dmaengine_terminate_sync(probe->tx_chan);
	dmaengine_terminate_sync(probe->rx_chan);
	dma_release_channel(probe->rx_chan);
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
	},
};

module_platform_driver(jpegpl_dma_probe_driver);

MODULE_AUTHOR("fpga-hdml");
MODULE_DESCRIPTION("Coherent AXI DMA loopback probe for jpegpldec PL data path");
MODULE_LICENSE("GPL");
