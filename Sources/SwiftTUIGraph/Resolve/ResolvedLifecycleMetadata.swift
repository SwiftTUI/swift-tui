/// Lifecycle handlers and task metadata attached to a node.
///
/// `tasks` accumulates in modifier-chain order so multiple `.task` modifiers on
/// one view node coexist like multiple appear/disappear handlers.
public struct LifecycleMetadata: Equatable, Sendable {
  public var appearHandlerIDs: [String]
  public var disappearHandlerIDs: [String]
  public var tasks: [TaskDescriptor]
  /// Observers accumulated on this resolved element, in inner-first order.
  /// Graph identity aliases can change while a modifier chain unwinds.
  package var changeObservationCount: Int = 0

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
    var merged = Self(
      appearHandlerIDs: appearHandlerIDs + other.appearHandlerIDs,
      disappearHandlerIDs: disappearHandlerIDs + other.disappearHandlerIDs,
      tasks: tasks + other.tasks
    )
    merged.changeObservationCount = changeObservationCount + other.changeObservationCount
    return merged
  }
}
