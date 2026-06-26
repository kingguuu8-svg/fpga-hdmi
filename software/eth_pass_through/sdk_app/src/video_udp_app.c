#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "lwip/err.h"
#include "lwip/ip.h"
#include "lwip/ip_addr.h"
#include "lwip/pbuf.h"
#include "lwip/stats.h"
#include "lwip/udp.h"
#include "netif/xadapter.h"
#include "netif/xemacpsif.h"
#include "xemacps_hw.h"
#include "xaxivdma.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xtime_l.h"

#include "video_udp_receiver.h"

#define STAGE1_VDMA_FRAMEBUFFER_BASE 0x01100000u
#define STAGE1_RX_BUFFER_A_BASE 0x01800000u
#define STAGE1_RX_BUFFER_B_BASE 0x01a00000u
#define STAGE1_RGMII_PROBE_BASE 0x1ff00000u
#define STAGE1_HEARTBEAT_PORT 5006u
#define STAGE1_PHY_LOOPBACK_SECONDS 5u
#define STAGE1_ENABLE_PHY_LOOPBACK_PROBE 0u
#define STAGE1_FORCE_PHY_100M 0u
#define RTL8211E_PHY_ADDR 1u
#define PHY_BMCR_REG 0u
#define PHY_ANAR_REG 4u
#define PHY_1000_CTRL_REG 9u
#define PHY_BMCR_LOOPBACK_BIT 0x4000u
#define PHY_BMCR_AUTONEG_ENABLE_BIT 0x1000u
#define PHY_BMCR_RESTART_AUTONEG_BIT 0x0200u
#define RTL8211E_PAGE_SELECT_REG 31u
#define RTL8211E_EXT_PAGE_SELECT 7u
#define RTL8211E_EXT_PAGE_REG 30u
#define RTL8211E_DELAY_EXT_PAGE 0x00a4u
#define RTL8211E_DELAY_REG 28u
#define RTL8211E_TX_DELAY_BIT 0x0002u
#define RTL8211E_RX_DELAY_BIT 0x0004u
#define STAGE1_RX_DRAIN_BUDGET 256u

static uint8_t packet_buf[VIDEO_UDP_HEADER_LEN + VIDEO_UDP_CHUNK_BYTES];
static video_udp_receiver_t receiver;
static XAxiVdma vdma;
static struct udp_pcb *video_pcb;
static struct udp_pcb *heartbeat_pcb;
static uint32_t accepted_packets;
static uint32_t heartbeat_seq;
static uint32_t rx_drain_total;
static uint32_t rx_drain_last;
static int rx_queue_len_last;
static int phy_loopback_active;
static int phy_loopback_done;
static XTime phy_loopback_end;
static u16 phy_loopback_saved_bmcr;
extern struct netif *echo_netif;

static const uint8_t phy_regs[] = {
    0, 1, 2, 3, 4, 5, 9, 10, 17, 18, 19, 26, 27, 31
};

static xemacpsif_s *get_xemacpsif(void);

static int start_vdma_read_channel(void)
{
    XAxiVdma_Config *config;
    XAxiVdma_DmaSetup read_cfg;
    UINTPTR frame_addr[XAXIVDMA_MAX_FRAMESTORE];
    int status;
    int i;

    config = XAxiVdma_LookupConfig(XPAR_AXIVDMA_0_DEVICE_ID);
    if (config == 0) {
        xil_printf("vdma lookup failed id=%u\n\r", XPAR_AXIVDMA_0_DEVICE_ID);
        return -1;
    }

    status = XAxiVdma_CfgInitialize(&vdma, config, config->BaseAddress);
    if (status != XST_SUCCESS) {
        xil_printf("vdma cfg init failed status=%d\n\r", status);
        return -2;
    }

    memset(&read_cfg, 0, sizeof(read_cfg));
    read_cfg.VertSizeInput = VIDEO_UDP_DEFAULT_HEIGHT;
    read_cfg.HoriSizeInput = VIDEO_UDP_DEFAULT_WIDTH * VIDEO_UDP_BYTES_PER_PIXEL;
    read_cfg.Stride = VIDEO_UDP_DEFAULT_WIDTH * VIDEO_UDP_BYTES_PER_PIXEL;
    read_cfg.FrameDelay = 0;
    read_cfg.EnableCircularBuf = 1;
    read_cfg.EnableSync = 1;
    read_cfg.PointNum = 0;
    read_cfg.EnableFrameCounter = 0;
    read_cfg.FixedFrameStoreAddr = 0;

    status = XAxiVdma_DmaConfig(&vdma, XAXIVDMA_READ, &read_cfg);
    if (status != XST_SUCCESS) {
        xil_printf("vdma read config failed status=%d\n\r", status);
        return -3;
    }

    for (i = 0; i < XAXIVDMA_MAX_FRAMESTORE; i++) {
        frame_addr[i] = STAGE1_VDMA_FRAMEBUFFER_BASE;
    }
    status = XAxiVdma_DmaSetBufferAddr(&vdma, XAXIVDMA_READ, frame_addr);
    if (status != XST_SUCCESS) {
        xil_printf("vdma read buffer setup failed status=%d\n\r", status);
        return -4;
    }

    status = XAxiVdma_DmaStart(&vdma, XAXIVDMA_READ);
    if (status != XST_SUCCESS) {
        xil_printf("vdma read start failed status=%d\n\r", status);
        return -5;
    }

    xil_printf("vdma read started id=%u base=0x%08x size=%lu\n\r",
               XPAR_AXIVDMA_0_DEVICE_ID,
               STAGE1_VDMA_FRAMEBUFFER_BASE,
               (unsigned long)VIDEO_UDP_FRAME_BYTES);
    return 0;
}

static void clear_vdma_framebuffer(void)
{
    memset((void *)STAGE1_VDMA_FRAMEBUFFER_BASE, 0, VIDEO_UDP_FRAME_BYTES);
    Xil_DCacheFlushRange((INTPTR)STAGE1_VDMA_FRAMEBUFFER_BASE,
                         VIDEO_UDP_FRAME_BYTES);
}

static void publish_active_frame_to_vdma(void)
{
    const uint8_t *active = video_udp_receiver_active_frame(&receiver);

    if (active == 0) {
        return;
    }

    memcpy((void *)STAGE1_VDMA_FRAMEBUFFER_BASE, active, VIDEO_UDP_FRAME_BYTES);
    Xil_DCacheFlushRange((INTPTR)STAGE1_VDMA_FRAMEBUFFER_BASE,
                         VIDEO_UDP_FRAME_BYTES);
}

static uint32_t gem_reg(uint32_t offset)
{
    return XEmacPs_ReadReg(XPAR_XEMACPS_0_BASEADDR, offset);
}

static void print_rgmii_probe(const char *tag)
{
    volatile uint32_t *probe = (volatile uint32_t *)STAGE1_RGMII_PROBE_BASE;
    uint32_t rx_ctl_rise;
    uint32_t rx_ctl_high;
    uint32_t rxc_edges;
    uint32_t rd_transitions;

    Xil_DCacheInvalidateRange((INTPTR)STAGE1_RGMII_PROBE_BASE, 16u);
    rx_ctl_rise = probe[0];
    rx_ctl_high = probe[1];
    rxc_edges = probe[2];
    rd_transitions = probe[3];

    xil_printf("%s rgmii_probe rise=%lu high=%lu edges=%lu transitions=%lu\n\r",
               tag,
               (unsigned long)rx_ctl_rise,
               (unsigned long)rx_ctl_high,
               (unsigned long)rxc_edges,
               (unsigned long)rd_transitions);
}

static XEmacPs *get_emacps(void)
{
    xemacpsif_s *xemacpsif;

    xemacpsif = get_xemacpsif();
    if (xemacpsif == 0) {
        return 0;
    }
    return &xemacpsif->emacps;
}

static xemacpsif_s *get_xemacpsif(void)
{
    struct xemac_s *xemac;
    xemacpsif_s *xemacpsif;

    if (echo_netif == 0 || echo_netif->state == 0) {
        return 0;
    }

    xemac = (struct xemac_s *)echo_netif->state;
    if (xemac->type != xemac_type_emacps || xemac->state == 0) {
        return 0;
    }

    xemacpsif = (xemacpsif_s *)xemac->state;
    return xemacpsif;
}

static int get_rx_queue_len(void)
{
    xemacpsif_s *xemacpsif = get_xemacpsif();

    if (xemacpsif == 0 || xemacpsif->recv_q == 0) {
        return -1;
    }

    return pq_qlength(xemacpsif->recv_q);
}

static void poll_emacps_rx(void)
{
    struct xemac_s *xemac;

    if (echo_netif == 0 || echo_netif->state == 0) {
        return;
    }

    xemac = (struct xemac_s *)echo_netif->state;
    if (xemac->type != xemac_type_emacps || xemac->state == 0) {
        return;
    }

    emacps_recv_handler((void *)xemac);
}

static void print_gem_stats(const char *tag)
{
    xil_printf(
        "%s tx=%lu txbc=%lu rx=%lu rxbc=%lu rxmc=%lu rxfcs=%lu rxudpck=%lu rxres=%lu rxor=%lu isr=0x%08lx rxsr=0x%08lx\n\r",
        tag,
        (unsigned long)gem_reg(XEMACPS_TXCNT_OFFSET),
        (unsigned long)gem_reg(XEMACPS_TXBCCNT_OFFSET),
        (unsigned long)gem_reg(XEMACPS_RXCNT_OFFSET),
        (unsigned long)gem_reg(XEMACPS_RXBROADCNT_OFFSET),
        (unsigned long)gem_reg(XEMACPS_RXMULTICNT_OFFSET),
        (unsigned long)gem_reg(XEMACPS_RXFCSCNT_OFFSET),
        (unsigned long)gem_reg(XEMACPS_RXUDPCCNT_OFFSET),
        (unsigned long)gem_reg(XEMACPS_RXRESERRCNT_OFFSET),
        (unsigned long)gem_reg(XEMACPS_RXORCNT_OFFSET),
        (unsigned long)gem_reg(XEMACPS_ISR_OFFSET),
        (unsigned long)gem_reg(XEMACPS_RXSR_OFFSET)
    );
}

static void print_phy_regs(uint32_t phy_addr, const char *tag)
{
    unsigned int i;
    u16 value;
    LONG status;
    XEmacPs *emacps = get_emacps();

    if (emacps == 0) {
        xil_printf("%s phy%lu unavailable\n\r",
                   tag, (unsigned long)phy_addr);
        return;
    }

    xil_printf("%s phy%lu", tag, (unsigned long)phy_addr);
    for (i = 0u; i < sizeof(phy_regs); i++) {
        status = XEmacPs_PhyRead(emacps, phy_addr, phy_regs[i], &value);
        if (status == XST_SUCCESS) {
            xil_printf(" r%02u=0x%04x", phy_regs[i], value);
        } else {
            xil_printf(" r%02u=ERR%ld", phy_regs[i], status);
        }
    }
    xil_printf("\n\r");
}

static void print_phy_snapshot(const char *tag)
{
    print_phy_regs(1u, tag);
    print_phy_regs(8u, tag);
}

static LONG rtl8211e_read_delay_reg(XEmacPs *emacps, u16 *value)
{
    LONG status;
    u16 saved_page = 0u;

    status = XEmacPs_PhyRead(emacps, RTL8211E_PHY_ADDR,
                             RTL8211E_PAGE_SELECT_REG, &saved_page);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XEmacPs_PhyWrite(emacps, RTL8211E_PHY_ADDR,
                              RTL8211E_PAGE_SELECT_REG,
                              RTL8211E_EXT_PAGE_SELECT);
    if (status == XST_SUCCESS) {
        status = XEmacPs_PhyWrite(emacps, RTL8211E_PHY_ADDR,
                                  RTL8211E_EXT_PAGE_REG,
                                  RTL8211E_DELAY_EXT_PAGE);
    }
    if (status == XST_SUCCESS) {
        status = XEmacPs_PhyRead(emacps, RTL8211E_PHY_ADDR,
                                 RTL8211E_DELAY_REG, value);
    }
    (void)XEmacPs_PhyWrite(emacps, RTL8211E_PHY_ADDR,
                           RTL8211E_PAGE_SELECT_REG, saved_page);
    return status;
}

static LONG rtl8211e_write_delay_reg(XEmacPs *emacps, u16 value)
{
    LONG status;
    u16 saved_page = 0u;

    status = XEmacPs_PhyRead(emacps, RTL8211E_PHY_ADDR,
                             RTL8211E_PAGE_SELECT_REG, &saved_page);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XEmacPs_PhyWrite(emacps, RTL8211E_PHY_ADDR,
                              RTL8211E_PAGE_SELECT_REG,
                              RTL8211E_EXT_PAGE_SELECT);
    if (status == XST_SUCCESS) {
        status = XEmacPs_PhyWrite(emacps, RTL8211E_PHY_ADDR,
                                  RTL8211E_EXT_PAGE_REG,
                                  RTL8211E_DELAY_EXT_PAGE);
    }
    if (status == XST_SUCCESS) {
        status = XEmacPs_PhyWrite(emacps, RTL8211E_PHY_ADDR,
                                  RTL8211E_DELAY_REG, value);
    }
    (void)XEmacPs_PhyWrite(emacps, RTL8211E_PHY_ADDR,
                           RTL8211E_PAGE_SELECT_REG, saved_page);
    return status;
}

static void configure_rtl8211e_delay(void)
{
    XEmacPs *emacps = get_emacps();
    LONG status;
    u16 before = 0u;
    u16 after = 0u;
    u16 requested;

    if (emacps == 0) {
        xil_printf("rtl8211e-delay unavailable\n\r");
        return;
    }

    status = rtl8211e_read_delay_reg(emacps, &before);
    if (status != XST_SUCCESS) {
        xil_printf("rtl8211e-delay read failed status=%ld\n\r", status);
        return;
    }

    requested = (u16)(before | RTL8211E_RX_DELAY_BIT);
    status = rtl8211e_write_delay_reg(emacps, requested);
    if (status != XST_SUCCESS) {
        xil_printf("rtl8211e-delay write failed status=%ld before=0x%04x requested=0x%04x\n\r",
                   status, before, requested);
        return;
    }

    status = rtl8211e_read_delay_reg(emacps, &after);
    if (status != XST_SUCCESS) {
        xil_printf("rtl8211e-delay reread failed status=%ld before=0x%04x requested=0x%04x\n\r",
                   status, before, requested);
        return;
    }

    xil_printf("rtl8211e-delay before=0x%04x after=0x%04x rx_delay=%u tx_delay=%u forced_rx_delay=1\n\r",
               before,
               after,
               (after & RTL8211E_RX_DELAY_BIT) ? 1u : 0u,
               (after & RTL8211E_TX_DELAY_BIT) ? 1u : 0u);
}

static void configure_rtl8211e_100m(void)
{
    XEmacPs *emacps = get_emacps();
    LONG status;
    volatile uint32_t wait;

    if (!STAGE1_FORCE_PHY_100M) {
        return;
    }
    if (emacps == 0) {
        xil_printf("rtl8211e-100m unavailable\n\r");
        return;
    }

    status = XEmacPs_PhyWrite(emacps, RTL8211E_PHY_ADDR,
                              PHY_1000_CTRL_REG, 0x0000u);
    if (status == XST_SUCCESS) {
        status = XEmacPs_PhyWrite(emacps, RTL8211E_PHY_ADDR,
                                  PHY_ANAR_REG, 0x0d81u);
    }
    if (status == XST_SUCCESS) {
        status = XEmacPs_PhyWrite(
            emacps,
            RTL8211E_PHY_ADDR,
            PHY_BMCR_REG,
            (u16)(PHY_BMCR_AUTONEG_ENABLE_BIT |
                  PHY_BMCR_RESTART_AUTONEG_BIT)
        );
    }
    if (status != XST_SUCCESS) {
        xil_printf("rtl8211e-100m config failed status=%ld\n\r", status);
        return;
    }

    for (wait = 0u; wait < 20000000u; wait++) {
    }
    XEmacPs_SetOperatingSpeed(emacps, 100u);
    xil_printf("rtl8211e-100m forced autoneg advertisement=0x0d81 gig_adv=0x0000 gem_speed=100\n\r");
}

static void start_phy_loopback_probe(void)
{
    XEmacPs *emacps = get_emacps();
    LONG status;
    XTime now;

    if (emacps == 0 || phy_loopback_done || phy_loopback_active) {
        return;
    }

    status = XEmacPs_PhyRead(emacps, RTL8211E_PHY_ADDR,
                             PHY_BMCR_REG, &phy_loopback_saved_bmcr);
    if (status != XST_SUCCESS) {
        xil_printf("phy-loopback read bmcr failed status=%ld\n\r", status);
        phy_loopback_done = 1;
        return;
    }

    status = XEmacPs_PhyWrite(emacps, RTL8211E_PHY_ADDR,
                              PHY_BMCR_REG,
                              (u16)(phy_loopback_saved_bmcr |
                                    PHY_BMCR_LOOPBACK_BIT));
    if (status != XST_SUCCESS) {
        xil_printf("phy-loopback enable failed status=%ld bmcr=0x%04x\n\r",
                   status, phy_loopback_saved_bmcr);
        phy_loopback_done = 1;
        return;
    }

    XTime_GetTime(&now);
    phy_loopback_end = now +
        ((XTime)STAGE1_PHY_LOOPBACK_SECONDS * (XTime)COUNTS_PER_SECOND);
    phy_loopback_active = 1;
    xil_printf("phy-loopback start saved_bmcr=0x%04x test_s=%u\n\r",
               phy_loopback_saved_bmcr, STAGE1_PHY_LOOPBACK_SECONDS);
}

static void service_phy_loopback_probe(void)
{
    XEmacPs *emacps;
    LONG status;
    XTime now;
    u16 current = 0u;

    if (!phy_loopback_active) {
        return;
    }

    XTime_GetTime(&now);
    if ((int64_t)(now - phy_loopback_end) < 0) {
        return;
    }

    emacps = get_emacps();
    print_gem_stats("phy-loopback-end-gem");
    if (emacps != 0) {
        (void)XEmacPs_PhyRead(emacps, RTL8211E_PHY_ADDR,
                              PHY_BMCR_REG, &current);
        status = XEmacPs_PhyWrite(emacps, RTL8211E_PHY_ADDR,
                                  PHY_BMCR_REG,
                                  phy_loopback_saved_bmcr);
        xil_printf("phy-loopback restore status=%ld bmcr_before_restore=0x%04x saved_bmcr=0x%04x\n\r",
                   status, current, phy_loopback_saved_bmcr);
    } else {
        xil_printf("phy-loopback restore skipped emacps unavailable\n\r");
    }

    phy_loopback_active = 0;
    phy_loopback_done = 1;
}

static void send_heartbeat(void)
{
    char msg[96];
    int len;
    struct pbuf *p;
    ip_addr_t dst;
    err_t err;

    if (heartbeat_pcb == 0) {
        return;
    }

    len = snprintf(
        msg,
        sizeof(msg),
        "stage1-heartbeat seq=%lu packets=%lu frames=%lu dropped=%lu",
        (unsigned long)heartbeat_seq++,
        (unsigned long)accepted_packets,
        (unsigned long)receiver.complete_frames,
        (unsigned long)receiver.dropped_packets
    );
    if (len <= 0) {
        return;
    }
    if (len >= (int)sizeof(msg)) {
        len = (int)sizeof(msg) - 1;
    }

    p = pbuf_alloc(PBUF_TRANSPORT, (u16_t)len, PBUF_RAM);
    if (p == 0) {
        xil_printf("heartbeat pbuf alloc failed\n\r");
        return;
    }

    memcpy(p->payload, msg, (size_t)len);
    IP4_ADDR(&dst, 192, 168, 1, 255);
    err = udp_sendto(heartbeat_pcb, p, &dst, STAGE1_HEARTBEAT_PORT);
    pbuf_free(p);

    xil_printf("heartbeat seq=%lu err=%d\n\r",
               (unsigned long)(heartbeat_seq - 1u), err);
    xil_printf("rxdrain total=%lu last=%lu qlen=%d\n\r",
               (unsigned long)rx_drain_total,
               (unsigned long)rx_drain_last,
               rx_queue_len_last);
#if LWIP_STATS
    xil_printf(
        "lwip link(r=%u d=%u m=%u) ip(r=%u d=%u c=%u p=%u) udp(r=%u d=%u c=%u) icmp(r=%u x=%u d=%u)\n\r",
        lwip_stats.link.recv,
        lwip_stats.link.drop,
        lwip_stats.link.memerr,
        lwip_stats.ip.recv,
        lwip_stats.ip.drop,
        lwip_stats.ip.chkerr,
        lwip_stats.ip.proterr,
        lwip_stats.udp.recv,
        lwip_stats.udp.drop,
        lwip_stats.udp.chkerr,
        lwip_stats.icmp.recv,
        lwip_stats.icmp.xmit,
        lwip_stats.icmp.drop
    );
#endif
    print_gem_stats("gem");
    print_rgmii_probe("pl");
    if (((heartbeat_seq - 1u) & 0x0fu) == 0u) {
        print_phy_snapshot("phy-live");
    }
}

static uint32_t drain_rx_queue(void)
{
    uint32_t drained = 0u;

    if (echo_netif == 0) {
        return 0u;
    }

    while (drained < STAGE1_RX_DRAIN_BUDGET) {
        if (xemacif_input(echo_netif) <= 0) {
            break;
        }
        drained++;
    }

    rx_drain_last = drained;
    rx_drain_total += drained;
    rx_queue_len_last = get_rx_queue_len();

    return drained;
}

int transfer_data(void)
{
    static int initialized;
    static XTime next_heartbeat;
    XTime now;

    poll_emacps_rx();
    (void)drain_rx_queue();

    XTime_GetTime(&now);
    if (!initialized) {
        next_heartbeat = now + COUNTS_PER_SECOND;
        initialized = 1;
    }

    if ((int64_t)(now - next_heartbeat) >= 0) {
        send_heartbeat();
        next_heartbeat = now + COUNTS_PER_SECOND;
    }
    service_phy_loopback_probe();

    return 0;
}

void print_app_header(void)
{
    xil_printf("\n\r\n\r----- eth-ps-pl-hdmi pass-through -----\n\r");
    xil_printf("UDP raw RGB888 video port %u, vdma framebuffer 0x%08x\n\r",
               VIDEO_UDP_DEFAULT_PORT, STAGE1_VDMA_FRAMEBUFFER_BASE);
}

static void video_udp_recv(
    void *arg,
    struct udp_pcb *pcb,
    struct pbuf *p,
    const ip_addr_t *addr,
    u16_t port
)
{
    int rc;
    u16_t packet_len;

    (void)arg;
    (void)pcb;
    (void)addr;
    (void)port;

    if (p == 0) {
        return;
    }

    packet_len = p->tot_len;
    if (packet_len > sizeof(packet_buf)) {
        pbuf_free(p);
        receiver.dropped_packets++;
        return;
    }

    pbuf_copy_partial(p, packet_buf, packet_len, 0);
    pbuf_free(p);

    rc = video_udp_receiver_on_packet(&receiver, packet_buf, packet_len);
    if (rc >= 0) {
        accepted_packets++;
        if ((accepted_packets & 0x1ffu) == 0u) {
            xil_printf("video packets=%lu frames=%lu dropped=%lu\n\r",
                       (unsigned long)accepted_packets,
                       (unsigned long)receiver.complete_frames,
                       (unsigned long)receiver.dropped_packets);
        }
    }
    if (rc == 1) {
        publish_active_frame_to_vdma();
        xil_printf("video frame complete frames=%lu packets=%lu dropped=%lu\n\r",
                   (unsigned long)receiver.complete_frames,
                   (unsigned long)accepted_packets,
                   (unsigned long)receiver.dropped_packets);
    } else if (rc < 0 && ((receiver.dropped_packets & 0xffu) == 1u)) {
        xil_printf("video packet rejected rc=%d dropped=%lu\n\r",
                   rc, (unsigned long)receiver.dropped_packets);
    }
}

int start_application(void)
{
    err_t err;
    uint8_t *rx_buffer_a = (uint8_t *)STAGE1_RX_BUFFER_A_BASE;
    uint8_t *rx_buffer_b = (uint8_t *)STAGE1_RX_BUFFER_B_BASE;

    accepted_packets = 0u;
    heartbeat_seq = 0u;
    rx_drain_total = 0u;
    rx_drain_last = 0u;
    rx_queue_len_last = -1;
    phy_loopback_active = 0;
    phy_loopback_done = 0;
    phy_loopback_saved_bmcr = 0u;
    video_udp_receiver_init(&receiver, rx_buffer_a, rx_buffer_b);
    clear_vdma_framebuffer();
    if (start_vdma_read_channel() != 0) {
        xil_printf("VDMA initialization failed\n\r");
        return -4;
    }

    video_pcb = udp_new();
    if (video_pcb == 0) {
        xil_printf("Error creating UDP PCB\n\r");
        return -1;
    }

    err = udp_bind(video_pcb, IP_ADDR_ANY, VIDEO_UDP_DEFAULT_PORT);
    if (err != ERR_OK) {
        xil_printf("Unable to bind UDP port %u: err=%d\n\r",
                   VIDEO_UDP_DEFAULT_PORT, err);
        udp_remove(video_pcb);
        video_pcb = 0;
        return -2;
    }

    udp_recv(video_pcb, video_udp_recv, 0);
    xil_printf("UDP video receiver started @ port %u\n\r",
               VIDEO_UDP_DEFAULT_PORT);

    heartbeat_pcb = udp_new();
    if (heartbeat_pcb == 0) {
        xil_printf("Error creating heartbeat UDP PCB\n\r");
        return -3;
    }
    ip_set_option(heartbeat_pcb, SOF_BROADCAST);

    xil_printf("UDP heartbeat broadcast started @ port %u\n\r",
               STAGE1_HEARTBEAT_PORT);
    configure_rtl8211e_delay();
    configure_rtl8211e_100m();
    print_gem_stats("gem-start");
    print_rgmii_probe("pl-start");
    print_phy_snapshot("phy-start");
    if (STAGE1_ENABLE_PHY_LOOPBACK_PROBE) {
        start_phy_loopback_probe();
    }
    return 0;
}
