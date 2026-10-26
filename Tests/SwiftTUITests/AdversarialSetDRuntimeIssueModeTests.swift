import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Campaign two, F2 pass 2 (STUI-1283), setD171–setD180: dispatch-time
// runtime issues routed through elided, aborted, batched and presented
// frames. Brief 08.

private let staleCode = "forEach.staleElementBindingWrite"

private struct SetDCountItem: Identifiable, Sendable {
  var id: Int
  var value: Int
}

@MainActor
private final class SetDStaleLog {
  var retained: Binding<SetDCountItem>?
  var presented = false
  var coverBinding: Binding<Bool> { .init(get: { self.presented }, set: { self.presented = $0 }) }
  /// Writes through the retained element binding of the removed item.
  func writeStale(_ value: Int = 9) { retained?.wrappedValue = SetDCountItem(id: 1, value: value) }
}

private struct SetDStaleRows: View {
  let log: SetDStaleLog
  @State private var items: [SetDCountItem] = [.init(id: 1, value: 0), .init(id: 2, value: 0)]
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach($items) { item in
        let _ = remember(item)
        Text("item\(item.wrappedValue.id)=\(item.wrappedValue.value)")
      }
      Button("remove") { items.removeAll { $0.id == 1 } }
      Button("stale") { log.writeStale() }
    }
    .fullScreenCover(isPresented: log.coverBinding) { Text("cover") }
  }

  private func remember(_ item: Binding<SetDCountItem>) {
    if item.wrappedValue.id == 1 { log.retained = item }
  }
}

/// Pass 1's off-screen paint-only animation (AdversarialSetDElisionControlTests).
private struct SetDOffscreenAnimation: View {
  @State private var phase: Double = 0
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text("filler").frame(height: 6)
        Text("paint").padding(1).frame(width: 10, height: 3)
          .blendBorder(blend: BorderBlend([.red, .blue, .red]), set: .single, phase: phase)
      }
    }
    .frame(width: 20, height: 1)
    .onAppear { withAnimation(.linear(duration: .seconds(1))) { phase = 1 } }
  }
}

@MainActor
@Suite("Campaign F2 pass 2: runtime-issue routing under frame modes", .serialized)
struct AdversarialSetDRuntimeIssueModeTests {
  private func staleHarness(_ name: String) throws -> (
    SetDLiveHarness<SetDStaleRows>, SetDStaleLog, SetDIssueLog
  ) {
    let log = SetDStaleLog()
    let issues = SetDIssueLog()
    _ = ImperativeRuntimeIssueQueue.drain()
    let h = try SetDLiveHarness(name, size: .init(width: 30, height: 8)) { SetDStaleRows(log: log) }
    h.runLoop.runtimeIssueSink = RuntimeIssueSink { issues.issues.append($0) }
    try h.clickText("remove")
    try #require(!h.frame.contains("item1"), "\(h.frame)")
    return (h, log, issues)
  }

  @Test("setD171: a dispatch-time issue survives an elided off-screen frame")
  func setD171IssueSurvivesElidedFrame() async throws {
    let log = SetDStaleLog()
    let issues = SetDIssueLog()
    _ = ImperativeRuntimeIssueQueue.drain()
    let root = testIdentity("setD", "171")
    let surface = SetDResizableSurface()
    let scheduler = FrameScheduler()
    let focus = FocusTracker(invalidationIdentities: [root])
    let loop = SwiftTUIRuntime.RunLoop(
      rootIdentity: root, presentationSurface: surface,
      terminalInputReader: SetDFiniteInput([]), signalReader: nil, scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: focus,
      viewBuilder: { _, _ in
        VStack(alignment: .leading, spacing: 0) {
          SetDStaleRows(log: log)
          SetDOffscreenAnimation()
        }
      })
    focus.invalidator = scheduler
    loop.runtimeIssueSink = RuntimeIssueSink { issues.issues.append($0) }
    let frozen = MonotonicInstant.now()
    loop.frameClock = { frozen }
    loop.renderMode = .asyncNoCancel
    defer { loop.lifecycleCoordinator.shutdown() }
    try await withAnimationSinks(loop.renderer.internalAnimationController) {
      var rendered = 0
      scheduler.requestInvalidation(of: [root])
      try loop.renderPendingFrames(renderedFrames: &rendered)
      loop.renderer.enableSelectiveEvaluation()
      try #require(loop.renderer.internalAnimationController.activeAnimationCount > 0)
      let remove = try #require(surface.raster.flatMap { setDCell(of: "remove", in: $0) })
      for kind in [MouseEvent.Kind.down(.primary), .up(.primary)] {
        #expect(
          loop.withRuntimeRegistrationScope {
            loop.handle(.input(.mouse(.init(kind: kind, location: Point(remove)))))
          } == nil)
        _ = try await loop.renderPendingFramesAsync(renderedFrames: &rendered, eventPump: nil)
      }
      try #require(surface.raster?.lines.joined().contains("item1") == false)
      log.writeStale()
      let elided = loop.renderer.elidedFrameCount
      scheduler.requestDeadline(frozen)
      _ = try await loop.renderPendingFramesAsync(renderedFrames: &rendered, eventPump: nil)
      try #require(loop.renderer.elidedFrameCount > elided, "the deadline frame was elided")
      scheduler.requestInvalidation(of: [root])
      _ = try await loop.renderPendingFramesAsync(renderedFrames: &rendered, eventPump: nil)
      #expect(issues.count(staleCode) == 1, "\(issues.issues.map(\.code))")
    }
  }

  @Test("setD172: without elision the issue is reported on the next frame")
  func setD172IssueReportedOnNextFrame() throws {
    let (h, log, issues) = try staleHarness("172")
    defer { h.shutdown() }
    log.writeStale()
    try h.renderRoot()
    #expect(issues.count(staleCode) == 1, "\(issues.issues.map(\.code))")
  }

  @Test("setD173: a queued issue survives an aborted frame head")
  func setD173IssueSurvivesAbortedFrameHead() {
    _ = ImperativeRuntimeIssueQueue.drain()
    let renderer = DefaultRenderer()
    let view = Text("aborted")
    let context = ResolveContext(identity: testIdentity("setD", "173"))
    _ = renderer.render(view, context: context, proposal: .init(width: 20, height: 2))
    ImperativeRuntimeIssueQueue.record(
      RuntimeIssue(severity: .warning, code: "setD.queued", message: "queued before an abort"))
    let draft = renderer.prepareFrameHeadForCancellationTesting(
      view, context: context, proposal: .init(width: 20, height: 2))
    renderer.abortPreparedFrameHeadForCancellationTesting(draft)
    let next = renderer.render(view, context: context, proposal: .init(width: 20, height: 2))
    setDKnown(
      "NEW-12: a dispatch-time runtime issue queued before an aborted frame head is never reported; the head drains the imperative queue into the discarded draft's layout context, and an aborted or cancelled draft reports its runtimeIssues, which are always empty (DefaultRendererFrameHeadCoordinator.swift:124-131, 160-175; DefaultRenderer.swift:495-503); contract: ImperativeRuntimeIssueQueue.swift:1-11, Logging-And-Diagnostics.md:118-131"
    ) {
      #expect(
        next.diagnostics.runtime.issues.contains { $0.code == "setD.queued" },
        "\(next.diagnostics.runtime.issues.map(\.code))")
    }
    _ = ImperativeRuntimeIssueQueue.drain()
  }

  @Test("setD174: without an abort the next render reports a queued issue")
  func setD174QueuedIssueReportedByNextRender() {
    _ = ImperativeRuntimeIssueQueue.drain()
    let renderer = DefaultRenderer()
    let view = Text("plain")
    let context = ResolveContext(identity: testIdentity("setD", "174"))
    _ = renderer.render(view, context: context, proposal: .init(width: 20, height: 2))
    ImperativeRuntimeIssueQueue.record(
      RuntimeIssue(severity: .warning, code: "setD.queued", message: "queued"))
    let next = renderer.render(view, context: context, proposal: .init(width: 20, height: 2))
    #expect(next.diagnostics.runtime.issues.contains { $0.code == "setD.queued" })
    _ = ImperativeRuntimeIssueQueue.drain()
  }

  @Test("setD175: the live sink reports one distinct issue once across frames")
  func setD175SessionDeduplication() throws {
    let (h, log, issues) = try staleHarness("175")
    defer { h.shutdown() }
    for _ in 0..<3 {
      log.writeStale()
      try h.renderRoot()
    }
    #expect(issues.count(staleCode) == 1, "\(issues.issues.map(\.code))")
  }

  @Test("setD176: two stale writes in one input batch report one issue")
  func setD176BatchedStaleWrites() throws {
    let (h, _, issues) = try staleHarness("176")
    defer { h.shutdown() }
    let stale = try #require(h.cell(of: "stale"))
    h.dispatchClick(stale)
    h.dispatchClick(stale)
    try h.render()
    #expect(issues.count(staleCode) == 1, "\(issues.issues.map(\.code))")
  }

  @Test("setD177: an unbounded table reports its realization once across resizes")
  func setD177UnboundedTableAcrossResizes() throws {
    let issues = SetDIssueLog()
    let rows = setDRows(30)
    // Correction C6: an enclosing ScrollView declares a measure viewport, so
    // the unbounded fallback needs a bare fixed-size table.
    let h = try SetDLiveHarness("177", size: .init(width: 30, height: 10)) {
      Table(rows, columns: [TableColumn("Name")]) { row in Text(row.id) }.fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    defer { h.shutdown() }
    h.runLoop.runtimeIssueSink = RuntimeIssueSink { issues.issues.append($0) }
    try h.renderRoot()
    // A fixed-size table's raster follows its ideal size, so the resizes are
    // driven without the harness's raster-size precondition.
    for size in [CellSize(width: 32, height: 12), CellSize(width: 30, height: 10)] {
      h.surface.surfaceSize = size
      #expect(
        h.runLoop.withRuntimeRegistrationScope { h.runLoop.handle(.signal("SIGWINCH")) } == nil)
      try h.render()
    }
    let distinct = h.runLoop.reportedRuntimeIssues.filter {
      $0.code == "collection.unboundedRealization"
    }
    #expect(distinct.count == 1, "\(distinct.map(\.message)); sink \(issues.issues.map(\.code))")
  }

  @Test("setD178: an untagged selectable row reports an issue and stays unselectable")
  func setD178UntaggedRowReports() throws {
    let box = SetDSelection<String?>(nil)
    let h = try SetDLiveHarness("178", size: .init(width: 30, height: 10)) {
      List(selection: box.binding) {
        Text("alpha").tag("alpha")
        Text("bravo")
        Text("charlie").tag("charlie")
      }
    }
    defer { h.shutdown() }
    #expect(
      h.runLoop.reportedRuntimeIssues.contains { $0.code == "collection.missingSelectionTag" },
      "\(h.runLoop.reportedRuntimeIssues.map(\.code))")
    try h.clickText("bravo")
    #expect(box.value == nil)
    try h.clickText("charlie")
    #expect(box.value == "charlie")
  }

  @Test("setD179: a stale write under a full-screen cover is reported")
  func setD179IssueUnderCover() throws {
    let (h, log, issues) = try staleHarness("179")
    defer { h.shutdown() }
    log.presented = true
    try h.renderRoot()
    try #require(h.frame.contains("cover"))
    log.writeStale()
    try h.renderRoot()
    #expect(issues.count(staleCode) == 1, "\(issues.issues.map(\.code))")
  }

  @Test("setD180: a stale write from a button action is reported on that click's frame")
  func setD180IssueFromAction() throws {
    let (h, _, issues) = try staleHarness("180")
    defer { h.shutdown() }
    try h.clickText("stale")
    #expect(issues.count(staleCode) == 1, "\(issues.issues.map(\.code))")
  }
}
