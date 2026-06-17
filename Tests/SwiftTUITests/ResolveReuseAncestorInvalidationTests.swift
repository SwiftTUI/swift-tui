import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct ResolveReuseAncestorInvalidationTests {
  @Test("captured binding hazard: ancestor invalidation recomputes binding-driven descendants")
  func ancestorInvalidationRecomputesBindingDrivenDescendants() {
    struct BindingDrivenRoot: View {
      let selection: Binding<String>

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Text("Header")
          Text(selection.wrappedValue)
        }
      }
    }

    // One two-frame render under whichever gate setting is active: frame one
    // seeds "Overview", then the external box flips to "Styling" and the root
    // is invalidated for frame two (returned).
    func renderFrames() -> FrameArtifacts {
      let renderer = DefaultRenderer(
        layoutEngine: .init(cache: MeasurementCache())
      )
      let rootIdentity = testIdentity("Root")
      final class SelectionBox: Sendable {
        private let valueStorage = LockedBox("Overview")

        var value: String {
          get { valueStorage.value }
          set { valueStorage.value = newValue }
        }
      }
      let box = SelectionBox()
      let selection = Binding<String>(
        get: { box.value },
        set: { box.value = $0 }
      )

      _ = renderer.render(
        BindingDrivenRoot(selection: selection),
        context: .init(identity: rootIdentity)
      )
      box.value = "Styling"

      return renderer.render(
        BindingDrivenRoot(selection: selection),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: [rootIdentity]
        )
      )
    }

    // Soundness invariant — gate-independent: the binding-driven Text must
    // reflect the new external value, never the stale one. The memo gate sees
    // that Text's view value change ("Overview" → "Styling") and refuses to
    // reuse it, so this holds whether the gate is on or off.
    for gate in [false, true] {
      let updated = withMemoReuse(gate) { renderFrames() }
      let rendered = updated.rasterSurface.lines.joined(separator: "\n")
      #expect(rendered.contains("Styling"))
      #expect(!rendered.contains("Overview"))
    }

    // Default (gate off): ancestor invalidation conservatively recomputes the
    // whole reached subtree — no descendant reuse.
    let gateOff = withMemoReuse(false) { renderFrames() }
    #expect(gateOff.diagnostics.work.resolvedNodesReused == 0)

    // Gate on: the stable `Text("Header")` (no recorded deps, unchanged view
    // value) is memo-reused despite its ancestor being invalidated, while the
    // changed binding-driven Text still recomputes (asserted above).
    let gateOn = withMemoReuse(true) { renderFrames() }
    #expect(gateOn.diagnostics.work.resolvedNodesReused > 0)
  }

  @Test("ancestor invalidation: clean descendant reuse is gated by the memo flag")
  func ancestorInvalidationCleanDescendantReuseIsGated() {
    struct StableRoot: View {
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Text("Stable")
          Text("AlsoStable")
        }
      }
    }

    func renderFrames() -> FrameArtifacts {
      let renderer = DefaultRenderer(
        layoutEngine: .init(cache: MeasurementCache())
      )
      let rootIdentity = testIdentity("Root")

      _ = renderer.render(
        StableRoot(),
        context: .init(identity: rootIdentity)
      )

      return renderer.render(
        StableRoot(),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: [rootIdentity]
        )
      )
    }

    // The rendered output is identical in both modes — reuse is a pure
    // optimization, never a behavior change.
    for gate in [false, true] {
      let updated = withMemoReuse(gate) { renderFrames() }
      let rendered = updated.rasterSurface.lines.joined(separator: "\n")
      #expect(rendered.contains("Stable"))
      #expect(rendered.contains("AlsoStable"))
    }

    // Default (gate off): the invalidated ancestor forces its entire reached
    // subtree to recompute — no descendant reuse.
    let gateOff = withMemoReuse(false) { renderFrames() }
    #expect(gateOff.diagnostics.work.resolvedNodesReused == 0)
    #expect(gateOff.diagnostics.work.resolvedNodesComputed > 0)

    // Gate on: the stable, dependency-free descendants are memo-reused even
    // though their ancestor was invalidated.
    let gateOn = withMemoReuse(true) { renderFrames() }
    #expect(gateOn.diagnostics.work.resolvedNodesReused > 0)
  }

  @Test("ancestor invalidation recomputes List row labels derived from root state")
  func ancestorInvalidationRecomputesListRowLabels() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let rootIdentity = testIdentity("Root")

    final class SelectionBox: Sendable {
      private let selectedIndexStorage = LockedBox(0)

      var selectedIndex: Int {
        get { selectedIndexStorage.value }
        set { selectedIndexStorage.value = newValue }
      }
    }
    let selectionBox = SelectionBox()

    struct RootList: View {
      let value: Int
      let selection: Binding<Int>

      var body: some View {
        List(selection: selection) {
          ForEach([0, 2, 4], id: \.self) { preset in
            Text(preset == value ? "\(preset) *" : "\(preset)")
              .tag(preset)
          }
        }
        .frame(width: 16, height: 6, alignment: .topLeading)
      }
    }

    let selection = Binding<Int>(
      get: { selectionBox.selectedIndex },
      set: { selectionBox.selectedIndex = $0 }
    )

    _ = renderer.render(
      RootList(value: 0, selection: selection),
      context: .init(identity: rootIdentity)
    )
    selectionBox.selectedIndex = 2

    let updated = renderer.render(
      RootList(value: 2, selection: selection),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    let rendered = updated.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("2 *"))
    #expect(!rendered.contains("0 *"))
  }

  /// Guards the H2 enabler (`TransactionSnapshot.isReuseEquivalent`): a sibling
  /// disjoint from the invalidation must reuse across frames even though the
  /// per-frame transaction `debugSignature` (the frame's cause summary) changes
  /// every frame. Before the enabler, `canReuse`'s full `==` on the transaction
  /// saw the changing `debugSignature` and defeated all retained reuse, so the
  /// whole tree re-resolved every invalidation frame.
  @Test("disjoint-sibling reuse survives a per-frame transaction debugSignature change")
  func disjointSiblingReuseSurvivesDebugSignatureChange() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let rootIdentity = testIdentity("DisjointReuse")
    let aID = testIdentity("DisjointReuse", "A")
    let bID = testIdentity("DisjointReuse", "B")

    struct TwoSiblings: View {
      let aID: Identity
      let bID: Identity

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          VStack(alignment: .leading, spacing: 0) {
            Text("A0")
            Text("A1")
          }
          .id(aID)
          VStack(alignment: .leading, spacing: 0) {
            Text("B0")
            Text("B1")
          }
          .id(bID)
        }
      }
    }

    _ = renderer.render(
      TwoSiblings(aID: aID, bID: bID),
      context: .init(
        identity: rootIdentity,
        transaction: TransactionSnapshot(debugSignature: "frame-1")
      )
    )

    // Invalidate only the A subtree, under a DIFFERENT debugSignature than the
    // first frame. The B subtree is disjoint and must reuse despite the
    // signature change.
    let second = renderer.render(
      TwoSiblings(aID: aID, bID: bID),
      context: .init(
        identity: rootIdentity,
        transaction: TransactionSnapshot(debugSignature: "frame-2"),
        invalidatedIdentities: [aID]
      )
    )

    #expect(second.diagnostics.work.resolvedNodesReused > 0)
    let rendered = second.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("A0"))
    #expect(rendered.contains("B0"))
  }

  @Test("scoped retained-reuse suppression recomputes only affected reached subtrees")
  func scopedRetainedReuseSuppressionKeepsUnaffectedReachedSubtreesReusable() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let rootIdentity = testIdentity("ScopedSuppression")
    let aID = testIdentity("ScopedSuppression", "A")
    let bID = testIdentity("ScopedSuppression", "B")
    let cID = testIdentity("ScopedSuppression", "C")

    struct ThreeSiblings: View {
      let aValue: String
      let aID: Identity
      let bID: Identity
      let cID: Identity

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          VStack(alignment: .leading, spacing: 0) {
            Text("A:\(aValue)")
          }
          .id(aID)
          VStack(alignment: .leading, spacing: 0) {
            Text("B:stable")
          }
          .id(bID)
          VStack(alignment: .leading, spacing: 0) {
            Text("C:stable")
          }
          .id(cID)
        }
      }
    }

    _ = renderer.render(
      ThreeSiblings(aValue: "0", aID: aID, bID: bID, cID: cID),
      context: .init(identity: rootIdentity)
    )

    renderer.enableSelectiveEvaluation()
    renderer.forceRootEvaluation()
    renderer.suppressRetainedReuseForNextFrame(
      .init(identities: [bID])
    )

    let updated = renderer.render(
      ThreeSiblings(aValue: "1", aID: aID, bID: bID, cID: cID),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [aID]
      )
    )

    let rendered = updated.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("A:1"))
    #expect(rendered.contains("B:stable"))
    #expect(rendered.contains("C:stable"))
    #expect(updated.diagnostics.work.resolvedNodesReused > 0)
    #expect(updated.diagnostics.work.resolvedNodesComputed > 0)
  }

  @Test("runtime focus-state dependency tracking is limited to authored environment readers")
  func runtimeFocusStateDependencyTrackingFindsEnvironmentReadersOnly() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let rootIdentity = testIdentity("RuntimeFocusDependency")
    let readoutID = testIdentity("RuntimeFocusDependency", "Readout")
    let buttonID = testIdentity("RuntimeFocusDependency", "Button")

    struct FocusDependencyProbe: View {
      let readoutID: Identity
      let buttonID: Identity

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          EnvironmentReader(\.focusedIdentity) { focusedIdentity in
            Text("Focus: \(focusedIdentity.map(\.description) ?? "none")")
          }
          .id(readoutID)
          Button("Focusable") {}
            .id(buttonID)
        }
      }
    }

    _ = renderer.render(
      FocusDependencyProbe(readoutID: readoutID, buttonID: buttonID),
      context: .init(identity: rootIdentity)
    )

    let dependencies = renderer.runtimeFocusStateDependentIdentities()
    #expect(
      dependencies.contains { identity in
        identity == readoutID
          || identity.isAncestor(of: readoutID)
          || identity.isDescendant(of: readoutID)
      }
    )
    #expect(!dependencies.contains(buttonID))
  }
}

/// Runs `body` with the memoized-body reuse gate forced to `enabled`, restoring
/// the previous setting afterward. Makes these tests deterministic regardless
/// of the ambient `SWIFTTUI_MEMO_REUSE` environment — the A/B measurement run
/// sets that variable process-wide, which would otherwise flip the gate-off
/// assertions.
@MainActor
private func withMemoReuse<Result>(
  _ enabled: Bool,
  _ body: () -> Result
) -> Result {
  let previous = MemoReuseConfiguration.isEnabled
  MemoReuseConfiguration.isEnabled = enabled
  defer { MemoReuseConfiguration.isEnabled = previous }
  return body()
}
