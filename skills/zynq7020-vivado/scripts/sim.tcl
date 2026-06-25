set repo_root [file normalize [lindex $argv 0]]
set example [lindex $argv 1]
set sim_root [file normalize [lindex $argv 2]]

if {$repo_root eq "" || $example eq "" || $sim_root eq ""} {
    error "Usage: sim.tcl <repo-root> <example> <sim-root>"
}
if {$example ne "video-pip"} {
    error "Unsupported simulation example '$example'."
}

file mkdir $sim_root
cd $sim_root

set vivado_bin [file dirname [file normalize [info nameofexecutable]]]
set xvlog [file join $vivado_bin xvlog]
set xelab [file join $vivado_bin xelab]
set xsim [file join $vivado_bin xsim]

set rtl_files [lsort [glob -nocomplain [file join $repo_root examples $example rtl *.v]]]
set sim_files [lsort [glob -nocomplain [file join $repo_root examples $example sim *.v]]]
if {[llength $rtl_files] == 0 || [llength $sim_files] == 0} {
    error "Simulation files are missing for '$example'."
}

exec $xvlog -nolog {*}$rtl_files {*}$sim_files >@ stdout 2>@ stderr
exec $xelab -nolog tb_video_pip_core -snapshot tb_video_pip_core >@ stdout 2>@ stderr
set sim_log [file join $sim_root xsim-run.log]
exec $xsim -nolog tb_video_pip_core -runall > $sim_log 2>@ stderr
set sim_text [read [open $sim_log r]]
puts $sim_text
if {[regexp {FAIL} $sim_text] || ![regexp {SIM_OK} $sim_text]} {
    error "Simulation failed; see $sim_log"
}
puts "SIM_FLOW_OK example=$example sim_root=$sim_root"
