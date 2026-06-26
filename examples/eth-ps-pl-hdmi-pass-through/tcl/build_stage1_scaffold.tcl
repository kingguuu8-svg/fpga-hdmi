set repo_root [file normalize [lindex $argv 0]]
set build_root [file normalize [lindex $argv 1]]

if {$repo_root eq "" || $build_root eq ""} {
    error "Usage: build_stage1_scaffold.tcl <repo-root> <build-root>"
}

set part "xc7z020clg484-1"
file mkdir $build_root
set report_root [file join $build_root reports]
file mkdir $report_root

set_param general.maxThreads 1

create_project eth_ps_pl_hdmi_pass_through $build_root -part $part -force
set_property target_language Verilog [current_project]

source [file join $repo_root examples eth-ps-pl-hdmi-pass-through tcl create_ps_emio_hp0_bd.tcl]
create_ps_emio_hp0_bd $repo_root

set bd_file [get_files ZYNQ.bd]
generate_target all $bd_file
make_wrapper -files $bd_file -top
add_files -norecurse [glob -nocomplain [file join $build_root eth_ps_pl_hdmi_pass_through.srcs sources_1 bd ZYNQ hdl *_wrapper.v]]

set rtl_files [concat \
    [glob -nocomplain [file join $repo_root examples eth-ps-pl-hdmi-pass-through rtl *.v]] \
    [glob -nocomplain [file join $repo_root examples video-pip rtl *.v]]]
read_verilog $rtl_files

report_ip_status -file [file join $report_root ip_status.rpt]
write_bd_tcl -force [file join $report_root ZYNQ_hp0_recreated.tcl]
write_hwdef -force -file [file join $report_root ZYNQ_hp0_scaffold.hdf]
if {![file exists [file join $report_root ZYNQ_hp0_scaffold.hdf]]} {
    error "Vivado did not produce ZYNQ_hp0_scaffold.hdf"
}

puts "STAGE1_BD_SCAFFOLD_OK bd=[get_files ZYNQ.bd] hdf=[file join $report_root ZYNQ_hp0_scaffold.hdf]"
