set repo_root [file normalize [lindex $argv 0]]
set build_root [file normalize [lindex $argv 1]]

if {$repo_root eq "" || $build_root eq ""} {
    error "Usage: build_stage1_vdma_board.tcl <repo-root> <build-root>"
}

set part "xc7z020clg484-1"
file mkdir $build_root
set report_root [file join $build_root reports]
file mkdir $report_root

set_param general.maxThreads 1

create_project eth_ps_vdma_hdmi_stage1_board $build_root -part $part -force
set_property target_language Verilog [current_project]

add_files -norecurse [list \
    [file join $repo_root examples eth-ps-pl-hdmi-pass-through rtl axis_pip_overlay_core.v] \
]
update_compile_order -fileset sources_1

source [file join $repo_root examples eth-ps-pl-hdmi-pass-through tcl create_ps_emio_vdma_hdmi_bd.tcl]
create_ps_emio_vdma_hdmi_bd $repo_root

set bd_file [get_files ZYNQ_CORE.bd]
generate_target all $bd_file
make_wrapper -files $bd_file -top
add_files -norecurse [glob -nocomplain [file join $build_root eth_ps_vdma_hdmi_stage1_board.srcs sources_1 bd ZYNQ_CORE hdl *_wrapper.v]]

add_files -norecurse [list \
    [file join $repo_root examples eth-ps-pl-hdmi-pass-through rtl rgmii_gmii_bridge.v] \
    [file join $repo_root examples eth-ps-pl-hdmi-pass-through rtl eth_ps_vdma_hdmi_board_top.v] \
]

set stage1_xdc [file join $repo_root examples eth-ps-pl-hdmi-pass-through xdc stage1_vdma_board.xdc]
add_files -fileset constrs_1 $stage1_xdc
set_property PROCESSING_ORDER LATE [get_files $stage1_xdc]
set_property top eth_ps_vdma_hdmi_board_top [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 1
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "synth_1 did not complete: [get_property STATUS [get_runs synth_1]]"
}
open_run synth_1
write_checkpoint -force [file join $build_root post_synth.dcp]
report_utilization -file [file join $report_root post_synth_utilization.rpt]
report_drc -file [file join $report_root post_synth_drc.rpt]

launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "impl_1 did not complete: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1

report_timing_summary -file [file join $report_root timing_summary.rpt]
report_drc -file [file join $report_root post_route_drc.rpt]
report_utilization -file [file join $report_root post_route_utilization.rpt]

set max_timing_paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $max_timing_paths] > 0} {
    set wns [get_property SLACK $max_timing_paths]
    if {$wns < 0} {
        error "Timing failed with WNS=$wns ns."
    }
} else {
    set wns "NA"
    puts "TIMING_NOTE no max timing paths found for stage1 VDMA board."
}

write_hwdef -force -file [file join $report_root eth_ps_vdma_hdmi_stage1_board.hdf]
file copy -force \
    [file join $build_root eth_ps_vdma_hdmi_stage1_board.runs impl_1 eth_ps_vdma_hdmi_board_top.bit] \
    [file join $build_root eth_ps_vdma_hdmi_stage1_board.bit]

puts "STAGE1_VDMA_BOARD_BUILD_OK bitstream=[file join $build_root eth_ps_vdma_hdmi_stage1_board.bit] wns=$wns"
