# macOS Playbooks

macOS is the reference platform. These playbooks are grouped by user capability so an agent can start from the behavior it wants to check.

## Chat

- [New conversation](chat/new-conversation.md)
- [Message composition](chat/message-composition.md)
- [Attachments](chat/attachments.md)
- [Chat lifecycle](chat/chat-lifecycle.md)

## Navigation and Organization

- [Sidebar and projects](sidebar-projects.md)
- [Search and navigation](search-navigation.md)
- [Browser](browser.md)

## Settings

- [Settings](settings.md)
- [Voice to Text](voice-to-text.md)
- [QuickAsk](quickask.md)
- [Secrets](secrets.md)
- [Memory](memory.md)
- [Local models](local-models.md)
- [Daemon bridge and Machines](daemon-bridge.md)
- [ClawJS services](clawjs-services.md)

## Runtime Defaults

- Default execution mode is dummy or fixture-backed.
- Real prompt submission requires explicit user confirmation.
- Real secret handling requires explicit user confirmation and must never expose secret values.
- Host-dependent bugs require both hermetic validation and real macOS host validation.
- Agents should choose playbooks by priority, controlled tags, and the root coverage matrix.
