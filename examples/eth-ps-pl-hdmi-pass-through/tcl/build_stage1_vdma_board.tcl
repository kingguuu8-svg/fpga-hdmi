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

proc run_generated_run {build_root run_name} {
    set project_name eth_ps_vdma_hdmi_stage1_board
    set run_dir [file join $build_root "${project_name}.runs" $run_name]
    set run_script [file join $run_dir runme.sh]
    if {![file exists $run_script]} {
        error "Generated run script is missing: $run_script"
    }
    puts "DIRECT_RUN_START run=$run_name script=$run_script"
    exec sh $run_script >@ stdout 2>@ stderr
    if {![file exists [file join $run_dir runme.log]]} {
        error "Generated run did not create runme.log: $run_name"
    }
    set done_files [glob -nocomplain [file join $run_dir ".vivado.end.rst"]]
    set error_files [glob -nocomplain [file join $run_dir ".vivado.*.error.rst"]]
    if {[llength $error_files] != 0 || [llength $done_files] == 0} {
        error "Generated run failed or did not finish: $run_name"
    }
    puts "DIRECT_RUN_OK run=$run_name"
}

proc run_synthesis_direct {build_root} {
    set project_name eth_ps_vdma_hdmi_stage1_board
    set runs_root [file join $build_root "${project_name}.runs"]
    foreach run_dir [lsort [glob -nocomplain -types d [file join $runs_root "*_synth_1"]]] {
        run_generated_run $build_root [file tail $run_dir]
    }
    run_generated_run $build_root synth_1
}

proc run_implementation_direct {build_root} {
    run_generated_run $build_root impl_1
}

create_project eth_ps_vdma_hdmi_stage1_board $build_root -part $part -force
set_property target_language Verilog [current_project]

add_files -norecurse [list \
    [file join $repo_root examples eth-ps-pl-hdmi-pass-through rtl axis_pip_overlay_core.v] \
    [file join $repo_root examples eth-ps-pl-hdmi-pass-through rtl axis_pip_frame_ram.v] \
    [file join $repo_root examples eth-ps-pl-hdmi-pass-through rtl axis_pip_input_broadcast.v] \
    [file join $repo_root examples eth-ps-pl-hdmi-pass-through rtl axis_dma_probe_core.v] \
    [file join $repo_root examples eth-ps-pl-hdmi-pass-through rtl jpeg_rgb_tile_writer.v] \
    [file join $repo_root examples eth-ps-pl-hdmi-pass-through rtl jpeg_pl_decoder_axis.v] \
]
add_files -norecurse [lsort [glob \
    [file join $repo_root third_party ultraembedded-core-jpeg src_v *.v]]]
update_compile_order -fileset sources_1

source [file join $repo_root examples eth-ps-pl-hdmi-pass-through tcl create_ps_emio_vdma_hdmi_bd.tcl]
create_ps_emio_vdma_hdmi_bd $repo_root

set bd_file [get_files ZYNQ_CORE.bd]
generate_target all $bd_file

# Vivado 2018.3 can omit SmartConnect's OOC clock file when an HP-facing
# master changes width. Keep the generated OOC run reproducible.
set axi_smc_ooc_xdc [file join $build_root \
    eth_ps_vdma_hdmi_stage1_board.srcs sources_1 bd ZYNQ_CORE ip \
    ZYNQ_CORE_axi_smc_0 ooc.xdc]
if {![file exists $axi_smc_ooc_xdc]} {
    set ooc_xdc [open $axi_smc_ooc_xdc w]
    puts $ooc_xdc "# Fallback for Vivado 2018.3 SmartConnect OOC generation"
    puts $ooc_xdc "create_clock -name aclk -period 6.667 \[get_ports aclk\]"
    puts $ooc_xdc "create_clock -name aclk1 -period 15.385 \[get_ports aclk1\]"
    close $ooc_xdc
}

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

launch_runs synth_1 -scripts_only -jobs 1
run_synthesis_direct $build_root
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "synth_1 did not complete: [get_property STATUS [get_runs synth_1]]"
}
open_run synth_1
write_checkpoint -force [file join $build_root post_synth.dcp]
report_utilization -file [file join $report_root post_synth_utilization.rpt]
report_drc -file [file join $report_root post_synth_drc.rpt]

set_property strategy Performance_Explore [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -scripts_only -jobs 1
run_implementation_direct $build_root
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "impl_1 did not complete: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1

report_timing_summary -file [file join $report_root timing_summary.rpt]
report_drc -file [file join $report_root post_route_drc.rpt]
report_utilization -file [file join $report_root post_route_utilization.rpt]

set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $drc_errors] != 0} {
    error "Post-route DRC failed with [llength $drc_errors] error(s)."
}

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

puts "STAGE1_VDMA_BOARD_BUILD_OK bitstream=[file join $build_root eth_ps_vdma_hdmi_stage1_board.bit] wns=$wns drc_errors=0"
