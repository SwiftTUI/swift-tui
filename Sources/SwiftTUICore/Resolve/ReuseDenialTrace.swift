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

/// Diagnostic-only trace of **why retained reuse was denied** per node, gated by
/// `SWIFTTUI_REUSE_TRACE` (default off). Inert and zero-cost when disabled.
///
/// Each resolve pass that recomputes a node instead of reusing it records the
/// reason (suppressed / env-mismatch / dirty / invalidation-conflict / …); for
/// `env-mismatch` it also records which environment keys differ. ``ViewGraph``
/// dumps and resets the per-frame histogram to stderr at `beginFrame`, so the
/// stream shows one `[REUSE-TRACE]` line per frame. Used to find what re-resolves
/// the background on sheet/palette open.
@MainActor
package enum ReuseDenialTrace {
  package static let environmentVariableName = "SWIFTTUI_REUSE_TRACE"

  /// Optional file sink. When `SWIFTTUI_REUSE_TRACE_FILE` names a writable path,
  /// each `[REUSE-TRACE]` line is appended there instead of stderr. The trace is
  /// otherwise stderr-only, where it is easily lost among build/runtime output
  /// (this is why it was previously misread as silent on the release perf path).
  /// A file sink makes the diagnostic a durable, run-correlated artifact.
  /// `nil` keeps the historical stderr behavior. Settable for tests.
  package static let fileEnvironmentVariableName = "SWIFTTUI_REUSE_TRACE_FILE"

  package static var isEnabled: Bool = environmentDefault()

  /// Resolved once on first emit. When set, trace lines append to this path
  /// (created if missing); when `nil`, they go to stderr.
  package static var outputFilePath: String? = environmentValue(
    named: fileEnvironmentVariableName
  )

  package private(set) static var reasonCounts: [String: Int] = [:]
  package private(set) static var environmentKeyDiffCounts: [String: Int] = [:]
  package private(set) static var invalidatedIdentityPaths: Set<String> = []

  package static func record(_ reason: String) {
    guard isEnabled else { return }
    reasonCounts[reason, default: 0] += 1
  }

  package static func recordEnvironmentKeyDiff(_ key: String) {
    guard isEnabled else { return }
    environmentKeyDiffCounts[key, default: 0] += 1
  }

  /// Records the set of invalidated identity paths seen on a conflict (deduped),
  /// to reveal which dirty ancestor blocks the background's descendants.
  package static func recordInvalidatedIdentity(_ path: String) {
    guard isEnabled else { return }
    invalidatedIdentityPaths.insert(path)
  }

  package static func reset() {
    reasonCounts.removeAll(keepingCapacity: true)
    environmentKeyDiffCounts.removeAll(keepingCapacity: true)
    invalidatedIdentityPaths.removeAll(keepingCapacity: true)
  }

  /// Writes the accumulated histogram to stderr (if non-empty) and resets it.
  /// Called at `ViewGraph.beginFrame`, so each line summarizes the frame that
  /// just finished resolving.
  package static func dumpAndReset(frameID: UInt64) {
    guard isEnabled, !reasonCounts.isEmpty else {
      reset()
      return
    }
    var line = "[REUSE-TRACE] frame=\(frameID) recompute-reasons:"
    for (reason, count) in reasonCounts.sorted(by: { $0.value > $1.value }) {
      line += " \(reason)=\(count)"
    }
    if !environmentKeyDiffCounts.isEmpty {
      line += " | env-diffs:"
      for (key, count) in environmentKeyDiffCounts.sorted(by: { $0.value > $1.value }) {
        line += " \(key)=\(count)"
      }
    }
    if !invalidatedIdentityPaths.isEmpty {
      line += " | invalidated: " + invalidatedIdentityPaths.sorted().joined(separator: ",")
    }
    line += "\n"
    emit(line)
    reset()
  }

  /// Routes a trace line to the configured file sink when one is set and
  /// writable, otherwise to stderr (the historical behavior).
  private static func emit(_ message: String) {
    #if !canImport(WASILibc)
      if let path = outputFilePath, !path.isEmpty, appendToFile(message, at: path) {
        return
      }
    #endif
    writeToStandardError(message)
  }

  #if !canImport(WASILibc)
    /// Appends `message` to `path` (opening it `O_CREAT | O_APPEND` each call so
    /// `outputFilePath` stays dynamic and no descriptor is leaked). Returns
    /// `false` on any open/write failure so the caller can fall back to stderr.
    /// WASI's capability model makes path-based `open` a no-op, so the file sink
    /// is compiled out there (see `Standard.File`).
    private static func appendToFile(_ message: String, at path: String) -> Bool {
      let descriptor = unsafe path.withCString { pathPointer in
        unsafe open(pathPointer, O_WRONLY | O_CREAT | O_APPEND, 0o644)
      }
      guard descriptor >= 0 else {
        return false
      }
      defer { _ = close(descriptor) }
      var message = message
      return message.withUTF8 { buffer in
        guard let base = buffer.baseAddress, buffer.count > 0 else {
          return true
        }
        var offset = 0
        while offset < buffer.count {
          let written = unsafe write(
            descriptor,
            base.advanced(by: offset),
            buffer.count - offset
          )
          if written > 0 {
            offset += written
          } else if written == -1, errno == EINTR {
            continue
          } else {
            return false
          }
        }
        return true
      }
    }
  #endif

  private static func writeToStandardError(_ message: String) {
    #if canImport(Darwin) || canImport(Glibc) || canImport(Android)
      var message = message
      message.withUTF8 { buffer in
        guard let base = buffer.baseAddress, buffer.count > 0 else {
          return
        }
        _ = unsafe write(STDERR_FILENO, base, buffer.count)
      }
    #elseif canImport(WASILibc) || canImport(ucrt)
      unsafe message.withCString { cMessage in
        _ = fputs(cMessage, stderr)
      }
    #endif
  }

  private static func environmentDefault() -> Bool {
    guard let rawValue = environmentValue(named: environmentVariableName) else {
      return false
    }
    return !rawValue.isEmpty && rawValue != "0"
  }

  private static func environmentValue(named name: String) -> String? {
    unsafe name.withCString { cName in
      guard let rawValue = unsafe getenv(cName) else {
        return nil
      }
      return unsafe String(cString: rawValue)
    }
  }
}
