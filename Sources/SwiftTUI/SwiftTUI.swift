// The SwiftTUI target also defines `SwiftTUI.App`, the command-enabled
// convenience overlay for apps that use `import SwiftTUI`.
@_exported import SwiftTUIAnimatedImage
// Unconditional: the command-declaration surface (SwiftTUICommand,
// SwiftTUIOptions, ArgumentParser's property wrappers) is part of the
// batteries-included convenience on every platform. On POSIX the web CLI
// below re-exports the same module — a duplicate `@_exported` of one module
// is idempotent — but on platforms without the web CLI this is the only
// path, and without it `@Argument`/`ParsableCommand` vanish from
// `import SwiftTUI` (measured: the 28 entry-point-fixture errors on the
// Windows all-targets build).
@_exported import SwiftTUIArguments

// Exactly one launch surface is re-exported: the combined terminal/browser
// runner on native platforms and the portable CLI on other compilation targets.
// Exporting both would make App entry-point witnesses ambiguous. Keep this
// platform allowlist in step with the manifest rather than testing canImport.
#if os(macOS) || os(iOS) || os(Linux) || os(Android) || os(Windows)
  @_exported import SwiftTUIWebHostCLI
#else
  @_exported import SwiftTUITerminalCLI
#endif
