# Create the Smart ZYNQ SL PS Ethernet/UART EMIO base design and expose HP0.
#
# This is an integration scaffold for the first-stage pass-through hardware.
# It intentionally starts from the official HelloFPGA EMIO Ethernet Vivado 2018.3
# handoff script already downloaded under tools/downloads, then applies the
# minimum in-repo delta needed for a PL AXI reader to access PS DDR.

proc create_ps_emio_hp0_bd {repo_root} {
    set official_bd_tcl [file join $repo_root tools downloads 10_PS_EMIO_NET_TEST \
        10_PS_EMIO_NET_TEST NET_TEST NET_TEST.srcs sources_1 bd ZYNQ hw_handoff ZYNQ_bd.tcl]

    if {![file exists $official_bd_tcl]} {
        error "Official HelloFPGA EMIO BD Tcl not found: $official_bd_tcl"
    }

    source $official_bd_tcl

    current_bd_design ZYNQ
    set ps7 [get_bd_cells processing_system7_0]

    # The official PS EMIO reference inserts Xilinx gmii_to_rgmii. The
    # connected board now has stronger evidence for the newer HelloFPGA
    # pure-PL RGMII bridge, so expose PS GEM GMII/MDIO directly and let the
    # top-level RTL provide the RGMII bridge.
    if {[llength [get_bd_cells -quiet gmii_to_rgmii_0]] != 0} {
        delete_bd_objs [get_bd_cells gmii_to_rgmii_0]
    }
    foreach intf_port {RGMII_0 MDIO_PHY_0} {
        if {[llength [get_bd_intf_ports -quiet $intf_port]] != 0} {
            delete_bd_objs [get_bd_intf_ports $intf_port]
        }
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
        {FCLK_CLK0              O 1 FCLK_CLK0}
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

    set_property -dict [list \
        CONFIG.PCW_USE_S_AXI_HP0 {1} \
        CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} \
        CONFIG.PCW_S_AXI_HP0_ID_WIDTH {6} \
    ] $ps7

    if {[llength [get_bd_intf_ports -quiet S_AXI_HP0_0]] == 0} {
        make_bd_intf_pins_external [get_bd_intf_pins processing_system7_0/S_AXI_HP0]
    }
    if {[llength [get_bd_ports -quiet S_AXI_HP0_ACLK_0]] == 0} {
        make_bd_pins_external [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK]
    }

    if {[llength [get_bd_addr_segs -quiet S_AXI_HP0_0/SEG_processing_system7_0_HP0_DDR_LOWOCM]] == 0} {
        create_bd_addr_seg -range 0x20000000 -offset 0x00000000 \
            [get_bd_addr_spaces S_AXI_HP0_0] \
            [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] \
            SEG_processing_system7_0_HP0_DDR_LOWOCM
    }

    validate_bd_design
    save_bd_design
}
