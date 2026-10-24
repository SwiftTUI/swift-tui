import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCScopedServicesTests {
  private func resolve<V: View>(
    _ content: V, graph: ViewGraph?, id: Int,
    environment: EnvironmentValues = .init()
  ) {
    graph?.beginFrame()
    var context = ResolveContext(
      identity: testIdentity("setC\(id)"), environmentValues: environment)
    context.viewGraph = graph
    _ = Resolver().resolve(content, in: context)
  }

  @Test func setC021SharedLeafRetainsSeparateDeclarationSnapshots() throws {
    let graph = ViewGraph()
    let log = SetCServiceLog()
    defer { log.entries.removeAll() }
    let leaf = SetCServiceLeaf(log: log)
    resolve(
      HStack {
        leaf.environment(\.imageResourceRoots, ["a"])
        leaf.environment(\.imageResourceRoots, ["b"])
      }, graph: graph, id: 21)
    try #require(log.entries.count == 2)
    #expect(log.entries[0].roots() == ["a"])
    #expect(log.entries[1].roots() == ["b"])
  }

  @Test func setC022ReevaluationDoesNotRewriteOldDeclarationSnapshot() throws {
    let graph = ViewGraph()
    let log = SetCServiceLog()
    defer { log.entries.removeAll() }
    let leaf = SetCServiceLeaf(log: log).padding(1)
    resolve(leaf.environment(\.imageResourceRoots, ["old"]), graph: graph, id: 22)
    let old = try #require(log.entries.last)
    resolve(leaf.environment(\.imageResourceRoots, ["new"]), graph: graph, id: 22)
    let fresh = try #require(log.entries.last)
    #expect(old.roots() == ["old"])
    #expect(fresh.roots() == ["new"])
  }

  @Test func setC023HandlerEnvironmentAndFocusedGraphChooseDifferentRoutes() throws {
    let first = ViewGraph()
    let second = ViewGraph()
    let log = SetCServiceLog()
    defer { log.entries.removeAll() }
    let provider = SetCServiceProvider()
    provider.publish("own")
    LiveFocusedValuesRegistry.register(scope: first.stateGraphScopeID) { [weak provider] in
      provider?.values
    }
    resolve(
      SetCServiceLeaf(log: log).environment(\.imageResourceRoots, ["own"]),
      graph: first, id: 23)
    let own = try #require(log.entries.last)
    resolve(
      SetCServiceLeaf(log: log).environment(\.imageResourceRoots, ["other"]),
      graph: second, id: 23)
    let other = try #require(log.entries.last)
    withImperativeAuthoringContext(other.scope) {
      #expect(own.roots() == ["other"])
      #expect(own.title() == "own")
    }
    #expect(own.roots() == ["own"])
  }

  @Test func setC024EarlyReturnFromNestedInvocationRestoresEnvironment() throws {
    let graph = ViewGraph()
    let log = SetCServiceLog()
    defer { log.entries.removeAll() }
    resolve(SetCServiceLeaf(log: log), graph: graph, id: 24)
    let entry = try #require(log.entries.last)
    let scope = try #require(entry.scope)
    var outer = EnvironmentValues()
    var inner = EnvironmentValues()
    outer.imageResourceRoots = ["outer"]
    inner.imageResourceRoots = ["inner"]
    withImperativeAuthoringContext(scope.withEnvironmentValues(outer)) {
      let result: Result<Void, SetCServiceError> =
        withImperativeAuthoringContext(scope.withEnvironmentValues(inner)) {
          #expect(entry.roots() == ["inner"])
          return .failure(.expected)
        }
      if case .success = result { Issue.record("fixture must return its error result") }
      #expect(entry.roots() == ["outer"])
    }
  }

  @Test func setC025GraphlessForwardingPreservesDeclaration() throws {
    let log = SetCServiceLog()
    defer { log.entries.removeAll() }
    resolve(
      SetCServiceLeaf(log: log).padding(1).environment(\.imageResourceRoots, ["declared"]),
      graph: nil, id: 25)
    let entry = try #require(log.entries.last)
    var incidental = EnvironmentValues()
    incidental.imageResourceRoots = ["incidental"]
    EnvironmentValuesStorage.binding(incidental) {
      #expect(entry.roots() == ["declared"])
    }
  }

  @Test(arguments: [26, 27, 28, 29, 30])
  func liveFocusedPublication(id: Int) throws {
    let graph = ViewGraph()
    let provider = SetCServiceProvider()
    provider.publish("a")
    LiveFocusedValuesRegistry.register(scope: graph.stateGraphScopeID) { [weak provider] in
      provider?.values
    }
    let log = SetCServiceLog()
    defer { log.entries.removeAll() }
    var declaration = EnvironmentValues()
    declaration.focusedValues.setCTitle = "snapshot"
    resolve(SetCServiceLeaf(log: log).padding(1), graph: graph, id: id, environment: declaration)
    let entry = try #require(log.entries.last)
    try #require(entry.title() == "a")
    let oldBinding = try #require(entry.binding())
    switch id {
    case 26:
      provider.publish("b", second: true)
      #expect(entry.title() == "b")
      entry.write(9)
      #expect(provider.b == 9)
      #expect(provider.a == 1)
    case 27:
      provider.values = FocusedValues()
      #expect(entry.title() == nil)
      #expect(entry.binding() == nil)
    case 28:
      provider.values = FocusedValues()
      entry.write(9)
      #expect(provider.a == 1)
      #expect(provider.b == 2)
    case 29:
      provider.publish("b", second: true)
      oldBinding.wrappedValue = 8
      entry.write(9)
      #expect(provider.a == 8)
      #expect(provider.b == 9)
    default:
      var outer = FocusedValues()
      var inner = FocusedValues()
      outer.setCTitle = "outer"
      inner.setCTitle = "inner"
      LiveFocusedValuesRegistry.withFocusedValuesOverride(outer) {
        #expect(entry.title() == "outer")
        LiveFocusedValuesRegistry.withFocusedValuesOverride(inner) {
          #expect(entry.title() == "inner")
        }
        #expect(entry.title() == "outer")
      }
      #expect(entry.title() == "a")
    }
  }
}

private enum SetCServiceError: Error { case expected }
private enum SetCTitleKey: FocusedValueKey { typealias Value = String }
private enum SetCNumberKey: FocusedValueKey { typealias Value = Binding<Int> }

extension FocusedValues {
  fileprivate var setCTitle: String? {
    get { self[SetCTitleKey.self] }
    set { self[SetCTitleKey.self] = newValue }
  }
  fileprivate var setCNumber: Binding<Int>? {
    get { self[SetCNumberKey.self] }
    set { self[SetCNumberKey.self] = newValue }
  }
}

@MainActor
private final class SetCServiceProvider {
  var a = 1
  var b = 2
  var values: FocusedValues?
  func publish(_ title: String, second: Bool = false) {
    var next = FocusedValues()
    next.setCTitle = title
    next.setCNumber = Binding(
      get: { [weak self] in second ? (self?.b ?? 0) : (self?.a ?? 0) },
      set: { [weak self] in
        if second { self?.b = $0 } else { self?.a = $0 }
      })
    values = next
  }
}

@MainActor
private final class SetCServiceLog {
  struct Entry {
    var roots: () -> [String]
    var title: () -> String?
    var binding: () -> Binding<Int>?
    var write: (Int) -> Void
    var scope: ImperativeAuthoringContextSnapshot?
  }
  var entries: [Entry] = []
}

private struct SetCServiceLeaf: View {
  @Environment(\.imageResourceRoots) var roots
  @FocusedValue(\.setCTitle) var title
  @FocusedBinding(\.setCNumber) var number
  let log: SetCServiceLog
  var body: some View {
    log.entries.append(
      .init(
        roots: { roots }, title: { title }, binding: { $number },
        write: { number = $0 }, scope: currentImperativeAuthoringContextSnapshot()))
    return Text("services")
  }
}
