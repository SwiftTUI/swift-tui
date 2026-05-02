---
adr: "0010"
title: "Crash guard lives in the CLI runner, not in SwiftTUI"
status: accepted
date: 2026-04-29
sources:
  - docs/RUNTIME.md
  - docs/HOST_PACKAGES.md
  - Vendor/UnixSignals
---

# ADR-0010: Crash guard lives in the CLI runner, not in SwiftTUI

## Context

A terminal-native app acquires the terminal's alternate-screen buffer,
puts the tty into raw mode, and disables echo. If the process crashes
without restoring those settings, the user is left in a broken shell —
no echo, no line editing, no cursor, possibly stuck in alternate
screen with no way back.

The framework needs a crash guard that:

- catches synchronous fatal signals (SIGABRT from
  `fatalError` / `preconditionFailure`, SIGSEGV, SIGBUS, SIGILL,
  SIGFPE, SIGTRAP),
- writes a pre-encoded reset sequence (disable mouse reporting, show
  cursor, reset style, exit alternate screen) using
  async-signal-safe `write(2)`,
- restores the saved termios via `tcsetattr`,
- re-raises the signal so the process still terminates with a
  diagnostic core dump.

The question is **which package owns this**.

POSIX signal handlers are a process-wide concept. They don't exist on
WASI. They're not a useful primitive for embedded SwiftUI hosts (the
host process's signal handlers belong to the host app). And they're
not a primitive for browser hosts at all.

## Decision

The crash guard lives in the **CLI runner package**
(`Runners/SwiftTUICLI`), not in the root `SwiftTUI` library.

`Runners/SwiftTUICLI/Sources/SwiftTUICLI/SceneRuntime.swift`
installs `CrashSignalHandler` from the vendored `UnixSignals` package
for the primary scene before the session enters raw mode. The guard:

- captures the pre-raw-mode termios from stdin,
- writes the reset escape sequence using `write(2)` (async-signal-safe),
- restores the saved termios via `tcsetattr` (practically safe on
  Darwin and Linux),
- re-raises the signal with the default handler so the process
  terminates normally with a core dump.

An alternate signal stack (`sigaltstack`) is installed so SIGSEGV from
stack overflow can still run the handler. The guard is removed when
the session ends normally.

## Status

Accepted. The crash guard ships in `SwiftTUICLI`'s
`SceneRuntime`. The root `SwiftTUI` library has no signal-handling
code paths.

## Consequences

**Enabled:**

- WASI builds (which have no signals) and browser hosts (which don't
  own signal handlers) link `SwiftTUI` cleanly without paying for
  POSIX signal infrastructure.
- The CLI runner is the single owner of process-global signal state.
  No conflict-resolution machinery is needed inside the library.
- Embedded SwiftUI / browser hosts that *do* own a real tty can
  install their own crash guard using the same vendored
  `UnixSignals` package without coordinating with SwiftTUI's
  internals.

**Foreclosed:**

- A consumer using `SwiftTUI` directly without a runner does not
  inherit a crash guard. They must install their own — which is the
  expected case for embedded hosts that own the tty themselves.
- The library does not expose a "register my crash guard" API. Signal
  handlers are inherently process-scoped, and only one scene can own
  the guard at a time. That ownership decision belongs to the runner.

**Known limitations (documented, not fixed):**

- SIGKILL and OOM-kill cannot be caught — the kernel terminates
  immediately.
- `tcsetattr` is not officially async-signal-safe per POSIX, though
  it is safe in practice on Darwin and Linux.
- The crash guard does not cover Windows.

**Discipline imposed:**

- New runner packages that own a tty (e.g. a future Android tty
  runner) must install their own crash guard or explicitly document
  why one is unnecessary.
- The root library's tests do not exercise the crash guard path —
  that coverage belongs to the runner package's tests.

The bet: process-global concerns belong to the package that owns the
process, not to the library that drives the view tree. Co-locating
ownership with responsibility is worth the small ergonomic cost of
two imports for terminal-native apps.
