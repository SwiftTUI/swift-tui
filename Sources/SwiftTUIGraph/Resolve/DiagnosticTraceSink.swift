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

/// Shared output sink for the env-gated diagnostic traces (`ReuseDenialTrace`,
/// `InvalidationSourceTrace`). Routes a line to an optional append-file
/// (`…_FILE` env override) so the diagnostic is captured as a durable artifact,
/// otherwise to stderr. Inert/zero-cost unless a trace calls it.
@MainActor
enum DiagnosticTraceSink {
  /// Emits `message` to the file at `filePath` (created if missing) when one is
  /// configured and writable, otherwise to stderr.
  static func emit(_ message: String, toFileAt filePath: String?) {
    #if !canImport(WASILibc)
      if let filePath, !filePath.isEmpty, appendToFile(message, at: filePath) {
        return
      }
    #endif
    writeToStandardError(message)
  }

  #if !canImport(WASILibc)
    /// Appends `message` to `path` (opening it `O_CREAT | O_APPEND` each call so
    /// the destination stays dynamic and no descriptor is leaked). Returns
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

  /// Reads an environment variable, returning `nil` when unset.
  static func environmentValue(named name: String) -> String? {
    unsafe name.withCString { cName in
      guard let rawValue = unsafe getenv(cName) else {
        return nil
      }
      return unsafe String(cString: rawValue)
    }
  }
}
