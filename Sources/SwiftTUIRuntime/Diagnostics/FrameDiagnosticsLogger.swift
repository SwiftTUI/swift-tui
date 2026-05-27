import SwiftTUICore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Writes per-frame diagnostic records to a file as tab-separated values.
///
/// Activate by setting a `FrameDiagnosticsLogger` on the run loop before
/// calling `run()`. Records are flushed immediately so the file is always
/// up-to-date even if the process is killed.
@MainActor
public final class FrameDiagnosticsLogger {
  private let fileDescriptor: Int32
  private let ownsDescriptor: Bool
  private let recordHandler: ((FrameDiagnosticRecord) -> Void)?
  private var headerWritten = false

  /// Creates a logger that writes to the given file path.
  /// The file is created (or truncated) immediately.
  public init?(path: String) {
    #if !canImport(WASILibc)
      let fd = unsafe open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
      guard fd >= 0 else {
        return nil
      }
      fileDescriptor = fd
      ownsDescriptor = true
      recordHandler = nil
    #else
      // WASI builds have no POSIX file I/O exposed; the logger is unavailable.
      fileDescriptor = -1
      ownsDescriptor = false
      recordHandler = nil
      return nil
    #endif
  }

  /// Creates a logger that forwards each record to an in-process handler.
  public init(recordHandler: @escaping (FrameDiagnosticRecord) -> Void) {
    fileDescriptor = -1
    ownsDescriptor = false
    self.recordHandler = recordHandler
  }

  deinit {
    #if !canImport(WASILibc)
      if ownsDescriptor {
        close(fileDescriptor)
      }
    #endif
  }

  /// Records a single frame's diagnostics.
  public func log(_ record: FrameDiagnosticRecord) {
    if ownsDescriptor {
      if !headerWritten {
        writeHeader()
        headerWritten = true
      }

      writeLine(FrameDiagnosticsTSVFormatting.fields(for: record).joined(separator: "\t"))
    }

    recordHandler?(record)
  }

  private func writeHeader() {
    writeLine(FrameDiagnosticsTSVFormatting.headerFields.joined(separator: "\t"))
  }

  private func writeLine(_ line: String) {
    #if !canImport(WASILibc)
      var data = line + "\n"
      data.withUTF8 { buffer in
        _ = unsafe write(fileDescriptor, buffer.baseAddress, buffer.count)
      }
    #endif
  }

}
