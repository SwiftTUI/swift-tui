import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Wave-1 regression hunt over the STUI-1128 repair (`6684cc5d`): twenty
/// finite scenarios (w1h001–w1h020, one per argument) at the neighbors of
/// `LocalPointerHandlerRegistry.removeUnpairedGestureFamilyRoutes`. Odd ids
/// exercise the wheel family, even ids the hover family, except 17–20.
@MainActor
@Suite("Pointer callback repair neighboring contracts")
struct PointerCallbackRepairRegressionTests {
  @Test(arguments: Array(1...20))
  func neighboringLifetime(id: Int) throws {
    let registry = LocalPointerHandlerRegistry()
    let identity = Identity(components: [IdentityComponent(rawValue: "w1h-\(id)")])
    let old = ViewNodeID(rawValue: 1)
    let live = ViewNodeID(rawValue: 2)
    let route = RouteID(identity: identity, ownerNodeID: old)
    let fresh = RouteID(identity: identity, ownerNodeID: live)
    let wheel = id % 2 == 1
    let calls = RepairCallbackCalls()

    if id <= 16 {
      switch (id - 1) / 2 {
      case 0:
        // w1h001 (wheel) / w1h002 (hover): captured callback release.
        weak let captured = installCapturedOwner(registry, wheel: wheel, route: route, owner: old)
        try #require(captured != nil)
        #expect(count(registry, wheel: wheel) == 2)
        registry.removeUnpairedGestureFamilyRoutes(pairedIdentities: [], keeping: [])
        #expect(count(registry, wheel: wheel) == 0)
        #expect(captured == nil)
      case 1:
        // w1h003 / w1h004: retired recency reuse.
        install(registry, wheel: wheel, route: route, owner: old, calls: calls, recency: 10)
        registry.removeUnpairedGestureFamilyRoutes(pairedIdentities: [], keeping: [])
        try #require(count(registry, wheel: wheel) == 0)
        install(registry, wheel: wheel, route: route, owner: live, calls: calls, recency: 1)
        #expect(count(registry, wheel: wheel) == 1)
        dispatch(registry, wheel: wheel, route: route)
        #expect(calls.count == 1)
      case 2:
        // w1h005 / w1h006: fresh owner replacement.
        let oldCalls = RepairCallbackCalls()
        install(registry, wheel: wheel, route: route, owner: old, calls: oldCalls, recency: 1)
        install(registry, wheel: wheel, route: fresh, owner: live, calls: calls, recency: 2)
        registry.removeUnpairedGestureFamilyRoutes(pairedIdentities: [], keeping: [live])
        #expect(keys(registry, wheel: wheel) == [fresh])
        dispatch(registry, wheel: wheel, route: RouteID(identity: identity))
        #expect(calls.count == 1)
        #expect(oldCalls.count == 0)
      case 3:
        // w1h007 / w1h008: equal recency owners.
        install(registry, wheel: wheel, route: route, owner: old, calls: calls, recency: 1)
        install(registry, wheel: wheel, route: fresh, owner: live, calls: calls, recency: 1)
        try #require(count(registry, wheel: wheel) == 2)
        registry.removeUnpairedGestureFamilyRoutes(pairedIdentities: [], keeping: [live])
        #expect(keys(registry, wheel: wheel) == [fresh])
        dispatch(registry, wheel: wheel, route: RouteID(identity: identity))
        #expect(calls.count == 1)
      case 4:
        // w1h009 / w1h010: recognizer identity isolation (replaces the
        // unauthorable two-kind scenarios; RouteKind has one case).
        let paired = identity.child(IdentityComponent(rawValue: "paired"))
        let pairedRoute = RouteID(identity: paired, ownerNodeID: old)
        install(registry, wheel: wheel, route: route, owner: old, calls: calls)
        install(registry, wheel: wheel, route: pairedRoute, owner: old, calls: calls)
        registry.removeUnpairedGestureFamilyRoutes(pairedIdentities: [paired], keeping: [])
        #expect(keys(registry, wheel: wheel) == [pairedRoute])
        dispatch(registry, wheel: wheel, route: route)
        #expect(calls.count == 0)
        dispatch(registry, wheel: wheel, route: pairedRoute)
        #expect(calls.count == 1)
      case 5:
        // w1h011 / w1h012: adopted owner rehome.
        var record = PointerNodeRecord()
        let owner = RuntimeRegistrationOwnerKey(viewNodeID: old, identity: identity)
        if wheel {
          record.wheelHandlers[route] = [
            { _ in
              calls.count += 1
              return .ignored
            }
          ]
          record.wheelOwners[route] = owner
        } else {
          record.hoverHandlers[route] = [{ _ in calls.count += 1 }]
          record.hoverOwners[route] = owner
        }
        record.rehomeAdoptedOwners(from: old, to: live)
        registry.restoreWheel(record.wheelHandlers, ownersByRouteID: record.wheelOwners)
        registry.restoreHover(record.hoverHandlers, ownersByRouteID: record.hoverOwners)
        registry.removeUnpairedGestureFamilyRoutes(pairedIdentities: [], keeping: [live])
        #expect(keys(registry, wheel: wheel) == [route])
        dispatch(registry, wheel: wheel, route: route)
        #expect(calls.count == 1)
      case 6:
        // w1h013 / w1h014: structural owner departure.
        let structural = Identity(components: [IdentityComponent(rawValue: "authored")])
        install(
          registry, wheel: wheel, route: route, owner: old, calls: calls,
          structural: structural
        )
        registry.removeSubtrees(rootedAt: [structural], preserving: [identity])
        try #require(count(registry, wheel: wheel) == 1)
        registry.removeUnpairedGestureFamilyRoutes(pairedIdentities: [], keeping: [])
        #expect(count(registry, wheel: wheel) == 0)
        dispatch(registry, wheel: wheel, route: route)
        #expect(calls.count == 0)
      default:
        // w1h015 / w1h016: unknown owner contract.
        install(registry, wheel: wheel, route: route, owner: nil, calls: calls)
        registry.removeUnpairedGestureFamilyRoutes(pairedIdentities: [], keeping: [])
        #expect(keys(registry, wheel: wheel) == [route])
        dispatch(registry, wheel: wheel, route: route)
        #expect(calls.count == 1)
        registry.removeSubtrees(rootedAt: [identity])
        #expect(count(registry, wheel: wheel) == 0)
        dispatch(registry, wheel: wheel, route: route)
        #expect(calls.count == 1)
      }
    } else if id <= 18 {
      // w1h017: wheel owner departs, hover stays. w1h018: the inverse.
      let wheelLives = id == 18
      install(registry, wheel: true, route: route, owner: wheelLives ? live : old, calls: calls)
      install(registry, wheel: false, route: route, owner: wheelLives ? old : live, calls: calls)
      registry.removeUnpairedGestureFamilyRoutes(pairedIdentities: [], keeping: [live])
      #expect(count(registry, wheel: true) == (wheelLives ? 1 : 0))
      #expect(count(registry, wheel: false) == (wheelLives ? 0 : 1))
      dispatch(registry, wheel: true, route: route)
      #expect(calls.count == (wheelLives ? 1 : 0))
      dispatch(registry, wheel: false, route: route)
      #expect(calls.count == 1)
    } else {
      // w1h019: plain primary handler, departed owner, no gesture stamp.
      // w1h020: unpaired structural primary handler with a live owner.
      registry.restore(
        [
          route: { _ in
            calls.count += 1
            return .claimed
          }
        ],
        ownersByRouteID: [route: .init(viewNodeID: id == 19 ? old : live, identity: identity)],
        structuralRoutes: id == 20 ? [identity: route] : [:]
      )
      registry.removeUnpairedGestureFamilyRoutes(pairedIdentities: [], keeping: [live])
      #expect(registry.snapshot().keys.contains(route))
      let result = registry.dispatch(routeID: route, event: wheelEvent)
      #expect(result == .claimed)
      #expect(calls.count == 1)
    }
  }

  private func install(
    _ registry: LocalPointerHandlerRegistry, wheel: Bool, route: RouteID,
    owner: ViewNodeID?, calls: RepairCallbackCalls, recency: UInt64 = 1,
    structural: Identity? = nil, levels: Int = 1
  ) {
    let owners = [
      route: RuntimeRegistrationOwnerKey(
        viewNodeID: owner, identity: structural ?? route.identity
      )
    ]
    if wheel {
      let callback: LocalPointerHandlerRegistry.Handler = { _ in
        calls.count += 1
        return .ignored
      }
      registry.restoreWheel(
        [route: Array(repeating: callback, count: levels)], ownersByRouteID: owners,
        recency: recency
      )
    } else {
      let callback: LocalPointerHandlerRegistry.HoverHandler = { _ in calls.count += 1 }
      registry.restoreHover(
        [route: Array(repeating: callback, count: levels)], ownersByRouteID: owners,
        recency: recency
      )
    }
  }

  private func installCapturedOwner(
    _ registry: LocalPointerHandlerRegistry, wheel: Bool, route: RouteID, owner: ViewNodeID
  ) -> RepairCallbackCalls {
    let calls = RepairCallbackCalls()
    install(registry, wheel: wheel, route: route, owner: owner, calls: calls, levels: 2)
    return calls
  }

  private func keys(_ registry: LocalPointerHandlerRegistry, wheel: Bool) -> Set<RouteID> {
    wheel ? Set(registry.snapshotWheel().keys) : Set(registry.snapshotHover().keys)
  }

  private func count(_ registry: LocalPointerHandlerRegistry, wheel: Bool) -> Int {
    wheel
      ? registry.snapshotWheel().values.reduce(0) { $0 + $1.count }
      : registry.snapshotHover().values.reduce(0) { $0 + $1.count }
  }

  private func dispatch(_ registry: LocalPointerHandlerRegistry, wheel: Bool, route: RouteID) {
    if wheel {
      registry.dispatch(routeID: route, event: wheelEvent)
    } else {
      registry.dispatchHover(routeID: route, phase: .exited)
    }
  }

  private var wheelEvent: LocalPointerEvent {
    LocalPointerEvent(
      kind: .scrolled(deltaX: 0, deltaY: 1), location: Point.zero,
      targetRect: .init(origin: .zero, size: .init(width: 1, height: 1))
    )
  }
}

@MainActor
private final class RepairCallbackCalls {
  var count = 0
}
