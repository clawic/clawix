---
name: performance-investigation
description: Investigate latency, freezes, memory growth, hitches, dropped frames, or perceived slowness with reproduction and instrumentation before optimizing.
keywords: [performance, latency, memory, hitches, profiling, instrumentation]
---

# performance-investigation

Diagnose performance before changing code.

## Procedure

1. Read the target performance docs and relevant private/public validation constraints.
2. Reproduce in the user-relevant mode when feasible.
3. Instrument before optimizing: traces, profiler samples, render logs, CPU/RAM, network, polling, timers, and host diagnostics as applicable.
4. Exercise realistic heavy workflows: large sessions, long scrolls, attachments, search, panels, terminals, browser/sidebar, composer, and streaming state.
5. Correlate observed UI behavior with measurements.
6. Classify causes as confirmed, probable, discarded, or not physically validated.

## Constraints

- Do not optimize from code inspection alone unless reproduction is impossible and the limitation is reported.
- Do not send real prompts or use paid services for performance work without approval.
- Keep validation partial if the real mode could not be exercised.
