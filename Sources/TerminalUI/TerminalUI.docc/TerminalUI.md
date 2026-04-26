# ``TerminalUI``

Render views, drive interactive terminal sessions, and connect the pure frame pipeline to a real terminal host.

## Overview

The `TerminalUI` module is the runtime-facing layer of TerminalUI.

Use it when you want to:

- resolve or render a `View` into inspectable frame artifacts
- run an interactive terminal session with `RunLoop`
- parse terminal input and signals
- present rasterized output with capability-aware ANSI rendering

`TerminalUI` re-exports `View` and `Core`, so importing `TerminalUI` is the normal entry point for most applications and examples.

## Runtime Story

`TerminalUI` has two main direct public entry paths:

- ``DefaultRenderer`` for one-shot rendering and frame inspection
- ``RunLoop`` for interactive sessions that own terminal I/O, scheduling, focus, lifecycle staging, and presentation

It also owns the shared scene-hosting APIs that peer platform integration
packages build on.

Scene declarations such as ``App`` and ``WindowGroup`` also live here, but
platform integration lives in peer packages: executable runner packages
`Runners/TerminalUICLI` and `Runners/TerminalUIWASI`, plus embedded host
packages `GUI/SwiftUITUIGUI`, `GUI/WebTUIGUI`, and `GUI/XtermWebTUIGUI`.
`TerminalUI` itself is library-only.

## Topics

### Rendering

- ``DefaultRenderer``
- ``TerminalSurfaceRenderer``
- ``TerminalCapabilityProfile``

### Interactive Runtime

- ``RunLoop``
- ``RunLoopResult``
- ``RunLoopExitReason``
- ``SignalReader``

### App And Scene Declarations

- ``App``
- ``Scene``
- ``SceneBuilder``
- ``WindowIdentifier``
- ``WindowGroup``

### Guide

- <doc:Running-Apps>
