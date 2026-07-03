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
    set sim_jobs [list [list \
        tb_video_pip_core \
        SIM_OK \
        [lsort [glob -nocomplain [file join $repo_root examples $example rtl *.v]]] \
        [lsort [glob -nocomplain [file join $repo_root examples $example sim *.v]]] \
    ]]
} elseif {$example eq "eth-ps-pl-hdmi-pass-through"} {
    set sim_jobs [list \
        [list \
            tb_axi_framebuffer_line_reader \
            AXI_FRAMEBUFFER_LINE_READER_OK \
            [list [file join $repo_root examples $example rtl axi_framebuffer_line_reader.v]] \
            [list [file join $repo_root examples $example sim tb_axi_framebuffer_line_reader.v]] \
        ] \
        [list \
            tb_axis_pip_overlay_core \
            PL_DUAL_VDMA_PIP_CORE_SIM_OK \
            [list [file join $repo_root examples $example rtl axis_pip_overlay_core.v]] \
            [list [file join $repo_root examples $example sim tb_axis_pip_overlay_core.v]] \
        ] \
    ]
} else {
    error "Unsupported simulation example '$example'."
}

foreach sim_job $sim_jobs {
    lassign $sim_job sim_top required_marker rtl_files sim_files

    foreach required_file [concat $rtl_files $sim_files] {
        if {![file exists $required_file]} {
            error "Simulation file is missing: $required_file"
        }
    }

    exec $xvlog -nolog {*}$rtl_files {*}$sim_files >@ stdout 2>@ stderr
    exec $xelab -nolog $sim_top -snapshot $sim_top >@ stdout 2>@ stderr
    set sim_log [file join $sim_root "$sim_top-xsim-run.log"]
    exec $xsim -nolog $sim_top -runall > $sim_log 2>@ stderr
    set fp [open $sim_log r]
    set sim_text [read $fp]
    close $fp
    puts $sim_text
    if {[regexp {FAIL} $sim_text] || ![regexp $required_marker $sim_text] || ![regexp {SIM_OK} $sim_text]} {
        error "Simulation failed for $sim_top; see $sim_log"
    }
    puts "SIM_JOB_OK example=$example top=$sim_top marker=$required_marker"
}
puts "SIM_FLOW_OK example=$example sim_root=$sim_root"
