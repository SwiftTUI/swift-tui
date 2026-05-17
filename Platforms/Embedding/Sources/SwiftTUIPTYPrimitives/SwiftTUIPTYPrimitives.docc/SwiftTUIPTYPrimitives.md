# ``SwiftTUIPTYPrimitives``

Open, resize, read, write, and close pseudo-terminal file descriptors.

## Overview

`SwiftTUIPTYPrimitives` is the low-level pty product used by terminal runners
and terminal-program embedding. Most apps should prefer `SwiftTUITerminal` or
`SwiftTUITerminalWorkspace`; import this product only when a custom integration
needs direct pty lifecycle control.

## Topics

### PTY Lifecycle

- ``PTYPair``
- ``PTYHandles``
- ``PTYError``
