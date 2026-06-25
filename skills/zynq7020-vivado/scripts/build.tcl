set repo_root [file normalize [lindex $argv 0]]
set profile_path [file normalize [lindex $argv 1]]
set example [lindex $argv 2]
set build_root [file normalize [lindex $argv 3]]

if {$repo_root eq "" || $profile_path eq "" || $example eq "" || $build_root eq ""} {
    error "Usage: build.tcl <repo-root> <board-profile> <example> <build-root>"
}

source $profile_path

foreach required {
    board_name part led_port led_pins led_iostandard led_active_low
} {
    if {![info exists $required]} {
        error "Board profile is missing '$required'."
    }
}
if {![info exists clock_required]} {
    set clock_required 1
}
if {![info exists led_slew]} {
    set led_slew ""
}
if {![info exists led_drive]} {
    set led_drive ""
}
if {![string match "xc7z020*" [string tolower $part]]} {
    error "Board part must be XC7Z020, got '$part'."
}
if {[llength $led_pins] == 0} {
    error "Board profile must define at least one LED pin."
}
if {$clock_required} {
    foreach required {clock_port clock_pin clock_period_ns clock_iostandard} {
        if {![info exists $required]} {
            error "Clocked build requires board profile field '$required'."
        }
    }
    if {$clock_pin eq "" || $clock_period_ns <= 0} {
        error "Clocked build requires a non-empty clock pin and positive period."
    }
}

set uses_led 1
set uses_key 0
set uses_hdmi 0

if {$example eq "led-chaser"} {
    set uses_clock 1
    if {!$clock_required} {
        error "Example 'led-chaser' requires a verified board clock."
    }
    set top led_chaser
    set rtl [file join $repo_root examples $example rtl led_chaser.v]
    set synth_generics [list \
        CLK_HZ=[expr {round(1000000000.0 / $clock_period_ns)}] \
        LED_COUNT=[llength $led_pins] \
        ACTIVE_LOW=$led_active_low]
} elseif {$example eq "led-static"} {
    set uses_clock 0
    set top led_static
    set rtl [file join $repo_root examples $example rtl led_static.v]
    set synth_generics [list \
        LED_COUNT=[llength $led_pins] \
        ACTIVE_LOW=$led_active_low]
} elseif {$example eq "video-pip"} {
    set uses_clock 1
    set uses_led 1
    set uses_key 0
    set uses_hdmi 1
    if {!$clock_required} {
        error "Example 'video-pip' requires a verified board clock."
    }
    set top video_pip_top
    set rtl [lsort [glob -nocomplain [file join $repo_root examples $example rtl *.v]]]
    set synth_generics {}
} else {
    error "Unsupported example '$example'."
}

if {$uses_clock} {
    foreach required {clock_port clock_pin clock_period_ns clock_iostandard} {
        if {![info exists $required]} {
            error "Clocked build requires board profile field '$required'."
        }
    }
    if {$clock_pin eq "" || $clock_period_ns <= 0} {
        error "Clocked build requires a non-empty clock pin and positive period."
    }
}
if {$uses_hdmi} {
    foreach required {hdmi_tmds_iostandard hdmi_clk_p_pin hdmi_d_p_pins} {
        if {![info exists $required]} {
            error "HDMI build requires board profile field '$required'."
        }
    }
    if {$hdmi_clk_p_pin eq "" || [llength $hdmi_d_p_pins] != 3} {
        error "HDMI profile must define one clock P pin and three data P pins."
    }
}
if {$uses_key} {
    foreach required {key_port key_pins key_iostandard key_active_low} {
        if {![info exists $required]} {
            error "Button-controlled build requires board profile field '$required'."
        }
    }
    if {[llength $key_pins] < 2} {
        error "Button-controlled build requires at least two key pins."
    }
}

file mkdir $build_root
set report_root [file join $build_root reports]
file mkdir $report_root

set_param general.maxThreads 1

read_verilog $rtl
if {[llength $synth_generics] > 0} {
    synth_design -top $top -part $part -verilog_define SYNTHESIS \
        -generic $synth_generics
} else {
    synth_design -top $top -part $part -verilog_define SYNTHESIS
}

if {$uses_clock} {
    set_property PACKAGE_PIN $clock_pin [get_ports $clock_port]
    set_property IOSTANDARD $clock_iostandard [get_ports $clock_port]
    create_clock -name sys_clk -period $clock_period_ns [get_ports $clock_port]
}

if {$uses_led} {
    for {set index 0} {$index < [llength $led_pins]} {incr index} {
        set port [format "%s\[%d\]" $led_port $index]
        set_property PACKAGE_PIN [lindex $led_pins $index] [get_ports $port]
        set_property IOSTANDARD $led_iostandard [get_ports $port]
        if {$led_slew ne ""} {
            set_property SLEW $led_slew [get_ports $port]
        }
        if {$led_drive ne ""} {
            set_property DRIVE $led_drive [get_ports $port]
        }
    }
}

if {$uses_key} {
    for {set index 0} {$index < 2} {incr index} {
        set port [format "%s\[%d\]" $key_port $index]
        set_property PACKAGE_PIN [lindex $key_pins $index] [get_ports $port]
        set_property IOSTANDARD $key_iostandard [get_ports $port]
        set_property PULLUP true [get_ports $port]
    }
}

if {$uses_hdmi} {
    set_property PACKAGE_PIN $hdmi_clk_p_pin [get_ports hdmi_clk_p]
    set_property IOSTANDARD $hdmi_tmds_iostandard [get_ports hdmi_clk_p]
    set_property IOSTANDARD $hdmi_tmds_iostandard [get_ports hdmi_clk_n]
    for {set index 0} {$index < 3} {incr index} {
        set port_p [format "hdmi_d_p\[%d\]" $index]
        set port_n [format "hdmi_d_n\[%d\]" $index]
        set_property PACKAGE_PIN [lindex $hdmi_d_p_pins $index] [get_ports $port_p]
        set_property IOSTANDARD $hdmi_tmds_iostandard [get_ports $port_p]
        set_property IOSTANDARD $hdmi_tmds_iostandard [get_ports $port_n]
    }
}

report_utilization -file [file join $report_root post_synth_utilization.rpt]
opt_design
place_design
phys_opt_design
route_design

report_drc -file [file join $report_root drc.rpt]
set critical_drc [get_drc_violations -quiet -filter {SEVERITY == "Error" || SEVERITY == "Critical Warning"}]
if {[llength $critical_drc] > 0} {
    error "Critical DRC violations remain: [llength $critical_drc]"
}

report_timing_summary -delay_type min_max -check_timing_verbose \
    -max_paths 10 -file [file join $report_root timing_summary.rpt]
set max_timing_paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $max_timing_paths] > 0} {
    if {[get_property SLACK $max_timing_paths] < 0} {
        error "Setup timing failed."
    }
} else {
    puts "TIMING_NOTE no max timing paths found for '$example'."
}

report_utilization -file [file join $report_root post_route_utilization.rpt]
write_checkpoint -force [file join $build_root $example.dcp]
write_bitstream -force [file join $build_root $example.bit]
puts "BUILD_OK board=$board_name part=$part bitstream=[file join $build_root $example.bit]"
