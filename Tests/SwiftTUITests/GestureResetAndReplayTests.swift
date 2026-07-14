import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct GestureResetAndReplayTests {
  @Test("resetAll drains inactive recognizers and clears state bindings without firing resetToSeed")
  func resetAllDrainsGestures() {
    let gestureRegistry = LocalGestureRegistry()
    let stateRegistry = LocalGestureStateRegistry()
    let identity = Identity(components: [IdentityComponent(rawValue: "r")])

    let tracker = TearDownTracker()
    // `tracker.phase` is `.possible` with no "has started tracking"
    // signal — default `isActive == false` — so resetAll tears it down.
    gestureRegistry.register(identity: identity, recognizer: AnyGestureRecognizer(tracker))

    let box = GestureStateBox<Int>(seed: 0, slotOrdinal: 0)
    box.setValue(99)
    stateRegistry.register(identity: identity, binding: box.eraseToAnyBinding())

    let set = RuntimeRegistrationSet(
      gestureRegistry: gestureRegistry,
      gestureStateRegistry: stateRegistry
    )
    set.resetAll()

    // Inactive recognizer: torn down and removed.
    #expect(tracker.tornDown == true)
    #expect(gestureRegistry.recognizer(for: identity) == nil)
    // State registry: bindings dict cleared …
    #expect(stateRegistry.bindings(for: identity).isEmpty)
    // … but the box is NOT reset. `resetAll` fires on every
    // full-resolve frame; calling `resetToSeed` from here would wipe
    // a mid-flight `@GestureState` value between frames. Subtree
    // teardown (`removeSubtrees`) is the correct path for that reset
    // (see `stateRegistryRemoveSubtrees`).
    #expect(box.currentValue() == 99)
  }

  @Test("resetAll preserves an active recognizer mid-gesture")
  func resetAllPreservesActive() {
    let gestureRegistry = LocalGestureRegistry()
    let identity = Identity(components: [IdentityComponent(rawValue: "r")])

    let active = ActiveTracker()
    gestureRegistry.register(identity: identity, recognizer: AnyGestureRecognizer(active))

    let set = RuntimeRegistrationSet(gestureRegistry: gestureRegistry)
    set.resetAll()

    // Active recognizer survives resetAll — otherwise a `.down` event
    // between full-resolve frames would have its captured state
    // silently torn down before the first `.dragged` arrives.
    #expect(active.tornDown == false)
    #expect(gestureRegistry.recognizer(for: identity) != nil)
  }

  @Test("Gesture recognizer survives a cache-hit rebuild via ViewNode replay")
  func recognizerSurvivesCacheReplay() throws {
    // This test exercises the record+restore path: render once so the
    // gesture registers; render AGAIN without re-running resolve
    // (simulating a cache hit) and verify the recognizer is still
    // registered and the pointer handler still routes to it.
    @MainActor class Box { var count = 0 }
    let box = Box()
    let root = Identity(components: [IdentityComponent(rawValue: "r")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 10, height: 3)

    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()
    var ctx = ResolveContext(identity: root, environmentValues: env)
    ctx.localPointerHandlerRegistry = pointerRegistry
    ctx.localGestureRegistry = gestureRegistry
    ctx.localGestureStateRegistry = gestureStateRegistry

    _ = DefaultRenderer().render(
      Text("Tap")
        .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
        .onTapGesture { box.count += 1 },
      context: ctx,
      proposal: .init(width: 10, height: 3)
    )

    // Simulate a full registration reset (as would happen on a full
    // rebuild frame).
    let registrations = RuntimeRegistrationSet(
      pointerHandlerRegistry: pointerRegistry,
      gestureRegistry: gestureRegistry,
      gestureStateRegistry: gestureStateRegistry
    )
    registrations.resetAll()

    // Re-render. The registrations should repopulate via the
    // ViewNode record/restore path (if resolve runs fresh) or via
    // explicit restore (if the snapshot is cached). At minimum, the
    // subsequent render must re-register the gesture.
    let artifacts2 = DefaultRenderer().render(
      Text("Tap")
        .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
        .onTapGesture { box.count += 1 },
      context: ctx,
      proposal: .init(width: 10, height: 3)
    )

    let region = try #require(artifacts2.semanticSnapshot.interactionRegions.first)
    _ = pointerRegistry.dispatch(
      routeID: region.routeID,
      event: .init(
        kind: .down(.primary), location: Point(region.rect.origin), targetRect: region.rect)
    )
    _ = pointerRegistry.dispatch(
      routeID: region.routeID,
      event: .init(
        kind: .up(.primary), location: Point(region.rect.origin), targetRect: region.rect)
    )
    #expect(box.count == 1)  // gesture still fires after reset+re-render
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

  func reArm() {}
}

/// Reports `isActive == true` to simulate a recognizer that has
/// captured interaction state while still in `.possible`.
@MainActor
private final class ActiveTracker: GestureRecognizer {
  typealias Value = Int
  var phase: GestureRecognizerPhase = .possible
  var isActive: Bool { true }
  var tornDown = false
  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition { .ignored }
  func handleDeadline(at instant: MonotonicInstant) -> Bool { false }
  func currentValue() -> Int? { nil }
  func tearDown() { tornDown = true }

  func reArm() {}
}
