import Dispatch
import Foundation
@_spi(Runners) import SwiftTUI
@_spi(Runners) import SwiftTUIProfiling

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#endif

func monotonicSeconds() -> Double {
  Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
}

func environmentValue(_ key: String) -> String? {
  #if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
    return unsafe key.withCString { name in
      guard let value = unsafe getenv(name) else {
        return nil
      }
      return unsafe String(cString: value)
    }
  #else
    return nil
  #endif
}

func setEnvironmentValue(_ value: String?, for key: String) throws {
  #if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
    let result: Int32
    if let value {
      result = unsafe key.withCString { name in
        unsafe value.withCString { rawValue in
          setenv(name, rawValue, 1)
        }
      }
    } else {
      result = unsafe key.withCString { name in
        unsetenv(name)
      }
    }
    guard result == 0 else {
      throw PerfScenarioError.environmentUnavailable
    }
  #else
    throw PerfScenarioError.environmentUnavailable
  #endif
}

public enum PerfScenarioError: Error, Equatable, CustomStringConvertible {
  case cannotCreateDiagnostics(String)
  case noWindowScene(String)
  case markerTimedOut(String)
  case markerHasNoCell(String)
  case environmentUnavailable

  public var description: String {
    switch self {
    case .cannotCreateDiagnostics(let path):
      return "could not create frame diagnostics at \(path)."
    case .noWindowScene(let scenario):
      return "scenario \(scenario) did not produce a window scene."
    case .markerTimedOut(let marker):
      return "timed out waiting for marker '\(marker)'."
    case .markerHasNoCell(let marker):
      return "marker '\(marker)' was not found in the latest frame."
    case .environmentUnavailable:
      return "environment mutation is unavailable on this platform."
    }
  }
}

public struct PerfScenarioRunOptions: Equatable, Sendable {
  /// Default cadence for the occupancy/memory sampler (was a magic literal).
  public static let defaultMemorySampleInterval = Duration.milliseconds(500)
  /// Default post-drive idle window during which memory keeps sampling, so a
  /// bounded cache has time to reach its plateau and a leak has time to show.
  public static let defaultMemoryIdleWindow = Duration.seconds(2)

  public var renderMode: RuntimeRenderMode
  public var iterations: Int
  public var artifactRoot: URL
  public var configuration: String
  public var terminalSize: PerfTerminalSize?
  public var cpuSampleInterval: Duration
  public var memorySampleInterval: Duration
  public var memoryIdleWindow: Duration

  public init(
    renderMode: RuntimeRenderMode = .async,
    iterations: Int = PerfRunConfig.defaultIterations,
    artifactRoot: URL = URL(fileURLWithPath: PerfRunConfig.defaultArtifactsRoot, isDirectory: true),
    configuration: String = PerfRunConfig.defaultConfiguration,
    terminalSize: PerfTerminalSize? = nil,
    cpuSampleInterval: Duration = .milliseconds(50),
    memorySampleInterval: Duration = defaultMemorySampleInterval,
    memoryIdleWindow: Duration = defaultMemoryIdleWindow
  ) {
    self.renderMode = renderMode
    self.iterations = iterations
    self.artifactRoot = artifactRoot
    self.configuration = configuration
    self.terminalSize = terminalSize
    self.cpuSampleInterval = cpuSampleInterval
    self.memorySampleInterval = memorySampleInterval
    self.memoryIdleWindow = memoryIdleWindow
  }
}

public struct PerfScenarioRunResult: Sendable {
  public var runDirectory: URL
  public var metadata: PerfRunMetadata
  public var events: [PerfEventRecord]
  public var cpuSamples: [PerfCPUSample]
  public var summary: PerfSummary
  public var presentedFrameCount: Int
}

@MainActor
public protocol PerfScenario {
  var name: PerfScenarioName { get }
  var defaultTerminalSize: PerfTerminalSize { get }
  var scriptedEvents: [String] { get }
  var visualMarkers: [String] { get }
  var settlingDescription: String { get }
  /// How long the runner waits for the FIRST presented frame before the drive
  /// closure runs. Scenarios whose initial tree is deliberately huge (the
  /// full-materialization baselines) override this; everything else keeps the
  /// historical 2 seconds.
  var initialFrameTimeout: Duration { get }

  func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult
}

extension PerfScenario {
  public var initialFrameTimeout: Duration { .seconds(2) }
}

public enum PerfScenarioRegistry {
  /// Extension point for scenarios registered at startup that cannot live in
  /// this package's committed sources — e.g. coordination-only scenarios that
  /// depend on a sibling repo (the example gallery). Populated before argument
  /// parsing; empty in a clean checkout.
  @MainActor
  public static var additionalScenarios: [any PerfScenario] = []

  @MainActor
  public static var all: [any PerfScenario] {
    [
      ExampleAppShellWorkflowScenario(),
      GalleryAnimationClickScenario(),
      LayoutScrollBurstScenario(),
      SyntheticPhaseAnimatorScenario(),
      SyntheticRepeatForeverScenario(),
      SyntheticShimmerScenario(),
      SyntheticNarrowInvalidationScenario(),
      SyntheticObservableFanoutScenario(),
      SheetOpenLatencyScenario(),
      GalleryTabSwitchScenario(),
      FileBrowserSelectionScenario(),
      TextInputEditingScenario(),
      MemoEquatableBoundaryScenario(),
      CanvasPartialReuseScenario(),
      GifPlaybackScenario(),
      LazyList1KScenario(),
      Table1Kx4Scenario(),
      LazyVStackScrollScenario(),
    ] + additionalScenarios
  }

  @MainActor
  public static func scenario(named name: PerfScenarioName) -> (any PerfScenario)? {
    all.first { $0.name == name }
  }
}

public struct PerfScenarioDriver {
  public let inputReader: PerfScriptedInputReader
  public let terminalHost: PerfTerminalHost

  @MainActor
  public func waitForFrame(
    containing marker: String,
    afterFrame frameNumber: Int = 0,
    timeout: Duration = .seconds(2)
  ) async throws -> PerfPresentedFrame {
    try await PerfScenarioRunner.waitForFrame(
      in: terminalHost,
      containing: marker,
      afterFrame: frameNumber,
      timeout: timeout
    )
  }

  @MainActor
  public func cell(containing marker: String) throws -> CellPoint {
    guard let cell = terminalHost.firstCell(containing: marker) else {
      throw PerfScenarioError.markerHasNoCell(marker)
    }
    return cell
  }

  @MainActor
  public func sendClick(at cell: CellPoint) {
    let location = Point(x: Double(cell.x) + 0.5, y: Double(cell.y) + 0.5)
    inputReader.send(.mouse(.init(kind: .down(.primary), location: location)))
    inputReader.send(.mouse(.init(kind: .up(.primary), location: location)))
  }

  @MainActor
  public func sendScroll(deltaY: Int, at cell: CellPoint) {
    inputReader.send(
      .mouse(
        .init(
          kind: .scrolled(deltaX: 0, deltaY: deltaY),
          location: Point(x: Double(cell.x) + 0.5, y: Double(cell.y) + 0.5)
        )))
  }
}

public final class PerfScriptedInputReader: TerminalInputReading {
  private var continuation: AsyncStream<InputEvent>.Continuation?
  private var pendingEvents: [InputEvent] = []
  private var finished = false

  public init() {}

  public func send(_ event: InputEvent) {
    guard !finished else {
      return
    }
    if let continuation {
      continuation.yield(event)
    } else {
      pendingEvents.append(event)
    }
  }

  public func finish() {
    finished = true
    continuation?.finish()
    continuation = nil
    pendingEvents.removeAll(keepingCapacity: true)
  }

  public func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      self.continuation = continuation
      for event in pendingEvents {
        continuation.yield(event)
      }
      pendingEvents.removeAll(keepingCapacity: true)
      if finished {
        continuation.finish()
      }
    }
  }
}

public enum PerfScenarioRunner {
  @MainActor
  public static func runWindow<Content: View>(
    scenario: any PerfScenario,
    options: PerfScenarioRunOptions,
    @ViewBuilder content: @escaping @MainActor () -> Content,
    drive: @escaping @MainActor (PerfScenarioDriver) async throws -> [PerfEventRecord]
  ) async throws -> PerfScenarioRunResult {
    let runDirectory = try makeRunDirectory(
      scenario: scenario.name,
      mode: options.renderMode,
      artifactRoot: options.artifactRoot
    )
    let terminalSize = options.terminalSize ?? scenario.defaultTerminalSize
    let terminalHost = PerfTerminalHost(size: terminalSize)
    let inputReader = PerfScriptedInputReader()
    let signalReader = InProcessSignalReader()
    let framesURL = runDirectory.appendingPathComponent("frames.tsv")
    guard let framesSink = TSVFileSink(path: framesURL.path) else {
      throw PerfScenarioError.cannotCreateDiagnostics(framesURL.path)
    }
    let scene = WindowGroup(scenario.name.rawValue) {
      content()
    }
    guard let selection = collectWindowSceneSelections(from: scene).first else {
      throw PerfScenarioError.noWindowScene(scenario.name.rawValue)
    }

    let stateContainer = StateContainer(
      initialState: SceneSessionState(),
      invalidationIdentities: [selection.rootIdentity]
    )
    let focusTracker = FocusTracker(invalidationIdentities: [selection.rootIdentity])
    let resources = SceneSessionResources(
      presentationSurface: terminalHost,
      terminalInputReader: inputReader,
      signalReader: signalReader,
      frameSink: framesSink
    )

    let startedAt = timestampString()
    let memorySampler = PerfMemorySampler()
    var events: [PerfEventRecord] = []
    let cpuReadings = try await withRenderModeEnvironment(options.renderMode) {
      try await CPUSampler.collect(interval: options.cpuSampleInterval) { @MainActor in
        let runTask = Task { @MainActor in
          try await selection.run(
            sessionName: scenario.name.rawValue,
            resources: resources,
            stateContainer: stateContainer,
            focusTracker: focusTracker
          )
        }

        var memoryTask: Task<Void, Never>?
        do {
          _ = try await waitForPresentedFrame(
            in: terminalHost,
            timeout: scenario.initialFrameTimeout
          )
          memoryTask = memorySampler.startSampling(interval: options.memorySampleInterval)
          events = try await drive(
            PerfScenarioDriver(
              inputReader: inputReader,
              terminalHost: terminalHost
            ))
          if options.memoryIdleWindow > .zero {
            try? await Task.sleep(for: options.memoryIdleWindow)
          }
          memoryTask?.cancel()
          inputReader.finish()
          signalReader.finish()
          _ = try await runTask.value
        } catch {
          memoryTask?.cancel()
          inputReader.finish()
          signalReader.finish()
          runTask.cancel()
          _ = try? await runTask.value
          throw error
        }
      }
    }
    let cpuSamples = cpuReadings.map(PerfCPUSample.init(from:))

    let metadata = PerfRunMetadata(
      gitSHA: gitSHA(),
      dirty: gitDirty(),
      renderMode: options.renderMode,
      scenario: scenario.name,
      iterationCount: options.iterations,
      configuration: options.configuration,
      swiftVersion: swiftVersion(),
      osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      hardwareModel: hardwareModel(),
      processorCount: ProcessInfo.processInfo.processorCount,
      terminalSize: terminalSize,
      startedAt: startedAt,
      endedAt: timestampString()
    )
    let frameRecords = try PerfFrameDiagnosticsTSVReader.read(
      from: framesURL,
      presentedFrames: terminalHost.presentedFrames
    )
    let summary = SummaryReducer.reduce(
      metadata: metadata,
      events: events,
      cpuSamples: cpuSamples,
      frames: frameRecords
    )

    try writeJSON(metadata, to: runDirectory.appendingPathComponent("run.json"))
    try writeString(
      PerfTSVWriter.eventsTSV(events),
      to: runDirectory.appendingPathComponent("events.tsv")
    )
    try writeString(
      PerfTSVWriter.cpuTSV(cpuSamples),
      to: runDirectory.appendingPathComponent("cpu.tsv")
    )
    try writeString(
      memorySampler.tsv(),
      to: runDirectory.appendingPathComponent("memory.tsv")
    )
    try writeString(
      MemoryGrowthAnalyzer.tsv(MemoryGrowthAnalyzer.analyze(memorySampler.samples)),
      to: runDirectory.appendingPathComponent("memory_growth.tsv")
    )
    try writeJSON(summary, to: runDirectory.appendingPathComponent("summary.json"))

    return PerfScenarioRunResult(
      runDirectory: runDirectory,
      metadata: metadata,
      events: events,
      cpuSamples: cpuSamples,
      summary: summary,
      presentedFrameCount: terminalHost.presentedFrames.count
    )
  }

  @MainActor
  public static func waitForFrame(
    in terminalHost: PerfTerminalHost,
    containing marker: String,
    afterFrame frameNumber: Int = 0,
    timeout: Duration = .seconds(2),
    hardCap: Duration = .seconds(30)
  ) async throws -> PerfPresentedFrame {
    let clock = ContinuousClock()
    let hardDeadline = clock.now.advanced(by: hardCap)
    var deadline = clock.now.advanced(by: timeout)
    var newestObserved = terminalHost.presentedFrames.last?.frameNumber ?? 0
    while clock.now < deadline && clock.now < hardDeadline {
      if let frame = terminalHost.presentedFrames.last(where: {
        $0.frameNumber > frameNumber && $0.text.contains(marker)
      }) {
        return frame
      }
      // Progress-gated deadline (never fixed wall-clock): while the run loop
      // keeps presenting new frames the scenario is advancing — just slowly,
      // e.g. on a loaded CI runner — so re-arm the idle window. The hard cap
      // bounds the wait even when continuous animation frames keep arriving.
      if let newest = terminalHost.presentedFrames.last?.frameNumber,
        newest > newestObserved
      {
        newestObserved = newest
        deadline = clock.now.advanced(by: timeout)
      }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    throw PerfScenarioError.markerTimedOut(marker)
  }

  @MainActor
  private static func waitForPresentedFrame(
    in terminalHost: PerfTerminalHost,
    timeout: Duration = .seconds(2)
  ) async throws -> PerfPresentedFrame {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
      if let frame = terminalHost.presentedFrames.last {
        return frame
      }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    throw PerfScenarioError.markerTimedOut("<first frame>")
  }

  private static func makeRunDirectory(
    scenario: PerfScenarioName,
    mode: RuntimeRenderMode,
    artifactRoot: URL
  ) throws -> URL {
    let timestamp = timestampString()
      .replacingOccurrences(of: ":", with: "-")
    let directory = artifactRoot.appendingPathComponent(
      "\(timestamp)-\(scenario.rawValue)-\(mode.rawValue)-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }

  private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: url)
  }

  private static func writeString(_ value: String, to url: URL) throws {
    try value.data(using: .utf8)?.write(to: url)
  }

  private static func timestampString() -> String {
    ISO8601DateFormatter().string(from: Date())
  }

  private static func swiftVersion() -> String {
    processOutput(["swift", "--version"]) ?? "unknown"
  }

  private static func gitSHA() -> String {
    processOutput(["git", "rev-parse", "HEAD"]) ?? "unknown"
  }

  private static func gitDirty() -> Bool {
    guard let output = processOutput(["git", "status", "--porcelain"]) else {
      return true
    }
    return !output.isEmpty
  }

  private static func hardwareModel() -> String? {
    #if canImport(Darwin)
      processOutput(["/usr/sbin/sysctl", "-n", "hw.model"])
    #else
      nil
    #endif
  }

  private static func processOutput(_ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
      try process.run()
    } catch {
      return nil
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  @MainActor
  private static func withRenderModeEnvironment<T>(
    _ mode: RuntimeRenderMode,
    operation: () async throws -> T
  ) async throws -> T {
    let key = RuntimeRenderMode.environmentVariableName
    let oldValue = environmentValue(key)
    try setEnvironmentValue(mode.rawValue, for: key)
    defer {
      try? setEnvironmentValue(oldValue, for: key)
    }
    return try await operation()
  }

  private static func environmentValue(_ key: String) -> String? {
    #if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
      return unsafe key.withCString { name in
        guard let value = unsafe getenv(name) else {
          return nil
        }
        return unsafe String(cString: value)
      }
    #else
      return nil
    #endif
  }

  private static func setEnvironmentValue(_ value: String?, for key: String) throws {
    #if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
      let result: Int32
      if let value {
        result = unsafe key.withCString { name in
          unsafe value.withCString { rawValue in
            setenv(name, rawValue, 1)
          }
        }
      } else {
        result = unsafe key.withCString { name in
          unsetenv(name)
        }
      }
      guard result == 0 else {
        throw PerfScenarioError.environmentUnavailable
      }
    #else
      throw PerfScenarioError.environmentUnavailable
    #endif
  }

  /// When the reuse-denial trace (`SWIFTTUI_REUSE_TRACE`) is armed, default its
  /// file sink (`SWIFTTUI_REUSE_TRACE_FILE`) to `reuse-trace.log` under the
  /// artifacts root so the diagnostic is captured as a run artifact instead of
  /// scrolling past on stderr (where it was previously misread as silent). An
  /// explicit operator override of the file path is respected.
  static func configureReuseTraceArtifact(at artifactRoot: URL) {
    guard let raw = environmentValue("SWIFTTUI_REUSE_TRACE"),
      !raw.isEmpty,
      raw != "0"
    else {
      return
    }
    if let existing = environmentValue("SWIFTTUI_REUSE_TRACE_FILE"), !existing.isEmpty {
      return
    }
    try? FileManager.default.createDirectory(
      at: artifactRoot,
      withIntermediateDirectories: true
    )
    let path = artifactRoot.appendingPathComponent("reuse-trace.log").path
    try? setEnvironmentValue(path, for: "SWIFTTUI_REUSE_TRACE_FILE")
  }
}
