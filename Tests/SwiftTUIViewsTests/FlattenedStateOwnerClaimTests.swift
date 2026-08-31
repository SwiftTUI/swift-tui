import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIViews

/// Pins the single-child flattening state-owner tiebreak
/// (`ViewGraph.flattenedStateOwnerNodeIDByIdentity`) for a composite whose
/// `@State` the update pass CLAIMS but whose body never READS: the slot is
/// unmaterialized when the enclosing chain absorbs the child's element, and
/// the authored node must still be registered as the identity's state owner
/// rather than reclaimed as a stranded chain interior at the finalize
/// barrier.
///
/// The shape is sextant's `FileColumn`: `@State scrollPosition` is read only
/// inside a `GeometryReader` closure (realized in the frame tail) and written
/// by `.onChange`, and the view sits under a `switch` branch. Gating the
/// registration on materialized slots reclaimed that node at the barrier
/// after the tail had bound the `ScrollView` position binding to it — the
/// present-time scroll-translation read then hit a dead owner
/// (`state.imperativeSeedFallback`) and the re-hosted slot re-seeded.
@MainActor
struct FlattenedStateOwnerClaimTests {
  @MainActor
  final class DeferredReadSink {
    var ownerLifetime: NodeOwnerLifetimeID?
    var read: (@MainActor () -> Int)?
    var binding: Binding<Int>?
  }

  /// The body hands out a reader closure and the projected binding without
  /// reading `offset` itself, so the update pass records a slot claim on the
  /// authored node while no graph slot materializes during resolve.
  private struct DeferredReadChild: View {
    @State private var offset = 0
    let sink: DeferredReadSink

    var body: some View {
      sink.ownerLifetime = ViewNodeContext.current?.ownerLifetimeID
      sink.read = { offset }
      sink.binding = $offset
      return Text("static")
    }
  }

  /// A conditional-branch layer over the child: an identity-extending,
  /// node-less layer whose single element the enclosing chain absorbs, so the
  /// child's own node is index-shadowed by the absorber's reindex.
  private struct BranchingHost: View {
    var showsChild: Bool
    let sink: DeferredReadSink

    var body: some View {
      if showsChild {
        DeferredReadChild(sink: sink)
      } else {
        Text("empty")
      }
    }
  }

  private func drainSeedFallbackIssues() -> [RuntimeIssue] {
    ImperativeRuntimeIssueQueue.drain().filter { issue in
      issue.code == "state.imperativeSeedFallback"
    }
  }

  @Test("a claimed-but-unread @State keeps its authored node across the finalize barrier")
  func claimedStateOwnerSurvivesAbsorbedShadowReclaim() throws {
    let sink = DeferredReadSink()
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    graph.beginFrame()
    var context = ResolveContext(
      identity: rootIdentity,
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    let resolved = Resolver().resolve(
      BranchingHost(showsChild: true, sink: sink),
      in: context
    )
    let ownerLifetime = try #require(sink.ownerLifetime)
    let authoredNode = try #require(graph.nodeForOwnerLifetimeID(ownerLifetime))
    // Claimed by the update pass, never materialized by the body — the exact
    // state the flattening tiebreak used to misread as "no authored state".
    #expect(authoredNode.stateSlots.isEmpty)
    #expect(authoredNode.hostsAuthoredStateSlots)

    // The finalize barrier is where an absorbed shadow is reclaimed.
    _ = graph.previewLifecycleEventPlan(resolved: resolved, placed: nil)
    #expect(graph.nodeForOwnerLifetimeID(ownerLifetime) === authoredNode)

    // The binding the body handed out is bound to that owner (the shape a
    // `ScrollView(position:)` registration retains). It must stay
    // graph-backed: a write lands in the live slot, the read observes it,
    // and neither degrades to the authored seed.
    let binding = try #require(sink.binding)
    _ = drainSeedFallbackIssues()
    binding.wrappedValue = 7
    #expect(binding.wrappedValue == 7)
    #expect(sink.read?() == 7)
    #expect(drainSeedFallbackIssues().isEmpty)
  }
}
