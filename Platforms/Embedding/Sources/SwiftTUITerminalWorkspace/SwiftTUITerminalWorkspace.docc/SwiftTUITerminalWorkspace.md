# ``SwiftTUITerminalWorkspace``

Build tabbed and split-pane terminal workspaces above `TerminalView`.

## Overview

`SwiftTUITerminalWorkspace` is the first-party workspace layer for apps that
need retained terminal sessions, tabs, split panes, directional focus, pane
commands, zoom, and serializable layout metadata.

Use this product when an app needs a multiplexer-like surface. Use
`SwiftTUITerminal` directly for a single embedded terminal pane.

## Topics

### Workspace View

- ``TerminalWorkspaceView``

### State

- ``TerminalWorkspaceState``
- ``TerminalWorkspaceTab``
- ``TerminalWorkspaceNode``
- ``TerminalPaneSpec``
- ``TerminalWorkspaceSessionStore``

### Commands And Identity

- ``TerminalWorkspaceAction``
- ``TerminalPaneID``
- ``TerminalWorkspaceTabID``
- ``TerminalWorkspaceDirection``
- ``TerminalSplitAxis``

### Layout And Geometry

- ``TerminalSplit``
- ``TerminalWorkspaceLayout``
- ``TerminalWorkspacePaneFrame``
