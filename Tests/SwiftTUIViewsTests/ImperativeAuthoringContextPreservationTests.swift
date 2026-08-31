import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIViews

/// Pins the imperative-dispatch hardening for the stale-`@State`-in-action-
/// closure bug class: every failure path used to end in a *silent* fallback
/// to the authored seed. Two contracts are pinned here:
///
/// 1. `withImperativeAuthoringContext(nil)` preserves the caller's ambient
///    authoring context. A nil registration snapshot means "registration saw
///    no context", not "clear the context" — installing nil severed a nested
///    dispatch (a user closure firing inside a control's established
///    dispatch context, the `onSubmit` shape) from the ambient owner.
/// 2. An imperative `@State` access that bottoms out at the authored seed on
///    a box that was previously graph-bound records a
///    `state.imperativeSeedFallback` runtime issue instead of failing
///    silently.
@MainActor
struct ImperativeAuthoringContextPreservationTests {
  @MainActor
  final class CapturedSnapshot {
    var snapshot: ImperativeAuthoringContextSnapshot?
  }

  /// A view whose body never reads `flag`, so the box binds only through the
  /// imperative access paths under test.
  private struct StateReadingProbe: View {
    static let flagColumn: UInt = 7

    @State private var flag: Bool
    let captured: CapturedSnapshot

    init(captured: CapturedSnapshot) {
      _flag = State(initialValue: false, line: 0, column: Self.flagColumn)
      self.captured = captured
    }

    var body: some View {
      captured.snapshot = currentImperativeAuthoringContextSnapshot()
      return Text("static")
    }

    func flagReader() -> @MainActor () -> Bool { { flag } }
    func flagWriter() -> @MainActor (Bool) -> Void { { flag = $0 } }
  }

  private func resolve(
    _ probe: StateReadingProbe,
    captured: CapturedSnapshot
  ) throws -> (
    graph: ViewGraph, ownerIdentity: Identity, snapshot: ImperativeAuthoringContextSnapshot
  ) {
    let graph = ViewGraph()
    let ownerIdentity = testIdentity("Root")
    graph.beginFrame()
    var context = ResolveContext(
      identity: ownerIdentity,
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(probe, in: context)
    let snapshot = try #require(captured.snapshot)
    return (graph, ownerIdentity, snapshot)
  }

  private func drainSeedFallbackIssues() -> [RuntimeIssue] {
    ImperativeRuntimeIssueQueue.drain().filter { issue in
      issue.code == "state.imperativeSeedFallback"
    }
  }

  /// The deliberate seed-fallback shapes below fire the gate-on
  /// `state-seed-fallback` soundness oracle by design: suppress its trace
  /// AND restore its counter afterward, per the oracle-reduction convention —
  /// a parallel stress test's `SoundnessGuard` window must not observe this
  /// suite's deliberate growth.
  private func withSeedFallbackTraceSuppressed<Result>(
    _ body: () throws -> Result
  ) rethrows -> Result {
    let savedTrace = SoundnessProbeConfiguration.isTraceEnabled
    let savedCount = SoundnessProbeConfiguration.stateSeedFallbackViolationCount
    SoundnessProbeConfiguration.isTraceEnabled = false
    defer {
      SoundnessProbeConfiguration.isTraceEnabled = savedTrace
      SoundnessProbeConfiguration.stateSeedFallbackViolationCount = savedCount
    }
    return try body()
  }

  @Test("a nil imperative snapshot preserves the ambient authoring context")
  func nilSnapshotPreservesAmbientContext() throws {
    let captured = CapturedSnapshot()
    let probe = StateReadingProbe(captured: captured)
    let (_, ownerIdentity, snapshot) = try resolve(probe, captured: captured)

    withImperativeAuthoringContext(snapshot) {
      #expect(currentAuthoringContext()?.viewIdentity == ownerIdentity)
      let innerIdentity = withImperativeAuthoringContext(nil) {
        currentAuthoringContext()?.viewIdentity
      }
      #expect(innerIdentity == ownerIdentity)
    }
  }

  @Test("a nil imperative snapshot preserves the ambient across the async overload")
  func nilSnapshotPreservesAmbientContextAsync() async throws {
    let captured = CapturedSnapshot()
    let probe = StateReadingProbe(captured: captured)
    let (_, ownerIdentity, snapshot) = try resolve(probe, captured: captured)

    // Explicit async closure values bind the async overloads — a plain
    // trailing closure with no awaits resolves to the sync ones and the
    // async path goes untested.
    let readAmbientIdentity: @MainActor () async -> Identity? = {
      await Task.yield()
      return currentAuthoringContext()?.viewIdentity
    }
    let innerIdentity = await withImperativeAuthoringContext(snapshot) {
      await withImperativeAuthoringContext(nil, readAmbientIdentity)
    }
    #expect(innerIdentity == ownerIdentity)
  }

  @Test("a nested nil-snapshot dispatch reads live @State without a seed fallback")
  func nestedNilDispatchReadsLiveState() throws {
    let captured = CapturedSnapshot()
    let probe = StateReadingProbe(captured: captured)
    let (_, _, snapshot) = try resolve(probe, captured: captured)

    withImperativeAuthoringContext(snapshot) { probe.flagWriter()(true) }
    _ = drainSeedFallbackIssues()

    // The onSubmit shape: a user closure registered with a nil snapshot fires
    // nested inside the control's established dispatch context. The read must
    // resolve the live slot through the preserved ambient — before the fix it
    // fell to the authored seed (and now records the fallback warning, which
    // is what this queue assertion discriminates on).
    let observed = withImperativeAuthoringContext(snapshot) {
      withImperativeAuthoringContext(nil) {
        probe.flagReader()()
      }
    }
    #expect(observed == true)
    #expect(drainSeedFallbackIssues().isEmpty)
  }

  @Test("a seed fallback on a previously bound box records a runtime issue")
  func contextlessReadOnBoundBoxRecordsSeedFallback() throws {
    let captured = CapturedSnapshot()
    let probe = StateReadingProbe(captured: captured)
    let (_, _, snapshot) = try resolve(probe, captured: captured)

    // Bind the box through a legitimate imperative access first.
    _ = withImperativeAuthoringContext(snapshot) { probe.flagReader()() }
    _ = drainSeedFallbackIssues()

    // A context-free read on the bound box degrades to the seed — silently,
    // before this warning existed.
    withSeedFallbackTraceSuppressed {
      _ = probe.flagReader()()
    }

    let issues = drainSeedFallbackIssues()
    #expect(issues.count == 1)
    #expect(issues.first?.severity == .warning)
    // `#fileID` defaults at the probe's `State(initialValue:)` call, so the
    // declaration site names this file with the probe's explicit line/column.
    #expect(
      issues.first?.message.contains(
        "declared at \(#fileID):0:\(StateReadingProbe.flagColumn)."
      ) == true
    )
  }

  @Test("a retired-owner read with no retained value records the seed fallback")
  func retiredOwnerReadRecordsSeedFallback() throws {
    let captured = CapturedSnapshot()
    let probe = StateReadingProbe(captured: captured)
    let (graph, ownerIdentity, snapshot) = try resolve(probe, captured: captured)

    // Bind through the live owner, then retire the subtree so the captured
    // handle no longer resolves (the identity-churn shape: list reshapes,
    // `.id` remounts between registration and fire).
    _ = withImperativeAuthoringContext(snapshot) { probe.flagReader()() }
    let owner = try #require(graph.nodeForIdentity(ownerIdentity))
    graph.beginFrame()
    graph.removeSubtree(rootedAt: owner)
    _ = drainSeedFallbackIssues()

    withSeedFallbackTraceSuppressed {
      _ = withImperativeAuthoringContext(snapshot) { probe.flagReader()() }
    }

    let issues = drainSeedFallbackIssues()
    #expect(issues.count == 1)
    #expect(issues.first?.message.contains("no longer live") == true)
    // The node-gone location closure captures the file by value: the box may
    // already be released when it fires, so the site must not need it.
    #expect(
      issues.first?.message.contains(
        "declared at \(#fileID):0:\(StateReadingProbe.flagColumn)."
      ) == true
    )
  }

  @Test("a never-bound box reads its seed without recording an issue")
  func neverBoundBoxStaysSilent() {
    let probe = StateReadingProbe(captured: CapturedSnapshot())
    _ = drainSeedFallbackIssues()

    // Pre-mount, construction-time reads legitimately see only the seed.
    #expect(probe.flagReader()() == false)

    #expect(drainSeedFallbackIssues().isEmpty)
  }
}
