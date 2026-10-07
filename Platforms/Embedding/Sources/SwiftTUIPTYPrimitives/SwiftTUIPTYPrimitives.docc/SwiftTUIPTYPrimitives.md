# ``SwiftTUIPTYPrimitives``

Open, resize, read, write, and close pseudo-terminal file descriptors.

## Overview

`SwiftTUIPTYPrimitives` is the low-level pty product used by terminal runners
and terminal-program embedding. For terminal views, use `SwiftTUITerminalView` from the separate
[`swift-tui-terminal-view`](https://github.com/SwiftTUI/swift-tui-terminal-view)
package. Import
this product only if a custom integration needs direct pty lifecycle control.

## Output backpressure

``PTYPair/read()`` remains a single-consumer `AsyncStream<[UInt8]>`. Its
unfolding iterator requests bytes from a lossless queue capped at **65,536
bytes**, plus at most one **4,096-byte** chunk handed to the consumer. Kernel
buffers and bytes retained by callers are separate. A stalled consumer stops
master reads so the child receives kernel backpressure. No timer polls an idle
or full PTY. Cancellation abandons queued output; `close()` releases the pair.
Normal EOF preserves queued bytes for the reader. Process exit defers closing
the retained slave until the kernel output tail has been read.

For opt-in diagnostics, set `SWIFTTUI_PTY_DIAGNOSTICS` to an existing writable
directory before constructing a pair. Each pair writes a `pty-<UUID>.tsv` file
with monotonic nanosecond timestamps, slave path, read/write chunk sizes, queued
bytes, oldest queued age and dequeued residence age. Ages start at the master
read; they exclude time waiting in the kernel. The sink records no terminal
contents. Logging is synchronous and adds overhead; measure acceptance latency
with the variable unset, and retain diagnostic runs separately. A missing or
unwritable directory disables tracing. The reader still enforces its byte cap.

## Topics

### Opening and Closing

- ``openPTY()``
- ``closeFD(_:)``

### PTY Lifecycle

- ``PTYPair``
- ``PTYHandles``
- ``PTYError``

### Resizing

- ``ptyResize(masterFD:cols:rows:)``

### Child processes

- ``ChildProcessPty``
