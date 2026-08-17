@_spi(Runners) public import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(ucrt)
  import CRT
#endif

/// Frame sink that appends one tab-separated record per frame to a file,
/// reincarnating the legacy `FrameDiagnosticsLogger`'s output on the neutral
/// ``FrameDiagnosticSink`` contract.
/// The sink writes the header row before the first record.
/// It flushes each line immediately.
/// Thus, the file stays current if the process stops.
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
      #if canImport(ucrt)
        var fd: CInt = -1
        _ = unsafe _sopen_s(
          &fd, path, _O_WRONLY | _O_CREAT | _O_TRUNC | _O_BINARY, _SH_DENYNO,
          _S_IREAD | _S_IWRITE)
      #else
        let fd = unsafe open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
      #endif
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
        #if canImport(ucrt)
          _ = unsafe _write(fileDescriptor, buffer.baseAddress, UInt32(buffer.count))
        #else
          _ = unsafe write(fileDescriptor, buffer.baseAddress, buffer.count)
        #endif
      }
    #endif
  }
}
