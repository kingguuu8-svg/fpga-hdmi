# JTAG backends

## XSCT

Use with a Xilinx/Digilent-compatible cable visible to `hw_server`.

## openFPGALoader

Use cable `ft4232` for the generic FT4232H VID `0403`, PID `6011`. On Windows,
bind only interface `MI_00` to WinUSB. Keep the other FTDI interfaces on their
existing drivers so UART ports remain available.

The MVP downloads volatile SRAM configuration only. Persistent boot media is a
later pipeline stage.

