import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUI
@testable import SwiftTUIViews

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

  @Test("RuntimeRegistrationSet.removeSubtrees preserves active gestures during reevaluation")
  func runtimeRemovalPreservesActiveGestures() {
    let gestureReg = LocalGestureRegistry()
    let stateReg = LocalGestureStateRegistry()
    let identity = Identity(components: [IdentityComponent(rawValue: "drag")])

    let tracker = ActiveTracker()
    gestureReg.register(identity: identity, recognizer: AnyGestureRecognizer(tracker))

    let box = GestureStateBox<Int>(seed: 0, slotOrdinal: 0)
    box.setValue(77)
    stateReg.register(identity: identity, binding: box.eraseToAnyBinding())

    let registrations = RuntimeRegistrationSet(
      gestureRegistry: gestureReg,
      gestureStateRegistry: stateReg
    )
    registrations.removeSubtrees(rootedAt: [identity])

    #expect(tracker.tornDown == false)
    #expect(gestureReg.recognizer(for: identity) != nil)
    #expect(box.currentValue() == 77)
    #expect(stateReg.bindings(for: identity).count == 1)
  }

  @Test("RuntimeRegistrationSet.pruneOrphanedGestures cancels removed active gestures")
  func runtimePrunesOrphanedGestures() {
    let gestureReg = LocalGestureRegistry()
    let stateReg = LocalGestureStateRegistry()
    let identity = Identity(components: [IdentityComponent(rawValue: "drag")])

    let tracker = ActiveTracker()
    gestureReg.register(identity: identity, recognizer: AnyGestureRecognizer(tracker))

    let box = GestureStateBox<Int>(seed: 0, slotOrdinal: 0)
    box.setValue(21)
    stateReg.register(identity: identity, binding: box.eraseToAnyBinding())

    let registrations = RuntimeRegistrationSet(
      gestureRegistry: gestureReg,
      gestureStateRegistry: stateReg
    )
    registrations.pruneOrphanedGestures(keeping: [])

    #expect(tracker.tornDown == true)
    #expect(gestureReg.recognizer(for: identity) == nil)
    #expect(box.currentValue() == 0)
    #expect(stateReg.bindings(for: identity).isEmpty)
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

@MainActor
private final class ActiveTracker: GestureRecognizer {
  typealias Value = Int
  var phase: GestureRecognizerPhase = .possible
  var tornDown = false
  var isActive: Bool { true }
  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition { .ignored }
  func handleDeadline(at instant: MonotonicInstant) -> Bool { false }
  func currentValue() -> Int? { nil }
  func tearDown() { tornDown = true }
}
