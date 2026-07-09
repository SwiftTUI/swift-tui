/// A scheduling priority for lifecycle-owned tasks.
public enum TaskPriority: String, Equatable, Sendable {
  case userInitiated
  case high
  case medium
  case low
  case background
}

/// Identifies a lifecycle-owned task.
public struct TaskDescriptor: Equatable, Sendable {
  public var id: String
  public var priority: TaskPriority

  /// Creates a task descriptor.
  public init(id: String, priority: TaskPriority) {
    self.id = id
    self.priority = priority
  }
}

/// A lifecycle operation emitted during commit planning.
package enum LifecycleCommitOperation: Equatable, Sendable {
  case appear(handlerIDs: [String])
  case disappear(handlerIDs: [String])
  case change(handlerIDs: [String])
  case taskStart(TaskDescriptor)
  case taskCancel(TaskDescriptor)

  package var commitEffectCategory: CommitEffectCategory {
    switch self {
    case .appear:
      .lifecycleAppear
    case .disappear:
      .lifecycleDisappear
    case .change:
      .lifecycleChange
    case .taskStart:
      .taskStart
    case .taskCancel:
      .taskCancel
    }
  }
}

/// A single lifecycle operation emitted for one identity.
package struct LifecycleCommitEntry: Equatable, Sendable {
  package var viewNodeID: ViewNodeID?
  package var identity: Identity
  package var operation: LifecycleCommitOperation

  package init(
    identity: Identity,
    operation: LifecycleCommitOperation
  ) {
    viewNodeID = nil
    self.identity = identity
    self.operation = operation
  }

  package init(
    viewNodeID: ViewNodeID?,
    identity: Identity,
    operation: LifecycleCommitOperation
  ) {
    self.viewNodeID = viewNodeID
    self.identity = identity
    self.operation = operation
  }
}

/// Closed categories of observable side effects carried by ``CommitPlan``.
package enum CommitEffectCategory: CaseIterable, Sendable {
  case lifecycleAppear
  case lifecycleDisappear
  case lifecycleChange
  case taskStart
  case taskCancel
  case handlerInstallations
}
