@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Drives a real `RunLoop` over one root view with pointer and key input and
/// collects the runtime issues it reports.
///
/// A one-shot `DefaultRenderer` render re-evaluates every ancestor of an
/// invalidated node. Only the live loop re-evaluates a node on its own, which
/// is the condition a per-evaluation diagnostic has to survive. Waits are
/// bounded in presented frames rather than wall-clock time.
@MainActor
final class RuntimeIssueJourneyHarness {
  private let host: RuntimeIssueJourneyRecordingHost
  private let inputReader: InjectedTerminalInputReader
  private let log: RuntimeIssueJourneyLog
  private let updates: MainActorConditionSignal
  private var runTask: Task<Void, any Error>?

  /// Every runtime issue the loop reported, in order.
  var issues: [RuntimeIssue] { log.reported }

  var duplicateSlotClaims: [RuntimeIssue] {
    issues.filter { $0.typedCode == .State.duplicateSlotClaim }
  }

  var screen: String {
    host.lastPresentedSurface?.lines.joined(separator: "\n") ?? ""
  }

  private init(
    host: RuntimeIssueJourneyRecordingHost,
    inputReader: InjectedTerminalInputReader,
    log: RuntimeIssueJourneyLog,
    updates: MainActorConditionSignal
  ) {
    self.host = host
    self.inputReader = inputReader
    self.log = log
    self.updates = updates
  }

  /// Starts the loop over `root` and waits for a frame showing `firstText`.
  static func start<Root: View>(
    named name: String,
    mode: RuntimeRenderMode,
    size: CellSize = CellSize(width: 60, height: 20),
    showing firstText: String,
    @ViewBuilder root: @escaping @MainActor () -> Root
  ) async throws -> RuntimeIssueJourneyHarness {
    let rootIdentity = testIdentity("\(name)-\(mode.rawValue)")
    var environment = EnvironmentValues()
    environment.terminalSize = size
    let updates = MainActorConditionSignal()
    let host = RuntimeIssueJourneyRecordingHost(size: size, updates: updates)
    let inputReader = InjectedTerminalInputReader()
    let log = RuntimeIssueJourneyLog()
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: inputReader,
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      environmentValues: environment,
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in root() }
    )
    focusTracker.invalidator = scheduler
    runLoop.renderMode = mode
    runLoop.runtimeIssueSink = RuntimeIssueSink { log.reported.append($0) }

    let harness = RuntimeIssueJourneyHarness(
      host: host, inputReader: inputReader, log: log, updates: updates)
    harness.runTask = Task { _ = try await runLoop.run() }
    try await harness.waitForScreen("the first frame") { $0.contains(firstText) }
    return harness
  }

  /// Presses and releases the primary button on the first occurrence of
  /// `label` in the presented frame.
  func click(_ label: String) throws {
    let surface = try #require(host.lastPresentedSurface)
    let point = try #require(
      Self.center(of: label, in: surface),
      "could not locate \(label) in:\n\(surface.lines.joined(separator: "\n"))"
    )
    inputReader.send(.mouse(.init(kind: .down(.primary), location: point)))
    inputReader.send(.mouse(.init(kind: .up(.primary), location: point)))
  }

  func type(_ text: String) {
    for character in text {
      inputReader.send(.key(.init(.character(character))))
    }
  }

  func waitForScreen(
    _ label: String,
    where matches: @escaping @MainActor @Sendable (String) -> Bool
  ) async throws {
    do {
      try await updates.wait(
        until: { matches(self.screen) }, for: label,
        within: ProgressBudget(stages: 64), on: host.presentedFrames
      )
    } catch let error as StageBudgetExceeded {
      throw RuntimeIssueJourneyWaitFailure(expectation: error.description, screen: screen)
    }
  }

  /// Ends input and waits for the loop to drain its pending frames and exit.
  func finish() async throws {
    inputReader.finish()
    let task = try #require(runTask)
    runTask = nil
    try await task.value
  }

  func stop() {
    inputReader.finish()
    runTask?.cancel()
  }

  private static func center(of target: String, in surface: RasterSurface) -> Point? {
    for (row, line) in surface.lines.enumerated() {
      guard let range = line.firstRange(of: target) else { continue }
      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      return Point(CellPoint(x: column + target.count / 2, y: row))
    }
    return nil
  }
}

struct RuntimeIssueJourneyWaitFailure: Error, CustomStringConvertible {
  let expectation: String
  let screen: String

  var description: String {
    "\(expectation) Last frame:\n\(screen)"
  }
}

@MainActor
private final class RuntimeIssueJourneyLog {
  var reported: [RuntimeIssue] = []
}

private final class RuntimeIssueJourneyRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  /// One stage per presented frame: the budget every harness wait is held to.
  let presentedFrames = ManualStageClock()
  private(set) var lastPresentedSurface: RasterSurface?
  private let updates: MainActorConditionSignal

  init(size: CellSize, updates: MainActorConditionSignal) {
    surfaceSize = size
    self.updates = updates
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    lastPresentedSurface = surface
    presentedFrames.advance()
    let updates = self.updates
    MainActor.assumeIsolated {
      updates.notify()
    }
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}
