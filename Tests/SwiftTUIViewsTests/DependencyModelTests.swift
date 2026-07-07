import Observation
import Synchronization
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

private final class DependencyObservableModel: Observable, Sendable {
  private let observationRegistrar = ObservationRegistrar()
  private let nameStorage = Mutex("Ada")
  private let ageStorage = Mutex(37)
  private let scoresStorage = Mutex([1, 2, 3])

  var name: String {
    get {
      observationRegistrar.access(self, keyPath: \.name)
      return nameStorage.withLock { $0 }
    }
    set {
      observationRegistrar.withMutation(of: self, keyPath: \.name) {
        nameStorage.withLock { $0 = newValue }
      }
    }
  }

  var age: Int {
    get {
      observationRegistrar.access(self, keyPath: \.age)
      return ageStorage.withLock { $0 }
    }
    set {
      observationRegistrar.withMutation(of: self, keyPath: \.age) {
        ageStorage.withLock { $0 = newValue }
      }
    }
  }

  var scores: [Int] {
    get {
      observationRegistrar.access(self, keyPath: \.scores)
      return scoresStorage.withLock { $0 }
    }
    set {
      observationRegistrar.withMutation(of: self, keyPath: \.scores) {
        scoresStorage.withLock { $0 = newValue }
      }
    }
  }
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

  @Test("wrapper dependency manifest matches shipped axes")
  func wrapperDependencyManifestMatchesShippedAxes() throws {
    let model = DependencyObservableModel()
    let manifest: [String: Set<DependencyAxis>] = [
      "@State": [.stateSlot],
      "@Binding": [],
      "@Environment": [.environmentKey],
      "EnvironmentReader": [.environmentKey],
      "@Bindable": [.observableObjectToken],
      "@GestureState": [.stateSlot],
      "@FocusState": [.stateSlot],
      // An `EnvironmentReader(\.focusedIdentity)` read records BOTH focus
      // dependency currencies: the wholesale-union runtime key (arbitrary
      // comparisons must recompute on every move) and the side-field read
      // sentinel the keyPath getter stamps (the root-path predicate that
      // demotes reader-free focus targets to chrome-only scope members).
      "focus environment": [.runtimeFocusEnvironmentKey, .runtimeFocusSideFieldRead],
    ]

    var environmentValues = EnvironmentValues()
    environmentValues.dependencyTrackedValue = "tracked"

    #expect(try dependencyAxes(StateDependencyProbe()) == manifest["@State"])
    #expect(try dependencyAxes(BindingManifestProbe()) == manifest["@Binding"])
    #expect(
      try dependencyAxes(
        EnvironmentPropertyWrapperDependencyProbe(),
        environmentValues: environmentValues
      ) == manifest["@Environment"]
    )
    #expect(
      try dependencyAxes(
        EnvironmentDependencyProbe(),
        environmentValues: environmentValues
      ) == manifest["EnvironmentReader"]
    )
    let bindableDependencies = try resolveDependencies(
      ObservableDependencyProbe(model: model)
    )
    #expect(
      dependencyAxes(bindableDependencies).isSuperset(
        of: manifest["@Bindable"] ?? []
      )
    )
    #expect(bindableDependencies.stateSlotReads.isEmpty)
    #expect(bindableDependencies.observableReads == [ObjectIdentifier(model)])
    #expect(
      try dependencyAxes(GestureStateDependencyProbe())
        == manifest["@GestureState"]
    )
    #expect(
      try dependencyAxes(FocusStateDependencyProbe())
        == manifest["@FocusState"]
    )

    let focusEnvironmentDependencies = try resolveDependencies(
      FocusEnvironmentDependencyProbe()
    )
    #expect(
      focusEnvironmentDependencies.environmentReads.isSubset(
        of: EnvironmentValues.runtimeFocusStateDependencyKeys.union(
          [EnvironmentValues.runtimeFocusSideFieldReadDependencyKey]
        )
      )
    )
    #expect(
      dependencyAxes(focusEnvironmentDependencies)
        == manifest["focus environment"]
    )
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
      dependencies.environmentReads.contains(ObjectIdentifier(DependencyObservableModelKey.self)))
    #expect(
      dependencies.observableReads == [
        ObjectIdentifier(model)
      ]
    )
  }

  @Test("characterization: observable environment graph keys are object tokens, not key paths")
  func observableEnvironmentReadsOfDifferentPropertiesShareObjectDependencyToken() throws {
    let model = DependencyObservableModel()
    var environmentValues = EnvironmentValues()
    environmentValues.dependencyObservableModel = model

    let nameDependencies = try resolveDependencies(
      ObservableEnvironmentDependencyProbe(property: .name),
      environmentValues: environmentValues
    )
    let ageDependencies = try resolveDependencies(
      ObservableEnvironmentDependencyProbe(property: .age),
      environmentValues: environmentValues
    )
    let collectionDependencies = try resolveDependencies(
      ObservableEnvironmentDependencyProbe(property: .firstScore),
      environmentValues: environmentValues
    )

    let expectedEnvironmentRead = ObjectIdentifier(DependencyObservableModelKey.self)
    let expectedObservableReads = Set([ObjectIdentifier(model)])
    // `@Environment` currently also carries authoring-context environment reads.
    // The parity invariant here is that the authored environment key and the
    // observable object token remain separate axes.
    #expect(nameDependencies.environmentReads.contains(expectedEnvironmentRead))
    #expect(ageDependencies.environmentReads.contains(expectedEnvironmentRead))
    #expect(collectionDependencies.environmentReads.contains(expectedEnvironmentRead))
    #expect(nameDependencies.observableReads == expectedObservableReads)
    #expect(ageDependencies.observableReads == expectedObservableReads)
    #expect(collectionDependencies.observableReads == expectedObservableReads)
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

private struct BindingManifestProbe: View {
  @Binding var value: String

  init() {
    _value = .constant("constant")
  }

  var body: some View {
    Text(value)
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
  let property: ObservableProperty

  init(property: ObservableProperty = .name) {
    self.property = property
  }

  var body: some View {
    switch property {
    case .name:
      Text(model.name)
    case .age:
      Text("\(model.age)")
    case .firstScore:
      Text("\(model.scores.first ?? -1)")
    }
  }
}

private struct GestureStateDependencyProbe: View {
  @GestureState private var offset = 0

  var body: some View {
    Text("Offset \(offset)")
  }
}

private struct FocusStateDependencyProbe: View {
  @FocusState private var focused: Bool

  var body: some View {
    Text(focused ? "Focused" : "Blurred")
  }
}

private struct FocusEnvironmentDependencyProbe: View {
  var body: some View {
    EnvironmentReader(\.focusedIdentity) { focusedIdentity in
      Text(focusedIdentity?.description ?? "none")
    }
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

private enum DependencyAxis: Hashable {
  case stateSlot
  case environmentKey
  case observableObjectToken
  case runtimeFocusEnvironmentKey
  case runtimeFocusSideFieldRead
  case runtimeFocusTargetScopedRead
}

@MainActor
private func dependencyAxes<V: View>(
  _ view: V,
  environmentValues: EnvironmentValues = .init()
) throws -> Set<DependencyAxis> {
  dependencyAxes(
    try resolveDependencies(
      view,
      environmentValues: environmentValues
    )
  )
}

private func dependencyAxes(
  _ dependencies: DependencySet
) -> Set<DependencyAxis> {
  var axes: Set<DependencyAxis> = []
  if !dependencies.stateSlotReads.isEmpty {
    axes.insert(.stateSlot)
  }
  if !dependencies.observableReads.isEmpty {
    axes.insert(.observableObjectToken)
  }
  let runtimeFocusReads = dependencies.environmentReads.intersection(
    EnvironmentValues.runtimeFocusStateDependencyKeys
  )
  if !runtimeFocusReads.isEmpty {
    axes.insert(.runtimeFocusEnvironmentKey)
  }
  let sideFieldReads = dependencies.environmentReads.intersection(
    [EnvironmentValues.runtimeFocusSideFieldReadDependencyKey]
  )
  if !sideFieldReads.isEmpty {
    axes.insert(.runtimeFocusSideFieldRead)
  }
  // Target-scoped side-field reads (`focusedIdentity(comparedAgainst:)`)
  // record their own sentinel plus the compared identities
  // (`DependencySet.focusComparisonTargets`); the focus-move predicates
  // treat such a reader as affected only by moves onto its targets.
  let targetScopedReads = dependencies.environmentReads.intersection(
    [EnvironmentValues.runtimeFocusTargetScopedReadDependencyKey]
  )
  if !targetScopedReads.isEmpty {
    axes.insert(.runtimeFocusTargetScopedRead)
  }
  if !dependencies.environmentReads
    .subtracting(runtimeFocusReads)
    .subtracting(sideFieldReads)
    .subtracting(targetScopedReads)
    .isEmpty
  {
    axes.insert(.environmentKey)
  }
  return axes
}
