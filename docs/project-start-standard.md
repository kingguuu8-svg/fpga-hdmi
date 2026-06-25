# Project Start Standard

The project is formally ready to start implementation work only when all items
below are true.

## Required State

- `AGENTS.md` is the registered rule entry point.
- Project-management documents are registered in `AGENTS.md`.
- The active technical route is recorded in `docs/project-roadmap.md`.
- `docs/current-cycle.md` states either the active cycle or that no cycle is
  active.
- `docs/cycle-log.md` records completed management and implementation cycles.
- `docs/reports/` exists for concise committed evidence reports.
- Existing source files needed for the FPGA workflow are tracked by git.
- Generated Vivado state, downloads, logs, bytecode caches, and bulky local
  artifacts are ignored.
- `git status --short` is clean except for intentionally ignored local build
  artifacts.

## First Implementation Cycle Gate

Before changing RTL, XDC, Tcl, PS software, UART tooling, Ethernet tooling, or
HDMI validation scripts:

```text
1. Open a concrete cycle in docs/current-cycle.md.
2. State objective, scope, verification plan, board action, evidence target,
   and closure criteria.
3. Implement only within that cycle unless the cycle is updated.
4. Close the cycle with simulation or the closest automated test, board action
   when hardware-affecting, concise evidence, and one git commit.
```

## Ready Definition

When this checklist passes, the project may start the first formal
implementation cycle:

```text
git branch: main
git status: clean
baseline source: tracked
active cycle: none
next cycle: identified in docs/current-cycle.md
```

