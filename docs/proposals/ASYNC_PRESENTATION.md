# Async Terminal Presentation

## Problem

The RunLoop's render path is synchronous on the main actor:

```
event → state mutation → pipeline → present(surface) → write(2) → next event
```

`present()` calls `TerminalPresentationPlanner.plan()` (cheap), then
`POSIXTerminalController.write()` (potentially expensive). The write path
issues direct `write(2)` syscalls to stdout, handling `EAGAIN` by blocking
with `poll()`. Over a slow pipe — SSH being the common case — this blocks the
main actor from handling input events until the write completes.

The other platforms don't have this problem. On macOS/iOS, Core Animation
composites on a separate process. On web, the WASI worker posts frames to the
browser's main thread. The terminal host is the only platform where the
framework is responsible for the last mile to the display.

## Goal

Move the terminal write path off the main actor so that the main actor can
return to handling input events immediately after producing a frame. Drop
intermediate frames when the write path can't keep up.

## Non-goals

- Changing the rendering pipeline. The 7-phase pipeline stays as-is.
- Changing the `TerminalHosting` protocol's public surface.
- Changing the `TerminalPresentationPlanner`. It already produces the right
  artifacts.
- Parallelizing the pipeline itself. Layout, draw, and raster still run
  synchronously on the main actor.
- Process-level separation (tmux-style session persistence). That's a
  different project.

---

## Current architecture (relevant pieces)

### Write path

```
RunLoop.renderPendingFrames()                          @MainActor
  renderer.render(...)        → FrameArtifacts
  terminalHost.present(surface)                        @MainActor
    TerminalPresentationPlanner.plan(prev, current)    pure, fast
      → TerminalPresentationPlan (strategy + spans)
    bufferedOutput = render plan to String              fast
    POSIXTerminalController.write(bufferedOutput)      BLOCKS on write(2)
      → write(2) loop, poll() on EAGAIN
    lastPresentedSurface = current                     bookkeeping
```

The blocking call is `write(bufferedOutput)` inside `present()`. Everything
before it is fast (microseconds). The write can take milliseconds to tens of
milliseconds depending on the pipe.

### Input path

Input already runs off the main actor:

```
InputReader (DispatchQueue / Task.detached)
  DispatchSource.makeReadSource(fd: 0)
  → reads bytes, parses events
  → yields to AsyncStream
RunLoop (MainActor)
  → consumes stream via EventPump
```

### Capability queries

`TerminalHost` issues synchronous OSC/CSI queries during `enableRawMode()`
and (for graphics) on-demand during `present()`. These are request-response
pairs on the terminal: write a query sequence to stdout, read the response
from stdin with a 40ms poll timeout.

These must remain synchronous — they happen before the run loop starts (at
initialization) or at first present (graphics probing). They cannot be
interleaved with async writes.

---

## Proposed design

### New type: `PresentationWriter`

A non-main-actor type that owns the terminal output file descriptor and
writes presentation plans to it. The `TerminalHost` creates it and feeds it
frames. The RunLoop doesn't know it exists.

```
┌─────────────────────────────┐    ┌──────────────────────────────┐
│         MainActor           │    │     PresentationWriter       │
│                             │    │     (off main actor)         │
│  event handling             │    │                              │
│  state mutation             │    │                              │
│  pipeline                   │    │                              │
│  plan = planner.plan(...)   │    │                              │
│  submit(plan, surface) ─────┼───>│  receive plan                │
│  (returns immediately)      │    │  write(2) bytes to fd        │
│  handle next event          │    │  update lastPresentedSurface │
│                             │    │                              │
└─────────────────────────────┘    └──────────────────────────────┘
```

### Responsibilities split

**Stays on main actor (`TerminalHost.present()`):**
- Call `TerminalPresentationPlanner.plan(previousSurface, currentSurface)`
- Render the plan to a `String` (or `[UInt8]`)
- Submit the rendered output + surface to the writer
- Return immediately

**Moves to `PresentationWriter`:**
- Own the output file descriptor (or a write-only wrapper)
- `write(2)` loop with `EAGAIN`/`poll()` handling
- Update `lastPresentedSurface` (needs to be communicated back or shared)
- Frame dropping when a newer frame arrives during a write

### Channel design

The channel between the main actor and the writer is a single-slot latest-
value buffer:

```swift
actor PresentationWriter {
    private let fd: Int32
    private var pending: PresentationFrame?
    private var isWriting: Bool = false

    func submit(_ frame: PresentationFrame) {
        pending = frame  // overwrites any unwritten frame
        if !isWriting {
            isWriting = true
            writePending()
        }
    }

    private func writePending() {
        while let frame = pending {
            pending = nil
            writeBytes(frame.output, to: fd)  // blocking write(2) — but on this actor, not main
        }
        isWriting = false
    }
}
```

When the main actor submits a frame:
- If the writer is idle, it begins writing immediately.
- If the writer is mid-write, the new frame replaces the pending slot. When
  the current write finishes, the writer picks up the latest frame and skips
  any intermediate ones.

This is natural frame dropping. If three frames arrive while one is being
written, only the most recent one is written next. The intermediate frames
are never presented — which is correct, because they represent stale state.

### The `lastPresentedSurface` problem

`TerminalPresentationPlanner.plan()` needs the previously presented surface
to compute incremental diffs. Today, `lastPresentedSurface` is updated
synchronously after `write()` completes. With async writes, the main actor
doesn't know which surface was last *actually written* to the terminal.

Two options:

**Option A: Optimistic tracking (recommended)**

The main actor maintains `lastPresentedSurface` as before — it updates it
immediately when submitting a frame, not when the write completes. The planner
diffs against the most recently *submitted* surface, not the most recently
*written* one.

This is correct because: if a frame is dropped (replaced by a newer one
before the writer got to it), the *next* frame's plan will be computed
against the dropped frame. The writer will then write that plan. But the
terminal still shows the *pre-drop* frame. The incremental diff is wrong —
it assumes the terminal shows the dropped frame, but the terminal shows the
frame before it.

This means: **after a frame drop, the next write must be a full repaint.**

The fix: the writer signals back when it drops a frame. The main actor marks
the next plan as needing a full repaint. This is cheap — full repaints are
already the fallback for surface size changes and first frames.

```swift
actor PresentationWriter {
    private(set) var didDropFrame: Bool = false

    func submit(_ frame: PresentationFrame) {
        if pending != nil {
            didDropFrame = true  // we're replacing an unwritten frame
        }
        pending = frame
        // ...
    }

    func consumeDropFlag() -> Bool {
        let dropped = didDropFrame
        didDropFrame = false
        return dropped
    }
}
```

On the main actor, before planning:

```swift
let forceFullRepaint = await writer.consumeDropFlag()
let previousSurface = forceFullRepaint ? nil : lastSubmittedSurface
let plan = planner.plan(previousSurface: previousSurface, currentSurface: newSurface)
```

Passing `nil` for `previousSurface` forces a full repaint, which is always
correct regardless of what the terminal currently shows.

**Option B: Writer-owned tracking**

The writer owns `lastPresentedSurface` and the planner runs on the writer
actor. This moves the planning step off the main actor too.

Upside: no "drop flag" coordination. The writer always knows what the
terminal actually shows and always computes correct diffs.

Downside: the `RasterSurface` must be sent to the writer actor for planning,
and the writer must own the planner. This moves more work off the main actor
than necessary. Planning is fast — it's the write that's slow.

**Recommendation: Option A.** It keeps the planning on the main actor where
it's simple, and handles frame drops with a one-bit signal. Frame drops are
uncommon (they require the terminal to be slower than the frame rate), and a
full repaint after a drop is cheap.

### Capability queries

Capability queries are synchronous request-response pairs that happen:
1. During `enableRawMode()` — before the run loop and before the writer
   exists. No conflict.
2. On-demand during `present()` for graphics probing — currently on first
   present.

For case 2: graphics probing must complete before the first frame is
submitted to the writer. The simplest approach is to probe eagerly during
`enableRawMode()` rather than lazily during `present()`. This is already
nearly the case — appearance queries run at enable time, and graphics queries
could be moved there.

If lazy probing is kept: the first call to `present()` runs the probes
synchronously (no frame has been submitted yet, so the writer has nothing to
do), then creates and starts the writer. Subsequent calls submit to the
writer.

### `TerminalHosting` protocol

The public protocol doesn't change. `present(_ surface:)` still returns
`TerminalPresentationMetrics` synchronously. The async write is an internal
implementation detail of `TerminalHost`.

For metrics: `present()` returns the metrics from the *planning* step (span
count, strategy, cells changed), not from the write step. These are available
immediately since planning runs on the main actor. Write-level metrics (bytes
written, write duration) would need to be reported separately if needed —
but they're not currently part of `TerminalPresentationMetrics`.

If `present()` needs to remain `throws` (it currently is, because `write(2)`
can fail): the main actor would check for write errors from the *previous*
frame's submission. If the writer encountered a write error, `present()`
throws it on the next call. This is a one-frame delay in error reporting,
which is fine — write errors are fatal (broken pipe) and the RunLoop will
exit.

---

## Changes by file

### `TerminalHost.swift`

- Add `PresentationWriter` as a private nested type or a package-internal
  type in the same file.
- `TerminalHost` gains a `private var writer: PresentationWriter?` created
  after capability probing completes.
- `present()` changes from: plan → render → write → update surface
  to: plan → render → submit to writer → update surface.
- Add `forceFullRepaint` flag, checked and cleared each frame.
- Move graphics capability probing to `enableRawMode()` (or keep lazy but
  ensure it completes before the writer is created).
- `disableRawMode()` drains the writer (waits for any in-flight write to
  finish before restoring terminal state).

### `POSIXTerminalController`

No changes. The write loop moves into `PresentationWriter`, but
`PresentationWriter` can call the controller's `write()` method or directly
use the same `platformWrite()` + `waitUntilWritable()` logic.

Alternatively: extract the write loop into a standalone function that both
the controller and the writer can call. This avoids duplicating the
`EAGAIN`/`EINTR`/`poll()` logic.

### `RunLoop+Rendering.swift`

No changes. `renderPendingFrames()` calls `terminalHost.present()` as before.
The async behavior is encapsulated inside `TerminalHost`.

### `DefaultRenderer`, `TerminalPresentationPlanner`, pipeline

No changes.

### `WebTerminalHost`

No changes needed. The web host already hands off to the browser's rendering
pipeline via message passing.

---

## Frame lifecycle under the new design

### Normal case (writer is idle)

```
1. Event arrives
2. Main actor: handle event → state mutation → pipeline → plan
3. Main actor: submit(plan, surface) to writer
4. Writer: immediately starts write(2)
5. Main actor: returns to event loop
6. Writer: write completes
7. (idle until next frame)
```

No observable difference from today, except the main actor is free during
step 6 instead of blocking.

### Slow terminal (writer is still writing)

```
1. Event arrives
2. Main actor: pipeline → plan → submit frame 2 to writer
   Writer: still writing frame 1
3. Event arrives
4. Main actor: pipeline → plan → submit frame 3 to writer
   Writer: still writing frame 1, frame 2 replaced by frame 3, drop flag set
5. Writer: finishes frame 1, picks up frame 3 (frame 2 was dropped)
6. Main actor: next present() sees drop flag → forces full repaint for frame 4
```

Frame 2 is never written to the terminal. Frame 3's plan may have been
computed as an incremental diff against frame 2, but the writer writes it
anyway — and then frame 4 gets a full repaint to correct any drift.

### Shutdown

```
1. RunLoop exit requested
2. Main actor: submits final frame (if any)
3. Main actor: calls disableRawMode()
4. disableRawMode(): awaits writer drain (writer finishes current write)
5. disableRawMode(): restores terminal state (show cursor, leave alt screen)
```

The drain ensures the last frame is fully written before the terminal is
restored. Without this, the terminal could show a partial frame momentarily
before the alt screen exits.

---

## Risks and mitigations

### Risk: write error reporting delay

Write errors (broken pipe, EIO) are detected one frame late — when the next
`present()` checks for errors from the previous submission.

**Mitigation:** Write errors are fatal. The RunLoop will exit on the next
`present()` call. One frame of delay before exit is acceptable. If immediate
detection is needed: the writer can signal an error via a shared atomic flag
that the RunLoop checks in its event loop, but this adds complexity for
minimal benefit.

### Risk: frame drop causes visible flash

After a frame drop, the next frame is a full repaint. If the repaint is
large, the terminal may briefly show a partially-written frame (tearing).

**Mitigation:** This already happens today for surface resizes. The
`TerminalHost` now wraps full repaint payloads in capability-gated
synchronized-output envelopes (`CSI ? 2026 h` / `CSI ? 2026 l`) when the
terminal supports them, which prevents tearing on supporting terminals
without changing incremental write semantics.

### Risk: actor hop latency

Submitting a frame to the writer actor requires a context switch. For frames
where the write would have been fast (small incremental update to a local
terminal), the actor hop adds overhead for no benefit.

**Mitigation:** The overhead is single-digit microseconds. The write is
at minimum a syscall (also microseconds). The difference is unmeasurable in
practice. If profiling shows it matters: the writer could be a simple
DispatchQueue + lock instead of a Swift actor, avoiding structured
concurrency overhead.

### Risk: `lastPresentedSurface` drift

The optimistic tracking model (Option A) assumes frame drops are uncommon and
recovers via full repaint. If the terminal is consistently slower than the
frame rate, every other frame triggers a full repaint.

**Mitigation:** This is self-correcting. Full repaints are more expensive to
write, which means the writer spends more time writing, which means more
frames are dropped, which means fewer writes total. The steady state is: one
full repaint, then one incremental, then one full repaint — alternating. This
is fine for a slow terminal. The alternative (sending every incremental diff
and falling behind) would be worse — it creates an unbounded backlog of stale
frames.

If this pattern is common enough to measure: the writer could report its
write duration, and the main actor could throttle frame production to match.
But this is optimization, not correctness.

---

## Implementation order

1. **Extract the write loop** from `POSIXTerminalController` into a
   standalone function (or keep it and let the writer call the controller).
   Verify nothing breaks — this is a pure refactor.

2. **Add `PresentationWriter`** as a package-internal actor. Give it
   `submit()`, `drain()`, and `consumeDropFlag()`. Write a test that submits
   frames faster than they can be written and verifies frame dropping.

3. **Move graphics probing** to `enableRawMode()` so it completes before the
   writer exists. Verify nothing breaks.

4. **Wire `TerminalHost.present()` to the writer.** Create the writer after
   probing completes. Submit frames instead of writing directly. Check the
   drop flag before planning. Drain on `disableRawMode()`.

5. **Test over SSH.** Introduce artificial write latency (e.g., pipe through
   `pv --rate-limit`) to verify frame dropping behavior, full-repaint
   recovery, and shutdown drain.

6. **Measure.** Compare input-to-display latency with and without the async
   writer on a local terminal. Verify the actor hop doesn't add measurable
   latency for the common (fast) case.
