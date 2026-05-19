/// Lifecycle handlers and task metadata attached to a node.
public struct LifecycleMetadata: Equatable, Sendable {
  public var appearHandlerIDs: [String]
  public var disappearHandlerIDs: [String]
  public var task: TaskDescriptor?

  public init(
    appearHandlerIDs: [String] = [],
    disappearHandlerIDs: [String] = [],
    task: TaskDescriptor? = nil
  ) {
    self.appearHandlerIDs = appearHandlerIDs
    self.disappearHandlerIDs = disappearHandlerIDs
    self.task = task
  }

  public var isEmpty: Bool {
    appearHandlerIDs.isEmpty
      && disappearHandlerIDs.isEmpty
      && task == nil
  }

  public func merging(_ other: Self) -> Self {
    Self(
      appearHandlerIDs: appearHandlerIDs + other.appearHandlerIDs,
      disappearHandlerIDs: disappearHandlerIDs + other.disappearHandlerIDs,
      task: other.task ?? task
    )
  }
}
