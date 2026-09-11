import Synchronization

/// Compile-time selection keeps disabled comparison walks free of per-node
/// counter branches, task-local reads, callbacks, and synchronization.
package protocol ComparisonWorkMode {
  static var isEnabled: Bool { get }
}

package enum CountComparisonWork: ComparisonWorkMode {
  package static var isEnabled: Bool { true }
}

package enum SkipComparisonWork: ComparisonWorkMode {
  package static var isEnabled: Bool { false }
}

/// Work actually reached by the retained measurement and placement comparators.
/// Failed comparisons include the prefix visited before rejection.
package struct ComparisonWork: Equatable, Sendable {
  package var measurementNodes = 0
  package var placementNodes = 0
  package var environmentSnapshots = 0
  package var environmentSharedStorage = 0
  package var environmentValues = 0

  package init() {}

  package mutating func merge(_ other: Self) {
    measurementNodes += other.measurementNodes
    placementNodes += other.placementNodes
    environmentSnapshots += other.environmentSnapshots
    environmentSharedStorage += other.environmentSharedStorage
    environmentValues += other.environmentValues
  }
}

/// A pass-owned accumulator. Walks keep scalar tallies locally and merge once;
/// Graph owns comparison accounting without depending on Core or profiling.
package final class ComparisonWorkRecorder: Sendable {
  private let storage = Mutex(ComparisonWork())

  package init() {}

  package var snapshot: ComparisonWork { storage.withLock { $0 } }

  package func merge(_ work: ComparisonWork) {
    storage.withLock { $0.merge(work) }
  }
}
