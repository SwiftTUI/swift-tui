import Testing

@testable import SwiftTUIGraph

@MainActor
struct FocusArrivalLifetimeTests {
  private final class Lifetime {
    var live = true
    var arms = 0
  }

  @Test(arguments: [false, true])
  func publicationPreservesArrivalButLifetimeRemovalDoesNot(ownerless: Bool) {
    let registry = LocalFocusBindingRegistry()
    let root = testIdentity("Arrival")
    let target = root.child("Target")
    let key = FocusBindingKey(owner: nil, suffix: .legacy("arrival"))
    func registerTarget() {
      registry.register(
        identity: target, bindingKey: key, bindingID: "arrival",
        hasPendingRequest: false, isSelected: false, applyRuntimeFocus: { _ in false })
    }
    func arrival(_ lifetime: Lifetime) -> DefaultFocusArrivalSnapshot {
      .init(
        bindingKey: key, ownerIdentity: ownerless ? nil : root, contextIdentity: root,
        isLive: { lifetime.live },
        armDefault: {
          lifetime.arms += 1
          return true
        })
    }
    let first = Lifetime()
    registerTarget()
    registry.recordArrivalDefault(arrival(first))
    registry.removeRegistrationsForRepublication(rootedAt: [root])
    registerTarget()
    #expect(registry.consumeArrivalDefaults())
    #expect(first.arms == 1)
    #expect(!registry.consumeArrivalDefaults())
    if ownerless {
      registry.recordArrivalDefault(arrival(first))
      registry.removeRegistrationsForRepublication(rootedAt: [root])
      registerTarget()
      #expect(!registry.consumeArrivalDefaults())
    }
    first.live = false
    let replacement = Lifetime()
    registry.recordArrivalDefault(arrival(replacement))
    registry.removeRegistrationsForRepublication(rootedAt: [root])
    registerTarget()
    #expect(registry.consumeArrivalDefaults())
    #expect(replacement.arms == 1)

    // A target elsewhere can keep the binding key alive after the declaration
    // owner disappears. That must not authorize its retired default.
    let departed = Lifetime()
    registry.removeSubtrees(rootedAt: [root])
    registerTarget()
    registry.recordArrivalDefault(arrival(departed))
    departed.live = false
    registry.removeRegistrationsForRepublication(rootedAt: [root])
    registerTarget()
    #expect(!registry.consumeArrivalDefaults())
    #expect(departed.arms == 0)
  }
}
