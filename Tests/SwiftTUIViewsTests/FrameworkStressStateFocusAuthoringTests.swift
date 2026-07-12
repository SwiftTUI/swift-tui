import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI state and focus authoring stress behavior", .serialized)
struct FrameworkStressStateFocusAuthoringTests {
  @Test("stress state focus 001 namespace never uses the reserved default")
  func stateFocus001NamespaceNeverUsesReservedDefault() {
    let namespace = Namespace()
    #expect(namespace.wrappedValue != .default)
    #expect(namespace.wrappedValue.rawValue > 0)
  }

  @Test("stress state focus 002 namespace declarations allocate distinct ids")
  func stateFocus002NamespaceDeclarationsAllocateDistinctIDs() {
    let first = Namespace()
    let second = Namespace()
    #expect(first.wrappedValue != second.wrappedValue)
  }

  @Test("stress state focus 003 repeated namespace reads remain stable")
  func stateFocus003RepeatedNamespaceReadsRemainStable() {
    let namespace = Namespace()
    let first = namespace.wrappedValue
    for _ in 0..<32 { #expect(namespace.wrappedValue == first) }
  }

  @Test("stress state focus 004 shared namespace view mounts isolate storage")
  func stateFocus004SharedNamespaceViewMountsIsolateStorage() {
    let capture = StateFocusNamespaceCapture()
    let shared = StateFocusNamespaceView(capture: capture)
    _ = stateFocusResolve(
      VStack {
        shared.id("left")
        shared.id("right")
      },
      identity: testIdentity("StateFocus004")
    )
    #expect(capture.values.count == 2)
    withKnownIssue(
      "A shared Namespace-owning view value publishes one namespace across distinct mounts"
    ) {
      #expect(Set(capture.values).count == 2)
    }
  }

  @Test("stress state focus 005 separate graphs isolate namespace storage")
  func stateFocus005SeparateGraphsIsolateNamespaceStorage() {
    let firstCapture = StateFocusNamespaceCapture()
    let secondCapture = StateFocusNamespaceCapture()
    _ = stateFocusResolve(
      StateFocusNamespaceView(capture: firstCapture),
      identity: testIdentity("StateFocus005"),
      graph: ViewGraph()
    )
    _ = stateFocusResolve(
      StateFocusNamespaceView(capture: secondCapture),
      identity: testIdentity("StateFocus005"),
      graph: ViewGraph()
    )
    #expect(firstCapture.values.last != secondCapture.values.last)
  }

  @Test("stress state focus 006 boolean focus state seeds false and unrequested")
  func stateFocus006BooleanFocusStateSeedsFalseAndUnrequested() {
    let state = FocusState<Bool>()
    let binding = state.projectedValue
    #expect(binding.registrationValue == false)
    #expect(binding.hasPendingRequest == false)
    #expect(binding.requestGeneration == 0)
  }

  @Test("stress state focus 007 optional focus state seeds nil and unrequested")
  func stateFocus007OptionalFocusStateSeedsNilAndUnrequested() {
    let state = FocusState<String?>()
    let binding = state.projectedValue
    #expect(binding.registrationValue == nil)
    #expect(binding.hasPendingRequest == false)
    #expect(binding.requestGeneration == 0)
  }

  @Test("stress state focus 008 same value requests still advance generation")
  func stateFocus008SameValueRequestsStillAdvanceGeneration() {
    let state = FocusState<Bool>()
    let binding = state.projectedValue
    for generation in 1...20 {
      binding.wrappedValue = false
      #expect(binding.requestGeneration == UInt64(generation))
      #expect(binding.hasPendingRequest)
    }
  }

  @Test("stress state focus 009 stale runtime apply preserves newer authored request")
  func stateFocus009StaleRuntimeApplyPreservesNewerAuthoredRequest() {
    let state = FocusState<Bool>()
    let binding = state.projectedValue
    let staleGeneration = binding.requestGeneration
    binding.wrappedValue = true
    #expect(
      !binding.applyRuntimeValue(
        false,
        observedRequestGeneration: staleGeneration,
        registrationIdentity: nil
      )
    )
    #expect(binding.registrationValue)
    #expect(binding.hasPendingRequest)
  }

  @Test("stress state focus 010 matching equal runtime apply clears pending without change")
  func stateFocus010MatchingEqualRuntimeApplyClearsPendingWithoutChange() {
    let state = FocusState<Bool>()
    let binding = state.projectedValue
    binding.wrappedValue = true
    let generation = binding.requestGeneration
    #expect(
      !binding.applyRuntimeValue(
        true,
        observedRequestGeneration: generation,
        registrationIdentity: nil
      )
    )
    #expect(binding.registrationValue)
    #expect(!binding.hasPendingRequest)
  }

  @Test("stress state focus 011 matching changed runtime apply reports change")
  func stateFocus011MatchingChangedRuntimeApplyReportsChange() {
    let state = FocusState<Bool>()
    let binding = state.projectedValue
    #expect(
      binding.applyRuntimeValue(
        true,
        observedRequestGeneration: binding.requestGeneration,
        registrationIdentity: nil
      )
    )
    #expect(binding.registrationValue)
  }

  @Test("stress state focus 012 independent local focus states have distinct keys")
  func stateFocus012IndependentLocalFocusStatesHaveDistinctKeys() {
    let first = FocusState<Bool>()
    let second = FocusState<Bool>()
    #expect(first.projectedValue.bindingKey != second.projectedValue.bindingKey)
    #expect(first.projectedValue.bindingID != second.projectedValue.bindingID)
  }

  @Test("stress state focus 013 two graph focus declarations occupy distinct slots")
  func stateFocus013TwoGraphFocusDeclarationsOccupyDistinctSlots() {
    let capture = StateFocusBindingCapture()
    _ = stateFocusResolve(
      StateFocusTwoBindingsView(capture: capture),
      identity: testIdentity("StateFocus013"),
      graph: ViewGraph()
    )
    #expect(capture.boolBindings.count == 2)
    #expect(capture.boolBindings[0].bindingKey != capture.boolBindings[1].bindingKey)
  }

  @Test("stress state focus 014 projection primes without recording a read")
  func stateFocus014ProjectionPrimesWithoutRecordingRead() throws {
    let graph = ViewGraph()
    let identity = testIdentity("StateFocus014")
    _ = stateFocusResolve(StateFocusProjectionOnlyView(), identity: identity, graph: graph)
    let owner = try #require(graph.nodeForIdentity(identity))
    let key = StateSlotKey(
      owner: owner.viewNodeID,
      ordinal: StateSlotOrdinals.authored(line: 14, column: 14)
    )
    #expect(graph.stateDependentIdentities(for: key).isEmpty)
  }

  @Test("stress state focus 015 wrapped read records the evaluating reader")
  func stateFocus015WrappedReadRecordsEvaluatingReader() throws {
    let graph = ViewGraph()
    let identity = testIdentity("StateFocus015")
    _ = stateFocusResolve(StateFocusWrappedReadView(), identity: identity, graph: graph)
    let owner = try #require(graph.nodeForIdentity(identity))
    let key = StateSlotKey(
      owner: owner.viewNodeID,
      ordinal: StateSlotOrdinals.authored(line: 15, column: 15)
    )
    #expect(!graph.stateDependentIdentities(for: key).isEmpty)
  }

  @Test("stress state focus 016 bookkeeping reads add no value dependency")
  func stateFocus016BookkeepingReadsAddNoValueDependency() throws {
    let graph = ViewGraph()
    let identity = testIdentity("StateFocus016")
    _ = stateFocusResolve(StateFocusBookkeepingView(), identity: identity, graph: graph)
    let owner = try #require(graph.nodeForIdentity(identity))
    let key = StateSlotKey(
      owner: owner.viewNodeID,
      ordinal: StateSlotOrdinals.authored(line: 16, column: 16)
    )
    #expect(graph.stateDependentIdentities(for: key).isEmpty)
  }

  @Test("stress state focus 017 focused registration captures generation without value read")
  func stateFocus017FocusedRegistrationCapturesGenerationWithoutValueRead() throws {
    let graph = ViewGraph()
    let registry = LocalFocusBindingRegistry()
    let identity = testIdentity("StateFocus017")
    _ = stateFocusResolve(
      StateFocusRegisteredView(),
      identity: identity,
      graph: graph,
      focusRegistry: registry
    )
    #expect(registry.snapshot().count == 1)
    let owner = try #require(graph.nodeForIdentity(identity))
    let key = StateSlotKey(
      owner: owner.viewNodeID,
      ordinal: StateSlotOrdinals.authored(line: 17, column: 17)
    )
    #expect(graph.stateDependentIdentities(for: key).isEmpty)
  }

  @Test("stress state focus 018 boolean and optional bindings cannot collide")
  func stateFocus018BooleanAndOptionalBindingsCannotCollide() {
    let boolState = FocusState<Bool>(line: 18, column: 18)
    let optionalState = FocusState<String?>(line: 18, column: 18)
    #expect(boolState.projectedValue.bindingKey != optionalState.projectedValue.bindingKey)
  }

  @Test("stress state focus 019 optional unfocus clears only its matching selection")
  func stateFocus019OptionalUnfocusClearsOnlyMatchingSelection() {
    let state = FocusState<String?>()
    let binding = state.projectedValue
    binding.wrappedValue = "B"
    let registry = LocalFocusBindingRegistry()
    let context = stateFocusContext(
      identity: testIdentity("StateFocus019"),
      focusRegistry: registry
    )
    _ = Resolver().resolve(Text("A").focused(binding, equals: "A"), in: context)
    #expect(!registry.sync(actualFocusedIdentity: nil))
    #expect(binding.registrationValue == "B")
  }

  @Test("stress state focus 020 false default focus is inert")
  func stateFocus020FalseDefaultFocusIsInert() {
    let state = FocusState<Bool>()
    let binding = state.projectedValue
    _ = Resolver().resolve(
      Text("target").defaultFocus(binding, false),
      in: .init(identity: testIdentity("StateFocus020"))
    )
    #expect(!binding.registrationValue)
    #expect(!binding.hasPendingRequest)
  }

  @Test("stress state focus 021 default focus respects existing authored value")
  func stateFocus021DefaultFocusRespectsExistingAuthoredValue() {
    let state = FocusState<String?>()
    let binding = state.projectedValue
    binding.wrappedValue = "authored"
    _ = Resolver().resolve(
      Text("target").defaultFocus(binding, "default"),
      in: .init(identity: testIdentity("StateFocus021"))
    )
    #expect(binding.registrationValue == "authored")
  }

  @Test("stress state focus 022 focused arrival records before mutating default")
  func stateFocus022FocusedArrivalRecordsBeforeMutatingDefault() {
    let state = FocusState<Bool>()
    let binding = state.projectedValue
    let registry = LocalFocusBindingRegistry()
    var environment = EnvironmentValues()
    environment.focusedIdentity = testIdentity("OtherFocus")
    var context = stateFocusContext(
      identity: testIdentity("StateFocus022"),
      environmentValues: environment,
      focusRegistry: registry
    )
    context.liveFocusBindingRegistry = registry
    _ = Resolver().resolve(Text("target").defaultFocus(binding), in: context)
    #expect(!binding.registrationValue)
    #expect(!registry.consumeArrivalDefaults())
  }

  @Test("stress state focus 023 default focus positions keep independent seeds")
  func stateFocus023DefaultFocusPositionsKeepIndependentSeeds() {
    let first = FocusState<Bool>()
    let second = FocusState<Bool>()
    _ = Resolver().resolve(
      Text("target")
        .defaultFocus(first.projectedValue)
        .defaultFocus(second.projectedValue),
      in: .init(identity: testIdentity("StateFocus023"))
    )
    #expect(first.projectedValue.registrationValue)
    #expect(second.projectedValue.registrationValue)
  }

  @Test("stress state focus 024 nil focused value registers nothing")
  func stateFocus024NilFocusedValueRegistersNothing() {
    let registry = LocalFocusedValuesRegistry()
    var context = ResolveContext(identity: testIdentity("StateFocus024"))
    context.localFocusedValuesRegistry = registry
    _ = Resolver().resolve(
      VStack { Text("child").id("child") }
        .focusedValue(\.stateFocusTitle, Optional<String>.none),
      in: context
    )
    #expect(registry.snapshot().isEmpty)

    _ = Resolver().resolve(
      VStack { Text("child").id("child") }
        .focusedValue(\.stateFocusTitle, "live"),
      in: context
    )
    let registration = registry.snapshot().first
    #expect(registration?.descendantIdentities.count ?? 0 >= 2)
  }

  @Test("stress state focus 025 focused binding equality uses current value")
  func stateFocus025FocusedBindingEqualityUsesCurrentValue() {
    var firstValue = 7
    var secondValue = 7
    let first = Binding(get: { firstValue }, set: { firstValue = $0 })
    let second = Binding(get: { secondValue }, set: { secondValue = $0 })
    #expect(first.isFocusedValueEqual(to: second))
    secondValue = 8
    #expect(!first.isFocusedValueEqual(to: second))
  }
}

private enum StateFocusTitleKey: FocusedValueKey {
  typealias Value = String
}

extension FocusedValues {
  fileprivate var stateFocusTitle: String? {
    get { self[StateFocusTitleKey.self] }
    set { self[StateFocusTitleKey.self] = newValue }
  }
}

@MainActor private final class StateFocusNamespaceCapture { var values: [Namespace.ID] = [] }
@MainActor private final class StateFocusBindingCapture {
  var boolBindings: [FocusState<Bool>.Binding] = []
}

@MainActor private struct StateFocusNamespaceView: View {
  @Namespace private var namespace
  let capture: StateFocusNamespaceCapture
  var body: some View {
    capture.values.append(namespace)
    return Text("namespace")
  }
}

@MainActor private struct StateFocusTwoBindingsView: View {
  @FocusState(line: 13, column: 1) private var first: Bool
  @FocusState(line: 13, column: 2) private var second: Bool
  let capture: StateFocusBindingCapture
  var body: some View {
    capture.boolBindings = [$first, $second]
    return Text("bindings")
  }
}

@MainActor private struct StateFocusProjectionOnlyView: View {
  @FocusState(line: 14, column: 14) private var focus: Bool
  var body: some View {
    _ = $focus
    return Text("projection")
  }
}

@MainActor private struct StateFocusWrappedReadView: View {
  @FocusState(line: 15, column: 15) private var focus: Bool
  var body: some View { Text("focus \(focus)") }
}

@MainActor private struct StateFocusBookkeepingView: View {
  @FocusState(line: 16, column: 16) private var focus: Bool
  var body: some View {
    _ = $focus.requestGeneration
    _ = $focus.registrationValue
    return Text("bookkeeping")
  }
}

@MainActor private struct StateFocusRegisteredView: View {
  @FocusState(line: 17, column: 17) private var focus: Bool
  var body: some View { Text("registered").focused($focus) }
}

@MainActor
private func stateFocusResolve<V: View>(
  _ view: V,
  identity: Identity,
  graph: ViewGraph? = nil,
  focusRegistry: LocalFocusBindingRegistry? = nil
) -> ResolvedNode {
  let graph = graph ?? ViewGraph()
  graph.beginFrame()
  var context = stateFocusContext(identity: identity, graph: graph, focusRegistry: focusRegistry)
  context.viewGraph = graph
  return Resolver().resolve(view, in: context)
}

@MainActor
private func stateFocusContext(
  identity: Identity,
  environmentValues: EnvironmentValues = .init(),
  graph: ViewGraph? = nil,
  focusRegistry: LocalFocusBindingRegistry? = nil
) -> ResolveContext {
  var context = ResolveContext(
    identity: identity,
    environmentValues: environmentValues,
    applyEnvironmentValues: true
  )
  context.viewGraph = graph
  context.localFocusBindingRegistry = focusRegistry
  return context
}
