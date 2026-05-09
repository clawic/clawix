# iOS Playbooks

iOS coverage is planned but intentionally not fully populated yet. Use the same Markdown plus YAML front matter schema described in the root writing guide when adding real playbooks.

## Planned Capabilities

| Capability | Target status | Notes |
| --- | --- | --- |
| Chat list | draft | Launch, empty state, search, archived/pinned state, new chat. |
| Chat detail | draft | Open chat, send follow-up, scroll, assistant streaming, interruption. |
| Composer attachments | draft | Photo library, camera capture, recent photos, attachment removal, send payload. |
| Voice recording | draft | Record, stop, waveform, transcription, send voice note. |
| Bridge pairing | draft | Pairing QR/code, reconnect, daemon unavailable, token failure. |
| Project detail | draft | Project chat list, project-scoped new chat, picker chrome. |
| Settings and permissions | draft | Photos, camera, microphone, speech, local notification prompts. |

## iOS Defaults

- Use a project-dedicated simulator.
- Use fixture or dummy bridge data by default.
- Real device, real prompt submission, real account access, and real media access require explicit confirmation.
- Screenshots should come from the simulator or device window, never a full desktop capture.
