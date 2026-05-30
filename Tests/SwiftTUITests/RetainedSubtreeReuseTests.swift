import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Guards the H3 retained-subtree reuse fast path
/// (`ViewGraph.recordReusedSubtree(_:invalidator:retained:)`): when a reused
/// subtree is fully disjoint from a frame's invalidation, the runtime records
/// only its root and skips the O(subtree) descendant bookkeeping walk, relying
/// on descendant committed state, presence (`hasCommittedPresence`), and
/// liveness (`liveIdentities`) carrying forward across `beginFrame`.
///
/// The risk these tests cover is that skipping the descendant walk silently
/// drops, corrupts, or fails to carry forward a still-present subtree. They
/// assert the disjoint subtree keeps rendering its exact content across repeated
/// retained frames, at depth, and that a subtree can transition retained ->
/// recompute (and back) without losing state.
@MainActor
@Suite
struct RetainedSubtreeReuseTests {
  private struct Siblings: View {
    let aValue: String
    let bValue: String
    let aID: Identity
    let bID: Identity

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 0) {
          Text("A:\(aValue)")
        }
        .id(aID)
        VStack(alignment: .leading, spacing: 0) {
          Text("B:\(bValue)")
        }
        .id(bID)
      }
    }
  }

  /// The disjoint sibling must stay reused AND keep rendering its exact content
  /// across many consecutive invalidation frames of the *other* sibling — the
  /// core carry-forward guarantee the descendant skip relies on.
  @Test("retained sibling stays reused and correct across repeated invalidation frames")
  func retainedSiblingStableAcrossManyFrames() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let rootIdentity = testIdentity("RetainedStable")
    let aID = testIdentity("RetainedStable", "A")
    let bID = testIdentity("RetainedStable", "B")

    _ = renderer.render(
      Siblings(aValue: "0", bValue: "static", aID: aID, bID: bID),
      context: .init(identity: rootIdentity)
    )

    for frame in 1...6 {
      let result = renderer.render(
        Siblings(aValue: "\(frame)", bValue: "static", aID: aID, bID: bID),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: [aID]
        )
      )
      let rendered = result.rasterSurface.lines.joined(separator: "\n")
      // The disjoint B subtree must be reused (not recomputed) ...
      #expect(
        result.diagnostics.work.resolvedNodesReused > 0,
        "frame \(frame): disjoint B subtree must reuse"
      )
      // ... and must still render its exact, unchanged content every frame.
      #expect(rendered.contains("B:static"), "frame \(frame): B content lost")
      // ... while the invalidated A subtree reflects the new value.
      #expect(rendered.contains("A:\(frame)"), "frame \(frame): A not updated")
    }
  }

  /// A retained subtree may be skipped for several frames, then itself become
  /// invalidated. It must recompute correctly from the carried-forward state
  /// (the frame gap must not leave it stale) — exercises the `prepareForFrame`
  /// frame-ID reconciliation across the skipped frames.
  @Test("a retained subtree recomputes correctly after being invalidated")
  func retainedSubtreeRecomputesAfterInvalidation() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let rootIdentity = testIdentity("RetainedThenInvalidate")
    let aID = testIdentity("RetainedThenInvalidate", "A")
    let bID = testIdentity("RetainedThenInvalidate", "B")

    _ = renderer.render(
      Siblings(aValue: "0", bValue: "first", aID: aID, bID: bID),
      context: .init(identity: rootIdentity)
    )

    // Several frames where B is retained (only A invalidated).
    for frame in 1...3 {
      _ = renderer.render(
        Siblings(aValue: "\(frame)", bValue: "first", aID: aID, bID: bID),
        context: .init(identity: rootIdentity, invalidatedIdentities: [aID])
      )
    }

    // Now invalidate B itself with new content: it must recompute, not stay
    // stuck on the carried-forward snapshot.
    let updated = renderer.render(
      Siblings(aValue: "3", bValue: "second", aID: aID, bID: bID),
      context: .init(identity: rootIdentity, invalidatedIdentities: [bID])
    )
    let rendered = updated.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("B:second"), "B failed to recompute after retained frames")
    #expect(!rendered.contains("B:first"), "B is stale after retained frames")
    #expect(rendered.contains("A:3"), "A content lost on B-invalidation frame")
  }

  /// The descendant skip must not lose *deep* content: a disjoint subtree with
  /// several nesting levels must surface all of them after reuse (its committed
  /// snapshot carries the whole subtree by value).
  @Test("retained reuse preserves a deeply nested disjoint subtree")
  func retainedReusePreservesDeepSubtree() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let rootIdentity = testIdentity("RetainedDeep")
    let aID = testIdentity("RetainedDeep", "A")
    let deepID = testIdentity("RetainedDeep", "Deep")

    struct DeepSiblings: View {
      let aValue: String
      let aID: Identity
      let deepID: Identity

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          VStack(alignment: .leading, spacing: 0) {
            Text("A:\(aValue)")
          }
          .id(aID)
          VStack(alignment: .leading, spacing: 0) {
            Text("L1")
            VStack(alignment: .leading, spacing: 0) {
              Text("L2")
              VStack(alignment: .leading, spacing: 0) {
                Text("L3-leaf")
              }
            }
          }
          .id(deepID)
        }
      }
    }

    _ = renderer.render(
      DeepSiblings(aValue: "0", aID: aID, deepID: deepID),
      context: .init(identity: rootIdentity)
    )

    let updated = renderer.render(
      DeepSiblings(aValue: "1", aID: aID, deepID: deepID),
      context: .init(identity: rootIdentity, invalidatedIdentities: [aID])
    )
    let rendered = updated.rasterSurface.lines.joined(separator: "\n")
    #expect(updated.diagnostics.work.resolvedNodesReused > 0, "deep subtree must reuse")
    #expect(rendered.contains("L1"), "deep level 1 lost")
    #expect(rendered.contains("L2"), "deep level 2 lost")
    #expect(rendered.contains("L3-leaf"), "deep leaf lost")
    #expect(rendered.contains("A:1"), "A not updated")
  }
}
