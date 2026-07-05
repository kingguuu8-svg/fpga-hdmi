set repo_root [file normalize [lindex $argv 0]]
set build_root [file normalize [lindex $argv 1]]

if {$repo_root eq "" || $build_root eq ""} {
    error "Usage: implement.tcl <repo-root> <build-root>"
}

file mkdir $build_root
set report_root [file join $build_root reports]
file mkdir $report_root
set rtl_files [lsort [glob [file join $repo_root third_party ultraembedded-core-jpeg src_v *.v]]]

read_verilog $rtl_files
synth_design -top jpeg_core -part xc7z020clg484-1 -mode out_of_context \
    -generic {SUPPORT_WRITABLE_DHT=0}
create_clock -name jpeg_clk -period 15.000 [get_ports clk_i]
write_checkpoint -force [file join $build_root post_synth.dcp]
report_utilization -file [file join $report_root post_synth_utilization.rpt]

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $build_root post_route.dcp]
report_utilization -file [file join $report_root post_route_utilization.rpt]
report_timing_summary -delay_type max -max_paths 10 \
    -file [file join $report_root post_route_timing_summary.rpt]
report_drc -file [file join $report_root post_route_drc.rpt]

set paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $paths] == 0} {
    error "No implemented timing path was found"
}
set wns [get_property SLACK [lindex $paths 0]]
set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
set cells [get_cells -hierarchical]

set handle [open [file join $report_root qualification_summary.txt] w]
puts $handle "part=xc7z020clg484-1"
puts $handle "clock_period_ns=15.000"
puts $handle "support_writable_dht=0"
puts $handle "wns_ns=$wns"
puts $handle "drc_error_count=[llength $drc_errors]"
puts $handle "cell_count=[llength $cells]"
close $handle

if {$wns < 0.0} {
    error "JPEG core timing failed at 66.667 MHz: WNS=$wns"
}
if {[llength $drc_errors] != 0} {
    error "JPEG core DRC failed with [llength $drc_errors] errors"
}
puts "JPEG_PL_IMPLEMENT_OK part=xc7z020clg484-1 period_ns=15.000 wns_ns=$wns drc_errors=0"
