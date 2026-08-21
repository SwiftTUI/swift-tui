@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Live-graph journeys for the plan's Stage-0 identity-preserving-churn
/// shapes (plan 2026-08-20-001): a body-captured closure stashed *before* a
/// structural churn fires *after* it, with no dispatch context at all.
///
/// Gate on, the carried capture serves — directly while its owner node
/// survives the churn (list reshape), and through the fire-time identity
/// refresh when the churn re-mints the node under the same resolve identity
/// (unmount/remount). Gate off, both shapes bottom out at the authored seed —
/// today's behavior, pinned. Both run on an invalidator-backed graph because
/// the snapshot harness mirrors imperative writes into the box seed and
/// false-passes this class by construction.
@MainActor
@Suite(.serialized)
struct CaptureBindingChurnJourneyTests {
  @MainActor
  private final class ChurnClosureLog {
    var preChurnRead: (@MainActor () -> String)?
  }

  private enum IDs {
    static let reshapeField = testIdentity("ChurnReshapeField")
    static let reshapeButton = testIdentity("ChurnReshapeButton")
    static let remountField = testIdentity("ChurnRemountField")
    static let remountButton = testIdentity("ChurnRemountButton")
  }

  // MARK: - Journey 1: list reshape between stash and fire

  private struct ReshapeRow: View {
    @State private var text = ""
    let item: Int
    let log: ChurnClosureLog

    var body: some View {
      let _ = stashIfTarget()
      if item == 3 {
        TextField("Row", text: $text)
          .id(IDs.reshapeField)
          .textFieldStyle(.plain)
      } else {
        Text("row \(item)")
      }
    }

    private func stashIfTarget() {
      guard item == 3, log.preChurnRead == nil else {
        return
      }
      log.preChurnRead = { text }
    }
  }

  private struct ReshapeRoot: View {
    @State private var items = [1, 2, 3]
    let log: ChurnClosureLog

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(items, id: \.self) { item in
          ReshapeRow(item: item, log: log)
        }
        Button("reshape") { items = [3, 1, 2] }
          .id(IDs.reshapeButton)
      }
    }
  }

  private func reshapeJourneyObservation(
    captureBindingEnabled: Bool
  ) throws -> String {
    let saved = StateCaptureBindingConfiguration.isEnabled
    StateCaptureBindingConfiguration.isEnabled = captureBindingEnabled
    defer { StateCaptureBindingConfiguration.isEnabled = saved }

    let log = ChurnClosureLog()
    let harness = try makeJourneyHarness(rootName: "ChurnReshapeRoot") { ReshapeRoot(log: log) }

    // The churn: rotate the list through the live action path, re-seating
    // every row between the stash (first render) and the typing below.
    _ = harness.runLoop.focusTracker.setFocus(to: IDs.reshapeButton)
    try harness.render()
    #expect(harness.runLoop.handleKeyPress(KeyPress(.return)) == nil)
    try harness.render()

    // Type into the RESHAPED row so the live slot holds a value the closure
    // can only observe by tracking the row's live state, not its
    // registration-time snapshot.
    _ = harness.runLoop.focusTracker.setFocus(to: IDs.reshapeField)
    try harness.render()
    for character in "07" {
      #expect(harness.runLoop.handleKeyPress(KeyPress(.character(character))) == nil)
      try harness.render()
    }

    #if DEBUG
      StateCaptureCensus.resetForTesting()
    #endif
    let read = try #require(log.preChurnRead)
    let observed = read()
    #if DEBUG
      if captureBindingEnabled {
        #expect(
          StateCaptureCensus.count(of: .captureHit)
            + StateCaptureCensus.count(of: .captureRefreshedOwner) >= 1
        )
        #expect(StateCaptureCensus.count(of: .seedFallback) == 0)
      } else {
        #expect(StateCaptureCensus.count(of: .seedFallback) >= 1)
      }
    #endif
    return observed
  }

  @Test("gate on: a pre-reshape closure observes typed state after the reshape")
  func preReshapeClosureObservesTypedStateWithCaptures() throws {
    let observed = try reshapeJourneyObservation(captureBindingEnabled: true)
    #expect(observed == "07")
  }

  @Test("gate off: the same reshape shape bottoms out at the authored seed (today's pin)")
  func preReshapeClosureSeedsWithoutCaptures() throws {
    let observed = try reshapeJourneyObservation(captureBindingEnabled: false)
    #expect(observed == "")
  }

  // MARK: - Journey 2: unmount/remount between stash and fire

  private struct RemountChild: View {
    @State private var text = ""
    let log: ChurnClosureLog

    var body: some View {
      let _ = stashOnce()
      TextField("Remount", text: $text)
        .id(IDs.remountField)
        .textFieldStyle(.plain)
    }

    private func stashOnce() {
      guard log.preChurnRead == nil else {
        return
      }
      log.preChurnRead = { text }
    }
  }

  private struct RemountRoot: View {
    @State private var showsChild = true
    let log: ChurnClosureLog

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        if showsChild {
          RemountChild(log: log)
        }
        Button("toggle") { showsChild.toggle() }
          .id(IDs.remountButton)
      }
    }
  }

  private func remountJourneyObservation(
    captureBindingEnabled: Bool
  ) throws -> String {
    let saved = StateCaptureBindingConfiguration.isEnabled
    StateCaptureBindingConfiguration.isEnabled = captureBindingEnabled
    defer { StateCaptureBindingConfiguration.isEnabled = saved }

    let log = ChurnClosureLog()
    let harness = try makeJourneyHarness(rootName: "ChurnRemountRoot") { RemountRoot(log: log) }

    // Unmount, then remount: the stashed closure's owner node is committed-
    // removed, and a NEW node occupies the same resolve identity afterward.
    _ = harness.runLoop.focusTracker.setFocus(to: IDs.remountButton)
    try harness.render()
    #expect(harness.runLoop.handleKeyPress(KeyPress(.return)) == nil)
    try harness.render()
    #expect(harness.runLoop.handleKeyPress(KeyPress(.return)) == nil)
    try harness.render()

    // Type into the REMOUNTED field so the live occupant's slot holds a
    // value the authored seed cannot mimic.
    _ = harness.runLoop.focusTracker.setFocus(to: IDs.remountField)
    try harness.render()
    for character in "07" {
      #expect(harness.runLoop.handleKeyPress(KeyPress(.character(character))) == nil)
      try harness.render()
    }

    #if DEBUG
      StateCaptureCensus.resetForTesting()
    #endif
    let read = try #require(log.preChurnRead)
    let observed = read()
    #if DEBUG
      if captureBindingEnabled {
        #expect(StateCaptureCensus.count(of: .captureRefreshedOwner) >= 1)
        #expect(StateCaptureCensus.count(of: .seedFallback) == 0)
      } else {
        #expect(StateCaptureCensus.count(of: .seedFallback) >= 1)
      }
    #endif
    return observed
  }

  @Test("gate on: a pre-remount closure refreshes to the live occupant's typed state")
  func preRemountClosureRefreshesToLiveOccupant() throws {
    let observed = try remountJourneyObservation(captureBindingEnabled: true)
    #expect(observed == "07")
  }

  @Test("gate off: the same remount shape bottoms out at the authored seed (today's pin)")
  func preRemountClosureSeedsWithoutCaptures() throws {
    let observed = try remountJourneyObservation(captureBindingEnabled: false)
    #expect(observed == "")
  }

  // MARK: - Harness

  private struct JourneyHarness<Root: View> {
    let runLoop: RunLoop<Int, Root>
    let renderCounter: RenderCounter

    @MainActor
    func render() throws {
      try runLoop.renderPendingFrames(renderedFrames: &renderCounter.renderedFrames)
    }
  }

  @MainActor
  private final class RenderCounter {
    var renderedFrames = 0
  }

  private func makeJourneyHarness<Root: View>(
    rootName: String,
    root: @escaping @MainActor () -> Root
  ) throws -> JourneyHarness<Root> {
    let terminalSize = CellSize(width: 40, height: 8)
    let terminal = RecordingPresentationSurface(surfaceSize: terminalSize)
    let rootIdentity = testIdentity(rootName)
    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: InertChurnTerminalInputReader(),
      signalReader: ImmediateFinishSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in root() }
    )
    focusTracker.invalidator = runLoop.scheduler

    let harness = JourneyHarness(runLoop: runLoop, renderCounter: RenderCounter())
    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    try harness.render()
    runLoop.renderer.enableSelectiveEvaluation()
    return harness
  }
}

private final class InertChurnTerminalInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
