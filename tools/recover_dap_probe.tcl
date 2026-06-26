connect -url tcp:127.0.0.1:3121

puts "before_targets:"
puts [targets]

set reset_status [catch {
    targets -set -nocase -filter {name =~ "DAP*"}
    rst -system
} reset_err]
puts "reset_status=$reset_status reset_err=$reset_err"

after 1000

puts "after_targets:"
puts [targets]

disconnect
