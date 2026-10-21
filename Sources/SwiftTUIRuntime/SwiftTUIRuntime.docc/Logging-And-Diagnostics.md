# Logging and Diagnostics

Where `print()` goes while SwiftTUI owns the terminal, and the screen-safe
ways to log, capture diagnostics, and observe runtime issues instead.

## Overview

Live routing of runtime issues to a separate TTY and the body helpers below
were added after 0.18.3. They require a framework checkout or release containing
those APIs. Older releases can capture runtime issues in a debug bundle.

An interactive SwiftTUI session takes over the terminal. The terminal host
puts the tty into raw mode and switches it to the alternate screen, and the
renderer presents every frame by writing escape sequences to standard
output. The framework preserves your process's standard descriptors. By default, stdout
and stderr reach that same terminal. A `print()` or raw stderr write can splice
into presentation escape sequences and corrupt the frame; text on the alternate
screen also disappears when the app exits.

Keep logs off the presentation terminal. Redirect **only stderr**, use a debug
bundle, or use a system logger. The framework's body diagnostics and standard
runtime-issue sink check the actual stderr destination against every active
terminal session. A different TTY, file or pipe can receive those records live.
Ordinary `print()` still writes to stdout and has no such protection.

## Watch a separate debug terminal

These steps work with a debug terminal app on macOS or Linux.

In terminal **B**, discover its device and leave it open as a viewer:

```sh
tty
cat >/dev/null
```

Copy the device path printed by `tty`. In terminal **A**, substitute that exact
path below (device names differ by system and session):

```sh
DEBUG_TTY='/path/printed/by/tty'
myapp 2>"$DEBUG_TTY"
```

App input and presentation remain in A. Logs appear in B before the app exits.
`cat` simply keeps B's shell out of the way; it is not reading the logs from a
pipe. Press Control-C in B to return to its prompt; leaving the terminal window
open preserves the destination. A new terminal window may have a different
path, so rerun `tty` and relaunch the app after replacing the viewer.

For a repeatable check, put `Self._printChanges()` at the top of a counter's
body (the example below), then activate its Increment button in A. B shows an
initial `@identity` line and then a `state` cause. You can also report a
`RuntimeIssue` with the public sink shown below. For ordinary app logging,
configure your logging library's stderr sink; `print()` does not become stderr
logging just because the shell redirects fd 2.

With a debug bundle active, framework body diagnostics and runtime issues go
to the bundle first. Omit `--debug`, `SWIFTTUI_DEBUG`, and `SWIFTTUI_DEBUG_DIR`
when checking the direct-TTY workflow. Other opt-in framework traces retain
their own destination rules; use a bundle when enabling them.

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
stderr destination is safe when it has been redirected away from the owned
TTY. Launching as `myapp 2>/tmp/myapp.log` makes ordinary stderr logging safe — the session needs stdin and
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
`soundness.log`, `profile.tsv`/`profile.jsonl`, `runtime-issues.log`,
`changes.log` and `changes.jsonl`. Files appear lazily when their streams emit;
`--debug` selects a destination but does not add body helper calls for you.
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

The framework deduplicates each distinct issue once per session. Direct calls
to `RuntimeIssueSink.report` below are explicit reports and are not deduplicated
by the sink itself. The terminal runner routes
them screen-safely:

- An active bundle takes precedence, including when stderr is redirected.
- Otherwise, stderr receives issues immediately if it does not target an owned
  presentation terminal. Duplicate descriptors for an owned TTY stay protected.
- Unsafe, unknown or failed destinations use a bounded buffer (256 lines plus
  an overflow count), flushed after all terminal screens are restored. A slow
  or disconnected viewer does not block the app or terminate it with SIGPIPE.
  A failed flush keeps bounded evidence for a later flush; use a bundle for
  durable capture when the viewer may disappear.

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

## Explain body evaluations

Both `View` and `ViewModifier` provide `_printChanges()` and `_logChanges()`.
Import `SwiftTUIViews` in a view library, or `SwiftTUI` in a terminal app:

```swift
struct DebugCounter: View {
  @State private var count = 0

  var body: some View {
    let _ = Self._printChanges()
    let _ = Self._logChanges()
    VStack {
      Text("Count: \(count)")
      Button("Increment") { count += 1 }
    }
  }
}
```

Place helpers before property reads, including in `body(content:)` of a custom
modifier. Each call emits synchronously for that body's current evaluation.
Both methods describe the same causes. Reused bodies emit nothing; an evaluation
attempt may be cancelled, retried or discarded before any frame is presented.
Initial evaluations include `@identity`; an accepted counter write can name
`_count` with an exact `state` cause. Existing trusted input comparisons can
report `@self`. Environment reads can be exact; observation reports only the
owner, never an invented model property name. Unknown inputs, custom-property
updates and incomplete history explicitly report unavailable precision. Late
first use cannot reconstruct earlier reads. No application values are printed.

`_printChanges()` writes readable lines to `changes.log` in a bundle, otherwise
to safe stderr. `_logChanges()` writes the equivalent JSONL to `changes.jsonl`.
Without a bundle, Apple runtime hosts send structured records at info level to
the unified log under subsystem `sh.swifttui`, category `Changed Body Properties`:

```sh
log stream --level info --predicate 'subsystem == "sh.swifttui" AND category == "Changed Body Properties"'
```

Other hosts and standalone view-library consumers use stderr. Unsafe or failed
body output is suppressed with a bounded loss count, reported after terminal
teardown; it never falls back to stdout. The record schema is internal and may
change. Individual records are limited to 8 KiB and 64 causes; omitted evidence
is counted. Tracking is bounded to 4,096 bodies per graph, with uncertainty
reported after eviction. Build the **framework**, not just the app, with `DEBUG`
to enable the helpers. They remain callable and silent in release builds.

In a second terminal, follow a bundle with:

```sh
# Terminal A
SWIFTTUI_DEBUG_DIR=/tmp/myapp-debug myapp

# Terminal B; warnings about missing files stop when the first record arrives.
tail -F /tmp/myapp-debug/changes.log /tmp/myapp-debug/changes.jsonl /tmp/myapp-debug/runtime-issues.log
```

## Inspect a compiled browser app

Build a debug WASI app with the public web packaging tool:

```sh
npx swifttui-web build --package-path . --app MyBrowserApp --configuration debug
```

Use the WASI-safe `SwiftTUIRuntime`/`SwiftTUIWASI` products in that executable;
the `SwiftTUI` terminal umbrella is not a WASI dependency. The same View and
ViewModifier helper calls write text and JSONL through fd 2. No file bundle or
Apple logging API is used, and the stdout frame protocol remains separate.

The standard `@swifttui/web` host shows stderr in the scene's diagnostic panel
(`.webhost-scene__diagnostic`, capped at 16 KiB). Inspect that element in browser
developer tools or select its text to copy a capture. A custom bridge host can
capture `BrowserWASIOutputSink.writeError`; the standard host does not promise
console forwarding. Treat chunks as a stream and split complete newline records
when parsing JSONL. Release framework builds, bodies without calls and reused
bodies emit no body diagnostics. Static browser compilation is a separate
workflow from the terminal hot-reload loader below.

## Keep watching through hot reload

First follow <doc:Compiled-Hot-Reload> to build `swifttui-dev` and add the root
export to a debug app. The terminal loader supports macOS and Linux; it does
not reload WASI, native SwiftUI hosts or Android apps.

Use the same TTY path discovered in B, then launch from A:

```sh
DEBUG_TTY='/path/printed/by/tty'
.build/debug/swifttui-dev \
  --package-path /absolute/path/to/app --product MyApp \
  --event-log /tmp/myapp-reloads.jsonl \
  2>"$DEBUG_TTY"
```

Environment variables and stderr redirection reach the initial app and all
accepted generations. App arguments go after `--`. To use persistent bundle
files instead, launch with:

```sh
SWIFTTUI_DEBUG_DIR=/tmp/myapp-debug \
  .build/debug/swifttui-dev \
  --package-path /absolute/path/to/app --product MyApp \
  --event-log /tmp/myapp-reloads.jsonl
```

Increment the counter, then edit a visible label in the existing Swift source.
After the new generation is accepted, the label changes, compatible count state
survives, and the next Increment action produces another live body diagnostic.
A new generation can produce initial-identity diagnostics during root discovery
as well as evaluation; those records alone do not prove presentation.

There are three separate channels to watch:

| Channel | Destination |
| --- | --- |
| App stderr and portable body output | Redirected TTY/file, unless the framework stream chose a bundle |
| Framework runtime issues and bundle streams | Selected bundle files, otherwise safe stderr/deferred output |
| Driver/compiler/reload output | Announced private spool's `diagnostics.log`, plus optional event JSONL |

Copy the **actual** spool path announced at startup, then follow it from B
(or another terminal while B is the direct viewer):

```sh
tail -F /actual/announced/spool/diagnostics.log /tmp/myapp-reloads.jsonl
```

Temporarily introduce a syntax error in the edited source. The compiler error
appears in the spool, the event log records failure, and the prior app remains
interactive. Fix the source; the next accepted generation resumes the same
logging workflow. The spool is removed when the driver shuts down. Copy it
before shutdown if needed; choose a persistent path for `--event-log` and the
debug bundle when retaining evidence.

### Troubleshooting

- **No live output:** check B's current `tty`, stderr redirection, and bundle
  precedence. Check that the body actually executes and the framework is a
  debug build. Framework issues can be deduplicated; helper calls are not.
- **Permission denied or wrong terminal:** use a device owned by your user.
  Keep A's stdin/stdout attached to A; do not redirect all three descriptors.
- **Viewer closed or stalled:** framework diagnostics use bounded, nonblocking
  writes and count/defer failed output. Reopen the viewer and relaunch with its
  current device path, or use a bundle plus `tail -F`. Ordinary application
  stderr writers have their own error handling and are not intercepted.
- **Only reload events are visible:** compiler text is in the spool; a shell
  stderr redirect does not capture every diagnostic stream. On Apple hosts,
  `_logChanges()` without a bundle uses the unified log.
- **An edit requests a restart:** changes to dependencies, manifests, lockfiles,
  source-file membership, resources or the toolchain are outside in-process
  reload. Restart after those changes and after the driver's image limit.

## Tracing the framework itself

`SWIFTTUI_TRACE` arms the framework's internal diagnostic streams by name
(`frames`, `memo`, `reuse`, `inval`, `soundness`, `publication`), writing
each into the debug bundle. You rarely need it day to day; for a bug report,
`SWIFTTUI_DEBUG=1` and attaching the announced bundle directory is usually
enough. The full grammar lives in <doc:Environment-Variables>.

## See Also

- <doc:Compiled-Hot-Reload>
- <doc:Environment-Variables>
- <doc:Running-Apps>
- <doc:Host-Integration>
