import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct GestureTeardownTests {
  @Test("LocalGestureRegistry.removeSubtrees clears descendants and tears down recognizers")
  func registryRemoveSubtrees() {
    let registry = LocalGestureRegistry()
    let parent = Identity(components: [IdentityComponent(rawValue: "p")])
    let child = parent.child(IdentityComponent(rawValue: "c"))
    let sibling = Identity(components: [IdentityComponent(rawValue: "s")])

    let parentTracker = TearDownTracker()
    let childTracker = TearDownTracker()
    let siblingTracker = TearDownTracker()
    registry.register(identity: parent, recognizer: AnyGestureRecognizer(parentTracker))
    registry.register(identity: child, recognizer: AnyGestureRecognizer(childTracker))
    registry.register(identity: sibling, recognizer: AnyGestureRecognizer(siblingTracker))

    registry.removeSubtrees(rootedAt: [parent])
    #expect(parentTracker.tornDown == true)
    #expect(childTracker.tornDown == true)
    #expect(siblingTracker.tornDown == false)
  }

  @Test("LocalGestureStateRegistry.removeSubtrees resets bindings on teardown")
  func stateRegistryRemoveSubtrees() {
    let registry = LocalGestureStateRegistry()
    let identity = Identity(components: [IdentityComponent(rawValue: "r")])
    let box = GestureStateBox<Int>(seed: 0, slotOrdinal: 0)
    box.setValue(42)
    registry.register(identity: identity, binding: box.eraseToAnyBinding())
    registry.removeSubtrees(rootedAt: [identity])
    #expect(box.currentValue() == 0)
  }

  @Test("Subtree removal via registry cleanup drains both registries")
  func fullTeardownDrainsBoth() {
    let gestureReg = LocalGestureRegistry()
    let stateReg = LocalGestureStateRegistry()
    let parent = Identity(components: [IdentityComponent(rawValue: "p")])
    let child = parent.child(IdentityComponent(rawValue: "c"))

    let tracker = TearDownTracker()
    gestureReg.register(identity: parent, recognizer: AnyGestureRecognizer(tracker))

    let box = GestureStateBox<Int>(seed: 0, slotOrdinal: 0)
    box.setValue(77)
    stateReg.register(identity: child, binding: box.eraseToAnyBinding())

    gestureReg.removeSubtrees(rootedAt: [parent])
    stateReg.removeSubtrees(rootedAt: [parent])

    #expect(tracker.tornDown == true)
    #expect(gestureReg.recognizer(for: parent) == nil)
    #expect(box.currentValue() == 0)  // reset fired
  }
}

@MainActor
private final class TearDownTracker: GestureRecognizer {
  typealias Value = Int
  var phase: GestureRecognizerPhase = .possible
  var tornDown = false
  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition { .ignored }
  func handleDeadline(at instant: MonotonicInstant) -> Bool { false }
  func currentValue() -> Int? { nil }
  func tearDown() { tornDown = true }
}
