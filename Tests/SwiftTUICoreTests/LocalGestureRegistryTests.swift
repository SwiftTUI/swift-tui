import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@MainActor
@Suite
struct LocalGestureRegistryTests {
  @Test("Registered recognizers are retrievable by identity")
  func registerAndRetrieve() {
    let registry = LocalGestureRegistry()
    let identity = Identity(components: [IdentityComponent(rawValue: "root")])
    let recognizer = AnyGestureRecognizer(NoopRecognizer())

    registry.register(identity: identity, recognizer: recognizer)
    #expect(registry.recognizer(for: identity) === recognizer)
  }

  @Test("removeSubtrees clears descendants but not siblings")
  func removeSubtrees() {
    let registry = LocalGestureRegistry()
    let parent = Identity(components: [IdentityComponent(rawValue: "p")])
    let child = parent.child(IdentityComponent(rawValue: "c"))
    let sibling = Identity(components: [IdentityComponent(rawValue: "s")])

    registry.register(identity: parent, recognizer: AnyGestureRecognizer(NoopRecognizer()))
    registry.register(identity: child, recognizer: AnyGestureRecognizer(NoopRecognizer()))
    registry.register(identity: sibling, recognizer: AnyGestureRecognizer(NoopRecognizer()))

    registry.removeSubtrees(rootedAt: [parent])

    #expect(registry.recognizer(for: parent) == nil)
    #expect(registry.recognizer(for: child) == nil)
    #expect(registry.recognizer(for: sibling) != nil)
  }

  @Test("Teardown is invoked when a recognizer is removed via subtree removal")
  func teardownOnRemove() {
    let registry = LocalGestureRegistry()
    let identity = Identity(components: [IdentityComponent(rawValue: "r")])
    let tracker = TearDownTracker()
    registry.register(
      identity: identity,
      recognizer: AnyGestureRecognizer(tracker)
    )
    registry.removeSubtrees(rootedAt: [identity])
    #expect(tracker.tornDown == true)
  }

  @Test("Re-registering the same identity tears down the previous recognizer")
  func replaceTearsDownPrevious() {
    let registry = LocalGestureRegistry()
    let identity = Identity(components: [IdentityComponent(rawValue: "r")])
    let first = TearDownTracker()
    let second = TearDownTracker()
    registry.register(identity: identity, recognizer: AnyGestureRecognizer(first))
    registry.register(identity: identity, recognizer: AnyGestureRecognizer(second))
    #expect(first.tornDown == true)
    #expect(second.tornDown == false)
  }
}

@MainActor
private final class NoopRecognizer: GestureRecognizer {
  typealias Value = Int
  var phase: GestureRecognizerPhase = .possible
  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition { .ignored }
  func handleDeadline(at instant: MonotonicInstant) -> Bool { false }
  func currentValue() -> Int? { nil }
  func tearDown() {}
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
