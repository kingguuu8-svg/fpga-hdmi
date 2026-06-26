set bitstream [file normalize [lindex $argv 0]]
set elf [file normalize [lindex $argv 1]]
set ps7_init_tcl [file normalize [lindex $argv 2]]

if {$bitstream eq "" || ![file exists $bitstream] ||
    $elf eq "" || ![file exists $elf] ||
    $ps7_init_tcl eq "" || ![file exists $ps7_init_tcl]} {
    error "Usage: program_stage1_run.tcl <bitstream> <elf> <ps7-init-tcl>"
}

connect -url tcp:127.0.0.1:3121
set target_text [targets]
if {![regexp -nocase {xc7z020} $target_text] ||
    ![regexp -nocase {cortex-a9|apu} $target_text]} {
    disconnect
    error "No complete Zynq-7000 target detected by XSCT."
}

targets -set -nocase -filter {name =~ "*xc7z020*"}
fpga -file $bitstream

targets -set -nocase -filter {name =~ "ARM Cortex-A9 MPCore #0"}
rst -processor
source $ps7_init_tcl
ps7_init
ps7_post_config
dow $elf
con

puts "STAGE1_PROGRAM_RUN_OK bitstream=$bitstream elf=$elf"
disconnect
