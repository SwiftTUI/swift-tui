import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Characterization coverage for the pointer registry's deliberate absence
/// from the node-liveness `prune(keeping:)` fan-out (F101). The registry
/// carries node-liveness-coupled interaction state (hover recency eviction,
/// owner-paired route resolution), but its stale capture/hover routes are
/// cleaned by `RunLoop.processFocusSyncIteration`'s paired-region pass —
/// sequenced immediately after `pruneOrphanedGestures` — not by a `prune`
/// override. These tests pin that shape: if someone later adds a real
/// `prune(keeping:)` override, the no-op characterization below flips and
/// forces a review of the FocusSync sequencing it would interact with.
@MainActor
@Suite("LocalPointerHandlerRegistry liveness characterization")
struct LocalPointerHandlerRegistryTests {
  @Test("prune(keeping:) is a deliberate no-op — even for unowned handlers")
  func pruneIsANoOpForPointerHandlers() {
    // Contrast with the gesture registries: the same nil-viewNodeID owner
    // shape that gesture prune force-drops survives here, because pointer
    // route cleanup belongs to the run loop's paired-region pass (F101).
    let registry = LocalPointerHandlerRegistry()
    let pressRoute = RouteID(identity: Identity(components: [IdentityComponent(rawValue: "b")]))
    let hoverRoute = RouteID(identity: Identity(components: [IdentityComponent(rawValue: "h")]))
    // No ViewNodeContext in a unit test: `.current` owners carry no
    // viewNodeID — the exact shape gesture prune would drop.
    registry.register(routeID: pressRoute) { _ in false }
    registry.registerHover(routeID: hoverRoute) { _ in }
    #expect(registry.hasHandler(routeID: pressRoute))
    #expect(registry.hasHoverHandler(routeID: hoverRoute))

    registry.prune(keeping: [])

    #expect(registry.hasHandler(routeID: pressRoute))
    #expect(registry.hasHoverHandler(routeID: hoverRoute))
  }

  @Test("removeSubtrees remains the registry's structural teardown path")
  func removeSubtreesTearsDownHandlers() {
    let registry = LocalPointerHandlerRegistry()
    let parent = Identity(components: [IdentityComponent(rawValue: "p")])
    let childRoute = RouteID(identity: parent.child(IdentityComponent(rawValue: "c")))
    let siblingRoute = RouteID(identity: Identity(components: [IdentityComponent(rawValue: "s")]))
    registry.register(routeID: childRoute) { _ in false }
    registry.register(routeID: siblingRoute) { _ in false }

    registry.removeSubtrees(rootedAt: [parent])

    #expect(!registry.hasHandler(routeID: childRoute))
    #expect(registry.hasHandler(routeID: siblingRoute))
  }
}
