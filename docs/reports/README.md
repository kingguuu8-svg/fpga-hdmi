# Reports

Use this directory for concise, git-tracked evidence reports.

## Policy

- Keep raw Vivado logs, generated hardware probes, captures, and bulky outputs
  under `build/reports/`.
- Commit only concise reports that explain what was tested, what passed, what
  failed, and where raw evidence can be regenerated or found locally.
- Each implementation cycle should either add a report here or reference an
  existing registered evidence document.

## Suggested Report Template

```text
# <cycle-id> Report

Date:
Commit:
Objective:
Commands:
Simulation:
Build:
Board programming:
Runtime verification:
Evidence files:
Result:
Residual risks:
```

