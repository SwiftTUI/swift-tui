import Testing

@testable import SwiftTUIRuntime

@Suite
struct ConcurrentRegistrationCarryTests {
  @Test("sinceBaseline returns only entries inserted since the baseline")
  func sinceBaselineReturnsNewEntries() {
    let baseline = ["a": 1, "b": 2]
    let live = ["a": 1, "b": 2, "c": 3, "d": 4]
    let carried = ConcurrentRegistrationCarry.sinceBaseline(live: live, baseline: baseline)
    #expect(carried == ["c": 3, "d": 4])
  }

  @Test("sinceBaseline excludes keys already present in the baseline by key, not value")
  func sinceBaselineKeyedNotValued() {
    let baseline = ["a": 1]
    // `a` changed value but is not new; only `b` is a concurrent insertion.
    let live = ["a": 99, "b": 2]
    let carried = ConcurrentRegistrationCarry.sinceBaseline(live: live, baseline: baseline)
    #expect(carried == ["b": 2])
  }

  @Test("reapply inserts carried entries that the target lacks")
  func reapplyInsertsMissing() {
    var target = ["a": 1]
    ConcurrentRegistrationCarry.reapply(["b": 2, "c": 3], into: &target)
    #expect(target == ["a": 1, "b": 2, "c": 3])
  }

  @Test("reapply never overwrites an entry the restored target already holds")
  func reapplyDoesNotOverwrite() {
    var target = ["a": 1, "b": 100]
    ConcurrentRegistrationCarry.reapply(["b": 2, "c": 3], into: &target)
    // `b` keeps the restored draft's own value (100), only `c` is added.
    #expect(target == ["a": 1, "b": 100, "c": 3])
  }

  @Test("the publish round-trip preserves concurrent insertions across a restore")
  func publishRoundTrip() {
    // Baseline snapshot at the moment the in-flight frame's draft was taken.
    let baseline = ["batchA": 1]
    // The live controller gained `batchB` while the frame's tail was in flight.
    let live = ["batchA": 1, "batchB": 2]
    let concurrent = ConcurrentRegistrationCarry.sinceBaseline(live: live, baseline: baseline)
    // A full `restore` clobbers live back to the draft's own state.
    var restored = ["batchA": 1, "batchC": 3]
    ConcurrentRegistrationCarry.reapply(concurrent, into: &restored)
    // The concurrent registration survives; the draft's own state is intact.
    #expect(restored == ["batchA": 1, "batchB": 2, "batchC": 3])
  }

  @Test("the primitive carries non-Equatable closure payloads by key")
  func carriesClosurePayloads() {
    let baseline: [Int: @Sendable () -> Void] = [1: {}]
    let live: [Int: @Sendable () -> Void] = [1: {}, 2: {}]
    let carried = ConcurrentRegistrationCarry.sinceBaseline(live: live, baseline: baseline)
    #expect(Set(carried.keys) == [2])
    var target: [Int: @Sendable () -> Void] = [1: {}, 3: {}]
    ConcurrentRegistrationCarry.reapply(carried, into: &target)
    #expect(Set(target.keys) == [1, 2, 3])
  }
}
