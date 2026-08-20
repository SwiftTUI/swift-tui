import Observation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

// DynamicProperty contract pins: update(in:) runs once per discovered property
// before the enclosing reuse decision and body evaluation, under the ambient
// authoring context the body observes. Composed built-ins keep their dependency
// wiring, while an uncertified direct or descendant property denies reuse.
//
// Frozen against real SwiftUI (scratch probe, 2026-08-04): SwiftUI calls
// update(in:) once per property per body evaluation including the first, nested
// properties update before their container, and two instances of one
// composed wrapper hold distinct @State storage. SwiftTUI's narrowed public
// contract makes update nonmutating and custom evaluation-visible storage
// reference-backed, so extracted value copies cannot discard promised writes.
@MainActor
private final class PassEventLog {
  private(set) var events: [String] = []

  func append(_ event: String) {
    events.append(event)
  }
}

@propertyWrapper
@MainActor
private struct UpdateRecorder: DynamicProperty {
  private let log: PassEventLog
  private let tag: String
  private let result: DynamicPropertyUpdateResult

  init(
    log: PassEventLog,
    tag: String,
    result: DynamicPropertyUpdateResult = .unchanged
  ) {
    self.log = log
    self.tag = tag
    self.result = result
  }

  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    log.append("update:\(tag)")
    return result
  }

  var wrappedValue: String {
    tag
  }
}

/// A wrapper composing another dynamic property, to pin nested-first update
/// ordering (the container's update(in:) must observe updated composed state).
@propertyWrapper
@MainActor
private struct NestingRecorder: DynamicProperty {
  private let log: PassEventLog
  private var inner: UpdateRecorder

  init(log: PassEventLog) {
    self.log = log
    inner = UpdateRecorder(log: log, tag: "inner")
  }

  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    log.append("update:outer")
    return .unchanged
  }

  var wrappedValue: String {
    inner.wrappedValue
  }
}

/// A wrapper composing `@State`, for the reuse-invalidation pin: a composed
/// state write must deny reuse for the reading subtree exactly like a
/// directly-declared `@State` write.
@propertyWrapper
@MainActor
private struct ComposedTick: DynamicProperty {
  private let state: State<Int>
  private let log: PassEventLog

  init(log: PassEventLog) {
    self.log = log
    state = State(wrappedValue: 0, line: 90, column: 9)
  }

  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    log.append("update:composed-tick")
    return .unchanged
  }

  var wrappedValue: Int {
    state.wrappedValue
  }

  func write(_ value: Int) {
    state.wrappedValue = value
  }
}

private enum PassProbeEnvironmentKey: EnvironmentKey {
  static let defaultValue = "default"
}

extension EnvironmentValues {
  fileprivate var passProbeValue: String {
    get { self[PassProbeEnvironmentKey.self] }
    set { self[PassProbeEnvironmentKey.self] = newValue }
  }
}

/// A wrapper composing `@Environment`, pinning that composed environment
/// reads resolve against the injected ambient values and stay
/// reader-attributed.
@propertyWrapper
@MainActor
private struct EnvironmentProbeReader: DynamicProperty {
  @Environment(\.passProbeValue) private var value
  private let updateLog: PassEventLog?

  init(updateLog: PassEventLog? = nil) {
    self.updateLog = updateLog
  }

  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    updateLog?.append("update:environment:\(value)")
    return .unchanged
  }

  var wrappedValue: String {
    value
  }
}

@MainActor
private final class AuthoredValueLog {
  var values: [Int] = []
}

@MainActor
private final class AuthoredReplacementModel: Observable {
  let value: Int

  init(_ value: Int) {
    self.value = value
  }
}

@MainActor
private struct BindingReplacementChild: View {
  @Binding private var value: Int
  let log: AuthoredValueLog

  init(value: Int, log: AuthoredValueLog) {
    _value = .constant(value)
    self.log = log
  }

  var body: some View {
    log.values.append(value)
    return Text("binding \(value)")
  }
}

@MainActor
private struct BindingReplacementRoot: View {
  let value: Int
  let log: AuthoredValueLog

  var body: some View {
    VStack {
      BindingReplacementChild(value: value, log: log)
    }
  }
}

@MainActor
private struct BindableReplacementChild: View {
  @Bindable private var model: AuthoredReplacementModel
  let log: AuthoredValueLog

  init(model: AuthoredReplacementModel, log: AuthoredValueLog) {
    _model = Bindable(model)
    self.log = log
  }

  var body: some View {
    log.values.append(model.value)
    return Text("bindable \(model.value)")
  }
}

@MainActor
private struct BindableReplacementRoot: View {
  let model: AuthoredReplacementModel
  let log: AuthoredValueLog

  var body: some View {
    VStack {
      BindableReplacementChild(model: model, log: log)
    }
  }
}

@MainActor
private final class ScopeOwnerCapture {
  var updateOwner: ViewNodeID?
  var bodyOwner: ViewNodeID?
}

@propertyWrapper
@MainActor
private struct ScopeOwnerRecorder: DynamicProperty {
  let capture: ScopeOwnerCapture

  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    capture.updateOwner = currentAuthoringContext()?.ownerNodeID
    return .unchanged
  }

  var wrappedValue: Int { 0 }
}

@MainActor
private struct ScopeOwnerHost: View {
  @ScopeOwnerRecorder private var value: Int
  let capture: ScopeOwnerCapture

  init(capture: ScopeOwnerCapture) {
    self.capture = capture
    _value = ScopeOwnerRecorder(capture: capture)
  }

  var body: some View {
    capture.bodyOwner = currentAuthoringContext()?.ownerNodeID
    return Text("owner \(value)")
  }
}

@MainActor
private struct ScopeOwnerPrimitive: PrimitiveView, ResolvableView {
  @ScopeOwnerRecorder private var value: Int
  let capture: ScopeOwnerCapture

  init(capture: ScopeOwnerCapture) {
    self.capture = capture
    _value = ScopeOwnerRecorder(capture: capture)
  }

  var body: Never {
    fatalError("ScopeOwnerPrimitive is resolved directly.")
  }

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    withDynamicPropertyUpdateScope(self, for: context) {
      capture.bodyOwner = currentAuthoringContext()?.ownerNodeID
      return [
        ResolvedNode(
          identity: context.identity,
          kind: .view("ScopeOwnerPrimitive"),
          environmentSnapshot: context.environment,
          transactionSnapshot: context.transaction
        )
      ]
    }
  }
}

@MainActor
private struct DynamicPropertyOutput: View, DynamicProperty {
  @UpdateRecorder private var nested: String
  let log: PassEventLog

  init(log: PassEventLog) {
    self.log = log
    _nested = UpdateRecorder(log: log, tag: "output-nested")
  }

  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    log.append("update:output")
    return .unchanged
  }

  var body: some View {
    log.append("outputBody")
    return Text(nested)
  }
}

@MainActor
private struct DynamicPropertyModifier: ViewModifier, DynamicProperty {
  @UpdateRecorder private var nested: String
  let log: PassEventLog

  init(log: PassEventLog) {
    self.log = log
    _nested = UpdateRecorder(log: log, tag: "modifier-nested")
  }

  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    log.append("update:modifier")
    return .unchanged
  }

  func body(content: Content) -> some View {
    log.append("modifierBody")
    return content
  }
}

@MainActor
private struct ComposedPassthroughModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
  }
}

@MainActor
private final class ComposedBodyCount {
  var value = 0
}

@MainActor
private struct PlainComposedMemoModifier: ViewModifier {
  let count: ComposedBodyCount

  func body(content: Content) -> some View {
    count.value += 1
    return content
  }
}

extension PlainComposedMemoModifier: @MainActor Equatable {
  static func == (lhs: PlainComposedMemoModifier, rhs: PlainComposedMemoModifier) -> Bool {
    lhs.count === rhs.count
  }
}

@MainActor
private struct OwnerCapturingDynamicPropertyOutput: View, DynamicProperty {
  let capture: ScopeOwnerCapture

  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    capture.updateOwner = currentAuthoringContext()?.ownerNodeID
    return .unchanged
  }

  var body: some View {
    capture.bodyOwner = currentAuthoringContext()?.ownerNodeID
    return Text("owner-output")
  }
}

@MainActor
private final class StatefulDynamicPropertyLog {
  var updateValues: [Int] = []
  var bodyValues: [Int] = []
}

@MainActor
private struct StatefulDynamicPropertyOutput: View, DynamicProperty {
  @State private var count = 0
  let log: StatefulDynamicPropertyLog

  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    count += 1
    log.updateValues.append(count)
    return .changed
  }

  var body: some View {
    log.bodyValues.append(count)
    return Text("output-count \(count)")
  }
}

@MainActor
private struct StatefulDynamicPropertyModifier: ViewModifier, DynamicProperty {
  @State private var count = 0
  let log: StatefulDynamicPropertyLog

  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    count += 1
    log.updateValues.append(count)
    return .changed
  }

  func body(content: Content) -> some View {
    log.bodyValues.append(count)
    return content
  }
}

@MainActor
struct DynamicPropertyUpdatePassTests {
  private struct PlainBodyHost: View {
    @UpdateRecorder private var recorder: String
    private let log: PassEventLog

    init(
      log: PassEventLog,
      result: DynamicPropertyUpdateResult = .unchanged
    ) {
      self.log = log
      _recorder = UpdateRecorder(log: log, tag: "plain", result: result)
    }

    var body: some View {
      log.append("body")
      return Text(recorder)
    }
  }

  private struct NestedHost: View {
    @NestingRecorder private var recorder: String
    private let log: PassEventLog

    init(log: PassEventLog) {
      self.log = log
      _recorder = NestingRecorder(log: log)
    }

    var body: some View {
      log.append("body")
      return Text(recorder)
    }
  }

  private struct RecorderModifier: ViewModifier {
    @UpdateRecorder private var recorder: String
    private let log: PassEventLog

    init(log: PassEventLog) {
      self.log = log
      _recorder = UpdateRecorder(log: log, tag: "modifier")
    }

    func body(content: Content) -> some View {
      log.append("modifierBody")
      return content
    }
  }

  private func makeContext(
    _ graph: ViewGraph,
    identity: Identity,
    environmentValues: EnvironmentValues = .init(),
    invalidatedIdentities: Set<Identity> = []
  ) -> ResolveContext {
    var context = ResolveContext(
      identity: identity,
      environmentValues: environmentValues,
      invalidatedIdentities: invalidatedIdentities,
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    return context
  }

  @Test("update(in:) runs once before a plain body evaluation")
  func updateRunsBeforePlainBody() {
    let log = PassEventLog()
    let graph = ViewGraph()
    graph.beginFrame()
    _ = Resolver().resolve(
      PlainBodyHost(log: log),
      in: makeContext(graph, identity: testIdentity("PlainBody"))
    )
    #expect(log.events == ["update:plain", "body"])
  }

  @Test("nested dynamic properties update before their container")
  func nestedPropertiesUpdateBeforeContainer() {
    let log = PassEventLog()
    let graph = ViewGraph()
    graph.beginFrame()
    _ = Resolver().resolve(
      NestedHost(log: log),
      in: makeContext(graph, identity: testIdentity("NestedOrdering"))
    )
    #expect(log.events == ["update:inner", "update:outer", "body"])
  }

  // `DynamicPropertyUpdatePassProbe` is `#if DEBUG` in SwiftTUIViews, so this
  // case cannot compile in release configuration. Guarding it keeps the
  // release-soundness lane (`swift test -c release`) building; without it the
  // whole SwiftTUIViewsTests module fails to compile and every release-config
  // test is lost, not just this one.
  #if DEBUG
    @Test("the pass covers ResolvableView primitives' dynamic-property scopes")
    func updatePassCoversPrimitiveDynamicScopes() {
      var updated: [String] = []
      DynamicPropertyUpdatePassProbe.onUpdate = { container, property in
        updated.append("\(container):\(property)")
      }
      defer { DynamicPropertyUpdatePassProbe.onUpdate = nil }

      let graph = ViewGraph()
      graph.beginFrame()
      _ = Resolver().resolve(
        TextEditor(text: .constant("hello")),
        in: makeContext(graph, identity: testIdentity("PrimitiveScope"))
      )
      // TextEditor stores a `Binding<String>` plus three `@State` — the pass
      // must reach the primitive's stored wrappers through its own
      // dynamic-property authoring scope.
      #expect(
        updated.contains { $0.hasPrefix("TextEditor:") },
        "no update(in:) ran for TextEditor's stored dynamic properties; saw \(updated)"
      )
    }
  #endif

  @Test("update(in:) runs before a ViewModifier's composed body")
  func updateRunsBeforeViewModifierBody() {
    let log = PassEventLog()
    let graph = ViewGraph()
    graph.beginFrame()
    _ = Resolver().resolve(
      Text("base").modifier(RecorderModifier(log: log)),
      in: makeContext(graph, identity: testIdentity("ModifierSurface"))
    )
    #expect(log.events == ["update:modifier", "modifierBody"])
  }

  @Test("an enclosing reuse skips its certified descendant pass; invalidation re-runs it")
  func reuseSkipsUpdatePassAndInvalidationRerunsIt() throws {
    let log = PassEventLog()
    let graph = ViewGraph()
    let rootIdentity = testIdentity("ReuseSkip")

    let view = VStack {
      PlainBodyHost(log: log)
      Text("static sibling")
    }

    graph.beginFrame()
    _ = Resolver().resolve(view, in: makeContext(graph, identity: rootIdentity))
    let firstFrame = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(resolved: firstFrame, placed: nil)
    #expect(log.events == ["update:plain", "body"])

    // Collect the two Text leaves from the committed tree (document order):
    // the recorder host collapses onto the first, the static sibling is the
    // second.
    var leafIdentities: [Identity] = []
    var work: [ResolvedNode] = [firstFrame]
    while let current = work.popLast() {
      if current.kind == .view("Text") {
        leafIdentities.append(current.identity)
      }
      work.append(contentsOf: current.children.reversed())
    }
    #expect(leafIdentities.count == 2)
    let hostIdentity = try #require(leafIdentities.first)
    let siblingIdentity = try #require(leafIdentities.last)

    // Frame 2: invalidation names only the static sibling. Under retained
    // reuse the recorder host serves its committed body, but its current
    // direct update still runs before that host's reuse door. The sibling-only
    // invalidation must therefore add one update without another body event.
    graph.beginFrame()
    _ = Resolver().resolve(
      view,
      in: makeContext(graph, identity: rootIdentity, invalidatedIdentities: [siblingIdentity])
    )
    _ = graph.finalizeFrame(rootIdentity: rootIdentity)

    let retainedReuseActive = !stackLeanResolveProfile || leanRetainedReuse
    if retainedReuseActive {
      #expect(
        log.events == ["update:plain", "body", "update:plain"],
        "a reused body must still receive its direct pre-door update; saw \(log.events)"
      )
    } else {
      #expect(log.events == ["update:plain", "body", "update:plain", "body"])
    }

    // Frame 3: invalidating the host re-runs update(in:) before its body.
    graph.beginFrame()
    _ = Resolver().resolve(
      view,
      in: makeContext(graph, identity: rootIdentity, invalidatedIdentities: [hostIdentity])
    )
    _ = graph.finalizeFrame(rootIdentity: rootIdentity)
    #expect(log.events.suffix(2) == ["update:plain", "body"])
  }

  @Test("an uncertified wrapper denies enclosing retained reuse")
  func uncertifiedWrapperDeniesEnclosingReuse() {
    let log = PassEventLog()
    let graph = ViewGraph()
    let rootIdentity = testIdentity("UncertifiedReuse")
    let siblingIdentity = testIdentity("UncertifiedReuse", "unrelated")
    let view = VStack {
      PlainBodyHost(log: log, result: .uncertified)
      Text("static sibling")
    }

    graph.beginFrame()
    _ = Resolver().resolve(view, in: makeContext(graph, identity: rootIdentity))
    _ = graph.finalizeFrame(rootIdentity: rootIdentity)

    graph.beginFrame()
    _ = Resolver().resolve(
      view,
      in: makeContext(
        graph,
        identity: rootIdentity,
        invalidatedIdentities: [siblingIdentity]
      )
    )
    _ = graph.finalizeFrame(rootIdentity: rootIdentity)

    #expect(log.events == ["update:plain", "body", "update:plain", "body"])
  }

  private struct ComposedTickHost: View {
    @ComposedTick private var tick: Int
    private let log: PassEventLog
    private let capture: ComposedTickCapture

    init(log: PassEventLog, capture: ComposedTickCapture) {
      self.log = log
      self.capture = capture
      _tick = ComposedTick(log: log)
    }

    var body: some View {
      log.append("body:\(tick)")
      capture.write = { [_tick] value in _tick.write(value) }
      capture.snapshot = currentImperativeAuthoringContextSnapshot()
      return Text("tick \(tick)")
    }
  }

  @MainActor
  private final class ComposedTickCapture {
    var write: ((Int) -> Void)?
    var snapshot: ImperativeAuthoringContextSnapshot?
  }

  private final class RecordingInvalidator: Invalidating {
    private(set) var requests: [Set<Identity>] = []

    func requestInvalidation(of identities: Set<Identity>) {
      requests.append(identities)
    }
  }

  @Test("a composed @State write invalidates the reader and re-runs its update")
  func composedStateWriteInvalidatesReader() throws {
    let log = PassEventLog()
    let capture = ComposedTickCapture()
    let graph = ViewGraph()
    let rootIdentity = testIdentity("ComposedInvalidation")
    let view = ComposedTickHost(log: log, capture: capture)

    graph.beginFrame()
    _ = Resolver().resolve(view, in: makeContext(graph, identity: rootIdentity))
    let firstFrame = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(resolved: firstFrame, placed: nil)
    #expect(log.events == ["update:composed-tick", "body:0"])

    let ownerNode = try #require(graph.nodeForIdentity(rootIdentity))
    let spy = RecordingInvalidator()
    ownerNode.invalidator = spy

    let snapshot = try #require(capture.snapshot)
    withImperativeAuthoringContext(snapshot) {
      capture.write?(3)
    }

    let invalidated = spy.requests.reduce(into: Set<Identity>()) { $0.formUnion($1) }
    #expect(!invalidated.isEmpty, "the composed state write scheduled no invalidation")

    graph.beginFrame()
    _ = Resolver().resolve(
      view,
      in: makeContext(graph, identity: rootIdentity, invalidatedIdentities: invalidated)
    )
    _ = graph.finalizeFrame(rootIdentity: rootIdentity)
    #expect(log.events.suffix(2) == ["update:composed-tick", "body:3"])
  }

  private struct EnvironmentReaderHost: View {
    @EnvironmentProbeReader private var probe: String
    private let capture: EnvironmentCapture

    init(capture: EnvironmentCapture, updateLog: PassEventLog? = nil) {
      self.capture = capture
      _probe = EnvironmentProbeReader(updateLog: updateLog)
    }

    var body: some View {
      capture.seen = probe
      return Text(probe)
    }
  }

  @MainActor
  private final class EnvironmentCapture {
    var seen: String?
  }

  @Test("@Environment inside a custom wrapper resolves and is reader-attributed")
  func environmentInsideCustomWrapperResolves() throws {
    let capture = EnvironmentCapture()
    let graph = ViewGraph()
    let identity = testIdentity("WrappedEnvironment")
    var environment = EnvironmentValues()
    environment.passProbeValue = "injected"

    graph.beginFrame()
    _ = Resolver().resolve(
      EnvironmentReaderHost(capture: capture),
      in: makeContext(graph, identity: identity, environmentValues: environment)
    )

    #expect(capture.seen == "injected")
    let dependencies = try #require(graph.dependencies(for: identity))
    #expect(
      dependencies.environmentReads.contains(ObjectIdentifier(PassProbeEnvironmentKey.self)),
      "the composed environment read was not attributed to the reading node"
    )
  }

  @Test("a transparent environment modifier updates its base once in the transformed scope")
  func transparentModifierUpdatesBaseInTransformedEnvironment() {
    let capture = EnvironmentCapture()
    let log = PassEventLog()
    let graph = ViewGraph()
    let identity = testIdentity("WrappedEnvironment", "transparent-modifier")

    graph.beginFrame()
    _ = Resolver().resolve(
      EnvironmentReaderHost(capture: capture, updateLog: log)
        .environment(\.passProbeValue, "modifier"),
      in: makeContext(graph, identity: identity)
    )

    #expect(log.events == ["update:environment:modifier"])
    #expect(capture.seen == "modifier")
  }

  @Test("parent replacement of Binding storage cannot memo-serve the old child body")
  func bindingReplacementStaysCurrentAcrossParentInvalidation() {
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyMemo", "BindingReplacement")
    let log = AuthoredValueLog()

    graph.beginFrame()
    _ = Resolver().resolve(
      BindingReplacementRoot(value: 1, log: log),
      in: makeContext(graph, identity: identity)
    )
    _ = graph.finalizeFrame(rootIdentity: identity)

    graph.beginFrame()
    _ = Resolver().resolve(
      BindingReplacementRoot(value: 2, log: log),
      in: makeContext(graph, identity: identity, invalidatedIdentities: [identity])
    )
    _ = graph.finalizeFrame(rootIdentity: identity)

    #expect(log.values == [1, 2])
  }

  @Test("parent replacement of Bindable storage cannot memo-serve the old child body")
  func bindableReplacementStaysCurrentAcrossParentInvalidation() {
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyMemo", "BindableReplacement")
    let log = AuthoredValueLog()

    graph.beginFrame()
    _ = Resolver().resolve(
      BindableReplacementRoot(model: AuthoredReplacementModel(1), log: log),
      in: makeContext(graph, identity: identity)
    )
    _ = graph.finalizeFrame(rootIdentity: identity)

    graph.beginFrame()
    _ = Resolver().resolve(
      BindableReplacementRoot(model: AuthoredReplacementModel(2), log: log),
      in: makeContext(graph, identity: identity, invalidatedIdentities: [identity])
    )
    _ = graph.finalizeFrame(rootIdentity: identity)

    #expect(log.values == [1, 2])
  }

  @Test("captured authoring scope governs both DynamicProperty update and body")
  func capturedAuthoringScopeWinsOverAmbientUpdateScope() {
    let graph = ViewGraph()
    let authoredIdentity = testIdentity("DynamicPropertyScope", "authored")
    let ambientIdentity = testIdentity("DynamicPropertyScope", "ambient")
    let hostIdentity = testIdentity("DynamicPropertyScope", "host")
    graph.beginFrame()

    let authoredNode = graph.prepareDynamicPropertyUpdate(identity: authoredIdentity)
    let ambientNode = graph.prepareDynamicPropertyUpdate(identity: ambientIdentity)
    let authoredScope = AuthoringContext(
      viewIdentity: authoredIdentity,
      focusedValues: .init(),
      viewNode: authoredNode
    )
    let ambientScope = AuthoringContext(
      viewIdentity: ambientIdentity,
      focusedValues: .init(),
      viewNode: ambientNode
    )
    let capture = ScopeOwnerCapture()
    let erased = scopedAnyView(authoringContext: authoredScope) {
      ScopeOwnerHost(capture: capture)
    }

    withAuthoringContext(ambientScope) {
      _ = Resolver().resolve(erased, in: makeContext(graph, identity: hostIdentity))
    }

    #expect(capture.updateOwner == authoredNode.viewNodeID)
    #expect(capture.bodyOwner == authoredNode.viewNodeID)
  }

  @Test("a primitive ignores a foreign ambient owner for both update and resolve")
  func primitiveUpdateAndResolveUseTheDestinationOwner() throws {
    let graph = ViewGraph()
    let foreignIdentity = testIdentity("DynamicPropertyScope", "foreign-primitive")
    let hostIdentity = testIdentity("DynamicPropertyScope", "primitive-host")
    graph.beginFrame()
    let foreignNode = graph.prepareDynamicPropertyUpdate(identity: foreignIdentity)
    let foreignScope = AuthoringContext(
      viewIdentity: foreignIdentity,
      focusedValues: .init(),
      viewNode: foreignNode
    )
    let capture = ScopeOwnerCapture()

    withAuthoringContext(foreignScope) {
      _ = Resolver().resolve(
        ScopeOwnerPrimitive(capture: capture),
        in: makeContext(graph, identity: hostIdentity)
      )
    }

    let hostNode = try #require(graph.nodeForIdentity(hostIdentity))
    #expect(capture.updateOwner == hostNode.viewNodeID)
    #expect(capture.bodyOwner == hostNode.viewNodeID)
    #expect(capture.updateOwner != foreignNode.viewNodeID)
  }

  @Test("an explicitly nil ScopedBuilder uses the destination owner for update and body")
  func explicitlyNilScopedBuilderDoesNotInheritForeignAmbientOwner() throws {
    let graph = ViewGraph()
    let foreignIdentity = testIdentity("DynamicPropertyScope", "foreign-builder")
    let hostIdentity = testIdentity("DynamicPropertyScope", "builder-host")
    graph.beginFrame()
    let foreignNode = graph.prepareDynamicPropertyUpdate(identity: foreignIdentity)
    let foreignScope = AuthoringContext(
      viewIdentity: foreignIdentity,
      focusedValues: .init(),
      viewNode: foreignNode
    )
    let capture = ScopeOwnerCapture()
    let builder = ScopedBuilder(
      scoped: ScopeOwnerHost(capture: capture),
      authoringContext: nil
    )

    withAuthoringContext(foreignScope) {
      _ = Resolver().resolve(builder, in: makeContext(graph, identity: hostIdentity))
    }

    let hostNode = try #require(graph.nodeForIdentity(hostIdentity))
    #expect(capture.updateOwner == hostNode.viewNodeID)
    #expect(capture.bodyOwner == hostNode.viewNodeID)
    #expect(capture.updateOwner != foreignNode.viewNodeID)
  }

  @Test("a forwarded DynamicProperty output owns one nested traversal")
  func scopedBuilderDynamicPropertyOutputUpdatesNestedStorageOnce() {
    let graph = ViewGraph()
    let log = PassEventLog()
    let identity = testIdentity("DynamicPropertyTraversal", "builder-output")
    let builder = ScopedBuilder(
      scoped: DynamicPropertyOutput(log: log),
      authoringContext: nil
    )

    graph.beginFrame()
    _ = Resolver().resolve(builder, in: makeContext(graph, identity: identity))

    #expect(log.events == ["update:output-nested", "update:output", "outputBody"])
  }

  @Test("a forwarded DynamicProperty modifier owns one nested traversal")
  func modifiedContentDynamicPropertyModifierUpdatesNestedStorageOnce() {
    let graph = ViewGraph()
    let log = PassEventLog()
    let identity = testIdentity("DynamicPropertyTraversal", "modifier")

    graph.beginFrame()
    _ = Resolver().resolve(
      Text("base").modifier(DynamicPropertyModifier(log: log)),
      in: makeContext(graph, identity: identity)
    )

    #expect(log.events == ["update:modifier-nested", "update:modifier", "modifierBody"])
  }

  @Test("a transparent modifier updates View-and-DynamicProperty content at its root exactly once")
  func transparentModifierDynamicPropertyContentUpdatesExactlyOnce() {
    let graph = ViewGraph()
    let log = PassEventLog()
    let identity = testIdentity("DynamicPropertyTraversal", "modifier-output")

    graph.beginFrame()
    _ = Resolver().resolve(
      DynamicPropertyOutput(log: log).disabled(true),
      in: makeContext(graph, identity: identity)
    )

    #expect(log.events == ["update:output-nested", "update:output", "outputBody"])
  }

  @Test("a composed modifier carrier owns View-and-DynamicProperty content exactly once")
  func composedModifierDynamicPropertyContentUpdatesExactlyOnce() {
    let graph = ViewGraph()
    let log = PassEventLog()
    let identity = testIdentity("DynamicPropertyTraversal", "composed-modifier-output")

    graph.beginFrame()
    _ = Resolver().resolve(
      DynamicPropertyOutput(log: log).modifier(ComposedPassthroughModifier()),
      in: makeContext(graph, identity: identity)
    )

    #expect(log.events == ["update:output-nested", "update:output", "outputBody"])
  }

  @Test("a structural modifier updates a View-and-DynamicProperty base exactly once")
  func structuralModifierDynamicPropertyContentUpdatesExactlyOnce() {
    let graph = ViewGraph()
    let log = PassEventLog()
    let identity = testIdentity("DynamicPropertyTraversal", "structural-modifier-output")

    graph.beginFrame()
    _ = Resolver().resolve(
      DynamicPropertyOutput(log: log).overlay {
        Text("overlay")
      },
      in: makeContext(graph, identity: identity)
    )

    #expect(log.events == ["update:output-nested", "update:output", "outputBody"])
  }

  @Test("an identity modifier updates a View-and-DynamicProperty base exactly once")
  func identityModifierDynamicPropertyContentUpdatesExactlyOnce() {
    let graph = ViewGraph()
    let log = PassEventLog()
    let identity = testIdentity("DynamicPropertyTraversal", "identity-modifier-output")

    graph.beginFrame()
    _ = Resolver().resolve(
      DynamicPropertyOutput(log: log).id("payload"),
      in: makeContext(graph, identity: identity)
    )

    #expect(log.events == ["update:output-nested", "update:output", "outputBody"])
  }

  @Test("plain composed modifier content does not disable enclosing reuse")
  func plainComposedModifierContentKeepsReuseEligible() throws {
    let graph = ViewGraph()
    let count = ComposedBodyCount()
    let identity = testIdentity("DynamicPropertyTraversal", "plain-composed-reuse")
    let view = VStack {
      Text("base").modifier(PlainComposedMemoModifier(count: count))
      Text("static sibling")
    }

    graph.beginFrame()
    _ = Resolver().resolve(view, in: makeContext(graph, identity: identity))
    let firstFrame = graph.snapshot(rootIdentity: identity)
    _ = graph.finalizeFrame(rootIdentity: identity)
    var leafIdentities: [Identity] = []
    var work = [firstFrame]
    while let current = work.popLast() {
      if current.kind == .view("Text") {
        leafIdentities.append(current.identity)
      }
      work.append(contentsOf: current.children.reversed())
    }
    let siblingIdentity = try #require(leafIdentities.last)

    graph.beginFrame()
    _ = Resolver().resolve(
      view,
      in: makeContext(
        graph,
        identity: identity,
        invalidatedIdentities: [siblingIdentity]
      )
    )
    _ = graph.finalizeFrame(rootIdentity: identity)

    let retainedReuseActive = !stackLeanResolveProfile || leanRetainedReuse
    #expect(count.value == (retainedReuseActive ? 1 : 2))
  }

  @Test("wrapper-free transparent containers keep a structural parent reuse-certified")
  func wrapperFreeNestedTransparentContainersKeepStructuralReuseCertified() throws {
    let savedTraceEnabled = ReuseDenialTrace.isEnabled
    defer {
      ReuseDenialTrace.reset()
      ReuseDenialTrace.isEnabled = savedTraceEnabled
    }
    ReuseDenialTrace.isEnabled = true

    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyTraversal", "nested-plain-structural-reuse")
    let view = VStack {
      Text("composed")
        .modifier(ComposedPassthroughModifier())
        .padding()
      ScopedBuilder(scoped: Text("scoped"), authoringContext: nil)
        .padding()
      Text("static sibling")
    }

    graph.beginFrame()
    _ = Resolver().resolve(view, in: makeContext(graph, identity: identity))
    let firstFrame = graph.snapshot(rootIdentity: identity)
    _ = graph.finalizeFrame(rootIdentity: identity)
    ReuseDenialTrace.reset()

    var leafIdentities: [Identity] = []
    var work = [firstFrame]
    while let current = work.popLast() {
      if current.kind == .view("Text") {
        leafIdentities.append(current.identity)
      }
      work.append(contentsOf: current.children.reversed())
    }
    let siblingIdentity = try #require(leafIdentities.last)

    graph.beginFrame()
    _ = Resolver().resolve(
      view,
      in: makeContext(
        graph,
        identity: identity,
        invalidatedIdentities: [siblingIdentity]
      )
    )
    _ = graph.finalizeFrame(rootIdentity: identity)

    #expect(ReuseDenialTrace.reasonCounts["dynamic-property-uncertified"] == nil)
  }

  @Test("a forwarded DynamicProperty output updates under its captured owner")
  func scopedBuilderDynamicPropertyOutputUsesItsCapturedOwner() {
    let graph = ViewGraph()
    let authoredIdentity = testIdentity("DynamicPropertyScope", "captured-output")
    let hostIdentity = testIdentity("DynamicPropertyScope", "captured-output-host")
    graph.beginFrame()
    let authoredNode = graph.prepareDynamicPropertyUpdate(identity: authoredIdentity)
    let authoredScope = AuthoringContext(
      viewIdentity: authoredIdentity,
      focusedValues: .init(),
      viewNode: authoredNode
    )
    let capture = ScopeOwnerCapture()
    let builder = ScopedBuilder(
      scoped: OwnerCapturingDynamicPropertyOutput(capture: capture),
      authoringContext: authoredScope
    )

    _ = Resolver().resolve(builder, in: makeContext(graph, identity: hostIdentity))

    #expect(capture.updateOwner == authoredNode.viewNodeID)
    #expect(capture.bodyOwner == authoredNode.viewNodeID)
  }

  @Test("a nested explicitly nil ScopedBuilder resets a captured owner for update and body")
  func nestedExplicitlyNilScopedBuilderUsesTheDestinationOwner() throws {
    let graph = ViewGraph()
    let authoredIdentity = testIdentity("DynamicPropertyScope", "outer-captured-builder")
    let hostIdentity = testIdentity("DynamicPropertyScope", "nested-nil-builder-host")
    graph.beginFrame()
    let authoredNode = graph.prepareDynamicPropertyUpdate(identity: authoredIdentity)
    let authoredScope = AuthoringContext(
      viewIdentity: authoredIdentity,
      focusedValues: .init(),
      viewNode: authoredNode
    )
    let capture = ScopeOwnerCapture()
    let inner = ScopedBuilder(
      scoped: OwnerCapturingDynamicPropertyOutput(capture: capture),
      authoringContext: nil
    )
    let outer = ScopedBuilder(scoped: inner, authoringContext: authoredScope)

    _ = Resolver().resolve(outer, in: makeContext(graph, identity: hostIdentity))

    let hostNode = try #require(graph.nodeForIdentity(hostIdentity))
    #expect(capture.updateOwner == hostNode.viewNodeID)
    #expect(capture.bodyOwner == hostNode.viewNodeID)
    #expect(capture.updateOwner != authoredNode.viewNodeID)
  }

  @Test("a forwarded DynamicProperty output keeps nested State at its root path")
  func scopedBuilderDynamicPropertyOutputKeepsStateContinuityAtRoot() throws {
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyTraversal", "stateful-builder-output")
    let log = StatefulDynamicPropertyLog()

    for _ in 0..<2 {
      graph.beginFrame()
      _ = Resolver().resolve(
        ScopedBuilder(
          scoped: StatefulDynamicPropertyOutput(log: log),
          authoringContext: nil
        ),
        in: makeContext(graph, identity: identity)
      )
      _ = graph.finalizeFrame(rootIdentity: identity)
    }

    #expect(log.updateValues == [1, 2])
    #expect(log.bodyValues == [1, 2])
    let slots = try #require(graph.nodeForIdentity(identity))
      .debugTotalStateSnapshot().stateSlots
    #expect(slots.count == 1)
    #expect(slots.first?.slot.path == .root)
  }

  @Test("a scoped exact-ID output keeps DynamicProperty State at the routed child")
  func scopedBuilderExactIdentityOutputKeepsStateAtRoutedChild() throws {
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyTraversal", "stateful-builder-exact-output")
    let exactIdentity = testIdentity("DynamicPropertyTraversal", "stateful-builder-exact-child")
    let log = StatefulDynamicPropertyLog()

    for iteration in 0..<2 {
      graph.beginFrame()
      if iteration == 0 {
        let hostNode = graph.prepareDynamicPropertyUpdate(identity: identity)
        graph.prepareEntityRoutedOwner(
          EntityIdentity("captured-payload-host"),
          for: hostNode
        )
      }
      _ = Resolver().resolve(
        ScopedBuilder(
          scoped: StatefulDynamicPropertyOutput(log: log).id(exactIdentity),
          authoringContext: nil
        ),
        in: makeContext(graph, identity: identity)
      )
      _ = graph.finalizeFrame(rootIdentity: identity)
    }

    #expect(log.updateValues == [1, 2])
    #expect(log.bodyValues == [1, 2])
    let routedNode = try #require(graph.nodeForIdentity(exactIdentity))
    let slots = routedNode.debugTotalStateSnapshot().stateSlots
    #expect(slots.count == 1)
    #expect(slots.first?.slot.path == .root)
    #expect(graph.nodeForIdentity(identity)?.debugTotalStateSnapshot().stateSlots.isEmpty == true)
  }

  @Test("a forwarded DynamicProperty modifier keeps nested State at its root path")
  func dynamicPropertyModifierKeepsStateContinuityAtRoot() throws {
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyTraversal", "stateful-modifier")
    let log = StatefulDynamicPropertyLog()

    for _ in 0..<2 {
      graph.beginFrame()
      _ = Resolver().resolve(
        Text("base").modifier(StatefulDynamicPropertyModifier(log: log)),
        in: makeContext(graph, identity: identity)
      )
      _ = graph.finalizeFrame(rootIdentity: identity)
    }

    #expect(log.updateValues == [1, 2])
    #expect(log.bodyValues == [1, 2])
    let slots = try #require(graph.nodeForIdentity(identity))
      .debugTotalStateSnapshot().stateSlots
    #expect(slots.count == 1)
    #expect(slots.first?.slot.path == .root)
  }

  @Test(
    "transparent View-and-DynamicProperty content keeps nested State continuous at its root path")
  func transparentDynamicPropertyContentKeepsStateContinuityAtRoot() throws {
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyTraversal", "stateful-modifier-output")
    let log = StatefulDynamicPropertyLog()

    for _ in 0..<2 {
      graph.beginFrame()
      _ = Resolver().resolve(
        StatefulDynamicPropertyOutput(log: log).disabled(true),
        in: makeContext(graph, identity: identity)
      )
      _ = graph.finalizeFrame(rootIdentity: identity)
    }

    #expect(log.updateValues == [1, 2])
    #expect(log.bodyValues == [1, 2])
    let slots = try #require(graph.nodeForIdentity(identity))
      .debugTotalStateSnapshot().stateSlots
    #expect(slots.count == 1)
    #expect(slots.first?.slot.path == .root)
  }

  @Test("memo shadow oracle excludes changed and uncertified DynamicProperty updates")
  func shadowOracleRequiresUnchangedDynamicPropertyResult() {
    struct OracleProbe: View, Equatable {
      var body: some View { Text("oracle") }
    }

    let savedEnabled = MemoSkipTrace.isEnabled
    let savedSampling = MemoSkipTrace.sampleEveryNFrames
    defer {
      MemoSkipTrace.isEnabled = savedEnabled
      MemoSkipTrace.sampleEveryNFrames = savedSampling
    }
    MemoSkipTrace.isEnabled = true
    MemoSkipTrace.sampleEveryNFrames = 1

    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyMemo", "shadow-result")
    graph.beginFrame()
    let node = graph.prepareDynamicPropertyUpdate(identity: identity)
    node.memoViewValue = OracleProbe()
    let context = makeContext(
      graph,
      identity: identity,
      invalidatedIdentities: [testIdentity("DynamicPropertyMemo", "ancestor")]
    )

    let changed = beginMemoObservation(
      OracleProbe(),
      graphNode: node,
      context: context,
      dynamicPropertyUpdateResult: .changed
    )
    let uncertified = beginMemoObservation(
      OracleProbe(),
      graphNode: node,
      context: context,
      dynamicPropertyUpdateResult: .uncertified
    )
    #expect(changed?.hadReads == nil)
    #expect(uncertified?.hadReads == nil)
  }

  @Test("changed and uncertified updates have named reuse-denial trace reasons")
  func updateResultsRemainVisibleInReuseDenialCensus() {
    let savedEnabled = ReuseDenialTrace.isEnabled
    defer {
      ReuseDenialTrace.reset()
      ReuseDenialTrace.isEnabled = savedEnabled
    }
    ReuseDenialTrace.isEnabled = true

    func denialCount(
      for result: DynamicPropertyUpdateResult,
      reason: String
    ) -> Int {
      ReuseDenialTrace.reset()
      let graph = ViewGraph()
      let identity = testIdentity("DynamicPropertyReuseDenial", reason)
      let unrelated = testIdentity("DynamicPropertyReuseDenial", "unrelated")
      let log = PassEventLog()

      graph.beginFrame()
      _ = Resolver().resolve(
        PlainBodyHost(log: log),
        in: makeContext(graph, identity: identity)
      )
      _ = graph.finalizeFrame(rootIdentity: identity)
      ReuseDenialTrace.reset()

      graph.beginFrame()
      _ = Resolver().resolve(
        PlainBodyHost(log: log, result: result),
        in: makeContext(
          graph,
          identity: identity,
          invalidatedIdentities: [unrelated]
        )
      )
      return ReuseDenialTrace.reasonCounts[reason] ?? 0
    }

    #expect(
      denialCount(for: .changed, reason: "dynamic-property-changed") == 1
    )
    #expect(
      denialCount(for: .uncertified, reason: "dynamic-property-uncertified") == 1
    )
  }
}
