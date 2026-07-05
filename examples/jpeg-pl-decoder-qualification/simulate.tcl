set repo_root [file normalize [lindex $argv 0]]
set sim_root [file normalize [lindex $argv 1]]
set word_count [lindex $argv 2]

if {$repo_root eq "" || $sim_root eq "" || $word_count eq ""} {
    error "Usage: simulate.tcl <repo-root> <sim-root> <word-count>"
}

file mkdir $sim_root
cd $sim_root
set vivado_bin [file dirname [file normalize [info nameofexecutable]]]
set xvlog [file join $vivado_bin xvlog]
set xelab [file join $vivado_bin xelab]
set xsim [file join $vivado_bin xsim]
set rtl_files [lsort [glob [file join $repo_root third_party ultraembedded-core-jpeg src_v *.v]]]
set testbench [file join $repo_root examples jpeg-pl-decoder-qualification tb_jpeg_core_720p.v]

exec $xvlog -nolog {*}$rtl_files $testbench > xvlog.log 2>@ stderr
exec $xelab -nolog --timescale 1ns/1ps --override_timeunit \
    --override_timeprecision tb_jpeg_core_720p -snapshot tb_jpeg_core_720p \
    > xelab.log 2>@ stderr
exec $xsim -nolog tb_jpeg_core_720p -testplusarg WORD_COUNT=$word_count -runall > xsim.log 2>@ stderr

set handle [open xsim.log r]
set text [read $handle]
close $handle
puts $text
if {[regexp {JPEG_PL_RTL_SIM_FAILED} $text] || ![regexp {JPEG_PL_RTL_SIM_OK} $text]} {
    error "JPEG RTL simulation failed; see [file join $sim_root xsim.log]"
}
if {![file exists [file join $sim_root rtl_pixels.hex]]} {
    error "JPEG RTL simulation produced no pixel dump"
}
puts "JPEG_PL_RTL_SIM_FLOW_OK sim_root=$sim_root"
