set repo_root [file normalize [lindex $argv 0]]
set build_root [file normalize [lindex $argv 1]]

if {$repo_root eq "" || $build_root eq ""} {
    error "Usage: synth_pip_overlay_ooc.tcl <repo-root> <build-root>"
}

set part "xc7z020clg484-1"
set report_root [file join $build_root reports]
file mkdir $build_root
file mkdir $report_root

set_param general.maxThreads 1
create_project pip_overlay_ooc $build_root -part $part -force
set_property target_language Verilog [current_project]

add_files -norecurse [list \
    [file join $repo_root examples eth-ps-pl-hdmi-pass-through rtl axis_pip_overlay_core.v] \
    [file join $repo_root examples eth-ps-pl-hdmi-pass-through rtl axis_pip_frame_ram.v] \
]
set_property top axis_pip_overlay_core [current_fileset]

set ooc_xdc [file join $build_root pip_overlay_ooc.xdc]
set fp [open $ooc_xdc w]
puts $fp {create_clock -name aclk -period 6.667 [get_ports aclk]}
close $fp
add_files -fileset constrs_1 $ooc_xdc
set_property PROCESSING_ORDER LATE [get_files $ooc_xdc]
update_compile_order -fileset sources_1

synth_design -top axis_pip_overlay_core -part $part -mode out_of_context
report_utilization -hierarchical -file [file join $report_root pip_overlay_utilization.rpt]
report_timing_summary -file [file join $report_root pip_overlay_timing.rpt]
report_drc -file [file join $report_root pip_overlay_drc.rpt]
write_checkpoint -force [file join $build_root pip_overlay_ooc.dcp]

set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $drc_errors] != 0} {
    error "PIP overlay OOC DRC failed with [llength $drc_errors] error(s)."
}
set max_paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $max_paths] == 0} {
    error "PIP overlay OOC has no setup timing path."
}
set wns [get_property SLACK $max_paths]
if {$wns < 0} {
    error "PIP overlay OOC timing failed with WNS=$wns ns."
}

puts "PIP_OVERLAY_OOC_OK wns=$wns drc_errors=0 report=[file join $report_root pip_overlay_utilization.rpt]"
