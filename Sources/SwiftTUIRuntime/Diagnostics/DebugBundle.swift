import SwiftTUICore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(WASILibc)
  import WASILibc
#endif

/// The session debug bundle: the `--debug` / `SWIFTTUI_DEBUG_DIR` umbrella.
///
/// A bundle is one directory that collects every armed diagnostic under a
/// fixed name (`frames.tsv`, `diagnostics.tsv`, `memo.log`, `reuse.log`,
/// `inval.log`, `soundness.log`, `profile.tsv` / `profile.jsonl`) plus a
/// `manifest.txt` recording what was armed — so "collect debug output" is one
/// variable and the whole directory is the support artifact.
///
/// `SWIFTTUI_DEBUG_DIR` names the directory explicitly. With `--debug` /
/// `SWIFTTUI_DEBUG=1` and no explicit directory, ``prepareIfNeeded(configuration:)``
/// installs a session default under `$TMPDIR` (or `/tmp`) and the CLI runner
/// prints the bundle path to stderr after the terminal is restored.
/// Unavailable on WASI (no path-based file sinks).
@MainActor
@_spi(Runners) public enum DebugBundle {
  /// The bundle directory this session prepared (installed default or
  /// explicit `SWIFTTUI_DEBUG_DIR` with the manifest written), or `nil` when
  /// no bundle is active.
  @_spi(Runners) public private(set) static var preparedDirectory: String?

  /// Arms the session bundle. Installs a default directory when
  /// `configuration.debug` is set and `SWIFTTUI_DEBUG_DIR` is not, then
  /// writes `manifest.txt` into whichever directory is active. Idempotent.
  @_spi(Runners) public static func prepareIfNeeded(configuration: RuntimeConfiguration) {
    #if !canImport(WASILibc)
      guard preparedDirectory == nil else {
        return
      }
      if configuration.debug, DebugLogRouter.activeDebugDirectory() == nil {
        DebugLogRouter.installDefaultDebugDirectory(defaultBundleDirectory())
      }
      guard configuration.debug || DebugLogRouter.environmentDebugDirectory != nil,
        let manifestPath = DebugLogRouter.resolvedFilePath(
          override: nil, bundleFileName: "manifest.txt"
        )
      else {
        return
      }
      guard DebugLogRouter.appendToFile(manifest(configuration: configuration), at: manifestPath)
      else {
        return
      }
      preparedDirectory = DebugLogRouter.activeDebugDirectory()
    #endif
  }

  /// Resolves a fixed-name file inside the active bundle, or `nil` when no
  /// bundle directory is active. Seam for runners (the CLI diagnostics TSV).
  @_spi(Runners) public static func bundleFilePath(named name: String) -> String? {
    DebugLogRouter.resolvedFilePath(override: nil, bundleFileName: name)
  }

  /// The one-line, post-teardown stderr announcement — `nil` when this
  /// session prepared no bundle.
  @_spi(Runners) public static func announcementLine() -> String? {
    preparedDirectory.map { directory in
      "SwiftTUI debug bundle: \(directory)\n"
    }
  }

  /// Test seam: clears the prepared-bundle latch. Pair with
  /// `DebugLogRouter.resetInstalledDefaultDirectoryForTesting()` so bundle
  /// tests leave no process-global state behind.
  @_spi(Runners) public static func resetForTesting() {
    preparedDirectory = nil
  }

  private static func manifest(configuration: RuntimeConfiguration) -> String {
    var lines: [String] = ["SwiftTUI debug bundle manifest"]
    #if !canImport(WASILibc)
      lines.append("pid: \(getpid())")
    #endif
    lines.append(
      "configuration: color=\(configuration.color.rawValue)"
        + " glyphs=\(configuration.glyphs.rawValue)"
        + " motion=\(configuration.motion.rawValue)"
        + " output=\(configuration.output.rawValue)"
        + " verbosity=\(configuration.verbosity.rawLevel)"
        + " debug=\(configuration.debug)"
        + " cursorFollowsFocus=\(configuration.cursorFollowsFocus)"
    )
    let gates = FeatureGate.allCases
      .map { gate in
        "\(gate.environmentVariableName)=\(gate.initialIsEnabled() ? "on" : "off")"
      }
      .joined(separator: " ")
    lines.append("gates: \(gates)")
    let selection = DebugTraceSelection.current.entries
      .map { entry in
        entry.sampleEveryNFrames.map { sample in "\(entry.name)@\(sample)" } ?? entry.name
      }
      .joined(separator: ",")
    lines.append("trace-selection: \(selection.isEmpty ? "(none)" : selection)")
    lines.append(
      "armed: memo-emission=\(MemoSkipTrace.emitsTraceLines)"
        + " reuse=\(ReuseDenialTrace.isEnabled)"
        + " inval=\(InvalidationSourceTrace.isEnabled)"
        + " soundness-trace=\(SoundnessProbeConfiguration.isTraceEnabled)"
        + " publication=\(RuntimeRegistrationPublicationDiagnosticsConfiguration.isEnabled)"
    )
    return lines.joined(separator: "\n") + "\n"
  }

  private static func defaultBundleDirectory() -> String {
    var base = FeatureFlags.environmentValue(named: "TMPDIR") ?? "/tmp"
    while base.count > 1, base.hasSuffix("/") {
      base.removeLast()
    }
    var name = "swifttui"
    if let executable = CommandLine.arguments.first {
      let basename = executable.split(separator: "/").last.map(String.init) ?? executable
      let sanitized = basename.filter { character in
        character.isLetter || character.isNumber || character == "-" || character == "_"
      }
      if !sanitized.isEmpty {
        name += "-" + sanitized
      }
    }
    #if !canImport(WASILibc)
      name += "-\(getpid())"
    #endif
    return base + "/" + name
  }
}
