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
public enum LifecycleCommitOperation: Equatable, Sendable {
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
public struct LifecycleCommitEntry: Equatable, Sendable {
  package var viewNodeID: ViewNodeID?
  public var identity: Identity
  public var operation: LifecycleCommitOperation

  public init(
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

/// Records a handler that must be installed for the committed frame.
public struct HandlerInstallation: Equatable, Sendable {
  public var handlerID: RouteID

  public init(handlerID: RouteID) {
    self.handlerID = handlerID
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

/// The runtime-facing result of the commit phase.
///
/// Commit packages the already-derived semantic snapshot with lifecycle and
/// handler-installation work that the runtime must apply in order. The semantic
/// snapshot is carried for runtime consumers; lifecycle and handler entries are
/// the commit-owned side-effect plan.
public struct CommitPlan: Equatable, Sendable {
  public var transaction: TransactionSnapshot
  public var semanticSnapshot: SemanticSnapshot
  public var lifecycle: [LifecycleCommitEntry]
  public var handlerInstallations: [HandlerInstallation]

  public init(
    transaction: TransactionSnapshot = .init(),
    semanticSnapshot: SemanticSnapshot = .init(),
    lifecycle: [LifecycleCommitEntry] = [],
    handlerInstallations: [HandlerInstallation] = []
  ) {
    self.transaction = transaction
    self.semanticSnapshot = semanticSnapshot
    self.lifecycle = lifecycle
    self.handlerInstallations = handlerInstallations
  }

  package var effectCategories: Set<CommitEffectCategory> {
    var categories = Set(lifecycle.map(\.operation.commitEffectCategory))
    if !handlerInstallations.isEmpty {
      categories.insert(.handlerInstallations)
    }
    return categories
  }
}
