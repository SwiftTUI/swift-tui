import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Regression: a prepared (abortable) frame head whose baseline checkpoints
// predate a SIBLING frame's commit must not restore those checkpoints — the
// whole-index restore would rewind the sibling's committed effects, evicting
// subtrees it minted while their `@State`/task closures stay bound to the
// orphaned nodes.
//
// Production shape (the gallery Life-tab revisit freeze): with the event pump
// attached, an input frame's head is prepared, its tail suspends, and a
// sibling frame commits a tab revisit (fresh subtree + auto-tick `.task`)
// before the first frame is cancelled or dropped. The stale head's discard
// then restored its baseline, evicting the revisit's node: the running task
// stepped an orphaned `@State` box whose invalidations dirtied nothing live —
// a permanent empty-frame drop loop; the screen never repainted again.
@MainActor
@Suite(.serialized)
struct StaleBaselineFrameHeadTests {
  @Test("aborting a stale-baseline frame head preserves the sibling commit")
  func abortingStaleBaselineHeadPreservesSiblingCommit() throws {
    let scaffold = try StaleBaselineScaffold()

    // Prepare an abortable head against the committed value-0 frame.
    let draft = scaffold.prepareHead()

    // Sibling commit: a later frame commits value 1 while the head is
    // suspended.
    try scaffold.commitSibling(value: 1)
    #expect(scaffold.terminal.frames.last?.contains("value 1") == true)
    let committed = scaffold.renderer.viewGraph.debugTotalStateSnapshot()

    // Aborting the stale head must not touch live graph state.
    scaffold.renderer.abortPreparedFrameHeadForCancellationTesting(draft)
    #expect(
      scaffold.renderer.viewGraph.debugTotalStateSnapshot() == committed,
      "aborting a stale-baseline head rewound the sibling frame's commit"
    )

    // The graph must still render the sibling's state going forward.
    try scaffold.render()
    #expect(scaffold.terminal.frames.last?.contains("value 1") == true)
  }

  @Test("resolving a stale-baseline completed frame skips it without state effects")
  func resolvingStaleBaselineCompletedFrameSkipsIt() async throws {
    let scaffold = try StaleBaselineScaffold()

    let draft = scaffold.prepareHead()
    try scaffold.commitSibling(value: 1)
    let committed = scaffold.renderer.viewGraph.debugTotalStateSnapshot()

    // The production commit-or-drop resolution must take the stale-baseline
    // skip: committing would materialize a stale prepared checkpoint and
    // dropping would restore a stale baseline — both rewind the sibling.
    let skipped = await scaffold.renderer.resolveCompletedFrameCandidateForTesting(draft)
    #expect(skipped, "a stale-baseline completed frame was committed or dropped")
    #expect(
      scaffold.renderer.viewGraph.debugTotalStateSnapshot() == committed,
      "resolving a stale-baseline completed frame mutated live graph state"
    )

    try scaffold.render()
    #expect(scaffold.terminal.frames.last?.contains("value 1") == true)
  }

  @Test("aborting a fresh-baseline frame head still restores its baseline")
  func abortingFreshBaselineHeadStillRestores() throws {
    let scaffold = try StaleBaselineScaffold()

    // No sibling commit: the baseline is current, so the abort must keep the
    // existing restore semantics (state mutations made for the aborted frame
    // are rolled back).
    let before = scaffold.renderer.viewGraph.debugTotalStateSnapshot()
    scaffold.runLoop.stateContainer.mutate { value in
      value = 1
    }
    let draft = scaffold.prepareHead()
    scaffold.renderer.abortPreparedFrameHeadForCancellationTesting(draft)
    #expect(scaffold.renderer.viewGraph.debugTotalStateSnapshot() == before)
  }

  // Late-preference reconciliation resolves a toolbar strip into the graph
  // between the tail's layout passes. On a stale head that work would land
  // in the sibling's committed graph, built from the stale frame's items, and
  // a stale head is discarded without a restore — nothing would undo it.
  @Test("a stale-baseline frame tail does not reconcile a toolbar into the sibling commit")
  func staleBaselineTailSkipsLatePreferenceReconciliation() async throws {
    let scaffold = try StaleBaselineScaffold { value in
      StaleBaselineToolbarProbe(value: value)
    }

    let draft = scaffold.prepareHead()
    try scaffold.commitSibling(value: 1)
    #expect(scaffold.terminal.frames.last?.contains("Item 1") == true)
    let committed = scaffold.renderer.viewGraph.debugTotalStateSnapshot()

    let skipped = await scaffold.renderer.resolveCompletedFrameCandidateForTesting(draft)
    #expect(skipped, "a stale-baseline completed frame was committed or dropped")
    #expect(
      scaffold.renderer.viewGraph.debugTotalStateSnapshot() == committed,
      "a stale-baseline frame tail reconciled its toolbar into live graph state"
    )

    try scaffold.render()
    #expect(scaffold.terminal.frames.last?.contains("Item 1") == true)
    #expect(scaffold.terminal.frames.last?.contains("Item 0") == false)
  }
}

// MARK: - Scaffold

@MainActor
private struct StaleBaselineScaffold<Content: View> {
  let rootIdentity = testIdentity("StaleBaselineFrameHeadRoot")
  let terminal = StaleBaselineTerminalHost()
  let renderer = DefaultRenderer()
  let runLoop: RunLoop<Int, Content>

  init(content: @escaping @MainActor (Int) -> Content) throws {
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        content(value)
      }
    )
    focusTracker.invalidator = runLoop.scheduler

    // Establish the committed value-0 baseline frame.
    try render()
    guard terminal.frames.last?.contains("value 0") == true else {
      throw StaleBaselineScaffoldError.initialFrameMissing
    }
  }

  func render() throws {
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
  }

  func prepareHead() -> FrameHeadDraft {
    renderer.prepareFrameHeadForCancellationTesting(
      runLoop.viewBuilder(
        (
          state: runLoop.stateContainer.state,
          focusedIdentity: runLoop.focusTracker.currentFocusIdentity
        )
      ),
      context: runLoop.resolveContext(
        for: ScheduledFrame(
          causes: [.invalidation],
          invalidatedIdentities: [rootIdentity],
          signalNames: [],
          externalReasons: [],
          triggeredDeadline: nil,
          nextDeadline: nil
        )
      ),
      proposal: runLoop.proposal()
    )
  }

  func commitSibling(value: Int) throws {
    runLoop.stateContainer.mutate { current in
      current = value
    }
    try render()
  }
}

extension StaleBaselineScaffold where Content == Text {
  init() throws {
    try self.init { value in
      Text("value \(value)")
    }
  }
}

/// A toolbar scope whose one item changes with the state value, so the strip
/// a stale head would reconcile differs from the one the sibling committed.
///
/// The content nests custom layouts past the frame-tail worker's engine
/// re-entry budget. That keeps the tail on the main actor, where the
/// non-cancellable layout stage this suite drives runs late-preference
/// reconciliation; a tree it can offload skips the reconcile on that path.
private struct StaleBaselineToolbarProbe: View {
  let value: Int

  var body: some View {
    StaleBaselinePassthroughLayout {
      StaleBaselinePassthroughLayout {
        StaleBaselinePassthroughLayout {
          Text("value \(value)")
        }
      }
    }
    .toolbarItem(.init(title: "Item \(value)", action: {}))
    .panel(id: "stale-baseline-toolbar")
    .toolbar()
  }
}

private struct StaleBaselinePassthroughLayout: Layout {
  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    subviews.first?.sizeThatFits(proposal) ?? .zero
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    for subview in subviews {
      subview.place(
        at: bounds.origin,
        proposal: .init(width: bounds.size.width, height: bounds.size.height)
      )
    }
  }
}

private enum StaleBaselineScaffoldError: Error {
  case initialFrameMissing
}

private final class StaleBaselineTerminalHost: PresentationSurface {
  let surfaceSize = CellSize(width: 60, height: 12)
  let proposal = ProposedSize(width: 60, height: 12)
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback
  private(set) var frames: [String] = []

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    frames.append(surface.lines.joined(separator: "\n"))
    return .fullRepaint(
      for: surface,
      capabilityProfile: capabilityProfile
    )
  }
}
