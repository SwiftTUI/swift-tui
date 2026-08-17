@_spi(Runners) public import SwiftTUIRuntime
import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(ucrt)
  import CRT
#endif

/// Appends one tab-separated row per terminal write submission to a file, the
/// `presents.tsv` sibling of `frames.tsv`.
///
/// The frame row is emitted at commit, but the `write(2)` that puts its bytes
/// on the wire completes later on the presentation writer's queue. Rather than
/// delay the frame row, write completion lands here and joins back on `frame`.
///
/// Unlike ``TSVFileSink`` this is not main-actor-isolated: submission and
/// supersession are recorded on the main actor, completion on the writer
/// queue. A mutex guards the descriptor and the lazy header so rows from both
/// never interleave mid-line.
@_spi(Runners) public final class PresentationWriteTSVSink: PresentationWriteSink {
  @_spi(Runners) public static let headerFields = [
    "frame",
    "submitted_ms",
    "written_ms",
    "write_ms",
    "bytes",
    "outcome",
  ]

  private struct State {
    var headerWritten = false
  }

  private let fileDescriptor: Int32
  private let ownsDescriptor: Bool
  private let state = Mutex(State())

  @_spi(Runners) public init?(path: String) {
    #if !canImport(WASILibc)
      let descriptor = unsafe open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
      guard descriptor >= 0 else {
        return nil
      }
      fileDescriptor = descriptor
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

  @_spi(Runners) public func record(_ sample: PresentationWriteSample) {
    let writeDuration = sample.writtenAt.map { sample.submittedAt.duration(to: $0) }
    let row = [
      String(sample.frame),
      formatMs(sample.submittedAt.offset),
      sample.writtenAt.map { formatMs($0.offset) } ?? "-",
      formatMs(writeDuration),
      String(sample.bytes),
      sample.outcome.rawValue,
    ].joined(separator: "\t")

    state.withLock { state in
      if !state.headerWritten {
        writeLine(Self.headerFields.joined(separator: "\t"))
        state.headerWritten = true
      }
      writeLine(row)
    }
  }

  /// Milliseconds with two fractional digits, matching `frames.tsv`'s duration
  /// columns so the two files reduce with one parser.
  private func formatMs(_ duration: Duration?) -> String {
    guard let duration else {
      return "-"
    }
    let totalMicroseconds =
      duration.components.seconds * 1_000_000
      + duration.components.attoseconds / 1_000_000_000_000
    let milliseconds = totalMicroseconds / 1000
    let fraction = (totalMicroseconds % 1000) / 10
    return "\(milliseconds).\(fraction < 10 ? "0" : "")\(fraction)"
  }

  private func writeLine(_ line: String) {
    #if !canImport(WASILibc)
      guard ownsDescriptor else {
        return
      }
      var data = line + "\n"
      data.withUTF8 { buffer in
        guard let base = buffer.baseAddress, buffer.count > 0 else {
          return
        }
        _ = unsafe write(fileDescriptor, base, buffer.count)
      }
    #endif
  }
}
