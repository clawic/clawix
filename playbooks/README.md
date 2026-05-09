# Computer Use Playbooks

This directory defines public, agent-readable playbooks for visual end-to-end checks that use Computer Use or equivalent human-like UI control.

The playbooks are documentation. They do not run code, install hooks, send prompts, touch real accounts, or modify production services. They describe how an agent should exercise the product visually, what variants matter, what safety boundary applies, and what checklist evidence should be collected.

## Platforms

- [macOS](macos/README.md) is the populated reference platform.
- [iOS](ios/README.md) has planned coverage structure.
- [Web](web/README.md) is a placeholder.
- [Linux](linux/README.md) is a placeholder.
- [Windows](windows/README.md) is a placeholder.
- [Android](android/README.md) is a placeholder.
- [Coverage Matrix](COVERAGE.md) tracks covered, partial, and missing areas.

## Canonical Format

Every executable playbook is a Markdown file with YAML front matter. The body stays readable for contributors; the front matter stays structured enough for future linting or automation.

Required front matter fields:

- `id`
- `platform`
- `surface`
- `status`
- `priority`
- `tags`
- `intent`
- `entrypoints`
- `variants`
- `required_state`
- `safety`
- `execution_mode`
- `artifacts`
- `assertions`
- `known_risks`

Required body sections:

- Goal
- Invariants
- Setup
- Entry Points
- Variant Matrix
- Critical Cases
- Steps
- Expected Results
- Failure Signals
- Evidence Checklist
- Screenshot Checklist
- Notes for Future Automation

See [Writing Guide](WRITING.md) before adding or changing playbooks.
