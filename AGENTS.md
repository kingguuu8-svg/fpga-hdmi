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
- `docs/project-start-standard.md`: checklist that defines when the repository
  is ready to start a formal implementation cycle.
- `docs/boards/hellofpga-smart-zynq-sl.md`: consolidated board reference for
  the connected HelloFPGA Smart ZYNQ SL board.
- `docs/boards/lookup-log.md`: chronological board-information lookup log.
  Update it whenever a board web page, schematic, official example, hardware
  probe, or downloaded reference project is inspected.
- `docs/protocols/video-udp.md`: first-stage raw-video UDP chunk protocol used
  by the PC sender and PS baremetal receiver.
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
- Board information must be promoted in two steps: record every inspected
  source in `docs/boards/lookup-log.md`, then copy stable facts into
  `docs/boards/hellofpga-smart-zynq-sl.md`. Before any new board lookup, first
  search these two files for the exact interface, pin, IP, clock, voltage, or
  software fact. Re-open board pages, schematics, downloaded examples, or probe
  hardware only when the needed fact is missing, stale, contradictory, or marked
  unverified.
- A board lookup is incomplete until the lookup log records the source, the
  question being answered, extracted conclusion, promotion target, and remaining
  uncertainty. If the lookup changes an implementation decision, also update the
  owning roadmap, protocol, board reference, or cycle report in the same change.
- Every board lookup must be normalized into a reusable fact card, not left as
  raw notes. The card must identify the source, exact lookup question, extracted
  implementation fact, impacted interface or file, verification status,
  promotion target, and remaining uncertainty.
- Backlog ideas are not active requirements. Promote an idea by adding it to the
  registered roadmap or asking the user to confirm the scope.

## Fact consistency

Drift-prone facts each have a single owner document. Non-owner documents must
not hold the concrete value of these facts; they may only reference the owner.

| Fact class | Owner document |
| --- | --- |
| MVP scope, resolution, pixel format, input/output spec | `docs/project-roadmap.md` |
| Active cycle state | `docs/current-cycle.md` |
| Board hard facts (pins, clocks, voltage, IP parameters) | `docs/boards/hellofpga-smart-zynq-sl.md` |
| Workflow entry points and shortest paths | `skills/zynq7020-pipeline/SKILL.md` |

When an owner document changes one of these facts, every reference to it must
be updated in the same commit. References must say "see `<owner>`" rather than
restating the value, so a value change cannot leave a stale copy behind. This
applies to `README.md`, skills, protocols, reports, and any other registered or
unregistered document.

The single-source rule is what prevents the kind of contradiction where the
roadmap says one resolution, the README says another, and the code implements a
third. The fix is not better priority rules between conflicting documents; the
fix is not having conflicting copies in the first place.

## Skill dynamic optimization

`skills/zynq7020-pipeline/SKILL.md` is a living workflow index, not a frozen
initial version. It must grow as the project discovers new verified paths.

When a cycle opens and follows a build/simulate/program/verify path that the
pipeline skill does not yet record, and that path is later verified feasible in
that cycle (a marker prints, a board action passes, or equivalent evidence),
the same commit that closes the cycle must add that path to the pipeline skill
as a new entry point.

When a cycle verifies a shorter feasible path than one already recorded in the
pipeline skill, the same commit must add the shorter path to the skill and mark
it `preferred`, superseding the older longer path. The older path is kept for
recovery context but is no longer the recommended first choice.

A path may only be promoted into the skill after it is verified feasible.
Paths that were attempted but failed (for example, a hand-written RGMII bridge
that did not achieve RX) must not be recorded as entry points. They belong in
the cycle report or lookup log as negative evidence, not in the skill as a
workflow option. This keeps the skill a registry of routes that work, not a
diary of routes that were tried.

The optimization rule and the fact-consistency rule above are coupled: the
pipeline skill is the owner of "workflow entry points and shortest paths", so
discovering a new path is a fact change to an owner document, and the same
single-commit update discipline applies.

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
- Keep the MVP path minimal, but follow the current registered roadmap. The
  active network-video MVP is not PL-only: it uses PS/Linux or a PS fallback
  receiver plus VDMA HDMI. While no TF card is available, pause hand-written
  RGMII bridge work and resume from the TF-card Linux ping route gate.
- Prefix terminal commands with `rtk`. When invoking PowerShell cmdlets, use
  `rtk powershell.exe -NoProfile -Command ...`.
- Use CUDA builds only if PyTorch is introduced.
