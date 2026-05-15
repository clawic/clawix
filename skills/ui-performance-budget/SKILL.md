---
name: ui-performance-budget
description: Capture and compare Clawix UI performance budgets for critical flows before optimizing visible or runtime UI behavior.
keywords: [ui, performance, budgets, latency, hitches, traces]
---

# ui-performance-budget

Use for sidebar lag, chat scroll performance, composer typing latency, dropdown
open delay, terminal/sidebar switching, right-sidebar/browser performance, or
any UI performance budget change.

## Procedure

1. Read `macos/PERF.md`, `docs/adr/0010-interface-governance.md`, and
   `docs/ui/performance-budgets.json`.
2. Identify the critical flow and whether its baseline is approved.
3. Capture evidence before optimization using the target performance playbook.
4. Compare against the approved baseline when present. If no approved baseline
   exists, produce a baseline-capture report for user approval.
5. Do not retune visual timing, layout, animation, or perceived style unless
   the task is visual-authorized.

## Constraints

- No performance fixes from static reading alone.
- No paid prompts, real service mutations, or production data during capture
  without explicit approval.
- Missing physical/provider prerequisites are `EXTERNAL PENDING`.
