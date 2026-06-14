import Observation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

private enum DependencyTrackingKey: EnvironmentKey {
  static let defaultValue = "unset"
}

private enum DependencyObservableModelKey: EnvironmentKey {
  static let defaultValue = DependencyObservableModel()
}

extension EnvironmentValues {
  fileprivate var dependencyTrackedValue: String {
    get { self[DependencyTrackingKey.self] }
    set { self[DependencyTrackingKey.self] = newValue }
  }

  fileprivate var dependencyObservableModel: DependencyObservableModel {
    get { self[DependencyObservableModelKey.self] }
    set { self[DependencyObservableModelKey.self] = newValue }
  }
}

@Observable
private final class DependencyObservableModel: @unchecked Sendable {
  var name = "Ada"
  var age = 37
  var scores = [1, 2, 3]
}

@MainActor
@Suite
struct DependencyModelTests {
  // MARK: - State

  @Test("state reads populate graph dependencies")
  func stateReadsPopulateDependencies() throws {
    let (dependencies, snapshot) = try resolveDependenciesWithSnapshot(
      StateDependencyProbe()
    )

    let stateRead = try #require(dependencies.stateSlotReads.first)
    #expect(dependencies.stateSlotReads.count == 1)
    #expect(snapshot.nodeIDByIdentity[testIdentity("Root")] == stateRead.owner)
  }

  // MARK: - Environment

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

  @Test("observable environment reads record both the key and object token")
  func observableEnvironmentReadsRecordKeyAndObjectToken() throws {
    let model = DependencyObservableModel()
    var environmentValues = EnvironmentValues()
    environmentValues.dependencyObservableModel = model

    let dependencies = try resolveDependencies(
      ObservableEnvironmentDependencyProbe(),
      environmentValues: environmentValues
    )

    #expect(
      dependencies.environmentReads == [
        ObjectIdentifier(DependencyObservableModelKey.self)
      ]
    )
    #expect(
      dependencies.observableReads == [
        ObjectIdentifier(model)
      ]
    )
  }

  // MARK: - Observable

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

  @Test("characterization: @Bindable graph keys are object tokens, not key paths")
  func bindableReadsOfDifferentPropertiesShareObjectDependencyToken() throws {
    let model = DependencyObservableModel()

    let nameDependencies = try resolveDependencies(
      ObservableDependencyProbe(model: model, property: .name)
    )
    let ageDependencies = try resolveDependencies(
      ObservableDependencyProbe(model: model, property: .age)
    )
    let collectionDependencies = try resolveDependencies(
      ObservableDependencyProbe(model: model, property: .firstScore)
    )

    let expected = Set([ObjectIdentifier(model)])
    #expect(nameDependencies.observableReads == expected)
    #expect(ageDependencies.observableReads == expected)
    #expect(collectionDependencies.observableReads == expected)
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
  let property: ObservableProperty

  init(
    model: DependencyObservableModel,
    property: ObservableProperty = .name
  ) {
    _model = Bindable(model)
    self.property = property
  }

  var body: some View {
    switch property {
    case .name:
      Text($model.name.wrappedValue)
    case .age:
      Text("\($model.age.wrappedValue)")
    case .firstScore:
      Text("\($model.scores.wrappedValue.first ?? -1)")
    }
  }
}

private enum ObservableProperty {
  case name
  case age
  case firstScore
}

private struct ObservableEnvironmentDependencyProbe: View {
  @Environment(\.dependencyObservableModel) private var model

  var body: some View {
    Text(model.name)
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
