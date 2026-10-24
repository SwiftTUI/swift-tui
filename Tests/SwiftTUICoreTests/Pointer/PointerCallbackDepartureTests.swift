import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@MainActor
@Suite("Pointer callback owner departure")
struct PointerCallbackDepartureTests {
  @Test(arguments: Array(1...8))
  func pairedCleanup(id: Int) {
    let isWheel = id <= 4
    let condition = (id - 1) % 4
    let identity = Identity(components: [IdentityComponent(rawValue: "departure-\(id)")])
    let node = ViewNodeID(rawValue: 1)
    let route = RouteID(identity: identity)
    let owner = RuntimeRegistrationOwnerKey(
      viewNodeID: condition == 3 ? nil : node, identity: identity
    )
    let registry = LocalPointerHandlerRegistry()
    let calls = PointerDepartureCalls()
    if isWheel {
      registry.restoreWheel(
        [
          route: [
            { _ in
              calls.count += 1
              return .claimed
            }
          ]
        ],
        ownersByRouteID: [route: owner], recency: 10
      )
    } else {
      registry.restoreHover(
        [route: [{ _ in calls.count += 1 }]],
        ownersByRouteID: [route: owner], recency: 10
      )
    }
    #expect(isWheel ? registry.snapshotWheel().count == 1 : registry.snapshotHover().count == 1)

    registry.removeUnpairedGestureFamilyRoutes(
      pairedIdentities: condition == 1 ? [identity] : [],
      keeping: condition == 2 ? [node] : []
    )

    let shouldRemain = condition != 0
    #expect(
      (isWheel ? registry.snapshotWheel()[route] != nil : registry.snapshotHover()[route] != nil)
        == shouldRemain
    )
    if isWheel {
      let result = registry.dispatch(
        routeID: route,
        event: LocalPointerEvent(
          kind: .scrolled(deltaX: 0, deltaY: 1), location: Point(x: 0, y: 0),
          targetRect: CellRect(origin: .zero, size: .init(width: 1, height: 1))
        )
      )
      #expect(result == (shouldRemain ? .claimed : .ignored))
    } else {
      registry.dispatchHover(routeID: route, phase: .exited)
    }
    #expect(calls.count == (shouldRemain ? 1 : 0))
  }
}

@MainActor
private final class PointerDepartureCalls {
  var count = 0
}
