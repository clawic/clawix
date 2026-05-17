# Performance

This is the public performance router for Clawix.

Performance work starts with measured reproduction and instrumentation, not
static code reading. For macOS investigations, use
[`macos/PERF.md`](macos/PERF.md); it defines the capture stack, symptom table,
trace artifacts, and the rule that a trace precedes optimization.

Interface performance budgets are governed cross-platform by
[`docs/ui/performance-budgets.registry.json`](docs/ui/performance-budgets.registry.json).
Those budgets are per critical flow and per governed platform. They become
enforceable only after the user approves measured private baselines, referenced
through [`docs/ui/private-baselines.manifest.json`](docs/ui/private-baselines.manifest.json).
The initial governed critical flows are sidebar hover/click/expand, chat scroll,
composer typing, dropdown open, terminal/sidebar switch, and right-sidebar/browser use.

Public checks validate the registry shape and baseline linkage through
`node scripts/ui_performance_budget_check.mjs`. Private evidence remains
outside the public repository and is verified with
`CLAWIX_UI_PRIVATE_BASELINE_ROOT=<private-root> node scripts/ui_private_performance_budget_verify.mjs --require-approved`.
