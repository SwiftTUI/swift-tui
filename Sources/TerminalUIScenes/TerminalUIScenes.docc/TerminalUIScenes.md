# ``TerminalUIScenes``

Launch scene-based terminal apps and scale the runtime from one window to multiple independently attachable terminal scenes.

## Overview

`TerminalUIScenes` builds on top of `TerminalUI`.

It adds:

- public scene launch through ``MultiSceneLauncher``
- the default `App.main()` implementation for scene-based terminal apps
- scene manifests through ``TerminalUISceneManifest`` and ``TerminalUISceneDescriptor``
- wrapper-owned embedding through ``HostedSceneSession``
- pty-backed secondary scene sessions
- scene discovery over Unix-domain sockets
- attach flows for running scenes
- per-scene runtime isolation with shared application state where appropriate

The product is optional, but it currently carries the public launch helper for scene-based apps, including the single-window case.

## Topics

### Entry Point

- ``MultiSceneLauncher``
- ``HostedSceneSession``
- ``TerminalUISceneManifest``
- ``TerminalUISceneDescriptor``

### Runtime Architecture

- <doc:Multi-Scene-Architecture>
