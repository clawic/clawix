# Bridge protocol (Mac <-> iPhone)

Wire format used by the iOS companion to talk to the macOS app over a
local-network WebSocket. Frames are JSON, one frame per WS text message.

## Envelope

Every frame is a flat JSON object:

```
{ "schemaVersion": 1, "type": "<tag>", ...payload fields }
```

`schemaVersion` is bumped on any breaking change. The iPhone refuses to
talk to a Mac reporting a different `schemaVersion` and shows an
"update Clawix on the Mac" empty state.

The current version is `1`.

## Lifecycle

1. iPhone opens WS over TLS. The server cert is pinned by the SHA-256
   fingerprint carried in the pairing QR.
2. First frame the iPhone sends MUST be `auth`. Anything else closes
   the connection with WS code `1008`.
3. Server replies with `authOk` or `authFailed`. On `authFailed` the
   iPhone clears its credentials and prompts for re-pairing.
4. After `authOk`, the iPhone may request `listSessions`, `openSession`,
   `sendPrompt`. The server may push `sessionsSnapshot`, `chatUpdated`,
   `messagesSnapshot`, `messageAppended`, `messageStreaming`,
   `errorEvent` at any time.

## Outbound (iPhone -> Mac)

- `auth` `{ token, deviceName? }`. Bearer token from the QR. Must be
  the first frame.
- `listSessions` `{}`. Asks for a snapshot of the current sessions list. The
  server replies with `sessionsSnapshot`.
- `openSession` `{ sessionId }`. Subscribes to a chat. The server replies
  with `messagesSnapshot` and continues to push `messageAppended` and
  `messageStreaming` for that chat.
- `sendPrompt` `{ sessionId, text }`. Routes a user prompt to the
  existing `AppState.sendUserMessageFromBridge(sessionId, text)` flow.

## Inbound (Mac -> iPhone)

- `authOk` `{ macName? }`.
- `authFailed` `{ reason }`. Generic reason string for debugging.
- `versionMismatch` `{ serverVersion }`. Sent before close when the
  server detects a frame with an older/newer `schemaVersion`.
- `sessionsSnapshot` `{ sessions: [WireChat] }`. Full list of sessions visible
  on the Mac.
- `chatUpdated` `{ chat: WireChat }`. Single chat changed (title,
  branch, hasActiveTurn, last message preview, etc.).
- `messagesSnapshot` `{ sessionId, messages: [WireMessage] }`. Full
  message list for a chat. Sent in response to `openSession`.
- `messageAppended` `{ sessionId, message: WireMessage }`. A new message
  joined the chat (user echo, assistant placeholder, etc.).
- `messageStreaming` `{ sessionId, messageId, content, reasoningText, finished }`.
  Carries the full current state of the message every tick. The
  iPhone replaces. Sending the full state, not deltas, trades a few
  extra KB on LAN for no append/delta correctness bugs (e.g. retry
  rewrites, edits). `finished=true` freezes the message.
- `errorEvent` `{ code, message }`. Non-fatal error to surface in UI.

## WireChat

```
{
  "id": "uuid",
  "title": "...",
  "createdAt": "iso8601",
  "isPinned": false,
  "isArchived": false,
  "hasActiveTurn": false,
  "lastMessageAt": "iso8601 | null",
  "lastMessagePreview": "string | null",
  "branch": "main | null",
  "cwd": "/abs/path | null"
}
```

## WireMessage

```
{
  "id": "uuid",
  "role": "user | assistant",
  "content": "...",
  "reasoningText": "...",
  "streamingFinished": true,
  "isError": false,
  "timestamp": "iso8601"
}
```

## Out of scope (MVP)

The MVP omits tool calls, plan questions, attachments, image
generation, work summaries and context-usage. They become new frame
types in a later `schemaVersion` bump.
