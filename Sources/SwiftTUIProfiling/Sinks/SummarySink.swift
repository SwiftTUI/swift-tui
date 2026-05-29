import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#endif

/// Buffers per-signal observations and writes a reduced report to standard
/// error on ``finish()``: frame count and worst frame time, per-provider last
/// and max occupancy (the growth tell), and peak CPU/RSS.
@MainActor
package final class SummarySink: ProfileSink {
  private struct MemoryEntry {
    var last: Int
    var max: Int
    var lastBytes: Int?
  }

  private var frameCount = 0
  private var elidedFrameCount = 0
  private var maxFrameDurationSeconds = 0.0
  private var memoryByName: [String: MemoryEntry] = [:]
  private var cpuPeakPercent = 0.0
  private var cpuPeakResidentBytes = 0

  package init() {}

  package func emit(_ record: ProfileRecord) {
    switch record {
    case .frame(let frame):
      frameCount += 1
      if frame.elided { elidedFrameCount += 1 }
      maxFrameDurationSeconds = max(maxFrameDurationSeconds, seconds(frame.totalFrameDuration))
    case .memory(let snapshots):
      for snapshot in snapshots {
        var entry = memoryByName[snapshot.name] ?? MemoryEntry(last: 0, max: 0, lastBytes: nil)
        entry.last = snapshot.count
        entry.max = max(entry.max, snapshot.count)
        entry.lastBytes = snapshot.approxBytes
        memoryByName[snapshot.name] = entry
      }
    case .cpu(let sample):
      cpuPeakPercent = max(cpuPeakPercent, sample.estimatedCPUPercent)
      cpuPeakResidentBytes = max(cpuPeakResidentBytes, sample.maxResidentBytes)
    }
  }

  package func finish() {
    writeStandardError(report())
  }

  /// The reduced report text, exposed for testing.
  package func report() -> String {
    var lines = ["=== SwiftTUI profiling summary ==="]
    if frameCount > 0 {
      lines.append(
        "frames: \(frameCount) committed, \(elidedFrameCount) elided, worst total \(milliseconds(maxFrameDurationSeconds))"
      )
    }
    if !memoryByName.isEmpty {
      lines.append("memory occupancy (last / max):")
      for name in memoryByName.keys.sorted() {
        let entry = memoryByName[name] ?? MemoryEntry(last: 0, max: 0, lastBytes: nil)
        let bytes = entry.lastBytes.map { " (~\(humanBytes($0)))" } ?? ""
        let grew = entry.max > entry.last ? "" : (entry.max > 0 ? " [at peak]" : "")
        lines.append("  \(name): \(entry.last) / \(entry.max)\(bytes)\(grew)")
      }
    }
    if cpuPeakPercent > 0 || cpuPeakResidentBytes > 0 {
      lines.append(
        "cpu: peak \(Int(cpuPeakPercent.rounded()))%, rss peak \(humanBytes(cpuPeakResidentBytes))")
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private func seconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
  }

  private func milliseconds(_ seconds: Double) -> String {
    "\(Int((seconds * 1000).rounded()))ms"
  }

  private func humanBytes(_ bytes: Int) -> String {
    if bytes >= 1_048_576 {
      return "\(Int((Double(bytes) / 1_048_576).rounded()))MB"
    }
    if bytes >= 1024 {
      return "\(Int((Double(bytes) / 1024).rounded()))KB"
    }
    return "\(bytes)B"
  }

  private func writeStandardError(_ text: String) {
    #if !canImport(WASILibc)
      var text = text
      text.withUTF8 { buffer in
        guard let base = buffer.baseAddress, buffer.count > 0 else {
          return
        }
        _ = unsafe write(STDERR_FILENO, base, buffer.count)
      }
    #endif
  }
}
