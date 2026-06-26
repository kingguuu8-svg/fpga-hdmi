set bitstream [file normalize [lindex $argv 0]]
set elf [file normalize [lindex $argv 1]]
set ps7_init_tcl [file normalize [lindex $argv 2]]
set marker [lindex $argv 3]

if {$marker eq ""} {
    set marker "PROGRAM_BIT_ELF_OK"
}

if {$bitstream eq "" || ![file exists $bitstream] ||
    $elf eq "" || ![file exists $elf] ||
    $ps7_init_tcl eq "" || ![file exists $ps7_init_tcl]} {
    error "Usage: program_bit_elf.tcl <bitstream> <elf> <ps7-init-tcl> ?marker?"
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

puts "$marker bitstream=$bitstream elf=$elf"
disconnect
