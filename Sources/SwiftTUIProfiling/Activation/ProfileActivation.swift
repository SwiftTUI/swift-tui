@_spi(Runners) import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#endif

/// Owns the live profiling session: builds the configured sinks, bridges the
/// runtime frame contract into them, and runs the periodic memory/CPU timers.
/// Activation is idempotent and a complete no-op when no config resolves.
@MainActor
public final class ProfileActivation {
  public static let shared = ProfileActivation()

  private var activated = false
  private var sinks: [any ProfileSink] = []
  private var timerTasks: [Task<Void, Never>] = []

  package init() {}

  /// Activates with an explicit config, or — when `explicit` is `nil` — with the
  /// config parsed from `SWIFTTUI_PROFILE`. Does nothing on a second call or
  /// when no config resolves.
  package func activateIfNeeded(config explicit: ProfileConfig?) {
    guard !activated else {
      return
    }
    let resolved = explicit ?? EnvProfileParser.parse(Self.environmentValue("SWIFTTUI_PROFILE"))
    guard let config = resolved, !config.signals.isEmpty else {
      return
    }
    activated = true
    activate(config)
  }

  /// Test seam: activate with explicit sinks, bypassing descriptor → sink
  /// construction and env parsing.
  package func activate(signals: Set<ProfileConfig.Signal>, sinks: [any ProfileSink]) {
    guard !activated else {
      return
    }
    activated = true
    self.sinks = sinks
    installSignals(signals)
  }

  private func activate(_ config: ProfileConfig) {
    sinks = makeSinks(config.sinks)
    installSignals(config.signals)
  }

  private func installSignals(_ signals: Set<ProfileConfig.Signal>) {
    if signals.contains(.frames) {
      ProfilingRegistry.shared.frameSink = ProfileFrameBridge(sinks: sinks)
    }
    for signal in signals {
      switch signal {
      case .frames:
        break
      case .memory(let interval):
        startTimer(interval) { [weak self] in self?.collectMemory() }
      case .cpu(let interval):
        startCPUTimer(interval)
      }
    }
  }

  /// Snapshots occupancy once and emits it to every sink. Extracted so tests can
  /// drive a tick without the timer.
  package func collectMemory() {
    let snapshots = MemoryMetricCollector().collect()
    emit(.memory(snapshots))
  }

  private func emit(_ record: ProfileRecord) {
    for sink in sinks {
      sink.emit(record)
    }
  }

  /// Cancels the timers and flushes every sink's reduced report. Call at app
  /// shutdown so buffered sinks (summary) produce output.
  public func finish() {
    for task in timerTasks {
      task.cancel()
    }
    timerTasks = []
    for sink in sinks {
      sink.finish()
    }
  }

  private func startTimer(_ interval: Duration, _ tick: @escaping @MainActor () -> Void) {
    let task = Task { @MainActor in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: interval)
        } catch {
          break
        }
        tick()
      }
    }
    timerTasks.append(task)
  }

  private func startCPUTimer(_ interval: Duration) {
    let task = Task { @MainActor [weak self] in
      var previous = try? CPUSampler.readCurrentUsage()
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: interval)
        } catch {
          break
        }
        guard let start = previous, let end = try? CPUSampler.readCurrentUsage() else {
          continue
        }
        previous = end
        self?.emit(.cpu(CPUSampler.sampleDelta(from: start, to: end)))
      }
    }
    timerTasks.append(task)
  }

  private func makeSinks(_ descriptors: [ProfileConfig.SinkDescriptor]) -> [any ProfileSink] {
    // With no sink named, fall back to a summary on stderr so activation is
    // never silent.
    guard !descriptors.isEmpty else {
      return [SummarySink()]
    }
    return descriptors.compactMap { descriptor in
      switch descriptor {
      case .summary:
        SummarySink()
      case .tsv(let path):
        FileProfileSink(path: path, format: .tsv)
      case .jsonl(let path):
        FileProfileSink(path: path, format: .jsonl)
      }
    }
  }

  private static func environmentValue(_ name: String) -> String? {
    #if canImport(WASILibc)
      return nil
    #else
      guard let value = unsafe getenv(name) else {
        return nil
      }
      return unsafe String(cString: value)
    #endif
  }
}

/// Bridges the runtime's per-frame ``FrameDiagnosticSink`` contract into the
/// product's ``ProfileSink`` fan-out: derives the rich record once and emits it
/// to every sink.
@MainActor
final class ProfileFrameBridge: FrameDiagnosticSink {
  private let sinks: [any ProfileSink]

  init(sinks: [any ProfileSink]) {
    self.sinks = sinks
  }

  func record(_ sample: RuntimeFrameSample) {
    let record = FrameRecordDerivation.record(from: sample)
    for sink in sinks {
      sink.emit(.frame(record))
    }
  }
}
