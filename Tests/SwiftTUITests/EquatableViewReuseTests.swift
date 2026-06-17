import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Stage-3 lead mechanism: a read-free boundary view that conforms to
/// `Equatable` is compared by the memo gate via a single `==` (the comparator's
/// fast path), letting the gate reuse its whole subtree without the per-field
/// `Mirror` descent. SwiftTUI's comparator already routes any `Equatable` view
/// value to that fast path, so plain `Equatable` conformance is the opt-in — no
/// wrapper required.
@MainActor
@Suite
struct EquatableBoundaryReuseTests {
  /// A read-free Equatable boundary: its own body reads no state (so it can pass
  /// the gate's `hasNoRecordedDependencies` guard); `==` is synthesized from the
  /// Sendable `title`.
  private struct Chrome: View, Equatable {
    let title: String

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("Chrome:\(title)")
        Text("Static")
      }
    }
  }

  private struct Root: View {
    let chromeTitle: String
    let dynamic: String

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Chrome(title: chromeTitle)
        Text(dynamic)
      }
    }
  }

  /// Renders frame one, then frame two with the root invalidated, under whichever
  /// gate setting is active. Returns the second frame.
  private func renderFrames(
    chrome1: String,
    dynamic1: String,
    chrome2: String,
    dynamic2: String
  ) -> FrameArtifacts {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let rootIdentity = testIdentity("Root")

    _ = renderer.render(
      Root(chromeTitle: chrome1, dynamic: dynamic1),
      context: .init(identity: rootIdentity)
    )

    return renderer.render(
      Root(chromeTitle: chrome2, dynamic: dynamic2),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )
  }

  @Test("Equatable boundary reuses its subtree when unchanged (gate on)")
  func equatableBoundaryReusesUnchangedSubtree() {
    func assertCorrectRender(_ frame: FrameArtifacts) {
      let rendered = frame.rasterSurface.lines.joined(separator: "\n")
      #expect(rendered.contains("Chrome:fixed"))
      #expect(rendered.contains("Static"))
      #expect(rendered.contains("v2"))
      #expect(!rendered.contains("v1"))
    }

    let gateOff = withMemoReuse(false) {
      renderFrames(chrome1: "fixed", dynamic1: "v1", chrome2: "fixed", dynamic2: "v2")
    }
    assertCorrectRender(gateOff)
    // Default (off): the invalidated ancestor recomputes its whole reached
    // subtree — no descendant reuse.
    #expect(gateOff.diagnostics.work.resolvedNodesReused == 0)

    let gateOn = withMemoReuse(true) {
      renderFrames(chrome1: "fixed", dynamic1: "v1", chrome2: "fixed", dynamic2: "v2")
    }
    assertCorrectRender(gateOn)
    // On: the `Chrome` boundary's WHOLE subtree is reused via one comparison (its
    // node plus the VStack and both Texts) — not just the leaves — while the
    // changed dynamic Text still recomputes. So reuse covers more than one node
    // AND the recomputed-node count drops below the gate-off baseline (the
    // boundary subtree moved from computed to reused — the env-dep widening).
    #expect(gateOn.diagnostics.work.resolvedNodesReused > 1)
    #expect(
      gateOn.diagnostics.work.resolvedNodesComputed
        < gateOff.diagnostics.work.resolvedNodesComputed
    )

    // Reuse is a pure optimization: identical surface in both modes.
    #expect(gateOn.rasterSurface.lines == gateOff.rasterSurface.lines)
  }

  @Test("EquatableView (.equatable()) opt-in reuses its subtree via the isolated ==")
  func equatableViewOptInReusesSubtree() {
    struct WrappedRoot: View {
      let title: String
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Chrome(title: title).equatable()
          Text(dynamic)
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("Root")
    let updated = withMemoReuse(true) { () -> FrameArtifacts in
      _ = renderer.render(
        WrappedRoot(title: "fixed", dynamic: "v1"),
        context: .init(identity: rootIdentity)
      )
      return renderer.render(
        WrappedRoot(title: "fixed", dynamic: "v2"),
        context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity])
      )
    }

    let rendered = updated.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("Chrome:fixed"))
    #expect(rendered.contains("v2"))
    #expect(!rendered.contains("v1"))
    // The `.equatable()` boundary reuses its whole subtree through
    // `EquatableView`'s `@MainActor`-isolated `==` (opened by the @MainActor
    // comparator), so reuse covers more than one node.
    #expect(updated.diagnostics.work.resolvedNodesReused > 1)
  }

  @Test("an Equatable view reading focus is NOT memo-reused — focus changes are honored")
  func focusReadingEquatableBoundaryIsNotMemoReused() {
    // A focus-reading view with a deliberately focus-blind `==` (the footgun the
    // gate defends against): `isFocused` is read from the environment but
    // excluded from the reuse snapshot, so without the focus-key exclusion the
    // gate would reuse a stale focus rendering on the one-shot render path.
    struct FocusChrome: View, Equatable {
      let tag: Int
      @Environment(\.isFocused) private var isFocused

      var body: some View {
        Text(isFocused ? "FOCUSED:\(tag)" : "BLURRED:\(tag)")
      }

      nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tag == rhs.tag
      }
    }

    struct Root: View {
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Text("header")
          FocusChrome(tag: 1)
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("Root")

    func render(focused: Bool, invalidate: Bool) -> FrameArtifacts {
      var environmentValues = EnvironmentValues()
      environmentValues.focusedIdentity = focused ? rootIdentity : nil
      return renderer.render(
        Root(),
        context: .init(
          identity: rootIdentity,
          environmentValues: environmentValues,
          invalidatedIdentities: invalidate ? [rootIdentity] : []
        )
      )
    }

    let focusedFrame = withMemoReuse(true) { render(focused: true, invalidate: false) }
    #expect(focusedFrame.rasterSurface.lines.joined(separator: "\n").contains("FOCUSED:1"))

    // Focus drops and the root is invalidated. `FocusChrome` is a descendant of
    // the invalidated root (not self-invalidated), its `==` is focus-blind
    // (tag unchanged), and the reuse snapshot omits focus state — so only the
    // focus-key dependency exclusion keeps it out of the memo set. The render
    // must reflect the lost focus.
    let blurredFrame = withMemoReuse(true) { render(focused: false, invalidate: true) }
    let rendered = blurredFrame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("BLURRED:1"))
    #expect(!rendered.contains("FOCUSED:1"))
  }

  @Test("Equatable boundary recomputes when its content changes")
  func equatableBoundaryRecomputesOnContentChange() {
    // The chrome title changes between frames: the comparator sees Chrome's `==`
    // report a change and the boundary recomputes — never serves the stale
    // subtree.
    for gate in [false, true] {
      let frame = withMemoReuse(gate) {
        renderFrames(chrome1: "old", dynamic1: "v1", chrome2: "new", dynamic2: "v2")
      }
      let rendered = frame.rasterSurface.lines.joined(separator: "\n")
      #expect(rendered.contains("Chrome:new"))
      #expect(!rendered.contains("Chrome:old"))
      #expect(rendered.contains("v2"))
    }
  }
}
