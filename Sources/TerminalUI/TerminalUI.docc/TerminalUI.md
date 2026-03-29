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

`TerminalUI` has two main public entry paths:

- ``DefaultRenderer`` for one-shot rendering and frame inspection
- ``RunLoop`` for interactive sessions that own terminal I/O, scheduling, focus, lifecycle staging, and presentation

Scene declarations such as ``App`` and ``WindowGroup`` also live here, but the current public launch helper for scene-based apps is in the separate `TerminalUIScenes` product.

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
- ``WindowGroup``

### Guide

- <doc:Running-Apps>
