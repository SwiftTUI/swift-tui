import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Gallery Navigations & Collections regression: switching to a tab whose
/// payload hosts a NavigationStack + ScrollView with List selection,
/// OutlineGroup, lazy stacks, and Table selection consistently reported
/// teardown-coherence soundness violations — `List`/`Table` value-collapse
/// their row mints into draw payloads and lazy indexed sources mint realized
/// elements from layout, so none of those stored subtrees joined a children
/// array and teardown could never reach them. The fix anchors each mint in
/// the hosted-detached ledger (`List.resolvedItems`, `Table.resolvedRows`,
/// `ForEachIndexedChildSource.child(at:)`), mirroring the value-dropped
/// `EmptyView`/`Group` anchoring.
@MainActor
@Suite
struct NavigationCollectionsTabSwitchTests {
  @Test("animated entry followed by a drain tick keeps the F66 skip premise")
  func animatedEntryDrainTickKeepsSkipPremise() async throws {
    let harness = try NavCollectionsTabHarness()
    defer { harness.shutdown() }

    // Animated (empty-batch) programmatic switch to the collections tab: the
    // stranded-batch drain tick that follows the entry frame is the
    // fully-reused frame shape the F66 skip gate DEBUG-asserts on (the
    // gallery crash stack); a premise regression crashes this test.
    try harness.clickText("GoNavAnimated")
    #expect(
      harness.frame.contains("Lazy row 0"),
      "the collections tab must be visible after the animated switch; frame:\n\(harness.frame)"
    )

    // Render the drain tick (and any follow-up deadline frames) without any
    // new invalidation.
    try await harness.renderDeadlineFrames(within: .milliseconds(200))
  }

  @Test("entering a collections tab leaves no teardown-coherence strand")
  func enteringCollectionsTabLeavesNoStrand() async throws {
    let harness = try NavCollectionsTabHarness()
    defer { harness.shutdown() }

    #expect(
      harness.frame.contains("plain-pane"),
      "the plain tab must render first; frame:\n\(harness.frame)"
    )

    // Switch to the collections tab via the strip.
    try harness.clickText("NavTab")
    #expect(
      harness.frame.contains("Lazy row 0"),
      "the collections tab must be visible after the switch; frame:\n\(harness.frame)"
    )

    // Idle frames without structural invalidation, then user-shaped
    // interactions: list selection, nav push/pop — the strands minted on
    // entry surface in the census regardless, but the interactions pin that
    // anchored mints survive selection rewrites and presentation churn.
    try harness.pumpMoveFrames(4)
    try harness.pumpExternalWakeFrames(4)
    try harness.clickText("Build lanes")
    try harness.pumpExternalWakeFrames(2)
    try harness.clickText("Open selected detail")
    try harness.pumpExternalWakeFrames(2)
    try harness.clickText("Done")
    try harness.pumpExternalWakeFrames(2)

    try harness.renderCensusFrames(4)
    let violation = harness.teardownCoherenceViolation()
    #expect(
      violation == nil,
      """
      entering the collections tab stranded stored node(s): \
      \(violation?.detail ?? "")
      """
    )

    // Leave and return — teardown of the collections payload and re-adoption
    // must both stay clean.
    try harness.clickText("PlainTab")
    try harness.pumpExternalWakeFrames(4)
    try harness.renderCensusFrames(4)
    let leaveViolation = harness.teardownCoherenceViolation()
    #expect(
      leaveViolation == nil,
      """
      leaving the collections tab stranded stored node(s): \
      \(leaveViolation?.detail ?? "")
      """
    )

    try harness.clickText("NavTab")
    try harness.pumpMoveFrames(4)
    try harness.renderCensusFrames(4)
    let returnViolation = harness.teardownCoherenceViolation()
    #expect(
      returnViolation == nil,
      """
      returning to the collections tab stranded stored node(s): \
      \(returnViolation?.detail ?? "")
      """
    )
  }
}

/// Mirrors the gallery's NavigationCollectionsTab at reduced size: a
/// NavigationStack-wrapped ScrollView hosting list selection, an outline,
/// lazy stacks, and table selection.
@MainActor
private struct NavCollectionsFixture: View {
  @State private var selection = 0

  var body: some View {
    TabView(selection: $selection) {
      Tab("PlainTab", value: 0) {
        VStack(alignment: .leading, spacing: 1) {
          Text("plain-pane")
          // Mirrors the gallery crash shape: an animated (empty-batch)
          // selection write whose stranded-batch drain tick renders a
          // fully-reused frame immediately after the collections tab's
          // entry frame.
          Button("GoNavAnimated") {
            withAnimation(.linear(duration: .milliseconds(1))) {
              selection = 1
            }
          }
        }
      }
      Tab("NavTab", value: 1) {
        NavCollectionsPane()
      }
    }
    .tabViewStyle(.literalTabs)
  }
}

@MainActor
private struct NavCollectionsPane: View {
  @State private var selectedDoc = "overview"
  @State private var selectedTableRow = "queued"
  @State private var showingDetail = false

  var body: some View {
    NavigationStack(id: "nav-collections-test") {
      ScrollView {
        VStack(alignment: .leading, spacing: 1) {
          HStack(alignment: .top, spacing: 2) {
            GroupBox("List selection") {
              List(selection: $selectedDoc) {
                Text("Overview").tag("overview")
                Text("Build lanes").tag("build-lanes")
              }
              .frame(width: 20, height: 4)
            }
            GroupBox("OutlineGroup") {
              OutlineGroup(Self.outlineNodes, children: \.children) { node in
                Text(node.title)
              }
              .frame(width: 24, height: 5, alignment: .topLeading)
            }
          }
          GroupBox("Lazy stacks") {
            VStack(alignment: .leading, spacing: 1) {
              LazyHStack(spacing: 1) {
                ForEach(0..<6, id: \.self) { index in
                  Text("H\(index)")
                }
              }
              LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                  Text("Lazy row \(index)")
                }
              }
            }
          }
          GroupBox("Table selection") {
            Table(
              selection: $selectedTableRow,
              columns: [
                TableColumn("State", width: 10),
                TableColumn("Count", width: 5, alignment: .trailing),
              ]
            ) {
              TableRow {
                Text("Queued")
                Text("3")
              }
              .tag("queued")
              TableRow {
                Text("Done")
                Text("8")
              }
              .tag("done")
            }
            .frame(height: 5)
          }
          Button("Open selected detail") {
            showingDetail = true
          }
          Spacer(minLength: 0)
        }
        .padding(1)
        .navigationDestination(isPresented: $showingDetail) {
          VStack(alignment: .leading, spacing: 1) {
            Text("detail-pane")
            Button("Done") {
              showingDetail = false
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private static let outlineNodes: [NavCollectionsOutlineNode] = [
    .init(
      title: "Examples",
      children: [
        .init(title: "Terminal"),
        .init(title: "Web/WASI"),
      ]
    ),
    .init(title: "Coverage", children: [.init(title: "Build lanes")]),
  ]
}

private struct NavCollectionsOutlineNode: Identifiable, Sendable {
  let id: String
  let title: String
  let children: [NavCollectionsOutlineNode]?

  init(title: String, children: [NavCollectionsOutlineNode]? = nil) {
    id = title
    self.title = title
    self.children = children
  }
}

@MainActor
private final class NavCollectionsTabHarness {
  private let terminal: NavCollectionsRecordingHost
  let runLoop: SwiftTUIRuntime.RunLoop<Int, NavCollectionsFixture>
  private let scheduler: FrameScheduler
  private let rootIdentity = testIdentity("NavCollectionsTabRoot")
  private var renderedFrames = 0
  private var didShutdown = false

  init() throws {
    let size = CellSize(width: 76, height: 44)
    let terminal = NavCollectionsRecordingHost(surfaceSize: size)
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: NavCollectionsEmptyKeyReader(),
      signalReader: NavCollectionsEmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in NavCollectionsFixture() }
    )
    focusTracker.invalidator = scheduler
    self.terminal = terminal
    self.runLoop = runLoop
    self.scheduler = scheduler

    scheduler.requestInvalidation(of: [rootIdentity])
    _ = try render()
  }

  var frame: String { terminal.frames.last ?? "" }

  func teardownCoherenceViolation()
    -> (isOverRemoval: Bool, detail: String, unreachableCount: Int)?
  {
    runLoop.renderer.viewGraph.debugTeardownCoherenceViolation()
  }

  func shutdown() {
    guard !didShutdown else { return }
    didShutdown = true
    scheduler.setWakeHandler(nil)
    runLoop.lifecycleCoordinator.shutdown()
  }

  @discardableResult
  func render() throws -> String {
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    return terminal.frames.last ?? ""
  }

  @discardableResult
  func clickText(_ label: String) throws -> String {
    let point = try #require(
      terminal.centerOfText(label),
      "could not find '\(label)' in frame:\n\(frame)"
    )
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .down(.primary), location: point)))
      ) == nil
    )
    _ = try render()
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .up(.primary), location: point)))
      ) == nil
    )
    return try render()
  }

  /// Pumps pointer-move events over blank surface area: each schedules a
  /// frame whose resolve computes zero nodes (nothing is invalidated), the
  /// shape that arms the F66 skip gate.
  func pumpMoveFrames(_ count: Int) throws {
    for offset in 0..<count {
      let point = Point(CellPoint(x: 1 + offset, y: 0))
      _ = runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .moved, location: point)))
      )
      _ = try render()
    }
  }

  /// Pumps frames with NO invalidated identities (external wakes) — frames
  /// whose resolve reuses everything it can, the shape that arms the F66
  /// skip gate.
  func pumpExternalWakeFrames(_ count: Int) throws {
    for index in 0..<count {
      scheduler.requestExternalWake(reason: "nav-collections-test-\(index)")
      _ = try render()
    }
  }

  /// Renders deadline-armed frames (animation drains) as they come due,
  /// without adding any invalidation, until no wake is armed inside `window`.
  func renderDeadlineFrames(within window: Duration) async throws {
    let bound = MonotonicInstant.now().advanced(by: window)
    while true {
      let now = MonotonicInstant.now()
      if scheduler.hasPendingFrame(at: now) {
        _ = try render()
        continue
      }
      guard let next = scheduler.nextWakeInstant(after: now), next <= bound else {
        return
      }
      await scheduler.waitForPendingFrame(at: now)
      _ = try render()
    }
  }

  /// Renders further frames synchronously so the teardown census re-runs
  /// after a structural change.
  func renderCensusFrames(_ count: Int) throws {
    for _ in 0..<count {
      scheduler.requestInvalidation(of: [rootIdentity])
      _ = try render()
    }
  }
}

private final class NavCollectionsRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var frames: [String] = []

  init(surfaceSize: CellSize) {
    self.surfaceSize = surfaceSize
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(capabilityProfile: capabilityProfile).render(surface)
    frames.append(rendered.replacingOccurrences(of: "\r\n", with: "\n"))
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
  }

  func centerOfText(_ target: String) -> Point? {
    guard let frame = frames.last else { return nil }
    for (row, line) in frame.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
      let text = String(line)
      guard let range = text.range(of: target) else { continue }
      let column = text.distance(from: text.startIndex, to: range.lowerBound)
      return Point(CellPoint(x: column + target.count / 2, y: row))
    }
    return nil
  }
}

private final class NavCollectionsEmptyKeyReader: InputReading {
  func events() -> AsyncStream<KeyPress> {
    AsyncStream { $0.finish() }
  }
}

private final class NavCollectionsEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
