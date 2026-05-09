# Clawix macOS · Performance Playbook

Diagnostic system for the macOS app. Built so any agent receiving
"this feels slow" / "RAM keeps growing" / "the sidebar is laggy" /
"frames drop" can produce a reproducible trace + supporting artifacts
in one command, without asking the user to do anything beyond
reproducing the symptom.

This file is the single source of truth for: what to capture, how to
read it, and which file to look at first per symptom. Update it when
a new symptom shows up or when a hot-path moves to a different file.

## Standing rule for agents

When the user reports any performance issue, BEFORE proposing a fix:

1. Read this file, find the symptom in the table below.
2. Run the capture for that template:
   ```
   bash macos/scripts/perf-capture.sh --template "<template>" --name <slug>
   ```
3. The user reproduces the symptom inside the launched app, then
   quits / Ctrl-C the script. The script prints the trace directory.
4. Open `trace.trace` in Instruments and cross-reference with
   `console.ndjson`, `clawix-renders.log`, and `Diagnostics-*/` in
   the same directory.
5. Only then propose a fix, citing what the trace showed.

Never start optimizing without a trace. Guessing at hot paths in a
1000+ file project is how surface-level changes ship without moving
the needle.

## Diagnostic stack overview

| Layer | Lives at | Always on? | What it gives |
| --- | --- | --- | --- |
| `RenderProbe` + `HitchProbe` | `Sources/Clawix/RenderProbe.swift` | yes | Per-window body re-eval counters and hitch buckets in `/tmp/clawix-renders.log` |
| `PerfSignpost` taxonomy | `Sources/Clawix/Diagnostics/Signposts.swift` | yes (suppressible via `CLAWIX_DISABLE_SIGNPOSTS=1`) | Categorised intervals/events visible in Instruments `os_signpost` track |
| `ResourceSampler` | `Sources/Clawix/Diagnostics/ResourceSampler.swift` | yes | RSS, footprint, %CPU once per second; emitted as signposts and dumped to `last-resources.json` on app exit |
| `HangDetector` | `Sources/Clawix/Diagnostics/HangDetector.swift` | DEBUG by default; `CLAWIX_FORCE_HANG_DETECTOR=1` to enable in release | Runloop-level main-thread stalls > `CLAWIX_HANG_MS` (default 250 ms) |
| `MetricKitObserver` | `Sources/Clawix/Diagnostics/MetricKitObserver.swift` | yes | Apple's own daily payloads (launch time, hitch ratio, hangs with backtraces, app exit reasons) |
| `streamingPerfLog` | `Sources/Clawix/StreamingFade.swift` | yes (toggle in source) | Streaming pipeline per-message timings via `Logger("stream-perf")` |

All of the above land in one place when you run `perf-capture.sh`:

- `trace.trace` (Instruments)
- `clawix-renders.log` (RenderProbe)
- `Diagnostics-<bundleId>/metrics-*.json`, `diagnostics-*.json`,
  `last-resources.json` (MetricKit + ResourceSampler)
- `console.ndjson` (`log show` filtered by subsystem)
- `README.txt` (what was captured)

## Signpost taxonomy

| Category | Emitted from | What you see |
| --- | --- | --- |
| `ui.chat` | `ChatView.swift` `MessageRow` body | One `row.body` event per message body re-eval |
| `ui.sidebar` | `SidebarView.swift:145` `makeSnapshot` | One `snapshot` interval per body invocation |
| `state.appstate` | `AppState.swift` `objectWillChange` ticks via `RenderProbe` | High-rate ticks correlated with publisher emissions |
| `ipc.client` | `AgentBackend/ClawixClient.swift:241` `handleLine` | One `decode` interval per JSON-RPC frame |
| `render.markdown` | `AgentBackend/AssistantMarkdownText.swift:148` `MarkdownParseCache.parse` | One `parse` interval per cache miss |
| `render.streaming` | `StreamingFade.swift` `ingest` | One `ingest` event per delta, value = delta length |
| `image.load` | (reserved for image decoding work) | (call sites added when needed) |
| `secrets.crypto` | (reserved for KDF / AEAD work) | (call sites added when needed) |
| `hang` | `Diagnostics/HangDetector.swift` | One `main-stalled` event per stall, value = ms |
| `resource` | `Diagnostics/ResourceSampler.swift` | `rss_mb`, `footprint_mb`, `cpu_pct` once per second |

Add a new category by editing `Signposts.swift`, registering it in
the table above, and only then emitting from a call site. The ad-hoc
"add an os_signpost here" anti-pattern is what the taxonomy exists to
prevent.

## Symptom → action table

For every row: capture with the listed template, open the trace, look
in the listed file:line, and check the indicated lane / artifact.

### Sidebar lag on hover, click, drag, or while typing

- Hypothesis: `makeSnapshot` is republishing on every body render and
  dragging O(N+M log M) work along with each `@Published` change.
- Capture: `bash macos/scripts/perf-capture.sh --template "SwiftUI" --name sidebar`.
- Look at: `macos/Sources/Clawix/SidebarView.swift:145`.
- In the trace: `ui.sidebar` lane should show one `snapshot` interval
  per body. Multiple per click = republish; the body is being
  invalidated by upstream `@Published`. Cross-check the `state.appstate`
  signpost rate.
- In `clawix-renders.log`: `makeSnapshot=N` per 0.5 s window. >5
  per click is suspicious.

### Long chat scrolls badly

- Hypothesis: `LazyVStack(ForEach(chat.messages))` without windowing
  + `MarkdownParseCache.parse` being a cache miss for every row.
- Capture: `bash macos/scripts/perf-capture.sh --template "Animation Hitches" --name chat-scroll`.
- Look at: `macos/Sources/Clawix/ChatView.swift:43` (the LazyVStack)
  and `:599` (`MessageRow.body`); markdown at
  `Sources/Clawix/AgentBackend/AssistantMarkdownText.swift:148`.
- In the trace: `Animation Hitches` lane shows the dropped frames. Open
  `os_signpost` track underneath: `render.markdown.parse` intervals
  > 4 ms during scroll = miss path triggering. `ui.chat.row.body` events
  per second above the visible row count = body re-evals beyond what
  scroll requires.

### RAM keeps growing during a long session

- Hypothesis: `streamCheckpoints` array growing unbounded, plus the
  whole `chats: [Chat]` array republishing on every delta.
- Capture: `bash macos/scripts/perf-capture.sh --template "Allocations" --name long-session`.
- Look at: `macos/Sources/Clawix/AppState.swift:42, 614, 3465-3584`
  and `macos/Sources/Clawix/ChatView.swift:850`.
- In the trace: mark a generation in Allocations between user
  interactions. The growing categories tell you what is leaking
  vs growing legitimately.
- In `Diagnostics-*/last-resources.json` and the per-second `resource`
  signposts: chart `rss_mb` over time. A monotonic upward staircase
  during streaming = checkpoint accumulation; a step on send/receive =
  array republish copy churn.

### Brief freezes / "the app skipped"

- Hypothesis: synchronous main-thread work, typically
  `JSONDecoder().decode` on the IPC hot path or a sync image decode.
- Capture: `bash macos/scripts/perf-capture.sh --template "Time Profiler" --name freeze`.
- Look at: `macos/Sources/Clawix/AgentBackend/ClawixClient.swift:241`
  (decode), `macos/Sources/Clawix/ChatView.swift:490-523`
  (`UserImageThumbnail` sync `NSImage(contentsOf:)`).
- In the trace: filter Time Profiler to the main thread; correlate
  the `hang.main-stalled` signpost events with the dominant
  symbols in the Heaviest Stack Trace.
- In `console.ndjson`: search for `"category":"hang"` lines. The
  follow-up message has the post-stall stack — imperfect (it's the
  thread state right after the stall released) but a useful first
  pass.

### Streaming feels stuttery / characters arrive in clumps

- Hypothesis: bursty deltas + checkpoint replay churn on every
  TimelineView animation tick.
- Capture: `bash macos/scripts/perf-capture.sh --template "os_signpost" --name streaming`.
- Look at: `macos/Sources/Clawix/StreamingFade.swift` and the
  TimelineView wrap at `Sources/Clawix/AgentBackend/AssistantMarkdownText.swift:208-230`.
- In the trace: `render.streaming.ingest` events with value field =
  delta length. Cluster of 100+ value events arriving inside
  the same 16 ms tick = bursty backend; long gaps with no events but
  `ui.chat.row.body` firing = re-renders without new content.
- Existing `stream-perf` Logger lines in `console.ndjson` give the
  per-message timings the StreamingFade pipeline already records.

### High idle CPU when nothing is happening

- Hypothesis: a TimelineView still animating, a publisher still
  ticking, or a polling loop forgot to stop.
- Capture: `bash macos/scripts/perf-capture.sh --template "Time Profiler" --name idle-cpu`.
- Look at: `Diagnostics-*/last-resources.json` `processCpuPercent` and
  the per-second `resource.cpu_pct` signposts: a busy idle is anything
  > ~5% on an unused window.
- In the trace: Time Profiler heaviest stack will name the offender
  directly. Most likely culprits are TimelineView animations not
  collapsing once `streamingFinished == true`, or `objectWillChange`
  taps without throttling.

## Decisions encoded by this system

- **Always capture a trace first.** Never propose changes from
  reading code alone. The hot paths in a SwiftUI app shift between
  releases of macOS; static reading is wrong as often as right.
- **One taxonomy.** New signposts go through `PerfSignpost`, not
  ad-hoc `os_signpost(.event)`. If a category does not fit, add it
  here first.
- **Bundle id never hardcoded.** `Bundle.main.bundleIdentifier` at
  runtime, so a fork building with its own id gets isolated logs and
  diagnostics dirs.
- **Output directory follows the bundle id.** Diagnostics live under
  `~/Library/Application Support/<bundleId>/Diagnostics/`. The
  capture script copies any directory there matching `*lawix*` so a
  release vs dev launch don't get mixed.
- **`/tmp/clawix-renders.log` is the only file diagnostic that
  predates this system.** Left as-is so existing readers keep
  working; the capture script copies it into the trace directory.

## Updating this file

When you discover a new symptom, add a row to the table. When you
move a function the table points at, update its `file:line`. When
you add a signpost category, add it to the taxonomy table AND
register it in `Signposts.swift`. Treat this file like the
`PerfSignpost` enum — both are the contract that lets the next agent
pick up cold without re-deriving the playbook.
