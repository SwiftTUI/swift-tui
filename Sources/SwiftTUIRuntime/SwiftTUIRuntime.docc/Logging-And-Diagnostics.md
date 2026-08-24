# Logging and Diagnostics

Where `print()` goes while SwiftTUI owns the terminal, and the screen-safe
ways to log, capture diagnostics, and observe runtime issues instead.

## Overview

An interactive SwiftTUI session takes over the terminal. The terminal host
puts the tty into raw mode and switches it to the alternate screen, and the
renderer presents every frame by writing escape sequences to standard
output. The framework never redirects or captures your process's standard
descriptors: while the session runs, stdout and stderr still point at the
very tty the frame is drawn on.

`print()` therefore misbehaves twice. Its bytes interleave with the
presentation writer's output — they can splice into the middle of an escape
sequence and they desynchronize the incremental-damage baseline the renderer
diffs against, so the corruption can outlive the frame that was on screen —
and they land on the *alternate* screen, so when the session ends and the
terminal restores the primary screen, whatever `print()` drew is gone.
Writing to standard error is unsafe for the same reason: fd 2 is the same
tty.

The rule: while the app owns the screen, keep every log byte off stdout and
stderr. The channels below stay safe.

## Log to a file from your app

Anything that keeps bytes off the tty is safe. The simplest reliable pattern
is appending to a log file and following it from a second terminal:

```swift
import Foundation

func log(_ message: String, path: String = "/tmp/myapp.log") {
  let url = URL(fileURLWithPath: path)
  let line = Data((message + "\n").utf8)
  if let handle = try? FileHandle(forWritingTo: url) {
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: line)
  } else {
    try? line.write(to: url)
  }
}
```

Then, in another terminal, `tail -F /tmp/myapp.log`. The same reasoning
extends to any logging backend: a file or system-log destination is safe; a
stderr-printing destination is not, until the session has ended. The danger
is bytes reaching the owned tty, so launching as `myapp 2>/tmp/myapp.log`
also makes ordinary stderr logging safe — the session needs stdin and
stdout, and never redirects stderr for you.

## Capture diagnostics with a debug bundle

The debug bundle is the framework's one-stop capture path: a single
directory that collects every armed diagnostic stream under a fixed name,
plus a `manifest.txt` recording the process id, the resolved configuration,
and which gates and traces were armed.

```bash
SWIFTTUI_DEBUG=1 SWIFTTUI_DEBUG_DIR=/tmp/myapp-debug myapp

# From another terminal, follow whatever lands in the bundle:
tail -F /tmp/myapp-debug/runtime-issues.log
```

`SWIFTTUI_DEBUG_DIR` names the directory explicitly. With `SWIFTTUI_DEBUG=1`
(or `--debug`) and no explicit directory, the runtime installs a default
bundle under `$TMPDIR`, and the terminal runner prints
`SwiftTUI debug bundle: <dir>` to stderr after teardown restores the primary
screen — including for sessions that end by throwing, which is exactly when
the bundle matters. Depending on what is armed, the bundle can contain
`frames.tsv`, `diagnostics.tsv`, `memo.log`, `reuse.log`, `inval.log`,
`soundness.log`, `profile.tsv`/`profile.jsonl`, and `runtime-issues.log`.
Bundles are unavailable on WASI, which has no path-based file sinks. See
<doc:Environment-Variables> for every variable involved.

## Runtime issues

The framework reports authored-state and runtime problems it detects while
resolving or presenting frames — a stale `ForEach` element binding, an
imperative `@State` access that observed the seed value, custom-layout
misuse — as *runtime issues*. Each is one line with a severity, a stable
code, an optional view path and source, and a message:

```
SwiftTUI runtime warning [forEach.staleElementBindingWrite] A ForEach
element binding for id 42 was written after its element left the collection;
the write was dropped.
```

Each distinct issue is reported once per session. The terminal runner routes
them screen-safely:

- With no owned screen, issues write to stderr immediately.
- While the session owns the screen and a debug bundle is armed, issues
  append to `runtime-issues.log` in the bundle.
- While the session owns the screen with no bundle, issues are held in a
  bounded buffer (256 lines, with a summary line counting any overflow) and
  flushed to stderr after teardown restores the primary screen.

So if warnings appear in your terminal right after the app exits, they were
raised during the session and deferred.

### Report your own issues

`RuntimeIssue` and `RuntimeIssueSink` are public, and the sink named
`standardError` is exactly the screen-aware router above, so your app can
put its own warnings through the same channel instead of hand-rolling the
deferral:

```swift
import SwiftTUI

@MainActor
func warnBadConfiguration(_ message: String) {
  RuntimeIssueSink.standardError.report(
    RuntimeIssue(
      severity: .warning,
      code: "myapp.configuration",
      message: message
    )
  )
}
```

### Observe issues from a host

A host product that retains scenes with ``HostedSceneSession`` can install
its own sink at construction and receive every reported issue on the main
actor:

```swift
let session = try HostedSceneSession(
  for: MyApp(),
  sceneID: sceneID,
  surface: surface,
  runtimeIssueSink: RuntimeIssueSink { issue in
    log(issue.description)
  }
)
```

Sessions driven through ``RunLoop`` directly expose the same channel as
``RunLoop/runtimeIssueSink``.

## Tracing the framework itself

`SWIFTTUI_TRACE` arms the framework's internal diagnostic streams by name
(`frames`, `memo`, `reuse`, `inval`, `soundness`, `publication`), writing
each into the debug bundle. You rarely need it day to day; for a bug report,
`SWIFTTUI_DEBUG=1` and attaching the announced bundle directory is usually
enough. The full grammar lives in <doc:Environment-Variables>.

## See Also

- <doc:Environment-Variables>
- <doc:Running-Apps>
- <doc:Host-Integration>
