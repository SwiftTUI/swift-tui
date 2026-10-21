import Observation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct BindingOwnershipContractTests {
  private struct Pair {
    var first = false
    var second = false
  }

  @Test func memberRoutesDistinguishFieldsAndOwners() {
    let first = State(wrappedValue: Pair())
    let second = State(wrappedValue: Pair())
    let firstRoute = first.projectedValue.first
    #expect(firstRoute.bindingSourceID != nil)
    #expect(firstRoute.bindingSourceID == first.projectedValue.first.bindingSourceID)
    #expect(firstRoute.bindingSourceID != first.projectedValue.second.bindingSourceID)
    let root = Identity(components: ["root"])
    #expect(
      root.explicitID(firstRoute.bindingSourceID)
        != root.explicitID(first.projectedValue.second.bindingSourceID))
    #expect(firstRoute.bindingSourceID != second.projectedValue.first.bindingSourceID)
    firstRoute.wrappedValue = true
    #expect(first.wrappedValue.first && !first.wrappedValue.second)
    #expect(!second.wrappedValue.first)
  }

  @Observable final class Model {
    var first = 0
    var second = 0
  }

  @Test func observableRoutesDistinguishPropertiesAndObjects() {
    let first = Model()
    let second = Model()
    let route = Bindable(first).first
    #expect(route.bindingSourceID != nil)
    #expect(route.bindingSourceID == Bindable(first).first.bindingSourceID)
    #expect(route.bindingSourceID != Bindable(first).second.bindingSourceID)
    #expect(route.bindingSourceID != Bindable(second).first.bindingSourceID)
  }

  @MainActor
  private struct ExplicitSources {
    var binding: Binding<Int>
    var bindable: Bindable<Model>
  }

  @Test func capturePreparationPreservesExplicitSources() {
    let state = State(wrappedValue: 0)
    let model = Model()
    let sources = ExplicitSources(binding: state.projectedValue, bindable: Bindable(model))
    let graph = ViewGraph()
    let node = graph.prepareDynamicPropertyUpdate(identity: testIdentity("consumer"))
    let scope = AuthoringContext(
      viewIdentity: node.identity, focusedValues: .init(), viewNode: node)
    let prepared = withAuthoringContext(scope) {
      bindingForwardedDynamicPropertyCaptures(sources)
    }
    #expect(prepared.binding.bindingSourceID == sources.binding.bindingSourceID)
    #expect(prepared.bindable.first.bindingSourceID == sources.bindable.first.bindingSourceID)
    prepared.binding.wrappedValue = 7
    prepared.bindable.first.wrappedValue = 9
    #expect(state.wrappedValue == 7)
    #expect(model.first == 9)
  }

  @Test func focusedClosureBindingsCarryTheirPublisher() {
    enum Key: FocusedValueKey { typealias Value = Binding<Int> }
    let first = State(wrappedValue: 0)
    let second = State(wrappedValue: 0)
    var lhs = FocusedValues()
    var rhs = FocusedValues()
    lhs[Key.self] = Binding(get: { first.wrappedValue }, set: { first.wrappedValue = $0 })
    rhs[Key.self] = Binding(get: { second.wrappedValue }, set: { second.wrappedValue = $0 })
    #expect(
      lhs.attributed(to: Identity(components: ["first"])).focusSyncEquals(
        lhs.attributed(to: Identity(components: ["first"]))))
    #expect(
      !lhs.attributed(to: Identity(components: ["first"])).focusSyncEquals(
        rhs.attributed(to: Identity(components: ["second"]))))
  }
}
