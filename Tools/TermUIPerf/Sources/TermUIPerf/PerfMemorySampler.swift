import Dispatch
import Foundation
@_spi(Runners) import SwiftTUIProfiling

/// Polls occupancy providers on a fixed cadence during a scenario run and
/// formats the readings as a long-form `memory.tsv` (one row per sample ×
/// provider), so a leak shows up as a provider whose `count` slope is positive.
@MainActor
final class PerfMemorySampler {
  struct Sample {
    let elapsedSeconds: Double
    let snapshots: [ProfiledMemorySnapshot]
  }

  private(set) var samples: [Sample] = []
  private let startNanos = DispatchTime.now().uptimeNanoseconds

  private func tick() {
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startNanos) / 1_000_000_000
    samples.append(Sample(elapsedSeconds: elapsed, snapshots: ProfiledMemory.snapshot()))
  }

  func startSampling(interval: Duration) -> Task<Void, Never> {
    Task { @MainActor in
      while !Task.isCancelled {
        self.tick()
        do {
          try await Task.sleep(for: interval)
        } catch {
          break
        }
      }
    }
  }

  func tsv() -> String {
    var lines = ["elapsed_s\tprovider\tcount\tapprox_bytes"]
    for sample in samples {
      let elapsed = String(format: "%.3f", sample.elapsedSeconds)
      for snapshot in sample.snapshots {
        let bytes = snapshot.approxBytes.map(String.init) ?? "-"
        lines.append("\(elapsed)\t\(snapshot.name)\t\(snapshot.count)\t\(bytes)")
      }
    }
    return lines.joined(separator: "\n") + "\n"
  }
}
