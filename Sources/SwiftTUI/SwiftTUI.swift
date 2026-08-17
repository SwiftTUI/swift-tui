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

// Exactly one launch surface is re-exported per platform (Stage 5.3 of the
// Windows plan, option (i)): the web CLI where it exists — byte-identical to
// the pre-split umbrella surface — and the portable terminal CLI otherwise.
// Exporting both would make the `App & SwiftTUICommand` entry-point
// extensions (`run()`, `main()`) ambiguous conformance witnesses.
//
// The condition is the platform mirror of the manifest's conditional-edge
// allowlist, not `canImport`: whole-file-guarded sibling modules still build
// (empty) on excluded platforms, so a stale module in the shared build
// directory makes `canImport` answer by build history, not by platform.
#if os(macOS) || os(iOS) || os(Linux) || os(Android)
  @_exported import SwiftTUIWebHostCLI
#else
  @_exported import SwiftTUITerminalCLI
#endif
