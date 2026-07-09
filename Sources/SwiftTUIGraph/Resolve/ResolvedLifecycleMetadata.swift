/// Lifecycle handlers and task metadata attached to a node.
///
/// `tasks` accumulates in modifier-chain order so multiple `.task` modifiers on
/// one view node coexist like multiple appear/disappear handlers.
public struct LifecycleMetadata: Equatable, Sendable {
  public var appearHandlerIDs: [String]
  public var disappearHandlerIDs: [String]
  public var tasks: [TaskDescriptor]

  public init(
    appearHandlerIDs: [String] = [],
    disappearHandlerIDs: [String] = [],
    tasks: [TaskDescriptor] = []
  ) {
    self.appearHandlerIDs = appearHandlerIDs
    self.disappearHandlerIDs = disappearHandlerIDs
    self.tasks = tasks
  }

  public var isEmpty: Bool {
    appearHandlerIDs.isEmpty
      && disappearHandlerIDs.isEmpty
      && tasks.isEmpty
  }

  public func merging(_ other: Self) -> Self {
    Self(
      appearHandlerIDs: appearHandlerIDs + other.appearHandlerIDs,
      disappearHandlerIDs: disappearHandlerIDs + other.disappearHandlerIDs,
      tasks: tasks + other.tasks
    )
  }
}
