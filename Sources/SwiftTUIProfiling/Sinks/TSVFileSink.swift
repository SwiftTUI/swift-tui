@_spi(Runners) public import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Frame sink that appends one tab-separated record per frame to a file,
/// reincarnating the legacy `FrameDiagnosticsLogger`'s output on the neutral
/// ``FrameDiagnosticSink`` contract. The header row is written lazily before
/// the first record and each line is flushed immediately, so the file stays
/// current even if the process is killed.
///
/// File I/O is unavailable on WASI, where `init(path:)` fails just as the
/// legacy logger did.
@MainActor
@_spi(Runners) public final class TSVFileSink: FrameDiagnosticSink {
  private let fileDescriptor: Int32
  private let ownsDescriptor: Bool
  private var headerWritten = false

  @_spi(Runners) public init?(path: String) {
    #if !canImport(WASILibc)
      let fd = unsafe open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
      guard fd >= 0 else {
        return nil
      }
      fileDescriptor = fd
      ownsDescriptor = true
    #else
      fileDescriptor = -1
      ownsDescriptor = false
      return nil
    #endif
  }

  deinit {
    #if !canImport(WASILibc)
      if ownsDescriptor {
        close(fileDescriptor)
      }
    #endif
  }

  @_spi(Runners) public func record(_ sample: RuntimeFrameSample) {
    let record = FrameRecordDerivation.record(from: sample)
    if !headerWritten {
      writeLine(FrameDiagnosticsTSVFormatting.headerFields.joined(separator: "\t"))
      headerWritten = true
    }
    writeLine(FrameDiagnosticsTSVFormatting.fields(for: record).joined(separator: "\t"))
  }

  private func writeLine(_ line: String) {
    #if !canImport(WASILibc)
      guard ownsDescriptor else {
        return
      }
      var data = line + "\n"
      data.withUTF8 { buffer in
        _ = unsafe write(fileDescriptor, buffer.baseAddress, buffer.count)
      }
    #endif
  }
}
