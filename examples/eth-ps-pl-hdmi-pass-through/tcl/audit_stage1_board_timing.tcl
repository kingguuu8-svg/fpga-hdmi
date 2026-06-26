set build_root [file normalize [lindex $argv 0]]

if {$build_root eq ""} {
    error "Usage: audit_stage1_board_timing.tcl <build-root>"
}

set project_file [file join $build_root eth_ps_pl_hdmi_stage1_board.xpr]
set report_root [file join $build_root reports]

if {![file exists $project_file]} {
    error "Stage1 board project not found: $project_file"
}

file mkdir $report_root
open_project $project_file
open_run impl_1

check_timing -verbose \
    -file [file join $report_root check_timing_verbose.rpt]
report_clock_interaction \
    -file [file join $report_root clock_interaction.rpt]

puts "STAGE1_TIMING_AUDIT_OK report_root=$report_root"
