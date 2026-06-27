package enum NodeLifecycleState: Equatable, Sendable {
  case appearing
  case alive
  case disappearing
}

package typealias LifecycleEvent = LifecycleCommitEntry
package typealias LifecycleOperation = LifecycleCommitOperation
