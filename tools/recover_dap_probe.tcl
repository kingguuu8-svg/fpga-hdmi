connect -url tcp:127.0.0.1:3121

puts "before_targets:"
puts [targets]

set reset_status [catch {
    if {[catch {targets -set -nocase -filter {name =~ "DAP*"}}]} {
        targets -set -nocase -filter {name =~ "APU*"}
    }
    rst -system
    after 500
    targets -set -nocase -filter {name =~ "APU*"}
    con
} reset_err]
puts "reset_status=$reset_status reset_err=$reset_err"

after 1000

puts "after_targets:"
puts [targets]

disconnect
