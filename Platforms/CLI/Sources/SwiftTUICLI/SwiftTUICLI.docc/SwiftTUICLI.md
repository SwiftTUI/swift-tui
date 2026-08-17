# ``SwiftTUICLI``

Launch SwiftTUI apps in a terminal process.

## Overview

`SwiftTUICLI` starts SwiftTUI apps in a terminal process. It handles standard
CLI mode routing, scene discovery, attach flows, pty-backed secondary scenes,
and one-shot rendering.

The `SwiftTUI` convenience product launches the terminal through
`SwiftTUIWebHostCLI`. This also makes `--web` available by default. For a
terminal-only custom launch path around `SwiftTUIRuntime`, import
`SwiftTUICLI` directly.

This module is a compatibility facade over two halves, both re-exported so
one `import SwiftTUICLI` keeps serving the combined surface:

- `SwiftTUITerminalCLI` — the portable launch half: `TerminalRunner`,
  `TerminalRunnerError`, `RenderOnce`, `SignalReader`, and the `App.main()`
  entry points. Its reference documentation lives with that module.
- `SwiftTUICLIAttach` — the POSIX-only attach subsystem: `ScenePty`, the
  instance-discovery sockets, and the attach proxy. Its dependency edge is
  platform-conditional; on platforms without it, the attach-bearing verbs
  fail with a clear diagnostic while ordinary launches are unaffected.
