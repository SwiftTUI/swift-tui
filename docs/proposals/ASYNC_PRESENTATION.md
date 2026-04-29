# Async Terminal Presentation

## Status

Implemented for the POSIX terminal host.

For the consolidated async rendering status, see
[`../ASYNC_RENDERING.md`](../ASYNC_RENDERING.md). This file records only the
presentation-write layer; it does not cover frame-tail layout, draw, or raster
offload.

`TerminalHost.present(_:)` still runs the render-to-presentation planning step
on the caller's actor, but it no longer performs the potentially blocking
terminal write inline. The host now batches the planned output into one string
and submits it to a private `PresentationWriter`, which writes on a dedicated
serial `DispatchQueue`.

The remaining known limitation is error wakeup behavior: write failures are
observed by the next `present()`, `write()`, `drainPendingPresentation()`, or
`disableRawMode()` call. A failure that happens while the runtime is otherwise
idle is stored, but it does not currently wake the event loop immediately.

## Problem

The RunLoop's render path used to be synchronous through the terminal write:

```
event -> state mutation -> pipeline -> present(surface) -> write(2) -> next event
```

`present()` calls `TerminalPresentationPlanner.plan()` (cheap), then writes the
planned output to stdout. The write path issues direct `write(2)` syscalls and
handles `EAGAIN` by blocking with `poll()`. Over a slow pipe, SSH being the
common case, this can take milliseconds to tens of milliseconds and would block
the main actor from handling input events until the write completed.

Other hosts do not have the same last-mile constraint. On macOS and iOS, Core
Animation composites separately. On web, the WASI worker posts frames to the
browser. The POSIX terminal host is responsible for final display writes.

## Goals

- Keep the seven-phase rendering pipeline unchanged.
- Keep `TerminalHosting`'s public surface unchanged.
- Keep planning in `TerminalHost.present(_:)`.
- Move blocking `write(2)` work off the main actor.
- Drop intermediate frames when the terminal writer cannot keep up.
- Recover from dropped frames with a full repaint.

## Non-goals

- Parallelizing layout, draw, or rasterization.
- Changing `TerminalPresentationPlanner`.
- Process-level separation or tmux-style session persistence.
- Changing web, GUI, or streaming hosts.

---

## Current architecture

### Write path

```
RunLoop.renderPendingFrames()                             @MainActor
  renderer.render(...)           -> FrameArtifacts
  terminalHost.present(surface)                           @MainActor
    synchronizePresentationState()
    resolvedGraphicsCapabilities(...)
    imageRenderer.preparedSurface(...)
    TerminalPresentationPlanner.plan(prev, current)
      -> TerminalPresentationPlan
    bufferedOutput = render plan to String
    presentationWriter.submit(bufferedOutput)             returns immediately
    lastSubmittedSurface = preparedSurface

PresentationWriter                                        serial DispatchQueue
  controller.write(bufferedOutput, to: fd)
    -> write(2) loop, poll() on EAGAIN
```

Everything up to `submit(...)` is still synchronous. The blocking syscall loop is
the only part moved off the caller.

### Input path

Input already runs off the main actor:

```
InputReader (DispatchQueue / Task.detached)
  DispatchSource.makeReadSource(fd: 0)
  -> reads bytes, parses events
  -> yields to AsyncStream
RunLoop (MainActor)
  -> consumes stream via EventPump
```

Async presentation complements this path by keeping terminal output writes from
blocking input consumption.

### Capability queries

`TerminalHost` still performs terminal request-response queries synchronously:

1. Appearance queries run during `enableRawMode()`.
2. Graphics probing is lazy and runs on first presentation that needs image
   attachments.

Graphics probing cannot interleave with async presentation writes because the
probe sends query bytes to stdout and reads the response from stdin. Before the
first graphics probe, `present(_:)` drains any pending writer output. It then
runs the probe synchronously and submits the resulting presentation payload
after probing finishes.

---

## Implemented design

### `PresentationWriter`

`PresentationWriter` is a private, `Sendable` class in `TerminalHost.swift`.
It owns:

- the terminal controller,
- the output file descriptor,
- a serial `DispatchQueue`,
- a `Mutex`-protected state record containing the pending frame, write status,
  drop flag, and pending error.

It deliberately uses a serial queue instead of a Swift actor. The write loop can
block in `poll()`, and a queue-backed worker avoids occupying a cooperative
Swift executor thread while still keeping the main actor free.

```swift
private final class PresentationWriter: Sendable {
  private struct State: Sendable {
    var pending: PresentationFrame?
    var isWriting = false
    var didDropFrame = false
    var pendingError: TerminalHostError?
  }

  private let queue = DispatchQueue(label: "swift-terminal-ui.presentation-writer")
  private let state = Mutex(State())

  func submit(_ frame: PresentationFrame) {
    let shouldStart = state.withLock { state in
      guard state.pendingError == nil else {
        return false
      }
      if state.pending != nil {
        state.didDropFrame = true
      }
      state.pending = frame
      guard !state.isWriting else {
        return false
      }
      state.isWriting = true
      return true
    }

    guard shouldStart else {
      return
    }

    queue.async { [self] in
      writePendingFrames()
    }
  }
}
```

The queue drains frames in order, but the buffer holds only one pending frame.
If a new frame arrives while one frame is being written and another frame is
already pending, the pending frame is replaced and `didDropFrame` is set.

### Main actor state

`TerminalHost` tracks submitted presentation state in `PresentationSession`:

- `lastSubmittedSurface`
- `transmittedKittyImages`
- `forceFullRepaint`
- `writer`

The planner diffs against `lastSubmittedSurface`, not against a
writer-confirmed surface. This is optimistic tracking: once a frame is
submitted, the main actor treats that surface as the next baseline.

When the writer reports a dropped frame, or when the main actor sees that the
writer still has a queued pending frame before planning the next frame,
`PresentationSession.markDroppedFrame()` sets `forceFullRepaint = true` and
clears retained Kitty image state.

### Drop recovery

Frame dropping creates a possible baseline mismatch:

1. Frame 1 is being written.
2. Frame 2 is submitted and becomes pending.
3. Frame 3 is submitted before frame 2 is written, replacing frame 2.
4. A later incremental plan might otherwise diff against a surface the terminal
   never displayed.

The implementation recovers by forcing a full repaint as soon as the mismatch is
known. `synchronizePresentationState()` consumes the writer's drop flag and also
marks a drop if the writer still has a pending frame at the beginning of a new
presentation. That means the next planned payload is full repaint rather than a
known-invalid incremental diff.

Full repaint recovery also clears retained Kitty image bookkeeping, because a
terminal clear invalidates assumptions about which image placements are still
visible.

### Metrics

`present(_:)` still returns `TerminalPresentationMetrics` synchronously. The
metrics describe the planned payload, not confirmed write completion.

`bytesWritten` is the number of UTF-8 bytes in the payload submitted to the
writer. It does not mean the writer has already completed those bytes when
`present(_:)` returns. Write duration and confirmed byte counts are not part of
`TerminalPresentationMetrics`.

### Errors

The writer stores the first write error in `pendingError` and stops accepting new
frames until that error is consumed. `TerminalHost` consumes pending errors in:

- `present(_:)`, via `synchronizePresentationState()`,
- `drainPendingPresentation()`,
- `write(_:)`, because it drains before writing synchronously,
- `disableRawMode()`, after draining the writer.

This preserves the synchronous `throws` contract without changing
`TerminalHosting`, but error reporting may be delayed until the next host call.
The known remaining gap is idle failure wakeup: if the writer fails and no later
host call occurs, the stored error does not currently interrupt the event loop.

### Synchronous writes

Direct host writes still exist for raw-mode setup, raw-mode teardown, capability
queries, `clearScreen()`, `moveCursor(to:)`, and public `write(_:)`.

Before a direct public write, `TerminalHost.write(_:)` drains pending
presentation output and invalidates retained presentation state. That keeps
manual writes from being interleaved with queued frame output and prevents the
next incremental presentation from diffing against stale terminal contents.

---

## Frame lifecycle

### Normal case

```
1. Event arrives.
2. Main actor handles event, mutates state, and renders frame artifacts.
3. TerminalHost plans presentation output.
4. TerminalHost submits output to PresentationWriter and returns.
5. Main actor continues handling input/events.
6. PresentationWriter writes the payload to the terminal.
```

### Slow terminal

```
1. Writer is still writing frame 1.
2. Main actor submits frame 2; it becomes pending.
3. Main actor submits frame 3 before frame 2 is written.
4. Writer replaces pending frame 2 with frame 3 and sets didDropFrame.
5. Main actor observes the drop or pending-frame state before a later plan.
6. The later plan is forced to full repaint.
```

Intermediate frames are intentionally discarded. They represent stale UI state,
and keeping them would produce an unbounded backlog.

### Shutdown

```
1. RunLoop exit requested.
2. Main actor submits final frame if needed.
3. disableRawMode() captures the writer.
4. disableRawMode() drains the writer.
5. disableRawMode() consumes pending write errors.
6. Terminal reset bytes are written synchronously.
7. Input flags and termios attributes are restored.
```

Draining before terminal reset prevents queued frame output from racing with
cursor restore, bracketed-paste disable, or alternate-screen exit.

---

## Risks and mitigations

### Write error reporting delay

Write errors are detected on the writer queue, then observed by the main actor
on a later host call. This is acceptable for the current synchronous
`TerminalHosting` contract, where write errors are fatal and teardown also
checks the pending error.

If immediate failure handling becomes required, add a writer-to-run-loop wakeup
path so a stored error schedules the event loop to exit even when no further
presentation is pending.

### Full repaint tearing

After a dropped frame, recovery uses a full repaint. Large full repaint payloads
can visibly tear on terminals that do not support synchronized output.

When the capability profile supports synchronized output, full repaint payloads
are wrapped with `CSI ? 2026 h` / `CSI ? 2026 l`. This includes drop-recovery
full repaints.

### Repeated drops on very slow terminals

If the terminal is consistently slower than frame production, the host may
alternate between dropped frames and full repaint recovery. This is still
bounded: the queue never grows beyond one pending frame.

If this becomes common in practice, the next step is frame pacing based on
writer duration. That is an optimization; correctness does not depend on it.

### Capability probe latency

Graphics probing can still block the caller on first image presentation. That is
intentional: query/response bytes cannot be safely interleaved with queued frame
output. The host drains before the probe and caches the resulting capability
state.

---

## Validation

The focused regression surface is
`TerminalHostPresentationBatchingTests`.

Current coverage includes:

- full repaint output is batched into one write,
- incremental spans are batched into one write,
- damage-aware presentation still narrows incremental output,
- stale pending frames are dropped,
- drop recovery forces full repaint,
- replacement of a queued frame can force immediate full repaint,
- synchronized-output envelopes wrap drop-recovery full repaints when supported.

Useful commands:

```bash
swiftly run swift test --filter TerminalUITests.TerminalHostPresentationBatchingTests
bun run test
```

Run `bun run test` before considering changes to shared presentation behavior
complete.
