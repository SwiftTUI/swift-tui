import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
struct BindingDependencyModelTests {
  @Test("binding projection without a wrappedValue read records no state dependency")
  func bindingProjectionWithoutReadRecordsNoStateDependency() {
    let snapshot = resolveSnapshot(ProjectingOnlyOwnerProbe())

    #expect(snapshot.stateSlotDependents.isEmpty)
  }

  @Test("manual closure binding reads do not create framework state dependencies")
  func manualClosureBindingReadDoesNotCreateStateDependency() {
    let binding = Binding<String>(
      get: { "manual" },
      set: { _ in }
    )

    let snapshot = resolveSnapshot(ManualBindingReaderProbe(binding: binding))

    #expect(snapshot.stateSlotDependents.isEmpty)
  }

  @Test("dynamic-member bindings track through their underlying state slot")
  func dynamicMemberBindingTracksUnderlyingStateSlot() {
    let snapshot = resolveSnapshot(DynamicMemberBindingOwnerProbe())

    #expect(snapshot.stateSlotDependents.count == 1)
    let dependents = snapshot.stateSlotDependents.values.flatMap { Array($0) }
    #expect(!dependents.isEmpty)
  }

  private func resolveSnapshot<V: View>(
    _ view: V
  ) -> ViewGraph.DebugTotalStateSnapshot {
    let graph = ViewGraph()
    graph.beginFrame()
    var context = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(view, in: context)
    return graph.debugTotalStateSnapshot()
  }
}

private struct ProjectingOnlyOwnerProbe: View {
  @State private var title = "projected"

  var body: some View {
    BindingStorageProbe(value: $title)
  }
}

private struct BindingStorageProbe: View {
  @Binding var value: String

  var body: some View {
    Text("stored")
  }
}

private struct ManualBindingReaderProbe: View {
  let binding: Binding<String>

  var body: some View {
    Text(binding.wrappedValue)
  }
}

private struct DynamicMemberBindingOwnerProbe: View {
  @State private var model = BindingDependencyModel(title: "dynamic")

  var body: some View {
    BindingTextReader(value: $model.title)
  }
}

private struct BindingDependencyModel: Equatable, Sendable {
  var title: String
}

private struct BindingTextReader: View {
  @Binding var value: String

  var body: some View {
    Text(value)
  }
}
