import Synchronization

#if canImport(Darwin)
  import Darwin
  import SwiftTUIPlatformIO
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(WASILibc)
  import WASILibc
#elseif canImport(ucrt)
  import CRT
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
  package enum FallbackPolicy { case legacyStandardError, safeStandardError }

  package static func emit(_ message: String, toFileAt filePath: String?) {
    _ = emit(message, toFileAt: filePath, fallback: .legacyStandardError)
  }

  /// Safe callers opt in to terminal protection and bounded nonblocking writes.
  /// Legacy trace destinations keep their established fallback behavior.
  @discardableResult
  package static func emit(
    _ message: String, toFileAt filePath: String?,
    fallback: FallbackPolicy,
    standardErrorDescriptor: Int32 = 2
  ) -> Bool {
    #if !canImport(WASILibc)
      if let filePath, !filePath.isEmpty,
        appendToFile(message, at: filePath, nonblocking: fallback == .safeStandardError)
      {
        return true
      }
    #endif
    if fallback == .safeStandardError {
      guard DiagnosticScreenOwnership.allowsDiagnosticWrite(to: standardErrorDescriptor) else {
        return false
      }
      return writeDiagnostic(message, to: standardErrorDescriptor)
    }
    writeToStandardError(message)
    return true
  }

  /// Appends `message` to `path`, returning `false` on any open/write
  /// failure. Compiled out on WASI, whose capability model makes path-based
  /// `open` a no-op (see `Standard.File`).
  @discardableResult
  package static func appendToFile(_ message: String, at path: String) -> Bool {
    appendToFile(message, at: path, nonblocking: false)
  }

  @discardableResult
  private static func appendToFile(_ message: String, at path: String, nonblocking: Bool) -> Bool {
    #if canImport(WASILibc)
      return false
    #elseif canImport(ucrt)
      // `open`/`_open` are variadic in ucrt and un-importable; `_sopen_s` is
      // the non-variadic form. `_O_BINARY` keeps appended bytes faithful —
      // the CRT's default text mode rewrites "\n" as "\r\n" on every `_write`.
      var descriptor: CInt = -1
      let openError = path.withCString { pathPointer in
        unsafe _sopen_s(
          &descriptor,
          pathPointer,
          _O_WRONLY | _O_CREAT | _O_APPEND | _O_BINARY,
          _SH_DENYNO,
          _S_IREAD | _S_IWRITE
        )
      }
      guard openError == 0, descriptor >= 0 else {
        return false
      }
      defer { _ = _close(descriptor) }
      var message = message
      return message.withUTF8 { buffer in
        guard let base = buffer.baseAddress, buffer.count > 0 else {
          return true
        }
        var offset = 0
        while offset < buffer.count {
          let written = unsafe _write(
            descriptor,
            base.advanced(by: offset),
            UInt32(buffer.count - offset)
          )
          guard written > 0 else {
            return false
          }
          offset += Int(written)
        }
        return true
      }
    #else
      let descriptor = path.withCString { pathPointer in
        unsafe open(
          pathPointer, O_WRONLY | O_CREAT | O_APPEND | (nonblocking ? O_NONBLOCK : 0), 0o644)
      }
      guard descriptor >= 0 else {
        return false
      }
      defer { _ = close(descriptor) }
      if nonblocking {
        if isatty(descriptor) == 1,
          !DiagnosticScreenOwnership.allowsDiagnosticWrite(to: descriptor)
        {
          return false
        }
        return writeDiagnostic(message, to: descriptor)
      }
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

  private static let diagnosticWriteLock = Mutex<Void>(())

  /// Best-effort delivery without waiting for a slow/disconnected viewer.
  /// Temporarily uses O_NONBLOCK, restoring the descriptor's flags; no change
  /// to process-wide signal dispositions. Callers retain/count failed output.
  package static func writeDiagnostic(_ message: String, to descriptor: Int32) -> Bool {
    diagnosticWriteLock.withLock { _ in
      #if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
        var info = stat()
        guard unsafe fstat(descriptor, &info) == 0 else { return false }
        if (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFIFO) {
          // A nonblocking pipe write at most PIPE_BUF bytes is all-or-none.
          // Drop oversized diagnostics instead of leaving a JSONL fragment.
          let atomicBytes = fpathconf(descriptor, Int32(_PC_PIPE_BUF))
          guard atomicBytes > 0, message.utf8.count <= atomicBytes else { return false }
        }
        #if !canImport(Darwin)
          let flags = fcntl(descriptor, F_GETFL)
          guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            return false
          }
          defer { _ = fcntl(descriptor, F_SETFL, flags) }
          var blocked = sigset_t()
          var original = sigset_t()
          var pending = sigset_t()
          _ = unsafe sigemptyset(&blocked)
          _ = unsafe sigaddset(&blocked, SIGPIPE)
          guard unsafe pthread_sigmask(SIG_BLOCK, &blocked, &original) == 0 else { return false }
          _ = unsafe sigpending(&pending)
          let wasPending = unsafe sigismember(&pending, SIGPIPE) == 1
          defer {
            // Consume a newly generated SIGPIPE before restoring the mask.
            if !wasPending {
              _ = unsafe sigpending(&pending)
              if unsafe sigismember(&pending, SIGPIPE) == 1 {
                var timeout = timespec(tv_sec: 0, tv_nsec: 0)
                _ = unsafe sigtimedwait(&blocked, nil, &timeout)
              }
            }
            _ = unsafe pthread_sigmask(SIG_SETMASK, &original, nil)
          }
        #endif
        var message = message
        return message.withUTF8 { bytes in
          guard let base = bytes.baseAddress else { return true }
          var offset = 0
          var interruptions = 0
          while offset < bytes.count {
            #if canImport(Darwin)
              let count = unsafe DarwinOutput.write(
                descriptor, base.advanced(by: offset), bytes.count - offset, nonBlocking: true)
            #else
              let count = unsafe write(descriptor, base.advanced(by: offset), bytes.count - offset)
            #endif
            if count > 0 {
              offset += count
            } else if count == -1, errno == EINTR, interruptions < 3 {
              interruptions += 1
            } else {
              return false
            }
          }
          return true
        }
      #elseif canImport(WASILibc)
        // WASI fd_write is the host's stderr bridge, never frame stdout.
        var message = message
        return message.withUTF8 { bytes in
          guard let base = bytes.baseAddress else { return true }
          return unsafe WASILibc.write(descriptor, base, bytes.count) == bytes.count
        }
      #elseif canImport(ucrt)
        var message = message
        return message.withUTF8 { bytes in
          guard let base = bytes.baseAddress else { return true }
          return unsafe _write(descriptor, base, UInt32(bytes.count)) == bytes.count
        }
      #else
        return false
      #endif
    }
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
      message.withCString { cMessage in
        _ = unsafe fputs(cMessage, stderr)
      }
    #endif
  }

  /// Best-effort recursive `mkdir` for the bundle directory. Recheck the leaf
  /// on each resolution: a previously prepared directory can have been removed
  /// between sessions. Compiled out on WASI (no path-based file sink).
  private static func ensureDirectoryExists(_ path: String) -> Bool {
    #if canImport(WASILibc)
      return false
    #else
      let leafResult = path.withCString { pathPointer in
        #if canImport(ucrt)
          unsafe _mkdir(pathPointer)
        #else
          unsafe mkdir(pathPointer, 0o755)
        #endif
      }
      if leafResult == 0 || errno == EEXIST { return true }
      guard errno == ENOENT else { return false }
      var partial = path.hasPrefix("/") ? "/" : ""
      for component in path.split(separator: "/") {
        partial += (partial.isEmpty || partial == "/") ? String(component) : "/" + component
        #if canImport(ucrt)
          // A bare drive designator ("C:") is not creatable — skip to its
          // children.
          if component.hasSuffix(":") {
            continue
          }
        #endif
        let result = partial.withCString { pathPointer in
          #if canImport(ucrt)
            unsafe _mkdir(pathPointer)
          #else
            unsafe mkdir(pathPointer, 0o755)
          #endif
        }
        if result != 0, errno != EEXIST {
          return false
        }
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
