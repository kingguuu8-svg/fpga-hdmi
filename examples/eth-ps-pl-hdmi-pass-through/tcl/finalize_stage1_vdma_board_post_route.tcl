set build_root [file normalize [lindex $argv 0]]

if {$build_root eq ""} {
    error "Usage: finalize_stage1_vdma_board_post_route.tcl <build-root>"
}

set project_name eth_ps_vdma_hdmi_stage1_board
set report_root [file join $build_root reports]
set project_file [file join $build_root "${project_name}.xpr"]
set run_bitstream [file join $build_root "${project_name}.runs" impl_1 eth_ps_vdma_hdmi_board_top.bit]
set final_bitstream [file join $build_root "${project_name}.bit"]

if {![file exists $project_file]} {
    error "Vivado project is missing: $project_file"
}

open_project $project_file
open_run impl_1

set before_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $before_path] == 0} {
    error "No maximum-delay timing path exists before post-route optimization."
}
set before_wns [get_property SLACK [lindex $before_path 0]]
puts "POST_ROUTE_PHYSOPT_START before_wns=$before_wns"

phys_opt_design -directive AggressiveExplore
route_design -preserve

file mkdir $report_root
report_timing_summary -file [file join $report_root timing_summary.rpt]
report_drc -file [file join $report_root post_route_drc.rpt]
report_utilization -file [file join $report_root post_route_utilization.rpt]

set after_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $after_path] == 0} {
    error "No maximum-delay timing path exists after post-route optimization."
}
set after_wns [get_property SLACK [lindex $after_path 0]]
if {$after_wns < 0} {
    error "Timing failed after post-route optimization: WNS=$after_wns ns."
}

set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $drc_errors] != 0} {
    error "Post-route DRC failed with [llength $drc_errors] error(s)."
}

write_checkpoint -force [file join $build_root post_route_physopt.dcp]
write_bitstream -force $run_bitstream
write_hwdef -force -file [file join $report_root "${project_name}.hdf"]
file copy -force $run_bitstream $final_bitstream

puts "POST_ROUTE_PHYSOPT_OK bitstream=$final_bitstream before_wns=$before_wns after_wns=$after_wns drc_errors=0"
