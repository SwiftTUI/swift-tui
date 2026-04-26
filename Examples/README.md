# Examples

This directory keeps the maintained example apps and package shells.

- `gallery`: the primary terminal-native demo package and regression sandbox for the supported `View` surface
- `SwiftUIExample`: a host app plus terminal package that demonstrates embedding TerminalUI scenes in SwiftUI via `GUI/SwiftUITUIGUI` (native surface)
- `WebExample`: a host app plus terminal package that demonstrates the Bun + WASI browser path used by `GUI/WebTUIGUI`
- `XtermWebExample`: a Bun + WASI browser example that uses the xterm.js host package `GUI/XtermWebTUIGUI`

The older `todoist` and `scroll-diagnostic` example packages were removed once
their value was outweighed by maintenance cost and duplicated coverage.
