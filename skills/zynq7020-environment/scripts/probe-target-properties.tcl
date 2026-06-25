set output_path [lindex $argv 0]
if {$output_path eq ""} {
    error "Usage: probe-target-properties.tcl <output-path>"
}

connect -url tcp:127.0.0.1:3121

set fp [open $output_path w]
puts $fp "targets:"
puts $fp [targets]

foreach target_id {1 2 3 4 5 6 7 8} {
    if {[catch {targets $target_id} err]} {
        continue
    }
    puts $fp ""
    puts $fp "target_$target_id:"
    if {![catch {targets -target-properties} props]} {
        puts $fp $props
    }
}

puts $fp ""
puts $fp "jtag_targets:"
if {![catch {jtag targets} jt]} {
    puts $fp $jt
} else {
    puts $fp "ERROR: $jt"
}
close $fp
disconnect

