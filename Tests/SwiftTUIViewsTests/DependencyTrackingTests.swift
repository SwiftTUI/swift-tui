import Observation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

private enum DependencyTrackingKey: EnvironmentKey {
  static let defaultValue = "unset"
}

extension EnvironmentValues {
  fileprivate var dependencyTrackedValue: String {
    get { self[DependencyTrackingKey.self] }
    set { self[DependencyTrackingKey.self] = newValue }
  }
}

@MainActor
@Observable
private final class DependencyObservableModel {
  var name = "Ada"
}

@MainActor
@Suite
struct DependencyTrackingTests {
  @Test("state reads populate graph dependencies")
  func stateReadsPopulateDependencies() throws {
    let (dependencies, snapshot) = try resolveDependenciesWithSnapshot(
      StateDependencyProbe()
    )

    let stateRead = try #require(dependencies.stateSlotReads.first)
    #expect(dependencies.stateSlotReads.count == 1)
    #expect(snapshot.nodeIDByIdentity[testIdentity("Root")] == stateRead.owner)
  }

  @Test("environment reads populate graph dependencies")
  func environmentReadsPopulateDependencies() throws {
    var environmentValues = EnvironmentValues()
    environmentValues.dependencyTrackedValue = "tracked"

    let dependencies = try resolveDependencies(
      EnvironmentDependencyProbe(),
      environmentValues: environmentValues
    )

    #expect(
      dependencies.environmentReads == [
        ObjectIdentifier(DependencyTrackingKey.self)
      ]
    )
  }

  @Test("@Environment reads populate graph dependencies")
  func environmentPropertyWrapperReadsPopulateDependencies() throws {
    var environmentValues = EnvironmentValues()
    environmentValues.dependencyTrackedValue = "tracked"

    let dependencies = try resolveDependencies(
      EnvironmentPropertyWrapperDependencyProbe(),
      environmentValues: environmentValues
    )

    #expect(
      dependencies.environmentReads == [
        ObjectIdentifier(DependencyTrackingKey.self)
      ]
    )
  }

  @Test("observable-backed reads populate graph dependencies")
  func observableReadsPopulateDependencies() throws {
    let model = DependencyObservableModel()

    let dependencies = try resolveDependencies(
      ObservableDependencyProbe(model: model)
    )

    #expect(
      dependencies.observableReads == [
        ObjectIdentifier(model)
      ]
    )
  }
}

private struct StateDependencyProbe: View {
  @State private var count = 1

  var body: some View {
    Text("Count \(count)")
  }
}

private struct EnvironmentDependencyProbe: View {
  var body: some View {
    EnvironmentReader(\.dependencyTrackedValue) { value in
      Text(value)
    }
  }
}

private struct EnvironmentPropertyWrapperDependencyProbe: View {
  @Environment(\.dependencyTrackedValue) private var value

  var body: some View {
    Text(value)
  }
}

private struct ObservableDependencyProbe: View {
  @Bindable private var model: DependencyObservableModel

  init(model: DependencyObservableModel) {
    _model = Bindable(model)
  }

  var body: some View {
    Text($model.name.wrappedValue)
  }
}

@MainActor
private func resolveDependencies<V: View>(
  _ view: V,
  environmentValues: EnvironmentValues = .init()
) throws -> DependencySet {
  return try resolveDependenciesWithSnapshot(
    view,
    environmentValues: environmentValues
  ).dependencies
}

@MainActor
private func resolveDependenciesWithSnapshot<V: View>(
  _ view: V,
  environmentValues: EnvironmentValues = .init()
) throws -> (
  dependencies: DependencySet,
  snapshot: ViewGraph.DebugTotalStateSnapshot
) {
  let graph = ViewGraph()
  graph.beginFrame()

  var context = ResolveContext(
    identity: testIdentity("Root"),
    environmentValues: environmentValues,
    applyEnvironmentValues: true
  )
  context.viewGraph = graph

  _ = Resolver().resolve(view, in: context)
  return (
    try #require(graph.dependencies(for: testIdentity("Root"))),
    graph.debugTotalStateSnapshot()
  )
}
