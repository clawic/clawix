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
3. If the symptom is broad ("it feels slow") or you need before/after
   comparison, run the structured workout in another terminal while the
   trace is recording:
   ```
   bash macos/scripts/perf-workout.sh
   ```
   For focused investigations, use `--profile sidebar` or
   `--profile chat`.
4. The user reproduces the symptom inside the launched app, then
   quits / Ctrl-C the script. The script prints the trace directory.
5. Open `trace.trace` in Instruments and cross-reference with
   `capture-metadata.env`, `git-status.txt`, `console.ndjson`,
   `clawix-renders.log`, and `Diagnostics-*/` in the same directory.
6. Only then propose a fix, citing what the trace showed.

Never start optimizing without a trace. Guessing at hot paths in a
1000+ file project is how surface-level changes ship without moving
the needle.

Interface performance budgets are tracked by critical flow in
`../docs/ui/performance-budgets.json`. A budget becomes enforceable only after
the user approves the measured baseline. Until then, captures are evidence for
baseline approval, not permission to redesign or retune visible UI.

If the trace does not contain enough evidence to separate UI rendering,
state publication, IPC/daemon latency, backend latency, disk IO and
payload size, add instrumentation first and capture again. Do not fill
that gap with static code-reading guesses.

## Diagnostic stack overview

| Layer | Lives at | Always on? | What it gives |
| --- | --- | --- | --- |
| `RenderProbe` + `HitchProbe` | `Sources/Clawix/RenderProbe.swift` | yes | Per-window body re-eval counters and hitch buckets in `/tmp/clawix-renders.log` |
| `PerfSignpost` taxonomy | `Sources/Clawix/Diagnostics/Signposts.swift` | yes (suppressible via `CLAWIX_DISABLE_SIGNPOSTS=1`) | Categorised intervals/events visible in Instruments `os_signpost` track |
| `ResourceSampler` | `Sources/Clawix/Diagnostics/ResourceSampler.swift` | yes | RSS, footprint, %CPU once per second; emitted as signposts and dumped to `last-resources.json` on app exit |
| `HangDetector` | `Sources/Clawix/Diagnostics/HangDetector.swift` | DEBUG by default; `CLAWIX_FORCE_HANG_DETECTOR=1` to enable in release | Runloop-level main-thread stalls > `CLAWIX_HANG_MS` (default 250 ms) |
| `MetricKitObserver` | `Sources/Clawix/Diagnostics/MetricKitObserver.swift` | yes | Apple's own daily payloads (launch time, hitch ratio, hangs with backtraces, app exit reasons) |
| `streamingPerfLog` | `Sources/Clawix/StreamingFade.swift` | yes (toggle in source) | Streaming pipeline per-message timings via `Logger("stream-perf")` |
| `perf-workout.sh` phase markers | `scripts/perf-workout.sh` | manual | Repeatable phase boundaries in `/tmp/clawix-renders.log` for before/after comparisons |

All of the above land in one place when you run `perf-capture.sh`:

- `trace.trace` (Instruments)
- `capture-metadata.env` and `git-status.txt` (exact build, bundle,
  git revision and scenario captured)
- `reproduction-workout.txt` (repeatable phase-marker instructions)
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

## Evidence checklist

Every performance report should leave enough evidence for the next
agent to answer these questions without rerunning the same session:

- Which exact build was tested? Read `capture-metadata.env`, not memory.
- Which user phase was slow? Use `perf-workout.sh` markers or explicit
  manual marks in `clawix-renders.log`.
- Was the main thread blocked, over-rendering, waiting on IPC, decoding
  payloads, parsing markdown, loading images, doing disk IO, or just
  receiving bursty backend output?
- How large was the work? Record counts or payload sizes when a hot
  path depends on number of chats, messages, visible rows, bytes,
  attachments, cache misses, queue depth or streaming delta length.
- What changed after the fix? Compare the same profile before/after:
  same app mode, same data set, same phase durations, same template.

When an answer depends on a missing measurement, add the measurement
before changing behavior. The minimum useful measurement is usually a
`PerfSignpost` interval/event plus one size value, for example payload
bytes, row count, message count, cache hit/miss or queue depth.

## Known coverage gaps

- End-to-end bridge/backend latency is not yet fully decomposed. Add
  signposts around UI request creation, bridge send, daemon receive,
  backend response, state apply and first render before optimizing a
  cross-process bottleneck.
- Payload cardinality is only partially visible. For JSON-RPC frames,
  markdown parse work, chat hydration, attachment handling and image
  decode, add sizes/counts next to timing signposts when those paths
  become suspects.
- Phase boundaries currently live in `clawix-renders.log`, not as app
  signposts. That is good enough for repeatable render-log analysis.
  If Instruments correlation becomes the blocker, add a dedicated
  phase signpost category and an in-app/debug bridge emitter.

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

### Expanding heavy work summaries hitches

- Hypothesis: a completed `Worked for...` disclosure is mounting too
  much historical reasoning/tool timeline at once, recomputing tool
  presentation rows, or losing its scroll anchor while the inserted
  content changes height.
- Capture: `bash macos/scripts/perf-capture.sh --template "Animation Hitches" --name work-summary-expand --scenario "expand heavy Worked for summaries"`.
- While recording: `bash macos/scripts/perf-workout.sh --profile chat`
  and manually expand/collapse the longest `Worked for...` rows.
- Look at: `macos/Sources/Clawix/ChatView.swift` `MessageRow`
  timeline rendering, `AgentBackend/ToolGroupView.swift`, and
  `AgentBackend/ToolTimelinePresentation.swift`.
- In the trace: `ui.chat` should show bounded
  `timeline.entries.visible` values after the first expand, not the
  full timeline cardinality. `tool.snapshot.cache_hit` should dominate
  repeated expand/collapse. `hitch>250ms` in `clawix-renders.log`
  during normal expansion is a regression.

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

### Broad or unclear slowness

- Hypothesis: unknown. The first task is narrowing the phase, not
  optimizing.
- Capture: `bash macos/scripts/perf-capture.sh --template "os_signpost" --name broad-slow --scenario "<short description>"`.
- While recording: `bash macos/scripts/perf-workout.sh` in another
  terminal, or a narrower `--profile sidebar` / `--profile chat`.
- In the artifacts: start with `capture-metadata.env`, then slice
  `clawix-renders.log` by `MARK:` lines. The phase with elevated
  hitches, render counts, CPU, memory, decode or parse intervals
  decides the next, narrower capture template.
- If no phase shows the symptom, rerun with a manually tailored
  reproduction and explicit marks. Do not ship a fix from an
  inconclusive broad run.

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
