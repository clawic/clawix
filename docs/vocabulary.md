# Clawix vocabulary

This document is the human-readable companion to
`docs/vocabulary.registry.json`. Clawix imports the shared ClawJS vocabulary and
adds host/UI-specific exceptions.

## Session

Use `session` and `sessionId` for framework and bridge conversation identity in
protocol, storage, durable cache, deep links, and framework-facing code.

Context-only word: `chat`. It is allowed in visible UI copy, UI-local models,
localization, and provider APIs. Do not add new bridge protocol fields such as
`chatId` for framework session identity.

## Thread ID

Use `threadId` for external runtime identity and reconciliation with Codex or
provider runtimes. Do not use it as the primary framework session key.

## Clawix Bridge

Use `clawix-bridge` for the stable bridge service. Do not reintroduce
`clawix-bridged` or `CLAWIX_BRIDGED_*`.

## Host

Use `host` for the signed native owner of Clawix operational state and
sensitive native capabilities. Node-only code must not become the owner of
native permission grants, approvals, secrets, or destructive actions.
