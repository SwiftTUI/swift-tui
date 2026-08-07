import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Implicit structural memoization, end to end: a read-free boundary view that
/// is NOT `Equatable` gets its subtree reused by the memo gate when its view
/// value is unchanged — through the per-type comparison plan (field tier /
/// byte tier) rather than an author opt-in. Companion to
/// `EquatableBoundaryReuseTests` (the opt-in tier) and
/// `MemoComparisonPlanTests` (the plan builder).
@MainActor
@Suite
struct ImplicitMemoReuseTests {
  /// Field-tier boundary: a `String` field keeps the type non-POD, and it
  /// deliberately does NOT conform to `Equatable`.
  private struct FieldChrome: View {
    let title: String
    let width: Int

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("Chrome:\(title):\(width)")
        Text("Static")
      }
    }
  }

  /// Byte-tier boundary: packed POD stored properties, not `Equatable`.
  private struct PodChrome: View {
    let count: Int
    let scale: Double

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("Pod:\(count):\(scale)")
        Text("Static")
      }
    }
  }

  /// Unplannable boundary: the stored closure keeps the type off every tier.
  private struct ClosureChrome: View {
    let title: String
    let onSelect: () -> Void

    var body: some View {
      Text("Closure:\(title)")
    }
  }

  private func renderTwoFrames<Root: View>(
    first: Root,
    second: Root
  ) -> RenderSnapshot {
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("Root")
    _ = renderer.render(first, context: .init(identity: rootIdentity))
    return renderer.render(
      second,
      context: .init(identity: rootIdentity, invalidatedIdentities: [rootIdentity])
    )
  }

  @Test("a non-Equatable field-tier boundary reuses its unchanged subtree")
  func fieldTierBoundaryReuses() {
    struct Root: View {
      let dynamic: String
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          FieldChrome(title: "fixed", width: 4)
          Text(dynamic)
        }
      }
    }

    let frame = renderTwoFrames(
      first: Root(dynamic: "v1"),
      second: Root(dynamic: "v2")
    )
    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("Chrome:fixed:4"))
    #expect(rendered.contains("v2"))
    #expect(!rendered.contains("v1"))
    // The whole chrome subtree (its node, the VStack, both Texts) is served
    // by the memo gate without any Equatable conformance.
    #expect(frame.diagnostics.work.resolvedNodesReused > 1)
  }

  @Test("a byte-tier boundary reuses its unchanged subtree")
  func byteTierBoundaryReuses() {
    struct Root: View {
      let dynamic: String
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          PodChrome(count: 3, scale: 1.5)
          Text(dynamic)
        }
      }
    }

    let frame = renderTwoFrames(
      first: Root(dynamic: "v1"),
      second: Root(dynamic: "v2")
    )
    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("Pod:3:1.5"))
    #expect(rendered.contains("v2"))
    #expect(frame.diagnostics.work.resolvedNodesReused > 1)
  }

  @Test("a changed boundary value recomputes and renders fresh content")
  func changedBoundaryRecomputes() {
    struct Root: View {
      let title: String
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          FieldChrome(title: title, width: 4)
          Text("tail")
        }
      }
    }

    let frame = renderTwoFrames(
      first: Root(title: "before"),
      second: Root(title: "after")
    )
    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    // Soundness end to end: no stale chrome may survive the value change.
    #expect(rendered.contains("Chrome:after:4"))
    #expect(!rendered.contains("Chrome:before:4"))
  }

  @Test("a class-box boundary refreshes mutated contents on a forced re-render")
  func classBoxBoundaryRefreshesOnForcedRerender() {
    final class ContentBox {
      var value = "before"
    }
    struct BoxedChrome: View {
      let box: ContentBox
      var body: some View {
        Text("Boxed:\(box.value)")
      }
    }
    struct Root: View {
      let box: ContentBox
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          BoxedChrome(box: box)
          Text("tail")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("Root")
    let box = ContentBox()
    _ = renderer.render(Root(box: box), context: .init(identity: rootIdentity))
    box.value = "after"
    // A forced re-render (empty, uncertified invalidation set) exists to
    // refresh exactly this out-of-band channel: the reference-identity plan
    // must not serve the stale committed subtree.
    let second = renderer.render(Root(box: box), context: .init(identity: rootIdentity))
    let rendered = second.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("Boxed:after"))
    #expect(!rendered.contains("Boxed:before"))
  }

  @Test("an unplannable closure-bearing boundary still renders correctly")
  func closureBoundaryStillRecomputes() {
    struct Root: View {
      let dynamic: String
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          ClosureChrome(title: "fixed", onSelect: {})
          Text(dynamic)
        }
      }
    }

    let frame = renderTwoFrames(
      first: Root(dynamic: "v1"),
      second: Root(dynamic: "v2")
    )
    let rendered = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("Closure:fixed"))
    #expect(rendered.contains("v2"))
    #expect(!rendered.contains("v1"))
  }
}
