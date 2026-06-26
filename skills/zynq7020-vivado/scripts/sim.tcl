set repo_root [file normalize [lindex $argv 0]]
set example [lindex $argv 1]
set sim_root [file normalize [lindex $argv 2]]

if {$repo_root eq "" || $example eq "" || $sim_root eq ""} {
    error "Usage: sim.tcl <repo-root> <example> <sim-root>"
}
file mkdir $sim_root
cd $sim_root

set vivado_bin [file dirname [file normalize [info nameofexecutable]]]
set xvlog [file join $vivado_bin xvlog]
set xelab [file join $vivado_bin xelab]
set xsim [file join $vivado_bin xsim]

if {$example eq "video-pip"} {
    set rtl_files [lsort [glob -nocomplain [file join $repo_root examples $example rtl *.v]]]
    set sim_files [lsort [glob -nocomplain [file join $repo_root examples $example sim *.v]]]
    set sim_top tb_video_pip_core
    set required_marker SIM_OK
} elseif {$example eq "eth-ps-pl-hdmi-pass-through"} {
    set rtl_files [list \
        [file join $repo_root examples $example rtl axi_framebuffer_line_reader.v]]
    set sim_files [list \
        [file join $repo_root examples $example sim tb_axi_framebuffer_line_reader.v]]
    set sim_top tb_axi_framebuffer_line_reader
    set required_marker AXI_FRAMEBUFFER_LINE_READER_OK
} else {
    error "Unsupported simulation example '$example'."
}

foreach required_file [concat $rtl_files $sim_files] {
    if {![file exists $required_file]} {
        error "Simulation file is missing: $required_file"
    }
}

exec $xvlog -nolog {*}$rtl_files {*}$sim_files >@ stdout 2>@ stderr
exec $xelab -nolog $sim_top -snapshot $sim_top >@ stdout 2>@ stderr
set sim_log [file join $sim_root xsim-run.log]
exec $xsim -nolog $sim_top -runall > $sim_log 2>@ stderr
set sim_text [read [open $sim_log r]]
puts $sim_text
if {[regexp {FAIL} $sim_text] || ![regexp $required_marker $sim_text] || ![regexp {SIM_OK} $sim_text]} {
    error "Simulation failed; see $sim_log"
}
puts "SIM_FLOW_OK example=$example sim_root=$sim_root"
