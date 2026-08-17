// This whole module is compiled out on Windows: the dependency edges to
// SwiftTerm and the PTY layer are platform-conditional in Package.swift, so
// the target must compile to an empty module there.
#if !os(Windows)
  @_exported import SwiftTUIRuntime
  // Re-export the emulation layer so the Stage 1.2 target split is invisible
  // to consumers: `import SwiftTUITerminal` keeps serving TerminalEmulator,
  // TerminalEmulatorEvent/Key/Mouse, TerminalBufferKind, and
  // TerminalMouseMode.
  @_exported import SwiftTUITerminalEmulation
#endif
