# ``SwiftTUIPTYPrimitives``

Open, resize, read, write, and close pseudo-terminal file descriptors.

## Overview

`SwiftTUIPTYPrimitives` is the low-level pty product used by terminal runners
and terminal-program embedding. For most apps, use `SwiftTUITerminal`. Import
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
