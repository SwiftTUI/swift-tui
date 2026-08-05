import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

// Stage 2 of the DynamicProperty program (plan 2026-08-04-003):
// path-qualified slot identity. Wrappers reached through a discovered
// dynamic property bind during the update pass with the discovery path in
// their slot key, so two instances of one composed wrapper get distinct
// storage — matching real SwiftUI (verified 2026-08-04). Wrappers composed
// in types that do NOT conform to DynamicProperty stay on the legacy
// silent-sharing path, which now reports a duplicate-claim RuntimeIssue.
@propertyWrapper
@MainActor
private struct QualifiedCounter: DynamicProperty {
  private let state: State<Int>

  init() {
    // The fixed source location models the third-party shape: every
    // instance's inner @State has the same authored ordinal, so only the
    // discovery-path qualification distinguishes them.
    state = State(wrappedValue: 0, line: 600, column: 6)
  }

  var wrappedValue: Int {
    state.wrappedValue
  }

  func write(_ value: Int) {
    state.wrappedValue = value
  }
}

/// The same composition WITHOUT the DynamicProperty conformance: invisible
/// to discovery, so both instances claim the unqualified slot — the legacy
/// sharing pin plus the new duplicate-claim diagnostic.
@propertyWrapper
@MainActor
private struct UndiscoveredCounter {
  private let state: State<Int>

  init() {
    state = State(wrappedValue: 0, line: 700, column: 7)
  }

  var wrappedValue: Int {
    state.wrappedValue
  }

  func write(_ value: Int) {
    state.wrappedValue = value
  }
}

@MainActor
private final class SlotIdentityCapture {
  var writeFirst: ((Int) -> Void)?
  var readFirst: (() -> Int)?
  var readSecond: (() -> Int)?
  var snapshot: ImperativeAuthoringContextSnapshot?
}

private struct QualifiedHost: View {
  @QualifiedCounter private var first: Int
  @QualifiedCounter private var second: Int
  private let capture: SlotIdentityCapture

  init(capture: SlotIdentityCapture) {
    self.capture = capture
  }

  var body: some View {
    capture.writeFirst = { [_first] value in _first.write(value) }
    capture.readFirst = { [_first] in _first.wrappedValue }
    capture.readSecond = { [_second] in _second.wrappedValue }
    capture.snapshot = currentImperativeAuthoringContextSnapshot()
    return Text("\(first) \(second)")
  }
}

private struct UndiscoveredHost: View {
  @UndiscoveredCounter private var first: Int
  @UndiscoveredCounter private var second: Int

  var body: some View {
    Text("\(first) \(second)")
  }
}

@MainActor
struct DynamicPropertySlotIdentityTests {
  private func resolve<V: View>(
    _ view: V,
    identity: Identity
  ) -> ViewGraph {
    let graph = ViewGraph()
    graph.beginFrame()
    var context = ResolveContext(
      identity: identity,
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(view, in: context)
    return graph
  }

  @Test("two instances of one composed wrapper hold distinct storage")
  func composedWrapperInstancesGetDistinctStorage() throws {
    let capture = SlotIdentityCapture()
    _ = resolve(QualifiedHost(capture: capture), identity: testIdentity("DistinctSlots"))
    let snapshot = try #require(capture.snapshot)

    withImperativeAuthoringContext(snapshot) {
      capture.writeFirst?(7)
    }

    let first = try #require(
      withImperativeAuthoringContext(snapshot) { capture.readFirst?() }
    )
    let second = try #require(
      withImperativeAuthoringContext(snapshot) { capture.readSecond?() }
    )
    #expect(first == 7)
    #expect(second == 0, "the second instance read the first instance's write — shared slot")
  }

  @Test("a composed write after distinct binding invalidates and re-resolves correctly")
  func composedWriteRoundTripsThroughDistinctSlots() throws {
    let capture = SlotIdentityCapture()
    let identity = testIdentity("DistinctSlotsRoundTrip")
    let graph = resolve(QualifiedHost(capture: capture), identity: identity)
    let snapshot = try #require(capture.snapshot)

    withImperativeAuthoringContext(snapshot) {
      capture.writeFirst?(3)
    }

    graph.beginFrame()
    var context = ResolveContext(
      identity: identity,
      environmentValues: .init(),
      invalidatedIdentities: [identity],
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(QualifiedHost(capture: capture), in: context)

    let first = try #require(
      withImperativeAuthoringContext(snapshot) { capture.readFirst?() }
    )
    let second = try #require(
      withImperativeAuthoringContext(snapshot) { capture.readSecond?() }
    )
    #expect(first == 3)
    #expect(second == 0)
  }

  @Test("undiscovered composition reports a duplicate-slot-claim RuntimeIssue")
  func undiscoveredCompositionReportsDuplicateClaim() {
    let graph = resolve(UndiscoveredHost(), identity: testIdentity("DuplicateClaim"))
    #expect(
      graph.frameRuntimeIssues.contains { $0.code == "state.duplicateSlotClaim" },
      "two distinct boxes claimed one slot silently; issues: \(graph.frameRuntimeIssues)"
    )
  }

  @Test("a discovered composition reports no duplicate-claim issue")
  func discoveredCompositionReportsNoDuplicateClaim() {
    let capture = SlotIdentityCapture()
    let graph = resolve(QualifiedHost(capture: capture), identity: testIdentity("NoDuplicate"))
    #expect(graph.frameRuntimeIssues.isEmpty, "unexpected issues: \(graph.frameRuntimeIssues)")
  }
}
