import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite("Retained validation work")
struct RetainedValidationWorkTests {
  @Test("comparison work counts visited prefixes, shared environments, and placement")
  func comparisonPrefixes() {
    let original = tree()
    let recorder = ComparisonWorkRecorder()
    #expect(original.measurementEquivalence(to: original, recorder: recorder).isCompatible)
    #expect(recorder.snapshot.measurementNodes == 3)
    #expect(recorder.snapshot.environmentSnapshots == 3)
    #expect(recorder.snapshot.environmentSharedStorage == 3)
    #expect(recorder.snapshot.environmentValues == 0)

    var changed = original
    changed.children[0].intrinsicSize = .init(width: 5, height: 1)
    #expect(!original.measurementEquivalence(to: changed, recorder: recorder).isCompatible)
    #expect(recorder.snapshot.measurementNodes == 5)
    #expect(original.placementEquivalence(to: original, recorder: recorder) == .identical)
    #expect(recorder.snapshot.placementNodes == 3)
  }

  @Test("cache hits expose witness refresh and actual typed environment comparisons")
  func witnessRefresh() throws {
    let cache = MeasurementCache()
    var original = tree()
    original.children[0].environmentSnapshot = environment(1)
    _ = LayoutEngine(cache: cache).measure(original, proposal: .unspecified, passContext: nil)
    var current = original
    current.children[0].environmentSnapshot = environment(1)
    let recorder = RetainedValidationRecorder()
    _ = try #require(cache.lookup(resolved: current, proposal: .unspecified, recorder: recorder))
    #expect(recorder.snapshot.comparison.environmentValues == 1)
    #expect(recorder.snapshot.identityNodesChecked == 3)
    #expect(recorder.snapshot.measuredNodesRestamped == 0)
    _ = try #require(cache.lookup(resolved: current, proposal: .unspecified, recorder: recorder))
    #expect(recorder.snapshot.comparison.environmentValues == 1)
    #expect(recorder.snapshot.comparison.measurementNodes == 6)
    current.children[0].environmentSnapshot = environment(2)
    #expect(cache.lookup(resolved: current, proposal: .unspecified, recorder: recorder) == nil)
    #expect(recorder.snapshot.comparison.environmentValues == 2)
    #expect(recorder.snapshot.comparison.measurementNodes == 8)
    #expect(recorder.snapshot.identityNodesChecked == 6)
  }

  @Test("identity drift counts the probe prefix and every rebuilt measured node")
  func restampWork() {
    let original = tree()
    var measured = LayoutEngine().measure(original, proposal: .unspecified, passContext: nil)
    measured.containerAllocationSnapshot = .init(
      childSizes: measured.childMeasurements.map {
        .init(identity: $0.identity, size: $0.measuredSize)
      })
    var current = original
    current.identity = testIdentity("new-root")
    current.children[0].identity = testIdentity("new-root", "first")
    let recorder = RetainedValidationRecorder()
    let stamped = measured.restampingIdentities(from: current, recorder: recorder)
    #expect(stamped.identity == current.identity)
    #expect(stamped.childMeasurements[0].identity == current.children[0].identity)
    #expect(recorder.snapshot.identityNodesChecked == 1)
    #expect(recorder.snapshot.measuredNodesRestamped == 3)
    #expect(recorder.snapshot.allocationIdentitiesRestamped == 2)
    #expect(
      stamped.containerAllocationSnapshot?.childSizes[0].identity == current.children[0].identity)
    #expect(stamped.measuredSize == measured.measuredSize)
    #expect(stamped == measured.restampingIdentities(from: current))
  }

  @Test(
    "shared and rematerialized warm inputs expose their different validation cost",
    arguments: [false, true])
  func warmInputStorage(rematerialized: Bool) throws {
    let cache = MeasurementCache()
    var original = tree()
    original.children[0].environmentSnapshot = environment(1)
    _ = LayoutEngine(cache: cache).measure(original, proposal: .unspecified, passContext: nil)
    var current = original
    if rematerialized { current.children[0].environmentSnapshot = environment(1) }
    let recorder = RetainedValidationRecorder()
    let first = try #require(
      cache.lookup(
        resolved: current, proposal: .unspecified, recorder: recorder))
    let second = try #require(
      cache.lookup(
        resolved: current, proposal: .unspecified, recorder: recorder))
    #expect(first == second)
    #expect(recorder.snapshot.comparison.measurementNodes == 6)
    #expect(recorder.snapshot.comparison.environmentValues == (rematerialized ? 1 : 0))
    #expect(recorder.snapshot.comparison.environmentSharedStorage == (rematerialized ? 5 : 6))
    #expect(recorder.snapshot.identityNodesChecked == 6)
  }

  @Test("pass collection is opt-in and metrics snapshots do not drain it")
  func passOwnership() {
    #expect(LayoutPassContext().workMetrics.retainedValidation == nil)
    let recorder = RetainedValidationRecorder()
    let context = LayoutPassContext(retainedValidationRecorder: recorder)
    _ = tree().measurementEquivalence(to: tree(), recorder: recorder.comparisons)
    #expect(context.workMetrics.retainedValidation?.comparison.measurementNodes == 3)
    #expect(context.workMetrics.retainedValidation?.comparison.measurementNodes == 3)
    var combined = context.workMetrics
    combined.merge(context.workMetrics)
    #expect(combined.retainedValidation?.comparison.measurementNodes == 6)
  }

  @Test("retained placement counts measured equality, translation checks, and metadata copies")
  func placedProductWork() {
    let original = tree()
    let engine = LayoutEngine()
    let measured = engine.measure(original, proposal: .unspecified, passContext: nil)
    let placed = engine.place(original, measured: measured)
    let recorder = RetainedValidationRecorder()
    #expect(measured.isEqual(to: measured, recorder: recorder))
    #expect(engine.isEquivalentForViewportTranslation(measured, measured, recorder: recorder))
    #expect(recorder.snapshot.measuredEqualityNodes == 3)
    #expect(recorder.snapshot.viewportComparisonNodes == 3)
    var current = original
    current.children[0].identity = testIdentity("changed-child")
    let stamped = engine.synchronizeRetainedPhaseMetadata(
      placed: placed, from: current, recorder: recorder)
    #expect(stamped.children[0].identity == current.children[0].identity)
    #expect(recorder.snapshot.placedNodesRestamped == 3)
    #expect(stamped.bounds == placed.bounds)
  }

  private func tree() -> ResolvedNode {
    ResolvedNode(
      viewNodeID: .init(rawValue: 1),
      identity: testIdentity("Root"),
      kind: .view("Root"),
      children: (0..<2).map { index in
        ResolvedNode(
          viewNodeID: .init(rawValue: UInt64(index + 2)),
          identity: testIdentity("Root", String(index)),
          kind: .view("Child"),
          intrinsicSize: .init(width: 4, height: 1)
        )
      }
    )
  }

  private func environment(_ value: Int) -> EnvironmentSnapshot {
    EnvironmentSnapshot(typedValues: [
      ObjectIdentifier(Int.self): EnvironmentSnapshotValue(
        keyType: Int.self, reuseValue: TypedReuseValue(value))
    ])
  }
}
