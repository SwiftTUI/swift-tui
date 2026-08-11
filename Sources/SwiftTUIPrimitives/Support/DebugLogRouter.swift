import Synchronization

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

/// Central router for the framework's env-gated debug output.
///
/// Every diagnostic stream (graph traces, the frame-pipeline trace, the CLI
/// diagnostics TSV, profiling sinks) resolves its destination and writes its
/// bytes through this one type, so the append-file plumbing, the stderr
/// fallback, and the WASI compile-out seam exist in exactly one place.
///
/// Destination resolution, most-specific first:
/// 1. an explicit per-stream file override (`SWIFTTUI_*_FILE`, or a
///    path-valued variable like `SWIFTTUI_FRAME_TRACE`),
/// 2. `SWIFTTUI_DEBUG_DIR/<bundleFileName>` — the debug-bundle directory,
/// 3. `nil` — the caller's historical stderr behavior.
///
/// The bundle directory comes from `SWIFTTUI_DEBUG_DIR`, or from
/// ``installDefaultDebugDirectory(_:)`` when the runtime arms a default
/// bundle for `--debug` / `SWIFTTUI_DEBUG=1`. The explicit variable always
/// wins over an installed default. The directory is created (best-effort,
/// recursive) the first time a stream resolves into it; on failure the
/// stream falls back to stderr rather than dropping output.
package enum DebugLogRouter {
  package static let debugDirectoryEnvironmentVariableName = "SWIFTTUI_DEBUG_DIR"

  /// `SWIFTTUI_DEBUG_DIR` as read from the process environment (latched,
  /// trailing slashes trimmed, empty treated as unset).
  package static let environmentDebugDirectory: String? = normalizedDirectory(
    FeatureFlags.environmentValue(named: debugDirectoryEnvironmentVariableName)
  )

  private static let installedDefaultDirectory = Mutex<String?>(nil)
  private static let preparedDirectories = Mutex<Set<String>>([])

  /// Installs a session-default bundle directory (the `--debug` umbrella).
  /// A no-op when `SWIFTTUI_DEBUG_DIR` is set — the explicit variable wins —
  /// or when a default was already installed. Returns the directory that is
  /// active after the call, or `nil` when none could be resolved.
  @discardableResult
  package static func installDefaultDebugDirectory(_ path: String) -> String? {
    if let environmentDebugDirectory {
      return environmentDebugDirectory
    }
    guard let normalized = normalizedDirectory(path) else {
      return activeDebugDirectory()
    }
    installedDefaultDirectory.withLock { installed in
      if installed == nil {
        installed = normalized
      }
    }
    return activeDebugDirectory()
  }

  /// The bundle directory debug streams resolve into, or `nil` when neither
  /// `SWIFTTUI_DEBUG_DIR` nor a runtime default is active.
  package static func activeDebugDirectory() -> String? {
    environmentDebugDirectory ?? installedDefaultDirectory.withLock { $0 }
  }

  /// Test seam: clears an installed session-default directory so router tests
  /// leave no process-global state behind. The `SWIFTTUI_DEBUG_DIR` latch is
  /// unaffected (it is unset in test processes).
  package static func resetInstalledDefaultDirectoryForTesting() {
    installedDefaultDirectory.withLock { installed in
      installed = nil
    }
  }

  /// Resolves where a diagnostic stream writes: explicit `override` file,
  /// else `<debug dir>/<bundleFileName>` (creating the directory on first
  /// use), else `nil` for stderr.
  package static func resolvedFilePath(
    override: String?,
    bundleFileName: String
  ) -> String? {
    if let override, !override.isEmpty {
      return override
    }
    guard let directory = activeDebugDirectory(), ensureDirectoryExists(directory) else {
      return nil
    }
    return directory + "/" + bundleFileName
  }

  /// Emits `message` to the file at `filePath` (created if missing) when one
  /// is configured and writable, otherwise to stderr.
  package static func emit(_ message: String, toFileAt filePath: String?) {
    #if !canImport(WASILibc)
      if let filePath, !filePath.isEmpty, appendToFile(message, at: filePath) {
        return
      }
    #endif
    writeToStandardError(message)
  }

  /// Appends `message` to `path`, returning `false` on any open/write
  /// failure. Compiled out on WASI, whose capability model makes path-based
  /// `open` a no-op (see `Standard.File`).
  @discardableResult
  package static func appendToFile(_ message: String, at path: String) -> Bool {
    #if canImport(WASILibc)
      return false
    #else
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
    #endif
  }

  package static func writeToStandardError(_ message: String) {
    #if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
      var message = message
      message.withUTF8 { buffer in
        guard let base = buffer.baseAddress, buffer.count > 0 else {
          return
        }
        _ = unsafe write(STDERR_FILENO, base, buffer.count)
      }
    #elseif canImport(WASILibc) || canImport(ucrt)
      unsafe message.withCString { cMessage in
        _ = unsafe fputs(cMessage, stderr)
      }
    #endif
  }

  /// Best-effort recursive `mkdir` for the bundle directory, attempted once
  /// per distinct path. Returns whether the directory exists (or plausibly
  /// exists) afterwards. Compiled out on WASI (no path-based file sink).
  private static func ensureDirectoryExists(_ path: String) -> Bool {
    #if canImport(WASILibc)
      return false
    #else
      let alreadyPrepared = preparedDirectories.withLock { prepared in
        prepared.contains(path)
      }
      if alreadyPrepared {
        return true
      }
      var partial = path.hasPrefix("/") ? "/" : ""
      for component in path.split(separator: "/") {
        partial += (partial.isEmpty || partial == "/") ? String(component) : "/" + component
        let result = unsafe partial.withCString { pathPointer in
          unsafe mkdir(pathPointer, 0o755)
        }
        if result != 0, errno != EEXIST {
          return false
        }
      }
      preparedDirectories.withLock { prepared in
        _ = prepared.insert(path)
      }
      return true
    #endif
  }

  private static func normalizedDirectory(_ raw: String?) -> String? {
    guard var value = raw, !value.isEmpty else {
      return nil
    }
    while value.count > 1, value.hasSuffix("/") {
      value.removeLast()
    }
    return value.isEmpty ? nil : value
  }
}
