import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite("Measurement-cache witness refresh")
struct MeasurementCacheWitnessRefreshTests {
  @Test("a typed witness cannot bridge through nil to a different concrete type")
  func wildcardCannotBridgeConcreteTypes() {
    let cache = MeasurementCache()
    let original = witnessNode(type: ObjectIdentifier(Int.self))
    seed(cache, with: original)
    var wildcard = original
    wildcard.typeDiscriminator = nil
    var different = original
    different.typeDiscriminator = ObjectIdentifier(String.self)

    #expect(cache.lookup(resolved: wildcard, proposal: .unspecified) != nil)
    #expect(cache.lookup(resolved: different, proposal: .unspecified) == nil)
    #expect(cache.metrics.hits == 1)
    #expect(cache.metrics.invalidations == 1)
    #expect(cache.count == 0)
  }

  @Test("a wildcard lookup preserves later reuse of the original concrete type")
  func wildcardPreservesOriginalConcreteType() {
    let cache = MeasurementCache()
    let original = witnessNode(type: ObjectIdentifier(Int.self))
    seed(cache, with: original)
    var wildcard = original
    wildcard.typeDiscriminator = nil

    #expect(cache.lookup(resolved: wildcard, proposal: .unspecified) != nil)
    #expect(cache.lookup(resolved: original, proposal: .unspecified) != nil)
    #expect(cache.metrics.hits == 2)
    #expect(cache.metrics.invalidations == 0)
  }

  @Test("a nested wildcard cannot replace its parent's concrete measurement witness")
  func nestedWildcardCannotBridgeConcreteTypes() {
    let cache = MeasurementCache()
    let original = witnessTree()
    seed(cache, with: original)
    var wildcard = original
    wildcard.children[0].typeDiscriminator = nil
    var different = original
    different.children[0].typeDiscriminator = ObjectIdentifier(String.self)
    let initialHits = cache.metrics.hits

    #expect(cache.lookup(resolved: wildcard, proposal: .unspecified) != nil)
    #expect(cache.lookup(resolved: different, proposal: .unspecified) == nil)
    #expect(cache.metrics.hits == initialHits + 1)
    #expect(cache.metrics.invalidations == 1)
  }

  @Test("certified hits stop repeating equivalent environment-value comparisons")
  func certifiedHitsRefreshEquivalentEnvironmentStorage() {
    let comparisons = WitnessComparisonCounter()
    let cache = MeasurementCache()
    var original = witnessTree()
    original.children[0].environmentSnapshot = environment(value: 1, comparisons: comparisons)
    seed(cache, with: original)
    var current = original
    current.children[0].environmentSnapshot = environment(value: 1, comparisons: comparisons)

    #expect(cache.lookup(resolved: current, proposal: .unspecified) != nil)
    let afterFirstHit = comparisons.count
    #expect(afterFirstHit == 1)
    #expect(cache.lookup(resolved: current, proposal: .unspecified) != nil)
    #expect(comparisons.count == afterFirstHit)
  }

  @Test("a changed environment invalidates a previously refreshed witness")
  func environmentChangeInvalidatesRefreshedWitness() {
    let comparisons = WitnessComparisonCounter()
    let cache = MeasurementCache()
    var original = witnessNode(type: ObjectIdentifier(Int.self))
    original.environmentSnapshot = environment(value: 1, comparisons: comparisons)
    seed(cache, with: original)
    var current = original
    current.environmentSnapshot = environment(value: 1, comparisons: comparisons)
    #expect(cache.lookup(resolved: current, proposal: .unspecified) != nil)

    current.environmentSnapshot = environment(value: 2, comparisons: comparisons)
    #expect(cache.lookup(resolved: current, proposal: .unspecified) == nil)
    #expect(cache.metrics.invalidations == 1)
    #expect(cache.count == 0)
  }

  @Test(
    "successive identity changes restamp both certified and wildcard hits",
    arguments: [false, true])
  func repeatedIdentityChangesRestamp(wildcard: Bool) throws {
    let cache = MeasurementCache()
    let original = witnessTree()
    seed(cache, with: original)
    for suffix in ["second", "third"] {
      var current = original
      current.identity = testIdentity("Root", suffix)
      current.children[0].identity = testIdentity("Root", suffix, "Child")
      if wildcard {
        current.children[0].typeDiscriminator = nil
      }

      let served = try #require(cache.lookup(resolved: current, proposal: .unspecified))
      #expect(served.identity == current.identity)
      #expect(served.childMeasurements.first?.identity == current.children[0].identity)
      #expect(served.measuredSize == .init(width: 4, height: 1))
    }
  }

  private func seed(_ cache: MeasurementCache, with node: ResolvedNode) {
    _ = LayoutEngine(cache: cache).measure(node, proposal: .unspecified, passContext: nil)
  }

  private func witnessNode(type: ObjectIdentifier?) -> ResolvedNode {
    ResolvedNode(
      viewNodeID: .init(rawValue: 1),
      identity: testIdentity("Root"),
      kind: .view("Witness"),
      typeDiscriminator: type,
      intrinsicSize: .init(width: 4, height: 1)
    )
  }

  private func witnessTree() -> ResolvedNode {
    var root = witnessNode(type: ObjectIdentifier(Int.self))
    root.children = [
      ResolvedNode(
        viewNodeID: .init(rawValue: 2),
        identity: testIdentity("Root", "Child"),
        kind: .view("WitnessChild"),
        typeDiscriminator: ObjectIdentifier(Int.self),
        intrinsicSize: .init(width: 4, height: 1)
      )
    ]
    return root
  }

  private func environment(
    value: Int,
    comparisons: WitnessComparisonCounter
  ) -> EnvironmentSnapshot {
    EnvironmentSnapshot(
      typedValues: [
        ObjectIdentifier(WitnessEnvironmentKey.self): EnvironmentSnapshotValue(
          keyType: WitnessEnvironmentKey.self,
          reuseValue: TypedReuseValue(
            WitnessEnvironmentValue(value: value, comparisons: comparisons))
        )
      ]
    )
  }
}

private enum WitnessEnvironmentKey {}

private struct WitnessEnvironmentValue: Equatable, Sendable {
  let value: Int
  let comparisons: WitnessComparisonCounter

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.comparisons.record()
    return lhs.value == rhs.value
  }
}

private final class WitnessComparisonCounter: Sendable {
  private let storage = Mutex(0)

  var count: Int { storage.withLock { $0 } }

  func record() {
    storage.withLock { $0 += 1 }
  }
}
