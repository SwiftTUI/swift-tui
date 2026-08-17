// SwiftTUICLI is a compatibility facade: Stage 2 of the Windows plan split
// the target into the portable launch half (SwiftTUITerminalCLI) and the
// POSIX-only attach half (SwiftTUICLIAttach). Existing `import SwiftTUICLI`
// consumers keep the combined surface unchanged.
@_exported import SwiftTUITerminalCLI

#if os(macOS) || os(iOS) || os(Linux) || os(Android)
  @_exported import SwiftTUICLIAttach
#endif
