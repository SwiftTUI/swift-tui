import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite("Route pairing and registration ordering")
struct RoutePairingRegistryTests {
  // MARK: - RouteID equality vs pairing

  @Test("RouteID equality is strict across owners; pairing ignores them")
  func routeIDEqualityIsStrictAndPairingIgnoresOwners() {
    let identity = testIdentity("PairingRoot", "control")
    let unowned = RouteID(identity: identity)
    let ownedByFive = RouteID(identity: identity, ownerNodeID: ViewNodeID(rawValue: 5))
    let ownedByNine = RouteID(identity: identity, ownerNodeID: ViewNodeID(rawValue: 9))
    let otherIdentity = RouteID(identity: testIdentity("PairingRoot", "other"))

    #expect(unowned != ownedByFive)
    #expect(ownedByFive != ownedByNine)
    #expect(ownedByFive == RouteID(identity: identity, ownerNodeID: ViewNodeID(rawValue: 5)))

    #expect(unowned.pairsIgnoringOwner(with: ownedByFive))
    #expect(ownedByFive.pairsIgnoringOwner(with: ownedByNine))
    #expect(!otherIdentity.pairsIgnoringOwner(with: ownedByFive))
  }

  // MARK: - Pointer handler pairing

  @MainActor
  @Test("paired pointer dispatch deterministically prefers the freshest owner")
  func pairedPointerDispatchPrefersFreshestOwner() {
    let identity = testIdentity("PairingRoot", "control")
    let staleRoute = RouteID(identity: identity, ownerNodeID: ViewNodeID(rawValue: 5))
    let freshRoute = RouteID(identity: identity, ownerNodeID: ViewNodeID(rawValue: 9))
    let registry = LocalPointerHandlerRegistry()

    var received: [String] = []
    registry.register(routeID: staleRoute) { _ in
      received.append("stale")
      return true
    }
    registry.register(routeID: freshRoute) { _ in
      received.append("fresh")
      return true
    }

    let event = LocalPointerEvent(
      kind: .down(.primary),
      location: Point(x: 0, y: 0),
      targetRect: .zero
    )

    // An exact key still dispatches exactly.
    #expect(registry.dispatch(routeID: staleRoute, event: event))
    #expect(received == ["stale"])
    received = []

    // An owner-less probe (the run loop's ancestor-walk fallback) pairs with
    // both entries; the freshest owner must win — the old wildcard `==` left
    // this to hash-seeded dictionary probe order.
    #expect(registry.dispatch(routeID: RouteID(identity: identity), event: event))
    #expect(received == ["fresh"])
    received = []

    // A probe carrying a re-minted (unknown) owner pairs the same way.
    let reMinted = RouteID(identity: identity, ownerNodeID: ViewNodeID(rawValue: 12))
    #expect(registry.dispatch(routeID: reMinted, event: event))
    #expect(received == ["fresh"])
    #expect(registry.handlerRouteID(pairingWith: reMinted) == freshRoute)
    #expect(registry.hasHandler(pairingWith: reMinted))
    #expect(!registry.hasHandler(routeID: reMinted))
  }

  @MainActor
  @Test("paired hover dispatch prefers the freshest recency, then owner")
  func pairedHoverDispatchPrefersFreshestRecency() {
    let identity = testIdentity("PairingRoot", "hoverable")
    let olderRoute = RouteID(identity: identity, ownerNodeID: ViewNodeID(rawValue: 9))
    let fresherRoute = RouteID(identity: identity, ownerNodeID: ViewNodeID(rawValue: 5))
    let registry = LocalPointerHandlerRegistry()

    var received: [String] = []
    // Restore with distinct recencies: insertion evicts the strictly staler
    // copy, so only the fresher handler remains to receive a paired dispatch.
    registry.restoreHover([olderRoute: { _ in received.append("older") }], recency: 1)
    registry.restoreHover([fresherRoute: { _ in received.append("fresher") }], recency: 2)

    registry.dispatchHover(
      routeID: RouteID(identity: identity, ownerNodeID: ViewNodeID(rawValue: 12)),
      phase: .exited
    )
    #expect(received == ["fresher"])
    received = []

    // Equal recency keeps genuinely stacked entries; the owner tiebreak makes
    // the paired pick deterministic.
    let stackedLow = RouteID(identity: identity, ownerNodeID: ViewNodeID(rawValue: 21))
    let stackedHigh = RouteID(identity: identity, ownerNodeID: ViewNodeID(rawValue: 22))
    registry.restoreHover(
      [
        stackedLow: { _ in received.append("low") },
        stackedHigh: { _ in received.append("high") },
      ],
      recency: 3
    )
    registry.dispatchHover(routeID: RouteID(identity: identity), phase: .exited)
    #expect(received == ["high"])
  }

  // MARK: - Key/paste registration ordinals

  @MainActor
  @Test("stacked key press priority follows persisted ordinals, not owner node IDs")
  func stackedKeyPressPriorityFollowsPersistedOrdinals() {
    let identity = testIdentity("PairingRoot", "focused")
    let registry = LocalKeyHandlerRegistry()

    var received: [String] = []
    let innerOwner = RuntimeRegistrationOwnerKey(
      viewNodeID: ViewNodeID(rawValue: 9),
      identity: identity
    )
    let outerOwner = RuntimeRegistrationOwnerKey(
      viewNodeID: ViewNodeID(rawValue: 5),
      identity: identity
    )

    // Fresh frame: the inner level registers first (ordinal 0, later-allocated
    // node), the outer second (ordinal 1). Dispatch walks the stack outermost
    // first, so the outer handler consumes.
    registry.restoreKeyPressHandlers(
      [
        identity: [
          { _ in
            received.append("inner")
            return true
          }
        ]
      ],
      ownersByIdentity: [identity: innerOwner],
      ordinalsByIdentity: [identity: 0]
    )
    registry.restoreKeyPressHandlers(
      [
        identity: [
          { _ in
            received.append("outer")
            return true
          }
        ]
      ],
      ownersByIdentity: [identity: outerOwner],
      ordinalsByIdentity: [identity: 1]
    )

    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.character("k"))))
    #expect(received == ["outer"])
    received = []

    // Partial republication after the outer level's node re-mints: its bucket
    // returns under a fresh, higher ViewNodeID but the SAME persisted ordinal.
    // Owner-derived ordering (the old scheme) would now sort the outer level
    // innermost and hand the key to the inner handler first — the inversion
    // this registry must not exhibit.
    let reMintedOuterOwner = RuntimeRegistrationOwnerKey(
      viewNodeID: ViewNodeID(rawValue: 12),
      identity: identity
    )
    registry.removeSubtrees(rootedAt: [identity])
    registry.restoreKeyPressHandlers(
      [
        identity: [
          { _ in
            received.append("inner")
            return true
          }
        ]
      ],
      ownersByIdentity: [identity: innerOwner],
      ordinalsByIdentity: [identity: 0]
    )
    registry.restoreKeyPressHandlers(
      [
        identity: [
          { _ in
            received.append("outer")
            return true
          }
        ]
      ],
      ownersByIdentity: [identity: reMintedOuterOwner],
      ordinalsByIdentity: [identity: 1]
    )

    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.character("k"))))
    #expect(received == ["outer"])
  }

  @MainActor
  @Test("stacked paste priority follows persisted ordinals across a re-mint")
  func stackedPastePriorityFollowsPersistedOrdinalsAcrossReMint() {
    // Paste has no matcher — bucket order alone selects the consumer, so an
    // ordinal inversion silently redirects every paste.
    let identity = testIdentity("PairingRoot", "pasteTarget")
    let registry = LocalKeyHandlerRegistry()

    var received: [String] = []
    let innerOwner = RuntimeRegistrationOwnerKey(
      viewNodeID: ViewNodeID(rawValue: 9),
      identity: identity
    )
    let reMintedOuterOwner = RuntimeRegistrationOwnerKey(
      viewNodeID: ViewNodeID(rawValue: 12),
      identity: identity
    )

    registry.restorePasteHandlers(
      [
        identity: [
          { _ in
            received.append("inner")
            return true
          }
        ]
      ],
      ownersByIdentity: [identity: innerOwner],
      ordinalsByIdentity: [identity: 0]
    )
    registry.restorePasteHandlers(
      [
        identity: [
          { _ in
            received.append("outer")
            return true
          }
        ]
      ],
      ownersByIdentity: [identity: reMintedOuterOwner],
      ordinalsByIdentity: [identity: 1]
    )

    #expect(registry.dispatchPaste(identity: identity, content: "clipboard"))
    #expect(received == ["outer"])
  }

  @MainActor
  @Test("fresh key press registrations mint ordinals above restored ones")
  func freshKeyPressRegistrationsMintOrdinalsAboveRestoredOnes() {
    // A bucket restored with a recorded ordinal must push the registry's mint
    // past it, so a level that genuinely re-registers (its record was pruned)
    // joins the back of the stack instead of colliding into a tie.
    let identity = testIdentity("PairingRoot", "restoredThenFresh")
    let registry = LocalKeyHandlerRegistry()

    var received: [String] = []
    let restoredOwner = RuntimeRegistrationOwnerKey(
      viewNodeID: ViewNodeID(rawValue: 9),
      identity: identity
    )
    registry.restoreKeyPressHandlers(
      [
        identity: [
          { _ in
            received.append("restored")
            return true
          }
        ]
      ],
      ownersByIdentity: [identity: restoredOwner],
      ordinalsByIdentity: [identity: 7]
    )
    // No ViewNodeContext in a unit test, so this registers under the nil-node
    // owner — a distinct bucket whose ordinal must mint above 7.
    registry.register(
      identity: identity,
      keyPressHandler: { _ in
        received.append("fresh")
        return true
      }
    )

    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.character("k"))))
    #expect(received == ["fresh"])
  }
}
