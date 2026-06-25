# Current Cycle

Status: no active implementation cycle.

## Rule

Open a cycle here before starting implementation work that should end in a
commit. A cycle must have a concrete objective, verification plan, and closure
criteria.

## Cycle Template

```text
Cycle ID:
Objective:
Scope:
Verification plan:
Board action:
Evidence target:
Closure criteria:
```

## Current State

The project-management bootstrap and source baseline are complete. No
implementation cycle is active.

The next implementation cycle should be opened here before modifying RTL, XDC,
Tcl, PS software, UART tools, Ethernet tools, or HDMI validation scripts.

Recommended next cycle:

```text
Cycle ID: mvp-network-video-control
Objective: build the first Ethernet-video + UART-control + HDMI-output MVP loop
Scope: PS receive path, PL video path, UART command endpoint, PC sender/control tools
Verification plan: simulation first, then Vivado build, then board programming
Board action: program connected XC7Z020 and verify HDMI/UART/Ethernet behavior
Evidence target: docs/reports/mvp-network-video-control.md
Closure criteria: visible HDMI output responds to UART control while video frames originate from PC-side Ethernet input or its staged MVP substitute
```
