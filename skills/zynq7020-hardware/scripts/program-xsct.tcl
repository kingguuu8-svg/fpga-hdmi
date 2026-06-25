set bitstream [file normalize [lindex $argv 0]]
if {$bitstream eq "" || ![file exists $bitstream]} {
    error "Usage: program-xsct.tcl <bitstream>"
}

connect -url tcp:127.0.0.1:3121
set target_text [targets]
if {![regexp -nocase {xc7z020|cortex-a9|arm cortex-a9|apu} $target_text]} {
    disconnect
    error "No Zynq-7000 target detected by XSCT."
}
fpga -file $bitstream
puts "PROGRAM_OK backend=xsct bitstream=$bitstream"
disconnect

