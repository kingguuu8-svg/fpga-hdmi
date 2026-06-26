set repo_root [file normalize [lindex $argv 0]]
set build_root [file normalize [lindex $argv 1]]
set hdf_arg [lindex $argv 2]

if {$repo_root eq "" || $build_root eq ""} {
    error "Usage: build_sdk_app.tcl <repo-root> <build-root> ?hdf?"
}

if {$hdf_arg eq ""} {
    set hdf [file join $repo_root build eth-ps-pl-hdmi-pass-through vdma-board reports eth_ps_vdma_hdmi_stage1_board.hdf]
} else {
    set hdf [file normalize $hdf_arg]
}
if {![file exists $hdf]} {
    error "Stage1 HDF not found: $hdf"
}

file mkdir $build_root
set workspace [file join $build_root sdk_workspace]
file delete -force $workspace
setws $workspace

createhw -name stage1_hw -hwspec $hdf
createbsp -name stage1_bsp -hwproject stage1_hw -proc ps7_cortexa9_0 -os standalone
setlib -bsp stage1_bsp -lib lwip202
configbsp -bsp stage1_bsp n_rx_descriptors 128
configbsp -bsp stage1_bsp n_tx_descriptors 128
configbsp -bsp stage1_bsp mem_size 1048576
configbsp -bsp stage1_bsp memp_n_pbuf 64
configbsp -bsp stage1_bsp pbuf_pool_size 1024
configbsp -bsp stage1_bsp pbuf_pool_bufsize 1700
regenbsp -bsp stage1_bsp

createapp \
    -name eth_pass_through \
    -hwproject stage1_hw \
    -bsp stage1_bsp \
    -proc ps7_cortexa9_0 \
    -os standalone \
    -app {lwIP Echo Server}

set app_src [file join $build_root sdk_workspace eth_pass_through src]
file copy -force \
    [file join $repo_root software eth_pass_through sdk_app src video_udp_app.c] \
    [file join $app_src echo.c]
foreach src_file {video_udp_protocol.c video_udp_protocol.h video_udp_receiver.c video_udp_receiver.h} {
    file copy -force \
        [file join $repo_root software eth_pass_through src $src_file] \
        [file join $app_src $src_file]
}

projects -build -type bsp -name stage1_bsp
projects -build -type app -name eth_pass_through

set elf [file join $build_root sdk_workspace eth_pass_through Debug eth_pass_through.elf]
if {![file exists $elf]} {
    error "Expected SDK ELF was not produced: $elf"
}

file copy -force $elf [file join $build_root eth_pass_through.elf]
puts "STAGE1_SDK_APP_BUILD_OK elf=[file join $build_root eth_pass_through.elf]"
