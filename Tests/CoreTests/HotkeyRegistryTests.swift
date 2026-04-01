import Testing

@testable import Core

@MainActor
@Suite
struct HotkeyRegistryTests {
  @Test("register and dispatch matching key press")
  func registerAndDispatch() {
    let registry = HotkeyRegistry()
    var called = false

    registry.register(
      binding: HotkeyBinding(key: LocalKeyPress(.character("s"), modifiers: .control))
    ) { _ in
      called = true
      return true
    }

    let handled = registry.dispatch(LocalKeyPress(.character("s"), modifiers: .control))
    #expect(handled)
    #expect(called)
  }

  @Test("dispatch returns false when no handler matches")
  func dispatchNoMatch() {
    let registry = HotkeyRegistry()

    registry.register(
      binding: HotkeyBinding(key: LocalKeyPress(.character("s"), modifiers: .control))
    ) { keyPress in
      keyPress.key == .character("s") && keyPress.modifiers == .control
    }

    let handled = registry.dispatch(LocalKeyPress(.character("x")))
    #expect(!handled)
  }

  @Test("first matching handler wins")
  func firstMatchWins() {
    let registry = HotkeyRegistry()
    var firstCalled = false
    var secondCalled = false

    registry.register(
      binding: HotkeyBinding(key: LocalKeyPress(.character("q")))
    ) { _ in
      firstCalled = true
      return true
    }

    registry.register(
      binding: HotkeyBinding(key: LocalKeyPress(.character("q")))
    ) { _ in
      secondCalled = true
      return true
    }

    let handled = registry.dispatch(LocalKeyPress(.character("q")))
    #expect(handled)
    #expect(firstCalled)
    #expect(!secondCalled)
  }

  @Test("handler returning false allows next handler")
  func passThrough() {
    let registry = HotkeyRegistry()
    var secondCalled = false

    registry.register(
      binding: HotkeyBinding(key: LocalKeyPress(.character("q")))
    ) { _ in
      false
    }

    registry.register(
      binding: HotkeyBinding(key: LocalKeyPress(.character("q")))
    ) { _ in
      secondCalled = true
      return true
    }

    let handled = registry.dispatch(LocalKeyPress(.character("q")))
    #expect(handled)
    #expect(secondCalled)
  }

  @Test("reset clears all handlers")
  func reset() {
    let registry = HotkeyRegistry()

    registry.register(
      binding: HotkeyBinding(key: LocalKeyPress(.character("q")))
    ) { _ in
      true
    }

    registry.reset()
    let handled = registry.dispatch(LocalKeyPress(.character("q")))
    #expect(!handled)
  }

  @Test("registeredBindings returns all bindings")
  func registeredBindings() {
    let registry = HotkeyRegistry()

    registry.register(
      binding: HotkeyBinding(key: LocalKeyPress(.character("s"), modifiers: .control), label: "Save")
    ) { _ in true }

    registry.register(
      binding: HotkeyBinding(key: LocalKeyPress(.character("q")), label: "Quit")
    ) { _ in true }

    let bindings = registry.registeredBindings()
    #expect(bindings.count == 2)
    #expect(bindings[0].label == "Save")
    #expect(bindings[1].label == "Quit")
  }

  @Test("snapshot and restore preserves handlers")
  func snapshotAndRestore() {
    let registry = HotkeyRegistry()
    var called = false

    registry.register(
      binding: HotkeyBinding(key: LocalKeyPress(.character("s"), modifiers: .control))
    ) { _ in
      called = true
      return true
    }

    let snapshot = registry.snapshot()
    registry.reset()
    #expect(!registry.dispatch(LocalKeyPress(.character("s"), modifiers: .control)))

    registry.restore(snapshot)
    let handled = registry.dispatch(LocalKeyPress(.character("s"), modifiers: .control))
    #expect(handled)
    #expect(called)
  }
}
