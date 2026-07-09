import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@MainActor
@Suite
struct CommandRegistryTests {
  @Test("Registered key commands can be looked up by scope identity and key")
  func keyCommandLookup() {
    let registry = CommandRegistry()
    let scope = Identity(components: ["a"])
    let binding = KeyBinding(key: .character("s"), modifiers: .ctrl)
    registry.registerKeyCommand(
      at: scope,
      binding: binding,
      description: "Save",
      isEnabled: true,
      action: {}
    )
    #expect(registry.keyCommand(at: scope, matching: binding) != nil)
    #expect(
      registry.keyCommand(
        at: scope,
        matching: .init(key: .character("x"), modifiers: .ctrl)
      ) == nil
    )
  }

  @Test("reset() clears all registrations")
  func resetClears() {
    let registry = CommandRegistry()
    let scope = Identity(components: ["a"])
    registry.registerKeyCommand(
      at: scope,
      binding: .init(key: .character("s"), modifiers: .ctrl),
      description: "Save",
      isEnabled: true,
      action: {}
    )
    registry.reset()
    #expect(
      registry.keyCommand(
        at: scope,
        matching: .init(key: .character("s"), modifiers: .ctrl)
      ) == nil
    )
  }

  @Test("Dispatch walks a scope chain shallowest-first and stops at the first match")
  func dispatchShallowestWins() {
    let registry = CommandRegistry()
    let shallow = Identity(components: ["shallow"])
    let deep = Identity(components: ["shallow", "deep"])
    let shallowFired = Counter()
    let deepFired = Counter()
    registry.registerKeyCommand(
      at: shallow,
      binding: .init(key: .character("s"), modifiers: .ctrl),
      description: "Shallow save",
      isEnabled: true,
      action: { shallowFired.increment() }
    )
    registry.registerKeyCommand(
      at: deep,
      binding: .init(key: .character("s"), modifiers: .ctrl),
      description: "Deep save",
      isEnabled: true,
      action: { deepFired.increment() }
    )
    let consumed = registry.dispatch(
      key: .init(key: .character("s"), modifiers: .ctrl),
      along: [shallow, deep]
    )
    #expect(consumed == true)
    #expect(shallowFired.count == 1)
    #expect(deepFired.count == 0)
  }

  @Test("Dispatch consumes but does not fire when the shallowest match is disabled")
  func dispatchDisabledShallowBlocksDeeper() {
    let registry = CommandRegistry()
    let shallow = Identity(components: ["shallow"])
    let deep = Identity(components: ["shallow", "deep"])
    let deepFired = Counter()
    registry.registerKeyCommand(
      at: shallow,
      binding: .init(key: .character("s"), modifiers: .ctrl),
      description: "Shallow (disabled)",
      isEnabled: false,
      action: {}
    )
    registry.registerKeyCommand(
      at: deep,
      binding: .init(key: .character("s"), modifiers: .ctrl),
      description: "Deep save",
      isEnabled: true,
      action: { deepFired.increment() }
    )
    let consumed = registry.dispatch(
      key: .init(key: .character("s"), modifiers: .ctrl),
      along: [shallow, deep]
    )
    #expect(consumed == true)  // strict shallowest-wins even when disabled
    #expect(deepFired.count == 0)
  }

  @Test("Dispatch returns false when no scope on the chain claims the key")
  func dispatchNoMatch() {
    let registry = CommandRegistry()
    let scope = Identity(components: ["a"])
    let consumed = registry.dispatch(
      key: .init(key: .character("s"), modifiers: .ctrl),
      along: [scope]
    )
    #expect(consumed == false)
  }

  @Test("Empty scopePath returns false from dispatch")
  func dispatchEmptyScopePath() {
    let registry = CommandRegistry()
    let consumed = registry.dispatch(
      key: .init(key: .character("s"), modifiers: .ctrl),
      along: []
    )
    #expect(consumed == false)
  }

  @Test("Duplicate identity in scopePath dispatches at first occurrence only")
  func dispatchHandlesDuplicateIdentityInPath() {
    let registry = CommandRegistry()
    let scope = Identity(components: ["shared"])
    let fired = Counter()
    registry.registerKeyCommand(
      at: scope,
      binding: .init(key: .character("s"), modifiers: .ctrl),
      description: "Shared",
      isEnabled: true,
      action: { fired.increment() }
    )
    let consumed = registry.dispatch(
      key: .init(key: .character("s"), modifiers: .ctrl),
      along: [scope, scope, scope]
    )
    #expect(consumed == true)
    #expect(fired.count == 1)
  }

  @Test("Re-registering the same (scope, binding) replaces the earlier command")
  func registerReplacesExistingBinding() {
    let registry = CommandRegistry()
    let scope = Identity(components: ["a"])
    let first = Counter()
    let second = Counter()
    registry.registerKeyCommand(
      at: scope,
      binding: .init(key: .character("s"), modifiers: .ctrl),
      description: "First",
      isEnabled: true,
      action: { first.increment() }
    )
    registry.registerKeyCommand(
      at: scope,
      binding: .init(key: .character("s"), modifiers: .ctrl),
      description: "Second",
      isEnabled: true,
      action: { second.increment() }
    )
    _ = registry.dispatch(
      key: .init(key: .character("s"), modifiers: .ctrl),
      along: [scope]
    )
    #expect(first.count == 0)
    #expect(second.count == 1)
  }

}

@MainActor
private final class Counter {
  var count = 0
  func increment() { count += 1 }
}
