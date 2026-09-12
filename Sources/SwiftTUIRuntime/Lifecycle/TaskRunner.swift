import SwiftTUICore

@MainActor
final class TaskRunner {
  private struct ActiveTaskKey: Hashable {
    var viewNodeID: ViewNodeID
    var descriptorID: String
  }

  private struct LogicalTaskKey: Hashable {
    var identity: Identity
    var descriptorID: String
  }

  private struct ActiveTask {
    var identity: Identity
    var descriptor: TaskDescriptor
    var generation: Int
    var task: Task<Void, Never>
    var ownership: TaskOwnership
  }

  /// Completion follows the current owner while the generation guards replacements.
  @MainActor
  private final class TaskOwnership {
    var key: ActiveTaskKey

    init(key: ActiveTaskKey) {
      self.key = key
    }
  }

  private var activeTasks: [ActiveTaskKey: ActiveTask] = [:]
  private var keysByNode: [ViewNodeID: Set<ActiveTaskKey>] = [:]
  private var keyByLogicalTask: [LogicalTaskKey: ActiveTaskKey] = [:]
  private var nextGeneration = 0

  deinit {
    // Owner release is also shutdown: dropping unstructured task handles
    // alone does not cancel the work that they represent.
    for activeTask in activeTasks.values {
      activeTask.task.cancel()
    }
  }

  @discardableResult
  func start(
    viewNodeID: ViewNodeID,
    identity: Identity,
    registration: TaskRegistration
  ) -> Task<Void, Never> {
    let descriptor = registration.descriptor
    let key = ActiveTaskKey(viewNodeID: viewNodeID, descriptorID: descriptor.id)
    cancel(key: key)

    // A node's viewNodeID can churn — a fresh id for the *same* identity on
    // re-evaluation (e.g. a `TimelineView` re-attaching its `.task` each tick).
    // Without this lookup, the old id's task is left running, and the lifecycle
    // diff can miss the transient disappearance. Keep the lookup per descriptor
    // so sibling task modifiers on the same identity do not cancel each other.
    let logicalKey = LogicalTaskKey(identity: identity, descriptorID: descriptor.id)
    if let staleKey = keyByLogicalTask[logicalKey] {
      cancel(key: staleKey)
    }

    nextGeneration += 1
    let generation = nextGeneration
    let ownership = TaskOwnership(key: key)
    let task = Task(priority: taskPriority(for: descriptor.priority)) { [weak self] in
      defer { self?.finish(key: ownership.key, generation: generation) }
      // Removal or shutdown can cancel this task before its first actor turn.
      // A retired operation must not enter user code and read released state.
      guard !Task.isCancelled else { return }
      await registration.run()
    }

    activeTasks[key] = ActiveTask(
      identity: identity,
      descriptor: descriptor,
      generation: generation,
      task: task,
      ownership: ownership
    )
    keysByNode[viewNodeID, default: []].insert(key)
    keyByLogicalTask[logicalKey] = key
    return task
  }

  func transfer(
    from source: ViewNodeID,
    to destination: ViewNodeID,
    identity: Identity,
    matching descriptor: TaskDescriptor
  ) {
    guard source != destination else { return }
    let sourceKey = ActiveTaskKey(viewNodeID: source, descriptorID: descriptor.id)
    let destinationKey = ActiveTaskKey(viewNodeID: destination, descriptorID: descriptor.id)
    guard let activeTask = activeTasks[sourceKey],
      activeTask.identity == identity, activeTask.descriptor == descriptor
    else { return }
    // A newer destination operation wins. Retire the displaced source rather
    // than overwriting a live handle or leaving work under an obsolete owner.
    guard activeTasks[destinationKey] == nil else {
      cancel(key: sourceKey)
      return
    }
    _ = remove(key: sourceKey)
    activeTask.ownership.key = destinationKey
    activeTasks[destinationKey] = activeTask
    keysByNode[destination, default: []].insert(destinationKey)
    keyByLogicalTask[LogicalTaskKey(identity: identity, descriptorID: descriptor.id)] =
      destinationKey
  }

  func cancel(
    viewNodeID: ViewNodeID,
    matching descriptor: TaskDescriptor? = nil
  ) {
    if let descriptor {
      let key = ActiveTaskKey(viewNodeID: viewNodeID, descriptorID: descriptor.id)
      if activeTasks[key]?.descriptor == descriptor { cancel(key: key) }
      return
    }
    for key in keysByNode[viewNodeID] ?? [] {
      cancel(key: key)
    }
  }

  private func cancel(key: ActiveTaskKey) {
    guard let activeTask = remove(key: key) else {
      return
    }
    activeTask.task.cancel()
  }

  private func remove(key: ActiveTaskKey) -> ActiveTask? {
    guard let activeTask = activeTasks.removeValue(forKey: key) else { return nil }
    keysByNode[key.viewNodeID]?.remove(key)
    if keysByNode[key.viewNodeID]?.isEmpty == true {
      keysByNode.removeValue(forKey: key.viewNodeID)
    }
    keyByLogicalTask.removeValue(
      forKey: LogicalTaskKey(identity: activeTask.identity, descriptorID: key.descriptorID))
    return activeTask
  }

  func cancelAll() {
    let tasks = activeTasks.values.map(\.task)
    activeTasks.removeAll(keepingCapacity: true)
    keysByNode.removeAll(keepingCapacity: true)
    keyByLogicalTask.removeAll(keepingCapacity: true)
    for task in tasks {
      task.cancel()
    }
  }

  package var activeTaskDescriptors: [Identity: [TaskDescriptor]] {
    activeTasks.values.reduce(into: [Identity: [TaskDescriptor]]()) { partial, task in
      partial[task.identity, default: []].append(task.descriptor)
    }
  }

  /// Raw count of live task handles (keyed by `viewNodeID` plus task
  /// descriptor). Used by tests to detect tasks that should have been cancelled.
  package var activeTaskCount: Int {
    activeTasks.count
  }

  private func finish(
    key: ActiveTaskKey,
    generation: Int
  ) {
    guard activeTasks[key]?.generation == generation else {
      return
    }
    _ = remove(key: key)
  }

  private func taskPriority(
    for priority: SwiftTUICore.TaskPriority
  ) -> _Concurrency.TaskPriority {
    switch priority {
    case .userInitiated:
      return .userInitiated
    case .high:
      return .high
    case .medium:
      return .medium
    case .low:
      return .low
    case .background:
      return .background
    }
  }
}
