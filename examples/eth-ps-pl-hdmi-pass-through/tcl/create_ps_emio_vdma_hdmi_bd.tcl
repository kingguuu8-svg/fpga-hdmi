# Create the stage-1 PS Ethernet/UART EMIO + VDMA HDMI design.
#
# The base is the official HelloFPGA VDMA HDMI design that has passed on the
# connected board. This script adds PS ENET0/UART0 EMIO and exposes GMII/MDIO
# for the existing top-level RGMII bridge.

proc create_ps_emio_vdma_hdmi_bd {repo_root} {
    set official_root [file join $repo_root tools downloads 19_VDMA_HDMI_TEST \
        19_VDMA_HDMI_TEST VDMA_HDMI_TEST]
    set official_bd_tcl [file join $official_root VDMA_HDMI_TEST.srcs sources_1 \
        bd ZYNQ_CORE hw_handoff ZYNQ_CORE_bd.tcl]
    set rgb2dvi_repo [file join $official_root vivado-library-master]

    if {![file exists $official_bd_tcl]} {
        error "Official HelloFPGA VDMA BD Tcl not found: $official_bd_tcl"
    }
    if {![file exists [file join $rgb2dvi_repo ip rgb2dvi component.xml]]} {
        error "Official rgb2dvi IP repository not found: $rgb2dvi_repo"
    }

    set_property ip_repo_paths $rgb2dvi_repo [current_project]
    update_ip_catalog

    source $official_bd_tcl

    current_bd_design ZYNQ_CORE
    set ps7 [get_bd_cells processing_system7_0]

    # Keep the VDMA clocks and DDR timing from the official passing design.
    # Add only the peripherals needed for the first-stage Ethernet/UART path.
    set_property -dict [list \
        CONFIG.PCW_ENET0_ENET0_IO {EMIO} \
        CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
        CONFIG.PCW_ENET0_GRP_MDIO_IO {EMIO} \
        CONFIG.PCW_ENET0_PERIPHERAL_CLKSRC {External} \
        CONFIG.PCW_ENET0_PERIPHERAL_DIVISOR0 {1} \
        CONFIG.PCW_ENET0_PERIPHERAL_DIVISOR1 {1} \
        CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
        CONFIG.PCW_ENET0_RESET_ENABLE {0} \
        CONFIG.PCW_EN_EMIO_ENET0 {1} \
        CONFIG.PCW_EN_ENET0 {1} \
        CONFIG.PCW_EN_EMIO_UART0 {1} \
        CONFIG.PCW_EN_UART0 {1} \
        CONFIG.PCW_IRQ_F2P_INTR {1} \
        CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
        CONFIG.PCW_UART0_BAUD_RATE {115200} \
        CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
        CONFIG.PCW_UART0_UART0_IO {EMIO} \
    ] $ps7

    if {[llength [get_bd_intf_ports -quiet UART_0_0]] == 0} {
        create_bd_intf_port -mode Master -vlnv xilinx.com:interface:uart_rtl:1.0 UART_0_0
        connect_bd_intf_net [get_bd_intf_ports UART_0_0] [get_bd_intf_pins processing_system7_0/UART_0]
    }

    foreach port_def {
        {GMII_ETHERNET_0_col    I 1 ENET0_GMII_COL}
        {GMII_ETHERNET_0_crs    I 1 ENET0_GMII_CRS}
        {GMII_ETHERNET_0_rx_clk I 1 ENET0_GMII_RX_CLK}
        {GMII_ETHERNET_0_rx_dv  I 1 ENET0_GMII_RX_DV}
        {GMII_ETHERNET_0_rx_er  I 1 ENET0_GMII_RX_ER}
        {GMII_ETHERNET_0_rxd    I 8 ENET0_GMII_RXD}
        {GMII_ETHERNET_0_tx_clk I 1 ENET0_GMII_TX_CLK}
        {GMII_ETHERNET_0_tx_en  O 1 ENET0_GMII_TX_EN}
        {GMII_ETHERNET_0_tx_er  O 1 ENET0_GMII_TX_ER}
        {GMII_ETHERNET_0_txd    O 8 ENET0_GMII_TXD}
        {MDIO_ETHERNET_0_mdc    O 1 ENET0_MDIO_MDC}
        {MDIO_ETHERNET_0_mdio_i I 1 ENET0_MDIO_I}
        {MDIO_ETHERNET_0_mdio_o O 1 ENET0_MDIO_O}
        {MDIO_ETHERNET_0_mdio_t O 1 ENET0_MDIO_T}
    } {
        lassign $port_def port_name port_dir port_width ps_pin
        if {[llength [get_bd_ports -quiet $port_name]] == 0} {
            if {$port_width == 1} {
                create_bd_port -dir $port_dir $port_name
            } else {
                create_bd_port -dir $port_dir -from [expr {$port_width - 1}] -to 0 $port_name
            }
        }
        connect_bd_net [get_bd_ports $port_name] [get_bd_pins processing_system7_0/$ps_pin]
    }

    # The RGMII IDELAYCTRL requires a 200 MHz reference. Reuse the already
    # validated VDMA HDMI 200 MHz serial clock rather than changing PS FCLKs.
    if {[llength [get_bd_ports -quiet IDELAY_REF_CLK]] == 0} {
        create_bd_port -dir O IDELAY_REF_CLK
        connect_bd_net [get_bd_ports IDELAY_REF_CLK] [get_bd_pins clk_wiz_0/clk_out2]
    }

    # PetaLinux device-tree generation requires the AXI VDMA interrupt outputs
    # to terminate at the PS interrupt controller. The official HDMI-only
    # project can run without these connections, but Linux cannot describe the
    # VDMA node correctly when the interrupt pins are left floating.
    if {[llength [get_bd_cells -quiet vdma_irq_concat]] == 0} {
        create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 vdma_irq_concat
        set_property -dict [list CONFIG.NUM_PORTS {16}] [get_bd_cells vdma_irq_concat]
    }
    if {[llength [get_bd_cells -quiet vdma_irq_zero]] == 0} {
        create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 vdma_irq_zero
        set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] \
            [get_bd_cells vdma_irq_zero]
    }

    if {[llength [get_bd_nets -quiet vdma_mm2s_irq]] == 0} {
        connect_bd_net -net vdma_mm2s_irq \
            [get_bd_pins axi_vdma_0/mm2s_introut] \
            [get_bd_pins vdma_irq_concat/In0]
    }
    if {[llength [get_bd_nets -quiet vdma_s2mm_irq]] == 0} {
        connect_bd_net -net vdma_s2mm_irq \
            [get_bd_pins axi_vdma_0/s2mm_introut] \
            [get_bd_pins vdma_irq_concat/In1]
    }
    if {[llength [get_bd_nets -quiet vdma_irq_zero_net]] == 0} {
        set zero_sinks {}
        for {set irq_idx 2} {$irq_idx < 16} {incr irq_idx} {
            lappend zero_sinks [get_bd_pins vdma_irq_concat/In$irq_idx]
        }
        connect_bd_net -net vdma_irq_zero_net \
            [get_bd_pins vdma_irq_zero/dout] \
            {*}$zero_sinks
    }
    if {[llength [get_bd_nets -quiet ps_irq_f2p]] == 0} {
        if {[llength [get_bd_pins -quiet processing_system7_0/IRQ_F2P]] == 0} {
            error "processing_system7_0/IRQ_F2P is not exposed after enabling PS fabric interrupts"
        }
        connect_bd_net -net ps_irq_f2p \
            [get_bd_pins vdma_irq_concat/dout] \
            [get_bd_pins processing_system7_0/IRQ_F2P]
    }

    validate_bd_design
    save_bd_design
}
