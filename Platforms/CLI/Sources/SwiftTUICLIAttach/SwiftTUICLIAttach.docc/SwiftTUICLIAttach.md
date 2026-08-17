# ``SwiftTUICLIAttach``

The POSIX-only attach subsystem: PTYs, Unix sockets, and instance discovery.

## Overview

This module carries the machinery behind `myapp instances`, `myapp scenes`,
and `myapp attach`: the Unix-domain discovery socket each running app binds,
the client that finds and queries those sockets, the PTY wrapper secondary
scenes render into, and the raw-mode proxy that connects the attaching
terminal to that PTY.

It is POSIX-only — PTYs and Unix sockets have no Windows spelling here — and
its dependency edge from `SwiftTUITerminalCLI` is platform-conditional, so
the portable launch half compiles without it. Most apps import
`SwiftTUICLI`, the compatibility facade that re-exports both halves.

## Topics

### Attach sessions

- ``ScenePty``
