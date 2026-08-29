import Testing

@testable import SwiftTUIGraph

/// The parent-detached keep-guard's proxies are LIVENESS proxies, not lifetime
/// anchors, so the keep they justify is provisional — the cascade that reached
/// the node is not finished, and every later stage of it severs edges without
/// looking at a node already in the walk's entered set. The measured shape is a
/// `Picker`'s detached `PickerOptions/Group[i]` results: the departing control's
/// hosted-detached descent enters one, the keep-guard keeps it on its
/// identity-index entry, and the SAME control's relation-target loop then
/// removes `parent`/`committedValue`/`hostedDetached` to it and skips it as
/// already-entered — leaving it stored, anchorless and unreachable for the F91
/// census to report. This suite pins both directions of the barrier verdict the
/// keep now defers to.
@MainActor
@Suite("Parent-detached keep-guard barrier verdict")
struct ParentDetachedKeepGuardBarrierTests {
  private let rootIdentity = testIdentity("KeepGuardRoot")
  private let controlIdentity = testIdentity("KeepGuardRoot", "Control")
  private let keeperIdentity = testIdentity("KeepGuardRoot", "Keeper")
  private let optionIdentity = testIdentity("KeepGuardRoot", "Control", "Option")

  /// Frame 1: the control commits under the root and resolves one DETACHED
  /// result (the picker-option shape) that no children array holds. The
  /// resolve-lifetime scope anchors it to the control and nothing else.
  private func buildCommittedControlWithDetachedOption(
    in graph: ViewGraph,
    keeperCommitted: Bool
  ) {
    graph.beginFrame()
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let controlNode = graph.beginEvaluation(identity: controlIdentity, invalidator: nil)
    let optionNode = graph.beginEvaluation(identity: optionIdentity, invalidator: nil)
    let resolvedOption =
      graph.finishEvaluation(
        optionNode,
        resolved: ResolvedNode(identity: optionIdentity, kind: .view("Option")),
        accessedStateSlots: 0
      ) ?? ResolvedNode(identity: optionIdentity, kind: .view("Option"))
    graph.withResolveLifetimeScope(hostedBy: controlNode) {
      graph.reportDetachedResolvedLifetimeResult(resolvedOption)
    }
    let resolvedControl =
      graph.finishEvaluation(
        controlNode,
        resolved: ResolvedNode(identity: controlIdentity, kind: .view("Control")),
        accessedStateSlots: 0
      ) ?? ResolvedNode(identity: controlIdentity, kind: .view("Control"))

    var rootChildren = [resolvedControl]
    if keeperCommitted {
      let keeperNode = graph.beginEvaluation(identity: keeperIdentity, invalidator: nil)
      let resolvedKeeper =
        graph.finishEvaluation(
          keeperNode,
          resolved: ResolvedNode(identity: keeperIdentity, kind: .view("Keeper")),
          accessedStateSlots: 0
        ) ?? ResolvedNode(identity: keeperIdentity, kind: .view("Keeper"))
      rootChildren.append(resolvedKeeper)
    }
    graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(identity: rootIdentity, kind: .root, children: rootChildren),
      accessedStateSlots: 0
    )
    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)
  }

  @Test("a proxy-kept parent-detached node is reclaimed at the barrier")
  func proxyKeptParentDetachedNodeIsReclaimedAtTheBarrier() {
    let graph = ViewGraph()
    buildCommittedControlWithDetachedOption(in: graph, keeperCommitted: false)

    // Next frame: a superseded pass re-visits the detached option …
    graph.beginFrame()
    let optionNode = graph.beginEvaluation(identity: optionIdentity, invalidator: nil)
    _ = graph.finishEvaluation(
      optionNode,
      resolved: ResolvedNode(identity: optionIdentity, kind: .view("Option")),
      accessedStateSlots: 0
    )
    #expect(
      optionNode.parent == nil,
      "the detached option must stay parent-detached (the guard's precondition)"
    )
    // … and the committed pass drops the control. Its teardown enters the
    // option through the hosted-detached edge, the keep-guard keeps it on its
    // identity-index entry, and the control's relation loop then severs the
    // last edge naming it.
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    _ = graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(identity: rootIdentity, kind: .root, children: []),
      accessedStateSlots: 0
    )
    #expect(
      graph.nodeIfExists(for: controlIdentity) == nil,
      "the dropped control must be torn down by the structural child diff"
    )
    #expect(
      graph.nodeIfExists(for: optionIdentity) === optionNode,
      "the option must be kept by the parent-detached guard (the shape under test)"
    )
    #expect(
      graph.lifetimeAnchors.anchors(for: optionNode.viewNodeID).isEmpty,
      "the departing control's cascade must have severed every edge naming the option"
    )
    #expect(
      graph.teardownBarrierWork.reasons(for: optionNode.viewNodeID)
        .contains(.sparedVisitedDescent),
      "a proxy-justified keep must enqueue the node for the barrier verdict"
    )

    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)

    #expect(
      graph.nodeIfExists(for: optionIdentity) == nil,
      "an anchor-less proxy-kept node must be reclaimed at the frame barrier"
    )
    let violation = graph.debugTeardownCoherenceViolation()
    #expect(
      violation == nil,
      "the proxy-kept option stranded stored node(s): \(violation?.detail ?? "")"
    )
  }

  @Test("a proxy-kept node re-hosted before the barrier survives it")
  func proxyKeptParentDetachedNodeReHostedBeforeTheBarrierSurvives() {
    let graph = ViewGraph()
    buildCommittedControlWithDetachedOption(in: graph, keeperCommitted: true)

    graph.beginFrame()
    let optionNode = graph.beginEvaluation(identity: optionIdentity, invalidator: nil)
    let resolvedOption =
      graph.finishEvaluation(
        optionNode,
        resolved: ResolvedNode(identity: optionIdentity, kind: .view("Option")),
        accessedStateSlots: 0
      ) ?? ResolvedNode(identity: optionIdentity, kind: .view("Option"))
    let keeperNode = graph.beginEvaluation(identity: keeperIdentity, invalidator: nil)
    let resolvedKeeper =
      graph.finishEvaluation(
        keeperNode,
        resolved: ResolvedNode(identity: keeperIdentity, kind: .view("Keeper")),
        accessedStateSlots: 0
      ) ?? ResolvedNode(identity: keeperIdentity, kind: .view("Keeper"))
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    _ = graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(identity: rootIdentity, kind: .root, children: [resolvedKeeper]),
      accessedStateSlots: 0
    )
    #expect(
      graph.nodeIfExists(for: controlIdentity) == nil,
      "the dropped control must be torn down by the structural child diff"
    )
    // The surviving keeper re-declares the option as its own detached content
    // AFTER the departing control's cascade stripped it — a genuine re-adoption
    // that lands as a durable anchor before the barrier reads reachability.
    graph.withResolveLifetimeScope(hostedBy: keeperNode) {
      graph.reportDetachedResolvedLifetimeResult(resolvedOption)
    }

    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)

    #expect(
      graph.nodeIfExists(for: optionIdentity) === optionNode,
      "a re-hosted proxy-kept node must survive the barrier verdict"
    )
    let violation = graph.debugTeardownCoherenceViolation()
    #expect(
      violation == nil,
      "the re-hosted option left an incoherent store: \(violation?.detail ?? "")"
    )
  }
}
