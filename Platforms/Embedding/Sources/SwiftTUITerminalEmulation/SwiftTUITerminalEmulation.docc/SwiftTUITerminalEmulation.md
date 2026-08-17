# ``SwiftTUITerminalEmulation``

The SwiftTerm-backed emulation vocabulary for embedded terminal sessions.

## Overview

This module carries the emulator actor and the value types a terminal session
exchanges with it: keys, mouse events, and screen events. It is the only
SwiftTUI module that depends on SwiftTerm, so the POSIX-bound dependency stays
isolated in one place. `SwiftTUITerminal` re-exports this module, which keeps
`import SwiftTUITerminal` the single import an embedding app needs.

The module is POSIX-only: on Windows it compiles to an empty module alongside
the rest of the embedding stack.

## Topics

### Emulator

- ``TerminalEmulator``
- ``TerminalEmulatorEvent``
- ``TerminalBufferKind``
- ``TerminalMouseMode``

### Input vocabulary

- ``TerminalEmulatorKey``
- ``TerminalEmulatorMouse``
