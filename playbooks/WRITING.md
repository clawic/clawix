# Writing Guide

Computer Use playbooks describe visual user flows, not implementation details. Write them so a capable agent can run the app, operate it like a human, inspect the result, and know when to stop.

Playbooks are not a runner specification. Use human-readable steps with stable anchors: visible labels, keyboard shortcuts, menu names, expected focus, screenshots, and user-visible state changes.

## Naming

- Use lowercase kebab-case file names.
- Name by user capability, not by source file or component name.
- Use stable IDs in the form `<platform>.<surface>.<capability>`.
- Keep public text in English.

## Status

Use one of:

- `reference`: the most complete example for a platform or surface.
- `ready`: broad enough for real agent use.
- `draft`: structure exists, but coverage is incomplete.
- `placeholder`: platform or surface exists, but no real playbook is defined.
- `deprecated`: retained for historical context; do not choose it for new validation.

## Priority

Use one of:

- `P0`: critical smoke or release-blocking capability.
- `P1`: common user flow or high-risk regression area.
- `P2`: important but less common flow.
- `P3`: low-risk exploratory or edge coverage.

## Controlled Tags

Use only these tags in front matter:

- `smoke`
- `regression`
- `host`
- `dummy`
- `sensitive`
- `confirmation`
- `navigation`
- `composer`
- `attachments`
- `settings`
- `runtime`
- `bridge`
- `services`
- `secrets`
- `voice`
- `browser`
- `memory`
- `models`
- `projects`
- `search`
- `ios-planned`

## Safety

Every playbook must declare whether the flow is safe in isolation and what requires explicit user confirmation.

Safety levels:

- `safe_dummy`: safe in dummy, fixture-backed, or intercepted mode.
- `host_local`: touches host-local state but not real external services by default.
- `confirmation_required`: must stop for explicit user confirmation before the risky step.
- `forbidden`: must not be performed by a playbook.

Default rules:

- Use dummy or fixture-backed data by default.
- Never send a real model prompt without explicit confirmation.
- Never write, update, delete, upload, publish, or pay for anything in a real external service without explicit confirmation.
- Never inspect, reveal, paste, or store real secret values.
- For host-dependent flows, record both hermetic validation expectations and real host validation expectations.

## Front Matter Shape

Use this shape unless a field needs a short scalar value:

```yaml
---
id: macos.chat.example
platform: macos
surface: chat
status: ready
priority: P1
tags:
  - regression
  - dummy
intent: "Describe the user-visible behavior being checked."
entrypoints:
  - keyboard shortcut
  - visible button
variants:
  - happy path
  - alternate path
  - edge path
required_state:
  app_mode: dummy
  data: fixture-backed chats
safety:
  level: safe_dummy
  default: isolated
  requires_explicit_confirmation:
    - real prompt submission
execution_mode:
  hermetic: required
  host: required for host-dependent bugs
artifacts:
  - focused window screenshot
assertions:
  - visual state that must be true
known_risks:
  - likely false positive or brittle area
---
```

## Body Sections

`Goal` states the user outcome in one paragraph.

`Invariants` lists behavior that must always hold across variants.

`Setup` describes the state an agent needs before acting. Prefer fixture-backed, local, dummy, or intercepted setup.

`Entry Points` names every meaningful way the user can enter the flow.

`Variant Matrix` names the dimensions that should be combined over time. It does not need to enumerate every Cartesian product.

`Critical Cases` lists the highest-value named cases agents should prioritize.

`Steps` gives a concrete happy path first, then alternate paths.

`Expected Results` describes visual, accessibility, and state outcomes.

`Failure Signals` describes what should make the agent stop and report a regression.

`Evidence Checklist` gives checkboxes or rows that an agent marks as `pass`, `fail`, or `no-run`.

`Screenshot Checklist` names the exact screens or states to capture.

`Notes for Future Automation` captures stable anchors, fixture needs, and what a future runner should parse.

## Maintenance

- Update a playbook when a user-visible flow changes.
- Add variants when a bug is found through a path not already covered.
- Keep one-off content checks out of persistent playbooks unless they protect durable behavior.
- Prefer broad capability coverage over implementation-specific instructions.
- Keep screenshots out of the repo unless they are intentional public assets.
- Any visible feature change should update an existing playbook, add a new playbook, or update the coverage matrix with a clear `partial` or `missing` entry.
