import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@MainActor
@Suite
struct DropDestinationRegistryTests {
  @Test("Registered handlers can be looked up by scope identity")
  func lookup() {
    let registry = DropDestinationRegistry()
    let scope = Identity(components: ["panel"])
    registry.register(at: scope) { _ in true }
    #expect(registry.handler(at: scope) != nil)
    #expect(registry.handler(at: Identity(components: ["other"])) == nil)
  }

  @Test("Dispatch walks leafmost-first and stops when a handler returns true")
  func leafmostFirstConsumes() {
    let registry = DropDestinationRegistry()
    let shallow = Identity(components: ["app"])
    let deep = Identity(components: ["app", "panel"])
    let shallowFired = Counter()
    let deepFired = Counter()
    registry.register(at: shallow) { _ in
      shallowFired.increment()
      return true
    }
    registry.register(at: deep) { _ in
      deepFired.increment()
      return true
    }
    let consumed = registry.dispatch(
      paths: [DroppedPath("/a")],
      along: [shallow, deep]  // shallowest-first input; registry walks reversed
    )
    #expect(consumed == true)
    #expect(deepFired.count == 1)
    #expect(shallowFired.count == 0)
  }

  @Test("Handler returning false bubbles to the next outer scope")
  func bubbleOnFalse() {
    let registry = DropDestinationRegistry()
    let shallow = Identity(components: ["app"])
    let deep = Identity(components: ["app", "panel"])
    let shallowFired = Counter()
    let deepFired = Counter()
    registry.register(at: shallow) { _ in
      shallowFired.increment()
      return true
    }
    registry.register(at: deep) { _ in
      deepFired.increment()
      return false
    }
    let consumed = registry.dispatch(
      paths: [DroppedPath("/a")],
      along: [shallow, deep]
    )
    #expect(consumed == true)
    #expect(deepFired.count == 1)
    #expect(shallowFired.count == 1)
  }

  @Test("Dispatch returns false when no scope on the chain has a destination")
  func noMatch() {
    let registry = DropDestinationRegistry()
    let consumed = registry.dispatch(
      paths: [DroppedPath("/a")],
      along: [Identity(components: ["app"])]
    )
    #expect(consumed == false)
  }

  @Test("Dispatch forwards spatial drop context to handlers")
  func dispatchForwardsContext() {
    let registry = DropDestinationRegistry()
    let scope = Identity(components: ["panel"])
    let expectedContext = DropContext(
      location: Point(x: 1.5, y: 2.25),
      pointer: .subCell(
        location: Point(x: 1.5, y: 2.25),
        source: .nativePixels,
        metrics: CellPixelMetrics(width: 8, height: 16, source: .reported)
      ),
      modifiers: [.shift, .ctrl]
    )
    var receivedContext: DropContext?

    registry.register(at: scope) { _, context in
      receivedContext = context
      return true
    }

    let consumed = registry.dispatch(
      paths: [DroppedPath("/a")],
      context: expectedContext,
      along: [scope]
    )

    #expect(consumed)
    #expect(receivedContext == expectedContext)
  }

  @Test("reset clears all registrations")
  func resetClears() {
    let registry = DropDestinationRegistry()
    let scope = Identity(components: ["panel"])
    registry.register(at: scope) { _ in true }
    registry.reset()
    #expect(registry.handler(at: scope) == nil)
  }

  @Test("removeSubtrees drops registrations under given roots")
  func subtreeRemoval() {
    let registry = DropDestinationRegistry()
    let kept = Identity(components: ["app"])
    let removed = Identity(components: ["app", "panel"])
    registry.register(at: kept) { _ in true }
    registry.register(at: removed) { _ in true }
    registry.removeSubtrees(rootedAt: [Identity(components: ["app", "panel"])])
    #expect(registry.handler(at: kept) != nil)
    #expect(registry.handler(at: removed) == nil)
  }
}

private final class Counter {
  private(set) var count = 0
  func increment() { count += 1 }
}
