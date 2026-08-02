# ``SwiftTUITerminalWorkspace``

Build tabbed and split-pane terminal workspaces above `TerminalView`.

## Overview

`SwiftTUITerminalWorkspace` is the first-party workspace layer. It provides
retained terminal sessions, tabs, split panes, directional focus, pane
commands, zoom, and serializable layout metadata.

For a multiplexer-like surface, use this product. For one embedded terminal
pane, use `SwiftTUITerminal` directly.

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
