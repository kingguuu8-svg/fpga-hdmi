# Project Agent Rules

## Rule entry point

- `AGENTS.md` is the authoritative project rule index for this repository.
- Project documents are not active project-management sources unless they are
  registered in this file.
- When a new project-management document is created, add it to the registry in
  this file in the same change.
- If registered documents conflict, prefer this order: user/developer/system
  instructions, `AGENTS.md`, then the registered project document.

## Registered project documents

- `README.md`: project overview, current workflow entry points, and basic usage.
- `docs/project-roadmap.md`: accepted system route, MVP scope, post-MVP phases,
  and phase acceptance criteria.
- `docs/current-cycle.md`: the current active cycle, or an explicit statement
  that no implementation cycle is open.
- `docs/cycle-log.md`: completed cycle ledger with commit IDs, verification
  scope, and residual risks.
- `docs/reports/`: concise, git-tracked evidence reports for completed cycles.
- `build/reports/`: raw generated reports and command output. These files
  support decisions but do not define rules and are not expected to be tracked.

## Project skills

This repository keeps its FPGA workflow skills under `skills/`. Do not install
project-specific skills into the user-level Codex skills directory.

For every Zynq-7020 workflow, load the orchestrator first:

- `skills/zynq7020-pipeline/SKILL.md`

Load the following child skills only when the corresponding stage is needed:

- `skills/zynq7020-environment/SKILL.md`: toolchain and connected-hardware discovery
- `skills/zynq7020-vivado/SKILL.md`: deterministic Vivado project generation and build
- `skills/zynq7020-hardware/SKILL.md`: JTAG programming and hardware verification

## Project management

- Keep one active route in `docs/project-roadmap.md`; do not scatter competing
  roadmaps across unregistered files.
- A hardware work cycle is: write or modify sources, run simulation or the
  closest available automated test, build/program the board when the change is
  hardware-affecting, record evidence, then make one git commit.
- For RTL, XDC, Tcl, board, or video-pipeline changes, a cycle is incomplete
  until simulation and board programming have either passed or are explicitly
  recorded as not run with the reason.
- Documentation-only changes may close as a documentation cycle without
  simulation or board programming, but must not be described as hardware
  verified.
- Record decisions and verification evidence in the registered document that
  owns the topic; use `docs/reports/` for concise committed evidence and
  `build/reports/` for raw generated command output and hardware probes.
- Backlog ideas are not active requirements. Promote an idea by adding it to the
  registered roadmap or asking the user to confirm the scope.

## Git management

- Use one commit per completed work cycle. Do not commit half-finished write,
  simulation, or board-programming states unless the user explicitly asks for a
  checkpoint commit.
- Before committing, run `git status --short`, stage only files that belong to
  the completed cycle, and preserve unrelated user changes.
- Commit message format: `cycle: <short result>` for implementation cycles,
  `docs: <short result>` for documentation-only cycles, and
  `fix: <short result>` for narrow repair cycles.
- If `.git` is absent, report that git management cannot proceed and ask before
  initializing or attaching a repository.
- Do not commit generated Vivado state, downloads, or bulky build products.
  Commit source RTL, XDC, Tcl, scripts, skills, and concise reports needed to
  reproduce or audit the cycle.

## Engineering rules

- Target the connected XC7Z020 board; never guess package, clock, voltage, or pin constraints.
- Keep generated Vivado state under `build/`; keep source RTL and XDC under `examples/`.
- Run Vivado in batch mode from checked-in Tcl.
- Treat timing failure, DRC errors, missing constraints, and device mismatch as hard failures.
- Keep the MVP path minimal: close the PL bitstream-to-board loop before adding PS software or Linux.
- Prefix terminal commands with `rtk`. When invoking PowerShell cmdlets, use
  `rtk powershell.exe -NoProfile -Command ...`.
- Use CUDA builds only if PyTorch is introduced.
