# Board profile contract

A profile is Tcl sourced by the deterministic build script. It must define:

- `board_name`
- `part`: exact XC7Z020 part including package and speed grade
- `clock_port`, `clock_pin`, `clock_period_ns`, `clock_iostandard`
- `led_port`, `led_pins`, `led_iostandard`, `led_active_low`

Use one or more LED pins. Preserve schematic signal order in `led_pins`.

