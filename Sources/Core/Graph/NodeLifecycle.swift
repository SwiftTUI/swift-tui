package enum NodeLifecycleState: Equatable, Sendable {
  case appearing
  case alive
  case disappearing
}

public typealias LifecycleEvent = LifecycleCommitEntry
public typealias LifecycleOperation = LifecycleCommitOperation
