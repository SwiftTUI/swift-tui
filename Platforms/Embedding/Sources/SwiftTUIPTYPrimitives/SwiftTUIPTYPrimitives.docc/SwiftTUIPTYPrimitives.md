# ``SwiftTUIPTYPrimitives``

Open, resize, read, write, and close pseudo-terminal file descriptors.

## Overview

`SwiftTUIPTYPrimitives` is the low-level pty product used by terminal runners
and terminal-program embedding. For terminal views, use `SwiftTUITerminalView` from the separate
[`swift-tui-terminal-view`](https://github.com/SwiftTUI/swift-tui-terminal-view)
package. Import
this product only if a custom integration needs direct pty lifecycle control.

## Topics

### Opening and Closing

- ``openPTY()``
- ``closeFD(_:)``

### PTY Lifecycle

- ``PTYPair``
- ``PTYHandles``
- ``PTYError``

### Resizing

- ``ptyResize(masterFD:cols:rows:)``

### Child processes

- ``ChildProcessPty``
