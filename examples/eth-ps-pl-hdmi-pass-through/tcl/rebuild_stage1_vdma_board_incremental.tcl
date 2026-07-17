set project_root [file normalize [lindex $argv 0]]
set output_root [file normalize [lindex $argv 1]]

if {$project_root eq "" || $output_root eq ""} {
    error "Usage: rebuild_stage1_vdma_board_incremental.tcl <existing-project-root> <output-root>"
}

set project_name eth_ps_vdma_hdmi_stage1_board
set project_file [file join $project_root "${project_name}.xpr"]
set reports [file join $output_root reports]
file mkdir $output_root
file mkdir $reports
set_param general.maxThreads 1

proc run_generated_run {project_root project_name run_name} {
    set run_dir [file join $project_root "${project_name}.runs" $run_name]
    set run_script [file join $run_dir runme.sh]
    if {![file exists $run_script]} {
        error "Generated run script is missing: $run_script"
    }
    puts "INCREMENTAL_RUN_START run=$run_name script=$run_script"
    exec sh $run_script >@ stdout 2>@ stderr
    set done_file [file join $run_dir .vivado.end.rst]
    set error_files [glob -nocomplain [file join $run_dir ".vivado.*.error.rst"]]
    if {[llength $error_files] != 0 || ![file exists $done_file]} {
        error "Incremental run failed or did not finish: $run_name"
    }
    puts "INCREMENTAL_RUN_OK run=$run_name"
}

if {![file exists $project_file]} {
    error "Existing Vivado project is missing: $project_file"
}
open_project $project_file
update_compile_order -fileset sources_1

set pip_run ZYNQ_CORE_axis_pip_overlay_core_0_0_synth_1
reset_run impl_1
reset_run synth_1
reset_run $pip_run

launch_runs $pip_run -scripts_only -jobs 1
run_generated_run $project_root $project_name $pip_run

launch_runs synth_1 -scripts_only -jobs 1
run_generated_run $project_root $project_name synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Incremental synth_1 did not complete: [get_property STATUS [get_runs synth_1]]"
}

set_property strategy Performance_Explore [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -scripts_only -jobs 1
run_generated_run $project_root $project_name impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Incremental impl_1 did not complete: [get_property STATUS [get_runs impl_1]]"
}

open_run impl_1
report_timing_summary -file [file join $reports timing_summary.rpt]
report_drc -file [file join $reports post_route_drc.rpt]
report_utilization -file [file join $reports post_route_utilization.rpt]

set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $drc_errors] != 0} {
    error "Incremental post-route DRC failed with [llength $drc_errors] error(s)."
}
set max_paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $max_paths] == 0} {
    error "Incremental implementation has no setup timing path."
}
set wns [get_property SLACK $max_paths]
if {$wns < 0} {
    error "Incremental implementation timing failed with WNS=$wns ns."
}

set source_bit [file join $project_root "${project_name}.runs" impl_1 eth_ps_vdma_hdmi_board_top.bit]
set output_bit [file join $output_root eth_ps_vdma_hdmi_stage1_board.bit]
file copy -force $source_bit $output_bit
write_hwdef -force -file [file join $reports eth_ps_vdma_hdmi_stage1_board.hdf]

puts "STAGE1_VDMA_BOARD_INCREMENTAL_BUILD_OK bitstream=$output_bit wns=$wns drc_errors=0"
