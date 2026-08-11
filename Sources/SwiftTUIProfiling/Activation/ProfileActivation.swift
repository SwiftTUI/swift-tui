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

/// Owns the live profiling session.
/// It builds the configured sinks and connects the runtime frame contract to them.
/// It also runs the periodic memory and CPU timers.
/// Activation is idempotent. It does nothing if no configuration resolves.
@MainActor
public final class ProfileActivation {
  public static let shared = ProfileActivation()

  private var activated = false
  private var sinks: [any ProfileSink] = []
  private var timerTasks: [Task<Void, Never>] = []
  /// Candidate `presents.tsv` paths derived from the configured TSV sinks.
  private var presentsPaths: [String] = []
  /// Retains the installed presentation-write sink for this session; the
  /// registry holds it too, but ownership belongs here alongside `sinks`.
  private var presentationWriteSink: PresentationWriteTSVSink?

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
    let descriptors = Self.resolvedDescriptors(config.sinks)
    sinks = makeSinks(descriptors)
    presentsPaths = descriptors.compactMap { descriptor in
      guard case .tsv(let path) = descriptor else {
        return nil
      }
      return Self.presentsPath(besideFramesPath: path)
    }
    installSignals(config.signals)
  }

  /// Fills the bare-`tsv`/`jsonl` descriptors (empty path) with their debug
  /// bundle destinations (`profile.tsv` / `profile.jsonl`); drops them when
  /// no bundle directory is active.
  nonisolated static func resolvedDescriptors(
    _ descriptors: [ProfileConfig.SinkDescriptor]
  ) -> [ProfileConfig.SinkDescriptor] {
    descriptors.compactMap { descriptor in
      switch descriptor {
      case .summary:
        return descriptor
      case .tsv(let path):
        guard path.isEmpty else {
          return descriptor
        }
        return DebugLogRouter.resolvedFilePath(override: nil, bundleFileName: "profile.tsv")
          .map { resolved in .tsv(path: resolved) }
      case .jsonl(let path):
        guard path.isEmpty else {
          return descriptor
        }
        return DebugLogRouter.resolvedFilePath(override: nil, bundleFileName: "profile.jsonl")
          .map { resolved in .jsonl(path: resolved) }
      }
    }
  }

  /// Opens the `presents.tsv` sibling for each TSV sink the `frames` signal
  /// writes to.
  ///
  /// The grammar is deliberately untouched: write completion is part of what
  /// `frames` means, it just cannot ride the frame row (it happens after
  /// commit, on another queue). The file is a sibling rather than extra
  /// columns so every existing `frames.tsv` consumer keeps its per-row
  /// independence.
  ///
  /// Only the real terminal host runs an asynchronous presentation writer, so
  /// on other hosts this file is opened and stays empty — which is the honest
  /// outcome. A synchronous host's "write latency" would be a fabricated zero.
  private func installPresentationWriteSinkIfNeeded(_ signals: Set<ProfileConfig.Signal>) {
    guard signals.contains(.frames), let path = presentsPaths.first else {
      return
    }
    guard let sink = PresentationWriteTSVSink(path: path) else {
      return
    }
    presentationWriteSink = sink
    ProfilingRegistry.shared.presentationWriteSink = sink
  }

  /// `presents.tsv` beside the frames file: same directory, fixed name. Fixed
  /// rather than derived from the frames file name so a reducer can find it
  /// without knowing what the operator called the frames file.
  nonisolated static func presentsPath(besideFramesPath framesPath: String) -> String {
    guard let separatorIndex = framesPath.lastIndex(of: "/") else {
      return "presents.tsv"
    }
    return framesPath[...separatorIndex] + "presents.tsv"
  }

  private func installSignals(_ signals: Set<ProfileConfig.Signal>) {
    if signals.contains(.frames) {
      ProfilingRegistry.shared.frameSink = ProfileFrameBridge(sinks: sinks)
    }
    installPresentationWriteSinkIfNeeded(signals)
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
