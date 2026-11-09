import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct GestureStateTests {

  @Test("a seed-only reauthor refreshes the gesture reset binding")
  func reauthoredResetSeed() {
    final class Probe { var binding: AnyGestureStateBinding? }
    struct Child: View {
      @GestureState var value: Int
      let probe: Probe
      init(seed: Int, probe: Probe) {
        _value = GestureState(initialValue: seed)
        self.probe = probe
      }
      var body: some View {
        let _ = { probe.binding = $value.eraseToAnyBinding() }()
        Text("Value \(value)").gesture(DragGesture().updating($value) { _, state, _ in state = 99 })
      }
    }
    struct Root: View {
      let seed: Int
      let probe: Probe
      var body: some View { Child(seed: seed, probe: probe) }
    }
    let probe = Probe()
    let renderer = DefaultRenderer()
    let context = ResolveContext(identity: testIdentity("GestureSeed"))
    _ = renderer.render(Root(seed: 3, probe: probe), context: context)
    _ = renderer.render(Root(seed: 7, probe: probe), context: context)
    probe.binding?.setValueErased(99)
    probe.binding?.resetToSeed()
    let result = renderer.render(Root(seed: 7, probe: probe), context: context)
    #expect(result.rasterSurface.lines.joined().contains("Value 7"))
  }

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
