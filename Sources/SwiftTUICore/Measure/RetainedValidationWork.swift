import Synchronization

/// Retained validation work for one layout pass. Core owns the product walks;
/// Graph supplies only its comparison tallies.
package struct RetainedValidationWork: Equatable, Sendable {
  package var comparison = ComparisonWork()
  package var measuredEqualityNodes = 0
  package var viewportComparisonNodes = 0
  package var identityNodesChecked = 0
  package var measuredNodesRestamped = 0
  package var allocationIdentitiesRestamped = 0
  package var placedNodesRestamped = 0

  package init() {}

  package mutating func merge(_ other: Self) {
    comparison.merge(other.comparison)
    measuredEqualityNodes += other.measuredEqualityNodes
    viewportComparisonNodes += other.viewportComparisonNodes
    identityNodesChecked += other.identityNodesChecked
    measuredNodesRestamped += other.measuredNodesRestamped
    allocationIdentitiesRestamped += other.allocationIdentitiesRestamped
    placedNodesRestamped += other.placedNodesRestamped
  }
}

package final class RetainedValidationRecorder: Sendable {
  package static let isEnabled = FeatureGate.retainedValidationCounters.initialIsEnabled()
  package let comparisons = ComparisonWorkRecorder()
  private let storage = Mutex(RetainedValidationWork())

  package init() {}

  package var snapshot: RetainedValidationWork {
    var result = storage.withLock { $0 }
    result.comparison = comparisons.snapshot
    return result
  }

  package func merge(_ work: RetainedValidationWork) {
    storage.withLock { $0.merge(work) }
  }
}
