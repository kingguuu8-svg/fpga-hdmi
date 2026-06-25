# MVP acceptance

- Vivado 2018.3 is detected.
- The carrier profile is schematic-backed.
- `led-static.bit` is produced when no base-board PL clock is verified.
- `led-chaser.bit` is produced only after the board profile has a verified
  clock pin and frequency.
- DRC contains no error or critical warning.
- Setup timing slack is non-negative.
- The connected XC7Z020 accepts the SRAM bitstream.
- The expected LED state or sequence is observed physically.
- Environment, build, timing, DRC, and programming reports are retained.
- `build/reports/latest-mvp-run.json` records the latest automated run.
