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
  ) -> RenderSnapshot {
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

  @Test("Equatable boundary reuses its subtree when unchanged")
  func equatableBoundaryReusesUnchangedSubtree() {
    let frame = renderFrames(
      chrome1: "fixed", dynamic1: "v1", chrome2: "fixed", dynamic2: "v2")

    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("Chrome:fixed"))
    #expect(rendered.contains("Static"))
    #expect(rendered.contains("v2"))
    #expect(!rendered.contains("v1"))

    // The `Chrome` boundary's WHOLE subtree is reused via one comparison (its
    // node plus the VStack and both Texts) — not just the leaves — while the
    // changed dynamic Text still recomputes. So reuse covers more than one node.
    #expect(frame.diagnostics.work.resolvedNodesReused > 1)
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
    _ = renderer.render(
      WrappedRoot(title: "fixed", dynamic: "v1"),
      context: .init(identity: rootIdentity)
    )
    let updated = renderer.render(
      WrappedRoot(title: "fixed", dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity])
    )

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

    func render(focused: Bool, invalidate: Bool) -> RenderSnapshot {
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

    let focusedFrame = render(focused: true, invalidate: false)
    #expect(focusedFrame.rasterSurface.lines.joined(separator: "\n").contains("FOCUSED:1"))

    // Focus drops and the root is invalidated. `FocusChrome` is a descendant of
    // the invalidated root (not self-invalidated), its `==` is focus-blind
    // (tag unchanged), and the reuse snapshot omits focus state — so only the
    // focus-key dependency exclusion keeps it out of the memo set. The render
    // must reflect the lost focus.
    let blurredFrame = render(focused: false, invalidate: true)
    let rendered = blurredFrame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("BLURRED:1"))
    #expect(!rendered.contains("FOCUSED:1"))
  }

  /// P0 (eval task #16): the one-shot `DefaultRenderer.render()` path is NOT
  /// focus/press-reuse-safe. A control (`Button`) reads `focusedIdentity` /
  /// `pressedIdentity` *directly* off the environment (not via `@Environment`), so
  /// it records NO dependency — unlike the `@Environment(\.isFocused)` reader in
  /// `focusReadingEquatableBoundaryIsNotMemoReused`, which the gate DOES catch. So
  /// an Equatable boundary wrapping such a control is memo-reused across a
  /// focus/press change on the one-shot path (focus/press are excluded from the
  /// reuse snapshot, and the run loop's suppression scope — which protects this in
  /// interactive use — is not computed one-shot). This test PINS that documented
  /// limitation; the live run loop is the focus/press-safe interactive path.
  @Test(
    "one-shot render() memo-reuses an Equatable boundary wrapping a focus-reading control across a focus change (documented limitation)"
  )
  func oneShotEquatableBoundaryReusesAcrossFocusChangeOfDirectReadingControl() {
    struct ControlBoundary: View, Equatable {
      let tag: Int  // constant across frames => == is focus/press-blind

      var body: some View {
        Button("press-me") {}
      }
    }

    struct Root: View {
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          ControlBoundary(tag: 1)
          Text("footer")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("Root")

    func render(focused: Bool, invalidate: Bool) -> RenderSnapshot {
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

    _ = render(focused: true, invalidate: false)
    let updated = render(focused: false, invalidate: true)

    // The boundary subtree is reused even though focus changed — the gap. (If a
    // future fix makes direct-reading controls record the focus/press dependency,
    // this flips to recompute; update this test and the `render()` doc together.)
    #expect(updated.diagnostics.work.resolvedNodesReused > 0)
    #expect(updated.rasterSurface.lines.joined(separator: "\n").contains("press-me"))
  }

  @Test(
    ".equatable() works inside a ForEach: rows render and memo-reuse across ancestor invalidation")
  func equatableBoundaryInsideForEachReusesAndRenders() {
    struct Row: View, Equatable {
      let index: Int

      var body: some View {
        Text("row-\(index)")
      }
    }

    struct ListRoot: View {
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Text(dynamic)
          ForEach(Array(0..<4), id: \.self) { index in
            Row(index: index).equatable()
          }
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("Root")

    func renderFrames() -> RenderSnapshot {
      _ = renderer.render(ListRoot(dynamic: "v1"), context: .init(identity: rootIdentity))
      return renderer.render(
        ListRoot(dynamic: "v2"),
        context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity])
      )
    }

    let updated = renderFrames()

    // The `.equatable()` rows (each its own boundary node inside the ForEach)
    // render correctly and are memo-reused under ancestor invalidation, while the
    // changed header recomputes. Identity is stable enough that reuse fires.
    let rendered = updated.rasterSurface.lines.joined(separator: "\n")
    for index in 0..<4 {
      #expect(rendered.contains("row-\(index)"))
    }
    #expect(rendered.contains("v2"))
    #expect(updated.diagnostics.work.resolvedNodesReused > 0)
  }

  /// P2 (eval task #16): the memo diagnostic flags an *inert* opt-in — a view
  /// the author conformed to `Equatable` (expecting memoization) that reads
  /// `@State`/`@Observable`/focus, so the gate denies it and `.equatable()` is a
  /// silent no-op. The #1 adoption trap.
  @Test("memo diagnostic flags an inert Equatable opt-in (reads @State -> never memo-reused)")
  func inertEquatableOptInIsDiagnosed() {
    struct InertChrome: View, Equatable {
      let tag: Int
      @State private var counter = 0

      var body: some View {
        // Reads @State -> records a dependency -> gate denies despite the
        // Equatable conformance. The `==` is `@State`-blind (compares `tag`).
        Text("inert:\(tag):\(counter)")
      }

      nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tag == rhs.tag
      }
    }

    struct Root: View {
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Text(dynamic)
          InertChrome(tag: 1)
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("Root")

    let prior = MemoTraceState.capture()
    MemoSkipTrace.isEnabled = true
    MemoSkipTrace.sampleEveryNFrames = 1
    MemoSkipTrace.isSampledFrame = false
    MemoSkipTrace.reset()
    // Route the per-frame trace dump to a file so it does not spam stderr.
    MemoSkipTrace.outputFilePath = "/tmp/swifttui-inert-diagnostic-test.txt"
    MemoSkipTrace.emitsTraceLines = true
    defer {
      prior.restore()
    }

    _ = renderer.render(Root(dynamic: "v1"), context: .init(identity: rootIdentity))
    // Frame 2 invalidates the root, reaching InertChrome (a descendant). Its
    // value is `==` (tag unchanged) and it passes the reuse guards, but it reads
    // @State -> the production gate denies it. The oracle records it as inert.
    _ = renderer.render(
      Root(dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity])
    )

    // `dumpAndReset` runs at the next frame's start, so after frame 2 the live
    // counter still holds frame 2's count.
    #expect(MemoSkipTrace.inertEquatableBoundary > 0)
  }

  @Test("memo diagnostic observes sampled frames only")
  func memoDiagnosticObservesSampledFramesOnly() {
    struct Root: View {
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Chrome(title: "fixed")
          Text(dynamic)
        }
      }
    }

    func renderTwoFrames() {
      let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
      let rootIdentity = testIdentity("Root")
      _ = renderer.render(Root(dynamic: "v1"), context: .init(identity: rootIdentity))
      _ = renderer.render(
        Root(dynamic: "v2"),
        context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity])
      )
    }

    let prior = MemoTraceState.capture()
    defer { prior.restore() }

    MemoSkipTrace.isEnabled = true
    MemoSkipTrace.sampleEveryNFrames = 100
    MemoSkipTrace.isSampledFrame = false
    MemoSkipTrace.emitsTraceLines = false
    MemoSkipTrace.reset()
    renderTwoFrames()
    #expect(MemoSkipTrace.computed == 0)

    MemoSkipTrace.sampleEveryNFrames = 1
    MemoSkipTrace.isSampledFrame = false
    MemoSkipTrace.reset()
    renderTwoFrames()
    #expect(MemoSkipTrace.computed > 0)
  }

  @Test("Equatable boundary recomputes when its content changes")
  func equatableBoundaryRecomputesOnContentChange() {
    // The chrome title changes between frames: the comparator sees Chrome's `==`
    // report a change and the boundary recomputes — never serves the stale
    // subtree.
    let frame = renderFrames(chrome1: "old", dynamic1: "v1", chrome2: "new", dynamic2: "v2")
    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("Chrome:new"))
    #expect(!rendered.contains("Chrome:old"))
    #expect(rendered.contains("v2"))
  }

  @Test("representative memo scenarios raise no memo-soundness alarm")
  func memoScenariosRaiseNoMemoSoundnessAlarm() {
    // The F90 alarm class — a no-reads *content* divergence on a would-skip
    // node — must stay 0 across the population the oracle observes every
    // frame. Renders both the Equatable-boundary fixture and a ForEach entity
    // fixture: entity rows re-stamp occurrence ordinals between frames (the
    // known bookkeeping-noise class), which must feed the histogram only,
    // never the alarm.
    struct EntityRoot: View {
      let dynamic: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Text(dynamic)
          ForEach(Array(0..<4), id: \.self) { index in
            Text("row-\(index)")
          }
        }
      }
    }

    let prior = MemoTraceState.capture()
    let alarmBefore = SoundnessProbeConfiguration.memoUnsoundSkipCount
    defer {
      prior.restore()
      SoundnessProbeConfiguration.memoUnsoundSkipCount = alarmBefore
    }
    MemoSkipTrace.isEnabled = true
    MemoSkipTrace.sampleEveryNFrames = 1
    MemoSkipTrace.isSampledFrame = false
    MemoSkipTrace.emitsTraceLines = false
    MemoSkipTrace.reset()

    _ = renderFrames(chrome1: "fixed", dynamic1: "v1", chrome2: "fixed", dynamic2: "v2")

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("Root")
    _ = renderer.render(EntityRoot(dynamic: "v1"), context: .init(identity: rootIdentity))
    _ = renderer.render(
      EntityRoot(dynamic: "v2"),
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity])
    )

    #expect(SoundnessProbeConfiguration.memoUnsoundSkipCount == alarmBefore)
  }

  private struct MemoTraceState {
    let isEnabled: Bool
    let sampleEveryNFrames: Int
    let isSampledFrame: Bool
    let outputFilePath: String?
    let emitsTraceLines: Bool

    @MainActor
    static func capture() -> Self {
      Self(
        isEnabled: MemoSkipTrace.isEnabled,
        sampleEveryNFrames: MemoSkipTrace.sampleEveryNFrames,
        isSampledFrame: MemoSkipTrace.isSampledFrame,
        outputFilePath: MemoSkipTrace.outputFilePath,
        emitsTraceLines: MemoSkipTrace.emitsTraceLines
      )
    }

    @MainActor
    func restore() {
      MemoSkipTrace.isEnabled = isEnabled
      MemoSkipTrace.sampleEveryNFrames = sampleEveryNFrames
      MemoSkipTrace.isSampledFrame = isSampledFrame
      MemoSkipTrace.outputFilePath = outputFilePath
      MemoSkipTrace.emitsTraceLines = emitsTraceLines
      MemoSkipTrace.reset()
    }
  }
}
