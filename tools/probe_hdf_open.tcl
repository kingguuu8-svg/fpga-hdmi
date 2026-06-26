set hdf [file normalize [lindex $argv 0]]
if {$hdf eq "" || ![file exists $hdf]} {
    error "Usage: probe_hdf_open.tcl <hdf>"
}

hsi::open_hw_design $hdf
puts "HDF_OPEN_OK $hdf"
puts "processors=[hsi::get_cells -hier -filter {IP_TYPE==PROCESSOR}]"
puts "memories=[hsi::get_mem_ranges]"
hsi::close_hw_design [hsi::current_hw_design]
