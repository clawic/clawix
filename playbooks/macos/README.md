# macOS Playbooks

macOS is the reference platform for v1. These playbooks are grouped by user capability so an agent can start from the behavior it wants to check.

## Chat

- [New conversation](chat/new-conversation.md)
- [Message composition](chat/message-composition.md)
- [Attachments](chat/attachments.md)
- [Chat lifecycle](chat/chat-lifecycle.md)

## Navigation and Organization

- [Sidebar and projects](sidebar-projects.md)
- [Search and navigation](search-navigation.md)

## Settings

- [Settings](settings.md)

## Runtime Defaults

- Default execution mode is dummy or fixture-backed.
- Real prompt submission requires explicit user confirmation.
- Real secret handling requires explicit user confirmation and must never expose secret values.
- Host-dependent bugs require both hermetic validation and real macOS host validation.
