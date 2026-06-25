set output_path [lindex $argv 0]
if {$output_path eq ""} {
    error "Usage: probe-hardware.tcl <output-path>"
}

connect -url tcp:127.0.0.1:3121
set target_text [targets]

set fp [open $output_path w]
puts $fp "xsct_targets: |"
foreach line [split $target_text "\n"] {
    puts $fp "  $line"
    puts $line
}
close $fp
disconnect

if {![regexp -nocase {xc7z020|cortex-a9|arm cortex-a9|apu} $target_text]} {
    error "No Zynq-7000 target detected."
}

