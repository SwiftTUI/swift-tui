import SwiftTUICore

@MainActor
final class TaskRunner {
  private struct ActiveTaskKey: Hashable {
    var viewNodeID: ViewNodeID
    var descriptorID: String
  }

  private struct ActiveTask {
    var identity: Identity
    var descriptor: TaskDescriptor
    var generation: Int
    var task: Task<Void, Never>
  }

  private var activeTasks: [ActiveTaskKey: ActiveTask] = [:]
  private var nextGeneration = 0

  func start(
    viewNodeID: ViewNodeID,
    identity: Identity,
    registration: TaskRegistration
  ) {
    let descriptor = registration.descriptor
    let key = ActiveTaskKey(viewNodeID: viewNodeID, descriptorID: descriptor.id)
    cancel(viewNodeID: viewNodeID, matching: descriptor)

    // A node's viewNodeID can churn — a fresh id for the *same* identity on
    // re-evaluation (e.g. a `TimelineView` re-attaching its `.task` each tick).
    // Without this sweep, the old id's task is left running, and the lifecycle
    // diff can miss the transient disappearance. Keep the sweep per descriptor
    // so sibling task modifiers on the same identity do not cancel each other.
    let staleKeys = activeTasks.compactMap { entry in
      entry.key.viewNodeID != viewNodeID
        && entry.value.identity == identity
        && entry.value.descriptor.id == descriptor.id
        ? entry.key
        : nil
    }
    for staleKey in staleKeys {
      cancel(key: staleKey)
    }

    nextGeneration += 1
    let generation = nextGeneration
    let task = Task(priority: taskPriority(for: descriptor.priority)) { [weak self] in
      await registration.run()
      self?.finish(key: key, generation: generation)
    }

    activeTasks[key] = ActiveTask(
      identity: identity,
      descriptor: descriptor,
      generation: generation,
      task: task
    )
  }

  func cancel(
    viewNodeID: ViewNodeID,
    matching descriptor: TaskDescriptor? = nil
  ) {
    let keys = activeTasks.compactMap { entry -> ActiveTaskKey? in
      guard entry.key.viewNodeID == viewNodeID else {
        return nil
      }
      guard descriptor == nil || descriptor == entry.value.descriptor else {
        return nil
      }
      return entry.key
    }

    for key in keys {
      cancel(key: key)
    }
  }

  private func cancel(key: ActiveTaskKey) {
    guard let activeTask = activeTasks.removeValue(forKey: key) else {
      return
    }
    activeTask.task.cancel()
  }

  func cancelAll() {
    let tasks = activeTasks.values.map(\.task)
    activeTasks.removeAll(keepingCapacity: true)
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
    activeTasks.removeValue(forKey: key)
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
