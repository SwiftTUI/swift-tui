# Multi-Scene Architecture

## Overview

Multi-scene TerminalUI applications are modeled as one primary scene plus zero or more secondary scenes.

The primary scene owns the inherited stdio terminal session. Secondary scenes are backed by ptys and can be attached to separately.

## Responsibilities

`TerminalUIScenes` is responsible for:

- collecting scene configurations from authored `WindowGroup`s
- launching a `SceneRuntime` per configuration
- exposing running scenes through a discovery socket
- letting clients list scenes or attach to a specific one

## Why It Is Separate

The scene-runtime layer is packaged separately so the core runtime can stay simpler:

- `TerminalUI` can stay focused on one-session terminal ownership
- multi-scene concerns such as ptys, sockets, and attachment do not leak into the single-session runtime APIs
- downstream apps can opt into the extra machinery only when they need it

## Related Symbol

- ``MultiSceneLauncher``
