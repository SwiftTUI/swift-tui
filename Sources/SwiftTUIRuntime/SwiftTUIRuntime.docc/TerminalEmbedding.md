# Terminal program embedding

Embed another program's terminal with `SwiftTUITerminalView` from the separate
[`swift-tui-terminal-view`](https://github.com/SwiftTUI/swift-tui-terminal-view)
package. Its [getting-started guide](https://swifttui.sh/docs/terminal-view/documentation/swifttuiterminalview/getting-started)
covers installation, sessions, key routing, host focus, and event modifiers.

The framework continues to own the terminal runner and presentation host.
`SwiftTUIPTYPrimitives` provides shared POSIX PTY plumbing, including
`ChildProcessPty`, for CLI attach and the embedding package.
