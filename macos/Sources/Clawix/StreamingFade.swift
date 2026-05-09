import SwiftUI
import os

// Streaming fade-in for assistant text. The unit of animation is the
// WORD: every word ramps from opacity 0 → 1 over `duration`. Words are
// scheduled with a leaky-bucket stagger so a bursty delta (one chunk
// dumping ten words at once) is replayed left-to-right at a stable
// pace, giving the answer a "typing" feel even when the backend
// streams in spikes. When the stream goes idle the queue empties on
// its own and the next delta starts a fresh schedule from `now`.

/// Toggle to surface streaming-pipeline timing in the dev log. Flip to
/// `false` once we've root-caused the perceived slowness; the logs are
/// noisy and shouldn't ship enabled.
let streamingPerfLogEnabled = false
let streamingPerfLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clawix", category: "stream-perf")

enum StreamingFade {
    /// How long a word takes to ramp from invisible to fully opaque.
    static let duration: Double = 0.22

    /// Minimum gap between consecutive words' fade-start times. A delta
    /// carrying N words spreads them across N · stagger seconds; deltas
    /// that arrive farther apart than this gap don't queue (each starts
    /// at its arrival time). Tuned tight enough that a burst feels like
    /// the natural stream pace rather than a forced metronome.
    static let stagger: Double = 0.008

    /// Opacity for the character at `offset` in the streamed string.
    /// Characters past the last scheduled word (i.e. a trailing partial
    /// word still waiting for its closing whitespace) read as fully
    /// transparent so they don't pop in mid-word.
    ///
    /// Checkpoints arrive sorted by `prefixCount` (the schedule writes
    /// them in append order with monotonically growing prefixes), so the
    /// "first prefixCount > offset" lookup is a binary search. Critical
    /// because this runs once per atom per animation frame: with 500
    /// atoms at 120Hz a linear scan over 500 checkpoints stalls the
    /// streaming pipeline.
    static func opacity(
        offset: Int,
        checkpoints: [StreamCheckpoint],
        now: Date
    ) -> Double {
        guard !checkpoints.isEmpty else { return 1.0 }
        var lo = 0
        var hi = checkpoints.count
        while lo < hi {
            let mid = (lo &+ hi) >> 1
            if checkpoints[mid].prefixCount > offset {
                hi = mid
            } else {
                lo = mid &+ 1
            }
        }
        guard lo < checkpoints.count else {
            // Past the last scheduled word → still pending, hide it.
            return 0.0
        }
        let stamp = checkpoints[lo].addedAt
        let elapsed = now.timeIntervalSince(stamp)
        if elapsed <= 0 { return 0.0 }
        if elapsed >= duration { return 1.0 }
        let t = elapsed / duration
        return 1.0 - pow(1.0 - t, 2.0)
    }

    /// Whether the renderer still has work to do this frame: either a
    /// scheduled word is mid-ramp, or the stream isn't finished yet so
    /// new deltas / new schedules may still land.
    static func isAnimating(
        checkpoints: [StreamCheckpoint],
        finished: Bool,
        now: Date
    ) -> Bool {
        if !finished { return !checkpoints.isEmpty }
        guard let last = checkpoints.last else { return false }
        return now.timeIntervalSince(last.addedAt) < duration
    }

    struct ScheduleResult {
        let newCheckpoints: [StreamCheckpoint]
        let pendingTail: String
    }

    /// Walks `pendingTail + delta` and emits one `StreamCheckpoint` per
    /// complete word (non-whitespace followed by whitespace), with
    /// leaky-bucket spacing so a burst still reads as typing. The new
    /// pending tail (the trailing partial word, or `""` if nothing is
    /// outstanding) comes back so the caller can hand it to the next
    /// delta. This is O(pendingTail + delta) per call; the caller
    /// avoids the previous O(content) reparse on every token.
    static func ingest(
        delta: String,
        pendingTail: String,
        scheduledLength: Int,
        lastFadeStart: Date,
        flush: Bool = false,
        now: Date = Date()
    ) -> ScheduleResult {
        PerfSignpost.renderStreaming.event("ingest", delta.count)
        let combined = pendingTail + delta
        var checkpoints: [StreamCheckpoint] = []
        var i = combined.startIndex
        var iCount = 0
        var fadeStart = lastFadeStart
        let endIdx = combined.endIndex

        while i < endIdx {
            var j = i
            var jCount = iCount
            // Leading whitespace (rare except at the very start) rides
            // with the next word.
            while j < endIdx, combined[j].isWhitespace {
                j = combined.index(after: j); jCount += 1
            }
            if j == endIdx {
                // Pure whitespace tail.
                if flush {
                    let nextSlot = max(now, fadeStart.addingTimeInterval(stagger))
                    checkpoints.append(StreamCheckpoint(
                        prefixCount: scheduledLength + jCount, addedAt: nextSlot
                    ))
                    fadeStart = nextSlot
                    i = j; iCount = jCount
                }
                break
            }
            // Word body.
            while j < endIdx, !combined[j].isWhitespace {
                j = combined.index(after: j); jCount += 1
            }
            if j == endIdx {
                // No closing whitespace yet → defer the partial word.
                if flush {
                    let nextSlot = max(now, fadeStart.addingTimeInterval(stagger))
                    checkpoints.append(StreamCheckpoint(
                        prefixCount: scheduledLength + jCount, addedAt: nextSlot
                    ))
                    fadeStart = nextSlot
                    i = j; iCount = jCount
                }
                break
            }
            // Trailing whitespace gets folded into the word so it owns
            // its own gap to the next word.
            while j < endIdx, combined[j].isWhitespace {
                j = combined.index(after: j); jCount += 1
            }
            let nextSlot = max(now, fadeStart.addingTimeInterval(stagger))
            checkpoints.append(StreamCheckpoint(
                prefixCount: scheduledLength + jCount, addedAt: nextSlot
            ))
            fadeStart = nextSlot
            i = j; iCount = jCount
        }

        let newPendingTail = i < endIdx ? String(combined[i..<endIdx]) : ""
        return ScheduleResult(newCheckpoints: checkpoints, pendingTail: newPendingTail)
    }
}

// MARK: - Atom source-offset mapping

/// Walks the parsed markdown structure in render order and assigns each
/// atom an approximate offset into the original source string. The
/// renderer hands that offset to `StreamingFade` so per-word ramps stay
/// aligned with the deltas the user typed.
///
/// The mapping uses `String.range(of:)` against the source from a moving
/// cursor, so it's tolerant of stripped formatting markers (`**bold**`
/// produces `"bold"` as the atom; we still find it in the source after
/// the `**`). On a miss (truncated source mid-stream, escape edge cases)
/// the resolver falls back to the cursor's current position, which keeps
/// the ramp roughly correct rather than crashing.
struct AtomOffsetResolver {
    private let source: String
    private var cursor: String.Index

    init(source: String) {
        self.source = source
        self.cursor = source.startIndex
    }

    /// Returns the offset (Character count from the start) where
    /// `needle` starts in the source, advancing the cursor past it. If
    /// the needle is empty, returns the cursor's current offset without
    /// moving it.
    mutating func locate(_ needle: String) -> Int {
        if needle.isEmpty {
            return source.distance(from: source.startIndex, to: cursor)
        }
        if let range = source.range(of: needle, range: cursor..<source.endIndex) {
            let offset = source.distance(from: source.startIndex, to: range.lowerBound)
            cursor = range.upperBound
            return offset
        }
        return source.distance(from: source.startIndex, to: cursor)
    }
}
