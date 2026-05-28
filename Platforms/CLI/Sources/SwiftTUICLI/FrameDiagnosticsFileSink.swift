@_spi(Runners) import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Writes per-frame diagnostics as tab-separated values to a file, for the
/// CLI's `TERMUI_DIAGNOSTICS` / `--debug` instrumentation. It derives the rich
/// record from the runtime's neutral ``RuntimeFrameSample`` and reuses the
/// shared TSV formatting, so the runtime carries no diagnostics logger of its
/// own. Apps that want richer profiling use `SwiftTUIProfiling`'s `.profiling()`.
@MainActor
final class FrameDiagnosticsFileSink: FrameDiagnosticSink {
  private let fileDescriptor: Int32
  private var headerWritten = false

  init?(path: String) {
    let descriptor = unsafe open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    guard descriptor >= 0 else {
      return nil
    }
    fileDescriptor = descriptor
  }

  deinit {
    close(fileDescriptor)
  }

  func record(_ sample: RuntimeFrameSample) {
    let record = FrameRecordDerivation.record(from: sample)
    if !headerWritten {
      writeLine(FrameDiagnosticsTSVFormatting.headerFields.joined(separator: "\t"))
      headerWritten = true
    }
    writeLine(FrameDiagnosticsTSVFormatting.fields(for: record).joined(separator: "\t"))
  }

  private func writeLine(_ line: String) {
    var data = line + "\n"
    data.withUTF8 { buffer in
      guard let base = buffer.baseAddress, buffer.count > 0 else {
        return
      }
      _ = unsafe write(fileDescriptor, base, buffer.count)
    }
  }
}
