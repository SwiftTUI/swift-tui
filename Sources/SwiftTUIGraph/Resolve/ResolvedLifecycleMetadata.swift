/// Lifecycle handlers and task metadata attached to a node.
///
/// `tasks` accumulates in modifier-chain order so multiple `.task` modifiers on
/// one view node coexist like multiple appear/disappear handlers.
public struct LifecycleMetadata: Equatable, Sendable {
  package var appearIDs: [LifecycleHandlerID]
  package var disappearIDs: [LifecycleHandlerID]

  public var appearHandlerIDs: [String] {
    get { appearIDs.map(\.description) }
    set { appearIDs = newValue.map(LifecycleHandlerID.legacy) }
  }
  public var disappearHandlerIDs: [String] {
    get { disappearIDs.map(\.description) }
    set { disappearIDs = newValue.map(LifecycleHandlerID.legacy) }
  }
  public var tasks: [TaskDescriptor]
  /// Observers accumulated on this resolved element, in inner-first order.
  /// Graph identity aliases can change while a modifier chain unwinds.
  package var changeObservationCount: Int = 0

  public init(
    appearHandlerIDs: [String] = [],
    disappearHandlerIDs: [String] = [],
    tasks: [TaskDescriptor] = []
  ) {
    self.init(
      appearIDs: appearHandlerIDs.map(LifecycleHandlerID.legacy),
      disappearIDs: disappearHandlerIDs.map(LifecycleHandlerID.legacy), tasks: tasks)
  }

  package init(
    appearIDs: [LifecycleHandlerID], disappearIDs: [LifecycleHandlerID],
    tasks: [TaskDescriptor] = []
  ) {
    self.appearIDs = appearIDs
    self.disappearIDs = disappearIDs
    self.tasks = tasks
  }

  public var isEmpty: Bool {
    appearIDs.isEmpty
      && disappearIDs.isEmpty
      && tasks.isEmpty
  }

  public func merging(_ other: Self) -> Self {
    var merged = Self(
      appearIDs: appearIDs + other.appearIDs,
      disappearIDs: disappearIDs + other.disappearIDs,
      tasks: tasks + other.tasks
    )
    merged.changeObservationCount = changeObservationCount + other.changeObservationCount
    return merged
  }
}
