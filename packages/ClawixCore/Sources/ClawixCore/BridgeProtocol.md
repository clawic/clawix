# Bridge protocol (Clawix clients <-> bridge daemon)

Wire format used by Clawix clients to talk to the signed bridge daemon over a
local WebSocket. Frames are JSON, one frame per WS text message.

## Envelope

Every frame is a flat JSON object:

```
{ "protocolVersion": 8, "type": "<tag>", ...payload fields }
```

Clawix is still pre-public, so the complete current bridge surface is the v1
contract. Clients refuse to talk to a daemon reporting a different
`protocolVersion` and show an "Update Clawix" empty state.

The current protocol version is `8`.

## Lifecycle

1. Client opens WS to the paired/local daemon endpoint.
2. First frame the companion sends MUST be `auth`. Anything else closes
   the connection with WS code `1008`.
3. Server replies with `authOk` or `authFailed`. On `authFailed` the
   companion clears its credentials and prompts for re-pairing.
4. After `authOk`, the client may request frames allowed for its
   `clientKind`. The daemon may push snapshots, deltas and non-fatal
   `errorEvent` frames at any time.

## Outbound (client -> daemon)

- `auth` `{ token, deviceName?, clientKind?, clientId?, installationId?, deviceId? }`.
  Bearer token from pairing or local bootstrap. Must be the first frame.
- `listSessions` `{}`. Asks for a snapshot of the current sessions list. The
  server replies with `sessionsSnapshot`.
- `openSession` `{ sessionId, limit? }`. Subscribes to a session and may request
  a trailing page.
- `loadOlderMessages` `{ sessionId, beforeMessageId, limit }`. Fetches older
  message pages.
- `sendMessage` / `newSession` `{ sessionId, text, attachments? }`. Routes a
  user prompt with optional image/audio attachments.
- Desktop-capable clients may additionally use edit/archive/pin/project,
  pairing, file, audio, image, rate-limit and skills frames registered in
  `BridgeProtocol.swift`.

## Inbound (daemon -> client)

- `authOk` `{ hostDisplayName? }`.
- `authFailed` `{ reason }`. Generic reason string for debugging.
- `versionMismatch` `{ serverVersion }`. Sent before close when the daemon
  detects an incompatible `protocolVersion`.
- `sessionsSnapshot` `{ sessions: [WireSession] }`. Full list of sessions visible
  on the Mac.
- `sessionUpdated` `{ session: WireSession }`. Single session changed (title,
  branch, hasActiveTurn, last message preview, etc.).
- `messagesSnapshot` `{ sessionId, messages: [WireMessage], hasMore? }`.
  Current message page for a session. Sent in response to `openSession`.
- `messageAppended` `{ sessionId, message: WireMessage }`. A new message
  joined the session (user echo, assistant placeholder, etc.).
- `messageStreaming` `{ sessionId, messageId, content, reasoningText, finished }`.
  Carries the full current state of the message every tick. The
  iPhone replaces. Sending the full state, not deltas, trades a few
  extra KB on LAN for no append/delta correctness bugs (e.g. retry
  rewrites, edits). `finished=true` freezes the message.
- `errorEvent` `{ code, message }`. Non-fatal error to surface in UI.

The exhaustive frame and model definitions live in `BridgeProtocol.swift` and
`BridgeModels.swift`; this document pins the public wire conventions, not a
second hand-maintained schema.
