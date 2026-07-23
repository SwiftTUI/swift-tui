import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Reproduction for the gallery "click a strip tab, then Tab past the end of
/// the options" debug crash (stamp-coherence assertion, 2026-07-23).
///
/// Root cause: `ViewNode.apply`'s child wiring re-seats `child.parent` to the
/// newest adopter without telling the previous parent. The literal-tabs shell
/// alternates between pairing the tab-content payload under the style's
/// content wrapper and (chain-absorbed) directly under the style ZStack, so a
/// strip-click re-resolve strands the wrapper node with a committed value
/// that still embeds the payload subtree. Focus traversal then re-mints the
/// focused control's conditional interior along the *live* spine — which no
/// longer passes through the stranded wrapper, so its committed snapshot
/// stays "fresh". The Tab press that wraps focus back to the strip re-resolves
/// the shell on a selective frame, retained reuse serves the stranded
/// wrapper's stale snapshot by identity, and the runtime-ID stamping fast
/// path trips the debug stamp-coherence assertion on the superseded interior
/// stamps (release builds silently commit the stale subtree instead).
@Suite("TabStripReuseStampCoherence", .serialized)
@MainActor
struct TabStripReuseStampCoherenceTests {
  private struct StripTabsProbe: View {
    @State private var selection = 0
    @State private var count = 0
    @State private var step = 1

    var body: some View {
      TabView(selection: $selection) {
        Tab("One", value: 0) {
          Text("plain first tab")
        }
        Tab("Two", value: 1) {
          VStack(alignment: .center, spacing: 1) {
            Text("count \(count)")
            HStack {
              Button(" - ") { count -= step }
              Button(" + ") { count += step }
            }
            .focusSection()
            HStack(spacing: 2) {
              Slider("Step", value: $step, in: 1...9, step: 1)
              Button("Reset") { count = 0 }
            }
            .focusSection()
          }
          .padding(1)
          .toolbarItem(.init(title: "Reset counter", action: { count = 0 }))
        }
      }
      .tabViewStyle(.literalTabs)
      .toolbarItem(.init(title: "Item", action: {}))
    }
  }

  @Test("pointer-selecting a strip tab then tabbing past the last option keeps stamps coherent")
  func stripClickThenTabTraversalKeepsStampsCoherent() async throws {
    let rootIdentity = testIdentity("TabStripReuseStampCoherence", "Root")
    let terminalSize = CellSize(width: 60, height: 18)
    let terminal = StampCoherenceTerminalHost(surfaceSize: terminalSize)
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: StampCoherenceEmptyInputReader(),
      signalReader: nil,
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = terminalSize
        return values
      }(),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in StripTabsProbe() }
    )
    focusTracker.invalidator = scheduler

    var renderedFrames = 0
    func drain() async throws {
      var iterations = 0
      while scheduler.hasPendingFrame(at: .now()) && iterations < 12 {
        _ = try await runLoop.renderPendingFramesAsync(renderedFrames: &renderedFrames)
        iterations += 1
      }
    }

    scheduler.requestInvalidation(of: [rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
    try await drain()

    // Pointer-activate the second strip tab (the gallery flow: launch on the
    // default tab, click another strip tab once) — the strip-click re-resolve
    // strands the content slot's committed value on the superseded pairing
    // shape.
    let stripRegion = try #require(
      runLoop.latestSemanticSnapshot.interactionRegions.first {
        $0.identity.description.contains("TabItem[1]")
      },
      "expected the second strip tab to publish an interaction region"
    )
    let stripCenter = PointerLocation.cellFallback(
      CellPoint(
        x: stripRegion.rect.origin.x + stripRegion.rect.size.width / 2,
        y: stripRegion.rect.origin.y + stripRegion.rect.size.height / 2
      )
    )
    runLoop.handleMouseDown(MouseButton.primary, location: stripCenter)
    runLoop.handleMouseUp(MouseButton.primary, location: stripCenter)
    try await drain()

    // The strip-click re-resolve re-seats the tab-content payload under a
    // different pairing parent. The abandoned content-slot node must not keep
    // a servable-fresh committed snapshot: the literal-tabs style body
    // re-creates that resolve root on every shell re-resolve, so retained
    // reuse serves it by identity on a later selective frame, committing
    // superseded interior content and stamps (the gallery Tab-wrap
    // stamp-coherence crash).
    #expect(
      Self.strandedContentSlotViolations(in: runLoop.renderer.viewGraph) == [],
      "strip click stranded a fresh content-slot snapshot behind a re-seated payload"
    )

    // Tab through every option of the clicked tab and past the end (the wrap
    // press re-resolves the shell on a selective frame). Before the fix the
    // gallery flow tripped the stamp-coherence assertion inside a handful of
    // presses; the invariant probe below catches the stranded-snapshot
    // precursor deterministically even where the crash frame's exact
    // invalidation cadence does not arise.
    for _ in 0..<10 {
      _ = runLoop.handle(.input(.key(.tab)))
      try await drain()
      #expect(
        Self.strandedContentSlotViolations(in: runLoop.renderer.viewGraph) == [],
        "focus traversal stranded a fresh content-slot snapshot behind a re-seated payload"
      )
    }

    #expect(runLoop.focusTracker.currentFocusIdentity != nil)
  }

  /// Content-slot nodes (the literal-tabs style's payload wrapper — a resolve
  /// root the style body re-creates every shell re-resolve, so retained reuse
  /// consults it by identity) that value-blind Layer-A reuse would still serve
  /// (`fresh` and not flagged foreign-parented) while the payload child has
  /// been adopted under a DIFFERENT live parent. Such a node can no longer
  /// hear the payload subtree change (the upward staleness walks follow the
  /// child's single `parent` slot), so serving it commits superseded interior
  /// content and stamps — the divergent-resolvedIdentity capture-host
  /// orphaning seam behind the gallery crash. Scoped to the slot rather than
  /// the whole graph: route- and chain-absorb co-listings elsewhere are
  /// covered by their own soundness protocols (value verification, stamp-claim
  /// withdrawal) and are not consulted as value-blind reuse roots.
  private static func strandedContentSlotViolations(
    in viewGraph: ViewGraph
  ) -> [String] {
    let graph = viewGraph.debugTotalStateSnapshot()
    var violations: [String] = []
    for (nodeID, node) in graph.nodesByNodeID {
      guard node.isCommittedSnapshotFresh, !node.hasForeignParentedChild else { continue }
      guard let identity = graph.identityByNodeID[nodeID] else { continue }
      guard identity.path.hasSuffix("TabBody/ZStack[0]/VStack[1]") else { continue }
      for childIdentity in node.children where childIdentity != identity {
        guard
          let childID = graph.nodeIDByIdentity[childIdentity],
          childID != nodeID,
          let child = graph.nodesByNodeID[childID],
          let childParent = child.parentIdentity,
          childParent != identity
        else { continue }
        violations.append(
          "servable \(nodeID) at \(identity.path) lists child \(childID) at "
            + "\(childIdentity.path) whose parent is \(childParent.path)"
        )
      }
    }
    return violations.sorted()
  }
}

private final class StampCoherenceTerminalHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  init(surfaceSize: CellSize) { self.surfaceSize = surfaceSize }
  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}
  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    .init(
      bytesWritten: 0, linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height, strategy: .fullRepaint)
  }
}

private final class StampCoherenceEmptyInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}
