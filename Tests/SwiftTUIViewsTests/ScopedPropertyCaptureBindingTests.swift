import Observation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Observable
private final class CaptureEnvironmentModel {
  var calls = 0
}

private enum CaptureTitleKey: FocusedValueKey { typealias Value = String }
private enum CaptureNumberKey: FocusedValueKey { typealias Value = Binding<Int> }

extension FocusedValues {
  fileprivate var captureTitle: String? {
    get { self[CaptureTitleKey.self] }
    set { self[CaptureTitleKey.self] = newValue }
  }
  fileprivate var captureNumber: Binding<Int>? {
    get { self[CaptureNumberKey.self] }
    set { self[CaptureNumberKey.self] = newValue }
  }
}

@MainActor
@Suite(.serialized)
struct ScopedPropertyCaptureBindingTests {
  private final class Log {
    var environment: (() -> [String])?
    var title: (() -> String?)?
    var number: (() -> Binding<Int>?)?
    var write: ((Int) -> Void)?
    var scope: ImperativeAuthoringContextSnapshot?
    var bodyEnvironment: [String] = []
    var stateRead: (() -> Int)?
    var stateBinding: Binding<Int>?
  }

  private struct Host: View {
    @State var count = 0
    @Environment(\.imageResourceRoots) var roots
    @FocusedValue(\.captureTitle) var title
    @FocusedBinding(\.captureNumber) var number
    let log: Log

    var body: some View {
      log.environment = { roots }
      log.title = { title }
      log.number = { $number }
      log.write = { number = $0 }
      log.scope = currentImperativeAuthoringContextSnapshot()
      log.bodyEnvironment = roots
      log.stateRead = { count }
      log.stateBinding = $count
      return Text(title ?? "none")
    }
  }

  private func environment(_ name: String) -> EnvironmentValues {
    var result = EnvironmentValues()
    result.imageResourceRoots = [name]
    result.focusedValues.captureTitle = name
    return result
  }

  private func resolve(_ log: Log, graph: ViewGraph? = nil, name: String = "declaration") {
    var context = ResolveContext(
      identity: testIdentity("scoped-capture"), environmentValues: environment(name))
    context.viewGraph = graph
    _ = Resolver().resolve(Host(log: log), in: context)
  }

  private func scope(_ log: Log, _ name: String) throws -> ImperativeAuthoringContextSnapshot {
    try #require(log.scope).withEnvironmentValues(environment(name))
  }

  @Test("registered environment overrides declaration and restores nested dispatch")
  func registrationCompatibility() throws {
    let log = Log()
    resolve(log, graph: ViewGraph())
    let read = try #require(log.environment)
    let outer = try scope(log, "outer")
    let inner = try scope(log, "inner")
    withImperativeAuthoringContext(outer) {
      #expect(read() == ["outer"])
      withImperativeAuthoringContext(inner) { #expect(read() == ["inner"]) }
      withImperativeAuthoringContext(nil) { #expect(read() == ["outer"]) }
      #expect(read() == ["outer"])
    }
    let graph = ViewGraph()
    let evaluating = graph.beginEvaluation(
      identity: testIdentity("foreign-evaluation"), invalidator: nil)
    ViewNodeContext.withValue(evaluating) {
      EnvironmentValuesStorage.binding(environment("incidental")) {
        withImperativeAuthoringContext(inner) { #expect(read() == ["inner"]) }
      }
    }
  }

  @Test(
    "declaration snapshots survive absent and incidental ambient scope, including graphless preparation"
  )
  func declarationFallback() throws {
    let log = Log()
    resolve(log)
    let read = try #require(log.environment)
    #expect(read() == ["declaration"])
    EnvironmentValuesStorage.binding(environment("incidental")) {
      #expect(read() == ["declaration"])
    }
    resolve(log, name: "changed")
    let freshRead = try #require(log.environment)
    #expect(log.bodyEnvironment == ["changed"])
    #expect(freshRead() == ["changed"])
    #expect(read() == ["declaration"])
  }

  @Test("nested resolution supersedes an outer handler environment")
  func evaluationInsideInvocation() throws {
    let log = Log()
    resolve(log)
    let invocation = try scope(log, "invocation")
    withImperativeAuthoringContext(invocation) {
      let inner = Log()
      resolve(inner, name: "evaluation")
      #expect(inner.bodyEnvironment == ["evaluation"])
    }
  }

  @Test("an explicit callback inside evaluation retains State capture and its refresh adapter")
  func stateInvocationInsideEvaluation() throws {
    let first = ViewGraph()
    let second = ViewGraph()
    let log = Log()
    resolve(log, graph: first)
    let read = try #require(log.stateRead)
    let binding = try #require(log.stateBinding)
    binding.wrappedValue = 9
    resolve(log, graph: second)
    let reader = second.beginEvaluation(identity: testIdentity("state-reader"), invalidator: nil)
    ViewNodeContext.withValue(reader) {
      withImperativeAuthoringContext(log.scope) { #expect(read() == 9) }
    }
  }

  @Test("async registration environments remain task-local across suspension")
  func asyncInvocation() async throws {
    let log = Log()
    resolve(log)
    let read = try #require(log.environment)
    let first = try scope(log, "first")
    let second = try scope(log, "second")
    let a = Task { @MainActor in
      await withImperativeAuthoringContext(first) {
        await Task.yield()
        return read()
      }
    }
    let b = Task { @MainActor in
      await withImperativeAuthoringContext(second) {
        await Task.yield()
        return read()
      }
    }
    #expect(await a.value == ["first"])
    #expect(await b.value == ["second"])
    #expect(read() == ["declaration"])
  }

  @MainActor
  private final class Provider {
    var values: FocusedValues?
    var first = 4
    var second = 4

    init() { values = .init() }

    func publish(_ title: String, second: Bool = false) {
      var next = FocusedValues()
      next.captureTitle = title
      next.captureNumber =
        second
        ? Binding(
          get: { [weak self] in self?.second ?? 0 }, set: { [weak self] in self?.second = $0 })
        : Binding(
          get: { [weak self] in self?.first ?? 0 }, set: { [weak self] in self?.first = $0 })
      values = next
    }
  }

  @Test("captured focused readers remain live and select the current publisher in their own graph")
  func liveFocusedServices() throws {
    let first = ViewGraph()
    let second = ViewGraph()
    let provider = Provider()
    provider.publish("first")
    LiveFocusedValuesRegistry.register(scope: first.stateGraphScopeID) { [weak provider] in
      provider?.values
    }
    let otherProvider = Provider()
    otherProvider.publish("foreign")
    LiveFocusedValuesRegistry.register(scope: second.stateGraphScopeID) { [weak otherProvider] in
      otherProvider?.values
    }
    let log = Log()
    resolve(log, graph: first)
    let title = try #require(log.title)
    let number = try #require(log.number)
    let write = try #require(log.write)
    resolve(log, graph: second, name: "foreign-snapshot")
    #expect(title() == "first")
    provider.publish("second", second: true)
    withImperativeAuthoringContext(log.scope) {
      #expect(title() == "second")
      #expect(number()?.wrappedValue == 4)
      write(19)
    }
    let reader = second.beginEvaluation(identity: testIdentity("foreign-reader"), invalidator: nil)
    ViewNodeContext.withValue(reader) {
      withImperativeAuthoringContext(log.scope) { #expect(title() == "second") }
    }
    #expect(provider.first == 4)
    #expect(provider.second == 19)
    #expect(otherProvider.first == 4)
    var press = FocusedValues()
    press.captureTitle = "press"
    LiveFocusedValuesRegistry.withFocusedValuesOverride(press) { #expect(title() == "press") }
    #expect(title() == "second")
    provider.values = nil
    withImperativeAuthoringContext(log.scope) { #expect(title() == "declaration") }
  }

  @MainActor
  private struct EnvironmentFields {
    @Environment(CaptureEnvironmentModel.self) var model: CaptureEnvironmentModel?
    @Environment(\.requestTermination) var action
    @Environment(\.isFocused) var focus
  }

  @Test("type-keyed models, actions and runtime focus keys follow the selected snapshot")
  func environmentForms() throws {
    let declared = CaptureEnvironmentModel()
    let registered = CaptureEnvironmentModel()
    var declaration = environment("declaration")
    declaration[CaptureEnvironmentModel.self] = declared
    declaration._isFocused = true
    declaration.requestTermination = RequestTerminationAction {
      declared.calls += 1
      return true
    }
    let prepared = EnvironmentValuesStorage.binding(declaration) {
      bindingForwardedDynamicPropertyCaptures(EnvironmentFields())
    }
    #expect(prepared.model === declared)
    #expect(prepared.focus)
    #expect(prepared.action())
    #expect(declared.calls == 1)

    var registration = environment("registration")
    registration[CaptureEnvironmentModel.self] = registered
    registration.requestTermination = RequestTerminationAction {
      registered.calls += 1
      return true
    }
    let snapshot = try #require(
      ImperativeAuthoringContextSnapshot(
        AuthoringContext(viewIdentity: testIdentity("operation"), focusedValues: .init()))
    )
    .withEnvironmentValues(registration)
    withImperativeAuthoringContext(snapshot) {
      #expect(prepared.model === registered)
      #expect(!prepared.focus)
      #expect(prepared.action())
    }
    #expect(declared.calls == 1)
    #expect(registered.calls == 1)
    #expect(prepared.model === declared)
  }
}
