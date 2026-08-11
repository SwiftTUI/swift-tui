import SwiftTUICore
import Synchronization
import Testing

@testable import SwiftTUIViews

/// Owning tests for the persistent custom-`Layout` cache store (plan
/// 2026-08-11-004 Stage 2).
///
/// Persistence is observable only for layouts that override `updateCache`
/// with an incremental refresh: the protocol's default re-makes the cache on
/// every read (the SwiftUI contract), so these fixtures override it to a
/// no-op and mint a nonce per `makeCache` — a served pass carries the OLD
/// nonce where a fresh pass mints a new one.
@MainActor
@Suite("Persistent custom-layout caches (plan 2026-08-11-004 Stage 2)")
struct PersistentCustomLayoutCacheTests {
  private static let proposal = ProposedSize(width: 40, height: 12)

  @Test("a committed cache serves the next pass without a fresh makeCache")
  func committedCacheServesNextPass() throws {
    let probe = CacheProbe()
    let node = containerNode("persist", layout: FixedSizeNonceLayout(probe: probe))
    let store = CustomLayoutCacheStore()
    let engine = LayoutEngine()

    let firstContext = LayoutPassContext(customLayoutCacheStore: store)
    let measured = engine.measure(node, proposal: Self.proposal, passContext: firstContext)
    _ = engine.place(
      node,
      measured: measured,
      in: .init(origin: .zero, size: measured.measuredSize),
      passContext: firstContext
    )

    // Commit gating: nothing lands in the store until the renderer applies
    // the recorded updates at frame commit.
    #expect(store.isEmpty)
    let updates = firstContext.workerCustomLayoutCacheUpdates
    #expect(updates.count == 1)
    for update in updates {
      update.apply()
    }
    #expect(!store.isEmpty)

    let secondContext = LayoutPassContext(customLayoutCacheStore: store)
    _ = engine.measure(node, proposal: Self.proposal, passContext: secondContext)

    #expect(store.metrics.serves == 1)
    #expect(secondContext.runtimeIssues.isEmpty)
  }

  @Test("an unapplied update persists nothing (abandoned frame candidates)")
  func unappliedUpdatePersistsNothing() {
    let probe = CacheProbe()
    let node = containerNode("abandoned", layout: FixedSizeNonceLayout(probe: probe))
    let store = CustomLayoutCacheStore()
    let engine = LayoutEngine()

    let firstContext = LayoutPassContext(customLayoutCacheStore: store)
    let measured = engine.measure(node, proposal: Self.proposal, passContext: firstContext)
    _ = engine.place(
      node,
      measured: measured,
      in: .init(origin: .zero, size: measured.measuredSize),
      passContext: firstContext
    )

    let secondContext = LayoutPassContext(customLayoutCacheStore: store)
    _ = engine.measure(node, proposal: Self.proposal, passContext: secondContext)

    #expect(store.isEmpty)
    #expect(store.metrics.serves == 0)
  }

  @Test("an invalidated container is denied the persisted serve")
  func invalidatedContainerDeniesServe() {
    let probe = CacheProbe()
    let node = containerNode("invalidated", layout: FixedSizeNonceLayout(probe: probe))
    let store = CustomLayoutCacheStore()
    let engine = LayoutEngine()

    let firstContext = LayoutPassContext(customLayoutCacheStore: store)
    let measured = engine.measure(node, proposal: Self.proposal, passContext: firstContext)
    _ = engine.place(
      node,
      measured: measured,
      in: .init(origin: .zero, size: measured.measuredSize),
      passContext: firstContext
    )
    for update in firstContext.workerCustomLayoutCacheUpdates {
      update.apply()
    }

    let secondContext = LayoutPassContext(
      customLayoutCacheStore: store,
      invalidatedIdentities: [node.identity]
    )
    _ = engine.measure(node, proposal: Self.proposal, passContext: secondContext)

    #expect(store.metrics.serves == 0)
  }

  @Test("a content change evicts the stored entry through equivalence")
  func contentChangeEvictsEntry() {
    let probe = CacheProbe()
    let layout = FixedSizeNonceLayout(probe: probe)
    let before = containerNode("evolving", layout: layout, childWidth: 6)
    let after = containerNode("evolving", layout: layout, childWidth: 9)
    let store = CustomLayoutCacheStore()

    store.store(
      Int(1),
      resolved: before,
      proposal: Self.proposal,
      layoutDebugName: "FixedSizeNonceLayout"
    )
    let served = store.lookup(
      resolved: after,
      proposal: Self.proposal,
      layoutDebugName: "FixedSizeNonceLayout"
    )

    #expect(served == nil)
    #expect(store.metrics.invalidations == 1)
    #expect(store.isEmpty)
  }

  @Test("a pass-coupled cache is caught by the divergence check (red proof)")
  func divergentCacheIsCaught() {
    let probe = CacheProbe()
    let node = containerNode("divergent", layout: NonceSizedLayout(probe: probe))
    let store = CustomLayoutCacheStore()
    let engine = LayoutEngine()

    let firstContext = LayoutPassContext(customLayoutCacheStore: store)
    let measured = engine.measure(node, proposal: Self.proposal, passContext: firstContext)
    _ = engine.place(
      node,
      measured: measured,
      in: .init(origin: .zero, size: measured.measuredSize),
      passContext: firstContext
    )
    for update in firstContext.workerCustomLayoutCacheUpdates {
      update.apply()
    }

    let secondContext = LayoutPassContext(customLayoutCacheStore: store)
    _ = engine.measure(node, proposal: Self.proposal, passContext: secondContext)

    // NonceSizedLayout sizes from its cache nonce, so the served (stale)
    // nonce and the verification's fresh nonce disagree — exactly the
    // pass-coupled state the check exists to catch. Record-only.
    #expect(
      secondContext.runtimeIssues.contains { issue in
        issue.code == "layout.persistedCacheDivergence"
      }
    )
  }

  @Test("a placement-time serve verifies recorded placements (red proof)")
  func divergentPlacementIsCaught() {
    let probe = CacheProbe()
    let node = containerNode("placement", layout: NoncePlacingLayout(probe: probe))
    let store = CustomLayoutCacheStore()
    let engine = LayoutEngine()

    let firstContext = LayoutPassContext(customLayoutCacheStore: store)
    let measured = engine.measure(node, proposal: Self.proposal, passContext: firstContext)
    _ = engine.place(
      node,
      measured: measured,
      in: .init(origin: .zero, size: measured.measuredSize),
      passContext: firstContext
    )
    for update in firstContext.workerCustomLayoutCacheUpdates {
      update.apply()
    }

    // Placement directly against a fresh context: no in-pass bridge entry
    // exists, so the store serves at placement and the placement-leg
    // verification compares recorded positions.
    let secondContext = LayoutPassContext(customLayoutCacheStore: store)
    _ = engine.place(
      node,
      measured: measured,
      in: .init(origin: .zero, size: measured.measuredSize),
      passContext: secondContext
    )

    #expect(
      secondContext.runtimeIssues.contains { issue in
        issue.code == "layout.persistedCacheDivergence"
      }
    )
  }

  @Test("the store keeps at most four proposal variants per identity")
  func storeCapsProposalVariants() {
    let node = containerNode("capped", layout: FixedSizeNonceLayout(probe: CacheProbe()))
    let store = CustomLayoutCacheStore()

    for width in 1...5 {
      store.store(
        width,
        resolved: node,
        proposal: ProposedSize(width: width, height: 10),
        layoutDebugName: "FixedSizeNonceLayout"
      )
    }

    #expect(store.count == 4)
  }

  @Test("prune drops departed identities and keeps live ones")
  func pruneDropsDepartedIdentities() {
    let kept = containerNode("kept", layout: FixedSizeNonceLayout(probe: CacheProbe()))
    let departed = containerNode("departed", layout: FixedSizeNonceLayout(probe: CacheProbe()))
    let store = CustomLayoutCacheStore()
    store.store(
      Int(1), resolved: kept, proposal: Self.proposal,
      layoutDebugName: "FixedSizeNonceLayout")
    store.store(
      Int(2), resolved: departed, proposal: Self.proposal,
      layoutDebugName: "FixedSizeNonceLayout")

    store.prune(keeping: [kept.identity])

    #expect(store.count == 1)
    #expect(
      store.lookup(
        resolved: kept, proposal: Self.proposal,
        layoutDebugName: "FixedSizeNonceLayout") != nil
    )
    #expect(
      store.lookup(
        resolved: departed, proposal: Self.proposal,
        layoutDebugName: "FixedSizeNonceLayout") == nil
    )
  }

  @Test("a different layout type at a reused identity misses, never casts")
  func layoutTypeDiscriminatorMisses() {
    let node = containerNode("retyped", layout: FixedSizeNonceLayout(probe: CacheProbe()))
    let store = CustomLayoutCacheStore()
    store.store(
      Int(1), resolved: node, proposal: Self.proposal,
      layoutDebugName: "FixedSizeNonceLayout")

    let served = store.lookup(
      resolved: node,
      proposal: Self.proposal,
      layoutDebugName: "SomeOtherLayout"
    )

    #expect(served == nil)
  }

  // MARK: - Fixtures

  private func containerNode(
    _ name: String,
    layout: some Layout,
    childWidth: Int = 6
  ) -> ResolvedNode {
    ResolvedNode(
      identity: testIdentity(name),
      kind: .view("PersistentCacheFixture"),
      children: [
        ResolvedNode(
          identity: testIdentity("\(name)-a"),
          kind: .view("Test"),
          intrinsicSize: .init(width: childWidth, height: 2)
        ),
        ResolvedNode(
          identity: testIdentity("\(name)-b"),
          kind: .view("Test"),
          intrinsicSize: .init(width: childWidth, height: 2)
        ),
      ],
      layoutBehavior: AnyLayout(layout).resolvedBehavior
    )
  }
}

/// Counts `makeCache` mints and hands each a fresh nonce.
private final class CacheProbe: Sendable {
  private let makes = Mutex<Int>(0)

  var makeCount: Int {
    makes.withLock { $0 }
  }

  func mintNonce() -> Int {
    makes.withLock { count in
      count += 1
      return count
    }
  }
}

/// Well-behaved persistence fixture: the nonce rides the cache but never
/// leaks into geometry, so a served pass is byte-identical to a fresh one.
private struct FixedSizeNonceLayout: Layout {
  let probe: CacheProbe

  func makeCache(subviews _: LayoutSubviews) -> Int {
    probe.mintNonce()
  }

  func updateCache(_ cache: inout Int, subviews _: LayoutSubviews) {}

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache _: inout Int
  ) -> LayoutSize {
    .init(width: 12, height: 4)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Int
  ) {
    for (index, subview) in subviews.enumerated() {
      subview.place(
        at: .init(x: bounds.origin.x, y: bounds.origin.y + index * 2),
        proposal: .init(width: .finite(6), height: .finite(2))
      )
    }
  }
}

/// Pass-coupled MEASURE fixture: the size derives from the cache nonce, the
/// purity violation the divergence check's size leg must catch.
private struct NonceSizedLayout: Layout {
  let probe: CacheProbe

  func makeCache(subviews _: LayoutSubviews) -> Int {
    probe.mintNonce()
  }

  func updateCache(_ cache: inout Int, subviews _: LayoutSubviews) {}

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache: inout Int
  ) -> LayoutSize {
    .init(width: 10 + cache, height: 4)
  }

  func placeSubviews(
    in _: LayoutRect,
    proposal _: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache _: inout Int
  ) {}
}

/// Pass-coupled PLACEMENT fixture: subview positions derive from the cache
/// nonce, the violation the placement leg must catch.
private struct NoncePlacingLayout: Layout {
  let probe: CacheProbe

  func makeCache(subviews _: LayoutSubviews) -> Int {
    probe.mintNonce()
  }

  func updateCache(_ cache: inout Int, subviews _: LayoutSubviews) {}

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache _: inout Int
  ) -> LayoutSize {
    .init(width: 12, height: 8)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Int
  ) {
    for (index, subview) in subviews.enumerated() {
      subview.place(
        at: .init(x: bounds.origin.x + cache, y: bounds.origin.y + index * 2),
        proposal: .init(width: .finite(6), height: .finite(2))
      )
    }
  }
}
