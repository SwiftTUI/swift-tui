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
  /// A task site within its owning identity, including the generation of a changing task ID.
  public struct ID: Hashable, Sendable {
    package enum Site: Hashable, Sendable {
      case authored(String)
      case modifier(ordinal: Int, token: UInt64?)
      case detached(ordinal: Int, type: ObjectIdentifier)
    }
    package let site: Site
  }

  public private(set) var typedID: ID
  package private(set) var owner: Identity?
  private var detachedTypeName: String?
  public var priority: TaskPriority

  public var id: String {
    get {
      switch typedID.site {
      case .authored(let value): return value
      case .modifier(let ordinal, let token):
        return label(ordinal: ordinal, token: token.map(String.init))
      case .detached(let ordinal, _):
        return label(ordinal: ordinal, token: detachedTypeName)
      }
    }
    set { self = Self(id: newValue, priority: priority) }
  }

  private func label(ordinal: Int, token: String?) -> String {
    let parts = [ordinal == 0 ? nil : String(ordinal), token.map { "id:\($0)" }].compactMap { $0 }
    let suffix = parts.isEmpty ? "" : "[\(parts.joined(separator: ":"))]"
    return "\(owner?.path ?? "")#task\(suffix)"
  }

  public init(id: String, priority: TaskPriority) {
    typedID = ID(site: .authored(id))
    self.priority = priority
  }

  package init(
    owner: Identity, ordinal: Int, token: UInt64?, detachedType: Any.Type?, priority: TaskPriority
  ) {
    self.owner = owner
    self.priority = priority
    if let detachedType {
      typedID = ID(site: .detached(ordinal: ordinal, type: ObjectIdentifier(detachedType)))
      detachedTypeName = String(reflecting: detachedType)
    } else {
      typedID = ID(site: .modifier(ordinal: ordinal, token: token))
    }
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    guard lhs.priority == rhs.priority else { return false }
    // The public string initializer can reconstruct a descriptor from its projection.
    if lhs.owner == rhs.owner && lhs.typedID == rhs.typedID { return true }
    return lhs.id == rhs.id
  }

}

/// A lifecycle operation emitted during commit planning.
package enum LifecycleCommitOperation: Equatable, Sendable {
  case appear(handlerIDs: [String])
  case disappear(handlerIDs: [String])
  case change(handlerIDs: [String])
  case taskStart(TaskDescriptor)
  case taskCancel(TaskDescriptor)
  /// Retains a running task when a visible identity acquires a new backing node.
  case taskTransfer(from: ViewNodeID, descriptor: TaskDescriptor)

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
    case .taskTransfer:
      .taskTransfer
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
  case taskTransfer
  case handlerInstallations
}
