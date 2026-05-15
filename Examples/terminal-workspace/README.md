# Terminal Workspace Example

This example demonstrates the first-class terminal workspace surface:
tabs, split panes, retained terminal sessions, visible active-pane chrome,
workspace commands, and layout persistence.

Run it from the repo root:

```bash
swiftly run swift run --package-path Examples/terminal-workspace terminal-workspace
```

Useful controls:

- `Ctrl+K`: command palette
- `Alt+H/J/K/L` or `Alt+Arrow`: move focus
- `Alt+V`: split the focused pane right
- `Alt+S`: split the focused pane down
- `Alt+T`: create a new shell tab
- `Alt+Z`: zoom or unzoom the focused pane
- `Alt+X`: close the focused pane

The example persists layout and command metadata to
`~/.swift-tui-terminal-workspace.json`. It intentionally restores fresh
processes on launch; detach/reattach is future workspace-session work.

## Test

```bash
swiftly run swift test --package-path Examples/terminal-workspace
```

The focused test pins the initial dev/ops workspace shape and pane identifiers
so the example remains useful as the workspace product evolves.
