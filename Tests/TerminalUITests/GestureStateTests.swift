import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct GestureStateTests {
  @Test("@GestureState wrappedValue starts at seed outside a resolve pass")
  func startsAtSeed() {
    struct V: View {
      @GestureState var offset: Int = 7
      var body: some View { Text("\(offset)") }
    }
    let v = V()
    // Direct access outside a resolve pass returns the seed (local fallback).
    #expect(v.offset == 7)
  }

  @Test("GestureStateBinding writes through to storage and resets to seed")
  func writeAndReset() {
    // Use the box directly for a unit test -- no resolve pass context.
    let box = GestureStateBox<Int>(seed: 0, slotOrdinal: 0)
    let binding = box.eraseToAnyBinding()
    binding.setValueErased(42)
    #expect(box.currentValue() == 42)
    binding.resetToSeed()
    #expect(box.currentValue() == 0)
  }

  @Test("LocalGestureStateRegistry drains bindings on subtree removal")
  func drainOnRemove() {
    let registry = LocalGestureStateRegistry()
    let identity = Identity(components: ["r"])
    let box = GestureStateBox<Int>(seed: 0, slotOrdinal: 0)
    // Set a non-seed value so the box has something to reset.
    box.setValue(99)
    registry.register(identity: identity, binding: box.eraseToAnyBinding())
    registry.removeSubtrees(rootedAt: [identity])
    #expect(box.currentValue() == 0)  // reset fired during removal
  }

  @Test("LocalGestureStateRegistry bindings(for:) returns registered bindings")
  func bindingsRetrieval() {
    let registry = LocalGestureStateRegistry()
    let identity = Identity(components: ["r"])
    let box = GestureStateBox<Int>(seed: 0, slotOrdinal: 0)
    registry.register(identity: identity, binding: box.eraseToAnyBinding())
    #expect(registry.bindings(for: identity).count == 1)
  }
}
